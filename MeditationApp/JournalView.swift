import SwiftUI

struct JournalView: View {
    @Environment(EmotionStore.self) private var store

    private var markdownExport: String {
        store.journalEntries.map { entry in
            let dateStr = entry.timestamp.formatted(date: .long, time: .shortened)
            return """
            # \(entry.emoji) \(entry.emotionName) — \(dateStr)

            **Question:** \(entry.question)

            **Reflection:** \(entry.answer)
            """
        }.joined(separator: "\n\n---\n\n")
    }

    var body: some View {
        NavigationStack {
            List {
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
                    Section("Past Reflections") {
                        ForEach(store.journalEntries) { entry in
                            JournalEntryRow(entry: entry)
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
                        "No Reflections Yet",
                        systemImage: "book.closed",
                        description: Text("Start a check-in to identify what you're feeling, then come here to reflect.")
                    )
                }
            }
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

private struct JournalEntryRow: View {
    let entry: JournalEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(entry.emoji)
                Text(entry.emotionName)
                    .font(.body)
                    .fontWeight(.medium)
                Spacer()
                Text(entry.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.question)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(entry.answer)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 3)
                .foregroundStyle(.primary)

            if !isExpanded && entry.answer.count > 120 {
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
