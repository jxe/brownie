import Foundation
import Observation

@Observable
class EmotionStore {
    static let maxEmotionCreditDuration: TimeInterval = 20
    private static let rankingScoreHalfLife: TimeInterval = 10 * 60

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
    private var emotionSelectionOrdinals: [String: Int] = [:]
    private var emotionRankingScores: [String: Double] = [:]
    private var nextSelectionOrdinal = 0
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
        static let emotionSelectionOrdinals = "checkin_emotionSelectionOrdinals"
        static let emotionRankingScores = "checkin_emotionRankingScores"
        static let nextSelectionOrdinal = "checkin_nextSelectionOrdinal"
        static let lastInteraction = "checkin_lastInteractionTime"
        static let sessionStart = "checkin_sessionStartTime"
        static let recentMeditationPlays = "recentMeditationPlays"
        static let deprecatedEmotionRecentContributions = "checkin_emotionRecentContributions"
        static let deprecatedRecentContributionsUpdatedAt = "checkin_recentContributionsUpdatedAt"
        static let deprecatedEmotionLastTapOrdinals = "checkin_emotionLastTapOrdinals"
        static let deprecatedNextTapOrdinal = "checkin_nextTapOrdinal"
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
        recordSelection(of: emotion)
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
        addRankingCredit(to: emotionName, duration: credit)
        return TimeCredit(
            emotionID: emotionName,
            totalContribution: emotionTimeContributions[emotionName, default: 0]
        )
    }

    private func recordSelection(of emotion: Emotion) {
        if emotionSelectionOrdinals[emotion.name] == nil {
            nextSelectionOrdinal += 1
            emotionSelectionOrdinals[emotion.name] = nextSelectionOrdinal
        }
        if emotionRankingScores[emotion.name] == nil {
            emotionRankingScores[emotion.name] = 0
        }
    }

    func deselect(_ emotion: Emotion) {
        emotionCounts.removeValue(forKey: emotion.name)
        emotionTimeContributions.removeValue(forKey: emotion.name)
        emotionSelectionOrdinals.removeValue(forKey: emotion.name)
        emotionRankingScores.removeValue(forKey: emotion.name)
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

    /// Selected emotions for the main check-in grid. The hidden ranking score is
    /// an exponential moving share of committed feeling time with a ten-minute
    /// half-life. This is equivalent to making each new second worth twice as
    /// much after every ten minutes of total credited time. Live accrual is
    /// deliberately excluded until it is committed.
    func selectedEmotionsRankedForCheckIn() -> [Emotion] {
        let selected = Emotion.all.filter { isSelected($0) }
        guard selected.count > 1 else { return selected }

        return selected.sorted { lhs, rhs in
            let lhsScore = emotionRankingScores[lhs.name, default: 0]
            let rhsScore = emotionRankingScores[rhs.name, default: 0]
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return selectionOrder(lhs, rhs)
        }
    }

    private func addRankingCredit(to emotionName: String, duration: TimeInterval) {
        let retainedShare = pow(0.5, duration / Self.rankingScoreHalfLife)
        emotionRankingScores = emotionRankingScores.mapValues { $0 * retainedShare }
        emotionRankingScores[emotionName, default: 0] += 1 - retainedShare
    }

    private func selectionOrder(_ lhs: Emotion, _ rhs: Emotion) -> Bool {
        let lhsSelection = emotionSelectionOrdinals[lhs.name, default: .max]
        let rhsSelection = emotionSelectionOrdinals[rhs.name, default: .max]
        if lhsSelection != rhsSelection { return lhsSelection < rhsSelection }
        return lhs.name < rhs.name
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

    func hasReflectionInCurrentSession(for emotion: Emotion) -> Bool {
        guard let sessionStartTime else { return false }
        return journalEntries.contains { entry in
            guard case .reflection(let reflection) = entry.content else { return false }
            return entry.timestamp >= sessionStartTime && reflection.emotionName == emotion.name
        }
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
        emotionSelectionOrdinals = [:]
        emotionRankingScores = [:]
        nextSelectionOrdinal = 0
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
        defaults.set(emotionSelectionOrdinals, forKey: SessionKeys.emotionSelectionOrdinals)
        defaults.set(emotionRankingScores, forKey: SessionKeys.emotionRankingScores)
        defaults.set(nextSelectionOrdinal, forKey: SessionKeys.nextSelectionOrdinal)
        defaults.removeObject(forKey: SessionKeys.deprecatedEmotionRecentContributions)
        defaults.removeObject(forKey: SessionKeys.deprecatedRecentContributionsUpdatedAt)
        defaults.removeObject(forKey: SessionKeys.deprecatedEmotionLastTapOrdinals)
        defaults.removeObject(forKey: SessionKeys.deprecatedNextTapOrdinal)
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
        if let ordinals = defaults.dictionary(forKey: SessionKeys.emotionSelectionOrdinals) as? [String: Int] {
            emotionSelectionOrdinals = ordinals
        }
        let loadedRankingScores: Bool
        if let scores = defaults.dictionary(forKey: SessionKeys.emotionRankingScores) as? [String: Double] {
            emotionRankingScores = scores
            loadedRankingScores = true
        } else {
            loadedRankingScores = false
        }
        nextSelectionOrdinal = defaults.integer(forKey: SessionKeys.nextSelectionOrdinal)
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
        let rankingMetadataChanged = backfillRankingMetadataIfNeeded()
        let rankingScoresChanged = repairRankingScores(backfillFromTime: !loadedRankingScores)
        if rankingMetadataChanged || rankingScoresChanged {
            saveSession()
        } else {
            defaults.removeObject(forKey: SessionKeys.deprecatedEmotionRecentContributions)
            defaults.removeObject(forKey: SessionKeys.deprecatedRecentContributionsUpdatedAt)
            defaults.removeObject(forKey: SessionKeys.deprecatedEmotionLastTapOrdinals)
            defaults.removeObject(forKey: SessionKeys.deprecatedNextTapOrdinal)
        }
    }

    /// Sessions saved before selection metadata existed retain their prior
    /// deterministic time order.
    private func backfillRankingMetadataIfNeeded() -> Bool {
        let selected = selectedEmotionsSorted()
        let selectedIDs = Set(selected.map(\.id))
        let selectionIDs = Set(emotionSelectionOrdinals.keys)

        guard selectedIDs != selectionIDs else {
            let repairedOrdinal = max(nextSelectionOrdinal, emotionSelectionOrdinals.values.max() ?? 0)
            let changed = repairedOrdinal != nextSelectionOrdinal
            nextSelectionOrdinal = repairedOrdinal
            return changed
        }

        emotionSelectionOrdinals = [:]
        for (index, emotion) in selected.enumerated() {
            emotionSelectionOrdinals[emotion.name] = index + 1
        }
        nextSelectionOrdinal = selected.count
        return true
    }

    /// Existing sessions predate the hidden score, so preserve their ordering by
    /// treating each emotion's committed-time share as its initial score. Future
    /// credits then converge naturally to the new exponential weighting.
    private func repairRankingScores(backfillFromTime: Bool) -> Bool {
        let selectedIDs = Set(Emotion.all.filter { isSelected($0) }.map(\.id))
        let previousScores = emotionRankingScores

        emotionRankingScores = emotionRankingScores.filter { selectedIDs.contains($0.key) }
        if backfillFromTime {
            let committedTime = emotionTimeContributions.values.reduce(0, +)
            emotionRankingScores = Dictionary(uniqueKeysWithValues: selectedIDs.map { emotionID in
                let score = committedTime > 0
                    ? emotionTimeContributions[emotionID, default: 0] / committedTime
                    : 0
                return (emotionID, score)
            })
        } else {
            for emotionID in selectedIDs where emotionRankingScores[emotionID] == nil {
                emotionRankingScores[emotionID] = 0
            }
        }

        return emotionRankingScores != previousScores
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
