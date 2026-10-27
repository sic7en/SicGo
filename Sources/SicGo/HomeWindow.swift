import AppKit

@MainActor
final class HomeWindow: NSWindowController {
    var capture: () -> Void = {}
    var openImage: () -> Void = {}
    var pasteImage: () -> Void = {}
    var openSettings: () -> Void = {}
    private var buttons: [UIString: NSButton] = [:]
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let statusIcon = NSImageView()

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 300),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "SicGo"; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.backgroundColor = .controlBackgroundColor
        let emblem = NSImageView(image: NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)!)
        emblem.symbolConfiguration = .init(pointSize: 36, weight: .light); emblem.contentTintColor = .secondaryLabelColor
        emblem.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let title = NSTextField(labelWithString: "SicGo"); title.font = .systemFont(ofSize: 24, weight: .semibold)
        descriptionLabel.font = .systemFont(ofSize: 13); descriptionLabel.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, descriptionLabel]); heading.orientation = .vertical
        heading.alignment = .leading; heading.spacing = 4
        let header = NSStackView(views: [emblem, heading]); header.spacing = 16; header.alignment = .centerY

        let capture = button(.systemScreenshot, "viewfinder", #selector(captureAction))
        capture.controlSize = .large; capture.keyEquivalent = "\r"
        capture.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let open = button(.openImage, "photo", #selector(openAction))
        let paste = button(.fromClipboard, "clipboard", #selector(pasteAction))
        for button in [open, paste] { button.controlSize = .large; button.heightAnchor.constraint(equalToConstant: 36).isActive = true }
        let imports = NSStackView(views: [open, paste]); imports.distribution = .fillEqually; imports.spacing = 12
        shortcutLabel.font = .systemFont(ofSize: 12); shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .center
        let actions = NSStackView(views: [capture, imports, shortcutLabel]); actions.orientation = .vertical
        actions.spacing = 12; actions.alignment = .centerX
        for view in actions.arrangedSubviews { view.widthAnchor.constraint(equalTo: actions.widthAnchor).isActive = true }

        statusLabel.font = .systemFont(ofSize: 11); statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusIcon.symbolConfiguration = .init(pointSize: 6, weight: .regular)
        let settings = button(.settingsMenu, "gearshape", #selector(settingsAction))
        settings.imagePosition = .imageOnly; settings.isBordered = false
        settings.widthAnchor.constraint(equalToConstant: 28).isActive = true
        settings.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let footer = NSStackView(views: [statusIcon, statusLabel, NSView(), settings]); footer.spacing = 8
        footer.distribution = .fill; footer.alignment = .centerY
        let line = NSBox(); line.boxType = .separator
        let stack = NSStackView(views: [header, actions, line, footer]); stack.orientation = .vertical
        stack.alignment = .leading; stack.spacing = 24; stack.setCustomSpacing(8, after: line)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); window.contentView = content; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        for view in [actions, line, footer] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        updateLocalization(receptionAvailable: true)
        window.center(); window.setFrameUsingName("SicGo.Home"); window.setContentSize(CGSize(width: 420, height: 300))
        window.setFrameAutosaveName("SicGo.Home")
    }
    required init?(coder: NSCoder) { fatalError() }
    private func button(_ key: UIString, _ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.bezelStyle = .rounded; button.font = .systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        button.imagePosition = .imageLeading; buttons[key] = button
        return button
    }
    func updateLocalization(receptionAvailable: Bool) {
        descriptionLabel.stringValue = localized(.homeDescription)
        shortcutLabel.stringValue = localized(.captureShortcut)
        statusLabel.stringValue = localized(receptionAvailable ? .receptionHint : .receptionUnavailable)
        statusIcon.image = NSImage(systemSymbolName: receptionAvailable ? "circle.fill" : "exclamationmark.circle", accessibilityDescription: nil)
        statusIcon.contentTintColor = receptionAvailable ? .systemGreen : .systemOrange
        for (key, button) in buttons {
            button.title = key == .settingsMenu ? "" : localized(key)
            button.toolTip = localized(key); button.setAccessibilityLabel(localized(key))
        }
    }
    @objc private func captureAction() { capture() }
    @objc private func openAction() { openImage() }
    @objc private func pasteAction() { pasteImage() }
    @objc private func settingsAction() { openSettings() }
}
