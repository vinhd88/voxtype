import XCTest
@testable import VoxType

final class DictationStateTests: XCTestCase {

    // MARK: - Equatable

    func testIdleEqualsIdle() {
        XCTAssertEqual(DictationState.idle, DictationState.idle)
    }

    func testListeningEqualsListening() {
        XCTAssertEqual(DictationState.listening, DictationState.listening)
    }

    func testTranscribingEqualsTranscribing() {
        XCTAssertEqual(DictationState.transcribing, DictationState.transcribing)
    }

    func testDoneWithSameTextAreEqual() {
        XCTAssertEqual(DictationState.done(text: "hello"), DictationState.done(text: "hello"))
    }

    func testDoneWithDifferentTextNotEqual() {
        XCTAssertNotEqual(DictationState.done(text: "hello"), DictationState.done(text: "world"))
    }

    func testErrorWithSameMessageAreEqual() {
        XCTAssertEqual(DictationState.error(message: "fail"), DictationState.error(message: "fail"))
    }

    func testErrorWithDifferentMessageNotEqual() {
        XCTAssertNotEqual(DictationState.error(message: "a"), DictationState.error(message: "b"))
    }

    func testDifferentCasesNotEqual() {
        XCTAssertNotEqual(DictationState.idle, DictationState.listening)
        XCTAssertNotEqual(DictationState.listening, DictationState.transcribing)
        XCTAssertNotEqual(DictationState.done(text: ""), DictationState.idle)
        XCTAssertNotEqual(DictationState.error(message: ""), DictationState.idle)
    }

    // MARK: - isProcessing

    func testIsProcessingOnlyForListeningAndTranscribing() {
        XCTAssertFalse(DictationState.idle.isProcessing)
        XCTAssertTrue(DictationState.listening.isProcessing)
        XCTAssertTrue(DictationState.transcribing.isProcessing)
        XCTAssertFalse(DictationState.done(text: "hi").isProcessing)
        XCTAssertFalse(DictationState.error(message: "x").isProcessing)
    }
}
