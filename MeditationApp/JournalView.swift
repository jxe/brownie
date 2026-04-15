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
