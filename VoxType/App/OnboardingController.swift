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

/// Manages the 5-step first-run onboarding flow.
@MainActor
final class OnboardingController: ObservableObject {
    @Published var step = 1
    @Published var canProceed = true
    @Published var micPermission: PermissionState = .mic()
    @Published var accessibilityPermission: PermissionState = .accessibility()
    @Published var modelStatus: TranscriptionService.ModelStatus = .notLoaded

    private let settings: SettingsStore
    private let audioService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityPollTimer: Timer?

    init(settings: SettingsStore, audioService: AudioCaptureService, transcriptionService: TranscriptionService) {
        self.settings = settings
        self.audioService = audioService
        self.transcriptionService = transcriptionService

        // Observe model status
        transcriptionService.$modelStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$modelStatus)

        updateCanProceed()
    }

    func next() {
        if step == 5 {
            settings.hasCompletedOnboarding = true
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
        case 2: canProceed = true // Mic step always proceedable
        case 3: canProceed = true // Accessibility step always proceedable
        default: canProceed = true
        }
    }
}
