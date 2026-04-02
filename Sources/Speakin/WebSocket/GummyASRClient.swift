import Foundation

// MARK: - Delegate Protocol

protocol GummyASRClientDelegate: AnyObject {
    func gummyClientDidConnect(_ client: GummyASRClient)
    func gummyClientDidDisconnect(_ client: GummyASRClient, reason: String)
    func gummyClient(_ client: GummyASRClient, didReceivePartialResult text: String)
    func gummyClient(_ client: GummyASRClient, didReceiveFinalSentence text: String)
    func gummyClientDidFinish(_ client: GummyASRClient)
    func gummyClient(_ client: GummyASRClient, didEncounterError error: Error)
}

// MARK: - Gummy ASR Client

/// Dedicated client for Gummy Realtime ASR (speech recognition).
/// Uses the standalone Gummy WebSocket API at `/api-ws/v1/inference`,
/// which is completely separate from the Qwen-Omni Realtime API.
///
/// Protocol:
///   1. Connect to wss://dashscope.aliyuncs.com/api-ws/v1/inference
///   2. Send `run-task` JSON message
///   3. Receive `task-started`
///   4. Send audio as Binary frames (~100ms chunks)
///   5. Receive `result-generated` events (partial + final sentences)
///   6. Send `finish-task` JSON message
///   7. Receive remaining results + `task-finished`
class GummyASRClient {
    weak var delegate: GummyASRClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var isConnected = false
    private(set) var taskStarted = false

    private var connectionID: UInt64 = 0
    private var taskID: String = ""

    /// All final sentences accumulated in this session
    private var finalSentences: [String] = []

    // MARK: - Connect

    func connect() {
        if webSocketTask != nil || isConnected {
            disconnect()
        }

        let settings = SettingsStore.shared
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            AppLogger.shared.log("[Gummy] no API key — skip connect")
            return
        }

        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        guard let url = URL(string: urlString) else { return }

        connectionID &+= 1
        let myID = connectionID
        AppLogger.shared.log("[Gummy] connecting (#\(myID))")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("speakin-macos", forHTTPHeaderField: "user-agent")

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        isConnected = true
        taskStarted = false
        finalSentences = []
        taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

        listenForMessages(connectionID: myID)
        sendRunTask()
    }

    func disconnect() {
        let oldTask = webSocketTask
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        taskStarted = false
        oldTask?.cancel(with: .goingAway, reason: nil)
        AppLogger.shared.log("[Gummy] disconnected")
    }

    // MARK: - Send Audio

    /// Send raw PCM audio data as a WebSocket binary frame.
    /// Audio should be 16kHz mono 16-bit PCM, sent in ~100ms chunks.
    func sendAudioData(_ data: Data) {
        guard isConnected, taskStarted else { return }
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                AppLogger.shared.log("[Gummy] send audio error: \(error.localizedDescription)")
            }
        }
    }

    /// Convenience: send base64-encoded PCM (decoded to raw bytes).
    func sendAudioFrame(_ base64PCM: String) {
        guard let data = Data(base64Encoded: base64PCM) else { return }
        sendAudioData(data)
    }

    /// Signal that audio is complete. Server will flush remaining results.
    func finishTask() {
        guard isConnected else { return }
        let message: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [String: Any]()
            ]
        ]
        sendJSON(message)
        AppLogger.shared.log("[Gummy] finish-task sent")
    }

    // MARK: - Private: Send run-task

    private func sendRunTask() {
        let settings = SettingsStore.shared
        let langCode = settings.language

        // Map our language codes to Gummy's source_language codes
        let sourceLanguage: String
        switch langCode {
        case "zh-CN": sourceLanguage = "zh"
        case "zh-TW": sourceLanguage = "zh"
        case "en":    sourceLanguage = "en"
        case "ja":    sourceLanguage = "ja"
        case "ko":    sourceLanguage = "ko"
        default:      sourceLanguage = "auto"
        }

        let message: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": "paraformer-realtime-v2",
                "parameters": [
                    "sample_rate": 16000,
                    "format": "pcm",
                    "language_hints": [sourceLanguage],
                    "disfluency_removal_enabled": true
                ] as [String: Any],
                "input": [String: Any]()
            ]
        ]

        sendJSON(message)
        AppLogger.shared.log("[Gummy] run-task sent (lang=\(sourceLanguage))")
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(jsonString)) { error in
            if let error = error {
                AppLogger.shared.log("[Gummy] send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Receive

    private func listenForMessages(connectionID connID: UInt64) {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.connectionID == connID else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message, connectionID: connID)
                self.listenForMessages(connectionID: connID)
            case .failure(let error):
                AppLogger.shared.log("[Gummy] receive error: \(error.localizedDescription)")
                self.isConnected = false
                self.taskStarted = false
                DispatchQueue.main.async {
                    guard self.connectionID == connID else { return }
                    self.delegate?.gummyClientDidDisconnect(self, reason: error.localizedDescription)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, connectionID connID: UInt64) {
        guard case .string(let text) = message else { return }
        guard let data = text.data(using: .utf8) else { return }

        AppLogger.shared.log("[Gummy] recv (#\(connID)): \(text.prefix(400))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.connectionID == connID else { return }
            self.processEvent(event, json: json)
        }
    }

    private func processEvent(_ event: String, json: [String: Any]) {
        switch event {
        case "task-started":
            taskStarted = true
            AppLogger.shared.log("[Gummy] task started")
            delegate?.gummyClientDidConnect(self)

        case "result-generated":
            handleResultGenerated(json)

        case "task-finished":
            AppLogger.shared.log("[Gummy] task finished, total sentences: \(finalSentences.count)")
            delegate?.gummyClientDidFinish(self)

        case "task-failed":
            let payload = json["payload"] as? [String: Any]
            let output = payload?["output"] as? [String: Any]
            let message = output?["message"] as? String ?? "Unknown error"
            let code = output?["code"] as? String ?? ""
            AppLogger.shared.log("[Gummy] task failed: \(code) — \(message)")
            delegate?.gummyClient(self, didEncounterError: SpeakinError.apiError("\(code): \(message)"))

        default:
            break
        }
    }

    private func handleResultGenerated(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any] else {
            return
        }

        // Paraformer uses "sentence", Gummy uses "transcription"
        guard let result = output["sentence"] as? [String: Any]
                ?? output["transcription"] as? [String: Any] else {
            return
        }

        let text = result["text"] as? String ?? ""
        // Paraformer uses "is_sentence_end", Gummy uses "sentence_end"
        let isSentenceEnd = result["is_sentence_end"] as? Bool
            ?? result["sentence_end"] as? Bool
            ?? false

        if isSentenceEnd {
            if !text.isEmpty {
                finalSentences.append(text)
                AppLogger.shared.log("[ASR] final sentence: \(text)")
                delegate?.gummyClient(self, didReceiveFinalSentence: text)
            }
        } else {
            delegate?.gummyClient(self, didReceivePartialResult: text)
        }
    }

    // MARK: - Public: Get accumulated transcript

    /// All final sentences joined together
    var fullTranscript: String {
        finalSentences.joined()
    }
}
