import SwiftUI

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

    var body: some View {
        MeditationListView()
    }
}
