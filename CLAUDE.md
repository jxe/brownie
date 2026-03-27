# Brownie - Meditation App

## Overview
iOS meditation app built with SwiftUI. Uses a custom text-based meditation script format that gets parsed into timed steps (speech, pauses, countdowns). Supports iCloud sync and background audio playback.

## Build & Run
- Open `MeditationApp.xcodeproj` in Xcode
- Target: iOS (iPhone/iPad)
- Requires: Xcode 15+, iOS 17+
- Build: `xcodebuild -project MeditationApp.xcodeproj -scheme MeditationApp -destination 'platform=iOS Simulator,name=iPhone 16'`

## Architecture
- **MeditationApp.swift** - App entry point, `SidebarDestination` enum, `ContentView` with `NavigationSplitView`
- **MeditationModels.swift** - Core types: Pool, Gender, PronounResolver, MeditationStep, Meditation
- **MeditationParser.swift** - Parses meditation script text into Meditation steps
- **MeditationPlayer.swift** - AVSpeechSynthesizer-based playback engine
- **MeditationListView.swift** - Main list of meditations with FAB for new meditation
- **MeditationEditorView.swift** - Editor for meditation scripts (presented as sheet)
- **MedTextEditor.swift** - Custom text editor component
- **SettingsView.swift** - App settings (voice selection, speaking rate, iCloud)
- **SampleMeditations.swift** - Built-in sample meditation scripts
- **FileManager+Meditations.swift** - File persistence and iCloud migration

## Navigation
- Uses `NavigationSplitView` for hamburger menu sidebar on iPhone
- `SidebarDestination` enum in MeditationApp.swift defines all menu items
- To add a new sidebar item: add a case to `SidebarDestination` and handle it in the detail `switch` in `ContentView`
- `MeditationEditorView` is presented as a `.sheet` from `MeditationListView`

## Key Patterns
- `@EnvironmentObject` for sharing MeditationPlayer across views
- Meditation scripts are plain text files stored in the app's documents directory
- The parser converts script text → [MeditationStep] for the player
