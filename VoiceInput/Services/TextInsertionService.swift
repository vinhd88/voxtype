import AppKit
import CoreGraphics

/// Inserts transcribed text into the active app via clipboard + Cmd+V.
final class TextInsertionService {
    enum InsertionResult {
        case success
        case clipboardOnly
        case failed(String)
    }

    /// Insert text at the current cursor position in the frontmost app.
    func insertText(_ text: String) async -> InsertionResult {
        let pasteboard = NSPasteboard.general

        // Save previous clipboard content
        let previousContent = pasteboard.string(forType: .string)
        let previousChangeCount = pasteboard.changeCount

        // Write text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Brief delay to ensure clipboard is written
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Attempt simulated paste
        let result = simulatePaste()

        // Schedule clipboard restoration after a delay (best effort)
        if let previous = previousContent {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                if pasteboard.changeCount != previousChangeCount {
                    // Only restore if clipboard hasn't been changed again by user
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }

        return result
    }

    /// Check if accessibility permission is granted for paste simulation.
    var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Private

    private func simulatePaste() -> InsertionResult {
        // Check accessibility permission
        guard AXIsProcessTrusted() else {
            return .clipboardOnly
        }

        // Simulate Cmd+V keypress
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09, // V key
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: 0x09,
            keyDown: false
        ) else {
            return .failed("Could not create key events")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return .success
    }
}
