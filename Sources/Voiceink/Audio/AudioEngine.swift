import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMSLevel level: Float)
    func audioEngine(_ engine: AudioEngine, didCaptureAudioFrame base64PCM: String)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private let processingQueue = DispatchQueue(label: "com.voiceink.audio", qos: .userInteractive)
    private(set) var isRecording = false

    // MARK: - Start / Stop

    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        AppLogger.shared.log("[Audio] hardwareFormat: rate=\(hardwareFormat.sampleRate), ch=\(hardwareFormat.channelCount), bitsPerCh=\(hardwareFormat.streamDescription.pointee.mBitsPerChannel)")

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioEngineError.noInputDevice
        }

        // Target format: 16kHz mono int16
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: AudioConstants.sampleRate,
            channels: 1,
            interleaved: true
        )!

        // Create converter from hardware format to target
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            AppLogger.shared.log("[Audio] converter creation failed from \(hardwareFormat) to \(targetFormat)")
            throw AudioEngineError.converterCreationFailed
        }
        self.converter = converter

        // Tap inputNode using its own native format — this is the most reliable approach
        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
        AppLogger.shared.log("[Audio] recording started")
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        AppLogger.shared.log("[Audio] recording stopped")
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // 1. Calculate RMS from the first channel
        let channelData = floatData[0]
        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let s = channelData[i]
            sumOfSquares += s * s
        }
        let rms = sqrtf(sumOfSquares / Float(frameLength))

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.audioEngine(self, didUpdateRMSLevel: rms)
        }

        // 2. Convert to 16kHz int16 PCM and Base64 encode
        processingQueue.async { [weak self] in
            guard let self = self, let converter = self.converter else { return }

            // Calculate expected output frame count after sample rate conversion
            let ratio = AudioConstants.sampleRate / buffer.format.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(frameLength) * ratio)
            guard outputFrameCount > 0 else { return }

            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: AudioConstants.sampleRate,
                channels: 1,
                interleaved: true
            )!

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount + 128) else {
                return
            }

            var error: NSError?
            var consumed = false
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if let error = error {
                AppLogger.shared.log("[Audio] conversion error: \(error)")
                return
            }

            guard let int16Data = outputBuffer.int16ChannelData else { return }
            let count = Int(outputBuffer.frameLength)
            guard count > 0 else { return }

            let data = Data(bytes: int16Data[0], count: count * 2)
            let base64 = data.base64EncodedString()
            self.delegate?.audioEngine(self, didCaptureAudioFrame: base64)
        }
    }
}

// MARK: - Errors

enum AudioEngineError: LocalizedError {
    case noInputDevice
    case converterCreationFailed
    case microphonePermissionDenied
    case microphonePermissionPending

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "未找到音频输入设备。"
        case .converterCreationFailed:
            return "音频格式转换器创建失败。"
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝，请在系统设置中授予。"
        case .microphonePermissionPending:
            return "正在请求麦克风权限，请授权后重试。"
        }
    }
}
