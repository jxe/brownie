import SwiftUI

/// Edits a meditation's tags, and its title too when given one.
struct TagEditorView: View {
    let title: String
    let suggestions: [String]
    let onSave: (_ name: String?, _ tags: [String]) -> Void
    /// Closes the editor when it's hosted from UIKit; otherwise the environment's dismiss does.
    var onClose: (() -> Void)?

    @State private var name: String?
    @State private var tags: [String]
    @State private var newTag: String = ""
    @Environment(\.dismiss) private var dismiss

    init(title: String, initialName: String? = nil, initialTags: [String], suggestions: [String],
         onSave: @escaping (_ name: String?, _ tags: [String]) -> Void, onClose: (() -> Void)? = nil) {
        self.title = title
        self.suggestions = suggestions
        self.onSave = onSave
        self.onClose = onClose
        _name = State(initialValue: initialName)
        _tags = State(initialValue: initialTags)
    }

    private var availableSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let current = name {
                    Section("Title") {
                        TextField("Title", text: Binding(get: { current }, set: { name = $0 }))
                    }
                }

                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        TagChipFlow(tags: tags) { tag in
                            removeTag(tag)
                        }
                    }
                }

                Section("Add tag") {
                    HStack {
                        TextField("New tag", text: $newTag)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { commitNewTag() }
                        Button("Add") { commitNewTag() }
                            .disabled(normalizedNewTag.isEmpty)
                    }
                }

                if !availableSuggestions.isEmpty {
                    Section("Suggestions") {
                        TagSuggestionFlow(tags: availableSuggestions) { tag in
                            addTag(tag)
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
                        commitNewTag()
                        onSave(name, tags)
                        close()
                    }
                }
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var normalizedNewTag: String {
        var value = newTag.trimmingCharacters(in: .whitespaces)
        while value.hasPrefix("#") { value.removeFirst() }
        return value.lowercased()
    }

    private func commitNewTag() {
        let value = normalizedNewTag
        guard !value.isEmpty else { return }
        addTag(value)
        newTag = ""
    }

    private func addTag(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

private struct TagChipFlow: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlexibleHStack {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(.subheadline)
                    Button {
                        onRemove(tag)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.18))
                .clipShape(Capsule())
            }
        }
    }
}

private struct TagSuggestionFlow: View {
    let tags: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlexibleHStack {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2)
                        Text(tag)
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlexibleHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = layoutRows(subviews: subviews, maxWidth: width)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let totalWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layoutRows(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, width: CGFloat)]
        var width: CGFloat
        var height: CGFloat
    }

    private func layoutRows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row(items: [], width: 0, height: 0)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let projected = current.width + (current.items.isEmpty ? 0 : spacing) + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row(items: [], width: 0, height: 0)
            }
            if !current.items.isEmpty { current.width += spacing }
            current.items.append((index, size.width))
            current.width += size.width
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
