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
                preferences.textFontName = "Menlo-Regular"
                preferences.toolbarOrder = Array(ToolbarItem.allCases.reversed())
                expect(defaults.synchronize())
            } else {
                expectEqual(preferences.tool, .text)
                expectEqual(preferences.windowTopLeft, CGPoint(x: -1400, y: 900))
                expectEqual(preferences.language, .simplifiedChinese)
                expectFalse(preferences.showHomeOnLaunch)
                expectEqual(preferences.textFontName, "Menlo-Regular")
                expectEqual(preferences.toolbarOrder, Array(ToolbarItem.allCases.reversed()))
                let color = preferences.color.usingColorSpace(.sRGB)!
                for (value, expected) in zip([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], [0.2, 0.4, 0.6, 0.8]) {
                    expect(abs(value - expected) < 0.0001)
                }
            }
            return
        }
        let checks = EditorChecks()
        checks.testReleaseVersions()
        try checks.testReleaseResponses()
        checks.testUpdateStateAndSettings()
        checks.testUpdateNetworkResponses()
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
        checks.testAnnotationPreferencesAlwaysRemember()
        checks.testToolbarReorderingPreservesEditing()
        checks.testToolbarDragCommitAndCancel()
        checks.testLoginSettingState()
        checks.testLanguageChangePreservesEditing()
        checks.testRememberedWindowStaysVisible()
        checks.testCursorStaysInsideImage()
        checks.testInactiveWindowDoesNotReplaceCursor()
        checks.testInlineTextClickAwayAndFirstDrag()
        checks.testInlineTextFocusAndDoubleClick()
        checks.testInlineTextLayoutAndCancel()
        checks.testAnnotationClipboardRoundTrip()
        checks.testDrawCopyPasteAndEdit()
        checks.testPasteAcrossImagesAndAtEdges()
        checks.testInvalidAnnotationClipboard()
        checks.testTextEditingKeepsNativeClipboard()
        checks.testTextFontPreferencesAndClipboard()
        checks.testImageCopyAndDoneStayUnchanged()
        checks.testPastedImageEditing()
        checks.testImageLayerClipboardAndFiles()
        checks.testRotationKeepsWindowFrame()
        checks.testImageLayerHistoryAndTransparency()
        checks.testRectangleInteriorAllowsAnotherAnnotation()
        checks.testResizingKeepsThinStroke()
        checks.testCropRotateAndUndoStayEditable()
        checks.testFourRotationsRestoreImagePixels()
        checks.testMosaicPixelsMatchReference()
        checks.testHistorySharesOriginalImage()
        checks.testHistoryBudgetAcrossCropRotateAndRedo()
        checks.testHistoryCountsAnnotationPayload()
        print("PASS: 44 checks — release versions/responses/network/update UI, image layers/paste/alpha/history, fixed-window rotation, toolbar order/persistence, fonts, annotation clipboard, inline text, mosaic pixels, settings, screenshot reception, geometry, undo, rendering")
    }

    private func image(width: Int = 320, height: Int = 200) -> CGImage {
        let c = Drawing.context(width: width, height: height)!
        c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.setFillColor(NSColor.black.cgColor); c.fill(CGRect(x: 2, y: 3, width: 20, height: 12))
        return c.makeImage()!
    }
    @MainActor private func inputFixture(pasteboard: NSPasteboard = .general, preferences: EditorPreferences = EditorPreferences()) -> (NSWindow, EditorCanvas) {
        _ = NSApplication.shared
        let canvas = EditorCanvas(document: EditorDocument(image: image()), pasteboard: pasteboard, preferences: preferences)
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
    @MainActor func testTextFontPreferencesAndClipboard() {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        // Every setting and clipboard change stays inside this fixture.
        let isolated = UserDefaults(suiteName: domain)!
        defer { isolated.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: isolated)
        expectEqual(preferences.textFontName, nil)
        let settings = SettingsWindow(preferences: preferences, loginItem: TestLoginItem())
        settings.menuNeedsUpdate(settings.fontPicker.menu!)
        settings.fontPicker.selectItem(withTitle: "Menlo")
        expect(settings.fontPicker.sendAction(settings.fontPicker.action, to: settings.fontPicker.target))
        let name = preferences.textFontName!
        expectEqual(EditorPreferences(defaults: isolated).textFontName, name)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let (window, canvas) = inputFixture(pasteboard: board, preferences: preferences)
        defer { window.contentView = nil }
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 160)))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        expectEqual(field.font?.fontName, name)
        field.string = "Font"
        settings.fontPicker.selectItem(at: 0)
        expect(settings.fontPicker.sendAction(settings.fontPicker.action, to: settings.fontPicker.target))
        expectEqual(preferences.textFontName, nil)
        canvas.finishText()
        let mark = canvas.document.state.marks[0]
        expectEqual(mark.fontName, name)
        expectEqual((Drawing.textAttributes(mark.color, size: mark.fontSize, fontName: mark.fontName)[.font] as? NSFont)?.fontName, name)
        expect(Drawing.render(canvas.document.state.image, marks: [mark]) != nil)
        canvas.copy(nil); canvas.paste(nil)
        expectEqual(canvas.document.state.marks.last?.fontName, name)
        canvas.undo(); expectEqual(canvas.document.state.marks, [mark])
        canvas.mouseDown(with: mouse(.leftMouseDown, window, mark.center, clicks: 2))
        let editing = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        expectEqual(editing.font?.fontName, name)
        editing.string = "Edited"; canvas.finishText()
        expectEqual(canvas.document.state.marks[0].fontName, name)
        canvas.tool = .text
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 220, y: 70)))
        let system = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        expectEqual(system.font, NSFont.systemFont(ofSize: 30))
        system.string = "New"; canvas.finishText()
        expectEqual(canvas.document.state.marks.last?.fontName, nil)
        expectEqual(Drawing.textFont(name: "SicGo Missing Font", size: 30), NSFont.systemFont(ofSize: 30))
        isolated.set("SicGo Missing Font", forKey: "editor.textFontName")
        expectEqual(preferences.textFontName, nil)
        expect(AnnotationClipboard.write(mark, to: board))
        var legacy = try! PropertyListSerialization.propertyList(from: board.data(forType: AnnotationClipboard.type)!, format: nil) as! [String: Any]
        legacy.removeValue(forKey: "fontName")
        let legacyData = try! PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        board.clearContents(); board.setData(legacyData, forType: AnnotationClipboard.type)
        expectEqual(AnnotationClipboard.read(from: board)?.fontName, nil)
    }
    @MainActor func testAnnotationClipboardRoundTrip() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        for tool in DrawingTool.allCases where tool != .select && tool != .crop && tool != .image {
            var mark = Annotation(tool: tool, frame: CGRect(x: 20, y: 30, width: 90, height: 60), angle: 0.7,
                                  color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
                                  text: "第一行\nSecond line", textLayout: CGSize(width: 90, height: 60), fontSize: 22)
            if tool == .arrow || tool == .pen { mark.setVertices([CGPoint(x: 20, y: 30), CGPoint(x: 110, y: 90)]) }
            expect(AnnotationClipboard.write(mark, to: board))
            let copy = AnnotationClipboard.read(from: board)!
            expect(copy.id != mark.id); expectEqual(copy.tool, mark.tool); expectEqual(copy.frame, mark.frame)
            expectEqual(copy.angle, mark.angle); expectEqual(copy.vertices, mark.vertices)
            expectEqual(copy.text, mark.text); expectEqual(copy.textLayout, mark.textLayout); expectEqual(copy.fontSize, 22)
            expect(abs(copy.color.redComponent - 0.2) < 0.0001)
            expect(abs(copy.color.alphaComponent - 0.8) < 0.0001)
            expectEqual(board.string(forType: .string), tool == .text ? mark.text : nil)
            expect(board.data(forType: .png) == nil)
        }
    }
    @MainActor func testDrawCopyPasteAndEdit() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let (window, canvas) = inputFixture(pasteboard: board)
        defer { window.contentView = nil }
        canvas.tool = .rectangle
        canvas.mouseDown(with: mouse(.leftMouseDown, window, CGPoint(x: 40, y: 40)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, CGPoint(x: 120, y: 100)))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, CGPoint(x: 120, y: 100)))
        let original = canvas.document.state.marks[0]
        var imageCopies = 0; canvas.onCopy = { imageCopies += 1 }
        canvas.copy(nil); canvas.paste(nil)
        expectEqual(imageCopies, 0); expectEqual(canvas.document.state.marks.count, 2)
        let copy = canvas.document.state.marks[1]
        expect(copy.id != original.id); expectEqual(copy.frame, original.frame.offsetBy(dx: 12, dy: -12))
        // The pasted box is already selected: drag its edge immediately.
        let edge = CGPoint(x: copy.frame.minX, y: copy.frame.midY), end = CGPoint(x: edge.x + 20, y: edge.y + 15)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, edge))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, end))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, end))
        let moved = canvas.document.state.marks[1]
        expectEqual(moved.frame, copy.frame.offsetBy(dx: 20, dy: 15))
        expectEqual(canvas.document.state.marks[0], original)
        let corner = moved.handles[3], resized = CGPoint(x: corner.x + 25, y: corner.y + 10)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, corner))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, resized))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, resized))
        expectEqual(canvas.document.state.marks[1].frame.size, CGSize(width: 105, height: 70))
        canvas.undo(); expectEqual(canvas.document.state.marks[1], moved)
        canvas.undo(); expectEqual(canvas.document.state.marks[1], copy)
        canvas.undo(); expectEqual(canvas.document.state.marks, [original])
        canvas.redo(); expectEqual(canvas.document.state.marks, [original, copy])
        canvas.paste(nil)
        expectEqual(canvas.document.state.marks[2].frame, original.frame.offsetBy(dx: 24, dy: -24))
        expectEqual(Set(canvas.document.state.marks.map(\.id)).count, 3)
        board.clearContents(); board.setString("ordinary clipboard text", forType: .string)
        canvas.paste(nil); expectEqual(canvas.document.state.marks.count, 3)
    }
    @MainActor func testPasteAcrossImagesAndAtEdges() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let original = Annotation(tool: .rectangle, frame: CGRect(x: 285, y: 5, width: 30, height: 35), angle: .pi / 5)
        expect(AnnotationClipboard.write(original, to: board))
        let (window, canvas) = inputFixture(pasteboard: board)
        defer { window.contentView = nil }
        canvas.paste(nil)
        let copy = canvas.document.state.marks[0]
        expectEqual(copy.frame.size, original.frame.size); expectEqual(copy.angle, original.angle)
        for corner in copy.handles {
            expect(corner.x >= -0.001 && corner.x <= 320.001 && corner.y >= -0.001 && corner.y <= 200.001)
        }
        // A larger shape copied from another image stays editable at its original size.
        let large = Annotation(tool: .ellipse, frame: CGRect(x: 600, y: 500, width: 700, height: 500))
        expect(AnnotationClipboard.write(large, to: board)); canvas.paste(nil)
        expectEqual(canvas.document.state.marks[1].center, CGPoint(x: 160, y: 100))
        expectEqual(canvas.document.state.marks[1].frame.size, large.frame.size)
        canvas.undo(); expectEqual(canvas.document.state.marks.count, 1)
    }
    @MainActor func testInvalidAnnotationClipboard() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setData(Data("invalid".utf8), forType: AnnotationClipboard.type)
        expect(AnnotationClipboard.read(from: board) == nil)
        let mark = Annotation(tool: .rectangle, frame: CGRect(x: 20, y: 30, width: 90, height: 60))
        expect(AnnotationClipboard.write(mark, to: board))
        let valid = board.data(forType: AnnotationClipboard.type)!
        var payload = try! PropertyListSerialization.propertyList(from: valid, format: nil) as! [String: Any]
        for (key, value) in [("version", 2 as Any), ("tool", "Crop" as Any), ("rgba", [1, 0] as Any), ("fontSize", -1 as Any)] {
            var invalid = payload; invalid[key] = value
            let data = try! PropertyListSerialization.data(fromPropertyList: invalid, format: .binary, options: 0)
            board.clearContents(); board.setData(data, forType: AnnotationClipboard.type)
            expect(AnnotationClipboard.read(from: board) == nil)
        }
        payload["angle"] = Double.infinity
        board.clearContents(); board.setData(try! PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0), forType: AnnotationClipboard.type)
        expect(AnnotationClipboard.read(from: board) == nil)
    }
    @MainActor func testTextEditingKeepsNativeClipboard() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let (window, canvas) = inputFixture(pasteboard: board)
        defer { window.contentView = nil }
        let text = Annotation(tool: .text, frame: CGRect(x: 30, y: 80, width: 90, height: 45),
                              text: "可编辑文字", textLayout: CGSize(width: 90, height: 45))
        expect(AnnotationClipboard.write(text, to: board)); canvas.paste(nil)
        let copy = canvas.document.state.marks[0]
        canvas.mouseDown(with: mouse(.leftMouseDown, window, copy.center, clicks: 2))
        let field = canvas.subviews.compactMap { $0 as? NSTextView }.first!
        expect(window.firstResponder === field); expectEqual(field.string, text.text)
        let count = board.changeCount
        canvas.copy(nil); canvas.paste(nil)
        expectEqual(board.changeCount, count); expect(window.firstResponder === field)
        field.string = "改好的副本"; canvas.finishText()
        expectEqual(canvas.document.state.marks.count, 1)
        expectEqual(canvas.document.state.marks[0].text, "改好的副本")
    }
    @MainActor func testImageCopyAndDoneStayUnchanged() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let editor = EditorWindow(image: image(), title: "Clipboard checks", pasteboard: board)
        let window = editor.window!, canvas = editor.canvas
        defer { window.contentView = nil }
        let mark = Annotation(tool: .rectangle, frame: CGRect(x: 40, y: 40, width: 80, height: 60))
        canvas.document.change { $0.marks.append(mark) }
        canvas.tool = .select
        canvas.mouseDown(with: mouse(.leftMouseDown, window, mark.center))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, mark.center))
        canvas.copy(nil); expectNotNil(board.data(forType: AnnotationClipboard.type))
        // Toolbar Copy always exports the entire image, even with a selected annotation.
        expect(NSApp.sendAction(Selector(("copyImage")), to: editor, from: nil))
        expect(board.data(forType: AnnotationClipboard.type) == nil)
        let bitmap = NSBitmapImageRep(data: board.data(forType: .png)!)!
        expectEqual(bitmap.pixelsWide, 320); expectEqual(bitmap.pixelsHigh, 200)
        expectNotNil(board.data(forType: .tiff))
        let rendered = Drawing.render(canvas.document.state.image, marks: canvas.document.state.marks)!
        let actual = Drawing.context(width: 320, height: 200)!, expected = Drawing.context(width: 320, height: 200)!
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
        actual.draw(bitmap.cgImage!, in: bounds); expected.draw(rendered, in: bounds)
        expectEqual(Data(bytes: actual.data!, count: actual.bytesPerRow * actual.height),
                    Data(bytes: expected.data!, count: expected.bytesPerRow * expected.height))
        var closed = false; editor.closed = { closed = true }
        expect(NSApp.sendAction(Selector(("done")), to: editor, from: nil))
        expect(closed); expectNotNil(board.data(forType: .png))
    }
    @MainActor func testPastedImageEditing() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let (window, canvas) = inputFixture(pasteboard: board)
        defer { window.contentView = nil }
        let source = image(width: 100, height: 50)
        board.setData(NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:])!, forType: .png)
        expect(AnnotationClipboard.canPaste(from: board))
        canvas.paste(nil)
        let mark = canvas.document.state.marks[0]
        expectEqual(mark.tool, .image); expectEqual(mark.frame.size, CGSize(width: 100, height: 50))
        expectEqual(mark.image?.width, 100); expectEqual(mark.image?.height, 50)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, mark.center))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, CGPoint(x: mark.center.x + 10, y: mark.center.y + 15)))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, CGPoint(x: mark.center.x + 10, y: mark.center.y + 15)))
        let moved = canvas.document.state.marks[0]
        expectEqual(moved.frame, mark.frame.offsetBy(dx: 10, dy: 15))
        let corner = moved.handles[3], end = CGPoint(x: corner.x + 20, y: corner.y + 30)
        canvas.mouseDown(with: mouse(.leftMouseDown, window, corner))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, end))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, end))
        expectEqual(canvas.document.state.marks[0].frame.width / canvas.document.state.marks[0].frame.height, 2)
        canvas.copy(nil); canvas.paste(nil)
        expectEqual(canvas.document.state.marks.count, 2)
        expect(canvas.document.state.marks[0].id != canvas.document.state.marks[1].id)
        canvas.undo(); canvas.undo(); expectEqual(canvas.document.state.marks, [moved])
        canvas.undo(); expectEqual(canvas.document.state.marks, [mark])
        canvas.undo(); expect(canvas.document.state.marks.isEmpty)
        canvas.redo(); expectEqual(canvas.document.state.marks, [mark])
        // A pasted image is movable while selected; drawing inside it remains possible.
        canvas.tool = .rectangle
        canvas.mouseDown(with: mouse(.leftMouseDown, window, mark.center))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, window, CGPoint(x: mark.center.x + 20, y: mark.center.y + 10)))
        canvas.mouseUp(with: mouse(.leftMouseUp, window, CGPoint(x: mark.center.x + 20, y: mark.center.y + 10)))
        expectEqual(canvas.document.state.marks.map(\.tool), [.image, .rectangle])
        expectEqual(canvas.document.state.marks[0], mark)
    }
    @MainActor func testImageLayerClipboardAndFiles() {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let source = image(width: 80, height: 40)
        let mark = Annotation(tool: .image, frame: CGRect(x: 20, y: 30, width: 160, height: 80), angle: 0.6, image: source)
        expect(AnnotationClipboard.write(mark, to: board))
        let copy = AnnotationClipboard.read(from: board)!
        expect(copy.id != mark.id); expectEqual(copy.frame, mark.frame); expectEqual(copy.angle, mark.angle)
        expectEqual(copy.image?.width, source.width); expectNotNil(board.data(forType: .png))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sicgo-image-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: path) }
        try! board.data(forType: .png)!.write(to: path)
        board.clearContents(); expect(board.writeObjects([path as NSURL]))
        expectEqual(AnnotationClipboard.readImage(from: board)?.width, 80)
        expect(FileManager.default.fileExists(atPath: path.path))
        board.clearContents(); board.setData(Data("bad image".utf8), forType: .png)
        expect(AnnotationClipboard.readImage(from: board) == nil)
        board.clearContents(); board.setString("ordinary text", forType: .string)
        expectFalse(AnnotationClipboard.canPaste(from: board))
    }
    @MainActor func testRotationKeepsWindowFrame() {
        let editor = EditorWindow(image: image(width: 800, height: 400), title: "Fixed rotation")
        let window = editor.window!, canvas = editor.canvas
        let mark = Annotation(tool: .image, frame: CGRect(x: 100, y: 90, width: 120, height: 60), image: image(width: 60, height: 30))
        canvas.document.change { $0.marks.append(mark) }
        let frame = window.frame, size = canvas.bounds.size
        canvas.rotateImage()
        expectEqual(window.frame, frame); expectEqual(canvas.bounds.size, size)
        expectEqual(canvas.document.size, CGSize(width: 400, height: 800))
        expectEqual(canvas.imageRect.midX, canvas.bounds.midX); expectEqual(canvas.imageRect.midY, canvas.bounds.midY)
        expect(abs(canvas.imageRect.width / canvas.imageRect.height - 0.5) < 0.00001)
        expect(canvas.annotationCursor(at: CGPoint(x: 1, y: canvas.bounds.midY)) == nil)
        expectEqual(canvas.document.state.marks[0].angle, .pi / 2)
        canvas.undo(); expectEqual(window.frame, frame); expectEqual(canvas.document.state.marks, [mark])
        canvas.redo(); expectEqual(window.frame, frame)
        for _ in 0..<3 { canvas.rotateImage(); expectEqual(window.frame, frame) }
        expectEqual(canvas.document.size, CGSize(width: 800, height: 400))
        expectEqual(canvas.document.state.marks[0].frame, mark.frame)
        canvas.document.crop(to: CGRect(x: 20, y: 20, width: 200, height: 200))
        expectEqual(window.frame, frame)
        canvas.undo(); expectEqual(window.frame, frame)
    }
    @MainActor func testImageLayerHistoryAndTransparency() {
        let patch = Drawing.context(width: 64, height: 32)!
        patch.setFillColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5).cgColor)
        patch.fill(CGRect(x: 16, y: 8, width: 32, height: 16))
        let layer = patch.makeImage()!, source = image(width: 320, height: 200)
        let mark = Annotation(tool: .image, frame: CGRect(x: 80, y: 80, width: 64, height: 32), image: layer)
        let rendered = Drawing.render(source, marks: [mark])!, bitmap = NSBitmapImageRep(cgImage: rendered)
        let center = bitmap.colorAt(x: 112, y: 103)!.usingColorSpace(.sRGB)!
        expect(center.redComponent > 0.98 && center.greenComponent > 0.4 && center.greenComponent < 0.8)
        let corner = bitmap.colorAt(x: 81, y: 118)!.usingColorSpace(.sRGB)!
        expect(corner.greenComponent > 0.98)
        let doc = EditorDocument(image: source, historyByteLimit: 100_000)
        doc.change { $0.marks.append(mark) }
        for _ in 0..<5 { doc.change { $0.marks[0].frame.origin.x += 1 } }
        expect(doc.historyByteEstimate < layer.bytesPerRow * layer.height)
        doc.change { $0.marks.removeAll() }
        expect(doc.historyByteEstimate >= layer.bytesPerRow * layer.height)
        doc.undo(); expect(doc.state.marks[0].image === layer)
        expect(doc.historyByteEstimate < layer.bytesPerRow * layer.height)
        let budgeted = EditorDocument(image: source, historyByteLimit: 1_000)
        budgeted.change { $0.marks.append(mark) }; budgeted.change { $0.marks.removeAll() }
        expect(budgeted.historyByteEstimate <= 1_000); expectFalse(budgeted.canUndo)
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
            Annotation(tool: .image, frame: CGRect(x: 15, y: 20, width: 130, height: 80), angle: 0.25, image: image(width: 70, height: 40)),
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
        defaults.set("unsupported", forKey: "interface.showHomeOnLaunch")
        let preferences = EditorPreferences(defaults: defaults)
        expectEqual(preferences.tool, .arrow)
        expectEqual(preferences.color, .systemRed)
        expect(preferences.windowTopLeft == nil)
        expectEqual(preferences.language, .english)
        expect(preferences.showHomeOnLaunch)
        defaults.set(["done", "missing", "done", "color"], forKey: "editor.toolbarOrder")
        expectEqual(preferences.toolbarOrder, [.done, .color] + ToolbarItem.allCases.filter { $0 != .done && $0 != .color })
        expectEqual(Set(preferences.toolbarOrder).count, ToolbarItem.allCases.count)
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
    @MainActor func testAnnotationPreferencesAlwaysRemember() {
        let domain = "local.SicGo.check.\(UUID().uuidString)", defaults: UserDefaults
        defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: defaults)
        preferences.tool = .text; preferences.color = .systemBlue
        let existing = EditorWindow(image: image(), title: "Existing", preferences: preferences)
        let existingColor = existing.canvas.color
        expectEqual(existing.canvas.tool, .text)
        let settings = SettingsWindow(preferences: preferences, loginItem: TestLoginItem())
        // Old opt-out and fixed defaults must not disable automatic remembering.
        defaults.set(false, forKey: "editor.rememberAnnotation")
        defaults.set(DrawingTool.pen.rawValue, forKey: "editor.defaultTool")
        defaults.set([0.0, 0.0, 0.0, 1.0], forKey: "editor.defaultColor")
        let next = EditorWindow(image: image(), title: "Next", preferences: preferences)
        expectEqual(next.canvas.tool, .text); expectEqual(next.canvas.color, existingColor)
        let rectangle = next.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "rectangle" }!.menuFormRepresentation!
        expect(NSApp.sendAction(rectangle.action!, to: rectangle.target, from: rectangle))
        let colorItem = next.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "color" }!
        let well = (colorItem.view as! NSStackView).arrangedSubviews[0] as! NSColorWell
        well.color = NSColor(srgbRed: 0.1, green: 0.7, blue: 0.3, alpha: 1)
        expect(well.sendAction(well.action, to: well.target))
        let reopened = EditorWindow(image: image(), title: "Reopened", preferences: preferences)
        expectEqual(reopened.canvas.tool, .rectangle); expectEqual(reopened.canvas.color, well.color)
        expectEqual(existing.canvas.tool, .text); expectEqual(existing.canvas.color, existingColor)
        settings.showHomeButton.state = .off
        expect(settings.showHomeButton.sendAction(settings.showHomeButton.action, to: settings.showHomeButton.target))
        expectFalse(preferences.showHomeOnLaunch)
    }
    @MainActor func testToolbarReorderingPreservesEditing() {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: domain)!
        defer { isolated.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: isolated)
        let editor = EditorWindow(image: image(), title: "Reorder", preferences: preferences)
        let other = EditorWindow(image: image(), title: "Other", preferences: preferences)
        let mark = Annotation(tool: .rectangle, frame: CGRect(x: 10, y: 10, width: 60, height: 40))
        editor.canvas.document.change { $0.marks.append(mark) }
        let frame = editor.window!.frame, pixels = editor.canvas.document.state.image, tool = editor.canvas.tool
        let settings = SettingsWindow(preferences: preferences, loginItem: TestLoginItem())
        settings.toolbarOrderChanged = { editor.applyToolbarOrder(); other.applyToolbarOrder() }
        expect(settings.toolbarOrderView.move(.done, by: -14))
        let expected = [ToolbarItem.done] + ToolbarItem.allCases.filter { $0 != .done }
        expectEqual(preferences.toolbarOrder, expected)
        func order(_ controller: EditorWindow) -> [ToolbarItem] {
            controller.window!.toolbar!.items.compactMap { ToolbarItem(rawValue: $0.itemIdentifier.rawValue) }
        }
        expectEqual(order(editor), expected); expectEqual(order(other), expected)
        expectEqual(order(EditorWindow(image: image(), title: "New", preferences: preferences)), expected)
        expectEqual(editor.window!.frame, frame); expectEqual(editor.canvas.tool, tool)
        expectEqual(editor.canvas.document.state.marks, [mark]); expect(editor.canvas.document.state.image === pixels)
        let rectangle = editor.window!.toolbar!.items.first { $0.itemIdentifier.rawValue == "rectangle" }!.menuFormRepresentation!
        expect(NSApp.sendAction(rectangle.action!, to: rectangle.target, from: rectangle))
        expectEqual(editor.canvas.tool, .rectangle)
        expect(NSApp.sendAction(NSSelectorFromString("resetToolbarOrder"), to: settings, from: nil))
        expectEqual(order(editor), ToolbarItem.allCases)
        expectEqual(editor.canvas.document.state.marks, [mark]); editor.canvas.undo(); expect(editor.canvas.document.state.marks.isEmpty)
    }
    @MainActor func testToolbarDragCommitAndCancel() {
        let domain = "local.SicGo.check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = EditorPreferences(defaults: defaults)
        let settings = SettingsWindow(preferences: preferences, loginItem: TestLoginItem())
        let window = settings.window!, strip = settings.toolbarOrderView
        window.contentView!.layoutSubtreeIfNeeded()
        let select = strip.subviews.first { $0.identifier?.rawValue == "select" } as! NSButton
        let last = strip.subviews.first { $0.identifier?.rawValue == "done" }!
        let start = strip.convert(CGPoint(x: select.frame.midX, y: select.frame.midY), to: nil)
        let end = strip.convert(CGPoint(x: last.frame.midX, y: last.frame.midY), to: nil)
        var changes = 0; settings.toolbarOrderChanged = { changes += 1 }
        select.mouseDown(with: mouse(.leftMouseDown, window, start))
        select.mouseDragged(with: mouse(.leftMouseDragged, window, end))
        expectEqual(changes, 0)
        select.mouseUp(with: mouse(.leftMouseUp, window, end))
        expectEqual(changes, 1); expectEqual(preferences.toolbarOrder.last, .select)
        let saved = preferences.toolbarOrder
        select.mouseDown(with: mouse(.leftMouseDown, window, end))
        select.mouseDragged(with: mouse(.leftMouseDragged, window, start))
        select.mouseUp(with: mouse(.leftMouseUp, window, strip.convert(CGPoint(x: -30, y: -30), to: nil)))
        expectEqual(preferences.toolbarOrder, saved); expectEqual(strip.order, saved); expectEqual(changes, 1)
        select.mouseDown(with: mouse(.leftMouseDown, window, end))
        select.mouseDragged(with: mouse(.leftMouseDragged, window, start))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        select.keyDown(with: escape); select.mouseUp(with: mouse(.leftMouseUp, window, start))
        expectEqual(strip.order, saved); expectEqual(changes, 1)
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
        expectEqual(done?.view?.accessibilityLabel(), "完成")
        expectEqual((done?.view as? NSButton)?.imagePosition, .imageOnly)
        expectEqual(editor.canvas.document.state.marks.first?.id, mark.id)
        expect(editor.canvas.document.state.image === pixels)
        expectEqual(editor.window!.frame, frame)
        expect(editor.canvas.document.canUndo)
        overrides["interface.language"] = InterfaceLanguage.english.rawValue
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        editor.updateLocalization()
        expectEqual(done?.view?.accessibilityLabel(), "Done")
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
