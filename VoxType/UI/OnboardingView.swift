import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: OnboardingController
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 20) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { step in
                    Circle()
                        .fill(step <= controller.step ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            // Step content
            Group {
                switch controller.step {
                case 1: welcomeStep
                case 2: micStep
                case 3: accessibilityStep
                case 4: modelStep
                case 5: tryItStep
                default: welcomeStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Navigation
            HStack {
                if controller.step > 1 {
                    Button("Back") { controller.back() }
                }
                Spacer()
                Button(controller.step == 5 ? "Get Started" : "Next") {
                    controller.next()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.canProceed)
            }
        }
        .frame(width: 520, height: 420)
        .padding(24)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome to VoxType")
                .font(.title)
                .fontWeight(.bold)
            Text("VoxType lets you dictate text anywhere on your Mac. Hold a hotkey, speak, and your words appear at the cursor.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Microphone

    private var micStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Microphone Access")
                .font(.title2)
                .fontWeight(.bold)
            Text("VoxType needs access to your microphone for speech recognition.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack {
                permissionBadge(controller.micPermission)
                Spacer()
                if controller.micPermission != .authorized {
                    Button("Grant Access") { controller.requestMicPermission() }
                }
            }
        }
    }

    // MARK: - Step 3: Accessibility

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Accessibility Access")
                .font(.title2)
                .fontWeight(.bold)
            Text("VoxType needs accessibility to detect hotkeys and insert text into other apps.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack {
                permissionBadge(controller.accessibilityPermission)
                Spacer()
                if controller.accessibilityPermission != .authorized {
                    Button("Open System Settings") { controller.openAccessibilitySettings() }
                }
            }
            if controller.accessibilityPermission == .denied {
                Text("After granting, you may need to restart VoxType.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Step 4: Model Download

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a Speech Model")
                .font(.title2)
                .fontWeight(.bold)
            Text("Select the model that fits your needs. Larger models are more accurate.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Model selection cards
            HStack(spacing: 10) {
                ForEach(WhisperModel.catalog) { model in
                    ModelCardView(
                        model: model,
                        isSelected: controller.selectedModel == model,
                        isDownloaded: controller.modelStatus == .ready && controller.selectedModel == model
                    ) {
                        guard controller.modelStatus != .downloading && controller.modelStatus != .loading else { return }
                        controller.selectedModel = model
                    }
                }
            }

            // Download button + progress
            Group {
                switch controller.modelStatus {
                case .notLoaded:
                    Button("Download \(controller.selectedModel.displayName)") {
                        controller.downloadModel()
                    }
                    .buttonStyle(.borderedProminent)

                case .downloading, .loading:
                    DownloadProgressView(
                        progress: controller.downloadProgress,
                        status: controller.modelStatus
                    )

                case .ready:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(controller.selectedModel.displayName) is ready to go!")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }

                case .failed(let msg):
                    VStack(spacing: 8) {
                        DownloadProgressView(
                            progress: controller.downloadProgress,
                            status: controller.modelStatus
                        )
                        Button("Retry Download") {
                            controller.retryDownload()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    // MARK: - Step 5: Try It

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Try It Out")
                .font(.title2)
                .fontWeight(.bold)
            Text("Hold the **\(settings.hotkeyDisplayName)** key and say something. Your words will appear in any text field.")
                .font(.body)
                .foregroundStyle(.secondary)
            Text("You can change the hotkey later in Settings (Cmd+,).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func permissionBadge(_ state: PermissionState) -> some View {
        switch state {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .restricted:
            Label("Restricted", systemImage: "lock.fill")
                .foregroundStyle(.orange)
        case .notDetermined:
            Label("Not requested", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }
}
