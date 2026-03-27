import SwiftUI

struct ReflectionView: View {
    let emotion: Emotion
    @Environment(EmotionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var answer = ""
    @FocusState private var isTextEditorFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Emotion header
                HStack(spacing: 10) {
                    Text(emotion.emoji)
                        .font(.largeTitle)
                    Text(emotion.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Question card
                Text(emotion.question)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )

                // Text editor
                TextEditor(text: $answer)
                    .focused($isTextEditorFocused)
                    .frame(minHeight: 200)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )

                // Save button
                Button {
                    store.submit(emotion: emotion, answer: answer)
                    dismiss()
                } label: {
                    Text("Save Reflection")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Reflect")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isTextEditorFocused = true
        }
    }
}
