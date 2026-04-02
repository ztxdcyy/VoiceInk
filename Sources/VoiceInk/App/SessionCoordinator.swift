import AppKit
import Foundation

private let log = AppLogger.shared

final class SessionCoordinator: NSObject {
    private enum SessionState: String {
        case idle, connecting, recording, waitingForResult, injecting
    }

    private let audioEngine = AudioEngine()
    private let apiClient = RealtimeAPIClient()
    private let capsulePanel = CapsulePanel()

    private var state: SessionState = .idle
    private var isFnHolding = false
    private var pendingStartAfterSessionReady = false

    private var recordingStartAt: Date?
    private var responseTimeoutTimer: Timer?

    private var currentTranscript = ""
    private var finalTranscript = ""
    /// Accumulates live input_audio_transcription deltas during recording
    private var liveTranscript = ""

    private let minimumHoldDuration: TimeInterval = 0.3
    private let responseTimeout: TimeInterval = 15

    override init() {
        super.init()
        audioEngine.delegate = self
        apiClient.delegate = self

        NotificationCenter.default.addObserver(
            self, selector: #selector(onSettingsChanged),
            name: .voiceInkSettingsSaved, object: nil
        )
        log.log("[Session] init")
    }

    deinit {
        responseTimeoutTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func onSettingsChanged() {
        if state == .idle, apiClient.connected {
            log.log("[Session] settings changed — disconnecting WS to apply new config on next use")
            apiClient.disconnect()
        }
    }

    private func beginRecordingIfPossible() {
        guard isFnHolding else {
            log.log("[Session] beginRecording skipped — Fn not held")
            return
        }

        do {
            try audioEngine.startRecording()
            recordingStartAt = Date()
            currentTranscript = ""
            finalTranscript = ""
            liveTranscript = ""
            state = .recording
            capsulePanel.setState(.recording)
            MenuBarManager.shared.setRecording(true)
            log.log("[Session] recording started")
        } catch {
            log.log("[Session] recording failed: \(error.localizedDescription)")
            state = .idle
            capsulePanel.setState(.error("无法开始录音: \(error.localizedDescription)"))
            MenuBarManager.shared.setRecording(false)
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
            apiClient.cancelResponse()
            state = .idle
            capsulePanel.setState(.hidden)
            return
        }

        state = .waitingForResult
        capsulePanel.setState(.waitingForResult)

        // Manual mode: commit audio buffer — server will fire inputAudioTranscriptionCompleted
        // which acts as both the final transcript and the "response done" signal.
        apiClient.commitAudioBuffer()
        startResponseTimeoutTimer()
        log.log("[Session] audio committed, waiting for transcription result")
    }

    private func resetToIdle() {
        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = nil

        audioEngine.stopRecording()
        MenuBarManager.shared.setRecording(false)

        state = .idle
        isFnHolding = false
        pendingStartAfterSessionReady = false
    }

    private func startResponseTimeoutTimer() {
        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = Timer.scheduledTimer(withTimeInterval: responseTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.state == .waitingForResult {
                log.log("[Session] response timeout (15s)")
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

        // connect() internally bumps connectionID and tears down any old connection,
        // so stale async callbacks from the previous WS will be automatically discarded.
        log.log("[Session] connecting fresh WS")
        capsulePanel.setState(.waitingForResult)
        state = .connecting
        pendingStartAfterSessionReady = true
        apiClient.connect()
    }

    func fnKeyDidRelease() {
        log.log("[Session] fnKeyDidRelease, state=\(state.rawValue)")
        isFnHolding = false

        switch state {
        case .connecting:
            log.log("[Session] released during connecting — cancel")
            pendingStartAfterSessionReady = false
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
        guard state == .recording else { return }
        apiClient.sendAudioFrame(base64PCM)
    }
}

// MARK: - RealtimeAPIClientDelegate

extension SessionCoordinator: RealtimeAPIClientDelegate {
    func realtimeClientDidConnect(_ client: RealtimeAPIClient) {
        log.log("[Session] WS connected")
    }

    func realtimeClientDidDisconnect(_ client: RealtimeAPIClient, reason: String) {
        log.log("[Session] WS disconnected, state=\(state.rawValue), reason=\(reason)")
        if state != .idle {
            capsulePanel.setState(.error(reason))
        }
        resetToIdle()
    }

    func realtimeClientSessionReady(_ client: RealtimeAPIClient) {
        log.log("[Session] session ready, pending=\(pendingStartAfterSessionReady)")
        guard pendingStartAfterSessionReady else { return }
        pendingStartAfterSessionReady = false
        beginRecordingIfPossible()
    }

    func realtimeClient(_ client: RealtimeAPIClient, didReceiveLiveTranscriptDelta delta: String) {
        // Show live transcription during recording AND while waiting for final result
        guard state == .recording || state == .waitingForResult else { return }
        liveTranscript += delta
        capsulePanel.updateTranscript(liveTranscript)
    }

    func realtimeClient(_ client: RealtimeAPIClient, didCompleteTranscript text: String) {
        log.log("[Session] transcript done: \(text.prefix(80))")
        finalTranscript = text
        if !text.isEmpty {
            capsulePanel.updateTranscript(text)
        }
    }

    func realtimeClientDidFinishResponse(_ client: RealtimeAPIClient) {
        log.log("[Session] response done, state=\(state.rawValue)")

        guard state == .waitingForResult else { return }

        responseTimeoutTimer?.invalidate()
        responseTimeoutTimer = nil

        // Prefer finalTranscript (from completed event), fall back to accumulated live deltas
        let completedText = finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = !completedText.isEmpty ? completedText : liveText

        log.log("[Session] final text (\(result.count) chars): \(result.prefix(100))")

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

    func realtimeClient(_ client: RealtimeAPIClient, didEncounterError error: Error) {
        log.log("[Session] API error: \(error.localizedDescription)")
        capsulePanel.setState(.error(error.localizedDescription))
        resetToIdle()
    }
}
