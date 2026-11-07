import AppKit
import LithePGCore
import SwiftUI

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    /// The caret or selection to restore when this editor shows a different tab's text.
    var selection: NSRange?
    /// Reports every caret and selection change, in UTF-16 offsets.
    var onSelectionChange: (NSRange) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.string = text
        textView.delegate = context.coordinator
        SQLSyntaxHighlighter.apply(to: textView)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView
        context.coordinator.restore(selection, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onSelectionChange = onSelectionChange
        // Re-highlight only when the text really changed (a tab switch, a history entry, an AI
        // draft). SwiftUI calls this for unrelated state such as the running flag, and a full
        // re-highlight on each of those made the editor lag on longer scripts.
        if textView.string != text {
            textView.string = text
            SQLSyntaxHighlighter.apply(to: textView)
            context.coordinator.restore(selection, in: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange) -> Void

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange) -> Void) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            SQLSyntaxHighlighter.apply(to: textView)
            selectionDidChange(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectionDidChange(in: textView)
        }

        /// Puts the caret back where it was for this tab, or at the end for text it has not
        /// seen, then reports it so Run targets the right statement straight away.
        func restore(_ selection: NSRange?, in textView: NSTextView) {
            let length = (textView.string as NSString).length
            var range = selection ?? NSRange(location: length, length: 0)
            range.location = min(max(range.location, 0), length)
            range.length = min(max(range.length, 0), length - range.location)
            textView.setSelectedRange(range)
            selectionDidChange(in: textView)
        }

        private func selectionDidChange(in textView: NSTextView) {
            let range = textView.selectedRange()
            onSelectionChange(range)
            CurrentStatementHighlighter.apply(to: textView, caret: range.location)
        }
    }
}

/// Tints the statement Run will execute when the editor holds more than one, so it is clear
/// which one runs. Uses TextKit 2 rendering attributes: they never touch the text storage, cost
/// nothing to undo, and leave the syntax colors alone.
///
/// Never reach for `textView.layoutManager` here. Asking a TextKit 2 view for it switches the
/// view to TextKit 1 and swaps in a fresh text container that wraps at the view's width, which
/// starts at zero, so the editor drew one character per line.
enum CurrentStatementHighlighter {
    static let tint = NSColor.controlAccentColor.withAlphaComponent(0.10)

    @MainActor
    static func apply(to textView: NSTextView, caret: Int) {
        guard let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let document = layoutManager.documentRange
        layoutManager.removeRenderingAttribute(.backgroundColor, for: document)
        guard let range = highlightRange(in: textView.string, caret: caret),
            let start = contentManager.location(document.location, offsetBy: range.location),
            let end = contentManager.location(start, offsetBy: range.length),
            let textRange = NSTextRange(location: start, end: end)
        else { return }
        layoutManager.addRenderingAttribute(.backgroundColor, value: tint, for: textRange)
    }

    /// Nil unless there are at least two statements; a single statement needs no marker.
    static func highlightRange(in sql: String, caret: Int) -> NSRange? {
        let statements = SQLStatementSplitter.statements(in: sql)
        guard statements.count > 1,
            let current = SQLStatementSplitter.statement(at: caret, in: sql)
        else { return nil }
        return NSRange(current.range)
    }
}
