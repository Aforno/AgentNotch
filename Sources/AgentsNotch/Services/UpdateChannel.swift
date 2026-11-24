import Foundation
import Sparkle

/// Which GitHub release feed Sparkle checks. Stable uses `SUFeedURL` from Info.plist.
enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case nightly

    static let nightlyFeedURL = "https://github.com/Aforno/AgentNotch/releases/download/nightly/appcast.xml"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        }
    }

    /// Feed override for Sparkle; `nil` keeps the Info.plist feed.
    var feedURLString: String? {
        switch self {
        case .stable: nil
        case .nightly: Self.nightlyFeedURL
        }
    }

    static let downloadsURL = URL(string: "https://github.com/Aforno/AgentNotch/releases")!

    var releasePage: URL {
        switch self {
        case .stable: Self.downloadsURL.appendingPathComponent("latest")
        case .nightly: Self.downloadsURL.appendingPathComponent("tag/nightly")
        }
    }

    /// Recognizes archives published by the stable and rolling nightly workflows.
    static func archiveChannel(for url: URL) -> Self? {
        let release = url.deletingLastPathComponent()
        guard release.deletingLastPathComponent().lastPathComponent == "download" else { return nil }
        if release.lastPathComponent == "nightly" { return .nightly }
        return release.lastPathComponent.hasPrefix("v") ? .stable : nil
    }

    static var current: UpdateChannel {
        UserDefaults.standard.string(forKey: AppPreferences.Key.updateChannel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }
}

/// Points Sparkle at the feed for the channel chosen in Settings. Sparkle asks on every check.
final class UpdateChannelFeedDelegate: NSObject, SPUUpdaterDelegate {
    weak var service: UpdateService?

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        service?.checkSelectedChannelIfPending()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.current.feedURLString
    }
}
