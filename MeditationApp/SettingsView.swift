import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var player: MeditationPlayer

    var body: some View {
        List {
            Section("Speaking Rate") {
                HStack {
                    Image(systemName: "tortoise")
                        .foregroundStyle(.secondary)
                    Slider(value: $player.speakingRate, in: 0.3...0.6, step: 0.05)
                    Image(systemName: "hare")
                        .foregroundStyle(.secondary)
                }
                Text(rateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                ForEach(groupedVoices, id: \.0) { section, voices in
                    DisclosureGroup(section) {
                        ForEach(voices, id: \.identifier) { voice in
                            Button {
                                player.selectedVoiceID = voice.identifier
                                preview(voice)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voice.name)
                                            .foregroundStyle(.primary)
                                        Text(voice.language)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if voice.identifier == player.selectedVoiceID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    refreshFromiCloud()
                } label: {
                    Label("Refresh from iCloud", systemImage: "arrow.clockwise.icloud")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Voice grouping

    @State private var previewSynthesizer = AVSpeechSynthesizer()

    private var groupedVoices: [(String, [AVSpeechSynthesisVoice])] {
        let voices = MeditationPlayer.availableVoices
        var dict: [String: [AVSpeechSynthesisVoice]] = [:]
        for v in voices {
            let label = qualityLabel(v.quality)
            dict[label, default: []].append(v)
        }
        let order = ["Premium", "Enhanced", "Default"]
        return order.compactMap { key in
            guard let list = dict[key] else { return nil }
            return (key, list)
        }
    }

    private func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Default"
        }
    }

    private func preview(_ voice: AVSpeechSynthesisVoice) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "This is how I sound.")
        utterance.voice = voice
        utterance.rate = player.speakingRate
        previewSynthesizer.speak(utterance)
    }

    private var rateLabel: String {
        let rate = player.speakingRate
        if rate <= 0.35 { return "Very Slow" }
        if rate <= 0.4 { return "Slow" }
        if rate <= 0.47 { return "Normal" }
        if rate <= 0.55 { return "Fast" }
        return "Very Fast"
    }

    // MARK: - iCloud refresh

    private func refreshFromiCloud() {
        // Trigger iCloud download for any evicted files
        let dir = FileManager.default.meditationsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles]) else { return }

        for file in files where file.pathExtension == "med" {
            let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values?.ubiquitousItemDownloadingStatus,
               status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            }
        }

        // Post notification so the list refreshes
        NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
}
