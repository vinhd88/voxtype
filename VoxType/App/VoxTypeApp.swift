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
                .environmentObject(appController.transcriptionService)
        }
        .windowResizability(.contentSize)

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
    private(set) var transcriptionService = TranscriptionService()

    /// Whether the app is running under XCTest.
    static let isRunningTests: Bool = {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.arguments.contains("-XCTest")
            || NSClassFromString("XCTestCase") != nil
    }()
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

        // Prompt for accessibility if not granted (skip during tests)
        if !hotkey.hasAccessibility && !Self.isRunningTests {
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

        // Auto-load model only if onboarding already completed
        // (first launch: onboarding controls model download)
        if settings.hasCompletedOnboarding {
            Task {
                await transcriptionService.prepareModel(named: settings.selectedModel)
            }
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

        // Rebuild menu when model status or download progress changes
        transcriptionService.$modelStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.menuBarController.rebuildMenu()
                // Update icon when idle — model status affects idle icon
                if self?.dictationManager.state == .idle {
                    self?.menuBarController.updateIcon(for: .idle)
                }
            }
            .store(in: &cancellables)

        transcriptionService.$downloadProgress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.menuBarController.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
