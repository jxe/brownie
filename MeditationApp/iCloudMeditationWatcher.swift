import Foundation

/// Watches the iCloud Documents container for `.med` file changes and posts
/// `.meditationsDidChange` whenever files are added, removed, or updated.
/// Also triggers downloads for any non-current items so list views can read them.
final class iCloudMeditationWatcher {
    private var query: NSMetadataQuery?
    private var queryObservers: [NSObjectProtocol] = []
    private var storageObserver: NSObjectProtocol?
    private var iCloudIdentityObserver: NSObjectProtocol?

    func start() {
        guard storageObserver == nil else { return }
        storageObserver = NotificationCenter.default.addObserver(
            forName: .meditationStorageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartQuery()
        }
        iCloudIdentityObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restartQuery()
        }
        restartQuery()
    }

    private func restartQuery() {
        stopQuery()
        guard FileManager.default.meditationStorageIsCloudBacked,
              FileManager.default.meditationStorageIsAvailable else { return }

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE '*.med'", NSMetadataItemFSNameKey)
        switch FileManager.default.meditationStorageMode {
        case .local:
            return
        case .legacyICloud:
            q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        case .externalFolder:
            q.searchScopes = [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        }

        let gatherObs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q,
            queue: .main
        ) { [weak self] _ in
            self?.handleResults()
        }
        let updateObs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: q,
            queue: .main
        ) { [weak self] _ in
            self?.handleResults()
        }
        queryObservers = [gatherObs, updateObs]

        query = q
        q.enableUpdates()
        q.start()
    }

    func stop() {
        stopQuery()
        if let storageObserver {
            NotificationCenter.default.removeObserver(storageObserver)
            self.storageObserver = nil
        }
        if let iCloudIdentityObserver {
            NotificationCenter.default.removeObserver(iCloudIdentityObserver)
            self.iCloudIdentityObserver = nil
        }
    }

    private func stopQuery() {
        query?.stop()
        query = nil
        for obs in queryObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        queryObservers = []
    }

    private func handleResults() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        for item in q.results {
            guard let mdItem = item as? NSMetadataItem,
                  let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  isURL(url, inside: FileManager.default.meditationsDirectory) else { continue }
            let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        // Notify the UI to re-scan the directory. The player is intentionally NOT a subscriber:
        // metadata churn (sync state, download progress, attribute refreshes) must never reach
        // into in-flight playback. User-initiated edit/archive/save paths stop the player explicitly.
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
    }

    private func isURL(_ url: URL, inside directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        return urlPath == directoryPath || urlPath.hasPrefix(directoryPath + "/")
    }

    deinit {
        stop()
    }
}
