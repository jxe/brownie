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
        let byName = Dictionary(files.map { ($0.deletingPathExtension().lastPathComponent, $0) },
                                uniquingKeysWith: { first, _ in first })

        // Played most recently first, then the newest files of this era to fill up.
        var names: [String] = player.listeningHistory.recentlyPlayed(at: now).filter { byName[$0] != nil }
        if names.count < recentCount {
            let eras = EraIndex.load()
            for url in files where names.count < recentCount {
                let name = url.deletingPathExtension().lastPathComponent
                guard !names.contains(name) else { continue }
                if let current = eras.current, !eras.belongs(url, to: current) { continue }
                names.append(name)
            }
        }
        let recent: [WidgetSnapshot.Item] = names.prefix(recentCount).compactMap { name in
            guard let url = byName[name] else { return nil }
            let title = MeditationParser.parseMetadata(FileManager.default.readMeditation(at: url) ?? "").title
            return WidgetSnapshot.Item(filename: name, title: title.isEmpty ? name : title)
        }

        let streak = store.currentMeditationStreak
        let workedToday = store.journalEntries.contains { entry in
            guard case .meditation(let m) = entry.content, m.worked else { return false }
            return cal.isDateInToday(entry.timestamp)
        }
        let streakLastDay = streak == 0 ? nil
            : (workedToday ? now : cal.date(byAdding: .day, value: -1, to: now))

        let secondsToday = player.listeningHistory.days(atLeast: 0, at: now)
            .filter { cal.isDateInToday($0.day) }
            .reduce(0) { $0 + $1.seconds }

        let checkedInToday = store.journalEntries.contains { entry in
            guard case .checkInSession = entry.content else { return false }
            return cal.isDateInToday(entry.timestamp)
        } || store.sessionStartTime.map { cal.isDateInToday($0) } == true

        let playing = player.state == .idle ? nil
            : player.currentSourceURL?.deletingPathExtension().lastPathComponent

        let snapshot = WidgetSnapshot(
            updatedAt: now, recent: Array(recent), playingFilename: playing,
            streak: streak, streakLastDay: streakLastDay,
            secondsToday: secondsToday, checkedInToday: checkedInToday,
            palette: UserDefaults.standard.string(forKey: AppPalette.preferenceKey))
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// The app's side of `PlayMeditationIntent`: finds the file and plays it on the shared player.
enum WidgetPlayHandler {
    @MainActor
    static func play(filename: String) async {
        guard let url = FileManager.default.meditationFiles()
                .first(where: { $0.deletingPathExtension().lastPathComponent == filename }),
              let content = FileManager.default.readMeditation(at: url) else { return }
        let player = MeditationPlayer.shared
        if player.currentSourceURL == url, player.state != .idle { return }
        player.play(MeditationParser.parse(content), sourceURL: url)
    }
}
