import Foundation

// MARK: - Client Events (Client → Server)

struct SessionUpdateEvent: Encodable {
    let type = "session.update"
    let session: SessionConfig
}

struct SessionConfig: Encodable {
    let modalities: [String]
    let instructions: String
    let input_audio_format: String
    let input_audio_transcription: InputAudioTranscription?
    let turn_detection: TurnDetectionConfig?

    /// When true, `turn_detection` encodes as JSON `null` (manual mode).
    /// When false, it encodes normally or is omitted.
    private let _turnDetectionExplicitNull: Bool

    init(
        modalities: [String],
        instructions: String,
        inputAudioFormat: String = "pcm",
        inputAudioTranscription: InputAudioTranscription? = nil,
        turnDetection: TurnDetectionConfig? = nil,
        turnDetectionExplicitNull: Bool = false
    ) {
        self.modalities = modalities
        self.instructions = instructions
        self.input_audio_format = inputAudioFormat
        self.input_audio_transcription = inputAudioTranscription
        self.turn_detection = turnDetection
        self._turnDetectionExplicitNull = turnDetectionExplicitNull
    }

    private enum CodingKeys: String, CodingKey {
        case modalities, instructions, input_audio_format
        case input_audio_transcription, turn_detection
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modalities, forKey: .modalities)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(input_audio_format, forKey: .input_audio_format)
        try container.encodeIfPresent(input_audio_transcription, forKey: .input_audio_transcription)

        if _turnDetectionExplicitNull {
            try container.encodeNil(forKey: .turn_detection)
        } else if let td = turn_detection {
            try container.encode(td, forKey: .turn_detection)
        }
    }
}

struct InputAudioTranscription: Encodable {
    let model: String

    static let `default` = InputAudioTranscription(model: "gummy-realtime-v1")
}

struct TurnDetectionConfig: Encodable {
    let type: String
    let threshold: Double?
    let silence_duration_ms: Int?

    static func serverVAD(threshold: Double = 0.5, silenceDurationMs: Int = 500) -> TurnDetectionConfig {
        TurnDetectionConfig(type: "server_vad", threshold: threshold, silence_duration_ms: silenceDurationMs)
    }
}

struct AudioAppendEvent: Encodable {
    let type = "input_audio_buffer.append"
    let audio: String
}

struct AudioCommitEvent: Encodable {
    let type = "input_audio_buffer.commit"
}

struct ResponseCreateEvent: Encodable {
    let type = "response.create"
}

struct ResponseCancelEvent: Encodable {
    let type = "response.cancel"
}

// MARK: - Server Events (Server → Client)

struct ServerEvent: Decodable {
    let type: String
    let delta: String?
    let text: String?
    let transcript: String?
    let error: ServerError?

    private enum CodingKeys: String, CodingKey {
        case type, delta, text, transcript, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        delta = try container.decodeIfPresent(String.self, forKey: .delta)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        transcript = try container.decodeIfPresent(String.self, forKey: .transcript)
        error = try container.decodeIfPresent(ServerError.self, forKey: .error)
    }
}

struct ServerError: Decodable {
    let type: String?
    let code: String?
    let message: String?
}

// MARK: - Server Event Types

enum ServerEventType: String {
    case sessionCreated = "session.created"
    case sessionUpdated = "session.updated"
    case inputAudioBufferCommitted = "input_audio_buffer.committed"
    case inputAudioTranscriptionCompleted = "conversation.item.input_audio_transcription.completed"
    case responseCreated = "response.created"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseAudioTranscriptDelta = "response.audio_transcript.delta"
    case responseAudioTranscriptDone = "response.audio_transcript.done"
    case responseDone = "response.done"
    case error = "error"
}

// MARK: - App Errors

enum VoiceInkError: LocalizedError {
    case missingAPIKey
    case connectionFailed(String)
    case timeout
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API Key is not configured. Please set it in Settings."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .timeout:
            return "Request timed out."
        case .apiError(let msg):
            return "API error: \(msg)"
        }
    }
}
