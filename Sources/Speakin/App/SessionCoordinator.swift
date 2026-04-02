import AppKit
import Foundation

private let log = AppLogger.shared

final class SessionCoordinator: NSObject {
    private enum SessionState: String {
        case idle, connecting, recording, waitingForResult, injecting
    }

    private let audioEngine = AudioEngine()
    private let asrClient = GummyASRClient()
    private let capsulePanel = CapsulePanel()

    private var state: SessionState = .idle
    private var isFnHolding = false
    private var pendingStartAfterConnect = false

    private var recordingStartAt: Date?
    private var responseTimeoutTimer: Timer?

    private let minimumHoldDuration: TimeInterval = 0.3
    private let responseTimeout: TimeInterval = 15

    override init() {
        super.init()
        audioEngine.delegate = self
        asrClient.delegate = self
        log.log("[Session] init — Gummy ASR mode")
    }

    deinit {
        responseTimeoutTimer?.invalidate()
        asrClient.disconnect()
    }

    // MARK: - Recording lifecycle

    private func beginRecordingIfPossible() {
        guard isFnHolding else {
            log.log("[Session] beginRecording skipped — Fn not held")
            return
        }

        do {
            try audioEngine.startRecording()
            recordingStartAt = Date()
            state = .recording
            capsulePanel.setState(.recording)
            MenuBarManager.shared.setRecording(true)
            log.log("[Session] recording started")
        } catch {
            log.log("[Session] recording failed: \(error.localizedDescription)")
            state = .idle
            capsulePanel.setState(.error("无法开始录音: \(error.localizedDescription)"))
            MenuBarManager.shared.setRecording(false)
            asrClient.disconnect()
        }
    }

    private func stopRecordingForRelease() {
        guard state == .recording else { return }

        audioEngine.stopRecording()
        MenuBarManager.shared.setRecording(false)

        let heldDuration = Date().timeIntervalSince(recordingStartAt ?? Date())
        recordingStartAt = nil
        log.log("[Session] Fn held for \(String(format: "%.2f", heldDuration))s")

        if heldDuration < minimumHoldDuration {
            log.log("[Session] too short — cancelled")
            asrClient.disconnect()
            state = .idle
            capsulePanel.setState(.hidden)
            return
        }

        state = .waitingForResult
        capsulePanel.setState(.waitingForResult)

        // Tell Gummy that audio is done — it will flush remaining results
        asrClient.finishTask()
        startResponseTimeoutTimer()
        log.log("[Session] finish-task sent, waiting for final results")
    }

    private func resetToIdle() {
        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = nil

        audioEngine.stopRecording()
        MenuBarManager.shared.setRecording(false)

        state = .idle
        isFnHolding = false
        pendingStartAfterConnect = false
    }

    private func startResponseTimeoutTimer() {
        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = Timer.scheduledTimer(withTimeInterval: responseTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .waitingForResult {
                log.log("[Session] response timeout (15s)")
                self.asrClient.disconnect()
                self.capsulePanel.setState(.error("请求超时"))
                self.resetToIdle()
            }
        }
    }
}

// MARK: - FnKeyMonitorDelegate

extension SessionCoordinator: FnKeyMonitorDelegate {
    func fnKeyDidPress() {
        log.log("[Session] fnKeyDidPress, state=\(state.rawValue)")

        guard state == .idle else {
            log.log("[Session] fnKeyDidPress ignored — state=\(state.rawValue)")
            return
        }

        guard let apiKey = SettingsStore.shared.apiKey, !apiKey.isEmpty else {
            log.log("[Session] no API key — opening settings")
            SettingsWindowController.shared.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        isFnHolding = true

        // Cache caret position (captured in CGEvent callback while frontmost app has focus)
        capsulePanel.cacheCaretPosition(FnKeyMonitor.shared.lastCaretRect)

        log.log("[Session] Fn pressed — connecting Gummy ASR")
        capsulePanel.setState(.waitingForResult)
        state = .connecting
        pendingStartAfterConnect = true
        asrClient.connect()
    }

    func fnKeyDidRelease() {
        log.log("[Session] fnKeyDidRelease, state=\(state.rawValue)")
        isFnHolding = false

        switch state {
        case .connecting:
            log.log("[Session] released during connecting — cancel")
            pendingStartAfterConnect = false
            asrClient.disconnect()
            state = .idle
            capsulePanel.setState(.hidden)

        case .recording:
            stopRecordingForRelease()

        case .waitingForResult, .injecting, .idle:
            break
        }
    }
}

// MARK: - AudioEngineDelegate

extension SessionCoordinator: AudioEngineDelegate {
    func audioEngine(_ engine: AudioEngine, didUpdateRMSLevel level: Float) {
        guard state == .recording else { return }
        capsulePanel.updateWaveformLevel(level)
    }

    func audioEngine(_ engine: AudioEngine, didCaptureAudioFrame base64PCM: String) {
        guard state == .recording, engine.isRecording else { return }
        asrClient.sendAudioFrame(base64PCM)
    }
}

// MARK: - GummyASRClientDelegate

extension SessionCoordinator: GummyASRClientDelegate {
    func gummyClientDidConnect(_ client: GummyASRClient) {
        log.log("[Session] Gummy task started, pending=\(pendingStartAfterConnect)")
        guard pendingStartAfterConnect else { return }
        pendingStartAfterConnect = false
        beginRecordingIfPossible()
    }

    func gummyClientDidDisconnect(_ client: GummyASRClient, reason: String) {
        log.log("[Session] Gummy disconnected, state=\(state.rawValue), reason=\(reason)")
        if state != .idle {
            capsulePanel.setState(.error(reason))
            resetToIdle()
        }
    }

    func gummyClient(_ client: GummyASRClient, didReceivePartialResult text: String) {
        // Partial results could be shown in capsule (future: live transcription)
        // For now, just log
    }

    func gummyClient(_ client: GummyASRClient, didReceiveFinalSentence text: String) {
        log.log("[Session] final sentence: \(text.prefix(80))")
    }

    func gummyClientDidFinish(_ client: GummyASRClient) {
        log.log("[Session] Gummy finished, state=\(state.rawValue)")

        guard state == .waitingForResult else { return }

        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = nil

        let result = client.fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        log.log("[Session] final text (\(result.count) chars): \(result.prefix(100))")

        asrClient.disconnect()

        if result.isEmpty {
            log.log("[Session] empty transcript — skip inject")
            capsulePanel.setState(.hidden)
            resetToIdle()
            return
        }

        state = .injecting
        TextInjector.inject(text: result)
        capsulePanel.setState(.hidden)
        resetToIdle()
    }

    func gummyClient(_ client: GummyASRClient, didEncounterError error: Error) {
        log.log("[Session] Gummy error: \(error.localizedDescription)")
        asrClient.disconnect()
        capsulePanel.setState(.error(error.localizedDescription))
        resetToIdle()
    }
}
