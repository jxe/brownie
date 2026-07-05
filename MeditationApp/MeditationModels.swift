import Foundation

// MARK: - Pool (weighted random picker)

class Pool {
    private struct Item: Equatable {
        let text: String
        let gender: Gender?
        let weight: Int
    }

    private let items: [Item]
    private var remainingCounts: [Int] = []
    private var lastDrawn: Item?
    private(set) var lastGender: Gender?

    init(items: [(String, Gender?, Int)]) {
        var combined: [Item] = []
        for item in items {
            let weight = max(1, item.2)
            if let index = combined.firstIndex(where: { $0.text == item.0 && $0.gender == item.1 }) {
                let existing = combined[index]
                combined[index] = Item(text: existing.text, gender: existing.gender, weight: existing.weight + weight)
            } else {
                combined.append(Item(text: item.0, gender: item.1, weight: weight))
            }
        }
        self.items = combined
        self.remainingCounts = combined.map(\.weight)
    }

    func draw() -> String {
        guard !items.isEmpty else { return "" }

        if remainingCounts.allSatisfy({ $0 == 0 }) {
            remainingCounts = items.map(\.weight)
        }

        var candidates = remainingCounts.indices.filter { remainingCounts[$0] > 0 }
        if let lastDrawn {
            let nonRepeating = candidates.filter { items[$0] != lastDrawn }
            if !nonRepeating.isEmpty {
                candidates = nonRepeating
            }
        }

        let totalWeight = candidates.reduce(0) { $0 + remainingCounts[$1] }
        var pick = Int.random(in: 0..<totalWeight)
        let selectedIndex = candidates.first { index in
            pick -= remainingCounts[index]
            return pick < 0
        } ?? candidates[0]

        remainingCounts[selectedIndex] -= 1
        let item = items[selectedIndex]
        lastDrawn = item
        if let g = item.gender {
            lastGender = g
        }
        return item.text
    }
}

// MARK: - Gender & Pronoun Resolution

enum Gender: Equatable {
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
    case bell(String)            // bell id from BellRegistry
}

// MARK: - Parsed Meditation

struct Meditation {
    let title: String
    let steps: [MeditationStep]
}
