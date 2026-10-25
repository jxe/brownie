import SwiftUI

/// Experimental replacement for `ReflectionView`: instead of a free-text answer,
/// feel the feeling through and turn it into a small to-do.
struct FeelingTodoView: View {
    let emotion: Emotion
    @Environment(EmotionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var todo: FeelingTodo?

    private var isAccruing: Bool {
        store.accruingEmotionID == emotion.id
    }

    var body: some View {
        ScrollView {
            if let todo = Binding($todo) {
                form(todo)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color("BackgroundColor"))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("To-do")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if store.isSelected(emotion) {
                        Button(role: .destructive) {
                            store.deselect(emotion)
                            dismiss()
                        } label: {
                            Label("Remove Feeling", systemImage: "xmark.circle")
                        }
                    }
                    if let todo, store.todos.contains(where: { $0.id == todo.id }) {
                        Button(role: .destructive) {
                            store.deleteTodo(todo)
                            self.todo = nil
                            dismiss()
                        } label: {
                            Label("Delete To-do", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if todo == nil {
                todo = store.openTodo(for: emotion) ?? FeelingTodo(emotion: emotion)
            }
        }
        .onChange(of: todo) { _, newValue in
            if let newValue { store.saveTodo(newValue) }
        }
    }

    @ViewBuilder
    private func form(_ todo: Binding<FeelingTodo>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Emotion header
            HStack(spacing: 10) {
                Text(emotion.emoji)
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(emotion.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    HStack(spacing: 6) {
                        TodoStateMark(state: todo.wrappedValue.state)
                            .frame(width: 12, height: 12)
                        Text(todo.wrappedValue.state.label)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                LiveTimeText(isLive: isAccruing) { store.timeContribution(for: emotion, asOf: $0) }
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isAccruing ? .primary : .secondary)
            }

            // Question card
            Text(emotion.question)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color("HighlightColor"))
                )

            feelSection(todo)

            field(todo.wrappedValue.concernPrompt, text: todo.concern)
            field("The long-term value or change", text: todo.value)
            actionField(todo)
        }
        .padding()
    }

    private func feelSection(_ todo: Binding<FeelingTodo>) -> some View {
        HStack(spacing: 10) {
            Button {
                store.tap(emotion)
            } label: {
                Label("Keep Feeling", systemImage: "heart")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(todo.wrappedValue.feltThroughAt != nil)

            Button {
                if todo.wrappedValue.feltThroughAt == nil {
                    if isAccruing { store.stopAccruing() }
                    todo.wrappedValue.feltThroughAt = Date()
                } else {
                    todo.wrappedValue.feltThroughAt = nil
                }
            } label: {
                Label(
                    "Felt Through",
                    systemImage: todo.wrappedValue.feltThroughAt == nil ? "circle" : "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(todo.wrappedValue.feltThroughAt == nil ? nil : .accentColor)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            TextField("", text: text, axis: .vertical)
                .lineLimit(1...6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("HighlightColor"))
                )
        }
    }

    private func actionField(_ todo: Binding<FeelingTodo>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The one thing you can do now")
                .font(.subheadline)
                .fontWeight(.medium)
            Picker("Action", selection: todo.actionVerb) {
                ForEach(FeelingTodo.ActionVerb.allCases) { verb in
                    Text(verb.label).tag(verb)
                }
            }
            .pickerStyle(.segmented)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    todo.wrappedValue.doneAt = todo.wrappedValue.doneAt == nil ? Date() : nil
                } label: {
                    Image(systemName: todo.wrappedValue.doneAt == nil ? "circle" : "checkmark.circle.fill")
                        .font(.title3)
                }
                .disabled(todo.wrappedValue.actionObject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(todo.wrappedValue.doneAt == nil ? "Mark done" : "Mark not done")

                Text(todo.wrappedValue.actionVerb.label)
                    .foregroundStyle(.secondary)
                TextField("…", text: todo.actionObject, axis: .vertical)
                    .lineLimit(1...4)
                    .strikethrough(todo.wrappedValue.doneAt != nil)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("HighlightColor"))
            )
        }
    }
}

/// A small mark for a to-do's state: empty, half, full, or checked.
struct TodoStateMark: View {
    let state: FeelingTodo.State

    var body: some View {
        GeometryReader { geo in
            let lineWidth = max(1, geo.size.width * 0.14)
            ZStack {
                switch state {
                case .incomplete:
                    Circle().strokeBorder(Color.accentColor, lineWidth: lineWidth)
                case .notFeltThrough:
                    Circle().strokeBorder(Color.accentColor, lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0.25, to: 0.75)
                        .fill(Color.accentColor)
                        .rotationEffect(.degrees(180))
                case .feltThrough:
                    Circle().fill(Color.accentColor)
                case .done:
                    Circle().fill(Color.accentColor)
                    Image(systemName: "checkmark")
                        .font(.system(size: geo.size.width * 0.6, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
