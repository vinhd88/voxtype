import Combine
import SwiftUI

@main
struct VoxTypeApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var appController: AppController

    init() {
        let store = SettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        _appController = StateObject(wrappedValue: AppController(settings: store))
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(settingsStore)
        }

        Window("Welcome to VoxType", id: "onboarding") {
            if let controller = appController.onboardingController {
                OnboardingView(controller: controller)
                    .environmentObject(settingsStore)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// Root controller that wires up all services and manages app lifecycle.
@MainActor
final class AppController: ObservableObject {
    private let settings: SettingsStore
    private let audioService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let textService = TextInsertionService()
    private(set) var hotkeyManager: HotkeyManager!
    private(set) var dictationManager: DictationManager!
    private(set) var onboardingController: OnboardingController?
    private let menuBarController: MenuBarController
    private let hudController = HUDController()

    init(settings: SettingsStore) {
        self.settings = settings
        self.menuBarController = MenuBarController(transcriptionService: transcriptionService)

        let hotkey = HotkeyManager(settings: settings)
        self.hotkeyManager = hotkey
        self.dictationManager = DictationManager(
            audioService: audioService,
            transcriptionService: transcriptionService,
            textService: textService,
            hotkeyManager: hotkey
        )

        // Prompt for accessibility if not granted (shows system dialog)
        if !hotkey.hasAccessibility {
            hotkey.requestAccessibility()
        }

        // Show onboarding on first launch
        if !settings.hasCompletedOnboarding {
            onboardingController = OnboardingController(
                settings: settings,
                audioService: audioService,
                transcriptionService: transcriptionService
            )
        }

        wireUI()

        // Kick off model preparation in background
        Task {
            await transcriptionService.prepareModel()
        }
    }

    private func wireUI() {
        // Observe dictation state for menu bar icon + HUD
        dictationManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.menuBarController.updateIcon(for: state)
                self?.hudController.show(state: state, audioLevel: self?.dictationManager.audioLevel ?? 0)
            }
            .store(in: &cancellables)

        dictationManager.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.dictationManager.state == .listening else { return }
                self.hudController.updateAudioLevel(level)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
