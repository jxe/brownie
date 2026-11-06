import SwiftUI

/// Pushed from the meditation list. Play, pause and stop try out the script as it
/// stands, saved or not; any edit stops playback, so the next play starts from the top.
struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MeditationPlayer.self) private var player
    @State private var pendingFix: MeditationFix? = nil
    /// The script as opened, to tell whether Cancel would throw changes away.
    @State private var openedContent: String?
    @State private var confirmingDiscard = false

    private var hasChanges: Bool {
        isNew || (openedContent.map { $0 != content } ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isNew {
                TextField("filename", text: $filename)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            // Long lines are hard to follow on iPad, so cap the measure and center it.
            MedTextEditor(text: $content)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)

            let diagnostics = MeditationParser.diagnose(content)
            if !diagnostics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(diagnostics.prefix(3)) { diagnostic in
                        // A diagnostic with a known rewrite can be tapped to apply it.
                        Button {
                            pendingFix = diagnostic.fix
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Label {
                                    Text("Line \(diagnostic.line): \(diagnostic.message)")
                                } icon: {
                                    if diagnostic.isDeprecation {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .foregroundStyle(Color.primary)
                                if diagnostic.fix != nil {
                                    Spacer(minLength: 8)
                                    Text("Fix")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if diagnostics.count > 3 {
                        Text("and \(diagnostics.count - 3) more")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .confirmationDialog(
            pendingFix?.title ?? "",
            isPresented: Binding(
                get: { pendingFix != nil },
                set: { if !$0 { pendingFix = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingFix
        ) { fix in
            Button("Fix") { apply(fix) }
            Button("Cancel", role: .cancel) {}
        } message: { fix in
            if !fix.replacement.isEmpty {
                Text(fix.replacement.trimmingCharacters(in: .whitespaces))
            }
        }
        .navigationTitle(isNew ? "New Meditation" : "Edit")
        .navigationBarTitleDisplayMode(.inline)
        // Cancel and Save stand in for Back, so leaving is always a choice about the edits.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges { confirmingDiscard = true } else { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(filename, content)
                    dismiss()
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                playbackControls
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onAppear {
            if openedContent == nil { openedContent = content }
        }
        // Any edit stops playback; the next play starts again from the top.
        .onChange(of: content) { stopIfPlaying() }
        .onChange(of: filename) { stopIfPlaying() }
        // What's playing may be unsaved, so it ends with the editor.
        .onDisappear { stopIfPlaying() }
    }

    @ViewBuilder
    private var playbackControls: some View {
        Button {
            switch player.state {
            case .playing: player.pause()
            case .paused: player.resume()
            default: player.play(MeditationParser.parse(content))
            }
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
        }
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .disabled(player.isPreparing)

        Button {
            player.stop()
        } label: {
            Image(systemName: "stop.fill")
        }
        .accessibilityLabel("Stop")
        .disabled(!isActive)

        Spacer()

        if isActive {
            Text(Duration.seconds(player.elapsedSeconds).formatted(.time(pattern: .minuteSecond)))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var isActive: Bool {
        switch player.state {
        case .playing, .paused, .preparing: true
        case .idle, .finished: false
        }
    }

    private func stopIfPlaying() {
        if player.state != .idle { player.stop() }
    }

    private func apply(_ fix: MeditationFix) {
        let ns = content as NSString
        // The script may have changed since the dialog opened; skip a fix that no longer fits.
        guard NSMaxRange(fix.range) <= ns.length else { return }
        content = ns.replacingCharacters(in: fix.range, with: fix.replacement)
    }
}
