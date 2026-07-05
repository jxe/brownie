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
    let isActive: Bool

    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.feelingsTabCenterX) private var feelingsTabCenterX

    @State private var showingNegativeSheet = false
    @State private var showingPositiveSheet = false
    @State private var navigationPath = NavigationPath()
    @State private var destinationFrames: [String: CGRect] = [:]
    @State private var visibleChipFrames: [String: CGRect] = [:]
    @State private var scrollViewFrame: CGRect = .zero
    @State private var pendingDestinationFrames: [String: CGRect]?
    @State private var destinationFrameUpdateScheduled = false
    @State private var floatingTimeEvents: [String: [FloatingTimeEvent]] = [:]
    @State private var autoStopAccruingWorkItem: DispatchWorkItem?
    @State private var liveNow = Date()

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    private var formattedSessionTime: String {
        ChipTimeFormatter.string(from: store.sessionTime(asOf: liveNow))
    }

    private var selectedEmotions: [Emotion] {
        store.selectedEmotionsSorted(asOf: liveNow)
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
                                isAccruing: store.accruingEmotionID == emotion.id,
                                timeContribution: store.timeContribution(for: emotion, asOf: liveNow),
                                floatingTimes: floatingTimeEvents[emotion.id, default: []],
                                onTap: { tapSelectedEmotion(emotion) },
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
                        visibleChipFrames = frames
                        if showingNegativeSheet || showingPositiveSheet {
                            queueDestinationFrameUpdate(frames)
                        }
                    }
                }
                // .padding(.vertical)
                // Extra bottom padding so content doesn't hide behind floating buttons
                // .padding(.bottom, 10)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            scrollViewFrame = geo.frame(in: .global)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            scrollViewFrame = newFrame
                        }
                }
            )
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    let globalPoint = CGPoint(
                        x: scrollViewFrame.minX + value.location.x,
                        y: scrollViewFrame.minY + value.location.y
                    )
                    stopAccruingIfBackgroundTap(at: globalPoint)
                }
            )
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
                            openEmotionPicker(.negative)
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
                            openEmotionPicker(.positive)
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 58, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            stopAccruingAndShowCredit()
                        }
                        .contextMenu {
                            if !store.emotionCounts.isEmpty {
                                Button {
                                    store.logAndClearSession()
                                } label: {
                                    Label("Log & clear session", systemImage: "checkmark.circle")
                                }
                            }
                        }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .navigationDestination(for: Emotion.self) { emotion in
                ReflectionView(emotion: emotion)
            }
        }
        .onAppear {
            store.clearSessionIfStale()
            liveNow = Date()
            scheduleAutoStopAccruing()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.clearSessionIfStale()
                liveNow = Date()
                scheduleAutoStopAccruing()
            } else {
                stopAccruingWithoutAnimation()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                liveNow = Date()
                scheduleAutoStopAccruing()
            } else {
                stopAccruingWithoutAnimation()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            guard isActive, scenePhase == .active, store.accruingEmotionID != nil else { return }
            liveNow = now
        }
        .sheet(isPresented: $showingNegativeSheet) {
            EmotionPickerSheet(
                title: "Negative",
                emotions: Emotion.negative,
                destinationFrames: $destinationFrames,
                onTimeCredit: showFloatingTime,
                onAccruingChanged: scheduleAutoStopAccruing
            )
        }
        .sheet(isPresented: $showingPositiveSheet) {
            EmotionPickerSheet(
                title: "Positive",
                emotions: Emotion.positive,
                destinationFrames: $destinationFrames,
                onTimeCredit: showFloatingTime,
                onAccruingChanged: scheduleAutoStopAccruing
            )
        }
    }

    private func queueDestinationFrameUpdate(_ frames: [String: CGRect]) {
        pendingDestinationFrames = frames
        guard !destinationFrameUpdateScheduled else { return }

        destinationFrameUpdateScheduled = true
        DispatchQueue.main.async {
            destinationFrameUpdateScheduled = false
            guard showingNegativeSheet || showingPositiveSheet else {
                pendingDestinationFrames = nil
                return
            }
            guard let frames = pendingDestinationFrames else { return }
            pendingDestinationFrames = nil
            if destinationFrames != frames {
                destinationFrames = frames
            }
        }
    }

    private func tapSelectedEmotion(_ emotion: Emotion) {
        if let creditedEmotion = store.tap(emotion) {
            showFloatingTime(creditedEmotion)
        }
        liveNow = Date()
        scheduleAutoStopAccruing()
    }

    private func stopAccruingIfBackgroundTap(at point: CGPoint) {
        let tappedChip = visibleChipFrames.values.contains { $0.contains(point) }
        guard !tappedChip else { return }

        stopAccruingAndShowCredit()
    }

    private func openEmotionPicker(_ category: EmotionCategory) {
        stopAccruingAndShowCredit()
        switch category {
        case .negative:
            showingNegativeSheet = true
        case .positive:
            showingPositiveSheet = true
        }
    }

    private func showFloatingTime(_ credit: EmotionStore.TimeCredit) {
        addFloatingTime(for: credit.emotionID, seconds: credit.totalContribution)
    }

    private func stopAccruingAndShowCredit() {
        cancelAutoStopAccruing()
        if let creditedEmotion = store.stopAccruing() {
            showFloatingTime(creditedEmotion)
        }
        liveNow = Date()
    }

    private func stopAccruingWithoutAnimation() {
        cancelAutoStopAccruing()
        store.stopAccruing()
        liveNow = Date()
    }

    private func scheduleAutoStopAccruing() {
        cancelAutoStopAccruing()

        guard isActive,
              scenePhase == .active,
              let emotionID = store.accruingEmotionID,
              let startedAt = store.accruingStartedAt else { return }

        let remaining = EmotionStore.maxEmotionCreditDuration - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else {
            stopAccruingAndShowCredit()
            return
        }

        let workItem = DispatchWorkItem {
            guard store.accruingEmotionID == emotionID else { return }
            stopAccruingAndShowCredit()
        }
        autoStopAccruingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: workItem)
    }

    private func cancelAutoStopAccruing() {
        autoStopAccruingWorkItem?.cancel()
        autoStopAccruingWorkItem = nil
    }

    private func addFloatingTime(for emotionID: String, seconds: TimeInterval) {
        let event = FloatingTimeEvent(seconds: seconds)
        floatingTimeEvents[emotionID, default: []].append(event)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            floatingTimeEvents[emotionID]?.removeAll { $0.id == event.id }
            if floatingTimeEvents[emotionID]?.isEmpty == true {
                floatingTimeEvents.removeValue(forKey: emotionID)
            }
        }
    }
}

// MARK: - Selected Emotion Chip (main screen)

private struct FloatingTimeEvent: Identifiable {
    let id = UUID()
    let seconds: TimeInterval
}

private struct SelectedEmotionChipView: View {
    let emotion: Emotion
    let isAccruing: Bool
    let timeContribution: TimeInterval
    let floatingTimes: [FloatingTimeEvent]
    var onTap: () -> Void
    var onReflect: () -> Void
    @Environment(EmotionStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    private var chipColor: Color {
        emotion.chipColor(for: colorScheme)
    }
    private var counterColor: Color {
        .white
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(spacing: 6) {
                Text(emotion.emoji)
                    .font(.title3)
                Text(emotion.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                EmotionChipBackground(emotion: emotion, colorScheme: colorScheme)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.yellow.opacity(colorScheme == .dark ? 0.7 : 1.0), lineWidth: colorScheme == .dark ? 0.75 : 1.25)
                    .opacity(emotion.category == .positive ? 1 : 0)
            )
            .overlay(alignment: .trailing) {
                if isAccruing {
                    Text(ChipTimeFormatter.string(from: timeContribution))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(counterColor)
                        .shadow(color: counterColor.opacity(0.95), radius: 5)
                        .shadow(color: counterColor.opacity(0.65), radius: 10)
                        .padding(.leading, 6)
                        .background(chipColor)
                        .padding(.trailing, 12)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
        .buttonStyle(ScaleButtonStyle())
        .overlay(alignment: .trailing) {
            ZStack {
                ForEach(floatingTimes) { entry in
                    FloatingTimeContributionView(seconds: entry.seconds)
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
}

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0))
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

private struct FloatingTimeContributionView: View {
    let seconds: TimeInterval
    @State private var isVisible = false
    private let tilt: Double = .random(in: -10...10)
    private var drift: CGFloat { CGFloat(tilt) * 0.5 }

    var body: some View {
        Text(ChipTimeFormatter.string(from: seconds))
            .font(.subheadline)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundStyle(.primary.opacity(isVisible ? 0 : 0.8))
            .rotationEffect(.degrees(isVisible ? tilt : 0))
            .offset(x: isVisible ? drift : 0, y: isVisible ? -34 : 0)
            .scaleEffect(isVisible ? 1.25 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    isVisible = true
                }
            }
    }
}

private enum ChipTimeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 {
            return "\(total)s"
        }

        if total >= 60 * 60 {
            let totalMinutes = Int((Double(total) / 60).rounded())
            return "\(totalMinutes / 60)h\(totalMinutes % 60)m"
        }

        let roundedMinutes = (Double(total) / 60 * 10).rounded() / 10
        if roundedMinutes.rounded() == roundedMinutes {
            return "\(Int(roundedMinutes))m"
        }
        return String(format: "%.1fm", roundedMinutes)
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
    var onTimeCredit: (EmotionStore.TimeCredit) -> Void
    var onAccruingChanged: () -> Void
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
        if let creditedEmotion = store.tap(emotion) {
            onTimeCredit(creditedEmotion)
        }
        onAccruingChanged()

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
            EmotionChipBackground(emotion: emotion, colorScheme: colorScheme)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.yellow.opacity(colorScheme == .dark ? 0.7 : 1.0), lineWidth: colorScheme == .dark ? 0.75 : 1.5)
                .opacity(emotion.category == .positive ? 1 : 0)
        )
        .foregroundStyle(colorScheme == .dark ? .white : .black)
    }
}

private struct EmotionChipBackground: View {
    let emotion: Emotion
    let colorScheme: ColorScheme

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 10)
                .fill(emotion.chipGradient(for: colorScheme, size: geo.size))
        }
    }
}

private extension Emotion {
    func chipGradient(for colorScheme: ColorScheme, size: CGSize) -> LinearGradient {
        let base = chipColor(for: colorScheme)
        let points = UnitPoint.gradientEndpoints(angle: .degrees(62), in: size)

        return LinearGradient(
            colors: [
                base.mix(with: .white, by: colorScheme == .dark ? 0.08 : 0.18),
                base,
                base.mix(with: .black, by: colorScheme == .dark ? 0.10 : 0.06),
            ],
            startPoint: points.start,
            endPoint: points.end
        )
    }
}

private extension UnitPoint {
    static func gradientEndpoints(angle: Angle, in size: CGSize) -> (start: UnitPoint, end: UnitPoint) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let radians = angle.radians
        let dx = cos(radians)
        let dy = sin(radians)
        let halfLength = (abs(width * dx) + abs(height * dy)) / 2

        return (
            UnitPoint(
                x: 0.5 - (dx * halfLength / width),
                y: 0.5 - (dy * halfLength / height)
            ),
            UnitPoint(
                x: 0.5 + (dx * halfLength / width),
                y: 0.5 + (dy * halfLength / height)
            )
        )
    }
}
