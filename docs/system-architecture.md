# VoxType -- System Architecture

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
   ^              │       ^                   │          │
   │              │       │                   │          │
   │              │  silence auto-stop        │          │
   │              │       │                   │          │
   │              │       └── (calls stopDictation)      │
   │              │ error                    │ success  │
   │              v                          v          │
   │        ┌──────────┐             ┌──────────────┐   │
   │        │  error   │             │    done      │   │
   │        └────┬─────┘             └──────┬───────┘   │
   │             │                          │           │
   └─────────────┴──── 3s auto-reset ───────┘           │
   ┌─────────────────────────────────────────────────────┘
   │  keyDown during transcribing (interrupts, restarts)
   └── transitions to .error if model not ready or mic denied
```

**State transitions:**

| From | To | Trigger |
|---|---|---|
| idle | listening | Configured hotkey key down (guard: model ready, mic permission) |
| idle | error | Model not ready or mic permission denied |
| listening | transcribing | Hotkey key up |
| listening | transcribing | Silence detected (auto-stop, when enabled in Settings) |
| transcribing | listening | Hotkey key down (interrupts in-flight transcription) |
| transcribing | done | Transcription + insertion succeeded |
| transcribing | error | Transcription failed after retry, or empty result |
| done | idle | 3-second auto-reset via `Task.sleep` |
| error | idle | 3-second auto-reset via `Task.sleep` |

Invalid transitions are guarded: `startDictation` checks `state != .listening`, `stopDictation` checks `state == .listening`. Transcription can be interrupted by pressing the hotkey again.

## Service Responsibilities

### AppController (VoxTypeApp.swift)

Root coordinator. `@MainActor @ObservableObject`. Owns all service instances and wires UI bindings.

- Receives `SettingsStore` via init, creates all services
- Creates `HotkeyManager(settings:)` which reads configurable hotkey from UserDefaults
- Creates `OnboardingController` on first launch (when `hasCompletedOnboarding == false`)
- Binds `DictationManager.$state` to `MenuBarController.updateIcon` and `HUDController.show`
- Binds `DictationManager.$audioLevel` to `HUDController.updateAudioLevel`
- Calls `TranscriptionService.prepareModel()` on a background `Task` at launch
- Prompts for accessibility if not granted

### DictationManager (Features/DictationManager.swift)

State machine orchestrator. `@MainActor @ObservableObject`.

- Publishes `state: DictationState` and `audioLevel: Float`
- Subscribes to `HotkeyManager.keyPressed` / `keyReleased` via Combine
- Subscribes to `AudioCaptureService.silenceDetected` (auto-stop when enabled in Settings)
- `startDictation()`: validates preconditions, can interrupt in-flight transcription, starts audio capture, transitions to `.listening`
- `stopDictation()`: stops capture, skips if audio < 0.3s (accidental tap), transitions to `.transcribing`, spawns async transcription
- `transcribeAndInsert(_:retryCount:)`: calls TranscriptionService, then TextInsertionService, logs latency. Retries once with 200ms backoff on failure.
- `scheduleReset()`: cancels previous reset, creates new 3-second Task to return to `.idle`

### AudioCaptureService (Services/AudioCaptureService.swift)

Microphone capture and format conversion. `ObservableObject` (not @MainActor -- audio runs on own queue).

- Uses `AVAudioEngine` with tap on input node bus 0
- Converts hardware format to 16kHz mono Float32 via `AVAudioConverter`
- Calculates RMS audio level on each buffer, publishes to `@Published audioLevel`
- RMS-based silence detection: counts consecutive frames below threshold (0.02). Fires `silenceDetected` PassthroughSubject when limit reached (configurable via `silenceTimeout` in UserDefaults, default 1.5s = 24000 frames at 16kHz)
- Buffers PCM frames on `bufferQueue` (serial DispatchQueue `com.voiceinput.audiobuffer`)
- `stopRecording()` merges all buffers into single `AVAudioPCMBuffer`
- `hasMicPermission` checks `AVCaptureDevice.authorizationStatus(for: .audio)` (was previously hardcoded to true)
- `requestMicPermission()` async wrapper around `AVCaptureDevice.requestAccess(for: .audio)`
- Uses inner `TapHandler` class (marked `@unchecked Sendable`) for the audio tap callback

### TranscriptionService (Services/TranscriptionService.swift)

WhisperKit model lifecycle and transcription. `@MainActor @ObservableObject`.

- Model: `openai_whisper-large-v3-turbo`, configured via `WhisperKitConfig`
- `prepareModel()`: creates `WhisperKit` instance, downloads model if needed
- `transcribe(_:)`: accepts `AVAudioPCMBuffer`, writes temp WAV file, calls `whisperKit.transcribe(audioPath:)`, cleans up temp file
- Publishes `modelStatus: ModelStatus` enum (notLoaded, downloading, loading, ready, failed)
- WAV writing: manual RIFF header construction, IEEE Float32 format (format tag 3)

### HotkeyManager (Services/HotkeyManager.swift)

Global hotkey detection via CGEvent tap. `ObservableObject`. Configurable key from SettingsStore.

- Target: configurable via UserDefaults (`hotkeyKeyCode`, `hotkeyModifiers`). Default: Right Option (keyCode 61, no modifiers).
- Supports modifier-only keys (Right Option, Caps Lock, etc.) and combo keys (Ctrl+Space, etc.)
- Observes `UserDefaults.didChangeNotification` to reinstall event tap when hotkey config changes
- Creates `CGEvent.tapCreate` with `.cgSessionEventTap`, `.listenOnly` mode
- Listens for `keyDown`, `keyUp`, `flagsChanged` events
- Handles `flagsChanged` for modifier-only keys (press/release detected via flag state)
- Emits `PassthroughSubject<Void, Never>` for keyPressed / keyReleased
- Re-enables tap if disabled by system timeout
- Falls back to 1s polling timer if accessibility not yet granted, auto-installs tap when granted
- Requires Accessibility permission (`AXIsProcessTrusted`)

### TextInsertionService (Services/TextInsertionService.swift)

Clipboard + simulated paste. Not @MainActor (pure AppKit/CoreGraphics calls).

- Saves previous clipboard content and changeCount
- Writes transcribed text to `NSPasteboard.general`
- Captures `changeCount` after writing as baseline
- 50ms delay, then simulates Cmd+V via `CGEvent` (virtual key 0x09 + .maskCommand)
- Schedules clipboard restoration after 500ms only if `changeCount` unchanged (prevents overwriting user copies)
- Returns `InsertionResult`: `.success`, `.clipboardOnly`, `.failed(String)`

### MenuBarController (App/MenuBarController.swift)

Status bar item. `@MainActor`. Updates icon based on `DictationState`.

- Menu items: model status (disabled info item from TranscriptionService.modelStatus), Settings (Cmd+,), About (version 1.0.0), Quit
- Weak reference to `TranscriptionService` for live model status display
- `rebuildMenu()` constructs full menu

### HUDController + HUDPanel + HUDContentView (UI/HUDView.swift)

Floating visual feedback.

- `HUDPanel`: NSPanel subclass, borderless, non-activating, `.floating` level, appears on all spaces
- `HUDState`: `@MainActor @Observable`, shared state injected into SwiftUI via `.environment()`
- `HUDController`: `@MainActor`, creates panel lazily, positions near menu bar center, updates HUDState for SwiftUI re-rendering
- `HUDContentView`: SwiftUI view with icon + label + audio level bar (listening) or result preview (done/error). Reads from `@Environment(HUDState.self)`.
- `AudioLevelBar`: red bar proportional to RMS level, minimum 2pt width

### SettingsStore (Services/SettingsStore.swift)

Settings persistence layer. `@MainActor @ObservableObject`. Uses `@AppStorage` (UserDefaults) for all values.

- General: `launchAtLogin` (uses SMAppService), `silenceDetectionEnabled`, `silenceTimeout` (0.5-3.0s)
- Hotkey: `hotkeyKeyCode`, `hotkeyModifiers`
- Advanced: `soundFeedback`, `debugLogging`
- Onboarding: `hasCompletedOnboarding`
- `hotkeyDisplayName`: computed property combining modifier symbols + key name

### SettingsView (UI/SettingsView.swift)

Settings window opened via Cmd+,. Three-tab TabView:

- **General**: Launch at Login toggle, silence detection toggle + timeout slider
- **Hotkey**: Current hotkey display, inline HotkeyRecorderView for recording new key
- **Advanced**: Sound feedback toggle, debug logging toggle

### HotkeyRecorderView (UI/HotkeyRecorderView.swift)

Key capture widget. `NSViewRepresentable` wrapping `RecorderNSView`.

- Uses NSEvent local monitors for `keyDown` and `flagsChanged`
- Modifier-only keys (Right Option, Caps Lock, etc.) detected via `flagsChanged` symmetric difference
- Combo keys (Ctrl+Space, etc.) detected via `keyDown` + modifier extraction
- Escape cancels recording
- System shortcuts (Cmd+Q, Cmd+W, Cmd+H, Cmd+M, Cmd+Tab) are blocked
- Callbacks: `onRecorded(CGKeyCode, UInt)`, `onCancel()`

### OnboardingController (App/OnboardingController.swift)

First-run flow controller. `@MainActor @ObservableObject`. 5-step flow.

- Published: `step`, `canProceed`, `micPermission`, `accessibilityPermission`, `modelStatus`
- Observes `TranscriptionService.$modelStatus` via Combine assign
- Mic permission: delegates to `AudioCaptureService.requestMicPermission()`
- Accessibility: opens system dialog via `AXIsProcessTrustedWithOptions`, polls at 1s until granted
- Sets `settings.hasCompletedOnboarding = true` on completion

### OnboardingView (UI/OnboardingView.swift)

First-run UI. 5-step wizard with dot indicator and Back/Next navigation.

1. Welcome -- app introduction
2. Microphone -- permission badge + grant button
3. Accessibility -- permission badge + system settings button, restart warning
4. Model Download -- live model status display
5. Try It -- usage instructions

## Data Flow

Complete sequence from hotkey press to text insertion:

```
User holds configured hotkey
         │
         v
  HotkeyManager          CGEvent tap detects target keyCode + modifiers
         │                keyDown, flagsChanged
         v
  DictationManager       startDictation()
         │                guard: model ready, mic permission
         │                (can interrupt in-flight transcription)
         v
  AudioCaptureService    startRecording()
         │                AVAudioEngine tap installed
         │                Hardware format -> 16kHz mono conversion
         │                Buffers accumulate on bufferQueue
         │                RMS level published -> HUD
         │
         ├── User releases hotkey ──> keyUp
         │
         └── OR silence detected ──> silenceDetected fires
              (RMS < 0.02 for 1.5s, configurable)
                            │
                            v
  DictationManager       stopDictation()
         │                stopRecording() -> merged AVAudioPCMBuffer
         │                skip if < 0.3s (accidental tap)
         v
  TranscriptionService   transcribe(audioBuffer)
         │                1. Write PCM -> temp WAV file (RIFF/IEEE Float32)
         │                2. whisperKit.transcribe(audioPath: wavPath)
         │                3. Delete temp WAV
         │                4. Return trimmed text
         │                (on failure: retry once with 200ms backoff)
         v
  TextInsertionService   insertText(text)
         │                1. Save previous clipboard
         │                2. Write text to NSPasteboard
         │                3. Capture changeCount as baseline
         │                4. 50ms delay
         │                5. Simulate Cmd+V via CGEvent
         │                6. Schedule clipboard restore (500ms, only if changeCount unchanged)
         v
  DictationManager       state = .done(text)
         │                Latency logged: transcription + insertion + total
         v
  Auto-reset             3 seconds -> state = .idle
```

## Threading Model

| Component | Thread Context | Notes |
|---|---|---|
| AppController | @MainActor | UI lifecycle, service wiring |
| DictationManager | @MainActor | State machine, UI bindings |
| TranscriptionService | @MainActor | WhisperKit async calls |
| SettingsStore | @MainActor | @AppStorage reads/writes |
| OnboardingController | @MainActor | UI state management |
| AudioCaptureService | Main + bufferQueue | Audio tap callback on bufferQueue, @Published updates on main |
| HotkeyManager | CFRunLoop (main) | CGEvent tap callback |
| TextInsertionService | Caller's context | async Task from DictationManager |
| HUDController | @MainActor | NSPanel management |
| HUDState | @MainActor | @Observable for SwiftUI |
| TapHandler (inner) | Audio tap thread | @unchecked Sendable, access via bufferQueue |

## Build Configuration

Defined in `project.yml`, processed by XcodeGen:

- `SWIFT_VERSION: "5.0"`
- `SWIFT_STRICT_CONCURRENCY: minimal`
- `SWIFT_OPTIMIZATION_LEVEL: "-Onone"` (debug)
- `LSUIElement: true` (no Dock icon)
- `com.apple.security.device.audio-input: true` (entitlement)
- Deployment target: macOS 14.0
