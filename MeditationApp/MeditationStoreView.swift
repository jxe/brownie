import SwiftUI

/// Browse meditations other people shared and add them to the library.
struct MeditationStoreView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = MeditationStore.shared
    @State private var search = ""
    @State private var inLibrary: Set<String> = []

    private var filtered: [SharedMeditation] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.visibleMeditations }
        return store.visibleMeditations.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || item.authorName.localizedCaseInsensitiveContains(query)
                || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { item in
                NavigationLink(value: item) {
                    StoreRow(item: item, isInLibrary: inLibrary.contains(item.id))
                }
                .listRowBackground(Color.clear)
                .contextMenu {
                    ShareLink(item: MeditationStore.shareURL(for: item.id)) {
                        Label("Share Link…", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    StoreModerationButtons(item: item)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color("BackgroundColor"))
            .overlay { emptyState }
            .searchable(text: $search, prompt: "Title, tag or author")
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SharedMeditation.self) { item in
                StoreDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await store.refresh() }
            .task {
                inLibrary = store.recordsInLibrary()
                await store.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .meditationsDidChange)) { _ in
                inLibrary = store.recordsInLibrary()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if filtered.isEmpty {
            if store.isLoading && store.meditations.isEmpty {
                ProgressView()
            } else if let error = store.loadError, store.meditations.isEmpty {
                ContentUnavailableView("Store Unavailable", systemImage: "wifi.slash", description: Text(error))
            } else if !search.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ContentUnavailableView(
                    "Nothing Shared Yet",
                    systemImage: "books.vertical",
                    description: Text("Share one of your meditations from its menu in the list.")
                )
            }
        }
    }
}

private struct StoreRow: View {
    let item: SharedMeditation
    let isInLibrary: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(byline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isInLibrary {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("In your library")
            }
        }
        .padding(.vertical, 4)
    }

    private var byline: String {
        let tags = item.tags.map { "#\($0)" }.joined(separator: " ")
        let author = item.authorName.isEmpty ? "" : "by \(item.authorName)"
        return [author, tags].filter { !$0.isEmpty }.joined(separator: "  ")
    }
}

struct StoreDetailView: View {
    let item: SharedMeditation
    @Environment(\.dismiss) private var dismiss
    private let store = MeditationStore.shared
    @State private var isInLibrary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                    if !item.authorName.isEmpty {
                        Text("by \(item.authorName)")
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.body)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color("HighlightColor").opacity(0.3))
                    )
            }
            .padding()
        }
        .background(Color("BackgroundColor"))
        .safeAreaInset(edge: .bottom) {
            Button {
                if store.download(item) != nil {
                    isInLibrary = true
                }
            } label: {
                Label(isInLibrary ? "In Your Library" : "Add to Library",
                      systemImage: isInLibrary ? "checkmark" : "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isInLibrary)
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: MeditationStore.shareURL(for: item.id), subject: Text(item.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    StoreModerationButtons(item: item) { dismiss() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { isInLibrary = store.recordsInLibrary().contains(item.id) }
    }
}

/// A store meditation opened from a med.nxhx.org link.
struct StoreLinkView: View {
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var item: SharedMeditation?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let item {
                    StoreDetailView(item: item)
                } else if let errorMessage {
                    ContentUnavailableView("Can't Open Link", systemImage: "link", description: Text(errorMessage))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("BackgroundColor"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: id) {
            item = nil
            errorMessage = nil
            do {
                item = try await MeditationStore.shared.fetchMeditation(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Report and hide-author actions, for a context menu or a toolbar menu.
private struct StoreModerationButtons: View {
    let item: SharedMeditation
    var onHidden: () -> Void = {}
    private let store = MeditationStore.shared

    private static let reasons = ["Offensive or harmful", "Spam", "Copied without permission", "Something else"]

    var body: some View {
        Menu {
            ForEach(Self.reasons, id: \.self) { reason in
                Button(reason) {
                    Task {
                        // Hidden locally either way; a failed report is retried by reporting again.
                        try? await store.report(item, reason: reason)
                        onHidden()
                    }
                }
            }
        } label: {
            Label("Report…", systemImage: "exclamationmark.bubble")
        }
        if item.authorID != nil, !item.authorName.isEmpty {
            Button(role: .destructive) {
                store.hideAuthor(of: item)
                onHidden()
            } label: {
                Label("Hide Everything by \(item.authorName)", systemImage: "eye.slash")
            }
        }
    }
}

/// Share a library meditation to the store, update an earlier share, or take it down.
struct ShareToStoreView: View {
    let filename: String
    let title: String
    let content: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("storeAuthorName") private var authorName = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    private let store = MeditationStore.shared

    private var isShared: Bool { store.link(for: filename)?.role == .shared }
    private var trimmedName: String { authorName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title)
                        .fontWeight(.medium)
                }
                Section {
                    TextField("Your name", text: $authorName)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Shared by")
                } footer: {
                    Text("Anyone using Brownie can see and download it, with your name. Your era tags aren't shared.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                if isShared {
                    Section {
                        Button("Remove from Store", role: .destructive) {
                            run { try await store.unpublish(filename: filename) }
                        }
                        .disabled(isWorking)
                    }
                }
            }
            .navigationTitle(isShared ? "Update in Store" : "Share to Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(isShared ? "Update" : "Share") {
                            let name = trimmedName
                            authorName = name
                            run { try await store.publish(content: content, filename: filename, authorName: name) }
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await action()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
