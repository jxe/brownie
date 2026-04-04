import SwiftUI

struct MeditationListView: View {
    @EnvironmentObject var player: MeditationPlayer
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

    private var filteredFiles: [URL] {
        guard let tag = selectedTag else { return files }
        return files.filter { fileTags[$0]?.contains(tag) == true }
    }
    var body: some View {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    if !allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(allTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedTag == tag ? Color.accentColor : Color(.systemGray5))
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
                    }
                    List {
                        ForEach(filteredFiles, id: \.self) { url in
                        rowView(for: url)
                            .listRowBackground(
                                player.currentSourceURL == url && player.isPlaying
                                    ? Color("HighlightColor")
                                    : Color("BackgroundColor")
                            )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                }

                Button {
                    newFile()
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(radius: 4, y: 2)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 0)
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .navigationTitle("Meditations")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
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
            .background(Color("BackgroundColor"))
            .onAppear { refreshFiles() }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                refreshFiles()
            }
    }

    @ViewBuilder
    private func rowView(for url: URL) -> some View {
        let isCurrent = player.currentSourceURL == url
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleFor(url))
                    .font(.body)
                    .fontWeight(.medium)
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
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            Spacer()

            Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor)
                .clipShape(Circle())
                .padding(.trailing, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isCurrent {
                player.togglePause()
            } else {
                playFile(url)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleteFile(url) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { editFile(url) } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accentColor)
            Button { editCopy(url) } label: {
                Label("Edit a Copy", systemImage: "doc.badge.plus")
            }
            .tint(.indigo)
        }
        .contextMenu {
            Button { editFile(url) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button { editCopy(url) } label: {
                Label("Edit a Copy", systemImage: "doc.badge.plus")
            }
            Button { playFile(url) } label: {
                Label("Play", systemImage: "play")
            }
            Divider()
            Button(role: .destructive) { deleteFile(url) } label: {
                Label("Delete", systemImage: "trash")
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
            let (title, tags) = parseTitleAndTags(url)
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

    private func parseTitleAndTags(_ url: URL) -> (title: String, tags: [String]) {
        guard let content = FileManager.default.readMeditation(at: url) else {
            return (url.deletingPathExtension().lastPathComponent, [])
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let after = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if after.isEmpty { continue }
                // Extract #tags from end of line
                var tags: [String] = []
                var titleParts: [String] = []
                let words = after.components(separatedBy: .whitespaces)
                var foundTags = false
                for word in words.reversed() {
                    if word.hasPrefix("#") && word.count > 1 {
                        tags.insert(String(word.dropFirst()), at: 0)
                        foundTags = true
                    } else if foundTags {
                        titleParts.insert(word, at: 0)
                    } else {
                        titleParts.insert(word, at: 0)
                    }
                }
                let title = titleParts.joined(separator: " ")
                return (title.isEmpty ? url.deletingPathExtension().lastPathComponent : title, tags)
            }
        }
        return (url.deletingPathExtension().lastPathComponent, [])
    }

    private func titleFor(_ url: URL) -> String {
        fileTitles[url] ?? parseTitleAndTags(url).title
    }

    private func playFile(_ url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let meditation = MeditationParser.parse(content)
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
}
