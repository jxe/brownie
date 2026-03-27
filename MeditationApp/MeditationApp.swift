import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable {
    case meditations
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .meditations: return "Meditations"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .meditations: return "list.bullet"
        case .settings: return "gear"
        }
    }
}

@main
struct MeditationApp: App {
    @StateObject private var player = MeditationPlayer()

    init() {
        SampleMeditations.installIfNeeded()
        FileManager.default.migrateToiCloud()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
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
            case .settings:
                SettingsView()
            }
        }
    }
}
