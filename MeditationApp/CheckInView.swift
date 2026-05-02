import SwiftUI
import UIKit

// MARK: - Disable ScrollView touch delay

/// Finds the nearest parent UIScrollView and sets delaysContentTouches = false
/// so that ButtonStyle.isPressed fires immediately on touch down.
private struct DisableScrollTouchDelay: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            var current: UIView? = view.superview
            while let parent = current {
                if let scrollView = parent as? UIScrollView {
                    scrollView.delaysContentTouches = false
                    break
                }
                current = parent.superview
            }
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct CheckInView: View {
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.feelingsTabCenterX) private var feelingsTabCenterX

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
                DisableScrollTouchDelay()
                    .frame(width: 0, height: 0)
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
                        if showingNegativeSheet || showingPositiveSheet {
                            destinationFrames = frames
                        }
                    }
                }
                // .padding(.vertical)
                // Extra bottom padding so content doesn't hide behind floating buttons
                // .padding(.bottom, 10)
            }
            .safeAreaInset(edge: .bottom) {
                GeometryReader { geo in
                    let barHorizontalPadding: CGFloat = 40
                    let barOriginX = geo.frame(in: .global).minX + barHorizontalPadding
                    let barWidth = geo.size.width - barHorizontalPadding * 2
                    // Map the feelings tab center (global X) into fraction of bar width
                    let tabX = feelingsTabCenterX ?? geo.size.width / 6
                    let tailFraction = max(0.08, min(0.92, (tabX - barOriginX) / barWidth))

                    HStack(spacing: 0) {
                        Button {
                            showingNegativeSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.tint)
                                Text("Negative")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        }
                        .buttonStyle(GlassPressStyle())

                        Divider()
                            .frame(height: 24)

                        Button {
                            showingPositiveSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(.tint)
                                Text("Positive")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                        }
                        .buttonStyle(GlassPressStyle())
                    }
                    .padding(.bottom, 10)
                    .clipShape(SpeechBubbleShape(tailFraction: tailFraction))
                    .contentShape(Rectangle())
                    .glassEffect(.regular, in: SpeechBubbleShape(tailFraction: tailFraction))
                    .padding(.horizontal, barHorizontalPadding)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 104)
                .padding(.bottom, 4)
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
        .onAppear { store.clearSessionIfStale() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active { store.clearSessionIfStale() }
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
    @State private var floatingCounts: [(id: UUID, count: Int)] = []
    private var chipColor: Color {
        emotion.chipColor(for: colorScheme)
    }

    var body: some View {
        Button {
            store.tap(emotion)
            triggerFloatingCount()
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
                    .fill(chipColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(colorScheme == .dark ? 0.7 : 1.0), lineWidth: colorScheme == .dark ? 0.75 : 1.25)
                    .opacity(emotion.category == .positive ? 1 : 0)
            )
            .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .buttonStyle(ScaleButtonStyle())
        .overlay(alignment: .trailing) {
            ZStack {
                ForEach(floatingCounts, id: \.id) { entry in
                    FloatingPlusOneView(count: entry.count)
                }
            }
            .padding(.trailing, 12)
        }
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

    private func triggerFloatingCount() {
        let id = UUID()
        floatingCounts.append((id: id, count: count))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            floatingCounts.removeAll { $0.id == id }
        }
    }
}

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.white.opacity(configuration.isPressed ? 0.2 : 0)
                    .blendMode(.plusLighter)
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScaleButtonContent(isPressed: configuration.isPressed, label: configuration.label)
    }
}

private struct ScaleButtonContent: View {
    let isPressed: Bool
    let label: ButtonStyleConfiguration.Label
    @State private var showScaled = false

    var body: some View {
        label
            .scaleEffect(showScaled ? 1.05 : 1.0)
            .animation(showScaled ? .interpolatingSpring(stiffness: 1200, damping: 15) : .spring(duration: 0.25, bounce: 0.4), value: showScaled)
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    showScaled = true
                } else {
                    // Keep scaled for at least 80ms after release
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        if !self.isPressed { showScaled = false }
                    }
                }
            }
    }
}

private struct FloatingPlusOneView: View {
    let count: Int
    @State private var isVisible = false

    var body: some View {
        Text("\(count)")
            .font(.title3)
            .foregroundStyle(.primary.opacity(isVisible ? 0 : 0.8))
            .offset(y: isVisible ? -30 : 0)
            .scaleEffect(isVisible ? 1.2 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7)) {
                    isVisible = true
                }
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
    let width: CGFloat
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            Text(emotion.emoji)
                .font(.title3)
            Text(emotion.name)
                .font(.subheadline)
                .fontWeight(.medium)
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
