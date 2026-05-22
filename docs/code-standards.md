# Voice Input -- Code Standards

**Last updated:** 2026-05-22

---

## Language and Build

| Setting | Value |
|---|---|
| Language | Swift 5.0 |
| Deployment target | macOS 14.0 |
| Concurrency strictness | `SWIFT_STRICT_CONCURRENCY: minimal` |
| Build system | XcodeGen (`project.yml`) |
| Min XcodeGen version | 2.42 |
| Min Xcode version | 16.0 |

## External Dependencies

Only two direct dependencies declared in `project.yml`:

| Package | Constraint | Resolved |
|---|---|---|
| WhisperKit | >= 0.15.0 | 0.18.0 |
| HotKey | >= 0.2.1 | 0.2.1 |

No other external packages. Transitive deps (swift-collections, swift-crypto, etc.) come via WhisperKit.

## File Naming

| Context | Convention | Example |
|---|---|---|
| Swift source files | PascalCase | `DictationManager.swift`, `AudioCaptureService.swift` |
| Documentation files | kebab-case | `project-overview-pdr.md`, `system-architecture.md` |
| Build config | lowercase | `project.yml`, `Info.plist` |

## Concurrency Model

### @MainActor

Applied to classes that interact with UI or publish state observed by UI:

- `AppController` -- owns UI controllers, binds Combine pipelines
- `DictationManager` -- publishes `@Published` state consumed by UI
- `TranscriptionService` -- publishes `@Published modelStatus`, called from `@MainActor` context
- `HUDController` -- manages NSPanel

### DispatchQueue

- `AudioCaptureService.bufferQueue` -- serial queue `com.voiceinput.audiobuffer` for thread-safe PCM buffer accumulation. All reads/writes to `pcmBuffers` go through this queue.

### @unchecked Sendable

- `AudioCaptureService.TapHandler` -- inner class used as audio tap callback. Marked `@unchecked Sendable` because all shared state access is serialized through `bufferQueue` or main queue.

### Swift Concurrency (async/await)

- `TranscriptionService.prepareModel()` -- async model download/load
- `TranscriptionService.transcribe(_:)` -- async WhisperKit call
- `TextInsertionService.insertText(_:)` -- async for `Task.sleep` delays
- `DictationManager.transcribeAndInsert(_:)` -- async, called from `Task {}` block

## Reactive Programming (Combine)

Patterns used throughout:

| Pattern | Where |
|---|---|
| `@Published` properties | DictationManager.state, DictationManager.audioLevel, TranscriptionService.modelStatus, AudioCaptureService.audioLevel |
| `PassthroughSubject` | HotkeyManager.keyPressed, HotkeyManager.keyReleased |
| `.receive(on: DispatchQueue.main).sink` | AppController.wireUI (state -> menu bar icon + HUD) |
| `Set<AnyCancellable>` | Stored in AppController and DictationManager for subscription lifecycle |

## Error Handling

### Service-level errors

Each service defines its own error enum conforming to `LocalizedError`:

- `AudioError` -- `.formatError`, `.notRecording`
- `TranscriptionError` -- `.modelNotReady`, `.invalidAudio`, `.emptyResult`

### State machine errors

`DictationManager` transitions to `.error(message: String)` for:

- Model not ready (checked before recording starts)
- Mic permission denied
- Audio capture failure (caught from `startRecording() throw`)
- Transcription failure (caught from `transcribe() throw`)
- Empty transcription result

All error states auto-reset to `.idle` after 3 seconds.

### TextInsertionService results

Uses `InsertionResult` enum rather than throwing:

- `.success` -- Cmd+V simulated successfully
- `.clipboardOnly` -- Accessibility not granted, text in clipboard only
- `.failed(String)` -- CGEvent creation failed

## Code Organization

### Service isolation

Each service is a standalone class with a single responsibility. Services do not reference each other. All coordination happens in `DictationManager`.

### Init injection

Services are created in `AppController` and passed to `DictationManager` via init parameters. No singletons, no service locator, no DI framework.

### File structure within a service

1. Imports
2. Class declaration with stored properties
3. Init
4. Public API methods
5. Private helper methods
6. Supporting types (error enums)

### MARK comments

Methods are grouped with `// MARK: -` comments (e.g., `// MARK: - State Transitions`, `// MARK: - Private`, `// MARK: - WAV Writing`).

## UI Patterns

### NSPanel for HUD

- `HUDPanel` subclass of `NSPanel` with `.borderless`, `.nonactivatingPanel` style mask
- `.floating` window level, clear background, all-spaces collection behavior
- `canBecomeKey` and `canBecomeMain` return false

### SwiftUI in AppKit

- `NSHostingView` wraps `HUDContentView` for display inside `HUDPanel`
- Color scheme forced to dark via `.environment(\.colorScheme, .dark)`
- `@ViewBuilder` computed properties for conditional content

### Menu bar

- `NSStatusItem` with SF Symbols, updated reactively from `DictationState`
- Single "Quit" menu item

## Privacy and Security

- `LSUIElement: true` -- no Dock icon, menu bar only
- `com.apple.security.device.audio-input` entitlement for hardened runtime
- Accessibility permission required for hotkey and paste simulation
- Temp WAV files written to `FileManager.default.temporaryDirectory`, deleted in `defer` block
- No network requests. All processing on-device.

## Logging

- `print()` statements prefixed with `[ComponentName]`: `[AudioCapture]`, `[Transcription]`, `[Hotkey]`, `[Latency]`
- Latency measurement uses `ContinuousClock.now` for high-precision timing
- No structured logging framework (OSLog not used in POC)

## What Not To Do

- Do not add external dependencies beyond WhisperKit and HotKey without updating `project.yml` and this doc
- Do not bypass the state machine guards (always check `state == .idle` before starting, `state == .listening` before stopping)
- Do not access `pcmBuffers` outside of `bufferQueue.sync {}`
- Do not modify `VoiceInput.xcodeproj` directly -- regenerate with `xcodegen generate` after `project.yml` changes
- Do not add `@MainActor` to `AudioCaptureService` (audio tap runs on its own thread)
