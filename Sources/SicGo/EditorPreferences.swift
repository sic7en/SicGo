import AppKit

/// Small UI preferences only; images and annotations never enter UserDefaults.
struct EditorPreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var language: InterfaceLanguage {
        get { defaults.string(forKey: "interface.language").flatMap(InterfaceLanguage.init(rawValue:)) ?? .english }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "interface.language") }
    }
    var showHomeOnLaunch: Bool {
        get { defaults.object(forKey: "interface.showHomeOnLaunch") as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: "interface.showHomeOnLaunch") }
    }
    var toolbarOrder: [ToolbarItem] {
        get { ToolbarItem.normalized((defaults.stringArray(forKey: "editor.toolbarOrder") ?? []).compactMap(ToolbarItem.init(rawValue:))) }
        nonmutating set { defaults.set(ToolbarItem.normalized(newValue).map(\.rawValue), forKey: "editor.toolbarOrder") }
    }
    var textFontName: String? {
        get {
            guard let name = defaults.string(forKey: "editor.textFontName"), name.utf8.count <= 256,
                  NSFont(name: name, size: 13) != nil else { return nil }
            return name
        }
        nonmutating set {
            if let name = newValue, name.utf8.count <= 256, NSFont(name: name, size: 13) != nil {
                defaults.set(name, forKey: "editor.textFontName")
            } else { defaults.removeObject(forKey: "editor.textFontName") }
        }
    }

    var tool: DrawingTool {
        get {
            let tool = defaults.string(forKey: "editor.tool").flatMap(DrawingTool.init(rawValue:)) ?? .arrow
            return tool == .image ? .arrow : tool
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "editor.tool") }
    }
    var color: NSColor {
        get { readColor(forKey: "editor.color") }
        nonmutating set { writeColor(newValue, forKey: "editor.color") }
    }
    private func readColor(forKey key: String) -> NSColor {
        guard let rgba = defaults.array(forKey: key) as? [Double], rgba.count == 4,
              rgba.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return .systemRed }
        return NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])
    }
    private func writeColor(_ value: NSColor, forKey key: String) {
        guard let color = value.usingColorSpace(.sRGB) else { return }
        defaults.set([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], forKey: key)
    }
    var windowTopLeft: CGPoint? {
        get {
            guard let point = defaults.array(forKey: "editor.windowTopLeft") as? [Double], point.count == 2,
                  point.allSatisfy(\.isFinite) else { return nil }
            return CGPoint(x: point[0], y: point[1])
        }
        nonmutating set {
            if let point = newValue, point.x.isFinite, point.y.isFinite {
                defaults.set([point.x, point.y], forKey: "editor.windowTopLeft")
            } else { defaults.removeObject(forKey: "editor.windowTopLeft") }
        }
    }
    static func visibleTopLeft(_ point: CGPoint, windowSize: CGSize, screen: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, screen.minX), max(screen.minX, screen.maxX - windowSize.width)),
                y: min(max(point.y, min(screen.maxY, screen.minY + windowSize.height)), screen.maxY))
    }
}
