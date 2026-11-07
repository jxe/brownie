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
            if !panelOpen && dragOffset == 0 { panelMounted = false }
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
