import AppKit
import ServiceManagement

@main
struct EditorChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3, ["--write-preferences", "--read-preferences"].contains(args[1]) {
            let defaults = UserDefaults(suiteName: args[2])!
            let preferences = EditorPreferences(defaults: defaults)
            if args[1] == "--write-preferences" {
                preferences.tool = .text
                preferences.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
                preferences.windowTopLeft = CGPoint(x: -1400, y: 900)
                preferences.language = .simplifiedChinese
                preferences.showHomeOnLaunch = false
                preferences.rememberAnnotation = false
                preferences.defaultTool = .rectangle
                preferences.defaultColor = NSColor(srgbRed: 0.1, green: 0.6, blue: 0.2, alpha: 1)
                expect(defaults.synchronize())
            } else {
                expectEqual(preferences.tool, .text)
                expectEqual(preferences.windowTopLeft, CGPoint(x: -1400, y: 900))
                expectEqual(preferences.language, .simplifiedChinese)
                expectFalse(preferences.showHomeOnLaunch)
                expectFalse(preferences.rememberAnnotation)
                expectEqual(preferences.startingTool, .rectangle)
                expect(abs(preferences.startingColor.greenComponent - 0.6) < 0.0001)
                let color = preferences.color.usingColorSpace(.sRGB)!
                for (value, expected) in zip([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], [0.2, 0.4, 0.6, 0.8]) {
                    expect(abs(value - expected) < 0.0001)
                }
            }
            return
        }
        let checks = EditorChecks()
        try checks.testCaptureIsRemovedAfterReading()
        try checks.testInvalidCaptureIsPreservedForRetry()
        try checks.testSettingsRestoreAndRecovery()
        try checks.testUserSettingsChangesArePreserved()
        try checks.testSystemScreenshotReception()
        try checks.testStoppingCancelsPendingReception()
        try checks.testPreferencesSurviveRelaunch()
        checks.testInvalidPreferencesUseDefaults()
        checks.testLanguageResolution()
        checks.testSettingsLanguageSelection()
        checks.testAnnotationDefaultsSettings()
        checks.testLoginSettingState()
        checks.testLanguageChangePreservesEditing()
        checks.testRememberedWindowStaysVisible()
        checks.testCursorStaysInsideImage()
        checks.testInactiveWindowDoesNotReplaceCursor()
        checks.testInlineTextClickAwayAndFirstDrag()
        checks.testInlineTextFocusAndDoubleClick()
        checks.testInlineTextLayoutAndCancel()
        checks.testRectangleInteriorAllowsAnotherAnnotation()
        checks.testResizingKeepsThinStroke()
        checks.testCropRotateAndUndoStayEditable()
        checks.testFourRotationsRestoreImagePixels()
        checks.testMosaicPixelsMatchReference()
        checks.testHistorySharesOriginalImage()
        checks.testHistoryBudgetAcrossCropRotateAndRedo()
        checks.testHistoryCountsAnnotationPayload()
        print("PASS: 27 checks — inline text click-away, single-drag and focus, mosaic pixels, history memory, settings, preferences, cursor boundaries, screenshot reception, geometry, undo, rendering")
    }

    private func image(width: Int = 320, height: Int = 200) -> CGImage {
        let c = Drawing.context(width: width, height: height)!
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.setFillColor(NSColor.black.cgColor); c.fill(CGRect(x: 2, y: 3, width: 20, height: 12))
        return c.makeImage()!
    }
    @MainActor private func inputFixture() -> (NSWindow, EditorCanvas) {
        _ = NSApplication.shared
        let canvas = EditorCanvas(document: EditorDocument(image: image()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas; canvas.tool = .text
        return (window, canvas)
    }
    @MainActor private func mouse(_ type: NSEvent.EventType, _ window: NSWindow, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 0)!
    }
    @MainActor func testInlineTextClickAwayAndFirstDrag() {
        let (window, canvas) = inputFixture()
        defer { window.contentView = nil }
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        field.string = "Hello"
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: field))
        expect(field.frame.height < 80); expect(field.frame.width < 160)
        let outside = CGPoint(x: 260, y: 40)
        expect(canvas.hitTest(outside) === canvas)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, outside))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, outside))
        expect(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
        expectEqual(canvas.document.state.marks.count, 1)
        let text = canvas.document.state.marks[0], center = text.center
        expectEqual(text.text, "Hello")
        expectEqual(canvas.annotationCursor(at: center), .openHand)
        let end = CGPoint(x: center.x + 25, y: center.y - 30)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, center))
        expect(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, end))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, end))
        expectEqual(canvas.document.state.marks[0].frame, text.frame.offsetBy(dx: 25, dy: -30))
        canvas.undo(); expectEqual(canvas.document.state.marks, [text])
        canvas.undo(); expect(canvas.document.state.marks.isEmpty)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        let nextField = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        nextField.string = "Focus first"
        let click = mouse(.leftMouseDown, window, outside)
        canvas.finishText(restoreFocus: false, triggeredBy: click)
        canvas.mouseDown(with: click)
        expect(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
        expectEqual(canvas.document.state.marks.count, 1)
    }
    @MainActor func testInlineTextFocusAndDoubleClick() {
        let (window, canvas) = inputFixture()
        defer { window.contentView = nil }
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        field.string = "文字"
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: field))
        expect(window.makeFirstResponder(canvas))
        expect(window.firstResponder === canvas)
        expectEqual(canvas.document.state.marks.count, 1)
        expect(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
        let text = canvas.document.state.marks[0]
        canvas.mouseDown(with: mouse(.leftMouseDown, window, text.center, clicks: 2))
        let edit = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        expectEqual(edit.string, text.text)
        edit.string = "改好的文字"
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: edit))
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 260, y: 40)))
        expectEqual(canvas.document.state.marks.count, 1)
        expectEqual(canvas.document.state.marks[0].id, text.id)
        expectEqual(canvas.document.state.marks[0].text, "改好的文字")
        canvas.undo(); expectEqual(canvas.document.state.marks, [text])
    }
    @MainActor func testInlineTextLayoutAndCancel() {
        let (window, canvas) = inputFixture()
        defer { window.contentView = nil }
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        let originalHeight = field.frame.height
        field.string = "第一行\n第二行\n"
        canvas.textDidChange(Notification(name: NSText.didChangeNotification, object: field))
        expect(field.frame.height > originalHeight * 2)
        expectEqual(field.frame.maxY, 160)
        expectEqual(field.textContainer?.containerSize.width, 280)
        expect(canvas.textView(field, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        expect(canvas.document.state.marks.isEmpty); expectFalse(canvas.document.canUndo)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 260, y: 40)))
        expect(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
        expect(canvas.document.state.marks.isEmpty); expectFalse(canvas.document.canUndo)
    }
    func testMosaicPixelsMatchReference() {
        // Frozen rendering order from the previous implementation. Compare raw pixels,
        // including overlapping/rotated mosaics and preview scales, not just dimensions.
        func reference(_ image: CGImage, _ marks: [Annotation], _ ctx: CGContext) {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            for (index, mark) in marks.enumerated() {
                ctx.saveGState()
                ctx.translateBy(x: mark.center.x, y: mark.center.y); ctx.rotate(by: mark.angle)
                ctx.translateBy(x: -mark.center.x, y: -mark.center.y)
                if mark.tool == .mosaic {
                    let grid = Drawing.context(width: max(1, Int(mark.frame.width / 14)), height: max(1, Int(mark.frame.height / 14)))!
                    grid.scaleBy(x: CGFloat(grid.width) / mark.frame.width, y: CGFloat(grid.height) / mark.frame.height)
                    grid.translateBy(x: -mark.frame.minX, y: -mark.frame.minY)
                    grid.translateBy(x: mark.center.x, y: mark.center.y); grid.rotate(by: -mark.angle)
                    grid.translateBy(x: -mark.center.x, y: -mark.center.y)
                    reference(image, Array(marks.prefix(index)), grid)
                    ctx.interpolationQuality = .none; ctx.draw(grid.makeImage()!, in: mark.frame)
                } else { Drawing.vector(mark, in: ctx) }
                ctx.restoreGState()
            }
            ctx.restoreGState()
        }
        let source = image()
        var arrow = Annotation(tool: .arrow, frame: .zero, color: .systemBlue)
        arrow.setVertices([CGPoint(x: 20, y: 150), CGPoint(x: 280, y: 20)])
        let marks = [
            Annotation(tool: .rectangle, frame: CGRect(x: 5, y: 10, width: 270, height: 160)),
            Annotation(tool: .mosaic, frame: CGRect(x: 0, y: 0, width: 140, height: 100)),
            Annotation(tool: .text, frame: CGRect(x: 45, y: 50, width: 120, height: 40), text: "Aa中文", textLayout: CGSize(width: 120, height: 40)),
            Annotation(tool: .mosaic, frame: CGRect(x: 30, y: 40, width: 170, height: 100), angle: -0.3),
            arrow,
            Annotation(tool: .mosaic, frame: CGRect(x: -25, y: 35, width: 120, height: 150), angle: 0.5)
        ]
        for scale in [CGFloat(0.75), 1, 2] {
            let expected = Drawing.context(width: Int(320 * scale), height: Int(200 * scale))!
            let actual = Drawing.context(width: Int(320 * scale), height: Int(200 * scale))!
            expected.scaleBy(x: scale, y: scale); actual.scaleBy(x: scale, y: scale)
            reference(source, marks, expected); Drawing.scene(source, marks: marks, in: actual)
            expectEqual(Data(bytes: actual.data!, count: actual.bytesPerRow * actual.height),
                        Data(bytes: expected.data!, count: expected.bytesPerRow * expected.height))
        }
    }
    @MainActor func testHistorySharesOriginalImage() {
        let doc = EditorDocument(image: image(), historyByteLimit: 32_768)
        doc.change { $0.marks.append(Annotation(tool: .rectangle, frame: CGRect(x: 0, y: 0, width: 40, height: 40))) }
        for i in 1...40 { doc.change { $0.marks[0].frame.origin.x = CGFloat(i) } }
        expect(doc.historyByteEstimate <= 32_768)
        var undos = 0
        while doc.canUndo { doc.undo(); undos += 1; expect(doc.historyByteEstimate <= 32_768) }
        expectEqual(undos, 30)
        while doc.canRedo { doc.redo(); expect(doc.historyByteEstimate <= 32_768) }
        expectEqual(doc.state.marks[0].frame.origin.x, 40)
    }
    @MainActor func testHistoryBudgetAcrossCropRotateAndRedo() {
        let doc = EditorDocument(image: image(), historyByteLimit: 600_000)
        for _ in 0..<8 { doc.rotateImage(); expect(doc.historyByteEstimate <= 600_000) }
        expect(doc.canUndo)
        doc.undo(); expect(doc.canRedo); expect(doc.historyByteEstimate <= 600_000)
        doc.undo(); expect(doc.historyByteEstimate <= 600_000)
        doc.redo(); expect(doc.historyByteEstimate <= 600_000)
        doc.crop(to: CGRect(x: 0, y: 0, width: 20, height: 20))
        expectFalse(doc.canRedo); expect(doc.historyByteEstimate <= 600_000)
        let smallBudget = EditorDocument(image: image(), historyByteLimit: 100_000)
        smallBudget.crop(to: CGRect(x: 0, y: 0, width: 20, height: 20))
        expectEqual(smallBudget.size, CGSize(width: 20, height: 20))
        expectFalse(smallBudget.canUndo); expectEqual(smallBudget.historyByteEstimate, 0)
    }
    @MainActor func testHistoryCountsAnnotationPayload() {
        let doc = EditorDocument(image: image(), historyByteLimit: 32_768)
        doc.change { $0.marks.append(Annotation(tool: .pen, frame: CGRect(x: 0, y: 0, width: 50, height: 50), vertices: Array(repeating: CGPoint(x: 0.2, y: 0.3), count: 4_000))) }
        doc.change { $0.marks[0].frame.origin.x += 1 }
        expectFalse(doc.canUndo); expectEqual(doc.historyByteEstimate, 0)
        expectEqual(doc.state.marks[0].vertices.count, 4_000)
    }
    func testPreferencesSurviveRelaunch() throws {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        for mode in ["--write-preferences", "--read-preferences"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            task.arguments = [mode, domain]
            try task.run(); task.waitUntilExit()
            expectEqual(task.terminationStatus, 0)
        }
    }
    func testInvalidPreferencesUseDefaults() {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("missing tool", forKey: "editor.tool")
        defaults.set([2, -1, 0, 1], forKey: "editor.color")
        defaults.set([10], forKey: "editor.windowTopLeft")
        defaults.set("unsupported", forKey: "interface.language")
        defaults.set("unsupported", forKey: "editor.defaultTool")
        defaults.set([-1, 5, 0, 1], forKey: "editor.defaultColor")
        defaults.set("unsupported", forKey: "editor.rememberAnnotation")
        defaults.set("unsupported", forKey: "interface.showHomeOnLaunch")
        let preferences = EditorPreferences(defaults: defaults)
        expectEqual(preferences.tool, .arrow)
        expectEqual(preferences.color, .systemRed)
        expect(preferences.windowTopLeft == nil)
        expectEqual(preferences.language, .english)
        expect(preferences.rememberAnnotation)
        expect(preferences.showHomeOnLaunch)
        expectEqual(preferences.defaultTool, .arrow)
        expectEqual(preferences.defaultColor, .systemRed)
    }
    func testLanguageResolution() {
        expectEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]), .simplifiedChinese)
        expectEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]), .english)
        expectEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["zh_TW"]), .simplifiedChinese)
        expectEqual(InterfaceLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .english)
        expectEqual(InterfaceLanguage.system.resolved(preferredLanguages: []), .english)
        expectEqual(localized(.settings, language: .english, preferredLanguages: ["zh-CN"]), "Settings")
        expectEqual(localized(.settings, language: .system, preferredLanguages: ["zh-CN"]), "设置")
        for key in UIString.allCases {
            expectFalse(localized(key, language: .english).isEmpty)
            expectFalse(localized(key, language: .simplifiedChinese).isEmpty)
        }
    }
    @MainActor func testSettingsLanguageSelection() {
        _ = NSApplication.shared
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        // Use a named isolated domain so these checks never touch app preferences.
        let isolated = UserDefaults(suiteName: domain)!
        defer { isolated.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: isolated), settings = SettingsWindow(preferences: EditorPreferences(defaults: isolated), loginItem: TestLoginItem())
        var changes = 0
        settings.languageChanged = { changes += 1 }
        for language in [InterfaceLanguage.simplifiedChinese, .english, .system] {
            settings.languagePicker.selectItem(at: InterfaceLanguage.allCases.firstIndex(of: language)!)
            expect(settings.languagePicker.sendAction(settings.languagePicker.action, to: settings.languagePicker.target))
            expectEqual(preferences.language, language)
            expectEqual(settings.window?.title, localized(.settings, language: language))
        }
        expectEqual(changes, 3)
        expectEqual(SettingsWindow(preferences: preferences, loginItem: TestLoginItem()).languagePicker.indexOfSelectedItem, 0)
    }
    @MainActor func testAnnotationDefaultsSettings() {
        let domain = "local.SicGo.check.\(UUID().uuidString)", defaults: UserDefaults
        defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.tool = .text; preferences.color = .systemBlue
        let existing = EditorWindow(image: image(), title: "Existing", preferences: preferences)
        let existingColor = existing.canvas.color
        expectEqual(existing.canvas.tool, .text)
        let settings = SettingsWindow(preferences: preferences, loginItem: TestLoginItem())
        expectFalse(settings.toolPicker.isEnabled); expectFalse(settings.colorWell.isEnabled)
        settings.rememberButton.state = .off
        expect(settings.rememberButton.sendAction(settings.rememberButton.action, to: settings.rememberButton.target))
        expect(settings.toolPicker.isEnabled); expect(settings.colorWell.isEnabled)
        settings.toolPicker.selectItem(at: DrawingTool.allCases.firstIndex(of: .rectangle)!)
        expect(settings.toolPicker.sendAction(settings.toolPicker.action, to: settings.toolPicker.target))
        settings.colorWell.color = NSColor(srgbRed: 0.1, green: 0.7, blue: 0.3, alpha: 1)
        expect(settings.colorWell.sendAction(settings.colorWell.action, to: settings.colorWell.target))
        let next = EditorWindow(image: image(), title: "Next", preferences: preferences)
        expectEqual(next.canvas.tool, .rectangle)
        expectEqual(next.canvas.color, settings.colorWell.color)
        expectEqual(existing.canvas.tool, .text); expectEqual(existing.canvas.color, existingColor)
        preferences.tool = .pen; preferences.color = .systemOrange
        expectEqual(preferences.startingTool, .rectangle)
        expectEqual(preferences.startingColor, settings.colorWell.color)
        settings.rememberButton.state = .on
        expect(settings.rememberButton.sendAction(settings.rememberButton.action, to: settings.rememberButton.target))
        expectEqual(preferences.startingTool, .pen); expectEqual(preferences.startingColor, preferences.color)
        settings.showHomeButton.state = .off
        expect(settings.showHomeButton.sendAction(settings.showHomeButton.action, to: settings.showHomeButton.target))
        expectFalse(preferences.showHomeOnLaunch)
    }
    @MainActor func testLoginSettingState() {
        let domain = "local.SicGo.check.\(UUID().uuidString)", defaults: UserDefaults
        defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let service = TestLoginItem()
        let controller = SettingsWindow(preferences: EditorPreferences(defaults: defaults), loginItem: service)
        func toggle(_ enabled: Bool) {
            controller.launchButton.state = enabled ? .on : .off
            expect(controller.launchButton.sendAction(controller.launchButton.action, to: controller.launchButton.target))
        }
        expectEqual(controller.launchButton.state, .off)
        toggle(true); expectEqual(service.status, .enabled); expectEqual(controller.launchButton.state, .on)
        toggle(false); expectEqual(service.status, .notRegistered)
        service.nextStatus = .requiresApproval
        toggle(true); expectEqual(controller.launchButton.state, .on)
        service.status = .notRegistered; controller.refreshPreferences()
        expectEqual(controller.launchButton.state, .off)
        var reported = false
        controller.reportLoginError = { _ in reported = true }
        service.shouldFail = true
        toggle(true)
        expect(reported); expectEqual(controller.launchButton.state, .off)
    }
    @MainActor func testLanguageChangePreservesEditing() {
        let defaults = UserDefaults.standard, previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        var overrides = previous; overrides["interface.language"] = InterfaceLanguage.english.rawValue
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        let editor = EditorWindow(image: image(), title: "Screenshot", titleKey: .screenshot)
        let original = EditorWindow(image: image(), title: "My image.png")
        let mark = Annotation(tool: .rectangle, frame: CGRect(x: 10, y: 10, width: 60, height: 40))
        editor.canvas.document.change { $0.marks.append(mark) }
        let frame = editor.window!.frame, pixels = editor.canvas.document.state.image
        overrides["interface.language"] = InterfaceLanguage.simplifiedChinese.rawValue
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        editor.updateLocalization(); original.updateLocalization()
        expectEqual(editor.window?.title, "截图")
        expectEqual(original.window?.title, "My image.png")
        let done = editor.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "done" }
        expectEqual((done?.view as? NSButton)?.title, "完成")
        expectEqual(editor.canvas.document.state.marks.first?.id, mark.id)
        expect(editor.canvas.document.state.image === pixels)
        expectEqual(editor.window!.frame, frame)
        expect(editor.canvas.document.canUndo)
        overrides["interface.language"] = InterfaceLanguage.english.rawValue
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        editor.updateLocalization()
        expectEqual((done?.view as? NSButton)?.title, "Done")
        editor.canvas.undo(); expect(editor.canvas.document.state.marks.isEmpty)
    }
    func testRememberedWindowStaysVisible() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 800, height: 600)
        let point = EditorPreferences.visibleTopLeft(CGPoint(x: -1400, y: 900), windowSize: size, screen: screen)
        expectEqual(point, CGPoint(x: -1400, y: 900))
        let clamped = EditorPreferences.visibleTopLeft(CGPoint(x: 4000, y: -200), windowSize: size, screen: screen)
        expectEqual(clamped, CGPoint(x: -800, y: 600))
    }
    @MainActor func testCursorStaysInsideImage() {
        _ = NSApplication.shared
        let canvas = EditorCanvas(document: EditorDocument(image: image()))
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        expectEqual(canvas.annotationCursor(at: CGPoint(x: 200, y: 200)), .crosshair)
        // Neither the letterbox margin nor the toolbar area belongs to the canvas cursor.
        expect(canvas.annotationCursor(at: CGPoint(x: 200, y: 20)) == nil)
        expect(canvas.annotationCursor(at: CGPoint(x: 200, y: 420)) == nil)
        expect(canvas.annotationCursor(at: CGPoint(x: -1, y: 200)) == nil)
        canvas.tool = .text
        expectEqual(canvas.annotationCursor(at: CGPoint(x: 200, y: 200)), .iBeam)
        canvas.tool = .select
        expectEqual(canvas.annotationCursor(at: CGPoint(x: 200, y: 200)), .arrow)
        canvas.document.change { $0.marks.append(Annotation(tool: .rectangle, frame: CGRect(x: 100, y: 60, width: 100, height: 80))) }
        expectEqual(canvas.annotationCursor(at: CGPoint(x: 200, y: 200)), .openHand)
    }
    @MainActor func testInactiveWindowDoesNotReplaceCursor() {
        let canvas = EditorCanvas(document: EditorDocument(image: image()))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        expectFalse(window.isKeyWindow)
        let before = NSCursor.current
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 80, y: 80), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        canvas.mouseMoved(with: event)
        expectEqual(NSCursor.current, before)
        window.contentView = nil
    }
    func testCaptureIsRemovedAfterReading() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SicGoTest-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = NSBitmapImageRep(cgImage: image()).representation(using: .png, properties: [:])!
        try bytes.write(to: url)
        let decoded = try CaptureImage.consume(url)
        expectEqual(decoded.width, 320)
        expectFalse(FileManager.default.fileExists(atPath: url.path))
        // The decoded image remains usable after its temporary file is gone.
        expectNotNil(Drawing.render(decoded, marks: []))
    }
    func testInvalidCaptureIsPreservedForRetry() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SicGoTest-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("invalid".utf8).write(to: url)
        expectThrows(try CaptureImage.consume(url))
        expect(FileManager.default.fileExists(atPath: url.path))
    }
    private func sandbox(_ work: (URL, String) throws -> Void) throws {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
        let folder = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            for key in CFPreferencesCopyKeyList(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? [] {
                CFPreferencesSetAppValue(key as CFString, nil, domain as CFString)
            }
            CFPreferencesAppSynchronize(domain as CFString)
            try? FileManager.default.removeItem(at: root)
        }
        try work(folder, domain)
    }
    private func set(_ key: String, _ value: Any?, _ domain: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }
    private func value(_ key: String, _ domain: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain as CFString) }
    func testSettingsRestoreAndRecovery() throws {
        for modern in [true, false] {
            try sandbox { folder, domain in
                set("location", "/original", domain); set("location-screenrecording", "/movies", domain)
                set("target-screenshot", "clipboard", domain); set("target", "preview", domain)
                let settings = ScreenshotSettings(folder: folder, domain: domain, screenshotSpecific: modern)
                try settings.begin()
                expectEqual(value(modern ? "location-screenshot" : "location", domain) as? String, folder.path)
                expectEqual(value("location-screenrecording", domain) as? String, "/movies")
                if modern { expectEqual(value("location", domain) as? String, "/original") }
                // A new instance recovers an interrupted lease before installing its own.
                let next = ScreenshotSettings(folder: folder, domain: domain, screenshotSpecific: modern)
                try next.begin(); try next.end()
                expectEqual(value("location", domain) as? String, "/original")
                expect(value("location-screenshot", domain) == nil)
                expect(value("show-thumbnail", domain) == nil)
                expectEqual(value("target-screenshot", domain) as? String, "clipboard")
                expectEqual(value("target", domain) as? String, "preview")
            }
        }
    }
    func testUserSettingsChangesArePreserved() throws {
        try sandbox { folder, domain in
            let settings = ScreenshotSettings(folder: folder, domain: domain, screenshotSpecific: true)
            try settings.begin()
            set("target-screenshot", "preview", domain)
            try settings.end()
            expectEqual(value("target-screenshot", domain) as? String, "preview")
            expect(value("location-screenshot", domain) == nil)
            try settings.begin()
            set("location-screenshot", "/new-user-folder", domain)
            try settings.end()
            expectEqual(value("location-screenshot", domain) as? String, "/new-user-folder")
        }
    }
    private func tagScreenshot(_ url: URL) {
        let bytes = Data([1])
        let result = bytes.withUnsafeBytes { pointer in
            setxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", pointer.baseAddress, bytes.count, 0, 0)
        }
        expectEqual(result, 0)
    }
    @MainActor func testSystemScreenshotReception() throws {
        try sandbox { folder, domain in
            let bytes = NSBitmapImageRep(cgImage: image()).representation(using: .png, properties: [:])!
            let old = folder.appendingPathComponent("old.png")
            try bytes.write(to: old); tagScreenshot(old)
            let settings = ScreenshotSettings(folder: folder, domain: domain, screenshotSpecific: true)
            let inbox = SystemScreenshotInbox(folder: folder, settings: settings)
            var received = 0, errors = 0
            inbox.onImage = { image, _ in received += 1; expectEqual(image.width, 320) }
            inbox.onError = { _ in errors += 1 }
            try inbox.start(); defer { try? inbox.stop() }
            let screenshot = folder.appendingPathComponent("new.png")
            try bytes.write(to: screenshot); tagScreenshot(screenshot)
            let normal = folder.appendingPathComponent("photo.png")
            try bytes.write(to: normal)
            let movie = folder.appendingPathComponent("recording.mov")
            try Data("video".utf8).write(to: movie)
            let link = folder.appendingPathComponent("linked.png")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)
            let partial = folder.appendingPathComponent("partial.png")
            try Data().write(to: partial); tagScreenshot(partial)
            let delayed = folder.appendingPathComponent("late-tag.png")
            try bytes.write(to: delayed)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                expect(FileManager.default.fileExists(atPath: partial.path))
                try! bytes.write(to: partial); self.tagScreenshot(partial); self.tagScreenshot(delayed)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(2))
            expectEqual(received, 3); expectEqual(errors, 0)
            for url in [old, normal, movie, link] { expect(FileManager.default.fileExists(atPath: url.path)) }
            for url in [screenshot, partial, delayed] { expectFalse(FileManager.default.fileExists(atPath: url.path)) }
        }
    }
    @MainActor func testStoppingCancelsPendingReception() throws {
        try sandbox { folder, domain in
            let inbox = SystemScreenshotInbox(folder: folder, settings: ScreenshotSettings(folder: folder, domain: domain, screenshotSpecific: true))
            inbox.onImage = { _, _ in preconditionFailure("Received after stop") }
            try inbox.start()
            let file = folder.appendingPathComponent("pending.png")
            let bytes = NSBitmapImageRep(cgImage: image()).representation(using: .png, properties: [:])!
            try bytes.write(to: file); tagScreenshot(file)
            try inbox.stop()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            expect(FileManager.default.fileExists(atPath: file.path))
            expect(value("location-screenshot", domain) == nil)
        }
    }
    func testRectangleInteriorAllowsAnotherAnnotation() {
        var box = Annotation(tool: .rectangle, frame: CGRect(x: 40, y: 40, width: 100, height: 80))
        expectFalse(box.hit(CGPoint(x: 90, y: 80), tolerance: 5, includeInterior: false))
        expect(box.hit(CGPoint(x: 40, y: 80), tolerance: 5, includeInterior: false))
        expect(box.hit(CGPoint(x: 90, y: 80), tolerance: 5, includeInterior: true))
        box.angle = .pi / 3
        expect(box.hit(box.toWorld(CGPoint(x: 40, y: 80)), tolerance: 5, includeInterior: false))
    }
    func testResizingKeepsThinStroke() {
        func thickness(_ frame: CGRect) -> Int {
            let mark = Annotation(tool: .rectangle, frame: frame, color: .red)
            let result = NSBitmapImageRep(cgImage: Drawing.render(image(), marks: [mark])!)
            return (0..<result.pixelsWide).filter { x in
                guard let c = result.colorAt(x: x, y: result.pixelsHigh - 1 - Int(frame.midY))?.usingColorSpace(.sRGB) else { return false }
                return c.redComponent > 0.9 && c.greenComponent < 0.2
            }.count
        }
        let small = thickness(CGRect(x: 60, y: 40, width: 50, height: 90))
        expectGreater(small, 0)
        expectEqual(small, thickness(CGRect(x: 60, y: 40, width: 200, height: 30)))
    }
    @MainActor func testCropRotateAndUndoStayEditable() {
        let doc = EditorDocument(image: image())
        let box = Annotation(tool: .rectangle, frame: CGRect(x: 60, y: 50, width: 80, height: 40))
        doc.change { $0.marks.append(box) }
        doc.crop(to: CGRect(x: 20, y: 30, width: 200, height: 140))
        expectEqual(doc.size, CGSize(width: 200, height: 140))
        expectEqual(doc.state.marks[0].frame.origin, CGPoint(x: 40, y: 20))
        doc.rotateImage()
        expectEqual(doc.size, CGSize(width: 140, height: 200))
        expectEqual(doc.state.marks[0].id, box.id)
        doc.undo(); doc.undo()
        expectEqual(doc.size, CGSize(width: 320, height: 200))
        expectEqual(doc.state.marks, [box])
        doc.redo()
        expectEqual(doc.size, CGSize(width: 200, height: 140))
    }
    @MainActor func testFourRotationsRestoreImagePixels() {
        let original = image(), doc = EditorDocument(image: image())
        for _ in 0..<4 { doc.rotateImage() }
        expectEqual(doc.size, CGSize(width: 320, height: 200))
        expectEqual(doc.state.image.dataProvider?.data as Data?, original.dataProvider?.data as Data?)
    }
}

func expect(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Check failed", file: file, line: line) }
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { expect(!value, file: file, line: line) }
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) { precondition(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line) }
func expectGreater<T: Comparable>(_ actual: T, _ lower: T, file: StaticString = #file, line: UInt = #line) { expect(actual > lower, file: file, line: line) }
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { expect(value != nil, file: file, line: line) }
func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected an error", file: file, line: line)
}

@MainActor
private final class TestLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var nextStatus: SMAppService.Status = .enabled
    var shouldFail = false
    func setEnabled(_ enabled: Bool) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        status = enabled ? nextStatus : .notRegistered
    }
}
