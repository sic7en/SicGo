import AppKit

extension EditorChecks {
    @MainActor func testUpdateNetworkResponses() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let expected: [(String, UpdateChecker.State)] = [
            ("1.3.3", .available(AppRelease(version: "1.4.0", url: URL(string: "https://github.com/sic7en/SicGo/releases/tag/v1.4.0")!))),
            ("9.0.0", .failed(.network)), ("9.0.1", .failed(.rateLimited)),
            ("9.0.2", .failed(.unavailable)), ("9.0.3", .failed(.invalidResponse)),
            ("9.0.4", .failed(.invalidResponse))
        ]
        for (version, state) in expected {
            let checker = UpdateChecker { try await UpdateService.check(currentVersion: version, configuration: configuration) }
            checker.check()
            let deadline = Date().addingTimeInterval(5)
            while checker.state == .checking && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            expectEqual(checker.state, state)
        }
    }
    func testReleaseVersions() {
        expect(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.9")!)
        expect(ReleaseVersion("2.0")! > ReleaseVersion("1.99.99")!)
        expectEqual(ReleaseVersion("v1.3.3"), ReleaseVersion("1.3.3.0"))
        for invalid in ["", "1", "1..2", "1.3.4-beta", "1.3.4+test", "-1.2.3", "1.2/evil", "https://evil.test", "99999999999999999999999.1", "1.2.3.4.5"] {
            expect(ReleaseVersion(invalid) == nil)
        }
    }
    func testReleaseResponses() throws {
        func json(_ tag: String, draft: Bool = false, preview: Bool = false) -> Data {
            try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": draft, "prerelease": preview,
                "html_url": "https://untrusted.invalid/payload"])
        }
        let next = try UpdateService.parse(json("v1.10.0"), status: 200, currentVersion: "1.3.3")
        expectEqual(next?.version, "1.10.0")
        expectEqual(next?.url.absoluteString, "https://github.com/sic7en/SicGo/releases/tag/v1.10.0")
        expect(try UpdateService.parse(json("v1.3.2"), status: 200, currentVersion: "1.3.3") == nil)
        expect(try UpdateService.parse(json("1.3.3"), status: 200, currentVersion: "1.3.3") == nil)
        for status in [404, 403, 429, 500, 301] { expectThrows(try UpdateService.parse(json("v2.0.0"), status: status, currentVersion: "1.3.3")) }
        expectThrows(try UpdateService.parse(json("v2.0.0", draft: true), status: 200, currentVersion: "1.3.3"))
        expectThrows(try UpdateService.parse(json("v2.0.0", preview: true), status: 200, currentVersion: "1.3.3"))
        expectThrows(try UpdateService.parse(json("v2.0.0-beta"), status: 200, currentVersion: "1.3.3"))
        expectThrows(try UpdateService.parse(Data("{}".utf8), status: 200, currentVersion: "1.3.3"))
        expectThrows(try UpdateService.parse(Data(repeating: 32, count: 1_048_577), status: 200, currentVersion: "1.3.3"))
    }
    @MainActor func testUpdateStateAndSettings() {
        _ = NSApplication.shared
        let suite = "SicGo.UpdateChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Keep all preferences and windows separate from the user's editing session.
        let preferences = EditorPreferences(defaults: defaults)
        preferences.language = .english
        let release = AppRelease(version: "2.0.0", url: URL(string: "https://github.com/sic7en/SicGo/releases/tag/v2.0.0")!)
        var requests = 0
        let updater = UpdateChecker {
            requests += 1
            if requests == 1 { return release }
            if requests == 2 { throw UpdateFailure.network }
            return nil
        }
        let settings = SettingsWindow(preferences: preferences, updater: updater)
        defer { settings.close(); defaults.removePersistentDomain(forName: suite) }
        expectEqual(requests, 0); expectEqual(updater.state, .idle)
        expect(settings.downloadButton.isHidden)
        func completeCheck() {
            let end = Date().addingTimeInterval(3)
            while updater.state == .checking && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            expect(updater.state != .checking)
        }
        settings.checkForUpdates(); settings.checkForUpdates()
        expectEqual(updater.state, .checking); expectFalse(settings.updateButton.isEnabled)
        completeCheck()
        expectEqual(requests, 1); expectEqual(updater.state, .available(release)); expectFalse(settings.downloadButton.isHidden)
        preferences.language = .simplifiedChinese; settings.updateLocalization()
        expectEqual(settings.updateButton.title, "检查更新…"); expect(settings.updateStatus.stringValue.contains("2.0.0"))
        settings.checkForUpdates(); completeCheck()
        expectEqual(updater.state, .failed(.network)); expect(settings.downloadButton.isHidden); expect(settings.updateButton.isEnabled)
        settings.checkForUpdates(); completeCheck()
        expectEqual(updater.state, .current); expectEqual(requests, 3)
        expectEqual(settings.updateStatus.stringValue, localized(.upToDate, language: .simplifiedChinese))
    }
}

private final class ReleaseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        expectEqual(request.url, UpdateService.endpoint)
        expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let version = request.value(forHTTPHeaderField: "User-Agent")!.replacingOccurrences(of: "SicGo/", with: "")
        if version == "9.0.0" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let status = version == "9.0.1" ? 403 : version == "9.0.2" ? 404 : 200
        let body: Data
        if version == "9.0.3" { body = Data("{bad json".utf8) }
        else if version == "9.0.4" { body = Data(repeating: 32, count: 1_048_577) }
        else { body = Data(#"{"tag_name":"v1.4.0","draft":false,"prerelease":false}"#.utf8) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
