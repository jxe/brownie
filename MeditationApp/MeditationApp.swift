import SwiftUI

enum TabDestination: Int {
    case feelings
    case meditations
    case journal
}

@main
struct MeditationApp: App {
    @StateObject private var player = MeditationPlayer()
    @State private var emotionStore = EmotionStore()

    init() {
        SampleMeditations.installIfNeeded()
        FileManager.default.migrateToiCloud()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environment(emotionStore)
        }
    }
}

// Environment key to pass the Feelings tab icon center X to CheckInView
private struct FeelingsTabCenterXKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var feelingsTabCenterX: CGFloat? {
        get { self[FeelingsTabCenterXKey.self] }
        set { self[FeelingsTabCenterXKey.self] = newValue }
    }
}

struct ContentView: View {
    @EnvironmentObject var player: MeditationPlayer
    @State private var selectedTab: TabDestination = .feelings
    @State private var feelingsTabCenterX: CGFloat?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Feelings", systemImage: "heart.text.square", value: .feelings) {
                NavigationStack {
                    CheckInView()
                }
            }
            Tab("Meditations", systemImage: "list.bullet", value: .meditations) {
                NavigationStack {
                    MeditationListView()
                }
            }
            Tab("Journal", systemImage: "book.closed", value: .journal) {
                NavigationStack {
                    JournalView()
                }
            }
        }
        .background(
            TabBarCenterXReader(tabIndex: 0) { centerX in
                feelingsTabCenterX = centerX
            }
        )
        .environment(\.feelingsTabCenterX, feelingsTabCenterX)
    }
}

/// Finds the center X of a specific tab bar button by walking the UIKit view hierarchy.
private struct TabBarCenterXReader: UIViewRepresentable {
    let tabIndex: Int
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            // Walk up to the root and dump the hierarchy to find tab bar buttons
            var root: UIView = uiView
            while let parent = root.superview { root = parent }
            Self.findTabButtons(in: root, tabIndex: tabIndex, onChange: onChange)
        }
    }

    private static func findTabButtons(in root: UIView, tabIndex: Int, onChange: (CGFloat) -> Void) {
        // Collect all views whose class name contains "TabBarButton" (works across UITabBar and new-style tab bars)
        var buttons: [UIView] = []
        collectTabBarButtons(in: root, result: &buttons)
        let sorted = buttons.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
        guard tabIndex < sorted.count else { return }
        let frame = sorted[tabIndex].convert(sorted[tabIndex].bounds, to: nil)
        onChange(frame.midX)
    }

    private static func collectTabBarButtons(in view: UIView, result: inout [UIView]) {
        let typeName = String(describing: type(of: view))
        if typeName.contains("TabBarButton") || typeName.contains("TabButton") {
            result.append(view)
            return // don't recurse into tab bar buttons
        }
        for subview in view.subviews {
            collectTabBarButtons(in: subview, result: &result)
        }
    }
}

private extension UIView {
    func findSuperview<T: UIView>(ofType type: T.Type) -> T? {
        var current = superview
        while let view = current {
            if let match = view as? T { return match }
            current = view.superview
        }
        return nil
    }
}
