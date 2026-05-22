import AppKit

/// Manages the status bar item in the macOS menu bar.
final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Voice Input")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Voice Input", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateIcon(for state: DictationState) {
        let (symbol, description): (String, String) = switch state {
        case .idle:
            ("mic", "Voice Input")
        case .listening:
            ("mic.fill", "Voice Input — Listening")
        case .transcribing:
            ("mic.badge.xmark", "Voice Input — Transcribing")
        case .done:
            ("checkmark.circle", "Voice Input — Done")
        case .error:
            ("exclamationmark.triangle", "Voice Input — Error")
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }
}
