import SwiftUI

/// Which meditations a list shows: the main screen (Feelings, then Current and Always
/// behind a filter bar), or a past era's, opened from History.
enum MeditationShelf: Hashable {
    case home
    case past(EraSelection)
}

struct MeditationListView: View {
    let shelf: MeditationShelf

    @Environment(MeditationPlayer.self) var player
    @Environment(EmotionStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appPalette) private var palette
    @Environment(\.openPanel) private var openPanel
    @Environment(\.panelIsOpen) private var panelIsOpen
    @Environment(\.setHomePagePushed) private var setHomePagePushed
    @Environment(\.rowInFlight) private var rowInFlight
    @Environment(\.colorScheme) private var colorScheme
    @State private var files: [URL] = []
    @State private var fileContents: [URL: String] = [:]
    @State private var fileTitles: [URL: String] = [:]
    @State private var fileTags: [URL: [String]] = [:]
    @State private var eraIndex = EraIndex()
    /// The library reload in flight, so a burst of requests (a save, then the iCloud watcher
    /// noticing that same save) becomes one reload instead of several.
    @State private var refreshTask: Task<Void, Never>?
    /// Set once the list has loaded, so coming back from a pushed page doesn't reload it.
    @State private var hasLoaded = false
    @State private var showingFeelings = false
    @State private var showingTodos = false
    /// The filter bar. The app opens with both on; at least one always stays on.
    /// Whether each section of the main screen is open. Both always show; their headers
    /// fold them away, and the app remembers how they were left.
    @AppStorage("homeCurrentExpanded") private var currentExpanded = true
    @AppStorage("homeFoundationsExpanded") private var foundationsExpanded = true
    /// Whether the rarely played meditations hidden from each section are showing. Not
    /// remembered: they're hidden again each time the app starts.
    @State private var showingQuietCurrent = false
    @State private var showingQuietEarlier = false
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilename = ""
    @State private var isNewFile = false
    @State private var editorURL: URL?
    @State private var hasGoodVoice = MeditationPlayer.hasGoodVoice
    @State private var confirmingStartEra = false
    /// Whether the previous era's leftovers are unfolded on the main screen. Nil follows the
    /// default: open while this era is still empty, folded once it has something.
    @State private var earlierExpandedChoice: Bool? = nil
    /// Where rows and headers are on screen, so a tap between them can stop playback.
    @State private var tappableFrames = TappableFrames()
    @State private var showingStore = false
    @State private var shareTarget: ShareTarget? = nil
    /// Filename of a downloaded meditation whose update is waiting for confirmation.
    @State private var updateTarget: String? = nil
    private let meditationStore = MeditationStore.shared

    private var hasEras: Bool { !eraIndex.eras.isEmpty }

    private func isTimeless(_ url: URL) -> Bool {
        fileTags[url]?.contains(EraIndex.timelessTag) == true
    }

    /// This era's meditations: made in it or brought along to it. Evergreen meditations are listed
    /// once, under Evergreen.
    private var currentFiles: [URL] {
        let base = files.filter { !isTimeless($0) }
        guard let current = eraIndex.current else { return base }
        return base.filter { eraIndex.belongs($0, to: current) }
    }

    /// Rarely played meditations past their first few days are hidden from the main screen
    /// until asked for. Only ones whose whole life listening has been counted for: older
    /// ones' plays were never measured. One that's playing, or was brought along to this era,
    /// always shows.
    private static let quietAfterDays = 4
    private static let quietBelowSeconds: TimeInterval = 10 * 60

    private func isQuiet(_ url: URL) -> Bool {
        guard EraIndex.dateString(for: url) >= ListeningHistory.countedSince,
              let days = EraIndex.daysSinceMade(url), days > Self.quietAfterDays,
              player.currentSourceURL != url,
              !eraIndex.wasBroughtAlong(url)
        else { return false }
        let listened = player.listeningHistory.record(for: EraIndex.name(of: url), at: Date())?.totalSeconds ?? 0
        return listened < Self.quietBelowSeconds
    }

    private var timelessFiles: [URL] {
        files.filter(isTimeless)
    }

    /// Meditations from a past era, minus ones already brought along to this one.
    private func pastFiles(_ selection: EraSelection) -> [URL] {
        eraIndex.pastFiles(selection, from: files, isTimeless: isTimeless)
    }

    /// The era before this one, whose leftovers wait at the bottom of the main screen.
    private var previousEra: EraSelection? {
        guard !eraIndex.eras.isEmpty else { return nil }
        return eraIndex.eras.count > 1 ? .era(eraIndex.eras[1].id) : .older
    }

    private var earlierFiles: [URL] {
        previousEra.map(pastFiles) ?? []
    }

    private var earlierExpanded: Binding<Bool> {
        Binding(
            get: { earlierExpandedChoice ?? currentFiles.isEmpty },
            set: { earlierExpandedChoice = $0 }
        )
    }

    private var pastShelfFiles: [URL] {
        if case .past(let era) = shelf { return pastFiles(era) }
        return []
    }

    private var isPast: Bool {
        if case .past = shelf { return true }
        return false
    }

    private var hasOpenTodos: Bool {
        !store.openTodos.isEmpty
    }

    private var title: String {
        switch shelf {
        case .home: ""
        case .past(let era): eraIndex.label(for: era)
        }
    }

    var body: some View {
            List {
                switch shelf {
                case .home:
                    // Feelings is one section among the others, under the same kind of
                    // header, not a title for the whole page.
                    Section {
                        feelingsHeader
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
                    } header: {
                        FeelingsSectionTitle(tappableFrames: tappableFrames) { showingFeelings = true }
                    }
                    if !files.isEmpty || hasOpenTodos {
                        // Current comes first: it's what's pressing right now.
                        Section {
                            if currentExpanded {
                                let quiet = currentFiles.filter(isQuiet)
                                ForEach(currentFiles.filter { showingQuietCurrent || !quiet.contains($0) }, id: \.self) { url in
                                    listRow(for: url, section: "current")
                                }
                                if !quiet.isEmpty {
                                    quietToggle(count: quiet.count, section: "current", isShown: $showingQuietCurrent)
                                }
                                if currentFiles.isEmpty {
                                    emptyRow(earlierFiles.isEmpty
                                        ? "Nothing here yet. Write a new meditation, or bring one along from a past era in History."
                                        : "Nothing here yet. Listen to last era's meditations below and bring along the ones that still fit.")
                                }
                            }
                        } header: {
                            // An era has no name, only when it started.
                            sectionToggle(eraIndex.current.map(eraIndex.label(for:)) ?? "Now", isExpanded: $currentExpanded)
                        }
                        Section {
                            if foundationsExpanded {
                                ForEach(timelessFiles, id: \.self) { url in
                                    listRow(for: url, section: "always")
                                }
                                if timelessFiles.isEmpty {
                                    emptyRow("Long-press a meditation and choose Make Evergreen.")
                                }
                            }
                        } header: {
                            sectionToggle("Evergreen", isExpanded: $foundationsExpanded)
                        }
                        // Last era's meditations that haven't come along yet, to listen to and
                        // bring along from the long-press menu.
                        if let previousEra, !earlierFiles.isEmpty {
                            Section {
                                if earlierExpanded.wrappedValue {
                                    let quiet = earlierFiles.filter(isQuiet)
                                    ForEach(earlierFiles.filter { showingQuietEarlier || !quiet.contains($0) }, id: \.self) { url in
                                        listRow(for: url, section: "earlier", bringAlong: true)
                                    }
                                    if !quiet.isEmpty {
                                        quietToggle(count: quiet.count, section: "earlier", isShown: $showingQuietEarlier)
                                    }
                                }
                            } header: {
                                sectionToggle("From \(eraIndex.label(for: previousEra))", isExpanded: earlierExpanded)
                            }
                        }
                    }
                case .past(let era):
                    if hasEras && !pastShelfFiles.isEmpty {
                        Text("Swipe right to bring along")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .tracksTappableFrame("past|hint", in: tappableFrames)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(pastShelfFiles, id: \.self) { url in
                        listRow(for: url, section: "past", bringAlong: hasEras)
                    }
                    if pastShelfFiles.isEmpty {
                        emptyRow("Everything from \(eraIndex.label(for: era)) has been brought along.")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if shelf == .home && files.isEmpty && !hasOpenTodos {
                    emptyLibrary
                }
            }
            // Tapping empty space stops the current meditation, like tapping outside the
            // feelings chips stops the running one.
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                    guard !tappableFrames.contains(value.location) else { return }
                    // Decide on the next turn of the run loop, after any row's own action has
                    // run: a row tap that this gesture also sees (say its frame went stale)
                    // must not stop the meditation the row just started.
                    DispatchQueue.main.async {
                        guard player.currentSourceURL != nil,
                              !tappableFrames.rowWasJustTapped else { return }
                        player.stop()
                    }
                }
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingFeelings) {
                CheckInView()
            }
            .navigationDestination(isPresented: $showingTodos) {
                TodosView()
            }
            .toolbar {
                if !isPast {
                    // History and Settings live in the left panel.
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            openPanel()
                        } label: {
                            Image(systemName: "sidebar.left")
                                .overlay(alignment: .topTrailing) {
                                    if !hasGoodVoice {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 4, y: -2)
                                    }
                                }
                        }
                        .accessibilityLabel("History and Settings")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingTodos = true
                        } label: {
                            Image(systemName: "checklist")
                                .overlay(alignment: .topTrailing) {
                                    let count = openTodoCount
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.caption2.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(Capsule().fill(palette.tint))
                                            .offset(x: 9, y: -8)
                                    }
                                }
                        }
                        .accessibilityLabel("To-dos")
                        .accessibilityValue(openTodoCount == 0 ? "Nothing open" : "\(openTodoCount) open")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                newFile()
                            } label: {
                                Label("New Meditation", systemImage: "square.and.pencil")
                            }
                            Button {
                                showingStore = true
                            } label: {
                                Label("Browse Store", systemImage: "books.vertical")
                            }
                            Divider()
                            Button {
                                confirmingStartEra = true
                            } label: {
                                Label("Start a New Era…", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add")
                    }
                }
            }
            .onAppear { hasGoodVoice = MeditationPlayer.hasGoodVoice }
            // Tells the now-playing bar whether the main screen is still the top page. From
            // these flags rather than appear/disappear, which only fire once a push ends.
            .onChange(of: showingFeelings || showingTodos || showingEditor, initial: true) { _, pushed in
                if shelf == .home { setHomePagePushed(pushed) }
            }
            // Settings lives in the panel, so recheck the voice when it closes. Not on
            // UserDefaults changes: every feeling tap saves the session there, and listing
            // the system voices on each save made taps lag.
            .onChange(of: panelIsOpen) { _, isOpen in
                if !isOpen { hasGoodVoice = MeditationPlayer.hasGoodVoice }
            }
            // A tap on the now-playing bar: open the playing meditation's editor, over
            // whatever the main screen has pushed. Already open on it: nothing to do.
            .onChange(of: EditorRequest.shared.url) { _, url in
                guard shelf == .home, let url else { return }
                EditorRequest.shared.url = nil
                if showingEditor {
                    guard editorURL != url else { return }
                    // Another meditation's editor: close it, then open this one.
                    showingEditor = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { editFile(url) }
                } else {
                    editFile(url)
                }
            }
            // The Today widget's tap: open Feelings, over nothing else.
            .onChange(of: EditorRequest.shared.openFeelings, initial: true) { _, open in
                guard shelf == .home, open else { return }
                EditorRequest.shared.openFeelings = false
                showingEditor = false
                showingTodos = false
                showingFeelings = true
            }
            .navigationDestination(isPresented: $showingEditor) {
                MeditationEditorView(
                    content: $editorContent,
                    filename: $editorFilename,
                    isNew: $isNewFile,
                    sourceURL: editorURL
                ) { savedFilename, savedContent in
                    // No stop here: an edit already stopped this script if it was playing.
                    // Update just this file's row; a new or renamed file also needs the
                    // file list redone, which happens off the main thread.
                    if let url = FileManager.default.saveMeditation(savedContent, filename: savedFilename) {
                        updateEntry(for: url, content: savedContent)
                        if !files.contains(url) { refreshFiles() }
                    } else {
                        refreshFiles()
                    }
                }
            }
            .sheet(isPresented: $showingStore) {
                MeditationStoreView()
            }
            // Only the main list opens store links, not a past era's list pushed from History.
            .sheet(isPresented: Binding(
                get: { shelf == .home && meditationStore.openedLinkID != nil },
                set: { if !$0 { meditationStore.openedLinkID = nil } }
            )) {
                if let id = meditationStore.openedLinkID {
                    StoreLinkView(id: id)
                }
            }
            .sheet(item: $shareTarget) { target in
                ShareToStoreView(filename: target.filename, title: target.title, content: target.content)
            }
            .confirmationDialog(
                "Get the new version?",
                isPresented: Binding(
                    get: { updateTarget != nil },
                    set: { if !$0 { updateTarget = nil } }
                ),
                titleVisibility: .visible,
                presenting: updateTarget
            ) { filename in
                Button("Update") { applyStoreUpdate(filename) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its author shared a new version. It replaces this copy, including any changes you made to it.")
            }
            .confirmationDialog("Start a new era today?", isPresented: $confirmingStartEra, titleVisibility: .visible) {
                Button("Start New Era") { startEra() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(hasEras
                    ? "It starts empty. This era's meditations wait below it, so you can listen and bring along the ones that still fit."
                    : "It starts empty. Your meditations so far wait below it, so you can listen and bring along the ones that still fit.")
            }
            .alert(
                "Couldn't Start the Meditation",
                isPresented: Binding(
                    get: { player.speechFailure != nil },
                    set: { if !$0 { player.speechFailure = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iOS didn't produce speech for its first line. Try again, or pick another voice in Settings.\n\n\(player.speechFailure ?? "")")
            }
            // The panel's pages (a past era opens from History) keep its warmer background.
            .background(isPast ? palette.panel : palette.canvas)
            // Only the first time: returning from a pushed page (the editor, Feelings) shows the
            // list as a back swipe starts, and saves and the iCloud watcher keep it current anyway.
            .onAppear {
                if !hasLoaded {
                    hasLoaded = true
                    // Right away the first time, so the list never flashes empty.
                    apply(LoadedLibrary.load())
                }
            }
            .task { await meditationStore.checkForUpdates() }
            .onChange(of: scenePhase) { _, newPhase in
                // Defensive refresh on returning to foreground in case the watcher missed
                // events while the app was suspended.
                if newPhase == .active {
                    refreshFiles()
                    Task { await meditationStore.checkForUpdates() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                // Watcher only drives list refresh. The player is intentionally not invalidated
                // here — sync churn must never tear down in-flight playback. User-initiated edit,
                // and archive paths call player.stop() explicitly.
                refreshFiles()
            }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Meditations Yet", systemImage: "leaf")
        } description: {
            Text("Write your own, or add some that other people shared.")
        } actions: {
            Button("New Meditation") { newFile() }
                .buttonStyle(.borderedProminent)
            Button("Browse Store") { showingStore = true }
        }
    }

    /// Feelings is the timeless practice with its own screen, and checking in is how
    /// to-dos start, so it leads the main screen: not a card like the meditation rows, but
    /// a heading and the check-in's own chips right on the page. Its own view, so a chip
    /// tap on the check-in screen re-renders just this, not the whole list beneath it.
    private var feelingsHeader: some View {
        FeelingsHeader(tappableFrames: tappableFrames) { showingFeelings = true }
    }

    /// Open to-dos live on their own page, reached from a toolbar button whose badge
    /// counts open actions plus to-dos that still need one.
    private var openTodoCount: Int {
        store.openTodos.reduce(0) { $0 + max($1.openActions.count, 1) }
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Under a section's rows: shows or hides the rarely played meditations it leaves out.
    private func quietToggle(count: Int, section: String, isShown: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { isShown.wrappedValue.toggle() }
        } label: {
            Text(isShown.wrappedValue ? "Hide Rarely Played" : "\(count) Rarely Played")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not a tap on empty space, so it never stops a playing meditation.
        .tracksTappableFrame("quiet|\(section)", in: tappableFrames)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// A section header that folds its section away, like a disclosure group.
    private func sectionToggle(_ title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                Spacer()
            }
            .homeSectionHeaderText()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not a tap on empty space, so it never stops a playing meditation.
        .tracksTappableFrame("header|\(title)", in: tappableFrames)
        .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private func listRow(for url: URL, section: String, bringAlong: Bool = false) -> some View {
        rowView(for: url, bringAlong: bringAlong)
            // Keyed by section too: a meditation can be listed in two sections.
            .tracksTappableFrame("\(section)|\(url.absoluteString)", in: tappableFrames)
            // The main screen's rows say where their fill is, so a row can fly into the
            // now-playing bar when it starts and back when it stops.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                guard shelf == .home else { return }
                HomeRowFrames.shared.frames[url] = frame.insetBy(dx: RowFillShape.margin.width, dy: RowFillShape.margin.height)
            }
            .onDisappear { if shelf == .home { HomeRowFrames.shared.frames[url] = nil } }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // The fill sits RowFillShape.margin inside the row, so these insets are that much
            // smaller than the gaps they make.
            .listRowInsets(EdgeInsets(
                top: 4 - RowFillShape.margin.height,
                leading: 16 - RowFillShape.margin.width,
                bottom: 4 - RowFillShape.margin.height,
                trailing: 16 - RowFillShape.margin.width
            ))
    }

    private static let timeSlotHeight: CGFloat = 17

    /// The title left in a playing row's gap: the bar's colour faded well toward the page,
    /// so it's quieter than the other titles rather than louder.
    private var holeTitleColor: Color {
        palette.tint.mix(with: palette.canvas, by: colorScheme == .dark ? 0.55 : 0.5)
    }

    static let editButtonWidth: CGFloat = 36

    @ViewBuilder
    private func rowView(for url: URL, bringAlong: Bool = false) -> some View {
        let filename = url.deletingPathExtension().lastPathComponent
        let isCurrent = player.currentSourceURL == url
        let isActive = isCurrent && player.isPlaying
        let isPreparing = isCurrent && player.isPreparing
        let isEngaged = isActive || isPreparing
        let hasLogToday = store.hasMeditationLogToday(filename: filename)
        let lastPlayed = player.listeningHistory.record(for: filename, at: Date())?.lastPlayed
        let hasUpdate = meditationStore.updates[filename] != nil
        let storeRole = meditationStore.link(for: filename)?.role
        // Don't read elapsedSeconds here: it ticks every second and would re-render the whole list.
        // The now-playing bar shows the time now, on every page, so the row doesn't.
        let showElapsedTime = false
        let inactiveFill = palette.card
        // Its stand-in is on its way into the now-playing bar.
        let isAway = rowInFlight == url
        // The playing row's card has fallen into the now-playing bar: what's left is the gap
        // it came out of, with its name and listening time still in it.
        // Paused too: whenever the bar is up with this meditation, its card is down there.
        let barHoldsIt: Bool = {
            guard isCurrent else { return false }
            switch player.state {
            case .preparing, .playing, .paused: return true
            case .idle, .finished: return false
            }
        }()
        let isHole = isEngaged || barHoldsIt || isAway
        Button {
            tappableFrames.noteRowTap()
            if isPreparing {
                player.stop()
            } else if isCurrent {
                player.togglePause()
            } else {
                playFile(url)
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(titleFor(url))
                            .font(.body)
                            .fontWeight(.medium)
                            // In the gap, the title stays in a quiet, faded shade of the bar's
                            // colour: quieter than the other titles, but tied to the bar.
                            .foregroundStyle(isHole ? holeTitleColor : Color.primary.opacity(0.88))
                    }
                    // Without the time label the title drops to the row's middle; the slot
                    // below keeps its height so rows don't change size when playback starts.
                    .offset(y: showElapsedTime ? 0 : Self.timeSlotHeight / 2 + 2)
                    ZStack(alignment: .leading) {
                        if showElapsedTime {
                            PlaybackTimeLabel()
                                .transition(.opacity.combined(with: .offset(y: 4)))
                        }
                    }
                    .frame(minHeight: Self.timeSlotHeight, alignment: .leading)
                }

                Spacer()

                LastPlayedLabel(filename: filename, history: player.listeningHistory, helpedToday: hasLogToday)
                    .opacity(hasUpdate ? 0 : isHole ? 0.55 : 1)
                // Room for the edit button, which sits over the row (see below).
                Color.clear
                    .frame(width: Self.editButtonWidth - 8, height: 1)
            }
            .padding(.horizontal, 14 + RowFillShape.margin.width)
            .padding(.vertical, 12 + RowFillShape.margin.height)
            // The hole: no card at all, just the page showing through, with the dimmed name
            // and listening time left floating where the card was.
            .background {
                RowFillShape()
                    .fill(inactiveFill)
                    .opacity(isHole ? 0 : 1)
            }
            // Opens at once as the card lifts out; fills back in gently when it's put back.
            .animation(isHole ? nil : .easeOut(duration: 0.3), value: isHole)
            .animation(.snappy(duration: 0.22), value: showElapsedTime)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(.contextMenuPreview, RowFillShape())
        }
        .buttonStyle(MeditationRowPressStyle())
        // Over the row rather than inside its label, so they get their own taps: tapping
        // the row plays, tapping the circled chevron opens the editor.
        .overlay(alignment: .trailing) {
            HStack(spacing: 0) {
                if hasUpdate {
                    Button {
                        updateTarget = filename
                    } label: {
                        Text("Update")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.accentColor.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Update from the store")
                }
                Button {
                    editFile(url)
                } label: {
                    Image(systemName: "chevron.right.circle")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.editButtonWidth, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit")
            }
            .padding(.trailing, 6 + RowFillShape.margin.width)
            .opacity(isHole ? 0.55 : 1)
        }
        .background(DisableScrollTouchDelay().frame(width: 0, height: 0))
        .swipeActions(edge: .trailing) {
            Button { archiveFile(url) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(palette.tint)
        }
        // No leading swipe on the main screen: a swipe from the left edge opens the panel there.
        .swipeActions(edge: .leading) {
            if bringAlong && isPast {
                Button { bringAlongToCurrentEra(url) } label: {
                    Label("Bring Along", systemImage: "arrow.up.circle")
                }
                .tint(palette.tint)
            }
        }
        .contextMenu {
            Section {
                ListeningStatsMenuItems(filename: filename, history: player.listeningHistory)
            }
            if bringAlong {
                Button { bringAlongToCurrentEra(url) } label: {
                    Label("Bring Along", systemImage: "arrow.up.circle")
                }
                Divider()
            }
            // A row tap plays, so the menu skips that.
            Button { editFile(url) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { editCopy(url) } label: {
                Label("Edit a Copy", systemImage: "doc.badge.plus")
            }
            Button { toggleFoundation(url) } label: {
                if isTimeless(url) {
                    Label("Not Evergreen", systemImage: "xmark.circle")
                } else {
                    Label("Make Evergreen", systemImage: "leaf")
                }
            }
            if !bringAlong && !isPast && eraIndex.wasBroughtAlong(url) {
                Button { sendBack(url) } label: {
                    Label("Send Back to Past Era", systemImage: "arrow.down.circle")
                }
            }
            if hasUpdate {
                Button { updateTarget = filename } label: {
                    Label("Update from Store", systemImage: "arrow.down.circle")
                }
            }
            // Only offered for something played today; an existing mark can always be removed.
            if hasLogToday || lastPlayed.map(Calendar.current.isDateInToday) == true {
                Button {
                    store.toggleMeditationLogForToday(title: titleFor(url), sourceURL: url)
                } label: {
                    if hasLogToday {
                        Label("Remove Helpful Mark", systemImage: "heart.slash")
                    } else {
                        Label("It Helped Today", systemImage: "heart")
                    }
                }
            }
            // Rarely used: sharing and archiving (archive is also a trailing swipe).
            Menu {
                // Downloads stay with their author; "Edit a Copy" makes one that can be shared.
                if storeRole != .downloaded {
                    Button { shareToStore(url) } label: {
                        Label(storeRole == .shared ? "Update in Store…" : "Share to Store…", systemImage: "square.and.arrow.up")
                    }
                }
                if let recordName = meditationStore.link(for: filename)?.recordName {
                    ShareLink(item: MeditationStore.shareURL(for: recordName)) {
                        Label("Share Store Link…", systemImage: "link")
                    }
                }
                Button { archiveFile(url) } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    /// Reloads the library in the background and applies it on the main thread. Reading goes
    /// through iCloud file coordination one file at a time, so doing it here on the main thread
    /// used to stall whatever was animating, a back swipe most of all.
    private func refreshFiles(animation: Animation? = nil) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let started = Date()
            let library = await Task.detached(priority: .userInitiated) { LoadedLibrary.load() }.value
            guard !Task.isCancelled else { return }
            withAnimation(animation) { apply(library) }
            PerfLog.note(String(format: "library reload: %d files, %.0f ms off the main thread",
                                library.files.count, Date().timeIntervalSince(started) * 1000))
        }
    }

    private func apply(_ library: LoadedLibrary) {
        files = library.files
        fileContents = library.contents
        fileTitles = library.titles
        fileTags = library.tags
        eraIndex = library.eraIndex
    }

    /// Refreshes one saved file's row without rereading the rest.
    private func updateEntry(for url: URL, content: String) {
        let meta = MeditationParser.parseMetadata(content)
        fileContents[url] = content
        fileTitles[url] = meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
        fileTags[url] = meta.tags
    }

    private func metadataFor(_ url: URL) -> (title: String, tags: [String]) {
        let content = fileContents[url] ?? FileManager.default.readMeditation(at: url) ?? ""
        let meta = MeditationParser.parseMetadata(content)
        let title = meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
        return (title, meta.tags)
    }

    private func titleFor(_ url: URL) -> String {
        fileTitles[url] ?? metadataFor(url).title
    }

    private func playFile(_ url: URL) {
        guard let content = fileContents[url] ?? FileManager.default.readMeditation(at: url) else { return }
        let meditation = MeditationParser.parse(content)
        player.play(meditation, sourceURL: url)
    }

    private func editFile(_ url: URL) {
        editorContent = fileContents[url] ?? FileManager.default.readMeditation(at: url) ?? ""
        editorFilename = url.deletingPathExtension().lastPathComponent
        editorURL = url
        isNewFile = false
        showingEditor = true
    }

    private func editCopy(_ url: URL) {
        guard let content = fileContents[url] ?? FileManager.default.readMeditation(at: url) else { return }
        let baseName = url.deletingPathExtension().lastPathComponent

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())

        // Regex: optional date prefix, optional -vN counter, then the rest
        let datePattern = #"^(\d{4}-\d{2}-\d{2})(?:-v(\d+))?-(.+)$"#
        let suffix: String
        if let match = baseName.range(of: datePattern, options: .regularExpression),
           let _ = match as Range<String.Index>?,
           let regex = try? NSRegularExpression(pattern: datePattern),
           let result = regex.firstMatch(in: baseName, range: NSRange(baseName.startIndex..., in: baseName)) {
            suffix = String(baseName[Range(result.range(at: 3), in: baseName)!])
        } else {
            // No date prefix — use the whole name as suffix
            suffix = baseName
        }

        let existingNames = Set(files.map { $0.deletingPathExtension().lastPathComponent })

        // Try today-suffix first, then today-v2-suffix, today-v3-suffix, ...
        let candidate: String
        let base = "\(today)-\(suffix)"
        if !existingNames.contains(base) {
            candidate = base
        } else {
            var counter = 2
            while existingNames.contains("\(today)-v\(counter)-\(suffix)") {
                counter += 1
            }
            candidate = "\(today)-v\(counter)-\(suffix)"
        }

        // The copy is made today, so it's part of the current era.
        let copyContent = content

        _ = FileManager.default.saveMeditation(copyContent, filename: candidate)
        refreshFiles()

        // Open the editor on the new copy
        editorContent = copyContent
        editorFilename = candidate
        editorURL = files.first { $0.deletingPathExtension().lastPathComponent == candidate }
        isNewFile = false
        showingEditor = true
    }

    private func shareToStore(_ url: URL) {
        guard let content = fileContents[url] ?? FileManager.default.readMeditation(at: url) else { return }
        shareTarget = ShareTarget(
            filename: url.deletingPathExtension().lastPathComponent,
            title: titleFor(url),
            content: content
        )
    }

    private func applyStoreUpdate(_ filename: String) {
        if player.currentSourceURL?.deletingPathExtension().lastPathComponent == filename {
            player.stop()
        }
        meditationStore.applyUpdate(to: filename)
        refreshFiles()
    }

    private func newFile() {
        // Made today, so it's part of the current era.
        editorContent = "# New Meditation\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        editorFilename = dateFormatter.string(from: Date())
        editorURL = nil
        isNewFile = true
        showingEditor = true
    }

    private func deleteFile(_ url: URL) {
        FileManager.default.deleteMeditation(at: url)
        refreshFiles()
    }

    private func archiveFile(_ url: URL) {
        if player.currentSourceURL == url {
            player.stop()
        }
        _ = FileManager.default.archiveMeditation(at: url)
        refreshFiles()
    }

    /// Doesn't stop playback: the script itself doesn't change.
    private func bringAlongToCurrentEra(_ url: URL) {
        EraIndex.bringAlong(url)
        refreshFiles(animation: .snappy(duration: 0.25))
    }

    private func sendBack(_ url: URL) {
        EraIndex.sendBack(url)
        refreshFiles(animation: .snappy(duration: 0.25))
    }

    /// Adds or removes the `timeless` tag, keeping the file's other tags in place.
    /// Doesn't stop playback: only the header changes.
    private func toggleFoundation(_ url: URL) {
        let (_, tags) = metadataFor(url)
        let newTags = tags.contains(EraIndex.timelessTag)
            ? tags.filter { $0 != EraIndex.timelessTag }
            : tags + [EraIndex.timelessTag]
        writeTags(newTags, for: url)
        refreshFiles(animation: .snappy(duration: 0.25))
    }

    private func writeTags(_ newTags: [String], for url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let (title, _) = metadataFor(url)
        let updated = MeditationMetadataWriter.rewrite(source: content, title: title, tags: newTags)
        let basename = url.deletingPathExtension().lastPathComponent
        _ = FileManager.default.saveMeditation(updated, filename: basename)
    }

    private func startEra() {
        EraIndex.startNew()
        earlierExpandedChoice = nil
        currentExpanded = true
        refreshFiles()
    }
}

/// Finds the nearest parent UIScrollView and sets delaysContentTouches = false so a
/// press shows on touch down. Waits until it's in a window, so it also works on a
/// pushed screen, whose views aren't in the hierarchy yet when they're made.
struct DisableScrollTouchDelay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ScrollTouchDelayDisablingView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? ScrollTouchDelayDisablingView)?.disableNearestScrollViewDelay()
    }
}

private final class ScrollTouchDelayDisablingView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        disableNearestScrollViewDelay()
        DispatchQueue.main.async { [weak self] in
            self?.disableNearestScrollViewDelay()
        }
    }

    func disableNearestScrollViewDelay() {
        var current = superview
        while let parent = current {
            if let scrollView = parent as? UIScrollView {
                scrollView.delaysContentTouches = false
                return
            }
            current = parent.superview
        }
    }
}

/// The top of the main screen: a "Feelings" heading and, during a check-in, that check-in's
/// feelings as the same coloured chips as on the Feelings page. With no check-in, the
/// feelings you've spent the most time with, faded, to start from. A chip tap opens
/// Feelings with that feeling tapped, as if tapped there. It reads the check-in itself,
/// which changes on every chip tap, so only this re-renders then.
private struct FeelingsHeader: View {
    let tappableFrames: TappableFrames
    let open: () -> Void
    @Environment(EmotionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    private static let maxChips = 6
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        content
            // An old check-in ends here too, not only once Feelings opens, so this never
            // shows feelings that opening the page would clear.
            .onAppear { store.clearSessionIfStale() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.clearSessionIfStale() }
            }
            .background(DisableScrollTouchDelay().frame(width: 0, height: 0))
            .tracksTappableFrame("card|Feelings", in: tappableFrames)
    }

    @ViewBuilder private var content: some View {
        let session = store.selectedEmotionsRankedForCheckIn()
        let inSession = !session.isEmpty
        let shown = inSession ? Array(session.prefix(Self.maxChips)) : suggestions
        VStack(alignment: .leading, spacing: 10) {
            if !shown.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(shown) { emotion in
                        HomeEmotionChip(emotion: emotion, faded: !inSession) {
                            _ = store.tap(emotion)
                            openFeelings()
                        }
                    }
                }
            }
            // Always one plain link under the chips, at the right with a chevron, opening Feelings with nothing tapped:
            // the hidden ones' count when the check-in has more than fit, otherwise a way
            // to start from a feeling not shown.
            Button { openFeelings() } label: {
                HStack(spacing: 6) {
                    Text(linkTitle(session: session, shown: shown))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.regular))
                }
                // The header's size and grey at regular weight, chevron and all.
                .homeSectionDetailText()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func linkTitle(session: [Emotion], shown: [Emotion]) -> String {
        if session.count > Self.maxChips { return "\(session.count - Self.maxChips) more" }
        return shown.isEmpty ? "Check in" : "Other feelings"
    }

    /// The feelings you've spent the most time with in past check-ins.
    private var suggestions: [Emotion] {
        let usage = store.historicalEmotionUsage()
        return Emotion.all
            .filter { (usage[$0.name]?.engagementSeconds ?? 0) > 0 || (usage[$0.name]?.tapCount ?? 0) > 0 }
            .sorted {
                let l = usage[$0.name]!, r = usage[$1.name]!
                if l.engagementSeconds != r.engagementSeconds { return l.engagementSeconds > r.engagementSeconds }
                return l.tapCount > r.tapCount
            }
            .prefix(4)
            .map { $0 }
    }

    private func openFeelings() {
        // Opening Feelings leaves a playing meditation playing: mark the tap so the list's
        // tap-to-stop lets it be, even if this view's frame went stale.
        tappableFrames.noteRowTap()
        open()
    }
}

/// The Feelings section's header on the main screen, styled like the era and Evergreen
/// headers so it doesn't read as the page's title. A tap opens Feelings; during a
/// check-in its time sits at the right.
private struct FeelingsSectionTitle: View {
    let tappableFrames: TappableFrames
    let open: () -> Void
    @Environment(EmotionStore.self) private var store

    var body: some View {
        let inSession = !store.selectedEmotionsRankedForCheckIn().isEmpty
        Button {
            tappableFrames.noteRowTap()
            open()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("How are you feeling?")
                Spacer()
                if inSession {
                    LiveTimeText(isLive: store.accruingEmotionID != nil) { store.sessionTime(asOf: $0) }
                        .monospacedDigit()
                        .homeSectionDetailText()
                }
            }
            .homeSectionHeaderText()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not a tap on empty space, so it never stops a playing meditation.
        .tracksTappableFrame("header|Feelings", in: tappableFrames)
    }
}

/// A feeling chip on the main screen, drawn like the Feelings page's chips.
private struct HomeEmotionChip: View {
    let emotion: Emotion
    let faded: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(emotion.emoji)
                    .font(.title3)
                Text(emotion.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(EmotionChipBackground(emotion: emotion, colorScheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            .opacity(faded ? 0.5 : 1)
        }
        .buttonStyle(MeditationRowPressStyle())
    }
}

/// Global frames of the list's tappable rows and headers. A plain class, not observed, so
/// scrolling updates it without re-rendering the list.
private final class TappableFrames {
    private var frames: [String: CGRect] = [:]

    func set(_ frame: CGRect, for key: String) { frames[key] = frame }
    func remove(_ key: String) { frames[key] = nil }
    func contains(_ point: CGPoint) -> Bool { frames.values.contains { $0.contains(point) } }

    private var lastRowTap = Date.distantPast
    func noteRowTap() { lastRowTap = Date() }
    var rowWasJustTapped: Bool { Date().timeIntervalSince(lastRowTap) < 0.5 }
}

private extension View {
    func tracksTappableFrame(_ key: String, in frames: TappableFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.set($0, for: key) }
            .onDisappear { frames.remove(key) }
    }
}

/// Where the main screen's meditation rows are on screen (their fill, in global
/// coordinates), so `ContentView` can fly a row into the now-playing bar and back. A plain
/// class: frames change on every scroll, and nothing should re-render for that.
@MainActor final class HomeRowFrames {
    static let shared = HomeRowFrames()
    var frames: [URL: CGRect] = [:]
}

/// Shared inset for the row background and its context-menu preview.
private struct RowFillShape: Shape {
    static let margin = CGSize(width: 4, height: 2)

    func path(in rect: CGRect) -> Path {
        Path(
            roundedRect: rect.insetBy(dx: Self.margin.width, dy: Self.margin.height),
            cornerRadius: 14,
            style: .continuous
        )
    }
}

private struct MeditationRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MeditationRowPressContent(isPressed: configuration.isPressed, label: configuration.label)
    }
}

private struct MeditationRowPressContent: View {
    let isPressed: Bool
    let label: ButtonStyleConfiguration.Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Only darkens: a scale effect here would also show in the long-press preview, which
    // UIKit cuts out at the unscaled size. UIKit shrinks the row itself while it's held.
    var body: some View {
        label
            .brightness(isPressed ? -0.04 : 0)
            // Darken immediately on press; ease back on release.
            .animation(
                reduceMotion ? nil : .easeOut(duration: isPressed ? 0.08 : 0.25),
                value: isPressed
            )
    }
}

/// The top of a row's long-press menu: time listened in the last 24 hours and ever, and
/// when it was last played. Plain text, so the items show but can't be tapped.
private struct ListeningStatsMenuItems: View {
    let filename: String
    let history: ListeningHistory

    var body: some View {
        let now = Date()
        if let record = history.record(for: filename, at: now) {
            Text("Last 24 hours: \(Self.duration(record.seconds(inLastDayAt: now)))")
            Text("All time: \(Self.duration(record.totalSeconds))")
            Text("Last played \(LastPlayedLabel.age(since: record.lastPlayed, now: now))")
        } else {
            Text("Not played yet")
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "none" }
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(Int(seconds)).formatted(.units(allowed: units, width: .narrow))
    }
}

/// Recent listening has a headphones glyph; older plays show their age explicitly.
private struct LastPlayedLabel: View {
    @Environment(\.appPalette) private var palette
    let filename: String
    let history: ListeningHistory
    let helpedToday: Bool

    var body: some View {
        let active = history.activeFile == filename
        TimelineView(.periodic(from: .now, by: active ? 1 : 60)) { context in
            label(at: context.date, active: active)
        }
    }

    private func label(at now: Date, active: Bool) -> some View {
        HStack(spacing: 4) {
            if helpedToday {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.tint)
                    .accessibilityLabel("Helpful today")
            }
            if let record = history.record(for: filename, at: now) {
                let seconds = record.seconds(inLastDayAt: now)
                if seconds > 0 || active {
                    let duration = Duration.seconds(Int(seconds))
                    let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Image(systemName: "headphones")
                            .font(.caption)
                            .imageScale(.small)
                            .foregroundStyle(.tertiary)
                        Text(duration.formatted(.units(allowed: units, width: .narrow)))
                    }
                    .accessibilityLabel("Listened for \(duration.formatted(.units(width: .wide))) in the last 24 hours")
                } else {
                    Text(Self.age(since: record.lastPlayed, now: now))
                        .accessibilityLabel("Last played \(record.lastPlayed.formatted(.relative(presentation: .named)))")
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    static func age(since date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86400: return "\(seconds / 3600)h ago"
        default:
            let days = seconds / 86400
            switch days {
            case ..<14: return "\(days)d ago"
            case ..<60: return "\(days / 7)w ago"
            case ..<365: return "\(days / 30)mo ago"
            default: return "\(days / 365)y ago"
            }
        }
    }
}

/// The now-playing bar: what's playing, how far along it is, and pause and stop. A full-width
/// stripe along the bottom edge, tinted like a playing row, running down under the home
/// indicator. `ContentView` keeps one under the main navigation stack while a meditation is
/// starting, playing or paused, on every page. It reads the player itself, so its changes don't re-render the pages above it.
struct NowPlayingBar: View {
    @Environment(\.appPalette) private var palette
    var contentHidden = false
    /// The bar's tap (which opens the editor) is down: the whole bar shades.
    @State private var pressed = false

    var body: some View {
        NowPlayingBarContent(pressed: $pressed)
            // Hidden while a row flies in, which stands in for it.
            .opacity(contentHidden ? 0 : 1)
            .background {
                ZStack {
                    palette.canvas
                    palette.highlight
                    Color.primary.opacity(pressed ? 0.08 : 0)
                        .animation(.easeOut(duration: 0.15), value: pressed)
                }
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Divider() }
            }
            .accessibilityElement(children: .contain)
    }
}

/// What's inside the now-playing bar: the dot, title and time, pause and stop, all live. The
/// row flying into the bar draws this too, so whatever the player does mid-flight (starting,
/// the first seconds ticking) already shows on it, and the landing changes nothing.
struct NowPlayingBarContent: View {
    /// Set while the bar's tap is down, for the bar to shade itself.
    var pressed: Binding<Bool>? = nil
    @Environment(MeditationPlayer.self) private var player
    @Environment(\.openNowPlaying) private var openNowPlaying
    /// What the bar last showed while something was on. A stop resets the player at once
    /// (no title, no time, not playing), but the bar is still sliding away then, so it keeps
    /// showing what was playing instead of changing under your finger on its way out.
    @State private var held = Held()

    private struct Held: Equatable {
        var url: URL?
        var title = ""
        var isPlaying = true
        var isPreparing = false
    }

    private var isOn: Bool {
        switch player.state {
        case .preparing, .playing, .paused: true
        case .idle, .finished: false
        }
    }

    private var live: Held {
        let title = !player.currentTitle.isEmpty ? player.currentTitle
            : player.currentSourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        return Held(url: player.currentSourceURL, title: title, isPlaying: player.isPlaying, isPreparing: player.isPreparing)
    }

    var body: some View {
        let shown = isOn ? live : held
        let title = shown.title
        // No spacing before pause, so the tap reaches right up to it.
        HStack(spacing: 0) {
            // Anywhere but pause and stop opens the playing meditation's editor.
            Button { openNowPlaying() } label: {
                HStack(spacing: 10) {
                    PlayingPulseDot(isPulsing: shown.isPlaying)
                        .frame(width: 12, height: 12)
                    // Switching to another meditation while the bar is up rolls the title and time
                    // over to the new one: the old pair rises out as the new one comes up from below.
                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.body)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if shown.isPreparing {
                                Text("Starting…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                PlaybackTimeLabel()
                            }
                        }
                        .id(shown.url)
                        .transition(.push(from: .bottom))
                    }
                    .clipped()
                    .animation(.snappy(duration: 0.3), value: shown.url)
                    Spacer(minLength: 8)
                }
                // The whole bar but pause and stop: out to the leading edge, and its height.
                .padding(.leading, 20)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(BarPressStyle(pressed: pressed))
            .accessibilityLabel("Edit \(title)")
            Group {
                if shown.isPreparing {
                    ProgressView()
                } else {
                    Button {
                        player.togglePause()
                    } label: {
                        Image(systemName: shown.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(shown.isPlaying ? "Pause" : "Resume")
                }
            }
            .frame(width: 44, height: 44)
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop")
            .padding(.leading, 10)
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .padding(.trailing, 10)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onChange(of: live, initial: true) { _, now in
            if isOn { held = now }
        }
    }
}

/// The now-playing bar's tap: passes its pressed state up, and `NowPlayingBar` shades the
/// whole bar, edge to edge and down to the bottom.
private struct BarPressStyle: ButtonStyle {
    var pressed: Binding<Bool>?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressed?.wrappedValue = isPressed
            }
    }
}

/// Elapsed time and total length of the current meditation. Kept in its own view so the
/// once-a-second elapsedSeconds tick only re-renders this label, not the list.
struct PlaybackTimeLabel: View {
    @Environment(MeditationPlayer.self) private var player
    /// The last time shown while something was on, kept through a stop (which resets the
    /// player's times to zero) so the bar doesn't change as it slides away.
    @State private var held: (elapsed: Int, total: Int?) = (0, nil)

    private var isOn: Bool {
        switch player.state {
        case .preparing, .playing, .paused: true
        case .idle, .finished: false
        }
    }

    var body: some View {
        let elapsed = isOn ? player.elapsedSeconds : held.elapsed
        let total = isOn ? player.totalSeconds : held.total
        HStack(spacing: 4) {
            Text(Self.formatTime(elapsed))
                .foregroundStyle(Color.accentColor)
            if let total {
                Text("/")
                Text(Self.formatTime(total))
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .onChange(of: player.elapsedSeconds, initial: true) { _, seconds in
            if isOn { held.elapsed = seconds }
        }
        .onChange(of: player.totalSeconds, initial: true) { _, seconds in
            if isOn { held.total = seconds }
        }
    }

    private static func formatTime(_ totalSeconds: Int) -> String {
        String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Pulsing "now playing" dot. The pulse is a Core Animation layer animation, so it runs in the
/// render server with no per-frame work in the app, and exists only while actually pulsing.
struct PlayingPulseDot: UIViewRepresentable {
    @Environment(\.appPalette) private var palette
    let isPulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> PulseDotView {
        let view = PulseDotView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PulseDotView, context: Context) {
        view.tintColor = UIColor(palette.tint)
        view.isPulsing = isPulsing && !reduceMotion
    }
}

final class PulseDotView: UIView {
    private static let animationKey = "pulse"
    private let dot = CALayer()

    var isPulsing = false {
        didSet {
            guard isPulsing != oldValue else { return }
            updateAnimation()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.addSublayer(dot)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PulseDotView, _) in
            view.updateColor()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        dot.cornerRadius = 4
        dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        updateColor()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColor()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    private func updateColor() {
        let color = tintColor ?? .systemBlue
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.backgroundColor = color.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }

    private func updateAnimation() {
        guard isPulsing, window != nil else {
            dot.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard dot.animation(forKey: Self.animationKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9
        scale.toValue = 1.3
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1.0
        opacity.toValue = 0.6

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.9
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        // Survive the app backgrounding and returning.
        group.isRemovedOnCompletion = false
        dot.add(group, forKey: Self.animationKey)
    }
}

private struct ShareTarget: Identifiable {
    let filename: String
    let title: String
    let content: String
    var id: String { filename }
}

/// Everything the list reads from disk, loaded together off the main thread.
private struct LoadedLibrary: Sendable {
    var files: [URL] = []
    var contents: [URL: String] = [:]
    var titles: [URL: String] = [:]
    var tags: [URL: [String]] = [:]
    var eraIndex = EraIndex()

    static func load() -> LoadedLibrary {
        var library = LoadedLibrary()
        library.files = FileManager.default.meditationFiles()
        for url in library.files {
            let loaded = FileManager.default.readMeditation(at: url)
            if let loaded { library.contents[url] = loaded }
            let meta = MeditationParser.parseMetadata(loaded ?? "")
            library.titles[url] = meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
            library.tags[url] = meta.tags
        }
        // Era tags left in scripts (from before eras were dates, or another device) move out.
        for (url, content) in EraIndex.migrateLegacyTags(files: library.files, contents: library.contents) {
            library.contents[url] = content
            library.tags[url] = MeditationParser.parseMetadata(content).tags
        }
        library.eraIndex = EraIndex.load()
        return library
    }
}

/// Timing notes for checking performance on a device: printed, and appended to
/// Library/Caches/perf.log, which `xcrun devicectl device copy from` can fetch.
enum PerfLog {
    private static let queue = DispatchQueue(label: "PerfLog")

    static func note(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        print(line, terminator: "")
        queue.async {
            guard let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
            let url = dir.appendingPathComponent("perf.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}

extension View {
    /// The main screen's section headers ("How are you feeling?", the era and Evergreen
    /// headers) and the text that sits with them (the check-in time, the link under the
    /// feeling chips), set explicitly so they all match instead of relying on the list's
    /// header defaults. The colour is concrete: `.secondary` inside a list header, which is
    /// already secondary, resolves a tier lighter than the same style in a row.
    func homeSectionHeaderText() -> some View {
        font(.headline).foregroundStyle(Color(uiColor: .secondaryLabel))
    }

    /// What sits with a section header (the check-in time, the link under the feeling
    /// chips): the header's size and grey, at regular weight.
    func homeSectionDetailText() -> some View {
        font(.headline.weight(.regular)).foregroundStyle(Color(uiColor: .secondaryLabel))
    }
}
