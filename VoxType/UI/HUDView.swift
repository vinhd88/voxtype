import SwiftUI
import AppKit

// MARK: - HUD Panel

/// Floating panel that shows dictation state near the menu bar.
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        minSize = NSSize(width: 200, height: 40)
        maxSize = NSSize(width: 400, height: 80)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - HUD State

/// Observable state shared with the persistent NSHostingView.
@MainActor
@Observable
final class HUDState {
    var state: DictationState = .idle
    var audioLevel: Float = 0.0
}

// MARK: - HUD Controller

/// Manages HUD panel lifecycle and positioning.
@MainActor
final class HUDController {
    private var panel: HUDPanel?
    private let hudState = HUDState()

    func show(state: DictationState, audioLevel: Float) {
        if state == .idle {
            hide()
            return
        }

        hudState.state = state
        hudState.audioLevel = audioLevel

        let p: HUDPanel
        if let existing = panel {
            p = existing
        } else {
            p = createPanel()
            let view = HUDContentView()
                .environment(hudState)
                .environment(\.colorScheme, .dark)
            p.contentView = NSHostingView(rootView: view)
        }
        p.orderFrontRegardless()
        positionNearMenuBar(p)
    }

    func updateAudioLevel(_ level: Float) {
        guard let panel = panel, panel.isVisible else { return }
        if hudState.state == .listening {
            hudState.audioLevel = level
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() -> HUDPanel {
        let p = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 52))
        self.panel = p
        return p
    }

    private func positionNearMenuBar(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let menuBarBottom = screen.visibleFrame.maxY
        let x = screen.frame.midX - panel.frame.width / 2
        let y = screen.frame.maxY - (screen.frame.height - menuBarBottom) - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - HUD SwiftUI Content

struct HUDContentView: View {
    @Environment(HUDState.self) private var hudState

    var body: some View {
        let state = hudState.state
        let audioLevel = hudState.audioLevel

        HStack(spacing: 10) {
            icon(for: state)
            VStack(alignment: .leading, spacing: 2) {
                label(for: state)
                if state == .listening {
                    AudioLevelBar(level: audioLevel)
                }
                if case .done(let text) = state {
                    Text(String(text.prefix(40)) + (text.count > 40 ? "..." : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if case .error(let msg) = state {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    @ViewBuilder private func icon(for state: DictationState) -> some View {
        switch state {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .font(.title3)
        case .transcribing:
            ProgressView()
                .controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private func label(for state: DictationState) -> some View {
        switch state {
        case .listening:
            Text("Listening...")
                .font(.subheadline.weight(.medium))
        case .transcribing:
            Text("Transcribing...")
                .font(.subheadline.weight(.medium))
        case .done:
            Text("Inserted")
                .font(.subheadline.weight(.medium))
        case .error:
            Text("Error")
                .font(.subheadline.weight(.medium))
        case .idle:
            EmptyView()
        }
    }
}

// MARK: - Audio Level Bar

struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: max(CGFloat(level) * geo.size.width, 2), height: 4)
            }
        }
        .frame(height: 4)
    }
}
