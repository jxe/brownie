import Foundation

/// Watches the iCloud Documents container for `.med` file changes and posts
/// `.meditationsDidChange` whenever files are added, removed, or updated.
/// Also triggers downloads for any non-current items so list views can read them.
final class iCloudMeditationWatcher {
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard query == nil else { return }
        guard FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.joeedelman.meditations") != nil else {
            return
        }

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE '*.med'", NSMetadataItemFSNameKey)
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        let gatherObs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: q,
            queue: .main
        ) { [weak self] _ in
            self?.handleResults(changedURLs: nil)
        }
        let updateObs = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: q,
            queue: .main
        ) { [weak self] note in
            let keys = [
                NSMetadataQueryUpdateChangedItemsKey,
                NSMetadataQueryUpdateAddedItemsKey,
                NSMetadataQueryUpdateRemovedItemsKey,
            ]
            var urls: [URL] = []
            for key in keys {
                guard let items = note.userInfo?[key] as? [NSMetadataItem] else { continue }
                for item in items {
                    if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                        urls.append(url)
                    }
                }
            }
            self?.handleResults(changedURLs: urls)
        }
        observers = [gatherObs, updateObs]

        query = q
        q.enableUpdates()
        q.start()
    }

    func stop() {
        query?.stop()
        query = nil
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers = []
    }

    private func handleResults(changedURLs: [URL]?) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        for item in q.results {
            guard let mdItem = item as? NSMetadataItem,
                  let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }

        NotificationCenter.default.post(name: .meditationsDidChange, object: changedURLs)
    }

    deinit {
        stop()
    }
}
