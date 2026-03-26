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

            // Pool definition: ~ name
            if trimmed.hasPrefix("~") {
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

            // Section: §N rest or §N×M innerDelay outerRest
            if trimmed.hasPrefix("§") {
                let (outerCount, innerCount, innerDelay, outerRest) = parseSectionHeader(trimmed)
                var bodyLines: [String] = []
                i += 1
                while i < lines.count {
                    let bodyLine = lines[i]
                    guard bodyLine.hasPrefix("  ") || bodyLine.hasPrefix("\t") else { break }
                    let bodyTrimmed = bodyLine.trimmingCharacters(in: .whitespaces)
                    if !bodyTrimmed.isEmpty && !bodyTrimmed.hasPrefix("#") {
                        bodyLines.append(bodyTrimmed)
                    }
                    i += 1
                }
                let sectionSteps = expandSection(
                    bodyLines: bodyLines,
                    outerCount: outerCount,
                    innerCount: innerCount,
                    innerDelay: innerDelay,
                    outerRest: outerRest,
                    pools: pools
                )
                steps.append(contentsOf: sectionSteps)
                continue
            }

            // Bare speak line
            let lineSteps = expandSpeakLine(trimmed, pools: pools)
            steps.append(contentsOf: lineSteps)
            i += 1
        }

        return Meditation(title: title, steps: steps)
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

    // MARK: - Section Header Parsing

    /// Parses: §5 28″  or  §3×5 6″ 28″
    private static func parseSectionHeader(_ header: String) -> (outerCount: Int, innerCount: Int?, innerDelay: TimeInterval?, outerRest: TimeInterval) {
        let body = String(header.dropFirst()) // drop §
        let tokens = body.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard let first = tokens.first else {
            return (5, nil, nil, 28)
        }

        // Check for × (nested: §3×5 6″ 28″)
        if first.contains("\u{00D7}") { // ×
            let parts = first.split(separator: "\u{00D7}")
            let outer = Int(parts[0]) ?? 3
            let inner = parts.count > 1 ? Int(parts[1]) ?? 5 : 5
            let innerDel = tokens.count > 1 ? parseSeconds(String(tokens[1])) : 12
            let outerRest = tokens.count > 2 ? parseSeconds(String(tokens[2])) : 28
            return (outer, inner, innerDel, outerRest)
        }

        // Simple: §5 28″
        let count = Int(first) ?? 5
        let rest = tokens.count > 1 ? parseSeconds(String(tokens[1])) : 28
        return (count, nil, nil, rest)
    }

    /// Parses "28″" or "28" -> 28.0
    private static func parseSeconds(_ token: String) -> TimeInterval {
        let cleaned = token.replacingOccurrences(of: "\u{2033}", with: "") // remove ″
            .replacingOccurrences(of: "\u{2032}", with: "") // remove ′
        if token.contains("\u{2032}") { // minutes
            return (Double(cleaned) ?? 1) * 60
        }
        return Double(cleaned) ?? 0
    }

    // MARK: - Section Expansion

    private static func expandSection(
        bodyLines: [String],
        outerCount: Int,
        innerCount: Int?,
        innerDelay: TimeInterval?,
        outerRest: TimeInterval,
        pools: [String: Pool]
    ) -> [MeditationStep] {
        var steps: [MeditationStep] = []

        for stanza in 0..<outerCount {
            // If nested (hymn), run inner cycles
            if let innerCount = innerCount, let innerDelay = innerDelay {
                for cycle in 0..<innerCount {
                    for line in bodyLines {
                        steps.append(contentsOf: expandSpeakLine(line, pools: pools))
                    }
                    if cycle < innerCount - 1 {
                        steps.append(.pause(innerDelay))
                    }
                }
            } else {
                // Simple stanza: just run the body lines
                for line in bodyLines {
                    steps.append(contentsOf: expandSpeakLine(line, pools: pools))
                }
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
                    textBuffer += drawn
                    if let g = pool.lastGender {
                        currentGender = g
                    }
                } else {
                    textBuffer += "{\(name)}"
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
                while i < chars.count && (chars[i].isNumber || chars[i] == "." || chars[i] == "\u{2033}" || chars[i] == "\u{2032}") {
                    numStr.append(chars[i])
                    i += 1
                }
                let secs = parseSeconds(numStr)
                tokens.append(.countdown(secs))
                continue
            }

            // Pool reference: {name}
            if ch == "{" {
                if !textBuf.isEmpty {
                    tokens.append(.text(textBuf))
                    textBuf = ""
                }
                i += 1
                var name = ""
                while i < chars.count && chars[i] != "}" {
                    name.append(chars[i])
                    i += 1
                }
                if i < chars.count { i += 1 } // skip }
                tokens.append(.poolRef(name))
                continue
            }

            // Inline seconds: digits followed by ″ or ′
            if ch.isNumber {
                // Look ahead for ″ or ′
                var numStr = String(ch)
                var j = i + 1
                while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                    numStr.append(chars[j])
                    j += 1
                }
                if j < chars.count && (chars[j] == "\u{2033}" || chars[j] == "\u{2032}") {
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
