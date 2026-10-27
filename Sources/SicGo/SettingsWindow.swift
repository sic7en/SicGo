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
final class SettingsWindow: NSWindowController, NSWindowDelegate, NSMenuDelegate {
    private let preferences: EditorPreferences
    private let loginItem: any LoginItemManaging
    private var labels: [UIString: NSTextField] = [:]
    private var buttons: [UIString: NSButton] = [:]
    private var switches: [UIString: NSSwitch] = [:]
    private let stack = NSStackView()
    private let loginNotice = NSStackView()
    private let updater: UpdateChecker
    let updateButton = NSButton()
    let downloadButton = NSButton()
    let updateStatus = NSTextField(wrappingLabelWithString: "")
    private let updateProgress = NSProgressIndicator()
    let languagePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let fontPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let toolbarOrderView = ToolbarOrderView(frame: .zero)
    private var fontsLoaded = false
    let launchButton = NSSwitch()
    let showHomeButton = NSSwitch()
    var languageChanged: () -> Void = {}
    var toolbarOrderChanged: () -> Void = {}
    var reportLoginError: ((Error) -> Void)?

    init(preferences: EditorPreferences = EditorPreferences(), loginItem: (any LoginItemManaging)? = nil,
         updater: UpdateChecker? = nil) {
        self.preferences = preferences; self.loginItem = loginItem ?? SystemLoginItem(); self.updater = updater ?? UpdateChecker()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true; window.delegate = self
        window.backgroundColor = .controlBackgroundColor
        languagePicker.target = self; languagePicker.action = #selector(chooseLanguage)
        for language in InterfaceLanguage.allCases {
            languagePicker.addItem(withTitle: language.rawValue)
            languagePicker.lastItem?.representedObject = language.rawValue
        }
        fontPicker.target = self; fontPicker.action = #selector(chooseFont); fontPicker.menu?.delegate = self
        for picker in [languagePicker, fontPicker] { picker.widthAnchor.constraint(equalToConstant: 176).isActive = true }
        configure(launchButton, .launchAtLogin, #selector(chooseLaunchAtLogin))
        configure(showHomeButton, .showHomeOnLaunch, #selector(chooseShowHome))
        let approval = label(.loginApproval, hint: true)
        let loginSettings = NSButton(title: "", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded; loginSettings.controlSize = .small; buttons[.loginSettings] = loginSettings
        loginNotice.orientation = .vertical; loginNotice.alignment = .leading; loginNotice.spacing = 8
        loginNotice.addArrangedSubview(approval); loginNotice.addArrangedSubview(loginSettings)
        let general = group(.general, views: [row(.language, languagePicker), separator(),
            row(.launchAtLogin, launchButton), loginNotice, row(.showHomeOnLaunch, showHomeButton)])
        let resetOrder = NSButton(title: "", target: self, action: #selector(resetToolbarOrder))
        resetOrder.bezelStyle = .rounded; resetOrder.controlSize = .small; buttons[.resetOrder] = resetOrder
        let orderHeader = NSStackView(views: [label(.toolbarOrder), NSView(), resetOrder]); orderHeader.spacing = 12
        let orderHint = label(.toolbarOrderHint, hint: true)
        let orderPanel = NSStackView(views: [orderHeader, toolbarOrderView, orderHint])
        orderPanel.orientation = .vertical; orderPanel.alignment = .leading; orderPanel.spacing = 8
        for view in orderPanel.arrangedSubviews { view.widthAnchor.constraint(equalTo: orderPanel.widthAnchor).isActive = true }
        toolbarOrderView.changed = { [weak self] order in
            guard let self else { return }
            self.preferences.toolbarOrder = order
            self.buttons[.resetOrder]?.isEnabled = order != ToolbarItem.allCases
            self.toolbarOrderChanged()
        }
        let annotation = group(.annotationSettings, views: [orderPanel, row(.textFont, fontPicker, hint: .newTextOnly)])
        let emblem = NSImageView(image: NSImage(systemSymbolName: "viewfinder", accessibilityDescription: nil)!)
        emblem.symbolConfiguration = .init(pointSize: 32, weight: .light); emblem.contentTintColor = .secondaryLabelColor
        let heading = NSTextField(labelWithString: "SicGo"); heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let introduction = NSStackView(views: [heading, label(.settingsDescription, hint: true)])
        introduction.orientation = .vertical; introduction.alignment = .leading; introduction.spacing = 4
        let header = NSStackView(views: [emblem, introduction]); header.spacing = 16; header.alignment = .centerY
        let version = NSTextField(labelWithString: "SicGo \(UpdateService.currentVersion) (\(UpdateService.currentBuild)) · Sic7en")
        version.font = .systemFont(ofSize: 12); version.textColor = .secondaryLabelColor
        updateButton.target = self; updateButton.action = #selector(checkForUpdates)
        downloadButton.target = self; downloadButton.action = #selector(openUpdate)
        for button in [updateButton, downloadButton] { button.bezelStyle = .rounded; button.controlSize = .small }
        updateProgress.style = .spinning; updateProgress.controlSize = .small; updateProgress.isDisplayedWhenStopped = false
        let updateActions = NSStackView(views: [version, NSView(), updateProgress, updateButton, downloadButton])
        updateActions.spacing = 8; updateActions.alignment = .centerY; updateActions.detachesHiddenViews = true
        updateStatus.font = .systemFont(ofSize: 12); updateStatus.textColor = .secondaryLabelColor
        let updates = NSStackView(views: [separator(), updateActions, updateStatus])
        updates.orientation = .vertical; updates.alignment = .leading; updates.spacing = 12
        for view in updates.arrangedSubviews { view.widthAnchor.constraint(equalTo: updates.widthAnchor).isActive = true }
        self.updater.changed = { [weak self] in self?.refreshUpdateStatus() }
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, general, annotation, updates] { stack.addArrangedSubview(view) }
        let content = NSView(); window.contentView = content; content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 32),
            general.widthAnchor.constraint(equalTo: stack.widthAnchor),
            annotation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            updates.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        updateLocalization(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ control: NSSwitch, _ key: UIString, _ action: Selector) {
        control.target = self; control.action = action; switches[key] = control
    }
    private func label(_ key: UIString, hint: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = .systemFont(ofSize: hint ? 12 : 13)
        field.textColor = hint ? .secondaryLabelColor : .labelColor; labels[key] = field
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    private func row(_ key: UIString, _ control: NSView, hint: UIString? = nil) -> NSStackView {
        let text = NSStackView(views: [label(key)])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 4
        if let hint { text.addArrangedSubview(label(hint, hint: true)) }
        for field in text.arrangedSubviews { field.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true }
        let row = NSStackView(views: [text, control]); row.spacing = 16
        row.alignment = .centerY; row.distribution = .fill
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return row
    }
    private func separator() -> NSBox { let line = NSBox(); line.boxType = .separator; return line }
    private func group(_ key: UIString, views: [NSView]) -> NSStackView {
        let body = NSStackView(views: views); body.orientation = .vertical; body.alignment = .leading
        body.spacing = 0; body.detachesHiddenViews = true
        for view in views where view is NSStackView || view is NSBox {
            view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        let heading = label(key); heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        let group = NSStackView(views: [heading, body]); group.orientation = .vertical
        group.alignment = .leading; group.spacing = 12
        body.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }
    func updateLocalization() {
        let language = preferences.language
        window?.title = localized(.settings, language: language)
        for (key, field) in labels { field.stringValue = localized(key, language: language) }
        for (key, button) in buttons { button.title = localized(key, language: language) }
        for (key, control) in switches { control.setAccessibilityLabel(localized(key, language: language)) }
        languagePicker.setAccessibilityLabel(localized(.language, language: language))
        fontPicker.setAccessibilityLabel(localized(.textFont, language: language))
        for item in languagePicker.itemArray {
            switch item.representedObject as? String {
            case InterfaceLanguage.system.rawValue: item.title = localized(.followSystem, language: language)
            case InterfaceLanguage.english.rawValue: item.title = "English"
            default: item.title = "简体中文"
            }
        }
        refreshUpdateStatus(); refreshPreferences()
    }
    func refreshPreferences() {
        languagePicker.selectItem(at: InterfaceLanguage.allCases.firstIndex(of: preferences.language)!)
        showHomeButton.state = preferences.showHomeOnLaunch ? .on : .off
        toolbarOrderView.reload(preferences.toolbarOrder, color: preferences.color, language: preferences.language)
        buttons[.resetOrder]?.isEnabled = preferences.toolbarOrder != ToolbarItem.allCases
        updateFontSelection()
        let status = loginItem.status
        launchButton.state = status == .enabled || status == .requiresApproval ? .on : .off
        loginNotice.isHidden = status != .requiresApproval
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(CGSize(width: 640, height: stack.fittingSize.height + 64))
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshPreferences() }
    @objc func checkForUpdates() { updater.check() }
    @objc private func openUpdate() {
        guard case .available(let release) = updater.state else { return }
        NSWorkspace.shared.open(release.url)
    }
    private func refreshUpdateStatus() {
        let language = preferences.language
        updateButton.title = localized(.checkForUpdates, language: language)
        downloadButton.title = localized(.downloadUpdate, language: language)
        updateButton.isEnabled = updater.state != .checking
        downloadButton.isHidden = true
        updateProgress.isHidden = updater.state != .checking
        if updater.state == .checking { updateProgress.startAnimation(nil) } else { updateProgress.stopAnimation(nil) }
        let message: UIString
        switch updater.state {
        case .idle: message = .updateHint
        case .checking: message = .checkingUpdates
        case .current: message = .upToDate
        case .available(let release):
            downloadButton.isHidden = false
            updateStatus.stringValue = String(format: localized(.updateAvailable, language: language), release.version)
            resizeToFit(); return
        case .failed(let error):
            switch error {
            case .unavailable: message = .updateUnavailable
            case .rateLimited: message = .updateRateLimited
            case .invalidResponse: message = .updateInvalid
            case .network: message = .updateNetworkError
            }
        }
        updateStatus.stringValue = localized(message, language: language)
        resizeToFit()
    }
    private func resizeToFit() {
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(CGSize(width: 640, height: stack.fittingSize.height + 64))
    }
    @objc private func chooseLanguage() {
        guard let value = languagePicker.selectedItem?.representedObject as? String,
              let language = InterfaceLanguage(rawValue: value) else { return }
        preferences.language = language
        updateLocalization(); languageChanged()
    }
    @objc private func resetToolbarOrder() {
        preferences.toolbarOrder = ToolbarItem.allCases
        refreshPreferences(); toolbarOrderChanged()
    }
    private func updateFontSelection() {
        let family = preferences.textFontName.flatMap { NSFont(name: $0, size: 13)?.familyName }
        if !fontsLoaded {
            fontPicker.removeAllItems()
            fontPicker.addItem(withTitle: localized(.systemFont, language: preferences.language))
            if let family { fontPicker.addItem(withTitle: family); fontPicker.lastItem?.representedObject = family }
        }
        fontPicker.item(at: 0)?.title = localized(.systemFont, language: preferences.language)
        let selected = fontPicker.itemArray.first { !$0.isSeparatorItem && ($0.representedObject as? String) == family }
        fontPicker.select(selected ?? fontPicker.item(at: 0))
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === fontPicker.menu, !fontsLoaded else { return }
        // Load installed family names only when the picker is opened. No fonts are bundled.
        fontsLoaded = true; fontPicker.removeAllItems()
        fontPicker.addItem(withTitle: localized(.systemFont, language: preferences.language))
        menu.addItem(.separator())
        for family in NSFontManager.shared.availableFontFamilies.filter({ !$0.hasPrefix(".") }).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            fontPicker.addItem(withTitle: family); fontPicker.lastItem?.representedObject = family
        }
        updateFontSelection()
    }
    @objc private func chooseFont() {
        if let family = fontPicker.selectedItem?.representedObject as? String {
            guard let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 30) else { updateFontSelection(); return }
            preferences.textFontName = font.fontName
        } else { preferences.textFontName = nil }
        updateFontSelection()
    }
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
