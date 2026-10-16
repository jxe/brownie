import SwiftUI

/// Toggles which eras a meditation belongs to, and whether it's timeless.
struct EraEditorView: View {
    let title: String
    let eras: [Era]
    let onSave: (Set<String>) -> Void

    @State private var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(title: String, eras: [Era], initialSelection: Set<String>, onSave: @escaping (Set<String>) -> Void) {
        self.title = title
        self.eras = eras
        self.onSave = onSave
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    toggle(EraIndex.timelessTag, label: "Timeless")
                } footer: {
                    Text("Timeless meditations are always shown, whatever era you're in.")
                }
                if !eras.isEmpty {
                    Section("Eras") {
                        ForEach(eras, id: \.tag) { era in
                            toggle(era.tag, label: era.tag, detail: "since \(era.started)")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(selection)
                        dismiss()
                    }
                }
            }
        }
    }

    private func toggle(_ tag: String, label: String, detail: String? = nil) -> some View {
        Toggle(isOn: Binding(
            get: { selection.contains(tag) },
            set: { isOn in
                if isOn { selection.insert(tag) } else { selection.remove(tag) }
            }
        )) {
            HStack {
                Text(label)
                if let detail {
                    Spacer()
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Names a new era. It starts empty; meditations from the previous era are brought along
/// one at a time from the list, where they can be played and read first.
struct NewEraView: View {
    let existingTags: Set<String>
    let onSave: (String) -> Void

    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    /// Era names are tags, so no spaces or leading `#`.
    private var tag: String {
        var value = name.trimmingCharacters(in: .whitespaces)
        while value.hasPrefix("#") { value.removeFirst() }
        return value.components(separatedBy: .whitespaces).joined(separator: "-")
    }

    private var isValid: Bool {
        !tag.isEmpty && tag != EraIndex.timelessTag && !existingTags.contains(tag)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Emoji or name", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    if existingTags.contains(tag) {
                        Text("That era already exists.")
                    } else if !existingTags.isEmpty {
                        Text("The new era starts empty. The previous era's meditations wait below it, so you can listen and bring along the ones that still fit.")
                    }
                }
            }
            .navigationTitle("New Era")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onSave(tag)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
