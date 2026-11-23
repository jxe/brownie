import SwiftUI
import UIKit

struct MedTextEditor: UIViewRepresentable {
    @Binding var text: String
    /// The meditation before the script (its title and pools), when `text` is only the script.
    /// The whole meditation is `outside + text`, so its pools count and diagnostics line up.
    var outside: String = ""
    /// A tap on a reference to a pool defined outside the script.
    var onOpenPool: ((String) -> Void)? = nil
    /// The ~ menu's New Pool…, or Make Pool… on selected text, named a pool; its `~name` is
    /// already in the script, and the definition goes outside it. The second value is the
    /// selected text, to become one of the pool's items (its first, for a new pool).
    var onNewPool: ((String, String?) -> Void)? = nil
    /// False when the editor sits in a page that scrolls: the text view takes the height of
    /// its text, and the page scrolls to keep the caret in view.
    var scrolls = true

    private static let symbolGroups: [[(label: String, char: String, accessibilityLabel: String)]] = [
        [
            ("~", "~", "Pool reference"),
            ("#", "#", "Title, tag, or comment marker"),
        ],
        [
            ("[", "[", "Start a group to repeat"),
            ("]", "]", "End the group, then its repeat count"),
            ("×", "\u{00D7}", "Repeat count, after what it repeats"),
            ("‖", "\u{2016}", "Break between repeats"),
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
        let textView = MedTextView()
        textView.font = medFont
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.delegate = context.coordinator
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = scrolls
        if !scrolls {
            textView.backgroundColor = .clear
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        textView.text = text
        textView.outsideText = outside
        context.coordinator.onOpenPool = onOpenPool
        context.coordinator.onNewPoolOutside = onNewPool
        textView.typingAttributes = medBaseAttributes
        textView.inputAccessoryView = makeToolbar(textView: textView)
        applyMedHighlights(to: textView)

        // Tapping a time, repeat count or pool edits it directly instead of placing the cursor.
        context.coordinator.textView = textView
        textView.onNewPool = { [weak coordinator = context.coordinator, weak textView] in
            if let coordinator, let textView { coordinator.startNewPool(in: textView) }
        }
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleQuickEditTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)
        context.coordinator.quickEditTap = tap
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onOpenPool = onOpenPool
        context.coordinator.onNewPoolOutside = onNewPool
        let medView = textView as? MedTextView
        let outsideChanged = medView.map { $0.outsideText != outside } ?? false
        if outsideChanged { medView?.outsideText = outside }
        if textView.text != text {
            textView.text = text
            applyMedHighlights(to: textView)
        } else if outsideChanged {
            // A pool added or removed outside changes which references are chips.
            applyMedHighlights(to: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard !scrolls else { return nil }
        let width = proposal.width ?? 320
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // Room to tap into below a short script.
        return CGSize(width: width, height: max(fitted.height, 72))
    }

    /// A button listing the pools (and remembered picks) defined in the script; tapping one inserts `~name`.
    private func makePoolMenuButton(textView: UITextView) -> UIButton {
        let btn = SymbolButton(label: "~…", accessibilityLabel: "Insert a pool reference") {}
        btn.showsMenuAsPrimaryAction = true
        btn.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak textView] completion in
                let names = MeditationParser.referenceableNames(in: (textView as? MedTextView)?.wholeText ?? textView?.text ?? "")
                func insertAction(_ name: String) -> UIAction {
                    UIAction(title: "~\(name)") { _ in textView?.insertText("~\(name)") }
                }
                var sections: [UIMenuElement] = [
                    // Defined right where it's first used: names it, puts the ~name here, and
                    // opens the new pool's sheet for its items.
                    UIMenu(options: .displayInline, children: [
                        UIAction(title: "New Pool…", image: UIImage(systemName: "plus")) { _ in
                            (textView as? MedTextView)?.onNewPool?()
                        }
                    ])
                ]
                if !names.pools.isEmpty {
                    sections.append(UIMenu(title: "Pools", options: .displayInline,
                                           children: names.pools.map(insertAction)))
                }
                if !names.picks.isEmpty {
                    sections.append(UIMenu(title: "Remembered picks", options: .displayInline,
                                           children: names.picks.map(insertAction)))
                }
                completion(sections)
            }
        ])
        return btn
    }

    /// Inserts a toolbar symbol, nudging toward postfix repeats: `×` and `‖` get a space
    /// before them, `]` comes with its `×`, and `[` wraps any selection as `[…] ×`.
    private static func insertSymbol(_ char: String, into textView: UITextView) {
        let content = textView.text as NSString
        let selection = textView.selectedRange
        let previous: Character? = selection.location > 0
            ? Character(content.substring(with: content.rangeOfComposedCharacterSequence(at: selection.location - 1)))
            : nil
        let needsSpace = previous.map { !$0.isWhitespace && $0 != "[" } ?? false

        switch char {
        case "[" where selection.length > 0:
            let selected = content.substring(with: selection)
            textView.insertText("[\(selected)] \u{00D7}")
        case "]":
            textView.insertText("] \u{00D7}")
        case "\u{00D7}" where needsSpace && previous != "]":
            textView.insertText(" \u{00D7}")
        case "\u{2016}" where needsSpace:
            textView.insertText(" \u{2016}")
        default:
            textView.insertText(char)
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
            if groupIndex == 0 {
                stack.addArrangedSubview(makePoolMenuButton(textView: textView))
            }
            for symbol in group {
                let btn = SymbolButton(label: symbol.label, accessibilityLabel: symbol.accessibilityLabel) { [weak textView] in
                    guard let tv = textView else { return }
                    Self.insertSymbol(symbol.char, into: tv)
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

    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate,
                       UIPopoverPresentationControllerDelegate {
        var text: Binding<String>
        weak var textView: UITextView?
        weak var quickEditTap: UITapGestureRecognizer?
        var onOpenPool: ((String) -> Void)?
        var onNewPoolOutside: ((String, String?) -> Void)?
        /// What the tap in progress landed on, found when the tap is about to be recognized.
        private var pendingTarget: MedQuickEditTarget?

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            applyMedHighlights(to: textView)
            if !textView.isScrollEnabled { textView.invalidateIntrinsicContentSize() }
            revealCaret(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Again once the keyboard has come up and the page has made room for it.
            revealCaret(in: textView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak textView] in
                if let self, let textView { self.revealCaret(in: textView) }
            }
        }

        /// When the text view doesn't scroll itself, scrolls the page it's in to show the caret.
        /// After the current layout pass, so a line just added has its height.
        private func revealCaret(in textView: UITextView) {
            guard !textView.isScrollEnabled else { return }
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.isFirstResponder,
                      let end = textView.selectedTextRange?.end else { return }
                var ancestor = textView.superview
                while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
                guard let page = ancestor as? UIScrollView else { return }
                let caret = textView.caretRect(for: end).insetBy(dx: 0, dy: -28)
                page.scrollRectToVisible(textView.convert(caret, to: page), animated: false)
            }
        }

        /// The caret never rests inside a folded pool: it goes to the end of the pool's `~name`
        /// line. Leaving a blank stretch between pools, opened for typing, folds it away again.
        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length == 0 { revealCaret(in: textView) }
            guard let medView = textView as? MedTextView, !medView.isAdjustingSelection,
                  medView.foldedText == textView.text else { return }
            let selection = textView.selectedRange
            if let open = medView.folds.compactMap(\.openedBlanks).first,
               !(open.location...NSMaxRange(open)).contains(selection.location) {
                applyMedHighlights(to: textView)
            }
            guard selection.length == 0,
                  let fold = medView.folds.first(where: { $0.hidesCaret(at: selection.location) }) else { return }
            medView.adjustSelection(to: fold.headerEnd)
        }

        /// Edits that would reach into a folded pool from outside stop at its `~name` line
        /// instead; Return there starts a new line under the whole pool.
        private func handleFoldedEdit(_ textView: UITextView, range: NSRange, text: String) -> Bool? {
            guard let medView = textView as? MedTextView, !medView.isAdjustingSelection,
                  medView.foldedText == textView.text else { return nil }
            for fold in medView.folds {
                let protected = fold.protectedRange(textLength: (textView.text as NSString).length)
                guard protected.length > 0 else { continue }
                if text == "\n" && range.length == 0 && range.location == fold.headerEnd {
                    medView.adjustSelection(to: fold.blockEnd)
                    medView.isAdjustingSelection = true
                    if let caret = textView.selectedTextRange { textView.replace(caret, withText: "\n") }
                    medView.isAdjustingSelection = false
                    textViewDidChange(textView)
                    return false
                }
                let overlap = NSIntersectionRange(range, protected).length > 0
                let coversAll = range.location <= protected.location && NSMaxRange(range) >= NSMaxRange(protected)
                if (overlap && !coversAll) || (range.length == 0 && fold.hidesCaret(at: range.location)) {
                    medView.adjustSelection(to: fold.headerEnd)
                    return false
                }
            }
            return nil
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if let handled = handleFoldedEdit(textView, range: range, text: text) { return handled }
            guard text == "\n" else { return true }

            let content = textView.text as NSString
            let lineRange = content.lineRange(for: NSRange(location: range.location, length: 0))
            let currentLine = content.substring(with: lineRange)

            // Measure leading whitespace
            let stripped = currentLine.drop(while: { $0 == " " || $0 == "\t" })
            let indent = String(currentLine.prefix(currentLine.count - stripped.count))

            // Pool definitions (~name or ~ name in column 1) and lines opening a [ group increase
            // indent. When the pools live outside the script, a ~name line there draws from one.
            let trimmed = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let newIndent: String
            let isPoolDef: Bool = {
                guard onNewPoolOutside == nil, indent.isEmpty, trimmed.hasPrefix("~") else { return false }
                let after = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                return !after.isEmpty && after.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            }()
            let opensGroup = trimmed.hasSuffix("[")
            if isPoolDef || opensGroup {
                newIndent = indent + "  "
            } else {
                newIndent = indent
            }

            // Insert newline + indent
            textView.replace(textView.selectedTextRange!, withText: "\n" + newIndent)
            return false
        }

        // MARK: Quick edits

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === quickEditTap, let textView else { return true }
            pendingTarget = quickEditTarget(at: gestureRecognizer.location(in: textView), in: textView)
            return pendingTarget != nil
        }

        /// The text view's own taps wait for ours, which fails at once unless it landed on a target.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === quickEditTap, let textView,
                  let other = otherGestureRecognizer as? UITapGestureRecognizer,
                  other.numberOfTapsRequired == 1,
                  let view = other.view, view.isDescendant(of: textView) else { return false }
            return true
        }

        @objc func handleQuickEditTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView, let target = pendingTarget else { return }
            pendingTarget = nil
            present(target, from: textView)
        }

        /// Which target, if any, sits under `point`. The tap must be on the token's glyphs, not
        /// just nearest to them, so taps in a line's empty space still place the cursor.
        private func quickEditTarget(at point: CGPoint, in textView: UITextView) -> MedQuickEditTarget? {
            guard let position = textView.closestPosition(to: point) else { return nil }
            let offset = textView.offset(from: textView.beginningOfDocument, to: position)
            let outside = (textView as? MedTextView)?.outsideText ?? ""
            return MedQuickEdit.targets(onLineAt: offset, in: textView.text, outside: outside).first { target in
                MedTextView.chipRects(for: target, in: textView)
                    .contains { chip in
                        // A little beyond the chip, and at least 36pt wide so a lone dot is easy to hit.
                        let dx = max(4, (36 - chip.width) / 2)
                        return chip.insetBy(dx: -dx, dy: -4).contains(point)
                    }
            }
        }

        private func textRange(_ range: NSRange, in textView: UITextView) -> UITextRange? {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length) else { return nil }
            return textView.textRange(from: start, to: end)
        }

        private func rects(for range: NSRange, in textView: UITextView) -> [CGRect] {
            guard let textRange = textRange(range, in: textView) else { return [] }
            return textView.selectionRects(for: textRange).map(\.rect).filter { !$0.isEmpty && !$0.isNull }
        }

        /// Replaces `range` with `replacement` (undoably) if the script still has `expected` there.
        @discardableResult
        private func replace(_ range: NSRange, expecting expected: String, with replacement: String,
                             in textView: UITextView) -> Bool {
            let ns = textView.text as NSString
            guard NSMaxRange(range) <= ns.length, ns.substring(with: range) == expected,
                  let textRange = textRange(range, in: textView) else { return false }
            textView.replace(textRange, withText: replacement)
            textViewDidChange(textView)
            return true
        }

        private func present(_ target: MedQuickEditTarget, from textView: UITextView) {
            guard let presenter = textView.medTopViewController() else { return }
            // Typing while the popover is up would shift the text it's editing.
            textView.resignFirstResponder()

            switch target {
            case .value(let edit):
                var range = edit.valueRange
                var current = (textView.text as NSString).substring(with: range)
                let popover = MedValuePopover(edit: edit) { [weak self, weak textView] value in
                    guard let self, let textView else { return }
                    let replacement = edit.text(for: value)
                    if self.replace(range, expecting: current, with: replacement, in: textView) {
                        range.length = (replacement as NSString).length
                        current = replacement
                    }
                }
                let host = UIHostingController(rootView: popover)
                host.sizingOptions = .preferredContentSize
                host.modalPresentationStyle = .popover
                if let pop = host.popoverPresentationController {
                    pop.sourceView = textView
                    pop.sourceRect = rects(for: edit.hitRange, in: textView).first ?? .zero
                    pop.permittedArrowDirections = [.up, .down]
                    pop.delegate = self
                }
                presenter.present(host, animated: true)

            case .pool(let name, _), .poolBlock(let name, _):
                guard let block = MedPoolBlock.find(named: name, in: textView.text) else {
                    // Defined outside the script: the editor around it opens that pool.
                    onOpenPool?(name)
                    return
                }
                let whole = (textView as? MedTextView)?.wholeText ?? textView.text ?? ""
                let sheet = MedPoolEditorSheet(
                    name: name, items: block.items,
                    references: MeditationParser.referenceableNames(in: whole),
                    isUnused: MeditationParser.unusedPoolNames(in: whole).contains(name),
                    onDone: { [weak self, weak textView, weak presenter] items in
                        if let self, let textView {
                            self.replace(block.range, expecting: block.source,
                                         with: block.text(with: items), in: textView)
                        }
                        presenter?.dismiss(animated: true)
                    },
                    onCancel: { [weak presenter] in presenter?.dismiss(animated: true) },
                    onDelete: { [weak self, weak textView, weak presenter] in
                        if let self, let textView {
                            // The block and its line break, so no empty line is left behind.
                            let ns = textView.text as NSString
                            var range = block.range
                            if NSMaxRange(range) < ns.length {
                                range.length += 1
                            } else if range.location > 0 {
                                range = NSRange(location: range.location - 1, length: range.length + 1)
                            }
                            self.replace(range, expecting: ns.substring(with: range), with: "", in: textView)
                        }
                        presenter?.dismiss(animated: true)
                    })
                let host = UIHostingController(rootView: sheet)
                // Swiping away would silently drop edits; Cancel and Done are explicit.
                host.isModalInPresentation = true
                if let sheetController = host.sheetPresentationController {
                    sheetController.detents = [.medium(), .large()]
                    sheetController.prefersGrabberVisible = true
                }
                presenter.present(host, animated: true)

            case .header:
                let script = textView.text ?? ""
                guard let headerRange = MedHeader.range(in: script) else { return }
                let source = (script as NSString).substring(with: headerRange)
                let meta = MeditationParser.parseMetadata(script)
                let editor = TagEditorView(
                    title: "Title & Tags", initialName: meta.title, initialTags: meta.tags,
                    suggestions: MedHeader.suggestedTags(),
                    onSave: { [weak self, weak textView] name, tags in
                        let title = name?.trimmingCharacters(in: .whitespaces) ?? meta.title
                        guard let self, let textView, title != meta.title || tags != meta.tags else { return }
                        let header = MeditationMetadataWriter.rewrite(source: source, title: title, tags: tags)
                        self.replace(headerRange, expecting: source, with: header, in: textView)
                    },
                    onClose: { [weak presenter] in presenter?.dismiss(animated: true) })
                let host = UIHostingController(rootView: editor)
                host.isModalInPresentation = true
                if let sheetController = host.sheetPresentationController {
                    sheetController.detents = [.medium(), .large()]
                    sheetController.prefersGrabberVisible = true
                }
                presenter.present(host, animated: true)
            }
        }

        // MARK: New pool

        /// Selected text can be made into a pool: Make Pool… in the edit menu.
        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let selection = medExtractableRange(range, in: textView.text ?? "") else { return nil }
            let make = UIAction(title: "Make Pool…", image: UIImage(systemName: "tray")) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.startNewPool(in: textView, extracting: selection)
            }
            return UIMenu(children: [make] + suggestedActions)
        }

        /// Asks for a name, then puts `~name` where the caret was and opens the new pool's sheet.
        /// With `extracting`, that text is what `~name` replaces, and it becomes one of the pool's items.
        func startNewPool(in textView: UITextView, extracting: NSRange? = nil) {
            guard let presenter = textView.medTopViewController() else { return }
            let caret = extracting ?? textView.selectedRange
            let item = extracting.map { (textView.text as NSString).substring(with: $0) }
            let alert = UIAlertController(
                title: item == nil ? "New Pool" : "Make Pool",
                message: item == nil
                    ? "A ~name goes here, and its items go in the pool."
                    : "The selected text becomes an item of the pool, and ~name takes its place. A pool that already exists gets it as one more item.",
                preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "name"
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak textView, weak alert] _ in
                guard let self, let textView, let name = Self.poolName(from: alert?.textFields?.first?.text ?? "") else { return }
                self.createPool(named: name, at: caret, item: item, in: textView)
            })
            presenter.present(alert, animated: true)
        }

        /// What was typed, made into a pool name: spaces become `_`, anything else odd is dropped.
        static func poolName(from typed: String) -> String? {
            let cleaned = typed.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "_")
                .filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" }
            guard let first = cleaned.first else { return nil }
            return first.isNumber ? "_" + cleaned : cleaned
        }

        private func createPool(named name: String, at caret: NSRange, item: String? = nil, in textView: UITextView) {
            let medView = textView as? MedTextView
            var ns = textView.text as NSString
            guard NSMaxRange(caret) <= ns.length else { return }
            medView?.isAdjustingSelection = true
            defer { medView?.isAdjustingSelection = false }

            // The reference, where the caret was (or in place of the selected text). A ~ typed
            // just before the caret is taken in.
            var refRange = caret
            if item == nil, refRange.location > 0, ns.character(at: refRange.location - 1) == 0x7E {
                refRange = NSRange(location: refRange.location - 1, length: refRange.length + 1)
            }
            let reference = "~\(name)"
            guard let refText = textRange(refRange, in: textView) else { return }
            textView.replace(refText, withText: reference)
            var caretAfter = refRange.location + (reference as NSString).length

            let text = textView.text ?? ""
            ns = text as NSString
            let whole = (textView as? MedTextView)?.wholeText ?? text
            if let onNewPoolOutside {
                // Pools live outside the script: it gets just the reference, and the editor
                // around it defines the pool (or adds the item to the one already there).
                textView.selectedRange = NSRange(location: caretAfter, length: 0)
                textViewDidChange(textView)
                onNewPoolOutside(name, item)
                return
            }
            if !MeditationParser.referenceableNames(in: whole).pools.contains(name) {
                // Defined before its first use: after the last pool above this line, so pools stay
                // together, or else on its own line just above (above the pool it's used in, if any).
                let lineStart = ns.lineRange(for: NSRange(location: refRange.location, length: 0)).location
                let blocks = MedPoolBlock.blockRanges(in: text)
                var anchor = blocks.first { NSLocationInRange(lineStart, $0.range) }?.range.location ?? lineStart
                if let header = MedHeader.range(in: text), anchor < NSMaxRange(header) {
                    anchor = NSMaxRange(header)
                }
                let insertion: (at: Int, text: String)
                // An indented line under `~name` is what makes it a pool, so an empty one gets a blank one.
                let itemLine = "\n  " + (item ?? "")
                if let previous = blocks.last(where: { NSMaxRange($0.range) <= anchor }) {
                    insertion = (NSMaxRange(previous.range), "\n~ \(name)\(itemLine)")
                } else {
                    insertion = (anchor, "~ \(name)\(itemLine)\n\n")
                }
                if let range = textRange(NSRange(location: insertion.at, length: 0), in: textView) {
                    textView.replace(range, withText: insertion.text)
                    if insertion.at <= refRange.location { caretAfter += (insertion.text as NSString).length }
                }
            }
            textView.selectedRange = NSRange(location: caretAfter, length: 0)
            textViewDidChange(textView)
            present(.poolBlock(name: name, hitRange: NSRange(location: 0, length: 0)), from: textView)
        }

        /// Keep the popover a popover on iPhone instead of turning it into a sheet.
        func adaptivePresentationStyle(for controller: UIPresentationController,
                                       traitCollection: UITraitCollection) -> UIModalPresentationStyle {
            .none
        }
    }
}

private extension UIView {
    /// The view controller to present from: the one owning this view, or whatever it presents on top.
    func medTopViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if var top = current as? UIViewController {
                while let presented = top.presentedViewController { top = presented }
                return top
            }
            responder = current.next
        }
        return nil
    }
}

private extension MedQuickEditTarget {
    var tapTint: UIColor {
        let base: UIColor
        switch self {
        case .value(let edit):
            base = edit.kind == .dots || edit.valueRange.length == 0 ? .systemOrange : .systemBlue
        case .pool, .poolBlock:
            base = .systemPurple
        case .header:
            base = .systemGray
        }
        return base
    }
}

/// The script editor's text view: draws a rounded chip behind each quick-edit target.
final class MedTextView: UITextView {
    /// The folded pools, and the text they were worked out for (stale while an edit is under way).
    var folds: [MedFold] = []
    /// The ~ menu's New Pool…, handled by the editor's coordinator.
    var onNewPool: (() -> Void)?
    /// The meditation before the script, when this view edits only the script.
    var outsideText = ""
    /// The whole meditation: what's outside the script, then the script.
    var wholeText: String { outsideText + (text ?? "") }
    var foldedText: String?
    /// Set while the caret is being moved on purpose, so the move isn't corrected again.
    var isAdjustingSelection = false
    private let chipView = UIView()
    private var chipLayers: [CALayer] = []
    private var chipsNeedUpdate = true
    private var chipWidth: CGFloat = 0

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        chipView.isUserInteractionEnabled = false
        chipView.backgroundColor = .clear
        // Behind the text, and scrolling with it since it's in content coordinates.
        insertSubview(chipView, at: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    func adjustSelection(to location: Int) {
        isAdjustingSelection = true
        selectedRange = NSRange(location: location, length: 0)
        isAdjustingSelection = false
    }

    func setChipsNeedUpdate() {
        chipsNeedUpdate = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if chipView.superview === self { sendSubviewToBack(chipView) }
        // layoutSubviews runs on every scroll, so only redo the chips when text or width changed.
        guard chipsNeedUpdate || bounds.width != chipWidth else { return }
        chipsNeedUpdate = false
        chipWidth = bounds.width
        updateChips()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setChipsNeedUpdate()
    }

    /// The chip behind each line of `range`: the glyphs plus `medChipPadding` on every side.
    /// The highlighter kerns `medChipGap` of room on each side of a target so neighbors stay clear.
    static func chipRects(for target: MedQuickEditTarget, in textView: UITextView) -> [CGRect] {
        guard target.isBlock else { return chipRects(for: target.hitRange, in: textView) }
        // A folded pool is one row: a full-width chip around its `~name` line. Selection rects
        // for whole lines run to the right edge, so measure the trimmed text.
        let ns = (textView.text ?? "") as NSString
        guard NSMaxRange(target.hitRange) <= ns.length else { return [] }
        var union = CGRect.null
        ns.enumerateSubstrings(in: target.hitRange, options: [.byLines]) { line, lineRange, _, stop in
            stop.pointee = true
            let line = line ?? ""
            let lead = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            let range = NSRange(location: lineRange.location + lead, length: trimmed.utf16.count)
            for rect in chipRects(for: range, in: textView) { union = union.union(rect) }
        }
        guard !union.isNull else { return [] }
        // Full width: as far in from the right edge as the chip starts from the left.
        union.size.width = max(union.width, textView.bounds.width - 2 * union.minX)
        return [union]
    }

    static func chipRects(for range: NSRange, in textView: UITextView) -> [CGRect] {
        guard range.length > 0 else { return [] }
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return [] }
        let font = textView.font ?? medFont
        let rects = textView.selectionRects(for: textRange).map(\.rect).filter { !$0.isNull && !$0.isEmpty && $0.width > 0 }
        // The trailing gap is kerned onto the target's last character, and selection rects
        // include it only sometimes, so end the last rect where that character's glyph ends.
        let ns = (textView.text ?? "") as NSString
        let lastChar = ns.rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1)
        var glyphEnd: CGFloat?
        if let lastStart = textView.position(from: textView.beginningOfDocument, offset: lastChar.location) {
            let width = ns.substring(with: lastChar).size(withAttributes: [.font: font]).width
            glyphEnd = textView.caretRect(for: lastStart).minX + width
        }
        // A wrapped range's later rects start right under the line before, taking in the line
        // spacing, so place them by the caret on their own line, offset like the first rect.
        func caretTop(_ rect: CGRect) -> CGFloat? {
            textView.closestPosition(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 1))
                .map { textView.caretRect(for: $0).minY }
        }
        let firstOffset = rects.first.flatMap { first in caretTop(first).map { first.minY - $0 } } ?? 0
        return rects.enumerated().map { index, rect in
            let top = index == 0 ? rect.minY : (caretTop(rect).map { $0 + firstOffset } ?? rect.minY)
            var glyphs = CGRect(x: rect.minX, y: top, width: rect.width, height: font.lineHeight)
            if index == rects.count - 1, let glyphEnd, glyphEnd > glyphs.minX {
                glyphs.size.width = glyphEnd - glyphs.minX
            }
            return glyphs.insetBy(dx: -medChipPadding.width, dy: -medChipPadding.height)
        }
    }

    private func updateChips() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        chipLayers.forEach { $0.removeFromSuperlayer() }
        chipLayers = []
        chipView.frame = CGRect(origin: .zero, size: CGSize(width: bounds.width, height: max(contentSize.height, bounds.height)))

        // Pool blocks get their own layers, added first, so the chips inside them draw on top.
        var blockPaths: [UIColor: UIBezierPath] = [:]
        var paths: [UIColor: UIBezierPath] = [:]
        let currentFolds = foldedText == text ? folds : []
        for target in MedQuickEdit.allTargets(in: text ?? "", outside: outsideText) {
            // Folded items have no chips of their own.
            if !target.isBlock, currentFolds.contains(where: { NSLocationInRange(target.hitRange.location, $0.itemsRange) }) {
                continue
            }
            // A pool reference reads as a link (pink text, no chip), still tappable to its well.
            if case .pool = target { continue }
            var tint = target.tapTint
            if case .poolBlock(let name, _) = target, currentFolds.first(where: { $0.name == name })?.isUnused == true {
                tint = .systemGray
            }
            let path = (target.isBlock ? blockPaths : paths)[tint] ?? UIBezierPath()
            let chips = Self.chipRects(for: target, in: self)
            for chip in chips {
                path.append(UIBezierPath(roundedRect: chip, cornerRadius: min(8, chip.height / 2)))
            }
            if target.isBlock { blockPaths[tint] = path } else { paths[tint] = path }
            // A folded pool says how many items it holds, at the right end of its row.
            if case .poolBlock(let name, _) = target, let fold = currentFolds.first(where: { $0.name == name }),
               let chip = chips.first {
                let label = CATextLayer()
                let font = UIFont.preferredFont(forTextStyle: .footnote)
                label.string = NSAttributedString(string: fold.summary, attributes: [
                    .font: font,
                    .foregroundColor: UIColor.secondaryLabel.resolvedColor(with: traitCollection),
                ])
                label.contentsScale = traitCollection.displayScale
                label.alignmentMode = .right
                let height = font.lineHeight
                label.frame = CGRect(x: chip.minX + 8, y: chip.midY - height / 2,
                                     width: chip.width - 20, height: height)
                chipView.layer.addSublayer(label)
                chipLayers.append(label)
            }
        }
        for (color, path) in Array(blockPaths) + Array(paths) {
            let resolved = color.resolvedColor(with: traitCollection)
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillColor = resolved.withAlphaComponent(0.10).cgColor
            layer.strokeColor = resolved.withAlphaComponent(0.35).cgColor
            layer.lineWidth = 0.75
            chipView.layer.addSublayer(layer)
            chipLayers.append(layer)
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

// Scripts are mostly prose, so they read in the body font (17pt at the default size, scaled
// with Dynamic Type). Computed so a size change in Settings takes effect the next time the
// text is highlighted.
var medFont: UIFont {
    UIFont.preferredFont(forTextStyle: .body)
}

// A space in a proportional font is narrow, so two-space indents nearly vanish. Leading
// spaces get extra kerning to be as wide as a monospaced space.
private func medIndentKern(for font: UIFont) -> CGFloat {
    let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
    return max(0, font.pointSize * 0.6 - spaceWidth)
}

private let medLeadingSpaces = try! NSRegularExpression(pattern: "^ +", options: [.anchorsMatchLines])

// Quick-edit chips: padding around the glyphs, and the extra room kerned on each side of a target.
private let medChipPadding = CGSize(width: 6, height: 5)
private let medChipGap: CGFloat = 9

private let medParagraphStyle: NSParagraphStyle = {
    let p = NSMutableParagraphStyle()
    p.headIndent = 24        // wrapped continuations indent by 24pt
    p.firstLineHeadIndent = 0
    p.lineSpacing = 11      // just enough that chips on neighboring lines keep ~1.5pt apart
    p.paragraphSpacing = 0
    return p
}()

private var medBaseAttributes: [NSAttributedString.Key: Any] { [
    .font: medFont,
    .foregroundColor: UIColor.label,
    .paragraphStyle: medParagraphStyle,
] }

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
        MedSyntaxRule(regex: rx(#"(?:^|(?<=[\s\]]))(?:×|x)\d+(?=$|[\s\[\]‖|])"#),
                      groupColors: [0: count]),
        MedSyntaxRule(regex: rx(#"[\[\]]"#),
                      groupColors: [0: count]),
        MedSyntaxRule(regex: rx(#"‖|\|\|"#),
                      groupColors: [0: pause]),
        MedSyntaxRule(regex: rx(#"(⏳)[ \t]*(\d+(?:\.\d+)?)?([″"′'])?"#),
                      groupColors: [1: pause, 2: count, 3: count]),
        MedSyntaxRule(regex: rx(#"\b(\d+(?:\.\d+)?)([″"])"#),
                      groupColors: [1: count, 2: count]),
        MedSyntaxRule(regex: rx(#"\b(\d+(?:\.\d+)?)([′'])"#),
                      groupColors: [1: count, 2: count]),
        MedSyntaxRule(regex: rx(#"·+"#),
                      groupColors: [0: pause]),
        MedSyntaxRule(regex: rx(#"(~)([A-Za-z_][A-Za-z0-9_]*)(?:(=)([A-Za-z_][A-Za-z0-9_]*))?"#),
                      groupColors: [1: pool, 2: pool, 3: pool, 4: pool]),
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
    let kern = medIndentKern(for: medFont)
    medLeadingSpaces.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
        guard let r = match?.range else { return }
        storage.addAttribute(.kern, value: kern, range: r)
    }
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
    // What a tap edits directly sits on a rounded chip, so it reads as tappable. Kern room on
    // both sides of each target so its chip's padding doesn't crowd the neighboring text.
    let ns = text as NSString
    func addGap(at index: Int) {
        guard index >= 0, index < storage.length else { return }
        let existing = (storage.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat) ?? 0
        storage.addAttribute(.kern, value: existing + medChipGap, range: NSRange(location: index, length: 1))
    }
    let outside = (textView as? MedTextView)?.outsideText ?? ""
    let targets = MedQuickEdit.allTargets(in: text, outside: outside)
    let chipStarts = Set(targets.compactMap { target -> Int? in
        if case .pool = target { return nil }
        return target.isBlock ? nil : target.hitRange.location
    })
    for target in targets
    where !target.isBlock && target.hitRange.length > 0 && NSMaxRange(target.hitRange) <= storage.length {
        // Pool references draw no chip, so they need no room of their own, except before a
        // chip that follows them, which would otherwise crowd the link.
        if case .pool = target {
            var next = NSMaxRange(target.hitRange)
            while next < ns.length, ns.character(at: next) == 32 || ns.character(at: next) == 9 { next += 1 }
            if chipStarts.contains(next) { addGap(at: NSMaxRange(target.hitRange) - 1) }
            continue
        }
        let before = target.hitRange.location - 1
        if before >= 0, ns.character(at: before) != 10 { addGap(at: before) }
        addGap(at: NSMaxRange(target.hitRange) - 1)
    }
    (textView as? MedTextView)?.setChipsNeedUpdate()
    // Diagnosed as a whole meditation, then shifted back to the script's own positions.
    let outsideLength = (outside as NSString).length
    for whole in MeditationParser.diagnose(outside + text) where whole.range.location >= outsideLength {
        let diagnostic = (range: NSRange(location: whole.range.location - outsideLength, length: whole.range.length),
                          isDeprecation: whole.isDeprecation)
        guard NSMaxRange(diagnostic.range) <= storage.length else { continue }
        if diagnostic.isDeprecation {
            // Old syntax still plays: show it struck through rather than as an error.
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: UIColor.secondaryLabel,
                .foregroundColor: UIColor.secondaryLabel,
            ], range: diagnostic.range)
            continue
        }
        storage.addAttributes([
            .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
            .underlineColor: UIColor.systemRed,
        ], range: diagnostic.range)
    }
    // Fold pools into one-line rows, last, so nothing above draws into the folded lines.
    let folds = MedFold.folds(in: text, caret: savedSelection.location)
    for fold in folds {
        if fold.itemsRange.length > 0 { storage.setAttributes(medFoldedAttributes, range: fold.itemsRange) }
        if let blanks = fold.blanks { storage.setAttributes(medFoldedAttributes, range: blanks) }
        if fold.isUnused {
            let header = ns.lineRange(for: NSRange(location: fold.headerEnd, length: 0))
            let headerText = NSRange(location: header.location, length: fold.headerEnd - header.location)
            storage.addAttribute(.foregroundColor, value: UIColor.tertiaryLabel, range: headerText)
        }
    }
    let medView = textView as? MedTextView
    medView?.folds = folds
    medView?.foldedText = text
    storage.endEditing()
    medView?.isAdjustingSelection = true
    textView.selectedRange = savedSelection
    medView?.isAdjustingSelection = false
    textView.typingAttributes = medBaseAttributes
}

// MARK: - Folded pools

/// A pool definition shown as one row: its `~name` line stays, its item lines are drawn at no
/// height, and so are blank lines between it and a pool right after it, so a run of pools reads
/// as an even stack. Only the drawing changes; the text keeps every line.
struct MedFold {
    let name: String
    /// End of the `~name` line's text, where the caret goes instead of into the fold.
    let headerEnd: Int
    /// End of the block's last line, before its line break.
    let blockEnd: Int
    /// Blank lines folded away between this pool and the next one, if any.
    let blanks: NSRange?
    /// Blank lines between this pool and the next that the caret is on, so left showing.
    let openedBlanks: NSRange?
    let itemCount: Int
    let isUnused: Bool

    /// The item lines, from the `~name` line's break to the block's end.
    var itemsRange: NSRange { NSRange(location: headerEnd, length: blockEnd - headerEnd) }

    /// The last caret position that isn't drawn.
    private var lastHidden: Int { blanks.map { NSMaxRange($0) - 1 } ?? blockEnd }

    func hidesCaret(at location: Int) -> Bool {
        location > headerEnd && location <= lastHidden
    }

    /// The folded characters, which an edit from outside mustn't cut into.
    func protectedRange(textLength: Int) -> NSRange {
        guard lastHidden > headerEnd else { return NSRange(location: headerEnd, length: 0) }
        return NSRange(location: headerEnd, length: min(lastHidden + 1, textLength) - headerEnd)
    }

    var summary: String {
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return isUnused ? "unused · \(items)" : items
    }

    static func folds(in text: String, caret: Int) -> [MedFold] {
        let ns = text as NSString
        let blocks = MedPoolBlock.blockRanges(in: text)
        let unused = MeditationParser.unusedPoolNames(in: text)
        var folds: [MedFold] = []
        for (index, block) in blocks.enumerated() {
            var headerStart = 0, headerLineEnd = 0, headerEnd = 0
            ns.getLineStart(&headerStart, end: &headerLineEnd, contentsEnd: &headerEnd,
                            for: NSRange(location: block.range.location, length: 0))
            let blockEnd = NSMaxRange(block.range)
            var blanks: NSRange?
            var opened: NSRange?
            if index + 1 < blocks.count, blockEnd < ns.length {
                let gapStart = blockEnd + 1
                let nextStart = blocks[index + 1].range.location
                if nextStart > gapStart,
                   ns.substring(with: NSRange(location: gapStart, length: nextStart - gapStart))
                       .allSatisfy({ $0.isWhitespace }) {
                    let gap = NSRange(location: gapStart, length: nextStart - gapStart)
                    if caret >= gapStart && caret < nextStart { opened = gap } else { blanks = gap }
                }
            }
            let items = MedPoolBlock.find(named: block.name, in: text)?.items.filter { !$0.commented }.count ?? 0
            folds.append(MedFold(name: block.name, headerEnd: headerEnd, blockEnd: blockEnd,
                                 blanks: blanks, openedBlanks: opened, itemCount: items,
                                 isUnused: unused.contains(block.name)))
        }
        return folds
    }
}

/// Drawn at no height and no width: what a folded pool hides.
private let medFoldedAttributes: [NSAttributedString.Key: Any] = {
    let p = NSMutableParagraphStyle()
    p.maximumLineHeight = 0.01
    p.minimumLineHeight = 0
    p.lineSpacing = 0
    p.paragraphSpacing = 0
    return [
        .font: UIFont.systemFont(ofSize: 0.01),
        .foregroundColor: UIColor.clear,
        .paragraphStyle: p,
    ]
}()

// MARK: - Pool item field

/// The part of `range` that Make Pool takes, when it's text that could become a pool item
/// (something on one line): surrounding spaces trimmed, and trailing pauses, times, bells and
/// repeat counts (words with no letters) left in place, so the timing stays where it was.
func medExtractableRange(_ range: NSRange, in text: String) -> NSRange? {
    let ns = text as NSString
    guard range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
    var start = range.location
    var end = NSMaxRange(range)
    func isSpace(_ i: Int) -> Bool { ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 }
    while start < end, isSpace(start) { start += 1 }
    while end > start, isSpace(end - 1) { end -= 1 }
    guard end > start else { return nil }
    guard !ns.substring(with: NSRange(location: start, length: end - start)).contains(where: \.isNewline) else { return nil }
    // Drop trailing words with no letters, unless that leaves nothing.
    var kept = end
    while kept > start {
        var wordStart = kept
        while wordStart > start, !isSpace(wordStart - 1) { wordStart -= 1 }
        let word = ns.substring(with: NSRange(location: wordStart, length: kept - wordStart))
        guard wordStart > start, !word.contains(where: { $0.isLetter || $0 == "~" }) else { break }
        kept = wordStart
        while kept > start, isSpace(kept - 1) { kept -= 1 }
    }
    return NSRange(location: start, length: kept - start)
}

/// A one-item text field for the pool sheet: script syntax colors, Return for the next item, and
/// a keyboard bar with the pool menu and the pause symbols an item most often needs.
struct MedItemField: UIViewRepresentable {
    @Binding var text: String
    /// Pools and remembered picks the script defines, for the `~…` menu.
    let references: (pools: [String], picks: [String])
    /// Commented-out items read as off: dimmed and struck through.
    var dimmed = false
    /// Becomes first responder when this turns true.
    var focused = false
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}
    var onSubmit: () -> Void = {}
    /// Make Pool… on selected text in the item: the range to take out.
    var onExtract: ((NSRange) -> Void)? = nil
    /// Tapping a `~name` reference jumps to that well instead of placing the cursor.
    var onOpenPool: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let field = UITextView()
        field.isScrollEnabled = false
        field.backgroundColor = .clear
        field.textContainerInset = .zero
        field.textContainer.lineFragmentPadding = 0
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .next
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.inputAccessoryView = makeItemToolbar(for: field, references: references)
        field.text = text
        context.coordinator.recolor(field)
        // A tap on a `~name` reference jumps to that well rather than placing the cursor.
        context.coordinator.field = field
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleRefTap))
        tap.delegate = context.coordinator
        field.addGestureRecognizer(tap)
        context.coordinator.refTap = tap
        return field
    }

    func updateUIView(_ field: UITextView, context: Context) {
        context.coordinator.parent = self
        // While typing, the field is the source of truth; a stale binding must not reset it.
        if field.text != text, !field.isFirstResponder {
            field.text = text
        }
        context.coordinator.recolor(field)
        if focused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, medFont.lineHeight))
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MedItemField
        weak var field: UITextView?
        var refTap: UITapGestureRecognizer?
        /// The well a tap would jump to, found as the tap begins.
        private var pendingPool: String?
        init(_ parent: MedItemField) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text.contains("\n") else { return true }
            parent.onSubmit()
            return false
        }

        // MARK: Tap a reference to jump to its well

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === refTap else { return true }
            // Without a handler (the pool sheet), never intercept — let the tap place the cursor.
            guard let field, parent.onOpenPool != nil else { return false }
            pendingPool = poolRef(at: gestureRecognizer.location(in: field), in: field)
            return pendingPool != nil
        }

        /// The field's own tap waits for ours, which fails at once unless it landed on a reference.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === refTap, let field,
                  let other = otherGestureRecognizer as? UITapGestureRecognizer,
                  other.numberOfTapsRequired == 1,
                  let view = other.view, view.isDescendant(of: field) else { return false }
            return true
        }

        @objc func handleRefTap() {
            guard let pool = pendingPool else { return }
            pendingPool = nil
            parent.onOpenPool?(pool)
        }

        /// The well a `~name` reference under `point` draws from (the pool after `=`, if any), or nil.
        private func poolRef(at point: CGPoint, in field: UITextView) -> String? {
            guard let position = field.closestPosition(to: point) else { return nil }
            let offset = field.offset(from: field.beginningOfDocument, to: position)
            let text = field.text ?? ""
            let ns = text as NSString
            let regex = try! NSRegularExpression(
                pattern: #"(~)([A-Za-z_][A-Za-z0-9_]*)(?:(=)([A-Za-z_][A-Za-z0-9_]*))?"#)
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard NSLocationInRange(offset, match.range)
                        || offset == NSMaxRange(match.range) else { continue }
                let drawn = match.range(at: 4).location != NSNotFound ? match.range(at: 4) : match.range(at: 2)
                return ns.substring(with: drawn)
            }
            return nil
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            recolor(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocus() }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onBlur() }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                      suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let onExtract = parent.onExtract,
                  let selection = medExtractableRange(range, in: textView.text ?? "") else { return nil }
            let make = UIAction(title: "Make Pool…", image: UIImage(systemName: "tray")) { [weak textView] _ in
                // The binding follows the field only while typing; bring it up to date first.
                if let textView { self.parent.text = textView.text }
                onExtract(selection)
            }
            return UIMenu(children: [make] + suggestedActions)
        }

        func recolor(_ field: UITextView) {
            let storage = field.textStorage
            let full = NSRange(location: 0, length: storage.length)
            let base: [NSAttributedString.Key: Any] = [
                .font: medFont,
                .foregroundColor: parent.dimmed ? UIColor.secondaryLabel : UIColor.label,
            ]
            field.typingAttributes = base
            guard full.length > 0 else { return }
            let selection = field.selectedRange
            let text = field.text ?? ""
            storage.beginEditing()
            storage.setAttributes(base, range: full)
            if parent.dimmed {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: UIColor.secondaryLabel], range: full)
            } else {
                for rule in medSyntaxRules {
                    rule.regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                        guard let match else { return }
                        for (group, color) in rule.groupColors where group < match.numberOfRanges {
                            let r = match.range(at: group)
                            guard r.location != NSNotFound, r.length > 0 else { continue }
                            storage.addAttribute(.foregroundColor, value: color, range: r)
                        }
                    }
                }
            }
            storage.endEditing()
            field.selectedRange = selection
        }
    }
}

private func makeItemToolbar(for field: UITextView, references: (pools: [String], picks: [String])) -> UIView {
    let bar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    bar.backgroundColor = .systemBackground.withAlphaComponent(0.55)
    bar.clipsToBounds = true

    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 2
    stack.translatesAutoresizingMaskIntoConstraints = false
    bar.contentView.addSubview(stack)

    let pools = SymbolButton(label: "~…", accessibilityLabel: "Insert a pool reference") {}
    pools.showsMenuAsPrimaryAction = true
    func insertAction(_ name: String) -> UIAction {
        UIAction(title: "~\(name)") { [weak field] _ in field?.insertText("~\(name)") }
    }
    var sections: [UIMenuElement] = []
    if !references.pools.isEmpty {
        sections.append(UIMenu(title: "Pools", options: .displayInline, children: references.pools.map(insertAction)))
    }
    if !references.picks.isEmpty {
        sections.append(UIMenu(title: "Remembered picks", options: .displayInline, children: references.picks.map(insertAction)))
    }
    if sections.isEmpty {
        sections.append(UIAction(title: "No pools defined yet", attributes: .disabled) { _ in })
    }
    pools.menu = UIMenu(children: sections)
    stack.addArrangedSubview(pools)
    stack.addArrangedSubview(AccessoryGap(width: 12))
    for (label, char, name) in [("·", "·", "One second pause"), ("″", "\u{2033}", "Seconds marker")] {
        stack.addArrangedSubview(SymbolButton(label: label, accessibilityLabel: name) { [weak field] in
            field?.insertText(char)
        })
    }

    let done = AccessoryIconButton(systemName: "keyboard.chevron.compact.down")
    done.accessibilityLabel = "Dismiss keyboard"
    done.translatesAutoresizingMaskIntoConstraints = false
    done.addAction(UIAction { [weak field] _ in field?.resignFirstResponder() }, for: .touchUpInside)
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
        stack.leadingAnchor.constraint(equalTo: bar.contentView.leadingAnchor, constant: 8),
        stack.topAnchor.constraint(equalTo: bar.contentView.topAnchor),
        stack.bottomAnchor.constraint(equalTo: bar.contentView.bottomAnchor),
        done.trailingAnchor.constraint(equalTo: bar.contentView.trailingAnchor, constant: -4),
        done.centerYAnchor.constraint(equalTo: bar.contentView.centerYAnchor),
        done.widthAnchor.constraint(equalToConstant: 48),
        done.heightAnchor.constraint(equalToConstant: 42),
    ])
    bar.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
    return bar
}
