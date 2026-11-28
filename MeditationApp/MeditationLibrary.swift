import Foundation

/// Where each meditation lives. The folder a script is in says where it shows up:
/// - an era's folder, named by the day the era started (`2026-11-21/`): the most recent era it
///   belongs to, so the newest era's folder holds what that era's section shows;
/// - `Evergreen/`: shown in every era;
/// - `Archive/`: put away;
/// - `Older/`: made before the first era and never brought along to one.
///
/// Its name, `yyyy-MM-dd-title`, says the day it was made, and so the era it was made in.
/// `eras.json` lists any other eras it belongs to (`Era.kept`). Names are unique across all
/// folders, and a meditation's filename (no extension) is its id: listening stats, store links
/// and journal marks are kept under it, and a rename in the app carries them over. A script
/// dropped at the top of the folder (from the Mac, say) joins the current era.
final class MeditationLibrary {
    static let shared = MeditationLibrary {
        FileManager.default.meditationStorageIsAvailable ? FileManager.default.meditationsDirectory : nil
    }

    static let evergreenFolder = "Evergreen"
    static let archiveFolder = "Archive"
    static let olderFolder = "Older"

    /// Called after a file moves (from, to), so whatever holds its URL (the player) can follow.
    var onMove: ((URL, URL) -> Void)?

    private let rootProvider: () -> URL?
    private let lock = NSRecursiveLock()

    init(root: @escaping () -> URL?) {
        rootProvider = root
    }

    // MARK: Lookups

    /// The key a meditation's listening stats, store link and journal marks are kept under:
    /// its filename without `.med`.
    func id(for url: URL) -> String {
        Self.name(of: url)
    }

    /// Where the meditation with this id (filename) is, in whichever folder.
    func url(forID id: String) -> URL? {
        url(forName: id)
    }

    /// Where the file with this name is, in whichever folder.
    func url(forName name: String) -> URL? {
        locked { root in
            guard let root else { return nil }
            return scan(root, eras: EraIndex.load(in: root)).files.first { $0.name == name }?.url
        }
    }

    /// Whether some meditation, in any folder (or not downloaded yet), already has this name.
    func isNameTaken(_ name: String) -> Bool {
        locked { root in
            guard let root else { return false }
            let found = scan(root, eras: EraIndex.load(in: root))
            return (found.files + found.placeholders).contains { $0.name == name }
        }
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

    /// Brings a meditation from an earlier era into the current one: it moves to the current
    /// era's folder, and still belongs to the eras it came from.
    func bringAlong(_ url: URL) {
        move(url) { member, eras in
            guard let current = eras.current, !member.contains(current.id) else { return nil }
            return eras.folder(for: current.id)
        }
    }

    /// Undoes bringing it along: back to the latest era it came from (or `Older`).
    func sendBack(_ url: URL) {
        move(url) { member, eras in
            guard let current = eras.current, member.contains(current.id) else { return nil }
            return Self.placement(member.filter { $0 != current.id }, eras: eras)
        }
    }

    /// Into `Evergreen`, or out of it to the latest era it belongs to.
    func setEvergreen(_ url: URL, _ on: Bool) {
        move(url) { member, eras in on ? Self.evergreenFolder : Self.placement(member, eras: eras) }
    }

    @discardableResult
    func archive(_ url: URL) -> URL? {
        move(url) { _, _ in Self.archiveFolder }
    }

    /// Out of the archive, to the latest era it belongs to.
    @discardableResult
    func unarchive(_ url: URL) -> URL? {
        move(url) { member, eras in Self.placement(member, eras: eras) }
    }

    /// Renames the file where it is, and keeps it in the eras it was brought along to. The
    /// caller moves its listening stats and store link to the new name.
    @discardableResult
    func rename(_ url: URL, to newName: String) -> URL? {
        locked { root in
            guard let root else { return nil }
            let oldName = Self.name(of: url)
            guard newName != oldName else { return url }
            let target = url.deletingLastPathComponent().appendingPathComponent("\(newName).med")
            guard moveFile(url, to: target) else { return nil }
            var eras = EraIndex.load(in: root)
            if eras.rename(oldName, to: newName) { eras.save(in: root) }
            return target
        }
    }

    func delete(_ url: URL) {
        locked { _ in try? FileManager.default.removeItem(at: url) }
    }

    /// Moves the meditation to the folder `decide` picks from the eras it belongs to (nil
    /// leaves it), and records in `eras.json` any eras it belongs to that its new folder and
    /// its name won't say. Returns where the file is now.
    @discardableResult
    private func move(_ url: URL, _ decide: ([String], EraIndex) -> String?) -> URL? {
        locked { root in
            guard let root else { return nil }
            var eras = EraIndex.load(in: root)
            var member = eras.eras(of: url)
            guard let folder = decide(member, eras) else { return url }
            let name = Self.name(of: url)
            let target = Self.fileURL(root, folder, name)
            if target.standardizedFileURL.path != url.standardizedFileURL.path {
                guard moveFile(url, to: target) else { return nil }
            }
            if let era = eras.era(inFolder: folder) {
                // Brought along: it now belongs to that era too; sent back: no longer to later ones.
                if !member.contains(era.id) { member.append(era.id) }
                member = member.filter { eras.era($0).map { $0.started <= era.started } ?? false }
            } else if folder == Self.olderFolder {
                member = []
            }
            if eras.remember(member, name: name, made: EraIndex.dateString(for: target), folder: folder) {
                eras.save(in: root)
            }
            return target
        }
    }

    // MARK: Sync

    /// Files scripts left at the top into the current era's folder, and renames a script whose
    /// name one in another folder already has (`-2`). Call before listing.
    func sync() {
        locked { root in
            guard let root else { return }
            let eras = EraIndex.load(in: root)
            let found = scan(root, eras: eras)
            var seen = Set<String>()
            // Where a name turns up twice, an era folder's copy keeps it over the archive's.
            for file in found.files.sorted(by: { Self.rank($0.folder) < Self.rank($1.folder) }) {
                var url = file.url
                if seen.contains(file.name) {
                    var n = 2
                    while seen.contains("\(file.name)-\(n)") || isNameTaken("\(file.name)-\(n)") { n += 1 }
                    let target = url.deletingLastPathComponent().appendingPathComponent("\(file.name)-\(n).med")
                    guard moveFile(url, to: target) else { continue }
                    url = target
                }
                seen.insert(Self.name(of: url))
                // At the top only while there are no eras; then it joins the current one.
                if file.folder.isEmpty, let current = eras.current, let folder = eras.folder(for: current.id) {
                    _ = moveFile(url, to: Self.fileURL(root, folder, Self.name(of: url)))
                }
            }
        }
    }

    private static func rank(_ folder: String) -> Int {
        switch folder {
        case archiveFolder: 3
        case "": 2
        case evergreenFolder, olderFolder: 1
        default: 0
        }
    }

    // MARK: Placement

    /// Where a meditation that isn't Evergreen or archived goes: the latest era it belongs to,
    /// else `Older`, or the top when there are no eras.
    static func placement(_ member: [String], eras: EraIndex) -> String {
        if let latest = eras.eras.first(where: { member.contains($0.id) }),
           let folder = eras.folder(for: latest.id) {
            return folder
        }
        return eras.eras.isEmpty ? "" : olderFolder
    }

    /// The top, or one of the library's own folders. A dated folder with no era (yet: its
    /// era's record may still be on its way from another device) counts too.
    private static func isFolder(_ folder: String, eras: EraIndex) -> Bool {
        folder.isEmpty || [evergreenFolder, archiveFolder, olderFolder].contains(folder)
            || eras.era(inFolder: folder) != nil
            || folder.range(of: #"^\d{4}-\d{2}-\d{2}(-\d+)?$"#, options: .regularExpression) != nil
    }

    // MARK: Disk

    private struct Found {
        let folder: String
        let name: String
        let url: URL
    }

    /// The scripts at the top and in the library's folders (era folders, Evergreen, Archive,
    /// Older), and the iCloud placeholders of ones not downloaded yet. Other folders (a
    /// backup, any of your own) are left alone.
    private func scan(_ root: URL, eras: EraIndex) -> (files: [Found], placeholders: [Found]) {
        let fm = FileManager.default
        var folders = [""]
        if let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for item in items where (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                let name = item.lastPathComponent
                if Self.isFolder(name, eras: eras) { folders.append(name) }
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

    private func moveFile(_ from: URL, to: URL) -> Bool {
        let moved = Self.moveFile(from, to: to)
        if moved { onMove?(from, to) }
        return moved
    }

    /// A coordinated move, so iCloud (and anything with the file open) follows it. Never
    /// writes over a file that's there.
    static func moveFile(_ from: URL, to: URL) -> Bool {
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
        return moved
    }

    private func locked<T>(_ body: (URL?) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(rootProvider())
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
}
