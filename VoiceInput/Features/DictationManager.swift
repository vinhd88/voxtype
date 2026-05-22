import AVFoundation
import Combine
import Foundation

/// Orchestrates all services through a strict state machine.
@MainActor
final class DictationManager: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published var audioLevel: Float = 0.0

    private let audioService: AudioCaptureService
    private let transcriptionService: TranscriptionService
    private let textService: TextInsertionService
    private let hotkeyManager: HotkeyManager

    private var cancellables = Set<AnyCancellable>()
    private var resetTask: Task<Void, Never>?

    init(
        audioService: AudioCaptureService,
        transcriptionService: TranscriptionService,
        textService: TextInsertionService,
        hotkeyManager: HotkeyManager
    ) {
        self.audioService = audioService
        self.transcriptionService = transcriptionService
        self.textService = textService
        self.hotkeyManager = hotkeyManager

        bindHotkey()
    }

    private func bindHotkey() {
        hotkeyManager.keyPressed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.startDictation() }
            .store(in: &cancellables)

        hotkeyManager.keyReleased
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.stopDictation() }
            .store(in: &cancellables)
    }

    // MARK: - State Transitions

    private func startDictation() {
        guard state == .idle else { return }

        // Check transcription readiness
        guard transcriptionService.isReady else {
            state = .error(message: "Speech model not ready yet")
            scheduleReset()
            return
        }

        // Check mic permission
        guard audioService.hasMicPermission else {
            state = .error(message: "Microphone permission required")
            scheduleReset()
            Task { await audioService.requestMicPermission() }
            return
        }

        do {
            try audioService.startRecording()
            state = .listening
        } catch {
            state = .error(message: "Mic error: \(error.localizedDescription)")
            scheduleReset()
        }
    }

    private func stopDictation() {
        guard state == .listening else { return }

        let audioBuffer = audioService.stopRecording()

        // Skip transcription if no audio was captured (e.g. very brief key press)
        guard audioBuffer.frameLength > 0 else {
            state = .error(message: "No audio captured")
            scheduleReset()
            return
        }

        state = .transcribing

        Task {
            await transcribeAndInsert(audioBuffer)
        }
    }

    private func transcribeAndInsert(_ audio: AVAudioPCMBuffer) async {
        let t0 = ContinuousClock.now

        do {
            let text = try await transcriptionService.transcribe(audio)
            let t1 = ContinuousClock.now

            guard !text.isEmpty else {
                state = .error(message: "No speech detected")
                scheduleReset()
                return
            }

            let result = await textService.insertText(text)
            let t2 = ContinuousClock.now

            let transcriptionDuration = t0.duration(to: t1)
            let insertionDuration = t1.duration(to: t2)
            let totalDuration = t0.duration(to: t2)

            print("[Latency] Transcription: \(transcriptionDuration) | Insertion: \(insertionDuration) | Total: \(totalDuration)")

            switch result {
            case .success:
                state = .done(text: text)
            case .clipboardOnly:
                state = .done(text: "(Copied) \(text)")
            case .failed(let msg):
                state = .done(text: "(Copy failed: \(msg)) \(text)")
            }
        } catch {
            state = .error(message: "Transcription failed: \(error.localizedDescription)")
        }

        scheduleReset()
    }

    private func scheduleReset() {
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
            guard !Task.isCancelled else { return }
            self.state = .idle
        }
    }
}
