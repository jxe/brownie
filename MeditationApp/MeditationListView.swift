import SwiftUI

struct MeditationListView: View {
    @EnvironmentObject var player: MeditationPlayer
    @State private var files: [URL] = []
    @State private var showingEditor = false
    @State private var editorContent = ""
    @State private var editorFilename = ""
    @State private var isNewFile = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(files, id: \.self) { url in
                    HStack {
                        Button {
                            editFile(url)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(titleFor(url))
                                    .font(.body)
                                Text(url.deletingPathExtension().lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .foregroundStyle(.primary)

                        Spacer()

                        Button {
                            if player.currentSourceURL == url {
                                player.togglePause()
                            } else {
                                playFile(url)
                            }
                        } label: {
                            Image(systemName: player.currentSourceURL == url && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.callout)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(player.currentSourceURL == url ? Color.accentColor : Color.accentColor.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, 4)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { deleteFile(url) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { duplicateFile(url) } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button { editFile(url) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button { duplicateFile(url) } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
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
            }
            .listStyle(.plain)
            .navigationTitle("Meditations")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newFile()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                MeditationEditorView(
                    content: $editorContent,
                    filename: $editorFilename,
                    isNew: isNewFile
                ) {
                    _ = FileManager.default.saveMeditation(editorContent, filename: editorFilename)
                    refreshFiles()
                }
            }
            .onAppear { refreshFiles() }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                refreshFiles()
            }
        }
    }

    private func refreshFiles() {
        files = FileManager.default.meditationFiles()
    }

    private func titleFor(_ url: URL) -> String {
        guard let content = FileManager.default.readMeditation(at: url) else {
            return url.deletingPathExtension().lastPathComponent
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let title = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { return title }
            }
        }
        return url.deletingPathExtension().lastPathComponent
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

    private func duplicateFile(_ url: URL) {
        guard let content = FileManager.default.readMeditation(at: url) else { return }
        let baseName = url.deletingPathExtension().lastPathComponent
        let newName = baseName + "-copy"
        _ = FileManager.default.saveMeditation(content, filename: newName)
        refreshFiles()
    }

    private func newFile() {
        editorContent = "# New Meditation\n\n"
        editorFilename = ""
        isNewFile = true
        showingEditor = true
    }

    private func deleteFile(_ url: URL) {
        FileManager.default.deleteMeditation(at: url)
        refreshFiles()
    }
}
