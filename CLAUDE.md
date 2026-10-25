# Brownie - Meditation & Emotion App

## Overview
iOS app built with SwiftUI combining guided meditation playback with emotion tracking and reflective journaling. Uses a custom text-based meditation script format that gets parsed into timed steps (speech, pauses, countdowns). Supports iCloud sync and background audio playback.

## Build & Run
- Open `MeditationApp.xcodeproj` in Xcode
- Target: iOS (iPhone/iPad)
- Requires: Xcode 15+, iOS 17+
- Build: `xcodebuild -project MeditationApp.xcodeproj -scheme Brownie -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`

## Adding New Swift Files
New `.swift` files must be manually added to `MeditationApp.xcodeproj/project.pbxproj` in **four places**:
1. **PBXBuildFile section** — `{isa = PBXBuildFile; fileRef = ...}`
2. **PBXFileReference section** — `{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ...; sourceTree = "<group>"; }`
3. **PBXGroup children** — add the file ref ID to the `MeditationApp` group's children list
4. **PBXSourcesBuildPhase files** — add the build file ID to the Sources phase

IDs follow a sequential pattern: build file IDs start with `A1000012...`, file ref IDs start with `A2000012...`, incrementing the last hex digits.

## Architecture

### Meditation
- **MeditationApp.swift** - App entry point, `TabDestination` enum, `ContentView` with a `TabView` (Feelings, Meditations, Journal)
- **MeditationModels.swift** - Core types: Pool, Gender, PronounResolver, MeditationStep, Meditation
- **MeditationParser.swift** - Parses meditation script text into Meditation steps
- **MeditationPlayer.swift** - AVSpeechSynthesizer-based playback engine (`@EnvironmentObject`)
- **AudioRenderer.swift** - Audio rendering support
- **StreamingPlayer.swift** - Streaming playback support
- **MeditationListView.swift** - Main list of meditations with FAB for new meditation
- **MeditationEditorView.swift** - Editor for meditation scripts (presented as sheet)
- **MedTextEditor.swift** - Custom text editor component (UITextViewRepresentable)
- **SettingsView.swift** - App settings (voice selection, speaking rate, iCloud)
- **SampleMeditations.swift** - Installs the store's featured meditations for brand-new local libraries
- **MeditationStore.swift** - CloudKit public-database store: browse, download, share, updates, reports. Local file ↔ record links live in UserDefaults
- **MeditationStoreView.swift** - Store sheet (opened from the Meditations plus menu or the empty-library screen) and the Share to Store sheet

### Store backend (outside the app)
- **cloudkit/schema.ckdb** - CloudKit public-database schema (record types, indexes, security roles). Change it alongside any new store field
- **tools/cloudkit.sh** - `cktool` wrapper: import the schema to Development, feature a starter
- **web/** - med.nxhx.org on Vercel (`api/page.js`, page logic in `src/pages.js`): `/m/<id>` link pages with social cards, `/m/<id>.med` raw scripts, and the apple-app-site-association file for universal links
- **FileManager+Meditations.swift** - File persistence and iCloud migration

### Emotion Tracking
- **EmotionModels.swift** - `Emotion` struct (name, emoji, question, category), `JournalEntry`, static lists of ~45 emotions
- **EmotionStore.swift** - `@Observable` class managing session emotion counts and persisted journal entries (JSON in Documents)
- **CheckInView.swift** - Emotion selection grid with tap-to-increment counts; emotions sort by count
- **ReflectionView.swift** - Old free-text reflection form, unused while the to-do experiment runs
- **FeelingTodoView.swift** - Experimental to-do form (feel it through; complaint/honor, long-term value, one local action). Opened by swiping a chip left or from Journal's Open To-dos. `FeelingTodo` lives in EmotionModels.swift and persists separately in Documents/feeling_todos.json, so removing the experiment leaves the journal file alone
- **JournalView.swift** - Open to-dos (plus this session's feelings without one) + past entries (journal entries merged with done to-dos) with share/export

## Navigation
- Uses a `TabView` with tabs Feelings, Meditations, Journal (`TabDestination` in MeditationApp.swift)
- Settings, the Store, and `MeditationEditorView` are presented as `.sheet`s from `MeditationListView`
- `JournalView` uses an inner `NavigationStack` with `.navigationDestination(for: Emotion.self)` to push `FeelingTodoView` (CheckInView does the same)

## Key Patterns
- `@EnvironmentObject` for sharing `MeditationPlayer` across views
- `@Observable` + `.environment()` for sharing `EmotionStore` across views
- Meditation scripts are plain text `.med` files stored in Documents/Meditations (or iCloud container)
- Journal entries are persisted as JSON in Documents/emotion_journal.json
- The parser converts script text → [MeditationStep] for the player
