import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            guard SMAppService.mainApp.status == .enabled else {
                throw LaunchAtLoginError.requiresApproval
            }
        } else {
            if SMAppService.mainApp.status == .enabled
                || SMAppService.mainApp.status == .requiresApproval
            {
                try SMAppService.mainApp.unregister()
            }
            guard SMAppService.mainApp.status != .enabled else {
                throw LaunchAtLoginError.statusDidNotChange
            }
        }
    }
}

private enum LaunchAtLoginError: LocalizedError {
    case requiresApproval
    case statusDidNotChange

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            "Launch at login requires approval in System Settings > General > Login Items."
        case .statusDidNotChange:
            "Launch at login did not update. Try again."
        }
    }
}
