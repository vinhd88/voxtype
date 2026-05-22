import AppKit

/// Manages the status bar item in the macOS menu bar.
final class MenuBarController {
    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoxType")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit VoxType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func updateIcon(for state: DictationState) {
        let (symbol, description): (String, String) = switch state {
        case .idle:
            ("mic", "VoxType")
        case .listening:
            ("mic.fill", "VoxType — Listening")
        case .transcribing:
            ("mic.badge.xmark", "VoxType — Transcribing")
        case .done:
            ("checkmark.circle", "VoxType — Done")
        case .error:
            ("exclamationmark.triangle", "VoxType — Error")
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
    }
}
