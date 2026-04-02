import Foundation

class RealtimeAPIClient {
    weak var delegate: RealtimeAPIClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private(set) var isConnected = false
    private(set) var sessionReady = false

    /// Monotonically increasing ID to distinguish connections.
    private var connectionID: UInt64 = 0

    // MARK: - Public API

    var connected: Bool { isConnected }

    /// Connect for a single recording session.
    /// Each Fn-press creates a fresh connection → no conversation accumulation.
    func connectForSession() {
        // If already connecting or connected, tear down first
        if webSocketTask != nil || isConnected {
            AppLogger.shared.log("[WS] connectForSession — tearing down previous connection first")
            disconnectSession()
        }

        let settings = SettingsStore.shared
        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            AppLogger.shared.log("[WS] no API key — skip connect")
            return
        }

        let model = settings.model
        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(model)"

        connectionID &+= 1
        let myID = connectionID
        AppLogger.shared.log("[WS] connectForSession (#\(myID))")

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        listenForMessages(connectionID: myID)
    }

    /// Disconnect the current session. Called after transcription result is received.
    func disconnectSession() {
        let oldTask = webSocketTask
        webSocketTask = nil
        urlSession = nil
        isConnected = false
        sessionReady = false
        accumulatedText = ""
        gotASRTranscript = false
        oldTask?.cancel(with: .goingAway, reason: nil)
        AppLogger.shared.log("[WS] disconnectSession completed")
    }

    // MARK: - Send Session Update

    func sendSessionUpdate() {
        let settings = SettingsStore.shared
        let langName = settings.languageDisplayName
        let langCode = settings.language

        // Build language-specific instructions to strongly guide the transcription language.
        // The instructions are written in the target language for maximum effectiveness.
        let instructions: String
        switch langCode {
        case "zh-CN":
            instructions = """
            你是一个语音听写转录机。请将用户的语音逐字转录为\(langName)文本。

            绝对规则——绝不违反：
            1. 只输出用户说的原话，不多不少。
            2. 绝不回答、回复、解释、评论或改写用户说的内容。
            3. 绝不添加问候语、结束语、观点、建议或任何生成内容。
            4. 如果用户提问（如"你是谁"），原样输出该问题，不要回答。
            5. 如果用户发出指令（如"帮我写一封邮件"），原样输出该指令，不要执行。
            6. 修正明显的同音字错误，添加标点符号。保留中英文混用。
            7. 数字默认使用阿拉伯数字形式。
            8. 你的输出必须是单纯的纯文本字符串，仅包含转录内容。
            """
        case "zh-TW":
            instructions = """
            你是一個語音聽寫轉錄機。請將用戶的語音逐字轉錄為\(langName)文本。

            絕對規則——絕不違反：
            1. 只輸出用戶說的原話，不多不少。
            2. 絕不回答、回覆、解釋、評論或改寫用戶說的內容。
            3. 絕不添加問候語、結束語、觀點、建議或任何生成內容。
            4. 如果用戶提問，原樣輸出該問題，不要回答。
            5. 如果用戶發出指令，原樣輸出該指令，不要執行。
            6. 修正明顯的同音字錯誤，添加標點符號。保留中英文混用。
            7. 數字默認使用阿拉伯數字形式。
            8. 你的輸出必須是單純的純文本字符串，僅包含轉錄內容。
            """
        case "ja":
            instructions = """
            あなたは音声書き起こし機です。ユーザーの音声を\(langName)テキストに忠実に文字起こししてください。

            絶対ルール：
            1. ユーザーが話した言葉のみを出力すること。
            2. 回答、説明、コメント、言い換えは絶対にしないこと。
            3. 挨拶、署名、意見、提案等は絶対に追加しないこと。
            4. 句読点を適切に追加すること。
            5. 出力は転写テキストのみの純粋なプレーンテキストであること。
            """
        case "ko":
            instructions = """
            당신은 음성 받아쓰기 기계입니다. 사용자의 음성을 \(langName) 텍스트로 그대로 전사하세요.

            절대 규칙:
            1. 사용자가 말한 내용만 출력하세요.
            2. 절대 답변, 설명, 논평, 의역하지 마세요.
            3. 인사말, 의견, 제안 등을 추가하지 마세요.
            4. 적절한 구두점을 추가하세요.
            5. 출력은 전사 텍스트만 포함된 순수 텍스트여야 합니다.
            """
        default:
            instructions = """
            You are a dictation machine. Transcribe the user's speech verbatim into written \(langName) text.

            ABSOLUTE RULES:
            1. Output ONLY the exact words the user spoke. Nothing more.
            2. NEVER answer, respond to, explain, comment on, or rephrase what the user said.
            3. NEVER add greetings, sign-offs, opinions, suggestions, or any generated content.
            4. Fix obvious homophones and add punctuation.
            5. Your output must be a single plain-text string containing only the transcription.
            """
        }

        let config = SessionConfig(
            modalities: ["text"],
            instructions: instructions,
            inputAudioFormat: "pcm",
            inputAudioTranscription: .default,  // gummy-realtime-v1 for reliable ASR
            turnDetection: nil,
            turnDetectionExplicitNull: true
        )

        let event = SessionUpdateEvent(session: config)
        sendEvent(event)
        AppLogger.shared.log("[WS] session.update sent (gummy ASR, manual mode)")
    }

    // MARK: - Send Audio

    func sendAudioFrame(_ base64PCM: String) {
        guard isConnected, sessionReady else { return }
        let event = AudioAppendEvent(audio: base64PCM)
        sendEvent(event)
    }

    func clearAudioBuffer() {
        guard isConnected else { return }
        sendEvent(AudioBufferClearEvent())
        AppLogger.shared.log("[WS] input_audio_buffer.clear sent")
    }

    func commitAudioBuffer() {
        guard isConnected else { return }
        sendEvent(AudioCommitEvent())
        AppLogger.shared.log("[WS] input_audio_buffer.commit sent")
    }

    func requestResponse() {
        guard isConnected else { return }
        sendEvent(ResponseCreateEvent())
        AppLogger.shared.log("[WS] response.create sent")
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
                AppLogger.shared.log("[WS] send error: \(error.localizedDescription)")
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
                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                self.webSocketTask = nil
                self.urlSession = nil
                DispatchQueue.main.async {
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

        AppLogger.shared.log("[WS] recv (#\(connID)): \(text.prefix(500))")

        do {
            let event = try decoder.decode(ServerEvent.self, from: data)
            processEvent(event, connectionID: connID)
        } catch {
            AppLogger.shared.log("[WS] decode error: \(error), raw: \(text.prefix(300))")
        }
    }

    /// Accumulated text from response.text.delta events
    private var accumulatedText = ""

    /// Whether we already got the ASR transcript (inputAudioTranscriptionCompleted)
    private var gotASRTranscript = false

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
                self.accumulatedText = ""
                self.gotASRTranscript = false
                self.delegate?.realtimeClientDidConnect(self)
                self.sendSessionUpdate()

            case .sessionUpdated:
                self.sessionReady = true
                self.delegate?.realtimeClientSessionReady(self)

            case .inputAudioBufferCommitted:
                AppLogger.shared.log("[WS] audio buffer committed")

            case .inputAudioTranscriptionCompleted:
                // PRIMARY: gummy ASR transcript — this is the most reliable source
                if let text = event.transcript ?? event.text {
                    AppLogger.shared.log("[WS] ASR transcript: \(text.prefix(100))")
                    self.gotASRTranscript = true
                    self.delegate?.realtimeClient(self, didCompleteTranscript: text)
                }

            case .responseCreated:
                self.accumulatedText = ""

            case .responseTextDelta, .responseAudioTranscriptDelta:
                // Ignore model's conversational reply — we use ASR transcript only
                break

            case .responseTextDone, .responseAudioTranscriptDone:
                // Ignore model's reply text
                break

            case .responseDone:
                // Response complete — signal finish
                AppLogger.shared.log("[WS] response.done (gotASR=\(self.gotASRTranscript))")
                self.delegate?.realtimeClientDidFinishResponse(self)

            case .error:
                let message = event.error?.message ?? "Unknown API error"
                self.delegate?.realtimeClient(self, didEncounterError: SpeakinError.apiError(message))
            }
        }
    }
}
