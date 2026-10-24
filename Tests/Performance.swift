import AppKit

@main
struct RenderingPerformance {
    @MainActor static func main() {
        let context = Drawing.context(width: 1920, height: 1080)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        for i in 0..<80 {
            context.setFillColor(NSColor(srgbRed: Double(i % 5) / 4, green: Double(i % 7) / 6, blue: 0.4, alpha: 1).cgColor)
            context.fill(CGRect(x: (i * 41) % 1800, y: (i * 67) % 1000, width: 160, height: 90))
        }
        let image = context.makeImage()!
        for count in [0, 6, 10, 12] {
            let marks = (0..<count).map { index in
                Annotation(tool: .mosaic, frame: CGRect(x: 200 + index * 40, y: 250 + index * 20, width: 420, height: 280), angle: Double(index % 3) * 0.17)
            }
            var times: [Double] = []
            for _ in 0..<3 {
                autoreleasepool {
                    let start = CFAbsoluteTimeGetCurrent()
                    let result = Drawing.render(image, marks: marks)!
                    precondition(result.width == image.width && result.height == image.height)
                    times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
                }
            }
            print("mosaics=\(count) median_ms=\(String(format: "%.2f", times.sorted()[1]))")
        }
    }
}
