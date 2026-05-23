# VoxType -- Product Development Requirements

**Last updated:** 2026-05-22
**Version:** 1.0.0

---

## Product Summary

Open-source macOS voice dictation app. Hold a configurable hotkey to record, release to transcribe on-device via WhisperKit, text is pasted into the active application automatically. Lives in the menu bar, no Dock icon. Includes settings UI, first-run onboarding, silence detection, and launch-at-login support.

## Target Platform

| Requirement | Value |
|---|---|
| OS | macOS 14.0+ (Sonoma) |
| Architecture | Apple Silicon (ARM64) |
| Xcode | 16.0+ |
| Build system | XcodeGen (`project.yml`) |

## Key Features

1. **Configurable push-to-talk hotkey** -- Hold a key to start recording, release to stop. Configurable via Settings (Cmd+,). Supports modifier-only keys (Right Option, Caps Lock, etc.) and combo keys (Ctrl+Space, etc.). Uses CGEvent tap for reliable key-down/key-up detection at the system level.
2. **On-device transcription** -- WhisperKit `whisper-large-v3-turbo` model runs locally. No audio data leaves the machine. Transcription retry (1 retry with 200ms backoff) on failure.
3. **Automatic text insertion** -- Transcribed text is written to clipboard and Cmd+V is simulated. Previous clipboard content is restored after 500ms (with changeCount guard to avoid overwriting user copies).
4. **RMS-based silence detection** -- Auto-stop recording after configurable silence period (default 1.5s). Enabled/disabled via Settings.
5. **Floating HUD** -- NSPanel near the menu bar shows state (listening, transcribing, done, error) and real-time audio level meter.
6. **Menu bar presence** -- Status bar icon changes per state. Menu includes model status indicator, Settings, About, and Quit. LSUIElement=true hides Dock icon.
7. **Settings window** -- Cmd+, opens tabbed Settings (General, Hotkey, Advanced). Backed by `SettingsStore` using `@AppStorage` (UserDefaults).
8. **Custom hotkey recorder** -- NSEvent-based recorder captures modifier-only and combo keys. Escape cancels, system shortcuts (Cmd+Q, etc.) are blocked.
9. **First-run onboarding** -- 5-step flow: Welcome, Microphone permission, Accessibility permission, Model download status, Try It. Skips on subsequent launches.
10. **Launch at login** -- Optional, via SMAppService. Toggle in Settings > General.

## Architecture Overview

Seven services/components with clear single responsibilities, orchestrated by `DictationManager`:

| Service | Responsibility |
|---|---|
| `AudioCaptureService` | Mic capture, hardware-to-16kHz conversion, RMS audio level, silence detection |
| `TranscriptionService` | WhisperKit model lifecycle, PCM-to-WAV, transcription |
| `HotkeyManager` | CGEvent tap for global configurable hold-to-talk, reacts to SettingsStore changes |
| `TextInsertionService` | Clipboard write + simulated Cmd+V paste, changeCount-based restoration |
| `SettingsStore` | @AppStorage-backed settings (hotkey, silence, launch-at-login, onboarding state) |
| `DictationManager` | State machine, wires hotkey events + silence detection to service calls |
| `OnboardingController` | 5-step first-run flow, permission checks, model status observation |

`AppController` (entry point) instantiates all services and binds UI observers. `SettingsStore` is injected into `AppController`, `HotkeyManager`, and `OnboardingController`.

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 5.0 |
| UI framework | SwiftUI (HUD, Settings, Onboarding), AppKit (NSPanel, NSStatusItem) |
| Speech-to-text | WhisperKit (resolved: 0.18.0, minimum declared: 0.15.0) |
| Audio | AVFoundation (AVAudioEngine) |
| Hotkey | CoreGraphics CGEvent tap |
| Paste simulation | CoreGraphics CGEvent |
| Settings persistence | @AppStorage (UserDefaults) |
| Launch at login | ServiceManagement (SMAppService) |
| Concurrency | Swift Concurrency (async/await, Task, @MainActor) |
| Reactive bindings | Combine (PassthroughSubject, @Published, sink), @Observable (HUD) |
| Build config | XcodeGen from `project.yml` |

## External Dependencies

| Package | Version | Purpose |
|---|---|---|
| WhisperKit | >= 0.15.0 (resolved 0.18.0) | On-device speech-to-text |

Transitive dependencies (via WhisperKit): swift-argument-parser, swift-asn1, swift-collections, swift-crypto, swift-jinja, swift-transformers, yyjson.

## Build Instructions

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project from project.yml
cd /path/to/voice-input-ai
xcodegen generate

# Open and run
open VoxType.xcodeproj
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
- **Memory:** WhisperKit `whisper-large-v3-turbo` model loaded once on launch, retained for app lifetime.
- **Concurrency:** `SWIFT_STRICT_CONCURRENCY: minimal`. `@MainActor` on UI-bound classes (`DictationManager`, `TranscriptionService`, `AppController`, `HUDController`, `SettingsStore`, `OnboardingController`). Audio buffer processing on dedicated `DispatchQueue`.
- **Resilience:** Transcription retry (1 retry with 200ms backoff). Clipboard restoration uses `changeCount` guard. Dictation can interrupt in-flight transcription.

## Known Limitations

- Model download occurs on first launch (whisper-large-v3-turbo is ~1.5GB).
- Onboarding accessibility step polls at 1s intervals rather than using system callback.
- Sound feedback and debug logging settings exist in UI but are not yet wired to behavior.

## Out of Scope (future)

- Multiple language support selection
- Transcription history / log
- Multiple model selection
- Voice activity detection (beyond RMS silence threshold)
- Cloud-based transcription fallback
