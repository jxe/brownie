import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(MeditationPlayer.self) var player
    @State private var isRefreshing = false
    @State private var metadataQuery: NSMetadataQuery?
    @State private var metadataObserver: NSObjectProtocol?
    @State private var showAllVoices = false
    @State private var showingFolderImporter = false
    @State private var pendingFolder: PendingMeditationFolder?
    @State private var showingFolderChoice = false
    @State private var showingLocalChoice = false
    @State private var storageErrorMessage = ""
    @State private var showingStorageError = false
    @State private var storageRevision = 0

    private var autoBinding: Binding<Bool> {
        Binding(
            get: { player.isAutoVoice },
            set: { newValue in
                if newValue {
                    player.selectedVoiceID = MeditationPlayer.autoVoiceID
                } else {
                    player.selectedVoiceID = MeditationPlayer.bestAutoVoice()?.identifier
                        ?? MeditationPlayer.availableVoices.first?.identifier
                        ?? player.selectedVoiceID
                    showAllVoices = true
                }
            }
        )
    }

    private var autoResolvedID: String? {
        MeditationPlayer.bestAutoVoice()?.identifier
    }

    var body: some View {
        @Bindable var player = player
        return List {
            Section("Speaking Rate") {
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $player.speakingRate, in: 0.3...0.6, step: 0.05)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
                Text(rateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                HStack {
                    Text("Current")
                    Spacer()
                    Text(player.resolvedVoiceDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Choose automatically", isOn: autoBinding)

                if !MeditationPlayer.hasGoodVoice {
                    VoiceQualityWarningView()
                }

                DisclosureGroup("Browse all voices", isExpanded: $showAllVoices) {
                    ForEach(groupedVoices, id: \.0) { section, voices in
                        Section(section) {
                            ForEach(voices, id: \.identifier) { voice in
                                Button {
                                    player.selectedVoiceID = voice.identifier
                                    preview(voice)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(voice.name)
                                                .foregroundStyle(.primary)
                                            Text(voice.language)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if player.isAutoVoice && voice.identifier == autoResolvedID {
                                            Text("Auto pick")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !player.isAutoVoice && voice.identifier == player.selectedVoiceID {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    showingFolderImporter = true
                } label: {
                    HStack {
                        Label("Folder", systemImage: "folder")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(storageDisplayName)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if storageMode != .local {
                    Button {
                        showingLocalChoice = true
                    } label: {
                        Label("Use On This iPhone", systemImage: "iphone")
                    }
                }

                if FileManager.default.meditationStorageIsCloudBacked,
                   FileManager.default.meditationStorageIsAvailable {
                    Button {
                        refreshFolder()
                    } label: {
                        HStack {
                            Label("Refresh Folder", systemImage: "arrow.clockwise.icloud")
                            if isRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                }
            } header: {
                Text("Meditation Folder")
            } footer: {
                Text("Choose an iCloud Drive folder if you want to edit meditation files on your Mac.")
            }

            Section {
                NavigationLink {
                    ArchivedMeditationsView()
                } label: {
                    Label("Archived Meditations", systemImage: "archivebox")
                }
            }

        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder]
        ) { result in
            handleFolderSelection(result)
        }
        .confirmationDialog(
            pendingFolder.map { "Use \($0.displayName) for meditations?" } ?? "Use selected folder?",
            isPresented: $showingFolderChoice,
            titleVisibility: .visible
        ) {
            Button("Copy Current Meditations") {
                usePendingFolder(copyCurrentLibrary: true)
            }
            Button("Use Without Copying") {
                usePendingFolder(copyCurrentLibrary: false)
            }
            Button("Cancel", role: .cancel) {
                pendingFolder = nil
            }
        } message: {
            Text("Copying keeps the current library where it is and adds non-conflicting copies to the selected folder.")
        }
        .confirmationDialog(
            "Use the meditation folder on this iPhone?",
            isPresented: $showingLocalChoice,
            titleVisibility: .visible
        ) {
            Button("Copy Current Meditations") {
                useLocalFolder(copyCurrentLibrary: true)
            }
            Button("Use Without Copying") {
                useLocalFolder(copyCurrentLibrary: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copying leaves the current synced folder unchanged and adds non-conflicting copies on this iPhone.")
        }
        .alert("Couldn’t Change Folder", isPresented: $showingStorageError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .meditationStorageDidChange)) { _ in
            storageRevision += 1
        }
    }

    private var storageMode: MeditationStorageMode {
        _ = storageRevision
        return FileManager.default.meditationStorageMode
    }

    private var storageDisplayName: String {
        _ = storageRevision
        return FileManager.default.meditationStorageDisplayName
    }

    private func handleFolderSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                throw CocoaError(.fileReadNoPermission)
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let bookmark = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            pendingFolder = PendingMeditationFolder(
                bookmark: bookmark,
                displayName: url.lastPathComponent
            )
            showingFolderChoice = true
        } catch {
            showStorageError(error)
        }
    }

    private func usePendingFolder(copyCurrentLibrary: Bool) {
        guard let pendingFolder else { return }
        do {
            try FileManager.default.selectExternalMeditationFolder(
                bookmark: pendingFolder.bookmark,
                displayName: pendingFolder.displayName,
                copyCurrentLibrary: copyCurrentLibrary
            )
            self.pendingFolder = nil
        } catch {
            showStorageError(error)
        }
    }

    private func useLocalFolder(copyCurrentLibrary: Bool) {
        do {
            try FileManager.default.selectLocalMeditationFolder(
                copyCurrentLibrary: copyCurrentLibrary
            )
        } catch {
            showStorageError(error)
        }
    }

    private func showStorageError(_ error: Error) {
        storageErrorMessage = error.localizedDescription
        showingStorageError = true
    }

    // MARK: - Voice grouping

    @State private var previewSynthesizer = AVSpeechSynthesizer()

    private var groupedVoices: [(String, [AVSpeechSynthesisVoice])] {
        let voices = MeditationPlayer.availableVoices
        var dict: [String: [AVSpeechSynthesisVoice]] = [:]
        for v in voices {
            let label = qualityLabel(v.quality)
            dict[label, default: []].append(v)
        }
        let order = ["Premium", "Enhanced", "Default"]
        return order.compactMap { key in
            guard let list = dict[key] else { return nil }
            return (key, list)
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    private func preview(_ voice: AVSpeechSynthesisVoice) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "This is how I sound.")
        utterance.voice = voice
        utterance.rate = player.speakingRate
        previewSynthesizer.speak(utterance)
    }

    private var rateLabel: String {
        let rate = player.speakingRate
        if rate <= 0.35 { return "Very Slow" }
        if rate <= 0.4 { return "Slow" }
        if rate <= 0.47 { return "Normal" }
        if rate <= 0.55 { return "Fast" }
        return "Very Fast"
    }

    // MARK: - Folder refresh

    private func refreshFolder() {
        guard !isRefreshing else { return }
        player.stop()

        guard FileManager.default.meditationStorageIsCloudBacked else {
            NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
            return
        }

        isRefreshing = true

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K LIKE '*.med'", NSMetadataItemFSNameKey)
        switch FileManager.default.meditationStorageMode {
        case .local:
            query.searchScopes = []
        case .legacyICloud:
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        case .externalFolder:
            query.searchScopes = [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        }

        // When query finishes gathering, download any non-current files
        if let metadataObserver {
            NotificationCenter.default.removeObserver(metadataObserver)
            self.metadataObserver = nil
        }
        metadataObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak query] _ in
            guard let query else { return }
            query.disableUpdates()

            for item in query.results {
                guard let mdItem = item as? NSMetadataItem,
                      let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
                      isURL(url, inside: FileManager.default.meditationsDirectory) else { continue }
                let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }

            query.stop()
            if let metadataObserver {
                NotificationCenter.default.removeObserver(metadataObserver)
                self.metadataObserver = nil
            }

            // Brief delay so downloads can begin before we reload the file list
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
                isRefreshing = false
            }
        }

        // Timeout after 10s in case the query never finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak query] in
            guard let query, query.isGathering else { return }
            query.stop()
            if let metadataObserver {
                NotificationCenter.default.removeObserver(metadataObserver)
                self.metadataObserver = nil
            }
            NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
            isRefreshing = false
        }

        metadataQuery = query
        query.start()
    }

    private func isURL(_ url: URL, inside directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        return urlPath == directoryPath || urlPath.hasPrefix(directoryPath + "/")
    }
}

private struct PendingMeditationFolder {
    let bookmark: Data
    let displayName: String
}

private struct VoiceQualityWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("No high-quality voices installed")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Meditations will sound robotic until you install a Premium or Enhanced voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open iOS **Settings → Accessibility → Spoken Content → Voices → English**, then tap a voice marked *Enhanced* or *Premium* to download it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
    static let meditationStorageDidChange = Notification.Name("meditationStorageDidChange")
}
