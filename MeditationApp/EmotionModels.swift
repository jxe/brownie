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
        return color.mix(with: .white, by: 0.35)
    }

    static let negative: [Emotion] = [
        Emotion(name: "Anger", emoji: "😠", question: "What way of living is being blocked by what external force?", category: .negative, color: Color(red: 0.88, green: 0.30, blue: 0.25)),
        Emotion(name: "Apathy", emoji: "😑", question: "What way of living has stopped mattering to you?", category: .negative, color: Color(red: 0.48, green: 0.48, blue: 0.48)),
        Emotion(name: "Bitterness", emoji: "😤", question: "What way of living feels unfairly denied to you?", category: .negative, color: Color(red: 0.72, green: 0.58, blue: 0.20)),
        Emotion(name: "Confusion", emoji: "🤔", question: "What way of living was out of focus?", category: .negative, color: Color(red: 0.60, green: 0.48, blue: 0.72)),
        Emotion(name: "Despair", emoji: "🕳️", question: "What way of living feels permanently out of reach?", category: .negative, color: Color(red: 0.38, green: 0.32, blue: 0.45)),
        Emotion(name: "Disappointment", emoji: "😕", question: "What way of living fell short of what you expected?", category: .negative, color: Color(red: 0.55, green: 0.52, blue: 0.62)),
        Emotion(name: "Disgust", emoji: "🤢", question: "What way of living is being violated?", category: .negative, color: Color(red: 0.40, green: 0.65, blue: 0.35)),
        Emotion(name: "Dread", emoji: "😱", question: "What way of living do you fear losing to what's coming?", category: .negative, color: Color(red: 0.50, green: 0.32, blue: 0.55)),
        Emotion(name: "Envy", emoji: "👀", question: "What way of living do you wish you could have?", category: .negative, color: Color(red: 0.45, green: 0.60, blue: 0.40)),
        Emotion(name: "Exhaustion", emoji: "🪫", question: "What way of living is on the other side of what's draining you?", category: .negative, color: Color(red: 0.52, green: 0.48, blue: 0.45)),
        Emotion(name: "Fear", emoji: "😨", question: "What way of living is threatened?", category: .negative, color: Color(red: 0.62, green: 0.42, blue: 0.75)),
        Emotion(name: "Frustration", emoji: "😩", question: "What way of living keeps slipping out of reach?", category: .negative, color: Color(red: 0.82, green: 0.48, blue: 0.28)),
        Emotion(name: "Grief", emoji: "🖤", question: "What way of living has ended permanently?", category: .negative, color: Color(red: 0.35, green: 0.35, blue: 0.40)),
        Emotion(name: "Guilt", emoji: "😞", question: "What way of living did you compromise in someone else?", category: .negative, color: Color(red: 0.58, green: 0.48, blue: 0.55)),
        Emotion(name: "Hatred", emoji: "💢", question: "What way of living is being destroyed by someone or something you want gone?", category: .negative, color: Color(red: 0.72, green: 0.15, blue: 0.22)),
        Emotion(name: "Helplessness", emoji: "🫠", question: "What way of living feels impossible to influence?", category: .negative, color: Color(red: 0.65, green: 0.58, blue: 0.48)),
        Emotion(name: "Humiliation", emoji: "🙈", question: "What way of living did you feel permanently incapable of?", category: .negative, color: Color(red: 0.78, green: 0.38, blue: 0.55)),
        Emotion(name: "Hurt", emoji: "🤕", question: "What happened that caused you pain?", category: .negative, color: Color(red: 0.72, green: 0.42, blue: 0.35)),
        Emotion(name: "Inadequacy", emoji: "📉", question: "What way of living do you feel unequipped for?", category: .negative, color: Color(red: 0.55, green: 0.45, blue: 0.40)),
        Emotion(name: "Jealousy", emoji: "💚", question: "What way of living do you see others enjoying?", category: .negative, color: Color(red: 0.35, green: 0.62, blue: 0.45)),
        Emotion(name: "Loneliness", emoji: "🕸️", question: "What type of connection was unavailable?", category: .negative, color: Color(red: 0.30, green: 0.45, blue: 0.70)),
        Emotion(name: "Lost", emoji: "🧭", question: "What way of living can you no longer find your way back to?", category: .negative, color: Color(red: 0.48, green: 0.52, blue: 0.58)),
        Emotion(name: "Numbness", emoji: "😶", question: "What way of living have you stopped being able to feel?", category: .negative, color: Color(red: 0.50, green: 0.50, blue: 0.52)),
        Emotion(name: "Overwhelm", emoji: "🌊", question: "What ways of living are all demanding attention at once?", category: .negative, color: Color(red: 0.38, green: 0.58, blue: 0.75)),
        Emotion(name: "Rage", emoji: "🤬", question: "What way of living has been so blocked that you want to destroy the obstacle?", category: .negative, color: Color(red: 0.82, green: 0.18, blue: 0.18)),
        Emotion(name: "Regret", emoji: "😔", question: "What way of living do you wish you had chosen?", category: .negative, color: Color(red: 0.55, green: 0.55, blue: 0.58)),
        Emotion(name: "Sadness", emoji: "😢", question: "What way of living was lost?", category: .negative, color: Color(red: 0.35, green: 0.55, blue: 0.82)),
        Emotion(name: "Shame", emoji: "😳", question: "What way of living did you not live up to?", category: .negative, color: Color(red: 0.85, green: 0.42, blue: 0.42)),
    ]

    static let positive: [Emotion] = [
        Emotion(name: "Acceptance", emoji: "🧘", question: "What way of living can you embrace as it is?", category: .positive, color: Color(red: 0.55, green: 0.70, blue: 0.78)),
        Emotion(name: "Awe", emoji: "🤩", question: "What way of living revealed something larger than yourself?", category: .positive, color: Color(red: 0.55, green: 0.40, blue: 0.82)),
        Emotion(name: "Belonging", emoji: "🤝", question: "What way of living makes you feel part of something?", category: .positive, color: Color(red: 0.62, green: 0.55, blue: 0.42)),
        Emotion(name: "Compassion", emoji: "💗", question: "What way of living opens your heart to others' experience?", category: .positive, color: Color(red: 0.75, green: 0.45, blue: 0.58)),
        Emotion(name: "Confidence", emoji: "💪", question: "What way of living do you feel ready for?", category: .positive, color: Color(red: 0.72, green: 0.55, blue: 0.30)),
        Emotion(name: "Curiosity", emoji: "🔍", question: "What way of living is pulling you to explore further?", category: .positive, color: Color(red: 0.82, green: 0.62, blue: 0.25)),
        Emotion(name: "Excitement", emoji: "🎉", question: "What way of living is about to begin?", category: .positive, color: Color(red: 0.88, green: 0.55, blue: 0.25)),
        Emotion(name: "Gratitude", emoji: "🙏", question: "What way of living are you thankful for?", category: .positive, color: Color(red: 0.45, green: 0.72, blue: 0.45)),
        Emotion(name: "Hope", emoji: "🌟", question: "What way of living do you look forward to?", category: .positive, color: Color(red: 0.40, green: 0.62, blue: 0.85)),
        Emotion(name: "Inspiration", emoji: "✨", question: "What way of living has shown you what's possible?", category: .positive, color: Color(red: 0.75, green: 0.65, blue: 0.30)),
        Emotion(name: "Joy", emoji: "😄", question: "What way of living has opened up?", category: .positive, color: Color(red: 0.90, green: 0.75, blue: 0.20)),
        Emotion(name: "Love", emoji: "❤️", question: "What way of living feels deeply fulfilling and connected?", category: .positive, color: Color(red: 0.85, green: 0.35, blue: 0.50)),
        Emotion(name: "Peace", emoji: "☮️", question: "What way of living feels complete as it is?", category: .positive, color: Color(red: 0.55, green: 0.72, blue: 0.60)),
        Emotion(name: "Pride", emoji: "🦚", question: "What way of living reflects your achievements?", category: .positive, color: Color(red: 0.45, green: 0.42, blue: 0.78)),
        Emotion(name: "Relief", emoji: "😮‍💨", question: "What way of living is no longer under threat?", category: .positive, color: Color(red: 0.50, green: 0.72, blue: 0.72)),
        Emotion(name: "Tenderness", emoji: "🥰", question: "What way of living brings out your gentle care?", category: .positive, color: Color(red: 0.82, green: 0.52, blue: 0.62)),
        Emotion(name: "Trust", emoji: "🤲", question: "What way of living can you rely on?", category: .positive, color: Color(red: 0.45, green: 0.60, blue: 0.55)),
        Emotion(name: "Wonder", emoji: "🌈", question: "What way of living still surprises you?", category: .positive, color: Color(red: 0.65, green: 0.50, blue: 0.78)),
    ]

    static let all: [Emotion] = negative + positive

    static func named(_ name: String) -> Emotion? {
        all.first { $0.name == name }
    }
}

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let emotionName: String
    let emoji: String
    let question: String
    let answer: String
    let timestamp: Date
}
