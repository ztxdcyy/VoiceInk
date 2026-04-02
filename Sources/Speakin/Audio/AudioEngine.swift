import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMSLevel level: Float)
    func audioEngine(_ engine: AudioEngine, didCaptureAudioFrame base64PCM: String)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?

    private var engine: AVAudioEngine?
    private let processingQueue = DispatchQueue(label: "com.speakin.audio", qos: .userInteractive)
    private(set) var isRecording = false

    /// Frame counter for debugging audio data issues
    private var frameCount: UInt64 = 0
    /// Total input samples processed (for debug)
    private var totalSamplesIn: UInt64 = 0
    /// Total output samples produced (for debug)
    private var totalSamplesOut: UInt64 = 0

    // MARK: - Start / Stop

    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        self.engine = engine
        frameCount = 0
        totalSamplesIn = 0
        totalSamplesOut = 0

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        AppLogger.shared.log("[Audio] hardwareFormat: rate=\(hardwareFormat.sampleRate), ch=\(hardwareFormat.channelCount), bitsPerCh=\(hardwareFormat.streamDescription.pointee.mBitsPerChannel)")

        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioEngineError.noInputDevice
        }

        let hwRate = hardwareFormat.sampleRate
        let targetRate = AudioConstants.sampleRate
        AppLogger.shared.log("[Audio] downsample: \(hwRate) → \(targetRate), ratio=\(hwRate / targetRate)")

        let bufferSize: AVAudioFrameCount = 4096
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, hardwareRate: hwRate, targetRate: targetRate)
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
        AppLogger.shared.log("[Audio] recording stopped, frames=\(frameCount), samplesIn=\(totalSamplesIn), samplesOut=\(totalSamplesOut)")
    }

    // MARK: - Audio Processing (Manual Downsample — no AVAudioConverter)

    /// Pure manual downsampling + Int16 conversion.
    /// AVAudioConverter has internal resample buffers that cause audio duplication artifacts;
    /// manual decimation with linear interpolation is simple and perfectly reliable for our 48→16kHz case.
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, hardwareRate: Double, targetRate: Double) {
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

        // 2. Manual downsample: linear interpolation from hardwareRate to 16kHz, then quantize to Int16.
        //    This is stateless per-buffer — zero risk of data duplication.
        processingQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }

            let step = hardwareRate / targetRate  // e.g. 48000/16000 = 3.0
            let outputCount = Int(floor(Double(frameLength) / step))
            guard outputCount > 0 else { return }

            // Allocate Int16 output directly
            var int16Samples = [Int16](repeating: 0, count: outputCount)

            for i in 0..<outputCount {
                let srcPos = Double(i) * step
                let idx = Int(srcPos)
                let frac = Float(srcPos - Double(idx))

                // Linear interpolation between adjacent samples
                let s0 = channelData[idx]
                let s1 = (idx + 1 < frameLength) ? channelData[idx + 1] : s0
                let sample = s0 + frac * (s1 - s0)

                // Clamp and convert to Int16
                let clamped = max(-1.0, min(1.0, sample))
                int16Samples[i] = Int16(clamped * 32767.0)
            }

            let data = int16Samples.withUnsafeBufferPointer { ptr in
                Data(bytes: ptr.baseAddress!, count: outputCount * 2)
            }
            let base64 = data.base64EncodedString()

            self.frameCount += 1
            self.totalSamplesIn += UInt64(frameLength)
            self.totalSamplesOut += UInt64(outputCount)
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
