import SwiftUI

struct MeditationEditorView: View {
    @Binding var content: String
    @Binding var filename: String
    let isNew: Bool
    let onSave: () -> Void
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
                        if isNew && filename.isEmpty {
                            let dateFormatter = DateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd"
                            filename = dateFormatter.string(from: Date())
                        }
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
