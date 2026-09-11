import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
