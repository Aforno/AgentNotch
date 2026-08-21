import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class UpdateService {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noRelease
        case available(version: String)
        case failed(String)
    }

    private(set) var state: State = .idle

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/Aforno/AgentNotch/releases/latest")!
    private let releasePageURL = URL(string: "https://github.com/Aforno/AgentNotch/releases/latest")!
    private let openURL: (URL) -> Void

    init(openURL: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }) {
        self.openURL = openURL
    }

    func checkAutomaticallyIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "automaticallyCheckForUpdates") else { return }
        let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= 24 * 60 * 60 else { return }
        Task { await check() }
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            var request = URLRequest(url: latestReleaseURL)
            request.timeoutInterval = 10
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("AgentNotch/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            if http.statusCode == 404 {
                state = .noRelease
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.http(http.statusCode)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if version.compare(currentVersion, options: .numeric) == .orderedDescending {
                state = .available(version: version)
            } else {
                state = .upToDate
            }
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openAvailableRelease() {
        openURL(releasePageURL)
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private struct GitHubRelease: Decodable {
        let tagName: String

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub returned an invalid update response."
            case let .http(code): "GitHub update check failed with HTTP \(code)."
            }
        }
    }
}
