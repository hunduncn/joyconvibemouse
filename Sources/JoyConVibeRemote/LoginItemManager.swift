import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct SystemLoginItemService: LoginItemService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

@MainActor
final class LoginItemManager {
    private let service: any LoginItemService

    init(service: (any LoginItemService)? = nil) {
        self.service = service ?? SystemLoginItemService()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isRegistered else { return }
            try service.register()
        } else {
            guard isRegistered else { return }
            try service.unregister()
        }
    }

    var isRegistered: Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }
}
