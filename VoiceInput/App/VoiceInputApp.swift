import Combine
import SwiftUI

@main
struct VoiceInputApp: App {
    @StateObject private var appController = AppController()

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Root controller that wires up all services and manages app lifecycle.
@MainActor
final class AppController: ObservableObject {
    private let audioService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let textService = TextInsertionService()
    private(set) var hotkeyManager: HotkeyManager!
    private(set) var dictationManager: DictationManager!
    private let menuBarController = MenuBarController()
    private let hudController = HUDController()

    init() {
        let hotkey = HotkeyManager()
        self.hotkeyManager = hotkey
        self.dictationManager = DictationManager(
            audioService: audioService,
            transcriptionService: transcriptionService,
            textService: textService,
            hotkeyManager: hotkey
        )

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
