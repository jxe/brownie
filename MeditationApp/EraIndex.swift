import Foundation

/// An era is a stretch of time, from the day it was started until the next one. It has no
/// name, and nothing about it is written into the scripts.
///
/// A meditation belongs to the era it was made in (by the date its filename starts with), and
/// to any later era it was brought along to. Its file sits in the folder of the latest one,
/// named by the day that era started (`MeditationLibrary`). `kept` lists, by filename, the
/// meditations that belong to this era but are neither made in it nor in its folder: ones
/// brought along further, to a later era.
struct Era: Codable, Hashable {
    var id: String
    var started: String  // yyyy-MM-dd
    var kept: [String]

    init(started: String, kept: [String] = []) {
        self.id = UUID().uuidString
        self.started = started
        self.kept = kept
    }

    private enum CodingKeys: String, CodingKey {
        case id, started, kept
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = try c.decode(String.self, forKey: .started)
        kept = try c.decodeIfPresent([String].self, forKey: .kept) ?? []
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? started
    }
}

/// Which era a past list shows: one era, or what was made before the first one.
enum EraSelection: Hashable {
    case era(String)  // Era.id
    case older
}

struct EraIndex {
    static let filename = "eras.json"

    /// Newest first. The first era is the current one.
    var eras: [Era] = []

    var current: Era? { eras.first }

    func era(_ id: String) -> Era? {
        eras.first { $0.id == id }
    }

    /// Each era's folder: the day it started, with `-2` on a second era started that day.
    var folders: [String: String] {
        var result: [String: String] = [:]
        var used: [String: Int] = [:]
        for era in eras.reversed() {
            let n = used[era.started, default: 0] + 1
            used[era.started] = n
            result[era.id] = n == 1 ? era.started : "\(era.started)-\(n)"
        }
        return result
    }

    func folder(for eraID: String) -> String? {
        folders[eraID]
    }

    func era(inFolder folder: String) -> Era? {
        folders.first { $0.value == folder }.flatMap { era($0.key) }
    }

    /// The era after this one, which ended it.
    private func next(after era: Era) -> Era? {
        guard let index = eras.firstIndex(where: { $0.id == era.id }), index > 0 else { return nil }
        return eras[index - 1]
    }

    /// The era a meditation was made in, or nil if it predates them all.
    func eraMade(_ url: URL) -> Era? {
        let made = Self.dateString(for: url)
        return eras.first { $0.started <= made }
    }

    /// The eras a meditation belongs to (ids), from where its file is: in an era's folder,
    /// that era and the earlier ones it came from; in `Older`, none; in Evergreen or the
    /// archive (or at the top), the ones it would go back to.
    func eras(of url: URL) -> [String] {
        let folder = url.deletingLastPathComponent().lastPathComponent
        if folder == MeditationLibrary.olderFolder { return [] }
        let name = Self.name(of: url)
        let made = Self.dateString(for: url)
        var ids: [String] = []
        if let era = eras.first(where: { $0.started <= made }) { ids.append(era.id) }
        for era in eras where era.kept.contains(name) && !ids.contains(era.id) { ids.append(era.id) }
        guard let folderEra = era(inFolder: folder) else { return ids }
        return ids.filter { id in self.era(id).map { $0.started < folderEra.started } ?? false } + [folderEra.id]
    }

    func belongs(_ url: URL, to era: Era) -> Bool {
        eras(of: url).contains(era.id)
    }

    /// In the current era because it was brought along, not because it was made then.
    func wasBroughtAlong(_ url: URL) -> Bool {
        guard let current else { return false }
        return belongs(url, to: current) && Self.dateString(for: url) < current.started
    }

    /// A past era's meditations, minus Evergreen ones and ones brought along to the current
    /// era: what its page lists.
    func pastFiles(_ selection: EraSelection, from files: [URL], isTimeless: (URL) -> Bool) -> [URL] {
        guard let current else { return [] }
        let candidates = files.filter { !isTimeless($0) && !belongs($0, to: current) }
        switch selection {
        case .era(let id):
            guard let era = era(id) else { return [] }
            return candidates.filter { belongs($0, to: era) }
        case .older:
            // Made before the first era and never brought along to any.
            return candidates.filter { eras(of: $0).isEmpty }
        }
    }

    /// `Since 19 Nov` for the current era, `16 Oct – 19 Nov` for a past one.
    func label(for era: Era) -> String {
        let start = Self.shortDate(era.started)
        guard let next = next(after: era) else { return "Since \(start)" }
        return "\(start) – \(Self.shortDate(next.started))"
    }

    func label(for selection: EraSelection) -> String {
        switch selection {
        case .era(let id):
            return era(id).map(label(for:)) ?? "Past Era"
        case .older:
            return eras.last.map { "Before \(Self.shortDate($0.started))" } ?? "Older"
        }
    }

    // MARK: Changes

    /// Starts a new era today. It begins empty; meditations are brought along one at a time.
    static func startNew() {
        var index = load()
        index.eras.insert(Era(started: todayString()), at: 0)
        index.save()
    }

    static func bringAlong(_ url: URL) {
        MeditationLibrary.shared.bringAlong(url)
    }

    /// Undoes bringing a meditation along: it goes back to the eras it came from.
    static func sendBack(_ url: URL) {
        MeditationLibrary.shared.sendBack(url)
    }

    /// Keeps a renamed meditation in the eras it was brought along to.
    mutating func rename(_ oldName: String, to newName: String) -> Bool {
        guard oldName != newName else { return false }
        var changed = false
        for i in eras.indices where eras[i].kept.contains(oldName) {
            eras[i].kept = eras[i].kept.map { $0 == oldName ? newName : $0 }
            changed = true
        }
        return changed
    }

    /// Records the eras a meditation belongs to that its filename and folder won't say:
    /// `member` minus the era it was made in and its folder's. True if anything changed.
    mutating func remember(_ member: [String], name: String, made: String, folder: String) -> Bool {
        let implied = Set([eras.first { $0.started <= made }?.id, era(inFolder: folder)?.id].compactMap { $0 })
        var changed = false
        for i in eras.indices {
            let should = member.contains(eras[i].id) && !implied.contains(eras[i].id)
            if should, !eras[i].kept.contains(name) {
                eras[i].kept.append(name)
                changed = true
            } else if !should, eras[i].kept.contains(name) {
                eras[i].kept.removeAll { $0 == name }
                changed = true
            }
        }
        return changed
    }

    // MARK: Storage

    static func load() -> EraIndex {
        load(in: FileManager.default.meditationsDirectory)
    }

    static func load(in directory: URL) -> EraIndex {
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // Not downloaded yet: iCloud leaves a `.eras.json.icloud` placeholder. Ask for it;
            // the watcher refreshes the list once it lands.
            let placeholder = directory.appendingPathComponent(".\(filename).icloud")
            if FileManager.default.fileExists(atPath: placeholder.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            return EraIndex()
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var data: Data?
        var coordinationError: NSError?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            data = try? Data(contentsOf: coordinatedURL)
        }
        guard let data, let eras = try? JSONDecoder().decode([Era].self, from: data) else {
            print("Brownie could not read \(filename)")
            return EraIndex()
        }
        return EraIndex(eras: eras.sorted { $0.started > $1.started })
    }

    func save() {
        guard FileManager.default.meditationStorageIsAvailable else { return }
        save(in: FileManager.default.meditationsDirectory)
    }

    func save(in directory: URL) {
        let url = directory.appendingPathComponent(Self.filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(eras) else { return }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                print("Save error: \(error)")
            }
        }
        if let coordinationError {
            print("Save coordination error: \(coordinationError)")
        }
    }

    // MARK: Dates

    static func name(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func todayString() -> String {
        dayFormatter.string(from: Date())
    }

    /// Whole days from the day a meditation was made to today, or nil if that day can't be read.
    static func daysSinceMade(_ url: URL) -> Int? {
        guard let made = dayFormatter.date(from: dateString(for: url)) else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: made), to: calendar.startOfDay(for: Date())).day
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// `19 Nov`, or `19 Nov 2025` outside this year, in the person's own date order.
    static func shortDate(_ day: String) -> String {
        guard let date = dayFormatter.date(from: day) else { return day }
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle().day().month(.abbreviated)
        return sameYear ? date.formatted(style) : date.formatted(style.year())
    }

    /// The `yyyy-MM-dd` date a meditation was made: its filename prefix, else when the file was created (not modified, so an edit doesn't move it into a
    /// later era).
    static func dateString(for url: URL) -> String {
        let name = url.lastPathComponent
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(name[range])
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return dayFormatter.string(from: values?.creationDate ?? values?.contentModificationDate ?? Date())
    }
}
