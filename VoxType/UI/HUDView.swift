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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - HUD Controller

/// Manages HUD panel lifecycle and positioning.
@MainActor
final class HUDController {
    private var panel: HUDPanel?

    func show(state: DictationState, audioLevel: Float) {
        if state == .idle {
            hide()
            return
        }

        let p = panel ?? createPanel()
        let view = HUDContentView(state: state, audioLevel: audioLevel)
            .environment(\.colorScheme, .dark)

        p.contentView = NSHostingView(rootView: view)
        p.orderFrontRegardless()
        positionNearMenuBar(p)
    }

    func updateAudioLevel(_ level: Float) {
        guard let panel = panel, panel.isVisible else { return }
        // Re-render with updated audio level
        let currentState = (panel.contentView as? NSHostingView<HUDContentView>)?.rootView.state ?? .idle
        if currentState == .listening {
            let view = HUDContentView(state: currentState, audioLevel: level)
                .environment(\.colorScheme, .dark)
            panel.contentView = NSHostingView(rootView: view)
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
    let state: DictationState
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                label
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    @ViewBuilder private var icon: some View {
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

    @ViewBuilder private var label: some View {
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
