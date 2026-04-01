import Foundation

class RealtimeAPIClient {
    weak var delegate: RealtimeAPIClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isConnected = false
    private var sessionReady = false

    /// Monotonically increasing ID to distinguish connections.
    /// Stale async callbacks from a previous connection are discarded
    /// by comparing their captured ID against the current value.
    private var connectionID: UInt64 = 0

    // MARK: - Connection

    var connected: Bool { isConnected }

    func connect() {
        // If there's a lingering connection, tear it down first
        if isConnected || webSocketTask != nil {
            disconnect()
        }

        let settings = SettingsStore.shared
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            delegate?.realtimeClient(self, didEncounterError: VoiceInkError.missingAPIKey)
            return
        }

        let model = settings.model
        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(model)"

        // Bump connection ID so any in-flight callbacks from the old connection are ignored
        connectionID &+= 1
        let myID = connectionID
        AppLogger.shared.log("[WS] connecting (#\(myID)) to \(urlString)")

        guard let url = URL(string: urlString) else {
            delegate?.realtimeClient(self, didEncounterError: VoiceInkError.connectionFailed("Invalid URL"))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        listenForMessages(connectionID: myID)
    }

    func disconnect() {
        let oldTask = webSocketTask
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        sessionReady = false
        oldTask?.cancel(with: .goingAway, reason: nil)
    }

    // MARK: - Send Session Update

    func sendSessionUpdate() {
        let config = SessionConfig(
            modalities: ["text"],
            instructions: "You are a transcription engine. This session is for audio transcription only.",
            inputAudioFormat: "pcm",
            inputAudioTranscription: .default,
            turnDetection: nil,
            turnDetectionExplicitNull: true
        )

        let event = SessionUpdateEvent(session: config)
        sendEvent(event)
        AppLogger.shared.log("[WS] session.update sent (manual mode + input_audio_transcription)")
    }

    // MARK: - Send Audio

    func sendAudioFrame(_ base64PCM: String) {
        guard isConnected, sessionReady else { return }
        let event = AudioAppendEvent(audio: base64PCM)
        sendEvent(event)
    }

    func commitAudioBuffer() {
        guard isConnected else { return }
        sendEvent(AudioCommitEvent())
    }

    func requestResponse() {
        guard isConnected else { return }
        sendEvent(ResponseCreateEvent())
    }

    func cancelResponse() {
        guard isConnected else { return }
        sendEvent(ResponseCancelEvent())
    }

    // MARK: - Private: Send

    private func sendEvent<T: Encodable>(_ event: T) {
        guard let data = try? encoder.encode(event),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                print("[VoiceInk] WebSocket send error: \(error)")
            }
        }
    }

    // MARK: - Private: Receive

    private func listenForMessages(connectionID connID: UInt64) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            // If connectionID has changed, this callback is from a stale connection — ignore it
            guard self.connectionID == connID else {
                AppLogger.shared.log("[WS] ignoring stale receive callback (conn #\(connID), current #\(self.connectionID))")
                return
            }

            switch result {
            case .success(let message):
                self.handleMessage(message, connectionID: connID)
                self.listenForMessages(connectionID: connID)
            case .failure(let error):
                let closeCode = self.webSocketTask?.closeCode.rawValue ?? -1
                let closeReason = self.webSocketTask?.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                AppLogger.shared.log("[WS] receive error (#\(connID)): \(error.localizedDescription), closeCode=\(closeCode), reason=\(closeReason)")

                // Build a human-readable disconnect reason
                let displayReason: String
                if closeReason.lowercased().contains("access denied") || closeReason.lowercased().contains("account") {
                    displayReason = "API 访问被拒：\(closeReason)"
                } else if closeReason.contains("InvalidParameter") {
                    displayReason = "API 参数错误：\(closeReason)"
                } else if closeReason.isEmpty {
                    displayReason = "连接已断开（\(error.localizedDescription)）"
                } else {
                    displayReason = "连接已断开：\(closeReason)"
                }

                self.isConnected = false
                self.sessionReady = false
                DispatchQueue.main.async {
                    // Double-check: only notify delegate if this is still the current connection
                    guard self.connectionID == connID else {
                        AppLogger.shared.log("[WS] suppressing disconnect notification for stale conn #\(connID)")
                        return
                    }
                    self.delegate?.realtimeClientDidDisconnect(self, reason: displayReason)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, connectionID connID: UInt64) {
        guard case .string(let text) = message else {
            AppLogger.shared.log("[WS] received non-string message")
            return
        }
        guard let data = text.data(using: .utf8) else { return }

        AppLogger.shared.log("[WS] recv (#\(connID)): \(text.prefix(200))")

        do {
            let event = try decoder.decode(ServerEvent.self, from: data)
            processEvent(event, connectionID: connID)
        } catch {
            AppLogger.shared.log("[WS] decode error: \(error), raw: \(text.prefix(300))")
        }
    }

    private func processEvent(_ event: ServerEvent, connectionID connID: UInt64) {
        guard let eventType = ServerEventType(rawValue: event.type) else {
            // Unknown event type, ignore
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // If connectionID has changed, discard events from old connection
            guard self.connectionID == connID else {
                AppLogger.shared.log("[WS] ignoring stale event \(event.type) from conn #\(connID)")
                return
            }

            switch eventType {
            case .sessionCreated:
                self.isConnected = true
                self.delegate?.realtimeClientDidConnect(self)
                self.sendSessionUpdate()

            case .sessionUpdated:
                self.sessionReady = true
                self.delegate?.realtimeClientSessionReady(self)

            case .inputAudioBufferCommitted:
                AppLogger.shared.log("[WS] audio buffer committed")

            case .inputAudioTranscriptionCompleted:
                if let transcript = event.transcript {
                    AppLogger.shared.log("[WS] transcription completed: \(transcript.prefix(100))")
                    self.delegate?.realtimeClient(self, didCompleteTranscript: transcript)
                }

            case .responseCreated, .responseTextDelta, .responseAudioTranscriptDelta,
                 .responseTextDone, .responseAudioTranscriptDone:
                break // Not used in transcription-only mode

            case .responseDone:
                break // Not used in transcription-only mode

            case .error:
                let message = event.error?.message ?? "Unknown API error"
                self.delegate?.realtimeClient(self, didEncounterError: VoiceInkError.apiError(message))
            }
        }
    }
}
