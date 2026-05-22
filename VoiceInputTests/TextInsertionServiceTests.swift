import AppKit
import XCTest
@testable import VoiceInput

final class TextInsertionServiceTests: XCTestCase {

    private var service: TextInsertionService!

    override func setUp() {
        service = TextInsertionService()
    }

    override func tearDown() {
        service = nil
    }

    // MARK: - Clipboard Write

    func testInsertWritesTextToClipboard() async {
        // Clear clipboard first
        NSPasteboard.general.clearContents()

        _ = await service.insertText("test text")

        let content = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(content, "test text")
    }

    func testInsertReturnsClipboardOnlyWithoutAccessibility() async {
        // In test environment, accessibility is typically not granted
        let result = await service.insertText("hello")
        // Without accessibility, should return clipboardOnly or success
        // (depends on whether AX is trusted in the test runner)
        switch result {
        case .success, .clipboardOnly:
            break // Both acceptable
        case .failed:
            XCTFail("Insertion should not fail for clipboard write")
        }
    }

    func testInsertEmptyString() async {
        _ = await service.insertText("")
        let content = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(content, "")
    }

    func testInsertUnicodeText() async {
        let unicode = "Xin chào Việt Nam 🇻🇳"
        _ = await service.insertText(unicode)
        let content = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(content, unicode)
    }

    func testInsertLongText() async {
        let longText = String(repeating: "a", count: 10_000)
        _ = await service.insertText(longText)
        let content = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(content?.count, 10_000)
    }

    // MARK: - Result Types

    func testInsertionResultEquality() {
        XCTAssertEqual(TextInsertionService.InsertionResult.success, .success)
        XCTAssertEqual(TextInsertionService.InsertionResult.clipboardOnly, .clipboardOnly)
        XCTAssertNotEqual(TextInsertionService.InsertionResult.success, .clipboardOnly)
    }

    func testInsertionResultFailedEquality() {
        XCTAssertEqual(
            TextInsertionService.InsertionResult.failed("a"),
            .failed("a")
        )
        XCTAssertNotEqual(
            TextInsertionService.InsertionResult.failed("a"),
            .failed("b")
        )
    }
}
