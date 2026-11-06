import SwiftUI

enum TabDestination: Int {
    case current
    case always
}

extension EnvironmentValues {
    /// Whether the tab a view sits in is the selected one.
    @Entry var tabIsSelected = false
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
    @AppStorage("selectedTab") private var selectedTab: TabDestination = .always
    @State private var feelingsTabCenterX: CGFloat?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Always", systemImage: "infinity", value: .always) {
                NavigationStack {
                    MeditationListView(shelf: .always)
                }
                .environment(\.tabIsSelected, selectedTab == .always)
            }
            Tab("Current", systemImage: "sun.max", value: .current) {
                NavigationStack {
                    MeditationListView(shelf: .current)
                }
                .environment(\.tabIsSelected, selectedTab == .current)
            }
        }
        // Both tabs open Feelings, so the bubble's tail points at whichever tab you're in.
        .background(
            TabBarCenterXReader(tabIndex: selectedTab == .always ? 0 : 1) { centerX in
                if centerX != feelingsTabCenterX {
                    feelingsTabCenterX = centerX
                }
            }
        )
        .environment(\.feelingsTabCenterX, feelingsTabCenterX)
        // med.nxhx.org/m/<id> universal links and brownie://m/<id> open the store item.
        .onOpenURL { url in
            guard let id = MeditationStore.recordName(from: url) else { return }
            selectedTab = .always
            MeditationStore.shared.openedLinkID = id
        }
    }
}
