import SwiftUI

struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pendingFix: MeditationFix? = nil

    var body: some View {
        NavigationStack {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(filename, content)
                        dismiss()
                    }
                }
            }
        }
    }

    private func apply(_ fix: MeditationFix) {
        let ns = content as NSString
        // The script may have changed since the dialog opened; skip a fix that no longer fits.
        guard NSMaxRange(fix.range) <= ns.length else { return }
        content = ns.replacingCharacters(in: fix.range, with: fix.replacement)
    }
}
