import SwiftUI

struct MeditationListView: View {
    @Environment(MeditationPlayer.self) var player
    @Environment(EmotionStore.self) var store
    @State private var files: [URL] = []
    @State private var fileTitles: [URL: String] = [:]
    @State private var fileTags: [URL: [String]] = [:]
    @State private var allTags: [String] = []
    @State private var selectedTag: String? = nil
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilename = ""
    @State private var isNewFile = false
    @State private var showingSettings = false
    @State private var hasGoodVoice = MeditationPlayer.hasGoodVoice
    @State private var helpfulConfirmURL: URL? = nil
    @State private var tagEditTarget: TagEditTarget? = nil

    private var filteredFiles: [URL] {
        guard let tag = selectedTag else { return files }
        return files.filter { fileTags[$0]?.contains(tag) == true }
    }
    var body: some View {
            List {
                if !allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedTag == tag ? Color.accentColor : Color.accentColor.opacity(0.18))
                                    .foregroundStyle(selectedTag == tag ? .white : .primary)
                                    .clipShape(Capsule())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedTag = selectedTag == tag ? nil : tag
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(filteredFiles, id: \.self) { url in
                    rowView(for: url)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .navigationTitle("Meditations")
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
                    let savedURL = FileManager.default.saveMeditation(savedContent, filename: savedFilename)
                    refreshFiles()
                    // If we just edited the currently-playing meditation, stop so next tap re-parses
                    if let savedURL, player.currentSourceURL == savedURL {
                        player.stop()
                    }
                }
            }
            .sheet(item: $tagEditTarget) { target in
                TagEditorView(
                    title: target.title,
                    initialTags: target.tags,
                    suggestions: allTags.filter { !target.tags.contains($0) }
                ) { newTags in
                    saveTags(newTags, for: target.url)
                }
            }
            .background(Color("BackgroundColor"))
            .onAppear { refreshFiles() }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                refreshFiles()
            }
    }

    @ViewBuilder
    private func rowView(for url: URL) -> some View {
        let filename = url.deletingPathExtension().lastPathComponent
        let isCurrent = player.currentSourceURL == url
        let isActive = isCurrent && player.isPlaying
        let hasLogToday = store.hasMeditationLogToday(filename: filename)
        let showHelpfulToggle = isCurrent
            || hasLogToday
            || store.wasRecentlyPlayed(filename: filename)
        Button {
            if isCurrent {
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
                            .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.6))
                        if isActive {
                            PlayingPulseDot()
                        }
                    }
                    if isCurrent && (player.isPlaying || player.elapsedSeconds > 0) {
                        Text(formatTime(player.elapsedSeconds))
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    } else if let tags = fileTags[url], !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color("HighlightColor").opacity(isActive ? 1.0 : 0.3))
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color("BackgroundColor"))
                    )
                    .animation(.easeInOut(duration: 0.2), value: isActive)
            )
            .shadow(color: .black.opacity(isActive ? 0.08 : 0.0), radius: isActive ? 6 : 0, y: isActive ? 3 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(MeditationRowPressStyle())
        .overlay(alignment: .trailing) {
            if showHelpfulToggle {
                Button {
                    helpfulConfirmURL = url
                } label: {
                    Image(systemName: hasLogToday ? "heart.fill" : "questionmark")
                        .font(hasLogToday ? .title3 : .footnote)
                        .foregroundStyle(hasLogToday ? Color("HeartColor") : Color.secondary)
                        .frame(width: 22, alignment: .center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hasLogToday ? "Marked as helpful today" : "Rate this meditation")
                .confirmationDialog(
                    titleFor(url),
                    isPresented: Binding(
                        get: { helpfulConfirmURL == url },
                        set: { if !$0 { helpfulConfirmURL = nil } }
                    ),
                    titleVisibility: .hidden
                ) {
                    if hasLogToday {
                        Button("Remove helpful mark", role: .destructive) {
                            store.toggleMeditationLogForToday(title: titleFor(url), sourceURL: url)
                        }
                    } else {
                        Button("Yes, it helped") {
                            store.toggleMeditationLogForToday(title: titleFor(url), sourceURL: url)
                        }
                    }
                } message: {
                    if hasLogToday {
                        Text("Remove today's helpful mark?")
                    } else {
                        Text("Did this meditation help you?")
                    }
                }
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
            Button { editTags(url) } label: {
                Label("Tags", systemImage: "tag")
            }
            .tint(.accentColor)
        }
        .contextMenu {
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
            Button { editTags(url) } label: {
                Label("Edit Tags", systemImage: "tag")
            }
            Divider()
            Button { archiveFile(url) } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func refreshFiles() {
        files = FileManager.default.meditationFiles()
        var titleMap: [URL: String] = [:]
        var tagMap: [URL: [String]] = [:]
        var tagSet: Set<String> = []
        for url in files {
            let (title, tags) = metadataFor(url)
            titleMap[url] = title
            tagMap[url] = tags
            tagSet.formUnion(tags)
        }
        fileTitles = titleMap
        fileTags = tagMap
        allTags = tagSet.sorted()
        if let sel = selectedTag, !tagSet.contains(sel) {
            selectedTag = nil
        }
    }

    private func metadataFor(_ url: URL) -> (title: String, tags: [String]) {
        let content = FileManager.default.readMeditation(at: url) ?? ""
        let meta = MeditationParser.parseMetadata(content)
        let title = meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
        return (title, meta.tags)
    }

    private func titleFor(_ url: URL) -> String {
        fileTitles[url] ?? metadataFor(url).title
    }

    private func playFile(_ url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let meditation = MeditationParser.parse(content)
        store.markMeditationPlayed(filename: url.deletingPathExtension().lastPathComponent)
        player.play(meditation, sourceURL: url)
    }

    private func editFile(_ url: URL) {
        editorContent = FileManager.default.readMeditation(at: url) ?? ""
        editorFilename = url.deletingPathExtension().lastPathComponent
        isNewFile = false
        showingEditor = true
    }

    private func editCopy(_ url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
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

        _ = FileManager.default.saveMeditation(content, filename: candidate)
        refreshFiles()

        // Open the editor on the new copy
        editorContent = content
        editorFilename = candidate
        isNewFile = false
        showingEditor = true
    }

    private func newFile() {
        editorContent = "# New Meditation\n\n"
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

    private func editTags(_ url: URL) {
        let (title, tags) = metadataFor(url)
        tagEditTarget = TagEditTarget(url: url, title: title, tags: tags)
    }

    private func saveTags(_ newTags: [String], for url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let (title, _) = metadataFor(url)
        let updated = MeditationMetadataWriter.rewrite(source: content, title: title, tags: newTags)
        let basename = url.deletingPathExtension().lastPathComponent
        let savedURL = FileManager.default.saveMeditation(updated, filename: basename)
        refreshFiles()
        if let savedURL, player.currentSourceURL == savedURL {
            player.stop()
        }
    }
}

private struct TagEditTarget: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let tags: [String]
}

private struct DisableScrollTouchDelay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            var current: UIView? = view.superview
            while let parent = current {
                if let scrollView = parent as? UIScrollView {
                    scrollView.delaysContentTouches = false
                    break
                }
                current = parent.superview
            }
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct MeditationRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MeditationRowPressContent(isPressed: configuration.isPressed, label: configuration.label)
    }
}

private struct MeditationRowPressContent: View {
    let isPressed: Bool
    let label: ButtonStyleConfiguration.Label
    @State private var showPressed = false

    var body: some View {
        label
            .scaleEffect(showPressed ? 0.97 : 1.0)
            .animation(showPressed ? .easeOut(duration: 0.1) : .spring(duration: 0.25, bounce: 0.4), value: showPressed)
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    showPressed = true
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        if !self.isPressed { showPressed = false }
                    }
                }
            }
    }
}

private struct PlayingPulseDot: View {
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 8, height: 8)
            .scaleEffect(pulse ? 1.3 : 0.9)
            .opacity(pulse ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
