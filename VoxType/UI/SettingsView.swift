import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            HotkeySettingsView()
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            ModelSettingsView()
                .tabItem { Label("Model", systemImage: "waveform") }
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

// MARK: - Model Tab

struct ModelSettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var transcriptionService: TranscriptionService
    @State private var switchingModel: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Current model status
            GroupBox("Current Model") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WhisperModel.find(byId: transcriptionService.currentModelId)?.displayName ?? transcriptionService.currentModelId)
                            .font(.headline)
                        modelStatusLabel
                    }
                    Spacer()
                }
                .padding(4)
            }

            // Available models
            GroupBox("Available Models") {
                VStack(spacing: 8) {
                    ForEach(WhisperModel.catalog) { model in
                        modelRow(model)
                    }
                }
                .padding(4)
            }

            // Progress during download
            if case .downloading = transcriptionService.modelStatus {
                DownloadProgressView(
                    progress: transcriptionService.downloadProgress,
                    status: transcriptionService.modelStatus
                )
            }

            Spacer()

            Text("Switching models requires downloading. The current model stays active until the new one is ready.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    @ViewBuilder
    private var modelStatusLabel: some View {
        switch transcriptionService.modelStatus {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .downloading:
            Label("Downloading \(Int(transcriptionService.downloadProgress * 100))%", systemImage: "arrow.down.circle")
                .foregroundStyle(Color.accentColor)
                .font(.caption)
        case .loading:
            Label("Preparing...", systemImage: "gear")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .notLoaded:
            Label("Not downloaded", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperModel) -> some View {
        let isActive = transcriptionService.currentModelId == model.id && transcriptionService.modelStatus == .ready
        let isCurrent = transcriptionService.currentModelId == model.id

        HStack {
            Image(systemName: model.iconName)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.body)
                Text("\(model.sizeLabel) — \(model.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if isCurrent && (transcriptionService.modelStatus == .downloading || transcriptionService.modelStatus == .loading) {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Switch") {
                    switchTo(model)
                }
                .disabled(transcriptionService.modelStatus == .downloading || transcriptionService.modelStatus == .loading)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func switchTo(_ model: WhisperModel) {
        settings.selectedModel = model.id
        Task {
            await transcriptionService.prepareModel(named: model.id)
        }
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
