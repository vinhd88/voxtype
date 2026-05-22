# VoxType

A macOS menu bar app for voice-to-text dictation powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit). Hold the Right Option key to record, release to transcribe and paste — works system-wide in any text field.

## How It Works

1. **Hold** Right Option — recording starts, HUD appears near the menu bar
2. **Speak** — real-time audio level shown in the HUD
3. **Release** — audio is transcribed via WhisperKit and pasted into the active text field
4. Done — HUD shows the result briefly, then disappears

## Features

- **Hold-to-talk** — Right Option key activates recording system-wide via CGEvent tap
- **On-device transcription** — WhisperKit runs locally, no internet required
- **Auto-paste** — transcribed text is inserted via clipboard + Cmd+V simulation
- **Menu bar HUD** — floating overlay with recording status, audio level, and result preview
- **Status icon** — menu bar mic icon changes with state (idle, listening, transcribing, done, error)
- **LSUIElement** — no dock icon, lives entirely in the menu bar

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation
- Microphone access
- Accessibility permission (for global hotkey)

## Setup

```bash
# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open VoxType.xcodeproj
```

Build and run from Xcode (Cmd+R). On first launch, grant microphone and accessibility permissions when prompted.

## Project Structure

```
VoxType/
├── App/
│   ├── VoxTypeApp.swift          # @main entry point + AppController
│   └── MenuBarController.swift   # Status item with state-based icons
├── Features/
│   ├── DictationManager.swift    # State machine orchestrator
│   └── DictationState.swift      # State enum
├── Services/
│   ├── AudioCaptureService.swift # 16kHz mic capture with RMS levels
│   ├── TranscriptionService.swift# WhisperKit model management
│   ├── HotkeyManager.swift       # Global hotkey via CGEvent tap
│   └── TextInsertionService.swift# Clipboard paste simulation
├── UI/
│   └── HUDView.swift             # Floating HUD panel + audio level bar
└── Resources/
    ├── Info.plist
    └── VoxType.entitlements
```

## Architecture

All services are instantiated by `AppController` and injected into `DictationManager` via init parameters — no service locator, no singletons.

```
AppController
  ├── MenuBarController
  ├── HUDController
  └── DictationManager
        ├── AudioCaptureService
        ├── TranscriptionService → WhisperKit
        ├── TextInsertionService
        └── HotkeyManager
```

State propagation uses Combine (`@Published` + `PassthroughSubject`) with `@MainActor` isolation on UI-bound types.

## Testing

```bash
# Run tests from Xcode
Cmd+U

# Or via xcodebuild
xcodebuild test -project VoxType.xcodeproj -scheme VoxType -destination 'platform=macOS'
```

Unit tests cover `DictationManager` state transitions, `TranscriptionService`, `TextInsertionService`, and `DictationState` using mock services.

## License

Private — All rights reserved.
