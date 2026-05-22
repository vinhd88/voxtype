import AVFoundation
import Combine
@testable import VoxType

/// Mock audio service that simulates recording without hardware.
class MockAudioCaptureService: AudioCaptureService {
    var shouldThrow = false
    var mockMicPermission = true
    var stubBuffer: AVAudioPCMBuffer?

    override var hasMicPermission: Bool { mockMicPermission }

    override func startRecording() throws {
        if shouldThrow { throw AudioError.formatError }
    }

    override func stopRecording() -> AVAudioPCMBuffer {
        if let stub = stubBuffer { return stub }
        // Return 500ms silence buffer at 16kHz mono (above min transcription threshold)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
        buffer.frameLength = 8000
        return buffer
    }
}

/// Mock transcription service that returns preset text.
@MainActor
class MockTranscriptionService: TranscriptionService {
    var mockResult: Result<String, Error> = .success("hello world")
    var mockReady = true

    override var isReady: Bool { mockReady }

    override func transcribe(_ audio: AVAudioPCMBuffer) async throws -> String {
        try mockResult.get()
    }
}

/// Mock text service that tracks insertions.
class MockTextInsertionService: TextInsertionService {
    var lastInsertedText: String?
    var mockResult: InsertionResult = .success

    override func insertText(_ text: String) async -> InsertionResult {
        lastInsertedText = text
        return mockResult
    }
}
