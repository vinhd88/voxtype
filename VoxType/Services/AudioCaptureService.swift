import AVFoundation
import Combine

/// Captures microphone audio, converts to 16kHz mono PCM for WhisperKit.
/// macOS does not use AVAudioSession — audio engine is started directly.
class AudioCaptureService: ObservableObject {
    @Published private(set) var audioLevel: Float = 0.0

    private let bufferQueue = DispatchQueue(label: "com.voiceinput.audiobuffer")
    private var pcmBuffers: [AVAudioPCMBuffer] = []
    private var engine: AVAudioEngine?
    private var _isRecording = false

    var isCurrentlyRecording: Bool {
        bufferQueue.sync { _isRecording }
    }

    private var isRecording: Bool {
        get { bufferQueue.sync { _isRecording } }
        set { bufferQueue.sync { _isRecording = newValue } }
    }

    // Target format for WhisperKit: 16kHz mono float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Check if microphone permission is granted on macOS.
    var hasMicPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Request microphone permission.
    @discardableResult
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording audio from the default microphone.
    func startRecording() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw AudioError.formatError
        }

        bufferQueue.sync { pcmBuffers.removeAll() }

        // nonisolated class to capture weak self for the audio tap callback
        // @unchecked Sendable: safe because all shared state access is through bufferQueue or main queue
        final class TapHandler: @unchecked Sendable {
            private weak var service: AudioCaptureService?
            private let converter: AVAudioConverter
            private let targetFormat: AVAudioFormat

            init(service: AudioCaptureService, converter: AVAudioConverter, targetFormat: AVAudioFormat) {
                self.service = service
                self.converter = converter
                self.targetFormat = targetFormat
            }

            func handle(_ buffer: AVAudioPCMBuffer) {
                guard let service else { return }
                // Calculate audio level (RMS)
                if let channelData = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameCount { sum += channelData[i] * channelData[i] }
                    let rms = sqrt(sum / Float(max(frameCount, 1)))
                    DispatchQueue.main.async {
                        service.audioLevel = min(rms * 5.0, 1.0)
                    }
                }

                // Convert to target format (16kHz mono)
                let ratio = targetFormat.sampleRate / buffer.format.sampleRate
                let targetFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                guard targetFrameCount > 0,
                      let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrameCount)
                else { return }

                var error: NSError?
                let inputBuffer = buffer
                converter.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                if let error {
                    print("[AudioCapture] Conversion error: \(error)")
                    return
                }

                service.bufferQueue.sync {
                    service.pcmBuffers.append(converted)
                }
            }
        }

        nonisolated(unsafe) let handler = TapHandler(service: self, converter: converter, targetFormat: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { buffer, _ in
            handler.handle(buffer)
        }

        try engine.start()
        self.engine = engine
        isRecording = true
        print("[AudioCapture] Recording started (hardware: \(hardwareFormat.sampleRate)Hz)")
    }

    /// Stop recording and return the merged PCM buffer in 16kHz mono format.
    func stopRecording() -> AVAudioPCMBuffer {
        guard isRecording else {
            return AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1)!
        }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        isRecording = false
        audioLevel = 0.0

        let merged = mergeBuffers()
        print("[AudioCapture] Recording stopped, \(merged.frameLength) frames captured")
        return merged
    }

    // MARK: - Private

    private func mergeBuffers() -> AVAudioPCMBuffer {
        let buffers = bufferQueue.sync { pcmBuffers }
        let totalFrames = buffers.reduce(0) { $0 + $1.frameLength }
        guard totalFrames > 0 else {
            return AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1)!
        }

        let merged = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: totalFrames)!
        var offset: Int = 0

        for buffer in buffers {
            let frames = Int(buffer.frameLength)
            if let src = buffer.floatChannelData?[0], let dst = merged.floatChannelData?[0] {
                dst.advanced(by: offset).initialize(from: src, count: frames)
            }
            offset += frames
        }

        merged.frameLength = totalFrames
        bufferQueue.sync { pcmBuffers.removeAll() }
        return merged
    }
}

enum AudioError: LocalizedError {
    case formatError
    case notRecording

    var errorDescription: String? {
        switch self {
        case .formatError: "Audio format conversion failed"
        case .notRecording: "Not currently recording"
        }
    }
}
