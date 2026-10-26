import Foundation

/// A likely mistake in a meditation script, located for display in the editor.
struct MeditationDiagnostic: Identifiable {
    let line: Int
    let range: NSRange      // UTF-16 range in the script source
    let message: String
    var isDeprecation = false   // old syntax that still plays, rather than a likely mistake
    var fix: MeditationFix? = nil
    var id: String { "\(range.location):\(message)" }
}

/// A rewrite that resolves a diagnostic: replace `range` of the script with `replacement`.
struct MeditationFix {
    let title: String
    let range: NSRange      // UTF-16 range in the script source
    let replacement: String
}

struct MeditationParser {

    // MARK: - Public

    static func parse(_ source: String) -> Meditation {
        let lines = source.components(separatedBy: .newlines)
        let meta = parseMetadata(source)
        let title = meta.title.isEmpty ? "Untitled" : meta.title
        var pools: [String: Pool] = [:]
        var bindings: [String: Pick] = [:]
        var steps: [MeditationStep] = []
        var builder = NodeBuilder()
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { i += 1; continue }

            // Comments / title / tag lines — handled by parseMetadata, skip here
            if trimmed.hasPrefix("#") {
                i += 1; continue
            }

            // Pool definition: "~ name" or "~name" at start of line (with nothing else on the line).
            // Inline "~name" within text is a pool reference, handled by the tokenizer.
            if trimmed.hasPrefix("~"),
               isPoolDefinitionHeader(trimmed) {
                let poolName = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                var items: [(String, Gender?, Int)] = []
                i += 1
                while i < lines.count {
                    let itemLine = lines[i]
                    guard itemLine.hasPrefix("  ") || itemLine.hasPrefix("\t") else { break }
                    let itemTrimmed = itemLine.trimmingCharacters(in: .whitespaces)
                    if itemTrimmed.isEmpty || itemTrimmed.hasPrefix("#") { i += 1; continue }
                    let (text, gender, weight) = parsePoolItem(itemTrimmed)
                    items.append((text, gender, weight))
                    i += 1
                }
                pools[poolName] = Pool(items: items)
                continue
            }

            // Old prefix repeats (×N text, ×N𝄐REST, ×N alone over an indented body) are
            // deprecated but still play; they become the same nodes as the postfix forms.
            builder.beginLine()
            if isRepeatLineStart(trimmed) {
                for node in legacyRepeatNodes(lines: lines, index: &i) {
                    builder.append(node)
                }
            } else {
                parseLine(trimmed, into: &builder)
                i += 1
            }

            // Expand as soon as no [ group is open, so pools defined further down
            // aren't visible to lines above them.
            if builder.isAtTopLevel {
                steps.append(contentsOf: expand(builder.takeAll(), round: nil, pools: pools, bindings: &bindings))
            }
        }

        // A [ left open runs to the end of the script.
        steps.append(contentsOf: expand(builder.finish(), round: nil, pools: pools, bindings: &bindings))

        return Meditation(title: title, steps: steps)
    }

    // MARK: - Lightweight Metadata

    /// Extracts title and tags from a meditation source without full parsing.
    /// Scans leading `#` comment lines; first non-tag `#` line is the title (with optional
    /// trailing `#tag` words), followed by any number of pure `#tag …` lines.
    static func parseMetadata(_ source: String) -> (title: String, tags: [String]) {
        let lines = source.components(separatedBy: .newlines)
        var title: String? = nil
        var tags: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") {
                if title != nil { break }
                continue
            }

            // Tokens on the raw trimmed line. A pure tag line is one where every
            // token is either a bare `#` (comment marker, ignored) or `#word`.
            // This supports both `# #tag1 #tag2` and `#tag1 #tag2`.
            let rawWords = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            let isPureTagLine = rawWords.allSatisfy { $0 == "#" || ($0.hasPrefix("#") && $0.count > 1) }

            if isPureTagLine {
                let extracted = rawWords.filter { $0.count > 1 }.map { String($0.dropFirst()) }
                if title == nil {
                    // Edge case: tag-only line before title — collect tags, keep looking for title.
                    tags.append(contentsOf: extracted)
                } else {
                    tags.append(contentsOf: extracted)
                }
                continue
            }

            // Not a pure tag line — if we don't have a title yet, this is it
            // (possibly with trailing `#tag` words).
            if title == nil {
                let after = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                let words = after.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                var titleWords: [String] = []
                var trailingTags: [String] = []
                var foundTitleWord = false
                for word in words.reversed() {
                    if !foundTitleWord && word.hasPrefix("#") && word.count > 1 {
                        trailingTags.insert(String(word.dropFirst()), at: 0)
                    } else {
                        foundTitleWord = true
                        titleWords.insert(word, at: 0)
                    }
                }
                title = titleWords.joined(separator: " ")
                tags.append(contentsOf: trailingTags)
            } else {
                // Non-tag `#` line after the title — treat as comment, stop scanning.
                break
            }
        }
        return (title ?? "", tags)
    }

    // MARK: - Diagnostics

    /// Finds the script problems most likely to go unnoticed until playback, such as a
    /// `~ref` that would be spoken literally because no pool by that name exists yet.
    static func diagnose(_ source: String) -> [MeditationDiagnostic] {
        let ns = source as NSString
        var lines: [(text: String, range: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { sub, range, _, _ in
            lines.append((sub ?? "", range))
        }

        // Pool items are drawn later, so refs inside them may name a pool defined anywhere.
        let allPools = Set(lines.compactMap { line -> String? in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            guard isPoolDefinitionHeader(trimmed) else { return nil }
            return trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        })

        var diagnostics: [MeditationDiagnostic] = []
        var definedPools: Set<String> = []
        var boundNames: Set<String> = []
        var openPool: (name: String, line: Int, range: NSRange, items: Int)? = nil
        var openBrackets: [(line: Int, range: NSRange)] = []

        func closeOpenPool() {
            if let pool = openPool, pool.items == 0 {
                diagnostics.append(MeditationDiagnostic(line: pool.line, range: pool.range,
                                                        message: "Pool ~\(pool.name) has no indented items under it."))
            }
            openPool = nil
        }

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            let isIndented = line.text.hasPrefix("  ") || line.text.hasPrefix("\t")
            let isPoolItem = openPool != nil && isIndented

            if !isPoolItem { closeOpenPool() }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if isPoolDefinitionHeader(trimmed) {
                let name = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                definedPools.insert(name)
                openPool = (name, lineNumber, line.range, 0)
                continue
            }
            if isPoolItem { openPool?.items += 1 }

            let lineNS = line.text as NSString
            let lineLength = NSRange(location: 0, length: lineNS.length)

            for match in capitalXRegex.matches(in: line.text, range: lineLength) {
                diagnostics.append(MeditationDiagnostic(
                    line: lineNumber,
                    range: NSRange(location: line.range.location + match.range.location, length: 1),
                    message: "Capital X isn't a repeat marker. Use x or ×.",
                    fix: MeditationFix(title: "Change X to ×",
                                       range: NSRange(location: line.range.location + match.range.location, length: 1),
                                       replacement: "×")))
            }

            if !isPoolItem, let match = legacyRepeatRegex.firstMatch(in: line.text, range: lineLength) {
                let marker = lineNS.substring(with: match.range(at: 1))
                let count = marker.dropFirst()
                let fermata = match.range(at: 2)
                let message: String
                if fermata.location != NSNotFound {
                    let rest = match.range(at: 3).location != NSNotFound ? lineNS.substring(with: match.range(at: 3)) : "28″"
                    message = "Old stanza syntax. Write the body, then ‖\(rest) ×\(count) at the end of the line, or wrap a block in [ ] ‖\(rest) ×\(count)."
                } else {
                    message = "Old prefix repeat. Put ×\(count) after what it repeats: at the end of the line, or after a [ ] block."
                }
                diagnostics.append(MeditationDiagnostic(
                    line: lineNumber,
                    range: NSRange(location: line.range.location + match.range.location, length: match.range.length),
                    message: message,
                    isDeprecation: true,
                    fix: legacyRepeatFix(lines, at: index, in: ns)))
            }

            if !isPoolItem {
                for (offset, ch) in line.text.utf16.enumerated() where ch == 0x5B || ch == 0x5D {
                    let range = NSRange(location: line.range.location + offset, length: 1)
                    if ch == 0x5B {
                        openBrackets.append((lineNumber, range))
                    } else if openBrackets.popLast() == nil {
                        diagnostics.append(MeditationDiagnostic(line: lineNumber, range: range,
                                                                message: "This ] has no [ before it, so it would be read out.",
                                                                fix: MeditationFix(title: "Remove this ]", range: range, replacement: "")))
                    }
                }
            }

            let matches = refRegex.matches(in: line.text, range: NSRange(location: 0, length: lineNS.length))
            for match in matches {
                let name = lineNS.substring(with: match.range(at: 1))
                let range = NSRange(location: line.range.location + match.range.location, length: match.range.length)
                let poolRange = match.range(at: 2)
                if poolRange.location != NSNotFound {
                    // ~name=pool
                    let poolName = lineNS.substring(with: poolRange)
                    let known = isPoolItem ? allPools.contains(poolName) : definedPools.contains(poolName)
                    if !known {
                        diagnostics.append(MeditationDiagnostic(line: lineNumber, range: range,
                                                                message: missingPoolMessage(poolName, definedLater: allPools.contains(poolName))))
                    }
                    boundNames.insert(name)
                    continue
                }
                if boundNames.contains(name) { continue }
                let known = isPoolItem ? allPools.contains(name) : definedPools.contains(name)
                if !known {
                    diagnostics.append(MeditationDiagnostic(line: lineNumber, range: range,
                                                            message: missingPoolMessage(name, definedLater: allPools.contains(name))))
                }
            }
        }
        closeOpenPool()
        for bracket in openBrackets {
            diagnostics.append(MeditationDiagnostic(line: bracket.line, range: bracket.range,
                                                    message: "This [ is never closed, so it runs to the end. Add ] ×N after what it repeats."))
        }
        return diagnostics.sorted { $0.range.location < $1.range.location }
    }

    /// Rewrites an old prefix repeat in the postfix form: `×4 text` becomes `text ×4`,
    /// `×5𝄐28″ ×4 text` becomes `text ×4 ‖28″ ×5`, and `×4` over an indented body wraps the
    /// body in `[` … `] ×4`. Nil for nested prefixes over a body, which need a person's judgment.
    private static func legacyRepeatFix(_ lines: [(text: String, range: NSRange)], at index: Int, in source: NSString) -> MeditationFix? {
        let line = lines[index]
        let indent = String(line.text.prefix { $0 == " " || $0 == "\t" })
        var rest = String(line.text.dropFirst(indent.count))
        var repeats: [(count: Substring, rest: String?)] = []   // outermost first
        while let match = legacyRepeatRegex.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) {
            let restNS = rest as NSString
            let count = restNS.substring(with: match.range(at: 1)).dropFirst()
            var breakDuration: String? = nil
            if match.range(at: 2).location != NSNotFound {
                breakDuration = match.range(at: 3).location != NSNotFound ? restNS.substring(with: match.range(at: 3)) : ""
            }
            repeats.append((count, breakDuration))
            rest = restNS.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
        }
        guard let outer = repeats.first else { return nil }

        if !rest.isEmpty {
            let suffix = repeats.reversed().map { r in
                r.rest.map { "‖\($0) ×\(r.count)" } ?? "×\(r.count)"
            }.joined(separator: " ")
            return MeditationFix(title: "Move the repeat to the end of the line",
                                 range: line.range,
                                 replacement: indent + rest + " " + suffix)
        }

        // A marker alone on its line repeats the more-indented lines under it.
        guard repeats.count == 1 else { return nil }
        var last: Int? = nil
        for next in (index + 1)..<lines.count {
            let text = lines[next].text
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if text.prefix(while: { $0 == " " || $0 == "\t" }).count <= indent.count { break }
            last = next
        }
        guard let last else { return nil }
        let bodyEnd = NSMaxRange(lines[last].range)
        let body = source.substring(with: NSRange(location: NSMaxRange(line.range), length: bodyEnd - NSMaxRange(line.range)))
        var closing = ""
        if let duration = outer.rest {
            closing += "\n" + indent + "  ‖" + duration
        }
        closing += "\n" + indent + "] ×\(outer.count)"
        return MeditationFix(title: "Wrap the indented lines in [ ] ×\(outer.count)",
                             range: NSRange(location: line.range.location, length: bodyEnd - line.range.location),
                             replacement: indent + "[" + body + closing)
    }

    /// Names a script defines, for offering as `~name` insertions: pools, then remembered picks.
    static func referenceableNames(in source: String) -> (pools: [String], picks: [String]) {
        var pools: [String] = []
        var picks: [String] = []
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            if isPoolDefinitionHeader(trimmed) {
                let name = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if !pools.contains(name) { pools.append(name) }
                continue
            }
            let ns = line as NSString
            for match in refRegex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            where match.range(at: 2).location != NSNotFound {
                let name = ns.substring(with: match.range(at: 1))
                if !picks.contains(name) { picks.append(name) }
            }
        }
        return (pools, picks)
    }

    private static func missingPoolMessage(_ name: String, definedLater: Bool) -> String {
        definedLater
            ? "~\(name) is used before its pool is defined. Move the pool above this line."
            : "There's no pool named ~\(name), so it would be read out as text."
    }

    /// A capital X where a repeat marker would go.
    private static let capitalXRegex = try! NSRegularExpression(pattern: #"(?:^|(?<=[\s\]]))X\d+(?=$|[\s\[\]])"#)

    /// An old prefix repeat at line start: `×5`, `×5𝄐28″` or `x5|28"` (but not the `||` break).
    private static let legacyRepeatRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([×x]\d+)(?:(𝄐|\|(?!\|))[ \t]*(\d+(?:\.\d+)?[″"′'])?)?"#)

    /// Matches `~name` and `~name=pool` the way the tokenizer reads them.
    private static let refRegex = try! NSRegularExpression(
        pattern: #"~([\p{L}_][\p{L}\p{N}_]*)(?:=([\p{L}_][\p{L}\p{N}_]*))?"#)

    // MARK: - Pool Definition Header

    /// Returns true if the line is a pool definition header: `~ name` or `~name` with nothing else.
    private static func isPoolDefinitionHeader(_ line: String) -> Bool {
        guard line.hasPrefix("~") else { return false }
        let after = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !after.isEmpty else { return false }
        return after.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Pool Item Parsing

    private static func parsePoolItem(_ text: String) -> (String, Gender?, Int) {
        let rock = "\u{1FAA8}"
        let rockCount = text.filter { String($0) == rock }.count
        var cleaned = text.replacingOccurrences(of: rock, with: "")
            .trimmingCharacters(in: .whitespaces)

        let gender: Gender?
        if cleaned.hasSuffix("\u{2640}") { // ♀
            cleaned = cleaned.dropLast().trimmingCharacters(in: .whitespaces)
            gender = .female
        } else if cleaned.hasSuffix("\u{2642}") { // ♂
            cleaned = cleaned.dropLast().trimmingCharacters(in: .whitespaces)
            gender = .male
        } else {
            gender = nil
        }

        return (cleaned, gender, rockCount + 1)
    }

    /// Parses "28″", "28\"", "3′", "3'", or "28" -> 28.0 (or 180.0 for minutes)
    private static func parseSeconds(_ token: String) -> TimeInterval {
        let cleaned = token.replacingOccurrences(of: "\u{2033}", with: "") // ″
            .replacingOccurrences(of: "\u{2032}", with: "") // ′
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        let isMinutes = token.contains("\u{2032}") || token.contains("'")
        if isMinutes {
            return (Double(cleaned) ?? 1) * 60
        }
        return Double(cleaned) ?? 0
    }

    /// True if char is a duration unit marker (″, ′, ", or ').
    private static func isDurationUnit(_ ch: Character) -> Bool {
        return ch == "\u{2033}" || ch == "\u{2032}" || ch == "\"" || ch == "'"
    }

    /// True if char is the old fermata symbol (𝄐 or its ASCII alternative |).
    private static func isFermata(_ ch: Character) -> Bool {
        return ch == "\u{1D110}" || ch == "|"
    }

    /// True if char is the multiplication sign (× or x).
    private static func isMultSign(_ ch: Character) -> Bool {
        return ch == "\u{00D7}" || ch == "x"
    }

    /// Returns true if line begins with a repeat marker: × or x followed by a digit.
    /// That is the old prefix form; postfix repeats come after what they repeat.
    private static func isRepeatLineStart(_ line: String) -> Bool {
        guard let first = line.first, isMultSign(first) else { return false }
        // x is only a repeat marker if followed by a digit (avoids "xenophobia" etc.)
        return line.dropFirst().first?.isNumber == true
    }

    /// Reads a duration like `28″`, `1.5′` or `28"` starting at `i`, returning seconds and the index after it.
    private static func readDuration(_ chars: [Character], at i: Int) -> (seconds: TimeInterval, next: Int)? {
        var j = i
        var numStr = ""
        while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
            numStr.append(chars[j])
            j += 1
        }
        guard !numStr.isEmpty, j < chars.count, isDurationUnit(chars[j]) else { return nil }
        numStr.append(chars[j])
        return (parseSeconds(numStr), j + 1)
    }

    // MARK: - Repeats, groups and breaks

    /// A script's playable structure. Repeats are kept unexpanded so each round draws pools afresh.
    private indirect enum Node {
        case text(String)               // spoken text with inline pauses, pool refs, countdowns and bells
        case group([Node])              // [ … ]
        case repeated(Int, [Node])      // … ×N
        case rest(TimeInterval)         // ‖28″ — a break between rounds of the enclosing repeat
    }

    /// Collects nodes line by line, keeping `[` groups open across lines.
    private struct NodeBuilder {
        private struct Scope {
            var nodes: [Node] = []
            var lineStart = 0           // where the current line's nodes begin
        }
        private var stack: [Scope] = [Scope()]

        var isAtTopLevel: Bool { stack.count == 1 }

        mutating func beginLine() {
            stack[stack.count - 1].lineStart = stack[stack.count - 1].nodes.count
        }

        mutating func append(_ node: Node) {
            stack[stack.count - 1].nodes.append(node)
        }

        mutating func open() {
            stack.append(Scope())
        }

        /// Closes the innermost `[`. Returns false if none is open.
        @discardableResult
        mutating func close() -> Bool {
            guard stack.count > 1 else { return false }
            let scope = stack.removeLast()
            append(.group(scope.nodes))
            return true
        }

        /// Postfix `×N`: wraps the group just closed, or else everything to its left on this line.
        mutating func repeatTail(_ count: Int, groupOnly: Bool) {
            var scope = stack[stack.count - 1]
            let start = groupOnly ? scope.nodes.count - 1 : scope.lineStart
            guard start >= 0, start < scope.nodes.count else { return }
            let body = Array(scope.nodes[start...])
            scope.nodes.replaceSubrange(start..., with: [.repeated(count, body)])
            stack[stack.count - 1] = scope
        }

        mutating func takeAll() -> [Node] {
            let nodes = stack[0].nodes
            stack[0] = Scope()
            return nodes
        }

        mutating func finish() -> [Node] {
            while close() {}
            return takeAll()
        }
    }

    /// Reads a postfix `×N` / `xN` at `i`: it must stand alone, after a space, line start or `]`.
    private static func readRepeatMarker(_ chars: [Character], at i: Int) -> (count: Int, next: Int)? {
        guard isMultSign(chars[i]) else { return nil }
        if i > 0 && !(chars[i - 1].isWhitespace || chars[i - 1] == "]") { return nil }
        var j = i + 1
        var numStr = ""
        while j < chars.count && chars[j].isNumber {
            numStr.append(chars[j])
            j += 1
        }
        guard let count = Int(numStr) else { return nil }
        if j < chars.count && !(chars[j].isWhitespace || "[]‖|".contains(chars[j])) { return nil }
        return (count, j)
    }

    /// Reads a break `‖28″` / `||28"` at `i`. A break with no duration rests 28 seconds.
    private static func readBreak(_ chars: [Character], at i: Int) -> (seconds: TimeInterval, next: Int)? {
        var j: Int
        if chars[i] == "\u{2016}" {
            j = i + 1
        } else if chars[i] == "|" && i + 1 < chars.count && chars[i + 1] == "|" {
            j = i + 2
        } else {
            return nil
        }
        while j < chars.count && (chars[j] == " " || chars[j] == "\t") { j += 1 }
        return readDuration(chars, at: j) ?? (28, j)
    }

    /// Splits one line into text, `[ ]` groups, postfix `×N` repeats and `‖` breaks.
    private static func parseLine(_ line: String, into builder: inout NodeBuilder) {
        let chars = Array(line)
        var text = ""
        var afterGroup = false      // only whitespace since the last `]`

        func flushText() {
            if !text.allSatisfy(\.isWhitespace) {
                builder.append(.text(text))
            }
            text = ""
        }

        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "[" {
                flushText()
                builder.open()
                afterGroup = false
                i += 1
                continue
            }
            if ch == "]" && !builder.isAtTopLevel {
                flushText()
                builder.close()
                afterGroup = true
                i += 1
                continue
            }
            if let marker = readRepeatMarker(chars, at: i) {
                flushText()
                builder.repeatTail(marker.count, groupOnly: afterGroup)
                afterGroup = false
                i = marker.next
                continue
            }
            if let brk = readBreak(chars, at: i) {
                flushText()
                builder.append(.rest(brk.seconds))
                afterGroup = false
                i = brk.next
                continue
            }
            if !ch.isWhitespace { afterGroup = false }
            text.append(ch)
            i += 1
        }
        flushText()
    }

    /// Parses one line on its own, closing any `[` it leaves open.
    private static func lineNodes(_ line: String) -> [Node] {
        var builder = NodeBuilder()
        parseLine(line, into: &builder)
        return builder.finish()
    }

    // MARK: - Old prefix repeats (deprecated)

    private enum LegacyRepeat {
        case stanza(count: Int, rest: TimeInterval, inlineBody: String?)  // ×5𝄐28″ [inline body]
        case inline(count: Int, text: String)                              // ×4 text...
        case block(count: Int)                                             // ×4 (alone, body follows indented)
    }

    /// Parses a line starting with × or x into one of the old prefix forms.
    private static func parseLegacyRepeat(_ line: String) -> LegacyRepeat {
        let chars = Array(line.dropFirst()) // drop × or x
        var idx = 0
        var numStr = ""
        while idx < chars.count && chars[idx].isNumber {
            numStr.append(chars[idx])
            idx += 1
        }

        // ×5𝄐28″ [optional inline body] — the fermata sits right after the count
        if idx < chars.count && isFermata(chars[idx]) && !(idx + 1 < chars.count && chars[idx + 1] == "|") {
            let count = Int(numStr) ?? 5
            var ri = idx + 1
            while ri < chars.count && (chars[ri] == " " || chars[ri] == "\t") { ri += 1 }
            var rest: TimeInterval = 28
            if let duration = readDuration(chars, at: ri) {
                rest = duration.seconds
                ri = duration.next
            }
            let inlineBody = String(chars[ri...]).trimmingCharacters(in: .whitespaces)
            return .stanza(count: count, rest: rest, inlineBody: inlineBody.isEmpty ? nil : inlineBody)
        }

        let count = Int(numStr) ?? 1
        let remaining = String(chars[idx...]).trimmingCharacters(in: .whitespaces)
        return remaining.isEmpty ? .block(count: count) : .inline(count: count, text: remaining)
    }

    /// Converts the old prefix repeat at `lines[index]` (and any indented body) into nodes,
    /// advancing `index` past what it read.
    private static func legacyRepeatNodes(lines: [String], index: inout Int) -> [Node] {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        switch parseLegacyRepeat(trimmed) {
        case .inline(let count, let text):
            index += 1
            return [.repeated(count, legacyBodyLineNodes(text))]
        case .block(let count):
            let body = collectIndentedBody(lines: lines, index: &index)
            return [.repeated(count, legacyBodyNodes(body))]
        case .stanza(let count, let rest, let inlineBody):
            let body: [Node]
            if let inlineBody = inlineBody {
                index += 1
                body = legacyBodyLineNodes(inlineBody)
            } else {
                body = legacyBodyNodes(collectIndentedBody(lines: lines, index: &index))
            }
            return [.repeated(count, body + [.rest(rest)])]
        }
    }

    /// A body line of an old repeat: itself possibly an inline `×N text`.
    private static func legacyBodyLineNodes(_ line: String) -> [Node] {
        if isRepeatLineStart(line), case .inline(let count, let text) = parseLegacyRepeat(line) {
            return [.repeated(count, lineNodes(text))]
        }
        return lineNodes(line)
    }

    /// Body lines of an old block repeat, still carrying their indentation so a nested
    /// `×N` alone can claim the lines indented under it.
    private static func legacyBodyNodes(_ body: [String]) -> [Node] {
        var nodes: [Node] = []
        var k = 0
        while k < body.count {
            let raw = body[k]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if isRepeatLineStart(trimmed), case .block(let count) = parseLegacyRepeat(trimmed) {
                let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
                var inner: [String] = []
                k += 1
                while k < body.count && body[k].prefix(while: { $0 == " " || $0 == "\t" }).count > indent {
                    inner.append(body[k])
                    k += 1
                }
                nodes.append(.repeated(count, legacyBodyNodes(inner)))
                continue
            }
            nodes.append(contentsOf: legacyBodyLineNodes(trimmed))
            k += 1
        }
        return nodes
    }

    /// Reads indented body lines (starting with 2+ spaces or tab), advancing index past them.
    /// Lines keep their indentation; blank and comment lines are dropped.
    private static func collectIndentedBody(lines: [String], index: inout Int) -> [String] {
        var body: [String] = []
        index += 1
        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("  ") || line.hasPrefix("\t") else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                body.append(line)
            }
            index += 1
        }
        return body
    }

    // MARK: - Expansion

    /// Expands nodes into steps. `round` is the innermost enclosing repeat's progress,
    /// which decides what a `‖` break says.
    private static func expand(
        _ nodes: [Node],
        round: (index: Int, count: Int)?,
        pools: [String: Pool],
        bindings: inout [String: Pick]
    ) -> [MeditationStep] {
        var steps: [MeditationStep] = []
        for node in nodes {
            switch node {
            case .text(let text):
                steps.append(contentsOf: expandSpeakLine(text, pools: pools, bindings: &bindings))
            case .group(let inner):
                steps.append(contentsOf: expand(inner, round: round, pools: pools, bindings: &bindings))
            case .repeated(let count, let body):
                for index in 0..<max(count, 0) {
                    steps.append(contentsOf: expand(body, round: (index, count), pools: pools, bindings: &bindings))
                }
                if count > 0 && containsOwnBreak(body) {
                    steps.append(.speak("End"))
                }
            case .rest(let secs):
                guard let round = round else {
                    // Outside any repeat a break is just a pause.
                    steps.append(.pause(secs))
                    continue
                }
                // Skipped after the final round.
                if round.index < round.count - 1 {
                    steps.append(.speak("Rest."))
                    steps.append(.pause(secs))
                    steps.append(.speak(round.index < round.count - 2 ? "Again." : "One last time."))
                    steps.append(.pause(1))
                }
            }
        }
        return steps
    }

    /// True if a break in `nodes` belongs to the repeat directly around them (not a nested one).
    private static func containsOwnBreak(_ nodes: [Node]) -> Bool {
        nodes.contains { node in
            switch node {
            case .rest: return true
            case .group(let inner): return containsOwnBreak(inner)
            case .text, .repeated: return false
            }
        }
    }

    // MARK: - Speak Line Expansion

    /// A remembered pool draw, bound with `~name=pool` and replayed by later `~name` references.
    private struct Pick {
        let expansion: Expansion
        let gender: Gender?
    }

    /// What a pool draw expands to: plain text that joins the surrounding sentence,
    /// or separate steps when the drawn item carries its own timing or bells.
    private enum Expansion {
        case text(String)
        case steps([MeditationStep])
    }

    /// Draws from a pool and expands the item, resolving nested pool refs, pauses, etc.
    private static func drawPick(from pool: Pool, pools: [String: Pool], bindings: inout [String: Pick]) -> Pick {
        let drawn = pool.draw()
        let gender = pool.lastGender
        // Re-tokenize drawn text to resolve nested pool refs, pauses, etc.
        let innerTokens = tokenize(drawn)
        let hasNestedSpecials = innerTokens.contains(where: {
            if case .text = $0 { return false }; return true
        })
        guard hasNestedSpecials else { return Pick(expansion: .text(drawn), gender: gender) }
        let nestedSteps = expandSpeakLine(drawn, pools: pools, bindings: &bindings)
        if nestedSteps.count == 1, case .speak(let nestedText) = nestedSteps[0] {
            return Pick(expansion: .text(nestedText), gender: gender)
        }
        return Pick(expansion: .steps(nestedSteps), gender: gender)
    }

    /// Expands a single speak line into steps, resolving pools, pauses, countdowns, and pronouns.
    private static func expandSpeakLine(_ line: String, pools: [String: Pool], bindings: inout [String: Pick]) -> [MeditationStep] {
        var steps: [MeditationStep] = []
        var currentGender: Gender? = nil

        // Split line into segments: text, pauses, countdowns, pool refs
        let segments = tokenize(line)

        var textBuffer = ""

        func insert(_ pick: Pick) {
            if let g = pick.gender {
                currentGender = g
            }
            switch pick.expansion {
            case .text(let t):
                textBuffer += t
            case .steps(let nestedSteps):
                // Flush current text buffer before inserting nested content
                if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                    steps.append(.speak(resolved))
                    textBuffer = ""
                }
                // Recursively expanded content contains timing or bells, so keep it as separate steps.
                steps.append(contentsOf: nestedSteps)
            }
        }

        for segment in segments {
            switch segment {
            case .text(let t):
                textBuffer += t
            case .poolRef(let name):
                // A bound pick takes precedence over a pool of the same name.
                if let pick = bindings[name] {
                    insert(pick)
                } else if let pool = pools[name] {
                    insert(drawPick(from: pool, pools: pools, bindings: &bindings))
                } else {
                    textBuffer += "~\(name)"
                }
            case .bind(let name, let poolName):
                // ~name=pool draws fresh, speaks it, and remembers it for later ~name refs.
                if let pool = pools[poolName] {
                    let pick = drawPick(from: pool, pools: pools, bindings: &bindings)
                    bindings[name] = pick
                    insert(pick)
                } else {
                    textBuffer += "~\(name)=\(poolName)"
                }
            case .dots(let count):
                // Flush text buffer, then pause
                if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                    steps.append(.speak(resolved))
                    textBuffer = ""
                }
                steps.append(.pause(TimeInterval(count)))
            case .seconds(let secs):
                if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                    steps.append(.speak(resolved))
                    textBuffer = ""
                }
                steps.append(.pause(secs))
            case .countdown(let secs):
                if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                    steps.append(.speak(resolved))
                    textBuffer = ""
                }
                steps.append(.countdown(secs))
            case .bell(let id):
                if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                    let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                    steps.append(.speak(resolved))
                    textBuffer = ""
                }
                steps.append(.bell(id))
            }
        }

        // Flush remaining text
        if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
            let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
            steps.append(.speak(resolved))
        }

        return steps
    }

    // MARK: - Tokenizer

    private enum Token {
        case text(String)
        case poolRef(String)
        case bind(String, String)   // ~name=pool
        case dots(Int)
        case seconds(TimeInterval)
        case countdown(TimeInterval)
        case bell(String)
    }

    private static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var textBuf = ""
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]

            // Middle dot: ·
            if ch == "\u{00B7}" {
                if !textBuf.isEmpty {
                    tokens.append(.text(textBuf))
                    textBuf = ""
                }
                var dotCount = 0
                while i < chars.count && chars[i] == "\u{00B7}" {
                    dotCount += 1
                    i += 1
                }
                tokens.append(.dots(dotCount))
                continue
            }

            // Countdown: ⏳
            if ch == "\u{23F3}" {
                if !textBuf.isEmpty {
                    tokens.append(.text(textBuf))
                    textBuf = ""
                }
                i += 1
                var numStr = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == "." || isDurationUnit(chars[i])) {
                    numStr.append(chars[i])
                    i += 1
                }
                let secs = parseSeconds(numStr)
                tokens.append(.countdown(secs))
                continue
            }

            // Bell / chime / gong emoji → bell token with id
            if let bellID = BellRegistry.id(for: ch) {
                if !textBuf.isEmpty {
                    tokens.append(.text(textBuf))
                    textBuf = ""
                }
                i += 1
                tokens.append(.bell(bellID))
                continue
            }

            // Pool reference: ~name (must be followed by a letter or underscore)
            if ch == "~" && i + 1 < chars.count && (chars[i+1].isLetter || chars[i+1] == "_") {
                if !textBuf.isEmpty {
                    tokens.append(.text(textBuf))
                    textBuf = ""
                }
                i += 1 // skip ~
                var name = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    name.append(chars[i])
                    i += 1
                }
                // Binding: ~name=pool (pool name must start with a letter or underscore)
                if i + 1 < chars.count && chars[i] == "=" && (chars[i+1].isLetter || chars[i+1] == "_") {
                    i += 1 // skip =
                    var poolName = ""
                    while i < chars.count && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                        poolName.append(chars[i])
                        i += 1
                    }
                    tokens.append(.bind(name, poolName))
                    continue
                }
                tokens.append(.poolRef(name))
                continue
            }

            // Inline seconds: digits followed by a duration unit (″ ′ " ')
            if ch.isNumber {
                var numStr = String(ch)
                var j = i + 1
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                    numStr.append(chars[j])
                    j += 1
                }
                if j < chars.count && isDurationUnit(chars[j]) {
                    // It's a duration
                    if !textBuf.isEmpty {
                        tokens.append(.text(textBuf))
                        textBuf = ""
                    }
                    numStr.append(chars[j])
                    let secs = parseSeconds(numStr)
                    tokens.append(.seconds(secs))
                    i = j + 1
                    continue
                }
                // Not a duration, treat as regular text
                textBuf.append(ch)
                i += 1
                continue
            }

            textBuf.append(ch)
            i += 1
        }

        if !textBuf.isEmpty {
            tokens.append(.text(textBuf))
        }

        return tokens
    }
}
