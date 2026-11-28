import Foundation
import WidgetKit

/// Writes the widgets' snapshot into the App Group and asks WidgetKit to redraw them.
/// App target only; the widget reads the snapshot with `WidgetSnapshot.load()`.
@MainActor
enum WidgetSync {
    private static let recentCount = 4

    static func update(player: MeditationPlayer, store: EmotionStore) {
        let now = Date()
        let cal = Calendar.current
        let files = FileManager.default.meditationFiles()
        let library = MeditationLibrary.shared
        // By id, which is what listening is kept under (and what the widget hands back to play).
        let byName = Dictionary(files.map { (library.id(for: $0), $0) },
                                uniquingKeysWith: { first, _ in first })

        // Played most recently first, then the newest files of this era to fill up.
        var names: [String] = player.listeningHistory.recentlyPlayed(at: now).filter { byName[$0] != nil }
        if names.count < recentCount {
            let eras = EraIndex.load()
            for url in files where names.count < recentCount {
                let name = library.id(for: url)
                guard !names.contains(name) else { continue }
                if let current = eras.current, !eras.belongs(url, to: current) { continue }
                names.append(name)
            }
        }
        let recent: [WidgetSnapshot.Item] = names.prefix(recentCount).compactMap { name in
            guard let url = byName[name] else { return nil }
            let title = MeditationParser.parseMetadata(FileManager.default.readMeditation(at: url) ?? "").title
            return WidgetSnapshot.Item(filename: name, title: title.isEmpty ? MeditationLibrary.name(of: url) : title)
        }

        let listening = player.listeningHistory.days(atLeast: 0, at: now)
        let secondsToday = listening.filter { cal.isDateInToday($0.day) }.reduce(0) { $0 + $1.seconds }

        // This era: listening on or after the day it started, and the meditation most listened to.
        let era = EraIndex.load().current
        let eraStart = era.flatMap { Self.dayFormatter.date(from: $0.started) }.map { cal.startOfDay(for: $0) }
        let eraDays = listening.filter { day in eraStart.map { day.day >= $0 } ?? true }
        let eraSeconds = eraDays.reduce(0) { $0 + $1.seconds }
        let byFile = Dictionary(grouping: eraDays, by: \.filename).mapValues { $0.reduce(0) { $0 + $1.seconds } }
        let eraTopTitle: String? = byFile.max { $0.value < $1.value }.map { top in
            let name = top.key
            let text = byName[name].flatMap { FileManager.default.readMeditation(at: $0) } ?? ""
            let title = MeditationParser.parseMetadata(text).title
            return title.isEmpty ? name : title
        }

        let todayFeelings = Self.todayFeelings(store: store, calendar: cal)

        let playing = player.state == .idle ? nil
            : player.currentSourceURL.map(library.id(for:))

        let snapshot = WidgetSnapshot(
            updatedAt: now, recent: Array(recent), playingFilename: playing,
            secondsToday: secondsToday, todayFeelings: todayFeelings,
            eraSeconds: eraSeconds, eraTopTitle: eraTopTitle, hasEra: era != nil,
            palette: UserDefaults.standard.string(forKey: AppPalette.preferenceKey))
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The check-in under way, if it started today, else today's last logged check-in.
    private static func todayFeelings(store: EmotionStore, calendar cal: Calendar) -> [WidgetSnapshot.Feeling] {
        if let started = store.sessionStartTime, cal.isDateInToday(started), !store.emotionCounts.isEmpty {
            return Emotion.all
                .filter { store.emotionCounts[$0.name, default: 0] > 0 }
                .sorted {
                    let l = store.emotionTimeContributions[$0.name, default: 0]
                    let r = store.emotionTimeContributions[$1.name, default: 0]
                    if l != r { return l > r }
                    return store.emotionCounts[$0.name, default: 0] > store.emotionCounts[$1.name, default: 0]
                }
                .map { WidgetSnapshot.Feeling(emoji: $0.emoji, name: $0.name) }
        }
        for entry in store.journalEntries.sorted(by: { $0.timestamp > $1.timestamp })
            where cal.isDateInToday(entry.timestamp) {
            if case .checkInSession(let session) = entry.content {
                return session.emotions.map { WidgetSnapshot.Feeling(emoji: $0.emoji, name: $0.name) }
            }
        }
        return []
    }
}

/// The app's side of `PlayMeditationIntent`: finds the file and plays it on the shared player.
enum WidgetPlayHandler {
    @MainActor
    /// `filename` is the meditation's id, as the snapshot gave it.
    static func play(filename: String) async {
        guard let url = MeditationLibrary.shared.url(forID: filename)
                ?? FileManager.default.meditationFiles().first(where: { MeditationLibrary.name(of: $0) == filename }),
              let content = FileManager.default.readMeditation(at: url) else { return }
        let player = MeditationPlayer.shared
        if player.currentSourceURL == url, player.state != .idle { return }
        player.play(MeditationParser.parse(content), sourceURL: url)
    }
}
