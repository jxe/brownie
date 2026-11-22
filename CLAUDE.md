# Brownie - Meditation & Emotion App

## Overview
iOS app built with SwiftUI combining guided meditation playback with emotion tracking and reflective journaling. Uses a custom text-based meditation script format that gets parsed into timed steps (speech, pauses, countdowns). Supports iCloud sync and background audio playback.

## Build & Run
- Open `MeditationApp.xcodeproj` in Xcode
- Target: iOS (iPhone/iPad)
- Requires: Xcode 15+, iOS 17+
- Build: `xcodebuild -project MeditationApp.xcodeproj -scheme Brownie -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`

## Adding New Swift Files
New `.swift` files must be manually added to `MeditationApp.xcodeproj/project.pbxproj` in **four places**:
1. **PBXBuildFile section** — `{isa = PBXBuildFile; fileRef = ...}`
2. **PBXFileReference section** — `{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ...; sourceTree = "<group>"; }`
3. **PBXGroup children** — add the file ref ID to the `MeditationApp` group's children list
4. **PBXSourcesBuildPhase files** — add the build file ID to the Sources phase

IDs follow a sequential pattern: build file IDs start with `A1000012...`, file ref IDs start with `A2000012...`, incrementing the last hex digits.

## Architecture

### Meditation
- **MeditationApp.swift** - App entry point, `ContentView`: one main screen with a left panel (History + Settings) that slides out
- **MeditationModels.swift** - Core types: Pool, Gender, PronounResolver, MeditationStep, Meditation
- **MeditationParser.swift** - Parses meditation script text into Meditation steps
- **MeditationPlayer.swift** - AVSpeechSynthesizer-based playback engine (`@EnvironmentObject`)
- **AudioRenderer.swift** - Audio rendering support
- **StreamingPlayer.swift** - Streaming playback support
- **MeditationListView.swift** - `MeditationShelf.home` is the main screen: Feelings and To-dos cards, both opening their own pages; then this era's meditations and the Foundations (meditations tagged `timeless`), always both, each under a header that folds its section like a disclosure group (remembered in `@AppStorage`). `.past` is a past era opened from History. Also holds `NowPlayingInset`, the now-playing bar (title, pulsing dot, time, pause, stop): a full-width stripe tinted like a playing row that runs to the bottom edge. Each page pushed onto the main `NavigationStack` carries its own with `.nowPlayingStripe()` (added where the page is pushed), so it slides in with the page; the main screen has none, since its playing row shows the same, and Feelings puts it under its Negative/Positive bar
- **MeditationEditorView.swift** - Editor for meditation scripts, pushed from the list. `MedDocument` splits the text into header (title/tag lines), pools and script: the title is a plain field (Foundation and Tags… are in the title bar's ⋯ menu, next to Play), the pools are a horizontal shelf of chips (item count, dimmed when unused, + Pool) that open the pool sheet, and `MedTextEditor` edits only the script (given the rest as `outside`). Edits write the file back as title, pools, script, so pools gather at the top; a file is only rewritten that way once something in it is edited. Play in the title bar tries the script as it stands and counts as a play for the row's last-played time (it hides while that script is playing); pause and stop are on the now-playing bar. Opening the editor of the meditation that's playing leaves it playing (and it keeps going after Back); opening any other meditation's editor stops what's playing, so the bar never shows one script under another. An edit stops only this script. Play saves first, so a new meditation gets its file and row, and the play counts under the file's current name. No title. Autosaves about a second after typing stops, and on leaving the page or the app; no Save button. A new meditation keeps its filename field for the visit, and renaming it after an autosave moves the file instead of leaving a copy; a name another meditation already has is saved as `name 2` (etc.) instead of writing over it
- **MedTextEditor.swift** - Custom text editor component (UITextViewRepresentable). A tap on a time, repeat count, pool reference, a whole pool definition or the title line opens a quick edit instead of placing the cursor; tappable text sits on a rounded chip (`MedTextView`), and each pool definition is folded into one row (`MedFold`): its `~name` line on a full-width chip with an item count (dimmed and marked unused when nothing draws from it), its item lines and any blank lines before the next pool drawn at no height. The text keeps every line; the caret skips folded text, and Return at a pool row starts a line under the whole pool
- **MedQuickEdit.swift** - Quick edits for the editor: finds tappable times/counts/pools on a line, the value popover, and the pool list sheet that rewrites the pool block (an item's options menu sets pronouns, 🪨 weight, and comments it out as `# item`); Delete Pool removes the whole block. New Pool… in the keyboard bar's ~ menu asks for a name, puts `~name` at the caret, defines the pool after the last pool above that line (or just above it), and opens its sheet
- **SettingsView.swift** - App settings (voice selection, speaking rate, iCloud)
- **EraIndex.swift** - Eras: unnamed stretches of time in `eras.json` (start date, plus meditations brought along by filename). A meditation belongs to the era it was made in and any era it was brought along to; nothing about eras is in the scripts (old `#era` tags are migrated out on load). Start a New Era is in the + menu; the previous era's leftovers sit folded at the bottom of the main screen with Bring Along in the long-press menu, and past eras open from History

### Colors
- `BackgroundColor` is plain white/black for the main screen and everything pushed from it; the left panel and its pages (History, Settings, past eras, Archived, Leaderboard) use the warmer `PanelBackgroundColor`
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
- **CheckInView.swift** - Emotion selection grid with tap-to-increment counts; emotions sort by count. Pushed from the Feelings card on the main screen
- **ReflectionView.swift** - Old free-text reflection form, unused while the to-do experiment runs
- **FeelingTodoView.swift** - Experimental to-do form (feel it through; complaint/honor, long-term value, one local action). Opened by swiping a chip left or from the To-dos page. `FeelingTodo` lives in EmotionModels.swift and persists separately in Documents/feeling_todos.json, so removing the experiment leaves the journal file alone. A to-do belongs to one feeling in one check-in session (`sessionStartedAt`, plus `sessionFeelings`, the run of feelings that session), not to the feeling for all time: a chip shows and opens only its to-do from the current session, and the Current list opens to-dos by id
- **JournalView.swift** - The left panel: History, with Settings as a fixed row at the bottom (streak, past eras, past entries (journal entries merged with done to-dos) with share/export). Also `TodosView`, the To-dos page (open actions and to-dos that need an action), built from `OpenTodosSection`

## Navigation
- No tab bar. `ContentView` shows one `MeditationListView(shelf: .home)` in a `NavigationStack`, with a second `NavigationStack` (JournalView: Settings + History) behind it on the left. The sidebar button (`openPanel` environment action) or a swipe from the left edge (`PanelEdgePan`, a UIKit edge-pan on the main navigation controller, only while the main screen is the top page) slides the main screen right; a tap or leftward drag on it closes the panel. Meditation rows on the main screen have no leading swipe, so they don't fight that edge swipe; Eras… is in the long-press menu. Settings is a fixed row at the bottom of the panel
- The panel's pages (Settings, Emotion Leaderboard, a past era, a past check-in) open on the main screen, not inside the panel: the panel calls the `openFromPanel` environment action with a `PanelPage`, which closes the panel and sets the main `NavigationStack`'s path. Rows there are Buttons (`PanelLinkLabel`), not NavigationLinks
- The main screen has no title or filter menu: it always shows everything, and the era and Foundations section headers collapse and expand their sections
- The Store and new-era sheets are presented from `MeditationListView`, and `MeditationEditorView` is pushed from it; store links open on the main screen
- `FeelingTodoView` is pushed with `.navigationDestination(item:)` from CheckInView and from TodosView

## Key Patterns
- `@EnvironmentObject` for sharing `MeditationPlayer` across views
- `@Observable` + `.environment()` for sharing `EmotionStore` across views
- Meditation scripts are plain text `.med` files stored in Documents/Meditations (or iCloud container)
- Journal entries are persisted as JSON in Documents/emotion_journal.json
- The parser converts script text → [MeditationStep] for the player
