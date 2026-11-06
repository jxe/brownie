import SwiftUI

enum TabDestination: Int {
    case now
    case always
}

extension EnvironmentValues {
    /// Whether the Always tab, which holds Feelings, is the selected tab.
    @Entry var alwaysTabIsSelected = false
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

struct ContentView: View {
    @Environment(MeditationPlayer.self) var player
    @AppStorage("selectedTab") private var selectedTab: TabDestination = .now
    @State private var feelingsTabCenterX: CGFloat?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Now", systemImage: "sun.max", value: .now) {
                NavigationStack {
                    MeditationListView(shelf: .now)
                }
            }
            Tab("Always", systemImage: "infinity", value: .always) {
                NavigationStack {
                    MeditationListView(shelf: .always)
                }
            }
        }
        // The Feelings bubble's tail points at the Always tab, where Feelings lives.
        .background(
            TabBarCenterXReader(tabIndex: 1) { centerX in
                if centerX != feelingsTabCenterX {
                    feelingsTabCenterX = centerX
                }
            }
        )
        .environment(\.feelingsTabCenterX, feelingsTabCenterX)
        .environment(\.alwaysTabIsSelected, selectedTab == .always)
        // med.nxhx.org/m/<id> universal links and brownie://m/<id> open the store item.
        .onOpenURL { url in
            guard let id = MeditationStore.recordName(from: url) else { return }
            selectedTab = .always
            MeditationStore.shared.openedLinkID = id
        }
    }
}
