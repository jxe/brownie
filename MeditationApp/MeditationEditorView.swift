import SwiftUI

/// Pushed from the meditation list. Play, pause and stop in the title bar try out the
/// script as it stands, saved or not, and keep playing after you go back. Any edit stops
/// playback, so the next play starts from the top. There's no Save button: Back asks
/// whether to save when anything changed.
struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    /// The file being edited, so the list shows its row as playing; nil for a new one.
    let sourceURL: URL?
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MeditationPlayer.self) private var player
    @State private var pendingFix: MeditationFix? = nil
    /// The script and filename as opened, to tell whether Back should ask to save.
    @State private var opened: (content: String, filename: String)?
    @State private var askingToSave = false

    private var hasChanges: Bool {
        guard let opened else { return false }
        return opened.content != content || opened.filename != filename
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
        .navigationBarTitleDisplayMode(.inline)
        // Our own Back, so it can ask about unsaved changes.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasChanges { askingToSave = true } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel("Back")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                playbackControls
            }
        }
        .confirmationDialog("Save your changes?", isPresented: $askingToSave, titleVisibility: .visible) {
            Button("Save") {
                onSave(filename, content)
                dismiss()
            }
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .onAppear {
            if opened == nil { opened = (content, filename) }
        }
        // Edge swipe: the system's own swipe back while nothing changed; with changes,
        // the same swipe asks first, like Back.
        .background(SwipeBackEnabler(isEnabled: !hasChanges).frame(width: 0, height: 0))
        .overlay(alignment: .leading) {
            if hasChanges {
                Color.clear
                    .frame(width: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onEnded { value in
                                if value.translation.width > 60 { askingToSave = true }
                            }
                    )
            }
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

/// Keeps the system's edge swipe back working although the editor hides the standard Back
/// button (which turns the swipe off), and switches it off while `isEnabled` is false.
private struct SwipeBackEnabler: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context: Context) -> SwipeBackView {
        let view = SwipeBackView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: SwipeBackView, context: Context) {
        view.isSwipeEnabled = isEnabled
        view.apply()
    }
}

private final class SwipeBackView: UIView {
    var isSwipeEnabled = true
    private weak var navigationController: UINavigationController?
    private weak var savedDelegate: UIGestureRecognizerDelegate?
    private var didSaveDelegate = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            navigationController = findNavigationController()
            apply()
        } else {
            restore()
        }
    }

    func apply() {
        guard let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        if !didSaveDelegate {
            savedDelegate = gesture.delegate
            didSaveDelegate = true
        }
        // The navigation controller's own delegate refuses the swipe when Back is hidden.
        gesture.delegate = nil
        gesture.isEnabled = isSwipeEnabled
    }

    /// Hands the swipe back to the navigation controller as it was, so the screens
    /// under the editor behave normally.
    private func restore() {
        guard didSaveDelegate, let gesture = navigationController?.interactivePopGestureRecognizer else { return }
        gesture.delegate = savedDelegate
        gesture.isEnabled = true
        didSaveDelegate = false
    }

    private func findNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController, let nav = controller.navigationController {
                return nav
            }
            responder = current.next
        }
        return nil
    }
}
