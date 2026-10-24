import AppKit

@MainActor
final class EditorDocument {
    struct State { var image: CGImage; var marks: [Annotation] }
    private(set) var state: State
    private var past: [State] = []
    private var future: [State] = []
    private let historyByteLimit: Int
    var changed: () -> Void = {}

    init(image: CGImage, historyByteLimit: Int = 128 * 1024 * 1024) {
        state = State(image: image, marks: []); self.historyByteLimit = max(0, historyByteLimit)
    }
    var size: CGSize { CGSize(width: state.image.width, height: state.image.height) }
    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }
    func preview(_ state: State) { self.state = state; changed() }
    func commit(from previous: State) {
        past.append(previous)
        future.removeAll(); trimHistory(); changed()
    }
    func change(_ edit: (inout State) -> Void) {
        let previous = state; edit(&state); commit(from: previous)
    }
    // Count each retained image once, excluding the mandatory current image. Annotation
    // payloads are counted conservatively even when Swift shares their backing storage.
    var historyByteEstimate: Int {
        var images: Set<ObjectIdentifier> = [ObjectIdentifier(state.image)]
        var bytes = 0
        for snapshot in past + future {
            if images.insert(ObjectIdentifier(snapshot.image)).inserted {
                bytes += snapshot.image.bytesPerRow * snapshot.image.height
            }
            bytes += MemoryLayout<State>.stride + snapshot.marks.count * MemoryLayout<Annotation>.stride
            for mark in snapshot.marks {
                bytes += mark.vertices.count * MemoryLayout<CGPoint>.stride + mark.text.utf8.count
            }
        }
        return bytes
    }
    private func trimHistory() {
        while past.count + future.count > 30 || historyByteEstimate > historyByteLimit {
            // Drop distant undo/redo states first; the current image is never discarded.
            if !past.isEmpty { past.removeFirst() }
            else if !future.isEmpty { future.removeFirst() }
            else { break }
        }
    }
    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(state); state = previous; trimHistory(); changed()
    }
    func redo() {
        guard let next = future.popLast() else { return }
        past.append(state); state = next; trimHistory(); changed()
    }
    func crop(to region: CGRect) {
        let r = region.integral.intersection(CGRect(origin: .zero, size: size))
        guard r.width >= 8, r.height >= 8, let ctx = Drawing.context(width: Int(r.width), height: Int(r.height)) else { return }
        ctx.draw(state.image, in: CGRect(x: -r.minX, y: -r.minY, width: size.width, height: size.height))
        guard let cropped = ctx.makeImage() else { return }
        change { state in
            state.image = cropped
            state.marks = state.marks.filter { mark in
                let corners = mark.handles
                let xs = corners.map(\.x), ys = corners.map(\.y)
                let extent = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0,
                                    width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
                return extent.insetBy(dx: -3, dy: -3).intersects(r)
            }.map { original in var mark = original; mark.frame.origin.x -= r.minX; mark.frame.origin.y -= r.minY; return mark }
        }
    }
    func rotateImage() {
        guard let ctx = Drawing.context(width: state.image.height, height: state.image.width) else { return }
        let old = size
        ctx.translateBy(x: old.height, y: 0); ctx.rotate(by: .pi / 2)
        ctx.draw(state.image, in: CGRect(origin: .zero, size: old))
        guard let rotated = ctx.makeImage() else { return }
        change { state in
            state.image = rotated
            state.marks = state.marks.map { original in
                var mark = original
                mark.frame.origin = CGPoint(x: old.height - original.center.y - original.frame.width / 2,
                                            y: original.center.x - original.frame.height / 2)
                mark.angle += .pi / 2
                return mark
            }
        }
    }
}
