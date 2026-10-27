import AppKit

@MainActor
private final class ToolButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        if state == .on || isHighlighted {
            // Four open corners leave the tool symbol and its color unobscured.
            NSColor.secondaryLabelColor.setStroke()
            let box = bounds.insetBy(dx: 1.5, dy: 1.5), corner: CGFloat = 7, radius: CGFloat = 3
            let path = NSBezierPath(); path.lineWidth = isHighlighted ? 1.75 : 1.5; path.lineCapStyle = .round
            for (x, y, sx, sy) in [(box.minX, box.minY, 1.0, 1.0), (box.maxX, box.minY, -1.0, 1.0),
                                    (box.minX, box.maxY, 1.0, -1.0), (box.maxX, box.maxY, -1.0, -1.0)] {
                let edge = CGPoint(x: x + sx * radius, y: y)
                path.move(to: CGPoint(x: x + sx * corner, y: y)); path.line(to: edge)
                path.curve(to: CGPoint(x: x, y: y + sy * radius),
                           controlPoint1: CGPoint(x: x + sx * radius * 0.45, y: y),
                           controlPoint2: CGPoint(x: x, y: y + sy * radius * 0.45))
                path.line(to: CGPoint(x: x, y: y + sy * corner))
            }
            path.stroke()
        }
        super.draw(dirtyRect)
    }
}

@MainActor
final class EditorWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let canvas: EditorCanvas
    var closed: () -> Void = {}
    private var toolButtons: [DrawingTool: NSButton] = [:]
    private var toolMenuItems: [DrawingTool: NSMenuItem] = [:]
    private var itemViews: [String: NSView] = [:]
    private var didFitImage = false
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private let preferences: EditorPreferences
    private let titleKey: UIString?
    private let toolbarLabels = Dictionary(uniqueKeysWithValues: ToolbarItem.allCases.map { ($0.rawValue, $0.labelKey) })
    private var restoringPosition = true

    init(image: CGImage, title: String, titleKey: UIString? = nil, preferences: EditorPreferences = EditorPreferences(), pasteboard: NSPasteboard = .general) {
        self.preferences = preferences; self.titleKey = titleKey
        canvas = EditorCanvas(document: EditorDocument(image: image), pasteboard: pasteboard, preferences: preferences)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        canvas.tool = preferences.tool; canvas.color = preferences.color
        window.title = title; window.titlebarAppearsTransparent = true; window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false; window.delegate = self; window.contentView = canvas
        for tool in [DrawingTool.select, .rectangle, .ellipse, .arrow, .pen, .text, .mosaic, .crop] {
            let button = icon(tool.symbol, tool.label, #selector(chooseTool(_:)), isTool: true)
            button.identifier = .init(tool.rawValue)
            button.setButtonType(.pushOnPushOff)
            button.isBordered = false
            // AppKit's selected/pressed bezel can follow the icon shape and accent color.
            // Draw neutral corner brackets while retaining native button behavior.
            (button.cell as? NSButtonCell)?.showsStateBy = []
            (button.cell as? NSButtonCell)?.highlightsBy = []
            button.setAccessibilityRole(.radioButton)
            toolButtons[tool] = button
        }
        let well = NSColorWell(); well.colorWellStyle = .minimal; well.color = canvas.color
        well.target = self; well.action = #selector(chooseColor(_:)); well.setAccessibilityLabel(localized(.annotationColor))
        NSLayoutConstraint.activate([well.widthAnchor.constraint(equalToConstant: 24), well.heightAnchor.constraint(equalToConstant: 24)])
        undoButton = icon("arrow.uturn.backward", localized(.undo), #selector(undo)); redoButton = icon("arrow.uturn.forward", localized(.redo), #selector(redo))
        let done = icon("checkmark.circle.fill", localized(.done), #selector(done))
        let completionSymbol = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            .applying(.init(paletteColors: [.white, .systemGreen]))
        done.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: localized(.done))?
            .withSymbolConfiguration(completionSymbol)
        done.image?.isTemplate = false
        done.contentTintColor = nil; done.imagePosition = .imageOnly
        done.keyEquivalent = "\r"; done.keyEquivalentModifierMask = [.command]
        done.toolTip = localized(.copyAndClose)
        itemViews = Dictionary(uniqueKeysWithValues: toolButtons.map { ($0.key.rawValue.lowercased(), $0.value as NSView) })
        itemViews.merge(["color": well, "undo": undoButton!, "redo": redoButton!,
                         "rotate": icon("rotate.left", localized(.rotateImage), #selector(rotateImage)),
                         "copy": icon("doc.on.doc", localized(.copyImage), #selector(copyImage)),
                         "discard": icon("trash", localized(.discard), #selector(discard)), "done": done]) { _, new in new }
        let toolbar = NSToolbar(identifier: "SicGo.Editor")
        toolbar.displayMode = .iconOnly; toolbar.delegate = self
        // The app preference is the single source of truth for toolbar ordering.
        toolbar.autosavesConfiguration = false; window.toolbar = toolbar
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onCopy = { [weak self] in self?.copyImage() }
        refresh()
        if let point = preferences.windowTopLeft, let screen = rememberedScreen {
            window.setFrameTopLeftPoint(EditorPreferences.visibleTopLeft(point, windowSize: window.frame.size, screen: screen.visibleFrame))
        } else { window.center() }
        restoringPosition = false; window.makeFirstResponder(canvas)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var rememberedScreen: NSScreen? {
        if let point = preferences.windowTopLeft,
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(point) }) { return screen }
        return NSScreen.main
    }
    private func icon(_ symbol: String, _ label: String, _ action: Selector, isTool: Bool = false) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)!
        let button = isTool ? ToolButton(image: image, target: self, action: action) : NSButton(image: image, target: self, action: action)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        button.bezelStyle = .recessed; button.showsBorderOnlyWhileMouseInside = true
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label; button.setAccessibilityLabel(label)
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 32), button.heightAnchor.constraint(equalToConstant: 32)])
        return button
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + preferences.toolbarOrder.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard let view = itemViews[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        // Keep the color well's compact style instead of the toolbar's automatic bezel.
        item.view = view is NSColorWell ? NSStackView(views: [view]) : view
        item.label = toolbarLabels[id.rawValue].map { localized($0) } ?? id.rawValue
        item.paletteLabel = item.label
        // Every item has a native overflow action, even after it is reordered.
        let menuItem = NSMenuItem(title: item.label, action: nil, keyEquivalent: "")
        if let button = view as? NSButton {
            menuItem.target = self; menuItem.action = button.action; menuItem.image = button.image
            if let value = button.identifier?.rawValue, let tool = DrawingTool(rawValue: value) {
                menuItem.representedObject = value; toolMenuItems[tool] = menuItem
            }
        } else if view is NSColorWell {
            menuItem.target = self; menuItem.action = #selector(showColor)
        }
        item.menuFormRepresentation = menuItem
        if ToolbarItem(rawValue: id.rawValue)?.tool != nil { item.visibilityPriority = .high }
        if id.rawValue == "done" { item.visibilityPriority = .user }
        return item
    }
    func updateLocalization() {
        if let titleKey { window?.title = localized(titleKey) }
        canvas.updateLocalization()
        for (tool, button) in toolButtons { button.toolTip = tool.label; button.setAccessibilityLabel(tool.label) }
        for (id, key) in toolbarLabels {
            guard let view = itemViews[id] else { continue }
            let label = localized(key); view.toolTip = label; view.setAccessibilityLabel(label)
        }
        itemViews["color"]?.setAccessibilityLabel(localized(.annotationColor))
        itemViews["done"]?.toolTip = localized(.copyAndClose)
        undoButton.toolTip = localized(.undo); undoButton.setAccessibilityLabel(localized(.undo))
        redoButton.toolTip = localized(.redo); redoButton.setAccessibilityLabel(localized(.redo))
        for item in window?.toolbar?.items ?? [] {
            if let key = toolbarLabels[item.itemIdentifier.rawValue] {
                item.label = localized(key); item.paletteLabel = item.label; item.menuFormRepresentation?.title = item.label
            }
        }
    }
    func applyToolbarOrder() {
        guard let toolbar = window?.toolbar else { return }
        let order = toolbarDefaultItemIdentifiers(toolbar)
        guard toolbar.items.map(\.itemIdentifier) != order else { return }
        for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
        toolMenuItems.removeAll()
        for (index, id) in order.enumerated() { toolbar.insertItem(withItemIdentifier: id, at: index) }
        refresh()
    }
    private func refresh() {
        undoButton?.isEnabled = canvas.document.canUndo; redoButton?.isEnabled = canvas.document.canRedo
        for (tool, button) in toolButtons {
            button.state = tool == canvas.tool ? .on : .off
            button.setAccessibilityValue(tool == canvas.tool ? 1 : 0)
            toolMenuItems[tool]?.state = button.state
        }
        guard !didFitImage, let window else { return }
        let image = canvas.document.size
        let screen = (restoringPosition ? rememberedScreen : window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let factor = min(1, screen.width * 0.82 / image.width, max(100, screen.height - 100) / image.height)
        let minimum = min(factor, 380 / image.width, 220 / image.height)
        window.contentMinSize = CGSize(width: image.width * minimum, height: image.height * minimum)
        window.setContentSize(CGSize(width: image.width * factor, height: image.height * factor))
        didFitImage = true
    }
    @objc private func chooseTool(_ sender: Any) {
        let value = (sender as? NSButton)?.identifier?.rawValue ?? (sender as? NSMenuItem)?.representedObject as? String
        guard let value, let tool = DrawingTool(rawValue: value) else { return }
        canvas.tool = tool; preferences.tool = tool; refresh(); window?.makeFirstResponder(canvas)
    }
    @objc private func showColor() { (itemViews["color"] as? NSColorWell)?.activate(true) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo) { return canvas.document.canUndo }
        if menuItem.action == #selector(redo) { return canvas.document.canRedo }
        return true
    }
    @objc private func chooseColor(_ sender: NSColorWell) { canvas.changeColor(sender.color); preferences.color = sender.color }
    @objc private func undo() { canvas.undo() }
    @objc private func redo() { canvas.redo() }
    @objc private func rotateImage() { canvas.rotateImage() }
    private func writeClipboard() -> Bool {
        canvas.finishText()
        guard let image = Drawing.render(canvas.document.state.image, marks: canvas.document.state.marks) else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        let item = NSPasteboardItem(); item.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        canvas.pasteboard.clearContents()
        return canvas.pasteboard.writeObjects([item])
    }
    @objc private func copyImage() {
        if !writeClipboard() {
            let alert = NSAlert(); alert.messageText = localized(.copyFailed)
            alert.addButton(withTitle: localized(.ok)); alert.runModal()
        }
    }
    @objc private func done() { if writeClipboard() { window?.close() } }
    @objc private func discard() { window?.close() }
    func windowDidMove(_ notification: Notification) { rememberPosition() }
    func windowDidEndLiveResize(_ notification: Notification) { rememberPosition() }
    private func rememberPosition() {
        guard !restoringPosition, let window, window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
        preferences.windowTopLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
    }
    func windowDidResignKey(_ notification: Notification) { canvas.finishText(restoreFocus: false); canvas.releaseCursor() }
    func windowWillClose(_ notification: Notification) { canvas.releaseCursor(); closed() }
}
