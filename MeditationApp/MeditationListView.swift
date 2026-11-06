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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openPanel) private var openPanel
    @State private var files: [URL] = []
    @State private var fileContents: [URL: String] = [:]
    @State private var fileTitles: [URL: String] = [:]
    @State private var fileTags: [URL: [String]] = [:]
    @State private var eraIndex = EraIndex()
    @State private var showingFeelings = false
    @State private var showingTodos = false
    /// The filter bar. The app opens with both on; at least one always stays on.
    @State private var showCurrent = true
    @State private var showAlways = true
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilename = ""
    @State private var isNewFile = false
    @State private var hasGoodVoice = MeditationPlayer.hasGoodVoice
    @State private var eraEditTarget: EraEditTarget? = nil
    @State private var showingNewEra = false
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

    /// The file's era tags, newest era first.
    private func eraTags(of url: URL) -> [String] {
        let tags = fileTags[url] ?? []
        return eraIndex.eras.map(\.tag).filter { tags.contains($0) }
    }

    /// Files with no era tag made since the current era started (e.g. created straight in
    /// iCloud) count as part of the current era.
    private func isUnassignedNew(_ url: URL) -> Bool {
        guard let current = eraIndex.current, eraTags(of: url).isEmpty else { return false }
        return EraIndex.dateString(for: url) >= current.started
    }

    /// The current era's meditations, timeless ones tagged with it included.
    private var currentEraFiles: [URL] {
        guard let current = eraIndex.current else { return files }
        return files.filter {
            fileTags[$0]?.contains(current.tag) == true || (!isTimeless($0) && isUnassignedNew($0))
        }
    }

    private var timelessFiles: [URL] {
        files.filter(isTimeless)
    }

    /// Meditations from a past era, minus ones already brought along.
    private func pastFiles(_ era: EraSelection) -> [URL] {
        guard let current = eraIndex.current else { return [] }
        switch era {
        case .era(let tag):
            return eraFilesFor(tag).filter { fileTags[$0]?.contains(current.tag) != true }
        case .older:
            return files.filter { !isTimeless($0) && eraTags(of: $0).isEmpty && !isUnassignedNew($0) }
        }
    }

    /// This era's meditations. Timeless ones tagged with the era show here only while
    /// Always is filtered out, so nothing is listed twice.
    private var currentFiles: [URL] {
        let base = hasEras ? currentEraFiles : files.filter { !isTimeless($0) }
        return showAlways ? base.filter { !isTimeless($0) } : base
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
        case .past(let era): era.label
        }
    }

    var body: some View {
            List {
                switch shelf {
                case .home:
                    feelingsCard
                    // To-dos are what's pressing for now, so they go with Current.
                    if showCurrent {
                        todosCard
                    }
                    if !files.isEmpty || hasOpenTodos {
                        // Current comes first: it's what's pressing right now.
                        if showCurrent {
                            Section {
                                ForEach(currentFiles, id: \.self) { url in
                                    listRow(for: url, section: "current")
                                }
                                if currentFiles.isEmpty {
                                    emptyRow("Nothing in this era yet. Bring meditations along from a past era in History, or write a new one.")
                                }
                            } header: {
                                Text(eraIndex.current.map { "Current · \($0.tag)" } ?? "Current")
                            }
                        }
                        if showAlways {
                            Section {
                                ForEach(timelessFiles, id: \.self) { url in
                                    listRow(for: url, section: "always")
                                }
                                if timelessFiles.isEmpty {
                                    emptyRow("Mark a meditation Timeless from its Eras menu to keep it here.")
                                }
                            } header: {
                                Text("Always")
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
                        emptyRow("Everything from \(era.label) has been brought along.")
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
                    ToolbarItem(placement: .principal) {
                        filterBar
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
                                showingNewEra = true
                            } label: {
                                Label("Start New Era…", systemImage: "sparkles")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add")
                    }
                }
            }
            .onAppear { hasGoodVoice = MeditationPlayer.hasGoodVoice }
            // Settings now lives in the panel, so watch for a voice change made there.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                hasGoodVoice = MeditationPlayer.hasGoodVoice
            }
            .sheet(isPresented: $showingEditor) {
                MeditationEditorView(
                    content: $editorContent,
                    filename: $editorFilename,
                    isNew: $isNewFile
                ) { savedFilename, savedContent in
                    player.stop()
                    _ = FileManager.default.saveMeditation(savedContent, filename: savedFilename)
                    refreshFiles()
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
            .sheet(item: $eraEditTarget) { target in
                EraEditorView(
                    title: target.title,
                    eras: eraIndex.eras,
                    initialSelection: Set(target.tags)
                ) { selection in
                    saveEras(selection, for: target.url)
                }
            }
            .sheet(isPresented: $showingNewEra) {
                NewEraView(existingTags: Set(eraIndex.eras.map(\.tag))) { tag in
                    startEra(tag)
                }
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
            .background(Color("BackgroundColor"))
            .onAppear { refreshFiles() }
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
    /// to-dos start, so it leads the main screen above the filter bar.
    private var feelingsCard: some View {
        let emojis = store.selectedEmotionsSorted().prefix(8).map(\.emoji).joined()
        return pageCard(
            emoji: "🪷",
            title: "Feelings",
            subtitle: emojis.isEmpty ? "Check in with what you’re feeling" : emojis
        ) {
            showingFeelings = true
        }
    }

    /// Open to-dos live on their own page, like Feelings.
    private var todosCard: some View {
        let open = store.openTodos
        let actions = open.reduce(0) { $0 + $1.openActions.count }
        let needingAction = open.filter { $0.openActions.isEmpty }.count
        let parts = [
            actions > 0 ? (actions == 1 ? "1 to-do" : "\(actions) to-dos") : nil,
            needingAction > 0 ? "\(needingAction) need\(needingAction == 1 ? "s" : "") an action" : nil,
        ].compactMap { $0 }
        return pageCard(
            emoji: "📝",
            title: "To-dos",
            subtitle: parts.isEmpty ? "Nothing open" : parts.joined(separator: " · ")
        ) {
            showingTodos = true
        }
    }

    /// A card that opens a page of its own, like Feelings or To-dos.
    private func pageCard(emoji: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        // A button, not a NavigationLink: the list's tap-to-stop gesture swallows a
        // NavigationLink row's plain tap.
        Button(action: action) {
            HStack(spacing: 12) {
                Text(emoji)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tracksTappableFrame("card|\(title)", in: tappableFrames)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("HighlightColor"))
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 30, bottom: 4, trailing: 30))
        .listRowSeparator(.hidden)
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

    /// A title menu in the middle of the top bar: it names what's showing, and its menu
    /// checks Current, Always, or both. Unchecking the only one that's on does nothing,
    /// so the list never goes empty.
    private var filterBar: some View {
        Menu {
            Toggle("Current", isOn: Binding(
                get: { showCurrent },
                set: { on in withAnimation(.snappy(duration: 0.25)) { showCurrent = on || !showAlways } }
            ))
            Toggle("Always", isOn: Binding(
                get: { showAlways },
                set: { on in withAnimation(.snappy(duration: 0.25)) { showAlways = on || !showCurrent } }
            ))
        } label: {
            HStack(spacing: 4) {
                Text(filterTitle)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .accessibilityLabel("Show")
        .accessibilityValue(filterTitle)
    }

    private var filterTitle: String {
        switch (showCurrent, showAlways) {
        case (true, true): "Current + Always"
        case (true, false): "Current"
        default: "Always"
        }
    }

    private func listRow(for url: URL, section: String, bringAlong: Bool = false) -> some View {
        rowView(for: url, bringAlong: bringAlong)
            // Keyed by section too: a meditation can be listed in two sections.
            .tracksTappableFrame("\(section)|\(url.absoluteString)", in: tappableFrames)
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

    @ViewBuilder
    private func rowView(for url: URL, bringAlong: Bool = false) -> some View {
        let filename = url.deletingPathExtension().lastPathComponent
        let isCurrent = player.currentSourceURL == url
        let isActive = isCurrent && player.isPlaying
        let isPreparing = isCurrent && player.isPreparing
        let isEngaged = isActive || isPreparing
        let hasLogToday = store.hasMeditationLogToday(filename: filename)
        let lastPlayed = store.lastPlayed(filename: filename)
        let hasUpdate = meditationStore.updates[filename] != nil
        let storeRole = meditationStore.link(for: filename)?.role
        // Don't read elapsedSeconds here: it ticks every second and would re-render the whole list.
        let showElapsedTime = isCurrent && (player.state == .playing || player.state == .paused)
        let activeFill = Color.accentColor.mix(with: Color("BackgroundColor"), by: colorScheme == .dark ? 0.72 : 0.65)
        let inactiveFill = Color("HighlightColor").opacity(0.3)
        // Lift and glow like a running feelings chip: soft dark shadow in light mode, a glow
        // of the row's own color in dark mode.
        let liftShadow = colorScheme == .dark ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.18)
        let outerGlow = colorScheme == .dark ? Color.accentColor.opacity(0.25) : Color.clear
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
                            .foregroundStyle(isEngaged ? Color.primary : Color.primary.opacity(0.88))
                        PlayingPulseDot(isPulsing: isActive)
                            .frame(width: 12, height: 12)
                            .opacity(isEngaged ? 1 : 0)
                            .scaleEffect(isEngaged ? 1 : 0.4)
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

                LastPlayedLabel(date: lastPlayed, helpedToday: hasLogToday)
                    .opacity(hasUpdate ? 0 : 1)
            }
            .padding(.horizontal, 14 + RowFillShape.margin.width)
            .padding(.vertical, 12 + RowFillShape.margin.height)
            .background(
                ZStack {
                    RowFillShape(isGrown: isEngaged)
                        .fill(Color("BackgroundColor"))

                    RowFillShape(isGrown: isEngaged)
                        .fill(isEngaged ? activeFill : inactiveFill)
                }
            )
            .shadow(
                color: isEngaged ? liftShadow : .clear,
                radius: colorScheme == .dark ? 8 : 7,
                y: colorScheme == .dark ? 0 : 3
            )
            .shadow(color: isEngaged ? outerGlow : .clear, radius: 16)
            // One snappy transaction for every piece of the state change, so fill, lift, shadow,
            // title, dot, and time label move together instead of on separate slow curves.
            .animation(.spring(duration: 0.3, bounce: 0.25), value: isEngaged)
            .animation(.snappy(duration: 0.22), value: showElapsedTime)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            // The long-press preview is cut out along the same shape as the fill, so the cut
            // always matches it: the row grows by layout, never by a scale effect.
            .contentShape(.contextMenuPreview, RowFillShape(isGrown: isEngaged))
        }
        .buttonStyle(MeditationRowPressStyle())
        // Over the row rather than inside its label, so it gets its own taps.
        .overlay(alignment: .trailing) {
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
                .padding(.trailing, 14 + RowFillShape.margin.width)
                .accessibilityLabel("Update from the store")
            }
        }
        .background(DisableScrollTouchDelay().frame(width: 0, height: 0))
        .swipeActions(edge: .trailing) {
            Button { archiveFile(url) } label: {
                Label("Archive", systemImage: "archivebox")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            if bringAlong {
                Button { bringAlongToCurrentEra(url) } label: {
                    Label("Bring Along", systemImage: "arrow.up.circle")
                }
                .tint(.green)
            } else {
                Button { editEras(url) } label: {
                    Label("Eras", systemImage: "sparkles")
                }
                .tint(.accentColor)
            }
        }
        .contextMenu {
            if bringAlong, let current = eraIndex.current {
                Button { bringAlongToCurrentEra(url) } label: {
                    Label("Bring Along to \(current.tag)", systemImage: "arrow.up.circle")
                }
                Divider()
            }
            // A row tap plays, and a leading swipe edits eras, so the menu skips both.
            Button { editFile(url) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { editCopy(url) } label: {
                Label("Edit a Copy", systemImage: "doc.badge.plus")
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

    private func refreshFiles() {
        files = FileManager.default.meditationFiles()
        var contentMap: [URL: String] = [:]
        var titleMap: [URL: String] = [:]
        var tagMap: [URL: [String]] = [:]
        for url in files {
            let loadedContent = FileManager.default.readMeditation(at: url)
            let content = loadedContent ?? ""
            if let loadedContent {
                contentMap[url] = loadedContent
            }
            let meta = MeditationParser.parseMetadata(content)
            let title = meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
            let tags = meta.tags
            titleMap[url] = title
            tagMap[url] = tags
        }
        fileContents = contentMap
        fileTitles = titleMap
        fileTags = tagMap
        eraIndex = EraIndex.load()
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
        store.markMeditationPlayed(filename: url.deletingPathExtension().lastPathComponent)
        player.play(meditation, sourceURL: url)
    }

    private func editFile(_ url: URL) {
        player.stop()
        editorContent = fileContents[url] ?? FileManager.default.readMeditation(at: url) ?? ""
        editorFilename = url.deletingPathExtension().lastPathComponent
        isNewFile = false
        showingEditor = true
    }

    private func editCopy(_ url: URL) {
        player.stop()
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

        // The copy joins the current era.
        var copyContent = content
        let (title, tags) = metadataFor(url)
        if let current = eraIndex.current, !tags.contains(current.tag) {
            copyContent = MeditationMetadataWriter.rewrite(source: content, title: title, tags: tags + [current.tag])
        }

        _ = FileManager.default.saveMeditation(copyContent, filename: candidate)
        refreshFiles()

        // Open the editor on the new copy
        editorContent = copyContent
        editorFilename = candidate
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
        // A meditation written while only Always shows is timeless; otherwise it joins the current era.
        let eraSuffix = showAlways && !showCurrent
            ? " #\(EraIndex.timelessTag)"
            : eraIndex.current.map { " #\($0.tag)" } ?? ""
        editorContent = "# New Meditation\(eraSuffix)\n\n"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        editorFilename = dateFormatter.string(from: Date())
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

    /// Adds the current era's tag. Doesn't stop playback: only the header changes.
    private func bringAlongToCurrentEra(_ url: URL) {
        guard let current = eraIndex.current else { return }
        let (_, tags) = metadataFor(url)
        guard !tags.contains(current.tag) else { return }
        writeTags(tags + [current.tag], for: url)
        withAnimation(.snappy(duration: 0.25)) {
            refreshFiles()
        }
    }

    private func editEras(_ url: URL) {
        let (title, tags) = metadataFor(url)
        let selectable = tags.filter { eraIndex.isEraTag($0) || $0 == EraIndex.timelessTag }
        eraEditTarget = EraEditTarget(url: url, title: title, tags: selectable)
    }

    /// Rewrites the file's era and timeless tags, keeping its other tags in place.
    /// Doesn't stop playback: only the header changes.
    private func saveEras(_ selection: Set<String>, for url: URL) {
        let (_, tags) = metadataFor(url)
        let isManaged = { (tag: String) in eraIndex.isEraTag(tag) || tag == EraIndex.timelessTag }
        var newTags = tags.filter { !isManaged($0) || selection.contains($0) }
        // Added eras go oldest first, matching how tags accumulate over time.
        for tag in eraIndex.eras.map(\.tag).reversed() + [EraIndex.timelessTag]
        where selection.contains(tag) && !newTags.contains(tag) {
            newTags.append(tag)
        }
        guard newTags != tags else { return }
        writeTags(newTags, for: url)
        refreshFiles()
    }

    private func writeTags(_ newTags: [String], for url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let (title, _) = metadataFor(url)
        let updated = MeditationMetadataWriter.rewrite(source: content, title: title, tags: newTags)
        let basename = url.deletingPathExtension().lastPathComponent
        _ = FileManager.default.saveMeditation(updated, filename: basename)
    }

    private func eraFilesFor(_ tag: String) -> [URL] {
        let isCurrent = tag == eraIndex.current?.tag
        return files.filter {
            !isTimeless($0) && (fileTags[$0]?.contains(tag) == true || (isCurrent && isUnassignedNew($0)))
        }
    }

    private func startEra(_ tag: String) {
        var index = EraIndex.load()
        index.eras.insert(Era(tag: tag, started: EraIndex.todayString()), at: 0)
        index.save()
        refreshFiles()
    }
}

enum EraSelection: Hashable {
    case era(String)
    case older

    var label: String {
        switch self {
        case .era(let tag): tag
        case .older: "Older"
        }
    }
}

private struct EraEditTarget: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let tags: [String]
}

private struct DisableScrollTouchDelay: UIViewRepresentable {
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

/// A row's rounded fill. At rest it sits `margin` inside the row's frame; a playing row
/// grows to fill the frame. Growing this way rather than with scaleEffect keeps the shape,
/// and so the long-press preview cut out along it, the size of what's drawn at every moment.
private struct RowFillShape: Shape {
    static let margin = CGSize(width: 4, height: 2)

    var grown: CGFloat

    init(isGrown: Bool) { grown = isGrown ? 1 : 0 }

    var animatableData: CGFloat {
        get { grown }
        set { grown = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let inset = 1 - grown
        return Path(
            roundedRect: rect.insetBy(dx: Self.margin.width * inset, dy: Self.margin.height * inset),
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

/// How long ago a meditation was last played. Today and yesterday count in hours ("now",
/// "3h", "26h") and stand out a little; older plays fade to days, weeks, months ("3d", "2w",
/// "4mo"). A small heart marks one logged as helpful today. Blank if never played on this device.
private struct LastPlayedLabel: View {
    let date: Date?
    let helpedToday: Bool

    private enum Recency { case today, yesterday, older }

    var body: some View {
        HStack(spacing: 3) {
            if helpedToday {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color("HeartColor"))
            }
            if let date {
                let recency = Self.recency(of: date)
                Text(Self.format(date))
                    .fontWeight(recency == .older ? .regular : .semibold)
                    .foregroundStyle(style(for: recency))
            }
        }
        .font(.caption)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func style(for recency: Recency) -> AnyShapeStyle {
        switch recency {
        case .today: AnyShapeStyle(Color.accentColor)
        case .yesterday, .older: AnyShapeStyle(.secondary)
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let date {
            parts.append("Last played \(date.formatted(.relative(presentation: .named)))")
        }
        if helpedToday { parts.append("helped today") }
        return parts.joined(separator: ", ")
    }

    private static func recency(of date: Date) -> Recency {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        return .older
    }

    static func format(_ date: Date) -> String {
        if recency(of: date) != .older {
            let hours = Int(Date().timeIntervalSince(date) / 3600)
            return hours < 1 ? "now" : "\(hours)h"
        }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<14: return "\(days)d"
        case ..<60: return "\(days / 7)w"
        case ..<365: return "\(days / 30)mo"
        default: return "\(days / 365)y"
        }
    }
}

/// Elapsed time and total length of the current meditation. Kept in its own view so the
/// once-a-second elapsedSeconds tick only re-renders this label, not the list.
private struct PlaybackTimeLabel: View {
    @Environment(MeditationPlayer.self) private var player

    var body: some View {
        HStack(spacing: 4) {
            Text(Self.formatTime(player.elapsedSeconds))
            if let total = player.totalSeconds {
                Text("/")
                Text(Self.formatTime(total))
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Color.accentColor)
    }

    private static func formatTime(_ totalSeconds: Int) -> String {
        String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

/// Pulsing "now playing" dot. The pulse is a Core Animation layer animation, so it runs in the
/// render server with no per-frame work in the app, and exists only while actually pulsing.
private struct PlayingPulseDot: UIViewRepresentable {
    let isPulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> PulseDotView {
        let view = PulseDotView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PulseDotView, context: Context) {
        view.isPulsing = isPulsing && !reduceMotion
    }
}

private final class PulseDotView: UIView {
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
        let color = UIColor(named: "AccentColor") ?? tintColor ?? .systemBlue
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
