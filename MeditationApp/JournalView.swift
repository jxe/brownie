import SwiftUI

/// The left panel: History (streak, leaderboard and past eras rows, past entries by day), with Settings
/// as a toolbar button.
struct JournalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(EmotionStore.self) private var store
    @Environment(\.openFromPanel) private var openFromPanel
    @Environment(\.closePanel) private var closePanel
    @State private var eraIndex = EraIndex()

    /// Eras before the current one, newest first, then what was made before the first era.
    private var pastEras: [EraSelection] {
        guard !eraIndex.eras.isEmpty else { return [] }
        return eraIndex.eras.dropFirst().map { .era($0.id) } + [.older]
    }

    @Environment(MeditationPlayer.self) private var player

    private var pastRows: [PastRow] { PastRow.all(in: store, listening: player.listeningHistory) }

    /// Past rows grouped by the day they happened, newest day first.
    private var pastDays: [(day: Date, rows: [PastRow])] {
        let calendar = Calendar.current
        var days: [(day: Date, rows: [PastRow])] = []
        for row in pastRows {
            let day = calendar.startOfDay(for: row.date)
            if days.last?.day == day {
                days[days.count - 1].rows.append(row)
            } else {
                days.append((day, [row]))
            }
        }
        return days
    }

    /// "Today", "Yesterday", then "Tue 24 Nov" (with the year once it isn't this one).
    private func dayHeader(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let weekday = day.formatted(.dateTime.weekday(.abbreviated))
        let dayMonth = day.formatted(.dateTime.day().month(.abbreviated))
        let sameYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return "\(weekday) \(dayMonth)" + (sameYear ? "" : " \(day.formatted(.dateTime.year()))")
    }

    /// Closes the panel first, then starts it once the main screen is in front, so the bar
    /// comes up (or the row drops into it) the way it does from the main screen, not in the
    /// middle of the slide.
    private func play(_ url: URL) {
        guard player.currentSourceURL != url,
              let content = FileManager.default.readMeditation(at: url) else {
            closePanel {}
            return
        }
        let meditation = MeditationParser.parse(content)
        closePanel { player.play(meditation, sourceURL: url) }
    }

    /// One line per past row; a tap opens its details on the main screen. Every row ends in
    /// the same slot (a chevron, a play glyph, or nothing), so all the times share one edge.
    @ViewBuilder
    private func historyRow(_ row: PastRow) -> some View {
        if case .listened(_, _, let url?) = row {
            // A meditation listened to a lot plays again, and the panel closes onto its bar.
            Button { play(url) } label: {
                PanelRowLabel(accessory: .play) { PastRowLine(row: row) }
            }
            .tint(.primary)
        } else if let page = row.page {
            Button { openFromPanel(page) } label: {
                PanelRowLabel(accessory: .chevron) { PastRowLine(row: row) }
            }
            // A list tints button text with the accent color; these read as plain rows.
            .tint(.primary)
        } else {
            PanelRowLabel(accessory: .none) { PastRowLine(row: row) }
        }
    }

    /// The panel's rows: no separators (days are set apart by space instead) and the
    /// same insets everywhere.
    static let rowInsets = EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)

    private var sidebarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.14, blue: 0.14)
            : Color(red: 0.95, green: 0.945, blue: 0.935)
    }

    var body: some View {
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
                    .listRowBackground(Color.clear)
                }
            }

            // Which feelings have taken the most time, over every check-in
            // The panel's links to its own pages, together on one card so they read as
            // navigation rather than history.
            Section {
                VStack(spacing: 0) {
                    Button { openFromPanel(.leaderboard) } label: {
                        PanelNavLabel(title: "Emotion Leaderboard", systemImage: "chart.bar")
                    }
                    // Earlier eras, on a page of their own
                    if !pastEras.isEmpty {
                        Divider().padding(.leading, 44)
                        Button { openFromPanel(.pastEras) } label: {
                            PanelNavLabel(title: "Past Eras", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                // A list tints button text with the accent color; these read as plain rows.
                .tint(.primary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            // Past entries, under a header for each day
            ForEach(pastDays, id: \.day) { day in
                Section {
                    ForEach(day.rows) { row in
                        historyRow(row)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(Self.rowInsets)
                    }
                } header: {
                    Text(dayHeader(day.day))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                }
            }

            // Empty state
            if pastRows.isEmpty && pastEras.isEmpty {
                ContentUnavailableView(
                    "Nothing Here Yet",
                    systemImage: "clock",
                    description: Text("Finished to-dos, check-ins, and meditations that helped show up here.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListHeaderHeight, 0)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(sidebarColor)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(sidebarColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { eraIndex = EraIndex.load() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { openFromPanel(.settings) } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
}

/// The To-dos page, opened from its card on the main screen.
struct TodosView: View {
    @Environment(\.appPalette) private var palette
    @Environment(EmotionStore.self) private var store
    @State private var openedTodo: FeelingTodo?

    var body: some View {
        List {
            OpenTodosSection { openedTodo = $0 }
            if store.openTodos.isEmpty {
                ContentUnavailableView(
                    "Nothing Open",
                    systemImage: "checkmark.circle",
                    description: Text("Swipe a feeling left on the Feelings page to make a to-do from it.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.canvas)
        .navigationTitle("To-dos")
        .navigationDestination(item: $openedTodo) { todo in
            if let emotion = Emotion.named(todo.emotionName) {
                FeelingTodoView(emotion: emotion, todoID: todo.id)
            }
        }
    }
}

/// Open to-dos for the To-dos page: one row per open action, and one row for each
/// to-do that has no action yet.
struct OpenTodosSection: View {
    @Environment(EmotionStore.self) private var store
    var onOpen: (FeelingTodo) -> Void

    /// Every filled-in action of every open to-do, one row each.
    private var openActions: [(todo: FeelingTodo, action: FeelingTodo.Action)] {
        store.openTodos.flatMap { todo in
            todo.openActions.map { (todo: todo, action: $0) }
        }
    }

    private var todosWithoutActions: [FeelingTodo] {
        store.openTodos.filter { $0.openActions.isEmpty }
    }

    var body: some View {
        if !openActions.isEmpty {
            Section("To-dos") {
                ForEach(openActions, id: \.action.id) { item in
                    if Emotion.named(item.todo.emotionName) != nil {
                        HStack {
                            OpenActionRow(todo: item.todo, action: item.action) {
                                store.toggleActionDone(item.action.id, in: item.todo.id)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(item.todo) }
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button {
                                store.toggleActionDone(item.action.id, in: item.todo.id)
                            } label: {
                                Label("Mark Done", systemImage: "checkmark.circle")
                            }
                            Button {
                                UIPasteboard.general.string = item.action.sentence
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.toggleActionDone(item.action.id, in: item.todo.id)
                            } label: {
                                Label("Done", systemImage: "checkmark")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }
        }

        if !todosWithoutActions.isEmpty {
            Section("Needs an Action") {
                ForEach(todosWithoutActions) { todo in
                    if Emotion.named(todo.emotionName) != nil {
                        HStack(spacing: 10) {
                            Text(todoSource(todo))
                                .lineLimit(1)
                            Spacer()
                            TodoStateMark(state: todo.state)
                                .frame(width: 14, height: 14)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(todo) }
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
    }
}

struct EmotionLeaderboardView: View {
    @Environment(\.appPalette) private var palette
    @Environment(EmotionStore.self) private var store

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
        // Most time first; taps break ties.
        .sorted { lhs, rhs in
            if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
            if lhs.taps != rhs.taps { return lhs.taps > rhs.taps }
            return lhs.name < rhs.name
        }
    }

    var body: some View {
        List {
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
                            Text(JournalTimeFormatter.string(from: standing.seconds))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("\(standing.taps) taps")
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
        .scrollContentBackground(.hidden)
        .background(palette.panel)
        .navigationTitle("Emotion Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
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

struct CheckInSessionDetailView: View {
    @Environment(\.appPalette) private var palette
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
        .scrollContentBackground(.hidden)
        .background(palette.panel)
        .navigationTitle("Check-in")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension JournalEntry.Content.CheckInSession.EmotionTally {
    var detailTimeString: String {
        if let engagementSeconds, engagementSeconds > 0 {
            return JournalTimeFormatter.string(from: engagementSeconds)
        }
        return "No time"
    }
}

/// "45s", "38m", "1h 38m", "2h".
private enum JournalTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }
}

private enum PastRow: Identifiable {
    case entry(JournalEntry)
    case todo(FeelingTodo)
    /// A day a meditation was listened to for `longListenSeconds` or more; `title` is its
    /// title, or its filename once the file is gone (and `url` nil).
    case listened(ListeningHistory.DayListening, title: String, url: URL?)

    /// A day's listening to one meditation that earns a row of its own.
    static let longListenSeconds: TimeInterval = 30 * 60

    /// Journal entries, done to-dos and long listens, newest first.
    static func all(in store: EmotionStore, listening: ListeningHistory) -> [PastRow] {
        let listens = listening.days(atLeast: longListenSeconds).map { day in
            let file = meditationFile(day.filename)
            return PastRow.listened(day, title: file?.title ?? day.filename, url: file?.url)
        }
        return (store.journalEntries.map(PastRow.entry) + store.doneTodos.map(PastRow.todo) + listens)
            .sorted { $0.date > $1.date }
    }

    /// The meditation's file, here or archived, and its title; nil if it's gone.
    private static func meditationFile(_ filename: String) -> (url: URL, title: String)? {
        let directory = FileManager.default.meditationsDirectory
        for url in [directory.appendingPathComponent(filename + ".med"),
                    directory.appendingPathComponent("Archive").appendingPathComponent(filename + ".med")] {
            if let content = FileManager.default.readMeditation(at: url) {
                let title = MeditationParser.parseMetadata(content).title
                return (url, title.isEmpty ? filename : title)
            }
        }
        return nil
    }

    /// The page its tap opens on the main screen. A meditation that helped has nothing more
    /// to show; one listened to a lot plays instead (see `JournalView.historyRow`).
    var page: PanelPage? {
        switch self {
        case .listened: return nil
        case .todo(let todo): return .todo(todo.id)
        case .entry(let entry):
            switch entry.content {
            case .checkInSession: return .checkIn(entry.id)
            case .reflection: return .reflection(entry.id)
            case .meditation: return nil
            }
        }
    }

    var id: String {
        switch self {
        case .entry(let entry): entry.id.uuidString
        case .todo(let todo): todo.id.uuidString
        case .listened(let day, _, _): "\(day.filename) \(ListeningHistory.dayKey(day.day))"
        }
    }

    var date: Date {
        switch self {
        case .entry(let entry): entry.timestamp
        case .todo(let todo): todo.doneAt ?? todo.createdAt
        case .listened(let day, _, _): day.lastListened
        }
    }
}

private struct OpenActionRow: View {
    let todo: FeelingTodo
    let action: FeelingTodo.Action
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onDone) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Mark done")
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Text(action.verb.label).fontWeight(.semibold).foregroundStyle(.tint)) \(action.object.trimmingCharacters(in: .whitespacesAndNewlines))")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(todoSource(todo))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            TodoStateMark(state: todo.state)
                .frame(width: 14, height: 14)
                .accessibilityLabel(todo.state.label)
        }
    }
}

/// "😠 Anger · Nov 6, with 😢🙏": the feeling, the day, and the rest of that session.
private func todoSource(_ todo: FeelingTodo) -> String {
    let day = (todo.sessionStartedAt ?? todo.createdAt).formatted(.dateTime.month(.abbreviated).day())
    let companions = todo.companionEmojis
    return "\(todo.emoji) \(todo.emotionName) · \(day)" + (companions.isEmpty ? "" : ", with \(companions)")
}

/// A past row on one line, with any detail in gray on the right: a check-in's feelings as
/// coloured tiles … "12m"; "Call Sam" … its feeling's tile; "Body scan"; "Body scan" … "45m";
/// an old reflection's tile and "Anger". No emoji marks the kind of row.
private struct PastRowLine: View {
    let row: PastRow

    private typealias Feeling = (name: String, emoji: String)

    var body: some View {
        switch row {
        case .listened(let day, let name, _):
            line { title(name) } detail: { time(day.seconds) }
        case .todo(let todo):
            line { title(todo.filledActions.first?.sentence ?? todo.emotionName) } detail: {
                EmotionTile(name: todo.emotionName, emoji: todo.emoji)
            }
        case .entry(let entry):
            switch entry.content {
            case .checkInSession(let s):
                line {
                    if s.emotions.isEmpty {
                        title("Check-in")
                    } else {
                        HStack(spacing: 4) {
                            ForEach(Array(s.emotions.prefix(4)), id: \.name) { tally in
                                EmotionTile(name: tally.name, emoji: tally.emoji)
                            }
                        }
                    }
                } detail: { time(s.engagementSeconds) }
            case .meditation(let m):
                line { title(m.title) } detail: { EmptyView() }
            case .reflection(let r):
                line {
                    HStack(spacing: 8) {
                        EmotionTile(name: r.emotionName, emoji: r.emoji)
                        title(r.emotionName)
                    }
                } detail: { EmptyView() }
            }
        }
    }

    private func line<Main: View, Detail: View>(@ViewBuilder _ main: () -> Main,
                                                @ViewBuilder detail: () -> Detail) -> some View {
        HStack(spacing: 8) {
            main()
            Spacer(minLength: 4)
            detail()
                .layoutPriority(1)
        }
        .frame(minHeight: EmotionTile.height)
        .padding(.vertical, 2)
    }

    /// A row's words sit on a tile too, like the feelings' emoji, so every kind of row
    /// reads as the same kind of thing.
    private func title(_ text: String) -> some View {
        TitleTile(text: text)
    }

    private func time(_ seconds: TimeInterval) -> some View {
        Text(JournalTimeFormatter.string(from: seconds))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
    }
}

/// A row's title on a rounded tile the height and corner of an `EmotionTile`, filled with
/// the main screen's meditation card colour lightened the way the emotion tiles are.
private struct TitleTile: View {
    let text: String
    @Environment(\.appPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = palette.card.mix(
            with: .white,
            by: colorScheme == .dark ? EmotionTile.darkLightening : EmotionTile.lightLightening
        )
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .frame(height: EmotionTile.height)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: [base.mix(with: .white, by: colorScheme == .dark ? 0.10 : 0.22), base],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
    }
}

/// A feeling's emoji on a small rounded tile in a lighter shade of that feeling's chip colour
/// (`Emotion.chipColor`, as on the Feelings page and the home header), lighter still at the top.
/// A feeling no longer in `Emotion.all` gets a neutral tile.
private struct EmotionTile: View {
    static let height: CGFloat = 26
    let name: String
    let emoji: String
    @Environment(\.colorScheme) private var colorScheme

    /// Lighter than the chips' colour: on a tile this small the full colour reads too heavy.
    private var base: Color {
        guard let chip = Emotion.named(name)?.chipColor(for: colorScheme) else {
            return Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
        }
        return chip.mix(with: .white, by: colorScheme == .dark ? Self.darkLightening : Self.lightLightening)
    }

    /// How far a tile's colour is mixed toward white from the chips' colour.
    static let lightLightening = 0.35
    static let darkLightening = 0.12

    var body: some View {
        Text(emoji)
            .font(.system(size: 15))
            .frame(width: 32, height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(
                        colors: [base.mix(with: .white, by: colorScheme == .dark ? 0.10 : 0.22), base],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
            .accessibilityLabel(name)
    }
}

/// The Past Eras page, opened from History: each past era newest first, then what came
/// before the first one, with its date range, how many meditations it lists, and its
/// most-listened meditation. A tap opens the era's own page.
struct PastErasView: View {
    @Environment(\.appPalette) private var palette
    @Environment(MeditationPlayer.self) private var player
    @State private var eraIndex = EraIndex()
    @State private var summaries: [EraSelection: Summary] = [:]

    struct Summary {
        var count = 0
        var mostListened: String?
    }

    private var pastEras: [EraSelection] {
        guard !eraIndex.eras.isEmpty else { return [] }
        return eraIndex.eras.dropFirst().map { .era($0.id) } + [.older]
    }

    var body: some View {
        List {
            ForEach(pastEras, id: \.self) { era in
                NavigationLink(value: PanelPage.era(era)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(eraIndex.label(for: era))
                            if let title = summaries[era]?.mostListened {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if let count = summaries[era]?.count {
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.panel)
        .navigationTitle("Past Eras")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// Reads every meditation's title and tags off the main thread, then sums up each era.
    private func load() async {
        let index = EraIndex.load()
        eraIndex = index
        let metas: [(url: URL, title: String, tags: [String])] = await Task.detached {
            FileManager.default.meditationFiles().map { url in
                let meta = MeditationParser.parseMetadata(FileManager.default.readMeditation(at: url) ?? "")
                return (url, meta.title.isEmpty ? EraIndex.name(of: url) : meta.title, meta.tags)
            }
        }.value
        let tags = Dictionary(uniqueKeysWithValues: metas.map { ($0.url, $0.tags) })
        let titles = Dictionary(uniqueKeysWithValues: metas.map { ($0.url, $0.title) })
        let files = metas.map(\.url)
        let history = player.listeningHistory
        var result: [EraSelection: Summary] = [:]
        let eras: [EraSelection] = index.eras.isEmpty ? [] : index.eras.dropFirst().map { .era($0.id) } + [.older]
        for era in eras {
            let eraFiles = index.pastFiles(era, from: files) { tags[$0]?.contains(EraIndex.timelessTag) == true }
            let listened = eraFiles
                .map { ($0, history.record(for: EraIndex.name(of: $0), at: Date())?.totalSeconds ?? 0) }
                .filter { $0.1 > 0 }
                .max { $0.1 < $1.1 }
            result[era] = Summary(count: eraFiles.count, mostListened: listened.flatMap { titles[$0.0] })
        }
        summaries = result
    }
}

/// A finished to-do opened from History: what it was about, and what was done.
struct DoneTodoDetailView: View {
    @Environment(\.appPalette) private var palette
    @Environment(EmotionStore.self) private var store
    let todo: FeelingTodo

    var body: some View {
        List {
            Section {
                LabeledContent("Feeling", value: "\(todo.emoji) \(todo.emotionName)")
                if let doneAt = todo.doneAt {
                    LabeledContent("Done", value: doneAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("Did") {
                ForEach(todo.filledActions) { action in
                    Label(action.sentence, systemImage: action.doneAt == nil ? "circle" : "checkmark.circle.fill")
                }
            }
            Section(todo.concernPrompt) {
                Text(todo.concern)
            }
            Section("Toward") {
                Text(todo.value)
            }
            if !todo.question.isEmpty {
                Section("Question") {
                    Text(todo.question)
                }
            }
            if todo.doneAt != nil {
                Section {
                    Button {
                        store.reopenTodo(todo)
                    } label: {
                        Label("Reopen", systemImage: "arrow.uturn.backward")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.panel)
        .navigationTitle("To-do")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// An old reflection opened from History.
struct ReflectionDetailView: View {
    @Environment(\.appPalette) private var palette
    let entry: JournalEntry
    let reflection: JournalEntry.Content.Reflection

    var body: some View {
        List {
            Section {
                LabeledContent("Feeling", value: "\(reflection.emoji) \(reflection.emotionName)")
                LabeledContent("When", value: entry.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Question") {
                Text(reflection.question)
            }
            Section("Reflection") {
                Text(reflection.answer)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.panel)
        .navigationTitle("Reflection")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The whole journal as Markdown, for Settings' Export Journal.
enum JournalExport {
    static func markdown(_ store: EmotionStore, listening: ListeningHistory) -> String {
        PastRow.all(in: store, listening: listening).map { row -> String in
            let entry: JournalEntry
            switch row {
            case .entry(let e):
                entry = e
            case .listened(let day, let title, _):
                let dateStr = day.day.formatted(date: .long, time: .omitted)
                return """
                # \(title) — \(dateStr)

                **Listened:** \(JournalTimeFormatter.string(from: day.seconds))
                """
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
}

/// A panel row that opens a page on the main screen: a button drawn like a NavigationLink row.
/// A History row with its trailing slot: the same width whether it holds a chevron (opens
/// a page), a play glyph (plays the meditation) or nothing, so times line up.
private struct PanelRowLabel<Content: View>: View {
    enum Accessory { case chevron, play, none }
    let accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content
            Group {
                switch accessory {
                case .chevron: Image(systemName: "chevron.right")
                case .play: Image(systemName: "play.fill").imageScale(.small)
                case .none: Color.clear
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 12)
        }
        .contentShape(Rectangle())
    }
}

/// A link on the panel's navigation card: an icon, a title and a chevron.
private struct PanelNavLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(title)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
