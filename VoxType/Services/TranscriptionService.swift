import AVFoundation
import Combine
import WhisperKit

// MARK: - Model Catalog

/// Available WhisperKit speech recognition models.
struct WhisperModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sizeLabel: String
    let description: String
    let iconName: String
    let tier: Int

    static let catalog: [WhisperModel] = [
        WhisperModel(
            id: "openai_whisper-tiny",
            displayName: "Whisper Tiny",
            sizeLabel: "~75 MB",
            description: "Fastest, good for quick notes",
            iconName: "bolt.fill",
            tier: 0
        ),
        WhisperModel(
            id: "openai_whisper-base",
            displayName: "Whisper Base",
            sizeLabel: "~150 MB",
            description: "Balanced speed and accuracy",
            iconName: "scope",
            tier: 1
        ),
        WhisperModel(
            id: "openai_whisper-large-v3_turbo",
            displayName: "Whisper Large Turbo",
            sizeLabel: "~800 MB",
            description: "Best accuracy, recommended",
            iconName: "star.fill",
            tier: 2
        ),
    ]

    static let defaultModel = catalog[2] // Large Turbo — best accuracy

    static func find(byId id: String) -> WhisperModel? {
        catalog.first { $0.id == id }
    }
}

// MARK: - TranscriptionService

/// Manages WhisperKit model lifecycle and transcription.
@MainActor
class TranscriptionService: ObservableObject {
    @Published private(set) var modelStatus: ModelStatus = .notLoaded
    @Published private(set) var downloadProgress: Double = 0.0

    private var whisperKit: WhisperKit?
    private(set) var currentModelId: String = WhisperModel.defaultModel.id

    enum ModelStatus: Equatable {
        case notLoaded
        case downloading
        case loading
        case ready
        case failed(String)
    }

    /// Download and load a WhisperKit model. No-op if the same model is already ready.
    func prepareModel(named modelId: String? = nil) async {
        let targetId = modelId ?? WhisperModel.defaultModel.id

        guard modelStatus != .ready || currentModelId != targetId else { return }
        guard modelStatus != .loading && modelStatus != .downloading else { return }

        currentModelId = targetId

        do {
            modelStatus = .downloading
            downloadProgress = 0.0

            let modelFolder = try await WhisperKit.download(
                variant: targetId,
                progressCallback: { [weak self] progress in
                    guard progress.totalUnitCount > 0 else { return }
                    let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = fraction
                    }
                }
            )

            modelStatus = .loading
            downloadProgress = 1.0

            let config = WhisperKitConfig(modelFolder: modelFolder.path)
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            modelStatus = .ready
        } catch {
            modelStatus = .failed(error.localizedDescription)
        }
    }

    /// Transcribe PCM audio buffer to text.
    func transcribe(_ audio: AVAudioPCMBuffer) async throws -> String {
        guard let whisperKit else {
            throw TranscriptionError.modelNotReady
        }

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

        var wav = Data()
        let sampleRate = Int32(format.sampleRate)
        let channels = Int32(format.channelCount)
        let bitsPerSample = Int32(32)

        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(36 + data.count).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * channels * bitsPerSample / 8
        wav.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        wav.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
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
