import AppKit
import LithePGCore
import SwiftUI

/// Colors JSON in the cell editor. Plain text is left alone.
enum JSONSyntaxHighlighter {
    static func color(for kind: JSONSyntaxTokens.Kind) -> NSColor {
        switch kind {
        case .key: .systemPurple
        case .string: .systemRed
        case .number: .systemBlue
        case .literal: .systemPink
        case .punctuation: .secondaryLabelColor
        }
    }

    @MainActor
    static func apply(to textView: NSTextView, baseColor: NSColor, colorsJSON: Bool = true) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let selectedRanges = textView.selectedRanges
        storage.beginEditing()
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        if colorsJSON, JSONSyntaxTokens.looksLikeJSON(text) {
            for token in JSONSyntaxTokens.tokens(in: text) {
                storage.addAttribute(.foregroundColor, value: color(for: token.kind), range: token.range)
            }
        }
        storage.endEditing()
        textView.selectedRanges = selectedRanges
    }
}

/// The cell editor's text area: a wrapping, monospaced `NSTextView` that colors JSON values.
/// SwiftUI's `TextEditor` cannot color text, which is why this bridges to AppKit.
struct CellValueEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Dims the text, for a value about to be replaced by NULL.
    var isDimmed: Bool
    /// Takes keyboard focus the first time the editor becomes editable.
    var focusWhenEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("cell-editor")
        configure(textView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        if textView.string != text {
            // Reset, Format JSON and Compact JSON replace the text from outside.
            textView.string = text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            context.coordinator.lastHighlightKey = nil
        }
        configure(textView, context: context)
    }

    private func configure(_ textView: NSTextView, context: Context) {
        textView.isEditable = isEditable && !isDimmed
        textView.isSelectable = true
        let baseColor: NSColor = isDimmed ? .tertiaryLabelColor : .labelColor
        let key = "\(isDimmed)|\(textView.string.hashValue)"
        if context.coordinator.lastHighlightKey != key {
            context.coordinator.lastHighlightKey = key
            JSONSyntaxHighlighter.apply(to: textView, baseColor: baseColor, colorsJSON: !isDimmed)
        }
        if focusWhenEditable, isEditable, !context.coordinator.didFocus {
            context.coordinator.didFocus = true
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var didFocus = false
        var lastHighlightKey: String?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            lastHighlightKey = "false|\(textView.string.hashValue)"
            JSONSyntaxHighlighter.apply(to: textView, baseColor: .labelColor)
        }
    }
}
