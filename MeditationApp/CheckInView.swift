import SwiftUI

struct CheckInView: View {
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var chipNamespace

    @State private var showingNegativeSheet = false
    @State private var showingPositiveSheet = false
    @State private var navigationPath = NavigationPath()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var selectedEmotions: [Emotion] {
        Emotion.all
            .filter { store.isSelected($0) }
            .sorted { store.count(for: $0) > store.count(for: $1) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(spacing: 20) {
                    // Selected emotion chips
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(selectedEmotions) { emotion in
                            SelectedEmotionChipView(
                                emotion: emotion,
                                namespace: chipNamespace,
                                onReflect: { navigationPath.append(emotion) }
                            )
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5).combined(with: .opacity),
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal)
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: selectedEmotions.map(\.id))

                    // Add emotion buttons
                    HStack(spacing: 12) {
                        Button {
                            showingNegativeSheet = true
                        } label: {
                            Label("Negative", systemImage: "minus.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingPositiveSheet = true
                        } label: {
                            Label("Positive", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(.secondarySystemBackground))
                                )
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Feelings")
            .navigationDestination(for: Emotion.self) { emotion in
                ReflectionView(emotion: emotion)
            }
        }
        .sheet(isPresented: $showingNegativeSheet) {
            EmotionPickerSheet(
                title: "Negative",
                emotions: Emotion.negative,
                namespace: chipNamespace
            )
        }
        .sheet(isPresented: $showingPositiveSheet) {
            EmotionPickerSheet(
                title: "Positive",
                emotions: Emotion.positive,
                namespace: chipNamespace
            )
        }
    }
}

// MARK: - Selected Emotion Chip (main screen)

private struct SelectedEmotionChipView: View {
    let emotion: Emotion
    var namespace: Namespace.ID
    var onReflect: () -> Void
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipColor)
                    .matchedGeometryEffect(id: emotion.id, in: namespace)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(0.7), lineWidth: 0.75)
                    .opacity(emotion.category == .positive ? 1 : 0)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onReflect()
            } label: {
                Label("Reflect", systemImage: "pencil.line")
            }
            Button(role: .destructive) {
                store.deselect(emotion)
            } label: {
                Label("Remove", systemImage: "xmark.circle")
            }
        } preview: {
            ReflectionPreview(emotion: emotion)
        }
    }
}

// MARK: - Context Menu Preview

private struct ReflectionPreview: View {
    let emotion: Emotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Text(emotion.emoji)
                    .font(.largeTitle)
                Text(emotion.name)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text(emotion.question)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                )

            Text("Tap \"Reflect\" to write your thoughts…")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Emotion Picker Sheet

private struct EmotionPickerSheet: View {
    let title: String
    let emotions: [Emotion]
    var namespace: Namespace.ID
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var justSelected: Set<String> = []

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var unselectedEmotions: [Emotion] {
        emotions.filter { !store.isSelected($0) && !justSelected.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(unselectedEmotions) { emotion in
                        Button {
                            selectEmotion(emotion)
                        } label: {
                            HStack(spacing: 6) {
                                Text(emotion.emoji)
                                    .font(.title3)
                                Text(emotion.name)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.secondarySystemBackground))
                                    .matchedGeometryEffect(id: emotion.id, in: namespace)
                            )
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: .scale(scale: 0.5).combined(with: .opacity)
                        ))
                    }
                }
                .padding()
                .animation(.spring(duration: 0.35, bounce: 0.25), value: unselectedEmotions.map(\.id))
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func selectEmotion(_ emotion: Emotion) {
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
            justSelected.insert(emotion.id)
        }
        // Small delay so the disappear animation plays before the chip appears on the main screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            store.tap(emotion)
        }
    }
}
