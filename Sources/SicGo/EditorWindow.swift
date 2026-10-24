import AppKit

@MainActor
final class EditorWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let canvas: EditorCanvas
    var closed: () -> Void = {}
    private var toolButtons: [DrawingTool: NSButton] = [:]
    private var itemViews: [String: NSView] = [:]
    private var fittedSize = CGSize.zero
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private let preferences: EditorPreferences
    private let titleKey: UIString?
    private let toolbarLabels: [String: UIString] = ["tools": .tools, "color": .color, "history": .history,
        "rotate": .rotateImage, "copy": .copyImage, "discard": .discard, "done": .done]
    private var restoringPosition = true

    init(image: CGImage, title: String, titleKey: UIString? = nil, preferences: EditorPreferences = EditorPreferences()) {
        self.preferences = preferences; self.titleKey = titleKey
        canvas = EditorCanvas(document: EditorDocument(image: image))
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        canvas.tool = preferences.startingTool; canvas.color = preferences.startingColor
        window.title = title; window.titlebarAppearsTransparent = true; window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false; window.delegate = self; window.contentView = canvas
        let palette = NSStackView(); palette.spacing = 3
        for tool in [DrawingTool.rectangle, .ellipse, .arrow, .pen, .text, .mosaic, .crop, .select] {
            let button = icon(tool.symbol, tool.label, #selector(chooseTool(_:)))
            button.identifier = .init(tool.rawValue)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            toolButtons[tool] = button; palette.addArrangedSubview(button)
        }
        let well = NSColorWell(); well.colorWellStyle = .minimal; well.color = canvas.color
        well.target = self; well.action = #selector(chooseColor(_:)); well.setAccessibilityLabel(localized(.annotationColor))
        well.frame.size = CGSize(width: 28, height: 24)
        undoButton = icon("arrow.uturn.backward", localized(.undo), #selector(undo)); redoButton = icon("arrow.uturn.forward", localized(.redo), #selector(redo))
        let history = NSStackView(views: [undoButton, redoButton]); history.spacing = 2
        let done = NSButton(title: localized(.done), target: self, action: #selector(done))
        done.bezelStyle = .rounded; done.keyEquivalent = "\r"; done.keyEquivalentModifierMask = [.command]
        done.toolTip = localized(.copyAndClose)
        itemViews = ["tools": palette, "color": well, "history": history,
                     "rotate": icon("rotate.left", localized(.rotateImage), #selector(rotateImage)),
                     "copy": icon("doc.on.doc", localized(.copyImage), #selector(copyImage)),
                     "discard": icon("trash", localized(.discard), #selector(discard)), "done": done]
        let toolbar = NSToolbar(identifier: "SicGo.Editor")
        toolbar.displayMode = .iconOnly; toolbar.delegate = self; toolbar.autosavesConfiguration = true; window.toolbar = toolbar
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
    private func icon(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: action)
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        button.isBordered = false; button.toolTip = label; button.setAccessibilityLabel(label)
        return button
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ["tools", "color", "history", "rotate", NSToolbarItem.Identifier.flexibleSpace.rawValue, "discard", "copy", "done"].map { NSToolbarItem.Identifier($0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        guard let view = itemViews[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id); item.view = view
        item.label = toolbarLabels[id.rawValue].map { localized($0) } ?? id.rawValue
        item.paletteLabel = item.label
        if id.rawValue == "tools" { item.visibilityPriority = .high }
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
        if let done = itemViews["done"] as? NSButton { done.title = localized(.done); done.toolTip = localized(.copyAndClose) }
        undoButton.toolTip = localized(.undo); undoButton.setAccessibilityLabel(localized(.undo))
        redoButton.toolTip = localized(.redo); redoButton.setAccessibilityLabel(localized(.redo))
        for item in window?.toolbar?.items ?? [] {
            if let key = toolbarLabels[item.itemIdentifier.rawValue] { item.label = localized(key); item.paletteLabel = item.label }
        }
    }
    private func refresh() {
        undoButton?.isEnabled = canvas.document.canUndo; redoButton?.isEnabled = canvas.document.canRedo
        for (tool, button) in toolButtons { button.contentTintColor = tool == canvas.tool ? .controlAccentColor : .secondaryLabelColor }
        guard fittedSize != canvas.document.size, let window else { return }
        let image = canvas.document.size
        let screen = (restoringPosition ? rememberedScreen : window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let factor = min(1, screen.width * 0.82 / image.width, max(100, screen.height - 100) / image.height)
        let minimum = min(factor, 380 / image.width, 220 / image.height)
        window.contentAspectRatio = image
        window.contentMinSize = CGSize(width: image.width * minimum, height: image.height * minimum)
        window.setContentSize(CGSize(width: image.width * factor, height: image.height * factor))
        fittedSize = image
    }
    @objc private func chooseTool(_ sender: NSButton) {
        guard let value = sender.identifier?.rawValue, let tool = DrawingTool(rawValue: value) else { return }
        canvas.tool = tool; preferences.tool = tool; refresh(); window?.makeFirstResponder(canvas)
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
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
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
