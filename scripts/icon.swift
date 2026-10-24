import AppKit

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("SicGo-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200).fill()
    let shape = NSBezierPath(); shape.lineWidth = 42; shape.lineCapStyle = .round; shape.lineJoinStyle = .round
    for (x, y, dx, dy) in [(260.0, 720.0, 120.0, -120.0), (764, 720, -120, -120), (260, 304, 120, 120)] {
        shape.move(to: CGPoint(x: x + dx, y: y)); shape.line(to: CGPoint(x: x, y: y)); shape.line(to: CGPoint(x: x, y: y + dy))
    }
    shape.move(to: CGPoint(x: 550, y: 294)); shape.line(to: CGPoint(x: 782, y: 526))
    NSColor.white.setStroke(); shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) { try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png")) }
    if [32, 64, 256, 512, 1024].contains(size) { try data.write(to: iconset.appendingPathComponent("icon_\(size/2)x\(size/2)@2x.png")) }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", CommandLine.arguments[1]]
try process.run(); process.waitUntilExit(); exit(process.terminationStatus)
