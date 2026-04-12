import AppKit
import Foundation

private let log = AppLogger.shared

final class SessionCoordinator: NSObject {
    private enum SessionState: String {
        case idle, connecting, recording, waitingForResult, injecting
    }

    private let audioEngine = AudioEngine()
    private let asrClient = SpeechClient()
    private let capsulePanel = CapsulePanel()

    private var state: SessionState = .idle
    private var isHotkeyHeld = false
    private var pendingStartAfterConnect = false

    private var recordingStartAt: Date?
    private var responseTimeoutTimer: Timer?

    private let minimumHoldDuration: TimeInterval = 0.3
    private let responseTimeout: TimeInterval = 15

    override init() {
        super.init()
        audioEngine.delegate = self
        asrClient.delegate = self
        log.log("[Session] init — DashScope ASR (paraformer-realtime-v2)")
    }

    deinit {
        responseTimeoutTimer?.invalidate()
        asrClient.disconnect()
    }

    // MARK: - Recording lifecycle

    private func beginRecordingIfPossible() {
        guard isHotkeyHeld else {
            log.log("[Session] beginRecording skipped — hotkey not held")
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
        log.log("[Session] hotkey held for \(String(format: "%.2f", heldDuration))s")

        if heldDuration < minimumHoldDuration {
            log.log("[Session] too short — cancelled")
            asrClient.disconnect()
            state = .idle
            capsulePanel.setState(.hidden)
            return
        }

        state = .waitingForResult
        capsulePanel.setState(.waitingForResult)

        // Tell ASR server that audio is done — it will flush remaining results
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
        isHotkeyHeld = false
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

// MARK: - HotkeyMonitorDelegate

extension SessionCoordinator: HotkeyMonitorDelegate {
    func hotkeyDidPress() {
        log.log("[Session] hotkeyDidPress, state=\(state.rawValue)")

        guard state == .idle else {
            log.log("[Session] hotkeyDidPress ignored — state=\(state.rawValue)")
            return
        }

        guard let apiKey = SettingsStore.shared.apiKey, !apiKey.isEmpty else {
            log.log("[Session] no API key — opening settings")
            SettingsWindowController.shared.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        isHotkeyHeld = true

        // Cache caret position (captured in CGEvent callback while frontmost app has focus)
        capsulePanel.cacheCaretPosition(HotkeyMonitor.shared.lastCaretRect)

        log.log("[Session] hotkey pressed — connecting ASR")
        capsulePanel.setState(.waitingForResult)
        state = .connecting
        pendingStartAfterConnect = true
        asrClient.connect()
    }

    func hotkeyDidRelease() {
        log.log("[Session] hotkeyDidRelease, state=\(state.rawValue)")
        isHotkeyHeld = false

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

// MARK: - SpeechClientDelegate

extension SessionCoordinator: SpeechClientDelegate {
    func speechClientDidConnect(_ client: SpeechClient) {
        log.log("[Session] ASR task started, pending=\(pendingStartAfterConnect)")
        guard pendingStartAfterConnect else { return }
        pendingStartAfterConnect = false
        beginRecordingIfPossible()
    }

    func speechClientDidDisconnect(_ client: SpeechClient, reason: String) {
        log.log("[Session] ASR disconnected, state=\(state.rawValue), reason=\(reason)")
        if state != .idle {
            capsulePanel.setState(.error(reason))
            resetToIdle()
        }
    }

    func speechClient(_ client: SpeechClient, didReceivePartialResult text: String) {
        // Partial results could be shown in capsule (future: live transcription)
        // For now, just log
    }

    func speechClient(_ client: SpeechClient, didReceiveFinalSentence text: String) {
        log.log("[Session] final sentence: \(text.prefix(80))")
    }

    func speechClientDidFinish(_ client: SpeechClient) {
        log.log("[Session] ASR finished, state=\(state.rawValue)")

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

    func speechClient(_ client: SpeechClient, didEncounterError error: Error) {
        log.log("[Session] ASR error: \(error.localizedDescription)")
        asrClient.disconnect()
        capsulePanel.setState(.error(error.localizedDescription))
        resetToIdle()
    }
}
