import CloudKit
import Foundation
import Observation

/// One meditation shared in the store: a `SharedMeditation` record in the public database.
struct SharedMeditation: Identifiable, Hashable {
    let id: String
    let title: String
    let tags: [String]
    let body: String
    let authorName: String
    /// The sharer's iCloud user record name, used to hide an author.
    let authorID: String?
    let modified: Date

    init?(record: CKRecord) {
        guard let body = record["body"] as? String else { return nil }
        id = record.recordID.recordName
        let title = (record["title"] as? String) ?? ""
        self.title = title.isEmpty ? "Untitled" : title
        tags = (record["tags"] as? [String]) ?? []
        self.body = body
        authorName = (record["authorName"] as? String) ?? ""
        authorID = record.creatorUserRecordID?.recordName
        modified = record.modificationDate ?? .distantPast
    }
}

/// What this device knows about a local file's place in the store.
struct StoreLink: Codable {
    enum Role: String, Codable {
        /// This person shared the file; sharing again updates their record.
        case shared
        /// Added from the store; a newer version from its author shows as an update.
        case downloaded
    }

    var recordName: String
    var role: Role
    /// The store version this file matches.
    var modified: Date
}

/// The shared meditation store, kept in Brownie's CloudKit public database.
///
/// The record types and their permissions are in `cloudkit/schema.ckdb`; `tools/cloudkit.sh` applies it.
/// Each shared meditation also has a web page at `shareURL(for:)`, served by `web/`.
@MainActor
@Observable
final class MeditationStore {
    static let shared = MeditationStore()

    static let containerIdentifier = "iCloud.com.joeedelman.meditations"
    static let webHost = "med.nxhx.org"
    private static let meditationType = "SharedMeditation"
    private static let featuredType = "Featured"
    private static let reportType = "Report"

    private static let linksKey = "storeLinksV1"
    private static let hiddenAuthorsKey = "storeHiddenAuthorsV1"
    private static let reportedKey = "storeReportedV1"

    private(set) var meditations: [SharedMeditation] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    /// Keyed by local filename (without extension): downloads whose author shared a newer version.
    private(set) var updates: [String: SharedMeditation] = [:]
    /// Keyed by local filename (without extension).
    private(set) var links: [String: StoreLink]
    private(set) var hiddenAuthors: Set<String>
    private(set) var reported: Set<String>
    /// A store item someone opened a link to, waiting to be shown.
    var openedLinkID: String?

    private var database: CKDatabase {
        CKContainer(identifier: Self.containerIdentifier).publicCloudDatabase
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.linksKey),
           let decoded = try? JSONDecoder().decode([String: StoreLink].self, from: data) {
            links = decoded
        } else {
            links = [:]
        }
        hiddenAuthors = Set(defaults.stringArray(forKey: Self.hiddenAuthorsKey) ?? [])
        reported = Set(defaults.stringArray(forKey: Self.reportedKey) ?? [])
    }

    /// The store minus what this person reported or whose author they hid.
    var visibleMeditations: [SharedMeditation] {
        meditations.filter { item in
            !reported.contains(item.id) && !(item.authorID.map(hiddenAuthors.contains) ?? false)
        }
    }

    func link(for filename: String) -> StoreLink? {
        links[filename]
    }

    /// Record names of store items that a file in the library (shared or downloaded) comes from.
    func recordsInLibrary() -> Set<String> {
        let localNames = Set(FileManager.default.meditationFiles().map { $0.deletingPathExtension().lastPathComponent })
        return Set(links.filter { localNames.contains($0.key) }.map(\.value.recordName))
    }

    // MARK: Links

    static func shareURL(for recordName: String) -> URL {
        URL(string: "https://\(webHost)/m/\(recordName)")!
    }

    /// The store item id in a `https://med.nxhx.org/m/<id>` or `brownie://m/<id>` link.
    static func recordName(from url: URL) -> String? {
        let isWeb = url.scheme == "https" && url.host == webHost
        let isApp = url.scheme == "brownie"
        guard isWeb || isApp else { return nil }
        // brownie://m/<id> puts "m" in the host; the web link puts it in the path.
        var parts = url.pathComponents.filter { $0 != "/" }
        if isApp, let host = url.host { parts.insert(host, at: 0) }
        guard parts.count == 2, parts[0] == "m" else { return nil }
        let id = parts[1].hasSuffix(".med") ? String(parts[1].dropLast(4)) : parts[1]
        return id.isEmpty ? nil : id
    }

    func fetchMeditation(id: String) async throws -> SharedMeditation {
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: id))
            guard let item = SharedMeditation(record: record) else {
                throw StoreError(message: "This link isn't a meditation.")
            }
            return item
        } catch let error as CKError where error.code == .unknownItem {
            throw StoreError(message: "This meditation is no longer in the store.")
        } catch let error as CKError {
            throw StoreError(message: Self.message(for: error))
        }
    }

    // MARK: Browsing

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let query = CKQuery(recordType: Self.meditationType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
            let (results, _) = try await database.records(matching: query, resultsLimit: 300)
            meditations = results.compactMap { try? $0.1.get() }.compactMap(SharedMeditation.init)
            loadError = nil
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// Saves a store meditation into the library as a new file. It joins the current era.
    @discardableResult
    func download(_ item: SharedMeditation) -> URL? {
        var content = item.body
        if let era = EraIndex.load().current {
            let meta = MeditationParser.parseMetadata(content)
            if !meta.tags.contains(era.tag) {
                content = MeditationMetadataWriter.rewrite(source: content, title: meta.title, tags: meta.tags + [era.tag])
            }
        }
        let filename = availableFilename(for: item.title)
        guard let url = FileManager.default.saveMeditation(content, filename: filename) else { return nil }
        links[filename] = StoreLink(recordName: item.id, role: .downloaded, modified: item.modified)
        saveLinks()
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
        return url
    }

    // MARK: Updates

    /// Looks up every downloaded file's store record and notes the ones with a newer version.
    func checkForUpdates() async {
        let downloads = links.filter { $0.value.role == .downloaded }
        guard !downloads.isEmpty else {
            updates = [:]
            return
        }
        let ids = downloads.map { CKRecord.ID(recordName: $0.value.recordName) }
        guard let results = try? await database.records(for: ids) else { return }
        var found: [String: SharedMeditation] = [:]
        for (filename, link) in downloads {
            guard let record = try? results[CKRecord.ID(recordName: link.recordName)]?.get(),
                  let item = SharedMeditation(record: record),
                  item.modified > link.modified else { continue }
            found[filename] = item
        }
        updates = found
    }

    /// Replaces a downloaded file with its author's newer version, keeping the file's own
    /// era and timeless tags.
    @discardableResult
    func applyUpdate(to filename: String) -> Bool {
        guard let item = updates[filename], var link = links[filename] else { return false }
        let localURL = FileManager.default.meditationFiles().first {
            $0.deletingPathExtension().lastPathComponent == filename
        }
        let localTags = localURL
            .flatMap { FileManager.default.readMeditation(at: $0) }
            .map { MeditationParser.parseMetadata($0).tags } ?? []
        let eras = EraIndex.load()
        let keptTags = localTags.filter { eras.isEraTag($0) || $0 == EraIndex.timelessTag }

        let meta = MeditationParser.parseMetadata(item.body)
        var content = item.body
        let mergedTags = meta.tags + keptTags.filter { !meta.tags.contains($0) }
        if mergedTags != meta.tags {
            content = MeditationMetadataWriter.rewrite(source: content, title: meta.title, tags: mergedTags)
        }
        guard FileManager.default.saveMeditation(content, filename: filename) != nil else { return false }

        link.modified = item.modified
        links[filename] = link
        saveLinks()
        updates.removeValue(forKey: filename)
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
        return true
    }

    // MARK: Sharing

    /// Shares a library file, or updates this person's earlier share of it.
    /// The sharer's era tags stay home; they mean nothing in someone else's library.
    func publish(content: String, filename: String, authorName: String) async throws {
        let eras = EraIndex.load()
        let meta = MeditationParser.parseMetadata(content)
        let tags = meta.tags.filter { !eras.isEraTag($0) }
        let body = tags == meta.tags
            ? content
            : MeditationMetadataWriter.rewrite(source: content, title: meta.title, tags: tags)

        var record = CKRecord(recordType: Self.meditationType)
        if let link = links[filename], link.role == .shared {
            do {
                record = try await database.record(for: CKRecord.ID(recordName: link.recordName))
            } catch let error as CKError where error.code == .unknownItem {
                // Removed from the store since; share it afresh.
            }
        }
        record["title"] = meta.title.isEmpty ? filename : meta.title
        record["tags"] = tags
        record["body"] = body
        record["authorName"] = authorName

        let saved: CKRecord
        do {
            saved = try await database.save(record)
        } catch {
            throw StoreError(message: Self.message(for: error))
        }
        links[filename] = StoreLink(recordName: saved.recordID.recordName, role: .shared, modified: saved.modificationDate ?? Date())
        saveLinks()
        if let item = SharedMeditation(record: saved) {
            meditations.removeAll { $0.id == item.id }
            meditations.insert(item, at: 0)
        }
    }

    func unpublish(filename: String) async throws {
        guard let link = links[filename], link.role == .shared else { return }
        do {
            _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: link.recordName))
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        } catch {
            throw StoreError(message: Self.message(for: error))
        }
        links.removeValue(forKey: filename)
        saveLinks()
        meditations.removeAll { $0.id == link.recordName }
    }

    // MARK: Moderation

    /// Files a report for Joe to review in the Dashboard, and hides the item here right away.
    func report(_ item: SharedMeditation, reason: String) async throws {
        let record = CKRecord(recordType: Self.reportType)
        record["meditation"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: item.id), action: .none)
        record["title"] = item.title
        record["reason"] = reason
        do {
            _ = try await database.save(record)
        } catch {
            throw StoreError(message: Self.message(for: error))
        }
        reported.insert(item.id)
        UserDefaults.standard.set(Array(reported), forKey: Self.reportedKey)
    }

    func hideAuthor(of item: SharedMeditation) {
        guard let authorID = item.authorID else { return }
        hiddenAuthors.insert(authorID)
        UserDefaults.standard.set(Array(hiddenAuthors), forKey: Self.hiddenAuthorsKey)
    }

    // MARK: Starters

    /// The meditations Joe featured, in the order he featured them.
    func fetchStarters() async throws -> [SharedMeditation] {
        let query = CKQuery(recordType: Self.featuredType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let (results, _) = try await database.records(matching: query, resultsLimit: 50)
        var ids: [CKRecord.ID] = []
        for case .success(let record) in results.map(\.1) {
            guard let name = record["meditationID"] as? String else { continue }
            let id = CKRecord.ID(recordName: name)
            if !ids.contains(id) { ids.append(id) }
        }
        guard !ids.isEmpty else { return [] }
        let records = try await database.records(for: ids)
        return ids
            .compactMap { try? records[$0]?.get() }
            .compactMap(SharedMeditation.init)
    }

    // MARK: Helpers

    private func saveLinks() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: Self.linksKey)
        }
    }

    /// A date-prefixed filename from the title, like the editor's new files, not yet in use.
    private func availableFilename(for title: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let base = "\(formatter.string(from: Date()))-\(slug.isEmpty ? "meditation" : slug)"
        let taken = Set(
            (FileManager.default.meditationFiles() + FileManager.default.archivedMeditationFiles())
                .map { $0.deletingPathExtension().lastPathComponent }
        )
        guard taken.contains(base) else { return base }
        var counter = 2
        while taken.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated:
            return "Sign in to iCloud in Settings to share."
        case .networkUnavailable, .networkFailure:
            return "Can't reach the store. Check your connection."
        case .permissionFailure:
            return "You can only change meditations you shared."
        default:
            return error.localizedDescription
        }
    }
}

struct StoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
