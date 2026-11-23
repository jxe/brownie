import SwiftUI

enum AppPalette: String, CaseIterable {
    case eucalyptus = "Eucalyptus & Sage"
    case indigo = "Indigo & Lavender"
    case marigold = "Marigold & Sand"

    static let defaultPalette: AppPalette = .marigold
    static let preferenceKey = "appPalette"

    private func adaptiveColor(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }

    var tint: Color {
        switch self {
        case .eucalyptus: adaptiveColor(light: 0x356456, dark: 0xA3D5BF)
        case .indigo: adaptiveColor(light: 0x4B5E8F, dark: 0xB9C8F2)
        case .marigold: adaptiveColor(light: 0xB77909, dark: 0xF2C773)
        }
    }

    var canvas: Color { Color(uiColor: .systemBackground).mix(with: highlight, by: 0.12) }
    var panel: Color { canvas.mix(with: highlight, by: 0.25) }
    var card: Color { canvas.mix(with: highlight, by: 0.48) }

    var highlight: Color {
        switch self {
        case .eucalyptus: adaptiveColor(light: 0xE1ECE4, dark: 0x223C33)
        case .indigo: adaptiveColor(light: 0xE8E6F4, dark: 0x30364D)
        case .marigold: adaptiveColor(light: 0xFAE9D2, dark: 0x493822)
        }
    }
}

extension EnvironmentValues {
    @Entry var appPalette: AppPalette = .defaultPalette
    /// Opens the left panel (History and Settings) from anywhere on the main screen.
    @Entry var openPanel: () -> Void = {}
    /// Whether the left panel is open, so the main screen can refresh what Settings may have changed.
    @Entry var panelIsOpen = false
    /// The main screen says whether one of its own pages (Feelings, To-dos, the editor) is
    /// pushed over it, so the now-playing bar knows the main screen isn't on top.
    @Entry var setHomePagePushed: (Bool) -> Void = { _ in }
    /// Closes the left panel and opens one of its pages on the main screen.
    @Entry var openFromPanel: (PanelPage) -> Void = { _ in }
}

/// A page the left panel opens. It opens on the main screen, not inside the panel.
enum PanelPage: Hashable {
    case settings
    case leaderboard
    case era(EraSelection)
    case checkIn(UUID)
}

private struct PanelPageView: View {
    @Environment(EmotionStore.self) private var store
    let page: PanelPage

    var body: some View {
        switch page {
        case .settings:
            SettingsView()
        case .leaderboard:
            EmotionLeaderboardView()
        case .era(let era):
            MeditationListView(shelf: .past(era))
        case .checkIn(let id):
            if let entry = store.journalEntries.first(where: { $0.id == id }),
               case .checkInSession(let session) = entry.content {
                CheckInSessionDetailView(entry: entry, session: session)
            } else {
                ContentUnavailableView("Check-in Not Found", systemImage: "clock")
            }
        }
    }
}

@main
struct BrownieApp: App {
    @AppStorage(AppPalette.preferenceKey) private var palette = AppPalette.defaultPalette
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
                .environment(\.appPalette, palette)
                .accentColor(palette.tint)
                .tint(palette.tint)
                .environment(player)
                .environment(emotionStore)
        }
    }
}

/// One main screen, with History and Settings in a panel that slides out from the left.
struct ContentView: View {
    @Environment(\.appPalette) private var palette
    @Environment(MeditationPlayer.self) var player
    @State private var panelOpen = false
    /// How far a drag has moved the main screen, while one is under way.
    @State private var dragOffset: CGFloat = 0
    /// Whether History is built at all. It stays up through the closing slide, then goes,
    /// so nothing behind the main screen re-renders as the store changes.
    @State private var panelMounted = false
    /// The main screen's pushed pages that came from the panel.
    @State private var mainPath: [PanelPage] = []
    /// Whether the main screen has pushed one of its own pages (see `setHomePagePushed`).
    @State private var homePagePushed = false
    /// Whether the now-playing bar is up. Follows `wantsNowPlayingBar` in an update of its
    /// own, so only the bar and the pages' resizing animate, never a push or pop with them.
    @State private var nowPlayingBarShown = false
    /// The bar's height above the home indicator, for where a flying row lands.
    @State private var nowPlayingBarHeight: CGFloat = 56
    /// A row flying into the bar, and whether it has got there.
    @State private var rowFlight: RowFlight?
    @State private var rowFlightLanded = false
    /// What's playing, with its title, for a row that starts while another plays.
    @State private var lastPlaying: (url: URL, title: String)?

    /// Something is starting, playing or paused, whatever page is on top.
    private var wantsNowPlayingBar: Bool {
        switch player.state {
        case .preparing, .playing, .paused: true
        case .idle, .finished: false
        }
    }

    /// The main screen itself is in front, so its rows are there to fly from.
    private var homeIsInFront: Bool {
        !homePagePushed && mainPath.isEmpty && !panelOpen
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = min(geo.size.width * 0.85, 380)
            let offset = max(0, min(panelWidth, (panelOpen ? panelWidth : 0) + dragOffset))
            ZStack(alignment: .leading) {
                if panelMounted {
                    NavigationStack {
                        JournalView()
                    }
                    .environment(\.openFromPanel, { page in
                        mainPath = [page]
                        setPanel(open: false)
                    })
                    .frame(width: panelWidth)
                }

                // One now-playing bar for every page, under the whole stack rather than
                // inside each page, so when it comes or goes the stack shrinks or grows
                // with it in one animation.
                VStack(spacing: 0) {
                    NavigationStack(path: $mainPath) {
                        MeditationListView(shelf: .home)
                            .navigationDestination(for: PanelPage.self) { PanelPageView(page: $0) }
                            // A swipe in from the left edge pulls the panel out, but only on the
                            // main screen itself: anywhere deeper, that swipe goes back.
                            .background(
                                PanelEdgePan(isEnabled: !panelOpen) { translation in
                                    if !panelMounted { panelMounted = true }
                                    dragOffset = max(0, translation)
                                } onEnded: { translation, velocity in
                                    setPanel(open: translation + velocity * 0.2 > panelWidth / 3)
                                }
                                .frame(width: 0, height: 0)
                            )
                    }
                    .environment(\.setHomePagePushed, { homePagePushed = $0 })
                    if nowPlayingBarShown {
                        NowPlayingBar(contentHidden: rowFlight != nil)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { nowPlayingBarHeight = $0 }
                            .transition(.move(edge: .bottom))
                    }
                }
                .onChange(of: wantsNowPlayingBar, initial: true) { _, wants in
                    guard wants != nowPlayingBarShown else { return }
                    // From the main screen, the row that started flies down into the bar,
                    // background and all. A stop just slides the bar away.
                    if wants, homeIsInFront, let url = player.currentSourceURL,
                       let row = visibleRowFrame(url, in: geo) {
                        flyRow(title: player.currentTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : player.currentTitle,
                               from: row, to: barFrame(in: geo))
                    }
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { nowPlayingBarShown = wants }
                }
                // Another row started while one was playing: it flies into the bar too.
                .onChange(of: player.currentSourceURL) { old, new in
                    if let new {
                        lastPlaying = (new, player.currentTitle.isEmpty ? new.deletingPathExtension().lastPathComponent : player.currentTitle)
                    }
                    guard old != nil, let new, nowPlayingBarShown, homeIsInFront,
                          let row = visibleRowFrame(new, in: geo) else { return }
                    flyRow(title: lastPlaying?.title ?? "", from: row, to: barFrame(in: geo))
                }
                .onChange(of: player.currentTitle) { _, title in
                    if let url = lastPlaying?.url, !title.isEmpty, player.currentSourceURL == url {
                        lastPlaying = (url, title)
                    }
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
                            .fill(palette.canvas)
                            .shadow(color: .black.opacity(0.18), radius: 12)
                            .ignoresSafeArea()
                    }
                }
                .offset(x: offset)
            }
        }
        .overlay { rowFlightLayer }
        // med.nxhx.org/m/<id> universal links and brownie://m/<id> open the store item.
        .onOpenURL { url in
            guard let id = MeditationStore.recordName(from: url) else { return }
            setPanel(open: false)
            MeditationStore.shared.openedLinkID = id
        }
    }

    /// Where the bar sits once it's up: full width along the bottom, down under the home indicator.
    private func barFrame(in geo: GeometryProxy) -> CGRect {
        let screen = geo.frame(in: .global)
        return CGRect(x: screen.minX, y: screen.maxY - nowPlayingBarHeight,
                      width: screen.width, height: nowPlayingBarHeight + geo.safeAreaInsets.bottom)
    }

    /// The row's fill, if it's on screen now.
    private func visibleRowFrame(_ url: URL, in geo: GeometryProxy) -> CGRect? {
        guard !UIAccessibility.isReduceMotionEnabled,
              let frame = HomeRowFrames.shared.frames[url],
              frame.intersects(geo.frame(in: .global)) else { return nil }
        return frame
    }

    private func flyRow(title: String, from: CGRect, to: CGRect) {
        let flight = RowFlight(title: title, from: from, to: to)
        rowFlight = flight
        rowFlightLanded = false
        // The next turn, so the stand-in is drawn where it starts before it moves.
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.5, bounce: 0.12)) {
                rowFlightLanded = true
            } completion: {
                if rowFlight?.id == flight.id { rowFlight = nil }
            }
        }
    }

    /// The stand-in for a row on its way into the bar, its background and all, drawn over everything.
    @ViewBuilder
    private var rowFlightLayer: some View {
        GeometryReader { layer in
            if let flight = rowFlight {
                let origin = layer.frame(in: .global).origin
                let atBar = rowFlightLanded
                let frame = rowFlightLanded ? flight.to : flight.from
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: atBar ? 0 : 14, style: .continuous)
                        .fill(atBar ? palette.highlight : palette.card)
                        .background(
                            RoundedRectangle(cornerRadius: atBar ? 0 : 14, style: .continuous)
                                .fill(palette.canvas)
                        )
                        // Lifted off the list while it travels, settled once it's the bar.
                        .shadow(color: .black.opacity(atBar ? 0 : 0.18), radius: 10, y: 4)
                    HStack(spacing: 10) {
                        PlayingPulseDot(isPulsing: false)
                            .frame(width: 12, height: 12)
                            .opacity(atBar ? 1 : 0)
                        Text(flight.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    // In a row the title starts at its padding with no dot before it; in
                    // the bar the dot comes first and the title rides above the time.
                    .padding(.leading, atBar ? 20 : 14 - 22)
                    .frame(height: atBar ? nowPlayingBarHeight - 16 : frame.height)
                }
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX - origin.x, y: frame.minY - origin.y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func setPanel(open: Bool) {
        if open { panelMounted = true }
        withAnimation(.snappy(duration: 0.3)) {
            panelOpen = open
            dragOffset = 0
        } completion: {
            if !panelOpen && dragOffset == 0 { panelMounted = false }
        }
    }

    private func closeDrag(panelWidth: CGFloat) -> some Gesture {
        // The overlay moves with the drag, so measure finger travel in a stationary space.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                dragOffset = min(0, value.translation.width)
            }
            .onEnded { value in
                setPanel(open: value.predictedEndTranslation.width > -panelWidth / 3)
            }
    }
}

/// A meditation row flying into the now-playing bar.
private struct RowFlight {
    let id = UUID()
    let title: String
    let from: CGRect
    let to: CGRect
}

/// Pulls the panel out with a swipe from the screen's left edge. It hangs a UIKit edge-pan
/// recognizer on the main screen's navigation controller, so it never holds up the list's
/// scrolling, and it only starts while the main screen is the top page and nothing covers it.
struct PanelEdgePan: UIViewRepresentable {
    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIView(context: Context) -> PanelEdgePanView {
        let view = PanelEdgePanView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PanelEdgePanView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }

    final class PanelEdgePanView: UIView {
        var isEnabled = true
        /// A separate object, since UIView already has its own gestureRecognizerShouldBegin(_:).
        private lazy var panDelegate = PanDelegate(view: self)
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        private var recognizer: UIScreenEdgePanGestureRecognizer?
        private weak var navigationController: UINavigationController?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Once added, it stays on the navigation controller even while this view is
            // out of the window behind a pushed page; shouldBegin keeps it quiet then.
            guard window != nil, recognizer == nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard recognizer == nil, let nav = owningNavigationController() else { return }
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.edges = .left
            pan.delegate = panDelegate
            nav.view.addGestureRecognizer(pan)
            recognizer = pan
            navigationController = nav
        }

        private func owningNavigationController() -> UINavigationController? {
            var responder: UIResponder? = self
            while let current = responder {
                if let vc = current as? UIViewController, let nav = vc.navigationController {
                    return nav
                }
                responder = current.next
            }
            return nil
        }

        /// Only on the main screen itself: not behind a pushed page or a sheet.
        fileprivate var shouldBeginPan: Bool {
            guard isEnabled, let nav = navigationController else { return false }
            return nav.viewControllers.count == 1 && nav.presentedViewController == nil
        }

        private final class PanDelegate: NSObject, UIGestureRecognizerDelegate {
            weak var view: PanelEdgePanView?

            init(view: PanelEdgePanView) { self.view = view }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                view?.shouldBeginPan ?? false
            }
        }

        @objc private func handle(_ pan: UIScreenEdgePanGestureRecognizer) {
            let translation = pan.translation(in: pan.view).x
            switch pan.state {
            case .began, .changed:
                onChanged(translation)
            case .ended:
                onEnded(translation, pan.velocity(in: pan.view).x)
            case .cancelled, .failed:
                onEnded(0, 0)
            default:
                break
            }
        }
    }
}
