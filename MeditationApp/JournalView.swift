import SwiftUI

struct JournalView: View {
    @Environment(EmotionStore.self) private var store
    @State private var navigationPath = NavigationPath()

    /// Every filled-in action of every open to-do, one row each.
    private var openActions: [(todo: FeelingTodo, action: FeelingTodo.Action)] {
        store.openTodos.flatMap { todo in
            todo.filledActions.map { (todo: todo, action: $0) }
        }
    }

    /// Open feelings with no actions yet: open to-dos without any, then this
    /// session's feelings that have no to-do.
    private var otherOpenEmotions: [Emotion] {
        let withoutActions = store.openTodos
            .filter { $0.filledActions.isEmpty }
            .compactMap { Emotion.named($0.emotionName) }
        let rest = store.selectedEmotionsSorted().filter { store.openTodo(for: $0) == nil }
        return withoutActions + rest
    }

    /// Journal entries and done to-dos, newest first.
    private var pastRows: [PastRow] {
        (store.journalEntries.map(PastRow.entry) + store.doneTodos.map(PastRow.todo))
            .sorted { $0.date > $1.date }
    }

    private var markdownExport: String {
        pastRows.map { row -> String in
            let entry: JournalEntry
            switch row {
            case .entry(let e):
                entry = e
            case .todo(let t):
                let dateStr = (t.doneAt ?? t.createdAt).formatted(date: .long, time: .shortened)
                return """
                # \(t.emoji) \(t.emotionName) to-do — \(dateStr)

                **Question:** \(t.question)

                **\(t.concernPrompt):** \(t.concern)

                **Long-term value or change:** \(t.value)

                **Did:**
                \(t.filledActions.map { "- \($0.sentence)" }.joined(separator: "\n"))
                """
            }
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
                let engagedStr = JournalTimeFormatter.string(from: s.engagementSeconds)
                let lines = s.emotions.map { tally in
                    let countString = "×\(tally.count)"
                    if let seconds = tally.engagementSeconds, seconds > 0 {
                        return "- \(tally.emoji) \(tally.name) \(JournalTimeFormatter.string(from: seconds)) (\(countString))"
                    }
                    return "- \(tally.emoji) \(tally.name) \(countString)"
                }.joined(separator: "\n")
                return """
                # 🪷 Check-in — \(dateStr)

                **Engaged:** \(engagedStr)

                \(lines)
                """
            }
        }.joined(separator: "\n\n---\n\n")
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
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

                // Open to-dos section
                if !openActions.isEmpty {
                    Section("Open To-dos") {
                        ForEach(openActions, id: \.action.id) { item in
                            if let emotion = Emotion.named(item.todo.emotionName) {
                                NavigationLink(value: emotion) {
                                    OpenActionRow(todo: item.todo, action: item.action)
                                }
                            }
                        }
                    }
                }

                // Feelings still open but without actions, together in one row
                if !otherOpenEmotions.isEmpty {
                    Section("Open Feelings") {
                        OpenFeelingsRow(emotions: otherOpenEmotions) { emotion in
                            navigationPath.append(emotion)
                        }
                    }
                }

                // Past entries section
                if !pastRows.isEmpty {
                    Section("Past Entries") {
                        ForEach(pastRows) { row in
                            switch row {
                            case .todo(let todo):
                                DoneTodoRow(todo: todo)
                            case .entry(let entry):
                                switch entry.content {
                                case .reflection(let r):
                                    ReflectionEntryRow(entry: entry, reflection: r)
                                case .meditation(let m):
                                    MeditationLogRow(entry: entry, meditation: m)
                                case .checkInSession(let s):
                                    NavigationLink {
                                        CheckInSessionDetailView(entry: entry, session: s)
                                    } label: {
                                        CheckInSessionRow(entry: entry, session: s)
                                    }
                                }
                            }
                        }
                        .onDelete { indexSet in
                            let rows = pastRows
                            for index in indexSet {
                                switch rows[index] {
                                case .todo(let todo): store.deleteTodo(todo)
                                case .entry(let entry): store.deleteEntry(entry)
                                }
                            }
                        }
                    }
                }

                // Empty state
                if openActions.isEmpty && otherOpenEmotions.isEmpty && pastRows.isEmpty {
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
                FeelingTodoView(emotion: emotion)
            }
            .toolbar {
                NavigationLink {
                    EmotionLeaderboardView()
                } label: {
                    Label("Emotion Leaderboard", systemImage: "chart.bar.xaxis")
                }

                if !pastRows.isEmpty {
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

private struct EmotionLeaderboardView: View {
    @Environment(EmotionStore.self) private var store
    @State private var metric: Metric = .time
    @State private var order: Order = .most

    private enum Metric: String, CaseIterable, Identifiable {
        case time = "Time"
        case taps = "Taps"

        var id: Self { self }
    }

    private enum Order: String, CaseIterable, Identifiable {
        case most = "Most"
        case least = "Least"

        var id: Self { self }
    }

    private struct Standing: Identifiable {
        let name: String
        let emoji: String
        let seconds: TimeInterval
        let taps: Int

        var id: String { name }
    }

    private var standings: [Standing] {
        let historicalUsage = store.historicalEmotionUsage()
        var totals: [String: (emoji: String, seconds: TimeInterval, taps: Int)] =
            Dictionary(uniqueKeysWithValues: Emotion.all.map {
                let usage = historicalUsage[$0.name] ?? .init()
                return ($0.name, (
                    emoji: $0.emoji,
                    seconds: usage.engagementSeconds,
                    taps: usage.tapCount
                ))
            })

        for entry in store.journalEntries {
            guard case .checkInSession(let session) = entry.content else { continue }
            for tally in session.emotions {
                guard totals[tally.name] == nil else { continue }
                let usage = historicalUsage[tally.name] ?? .init()
                totals[tally.name] = (tally.emoji, usage.engagementSeconds, usage.tapCount)
            }
        }

        return totals.map { name, total in
            Standing(name: name, emoji: total.emoji, seconds: total.seconds, taps: total.taps)
        }
        .sorted { lhs, rhs in
            let lhsValue = metric == .time ? lhs.seconds : Double(lhs.taps)
            let rhsValue = metric == .time ? rhs.seconds : Double(rhs.taps)
            if lhsValue != rhsValue {
                return order == .most ? lhsValue > rhsValue : lhsValue < rhsValue
            }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Measure", selection: $metric) {
                    ForEach(Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Order", selection: $order) {
                    ForEach(Order.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(Array(standings.enumerated()), id: \.element.id) { index, standing in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)

                        Text(standing.emoji)
                            .font(.title3)

                        Text(standing.name)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(primaryValue(for: standing))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text(secondaryValue(for: standing))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Totals from completed check-ins. Emotions not yet used appear with zero totals; historical emotions remain visible.")
            }
        }
        .navigationTitle("Emotion Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func primaryValue(for standing: Standing) -> String {
        if metric == .time {
            return JournalTimeFormatter.string(from: standing.seconds)
        }
        return "\(standing.taps) taps"
    }

    private func secondaryValue(for standing: Standing) -> String {
        if metric == .time {
            return "\(standing.taps) taps"
        }
        return JournalTimeFormatter.string(from: standing.seconds)
    }
}

private extension JournalView {
    func reflectDetail(for emotion: Emotion) -> String {
        let seconds = store.timeContribution(for: emotion)
        let count = store.count(for: emotion)
        if seconds > 0 {
            return "\(JournalTimeFormatter.string(from: seconds)) · ×\(count)"
        }
        return "×\(count)"
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
        session.emotions.prefix(4)
    }

    private var moreCount: Int {
        max(0, session.emotions.count - 4)
    }

    private var engagedString: String {
        JournalTimeFormatter.string(from: session.engagementSeconds)
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
                        Text(tally.summaryString)
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

            Text("\(engagedString) engaged")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CheckInSessionDetailView: View {
    let entry: JournalEntry
    let session: JournalEntry.Content.CheckInSession

    private var startString: String {
        session.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var endString: String {
        entry.timestamp.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Engaged", value: JournalTimeFormatter.string(from: session.engagementSeconds))
                LabeledContent("Started", value: startString)
                LabeledContent("Ended", value: endString)
            }

            Section("Emotions") {
                ForEach(session.emotions, id: \.name) { tally in
                    HStack(spacing: 10) {
                        Text(tally.emoji)
                            .font(.title3)
                        Text(tally.name)
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tally.detailTimeString)
                                .font(.body)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("×\(tally.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension JournalEntry.Content.CheckInSession.EmotionTally {
    var summaryString: String {
        if let engagementSeconds, engagementSeconds > 0 {
            return JournalTimeFormatter.string(from: engagementSeconds)
        }
        return "\(count)"
    }

    var detailTimeString: String {
        if let engagementSeconds, engagementSeconds > 0 {
            return JournalTimeFormatter.string(from: engagementSeconds)
        }
        return "No time"
    }
}

private enum JournalTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 {
            return "\(total)s"
        }

        let roundedMinutes = (Double(total) / 60 * 10).rounded() / 10
        if roundedMinutes.rounded() == roundedMinutes {
            return "\(Int(roundedMinutes))m"
        }
        return String(format: "%.1fm", roundedMinutes)
    }
}

private enum PastRow: Identifiable {
    case entry(JournalEntry)
    case todo(FeelingTodo)

    var id: UUID {
        switch self {
        case .entry(let entry): entry.id
        case .todo(let todo): todo.id
        }
    }

    var date: Date {
        switch self {
        case .entry(let entry): entry.timestamp
        case .todo(let todo): todo.doneAt ?? todo.createdAt
        }
    }
}

private struct OpenActionRow: View {
    let todo: FeelingTodo
    let action: FeelingTodo.Action

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Text(action.verb.label).fontWeight(.semibold).foregroundStyle(.tint)) \(action.object.trimmingCharacters(in: .whitespacesAndNewlines))")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(todo.emoji) \(todo.emotionName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            TodoStateMark(state: todo.state)
                .frame(width: 14, height: 14)
                .accessibilityLabel(todo.state.label)
        }
    }
}

private struct OpenFeelingsRow: View {
    let emotions: [Emotion]
    var onSelect: (Emotion) -> Void
    @Environment(EmotionStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emotions) { emotion in
                    Button {
                        onSelect(emotion)
                    } label: {
                        HStack(spacing: 4) {
                            Text(emotion.emoji)
                            Text(emotion.name)
                                .font(.subheadline)
                            if let todo = store.openTodo(for: emotion) {
                                TodoStateMark(state: todo.state)
                                    .frame(width: 10, height: 10)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color("HighlightColor")))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct DoneTodoRow: View {
    let todo: FeelingTodo
    @Environment(EmotionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(todo.emoji)
                Text(todo.emotionName)
                    .fontWeight(.medium)
                Spacer()
                Text((todo.doneAt ?? todo.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(todo.filledActions) { action in
                Label(action.sentence, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
            }
            Text("\(todo.concernPrompt): \(todo.concern)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Toward: \(todo.value)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !store.openTodos.contains(where: { $0.emotionName == todo.emotionName }) {
                Button {
                    store.reopenTodo(todo)
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }
}
