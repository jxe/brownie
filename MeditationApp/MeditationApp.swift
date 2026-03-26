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
    @State private var showFullPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MeditationListView()
                .padding(.bottom, player.totalSteps > 0 ? 60 : 0)

            if player.totalSteps > 0 {
                MiniPlayerBar(showFullPlayer: $showFullPlayer)
                    .ignoresSafeArea(.container, edges: .bottom)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: player.totalSteps > 0)
        .sheet(isPresented: $showFullPlayer) {
            PlayerView()
                .environmentObject(player)
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject var player: MeditationPlayer
    @Binding var showFullPlayer: Bool

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(player.stepIndex), total: max(Double(player.totalSteps), 1))
                .tint(.white.opacity(0.7))

            HStack(spacing: 12) {
                Text(player.currentText.isEmpty ? "..." : player.currentText)
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.up")
                    .font(.caption)
                    .opacity(0.6)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline)
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.bottom, safeAreaBottom)
        .foregroundStyle(.white)
        .background(Color.accentColor)
        .contentShape(Rectangle())
        .onTapGesture { showFullPlayer = true }
    }
}
