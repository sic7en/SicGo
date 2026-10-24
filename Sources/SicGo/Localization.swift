import Foundation

enum InterfaceLanguage: String, CaseIterable {
    case system, english = "en", simplifiedChinese = "zh-Hans"

    func resolved(preferredLanguages: [String]) -> InterfaceLanguage {
        guard self == .system else { return self }
        // Choose the first language SicGo supports, falling back to English.
        for language in preferredLanguages {
            switch language.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            case "zh": return .simplifiedChinese
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

/// App-owned text only. Stable tool identifiers and user image/text content are never translated.
enum UIString: String, CaseIterable {
    case settings = "Settings", settingsMenu = "Settings…", language = "Interface language"
    case followSystem = "Follow System"
    case general = "General", annotationSettings = "Annotation"
    case launchAtLogin = "Launch at login", showHomeOnLaunch = "Show main window on launch"
    case loginApproval = "Allow SicGo in System Settings to launch at login."
    case loginSettings = "Open System Settings…", loginError = "Unable to change login settings"
    case rememberAnnotation = "Remember last tool and color"
    case annotationDefaultsHint = "Turn off to start every new image with the defaults below."
    case defaultTool = "Default tool", defaultColor = "Default color"
    case newImagesOnly = "Applies to new images. Current annotations stay unchanged."
    case file = "File", edit = "Edit", about = "About SicGo", quit = "Quit SicGo"
    case systemScreenshot = "Screenshot…", openImage = "Open Image…"
    case newFromClipboard = "New from Clipboard", show = "Show Main Window", close = "Close"
    case cut = "Cut", copy = "Copy", paste = "Paste", selectAll = "Select All"
    case homeDescription = "⇧⌘4  Capture. Annotate. Copy.", fromClipboard = "From Clipboard"
    case receptionHint = "System screenshots open here · No history"
    case receptionUnavailable = "Screenshot reception unavailable"
    case credits = "Annotate system screenshots, copy, and close."
    case open = "Open", ok = "OK", error = "Unable to complete the operation"
    case clipboardEmpty = "No image on the clipboard", clipboardHint = "Copy an image, then try again."
    case clipboard = "Clipboard", screenshot = "Screenshot"
    case select = "Select", rectangle = "Rectangle", ellipse = "Ellipse", arrow = "Arrow"
    case pen = "Pen", text = "Text", mosaic = "Mosaic", crop = "Crop"
    case annotationColor = "Annotation color", undo = "Undo", redo = "Redo", done = "Done"
    case copyAndClose = "Copy and close (⌘Return)", rotateImage = "Rotate image"
    case copyImage = "Copy image", discard = "Discard", tools = "Tools", color = "Color", history = "History"
    case copyFailed = "Unable to copy image", annotationCanvas = "Annotation canvas", annotationText = "Annotation text"

    var chinese: String {
        switch self {
        case .settings: return "设置"
        case .settingsMenu: return "设置…"
        case .language: return "界面语言"
        case .followSystem: return "跟随系统"
        case .general: return "通用"
        case .annotationSettings: return "标注"
        case .launchAtLogin: return "登录时启动 SicGo"
        case .showHomeOnLaunch: return "启动时显示主窗口"
        case .loginApproval: return "请在系统设置中允许 SicGo 登录时启动。"
        case .loginSettings: return "打开系统设置…"
        case .loginError: return "无法更改登录启动设置"
        case .rememberAnnotation: return "记住上次的工具和颜色"
        case .annotationDefaultsHint: return "关闭后，每张新图片都使用下方默认值。"
        case .defaultTool: return "默认工具"
        case .defaultColor: return "默认颜色"
        case .newImagesOnly: return "仅影响新打开的图片，当前标注保持不变。"
        case .file: return "文件"
        case .edit: return "编辑"
        case .about: return "关于 SicGo"
        case .quit: return "退出 SicGo"
        case .systemScreenshot: return "截屏…"
        case .openImage: return "打开图片…"
        case .newFromClipboard: return "粘贴图片"
        case .show: return "显示主窗口"
        case .close: return "关闭"
        case .cut: return "剪切"
        case .copy: return "复制"
        case .paste: return "粘贴"
        case .selectAll: return "全选"
        case .homeDescription: return "⇧⌘4  截图、标注、复制。"
        case .fromClipboard: return "从剪贴板打开"
        case .receptionHint: return "自动接收系统截图 · 不保留历史"
        case .receptionUnavailable: return "暂时无法接收系统截图"
        case .credits: return "标注系统截图，复制后即可关闭。"
        case .open: return "打开"
        case .ok: return "好"
        case .error: return "无法完成操作"
        case .clipboardEmpty: return "剪贴板中没有图片"
        case .clipboardHint: return "请先复制一张图片，再试一次。"
        case .clipboard: return "剪贴板"
        case .screenshot: return "截图"
        case .select: return "选择"
        case .rectangle: return "方框"
        case .ellipse: return "椭圆"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .text: return "文字"
        case .mosaic: return "马赛克"
        case .crop: return "裁剪"
        case .annotationColor: return "标注颜色"
        case .undo: return "撤销"
        case .redo: return "重做"
        case .done: return "完成"
        case .copyAndClose: return "复制并关闭（⌘Return）"
        case .rotateImage: return "旋转图片"
        case .copyImage: return "复制图片"
        case .discard: return "丢弃"
        case .tools: return "标注工具"
        case .color: return "颜色"
        case .history: return "撤销与重做"
        case .copyFailed: return "无法复制图片"
        case .annotationCanvas: return "标注画布"
        case .annotationText: return "标注文字"
        }
    }
}

func localized(_ key: UIString, language: InterfaceLanguage = EditorPreferences().language,
               preferredLanguages: [String] = Locale.preferredLanguages) -> String {
    language.resolved(preferredLanguages: preferredLanguages) == .simplifiedChinese ? key.chinese : key.rawValue
}

extension DrawingTool {
    var label: String { localized(labelKey) }
    var labelKey: UIString {
        let key: UIString
        switch self {
        case .select: key = .select
        case .rectangle: key = .rectangle
        case .ellipse: key = .ellipse
        case .arrow: key = .arrow
        case .pen: key = .pen
        case .text: key = .text
        case .mosaic: key = .mosaic
        case .crop: key = .crop
        }
        return key
    }
}
