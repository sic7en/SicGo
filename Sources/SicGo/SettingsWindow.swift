import AppKit
import ServiceManagement

@MainActor
protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
private struct SystemLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
        } else if status == .enabled || status == .requiresApproval {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let preferences: EditorPreferences
    private let loginItem: any LoginItemManaging
    private var labels: [UIString: NSTextField] = [:]
    private var buttons: [UIString: NSButton] = [:]
    private let stack = NSStackView()
    let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let toolPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let colorWell = NSColorWell()
    let rememberButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let launchButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let showHomeButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    var languageChanged: () -> Void = {}
    var reportLoginError: ((Error) -> Void)?

    init(preferences: EditorPreferences = EditorPreferences(), loginItem: (any LoginItemManaging)? = nil) {
        self.preferences = preferences; self.loginItem = loginItem ?? SystemLoginItem()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 470),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true; window.delegate = self
        languagePicker.target = self; languagePicker.action = #selector(chooseLanguage)
        for language in InterfaceLanguage.allCases {
            languagePicker.addItem(withTitle: language.rawValue)
            languagePicker.lastItem?.representedObject = language.rawValue
        }
        toolPicker.target = self; toolPicker.action = #selector(chooseTool)
        for tool in DrawingTool.allCases {
            toolPicker.addItem(withTitle: tool.rawValue)
            toolPicker.lastItem?.representedObject = tool.rawValue
            toolPicker.lastItem?.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
        }
        for picker in [languagePicker, toolPicker] { picker.widthAnchor.constraint(equalToConstant: 190).isActive = true }
        colorWell.colorWellStyle = .minimal; colorWell.target = self; colorWell.action = #selector(chooseColor)
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 25).isActive = true
        configure(launchButton, .launchAtLogin, #selector(chooseLaunchAtLogin))
        configure(showHomeButton, .showHomeOnLaunch, #selector(chooseShowHome))
        configure(rememberButton, .rememberAnnotation, #selector(chooseRemember))
        let approval = label(.loginApproval, hint: true)
        let loginSettings = NSButton(title: "", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded; loginSettings.controlSize = .small; buttons[.loginSettings] = loginSettings
        let general = group(.general, views: [row(.language, languagePicker), separator(), launchButton, approval, loginSettings, showHomeButton])
        let annotation = group(.annotationSettings, views: [rememberButton, label(.annotationDefaultsHint, hint: true), separator(), row(.defaultTool, toolPicker), row(.defaultColor, colorWell)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [general, annotation, label(.newImagesOnly, hint: true)] { stack.addArrangedSubview(view) }
        let content = NSView(); window.contentView = content; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            general.widthAnchor.constraint(equalTo: stack.widthAnchor),
            annotation.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        updateLocalization(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ button: NSButton, _ key: UIString, _ action: Selector) {
        button.target = self; button.action = action; buttons[key] = button
    }
    private func label(_ key: UIString, hint: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = .systemFont(ofSize: hint ? 12 : 13, weight: hint ? .regular : .medium)
        field.textColor = hint ? .secondaryLabelColor : .labelColor; labels[key] = field
        return field
    }
    private func row(_ key: UIString, _ control: NSView) -> NSStackView {
        let row = NSStackView(views: [label(key), NSView(), control]); row.spacing = 12
        row.alignment = .centerY
        return row
    }
    private func separator() -> NSBox { let line = NSBox(); line.boxType = .separator; return line }
    private func group(_ key: UIString, views: [NSView]) -> NSStackView {
        let box = NSBox(); box.boxType = .custom; box.titlePosition = .noTitle
        box.fillColor = .controlBackgroundColor; box.borderColor = .separatorColor
        box.borderWidth = 0.5; box.cornerRadius = 8; box.contentViewMargins = .zero
        let content = NSView(); box.contentView = content
        let body = NSStackView(views: views); body.orientation = .vertical; body.alignment = .leading
        body.spacing = 12; body.detachesHiddenViews = true; body.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            body.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        for view in views where view is NSStackView || view is NSBox {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        let group = NSStackView(views: [label(key), box]); group.orientation = .vertical
        group.alignment = .leading; group.spacing = 8
        box.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }
    func updateLocalization() {
        let language = preferences.language
        window?.title = localized(.settings, language: language)
        for (key, field) in labels { field.stringValue = localized(key, language: language) }
        for (key, button) in buttons { button.title = localized(key, language: language) }
        languagePicker.setAccessibilityLabel(localized(.language, language: language))
        toolPicker.setAccessibilityLabel(localized(.defaultTool, language: language))
        colorWell.setAccessibilityLabel(localized(.defaultColor, language: language))
        for item in languagePicker.itemArray {
            switch item.representedObject as? String {
            case InterfaceLanguage.system.rawValue: item.title = localized(.followSystem, language: language)
            case InterfaceLanguage.english.rawValue: item.title = "English"
            default: item.title = "简体中文"
            }
        }
        for item in toolPicker.itemArray {
            if let value = item.representedObject as? String, let tool = DrawingTool(rawValue: value) {
                item.title = localized(tool.labelKey, language: language)
            }
        }
        refreshPreferences()
    }
    func refreshPreferences() {
        languagePicker.selectItem(at: InterfaceLanguage.allCases.firstIndex(of: preferences.language)!)
        showHomeButton.state = preferences.showHomeOnLaunch ? .on : .off
        rememberButton.state = preferences.rememberAnnotation ? .on : .off
        toolPicker.selectItem(at: DrawingTool.allCases.firstIndex(of: preferences.defaultTool)!)
        colorWell.color = preferences.defaultColor
        toolPicker.isEnabled = !preferences.rememberAnnotation; colorWell.isEnabled = !preferences.rememberAnnotation
        let status = loginItem.status
        launchButton.state = status == .enabled || status == .requiresApproval ? .on : .off
        labels[.loginApproval]?.isHidden = status != .requiresApproval
        buttons[.loginSettings]?.isHidden = status != .requiresApproval
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(CGSize(width: 500, height: stack.fittingSize.height + 48))
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshPreferences() }
    func windowWillClose(_ notification: Notification) { colorWell.deactivate() }
    @objc private func chooseLanguage() {
        guard let value = languagePicker.selectedItem?.representedObject as? String,
              let language = InterfaceLanguage(rawValue: value) else { return }
        preferences.language = language
        updateLocalization(); languageChanged()
    }
    @objc private func chooseTool() {
        guard let value = toolPicker.selectedItem?.representedObject as? String, let tool = DrawingTool(rawValue: value) else { return }
        preferences.defaultTool = tool
    }
    @objc private func chooseColor() { preferences.defaultColor = colorWell.color }
    @objc private func chooseRemember() { preferences.rememberAnnotation = rememberButton.state == .on; refreshPreferences() }
    @objc private func chooseShowHome() { preferences.showHomeOnLaunch = showHomeButton.state == .on }
    @objc private func chooseLaunchAtLogin() {
        do { try loginItem.setEnabled(launchButton.state == .on) }
        catch {
            if let reportLoginError { reportLoginError(error) }
            else if let window {
                let alert = NSAlert(); alert.messageText = localized(.loginError); alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: localized(.ok)); alert.beginSheetModal(for: window)
            }
        }
        refreshPreferences()
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}
