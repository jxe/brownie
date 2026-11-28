import SwiftUI

/// A meditation's options outside its text: Evergreen, and its file's name. Also its title,
/// when given one (from the title line in a text editor). Tags are gone: old scripts may still
/// have `#tags` in their header, which are kept as they are and mean nothing.
struct MeditationOptionsView: View {
    let title: String
    let onSave: (_ name: String?, _ evergreen: Bool?) -> Void
    /// Closes the sheet when it's hosted from UIKit; otherwise the environment's dismiss does.
    var onClose: (() -> Void)?
    /// The file's name, and what renames it (after the sheet closes). Nil hides the File section.
    var fileName: String?
    var onRename: (() -> Void)?

    @State private var name: String?
    /// Nil hides the Evergreen toggle.
    @State private var evergreen: Bool?
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String? = nil, evergreen: Bool? = nil,
         fileName: String? = nil, onRename: (() -> Void)? = nil,
         onSave: @escaping (_ name: String?, _ evergreen: Bool?) -> Void, onClose: (() -> Void)? = nil) {
        self.title = title
        self.fileName = fileName
        self.onRename = onRename
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: initialName)
        _evergreen = State(initialValue: evergreen)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let current = name {
                    Section("Title") {
                        TextField("Title", text: Binding(get: { current }, set: { name = $0 }))
                    }
                }

                if let current = evergreen {
                    Section {
                        Toggle(isOn: Binding(get: { current }, set: { evergreen = $0 })) {
                            Label("Evergreen", systemImage: "leaf")
                        }
                    } footer: {
                        Text("Shown in every era, not just the one it was made in. It lives in the Evergreen folder.")
                    }
                }

                if let fileName, let onRename {
                    Section("File") {
                        Button {
                            onSave(name, evergreen)
                            close()
                            onRename()
                        } label: {
                            LabeledContent {
                                Text(fileName).lineLimit(1).truncationMode(.middle)
                            } label: {
                                Label("Rename File…", systemImage: "doc")
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, evergreen)
                        close()
                    }
                }
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}
