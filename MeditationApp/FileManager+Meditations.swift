import Foundation

enum MeditationStorageMode: String {
    case local
    case legacyICloud
    case externalFolder
}

private enum MeditationStorageKeys {
    static let mode = "meditationStorageModeV1"
    static let externalFolderBookmark = "meditationExternalFolderBookmarkV1"
    static let externalFolderName = "meditationExternalFolderNameV1"
}

private struct MeditationLibrarySnapshotItem {
    let relativePath: String
    let contents: String
}

private final class MeditationExternalFolderAccess {
    static let shared = MeditationExternalFolderAccess()

    private var activeBookmark: Data?
    private var activeURL: URL?

    var currentBookmark: Data? { activeBookmark }

    func resolve(_ bookmark: Data) -> URL? {
        if activeBookmark == bookmark, let activeURL {
            return activeURL
        }

        reset()

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else {
            return nil
        }

        activeBookmark = bookmark
        activeURL = url

        if isStale,
           let refreshedBookmark = try? url.bookmarkData(
               options: .minimalBookmark,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            activeBookmark = refreshedBookmark
            UserDefaults.standard.set(refreshedBookmark, forKey: MeditationStorageKeys.externalFolderBookmark)
        }

        return url
    }

    func reset() {
        if let activeURL {
            activeURL.stopAccessingSecurityScopedResource()
        }
        activeBookmark = nil
        activeURL = nil
    }

    deinit {
        reset()
    }
}

extension FileManager {
    /// Resolves the app's iCloud container, but only when an iCloud account is
    /// present. `ubiquityIdentityToken` is a cheap check; calling
    /// `url(forUbiquityContainerIdentifier:)` with no account spins up the
    /// iCloud daemon and floods the console with permission/account errors.
    var iCloudContainerURL: URL? {
        guard ubiquityIdentityToken != nil else { return nil }
        return url(forUbiquityContainerIdentifier: "iCloud.com.joeedelman.meditations")
    }

    var meditationStorageMode: MeditationStorageMode {
        guard let rawValue = UserDefaults.standard.string(forKey: MeditationStorageKeys.mode),
              let mode = MeditationStorageMode(rawValue: rawValue) else {
            return .local
        }
        return mode
    }

    var meditationStorageIsConfigured: Bool {
        UserDefaults.standard.string(forKey: MeditationStorageKeys.mode) != nil
    }

    var meditationStorageDisplayName: String {
        switch meditationStorageMode {
        case .local:
            return "On This iPhone"
        case .legacyICloud:
            return meditationStorageIsAvailable
                ? "Brownie in iCloud Drive"
                : "Brownie in iCloud Drive (Unavailable)"
        case .externalFolder:
            let name = UserDefaults.standard.string(forKey: MeditationStorageKeys.externalFolderName)
                ?? "Selected Folder"
            return meditationStorageIsAvailable ? name : "\(name) (Unavailable)"
        }
    }

    var meditationStorageIsCloudBacked: Bool {
        meditationStorageMode != .local
    }

    /// Establishes a durable storage choice for apps upgrading from the former
    /// automatic-iCloud behavior. A library already present in Brownie's iCloud
    /// container remains there; otherwise a genuinely new library starts locally.
    func configureInitialMeditationStorageIfNeeded() {
        guard !meditationStorageIsConfigured else { return }

        if let legacyDirectory = legacyICloudDocumentsDirectory(createIfNeeded: false),
           directoryContainsMeditations(legacyDirectory) {
            UserDefaults.standard.set(MeditationStorageMode.legacyICloud.rawValue, forKey: MeditationStorageKeys.mode)
            return
        }

        if directoryContainsMeditations(localMeditationsDirectory) {
            UserDefaults.standard.set(MeditationStorageMode.local.rawValue, forKey: MeditationStorageKeys.mode)
            return
        }

        // If an upgrading user's iCloud account is temporarily unavailable,
        // leave the decision unresolved and try again next launch. This avoids
        // seeding a parallel local library while their established library is hidden.
        if iCloudContainerURL == nil, hasExistingBrownieData {
            return
        }

        UserDefaults.standard.set(MeditationStorageMode.local.rawValue, forKey: MeditationStorageKeys.mode)
    }

    var meditationsDirectory: URL {
        let directory = resolvedMeditationsDirectory ?? localMeditationsDirectory
        if meditationStorageIsAvailable, !fileExists(atPath: directory.path) {
            try? createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    var meditationStorageIsAvailable: Bool {
        resolvedMeditationsDirectory != nil
    }

    private var resolvedMeditationsDirectory: URL? {
        switch meditationStorageMode {
        case .local:
            return localMeditationsDirectory
        case .legacyICloud:
            return legacyICloudDocumentsDirectory(createIfNeeded: true)
        case .externalFolder:
            if let bookmark = UserDefaults.standard.data(forKey: MeditationStorageKeys.externalFolderBookmark),
               let externalURL = MeditationExternalFolderAccess.shared.resolve(bookmark) {
                return externalURL
            }
            return nil
        }
    }

    private var localMeditationsDirectory: URL {
        let docs = urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Meditations", isDirectory: true)
    }

    private var hasExistingBrownieData: Bool {
        let documents = urls(for: .documentDirectory, in: .userDomainMask).first!
        if fileExists(atPath: documents.appendingPathComponent("emotion_journal.json").path) {
            return true
        }

        let defaults = UserDefaults.standard
        let legacyKeys = [
            "selectedTab",
            "selectedVoiceID",
            "speakingRate",
            "recentMeditationPlays",
            "meditationListeningHistory",
            "checkin_emotionCounts",
            "checkin_sessionTime",
        ]
        return legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private func legacyICloudDocumentsDirectory(createIfNeeded: Bool) -> URL? {
        guard let iCloudContainerURL else { return nil }
        let directory = iCloudContainerURL.appendingPathComponent("Documents", isDirectory: true)
        if createIfNeeded, !fileExists(atPath: directory.path) {
            try? createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func directoryContainsMeditations(_ directory: URL) -> Bool {
        guard let files = try? contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }
        return files.contains { $0.pathExtension == "med" }
    }

    /// Every meditation but the archived ones, from all the library's folders.
    func meditationFiles() -> [URL] {
        MeditationLibrary.shared.files(archived: false)
    }

    func archivedMeditationFiles() -> [URL] {
        MeditationLibrary.shared.files(archived: true)
    }

    func readMeditation(at url: URL) -> String? {
        // Coordinated read so iCloud downloads the latest content (if any) before we parse,
        // and so we play nicely with any other process / NSFilePresenter touching the file.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var readError: Error?
        var result: String?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                result = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } catch {
                readError = error
            }
        }
        if result == nil {
            // iCloud/account daemons can emit transient simulator diagnostics; log only when
            // Brownie actually cannot load the selected meditation text.
            if let readError {
                print("Brownie could not read \(url.lastPathComponent): \(readError.localizedDescription)")
            } else if let coordinationError {
                print("Brownie could not coordinate iCloud read for \(url.lastPathComponent): \(coordinationError.localizedDescription)")
            }
        }
        return result
    }

    /// Writes the meditation with this filename wherever it is, or, for a new one, into the
    /// current era's folder (and the library).
    func saveMeditation(_ content: String, filename: String) -> URL? {
        guard meditationStorageIsAvailable else { return nil }
        let name = filename.hasSuffix(".med") ? String(filename.dropLast(4)) : filename
        let library = MeditationLibrary.shared
        if let url = library.url(forName: name) {
            return writeMeditation(content, to: url) ? url : nil
        }
        guard let url = library.newFileURL(named: name), writeMeditation(content, to: url) else { return nil }
        library.registerNew(url)
        return url
    }

    private func writeMeditation(_ content: String, to url: URL) -> Bool {
        let parentDirectory = url.deletingLastPathComponent()
        if !fileExists(atPath: parentDirectory.path) {
            try? createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try content.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            print("Save coordination error: \(coordinationError)")
            return false
        }
        if let writeError {
            print("Save error: \(writeError)")
            return false
        }
        return true
    }

    func deleteMeditation(at url: URL) {
        guard meditationStorageIsAvailable else { return }
        MeditationLibrary.shared.delete(url)
    }

    @discardableResult
    func archiveMeditation(at url: URL) -> URL? {
        guard meditationStorageIsAvailable else { return nil }
        return MeditationLibrary.shared.archive(url)
    }

    @discardableResult
    func unarchiveMeditation(at url: URL) -> URL? {
        guard meditationStorageIsAvailable else { return nil }
        return MeditationLibrary.shared.unarchive(url)
    }

    func selectExternalMeditationFolder(
        bookmark: Data,
        displayName: String,
        copyCurrentLibrary: Bool
    ) throws {
        if copyCurrentLibrary, !meditationStorageIsAvailable {
            throw CocoaError(.fileReadNoPermission)
        }
        let snapshot = copyCurrentLibrary ? try meditationLibrarySnapshot() : []
        guard let destinationDirectory = MeditationExternalFolderAccess.shared.resolve(bookmark) else {
            throw CocoaError(.fileReadNoPermission)
        }

        if copyCurrentLibrary {
            try restoreMeditationLibrarySnapshot(snapshot, to: destinationDirectory)
        }

        let storedBookmark = MeditationExternalFolderAccess.shared.currentBookmark ?? bookmark
        UserDefaults.standard.set(storedBookmark, forKey: MeditationStorageKeys.externalFolderBookmark)
        UserDefaults.standard.set(displayName, forKey: MeditationStorageKeys.externalFolderName)
        UserDefaults.standard.set(MeditationStorageMode.externalFolder.rawValue, forKey: MeditationStorageKeys.mode)
        notifyMeditationStorageChanged()
    }

    func selectLocalMeditationFolder(copyCurrentLibrary: Bool) throws {
        if copyCurrentLibrary, !meditationStorageIsAvailable {
            throw CocoaError(.fileReadNoPermission)
        }
        let snapshot = copyCurrentLibrary ? try meditationLibrarySnapshot() : []

        if copyCurrentLibrary {
            try restoreMeditationLibrarySnapshot(snapshot, to: localMeditationsDirectory)
        }

        UserDefaults.standard.set(MeditationStorageMode.local.rawValue, forKey: MeditationStorageKeys.mode)
        MeditationExternalFolderAccess.shared.reset()
        notifyMeditationStorageChanged()
    }

    /// Every script in its folder, plus the library index and the eras, so a copy keeps
    /// which era each meditation is in and its listening stats.
    private func meditationLibrarySnapshot() throws -> [MeditationLibrarySnapshotItem] {
        MeditationLibrary.shared.sync()
        let root = meditationsDirectory
        var snapshot: [MeditationLibrarySnapshotItem] = []
        for url in meditationFiles() + archivedMeditationFiles() {
            guard let contents = readMeditation(at: url) else {
                throw CocoaError(.fileReadUnknown)
            }
            let folder = MeditationLibrary.folderName(of: url, root: root)
            snapshot.append(
                MeditationLibrarySnapshotItem(
                    relativePath: folder.isEmpty ? url.lastPathComponent : "\(folder)/\(url.lastPathComponent)",
                    contents: contents
                )
            )
        }
        for name in [MeditationLibrary.filename, EraIndex.filename] {
            if let contents = readMeditation(at: root.appendingPathComponent(name)) {
                snapshot.append(MeditationLibrarySnapshotItem(relativePath: name, contents: contents))
            }
        }
        return snapshot
    }

    private func restoreMeditationLibrarySnapshot(
        _ snapshot: [MeditationLibrarySnapshotItem],
        to destinationDirectory: URL
    ) throws {
        for item in snapshot {
            // An index or eras already there belong to that folder's own meditations.
            let isIndex = item.relativePath == MeditationLibrary.filename || item.relativePath == EraIndex.filename
            if isIndex, fileExists(atPath: destinationDirectory.appendingPathComponent(item.relativePath).path) {
                continue
            }
            let proposedURL = destinationDirectory.appendingPathComponent(item.relativePath)
            let destinationURL = availableCopyDestination(for: proposedURL, matching: item.contents)
            guard let destinationURL else { continue }
            guard writeMeditation(item.contents, to: destinationURL) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    /// Returns nil when an identical file is already present. Differing files
    /// keep both versions with a numeric suffix instead of overwriting either.
    private func availableCopyDestination(for proposedURL: URL, matching contents: String) -> URL? {
        guard fileExists(atPath: proposedURL.path) else { return proposedURL }
        if readMeditation(at: proposedURL) == contents { return nil }

        let basename = proposedURL.deletingPathExtension().lastPathComponent
        let pathExtension = proposedURL.pathExtension
        let directory = proposedURL.deletingLastPathComponent()
        var suffix = 1
        while true {
            let filename = "\(basename)-\(suffix).\(pathExtension)"
            let candidate = directory.appendingPathComponent(filename)
            if !fileExists(atPath: candidate.path) { return candidate }
            if readMeditation(at: candidate) == contents { return nil }
            suffix += 1
        }
    }

    private func notifyMeditationStorageChanged() {
        MeditationLibrary.shared.forget()
        NotificationCenter.default.post(name: .meditationStorageDidChange, object: nil)
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
    }
}
