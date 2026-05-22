# Voice Input -- Product Development Requirements

**Last updated:** 2026-05-22
**Version:** 0.1.0 (POC)

---

## Product Summary

Open-source macOS voice dictation app. Hold Right Option key to record, release to transcribe on-device via WhisperKit, text is pasted into the active application automatically. Lives in the menu bar, no Dock icon.

## Target Platform

| Requirement | Value |
|---|---|
| OS | macOS 14.0+ (Sonoma) |
| Architecture | Apple Silicon (ARM64) |
| Xcode | 16.0+ |
| Build system | XcodeGen (`project.yml`) |

## Key Features

1. **Push-to-talk hotkey** -- Hold Right Option key to start recording, release to stop. Uses CGEvent tap for reliable key-down/key-up detection at the system level.
2. **On-device transcription** -- WhisperKit `large-v3-turbo` model runs locally. No audio data leaves the machine.
3. **Automatic text insertion** -- Transcribed text is written to clipboard and Cmd+V is simulated. Previous clipboard content is restored after 500ms.
4. **Floating HUD** -- NSPanel near the menu bar shows state (listening, transcribing, done, error) and real-time audio level meter.
5. **Menu bar presence** -- Status bar icon changes per state. LSUIElement=true hides Dock icon.

## Architecture Overview

Five services with clear single responsibilities, orchestrated by `DictationManager`:

| Service | Responsibility |
|---|---|
| `AudioCaptureService` | Mic capture, hardware-to-16kHz conversion, RMS audio level |
| `TranscriptionService` | WhisperKit model lifecycle, PCM-to-WAV, transcription |
| `HotkeyManager` | CGEvent tap for global Right Option hold-to-talk |
| `TextInsertionService` | Clipboard write + simulated Cmd+V paste |
| `DictationManager` | State machine, wires hotkey events to service calls |

`AppController` (entry point) instantiates all services and binds UI observers.

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 5.0 |
| UI framework | SwiftUI (HUD), AppKit (NSPanel, NSStatusItem) |
| Speech-to-text | WhisperKit (resolved: 0.18.0, minimum declared: 0.15.0) |
| Audio | AVFoundation (AVAudioEngine) |
| Hotkey | CoreGraphics CGEvent tap |
| Paste simulation | CoreGraphics CGEvent |
| Concurrency | Swift Concurrency (async/await, Task, @MainActor) |
| Reactive bindings | Combine (PassthroughSubject, @Published, sink) |
| Build config | XcodeGen from `project.yml` |

## External Dependencies

| Package | Version | Purpose |
|---|---|---|
| WhisperKit | >= 0.15.0 (resolved 0.18.0) | On-device speech-to-text |
| HotKey | >= 0.2.1 | Declared in project.yml (note: code uses custom CGEvent tap instead) |

Transitive dependencies (via WhisperKit): swift-argument-parser, swift-asn1, swift-collections, swift-crypto, swift-jinja, swift-transformers, yyjson.

## Build Instructions

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project from project.yml
cd /path/to/voice-input-ai
xcodegen generate

# Open and run
open VoiceInput.xcodeproj
```

## Permissions Required

| Permission | Purpose |
|---|---|
| Microphone (`NSMicrophoneUsageDescription`) | Audio capture for dictation |
| Accessibility (AXIsProcessTrusted) | Global hotkey detection + Cmd+V simulation |
| Audio input entitlement | Hardened runtime audio access |

## Non-functional Requirements

- **Latency:** Transcription + insertion logged via `ContinuousClock` in `DictationManager.transcribeAndInsert`.
- **Privacy:** All processing on-device. No network calls. Temp WAV file deleted after transcription.
- **Memory:** WhisperKit `large-v3-turbo` model loaded once on launch, retained for app lifetime.
- **Concurrency:** `SWIFT_STRICT_CONCURRENCY: minimal`. `@MainActor` on UI-bound classes (`DictationManager`, `TranscriptionService`, `AppController`, `HUDController`). Audio buffer processing on dedicated `DispatchQueue`.

## Known Limitations (POC)

- Model download occurs on first launch (large-v3-turbo is ~1.5GB).
- No settings UI -- hotkey is hardcoded to Right Option.
- Clipboard restoration is best-effort, race condition possible if user copies during insertion.
- `hasMicPermission` always returns `true` (macOS permission check not yet implemented).
- No error retry mechanism beyond the 3-second auto-reset.

## Out of Scope (for POC)

- Custom hotkey configuration
- Multiple language support selection
- Transcription history / log
- Settings window
- Auto-detect silence / voice activity detection
- Multiple model selection
