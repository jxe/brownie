import SwiftUI

/// Pushed from the meditation list. The title sits at the top as a field (Evergreen and tags
/// are in the title bar's ⋯ menu), then the pools as a shelf of chips, then the script; the file is still the same plain text, written
/// with its pools gathered at the top. Play in the title bar tries out the script as it stands;
/// pause and stop are on the now-playing bar, and it keeps playing after you go back. Opening
/// another meditation's editor stops what's playing. Any edit stops playback, so the
/// next play starts from the top. Edits save themselves a moment after you stop typing,
/// and again on leaving the page or the app.
struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    /// The file as it was opened; nil for a new one. Once autosave has written the file, or
    /// renamed it, `fileURL` is where it is now.
    let sourceURL: URL?
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MeditationPlayer.self) private var player
    @State private var pendingFix: MeditationFix? = nil
    /// The script and filename as last written to disk (or as opened).
    @State private var saved: (content: String, filename: String)?
    /// The file's name follows the title (`date-slug`) while this is set: for a new
    /// meditation, or one whose name still is what its title gives. Renaming it by hand
    /// from the ⋯ menu stops that.
    @State private var followsTitle = false
    @State private var renamingFile = false
    @State private var newFilename = ""
    /// The name this page's file has on disk: the opened file's, or what autosave last wrote.
    /// A rename removes it; a name that belongs to some other meditation is never written over.
    @State private var diskName: String?
    /// Set once this page plays its script, so a new meditation (no file yet) knows it's the
    /// one playing.
    @State private var startedHere = false
    /// The meditation in its three parts: the title, the pools, and the script. Worked out
    /// from `content` when the page opens or something else changes it, so typing in the
    /// script never moves text around under the caret.
    @State private var doc = MedDocument("")
    /// The well whose section to scroll to, once it's laid out.
    @State private var scrollTarget: String?
    /// The well to give a new blank item and focus, once it's laid out.
    @State private var focusRequest: String?
    /// The well with an item being typed in.
    @State private var focusedWell: String?
    @State private var namingNewPool = false
    @State private var newPoolName = ""
    @State private var editingTags = false
    /// The title as typed. Written into the header as it changes, but read back from it only
    /// while the field isn't being typed in: the header keeps one space between words, so
    /// reading it back mid-word would reset the field and throw the caret to the end.
    @State private var titleDraft = ""
    @FocusState private var titleFocused: Bool

    /// Where this page's file is now, so a play counts for (and lights up) the right row after
    /// a new meditation's first autosave or a rename.
    private var fileURL: URL? {
        guard let diskName else { return sourceURL }
        return FileManager.default.meditationsDirectory.appendingPathComponent("\(diskName).med")
    }

    private var hasChanges: Bool {
        guard let saved else { return false }
        return saved.content != content || saved.filename != filename
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Long lines are hard to follow on iPad, so cap the measure and center it.
                    VStack(alignment: .leading, spacing: 0) {
                        headerFields
                        Divider().padding(.horizontal, 20)
                        MedTextEditor(
                            text: scriptBinding,
                            outside: doc.prefix,
                            onOpenPool: { dismissKeyboard(); scrollToWell($0) },
                            onNewPool: { addPool(named: $0, item: $1) },
                            scrolls: false
                        )
                        wells
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { dismissKeyboard() }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                // A tap on the page's empty space (between and below the wells) puts the
                // keyboard away; fields and buttons on top take their own taps.
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissKeyboard() }
                }
                // Play floats at the bottom corner while nothing plays; once something does,
                // the now-playing bar takes its place.
                .overlay(alignment: .bottomTrailing) {
                    playButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                }
                .onChange(of: scrollTarget) { _, name in
                    guard let name else { return }
                    scrollTarget = nil
                    withAnimation(.snappy) { proxy.scrollTo(WellSection.anchor(name), anchor: .top) }
                }
            }

            // A new pool is empty while its first item is typed; that's not a mistake yet.
            let diagnostics = MeditationParser.diagnose(content).filter { diagnostic in
                guard let well = focusedWell else { return true }
                return diagnostic.message != "Pool ~\(well) has no indented items under it."
            }
            if !diagnostics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diagnostics.prefix(3)) { diagnostic in
                        // A diagnostic with a known rewrite can be tapped to apply it.
                        Button {
                            pendingFix = diagnostic.fix
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Label {
                                    Text("Line \(diagnostic.line): \(diagnostic.message)")
                                } icon: {
                                    if diagnostic.isDeprecation {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .foregroundStyle(Color.primary)
                                if diagnostic.fix != nil {
                                    Spacer(minLength: 8)
                                    Text("Fix")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if diagnostics.count > 3 {
                        Text("and \(diagnostics.count - 3) more")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog(
            pendingFix?.title ?? "",
            isPresented: Binding(
                get: { pendingFix != nil },
                set: { if !$0 { pendingFix = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingFix
        ) { fix in
            if fix.replacement.isEmpty {
                Button("Delete", role: .destructive) { apply(fix) }
            } else {
                Button("Fix") { apply(fix) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { fix in
            if !fix.replacement.isEmpty {
                Text(fix.replacement.trimmingCharacters(in: .whitespaces))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                moreMenu
            }
        }
        .sheet(isPresented: $editingTags) {
            TagEditorView(title: "Tags", initialTags: meta.tags, suggestions: MedHeader.suggestedTags()) { _, tags in
                setHeader(title: meta.title, tags: tags)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Rename File", isPresented: $renamingFile) {
            TextField("filename", text: $newFilename)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = newFilename.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "/", with: "-")
                guard !name.isEmpty, name != filename else { return }
                followsTitle = false
                filename = name
            }
        } message: {
            Text(followsTitle
                 ? "The file is named after the title. Renaming it stops that."
                 : "The file's name in your Meditations folder.")
        }
        .alert("New Pool", isPresented: $namingNewPool) {
            TextField("name", text: $newPoolName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                if let name = MedTextEditor.Coordinator.poolName(from: newPoolName) { addPool(named: name) }
            }
        } message: {
            Text("Its items go in the pool; use it in the script as ~name.")
        }
        .onAppear {
            syncDocument()
            titleDraft = meta.title
            if saved == nil {
                if !isNew { diskName = filename.trimmingCharacters(in: .whitespaces) }
                let derived = MedFilename.derived(from: meta.title, keepingDateOf: filename)
                followsTitle = isNew
                    || (filename == derived && MeditationStore.shared.link(for: filename) == nil)
                // Before `saved`, so naming a new meditation isn't an edit to save.
                if followsTitle { filename = derived }
                saved = (content, filename)
                // Editing one meditation while another plays isn't supported: the now-playing
                // bar would sit under the wrong script. What's playing stops; this script, if
                // it's the one playing, carries on.
                if [MeditationPlayer.State.preparing, .playing, .paused].contains(player.state), !isPlayingThisScript { player.stop() }
            }
        }
        // Autosave once typing pauses. Changing either restarts the wait.
        .task(id: "\(filename)\u{0}\(content)") {
            guard hasChanges else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveIfNeeded()
        }
        .onDisappear {
            removeEmptyWells(except: nil)
            saveIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveIfNeeded() }
        }
        // Any edit stops this script's playback; the next play starts again from the top.
        .onChange(of: content) {
            syncDocument()
            stopIfPlaying()
        }
        .onChange(of: filename) { stopIfPlaying() }
    }

    // MARK: Title, tags and pools

    private var meta: (title: String, tags: [String]) {
        let parsed = MeditationParser.parseMetadata(doc.header)
        return (parsed.title, parsed.tags)
    }

    /// Picks up a change to `content` made elsewhere (a diagnostic's fix, say); the page's own
    /// edits already match it.
    private func syncDocument() {
        if doc.joined != content { doc = MedDocument(content) }
    }

    private func update(_ change: (inout MedDocument) -> Void) {
        var next = doc
        change(&next)
        doc = next
        if content != next.joined { content = next.joined }
    }

    private var scriptBinding: Binding<String> {
        Binding(get: { doc.script }, set: { script in update { $0.script = script } })
    }

    private func setHeader(title: String, tags: [String]) {
        update { doc in
            let title = title.trimmingCharacters(in: .whitespaces)
            doc.header = title.isEmpty && tags.isEmpty
                ? ""
                : MeditationMetadataWriter.rewrite(source: doc.header, title: title, tags: tags)
                    .trimmingCharacters(in: .newlines)
        }
        if followsTitle {
            let name = MedFilename.derived(from: title, keepingDateOf: filename)
            if name != filename { filename = name }
        }
    }

    private var isFoundation: Bool { meta.tags.contains(EraIndex.timelessTag) }

    /// The title as a plain field. Evergreen and tags are in the title bar's ⋯ menu.
    private var headerFields: some View {
        TextField("Title", text: $titleDraft)
        .focused($titleFocused)
        .font(.title2.weight(.semibold))
        .submitLabel(.done)
        .onSubmit { dismissKeyboard() }
        .onChange(of: titleDraft) { _, typed in
            if typed != meta.title { setHeader(title: typed, tags: meta.tags) }
        }
        // Changed some other way (or typing is done): show the title as the file has it.
        .onChange(of: meta.title) { _, title in
            if !titleFocused, titleDraft != title { titleDraft = title }
        }
        .onChange(of: titleFocused) { _, focused in
            if !focused, titleDraft != meta.title { titleDraft = meta.title }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// The title bar's ⋯ menu: things about the whole meditation rather than its script.
    private var moreMenu: some View {
        Menu {
            Button {
                let tags = isFoundation
                    ? meta.tags.filter { $0 != EraIndex.timelessTag }
                    : meta.tags + [EraIndex.timelessTag]
                setHeader(title: meta.title, tags: tags)
            } label: {
                if isFoundation {
                    Label("Evergreen", systemImage: "checkmark")
                } else {
                    Label("Evergreen", systemImage: "leaf")
                }
            }
            let others = meta.tags.filter { $0 != EraIndex.timelessTag }
            Button {
                editingTags = true
            } label: {
                if others.isEmpty {
                    Label("Tags…", systemImage: "number")
                } else {
                    Label {
                        Text("Tags…")
                        Text(others.map { "#\($0)" }.joined(separator: " "))
                    } icon: {
                        Image(systemName: "number")
                    }
                }
            }
            Button {
                newFilename = diskName ?? filename
                renamingFile = true
            } label: {
                Label {
                    Text("Rename File…")
                    Text(diskName ?? filename)
                } icon: {
                    Image(systemName: "doc")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    // MARK: Wells

    /// The pools in the order the script first reaches them, depth first: a pool the script
    /// draws from, then the pools its items draw from. Pools nothing reaches come last.
    private var wellOrder: [String] {
        let defined = doc.poolNames
        var order: [String] = []
        func visit(_ name: String) {
            guard defined.contains(name), !order.contains(name),
                  let index = doc.poolIndex(named: name) else { return }
            order.append(name)
            let items = doc.pools[index].split(separator: "\n", omittingEmptySubsequences: false)
                .dropFirst().joined(separator: "\n")
            for reference in MeditationParser.poolReferences(in: items) { visit(reference) }
        }
        for reference in MeditationParser.poolReferences(in: doc.script) { visit(reference) }
        for name in defined where !order.contains(name) { order.append(name) }
        return order
    }

    /// One section per pool under the script, its items edited in place, then New Pool.
    private var wells: some View {
        let unused = MeditationParser.unusedPoolNames(in: content)
        let references = MeditationParser.referenceableNames(in: content)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(wellOrder, id: \.self) { name in
                if let index = doc.poolIndex(named: name) {
                    WellSection(
                        name: name,
                        poolText: doc.pools[index],
                        isUnused: unused.contains(name),
                        canInline: MeditationParser.canInlinePool(name, in: content),
                        references: references,
                        focusRequest: $focusRequest,
                        onWrite: { items in writeWell(name, items: items) },
                        onFocusChange: { wellFocusChanged(name, focused: $0) },
                        onDelete: {
                            update { doc in
                                if let i = doc.poolIndex(named: name) { doc.pools.remove(at: i) }
                            }
                        },
                        onInline: { inlinePool(named: name, with: $0) },
                        onExtract: { items, newPool, text in
                            extract(from: name, items: items, into: newPool, text: text)
                        },
                        onOpenPool: { dismissKeyboard(); scrollToWell($0) })
                    .id(WellSection.anchor(name))
                }
            }
            // Centered under the wells, where the next one would go.
            Button {
                newPoolName = ""
                namingNewPool = true
            } label: {
                Label("New Pool", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            // Room to scroll the last well clear of the play button.
            .padding(.bottom, 88)
        }
    }

    /// Writes a well's items back into its pool block, and returns the block as written.
    private func writeWell(_ name: String, items: [MedPoolBlock.Item]) -> String {
        var written = ""
        update { doc in
            guard let i = doc.poolIndex(named: name) else { return }
            doc.pools[i] = MedPoolBlock.find(named: name, in: doc.pools[i])?.text(with: items) ?? doc.pools[i]
            written = doc.pools[i]
        }
        return written
    }

    private func scrollToWell(_ name: String) {
        // After this update, so a well just added is there to scroll to.
        DispatchQueue.main.async { scrollTarget = name }
    }

    /// Defines a pool (unless it exists) and scrolls to it. `item`, text taken out of the
    /// script or another pool, is its first item, or one more if the pool exists; without
    /// one, the pool gets a new blank item to type in.
    private func addPool(named name: String, item: String? = nil) {
        let item = item?.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        let firstItem = item.flatMap { $0.isEmpty ? nil : $0 }
        if let index = doc.poolIndex(named: name) {
            if let firstItem, let block = MedPoolBlock.find(named: name, in: doc.pools[index]) {
                update { $0.pools[index] = block.text(with: block.items + [MedPoolBlock.Item(text: firstItem)]) }
            }
        } else {
            // A pool needs an indented line under its `~name` to be one, so a new empty pool
            // gets a blank one until it has items (and goes away if it never does).
            update { $0.pools.append("~ \(name)\n  " + (firstItem ?? "")) }
        }
        if firstItem == nil { focusRequest = name }
        scrollToWell(name)
    }

    /// Typing moved into or out of a well. Leaving one removes any well left with no items,
    /// once it's clear the typing didn't just move to another item of the same well.
    private func wellFocusChanged(_ name: String, focused: Bool) {
        if focused {
            focusedWell = name
            return
        }
        if focusedWell == name { focusedWell = nil }
        DispatchQueue.main.async { removeEmptyWells(except: focusedWell ?? focusRequest) }
    }

    /// Removes pools with no items: with nothing under its `~name` line one wouldn't be a
    /// pool, just a line drawing from one.
    private func removeEmptyWells(except keep: String?) {
        let empty = doc.pools.indices.filter { i in
            guard let block = MedPoolBlock.blockRanges(in: doc.pools[i]).first,
                  let found = MedPoolBlock.find(named: block.name, in: doc.pools[i]) else { return true }
            return block.name != keep && found.items.isEmpty
        }
        guard !empty.isEmpty else { return }
        update { doc in
            for i in empty.reversed() { doc.pools.remove(at: i) }
        }
    }

    /// Writes `text` in place of every `~name`, in the script and the other pools, and removes the pool.
    private func inlinePool(named name: String, with text: String) {
        update { doc in
            guard let index = doc.poolIndex(named: name) else { return }
            doc.pools.remove(at: index)
            doc.pools = doc.pools.map { MeditationParser.inliningPool(name, with: text, in: $0) }
            doc.script = MeditationParser.inliningPool(name, with: text, in: doc.script)
        }
    }

    /// Saves pool `name` with `items` (selected text in one of them now `~newPool`), then
    /// moves the text into `newPool` and scrolls to that one.
    private func extract(from name: String, items: [MedPoolBlock.Item], into newPool: String, text: String) {
        update { doc in
            if let i = doc.poolIndex(named: name) {
                doc.pools[i] = MedPoolBlock.find(named: name, in: doc.pools[i])?.text(with: items) ?? doc.pools[i]
            }
        }
        addPool(named: newPool, item: text)
    }

    /// A round play button floating at the bottom corner: plays the script as it stands. Pause
    /// and stop are on the now-playing bar, so it shows only while that bar is down.
    @ViewBuilder
    private var playButton: some View {
        if player.state == .idle || player.state == .finished {
            Button {
                dismissKeyboard()
                // Write any pending edit first, so a new meditation has a file (and a row)
                // and the play is counted under the name it has now.
                saveIfNeeded()
                startedHere = true
                // The player records listening time under the file it is given, so pass where the
                // script is now (after any rename the save just did).
                player.play(MeditationParser.parse(content), sourceURL: fileURL)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Whether what's playing (or paused, or starting) came from this page's script.
    private var isPlayingThisScript: Bool {
        switch player.state {
        case .playing, .paused, .preparing:
            if let url = player.currentSourceURL, url == sourceURL || url == fileURL { return true }
            return startedHere && player.currentSourceURL == nil
        case .idle, .finished:
            return false
        }
    }

    private func saveIfNeeded() {
        guard hasChanges else { return }
        let name = filename.trimmingCharacters(in: .whitespaces)
        // A new meditation needs a name first; wait until it has one.
        guard !name.isEmpty else { return }
        // Autosave runs mid-typing, so the name may match another meditation (two new ones on
        // the same day both start as the date). Never write over it: use the next free name.
        let target = freeName(for: name)
        onSave(target, content)
        // Renamed: the file was written under its new name, so remove the old one.
        if let diskName, diskName != target {
            let old = FileManager.default.meditationsDirectory.appendingPathComponent("\(diskName).med")
            FileManager.default.deleteMeditation(at: old)
            // Eras, listening stats and store links know it by name.
            EraIndex.rename(diskName, to: target)
            player.listeningHistory.rename(diskName, to: target)
            MeditationStore.shared.renameLink(diskName, to: target)
        }
        diskName = target
        saved = (content, filename)
        isNew = false
    }

    /// `name`, or `name 2`, `name 3`… when another meditation already has it.
    private func freeName(for name: String) -> String {
        let dir = FileManager.default.meditationsDirectory
        func taken(_ candidate: String) -> Bool {
            candidate != diskName
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(candidate).med").path)
        }
        var candidate = name
        var n = 2
        while taken(candidate) {
            candidate = "\(name) \(n)"
            n += 1
        }
        return candidate
    }

    /// Stops this script if it's what's playing; something else playing carries on.
    private func stopIfPlaying() {
        if isPlayingThisScript { player.stop() }
    }

    private func apply(_ fix: MeditationFix) {
        let ns = content as NSString
        // The script may have changed since the dialog opened; skip a fix that no longer fits.
        guard NSMaxRange(fix.range) <= ns.length else { return }
        content = ns.replacingCharacters(in: fix.range, with: fix.replacement)
    }
}


/// One pool under the script: a `~name` header with its item count (long-press it for options), then its
/// items, each edited in place and written straight back to the pool block.
private struct WellSection: View {
    let name: String
    /// The pool block as it is in the document.
    let poolText: String
    /// No line draws from this pool.
    let isUnused: Bool
    /// See `MeditationParser.canInlinePool`.
    let canInline: Bool
    /// The meditation's pools and remembered picks, for the item fields' `~…` menu.
    let references: (pools: [String], picks: [String])
    /// A well's name when it should get a new blank item, focused. Cleared once done.
    @Binding var focusRequest: String?
    /// Writes the items back, returning the block as written.
    let onWrite: ([MedPoolBlock.Item]) -> String
    let onFocusChange: (Bool) -> Void
    let onDelete: () -> Void
    let onInline: (String) -> Void
    /// Make Pool… on text selected in an item: the items with `~name` in place of the
    /// selection, the new pool's name, and the selected text for it.
    let onExtract: (_ items: [MedPoolBlock.Item], _ newPool: String, _ text: String) -> Void
    /// Tapping a `~name` reference in an item jumps to that well.
    let onOpenPool: (String) -> Void

    /// The items being edited, with their ids kept while typing; blank ones aren't written.
    @State private var items: [MedPoolBlock.Item] = []
    /// The block as this section last read or wrote it, so a change from elsewhere is picked up.
    @State private var known: String?
    @State private var focused: UUID?
    @State private var confirmingDelete = false
    @State private var confirmingInline = false
    @State private var extracting: (item: UUID, range: NSRange)?
    @State private var newPoolName = ""

    /// How far the card is swiped left to show Delete behind it; 0 when closed.
    @State private var swipeOffset: CGFloat = 0
    /// Where the card sat when the current swipe began.
    @State private var swipeStart: CGFloat?
    /// How far a swipe opens the card.
    private static let deleteWidth: CGFloat = 88

    static func anchor(_ name: String) -> String { "well:\(name)" }

    /// The pool's one live item, when it has exactly one.
    private var onlyItem: String? {
        let live = items.filter { !$0.commented }
            .map { $0.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return live.count == 1 ? live[0] : nil
    }

    private var liveCount: Int {
        items.filter { !$0.commented && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var body: some View {
        // Swipe the card left for Delete, as in Mail; a long swipe asks to delete straight away.
        ZStack(alignment: .trailing) {
            if swipeOffset < 0 {
                Button {
                    confirmingDelete = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: max(0, -swipeOffset - 8))
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.red))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            card
                .offset(x: swipeOffset)
                // While it's open, a tap on the card closes it instead of editing.
                .overlay {
                    if swipeOffset < 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: swipeOffset)
                            .onTapGesture { closeSwipe() }
                    }
                }
        }
        .simultaneousGesture(swipe)
        .accessibilityAction(named: "Delete Pool") { confirmingDelete = true }
        .onChange(of: confirmingDelete) { _, showing in
            if !showing { closeSwipe() }
        }
        // Content inside lines up with the title and script (8 + 12 = 20).
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .onAppear {
            readIfChanged()
            takeFocusRequest()
        }
        .onChange(of: poolText) { readIfChanged() }
        .onChange(of: focusRequest) { takeFocusRequest() }
        .onChange(of: focused) { old, id in
            // A blank item goes once typing leaves it.
            if let old, old != id, let item = items.first(where: { $0.id == old }),
               item.text.trimmingCharacters(in: .whitespaces).isEmpty {
                items.removeAll { $0.id == old }
            }
            onFocusChange(id != nil)
        }
        .confirmationDialog("Delete ~\(name) and its \(liveCount) items?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Pool", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Write “\(onlyItem ?? "")” in place of each ~\(name), and remove the pool?",
                            isPresented: $confirmingInline, titleVisibility: .visible) {
            Button("Replace with Text") {
                if let onlyItem { onInline(onlyItem) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Make Pool", isPresented: Binding(
            get: { extracting != nil },
            set: { if !$0 { extracting = nil } }
        )) {
            TextField("name", text: $newPoolName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { extracting = nil }
            Button("Create") { extract() }
        } message: {
            Text("The selected text becomes an item of the new pool, and ~name takes its place.")
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(items) { item in
                row(item.id)
            }
            Button {
                addItem(after: nil)
            } label: {
                Label("Item", systemImage: "plus")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        // A faint card holds each well, so its items read as one group.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
                // Opaque under the tint, so Delete behind shows only where the card moved off.
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .systemBackground)))
        )
    }

    /// A sideways drag on the card; drags that are mostly up or down are left to the page.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if swipeStart == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    swipeStart = swipeOffset
                    dismissKeyboard()
                }
                guard let start = swipeStart else { return }
                swipeOffset = min(0, start + value.translation.width)
            }
            .onEnded { value in
                guard let start = swipeStart else { return }
                swipeStart = nil
                let end = start + value.predictedEndTranslation.width
                withAnimation(.snappy) {
                    if end < -Self.deleteWidth * 2.6 {
                        swipeOffset = -Self.deleteWidth
                        confirmingDelete = true
                    } else if end < -Self.deleteWidth / 2 {
                        swipeOffset = -Self.deleteWidth
                    } else {
                        swipeOffset = 0
                    }
                }
            }
    }

    private func closeSwipe() {
        withAnimation(.snappy) { swipeOffset = 0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("~\(name)")
            .font(.subheadline.monospaced().weight(.semibold))
            .opacity(isUnused ? 0.45 : 1)
            if isUnused {
                Text("unused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .frame(minHeight: 30)
        .padding(.leading, 12)
        .padding(.trailing, 12)
        // The pool's options are a long press on its name row, not a visible button.
        .contentShape(Rectangle())
        .contextMenu {
            if onlyItem != nil {
                Button {
                    confirmingInline = true
                } label: {
                    Label("Replace ~\(name) with Its Text", systemImage: "text.insert")
                }
                .disabled(!canInline)
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete Pool", systemImage: "trash")
            }
            // The menu's items appear as it opens: put the keyboard away then.
            .onAppear { dismissKeyboard() }
        }
        .accessibilityHint(isUnused ? "Not used in the script" : "")
    }

    private func row(_ id: UUID) -> some View {
        let item = binding(for: id)
        return HStack(alignment: .center, spacing: 8) {
            MedItemField(text: item.text, references: references,
                         dimmed: item.wrappedValue.commented, focused: focused == id,
                         onFocus: { focused = id },
                         onBlur: { if focused == id { focused = nil } },
                         onSubmit: { addItem(after: id) },
                         onExtract: { range in
                             newPoolName = ""
                             extracting = (id, range)
                         },
                         onOpenPool: onOpenPool)
                .overlay(alignment: .leading) {
                    if item.wrappedValue.text.isEmpty {
                        Text("New item").font(Font(medFont)).foregroundStyle(.tertiary).allowsHitTesting(false)
                    }
                }
            MedItemMarkerMenu(item: item, onDelete: { remove(id) })
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
    }

    private func binding(for id: UUID) -> Binding<MedPoolBlock.Item> {
        Binding(
            get: { items.first { $0.id == id } ?? MedPoolBlock.Item() },
            set: { item in
                guard let index = items.firstIndex(where: { $0.id == id }) else { return }
                items[index] = item
                write()
            })
    }

    private func write() {
        known = onWrite(items)
    }

    /// Takes up the block as it now is, unless it's what this section wrote.
    private func readIfChanged() {
        guard poolText != known else { return }
        known = poolText
        items = MedPoolBlock.find(named: name, in: poolText)?.items ?? []
    }

    private func takeFocusRequest() {
        guard focusRequest == name else { return }
        focusRequest = nil
        addItem(after: nil)
    }

    private func addItem(after id: UUID?) {
        let item = MedPoolBlock.Item()
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(item, at: index + 1)
        } else {
            items.append(item)
        }
        focused = item.id
    }

    private func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if focused == id { focused = nil }
        write()
    }

    /// Takes the selected text out of its item into pool `newPoolName`, leaving `~name` behind.
    private func extract() {
        defer { extracting = nil }
        guard let extracting,
              let newName = MedTextEditor.Coordinator.poolName(from: newPoolName), newName != name,
              let index = items.firstIndex(where: { $0.id == extracting.item }) else { return }
        let ns = items[index].text as NSString
        guard NSMaxRange(extracting.range) <= ns.length else { return }
        let selected = ns.substring(with: extracting.range)
        var updated = items
        updated[index].text = ns.replacingCharacters(in: extracting.range, with: "~\(newName)")
        focused = nil
        onExtract(updated, newName, selected)
    }
}

/// A small rounded chip for the editor's header and pool shelf.
private struct ShelfChipStyle: ButtonStyle {
    var selected: Bool
    var monospaced = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(monospaced ? .subheadline.monospaced() : .subheadline)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A meditation in three parts: the title and tag lines, the pool definitions, and the
/// script. Written back as the title, then the pools, then the script, each after a blank line.
struct MedDocument: Equatable {
    /// The title and tag lines, without a final line break; empty when there's no title.
    var header: String
    /// Each pool definition, `~name` line and items, without a final line break.
    var pools: [String]
    /// Everything else, as written.
    var script: String

    init(_ content: String) {
        var rest = String(content.drop { $0 == "\n" })
        if let range = MedHeader.range(in: rest) {
            let ns = rest as NSString
            header = ns.substring(with: range).trimmingCharacters(in: .newlines)
            rest = ns.substring(from: NSMaxRange(range))
        } else {
            header = ""
        }
        let blocks = MedPoolBlock.blockRanges(in: rest)
        let restNS = rest as NSString
        pools = blocks.map { restNS.substring(with: $0.range) }
        // Take the pools out, last first so earlier ranges stay put, along with the line break
        // after each and a blank line that would be left doubled.
        let remaining = NSMutableString(string: rest)
        for block in blocks.reversed() {
            var range = block.range
            if NSMaxRange(range) < remaining.length { range.length += 1 }
            remaining.deleteCharacters(in: range)
            let at = range.location
            if at < remaining.length, remaining.character(at: at) == 10,
               at == 0 || remaining.character(at: at - 1) == 10 {
                remaining.deleteCharacters(in: NSRange(location: at, length: 1))
            }
        }
        script = String(String(remaining).drop { $0 == "\n" })
    }

    /// What comes before the script in the file.
    var prefix: String {
        let parts = [header, pools.joined(separator: "\n\n")].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: "\n\n") + "\n\n"
    }

    var joined: String { prefix + script }

    var poolNames: [String] {
        pools.compactMap(Self.name(of:))
    }

    func poolIndex(named name: String) -> Int? {
        pools.firstIndex { Self.name(of: $0) == name }
    }

    func itemCount(of name: String) -> Int {
        guard let index = poolIndex(named: name),
              let block = MedPoolBlock.find(named: name, in: pools[index]) else { return 0 }
        return block.items.filter { !$0.commented }.count
    }

    private static func name(of pool: String) -> String? {
        let first = pool.prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        guard MeditationParser.isPoolDefinitionHeader(first) else { return nil }
        return first.dropFirst().trimmingCharacters(in: .whitespaces)
    }
}

/// Meditation filenames made from titles: `yyyy-MM-dd-the-title`.
enum MedFilename {
    /// The title in lowercase words joined by hyphens; "meditation" when it has none.
    static func slug(_ title: String) -> String {
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "meditation" : slug
    }

    /// `date-slug`, keeping the date `filename` starts with (the day it was made), else today.
    static func derived(from title: String, keepingDateOf filename: String) -> String {
        let date: String
        if let range = filename.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            date = String(filename[range])
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.string(from: Date())
        }
        return "\(date)-\(slug(title))"
    }
}

/// Puts the keyboard away, from whichever field has it.
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
