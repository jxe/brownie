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
                    rowView(for: url)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Brownie")
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

    @ViewBuilder
    private func rowView(for url: URL) -> some View {
        let isCurrent = player.currentSourceURL == url
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleFor(url))
                    .font(.body)
                if isCurrent && (player.isPlaying || player.elapsedSeconds > 0) {
                    Text(formatTime(player.elapsedSeconds))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(url.deletingPathExtension().lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            Spacer()

            Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.8))
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

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
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
