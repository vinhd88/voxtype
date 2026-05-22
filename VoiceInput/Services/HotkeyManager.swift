import Combine
@preconcurrency import CoreFoundation
import AppKit

/// Global hold-to-talk hotkey using CGEvent tap for reliable key-down/key-up.
final class HotkeyManager: ObservableObject {
    let keyPressed = PassthroughSubject<Void, Never>()
    let keyReleased = PassthroughSubject<Void, Never>()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false

    // Default hold-to-talk key: Right Option
    // KeyCode 61 = Right Option on macOS
    private let targetKeyCode: CGKeyCode = 61

    // Hardcoded to avoid Swift 6 concurrency issue with kAXTrustedCheckOptionPrompt
    private static let axPromptOption = "AXTrustedCheckOptionPrompt" as CFString

    init() {
        installEventTap()
    }

    deinit {
        removeEventTap()
    }

    // MARK: - CGEvent Tap (Hold-to-Talk)

    private func installEventTap() {
        // Check accessibility permission first (no prompt)
        guard AXIsProcessTrusted() else {
            print("[Hotkey] Accessibility not granted. Hold-to-talk requires Accessibility permission.")
            print("[Hotkey] Please grant in System Settings → Privacy & Security → Accessibility")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                // Safe: HotkeyManager.deinit calls removeEventTap() which disables the tap
                // before the object is deallocated, so the callback cannot fire after deinit.
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

        print("[Hotkey] Event tap installed — hold Right Option to dictate")
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
        // Re-enable tap if it was disabled by the system
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isRightOption = keyCode == targetKeyCode

        guard isRightOption else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown, .flagsChanged:
            if !isKeyDown {
                isKeyDown = true
                print("[Hotkey] Key DOWN")
                keyPressed.send()
            }
        case .keyUp:
            if isKeyDown {
                isKeyDown = false
                print("[Hotkey] Key UP")
                keyReleased.send()
            }
        default:
            break
        }

        return Unmanaged.passRetained(event)
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
