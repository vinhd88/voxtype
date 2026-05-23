import AVFoundation
import Combine
import SwiftUI

/// Permission state for mic and accessibility.
enum PermissionState {
    case notDetermined
    case authorized
    case denied
    case restricted

    static func mic() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notDetermined
        }
    }

    static func accessibility() -> PermissionState {
        AXIsProcessTrusted() ? .authorized : .denied
    }
}

/// Manages the first-run onboarding flow with model download.
@MainActor
final class OnboardingController: ObservableObject {
    @Published var step = 1
    @Published var canProceed = true
    @Published var micPermission: PermissionState = .mic()
    @Published var accessibilityPermission: PermissionState = .accessibility()
    @Published var modelStatus: TranscriptionService.ModelStatus = .notLoaded
    @Published var selectedModel: WhisperModel = WhisperModel.defaultModel
    @Published var downloadProgress: Double = 0.0

    private let settings: SettingsStore
    private let audioService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore, audioService: AudioCaptureService, transcriptionService: TranscriptionService) {
        self.settings = settings
        self.audioService = audioService
        self.transcriptionService = transcriptionService

        transcriptionService.$modelStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$modelStatus)

        transcriptionService.$downloadProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$downloadProgress)

        if let saved = WhisperModel.find(byId: settings.selectedModel) {
            selectedModel = saved
        }

        updateCanProceed()
    }

    func next() {
        if step == 5 {
            settings.hasCompletedOnboarding = true
            settings.selectedModel = selectedModel.id
        } else {
            step += 1
            updateCanProceed()
        }
    }

    func back() {
        guard step > 1 else { return }
        step -= 1
        updateCanProceed()
    }

    func requestMicPermission() {
        Task {
            _ = await audioService.requestMicPermission()
            micPermission = .mic()
            updateCanProceed()
        }
    }

    func openAccessibilitySettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        startAccessibilityPolling()
    }

    /// Start downloading the selected model.
    func downloadModel() {
        Task {
            await transcriptionService.prepareModel(named: selectedModel.id)
        }
    }

    /// Retry download after failure.
    func retryDownload() {
        downloadModel()
    }

    private func startAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let state = PermissionState.accessibility()
            if state != self.accessibilityPermission {
                self.accessibilityPermission = state
                self.updateCanProceed()
            }
            if state == .authorized {
                self.accessibilityPollTimer?.invalidate()
                self.accessibilityPollTimer = nil
            }
        }
    }

    private func updateCanProceed() {
        switch step {
        case 4: canProceed = modelStatus == .ready
        default: canProceed = true
        }
    }
}
