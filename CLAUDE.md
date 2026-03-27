# Brownie - Meditation & Emotion App

## Overview
iOS app built with SwiftUI combining guided meditation playback with emotion tracking and reflective journaling. Uses a custom text-based meditation script format that gets parsed into timed steps (speech, pauses, countdowns). Supports iCloud sync and background audio playback.

## Build & Run
- Open `MeditationApp.xcodeproj` in Xcode
- Target: iOS (iPhone/iPad)
- Requires: Xcode 15+, iOS 17+
- Build: `xcodebuild -project MeditationApp.xcodeproj -scheme MeditationApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'`

## Adding New Swift Files
New `.swift` files must be manually added to `MeditationApp.xcodeproj/project.pbxproj` in **four places**:
1. **PBXBuildFile section** — `{isa = PBXBuildFile; fileRef = ...}`
2. **PBXFileReference section** — `{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ...; sourceTree = "<group>"; }`
3. **PBXGroup children** — add the file ref ID to the `MeditationApp` group's children list
4. **PBXSourcesBuildPhase files** — add the build file ID to the Sources phase

IDs follow a sequential pattern: build file IDs start with `A1000012...`, file ref IDs start with `A2000012...`, incrementing the last hex digits.

## Architecture

### Meditation
- **MeditationApp.swift** - App entry point, `SidebarDestination` enum, `ContentView` with `NavigationSplitView`
- **MeditationModels.swift** - Core types: Pool, Gender, PronounResolver, MeditationStep, Meditation
- **MeditationParser.swift** - Parses meditation script text into Meditation steps
- **MeditationPlayer.swift** - AVSpeechSynthesizer-based playback engine (`@EnvironmentObject`)
- **AudioRenderer.swift** - Audio rendering support
- **StreamingPlayer.swift** - Streaming playback support
- **MeditationListView.swift** - Main list of meditations with FAB for new meditation
- **MeditationEditorView.swift** - Editor for meditation scripts (presented as sheet)
- **MedTextEditor.swift** - Custom text editor component (UITextViewRepresentable)
- **SettingsView.swift** - App settings (voice selection, speaking rate, iCloud)
- **SampleMeditations.swift** - Built-in sample meditation scripts
- **FileManager+Meditations.swift** - File persistence and iCloud migration

### Emotion Tracking
- **EmotionModels.swift** - `Emotion` struct (name, emoji, question, category), `JournalEntry`, static lists of ~45 emotions
- **EmotionStore.swift** - `@Observable` class managing session emotion counts and persisted journal entries (JSON in Documents)
- **CheckInView.swift** - Emotion selection grid with tap-to-increment counts; emotions sort by count
- **ReflectionView.swift** - Single-emotion reflection form (pushed from JournalView)
- **JournalView.swift** - Combined reflection picker (for selected emotions) + past journal entries list with share/export

## Navigation
- Uses `NavigationSplitView` for sidebar
- `SidebarDestination` enum in MeditationApp.swift defines all sidebar items: Meditations, Check In, Journal, Settings
- To add a new sidebar item: add a case to `SidebarDestination` (with label + icon), handle it in the detail `switch` in `ContentView`
- `MeditationEditorView` is presented as a `.sheet` from `MeditationListView`
- `JournalView` uses an inner `NavigationStack` with `.navigationDestination(for: Emotion.self)` to push `ReflectionView`

## Key Patterns
- `@EnvironmentObject` for sharing `MeditationPlayer` across views
- `@Observable` + `.environment()` for sharing `EmotionStore` across views
- Meditation scripts are plain text `.med` files stored in Documents/Meditations (or iCloud container)
- Journal entries are persisted as JSON in Documents/emotion_journal.json
- The parser converts script text → [MeditationStep] for the player
