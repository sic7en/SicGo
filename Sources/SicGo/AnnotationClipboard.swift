import AppKit
import ImageIO

enum AnnotationClipboard {
    static let type = NSPasteboard.PasteboardType("local.makstton.SicGo.annotation")
    private static let maximumBytes = 8 * 1024 * 1024
    private static let maximumImageBytes = 64 * 1024 * 1024
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic")]

    private struct Payload: Codable {
        let version: Int
        let tool: String
        let frame: CGRect
        let angle: CGFloat
        let rgba: [CGFloat]
        let vertices: [CGPoint]
        let text: String
        let textLayout: CGSize
        let fontSize: CGFloat
        let fontName: String?
        let imagePNG: Data?
    }

    static func write(_ mark: Annotation, to pasteboard: NSPasteboard) -> Bool {
        guard let color = mark.color.usingColorSpace(.sRGB) else { return false }
        let png = mark.image.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        guard mark.tool != .image || png != nil else { return false }
        let payload = Payload(version: mark.tool == .image ? 2 : 1, tool: mark.tool.rawValue, frame: mark.frame, angle: mark.angle,
                              rgba: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent],
                              vertices: mark.vertices, text: mark.text, textLayout: mark.textLayout, fontSize: mark.fontSize, fontName: mark.fontName, imagePNG: png)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        guard let data = try? encoder.encode(payload), data.count <= (mark.tool == .image ? maximumImageBytes : maximumBytes) else { return false }
        let item = NSPasteboardItem(); item.setData(data, forType: type)
        if mark.tool == .image, let png { item.setData(png, forType: .png) }
        if mark.tool == .text { item.setString(mark.text, forType: .string) }
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func read(from pasteboard: NSPasteboard) -> Annotation? {
        guard let data = pasteboard.data(forType: type), data.count <= maximumImageBytes,
              let payload = try? PropertyListDecoder().decode(Payload.self, from: data),
              let tool = DrawingTool(rawValue: payload.tool), tool != .select, tool != .crop,
              (payload.version == 1 && tool != .image && data.count <= maximumBytes) || (payload.version == 2 && tool == .image),
              payload.rgba.count == 4, payload.rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              payload.angle.isFinite, payload.fontSize.isFinite, payload.fontSize > 0,
              payload.frame.width > 0, payload.frame.height > 0,
              payload.textLayout.width >= 0, payload.textLayout.height >= 0,
              (payload.fontName?.utf8.count ?? 0) <= 256 else { return nil }
        let geometry = [payload.frame.minX, payload.frame.minY, payload.frame.width, payload.frame.height,
                        payload.textLayout.width, payload.textLayout.height, payload.fontSize]
        guard geometry.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
              payload.vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              tool != .arrow || payload.vertices.count == 2,
              tool != .pen || payload.vertices.count >= 2 else { return nil }
        let image = payload.imagePNG.flatMap { decodeImage(CGImageSourceCreateWithData($0 as CFData, nil)) }
        guard tool != .image || image != nil else { return nil }
        // Each paste is a new editable object; do not serialize or reuse its identity.
        return Annotation(tool: tool, frame: payload.frame, angle: payload.angle,
                          color: NSColor(srgbRed: payload.rgba[0], green: payload.rgba[1], blue: payload.rgba[2], alpha: payload.rgba[3]),
                          vertices: payload.vertices, text: payload.text, textLayout: payload.textLayout, fontSize: payload.fontSize, fontName: payload.fontName, image: image)
    }

    static func canPaste(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [type, .fileURL] + imageTypes) != nil
    }
    static func readImage(from pasteboard: NSPasteboard) -> CGImage? {
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), data.count <= maximumImageBytes,
               let image = decodeImage(CGImageSourceCreateWithData(data as CFData, nil)) { return image }
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first, url.isFileURL {
            return decodeImage(CGImageSourceCreateWithURL(url as CFURL, nil))
        }
        return nil
    }
    private static func decodeImage(_ source: CGImageSource?) -> CGImage? {
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32768, height <= 32768, width * height <= 32 * 1024 * 1024 else { return nil }
        // Keep original pixels and EXIF orientation; never upscale or re-encode in history.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
