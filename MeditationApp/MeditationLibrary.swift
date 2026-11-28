import Foundation

/// One meditation in `library.json`.
struct LibraryEntry: Codable, Equatable {
    /// Never changes, whatever the file is renamed to or wherever it moves. Listening stats,
    /// store links and journal entries know a meditation by this. A meditation that was
    /// already here when the library was first indexed keeps its filename from then as its id,
    /// so what was keyed by filename before still finds it.
    var id: String
    /// The file's name on disk, without `.med`. Unique across all folders.
    var name: String
    /// The folder it was last seen in, relative to the library: an era's folder, `Evergreen`,
    /// `Archive`, `Older`, or "" for the top.
    var folder: String
    /// Every era it belongs to (era ids), not just the one whose folder it's in.
    var eras: [String]
    /// `yyyy-MM-dd`, the day it was made.
    var made: String
}

private struct LibraryFile: Codable {
    var version = 1
    var meditations: [LibraryEntry]
}

/// Where each meditation lives, and what it belongs to.
///
/// The folder a script is in says where it shows up:
/// - an era's folder, named by the day the era started (`2026-11-21/`): the most recent era it
///   belongs to, so the newest era's folder holds what that era's section shows;
/// - `Evergreen/`: shown in every era;
/// - `Archive/`: put away;
/// - `Older/`: made before the first era and never brought along to one.
///
/// `library.json` keeps what a folder can't say: each meditation's stable id, the day it was
/// made, and every era it belongs to (a meditation brought along to a later era still belongs
/// to the one it came from). Bringing one along, making it Evergreen or archiving it moves its
/// file. A script the app hasn't seen before (added on the Mac, say) gets an id and joins the
/// era of the folder it's in; one dropped at the top joins the current era.
final class MeditationLibrary {
    static let shared = MeditationLibrary {
        FileManager.default.meditationStorageIsAvailable ? FileManager.default.meditationsDirectory : nil
    }

    static let filename = "library.json"
    static let evergreenFolder = "Evergreen"
    static let archiveFolder = "Archive"
    static let olderFolder = "Older"
    /// A copy of the old flat folder, made once before it's sorted into folders.
    static let backupFolder = "Before Folders"

    /// Called after a file moves (from, to), so whatever holds its URL (the player) can follow.
    var onMove: ((URL, URL) -> Void)?

    private let rootProvider: () -> URL?
    private let lock = NSRecursiveLock()
    private var entries: [String: LibraryEntry] = [:]
    private var idByName: [String: String] = [:]
    private var loadedRoot: URL?
    /// Set when `library.json` exists but can't be read (a sync conflict mid-write, say). Then
    /// nothing is moved or written until it reads again, so it's never written over.
    private var unreadable = false

    init(root: @escaping () -> URL?) {
        rootProvider = root
    }

    // MARK: Lookups

    /// The meditation's stable id; its filename for one the library hasn't indexed yet.
    func id(for url: URL) -> String {
        id(forName: Self.name(of: url))
    }

    func id(forName name: String) -> String {
        cached { idByName[name] ?? name }
    }

    /// Where the meditation with this id is now, if the library knows it.
    func url(forID id: String) -> URL? {
        locked { root in
            guard let root, let entry = entries[id] else { return nil }
            return Self.fileURL(root, entry.folder, entry.name)
        }
    }

    /// Where the file with this name is: where the library has it, else wherever it turns up.
    func url(forName name: String) -> URL? {
        locked { root in
            guard let root else { return nil }
            if let id = idByName[name], let entry = entries[id] {
                return Self.fileURL(root, entry.folder, entry.name)
            }
            let eras = EraIndex.load(in: root)
            return scan(root, eras: eras).files.first { $0.name == name }?.url
        }
    }

    /// Whether some meditation, here or in any folder, already has this name.
    func isNameTaken(_ name: String) -> Bool {
        locked { root in
            guard let root else { return false }
            if idByName[name] != nil { return true }
            let eras = EraIndex.load(in: root)
            let found = scan(root, eras: eras)
            return (found.files + found.placeholders).contains { $0.name == name }
        }
    }

    /// The eras it belongs to (ids). One not indexed yet belongs to its folder's era.
    func eras(of url: URL) -> [String] {
        if let known = cached({ idByName[Self.name(of: url)].flatMap { entries[$0]?.eras } }) { return known }
        return locked { root in
            guard let root else { return [] }
            return EraIndex.load(in: root).era(inFolder: Self.folderName(of: url, root: root)).map { [$0.id] } ?? []
        }
    }

    /// The `yyyy-MM-dd` day it was made, if the library knows it.
    func made(of url: URL) -> String? {
        cached { idByName[Self.name(of: url)].flatMap { entries[$0]?.made } }
    }

    static func isEvergreen(_ url: URL) -> Bool {
        url.deletingLastPathComponent().lastPathComponent == evergreenFolder
    }

    /// Every meditation on disk: all but the archived ones, or only those.
    func files(archived: Bool) -> [URL] {
        locked { root in
            guard let root else { return [] }
            return scan(root, eras: EraIndex.load(in: root)).files
                .filter { ($0.folder == Self.archiveFolder) == archived }
                .map(\.url)
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        }
    }

    // MARK: Changes

    /// Where a new meditation called `name` goes: the current era's folder, or the top when
    /// there are no eras.
    func newFileURL(named name: String) -> URL? {
        locked { root in
            guard let root else { return nil }
            let eras = EraIndex.load(in: root)
            let folder = eras.current.flatMap { eras.folder(for: $0.id) } ?? ""
            return Self.fileURL(root, folder, name)
        }
    }

    /// Adds a file the app just wrote.
    func registerNew(_ url: URL) {
        locked { root in
            guard let root, read(root), idByName[Self.name(of: url)] == nil else { return }
            let eras = EraIndex.load(in: root)
            let folder = Self.folderName(of: url, root: root)
            add(newEntry(name: Self.name(of: url), folder: folder, url: url, eras: eras))
            write(root)
        }
    }

    /// Brings a meditation from an earlier era into the current one: it moves to the current
    /// era's folder, and still belongs to the eras it came from.
    func bringAlong(_ url: URL) {
        change(url) { entry, eras in
            guard let current = eras.current, !entry.eras.contains(current.id) else { return nil }
            entry.eras.append(current.id)
            return eras.folder(for: current.id)
        }
    }

    /// Undoes bringing it along: back to the latest era it came from (or `Older`).
    func sendBack(_ url: URL) {
        change(url) { entry, eras in
            guard let current = eras.current, entry.eras.contains(current.id) else { return nil }
            entry.eras.removeAll { $0 == current.id }
            return self.placement(entry, eras: eras)
        }
    }

    /// Into `Evergreen`, or out of it to the latest era it belongs to.
    func setEvergreen(_ url: URL, _ on: Bool) {
        change(url) { entry, eras in
            on ? Self.evergreenFolder : self.placement(entry, eras: eras)
        }
    }

    @discardableResult
    func archive(_ url: URL) -> URL? {
        change(url) { _, _ in Self.archiveFolder }
    }

    /// Out of the archive, to the latest era it belongs to.
    @discardableResult
    func unarchive(_ url: URL) -> URL? {
        change(url) { entry, eras in self.placement(entry, eras: eras) }
    }

    /// Renames the file where it is. Its id, and so its stats and links, stay as they were.
    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        locked { root in
            guard let root, read(root) else { return nil }
            let oldName = Self.name(of: url)
            guard newName != oldName else { return url }
            let eras = EraIndex.load(in: root)
            if idByName[oldName] == nil {
                add(newEntry(name: oldName, folder: Self.folderName(of: url, root: root), url: url, eras: eras))
            }
            guard let id = idByName[oldName], var entry = entries[id] else { return nil }
            let folder = Self.folderName(of: url, root: root)
            let target = Self.fileURL(root, folder, newName)
            guard move(url, to: target) else { return nil }
            idByName[oldName] = nil
            entry.name = newName
            entry.folder = folder
            add(entry)
            write(root)
            return target
        }
    }

    func delete(_ url: URL) {
        locked { root in
            guard let root else { return }
            try? FileManager.default.removeItem(at: url)
            guard read(root), let id = idByName[Self.name(of: url)] else { return }
            idByName[Self.name(of: url)] = nil
            entries[id] = nil
            write(root)
        }
    }

    /// Moves the meditation to the folder `decide` picks after changing its entry; nil leaves
    /// it as it was. Returns where the file is now.
    @discardableResult
    private func change(_ url: URL, _ decide: (inout LibraryEntry, EraIndex) -> String?) -> URL? {
        locked { root in
            guard let root, read(root) else { return nil }
            let eras = EraIndex.load(in: root)
            let name = Self.name(of: url)
            if idByName[name] == nil {
                add(newEntry(name: name, folder: Self.folderName(of: url, root: root), url: url, eras: eras))
            }
            guard let id = idByName[name], var entry = entries[id] else { return nil }
            guard let folder = decide(&entry, eras) else { return url }
            let target = Self.fileURL(root, folder, entry.name)
            if target.standardizedFileURL.path != url.standardizedFileURL.path {
                guard move(url, to: target) else { return nil }
            }
            entry.folder = folder
            add(entry)
            write(root)
            return target
        }
    }

    // MARK: Sync

    /// Brings `library.json` and the folders into line: indexes scripts it hasn't seen, files
    /// any left at the top, notices ones moved between folders on the Mac, and renames a
    /// script whose name another one already has. The first time, it sorts the old flat
    /// folder into folders (after copying it to `Before Folders`). Call before listing.
    func sync() {
        locked { root in
            guard let root else { return }
            let fm = FileManager.default
            let indexURL = root.appendingPathComponent(Self.filename)
            // Without the eras, folders can't be told apart: wait for them to download.
            let erasURL = root.appendingPathComponent(EraIndex.filename)
            if !fm.fileExists(atPath: erasURL.path),
               fm.fileExists(atPath: root.appendingPathComponent(".\(EraIndex.filename).icloud").path) {
                try? fm.startDownloadingUbiquitousItem(at: erasURL)
                return
            }
            let eras = EraIndex.load(in: root)
            if fm.fileExists(atPath: indexURL.path) {
                guard read(root) else { return }
            } else {
                // Not downloaded yet: wait for it rather than starting a second index.
                let placeholder = root.appendingPathComponent(".\(Self.filename).icloud")
                if fm.fileExists(atPath: placeholder.path) {
                    try? fm.startDownloadingUbiquitousItem(at: indexURL)
                    return
                }
                guard migrateFlatFolder(root, eras: eras) else { return }
            }
            reconcile(root, eras: eras)
        }
    }

    private func reconcile(_ root: URL, eras: EraIndex) {
        let found = scan(root, eras: eras)
        var changed = false
        // Placeholders aren't counted: one can linger where a file was while it moves.
        var seen = Set<String>()
        // Where a name turns up twice, the copy where the library has it keeps it.
        let ordered = found.files.enumerated().sorted { a, b in
            func rank(_ f: Found) -> Int {
                guard let id = idByName[f.name], let entry = entries[id] else { return 1 }
                return entry.folder == f.folder ? 0 : 1
            }
            let (ra, rb) = (rank(a.element), rank(b.element))
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)

        for original in ordered {
            var file = original
            if seen.contains(file.name) {
                let free = freeName(file.name, root: root, eras: eras, also: seen)
                let target = Self.fileURL(root, file.folder, free)
                guard move(file.url, to: target) else { continue }
                file = Found(folder: file.folder, name: free, url: target)
                // A new file under its new name, not the meditation the name belonged to.
            }
            seen.insert(file.name)

            if original.name == file.name, let id = idByName[file.name], var entry = entries[id] {
                if file.folder == entry.folder {
                    // At the top only while there are no eras; once there are, it gets a folder.
                    guard file.folder.isEmpty, eras.current != nil else { continue }
                    let target = placement(entry, eras: eras)
                    guard move(file.url, to: Self.fileURL(root, target, entry.name)) else { continue }
                    entry.folder = target
                } else if file.folder.isEmpty {
                    // Left at the top by an interrupted move: finish it.
                    let target = isFolder(entry.folder, eras: eras) && !entry.folder.isEmpty
                        ? entry.folder : placement(entry, eras: eras)
                    guard target != file.folder,
                          move(file.url, to: Self.fileURL(root, target, entry.name)) else { continue }
                    entry.folder = target
                } else {
                    // Moved to another folder (on the Mac, or by another device): that's where it is now.
                    entry.folder = file.folder
                    if let era = eras.era(inFolder: file.folder) {
                        // In an era's folder: that's its latest era.
                        entry.eras = entry.eras.filter { id in
                            eras.era(id).map { $0.started <= era.started } ?? false
                        }
                        if !entry.eras.contains(era.id) { entry.eras.append(era.id) }
                    } else if file.folder == Self.olderFolder {
                        entry.eras = []
                    }
                }
                add(entry)
                changed = true
            } else {
                // New to the library. At the top, it joins the current era.
                var entry = newEntry(name: file.name, folder: file.folder, url: file.url, eras: eras)
                if file.folder.isEmpty, let current = eras.current, let folder = eras.folder(for: current.id) {
                    let target = Self.fileURL(root, folder, file.name)
                    if move(file.url, to: target) { entry.folder = folder }
                }
                add(entry)
                changed = true
            }
        }
        if changed { write(root) }
    }

    /// The first run with folders: the old flat folder (scripts at the top, `Archive/`, era
    /// membership in `eras.json`'s `kept` lists and old era tags, Evergreen as a `#timeless`
    /// tag) becomes an index and folders. Waits while any script there isn't downloaded yet.
    private func migrateFlatFolder(_ root: URL, eras: EraIndex) -> Bool {
        let fm = FileManager.default
        let found = scan(root, eras: eras)
        let flat = found.files.filter { $0.folder.isEmpty || $0.folder == Self.archiveFolder }
        let waiting = found.placeholders.filter { $0.folder.isEmpty || $0.folder == Self.archiveFolder }
        if !waiting.isEmpty {
            for file in waiting { try? fm.startDownloadingUbiquitousItem(at: file.url) }
            return false
        }

        if !flat.isEmpty {
            // A copy of everything as it was, once.
            let backup = root.appendingPathComponent(Self.backupFolder, isDirectory: true)
            if !fm.fileExists(atPath: backup.path) {
                do {
                    try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                    for file in flat {
                        let dir = file.folder.isEmpty ? backup : backup.appendingPathComponent(file.folder, isDirectory: true)
                        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                        try fm.copyItem(at: file.url, to: dir.appendingPathComponent(file.url.lastPathComponent))
                    }
                    let erasFile = root.appendingPathComponent(EraIndex.filename)
                    if fm.fileExists(atPath: erasFile.path) {
                        try fm.copyItem(at: erasFile, to: backup.appendingPathComponent(EraIndex.filename))
                    }
                } catch {
                    print("Brownie could not back up the library before sorting it into folders: \(error)")
                    return false
                }
            }
        }

        let legacyTags = Dictionary(eras.eras.compactMap { era in era.legacyTag.map { ($0, era.id) } },
                                    uniquingKeysWith: { first, _ in first })
        var moves: [(from: URL, to: URL)] = []
        var names = Set<String>()
        // Live ones first, so a name in both keeps the live one's id.
        for file in flat.sorted(by: { $0.folder.isEmpty && !$1.folder.isEmpty }) {
            var name = file.name
            if names.contains(name) {
                var n = 2
                while names.contains("\(file.name)-\(n)") || fm.fileExists(atPath: Self.fileURL(root, file.folder, "\(file.name)-\(n)").path) { n += 1 }
                name = "\(file.name)-\(n)"
            }
            names.insert(name)
            let tags = Self.headerTags(FileManager.default.readMeditation(at: file.url) ?? "")
            let made = Self.madeDay(name: file.name, url: file.url)
            var member: [String] = []
            if let era = eras.eras.first(where: { $0.started <= made }) { member.append(era.id) }
            for era in eras.eras where era.kept.contains(file.name) || era.legacyTag.map({ tags.contains($0) }) == true {
                if !member.contains(era.id) { member.append(era.id) }
            }
            for tag in tags { if let id = legacyTags[tag], !member.contains(id) { member.append(id) } }
            var entry = LibraryEntry(id: name, name: name, folder: file.folder, eras: member, made: made)
            if file.folder.isEmpty {
                entry.folder = tags.contains(EraIndex.timelessTag) ? Self.evergreenFolder : placement(entry, eras: eras)
            }
            add(entry)
            let target = Self.fileURL(root, entry.folder, name)
            if target.path != file.url.path { moves.append((file.url, target)) }
        }
        // The index first: if the moves are cut short, the next sync finishes them.
        write(root, creating: true)
        for (from, to) in moves { _ = move(from, to: to) }
        return true
    }

    // MARK: Placement

    /// Where a meditation that isn't Evergreen or archived goes: the latest era it belongs to,
    /// else `Older`, or the top when there are no eras.
    private func placement(_ entry: LibraryEntry, eras: EraIndex) -> String {
        if let latest = eras.eras.first(where: { entry.eras.contains($0.id) }),
           let folder = eras.folder(for: latest.id) {
            return folder
        }
        return eras.eras.isEmpty ? "" : Self.olderFolder
    }

    /// The top, or one of the library's own folders. A dated folder with no era (yet: its
    /// era's record may still be on its way from another device) counts too.
    private func isFolder(_ folder: String, eras: EraIndex) -> Bool {
        folder.isEmpty || [Self.evergreenFolder, Self.archiveFolder, Self.olderFolder].contains(folder)
            || eras.era(inFolder: folder) != nil
            || folder.range(of: #"^\d{4}-\d{2}-\d{2}(-\d+)?$"#, options: .regularExpression) != nil
    }

    private func newEntry(name: String, folder: String, url: URL, eras: EraIndex) -> LibraryEntry {
        let made = Self.madeDay(name: name, url: url)
        var member: [String] = []
        if let era = eras.era(inFolder: folder) {
            member = [era.id]
        } else if folder.isEmpty, let current = eras.current {
            member = [current.id]
        } else if folder == Self.evergreenFolder || folder == Self.archiveFolder,
                  let era = eras.eras.first(where: { $0.started <= made }) {
            member = [era.id]
        }
        let id = entries[name] == nil ? name : UUID().uuidString
        return LibraryEntry(id: id, name: name, folder: folder, eras: member, made: made)
    }

    private func freeName(_ name: String, root: URL, eras: EraIndex, also taken: Set<String>) -> String {
        var n = 2
        while taken.contains("\(name)-\(n)") || isNameTaken("\(name)-\(n)") { n += 1 }
        return "\(name)-\(n)"
    }

    // MARK: Disk

    private struct Found {
        let folder: String
        let name: String
        let url: URL
    }

    /// The scripts at the top and in the library's folders (era folders, Evergreen, Archive,
    /// Older), and the iCloud placeholders of ones not downloaded yet. Other folders (the
    /// backup, any of your own) are left alone.
    private func scan(_ root: URL, eras: EraIndex) -> (files: [Found], placeholders: [Found]) {
        let fm = FileManager.default
        var folders = [""]
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let name = item.lastPathComponent
                if name != Self.backupFolder, isFolder(name, eras: eras) { folders.append(name) }
            }
        }
        var files: [Found] = []
        var placeholders: [Found] = []
        for folder in folders {
            let dir = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
            guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for item in items {
                if item.hasSuffix(".med"), !item.hasPrefix(".") {
                    let name = String(item.dropLast(4))
                    files.append(Found(folder: folder, name: name, url: dir.appendingPathComponent(item)))
                } else if item.hasPrefix("."), item.hasSuffix(".med.icloud") {
                    let name = String(item.dropFirst().dropLast(".med.icloud".count))
                    placeholders.append(Found(folder: folder, name: name, url: dir.appendingPathComponent("\(name).med")))
                }
            }
        }
        return (files, placeholders)
    }

    private func move(_ from: URL, to: URL) -> Bool {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: to.path) else {
            print("Brownie did not move \(from.lastPathComponent): \(to.path) is taken")
            return false
        }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var moved = false
        coordinator.coordinate(writingItemAt: from, options: .forMoving,
                               writingItemAt: to, options: .forReplacing,
                               error: &coordinationError) { source, destination in
            do {
                coordinator.item(at: source, willMoveTo: destination)
                try fm.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
                moved = true
            } catch {
                print("Brownie could not move \(from.lastPathComponent): \(error)")
            }
        }
        if let coordinationError { print("Brownie could not move \(from.lastPathComponent): \(coordinationError)") }
        if moved { onMove?(from, to) }
        return moved
    }

    /// Drops what's loaded, for when the library moves to another folder.
    func forget() {
        lock.lock()
        defer { lock.unlock() }
        loadedRoot = nil
        entries = [:]
        idByName = [:]
        unreadable = false
    }

    private func ensureLoaded(_ root: URL) {
        guard loadedRoot?.path != root.path else { return }
        entries = [:]
        idByName = [:]
        unreadable = false
        loadedRoot = root
        _ = read(root)
    }

    /// Reads `library.json` afresh. False if it's there but can't be read.
    @discardableResult
    private func read(_ root: URL) -> Bool {
        let url = root.appendingPathComponent(Self.filename)
        loadedRoot = root
        guard FileManager.default.fileExists(atPath: url.path) else {
            unreadable = false
            return true
        }
        var data: Data?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            data = try? Data(contentsOf: $0)
        }
        guard let data, let file = try? JSONDecoder().decode(LibraryFile.self, from: data) else {
            print("Brownie could not read \(Self.filename)")
            unreadable = true
            return false
        }
        unreadable = false
        entries = [:]
        idByName = [:]
        for entry in file.meditations { add(entry) }
        return true
    }

    /// Only `creating` (sorting the old flat folder) starts a new `library.json`: anything
    /// else writing one first would leave an index of a few meditations, and the flat
    /// folder would never be sorted.
    private func write(_ root: URL, creating: Bool = false) {
        guard !unreadable else { return }
        let url = root.appendingPathComponent(Self.filename)
        guard creating || FileManager.default.fileExists(atPath: url.path) else { return }
        let sorted = entries.values.sorted { ($0.folder, $0.name) < ($1.folder, $1.name) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(LibraryFile(meditations: sorted)) else { return }
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            do { try data.write(to: $0, options: .atomic) } catch { print("Brownie could not save \(Self.filename): \(error)") }
        }
        if let coordinationError { print("Brownie could not save \(Self.filename): \(coordinationError)") }
    }

    private func add(_ entry: LibraryEntry) {
        if let old = entries[entry.id], old.name != entry.name, idByName[old.name] == entry.id {
            idByName[old.name] = nil
        }
        entries[entry.id] = entry
        idByName[entry.name] = entry.id
    }

    /// Reads the index as last loaded, without looking up the storage location (in iCloud
    /// that's slow, and rows ask for ids as they draw).
    private func cached<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        if loadedRoot == nil, let root = rootProvider() { ensureLoaded(root) }
        return body()
    }

    private func locked<T>(_ body: (URL?) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let root = rootProvider()
        if let root { ensureLoaded(root) }
        return body(root)
    }

    // MARK: Helpers

    static func name(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func fileURL(_ root: URL, _ folder: String, _ name: String) -> URL {
        let dir = folder.isEmpty ? root : root.appendingPathComponent(folder, isDirectory: true)
        return dir.appendingPathComponent("\(name).med")
    }

    /// The folder a file is in, relative to the library ("" for the top).
    static func folderName(of url: URL, root: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let top = root.standardizedFileURL.resolvingSymlinksInPath().path
        return parent == top ? "" : url.deletingLastPathComponent().lastPathComponent
    }

    /// The day in its name (`2026-11-28-…`), else the day the file was created.
    static func madeDay(name: String, url: URL) -> String {
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(name[range])
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return dayFormatter.string(from: values?.creationDate ?? values?.contentModificationDate ?? Date())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The `#tags` in a script's header (only read when sorting the old flat folder).
    static func headerTags(_ source: String) -> [String] {
        var tags: [String] = []
        var titleSeen = false
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else {
                if titleSeen { break }
                continue
            }
            let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let pure = words.allSatisfy { $0 == "#" || ($0.hasPrefix("#") && $0.count > 1) }
            if pure {
                tags += words.filter { $0.count > 1 }.map { String($0.dropFirst()) }
                continue
            }
            if titleSeen { break }
            titleSeen = true
            tags += words.dropFirst().reversed().prefix { $0.hasPrefix("#") && $0.count > 1 }.map { String($0.dropFirst()) }
        }
        return tags
    }
}
