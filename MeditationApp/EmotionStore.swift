import Foundation
import Observation

@Observable
class EmotionStore {
    static let maxEmotionCreditDuration: TimeInterval = 20

    struct HistoricalEmotionUsage {
        var engagementSeconds: TimeInterval = 0
        var tapCount: Int = 0
    }

    struct TimeCredit {
        let emotionID: String
        let totalContribution: TimeInterval
    }

    var emotionCounts: [String: Int] = [:]
    var emotionTimeContributions: [String: TimeInterval] = [:]
    var inFlightEmotions: Set<String> = []
    private(set) var journalEntries: [JournalEntry] = []

    /// Cumulative engagement time in seconds, grows with each tap.
    var sessionTime: TimeInterval = 0
    private var lastTapTime: Date?
    private var lastTappedEmotionName: String?
    var accruingEmotionID: String? { lastTappedEmotionName }
    var accruingStartedAt: Date? { lastTapTime }
    private var lastInteractionTime: Date?
    /// Wall-clock timestamp of the first tap in the current session. Cleared
    /// alongside `emotionCounts`; used to compute the session span when logging.
    private(set) var sessionStartTime: Date?

    private enum SessionKeys {
        static let emotionCounts = "checkin_emotionCounts"
        static let emotionTimeContributions = "checkin_emotionTimeContributions"
        static let sessionTime = "checkin_sessionTime"
        static let lastTap = "checkin_lastTapTime"
        static let lastTappedEmotion = "checkin_lastTappedEmotion"
        static let lastInteraction = "checkin_lastInteractionTime"
        static let sessionStart = "checkin_sessionStartTime"
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

    @discardableResult
    func tap(_ emotion: Emotion) -> TimeCredit? {
        let now = Date()
        if sessionStartTime == nil {
            sessionStartTime = now
        }
        emotionCounts[emotion.name, default: 0] += 1
        let creditedEmotion = addSessionCredit(at: now)
        lastTappedEmotionName = emotion.name
        lastInteractionTime = now
        saveSession()
        return creditedEmotion
    }

    @discardableResult
    func stopAccruing() -> TimeCredit? {
        guard lastTapTime != nil || lastTappedEmotionName != nil else { return nil }

        let now = Date()
        let creditedEmotion = addSessionCredit(at: now)
        lastTappedEmotionName = nil
        lastTapTime = nil
        lastInteractionTime = now
        saveSession()
        return creditedEmotion
    }

    private func addSessionCredit(at now: Date) -> TimeCredit? {
        defer { lastTapTime = now }
        guard let last = lastTapTime else { return nil }

        let elapsed = now.timeIntervalSince(last)
        let credit = min(elapsed, Self.maxEmotionCreditDuration)
        guard credit > 0 else { return nil }

        guard let emotionName = lastTappedEmotionName,
              emotionCounts[emotionName, default: 0] > 0 else { return nil }

        sessionTime += credit
        emotionTimeContributions[emotionName, default: 0] += credit
        return TimeCredit(
            emotionID: emotionName,
            totalContribution: emotionTimeContributions[emotionName, default: 0]
        )
    }

    func deselect(_ emotion: Emotion) {
        emotionCounts.removeValue(forKey: emotion.name)
        emotionTimeContributions.removeValue(forKey: emotion.name)
        if lastTappedEmotionName == emotion.name {
            lastTappedEmotionName = nil
            lastTapTime = nil
        }
        lastInteractionTime = Date()
        saveSession()
    }

    func count(for emotion: Emotion) -> Int {
        emotionCounts[emotion.name, default: 0]
    }

    func timeContribution(for emotion: Emotion) -> TimeInterval {
        emotionTimeContributions[emotion.name, default: 0]
    }

    func timeContribution(for emotion: Emotion, asOf date: Date) -> TimeInterval {
        timeContribution(for: emotion) + liveAccruingCredit(for: emotion.name, asOf: date)
    }

    func sessionTime(asOf date: Date) -> TimeInterval {
        sessionTime + liveAccruingCredit(asOf: date)
    }

    func isSelected(_ emotion: Emotion) -> Bool {
        count(for: emotion) > 0
    }

    func selectedEmotionsSorted() -> [Emotion] {
        selectedEmotionsSorted(asOf: nil)
    }

    func historicalEmotionUsage() -> [String: HistoricalEmotionUsage] {
        var usage: [String: HistoricalEmotionUsage] = [:]
        for entry in journalEntries {
            guard case .checkInSession(let session) = entry.content else { continue }
            for tally in session.emotions {
                usage[tally.name, default: HistoricalEmotionUsage()].engagementSeconds +=
                    tally.engagementSeconds ?? 0
                usage[tally.name, default: HistoricalEmotionUsage()].tapCount += tally.count
            }
        }
        return usage
    }

    func selectedEmotionsSorted(asOf date: Date) -> [Emotion] {
        selectedEmotionsSorted(asOf: date as Date?)
    }

    private func selectedEmotionsSorted(asOf date: Date?) -> [Emotion] {
        Emotion.all
            .filter { isSelected($0) }
            .sorted { lhs, rhs in
                let lhsTime = date.map { timeContribution(for: lhs, asOf: $0) } ?? timeContribution(for: lhs)
                let rhsTime = date.map { timeContribution(for: rhs, asOf: $0) } ?? timeContribution(for: rhs)
                if lhsTime != rhsTime { return lhsTime > rhsTime }

                let lhsCount = count(for: lhs)
                let rhsCount = count(for: rhs)
                if lhsCount != rhsCount { return lhsCount > rhsCount }

                return lhs.name < rhs.name
            }
    }

    private func liveAccruingCredit(for emotionName: String? = nil, asOf date: Date) -> TimeInterval {
        guard let lastTapTime,
              let lastTappedEmotionName,
              emotionName == nil || emotionName == lastTappedEmotionName,
              emotionCounts[lastTappedEmotionName, default: 0] > 0 else { return 0 }

        return min(max(0, date.timeIntervalSince(lastTapTime)), Self.maxEmotionCreditDuration)
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
        guard let last = lastInteractionTime,
              Date().timeIntervalSince(last) > 6 * 60 * 60 else { return }
        logAndClearSession()
    }

    /// Write a `.checkInSession` journal entry for the current counts (if any) and
    /// reset session state. Called by the manual long-press clear and by the
    /// auto-stale path.
    func logAndClearSession() {
        guard !emotionCounts.isEmpty else {
            clearSessionState()
            return
        }
        let tallies: [JournalEntry.Content.CheckInSession.EmotionTally] =
            Emotion.all.compactMap { e in
                let n = emotionCounts[e.name, default: 0]
                guard n > 0 else { return nil }
                return .init(
                    name: e.name,
                    emoji: e.emoji,
                    count: n,
                    engagementSeconds: emotionTimeContributions[e.name, default: 0]
                )
            }
            .sorted {
                let lhsTime = $0.engagementSeconds ?? 0
                let rhsTime = $1.engagementSeconds ?? 0
                if lhsTime != rhsTime { return lhsTime > rhsTime }
                return $0.count > $1.count
            }
        let entry = JournalEntry(
            id: UUID(),
            timestamp: Date(),
            content: .checkInSession(.init(
                startedAt: sessionStartTime ?? lastInteractionTime ?? Date(),
                engagementSeconds: sessionTime,
                emotions: tallies
            ))
        )
        journalEntries.insert(entry, at: 0)
        save()
        clearSessionState()
    }

    private func clearSessionState() {
        emotionCounts = [:]
        emotionTimeContributions = [:]
        sessionTime = 0
        lastTapTime = nil
        lastTappedEmotionName = nil
        lastInteractionTime = nil
        sessionStartTime = nil
        saveSession()
    }

    private func saveSession() {
        let defaults = UserDefaults.standard
        defaults.set(emotionCounts, forKey: SessionKeys.emotionCounts)
        defaults.set(emotionTimeContributions, forKey: SessionKeys.emotionTimeContributions)
        defaults.set(sessionTime, forKey: SessionKeys.sessionTime)
        if let time = lastTapTime {
            defaults.set(time.timeIntervalSince1970, forKey: SessionKeys.lastTap)
        } else {
            defaults.removeObject(forKey: SessionKeys.lastTap)
        }
        if let emotionName = lastTappedEmotionName {
            defaults.set(emotionName, forKey: SessionKeys.lastTappedEmotion)
        } else {
            defaults.removeObject(forKey: SessionKeys.lastTappedEmotion)
        }
        if let time = lastInteractionTime {
            defaults.set(time.timeIntervalSince1970, forKey: SessionKeys.lastInteraction)
        } else {
            defaults.removeObject(forKey: SessionKeys.lastInteraction)
        }
        if let start = sessionStartTime {
            defaults.set(start.timeIntervalSince1970, forKey: SessionKeys.sessionStart)
        } else {
            defaults.removeObject(forKey: SessionKeys.sessionStart)
        }
    }

    private func loadSession() {
        let defaults = UserDefaults.standard
        if let counts = defaults.dictionary(forKey: SessionKeys.emotionCounts) as? [String: Int] {
            emotionCounts = counts
        }
        if let contributions = defaults.dictionary(forKey: SessionKeys.emotionTimeContributions) as? [String: Double] {
            emotionTimeContributions = contributions
        }
        let time = defaults.double(forKey: SessionKeys.sessionTime)
        if time > 0 { sessionTime = time }
        let tapStamp = defaults.double(forKey: SessionKeys.lastTap)
        if tapStamp > 0 { lastTapTime = Date(timeIntervalSince1970: tapStamp) }
        lastTappedEmotionName = defaults.string(forKey: SessionKeys.lastTappedEmotion)
        let stamp = defaults.double(forKey: SessionKeys.lastInteraction)
        if stamp > 0 { lastInteractionTime = Date(timeIntervalSince1970: stamp) }
        let startStamp = defaults.double(forKey: SessionKeys.sessionStart)
        if startStamp > 0 { sessionStartTime = Date(timeIntervalSince1970: startStamp) }
        // Backfill: in-flight session from before this field existed.
        if !emotionCounts.isEmpty && sessionStartTime == nil {
            sessionStartTime = lastInteractionTime ?? Date()
        }
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
        do {
            let data = try Data(contentsOf: journalFileURL)
            journalEntries = try JSONDecoder().decode([JournalEntry].self, from: data)
        } catch {
            print("EmotionStore load error: \(error)")
        }
    }
}
