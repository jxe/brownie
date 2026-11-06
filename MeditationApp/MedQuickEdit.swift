import SwiftUI
import UIKit

// MARK: - Tap targets
//
// Small edits that shouldn't need the cursor: tapping a time, a repeat count or a pool
// in the script editor opens a popover or sheet, and the change is written back into the
// text. The `.med` text stays the only source of truth.

/// A number in the script that a popover can change: a pause, countdown, break, dots or repeat count.
struct MedValueEdit {
    enum Kind { case pause, countdown, breakRest, dots, repeatCount }

    let kind: Kind
    let value: Int
    /// The text an edit replaces. Empty for a bare `‖`, whose duration is inserted after it.
    let valueRange: NSRange
    /// The text a tap must land on.
    let hitRange: NSRange
    /// Written as `3′` rather than `180″`, so it steps by minutes.
    var minutes = false
    /// Written with `"` and `'` instead of `″` and `′`.
    var ascii = false
    /// `×` or `x`.
    var repeatSign = "\u{00D7}"

    var isDuration: Bool { kind == .pause || kind == .countdown || kind == .breakRest }

    var title: String {
        switch kind {
        case .pause, .dots: return "Pause"
        case .countdown: return "Countdown"
        case .breakRest: return "Break between rounds"
        case .repeatCount: return "Repeat"
        }
    }

    var bounds: ClosedRange<Int> {
        switch kind {
        case .pause, .countdown, .breakRest: return 1...3600
        case .dots: return 1...20
        case .repeatCount: return 1...99
        }
    }

    var smallStep: Int { isDuration && minutes ? 60 : 1 }
    var bigStep: Int? { isDuration ? (minutes ? 300 : 10) : nil }

    var quickPicks: [Int] {
        switch kind {
        case .countdown: return [60, 120, 180, 240, 300, 600]
        case .pause, .breakRest: return [5, 10, 15, 20, 30, 45, 60, 120]
        case .dots: return []
        case .repeatCount: return [2, 3, 4, 5, 6, 8, 10]
        }
    }

    /// The script text for a value.
    func text(for value: Int) -> String {
        switch kind {
        case .pause, .countdown, .breakRest:
            return Self.durationText(value, ascii: ascii)
        case .dots:
            return String(repeating: "·", count: value)
        case .repeatCount:
            return "\(repeatSign)\(value)"
        }
    }

    /// How the popover shows a value: "22 sec", "1 min 30 sec", "4 times".
    func display(_ value: Int) -> String {
        switch kind {
        case .pause, .countdown, .breakRest, .dots:
            let m = value / 60, s = value % 60
            if m == 0 { return "\(s) sec" }
            return s == 0 ? "\(m) min" : "\(m) min \(s) sec"
        case .repeatCount:
            return value == 1 ? "once" : "\(value) times"
        }
    }

    /// A short label for a step or quick pick: "10s", "2m", "4×".
    func shortLabel(_ value: Int) -> String {
        switch kind {
        case .pause, .countdown, .breakRest, .dots:
            return value >= 60 && value % 60 == 0 ? "\(value / 60)m" : "\(value)s"
        case .repeatCount:
            return "\(value)×"
        }
    }

    static func durationText(_ seconds: Int, ascii: Bool) -> String {
        if seconds >= 60 && seconds % 60 == 0 {
            return "\(seconds / 60)\(ascii ? "'" : "\u{2032}")"
        }
        return "\(seconds)\(ascii ? "\"" : "\u{2033}")"
    }
}

enum MedQuickEditTarget {
    case value(MedValueEdit)
    /// A pool header line or a `~name` reference to a pool the script defines.
    case pool(name: String, hitRange: NSRange)

    var hitRange: NSRange {
        switch self {
        case .value(let edit): return edit.hitRange
        case .pool(_, let range): return range
        }
    }
}

enum MedQuickEdit {
    // `⏳3′`, `‖28″`, `22″`, `1.5'`. Group 1 is the ⏳ or break before it, 2 the number, 3 the unit.
    private static let durationRegex = try! NSRegularExpression(
        pattern: #"(⏳[ \t]*|‖[ \t]*|\|\|[ \t]*)?(?<![\p{L}\p{N}.])(\d+(?:\.\d+)?)([″"′'])"#)
    // A break with no duration (it rests 28″).
    private static let bareBreakRegex = try! NSRegularExpression(pattern: #"(‖|\|\|)(?![ \t]*\d)"#)
    private static let dotsRegex = try! NSRegularExpression(pattern: "·+")
    // Same shape the highlighter colors as a repeat count.
    private static let repeatRegex = try! NSRegularExpression(
        pattern: #"(?:^|(?<=[\s\]]))([×x])(\d+)(?=$|[\s\[\]‖|])"#)
    private static let refRegex = try! NSRegularExpression(
        pattern: #"~([\p{L}_][\p{L}\p{N}_]*)(?:=([\p{L}_][\p{L}\p{N}_]*))?"#)

    /// Everything editable on the line that holds `offset`, in document coordinates (UTF-16).
    static func targets(onLineAt offset: Int, in text: String) -> [MedQuickEditTarget] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                        for: NSRange(location: min(max(offset, 0), ns.length), length: 0))
        let line = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
        let lineNS = line as NSString
        let full = NSRange(location: 0, length: lineNS.length)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return [] }

        func shifted(_ r: NSRange) -> NSRange { NSRange(location: r.location + start, length: r.length) }

        if MeditationParser.isPoolDefinitionHeader(trimmed) {
            let name = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            let lead = (line.prefix { $0 == " " || $0 == "\t" } as Substring).utf16.count
            return [.pool(name: name, hitRange: shifted(NSRange(location: lead, length: trimmed.utf16.count)))]
        }

        var targets: [MedQuickEditTarget] = []

        for m in durationRegex.matches(in: line, range: full) {
            let number = lineNS.substring(with: m.range(at: 2))
            let unit = lineNS.substring(with: m.range(at: 3))
            let isMinutes = unit == "′" || unit == "'"
            let seconds = Int(((Double(number) ?? 0) * (isMinutes ? 60 : 1)).rounded())
            var kind = MedValueEdit.Kind.pause
            if m.range(at: 1).location != NSNotFound {
                kind = lineNS.substring(with: m.range(at: 1)).hasPrefix("⏳") ? .countdown : .breakRest
            }
            let valueRange = NSRange(location: m.range(at: 2).location,
                                     length: NSMaxRange(m.range(at: 3)) - m.range(at: 2).location)
            targets.append(.value(MedValueEdit(
                kind: kind, value: max(1, seconds),
                valueRange: shifted(valueRange), hitRange: shifted(m.range),
                minutes: isMinutes && seconds % 60 == 0, ascii: unit == "\"" || unit == "'")))
        }

        for m in bareBreakRegex.matches(in: line, range: full) {
            let after = NSRange(location: NSMaxRange(m.range), length: 0)
            targets.append(.value(MedValueEdit(
                kind: .breakRest, value: 28, valueRange: shifted(after), hitRange: shifted(m.range),
                ascii: lineNS.substring(with: m.range) == "||")))
        }

        for m in dotsRegex.matches(in: line, range: full) {
            targets.append(.value(MedValueEdit(
                kind: .dots, value: m.range.length, valueRange: shifted(m.range), hitRange: shifted(m.range))))
        }

        for m in repeatRegex.matches(in: line, range: full) {
            let count = Int(lineNS.substring(with: m.range(at: 2))) ?? 1
            targets.append(.value(MedValueEdit(
                kind: .repeatCount, value: count, valueRange: shifted(m.range), hitRange: shifted(m.range),
                repeatSign: lineNS.substring(with: m.range(at: 1)))))
        }

        let pools = Set(MeditationParser.referenceableNames(in: text).pools)
        for m in refRegex.matches(in: line, range: full) {
            let name = lineNS.substring(with: m.range(at: 1))
            let source = m.range(at: 2).location != NSNotFound ? lineNS.substring(with: m.range(at: 2)) : name
            let pool = pools.contains(source) ? source : boundPool(for: name, in: text)
            if let pool, pools.contains(pool) {
                targets.append(.pool(name: pool, hitRange: shifted(m.range)))
            }
        }

        return targets
    }

    /// The pool a remembered pick `~name=pool` draws from, if the script binds `name`.
    private static func boundPool(for name: String, in text: String) -> String? {
        let ns = text as NSString
        for m in refRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        where m.range(at: 2).location != NSNotFound && ns.substring(with: m.range(at: 1)) == name {
            return ns.substring(with: m.range(at: 2))
        }
        return nil
    }
}

// MARK: - Pool blocks

/// A pool definition as written: the `~name` line and the indented lines under it.
struct MedPoolBlock {
    struct Item: Identifiable {
        let id = UUID()
        var text: String
        var gender: Gender?
        /// Extra 🪨 weight markers.
        var rocks: Int
        /// The line as written, kept for an unchanged item so its spacing and marker order survive.
        fileprivate var original: (line: String, text: String, gender: Gender?, rocks: Int)?

        init(text: String = "", gender: Gender? = nil, rocks: Int = 0) {
            self.text = text
            self.gender = gender
            self.rocks = rocks
        }

        fileprivate var isUnchanged: Bool {
            guard let original else { return false }
            return original.text == text && original.gender == gender && original.rocks == rocks
        }
    }

    private enum Line {
        case item
        /// A comment or blank indented line, kept where it was.
        case other(String)
    }

    let name: String
    /// From the start of the `~name` line to the end of the block's last line, without its newline.
    let range: NSRange
    /// The block's text as it was found, to check it hasn't changed before writing back.
    let source: String
    let items: [Item]
    private let header: String
    private let indent: String
    private let lines: [Line]

    /// The first definition of pool `name` in the script.
    static func find(named name: String, in text: String) -> MedPoolBlock? {
        let ns = text as NSString
        var lineRanges: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lineRanges.append(range)
        }
        for (index, headerRange) in lineRanges.enumerated() {
            let header = ns.substring(with: headerRange)
            let trimmed = header.trimmingCharacters(in: .whitespaces)
            guard MeditationParser.isPoolDefinitionHeader(trimmed),
                  trimmed.dropFirst().trimmingCharacters(in: .whitespaces) == name else { continue }

            // Same rule as the parser: the block runs while lines start with two spaces or a tab.
            var lines: [Line] = []
            var items: [Item] = []
            var indent: String?
            var last = headerRange
            for bodyRange in lineRanges[(index + 1)...] {
                let line = ns.substring(with: bodyRange)
                guard line.hasPrefix("  ") || line.hasPrefix("\t") else { break }
                last = bodyRange
                let itemText = line.trimmingCharacters(in: .whitespaces)
                if itemText.isEmpty || itemText.hasPrefix("#") {
                    lines.append(.other(line))
                    continue
                }
                let (text, gender, weight) = MeditationParser.parsePoolItem(itemText)
                var item = Item(text: text, gender: gender, rocks: weight - 1)
                item.original = (line, text, gender, weight - 1)
                items.append(item)
                lines.append(.item)
                if indent == nil { indent = String(line.prefix { $0 == " " || $0 == "\t" }) }
            }
            let range = NSRange(location: headerRange.location, length: NSMaxRange(last) - headerRange.location)
            return MedPoolBlock(name: name, range: range, source: ns.substring(with: range), items: items,
                                header: header, indent: indent ?? "  ", lines: lines)
        }
        return nil
    }

    /// The block rewritten with `newItems`. Comments stay in place, unchanged items keep their
    /// original line, and new items go after the last existing one.
    func text(with newItems: [Item]) -> String {
        var remaining = newItems.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }[...]
        var out = [header]
        guard let lastItemSlot = lines.lastIndex(where: { if case .item = $0 { return true } else { return false } }) else {
            out += remaining.map(render)
            for case .other(let line) in lines { out.append(line) }
            return out.joined(separator: "\n")
        }
        for (i, line) in lines.enumerated() {
            switch line {
            case .other(let text):
                out.append(text)
            case .item:
                if let next = remaining.popFirst() { out.append(render(next)) }
            }
            if i == lastItemSlot {
                out += remaining.map(render)
                remaining = []
            }
        }
        return out.joined(separator: "\n")
    }

    private func render(_ item: Item) -> String {
        if item.isUnchanged, let original = item.original { return original.line }
        var line = indent + item.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        switch item.gender {
        case .female: line += " \u{2640}"
        case .male: line += " \u{2642}"
        case nil: break
        }
        if item.rocks > 0 { line += " " + String(repeating: "\u{1FAA8}", count: item.rocks) }
        return line
    }
}

// MARK: - Popover for a number

struct MedValuePopover: View {
    let edit: MedValueEdit
    let onChange: (Int) -> Void
    @State private var value: Int

    init(edit: MedValueEdit, onChange: @escaping (Int) -> Void) {
        self.edit = edit
        self.onChange = onChange
        _value = State(initialValue: edit.value)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(edit.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                if let big = edit.bigStep { stepButton(-big) }
                stepButton(-edit.smallStep)
                Text(edit.display(value))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 104)
                    .contentTransition(.numericText())
                stepButton(edit.smallStep)
                if let big = edit.bigStep { stepButton(big) }
            }

            if !edit.quickPicks.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(edit.quickPicks, id: \.self) { pick in
                        Button(edit.shortLabel(pick)) { set(pick) }
                            .buttonStyle(.bordered)
                            .tint(pick == value ? .accentColor : .secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func stepButton(_ delta: Int) -> some View {
        Button {
            set(value + delta)
        } label: {
            Text((delta < 0 ? "−" : "+") + edit.shortLabel(abs(delta)).replacingOccurrences(of: "×", with: ""))
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(minWidth: 30)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
        .disabled(delta < 0 ? value <= edit.bounds.lowerBound : value >= edit.bounds.upperBound)
    }

    private func set(_ newValue: Int) {
        let clamped = min(max(newValue, edit.bounds.lowerBound), edit.bounds.upperBound)
        guard clamped != value else { return }
        withAnimation(.snappy) { value = clamped }
        onChange(clamped)
    }
}

// MARK: - Sheet for a pool

struct MedPoolEditorSheet: View {
    let name: String
    let onDone: ([MedPoolBlock.Item]) -> Void
    let onCancel: () -> Void
    @State private var items: [MedPoolBlock.Item]
    @FocusState private var focused: UUID?

    init(name: String, items: [MedPoolBlock.Item],
         onDone: @escaping ([MedPoolBlock.Item]) -> Void, onCancel: @escaping () -> Void) {
        self.name = name
        self.onDone = onDone
        self.onCancel = onCancel
        _items = State(initialValue: items)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            TextField("New item", text: $item.text)
                                .focused($focused, equals: item.id)
                                .submitLabel(.next)
                                .onSubmit { addItem(after: item.id) }
                            markerMenu($item)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        addItem(after: nil)
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                } footer: {
                    Text("Each ~\(name) draws one of these at random. Swipe to delete, Return for the next item.")
                }
            }
            .navigationTitle("~\(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(items) }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    EditButton()
                }
            }
        }
    }

    private func markerMenu(_ item: Binding<MedPoolBlock.Item>) -> some View {
        Menu {
            Picker("Pronouns", selection: item.gender) {
                Text("No pronouns").tag(Gender?.none)
                Text("♀ she / her").tag(Gender?.some(.female))
                Text("♂ he / him").tag(Gender?.some(.male))
            }
            Picker("Weight", selection: item.rocks) {
                Text("Normal").tag(0)
                ForEach(1...4, id: \.self) { n in
                    Text(String(repeating: "🪨", count: n)).tag(n)
                }
            }
        } label: {
            let markers = markerText(item.wrappedValue)
            if markers.isEmpty {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            } else {
                Text(markers)
            }
        }
        .accessibilityLabel("Pronouns and weight")
    }

    private func markerText(_ item: MedPoolBlock.Item) -> String {
        var parts: [String] = []
        switch item.gender {
        case .female: parts.append("♀")
        case .male: parts.append("♂")
        case nil: break
        }
        if item.rocks > 0 { parts.append(String(repeating: "🪨", count: item.rocks)) }
        return parts.joined(separator: " ")
    }

    private func addItem(after id: UUID?) {
        let item = MedPoolBlock.Item()
        if let id, let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(item, at: index + 1)
        } else {
            items.append(item)
        }
        focused = item.id
    }
}
