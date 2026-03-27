import SwiftUI

struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    let isNew: Bool
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

                MedTextEditor(text: $content)
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
