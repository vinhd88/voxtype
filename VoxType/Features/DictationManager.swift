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
    private var transcriptionTask: Task<Void, Never>?

    // Minimum frames to attempt transcription (0.3s at 16kHz)
    private let minFramesForTranscription: AVAudioFrameCount = 4800

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

        // Silence detection: auto-stop when user stops speaking
        audioService.silenceDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.state == .listening else { return }
                let enabled = UserDefaults.standard.bool(forKey: "silenceDetectionEnabled")
                guard enabled else { return }
                self.stopDictation()
            }
            .store(in: &cancellables)
    }

    // MARK: - State Transitions

    private func startDictation() {
        // Allow interrupting transcription — user wants to dictate something new
        if state == .transcribing {
            transcriptionTask?.cancel()
            transcriptionTask = nil
            // Ensure any in-flight recording is cleaned up
            if audioService.isCurrentlyRecording {
                _ = audioService.stopRecording()
            }
        }

        // Allow starting from any non-listening state
        guard state != .listening else { return }

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

        resetTask?.cancel()

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

        // Skip if audio too short — accidental tap, not intentional speech
        guard audioBuffer.frameLength >= minFramesForTranscription else {
            print("[Dictation] Audio too short (\(audioBuffer.frameLength) frames), skipping transcription")
            state = .idle
            return
        }

        state = .transcribing

        transcriptionTask = Task {
            await transcribeAndInsert(audioBuffer)
        }
    }

    private func transcribeAndInsert(_ audio: AVAudioPCMBuffer, retryCount: Int = 0) async {
        let t0 = ContinuousClock.now

        do {
            let text = try await transcriptionService.transcribe(audio)
            guard !Task.isCancelled else { return }
            let t1 = ContinuousClock.now

            guard !text.isEmpty else {
                state = .error(message: "No speech detected")
                scheduleReset()
                return
            }

            let result = await textService.insertText(text)
            guard !Task.isCancelled else { return }
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
            guard !Task.isCancelled else { return }

            if retryCount == 0 {
                print("[Dictation] Transcription failed, retrying... (\(error))")
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms backoff
                guard !Task.isCancelled else { return }
                await transcribeAndInsert(audio, retryCount: 1)
                return
            }

            state = .error(message: "Transcription failed. \(suggestedAction(for: error))")
        }

        scheduleReset()
    }

    private func suggestedAction(for error: Error) -> String {
        if let err = error as? TranscriptionError {
            switch err {
            case .modelNotReady: return "Wait for model to finish loading."
            case .invalidAudio: return "Try speaking louder or closer to the mic."
            case .emptyResult: return "No speech was detected. Try again."
            }
        }
        return "Try again or check your microphone."
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
