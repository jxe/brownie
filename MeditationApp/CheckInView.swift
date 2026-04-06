import SwiftUI

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
                }
                .padding(.vertical)
                // Extra bottom padding so content doesn't hide behind floating buttons
                .padding(.bottom, 60)
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
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)

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
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 10) // compensate for tail height so labels center in body
                    .background(
                        SpeechBubbleShape(tailFraction: tailFraction)
                            .fill(Color(.secondarySystemFill))
                            .overlay(
                                SpeechBubbleShape(tailFraction: tailFraction)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                                    .blur(radius: 2)
                                    .offset(y: 1)
                                    .clipShape(SpeechBubbleShape(tailFraction: tailFraction))
                            )
                    )
                    .padding(.horizontal, barHorizontalPadding)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 80)
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
    @State private var isPressed = false
    @State private var showScaled = false

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
        .buttonStyle(.plain)
        .scaleEffect(showScaled ? 1.05 : 1.0)
        .animation(showScaled ? .interpolatingSpring(stiffness: 1200, damping: 15) : .spring(duration: 0.25, bounce: 0.4), value: showScaled)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    showScaled = true
                }
                .onEnded { _ in
                    isPressed = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        if !isPressed { showScaled = false }
                    }
                }
        )
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

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.08 : 1.0)
            .animation(configuration.isPressed ? .interpolatingSpring(stiffness: 1200, damping: 15) : .spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private struct FloatingPlusOneView: View {
    let count: Int
    @State private var isVisible = false

    var body: some View {
        Text("\(count)")
            .font(.caption)
            .fontWeight(.bold)
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

// MARK: - Speech Bubble Shape

private struct SpeechBubbleShape: InsettableShape {
    var tailFraction: CGFloat = 1.0 / 6.0
    var tailWidth: CGFloat = 20
    var tailHeight: CGFloat = 10
    var cornerRadius: CGFloat = 18
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> SpeechBubbleShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let bodyBottom = r.maxY - tailHeight
        let tailCenterX = r.minX + r.width * tailFraction
        let halfTail = tailWidth / 2
        let cr = min(cornerRadius, r.width / 2, (r.height - tailHeight) / 2)

        var path = Path()

        // Start at top-left after corner
        path.move(to: CGPoint(x: r.minX + cr, y: r.minY))
        // Top edge
        path.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))
        // Top-right corner
        path.addArc(center: CGPoint(x: r.maxX - cr, y: r.minY + cr), radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge
        path.addLine(to: CGPoint(x: r.maxX, y: bodyBottom - cr))
        // Bottom-right corner
        path.addArc(center: CGPoint(x: r.maxX - cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        // Bottom edge to tail
        path.addLine(to: CGPoint(x: tailCenterX + halfTail, y: bodyBottom))
        // Tail
        path.addLine(to: CGPoint(x: tailCenterX, y: r.maxY))
        path.addLine(to: CGPoint(x: tailCenterX - halfTail, y: bodyBottom))
        // Bottom edge to left
        path.addLine(to: CGPoint(x: r.minX + cr, y: bodyBottom))
        // Bottom-left corner
        path.addArc(center: CGPoint(x: r.minX + cr, y: bodyBottom - cr), radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        // Top-left corner
        path.addArc(center: CGPoint(x: r.minX + cr, y: r.minY + cr), radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()

        return path
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
