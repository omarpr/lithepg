import AppKit
import LithePGCore
import SwiftUI

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    /// The caret or selection to restore when this editor shows a different tab's text.
    var selection: NSRange?
    /// Reports every caret and selection change, in UTF-16 offsets.
    var onSelectionChange: (NSRange) -> Void = { _ in }
    /// Keywords plus the loaded schema's tables and columns for autocomplete.
    var completionIndex = SQLCompletionIndex(schema: nil)

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange, completionIndex: completionIndex)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
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
        context.coordinator.observeDismissals(of: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.completionIndex = completionIndex
        // Re-highlight only when the text really changed (a tab switch, a history entry, an AI
        // draft). SwiftUI calls this for unrelated state such as the running flag, and a full
        // re-highlight on each of those made the editor lag on longer scripts.
        if textView.string != text {
            context.coordinator.popup.hide()
            textView.string = text
            SQLSyntaxHighlighter.apply(to: textView)
            context.coordinator.restore(selection, in: textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: (NSRange) -> Void
        var completionIndex: SQLCompletionIndex
        let popup = CompletionPopup()
        /// What the pending edit inserts, captured before the text changes. Nil outside an edit.
        private var pendingInsertion: String?
        /// Opened with Esc rather than by typing, so it stays open even with no partial word.
        private var openedManually = false
        private var observers: [NSObjectProtocol] = []

        init(
            text: Binding<String>,
            onSelectionChange: @escaping (NSRange) -> Void,
            completionIndex: SQLCompletionIndex
        ) {
            self.text = text
            self.onSelectionChange = onSelectionChange
            self.completionIndex = completionIndex
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            pendingInsertion = replacementString ?? ""
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            SQLSyntaxHighlighter.apply(to: textView)
            let inserted = pendingInsertion ?? ""
            pendingInsertion = nil
            selectionDidChange(in: textView)
            updateCompletions(in: textView, afterInserting: inserted)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectionDidChange(in: textView)
            // Edits report through textDidChange; this path is a click or an arrow key.
            guard pendingInsertion == nil, popup.isVisible else { return }
            let selection = textView.selectedRange()
            guard selection.length == 0,
                let current = popup.result,
                let fresh = completionIndex.complete(in: textView.string, at: selection.location),
                fresh.replacementRange.location == current.replacementRange.location
            else {
                hideCompletions()
                return
            }
            popup.show(fresh, in: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            hideCompletions()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if popup.isVisible {
                switch selector {
                case #selector(NSResponder.moveUp(_:)):
                    popup.moveSelection(by: -1)
                    return true
                case #selector(NSResponder.moveDown(_:)):
                    popup.moveSelection(by: 1)
                    return true
                case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
                    popup.moveSelection(by: -CompletionPopup.maxVisibleRows)
                    return true
                case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
                    popup.moveSelection(by: CompletionPopup.maxVisibleRows)
                    return true
                case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                    guard let item = popup.selectedCompletion, let result = popup.result else { return false }
                    // A word typed out in full stays as typed, and Return still starts a new line.
                    if item.insertText.lowercased() == result.partial.lowercased() {
                        hideCompletions()
                        return false
                    }
                    accept(item, in: textView)
                    return true
                case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                    hideCompletions()
                    return true
                default:
                    return false
                }
            }
            // Esc (and Option-Esc) open the list on demand, the standard macOS completion keys.
            if selector == #selector(NSResponder.cancelOperation(_:))
                || selector == #selector(NSTextView.complete(_:))
            {
                let caret = textView.selectedRange()
                guard caret.length == 0,
                    let result = completionIndex.complete(in: textView.string, at: caret.location)
                else { return true }
                openedManually = true
                popup.onAccept = { [weak self, weak textView] item in
                    guard let self, let textView else { return }
                    self.accept(item, in: textView)
                }
                popup.show(result, in: textView)
                return true
            }
            return false
        }

        /// Opens the list after an identifier character once two are typed, or right after a
        /// `.`; keeps an open list in step with typing and deleting; closes it otherwise.
        private func updateCompletions(in textView: NSTextView, afterInserting inserted: String) {
            let caret = textView.selectedRange()
            let typedTrigger = SQLCompletionIndex.triggersCompletion(inserted)
            guard caret.length == 0, popup.isVisible || typedTrigger,
                let result = completionIndex.complete(in: textView.string, at: caret.location)
            else {
                hideCompletions()
                return
            }
            let afterDot = result.replacementRange.location > 0
                && (textView.string as NSString).character(at: result.replacementRange.location - 1) == 0x2E
            let longEnough = result.partial.utf16.count >= 2 || afterDot
            guard longEnough || (popup.isVisible && openedManually) else {
                hideCompletions()
                return
            }
            popup.onAccept = { [weak self, weak textView] item in
                guard let self, let textView else { return }
                self.accept(item, in: textView)
            }
            popup.show(result, in: textView)
        }

        private func accept(_ item: SQLCompletion, in textView: NSTextView) {
            guard let range = popup.result?.replacementRange else { return }
            hideCompletions()
            textView.insertText(item.insertText, replacementRange: range)
        }

        private func hideCompletions() {
            openedManually = false
            popup.hide()
        }

        /// Scrolling, switching windows or apps, and leaving the editor all close the list.
        func observeDismissals(of textView: NSTextView, in scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.hideCompletions() }
                })
            observers.append(
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self, weak textView] note in
                    let resigned = (note.object as AnyObject?).map(ObjectIdentifier.init)
                    MainActor.assumeIsolated {
                        guard let resigned,
                            resigned == textView?.window.map(ObjectIdentifier.init)
                        else { return }
                        self?.hideCompletions()
                    }
                })
        }

        func tearDown() {
            hideCompletions()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
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
