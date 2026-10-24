import AppKit

enum CaptureImage {
    static func read(_ url: URL) throws -> CGImage {
        let data = try Data(contentsOf: url)
        guard let image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
    static func consume(_ url: URL) throws -> CGImage {
        let image = try read(url)
        try FileManager.default.removeItem(at: url)
        return image
    }
    static func isSystemScreenshot(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }
    }
}

/// A recoverable lease on the system screenshot destination. No screen capture APIs.
final class ScreenshotSettings {
    private let domain: CFString
    private let receipt: URL
    private let locationKey: String
    private let desired: [String: Any]

    init(folder: URL, domain: String = "com.apple.screencapture", screenshotSpecific: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27) {
        self.domain = domain as CFString
        receipt = folder.deletingLastPathComponent().appendingPathComponent("screenshot-settings.plist")
        locationKey = screenshotSpecific ? "location-screenshot" : "location"
        desired = [locationKey: folder.path, screenshotSpecific ? "target-screenshot" : "target": "file", "show-thumbnail": false]
    }
    private func value(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
    private func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        guard let left = lhs as? NSObject, let right = rhs as? NSObject else { return lhs == nil && rhs == nil }
        return left.isEqual(right)
    }
    func begin() throws {
        try end() // Recover the previous lease after an interrupted run.
        CFPreferencesAppSynchronize(domain)
        var original: [String: Any] = [:]
        for key in desired.keys { original[key] = value(key) }
        let data = try PropertyListSerialization.data(fromPropertyList: ["original": original, "applied": desired, "locationKey": locationKey], format: .binary, options: 0)
        try data.write(to: receipt, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
        for (key, value) in desired { CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain) }
        guard CFPreferencesAppSynchronize(domain) else { try? end(); throw CocoaError(.fileWriteUnknown) }
    }
    func end() throws {
        guard FileManager.default.fileExists(atPath: receipt.path) else { return }
        let data = try Data(contentsOf: receipt)
        guard let saved = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let original = saved["original"] as? [String: Any], let applied = saved["applied"] as? [String: Any],
              let location = saved["locationKey"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        CFPreferencesAppSynchronize(domain)
        // Preserve later changes made by the user in Screenshot Options.
        if same(value(location), applied[location]) {
            for (key, expected) in applied where same(value(key), expected) {
                CFPreferencesSetAppValue(key as CFString, original[key] as CFPropertyList?, domain)
            }
            guard CFPreferencesAppSynchronize(domain) else { throw CocoaError(.fileWriteUnknown) }
        }
        try FileManager.default.removeItem(at: receipt)
    }
}

@MainActor
final class SystemScreenshotInbox {
    nonisolated static let defaultFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("local.makstton.SicGo/System Screenshots", isDirectory: true)
    private let folder: URL
    private let settings: ScreenshotSettings
    private var source: DispatchSourceFileSystemObject?
    private var scheduled: DispatchWorkItem?
    private var ignored = Set<URL>()
    private var attempts: [URL: Int] = [:]
    private var stamps: [URL: String] = [:]
    var onImage: ((CGImage, String) -> Void)?
    var onError: ((Error) -> Void)?

    init(folder: URL = defaultFolder, settings: ScreenshotSettings? = nil) {
        self.folder = folder; self.settings = settings ?? ScreenshotSettings(folder: folder)
    }
    func start() throws {
        guard source == nil else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Existing files belong to a previous session. Never consume them implicitly.
        ignored = Set(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write], queue: .main)
        watcher.setEventHandler { [weak self] in self?.schedule() }
        watcher.setCancelHandler { Darwin.close(fd) }
        source = watcher; watcher.resume()
        do { try settings.begin() }
        catch { watcher.cancel(); source = nil; throw error }
    }
    func stop() throws {
        try settings.end()
        scheduled?.cancel(); scheduled = nil
        source?.cancel(); source = nil
    }
    private func schedule() {
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func scan() {
        guard source != nil else { return }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { return }
        var retry = false
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !ignored.contains(file) {
            guard ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff"].contains(file.pathExtension.lowercased()),
                  let info = try? file.resourceValues(forKeys: keys), info.isRegularFile == true, info.isSymbolicLink != true else {
                ignored.insert(file); continue
            }
            let stamp = "\(info.fileSize ?? 0):\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            let stable = stamps[file] == stamp; stamps[file] = stamp
            attempts[file, default: 0] += 1
            if stable, CaptureImage.isSystemScreenshot(file) {
                do {
                    let image = try CaptureImage.consume(file)
                    ignored.insert(file); attempts[file] = nil; stamps[file] = nil
                    onImage?(image, "Screenshot")
                    continue
                } catch {
                    if attempts[file, default: 0] >= 20 { ignored.insert(file); onError?(error); continue }
                }
            }
            if attempts[file, default: 0] < 20 { retry = true }
            else { ignored.insert(file) }
        }
        let existing = Set(files)
        ignored.formIntersection(existing)
        attempts = attempts.filter { existing.contains($0.key) && !ignored.contains($0.key) }
        stamps = stamps.filter { existing.contains($0.key) && !ignored.contains($0.key) }
        if retry { schedule() }
    }
}
