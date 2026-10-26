import SwiftUI

struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    @Binding var isNew: Bool
    let onSave: (_ filename: String, _ content: String) -> Void
    @Environment(\.dismiss) private var dismiss

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
}
