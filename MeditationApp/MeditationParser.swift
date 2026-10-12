import Foundation

/// A likely mistake in a meditation script, located for display in the editor.
struct MeditationDiagnostic: Identifiable {
    let line: Int
    let range: NSRange      // UTF-16 range in the script source
    let message: String
    var id: String { "\(range.location):\(message)" }
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

            // Repeat block: ×N𝄐REST or ×N text... (× and x are interchangeable)
            if isRepeatLineStart(trimmed) {
                let parsed = parseRepeatLine(trimmed)
                switch parsed {
                case .stanzaBlock(let outerCount, let outerRest, let inlineBody):
                    // ×N𝄐REST [inline body] — stanza block
                    let bodyLines: [String]
                    if let inlineBody = inlineBody {
                        // One-liner: ×5𝄐28″ ×4 text... — inline body on same line
                        bodyLines = [inlineBody]
                        i += 1
                    } else {
                        // Block form: read indented body lines
                        bodyLines = collectIndentedBody(lines: lines, index: &i)
                    }
                    // Expand inner ×N repeats within body lines
                    let expandedBody = expandInnerRepeats(bodyLines)
                    let sectionSteps = expandStanzaBlock(
                        bodyLines: expandedBody,
                        outerCount: outerCount,
                        outerRest: outerRest,
                        pools: pools,
                        bindings: &bindings
                    )
                    steps.append(contentsOf: sectionSteps)

                case .inlineRepeat(let count, let text):
                    // ×N text... — simple repeat
                    for _ in 0..<count {
                        steps.append(contentsOf: expandSpeakLine(text, pools: pools, bindings: &bindings))
                    }
                    i += 1

                case .blockRepeat(let count):
                    // ×N (alone) — read indented body, repeat N times
                    let bodyLines = collectIndentedBody(lines: lines, index: &i)
                    for _ in 0..<count {
                        for bodyLine in bodyLines {
                            steps.append(contentsOf: expandSpeakLine(bodyLine, pools: pools, bindings: &bindings))
                        }
                    }
                }
                continue
            }

            // Bare speak line
            let lineSteps = expandSpeakLine(trimmed, pools: pools, bindings: &bindings)
            steps.append(contentsOf: lineSteps)
            i += 1
        }

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

            if let first = trimmed.first, first == "X", trimmed.dropFirst().first?.isNumber == true {
                let start = (line.text as NSString).range(of: "X")
                diagnostics.append(MeditationDiagnostic(
                    line: lineNumber,
                    range: NSRange(location: line.range.location + start.location, length: 1),
                    message: "Capital X isn't a repeat marker. Use x or ×."))
            }

            let lineNS = line.text as NSString
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
        return diagnostics
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

    /// True if char is the fermata symbol (𝄐 or its ASCII alternative |).
    private static func isFermata(_ ch: Character) -> Bool {
        return ch == "\u{1D110}" || ch == "|"
    }

    /// True if char is the multiplication sign (× or x).
    private static func isMultSign(_ ch: Character) -> Bool {
        return ch == "\u{00D7}" || ch == "x"
    }

    /// Returns true if line begins with a repeat marker: × or x followed by a digit.
    private static func isRepeatLineStart(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == "\u{00D7}" {
            // × is always a repeat marker
            return line.count > 1 && line.dropFirst().first?.isNumber == true
        }
        if first == "x" {
            // x is only a repeat marker if followed by a digit (avoids "xenophobia" etc.)
            return line.count > 1 && line.dropFirst().first?.isNumber == true
        }
        return false
    }

    // MARK: - Repeat Notation (× syntax)

    private enum RepeatParsed {
        case stanzaBlock(outerCount: Int, outerRest: TimeInterval, inlineBody: String?)  // ×5𝄐28″ [inline body]
        case inlineRepeat(count: Int, text: String)                  // ×4 text...
        case blockRepeat(count: Int)                                 // ×4 (alone, body follows indented)
    }

    /// Parses a line starting with × or x into one of the repeat forms.
    private static func parseRepeatLine(_ line: String) -> RepeatParsed {
        let after = String(line.dropFirst()) // drop × or x

        // Check for fermata (𝄐 or |) — stanza block form: ×5𝄐28″ [optional inline body]
        if let fermataIdx = after.firstIndex(where: { isFermata($0) }) {
            let countStr = String(after[..<fermataIdx])
            let count = Int(countStr) ?? 5
            let afterFermata = String(after[after.index(after: fermataIdx)...])
                .trimmingCharacters(in: .whitespaces)
            // Extract the rest duration (leading number + unit), then any remaining inline body
            var restStr = ""
            var ri = afterFermata.startIndex
            while ri < afterFermata.endIndex {
                let ch = afterFermata[ri]
                if ch.isNumber || ch == "." || isDurationUnit(ch) {
                    restStr.append(ch)
                    ri = afterFermata.index(after: ri)
                } else {
                    break
                }
            }
            let rest = restStr.isEmpty ? 28.0 : parseSeconds(restStr)
            let inlineBody = String(afterFermata[ri...]).trimmingCharacters(in: .whitespaces)
            return .stanzaBlock(outerCount: count, outerRest: rest,
                                inlineBody: inlineBody.isEmpty ? nil : inlineBody)
        }

        // Extract count (leading digits)
        var numStr = ""
        var idx = after.startIndex
        while idx < after.endIndex && after[idx].isNumber {
            numStr.append(after[idx])
            idx = after.index(after: idx)
        }
        let count = Int(numStr) ?? 1

        // Remaining text after count
        let remaining = String(after[idx...]).trimmingCharacters(in: .whitespaces)
        if remaining.isEmpty {
            return .blockRepeat(count: count)
        } else {
            return .inlineRepeat(count: count, text: remaining)
        }
    }

    /// Reads indented body lines (starting with 2+ spaces or tab), advancing index past them.
    private static func collectIndentedBody(lines: [String], index: inout Int) -> [String] {
        var body: [String] = []
        index += 1
        while index < lines.count {
            let line = lines[index]
            guard line.hasPrefix("  ") || line.hasPrefix("\t") else { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                body.append(trimmed)
            }
            index += 1
        }
        return body
    }

    /// Expands inner ×N inline repeats within body lines of a stanza block.
    private static func expandInnerRepeats(_ bodyLines: [String]) -> [String] {
        var expanded: [String] = []
        for line in bodyLines {
            if isRepeatLineStart(line) {
                let parsed = parseRepeatLine(line)
                switch parsed {
                case .inlineRepeat(let count, let text):
                    for _ in 0..<count {
                        expanded.append(text)
                    }
                default:
                    expanded.append(line)
                }
            } else {
                expanded.append(line)
            }
        }
        return expanded
    }

    // MARK: - Stanza Expansion

    private static func expandStanzaBlock(
        bodyLines: [String],
        outerCount: Int,
        outerRest: TimeInterval,
        pools: [String: Pool],
        bindings: inout [String: Pick]
    ) -> [MeditationStep] {
        var steps: [MeditationStep] = []

        for stanza in 0..<outerCount {
            for line in bodyLines {
                steps.append(contentsOf: expandSpeakLine(line, pools: pools, bindings: &bindings))
            }

            // Rest between stanzas
            if stanza < outerCount - 2 {
                steps.append(.speak("Rest."))
                steps.append(.pause(outerRest))
                steps.append(.speak("Again."))
                steps.append(.pause(1))
            } else if stanza == outerCount - 2 {
                steps.append(.speak("Rest."))
                steps.append(.pause(outerRest))
                steps.append(.speak("One last time."))
                steps.append(.pause(1))
            }
        }

        steps.append(.speak("End"))
        return steps
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
