# Brownie - Meditation App

## Overview
iOS meditation app built with SwiftUI. Uses a custom text-based meditation script format that gets parsed into timed steps (speech, pauses, countdowns). Supports iCloud sync and background audio playback.

## Build & Run
- Open `MeditationApp.xcodeproj` in Xcode
- Target: iOS (iPhone/iPad)
- Requires: Xcode 15+, iOS 17+
- Build: `xcodebuild -project MeditationApp.xcodeproj -scheme MeditationApp -destination 'platform=iOS Simulator,name=iPhone 16'`

## Architecture
- **MeditationApp.swift** - App entry point, ContentView
- **MeditationModels.swift** - Core types: Pool, Gender, PronounResolver, MeditationStep, Meditation
- **MeditationParser.swift** - Parses meditation script text into Meditation steps
- **MeditationPlayer.swift** - AVSpeechSynthesizer-based playback engine
- **MeditationListView.swift** - Main list of meditations
- **MeditationEditorView.swift** - Editor for meditation scripts
- **MedTextEditor.swift** - Custom text editor component
- **SettingsView.swift** - App settings
- **SampleMeditations.swift** - Built-in sample meditation scripts
- **FileManager+Meditations.swift** - File persistence and iCloud migration

## Key Patterns
- `@EnvironmentObject` for sharing MeditationPlayer across views
- Meditation scripts are plain text files stored in the app's documents directory
- The parser converts script text → [MeditationStep] for the player
