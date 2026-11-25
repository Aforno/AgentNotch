import Foundation
import Sparkle

/// Which GitHub release feed Sparkle checks. Stable uses `SUFeedURL` from Info.plist.
enum UpdateChannel: String, Identifiable {
    case stable
    case nightly
    case preview

    static let nightlyFeedURL = "https://github.com/Aforno/AgentNotch/releases/download/nightly/appcast.xml"
    static let previewFeedURL = "https://github.com/Aforno/AgentNotch/releases/download/nightly-preview/appcast.xml"
    static let selectableChannels: [Self] = [.stable, .nightly]

    var id: String { rawValue }
    var title: String {
        switch self {
        case .stable: "Stable"
        case .nightly: "Nightly"
        case .preview: "Preview"
        }
    }

    /// Feed override for Sparkle; `nil` keeps the Info.plist feed.
    var feedURLString: String? {
        switch self {
        case .stable: nil
        case .nightly: Self.nightlyFeedURL
        case .preview: Self.previewFeedURL
        }
    }

    static let downloadsURL = URL(string: "https://github.com/Aforno/AgentNotch/releases")!

    var releasePage: URL {
        switch self {
        case .stable: Self.downloadsURL.appendingPathComponent("latest")
        case .nightly: Self.downloadsURL.appendingPathComponent("tag/nightly")
        case .preview: Self.downloadsURL.appendingPathComponent("tag/nightly-preview")
        }
    }

    /// Recognizes archives by their release tag, including cached Sparkle offers.
    static func archiveChannel(for url: URL) -> Self? {
        let release = url.deletingLastPathComponent()
        guard release.deletingLastPathComponent().lastPathComponent == "download" else { return nil }
        if release.lastPathComponent == "nightly" { return .nightly }
        if release.lastPathComponent == "nightly-preview" { return .preview }
        return release.lastPathComponent.hasPrefix("v") ? .stable : nil
    }

    static func selected(in preferences: UserDefaults) -> Self {
        preferences.string(forKey: AppPreferences.Key.updateChannel) == nightly.rawValue ? .nightly : .stable
    }
}

/// Points Sparkle at the feed for the channel chosen in Settings. Sparkle asks on every check.
final class UpdateChannelFeedDelegate: NSObject, SPUUpdaterDelegate {
    weak var service: UpdateService?

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        service?.checkSelectedChannelIfPending()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        service?.selectedChannel.feedURLString
    }
}
