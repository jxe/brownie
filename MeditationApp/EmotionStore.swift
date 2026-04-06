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
    }

    init() {
        load()
        loadSession()
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
            emotionName: emotion.name,
            emoji: emotion.emoji,
            question: emotion.question,
            answer: answer,
            timestamp: Date()
        )
        journalEntries.insert(entry, at: 0)
        save()
    }

    func deleteEntry(_ entry: JournalEntry) {
        journalEntries.removeAll { $0.id == entry.id }
        save()
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
        do {
            let data = try Data(contentsOf: journalFileURL)
            journalEntries = try JSONDecoder().decode([JournalEntry].self, from: data)
        } catch {
            print("EmotionStore load error: \(error)")
        }
    }
}
