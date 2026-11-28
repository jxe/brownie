import Foundation

/// An era is a stretch of time, from the day it was started until the next one. It has no
/// name, and nothing about it is written into the scripts.
///
/// A meditation belongs to the era it was made in, and to any later era it was brought along
/// to. That's kept in `library.json` (`MeditationLibrary`), and each meditation's file sits in
/// the folder of the latest era it belongs to, named by the day that era started.
struct Era: Codable, Hashable {
    var id: String
    var started: String  // yyyy-MM-dd
    /// Brought-along meditations by filename, from before the library had folders. Only read
    /// when the old flat folder is sorted into folders.
    var kept: [String]
    /// Eras used to be tags in each script's header (`#🌱`). An era from then keeps its old tag
    /// so any script still carrying it (another device, an edit in VS Code) is folded into
    /// `kept` and has the tag taken out.
    var legacyTag: String?

    init(started: String, kept: [String] = []) {
        self.id = UUID().uuidString
        self.started = started
        self.kept = kept
        self.legacyTag = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, started, kept, legacyTag
        case tag  // the old format: {"tag": "🌱", "started": "2026-09-19"}
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        started = try c.decode(String.self, forKey: .started)
        kept = try c.decodeIfPresent([String].self, forKey: .kept) ?? []
        legacyTag = try c.decodeIfPresent(String.self, forKey: .legacyTag)
            ?? c.decodeIfPresent(String.self, forKey: .tag)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? legacyTag ?? started
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(started, forKey: .started)
        try c.encode(kept, forKey: .kept)
        try c.encodeIfPresent(legacyTag, forKey: .legacyTag)
    }
}

/// Which era a past list shows: one era, or what was made before the first one.
enum EraSelection: Hashable {
    case era(String)  // Era.id
    case older
}

struct EraIndex {
    static let filename = "eras.json"
    static let timelessTag = "timeless"

    /// Newest first. The first era is the current one.
    var eras: [Era] = []

    var current: Era? { eras.first }

    /// Tags that used to mark eras. The store leaves them out of what it shares.
    func isEraTag(_ tag: String) -> Bool {
        eras.contains { $0.legacyTag == tag }
    }

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

    func belongs(_ url: URL, to era: Era) -> Bool {
        MeditationLibrary.shared.eras(of: url).contains(era.id)
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
            return candidates.filter { MeditationLibrary.shared.eras(of: $0).isEmpty }
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
        let url = FileManager.default.meditationsDirectory.appendingPathComponent(Self.filename)
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

    /// The `yyyy-MM-dd` date a meditation was made: as the library has it, else its filename
    /// prefix, else when the file was created (not modified, so an edit doesn't move it into a
    /// later era).
    static func dateString(for url: URL) -> String {
        if let made = MeditationLibrary.shared.made(of: url) { return made }
        let name = url.lastPathComponent
        if let range = name.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(name[range])
        }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return dayFormatter.string(from: values?.creationDate ?? values?.contentModificationDate ?? Date())
    }
}
