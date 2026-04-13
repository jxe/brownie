import SwiftUI
import UIKit

struct MedTextEditor: UIViewRepresentable {
    @Binding var text: String

    private static let symbols: [(String, String)] = [
        ("·", "·"),
        ("″", "\u{2033}"),
        ("′", "\u{2032}"),
        ("×", "\u{00D7}"),
        ("\u{1D110}", "\u{1D110}"),  // 𝄐 fermata (rest between stanzas)
        ("⏳", "\u{23F3}"),
        ("🔔", "\u{1F514}"),
        ("♀", "\u{2640}"),
        ("♂", "\u{2642}"),
        ("~", "~"),
        ("#", "#"),
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = context.coordinator
        textView.text = text
        textView.inputAccessoryView = makeToolbar(textView: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }

    private func makeToolbar(textView: UITextView) -> UIView {
        let bar = UIView()
        bar.backgroundColor = .secondarySystemBackground

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        for (label, char) in Self.symbols {
            let btn = SymbolButton(symbol: char, label: label) { [weak textView] in
                guard let tv = textView else { return }
                tv.insertText(char)
            }
            stack.addArrangedSubview(btn)
        }

        // Add a "Done" button at the end
        let done = UIButton(type: .system)
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        done.addAction(UIAction { [weak textView] _ in
            textView?.resignFirstResponder()
        }, for: .touchUpInside)
        stack.addArrangedSubview(done)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        bar.frame = CGRect(x: 0, y: 0, width: 0, height: 44)
        return bar
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n" else { return true }

            let content = textView.text as NSString
            let lineRange = content.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = content.substring(with: lineRange)

            // Measure leading whitespace
            let stripped = currentLine.drop(while: { $0 == " " || $0 == "\t" })
            let indent = String(currentLine.prefix(currentLine.count - stripped.count))

            // Pool definition (~name or ~ name) and × / x repeats should increase indent
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let newIndent: String
            let isPoolDef: Bool = {
                guard trimmed.hasPrefix("~") else { return false }
                let after = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                return !after.isEmpty && after.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            }()
            let isRepeat: Bool = {
                guard let first = trimmed.first else { return false }
                if first == "\u{00D7}" || first == "x" {
                    return trimmed.count > 1 && trimmed.dropFirst().first?.isNumber == true
                }
                return false
            }()
            if isPoolDef || isRepeat {
                newIndent = indent + "  "
            } else {
                newIndent = indent
            }

            // Insert newline + indent
            textView.replace(textView.selectedTextRange!, withText: "\n" + newIndent)
            return false
        }
    }
}

private class SymbolButton: UIButton {
    init(symbol: String, label: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.title = label
        config.baseForegroundColor = .label
        config.baseBackgroundColor = .tertiarySystemBackground
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 18)
            return out
        }
        self.configuration = config
        addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }
}
