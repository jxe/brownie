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
                if centerX != feelingsTabCenterX {
                    feelingsTabCenterX = centerX
                }
            }
        )
        .environment(\.feelingsTabCenterX, feelingsTabCenterX)
    }
}

