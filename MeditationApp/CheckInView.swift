import SwiftUI

struct CheckInView: View {
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingNegativeSheet = false
    @State private var showingPositiveSheet = false
    @State private var navigationPath = NavigationPath()
    @State private var destinationFrames: [String: CGRect] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var formattedSessionTime: String {
        let total = Int(store.sessionTime)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

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
                                onReflect: { navigationPath.append(emotion) }
                            )
                            .opacity(store.inFlightEmotions.contains(emotion.id) ? 0 : 1)
                            .transition(.asymmetric(
                                insertion: .identity,
                                removal: .scale(scale: 0.8).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal)
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: selectedEmotions.map(\.id))
                    .onPreferenceChange(ChipDestinationPreferenceKey.self) { frames in
                        destinationFrames = frames
                    }

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(formattedSessionTime)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: Emotion.self) { emotion in
                ReflectionView(emotion: emotion)
            }
        }
        .sheet(isPresented: $showingNegativeSheet) {
            EmotionPickerSheet(
                title: "Negative",
                emotions: Emotion.negative,
                destinationFrames: $destinationFrames
            )
        }
        .sheet(isPresented: $showingPositiveSheet) {
            EmotionPickerSheet(
                title: "Positive",
                emotions: Emotion.positive,
                destinationFrames: $destinationFrames
            )
        }
    }
}

// MARK: - Selected Emotion Chip (main screen)

private struct SelectedEmotionChipView: View {
    let emotion: Emotion
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
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(colorScheme == .dark ? 0.7 : 1.0), lineWidth: colorScheme == .dark ? 0.75 : 1.25)
                    .opacity(emotion.category == .positive ? 1 : 0)
            )
            .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .buttonStyle(.plain)
        .overlay(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ChipDestinationPreferenceKey.self,
                    value: [emotion.id: geo.frame(in: .global)]
                )
            }
        )
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
    @Binding var destinationFrames: [String: CGRect]
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var justSelected: Set<String> = []
    @State private var chipFrames: [String: CGRect] = [:]

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
                            )
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear {
                                        chipFrames[emotion.id] = geo.frame(in: .global)
                                    }
                                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                        chipFrames[emotion.id] = newFrame
                                    }
                            }
                        )
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
        let sourceFrame = chipFrames[emotion.id] ?? .zero

        // Hide chip in the sheet
        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
            _ = justSelected.insert(emotion.id)
        }

        // Mark as in-flight and add to store so the main grid lays out the chip (invisible)
        store.inFlightEmotions.insert(emotion.id)
        store.tap(emotion)

        // Wait one frame for the main grid to lay out the new chip and report its frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let destFrame = destinationFrames[emotion.id] ?? .zero

            // Build a snapshot view matching the destination chip appearance
            let chipSnapshot = FlightChipView(
                emotion: emotion,
                count: store.count(for: emotion),
                width: destFrame.width,
                colorScheme: colorScheme
            )

            if sourceFrame != .zero && destFrame != .zero {
                ChipFlightAnimator.shared.fly(
                    emotionId: emotion.id,
                    chipView: chipSnapshot,
                    from: sourceFrame,
                    to: destFrame
                ) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        _ = store.inFlightEmotions.remove(emotion.id)
                    }
                }
            } else {
                // Fallback: just reveal the chip
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    _ = store.inFlightEmotions.remove(emotion.id)
                }
            }

            dismiss()
        }
    }
}

// MARK: - Flight Chip Snapshot View

/// A lightweight view rendered by ImageRenderer to create the flying chip snapshot.
private struct FlightChipView: View {
    let emotion: Emotion
    let count: Int
    let width: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
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
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.5))
        }
        .frame(width: width - 24, alignment: .leading) // account for horizontal padding
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(emotion.chipColor(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.yellow.opacity(colorScheme == .dark ? 0.7 : 1.0), lineWidth: colorScheme == .dark ? 0.75 : 1.5)
                .opacity(emotion.category == .positive ? 1 : 0)
        )
        .foregroundStyle(colorScheme == .dark ? .white : .black)
    }
}
