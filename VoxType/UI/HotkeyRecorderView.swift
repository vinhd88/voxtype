import AppKit
import CoreGraphics
import SwiftUI

/// NSViewRepresentable that captures a single key press for hotkey recording.
/// Supports modifier-only keys (Right Option, Caps Lock) and combo keys (Ctrl+Space, etc.).
struct HotkeyRecorderView: NSViewRepresentable {
    let onRecorded: (CGKeyCode, UInt) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        view.onRecorded = onRecorded
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        nsView.onRecorded = onRecorded
        nsView.onCancel = onCancel
    }
}

final class RecorderNSView: NSView {
    var onRecorded: ((CGKeyCode, UInt) -> Void)?
    var onCancel: (() -> Void)?

    private var localMonitor: Any?
    private var flagsMonitor: Any?
    private var previousFlags: CGEventFlags = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        installMonitors()
    }

    override func removeFromSuperview() {
        removeMonitors()
        super.removeFromSuperview()
    }

    private func installMonitors() {
        // Monitor keyDown events for character keys
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil // Consume the event
        }

        // Monitor flagsChanged for modifier-only keys
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return nil
        }
    }

    private func removeMonitors() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)

        // Escape cancels recording
        if keyCode == 53 {
            onCancel?()
            removeMonitors()
            return
        }

        // Block system-critical shortcuts
        if isSystemShortcut(keyCode: keyCode, modifiers: event.modifierFlags) {
            return
        }

        let modifiers = extractModifiers(event.modifierFlags)

        // If only modifiers are pressed (no character), this fires for character keys
        if modifiers == 0 {
            // Single key without modifiers — valid for modifier-only keys won't reach here
            // This handles keys like Space, Return, etc.
        }

        onRecorded?(keyCode, modifiers)
        removeMonitors()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)
        let currentFlags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))

        // Detect modifier key press (not release)
        let changedFlags = currentFlags.symmetricDifference(previousFlags)
        let newFlags = changedFlags.intersection(currentFlags)

        previousFlags = currentFlags

        // Only react to modifier press, not release
        guard !newFlags.isEmpty else { return }

        // Check if this is a modifier-only key (right-side modifiers)
        let isModifierOnly = isModifierKeyCode(keyCode)
        guard isModifierOnly else { return }

        // Extract the specific modifier flag for this key
        let modifierFlag = modifierFlagForKeyCode(keyCode)
        onRecorded?(keyCode, modifierFlag)
        removeMonitors()
    }

    private func extractModifiers(_ nsModifiers: NSEvent.ModifierFlags) -> UInt {
        var flags: UInt = 0
        if nsModifiers.contains(.control) { flags |= UInt(CGEventFlags.maskControl.rawValue) }
        if nsModifiers.contains(.option) { flags |= UInt(CGEventFlags.maskAlternate.rawValue) }
        if nsModifiers.contains(.shift) { flags |= UInt(CGEventFlags.maskShift.rawValue) }
        if nsModifiers.contains(.command) { flags |= UInt(CGEventFlags.maskCommand.rawValue) }
        return flags
    }

    private func isModifierKeyCode(_ code: CGKeyCode) -> Bool {
        // Right Option: 61, Right Cmd: 54, Right Ctrl: 62, Caps Lock: 57
        // Left Option: 58, Left Cmd: 55, Left Ctrl: 59, Left Shift: 56, Right Shift: 60
        [54, 55, 56, 57, 58, 59, 60, 61, 62].contains(code)
    }

    private func modifierFlagForKeyCode(_ code: CGKeyCode) -> UInt {
        switch code {
        case 58, 61: UInt(CGEventFlags.maskAlternate.rawValue) // Option
        case 55, 54: UInt(CGEventFlags.maskCommand.rawValue)   // Command
        case 59, 62: UInt(CGEventFlags.maskControl.rawValue)   // Control
        case 56, 60: UInt(CGEventFlags.maskShift.rawValue)     // Shift
        case 57: 0 // Caps Lock — no modifier flag, just the keycode
        default: 0
        }
    }

    private func isSystemShortcut(keyCode: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Block Cmd+Q, Cmd+W, Cmd+H, Cmd+M, Cmd+Tab
        if modifiers.contains(.command) {
            return [0x0C, 0x0D, 0x04, 0x2E, 48].contains(Int(keyCode)) // Q, W, H, M, Tab
        }
        return false
    }
}
