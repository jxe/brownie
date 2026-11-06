import SwiftUI

extension EnvironmentValues {
    /// Opens the left panel (History and Settings) from anywhere on the main screen.
    @Entry var openPanel: () -> Void = {}
    /// Whether the left panel is open, so the main screen can refresh what Settings may have changed.
    @Entry var panelIsOpen = false
}

@main
struct BrownieApp: App {
    @State private var player = MeditationPlayer()
    @State private var emotionStore = EmotionStore()
    private let icloudWatcher = iCloudMeditationWatcher()

    init() {
        FileManager.default.configureInitialMeditationStorageIfNeeded()
        Task { await SampleMeditations.installIfNeeded() }
        icloudWatcher.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
                .environment(emotionStore)
        }
    }
}

/// One main screen, with History and Settings in a panel that slides out from the left.
struct ContentView: View {
    @Environment(MeditationPlayer.self) var player
    @State private var panelOpen = false
    /// How far a drag has moved the main screen, while one is under way.
    @State private var dragOffset: CGFloat = 0
    /// Whether History is built at all. It stays up through the closing slide, then goes,
    /// so nothing behind the main screen re-renders as the store changes.
    @State private var panelMounted = false

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.85, 380)
            let offset = max(0, min(panelWidth, (panelOpen ? panelWidth : 0) + dragOffset))
            ZStack(alignment: .leading) {
                if panelMounted {
                    NavigationStack {
                        JournalView()
                    }
                    .frame(width: panelWidth)
                }

                NavigationStack {
                    MeditationListView(shelf: .home)
                }
                .environment(\.openPanel, { setPanel(open: true) })
                .environment(\.panelIsOpen, panelOpen)
                .allowsHitTesting(!panelOpen)
                .overlay {
                    // While the panel is open, a tap or a leftward drag on the main screen closes it.
                    if panelOpen {
                        Color.black.opacity(0.0001)
                            .onTapGesture { setPanel(open: false) }
                            .gesture(closeDrag(panelWidth: panelWidth))
                    }
                }
                // The shadow comes from a plain shape behind the screen: a shadow on the
                // whole NavigationStack would re-render offscreen on every change.
                .background {
                    if offset > 0 {
                        Rectangle()
                            .fill(Color("BackgroundColor"))
                            .shadow(color: .black.opacity(0.18), radius: 12)
                            .ignoresSafeArea()
                    }
                }
                .offset(x: offset)
            }
        }
        // med.nxhx.org/m/<id> universal links and brownie://m/<id> open the store item.
        .onOpenURL { url in
            guard let id = MeditationStore.recordName(from: url) else { return }
            setPanel(open: false)
            MeditationStore.shared.openedLinkID = id
        }
    }

    private func setPanel(open: Bool) {
        if open { panelMounted = true }
        withAnimation(.snappy(duration: 0.3)) {
            panelOpen = open
            dragOffset = 0
        } completion: {
            if !panelOpen { panelMounted = false }
        }
    }

    private func closeDrag(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                setPanel(open: value.predictedEndTranslation.width > -panelWidth / 3)
            }
    }
}
