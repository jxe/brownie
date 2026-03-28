import Foundation
import Observation

@Observable
class EmotionStore {
    var emotionCounts: [String: Int] = [:]
    var inFlightEmotions: Set<String> = []
    private(set) var journalEntries: [JournalEntry] = []

    init() {
        load()
    }

    func tap(_ emotion: Emotion) {
        emotionCounts[emotion.name, default: 0] += 1
    }

    func deselect(_ emotion: Emotion) {
        emotionCounts.removeValue(forKey: emotion.name)
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
        deselect(emotion)
        save()
    }

    func deleteEntry(_ entry: JournalEntry) {
        journalEntries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: - Persistence

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
