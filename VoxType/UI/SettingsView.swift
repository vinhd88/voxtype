import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            HotkeySettingsView()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Silence Detection") {
                Toggle("Auto-stop when silent", isOn: $settings.silenceDetectionEnabled)
                if settings.silenceDetectionEnabled {
                    HStack {
                        Text("Silence timeout")
                        Slider(value: $settings.silenceTimeout, in: 0.5...3.0, step: 0.1) {
                            Text("Timeout")
                        }
                        Text(String(format: "%.1fs", settings.silenceTimeout))
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Tab

struct HotkeySettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hold-to-Talk Hotkey")
                .font(.headline)

            HStack {
                Text("Current: \(settings.hotkeyDisplayName)")
                    .font(.body)
                Spacer()
                Button(isRecording ? "Cancel" : "Record New") {
                    isRecording.toggle()
                }
            }

            if isRecording {
                GroupBox {
                    VStack(spacing: 8) {
                        Text("Press a key combination...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        HotkeyRecorderView(
                            onRecorded: { keyCode, modifiers in
                                settings.hotkeyKeyCode = Int(keyCode)
                                settings.hotkeyModifiers = Int(modifiers)
                                isRecording = false
                            },
                            onCancel: { isRecording = false }
                        )
                        .frame(height: 40)
                    }
                    .padding(8)
                }
            }

            Divider()

            Text("Hold the configured key to start recording, release to transcribe.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Advanced Tab

struct AdvancedSettingsView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Play sound on start/stop", isOn: $settings.soundFeedback)
            }

            Section("Debug") {
                Toggle("Enable debug logging", isOn: $settings.debugLogging)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
