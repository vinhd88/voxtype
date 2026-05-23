import AppKit

/// Manages the status bar item in the macOS menu bar.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private weak var transcriptionService: TranscriptionService?

    init(transcriptionService: TranscriptionService? = nil) {
        self.transcriptionService = transcriptionService

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoxType")
        statusItem.button?.image?.size = NSSize(width: 18, height: 18)

        rebuildMenu()
    }

    func updateIcon(for state: DictationState) {
        let (symbol, description): (String, String) = switch state {
        case .idle:
            // Show model-ready state when idle
            modelIdleSymbol()
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

    func rebuildMenu() {
        let menu = NSMenu()

        // Model status (disabled info item)
        let statusTitle = modelStatusText
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        // If model failed, add open settings action
        if case .failed = transcriptionService?.modelStatus {
            let retryItem = NSMenuItem(
                title: "Open Settings to Fix...",
                action: #selector(openSettings),
                keyEquivalent: ""
            )
            menu.addItem(retryItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About VoxType",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit VoxType",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        self.statusItem.menu = menu
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "VoxType",
                .applicationVersion: "1.0.0",
            ]
        )
    }

    // MARK: - Icon Helpers

    /// Returns the appropriate mic symbol for idle state based on model readiness.
    private func modelIdleSymbol() -> (String, String) {
        switch transcriptionService?.modelStatus {
        case .ready:
            return ("mic.fill", "VoxType — Ready")
        case .downloading:
            return ("mic.badge.xmark", "VoxType — Downloading Model")
        case .loading:
            return ("mic.badge.xmark", "VoxType — Loading Model")
        case .failed:
            return ("mic", "VoxType — Model Error")
        default:
            return ("mic", "VoxType")
        }
    }

    private var modelStatusText: String {
        switch transcriptionService?.modelStatus {
        case .ready:
            let name = WhisperModel.find(byId: transcriptionService?.currentModelId ?? "")?.displayName ?? "Model"
            return "\(name): Ready ✓"
        case .downloading:
            let pct = Int((transcriptionService?.downloadProgress ?? 0) * 100)
            return "Model: Downloading \(pct)%"
        case .loading:
            return "Model: Loading..."
        case .failed:
            return "Model: Failed"
        default:
            return "Model: Not Loaded"
        }
    }
}
