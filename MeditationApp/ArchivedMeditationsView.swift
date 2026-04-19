import SwiftUI

struct ArchivedMeditationsView: View {
    @State private var files: [URL] = []
    @State private var pendingDelete: URL? = nil

    var body: some View {
        List {
            if files.isEmpty {
                Text("No archived meditations")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(files, id: \.self) { url in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titleFor(url))
                            .font(.body)
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = url
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            unarchive(url)
                        } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .navigationTitle("Archived")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
            reload()
        }
        .confirmationDialog(
            "Delete this meditation permanently?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let url = pendingDelete {
                Button("Delete", role: .destructive) { deletePermanently(url) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func reload() {
        files = FileManager.default.archivedMeditationFiles()
    }

    private func titleFor(_ url: URL) -> String {
        let content = FileManager.default.readMeditation(at: url) ?? ""
        let meta = MeditationParser.parseMetadata(content)
        return meta.title.isEmpty ? url.deletingPathExtension().lastPathComponent : meta.title
    }

    private func unarchive(_ url: URL) {
        _ = FileManager.default.unarchiveMeditation(at: url)
        reload()
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
    }

    private func deletePermanently(_ url: URL) {
        FileManager.default.deleteMeditation(at: url)
        pendingDelete = nil
        reload()
    }
}
