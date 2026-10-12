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

/// Names a new era and picks which meditations come along into it.
struct NewEraView: View {
    let candidates: [URL]
    let titles: [URL: String]
    let existingTags: Set<String>
    let onSave: (String, Set<URL>) -> Void

    @State private var name = ""
    @State private var members: Set<URL>
    @Environment(\.dismiss) private var dismiss

    init(
        candidates: [URL],
        titles: [URL: String],
        existingTags: Set<String>,
        preselected: Set<URL>,
        onSave: @escaping (String, Set<URL>) -> Void
    ) {
        self.candidates = candidates
        self.titles = titles
        self.existingTags = existingTags
        self.onSave = onSave
        _members = State(initialValue: preselected)
    }

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
                    }
                }
                Section {
                    ForEach(candidates, id: \.self) { url in
                        Button {
                            if members.contains(url) { members.remove(url) } else { members.insert(url) }
                        } label: {
                            HStack {
                                Text(titles[url] ?? url.deletingPathExtension().lastPathComponent)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: members.contains(url) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(members.contains(url) ? Color.accentColor : Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Bring along (\(members.count))")
                } footer: {
                    Text("They stay in their earlier eras too.")
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
                        onSave(tag, members)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
