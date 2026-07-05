import SwiftUI
import UIKit

struct MedTextEditor: UIViewRepresentable {
    @Binding var text: String

    private static let symbolGroups: [[(label: String, char: String, accessibilityLabel: String)]] = [
        [
            ("~", "~", "Pool reference"),
            ("#", "#", "Title, tag, or comment marker"),
        ],
        [
            ("×", "\u{00D7}", "Repeat marker"),
            ("\u{1D110}", "\u{1D110}", "Fermata rest marker"),
        ],
        [
            ("·", "·", "One second pause"),
            ("″", "\u{2033}", "Seconds marker"),
            ("′", "\u{2032}", "Minutes marker"),
            ("⏳", "\u{23F3}", "Countdown timer"),
        ],
        [
            ("🔔", "\u{1F514}", "Bell"),
            ("🛎", "\u{1F6CE}", "Chime"),
            ("🛢", "\u{1F6E2}", "Gong"),
        ],
        [
            ("♀", "\u{2640}", "Female gender marker"),
            ("♂", "\u{2642}", "Male gender marker"),
            ("🪨", "\u{1FAA8}", "Pool item weight marker"),
        ],
    ]

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = medMonoFont
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.text = text
        textView.typingAttributes = medBaseAttributes
        textView.inputAccessoryView = makeToolbar(textView: textView)
        applyMedHighlights(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
            applyMedHighlights(to: textView)
        }
    }

    private func makeToolbar(textView: UITextView) -> UIView {
        let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        bar.backgroundColor = .systemBackground.withAlphaComponent(0.55)
        bar.clipsToBounds = true

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceHorizontal = true
        scroll.contentInsetAdjustmentBehavior = .never
        bar.contentView.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        for (groupIndex, group) in Self.symbolGroups.enumerated() {
            if groupIndex > 0 {
                stack.addArrangedSubview(AccessoryGap(width: 12))
            }
            for symbol in group {
                let btn = SymbolButton(label: symbol.label, accessibilityLabel: symbol.accessibilityLabel) { [weak textView] in
                    guard let tv = textView else { return }
                    tv.insertText(symbol.char)
                }
                stack.addArrangedSubview(btn)
            }
        }

        let trailingSeparator = UIView()
        trailingSeparator.translatesAutoresizingMaskIntoConstraints = false
        trailingSeparator.backgroundColor = .clear
        bar.contentView.addSubview(trailingSeparator)

        let done = AccessoryIconButton(systemName: "keyboard.chevron.compact.down")
        done.accessibilityLabel = "Dismiss keyboard"
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addAction(UIAction { [weak textView] _ in
            textView?.resignFirstResponder()
        }, for: .touchUpInside)
        bar.contentView.addSubview(done)

        let topRule = UIView()
        topRule.translatesAutoresizingMaskIntoConstraints = false
        topRule.backgroundColor = .separator.withAlphaComponent(0.35)
        bar.contentView.addSubview(topRule)

        NSLayoutConstraint.activate([
            topRule.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor),
            topRule.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor),
            topRule.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            topRule.heightAnchor.constraint(equalToConstant: 0.5),

            scroll.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingSeparator.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),

            trailingSeparator.trailingAnchor.constraint(equalTo: done.leadingAnchor),
            trailingSeparator.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: 8),
            trailingSeparator.heightAnchor.constraint(equalToConstant: 1),

            done.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -4),
            done.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
            done.widthAnchor.constraint(equalToConstant: 48),
            done.heightAnchor.constraint(equalToConstant: 42),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])

        bar.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
        return bar
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            applyMedHighlights(to: textView)
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
    init(label: String, accessibilityLabel: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        setTitle(label, for: .normal)
        setTitleColor(.label, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 19, weight: .semibold)
        backgroundColor = .clear
        layer.cornerRadius = 8
        self.accessibilityLabel = accessibilityLabel
        translatesAutoresizingMaskIntoConstraints = false
        addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 38),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .tertiarySystemFill : .clear
            transform = isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private class AccessoryIconButton: UIButton {
    init(systemName: String) {
        super.init(frame: .zero)
        let image = UIImage(systemName: systemName)
        setImage(image, for: .normal)
        tintColor = .label
        backgroundColor = .clear
        layer.cornerRadius = 8
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .tertiarySystemFill : .clear
            transform = isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private class AccessoryGap: UIView {
    init(width: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Syntax highlighting
//
// Patterns ported from the VSCode TextMate grammar at
// tools/vscode-med/syntaxes/med.tmLanguage.json — keep the two in sync if the
// .med language evolves.

private let medMonoFont: UIFont = UIFont(name: "Menlo", size: 14)
    ?? .monospacedSystemFont(ofSize: 14, weight: .regular)

private let medParagraphStyle: NSParagraphStyle = {
    let p = NSMutableParagraphStyle()
    p.headIndent = 24        // wrapped continuations indent by 24pt
    p.firstLineHeadIndent = 0
    p.paragraphSpacing = 6
    return p
}()

private let medBaseAttributes: [NSAttributedString.Key: Any] = [
    .font: medMonoFont,
    .foregroundColor: UIColor.label,
    .paragraphStyle: medParagraphStyle,
]

private struct MedSyntaxRule {
    let regex: NSRegularExpression
    /// group index → color. 0 = whole match.
    let groupColors: [Int: UIColor]
}

private let medSyntaxRules: [MedSyntaxRule] = {
    func rx(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
    let secondary = UIColor.secondaryLabel
    let pool = UIColor.systemPurple
    let count = UIColor.systemBlue
    let pause = UIColor.systemOrange
    let gender = UIColor.systemPink
    let weight = UIColor.systemBrown
    return [
        MedSyntaxRule(regex: rx(#"\A\s*(#)[ \t]*(.*?)(?:[ \t]+((?:#\S+[ \t]*)+))?[ \t]*$"#),
                      groupColors: [0: secondary]),
        MedSyntaxRule(regex: rx(#"^[ \t]*#[ \t]*(#\S+(?:[ \t]+#\S+)*)[ \t]*$|^[ \t]*(#\S+(?:[ \t]+#\S+)*)[ \t]*$"#),
                      groupColors: [0: secondary]),
        MedSyntaxRule(regex: rx(#"^\s*#.*$"#),
                      groupColors: [0: secondary]),
        MedSyntaxRule(regex: rx(#"^[ \t]*(~)[ \t]*([A-Za-z0-9_]+)[ \t]*$"#),
                      groupColors: [1: pool, 2: pool]),
        MedSyntaxRule(regex: rx(#"(?:^|(?<=\s))(?:×|x)\d+"#),
                      groupColors: [0: count]),
        MedSyntaxRule(regex: rx(#"(𝄐|\|)"#),
                      groupColors: [0: count]),
        MedSyntaxRule(regex: rx(#"(⏳)[ \t]*(\d+(?:\.\d+)?)?([″"′'])?"#),
                      groupColors: [1: pause, 2: count, 3: count]),
        MedSyntaxRule(regex: rx(#"\b(\d+(?:\.\d+)?)([″"])"#),
                      groupColors: [1: count, 2: count]),
        MedSyntaxRule(regex: rx(#"\b(\d+(?:\.\d+)?)([′'])"#),
                      groupColors: [1: count, 2: count]),
        MedSyntaxRule(regex: rx(#"·+"#),
                      groupColors: [0: pause]),
        MedSyntaxRule(regex: rx(#"(~)([A-Za-z_][A-Za-z0-9_]*)"#),
                      groupColors: [1: pool, 2: pool]),
        MedSyntaxRule(regex: rx(#"[♀♂]"#),
                      groupColors: [0: gender]),
        MedSyntaxRule(regex: rx(#"🪨"#),
                      groupColors: [0: weight]),
    ]
}()

private func applyMedHighlights(to textView: UITextView) {
    let storage = textView.textStorage
    let full = NSRange(location: 0, length: storage.length)
    guard full.length > 0 else {
        textView.typingAttributes = medBaseAttributes
        return
    }
    let savedSelection = textView.selectedRange
    let text = textView.text ?? ""
    storage.beginEditing()
    storage.setAttributes(medBaseAttributes, range: full)
    for rule in medSyntaxRules {
        rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match = match else { return }
            for (group, color) in rule.groupColors {
                guard group < match.numberOfRanges else { continue }
                let r = match.range(at: group)
                guard r.location != NSNotFound, r.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }
    }
    storage.endEditing()
    textView.selectedRange = savedSelection
    textView.typingAttributes = medBaseAttributes
}
