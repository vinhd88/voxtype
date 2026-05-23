import Combine
@preconcurrency import CoreFoundation
import AppKit

/// Global hold-to-talk hotkey using CGEvent tap for reliable key-down/key-up.
/// Reads target key from SettingsStore and reinstalls tap when config changes.
final class HotkeyManager: ObservableObject {
    let keyPressed = PassthroughSubject<Void, Never>()
    let keyReleased = PassthroughSubject<Void, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    private var pollTimer: Timer?

    private var targetKeyCode: CGKeyCode
    private var targetModifiers: UInt

    private static let axPromptOption = "AXTrustedCheckOptionPrompt" as CFString

    init(settings: SettingsStore? = nil) {
        // Read initial hotkey from UserDefaults directly (SettingsStore is @MainActor)
        let savedKeyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let savedModifiers = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        targetKeyCode = savedKeyCode > 0 ? CGKeyCode(savedKeyCode) : 61
        targetModifiers = UInt(savedModifiers)

        // Observe UserDefaults changes for hotkey config
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromDefaults()
        }

        installEventTapOrPoll()
    }

    deinit {
        pollTimer?.invalidate()
        removeEventTap()
    }

    // MARK: - Hotkey Update

    private func syncFromDefaults() {
        let newKeyCode = CGKeyCode(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let newModifiers = UInt(UserDefaults.standard.integer(forKey: "hotkeyModifiers"))
        let effectiveKeyCode = newKeyCode == 0 ? CGKeyCode(61) : newKeyCode

        guard effectiveKeyCode != targetKeyCode || newModifiers != targetModifiers else { return }
        updateHotkey(keyCode: effectiveKeyCode, modifiers: newModifiers)
    }

    private func updateHotkey(keyCode: CGKeyCode, modifiers: UInt) {
        targetKeyCode = keyCode
        targetModifiers = modifiers
        isKeyDown = false
        removeEventTap()
        installEventTap()
        print("[Hotkey] Updated to keyCode=\(keyCode), modifiers=\(modifiers)")
    }

    // MARK: - CGEvent Tap (Hold-to-Talk)

    private func installEventTapOrPoll() {
        if AXIsProcessTrusted() {
            installEventTap()
        } else {
            print("[Hotkey] Waiting for accessibility permission...")
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.installEventTap()
                }
            }
        }
    }

    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("[Hotkey] Failed to create event tap")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Hotkey] Event tap installed — keyCode=\(targetKeyCode)")
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
    }

    /// Handle intercepted key events. Returns the event to pass through (we only listen).
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Check if this key matches our target
        let isTargetKey: Bool
        if targetModifiers == 0 {
            // Modifier-only mode: match by keyCode alone
            isTargetKey = keyCode == targetKeyCode
        } else {
            // Combo mode: match keyCode + modifier flags
            let eventMods = extractModifierFlags(event.flags)
            isTargetKey = keyCode == targetKeyCode && eventMods == targetModifiers
        }

        guard isTargetKey else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyDown {
                isKeyDown = true
                keyPressed.send()
            }
        case .keyUp:
            if isKeyDown {
                isKeyDown = false
                keyReleased.send()
            }
        case .flagsChanged:
            // Modifier keys use flagsChanged for both press and release
            let isPressed = isModifierPressed(event.flags)
            if isPressed && !isKeyDown {
                isKeyDown = true
                keyPressed.send()
            } else if !isPressed && isKeyDown {
                isKeyDown = false
                keyReleased.send()
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Modifier Detection

    /// Check if the target modifier is currently pressed based on event flags.
    private func isModifierPressed(_ flags: CGEventFlags) -> Bool {
        if targetModifiers == 0 {
            // Modifier-only key: check if the relevant modifier flag is set
            switch targetKeyCode {
            case 58, 61: return flags.contains(.maskAlternate)  // Option
            case 55, 54: return flags.contains(.maskCommand)    // Command
            case 59, 62: return flags.contains(.maskControl)    // Control
            case 56, 60: return flags.contains(.maskShift)      // Shift
            case 57: return flags.contains(.maskAlternate)      // Caps Lock (approximation)
            default: return false
            }
        }
        // Combo keys: check if all required modifiers are present
        return flags.rawValue & UInt64(targetModifiers) == UInt64(targetModifiers)
    }

    private func extractModifierFlags(_ flags: CGEventFlags) -> UInt {
        var result: UInt = 0
        if flags.contains(.maskControl) { result |= UInt(CGEventFlags.maskControl.rawValue) }
        if flags.contains(.maskAlternate) { result |= UInt(CGEventFlags.maskAlternate.rawValue) }
        if flags.contains(.maskShift) { result |= UInt(CGEventFlags.maskShift.rawValue) }
        if flags.contains(.maskCommand) { result |= UInt(CGEventFlags.maskCommand.rawValue) }
        return result
    }

    /// Check if accessibility permission is granted.
    var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt user for accessibility permission.
    func requestAccessibility() {
        let options = [Self.axPromptOption: true as CFBoolean] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
