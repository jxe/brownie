import Foundation

struct MeditationParser {

    // MARK: - Public

    static func parse(_ source: String) -> Meditation {
        let lines = source.components(separatedBy: .newlines)
        var title = "Untitled"
        var pools: [String: Pool] = [:]
        var steps: [MeditationStep] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { i += 1; continue }

            // Comment / title
            if trimmed.hasPrefix("#") {
                let comment = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if title == "Untitled" && !comment.isEmpty {
                    title = comment
                }
                i += 1; continue
            }

            // Pool definition: "~ name" or "~name" at start of line (with nothing else on the line).
            // Inline "~name" within text is a pool reference, handled by the tokenizer.
            if trimmed.hasPrefix("~"),
               isPoolDefinitionHeader(trimmed) {
                let poolName = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                var items: [(String, Gender?)] = []
                i += 1
                while i < lines.count {
                    let itemLine = lines[i]
                    guard itemLine.hasPrefix("  ") || itemLine.hasPrefix("\t") else { break }
                    let itemTrimmed = itemLine.trimmingCharacters(in: .whitespaces)
                    if itemTrimmed.isEmpty || itemTrimmed.hasPrefix("#") { i += 1; continue }
                    let (text, gender) = parsePoolItem(itemTrimmed)
                    items.append((text, gender))
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
                        pools: pools
                    )
                    steps.append(contentsOf: sectionSteps)

                case .inlineRepeat(let count, let text):
                    // ×N text... — simple repeat
                    for _ in 0..<count {
                        steps.append(contentsOf: expandSpeakLine(text, pools: pools))
                    }
                    i += 1

                case .blockRepeat(let count):
                    // ×N (alone) — read indented body, repeat N times
                    let bodyLines = collectIndentedBody(lines: lines, index: &i)
                    for _ in 0..<count {
                        for bodyLine in bodyLines {
                            steps.append(contentsOf: expandSpeakLine(bodyLine, pools: pools))
                        }
                    }
                }
                continue
            }

            // Bare speak line
            let lineSteps = expandSpeakLine(trimmed, pools: pools)
            steps.append(contentsOf: lineSteps)
            i += 1
        }

        return Meditation(title: title, steps: steps)
    }

    // MARK: - Pool Definition Header

    /// Returns true if the line is a pool definition header: `~ name` or `~name` with nothing else.
    private static func isPoolDefinitionHeader(_ line: String) -> Bool {
        guard line.hasPrefix("~") else { return false }
        let after = line.dropFirst().trimmingCharacters(in: .whitespaces)
        guard !after.isEmpty else { return false }
        return after.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    // MARK: - Pool Item Parsing

    private static func parsePoolItem(_ text: String) -> (String, Gender?) {
        if text.hasSuffix("\u{2640}") { // ♀
            let name = text.dropLast().trimmingCharacters(in: .whitespaces)
            return (name, .female)
        }
        if text.hasSuffix("\u{2642}") { // ♂
            let name = text.dropLast().trimmingCharacters(in: .whitespaces)
            return (name, .male)
        }
        return (text, nil)
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
        pools: [String: Pool]
    ) -> [MeditationStep] {
        var steps: [MeditationStep] = []

        for stanza in 0..<outerCount {
            for line in bodyLines {
                steps.append(contentsOf: expandSpeakLine(line, pools: pools))
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

    /// Expands a single speak line into steps, resolving pools, pauses, countdowns, and pronouns.
    private static func expandSpeakLine(_ line: String, pools: [String: Pool]) -> [MeditationStep] {
        var steps: [MeditationStep] = []
        var currentGender: Gender? = nil

        // Split line into segments: text, pauses, countdowns, pool refs
        let segments = tokenize(line)

        var textBuffer = ""

        for segment in segments {
            switch segment {
            case .text(let t):
                textBuffer += t
            case .poolRef(let name):
                if let pool = pools[name] {
                    let drawn = pool.draw()
                    if let g = pool.lastGender {
                        currentGender = g
                    }
                    // Re-tokenize drawn text to resolve nested pool refs, pauses, etc.
                    let innerTokens = tokenize(drawn)
                    let hasNestedSpecials = innerTokens.contains(where: {
                        if case .text = $0 { return false }; return true
                    })
                    if hasNestedSpecials {
                        // Flush current text buffer before inserting nested content
                        if !textBuffer.trimmingCharacters(in: .whitespaces).isEmpty {
                            let resolved = PronounResolver.resolve(textBuffer.trimmingCharacters(in: .whitespaces), gender: currentGender)
                            steps.append(.speak(resolved))
                            textBuffer = ""
                        }
                        // Recursively expand the drawn text as its own speak line
                        steps.append(contentsOf: expandSpeakLine(drawn, pools: pools))
                    } else {
                        textBuffer += drawn
                    }
                } else {
                    textBuffer += "~\(name)"
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
        case dots(Int)
        case seconds(TimeInterval)
        case countdown(TimeInterval)
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
