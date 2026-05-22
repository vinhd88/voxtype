import AVFoundation
import Combine
import WhisperKit

/// Manages WhisperKit model lifecycle and transcription.
@MainActor
final class TranscriptionService: ObservableObject {
    @Published private(set) var modelStatus: ModelStatus = .notLoaded

    private var whisperKit: WhisperKit?
    private let modelName = "large-v3-turbo"

    enum ModelStatus: Equatable {
        case notLoaded
        case downloading
        case loading
        case ready
        case failed(String)
    }

    /// Download and load the WhisperKit model. Call once on app launch.
    func prepareModel() async {
        guard modelStatus != .ready else { return }

        do {
            modelStatus = .loading

            let config = WhisperKitConfig(model: modelName)
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            modelStatus = .ready
            print("[Transcription] Model ready: \(modelName)")
        } catch {
            modelStatus = .failed(error.localizedDescription)
            print("[Transcription] Model preparation failed: \(error)")
        }
    }

    /// Transcribe PCM audio buffer to text.
    func transcribe(_ audio: AVAudioPCMBuffer) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.modelNotReady
        }

        // Write PCM to temp WAV file — WhisperKit's file-based API is most reliable
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceinput_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try writePCMTempoWAV(audio, to: tempURL)

        let results = try await whisperKit.transcribe(audioPath: tempURL.path)
        let text = results.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text
    }

    var isReady: Bool { modelStatus == .ready }

    // MARK: - WAV Writing

    private func writePCMTempoWAV(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let format = buffer.format
        let frameCount = buffer.frameLength
        let bytesPerFrame = UInt32(format.streamDescription.pointee.mBytesPerFrame)
        let dataSize = frameCount * bytesPerFrame

        guard let channelData = buffer.floatChannelData?[0] else {
            throw TranscriptionError.invalidAudio
        }

        let data = Data(bytes: channelData, count: Int(dataSize))

        // Build WAV header + data
        var wav = Data()
        let sampleRate = Int32(format.sampleRate)
        let channels = Int32(format.channelCount)
        let bitsPerSample = Int32(32) // Float32

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(36 + data.count).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)
        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // IEEE float
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * channels * bitsPerSample / 8
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        // data chunk
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(data.count).littleEndian) { Array($0) })
        wav.append(data)

        try wav.write(to: url)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotReady
    case invalidAudio
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotReady: "Speech model is not loaded yet"
        case .invalidAudio: "Audio buffer is invalid"
        case .emptyResult: "No speech detected"
        }
    }
}
