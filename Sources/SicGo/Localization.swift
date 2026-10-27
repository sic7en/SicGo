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
    case settingsDescription = "Language, startup, and annotation preferences."
    case followSystem = "Follow System"
    case checkForUpdates = "Check for Updates…", downloadUpdate = "Download Update…"
    case updateHint = "Checks GitHub only when clicked. No background checks."
    case checkingUpdates = "Checking GitHub Releases…"
    case upToDate = "You're up to date. No newer release is available."
    case updateAvailable = "SicGo %@ is available. Open the release page to download. Finish editing before replacing the app."
    case updateUnavailable = "No public release is available yet. Try again later."
    case updateRateLimited = "GitHub is limiting requests. Please try again later."
    case updateInvalid = "Couldn't verify the release information. Please try again later."
    case updateNetworkError = "Couldn't connect to GitHub. Check your connection and try again."
    case general = "General", annotationSettings = "Annotation"
    case launchAtLogin = "Launch at login", showHomeOnLaunch = "Show main window on launch"
    case loginApproval = "Allow SicGo in System Settings to launch at login."
    case loginSettings = "Open System Settings…", loginError = "Unable to change login settings"
    case textFont = "Text font", systemFont = "System font", newTextOnly = "Used for new text annotations."
    case toolbarOrder = "Toolbar order", resetOrder = "Reset order"
    case toolbarOrderHint = "Drag to reorder, or focus an icon and use ← / →. Changes apply immediately."
    case moveLeft = "Move left", moveRight = "Move right"
    case file = "File", edit = "Edit", about = "About SicGo", quit = "Quit SicGo"
    case systemScreenshot = "Screenshot…", openImage = "Open Image…"
    case newFromClipboard = "New from Clipboard", show = "Show Main Window", close = "Close"
    case cut = "Cut", copy = "Copy", paste = "Paste", selectAll = "Select All"
    case homeDescription = "Capture. Annotate. Copy.", fromClipboard = "From Clipboard"
    case captureShortcut = "⇧⌘4  Capture a region"
    case receptionHint = "System screenshots open here · No history"
    case receptionUnavailable = "Screenshot reception unavailable"
    case credits = "Annotate system screenshots, copy, and close."
    case open = "Open", ok = "OK", error = "Unable to complete the operation"
    case clipboardEmpty = "No image on the clipboard", clipboardHint = "Copy an image, then try again."
    case clipboard = "Clipboard", screenshot = "Screenshot"
    case select = "Select", rectangle = "Rectangle", ellipse = "Ellipse", arrow = "Arrow"
    case pen = "Pen", text = "Text", mosaic = "Mosaic", crop = "Crop"
    case image = "Image"
    case annotationColor = "Annotation color", undo = "Undo", redo = "Redo", done = "Done"
    case copyAndClose = "Copy and close (⌘Return)", rotateImage = "Rotate image"
    case copyImage = "Copy image", discard = "Discard", tools = "Tools", color = "Color", history = "History"
    case adjustImage = "Image adjustments"
    case copyFailed = "Unable to copy image", annotationCanvas = "Annotation canvas", annotationText = "Annotation text"

    var chinese: String {
        switch self {
        case .settings: return "设置"
        case .settingsDescription: return "语言、启动方式与标注偏好。"
        case .settingsMenu: return "设置…"
        case .language: return "界面语言"
        case .followSystem: return "跟随系统"
        case .checkForUpdates: return "检查更新…"
        case .downloadUpdate: return "下载更新…"
        case .updateHint: return "点击时才连接 GitHub，不在后台检查。"
        case .checkingUpdates: return "正在检查 GitHub 最新版本…"
        case .upToDate: return "已是最新版本，暂无更新。"
        case .updateAvailable: return "SicGo %@ 已发布，可前往发布页下载。完成当前编辑后再替换应用。"
        case .updateUnavailable: return "暂时没有公开发布的版本，请稍后再试。"
        case .updateRateLimited: return "GitHub 暂时限制了请求，请稍后再试。"
        case .updateInvalid: return "无法验证版本信息，请稍后重试。"
        case .updateNetworkError: return "无法连接 GitHub，请检查网络后重试。"
        case .general: return "通用"
        case .annotationSettings: return "标注"
        case .launchAtLogin: return "登录时启动 SicGo"
        case .showHomeOnLaunch: return "启动时显示主窗口"
        case .loginApproval: return "请在系统设置中允许 SicGo 登录时启动。"
        case .loginSettings: return "打开系统设置…"
        case .loginError: return "无法更改登录启动设置"
        case .textFont: return "文字字体"
        case .toolbarOrder: return "工具栏排列"
        case .resetOrder: return "恢复顺序"
        case .toolbarOrderHint: return "拖动图标调整顺序，或选中后按 ← / →，立即生效。"
        case .moveLeft: return "向左移动"
        case .moveRight: return "向右移动"
        case .systemFont: return "系统字体"
        case .newTextOnly: return "用于之后新输入的标注文字。"
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
        case .homeDescription: return "截图、标注、复制。"
        case .captureShortcut: return "⇧⌘4  截取屏幕区域"
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
        case .image: return "图片"
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
        case .adjustImage: return "图片调整"
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
        case .image: key = .image
        }
        return key
    }
}
