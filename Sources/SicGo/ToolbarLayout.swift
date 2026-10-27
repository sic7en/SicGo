import AppKit

enum ToolbarItem: String, CaseIterable {
    case select, rectangle, ellipse, arrow, pen, text, mosaic, color, crop, rotate, undo, redo, discard, copy, done

    var tool: DrawingTool? { DrawingTool.allCases.first { $0.rawValue.lowercased() == rawValue } }
    var labelKey: UIString {
        if let tool { return tool.labelKey }
        switch self {
        case .color: return .annotationColor
        case .rotate: return .rotateImage
        case .undo: return .undo
        case .redo: return .redo
        case .discard: return .discard
        case .copy: return .copyImage
        default: return .done
        }
    }
    var symbol: String {
        if let tool { return tool.symbol }
        switch self {
        case .color: return "square.fill"
        case .rotate: return "rotate.left"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .discard: return "trash"
        case .copy: return "doc.on.doc"
        default: return "checkmark.circle.fill"
        }
    }
    static func normalized(_ order: [ToolbarItem]) -> [ToolbarItem] {
        var seen = Set<ToolbarItem>()
        return (order + allCases).filter { seen.insert($0).inserted }
    }
}

@MainActor
final class ToolbarOrderView: NSView {
    private(set) var order = ToolbarItem.allCases
    var changed: ([ToolbarItem]) -> Void = { _ in }
    private var buttons: [ToolbarItem: OrderButton] = [:]
    private var original: [ToolbarItem]?
    private var dragged: ToolbarItem?
    private var origin = CGPoint.zero
    private var didDrag = false
    private let step: CGFloat = 36

    override init(frame: NSRect) {
        super.init(frame: frame)
        for item in ToolbarItem.allCases {
            let button = OrderButton(); button.item = item; button.owner = self
            button.identifier = .init(item.rawValue); button.imagePosition = .imageOnly
            button.bezelStyle = .recessed; button.showsBorderOnlyWhileMouseInside = true
            button.contentTintColor = .secondaryLabelColor
            button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
            if item == .done {
                let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
                    .applying(.init(paletteColors: [.white, .systemGreen]))
                button.image = button.image?.withSymbolConfiguration(configuration)
                button.image?.isTemplate = false; button.contentTintColor = nil
            }
            addSubview(button); buttons[item] = button
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: step * CGFloat(order.count) - 4, height: 40) }
    private var startX: CGFloat { max(0, (bounds.width - intrinsicContentSize.width) / 2) }
    override func layout() {
        super.layout()
        for (index, item) in order.enumerated() {
            buttons[item]?.frame = CGRect(x: startX + CGFloat(index) * step, y: (bounds.height - 32) / 2, width: 32, height: 32)
        }
        setAccessibilityChildren(NSAccessibility.unignoredChildren(from: order.compactMap { buttons[$0] }))
    }
    func reload(_ order: [ToolbarItem], color: NSColor, language: InterfaceLanguage) {
        cancelDrag(); self.order = ToolbarItem.normalized(order); needsLayout = true
        for (item, button) in buttons {
            let label = localized(item.labelKey, language: language)
            button.toolTip = label; button.setAccessibilityLabel(label)
            button.setAccessibilityHelp(localized(.toolbarOrderHint, language: language))
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: localized(.moveLeft, language: language)) { [weak self] in self?.move(item, by: -1) ?? false },
                NSAccessibilityCustomAction(name: localized(.moveRight, language: language)) { [weak self] in self?.move(item, by: 1) ?? false }
            ])
        }
        buttons[.color]?.image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            color.setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill(); return true
        }
        buttons[.color]?.contentTintColor = nil
    }
    @discardableResult func move(_ item: ToolbarItem, by offset: Int) -> Bool {
        guard let index = order.firstIndex(of: item), order.indices.contains(index + offset) else { return false }
        order.remove(at: index); order.insert(item, at: index + offset); needsLayout = true; changed(order); return true
    }
    fileprivate func begin(_ item: ToolbarItem, at point: CGPoint) {
        original = order; dragged = item; origin = point; didDrag = false
    }
    fileprivate func drag(to point: CGPoint) {
        guard let item = dragged, let from = order.firstIndex(of: item) else { return }
        guard didDrag || hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        didDrag = true
        let to = min(order.count - 1, max(0, Int(((point.x - startX - 16) / step).rounded())))
        if from != to { order.remove(at: from); order.insert(item, at: to); needsLayout = true; layoutSubtreeIfNeeded() }
    }
    fileprivate func end(at point: CGPoint) {
        guard let original else { return }
        let accepted = didDrag && bounds.contains(point)
        if !accepted { order = original }
        self.original = nil; dragged = nil; didDrag = false; needsLayout = true
        if accepted && order != original { changed(order) }
    }
    fileprivate func cancelDrag() {
        if let original { order = original; needsLayout = true }
        original = nil; dragged = nil; didDrag = false
        buttons.values.forEach { $0.highlight(false) }
    }
}

@MainActor
private final class OrderButton: NSButton {
    var item: ToolbarItem = .select
    weak var owner: ToolbarOrderView?
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        window?.makeFirstResponder(self); highlight(true)
        owner.begin(item, at: owner.convert(event.locationInWindow, from: nil))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let owner else { return }; owner.drag(to: owner.convert(event.locationInWindow, from: nil))
    }
    override func mouseUp(with event: NSEvent) {
        guard let owner else { return }; highlight(false); owner.end(at: owner.convert(event.locationInWindow, from: nil))
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: owner?.move(item, by: -1)
        case 124: owner?.move(item, by: 1)
        case 53: owner?.cancelDrag()
        default: super.keyDown(with: event)
        }
    }
}
