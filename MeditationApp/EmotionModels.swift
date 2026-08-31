import SwiftUI

enum EmotionCategory: String, Codable, CaseIterable {
    case negative, positive
}

struct Emotion: Identifiable, Hashable {
    let name: String
    let emoji: String
    let question: String
    let category: EmotionCategory
    let color: Color
    var id: String { name }

    func chipColor(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return color.mix(with: .black, by: 0.35)
        }
        return color.mix(with: .white, by: 0.45)
    }

    static let negative: [Emotion] = [
        Emotion(name: "Anger", emoji: "😠", question: "What way of living is being blocked?", category: .negative, color: Color(red: 0.88, green: 0.30, blue: 0.25)),
        Emotion(name: "Bitterness", emoji: "😤", question: "What way of living feels unfairly denied to you?", category: .negative, color: Color(red: 0.47, green: 0.44, blue: 0.16)),
        Emotion(name: "Confusion", emoji: "🤔", question: "What way of living was out of focus?", category: .negative, color: Color(red: 0.54, green: 0.54, blue: 0.52)),
        Emotion(name: "Despair", emoji: "🕳️", question: "What way of living feels permanently out of reach?", category: .negative, color: Color(red: 0.32, green: 0.29, blue: 0.35)),
        Emotion(name: "Disappointment", emoji: "😕", question: "What way of living did you hope for?", category: .negative, color: Color(red: 0.49, green: 0.51, blue: 0.56)),
        Emotion(name: "Disgust", emoji: "🤢", question: "What way of living is being violated?", category: .negative, color: Color(red: 0.25, green: 0.40, blue: 0.16)),
        Emotion(name: "Dread", emoji: "😱", question: "What way of living do you fear losing to what's coming?", category: .negative, color: Color(red: 0.46, green: 0.40, blue: 0.17)),
        Emotion(name: "Envy", emoji: "👀", question: "What way of living do you wish you could have?", category: .negative, color: Color(red: 0.38, green: 0.50, blue: 0.24)),
        Emotion(name: "Exhaustion", emoji: "🪫", question: "What way of living is on the other side of what's draining you?", category: .negative, color: Color(red: 0.46, green: 0.43, blue: 0.40)),
        Emotion(name: "Fear", emoji: "😨", question: "What way of living is threatened?", category: .negative, color: Color(red: 0.82, green: 0.73, blue: 0.16)),
        Emotion(name: "Fed Up", emoji: "🙅", question: "What way of living are you no longer willing to compromise?", category: .negative, color: Color(red: 0.68, green: 0.36, blue: 0.30)),
        Emotion(name: "Frustration", emoji: "😩", question: "What way of living keeps slipping out of reach?", category: .negative, color: Color(red: 0.82, green: 0.48, blue: 0.28)),
        Emotion(name: "Grief", emoji: "🖤", question: "What way of living has ended permanently?", category: .negative, color: Color(red: 0.27, green: 0.26, blue: 0.30)),
        Emotion(name: "Guilt", emoji: "😞", question: "What way of living did you compromise for someone else?", category: .negative, color: Color(red: 0.53, green: 0.42, blue: 0.48)),
        Emotion(name: "Hatred", emoji: "💢", question: "What way of living is being destroyed by someone or something you want gone?", category: .negative, color: Color(red: 0.72, green: 0.15, blue: 0.22)),
        Emotion(name: "Helplessness", emoji: "🫠", question: "What way of living feels impossible to influence?", category: .negative, color: Color(red: 0.45, green: 0.48, blue: 0.53)),
        Emotion(name: "Humiliation", emoji: "🙈", question: "What way of living did you feel permanently incapable of?", category: .negative, color: Color(red: 0.60, green: 0.31, blue: 0.42)),
        Emotion(name: "Hurt", emoji: "🤕", question: "What way of living were you wrongly deprived of?", category: .negative, color: Color(red: 0.62, green: 0.29, blue: 0.35)),
        Emotion(name: "Inadequacy", emoji: "📉", question: "What way of living do you feel unequipped for?", category: .negative, color: Color(red: 0.46, green: 0.41, blue: 0.46)),
        Emotion(name: "Loneliness", emoji: "🕸️", question: "What way of living depends on others being near?", category: .negative, color: Color(red: 0.27, green: 0.39, blue: 0.55)),
        Emotion(name: "Lost", emoji: "🧭", question: "What way of living can you no longer find your way back to?", category: .negative, color: Color(red: 0.44, green: 0.49, blue: 0.54)),
        Emotion(name: "Numbness", emoji: "😶", question: "What way of living have you stopped being able to feel?", category: .negative, color: Color(red: 0.46, green: 0.47, blue: 0.48)),
        Emotion(name: "Overwhelm", emoji: "🌊", question: "What ways of living are all demanding attention at once?", category: .negative, color: Color(red: 0.29, green: 0.49, blue: 0.62)),
        Emotion(name: "Rage", emoji: "🤬", question: "What way of living has been so blocked that you want to destroy the obstacle?", category: .negative, color: Color(red: 0.82, green: 0.18, blue: 0.18)),
        Emotion(name: "Regret", emoji: "😔", question: "What way of living do you wish you had chosen?", category: .negative, color: Color(red: 0.40, green: 0.48, blue: 0.57)),
        Emotion(name: "Resentment", emoji: "🧱", question: "What way of living has been dismissed or taken from you too many times?", category: .negative, color: Color(red: 0.64, green: 0.40, blue: 0.32)),
        Emotion(name: "Sadness", emoji: "😢", question: "What way of living was lost?", category: .negative, color: Color(red: 0.33, green: 0.49, blue: 0.68)),
        Emotion(name: "Scorn", emoji: "😒", question: "What way of living feels beneath what you can respect?", category: .negative, color: Color(red: 0.53, green: 0.43, blue: 0.18)),
        Emotion(name: "Shame", emoji: "😳", question: "What way of living did you not live up to?", category: .negative, color: Color(red: 0.45, green: 0.23, blue: 0.31)),
        Emotion(name: "Yearning", emoji: "🥺", question: "What way of living are you longing for?", category: .negative, color: Color(red: 0.58, green: 0.45, blue: 0.72)),
    ]

    static let positive: [Emotion] = [
        Emotion(name: "Acceptance", emoji: "🧘", question: "What way of living can you embrace as it is?", category: .positive, color: Color(red: 0.49, green: 0.65, blue: 0.69)),
        Emotion(name: "Belonging", emoji: "🤝", question: "What way of living makes you feel part of something?", category: .positive, color: Color(red: 0.63, green: 0.49, blue: 0.36)),
        Emotion(name: "Compassion", emoji: "💗", question: "What way of living opens your heart to others' experience?", category: .positive, color: Color(red: 0.78, green: 0.45, blue: 0.56)),
        Emotion(name: "Confidence", emoji: "💪", question: "What way of living do you feel ready for?", category: .positive, color: Color(red: 0.31, green: 0.50, blue: 0.73)),
        Emotion(name: "Curiosity", emoji: "🔍", question: "What way of living is pulling you to explore further?", category: .positive, color: Color(red: 0.31, green: 0.61, blue: 0.65)),
        Emotion(name: "Determination", emoji: "🔥", question: "What way of living are you committed to pursuing?", category: .positive, color: Color(red: 0.80, green: 0.42, blue: 0.22)),
        Emotion(name: "Excitement", emoji: "🎉", question: "What way of living is about to begin?", category: .positive, color: Color(red: 0.88, green: 0.55, blue: 0.25)),
        Emotion(name: "Gratitude", emoji: "🙏", question: "What way of living are you thankful for?", category: .positive, color: Color(red: 0.45, green: 0.72, blue: 0.45)),
        Emotion(name: "Hope", emoji: "🌟", question: "What way of living do you look forward to?", category: .positive, color: Color(red: 0.40, green: 0.62, blue: 0.85)),
        Emotion(name: "Inspiration", emoji: "✨", question: "What way of living has shown you what's possible?", category: .positive, color: Color(red: 0.64, green: 0.47, blue: 0.76)),
        Emotion(name: "Joy", emoji: "😄", question: "What way of living has opened up?", category: .positive, color: Color(red: 0.91, green: 0.71, blue: 0.25)),
        Emotion(name: "Love", emoji: "❤️", question: "What way of living feels deeply fulfilling and connected?", category: .positive, color: Color(red: 0.84, green: 0.31, blue: 0.44)),
        Emotion(name: "Peace", emoji: "☮️", question: "What way of living feels complete as it is?", category: .positive, color: Color(red: 0.37, green: 0.61, blue: 0.48)),
        Emotion(name: "Pride", emoji: "🦚", question: "What way of living reflects your achievements?", category: .positive, color: Color(red: 0.45, green: 0.42, blue: 0.78)),
        Emotion(name: "Relief", emoji: "😮‍💨", question: "What way of living is no longer under threat?", category: .positive, color: Color(red: 0.44, green: 0.66, blue: 0.67)),
        Emotion(name: "Safety", emoji: "🛡️", question: "What way of living lets you feel protected and at ease?", category: .positive, color: Color(red: 0.32, green: 0.55, blue: 0.46)),
        Emotion(name: "Tenderness", emoji: "🥰", question: "What way of living brings out your gentle care?", category: .positive, color: Color(red: 0.85, green: 0.55, blue: 0.64)),
        Emotion(name: "Trust", emoji: "🤲", question: "What way of living can you rely on?", category: .positive, color: Color(red: 0.32, green: 0.48, blue: 0.52)),
        Emotion(name: "Wonder", emoji: "🌈", question: "What way of living still surprises you?", category: .positive, color: Color(red: 0.65, green: 0.50, blue: 0.78)),
        Emotion(name: "Worthiness", emoji: "🏅", question: "What way of living feels rightfully yours?", category: .positive, color: Color(red: 0.78, green: 0.62, blue: 0.35)),
    ]

    static let all: [Emotion] = negative + positive

    static func named(_ name: String) -> Emotion? {
        all.first { $0.name == name }
    }
}

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let content: Content

    enum Content: Codable {
        case reflection(Reflection)
        case meditation(Meditation)
        case checkInSession(CheckInSession)

        struct Reflection: Codable {
            let emotionName: String
            let emoji: String
            let question: String
            let answer: String
        }

        struct Meditation: Codable {
            let title: String
            /// Basename of the .med file (no path, no extension). Acts as a stable
            /// per-meditation identifier across days. Nil for ad-hoc/sample playback.
            let filename: String?
            /// Always `true` in v1 — we only persist positive outcomes. Kept as a
            /// field so negative logging can be added later without a migration.
            let worked: Bool
        }

        struct CheckInSession: Codable {
            struct EmotionTally: Codable {
                let name: String
                let emoji: String
                let count: Int
                /// Cumulative engagement time attributed to this emotion, when available.
                let engagementSeconds: Double?
            }
            /// First tap of the session. The entry's `timestamp` is the session end.
            let startedAt: Date
            /// Cumulative engagement time at clear (mirrors `EmotionStore.sessionTime`).
            let engagementSeconds: Double
            /// Tallies sorted by engagement desc, falling back to count desc.
            let emotions: [EmotionTally]
        }
    }
}
