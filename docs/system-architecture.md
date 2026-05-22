# Voice Input -- System Architecture

**Last updated:** 2026-05-22

---

## State Machine

The core workflow is a strict state machine managed by `DictationManager`. States are defined in `DictationState` enum.

```
                    ┌─────────────────────────────────────┐
                    │             keyDown                  │
                    v                                     │
┌───────┐    ┌────────────┐    keyUp    ┌───────────────┐ │
│ idle  │───>│ listening  │───────────>│ transcribing  │ │
└──┬────┘    └─────┬──────┘            └──────┬────────┘ │
   ^              │                          │          │
   │              │ error                    │ success  │
   │              v                          v          │
   │        ┌──────────┐             ┌──────────────┐   │
   │        │  error   │             │    done      │   │
   │        └────┬─────┘             └──────┬───────┘   │
   │             │                          │           │
   └─────────────┴──── 3s auto-reset ───────┘           │
   ┌─────────────────────────────────────────────────────┘
   │  (guard: state == .idle on startDictation)
   └── transitions to .error if model not ready or mic denied
```

**State transitions:**

| From | To | Trigger |
|---|---|---|
| idle | listening | Right Option key down (guard: model ready, mic permission) |
| idle | error | Model not ready or mic permission denied |
| listening | transcribing | Right Option key up |
| transcribing | done | Transcription + insertion succeeded |
| transcribing | error | Transcription failed or empty result |
| done | idle | 3-second auto-reset via `Task.sleep` |
| error | idle | 3-second auto-reset via `Task.sleep` |

Invalid transitions are guarded: `startDictation` checks `state == .idle`, `stopDictation` checks `state == .listening`.

## Service Responsibilities

### AppController (VoiceInputApp.swift)

Root coordinator. `@MainActor @ObservableObject`. Owns all service instances and wires UI bindings.

- Creates all five services in `init`
- Binds `DictationManager.$state` to `MenuBarController.updateIcon` and `HUDController.show`
- Binds `DictationManager.$audioLevel` to `HUDController.updateAudioLevel`
- Calls `TranscriptionService.prepareModel()` on a background `Task` at launch

### DictationManager (Features/DictationManager.swift)

State machine orchestrator. `@MainActor @ObservableObject`.

- Publishes `state: DictationState` and `audioLevel: Float`
- Subscribes to `HotkeyManager.keyPressed` / `keyReleased` via Combine
- `startDictation()`: validates preconditions, starts audio capture, transitions to `.listening`
- `stopDictation()`: stops capture, transitions to `.transcribing`, spawns async transcription
- `transcribeAndInsert(_:)`: calls TranscriptionService, then TextInsertionService, logs latency
- `scheduleReset()`: cancels previous reset, creates new 3-second Task to return to `.idle`

### AudioCaptureService (Services/AudioCaptureService.swift)

Microphone capture and format conversion. `ObservableObject` (not @MainActor -- audio runs on own queue).

- Uses `AVAudioEngine` with tap on input node bus 0
- Converts hardware format to 16kHz mono Float32 via `AVAudioConverter`
- Calculates RMS audio level on each buffer, publishes to `@Published audioLevel`
- Buffers PCM frames on `bufferQueue` (serial DispatchQueue `com.voiceinput.audiobuffer`)
- `stopRecording()` merges all buffers into single `AVAudioPCMBuffer`
- Uses inner `TapHandler` class (marked `@unchecked Sendable`) for the audio tap callback

### TranscriptionService (Services/TranscriptionService.swift)

WhisperKit model lifecycle and transcription. `@MainActor @ObservableObject`.

- Model: `large-v3-turbo`, configured via `WhisperKitConfig`
- `prepareModel()`: creates `WhisperKit` instance, downloads model if needed
- `transcribe(_:)`: accepts `AVAudioPCMBuffer`, writes temp WAV file, calls `whisperKit.transcribe(audioPath:)`, cleans up temp file
- Publishes `modelStatus: ModelStatus` enum (notLoaded, downloading, loading, ready, failed)
- WAV writing: manual RIFF header construction, IEEE Float32 format (format tag 3)

### HotkeyManager (Services/HotkeyManager.swift)

Global hotkey detection via CGEvent tap. `ObservableObject`.

- Target: Right Option key (keyCode 61)
- Creates `CGEvent.tapCreate` with `.cgSessionEventTap`, `.listenOnly` mode
- Listens for `keyDown`, `keyUp`, `flagsChanged` events
- Emits `PassthroughSubject<Void, Never>` for keyPressed / keyReleased
- Re-enables tap if disabled by system timeout
- Requires Accessibility permission (`AXIsProcessTrusted`)

### TextInsertionService (Services/TextInsertionService.swift)

Clipboard + simulated paste. Not @MainActor (pure AppKit/CoreGraphics calls).

- Saves previous clipboard content and changeCount
- Writes transcribed text to `NSPasteboard.general`
- 50ms delay, then simulates Cmd+V via `CGEvent` (virtual key 0x09 + .maskCommand)
- Schedules clipboard restoration after 500ms (skips if clipboard changed by user)
- Returns `InsertionResult`: `.success`, `.clipboardOnly`, `.failed(String)`

### MenuBarController (App/MenuBarController.swift)

Status bar item. Updates icon based on `DictationState`.

### HUDController + HUDPanel + HUDContentView (UI/HUDView.swift)

Floating visual feedback.

- `HUDPanel`: NSPanel subclass, borderless, non-activating, `.floating` level, appears on all spaces
- `HUDController`: `@MainActor`, creates panel lazily, positions near menu bar center, re-renders SwiftUI content on state/level changes
- `HUDContentView`: SwiftUI view with icon + label + audio level bar (listening) or result preview (done/error)
- `AudioLevelBar`: red bar proportional to RMS level, minimum 2pt width

## Data Flow

Complete sequence from hotkey press to text insertion:

```
User holds Right Option
         │
         v
  HotkeyManager          CGEvent tap detects keyCode 61
         │                keyDown, flagsChanged
         v
  DictationManager       startDictation()
         │                guard: idle, model ready, mic permission
         v
  AudioCaptureService    startRecording()
         │                AVAudioEngine tap installed
         │                Hardware format -> 16kHz mono conversion
         │                Buffers accumulate on bufferQueue
         │                RMS level published -> HUD
         v
  User releases Right Option
         │
         v
  HotkeyManager          keyUp detected
         v
  DictationManager       stopDictation()
         │                stopRecording() -> merged AVAudioPCMBuffer
         v
  TranscriptionService   transcribe(audioBuffer)
         │                1. Write PCM -> temp WAV file (RIFF/IEEE Float32)
         │                2. whisperKit.transcribe(audioPath: wavPath)
         │                3. Delete temp WAV
         │                4. Return trimmed text
         v
  TextInsertionService   insertText(text)
         │                1. Save previous clipboard
         │                2. Write text to NSPasteboard
         │                3. 50ms delay
         │                4. Simulate Cmd+V via CGEvent
         │                5. Schedule clipboard restore (500ms)
         v
  DictationManager       state = .done(text)
         │                Latency logged: transcription + insertion + total
         v
  Auto-reset             3 seconds -> state = .idle
```

## Threading Model

| Component | Thread Context | Notes |
|---|---|---|
| AppController | @MainActor | UI lifecycle |
| DictationManager | @MainActor | State machine, UI bindings |
| TranscriptionService | @MainActor | WhisperKit async calls |
| AudioCaptureService | Main + bufferQueue | Audio tap callback on bufferQueue, @Published updates on main |
| HotkeyManager | CFRunLoop (main) | CGEvent tap callback |
| TextInsertionService | Caller's context | async Task from DictationManager |
| HUDController | @MainActor | NSPanel management |
| TapHandler (inner) | Audio tap thread | @unchecked Sendable, access via bufferQueue |

## Build Configuration

Defined in `project.yml`, processed by XcodeGen:

- `SWIFT_VERSION: "5.0"`
- `SWIFT_STRICT_CONCURRENCY: minimal`
- `SWIFT_OPTIMIZATION_LEVEL: "-Onone"` (debug)
- `LSUIElement: true` (no Dock icon)
- `com.apple.security.device.audio-input: true` (entitlement)
- Deployment target: macOS 14.0
