import SwiftUI

struct MeditationListView: View {
    @Environment(MeditationPlayer.self) var player
    @Environment(EmotionStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var files: [URL] = []
    @State private var fileContents: [URL: String] = [:]
    @State private var fileTitles: [URL: String] = [:]
    @State private var fileTags: [URL: [String]] = [:]
    @State private var eraIndex = EraIndex()
    /// nil means the current era, so starting a new era moves the view along with it.
    @State private var selectedEraOverride: EraSelection? = nil
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilename = ""
    @State private var isNewFile = false
    @State private var showingSettings = false
    @State private var hasGoodVoice = MeditationPlayer.hasGoodVoice
    @State private var eraEditTarget: EraEditTarget? = nil
    @State private var showingNewEra = false
    @AppStorage("timelessCollapsed") private var timelessCollapsed = false
    /// Set once the user folds or unfolds the previous era; until then it's open only while
    /// the current era is empty.
    @State private var previousEraCollapsedOverride: Bool? = nil
    /// Where rows and headers are on screen, so a tap between them can stop playback.
    @State private var tappableFrames = TappableFrames()

    private var hasEras: Bool { !eraIndex.eras.isEmpty }

    private var selectedEra: EraSelection {
        if let selectedEraOverride { return selectedEraOverride }
        if let current = eraIndex.current { return .era(current.tag) }
        return .older
    }

    private var selectedEraBinding: Binding<EraSelection> {
        Binding(
            get: { selectedEra },
            set: { newValue in
                selectedEraOverride = newValue == .era(eraIndex.current?.tag ?? "") ? nil : newValue
            }
        )
    }

    private var selectedEraTag: String? {
        if case .era(let tag) = selectedEra { return tag }
        return nil
    }

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

    /// Timeless meditations not already shown under the selected era.
    private var timelessFiles: [URL] {
        guard hasEras else { return [] }
        return files.filter { isTimeless($0) && !isInSelectedEra($0) }
    }

    private func isInSelectedEra(_ url: URL) -> Bool {
        guard let selectedEraTag else { return false }
        return fileTags[url]?.contains(selectedEraTag) == true
    }

    private var eraFiles: [URL] {
        guard hasEras else { return files }
        let rest = files.filter { !isTimeless($0) }
        switch selectedEra {
        case .older:
            return rest.filter { eraTags(of: $0).isEmpty && !isUnassignedNew($0) }
        case .era(let tag):
            // Timeless meditations also tagged with this era show here rather than under Timeless.
            let isCurrent = tag == eraIndex.current?.tag
            return files.filter {
                fileTags[$0]?.contains(tag) == true || (isCurrent && !isTimeless($0) && isUnassignedNew($0))
            }
        }
    }

    /// While viewing the current era: the era before it, or "Older" when it's the first era.
    private var previousEraLabel: String? {
        guard let current = eraIndex.current, selectedEra == .era(current.tag) else { return nil }
        return eraIndex.eras.count > 1 ? eraIndex.eras[1].tag : "Older"
    }

    private var previousEraCollapsed: Bool {
        previousEraCollapsedOverride ?? !eraFiles.isEmpty
    }

    /// Previous-era meditations not yet brought into the current era.
    private var previousEraFiles: [URL] {
        guard previousEraLabel != nil, let current = eraIndex.current else { return [] }
        if eraIndex.eras.count > 1 {
            return eraFilesFor(eraIndex.eras[1].tag).filter { fileTags[$0]?.contains(current.tag) != true }
        }
        return files.filter { !isTimeless($0) && eraTags(of: $0).isEmpty && !isUnassignedNew($0) }
    }

    private var eraTitle: String {
        guard hasEras else { return "Meditations" }
        switch selectedEra {
        case .older: return "Older"
        case .era(let tag): return tag
        }
    }

    var body: some View {
            List {
                ForEach(eraFiles, id: \.self) { url in
                    listRow(for: url)
                }
                if !timelessFiles.isEmpty {
                    timelessHeader
                    // Collapsed still shows whatever's playing, so it can be paused.
                    ForEach(timelessFiles.filter { !timelessCollapsed || player.currentSourceURL == $0 }, id: \.self) { url in
                        listRow(for: url)
                    }
                }
                if let previousEraLabel, !previousEraFiles.isEmpty {
                    previousEraHeader(previousEraLabel)
                    ForEach(previousEraFiles.filter { !previousEraCollapsed || player.currentSourceURL == $0 }, id: \.self) { url in
                        listRow(for: url, bringAlong: true)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Tapping empty space stops the current meditation, like tapping outside the
            // feelings chips stops the running one.
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                    guard player.currentSourceURL != nil,
                          !tappableFrames.contains(value.location) else { return }
                    player.stop()
                }
            )
            .navigationTitle(eraTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu {
                if hasEras {
                    Picker("Era", selection: selectedEraBinding) {
                        ForEach(eraIndex.eras, id: \.tag) { era in
                            Text(era.tag == eraIndex.current?.tag ? "\(era.tag)  Current" : era.tag)
                                .tag(EraSelection.era(era.tag))
                        }
                        Text("Older").tag(EraSelection.older)
                    }
                    Divider()
                }
                Button {
                    showingNewEra = true
                } label: {
                    Label("Start New Era…", systemImage: "sparkles")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .overlay(alignment: .topTrailing) {
                                if !hasGoodVoice {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 4, y: -2)
                                }
                            }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newFile()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { hasGoodVoice = MeditationPlayer.hasGoodVoice }
            .onChange(of: showingSettings) { _, _ in
                hasGoodVoice = MeditationPlayer.hasGoodVoice
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
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
            .background(Color("BackgroundColor"))
            .onAppear { refreshFiles() }
            .onChange(of: scenePhase) { _, newPhase in
                // Defensive refresh on returning to foreground in case the watcher missed
                // events while the app was suspended.
                if newPhase == .active { refreshFiles() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                // Watcher only drives list refresh. The player is intentionally not invalidated
                // here — sync churn must never tear down in-flight playback. User-initiated edit,
                // and archive paths call player.stop() explicitly.
                refreshFiles()
            }
    }

    private var timelessHeader: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                timelessCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Timeless")
                if timelessCollapsed {
                    Text("\(timelessFiles.count)")
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(timelessCollapsed ? 0 : 90))
                Spacer()
            }
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .tracksTappableFrame("header.timeless", in: tappableFrames)
        .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityLabel(timelessCollapsed ? "Show timeless meditations" : "Hide timeless meditations")
    }

    private func previousEraHeader(_ tag: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                previousEraCollapsedOverride = !previousEraCollapsed
            }
        } label: {
            HStack(spacing: 6) {
                Text("From \(tag)")
                if previousEraCollapsed {
                    Text("\(previousEraFiles.count)")
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(previousEraCollapsed ? 0 : 90))
                Spacer()
                if !previousEraCollapsed {
                    Text("Swipe right to bring along")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
        .tracksTappableFrame("header.previousEra", in: tappableFrames)
        .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityLabel(previousEraCollapsed ? "Show meditations from \(tag)" : "Hide meditations from \(tag)")
    }

    private func listRow(for url: URL, bringAlong: Bool = false) -> some View {
        rowView(for: url, bringAlong: bringAlong)
            .tracksTappableFrame(url.absoluteString, in: tappableFrames)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
        // Don't read elapsedSeconds here: it ticks every second and would re-render the whole list.
        let showElapsedTime = isCurrent && (player.state == .playing || player.state == .paused)
        let activeFill = Color.accentColor.mix(with: Color("BackgroundColor"), by: colorScheme == .dark ? 0.72 : 0.65)
        let inactiveFill = Color("HighlightColor").opacity(0.3)
        // Lift and glow like a running feelings chip: soft dark shadow in light mode, a glow
        // of the row's own color in dark mode.
        let liftShadow = colorScheme == .dark ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.18)
        let outerGlow = colorScheme == .dark ? Color.accentColor.opacity(0.25) : Color.clear
        Button {
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
                            .foregroundStyle(isEngaged ? Color.primary : Color.primary.opacity(0.75))
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
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color("BackgroundColor"))

                    RoundedRectangle(cornerRadius: 14)
                        .fill(isEngaged ? activeFill : inactiveFill)
                }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            )
            .scaleEffect(isEngaged ? 1.03 : 1.0)
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
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(MeditationRowPressStyle())
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
            Button { playFile(url) } label: {
                Label("Play", systemImage: "play")
            }
            Divider()
            Button { editFile(url) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { editCopy(url) } label: {
                Label("Edit a Copy", systemImage: "doc.badge.plus")
            }
            Button { editEras(url) } label: {
                Label("Eras…", systemImage: "sparkles")
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
            Divider()
            Button { archiveFile(url) } label: {
                Label("Archive", systemImage: "archivebox")
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
        if case .era(let tag) = selectedEraOverride, !eraIndex.isEraTag(tag) {
            selectedEraOverride = nil
        }
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

    private func newFile() {
        let eraSuffix = eraIndex.current.map { " #\($0.tag)" } ?? ""
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
        previousEraCollapsedOverride = nil
        selectedEraOverride = nil
        refreshFiles()
    }
}

private enum EraSelection: Hashable {
    case era(String)
    case older
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
}

private extension View {
    func tracksTappableFrame(_ key: String, in frames: TappableFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.set($0, for: key) }
            .onDisappear { frames.remove(key) }
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

    var body: some View {
        label
            .scaleEffect(reduceMotion || !isPressed ? 1.0 : 0.965)
            .brightness(isPressed ? -0.03 : 0)
            // Press down immediately; spring back with a little life on release.
            .animation(
                reduceMotion ? nil : (isPressed ? .easeOut(duration: 0.08) : .spring(duration: 0.35, bounce: 0.45)),
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
                    .font(.system(size: 9))
                    .foregroundStyle(Color("HeartColor"))
            }
            if let date {
                let recency = Self.recency(of: date)
                Text(Self.format(date))
                    .fontWeight(recency == .older ? .regular : .semibold)
                    .foregroundStyle(style(for: recency))
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func style(for recency: Recency) -> AnyShapeStyle {
        switch recency {
        case .today: AnyShapeStyle(Color.accentColor)
        case .yesterday: AnyShapeStyle(.secondary)
        case .older: AnyShapeStyle(.tertiary)
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
