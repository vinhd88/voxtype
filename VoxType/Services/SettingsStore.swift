import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    // General
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }
    @AppStorage("silenceDetectionEnabled") var silenceDetectionEnabled: Bool = true
    @AppStorage("silenceTimeout") var silenceTimeout: Double = 1.5

    // Hotkey (Phase 3 will implement recorder)
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 61 // Right Option
    @AppStorage("hotkeyModifiers") var hotkeyModifiers: Int = 0

    // Advanced
    @AppStorage("soundFeedback") var soundFeedback: Bool = false
    @AppStorage("debugLogging") var debugLogging: Bool = false

    // Onboarding
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false

    // Model selection
    @AppStorage("selectedModel") var selectedModel: String = WhisperModel.defaultModel.id

    // Persisted model folder path from WhisperKit download (avoids re-downloading)
    @AppStorage("modelFolderPath") var modelFolderPath: String = ""

    // Computed: human-readable hotkey name
    var hotkeyDisplayName: String {
        let keyCode = CGKeyCode(hotkeyKeyCode)
        let modifierNames = modifierFlagNames(UInt(hotkeyModifiers))

        if modifierNames.isEmpty {
            return keyCodeName(keyCode)
        }
        return "\(modifierNames)\(keyCodeName(keyCode))"
    }

    static let defaultKeyCode: CGKeyCode = 61 // Right Option
    static let defaultModifiers: UInt = 0

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] Launch at login error: \(error)")
            launchAtLogin = !launchAtLogin // Revert on failure
        }
    }

    private func keyCodeName(_ code: CGKeyCode) -> String {
        switch code {
        case 61: "Right Option"
        case 54: "Right Command"
        case 58: "Left Option"
        case 55: "Left Command"
        case 59: "Left Control"
        case 62: "Right Control"
        case 57: "Caps Lock"
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 51: "Delete"
        case 53: "Escape"
        default: "Key \(code)"
        }
    }

    private func modifierFlagNames(_ flags: UInt) -> String {
        var parts: [String] = []
        let cgFlags = CGEventFlags(rawValue: UInt64(flags))
        if cgFlags.contains(.maskControl) { parts.append("⌃") }
        if cgFlags.contains(.maskAlternate) { parts.append("⌥") }
        if cgFlags.contains(.maskShift) { parts.append("⇧") }
        if cgFlags.contains(.maskCommand) { parts.append("⌘") }
        return parts.joined()
    }
}
