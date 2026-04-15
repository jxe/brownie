import Foundation
import Observation

@Observable
class EmotionStore {
    var emotionCounts: [String: Int] = [:]
    var inFlightEmotions: Set<String> = []
    private(set) var journalEntries: [JournalEntry] = []

    /// Cumulative engagement time in seconds, grows with each tap.
    var sessionTime: TimeInterval = 0
    private var lastTapTime: Date?
    private var lastInteractionTime: Date?

    private enum SessionKeys {
        static let emotionCounts = "checkin_emotionCounts"
        static let sessionTime = "checkin_sessionTime"
        static let lastInteraction = "checkin_lastInteractionTime"
        static let recentMeditationPlays = "recentMeditationPlays"
    }

    /// Map of meditation filename → last-played timestamp. Persisted in
    /// UserDefaults so "recently played" survives app restarts and iOS kills.
    private var recentPlays: [String: Date] = [:]

    init() {
        load()
        loadSession()
        loadRecentPlays()
    }

    func tap(_ emotion: Emotion) {
        emotionCounts[emotion.name, default: 0] += 1
        addSessionCredit()
        lastInteractionTime = Date()
        saveSession()
    }

    private func addSessionCredit() {
        let now = Date()
        if let last = lastTapTime {
            let elapsed = now.timeIntervalSince(last)
            let credit = min(elapsed, 20)
            sessionTime += credit
        }
        lastTapTime = now
    }

    func deselect(_ emotion: Emotion) {
        emotionCounts.removeValue(forKey: emotion.name)
        lastInteractionTime = Date()
        saveSession()
    }

    func count(for emotion: Emotion) -> Int {
        emotionCounts[emotion.name, default: 0]
    }

    func isSelected(_ emotion: Emotion) -> Bool {
        count(for: emotion) > 0
    }

    func selectedEmotionsSorted() -> [Emotion] {
        Emotion.all
            .filter { isSelected($0) }
            .sorted { count(for: $0) > count(for: $1) }
    }

    func submit(emotion: Emotion, answer: String) {
        let entry = JournalEntry(
            id: UUID(),
            timestamp: Date(),
            content: .reflection(.init(
                emotionName: emotion.name,
                emoji: emotion.emoji,
                question: emotion.question,
                answer: answer
            ))
        )
        journalEntries.insert(entry, at: 0)
        save()
    }

    func deleteEntry(_ entry: JournalEntry) {
        journalEntries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Meditation Logs

    /// Insert a positive meditation log entry dated `Date()`.
    func logMeditation(title: String, sourceURL: URL?) {
        let entry = JournalEntry(
            id: UUID(),
            timestamp: Date(),
            content: .meditation(.init(
                title: title,
                filename: sourceURL?.deletingPathExtension().lastPathComponent,
                worked: true
            ))
        )
        journalEntries.insert(entry, at: 0)
        save()
    }

    /// If a meditation log for `sourceURL`'s filename exists for today, remove it;
    /// otherwise create one. Used by the row-level toggle button.
    func toggleMeditationLogForToday(title: String, sourceURL: URL?) {
        let filename = sourceURL?.deletingPathExtension().lastPathComponent
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        if let existing = journalEntries.first(where: { entry in
            guard case .meditation(let m) = entry.content else { return false }
            return m.filename == filename && cal.isDate(entry.timestamp, inSameDayAs: today)
        }) {
            journalEntries.removeAll { $0.id == existing.id }
            save()
        } else {
            logMeditation(title: title, sourceURL: sourceURL)
        }
    }

    func hasMeditationLogToday(filename: String?) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return journalEntries.contains { entry in
            guard case .meditation(let m) = entry.content else { return false }
            return m.filename == filename && cal.isDate(entry.timestamp, inSameDayAs: today)
        }
    }

    /// Consecutive calendar days (ending today, or yesterday if today has no
    /// log yet) with at least one positive meditation log. Returns 0 if neither
    /// today nor yesterday has a log.
    var currentMeditationStreak: Int {
        let cal = Calendar.current
        let days: Set<Date> = Set(journalEntries.compactMap { entry in
            guard case .meditation(let m) = entry.content, m.worked else { return nil }
            return cal.startOfDay(for: entry.timestamp)
        })
        guard !days.isEmpty else { return 0 }

        let today = cal.startOfDay(for: Date())
        var cursor = days.contains(today)
            ? today
            : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        guard days.contains(cursor) else { return 0 }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
    }

    // MARK: - Recent Plays

    func markMeditationPlayed(filename: String?) {
        guard let filename else { return }
        recentPlays[filename] = Date()
        saveRecentPlays()
    }

    func wasRecentlyPlayed(filename: String?, within hours: Double = 24) -> Bool {
        guard let filename, let last = recentPlays[filename] else { return false }
        return Date().timeIntervalSince(last) < hours * 3600
    }

    private func saveRecentPlays() {
        // UserDefaults can persist [String: Date] directly via property-list encoding.
        UserDefaults.standard.set(recentPlays, forKey: SessionKeys.recentMeditationPlays)
    }

    private func loadRecentPlays() {
        if let dict = UserDefaults.standard.dictionary(forKey: SessionKeys.recentMeditationPlays) as? [String: Date] {
            recentPlays = dict
        }
    }

    // MARK: - Session Persistence

    func clearSessionIfStale() {
        guard let last = lastInteractionTime else { return }
        if Date().timeIntervalSince(last) > 6 * 60 * 60 {
            emotionCounts = [:]
            sessionTime = 0
            lastTapTime = nil
            lastInteractionTime = nil
            saveSession()
        }
    }

    private func saveSession() {
        let defaults = UserDefaults.standard
        defaults.set(emotionCounts, forKey: SessionKeys.emotionCounts)
        defaults.set(sessionTime, forKey: SessionKeys.sessionTime)
        if let time = lastInteractionTime {
            defaults.set(time.timeIntervalSince1970, forKey: SessionKeys.lastInteraction)
        } else {
            defaults.removeObject(forKey: SessionKeys.lastInteraction)
        }
    }

    private func loadSession() {
        let defaults = UserDefaults.standard
        if let counts = defaults.dictionary(forKey: SessionKeys.emotionCounts) as? [String: Int] {
            emotionCounts = counts
        }
        let time = defaults.double(forKey: SessionKeys.sessionTime)
        if time > 0 { sessionTime = time }
        let stamp = defaults.double(forKey: SessionKeys.lastInteraction)
        if stamp > 0 { lastInteractionTime = Date(timeIntervalSince1970: stamp) }
    }

    // MARK: - Journal Persistence

    private var journalFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("emotion_journal.json")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(journalEntries)
            try data.write(to: journalFileURL, options: .atomic)
        } catch {
            print("EmotionStore save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: journalFileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: journalFileURL)
        } catch {
            print("EmotionStore load error: \(error)")
            return
        }

        let decoder = JSONDecoder()

        // New format.
        if let entries = try? decoder.decode([JournalEntry].self, from: data) {
            journalEntries = entries
            return
        }

        // Legacy format: [{ id, emotionName, emoji, question, answer, timestamp }].
        // Migrate in place and rewrite the file in the new format.
        if let legacy = try? decoder.decode([LegacyJournalEntry].self, from: data) {
            journalEntries = legacy.map { old in
                JournalEntry(
                    id: old.id,
                    timestamp: old.timestamp,
                    content: .reflection(.init(
                        emotionName: old.emotionName,
                        emoji: old.emoji,
                        question: old.question,
                        answer: old.answer
                    ))
                )
            }
            save()
            return
        }

        print("EmotionStore: failed to decode journal in either format")
    }

    private struct LegacyJournalEntry: Codable {
        let id: UUID
        let emotionName: String
        let emoji: String
        let question: String
        let answer: String
        let timestamp: Date
    }
}
