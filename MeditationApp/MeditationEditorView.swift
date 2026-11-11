import SwiftUI

/// Pushed from the meditation list. Play, pause and stop in the title bar try out the
/// script as it stands, and keep playing after you go back. Any edit stops playback, so the
/// next play starts from the top. Edits save themselves a moment after you stop typing,
/// and again on leaving the page or the app.
struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    /// The file being edited, so the list shows its row as playing; nil for a new one.
    let sourceURL: URL?
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(MeditationPlayer.self) private var player
    @State private var pendingFix: MeditationFix? = nil
    /// The script and filename as last written to disk (or as opened).
    @State private var saved: (content: String, filename: String)?
    /// Set when the page opens, so a new meditation's filename field doesn't vanish
    /// mid-typing once the first autosave has written the file.
    @State private var showsFilename = false
    /// The name this page's file has on disk: the opened file's, or what autosave last wrote.
    /// A rename removes it; a name that belongs to some other meditation is never written over.
    @State private var diskName: String?

    private var hasChanges: Bool {
        guard let saved else { return false }
        return saved.content != content || saved.filename != filename
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsFilename {
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                playbackControls
            }
        }
        .onAppear {
            if saved == nil {
                saved = (content, filename)
                showsFilename = isNew
                if !isNew { diskName = filename.trimmingCharacters(in: .whitespaces) }
            }
        }
        // Autosave once typing pauses. Changing either restarts the wait.
        .task(id: "\(filename)\u{0}\(content)") {
            guard hasChanges else { return }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveIfNeeded()
        }
        .onDisappear { saveIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveIfNeeded() }
        }
        // Any edit stops playback; the next play starts again from the top.
        .onChange(of: content) { stopIfPlaying() }
        .onChange(of: filename) { stopIfPlaying() }
    }

    @ViewBuilder
    private var playbackControls: some View {
        Button {
            switch player.state {
            case .playing: player.pause()
            case .paused: player.resume()
            default: player.play(MeditationParser.parse(content), sourceURL: sourceURL)
            }
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
        }
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
        .disabled(player.isPreparing)

        if isActive {
            Button {
                player.stop()
            } label: {
                Image(systemName: "stop.fill")
            }
            .accessibilityLabel("Stop")
        }
    }

    private var isActive: Bool {
        switch player.state {
        case .playing, .paused, .preparing: true
        case .idle, .finished: false
        }
    }

    private func saveIfNeeded() {
        guard hasChanges else { return }
        let name = filename.trimmingCharacters(in: .whitespaces)
        // A new meditation needs a name first; wait until it has one.
        guard !name.isEmpty else { return }
        // Autosave runs mid-typing, so the name may match another meditation (two new ones on
        // the same day both start as the date). Never write over it: use the next free name.
        let target = freeName(for: name)
        onSave(target, content)
        // Renamed: the file was written under its new name, so remove the old one.
        if let diskName, diskName != target {
            let old = FileManager.default.meditationsDirectory.appendingPathComponent("\(diskName).med")
            FileManager.default.deleteMeditation(at: old)
        }
        diskName = target
        saved = (content, filename)
        isNew = false
    }

    /// `name`, or `name 2`, `name 3`… when another meditation already has it.
    private func freeName(for name: String) -> String {
        let dir = FileManager.default.meditationsDirectory
        func taken(_ candidate: String) -> Bool {
            candidate != diskName
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(candidate).med").path)
        }
        var candidate = name
        var n = 2
        while taken(candidate) {
            candidate = "\(name) \(n)"
            n += 1
        }
        return candidate
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
