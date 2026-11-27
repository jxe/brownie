import AppIntents
import Foundation

// Shared by the app and the widget extension (BrownieWidget). The app writes a small
// snapshot into the App Group; the widget only reads it, since it can't reach the
// meditation files or the journal.

enum WidgetShared {
    static let appGroup = "group.com.joeedelman.meditations"
    static let quickPlayKind = "QuickPlay"
    static let todayKind = "Today"
    /// Opens Feelings on the main screen (the Today widget's tap).
    static let feelingsURL = URL(string: "brownie://feelings")!

    static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-snapshot.json")
    }
}

/// What the widgets show, as of `updatedAt`.
struct WidgetSnapshot: Codable {
    struct Item: Codable, Hashable {
        /// The file's name without `.med`, which the play intent looks up.
        let filename: String
        let title: String
    }

    var updatedAt: Date
    /// Latest first: what was played most recently, then the newest of this era.
    var recent: [Item]
    var playingFilename: String?
    /// Consecutive days with a meditation that worked, ending on `streakLastDay`.
    var streak: Int
    var streakLastDay: Date?
    var secondsToday: TimeInterval
    var checkedInToday: Bool
    /// `AppPalette` raw value, so the widget's tint matches the app's.
    var palette: String?

    static let placeholder = WidgetSnapshot(
        updatedAt: Date(),
        recent: [
            Item(filename: "", title: "Morning sit"),
            Item(filename: "", title: "Body scan"),
            Item(filename: "", title: "Loving kindness"),
            Item(filename: "", title: "Breath count"),
        ],
        playingFilename: nil, streak: 3, streakLastDay: Date(),
        secondsToday: 12 * 60, checkedInToday: true, palette: nil)

    static func load() -> WidgetSnapshot? {
        guard let url = WidgetShared.snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = WidgetShared.snapshotURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // The widget may show a snapshot from an earlier day; these read it as of `now`.

    func streak(at now: Date) -> Int {
        guard let last = streakLastDay else { return 0 }
        let cal = Calendar.current
        return cal.isDateInToday(last) || cal.isDateInYesterday(last) || cal.isDate(last, inSameDayAs: now)
            ? streak : 0
    }

    func isToday(at now: Date) -> Bool {
        Calendar.current.isDate(updatedAt, inSameDayAs: now)
    }
}

/// Starts a meditation from a widget. As an audio playback intent it runs in the app's
/// process (launched in the background if need be), so the app's player plays it and the
/// now-playing bar is up when the app opens.
struct PlayMeditationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Meditation"
    static let description = IntentDescription("Starts a Brownie meditation.")

    @Parameter(title: "Filename")
    var filename: String

    init() {}

    init(filename: String) {
        self.filename = filename
    }

    func perform() async throws -> some IntentResult {
        await WidgetPlayHandler.play(filename: filename)
        return .result()
    }
}
