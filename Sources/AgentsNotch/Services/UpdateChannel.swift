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

    static var current: UpdateChannel {
        UserDefaults.standard.string(forKey: AppPreferences.Key.updateChannel)
            .flatMap(UpdateChannel.init(rawValue:)) ?? .stable
    }
}

/// Points Sparkle at the feed for the channel chosen in Settings. Sparkle asks on every check.
final class UpdateChannelFeedDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        UpdateChannel.current.feedURLString
    }
}
