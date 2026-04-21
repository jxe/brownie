import SwiftUI

enum TabDestination: Int {
    case feelings
    case meditations
    case journal
}

@main
struct MeditationApp: App {
    @State private var player = MeditationPlayer()
    @State private var emotionStore = EmotionStore()
    private let icloudWatcher = iCloudMeditationWatcher()

    init() {
        SampleMeditations.installIfNeeded()
        FileManager.default.migrateToiCloud()
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
    @AppStorage("selectedTab") private var selectedTab: TabDestination = .feelings
    @State private var feelingsTabCenterX: CGFloat?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Feelings", systemImage: "heart.text.square", value: .feelings) {
                CheckInView()
            }
            Tab("Meditations", systemImage: "list.bullet", value: .meditations) {
                NavigationStack {
                    MeditationListView()
                }
            }
            Tab("Journal", systemImage: "book.closed", value: .journal) {
                JournalView()
            }
        }
        .background(
            TabBarCenterXReader(tabIndex: 0) { centerX in
                if centerX != feelingsTabCenterX {
                    feelingsTabCenterX = centerX
                }
            }
        )
        .environment(\.feelingsTabCenterX, feelingsTabCenterX)
    }
}

