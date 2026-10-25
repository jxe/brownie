import AVFoundation
import Speech
import SwiftUI

/// Experimental replacement for `ReflectionView`: instead of a free-text answer,
/// feel the feeling through and turn it into a small to-do.
struct FeelingTodoView: View {
    let emotion: Emotion
    @Environment(EmotionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var todo: FeelingTodo?
    @State private var dictation = DictationRecorder()
    @FocusState private var focusedAction: UUID?

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
            // The timer only runs here while "Keep Feeling" is on.
            if isAccruing { store.stopAccruing() }
        }
        .onDisappear {
            dictation.stop()
            if var todo, todo.actions.contains(where: \.isBlank) {
                todo.actions.removeAll(where: \.isBlank)
                store.saveTodo(todo)
            }
        }
        .task(id: isAccruing) {
            // Taps cap credit at `maxEmotionCreditDuration`; keep extending while on.
            while isAccruing && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(EmotionStore.maxEmotionCreditDuration / 2))
                guard isAccruing, !Task.isCancelled else { break }
                store.keepAccruing(emotion)
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

            field(todo.wrappedValue.concernPrompt, id: "concern", text: todo.concern)
            field("The long-term value or change", id: "value", text: todo.value)
            actionField(todo)
            doneButton(todo)
        }
        .padding()
    }

    private func feelSection(_ todo: Binding<FeelingTodo>) -> some View {
        HStack(spacing: 10) {
            Button {
                if isAccruing {
                    store.stopAccruing()
                } else {
                    store.keepAccruing(emotion)
                }
            } label: {
                Label("Keep Feeling", systemImage: isAccruing ? "heart.fill" : "heart")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(isAccruing ? .accentColor : nil)
            .disabled(todo.wrappedValue.feltThroughAt != nil)
            .accessibilityValue(isAccruing ? "On" : "Off")

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

    private func field(_ title: String, id: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(alignment: .top, spacing: 8) {
                TextField("", text: text, axis: .vertical)
                    .lineLimit(1...6)
                micButton(id: id, text: text)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color("HighlightColor"))
            )
        }
    }

    private func micButton(id: String, text: Binding<String>) -> some View {
        let isListening = dictation.activeField == id
        return Button {
            // Dictate without the keyboard in the way.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            focusedAction = nil
            dictation.toggle(id, text: text)
        } label: {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .symbolEffect(.pulse, isActive: isListening)
                .foregroundStyle(isListening ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isListening ? "Stop dictation" : "Dictate")
    }

    private func actionField(_ todo: Binding<FeelingTodo>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What you can do now")
                .font(.subheadline)
                .fontWeight(.medium)
            ForEach(todo.actions) { action in
                actionRow(action)
            }
            HStack(spacing: 8) {
                ForEach(FeelingTodo.ActionVerb.allCases) { verb in
                    Button {
                        let action = FeelingTodo.Action(verb: verb)
                        todo.wrappedValue.actions.append(action)
                        focusedAction = action.id
                    } label: {
                        Label(verb.label, systemImage: "plus")
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func doneButton(_ todo: Binding<FeelingTodo>) -> some View {
        let isDone = todo.wrappedValue.doneAt != nil
        return Button {
            if !isDone, isAccruing { store.stopAccruing() }
            todo.wrappedValue.doneAt = isDone ? nil : Date()
        } label: {
            Label(isDone ? "Done" : "Mark Feeling Done", systemImage: isDone ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isDone && todo.wrappedValue.filledActions.isEmpty)
        .accessibilityHint(isDone ? "Reopens this to-do" : "Marks all its actions done")
    }

    private func actionRow(_ action: Binding<FeelingTodo.Action>) -> some View {
        let isDone = todo?.doneAt != nil
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.wrappedValue.verb.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(action.wrappedValue.verb.prompt, text: action.object, axis: .vertical)
                    .lineLimit(1...4)
                    .strikethrough(isDone)
                    .focused($focusedAction, equals: action.wrappedValue.id)
            }
            micButton(id: action.wrappedValue.id.uuidString, text: action.object)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color("HighlightColor"))
        )
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

/// Live dictation into one text field at a time, appended after what's already there.
@MainActor
@Observable
final class DictationRecorder {
    private(set) var activeField: String?
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggle(_ field: String, text: Binding<String>) {
        if activeField == field {
            stop()
            return
        }
        stop()
        Task { await start(field, text: text) }
    }

    func stop() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if activeField != nil {
            activeField = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func start(_ field: String, text: Binding<String>) async {
        guard await Self.requestPermissions(),
              let recognizer, recognizer.isAvailable else { return }

        let base = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true

            let input = audioEngine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()

            self.request = request
            activeField = field
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.activeField == field else { return }
                    if let result {
                        let spoken = result.bestTranscription.formattedString
                        text.wrappedValue = base.isEmpty ? spoken : "\(base) \(spoken)"
                        if result.isFinal { self.stop() }
                    } else if error != nil {
                        self.stop()
                    }
                }
            }
        } catch {
            print("Dictation error: \(error)")
            activeField = field
            stop()
        }
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
