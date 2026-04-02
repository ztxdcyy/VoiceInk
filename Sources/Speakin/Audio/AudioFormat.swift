import AVFoundation

enum AudioConstants {
    /// Qwen-Omni-Realtime required input format
    static let sampleRate: Double = 16_000        // 16 kHz
    static let channels: AVAudioChannelCount = 1   // Mono
    static let bitDepth: Int = 16                  // 16-bit signed integer
    static let bytesPerSample: Int = 2             // 16-bit = 2 bytes

    /// Target PCM format for the API
    static var targetFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )!
    }

    /// Float version for installTap (mixer output)
    static var floatFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!
    }

    /// Audio frame duration in milliseconds
    static let frameDurationMs: Int = 100          // 100ms per frame
    /// Samples per frame
    static let samplesPerFrame: Int = Int(sampleRate) * frameDurationMs / 1000  // 1600
}
