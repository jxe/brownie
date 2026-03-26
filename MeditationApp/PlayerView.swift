import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var player: MeditationPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            // Drag indicator
            Capsule()
                .fill(.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Spacer()

            if !player.currentText.isEmpty {
                Text(player.currentText)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.3), value: player.currentText)
            } else if player.isPlaying {
                Text("...")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(player.stepIndex), total: max(Double(player.totalSteps), 1))
                .padding(.horizontal, 40)

            HStack(spacing: 40) {
                Button {
                    player.stop()
                    dismiss()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title)
                }

                Button {
                    player.togglePause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                }
            }

            Spacer()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
