import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case meditations
    case feelings
    case journal
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meditations: return "Meditations"
        case .feelings: return "Feelings"
        case .journal: return "Journal"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .meditations: return "list.bullet"
        case .feelings: return "heart.text.square"
        case .journal: return "book.closed"
        case .settings: return "gear"
        }
    }
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
    @State private var selectedDestination: SidebarDestination? = .meditations

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $selectedDestination) { item in
                Label(item.label, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Brownie")
        } detail: {
            switch selectedDestination {
            case .meditations, .none:
                MeditationListView()
            case .feelings:
                CheckInView()
            case .journal:
                JournalView()
            case .settings:
                SettingsView()
            }
        }
    }
}
