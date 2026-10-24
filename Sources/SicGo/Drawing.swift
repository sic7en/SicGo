import AppKit

enum DrawingTool: String, CaseIterable {
    case select = "Select", rectangle = "Rectangle", ellipse = "Ellipse"
    case arrow = "Arrow", pen = "Pen", text = "Text", mosaic = "Mosaic", crop = "Crop"

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .mosaic: return "square.grid.3x3.fill"
        case .crop: return "crop"
        }
    }
}

struct Annotation: Equatable {
    var id = UUID()
    var tool: DrawingTool
    var frame: CGRect
    var angle: CGFloat = 0
    var color: NSColor = .systemRed
    var vertices: [CGPoint] = []
    var text = ""
    var textLayout = CGSize.zero
    var fontSize: CGFloat = 30
    static let lineWidth: CGFloat = 3

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    func toWorld(_ point: CGPoint) -> CGPoint { rotatePoint(point, around: center, by: angle) }
    func toLocal(_ point: CGPoint) -> CGPoint { rotatePoint(point, around: center, by: -angle) }
    var handles: [CGPoint] {
        if tool == .arrow { return resolvedVertices.map(toWorld) }
        return [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)].map(toWorld)
    }
    var resolvedVertices: [CGPoint] {
        vertices.map { CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height) }
    }
    mutating func setVertices(_ points: [CGPoint]) {
        guard !points.isEmpty else { return }
        let xs = points.map(\.x), ys = points.map(\.y)
        let left = xs.min()!, bottom = ys.min()!
        frame = CGRect(x: left, y: bottom, width: max(1, xs.max()! - left), height: max(1, ys.max()! - bottom))
        vertices = points.map { CGPoint(x: ($0.x - left) / frame.width, y: ($0.y - bottom) / frame.height) }
    }
    func hit(_ point: CGPoint, tolerance: CGFloat, includeInterior: Bool) -> Bool {
        let p = toLocal(point)
        if includeInterior || tool == .text || tool == .mosaic {
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        }
        switch tool {
        case .rectangle:
            return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
                && !frame.insetBy(dx: tolerance, dy: tolerance).contains(p)
        case .ellipse:
            let rx = max(1, frame.width / 2), ry = max(1, frame.height / 2)
            return abs(hypot((p.x - frame.midX) / rx, (p.y - frame.midY) / ry) - 1) <= tolerance / min(rx, ry)
        case .arrow, .pen:
            let points = resolvedVertices
            return zip(points, points.dropFirst()).contains { distance(p, to: $0, end: $1) <= tolerance + Self.lineWidth / 2 }
        default: return false
        }
    }
}

func rotatePoint(_ p: CGPoint, around c: CGPoint, by radians: CGFloat) -> CGPoint {
    let x = p.x - c.x, y = p.y - c.y
    return CGPoint(x: c.x + x * cos(radians) - y * sin(radians), y: c.y + x * sin(radians) + y * cos(radians))
}

func distance(_ p: CGPoint, to a: CGPoint, end b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.001, dx * dx + dy * dy)))
    return hypot(p.x - a.x - dx * t, p.y - a.y - dy * t)
}

enum Drawing {
    static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
    static func render(_ image: CGImage, marks: [Annotation]) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height) else { return nil }
        scene(image, marks: marks, in: ctx)
        return ctx.makeImage()
    }
    static func scene(_ image: CGImage, marks: [Annotation], in ctx: CGContext) {
        // Every mosaic samples the preceding scene, but its tiny pixel grid is independent
        // of the destination. Build it once and reuse it for later mosaics in this draw.
        var patches = [CGImage?](repeating: nil, count: marks.count)
        for (index, mark) in marks.enumerated() where mark.tool == .mosaic {
            guard let grid = context(width: max(1, Int(mark.frame.width / 14)), height: max(1, Int(mark.frame.height / 14))) else { continue }
            grid.scaleBy(x: CGFloat(grid.width) / mark.frame.width, y: CGFloat(grid.height) / mark.frame.height)
            grid.translateBy(x: -mark.frame.minX, y: -mark.frame.minY)
            grid.translateBy(x: mark.center.x, y: mark.center.y)
            grid.rotate(by: -mark.angle)
            grid.translateBy(x: -mark.center.x, y: -mark.center.y)
            composite(image, marks: marks[..<index], patches: patches, in: grid)
            patches[index] = grid.makeImage()
        }
        composite(image, marks: marks[...], patches: patches, in: ctx)
    }
    private static func composite(_ image: CGImage, marks: ArraySlice<Annotation>, patches: [CGImage?], in ctx: CGContext) {
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for index in marks.indices {
            let mark = marks[index]
            ctx.saveGState()
            ctx.translateBy(x: mark.center.x, y: mark.center.y)
            ctx.rotate(by: mark.angle)
            ctx.translateBy(x: -mark.center.x, y: -mark.center.y)
            if mark.tool == .mosaic {
                if let patch = patches[index] {
                    ctx.interpolationQuality = .none
                    ctx.draw(patch, in: mark.frame)
                }
            } else { vector(mark, in: ctx) }
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
    static func vector(_ mark: Annotation, in ctx: CGContext) {
        ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(Annotation.lineWidth); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let points = mark.resolvedVertices
        switch mark.tool {
        case .rectangle: ctx.stroke(mark.frame)
        case .ellipse: ctx.strokeEllipse(in: mark.frame)
        case .arrow:
            guard let a = points.first, let b = points.last else { return }
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 1 else { return }
            let heading = atan2(b.y - a.y, b.x - a.x)
            let head = min(13, length * 0.4), half = head * 0.42
            let neck = CGPoint(x: b.x - cos(heading) * head, y: b.y - sin(heading) * head)
            ctx.move(to: a); ctx.addLine(to: neck); ctx.strokePath()
            ctx.move(to: b)
            ctx.addLine(to: CGPoint(x: neck.x - sin(heading) * half, y: neck.y + cos(heading) * half))
            ctx.addLine(to: CGPoint(x: neck.x + sin(heading) * half, y: neck.y - cos(heading) * half))
            ctx.closePath(); ctx.fillPath()
        case .pen:
            guard let first = points.first else { return }
            ctx.move(to: first)
            for p in points.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        case .text:
            guard mark.textLayout.width > 0, mark.textLayout.height > 0 else { return }
            ctx.saveGState()
            ctx.translateBy(x: mark.frame.minX, y: mark.frame.minY)
            ctx.scaleBy(x: mark.frame.width / mark.textLayout.width, y: mark.frame.height / mark.textLayout.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (mark.text as NSString).draw(with: CGRect(origin: .zero, size: mark.textLayout),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttributes(mark.color, size: mark.fontSize))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
        default: break
        }
    }
    static func textAttributes(_ color: NSColor, size: CGFloat) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
        return [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph]
    }
}
