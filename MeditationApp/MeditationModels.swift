import Foundation

// MARK: - Pool (shuffled random picker)

class Pool {
    private let items: [(text: String, gender: Gender?)]
    private var remaining: [(text: String, gender: Gender?)] = []
    private(set) var lastGender: Gender?

    init(items: [(String, Gender?)]) {
        self.items = items
    }

    func draw() -> String {
        if remaining.isEmpty {
            remaining = items.shuffled()
        }
        let item = remaining.removeLast()
        if let g = item.gender {
            lastGender = g
        }
        return item.text
    }
}

// MARK: - Gender & Pronoun Resolution

enum Gender {
    case female, male
}

struct PronounResolver {
    static func resolve(_ text: String, gender: Gender?) -> String {
        guard let gender = gender else { return text }
        var result = text
        let replacements: [(pattern: String, female: String, male: String)] = [
            ("\\bthemselves\\b", "herself", "himself"),
            ("\\btheirs\\b", "hers", "his"),
            ("\\btheir\\b", "her", "his"),
            ("\\bthem\\b", "her", "him"),
            ("\\bthey\\b", "she", "he"),
            ("\\bThemselves\\b", "Herself", "Himself"),
            ("\\bTheirs\\b", "Hers", "His"),
            ("\\bTheir\\b", "Her", "His"),
            ("\\bThem\\b", "Her", "Him"),
            ("\\bThey\\b", "She", "He"),
        ]
        for r in replacements {
            if let regex = try? NSRegularExpression(pattern: r.pattern) {
                let range = NSRange(result.startIndex..., in: result)
                let replacement = gender == .female ? r.female : r.male
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        return result
    }
}

// MARK: - Meditation Steps

enum MeditationStep {
    case speak(String)
    case pause(TimeInterval)
    case countdown(TimeInterval) // spoken countdown
    case bell
}

// MARK: - Parsed Meditation

struct Meditation {
    let title: String
    let steps: [MeditationStep]
}
