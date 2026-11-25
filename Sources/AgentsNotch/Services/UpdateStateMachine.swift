/// Pure update-status transitions. Sparkle (and tests) feed events; the UI
/// only reads `UpdateState`.
enum UpdateState: Equatable {
    case idle
    case checking
    case awaitingStableRelease
    case upToDate
    case available(version: String)
    case downloading(version: String, percent: Double)
    case downloaded(version: String)
    case installing(version: String)
    case failed(String)
    case unavailable(String)
}

enum UpdateEvent: Equatable {
    case checkStarted
    case noUpdate
    case updateAvailable(version: String)
    case failed(String)
    case downloadStarted
    case downloadProgress(Double)
    case downloadComplete
    case installStarted
    case sessionEnded
}

func reduceUpdateState(_ state: UpdateState, _ event: UpdateEvent) -> UpdateState {
    switch event {
    case .checkStarted:
        switch state {
        case .downloading, .installing, .unavailable, .downloaded:
            return state
        default:
            return .checking
        }

    case .noUpdate:
        switch state {
        case .downloaded(let version), .installing(let version):
            return .downloaded(version: version)
        case .downloading, .unavailable:
            return state
        default:
            return .upToDate
        }

    case let .updateAvailable(version):
        switch state {
        case .downloaded(let downloaded) where downloaded == version:
            return .downloaded(version: version)
        case .downloading, .installing, .unavailable:
            return state
        default:
            return .available(version: version)
        }

    case let .failed(message):
        if case .unavailable = state { return state }
        return .failed(message)

    case .downloadStarted:
        if case let .available(version) = state {
            return .downloading(version: version, percent: 0)
        }
        return state

    case let .downloadProgress(percent):
        if case let .downloading(version, _) = state {
            return .downloading(version: version, percent: min(1, max(0, percent)))
        }
        return state

    case .downloadComplete:
        switch state {
        case let .downloading(version, _), let .available(version):
            return .downloaded(version: version)
        default:
            return state
        }

    case .installStarted:
        switch state {
        case let .downloaded(version), let .available(version):
            return .installing(version: version)
        default:
            return state
        }

    case .sessionEnded:
        switch state {
        case .checking, .available, .downloading, .downloaded, .installing:
            return .idle
        default:
            return state
        }
    }
}
