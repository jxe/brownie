import SwiftUI

struct JournalView: View {
    @Environment(EmotionStore.self) private var store

    private var markdownExport: String {
        store.journalEntries.map { entry in
            let dateStr = entry.timestamp.formatted(date: .long, time: .shortened)
            switch entry.content {
            case .reflection(let r):
                return """
                # \(r.emoji) \(r.emotionName) — \(dateStr)

                **Question:** \(r.question)

                **Reflection:** \(r.answer)
                """
            case .meditation(let m):
                return """
                # 🧘 \(m.title) — \(dateStr)

                **Meditation:** Helped
                """
            case .checkInSession(let s):
                let startStr = s.startedAt.formatted(date: .omitted, time: .shortened)
                let endStr = entry.timestamp.formatted(date: .omitted, time: .shortened)
                let spanMin = max(1, Int((entry.timestamp.timeIntervalSince(s.startedAt) / 60).rounded()))
                let engagedMin = Int(s.engagementSeconds) / 60
                let engagedSec = Int(s.engagementSeconds) % 60
                let engagedStr = String(format: "%d:%02d", engagedMin, engagedSec)
                let lines = s.emotions.map { "- \($0.emoji) \($0.name) ×\($0.count)" }.joined(separator: "\n")
                return """
                # 🪷 Check-in — \(dateStr)

                **Span:** \(startStr)–\(endStr) (\(spanMin) min)
                **Engaged:** \(engagedStr)

                \(lines)
                """
            }
        }.joined(separator: "\n\n---\n\n")
    }

    var body: some View {
        NavigationStack {
            List {
                // Streak banner
                let streak = store.currentMeditationStreak
                if streak >= 2 {
                    Section {
                        HStack {
                            Text("🔥")
                            Text("\(streak)-day meditation streak")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Reflect section
                if !store.selectedEmotionsSorted().isEmpty {
                    Section("Reflect") {
                        ForEach(store.selectedEmotionsSorted()) { emotion in
                            NavigationLink(value: emotion) {
                                HStack(spacing: 10) {
                                    Text(emotion.emoji)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(emotion.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                            Text("(\(store.count(for: emotion)))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(emotion.question)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                // Past entries section
                if !store.journalEntries.isEmpty {
                    Section("Past Entries") {
                        ForEach(store.journalEntries) { entry in
                            switch entry.content {
                            case .reflection(let r):
                                ReflectionEntryRow(entry: entry, reflection: r)
                            case .meditation(let m):
                                MeditationLogRow(entry: entry, meditation: m)
                            case .checkInSession(let s):
                                CheckInSessionRow(entry: entry, session: s)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.deleteEntry(store.journalEntries[index])
                            }
                        }
                    }
                }

                // Empty state
                if store.selectedEmotionsSorted().isEmpty && store.journalEntries.isEmpty {
                    ContentUnavailableView(
                        "No Entries Yet",
                        systemImage: "book.closed",
                        description: Text("Start a check-in to identify what you're feeling, or mark a meditation as helpful after listening.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color("BackgroundColor"))
            .navigationTitle("Journal")
            .navigationDestination(for: Emotion.self) { emotion in
                ReflectionView(emotion: emotion)
            }
            .toolbar {
                if !store.journalEntries.isEmpty {
                    ShareLink(
                        item: markdownExport,
                        subject: Text("Emotion Journal"),
                        message: Text("My emotional reflections")
                    )
                }
            }
        }
    }
}

private struct ReflectionEntryRow: View {
    let entry: JournalEntry
    let reflection: JournalEntry.Content.Reflection
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(reflection.emoji)
                Text(reflection.emotionName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(entry.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(reflection.question)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reflection.answer)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.primary)

            if !isExpanded && reflection.answer.count > 120 {
                Button("Show more") {
                    withAnimation { isExpanded = true }
                }
                .font(.caption)
            } else if isExpanded {
                Button("Show less") {
                    withAnimation { isExpanded = false }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MeditationLogRow: View {
    let entry: JournalEntry
    let meditation: JournalEntry.Content.Meditation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(meditation.title)
                    .font(.body)
                    .fontWeight(.medium)
                Text("Meditation helped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.timestamp, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInSessionRow: View {
    let entry: JournalEntry
    let session: JournalEntry.Content.CheckInSession

    private var topEmotions: ArraySlice<JournalEntry.Content.CheckInSession.EmotionTally> {
        session.emotions.prefix(5)
    }

    private var moreCount: Int {
        max(0, session.emotions.count - 5)
    }

    private var engagedString: String {
        let total = Int(session.engagementSeconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var spanMinutes: Int {
        max(1, Int((entry.timestamp.timeIntervalSince(session.startedAt) / 60).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Check-in")
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(entry.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                ForEach(Array(topEmotions), id: \.name) { tally in
                    HStack(spacing: 3) {
                        Text(tally.emoji)
                        Text("\(tally.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                if moreCount > 0 {
                    Text("+\(moreCount) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text("\(engagedString) engaged · \(spanMinutes) min span")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
