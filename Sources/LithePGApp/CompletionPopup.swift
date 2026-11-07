import AppKit
import LithePGCore

/// The editor's autocomplete dropdown: a borderless, non-activating panel anchored under the
/// word being typed. Focus stays in the text view, which forwards the arrow, Tab, Return and
/// Esc keys here while the list is showing.
///
/// Drawn with a plain `NSTableView`. A SwiftUI list hosted in this panel kept showing its first
/// rendering after the panel was hidden and shown again, so the AppKit table is used instead.
@MainActor
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var items: [SQLCompletion] = []
    private var panel: NSPanel?
    private var tableView: NSTableView?
    private weak var parentWindow: NSWindow?
    private(set) var result: SQLCompletionResult?

    static let rowHeight: CGFloat = 24
    static let maxVisibleRows = 8
    static let width: CGFloat = 380
    private static let inset: CGFloat = 4

    var isVisible: Bool { panel?.isVisible == true }

    var onAccept: (SQLCompletion) -> Void = { _ in }

    private var selected: Int {
        get { tableView?.selectedRow ?? -1 }
        set {
            guard let tableView, items.indices.contains(newValue) else { return }
            tableView.selectRowIndexes([newValue], byExtendingSelection: false)
            tableView.scrollRowToVisible(newValue)
        }
    }

    var selectedCompletion: SQLCompletion? {
        items.indices.contains(selected) ? items[selected] : nil
    }

    func show(_ result: SQLCompletionResult, in textView: NSTextView) {
        guard let window = textView.window else { return }
        // Keep the highlighted suggestion when the list only narrows as you type.
        let previous = selectedCompletion
        self.result = result
        items = result.completions

        let panel = panel ?? makePanel()
        tableView?.reloadData()
        selected = previous.flatMap { item in items.firstIndex(of: item) } ?? 0

        let rows = min(items.count, Self.maxVisibleRows)
        let size = NSSize(width: Self.width, height: CGFloat(rows) * Self.rowHeight + Self.inset * 2)
        let anchor = textView.firstRect(forCharacterRange: result.replacementRange, actualRange: nil)
        var origin = NSPoint(x: anchor.minX - 8, y: anchor.minY - size.height - 2)
        if let screen = window.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = anchor.maxY + 2 }  // no room below: open above
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if parentWindow !== window {
            parentWindow?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            parentWindow = window
        }
        panel.orderFront(nil)
    }

    func hide() {
        result = nil
        guard let panel, panel.isVisible else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow = nil
        panel.orderOut(nil)
    }

    func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = max(selected, 0)
        if abs(offset) == 1 {
            selected = (current + offset + items.count) % items.count  // arrows wrap around
        } else {
            selected = min(max(current + offset, 0), items.count - 1)  // pages stop at the ends
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor

        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none
        table.allowsEmptySelection = false
        table.refusesFirstResponder = true
        table.setAccessibilityLabel("Completions")
        let column = NSTableColumn(identifier: .init("completion"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.inset),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.inset),
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.inset),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.inset),
        ])

        panel.contentView = background
        self.panel = panel
        return panel
    }

    @objc private func rowClicked() {
        guard let tableView, items.indices.contains(tableView.clickedRow) else { return }
        onAccept(items[tableView.clickedRow])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompletionRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: CompletionCell.identifier, owner: nil) as? CompletionCell)
            ?? CompletionCell()
        cell.configure(with: items[row])
        return cell
    }
}

/// The list never takes keyboard focus (typing stays in the editor), so AppKit would draw its
/// selection in the inactive gray. Like a menu, it always shows the accent color instead.
private final class CompletionRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}

/// One suggestion: a kind icon, the text that will be inserted, and its detail on the right.
private final class CompletionCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("CompletionCell")

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        title.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .regular)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.alignment = .right
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        textField = title
        imageView = icon
        for view in [icon, title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 10),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with item: SQLCompletion) {
        title.stringValue = item.insertText
        detail.stringValue = item.detail ?? ""
        let (symbol, tint) = Self.appearance(for: item.kind)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.kind.rawValue)
        icon.contentTintColor = tint
        setAccessibilityLabel("\(item.insertText), \(item.detail ?? item.kind.rawValue)")
    }

    /// Selected rows draw on the accent color, so the text switches to its contrasting color.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emphasized = backgroundStyle == .emphasized
            title.textColor = emphasized ? .alternateSelectedControlTextColor : .labelColor
            detail.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    private static func appearance(for kind: SQLCompletion.Kind) -> (String, NSColor) {
        switch kind {
        case .keyword: ("textformat", .systemBlue)
        case .function: ("function", .systemPurple)
        case .schema: ("folder", .secondaryLabelColor)
        case .table: ("tablecells", .systemOrange)
        case .view: ("eye", .systemOrange)
        case .column: ("line.3.horizontal", .systemGreen)
        }
    }
}
