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
    /// The main screen's row whose stand-in is flying into the now-playing bar. The row
    /// shows itself empty while it's away, and takes its playing look once it lands.
    @Entry var rowInFlight: URL? = nil
    /// Closes the left panel and opens one of its pages on the main screen.
    @Entry var openFromPanel: (PanelPage) -> Void = { _ in }
    /// Closes the left panel, leaving the main screen as it is, then runs `then` once it's shut.
    @Entry var closePanel: (_ then: @escaping () -> Void) -> Void = { then in then() }
    /// Opens the playing meditation's editor on the main screen (a tap on the now-playing bar).
    @Entry var openNowPlaying: () -> Void = {}
}

/// The main screen's request to open a meditation's editor, from outside the list that
/// holds the editor (the now-playing bar). The home list takes it and clears it.
@Observable final class EditorRequest {
    static let shared = EditorRequest()
    var url: URL?
}

/// A page the left panel opens. It opens on the main screen, not inside the panel.
enum PanelPage: Hashable {
    case settings
    case leaderboard
    case era(EraSelection)
    case checkIn(UUID)
    case todo(UUID)
    case reflection(UUID)
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
        case .todo(let id):
            if let todo = store.todos.first(where: { $0.id == id }) {
                DoneTodoDetailView(todo: todo)
            } else {
                ContentUnavailableView("To-do Not Found", systemImage: "clock")
            }
        case .reflection(let id):
            if let entry = store.journalEntries.first(where: { $0.id == id }),
               case .reflection(let reflection) = entry.content {
                ReflectionDetailView(entry: entry, reflection: reflection)
            } else {
                ContentUnavailableView("Reflection Not Found", systemImage: "clock")
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
    /// How far a drag has moved the main screen, while one is under way. Kept in its own
    /// object and read only by `PanelSlide`, so a drag re-renders just the slide, not this body
    /// (whose fresh environment closures would re-render both screens every frame).
    @State private var drag = PanelDrag()
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
    /// The bar is sinking away after a stop; it's removed once it's down.
    @State private var nowPlayingBarSinking = false
    /// The bar's frame on screen (above the home indicator), for where a flying row lands.
    @State private var nowPlayingBarFrame: CGRect = .zero
    /// The home indicator's inset, for guessing where the bar goes before it has ever shown.
    @State private var bottomSafeInset: CGFloat = 34
    /// A row flying into the bar, and how far along it is (0 at the row, 1 at the bar).
    @State private var rowFlight: RowFlight?
    @State private var rowFlightProgress: CGFloat = 0

    /// The bar's own height (above the home indicator), which the pages get as bottom safe area.
    private var nowPlayingBarHeight: CGFloat {
        nowPlayingBarFrame.isEmpty ? 56 : nowPlayingBarFrame.height
    }

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
            ZStack(alignment: .leading) {
                if panelMounted {
                    NavigationStack {
                        JournalView()
                            // A leftward swipe anywhere on the panel, rows included, closes it,
                            // following the finger like the drag on the main screen does.
                            .background(
                                PanelClosePan(isEnabled: panelOpen) { translation in
                                    drag.offset = min(0, translation)
                                } onEnded: { translation, velocity in
                                    setPanel(open: translation + velocity * 0.2 > -panelWidth / 3)
                                }
                                .frame(width: 0, height: 0)
                            )
                    }
                    .environment(\.openFromPanel, { page in
                        mainPath = [page]
                        setPanel(open: false)
                    })
                    .environment(\.closePanel, { then in setPanel(open: false, then: then) })
                    .frame(width: panelWidth)
                }

                // One now-playing bar for every page, over the bottom of the whole stack rather
                // than inside each page. The stack keeps its full size: its pages just get
                // the bar's height as extra bottom safe area, so their backgrounds run on
                // under the bar and nothing behind it can show through as it comes and goes.
                ZStack(alignment: .bottom) {
                    NavigationStack(path: $mainPath) {
                        MeditationListView(shelf: .home)
                            .navigationDestination(for: PanelPage.self) { PanelPageView(page: $0) }
                            // A swipe in from the left edge pulls the panel out, but only on the
                            // main screen itself: anywhere deeper, that swipe goes back.
                            .background(
                                PanelEdgePan(isEnabled: !panelOpen) { translation in
                                    if !panelMounted { panelMounted = true }
                                    drag.offset = max(0, translation)
                                } onEnded: { translation, velocity in
                                    setPanel(open: translation + velocity * 0.2 > panelWidth / 3)
                                }
                                .frame(width: 0, height: 0)
                            )
                    }
                    .environment(\.setHomePagePushed, { homePagePushed = $0 })
                    // The pages keep the bar's space until it has sunk away, then take it
                    // back at once.
                    .safeAreaPadding(.bottom, nowPlayingBarShown ? nowPlayingBarHeight : 0)
                    if nowPlayingBarShown {
                        // A flying row stands in for the bar: the real one comes in only as it
                        // lands, unseen under it (no slide of its own), and its contents fade in
                        // as the stand-in fades out. Switching to another meditation while the
                        // bar is up flies nothing: the bar's contents just roll over.
                        NowPlayingBar(contentHidden: rowFlight != nil)
                            // A stop sinks it down and fades it, explicitly, before it goes: a
                            // removal transition here didn't run.
                            .offset(y: nowPlayingBarSinking ? nowPlayingBarHeight + bottomSafeInset : 0)
                            .opacity(nowPlayingBarSinking ? 0 : 1)
                            // Measured outside the sink's offset (and not while sinking), so a
                            // flight lands where the bar sits, not where it sank to.
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                if !nowPlayingBarSinking { nowPlayingBarFrame = frame }
                            }
                            .transition(rowFlight == nil
                                ? AnyTransition.asymmetric(insertion: .move(edge: .bottom), removal: .identity)
                                : .identity)
                            .zIndex(1)
                    }
                }
                .environment(\.rowInFlight, rowFlight?.url)
                .environment(\.openNowPlaying, { openNowPlaying() })
                .onChange(of: geo.safeAreaInsets.bottom, initial: true) { _, inset in bottomSafeInset = inset }
                .onChange(of: wantsNowPlayingBar, initial: true) { _, wants in
                    // Started again while it was sinking: bring it back up.
                    if wants && nowPlayingBarSinking {
                        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { nowPlayingBarSinking = false }
                        return
                    }
                    guard wants != nowPlayingBarShown else { return }
                    if !wants {
                        withAnimation(.easeIn(duration: 0.25)) {
                            nowPlayingBarSinking = true
                        } completion: {
                            guard nowPlayingBarSinking else { return }
                            if !wantsNowPlayingBar { nowPlayingBarShown = false }
                            nowPlayingBarSinking = false
                        }
                        return
                    }
                    // From the main screen, the row that started flies down into the bar,
                    // background and all. A stop just slides the bar away.
                    // The bar itself comes in when the stand-in lands, so no empty strip opens
                    // at the bottom while it's on its way.
                    if wants, homeIsInFront, let url = player.currentSourceURL,
                       let row = visibleRowFrame(url, in: geo) {
                        flyRow(url, title: player.currentTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : player.currentTitle,
                               from: row)
                        return
                    }
                    withAnimation(.spring(duration: 0.3, bounce: 0.15)) { nowPlayingBarShown = wants }
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
                .modifier(PanelSlide(drag: drag, panelOpen: panelOpen, panelWidth: panelWidth, canvas: palette.canvas))
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

    /// Opens the playing meditation's editor: closes the panel, pops any page the panel opened,
    /// and asks the home list (which holds the editor) to push it.
    private func openNowPlaying() {
        guard let url = player.currentSourceURL else { return }
        if panelOpen { setPanel(open: false) }
        if mainPath.isEmpty {
            EditorRequest.shared.url = url
        } else {
            // The panel's page pops first; pushing the editor while that pop runs garbles both.
            mainPath = []
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { EditorRequest.shared.url = url }
        }
    }

    /// The row's fill, if it's on screen now.
    private func visibleRowFrame(_ url: URL, in geo: GeometryProxy) -> CGRect? {
        guard !UIAccessibility.isReduceMotionEnabled,
              let frame = HomeRowFrames.shared.frames[url],
              frame.intersects(geo.frame(in: .global)) else { return nil }
        return frame
    }

    private func flyRow(_ url: URL, title: String, from: CGRect) {
        // Drop and catch: the hop and fall are one thrown arc under constant gravity, so its
        // time follows from the drop: up at v0 to the hop's height, then down to the bar.
        let barTop = nowPlayingBarFrame.isEmpty ? from.maxY + 400 : nowPlayingBarFrame.minY
        let drop = Double(max(0, barTop + (nowPlayingBarFrame.isEmpty ? 28 : nowPlayingBarFrame.height / 2) - from.midY))
        let gravity = 5000.0, hop = Double(RowFlightView.hopHeight)
        let v0 = (2 * gravity * hop).squareRoot()
        let fall = min(0.7, max(0.25, (v0 + (v0 * v0 + 2 * gravity * drop).squareRoot()) / gravity))
        let duration = fall + RowFlightView.catchDuration
        let flight = RowFlight(url: url, title: title, from: from, fallShare: CGFloat(fall / duration))
        rowFlight = flight
        rowFlightProgress = 0
        // The next turn, so the stand-in is drawn over the row before it moves. Linear: the
        // view shapes its own timing (gravity, then the catch's settle) from the progress.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration)) {
                rowFlightProgress = 1
            } completion: {
                guard rowFlight?.id == flight.id else { return }
                // The real bar slips in under the stand-in, with no animation, so the pages
                // make room for it while it's covered...
                if !nowPlayingBarShown && wantsNowPlayingBar {
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) { nowPlayingBarShown = true }
                }
                // ...then the stand-in, which by now looks exactly like it, goes at once: no
                // crossfade, which only dimmed the two copies as they passed. The row takes its
                // playing look with its own fade.
                DispatchQueue.main.async {
                    guard rowFlight?.id == flight.id else { return }
                    // Not withAnimation, and not disabling animations either: the row's own
                    // fade still has to run.
                    rowFlight = nil
                }
            }
        }
    }

    /// Where a flight lands: the bar's frame, run down under the home indicator. The bar isn't
    /// up yet, so this is where it last was (it always sits in the same place), or a guess
    /// the first time.
    private func rowFlightTarget(screen: CGRect) -> CGRect {
        let bar = nowPlayingBarFrame.isEmpty
            ? CGRect(x: screen.minX, y: screen.maxY - bottomSafeInset - 56, width: screen.width, height: 56)
            : nowPlayingBarFrame
        return CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: screen.maxY - bar.minY)
    }

    /// The stand-in for a row on its way into the bar, its background and all, drawn over everything.
    @ViewBuilder
    private var rowFlightLayer: some View {
        GeometryReader { layer in
            if let flight = rowFlight {
                let screen = layer.frame(in: .global)
                RowFlightView(
                    progress: rowFlightProgress,
                    fallShare: flight.fallShare,
                    title: flight.title,
                    from: flight.from.offsetBy(dx: -screen.minX, dy: -screen.minY),
                    to: rowFlightTarget(screen: screen).offsetBy(dx: -screen.minX, dy: -screen.minY),
                    barHeight: nowPlayingBarFrame.isEmpty ? 56 : nowPlayingBarFrame.height,
                    palette: palette
                )
                .transition(.identity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func setPanel(open: Bool, then: (() -> Void)? = nil) {
        if open { panelMounted = true }
        withAnimation(.snappy(duration: 0.3)) {
            panelOpen = open
            drag.offset = 0
        } completion: {
            if !panelOpen && drag.offset == 0 { panelMounted = false }
            then?()
        }
    }

    private func closeDrag(panelWidth: CGFloat) -> some Gesture {
        // The overlay moves with the drag, so measure finger travel in a stationary space.
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                drag.offset = min(0, value.translation.width)
            }
            .onEnded { value in
                setPanel(open: value.predictedEndTranslation.width > -panelWidth / 3)
            }
    }
}

/// A meditation row flying into the now-playing bar.
private struct RowFlight {
    let id = UUID()
    let url: URL
    let title: String
    /// The row's fill, in global coordinates.
    let from: CGRect
    /// How much of the flight is the fall; the rest is the catch.
    let fallShare: CGFloat
}

/// A row card dropped into the now-playing bar and caught there. It stays the same card the
/// whole way, with its title on it, so you can follow it. `progress` runs linearly from 0 to
/// 1; the view turns it into two phases:
/// - the fall (`fallShare` of the flight): a small hop up off the row, then down under
///   gravity, speeding up, stretching a little with speed, lifted on a shadow;
/// - the catch: as it reaches the bar's place it spreads at once into the bar's width,
///   square corners and highlight, the bar's own live contents (`NowPlayingBarContent`)
///   coming up on it as the row's title goes, and it dips under the impact and settles
///   back, as if the bar had caught its weight.
private struct RowFlightView: View, Animatable {
    static let catchDuration: Double = 0.38
    static let hopHeight: CGFloat = 30

    var progress: CGFloat
    let fallShare: CGFloat
    let title: String
    let from: CGRect
    let to: CGRect
    let barHeight: CGFloat
    let palette: AppPalette

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private static func clamp(_ t: CGFloat) -> CGFloat { min(max(t, 0), 1) }
    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let t = clamp(t)
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        let p = progress
        // 0...1 through each phase.
        let fallT = Self.clamp(p / max(fallShare, 0.01))
        let catchT = Self.clamp((p - fallShare) / max(1 - fallShare, 0.01))

        // Where the card is caught: its middle on the bar's content line.
        let caughtY = to.minY + barHeight / 2
        // The hop and fall: one parabola, as if tossed up off the row and left to gravity,
        // so it slows into the top of the hop and speeds up smoothly all the way down.
        // y = start + a·t² − b·t, through the bar at t = 1, topping out hopHeight above the
        // start (b²/4a = hopHeight).
        let drop = max(0, caughtY - from.midY)
        let rootA = Self.hopHeight.squareRoot() + (Self.hopHeight + drop).squareRoot()
        let a = rootA * rootA
        let b = 2 * (a * Self.hopHeight).squareRoot()
        let fallY = from.midY + a * fallT * fallT - b * fallT
        // How high above the row it is, 0...1 of the hop, and how fast it's going, 0...1.
        let height = Self.clamp((from.midY - fallY) / Self.hopHeight)
        let speed = Self.clamp(abs(2 * a * fallT - b) / max(2 * a - b, 1))

        // The catch: it spreads fast at the moment of impact and eases into place.
        let spread = 1 - pow(1 - catchT, 3)
        // The dip: pushed down by the impact, then a small spring back up and settle.
        let dip = 9 * sin(.pi * 2 * 0.9 * catchT) * pow(1 - catchT, 2.2)

        let width = Self.lerp(from.width, to.width, spread)
        let cardHeight = Self.lerp(from.height, to.height, spread)
        let centerY = catchT > 0
            ? Self.lerp(caughtY, to.midY, spread) + dip
            : fallY
        let center = CGPoint(x: Self.lerp(from.midX, to.midX, spread), y: centerY)
        let corner = Self.lerp(14, 0, spread)

        // Stretched a little by its speed on the way down, back to round as it's caught.
        let speedStretch = 0.05 * (fallT > b / (2 * a) ? speed : 0) * (1 - spread)
        // Lifted toward you as it rises (a little bigger, with a softer shadow), and still
        // floating on a light shadow as it falls, until the bar takes it.
        let lift = (1 - spread) * (0.45 + 0.55 * height)
        let liftScale = 1 + 0.04 * height * (1 - spread)

        // The row's title rides on the card and heads for the bar's title line as the bar's
        // own contents come up in its place.
        let titleX = Self.lerp(14, 20 + 12 + 10, spread)
        let titleCenterY = Self.lerp(from.height / 2, (barHeight - 40) / 2 + 11, spread)
        let barContent = Self.smoothstep(spread / 0.7)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(palette.card.mix(with: palette.highlight, by: Double(spread)))
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous).fill(palette.canvas)
                )
                .shadow(color: .black.opacity(0.16 * lift), radius: 5 + 9 * lift, y: 2 + 7 * lift)
            Text(title)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(Color.primary)
                .frame(width: max(0, width - titleX - 110), height: 22, alignment: .leading)
                .offset(x: titleX, y: titleCenterY - 11)
                .opacity(1 - barContent)
            NowPlayingBarContent()
                .frame(width: width, height: barHeight)
                .opacity(barContent)
        }
        .frame(width: width, height: cardHeight, alignment: .topLeading)
        .scaleEffect(x: (1 - speedStretch * 0.5) * liftScale, y: (1 + speedStretch) * liftScale)
        .position(center)
    }
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

/// A drag's offset of the main screen, apart from `ContentView`'s own state.
@Observable final class PanelDrag {
    var offset: CGFloat = 0
}

/// Slides the main screen right by the panel's width (while open) plus any drag. Only this
/// reads the drag, so following a finger re-renders nothing else.
private struct PanelSlide: ViewModifier {
    let drag: PanelDrag
    let panelOpen: Bool
    let panelWidth: CGFloat
    let canvas: Color

    func body(content: Content) -> some View {
        let offset = max(0, min(panelWidth, (panelOpen ? panelWidth : 0) + drag.offset))
        content
            // The shadow comes from a plain shape behind the screen: a shadow on the
            // whole NavigationStack would re-render offscreen on every change.
            .background {
                if offset > 0 {
                    Rectangle()
                        .fill(canvas)
                        .shadow(color: .black.opacity(0.18), radius: 12)
                        .ignoresSafeArea()
                }
            }
            .offset(x: offset)
    }
}

/// A leftward pan on the panel's navigation controller that closes the panel. It only begins
/// for mostly-horizontal leftward motion, so the list still scrolls vertically; once it
/// begins it cancels the list's own scrolling and the row's tap.
struct PanelClosePan: UIViewRepresentable {
    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIView(context: Context) -> PanelClosePanView {
        let view = PanelClosePanView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PanelClosePanView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
    }

    final class PanelClosePanView: UIView {
        var isEnabled = true
        private lazy var panDelegate = PanDelegate(view: self)
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat, CGFloat) -> Void = { _, _ in }
        private var recognizer: UIPanGestureRecognizer?
        /// The list held still while the pan runs.
        private weak var heldScrollView: UIScrollView?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, recognizer == nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard recognizer == nil, let nav = owningNavigationController() else { return }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.delegate = panDelegate
            nav.view.addGestureRecognizer(pan)
            recognizer = pan
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

        fileprivate func shouldBegin(_ pan: UIPanGestureRecognizer) -> Bool {
            guard isEnabled else { return false }
            let v = pan.velocity(in: pan.view)
            return v.x < 0 && abs(v.x) > abs(v.y)
        }

        private final class PanDelegate: NSObject, UIGestureRecognizerDelegate {
            weak var view: PanelClosePanView?

            init(view: PanelClosePanView) { self.view = view }

            func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
                guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
                return view?.shouldBegin(pan) ?? false
            }

            /// Alongside the list's scrolling, which it then stops (see `handle`).
            func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                   shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
                true
            }
        }

        @objc private func handle(_ pan: UIPanGestureRecognizer) {
            // In the window's space, which nothing moves.
            let space = pan.view?.window
            let translation = pan.translation(in: space).x
            switch pan.state {
            case .began:
                // Hold the list under the finger still until the pan ends.
                var view = pan.view?.hitTest(pan.location(in: pan.view), with: nil)
                while let current = view {
                    if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                        scroll.isScrollEnabled = false
                        heldScrollView = scroll
                        break
                    }
                    view = current.superview
                }
                onChanged(translation)
            case .changed:
                onChanged(translation)
            case .ended:
                releaseScrollView()
                onEnded(translation, pan.velocity(in: space).x)
            case .cancelled, .failed:
                releaseScrollView()
                onEnded(0, 0)
            default:
                break
            }
        }

        private func releaseScrollView() {
            heldScrollView?.isScrollEnabled = true
            heldScrollView = nil
        }
    }
}
