import Foundation

/// Stable numeric release versions only. Never compare versions lexicographically.
struct ReleaseVersion: Comparable {
    let parts: [Int]
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(components.count), value.utf8.count <= 48,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) }) else { return nil }
        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct AppRelease: Equatable {
    let version: String
    let url: URL
}

enum UpdateFailure: Error, Equatable {
    case unavailable, rateLimited, invalidResponse, network
}

enum UpdateService {
    static let repository = URL(string: "https://github.com/sic7en/SicGo")!
    static let endpoint = URL(string: "https://api.github.com/repos/sic7en/SicGo/releases/latest")!
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    static let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    static func parse(_ data: Data, status: Int, currentVersion: String) throws -> AppRelease? {
        if status == 404 { throw UpdateFailure.unavailable }
        if status == 403 || status == 429 { throw UpdateFailure.rateLimited }
        guard status == 200, data.count <= 1_048_576,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let latest = ReleaseVersion(release.tag_name), let current = ReleaseVersion(currentVersion) else {
            throw UpdateFailure.invalidResponse
        }
        guard latest > current else { return nil }
        // Construct the link from the validated tag; never open arbitrary URLs from the response.
        return AppRelease(version: release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name,
                          url: repository.appendingPathComponent("releases/tag/" + release.tag_name))
    }

    static func check(currentVersion: String = currentVersion, configuration: URLSessionConfiguration = .ephemeral) async throws -> AppRelease? {
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SicGo/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw UpdateFailure.invalidResponse }
            guard response.statusCode == 200 else { return try parse(Data(), status: response.statusCode, currentVersion: currentVersion) }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw UpdateFailure.invalidResponse }
                data.append(byte)
            }
            return try parse(data, status: response.statusCode, currentVersion: currentVersion)
        } catch let failure as UpdateFailure { throw failure }
        catch { throw UpdateFailure.network }
    }
}

@MainActor
final class UpdateChecker {
    enum State: Equatable {
        case idle, checking, current, available(AppRelease), failed(UpdateFailure)
    }
    private(set) var state: State = .idle { didSet { changed() } }
    var changed: () -> Void = {}
    private let fetch: () async throws -> AppRelease?

    init(fetch: @escaping () async throws -> AppRelease? = { try await UpdateService.check() }) { self.fetch = fetch }

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task { [weak self, fetch] in
            do {
                let release = try await fetch()
                self?.state = release.map(State.available) ?? .current
            } catch { self?.state = .failed(error as? UpdateFailure ?? .network) }
        }
    }
}
