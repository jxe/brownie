import SwiftUI

struct CheckInView: View {
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var selectedEmotions: [Emotion] {
        Emotion.all
            .filter { store.isSelected($0) }
            .sorted { store.count(for: $0) > store.count(for: $1) }
    }

    private var unselectedNegative: [Emotion] {
        Emotion.negative.filter { !store.isSelected($0) }
    }

    private var unselectedPositive: [Emotion] {
        Emotion.positive.filter { !store.isSelected($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !selectedEmotions.isEmpty {
                    emotionGrid(emotions: selectedEmotions)
                }

                if !unselectedNegative.isEmpty {
                    emotionSection(title: "Negative", emotions: unselectedNegative)
                }

                if !unselectedPositive.isEmpty {
                    emotionSection(title: "Positive", emotions: unselectedPositive)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Feelings")
    }

    @ViewBuilder
    private func emotionGrid(emotions: [Emotion]) -> some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(emotions) { emotion in
                EmotionChipView(emotion: emotion)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func emotionSection(title: String, emotions: [Emotion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            emotionGrid(emotions: emotions)
        }
    }
}

private struct EmotionChipView: View {
    let emotion: Emotion
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    private var isSelected: Bool { store.isSelected(emotion) }
    private var count: Int { store.count(for: emotion) }

    private var chipColor: Color {
        emotion.chipColor(for: colorScheme)
    }

    var body: some View {
        Button {
            store.tap(emotion)
        } label: {
            HStack(spacing: 6) {
                Text(emotion.emoji)
                    .font(.title3)
                Text(emotion.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if isSelected {
                    Spacer()
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.3))
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? chipColor : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 0.75)
                    .opacity(isSelected && emotion.category == .positive ? 1 : 0)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isSelected {
                Button(role: .destructive) {
                    store.deselect(emotion)
                } label: {
                    Label("Remove", systemImage: "xmark.circle")
                }
            }
        }
    }
}
