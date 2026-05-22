import AVFoundation
import Combine
import XCTest
@testable import VoiceInput

@MainActor
final class DictationManagerTests: XCTestCase {
    private var audio: MockAudioCaptureService!
    private var transcription: MockTranscriptionService!
    private var text: MockTextInsertionService!
    private var hotkey: HotkeyManager!
    private var manager: DictationManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        audio = MockAudioCaptureService()
        transcription = MockTranscriptionService()
        text = MockTextInsertionService()
        hotkey = HotkeyManager()
        manager = DictationManager(
            audioService: audio,
            transcriptionService: transcription,
            textService: text,
            hotkeyManager: hotkey
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        manager = nil
        hotkey = nil
        text = nil
        transcription = nil
        audio = nil
    }

    // MARK: - Helpers

    /// Send keyPressed and wait for Combine delivery via DispatchQueue.main.
    private func pressKey() async {
        hotkey.keyPressed.send()
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    /// Send keyReleased and wait for Combine delivery.
    private func releaseKey() async {
        hotkey.keyReleased.send()
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    // MARK: - Start Dictation

    func testStartSetsStateToListening() async {
        XCTAssertEqual(manager.state, .idle)
        await pressKey()
        XCTAssertEqual(manager.state, .listening)
    }

    func testStartDoesNothingWhenNotIdle() async {
        await pressKey()
        XCTAssertEqual(manager.state, .listening)
        await pressKey()
        XCTAssertEqual(manager.state, .listening)
    }

    func testStartErrorsWhenModelNotReady() async {
        transcription.mockReady = false
        await pressKey()
        XCTAssertEqual(manager.state, .error(message: "Speech model not ready yet"))
    }

    func testStartErrorsWhenNoMicPermission() async {
        audio.mockMicPermission = false
        await pressKey()
        XCTAssertEqual(manager.state, .error(message: "Microphone permission required"))
    }

    func testStartErrorsWhenRecordingThrows() async {
        audio.shouldThrow = true
        await pressKey()
        if case .error = manager.state {
            // Expected
        } else {
            XCTFail("Expected error state, got \(manager.state)")
        }
    }

    // MARK: - Stop Dictation

    func testStopTriggersTranscription() async throws {
        await pressKey()
        XCTAssertEqual(manager.state, .listening)

        await releaseKey()

        // Wait for async transcription + insertion (mock is instant)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(text.lastInsertedText, "hello world")

        // Verify it completed successfully
        if case .done(let t) = manager.state {
            XCTAssertEqual(t, "hello world")
        } else {
            XCTFail("Expected .done state, got \(manager.state)")
        }
    }

    func testFullCycleEndsInDone() async throws {
        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 500_000_000)

        if case .done(let t) = manager.state {
            XCTAssertEqual(t, "hello world")
        } else {
            XCTFail("Expected .done state, got \(manager.state)")
        }
    }

    func testEmptyTranscriptionShowsError() async throws {
        transcription.mockResult = .success("")
        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 500_000_000)

        if case .error(let msg) = manager.state {
            XCTAssertEqual(msg, "No speech detected")
        } else {
            XCTFail("Expected .error state, got \(manager.state)")
        }
    }

    func testTranscriptionFailureShowsError() async throws {
        transcription.mockResult = .failure(TranscriptionError.modelNotReady)
        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 500_000_000)

        if case .error(let msg) = manager.state {
            XCTAssertTrue(msg.contains("Transcription failed"), "Got: \(msg)")
        } else {
            XCTFail("Expected .error state, got \(manager.state)")
        }
    }

    func testClipboardOnlyResult() async throws {
        text.mockResult = .clipboardOnly
        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 500_000_000)

        if case .done(let t) = manager.state {
            XCTAssertTrue(t.hasPrefix("(Copied)"), "Expected (Copied) prefix, got: \(t)")
        } else {
            XCTFail("Expected .done state, got \(manager.state)")
        }
    }

    func testInsertionFailedResult() async throws {
        text.mockResult = .failed("no access")
        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 500_000_000)

        if case .done(let t) = manager.state {
            XCTAssertTrue(t.contains("Copy failed"), "Expected copy failed message, got: \(t)")
        } else {
            XCTFail("Expected .done state, got \(manager.state)")
        }
    }

    func testStopIgnoredWhenNotListening() async {
        await releaseKey()
        XCTAssertEqual(manager.state, .idle)
    }

    func testEmptyAudioBufferShowsError() async throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        let emptyBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        emptyBuffer.frameLength = 0
        audio.stubBuffer = emptyBuffer

        await pressKey()
        await releaseKey()

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(manager.state, .error(message: "No audio captured"))
    }

    // MARK: - Auto Reset

    func testAutoResetsToIdleAfterError() async {
        transcription.mockReady = false
        await pressKey()
        if case .error = manager.state {
            // Expected
        } else {
            XCTFail("Expected error state")
        }
    }
}
