import AppKit

@MainActor
private final class AnnotationTextView: NSTextView {
    var editingEnded: () -> Void = {}
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { editingEnded() }
        return accepted
    }
}

@MainActor
final class EditorCanvas: NSView, NSTextViewDelegate {
    let document: EditorDocument
    var tool: DrawingTool = .arrow { didSet { finishText(); selection = nil; needsDisplay = true; refreshCursor() } }
    var color: NSColor = .systemRed
    var onChange: () -> Void = {}
    var onCopy: () -> Void = {}
    private var selection: UUID?
    private var tracking: NSTrackingArea?
    private var ownsCursor = false
    private enum Drag { case draw, move, handle(Int) }
    private var drag: Drag?
    private var initial: EditorDocument.State?
    private var origin = CGPoint.zero
    private var trail: [CGPoint] = []
    private var draft: Annotation?
    private var textView: AnnotationTextView?
    private weak var textCommitClick: NSEvent?
    private var textBefore: EditorDocument.State?
    private var textMark: Annotation?
    private var textOrigin = CGPoint.zero
    private var rotationBefore: EditorDocument.State?
    private var rotation: CGFloat = 0

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        updateLocalization()
        document.changed = { [weak self] in
            guard let self else { return }
            self.needsDisplay = true; self.onChange()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateLocalization() {
        setAccessibilityLabel(localized(.annotationCanvas))
        textView?.setAccessibilityLabel(localized(.annotationText))
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var imageRect: CGRect {
        let factor = min(bounds.width / document.size.width, bounds.height / document.size.height)
        let size = CGSize(width: document.size.width * factor, height: document.size.height * factor)
        return CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    private var scale: CGFloat { max(0.001, imageRect.width / document.size.width) }
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - imageRect.minX) / scale, y: (p.y - imageRect.minY) / scale)
    }
    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(document.size.width, max(0, p.x)), y: min(document.size.height, max(0, p.y)))
    }
    private var selectedIndex: Int? { document.state.marks.firstIndex { $0.id == selection } }
    private func handle(at p: CGPoint, on mark: Annotation) -> Int? {
        mark.handles.firstIndex { hypot($0.x - p.x, $0.y - p.y) <= 8 / scale }
    }
    private func hit(_ p: CGPoint) -> Annotation? {
        document.state.marks.last { $0.hit(p, tolerance: 5 / scale, includeInterior: tool == .select) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        // cursorUpdate lets AppKit restore the destination view's cursor on exit.
        tracking = NSTrackingArea(rect: imageRect.intersection(visibleRect), options: [.activeInKeyWindow, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(tracking!)
    }
    func annotationCursor(at location: CGPoint) -> NSCursor? {
        guard imageRect.contains(location), visibleRect.contains(location) else { return nil }
        if let textView, textView.frame.contains(location) { return .iBeam }
        let p = CGPoint(x: (location.x - imageRect.minX) / scale, y: (location.y - imageRect.minY) / scale)
        if let i = selectedIndex, let index = handle(at: p, on: document.state.marks[i]) {
            let mark = document.state.marks[i]
            if mark.tool == .arrow { return .crosshair }
            if #available(macOS 15, *) {
                let h = mark.handles[index]
                let position: NSCursor.FrameResizePosition = h.x < mark.center.x
                    ? (h.y < mark.center.y ? .bottomLeft : .topLeft)
                    : (h.y < mark.center.y ? .bottomRight : .topRight)
                return .frameResize(position: position, directions: .all)
            } else { return .crosshair }
        } else if let mark = hit(p), mark.tool == .text || tool == .select || mark.id == selection { return .openHand }
        return tool == .text ? .iBeam : tool == .select ? .arrow : .crosshair
    }
    private func applyCursor(at location: CGPoint) {
        guard let window, window.isKeyWindow, NSApp.isActive, !isHiddenOrHasHiddenAncestor,
              let cursor = annotationCursor(at: location) else { return }
        ownsCursor = true; cursor.set()
    }
    private func updateCursor(with event: NSEvent) {
        guard let window, event.window === window else { return }
        applyCursor(at: convert(event.locationInWindow, from: nil))
    }
    override func cursorUpdate(with event: NSEvent) { updateCursor(with: event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(with: event) }
    override func mouseExited(with event: NSEvent) { ownsCursor = false }
    private func refreshCursor() {
        guard let window else { return }
        applyCursor(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
    func releaseCursor() {
        guard ownsCursor else { return }
        ownsCursor = false; NSCursor.arrow.set()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { releaseCursor() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.translateBy(x: imageRect.minX, y: imageRect.minY); ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        var marks = document.state.marks
        if let draft, draft.tool != .crop { marks.append(draft) }
        Drawing.scene(document.state.image, marks: marks, in: ctx)
        if let draft, draft.tool == .crop {
            ctx.setLineWidth(1 / scale); ctx.setStrokeColor(NSColor.white.cgColor); ctx.stroke(draft.frame)
            ctx.setLineDash(phase: 0, lengths: [5 / scale, 5 / scale])
            ctx.setStrokeColor(NSColor.darkGray.cgColor); ctx.stroke(draft.frame)
        }
        if textView == nil, draft == nil, let i = selectedIndex {
            ctx.setLineDash(phase: 0, lengths: []); ctx.setLineWidth(1 / scale)
            ctx.setStrokeColor(NSColor(white: 0.25, alpha: 1).cgColor); ctx.setFillColor(NSColor.white.cgColor)
            for p in document.state.marks[i].handles {
                let box = CGRect(x: p.x - 3 / scale, y: p.y - 3 / scale, width: 6 / scale, height: 6 / scale)
                ctx.fill(box); ctx.stroke(box)
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        let wasEditingText = textView != nil || textCommitClick === event
        textCommitClick = nil
        finishRotation(cancel: false); finishText()
        window?.makeFirstResponder(self)
        let p = point(event)
        initial = document.state; origin = p; trail = []
        guard imageRect.contains(convert(event.locationInWindow, from: nil)) else { initial = nil; return }
        let target = hit(p)
        if let target, target.tool == .text, event.clickCount >= 2 {
            startText(at: p, editing: target); return
        }
        if let i = selectedIndex, let h = handle(at: p, on: document.state.marks[i]) { drag = .handle(h); return }
        if let target, target.tool == .text || target.id == selection || tool == .select {
            selection = target.id; drag = .move; needsDisplay = true; return
        }
        selection = nil
        // The first click outside the text commits it; it must not immediately open
        // another empty editor at the same click location.
        if wasEditingText { initial = nil; needsDisplay = true; refreshCursor(); return }
        if tool == .text { startText(at: p, editing: nil); return }
        if tool == .select { initial = nil; needsDisplay = true; return }
        drag = .draw; trail = [clamp(p)]
    }
    override func mouseDragged(with event: NSEvent) {
        guard let drag, let initial else { return }
        let p = point(event)
        switch drag {
        case .draw:
            if tool == .pen { trail.append(clamp(p)) } else { trail = [clamp(origin), clamp(p)] }
            var mark = Annotation(tool: tool, frame: .zero, color: color)
            mark.setVertices(trail); draft = mark; needsDisplay = true
        case .move, .handle:
            guard let index = initial.marks.firstIndex(where: { $0.id == selection }) else { return }
            let original = initial.marks[index]
            var mark = original
            if case .move = drag { mark.frame = original.frame.offsetBy(dx: p.x - origin.x, dy: p.y - origin.y) }
            else if case .handle(let h) = drag {
                if mark.tool == .arrow {
                    var points = original.handles
                    var end = p
                    if event.modifierFlags.contains(.shift) {
                        let anchor = points[1 - h], radius = hypot(p.x - anchor.x, p.y - anchor.y)
                        let a = (atan2(p.y - anchor.y, p.x - anchor.x) / (.pi / 4)).rounded() * (.pi / 4)
                        end = CGPoint(x: anchor.x + radius * cos(a), y: anchor.y + radius * sin(a))
                    }
                    points[h] = end; mark.angle = 0; mark.setVertices(points)
                } else {
                    let anchor = original.handles[3 - h]
                    let local = rotatePoint(p, around: anchor, by: -original.angle)
                    let sx: CGFloat = h % 2 == 0 ? -1 : 1, sy: CGFloat = h < 2 ? -1 : 1
                    var w = max(6, (local.x - anchor.x) * sx), height = max(6, (local.y - anchor.y) * sy)
                    if event.modifierFlags.contains(.shift) {
                        let ratio = original.frame.width / original.frame.height
                        if w / height > ratio { height = w / ratio } else { w = height * ratio }
                    }
                    let center = rotatePoint(CGPoint(x: anchor.x + sx * w / 2, y: anchor.y + sy * height / 2), around: anchor, by: original.angle)
                    mark.frame = CGRect(x: center.x - w / 2, y: center.y - height / 2, width: w, height: height)
                }
            }
            var preview = initial; preview.marks[index] = mark; document.preview(preview)
        }
    }
    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; initial = nil; trail = []; draft = nil; needsDisplay = true }
        guard let drag, let initial else { return }
        if case .draw = drag {
            if let draft, hypot(point(event).x - origin.x, point(event).y - origin.y) > 2 / scale {
                if draft.tool == .crop { document.crop(to: draft.frame) }
                else { document.change { $0.marks.append(draft) }; selection = draft.id }
            } else { selection = hit(point(event))?.id }
        } else if document.state.marks != initial.marks { document.commit(from: initial) }
        refreshCursor()
    }
    func changeColor(_ color: NSColor) {
        finishText(); self.color = color
        if let i = selectedIndex { document.change { $0.marks[i].color = color } }
    }
    func undo() { finishText(); cancelDrag(); selection = nil; document.undo(); refreshCursor() }
    func redo() { finishText(); cancelDrag(); selection = nil; document.redo(); refreshCursor() }
    func rotateImage() { finishText(); cancelDrag(); selection = nil; document.rotateImage(); refreshCursor() }
    private func cancelDrag() {
        if let initial { document.preview(initial) }
        initial = nil; draft = nil; drag = nil; trail = []; finishRotation(cancel: true)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelDrag(); selection = nil; needsDisplay = true; refreshCursor(); return }
        if [51, 117].contains(event.keyCode), let selection {
            document.change { $0.marks.removeAll { $0.id == selection } }; self.selection = nil; refreshCursor(); return
        }
        super.keyDown(with: event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if textView == nil, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            event.modifierFlags.contains(.shift) ? redo() : undo(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    @objc func copy(_ sender: Any?) { onCopy() }
    override func rotate(with event: NSEvent) {
        if event.phase.contains(.cancelled) { finishRotation(cancel: true); return }
        guard textView == nil, let i = selectedIndex else { return }
        if rotationBefore == nil {
            guard document.state.marks[i].frame.contains(document.state.marks[i].toLocal(point(event))) else { return }
            rotationBefore = document.state; rotation = 0
        }
        guard let before = rotationBefore else { return }
        rotation += CGFloat(event.rotation) * .pi / 180
        var next = before; next.marks[i].angle += rotation; document.preview(next)
        if event.phase.contains(.ended) { finishRotation(cancel: false) }
    }
    override func endGesture(with event: NSEvent) { finishRotation(cancel: event.phase.contains(.cancelled)) }
    private func finishRotation(cancel: Bool) {
        guard let before = rotationBefore else { return }
        rotationBefore = nil
        if cancel { document.preview(before) } else if abs(rotation) > 0.00001 { document.commit(from: before) }
        rotation = 0
    }
    private func startText(at p: CGPoint, editing mark: Annotation?) {
        textBefore = document.state; textMark = mark
        textOrigin = mark.map { CGPoint(x: $0.frame.minX, y: $0.frame.maxY) } ?? p
        if let mark { var next = document.state; next.marks.removeAll { $0.id == mark.id }; document.preview(next) }
        initial = nil; selection = nil; drag = nil
        let field = AnnotationTextView(frame: .zero)
        field.isRichText = false; field.drawsBackground = false; field.textContainerInset = .zero
        field.textContainer?.lineFragmentPadding = 0
        field.isHorizontallyResizable = false; field.isVerticallyResizable = false
        field.textContainer?.widthTracksTextView = false; field.textContainer?.heightTracksTextView = false
        field.textColor = mark?.color ?? color; field.insertionPointColor = mark?.color ?? color
        field.string = mark?.text ?? ""; field.delegate = self; field.allowsUndo = true
        field.setAccessibilityLabel(localized(.annotationText))
        field.editingEnded = { [weak self] in self?.finishText(restoreFocus: false, triggeredBy: NSApp.currentEvent) }
        textView = field; addSubview(field); layoutText(); window?.makeFirstResponder(field)
        if mark != nil { field.selectAll(nil) }
        refreshCursor()
    }
    override func layout() { super.layout(); layoutText() }
    func textDidChange(_ notification: Notification) { layoutText() }
    private var editingFontSize: CGFloat {
        guard let mark = textMark else { return 30 }
        return mark.fontSize * mark.frame.height / max(1, mark.textLayout.height)
    }
    private func layoutText() {
        guard let field = textView else { return }
        let x = imageRect.minX + textOrigin.x * scale, top = imageRect.minY + textOrigin.y * scale
        field.font = .systemFont(ofSize: editingFontSize * scale, weight: .medium)
        let available = CGSize(width: max(30, imageRect.maxX - x), height: max(30, top - imageRect.minY))
        guard let container = field.textContainer, let manager = field.layoutManager else { return }
        container.containerSize = available
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let lineHeight = manager.defaultLineHeight(for: field.font!)
        let height = min(available.height, max(lineHeight, used.maxY, manager.extraLineFragmentRect.maxY))
        let width = min(available.width, max(30, used.maxX + 8))
        // Keep wrapping tied to the image edge while the clickable view hugs its text.
        field.frame = CGRect(x: x, y: top - height, width: width, height: height)
    }
    func finishText(restoreFocus: Bool = true, triggeredBy event: NSEvent? = nil) {
        finishRotation(cancel: false)
        guard let field = textView, let before = textBefore else { return }
        // AppKit may transfer focus before delivering mouseDown to the canvas.
        // Remember that same click so committing does not start a new text field.
        if let event, event.type == .leftMouseDown, event.window === window { textCommitClick = event }
        let text = field.string, ink = field.textColor ?? color, font = editingFontSize
        let available = max(1, (field.textContainer?.containerSize.width ?? field.frame.width) / scale)
        let editedMark = textMark
        textView = nil; textBefore = nil; textMark = nil
        field.editingEnded = {}; field.delegate = nil; field.removeFromSuperview()
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let measured = (text as NSString).boundingRect(with: CGSize(width: available, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: Drawing.textAttributes(ink, size: font))
            let size = CGSize(width: min(available, ceil(measured.width) + 3), height: max(font * 1.25, ceil(measured.height)))
            var mark = editedMark ?? Annotation(tool: .text, frame: .zero)
            mark.text = text; mark.color = ink; mark.fontSize = font; mark.textLayout = size
            mark.frame = CGRect(x: textOrigin.x, y: textOrigin.y - size.height, width: size.width, height: size.height)
            var next = document.state
            let slot = before.marks.firstIndex { $0.id == mark.id } ?? next.marks.count
            next.marks.insert(mark, at: min(slot, next.marks.count)); document.preview(next); selection = mark.id
        }
        if document.state.marks != before.marks { document.commit(from: before) }
        if restoreFocus { window?.makeFirstResponder(self) }
        needsDisplay = true; refreshCursor()
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), NSApp.currentEvent?.modifierFlags.contains(.shift) != true { finishText(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            let before = textBefore, field = self.textView
            self.textView = nil; textBefore = nil; textMark = nil
            field?.editingEnded = {}; field?.delegate = nil; field?.removeFromSuperview()
            if let before { document.preview(before) }
            window?.makeFirstResponder(self); refreshCursor(); return true
        }
        return false
    }
}
