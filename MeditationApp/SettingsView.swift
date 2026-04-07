import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var player: MeditationPlayer
    @State private var isRefreshing = false
    @State private var metadataQuery: NSMetadataQuery?
    @State private var showAllVoices = false

    private var autoBinding: Binding<Bool> {
        Binding(
            get: { player.isAutoVoice },
            set: { newValue in
                if newValue {
                    player.selectedVoiceID = MeditationPlayer.autoVoiceID
                } else {
                    player.selectedVoiceID = MeditationPlayer.bestAutoVoice()?.identifier
                        ?? MeditationPlayer.availableVoices.first?.identifier
                        ?? player.selectedVoiceID
                    showAllVoices = true
                }
            }
        )
    }

    private var autoResolvedID: String? {
        MeditationPlayer.bestAutoVoice()?.identifier
    }

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
                HStack {
                    Text("Current")
                    Spacer()
                    Text(player.resolvedVoiceDisplayName)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Toggle("Choose automatically", isOn: autoBinding)

                if !MeditationPlayer.hasGoodVoice {
                    VoiceQualityWarningView()
                }

                DisclosureGroup("Browse all voices", isExpanded: $showAllVoices) {
                    ForEach(groupedVoices, id: \.0) { section, voices in
                        Section(section) {
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
                                        if player.isAutoVoice && voice.identifier == autoResolvedID {
                                            Text("Auto pick")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if !player.isAutoVoice && voice.identifier == player.selectedVoiceID {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
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
                    HStack {
                        Label("Refresh from iCloud", systemImage: "arrow.clockwise.icloud")
                        if isRefreshing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRefreshing)
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
        guard !isRefreshing else { return }

        // If iCloud is not available, just reload local files
        guard FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.joeedelman.meditations") != nil else {
            NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
            return
        }

        isRefreshing = true

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K LIKE '*.med'", NSMetadataItemFSNameKey)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        // When query finishes gathering, download any non-current files
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering,
            object: query,
            queue: .main
        ) { [weak query] _ in
            guard let query else { return }
            query.disableUpdates()

            for item in query.results {
                guard let mdItem = item as? NSMetadataItem,
                      let url = mdItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
                let status = mdItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                }
            }

            query.stop()

            // Brief delay so downloads can begin before we reload the file list
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
                isRefreshing = false
            }
        }

        // Timeout after 10s in case the query never finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak query] in
            guard let query, query.isGathering else { return }
            query.stop()
            NotificationCenter.default.post(name: .meditationsDidChange, object: nil)
            isRefreshing = false
        }

        metadataQuery = query
        query.start()
    }
}

private struct VoiceQualityWarningView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("No high-quality voices installed")
                    .font(.subheadline.weight(.semibold))
            }
            Text("Meditations will sound robotic until you install a Premium or Enhanced voice.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Open iOS **Settings → Accessibility → Spoken Content → Voices → English**, then tap a voice marked *Enhanced* or *Premium* to download it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

extension Notification.Name {
    static let meditationsDidChange = Notification.Name("meditationsDidChange")
}
