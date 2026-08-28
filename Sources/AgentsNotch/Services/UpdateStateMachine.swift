/// Pure update-status transitions. Sparkle (and tests) feed events; the UI
/// only reads `UpdateState`.
enum UpdateState: Equatable {
    case idle
    case checking
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
    case checkFailed(String)
    case downloadStarted
    case downloadProgress(Double)
    case downloadFailed(String)
    case downloadComplete
    case installStarted
    case installFailed(String)
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

    case let .checkFailed(message):
        switch state {
        case .downloaded(let version), .installing(let version):
            return .downloaded(version: version)
        case .downloading, .unavailable:
            return state
        default:
            return .failed(message)
        }

    case .downloadStarted:
        if case let .available(version) = state {
            return .downloading(version: version, percent: 0)
        }
        return state

    case let .downloadProgress(percent):
        if case let .downloading(version, _) = state {
            return .downloading(version: version, percent: clampUpdateProgress(percent))
        }
        return state

    case let .downloadFailed(message):
        switch state {
        case let .downloading(version, _):
            return .available(version: version)
        case .unavailable:
            return state
        default:
            return .failed(message)
        }

    case .downloadComplete:
        switch state {
        case let .downloading(version, _):
            return .downloaded(version: version)
        case let .available(version):
            return .downloaded(version: version)
        default:
            return state
        }

    case .installStarted:
        switch state {
        case let .downloaded(version):
            return .installing(version: version)
        case let .available(version):
            return .installing(version: version)
        default:
            return state
        }

    case let .installFailed(message):
        switch state {
        case let .installing(version), let .downloaded(version):
            return .downloaded(version: version)
        case .unavailable:
            return state
        default:
            return .failed(message)
        }

    case .sessionEnded:
        switch state {
        case .checking:
            return .idle
        case let .downloading(version, _):
            return .available(version: version)
        case .installing(let version):
            return .downloaded(version: version)
        default:
            return state
        }
    }
}

func clampUpdateProgress(_ percent: Double) -> Double {
    min(1, max(0, percent))
}
