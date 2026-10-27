import AppKit
import UniformTypeIdentifiers

@main
enum SicGoMain {
    static func main() {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            let delegate = SicGoApp()
            application.delegate = delegate; application.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { application.run() }
        }
    }
}

@MainActor
final class SicGoApp: NSObject, NSApplicationDelegate {
    private let inbox = SystemScreenshotInbox()
    private var signals: [DispatchSourceSignal] = []
    private var home: HomeWindow?
    private var status: NSStatusItem!
    private var editors: [UUID: EditorWindow] = [:]
    private var openingFiles: [URL] = []
    private var ready = false
    private var receptionAvailable = true
    private var settings: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenus()
        inbox.onImage = { [weak self] image, _ in self?.present(image, title: localized(.screenshot), titleKey: .screenshot) }
        inbox.onError = { [weak self] error in self?.report(error) }
        do { try inbox.start() }
        catch { receptionAvailable = false; updateHomeLocalization(); report(error) }
        NotificationCenter.default.addObserver(self, selector: #selector(systemLanguageChanged), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signals.append(source)
        }
        ready = true
        let args = CommandLine.arguments.dropFirst()
        if let flag = args.firstIndex(of: "--open"), args.index(after: flag) < args.endIndex {
            openingFiles.append(URL(fileURLWithPath: args[args.index(after: flag)]))
        }
        if !openingFiles.isEmpty { openingFiles.forEach(open); openingFiles = [] }
        else if EditorPreferences().showHomeOnLaunch { showHome() }
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if ready { urls.forEach(open) } else { openingFiles.append(contentsOf: urls) }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHome() }; return true
    }
    func applicationDidResignActive(_ notification: Notification) { editors.values.forEach { $0.canvas.releaseCursor() } }
    func applicationDidHide(_ notification: Notification) { editors.values.forEach { $0.canvas.releaseCursor() } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        do { try inbox.stop(); return .terminateNow }
        catch { report(error); return .terminateCancel }
    }
    private func command(_ title: String, _ selector: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            item.image?.isTemplate = true
        }
        return item
    }
    private func buildMenus() {
        let main = NSMenu(), app = NSMenu(title: "SicGo"), file = NSMenu(title: localized(.file)), edit = NSMenu(title: localized(.edit))
        app.addItem(command(localized(.about), #selector(about)))
        app.addItem(.separator()); app.addItem(command(localized(.settingsMenu), #selector(showSettings), key: ","))
        app.addItem(command(localized(.checkForUpdates), #selector(checkForUpdates)))
        app.addItem(.separator()); app.addItem(command(localized(.quit), #selector(quit), key: "q"))
        file.addItem(command(localized(.systemScreenshot), #selector(openScreenshot)))
        file.addItem(command(localized(.openImage), #selector(openImage), key: "o"))
        file.addItem(command(localized(.newFromClipboard), #selector(pasteImage), key: "n"))
        file.addItem(.separator()); file.addItem(command(localized(.show), #selector(showHome)))
        let close = NSMenuItem(title: localized(.close), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"); file.addItem(close)
        let editCommands: [(UIString, String, String)] = [(.cut, "cut:", "x"), (.copy, "copy:", "c"), (.paste, "paste:", "v"), (.selectAll, "selectAll:", "a")]
        for (name, selector, key) in editCommands {
            edit.addItem(NSMenuItem(title: localized(name), action: Selector(selector), keyEquivalent: key))
        }
        for menu in [app, file, edit] { let item = NSMenuItem(); item.submenu = menu; main.addItem(item) }
        NSApp.mainMenu = main
        if status == nil { status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "SicGo")
        status.button?.toolTip = "SicGo"
        let quick = NSMenu(); quick.minimumWidth = 220
        quick.addItem(command(localized(.systemScreenshot), #selector(openScreenshot), symbol: "viewfinder"))
        quick.addItem(command(localized(.newFromClipboard), #selector(pasteImage), key: "n", symbol: "clipboard"))
        quick.addItem(command(localized(.openImage), #selector(openImage), key: "o", symbol: "photo"))
        quick.addItem(.separator())
        quick.addItem(command(localized(.show), #selector(showHome), symbol: "macwindow"))
        quick.addItem(command(localized(.settingsMenu), #selector(showSettings), key: ",", symbol: "gearshape"))
        quick.addItem(command(localized(.checkForUpdates), #selector(checkForUpdates), symbol: "arrow.triangle.2.circlepath"))
        quick.addItem(.separator())
        quick.addItem(command(localized(.quit), #selector(quit), key: "q", symbol: "power"))
        status.menu = quick
    }
    private func buildHome() {
        let home = HomeWindow(); self.home = home
        home.capture = { [weak self] in self?.openScreenshot() }
        home.openImage = { [weak self] in self?.openImage() }
        home.pasteImage = { [weak self] in self?.pasteImage() }
        home.openSettings = { [weak self] in self?.showSettings() }
        updateHomeLocalization()
    }
    private func updateHomeLocalization() { home?.updateLocalization(receptionAvailable: receptionAvailable) }
    private func updateLocalization() {
        buildMenus(); updateHomeLocalization(); settings?.updateLocalization()
        editors.values.forEach { $0.updateLocalization() }
    }
    @objc private func systemLanguageChanged() {
        if EditorPreferences().language == .system { updateLocalization() }
    }
    @objc private func showSettings() {
        if settings == nil {
            settings = SettingsWindow()
            settings?.languageChanged = { [weak self] in self?.updateLocalization() }
            settings?.toolbarOrderChanged = { [weak self] in self?.editors.values.forEach { $0.applyToolbarOrder() } }
        }
        settings?.refreshPreferences(); settings?.showWindow(nil); settings?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showHome() {
        if home == nil { buildHome() }
        home?.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func checkForUpdates() {
        showSettings(); settings?.checkForUpdates()
    }
    @objc private func about() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "SicGo", .applicationVersion: version, .credits: NSAttributedString(string: localized(.credits))])
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp, .webP]
        panel.allowsMultipleSelection = false; panel.prompt = localized(.open)
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    private func open(_ url: URL) {
        do { present(try CaptureImage.read(url), title: url.lastPathComponent) }
        catch { report(error) }
    }
    @objc private func pasteImage() {
        guard let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let alert = NSAlert(); alert.messageText = localized(.clipboardEmpty); alert.informativeText = localized(.clipboardHint)
            alert.addButton(withTitle: localized(.ok)); alert.runModal(); return
        }
        present(image, title: localized(.clipboard), titleKey: .clipboard)
    }
    @objc private func openScreenshot() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.screenshot.launcher") else {
            report(CocoaError(.fileNoSuchFile)); return
        }
        NSApp.hide(nil)
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { NSApp.unhide(nil); self?.report(error) } }
        }
    }
    private func present(_ image: CGImage, title: String, titleKey: UIString? = nil) {
        home?.window?.orderOut(nil)
        let id = UUID(), editor = EditorWindow(image: image, title: title, titleKey: titleKey)
        editor.closed = { [weak self] in
            self?.editors.removeValue(forKey: id)
            if self?.editors.isEmpty == true, self?.settings?.window?.isVisible != true, self?.home?.window?.isVisible != true { NSApp.hide(nil) }
        }
        editors[id] = editor; editor.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func report(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = localized(.error); alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: localized(.ok)); alert.runModal()
    }
}
