import ServiceManagement
import XCTest
import JoyConVibeCore
@testable import JoyConVibeRemote

@MainActor
final class ReleaseLifecycleTests: XCTestCase {
    func testDisablingPendingLoginRegistrationActuallyUnregisters() throws {
        let service = FakeLoginService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)
        try manager.setEnabled(false)
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertFalse(manager.isRegistered)
    }

    func testEnablingPendingRegistrationDoesNotRegisterAgain() throws {
        let service = FakeLoginService(status: .requiresApproval)
        let manager = LoginItemManager(service: service)
        try manager.setEnabled(true)
        XCTAssertEqual(service.registerCount, 0)
        XCTAssertTrue(manager.requiresApproval)
    }

    func testLoginUnregisterFailureKeepsToggleConsistentWithSystem() {
        withModel { model, _, service in
            service.status = .requiresApproval
            service.failUnregister = true
            model.setLaunchAtLogin(false)
            XCTAssertTrue(model.settings.launchAtLogin)
            XCTAssertNotNil(model.loginItemMessage)
            service.failUnregister = false
            model.setLaunchAtLogin(false)
            XCTAssertFalse(model.settings.launchAtLogin)
            XCTAssertNil(model.loginItemMessage)
        }
    }

    func testFailedLoginRegistrationDoesNotLeaveToggleEnabled() {
        withModel { model, _, service in
            service.failRegister = true
            model.setLaunchAtLogin(true)
            XCTAssertFalse(model.settings.launchAtLogin)
            XCTAssertNotNil(model.loginItemMessage)
        }
    }

    func testPendingLoginApprovalIsExplainedAndExternalChangesAreReflected() {
        withModel { model, _, service in
            service.status = .requiresApproval
            model.refreshPermissions()
            XCTAssertTrue(model.settings.launchAtLogin)
            XCTAssertNotNil(model.loginItemMessage)
            service.status = .notRegistered
            model.refreshPermissions()
            XCTAssertFalse(model.settings.launchAtLogin)
            XCTAssertNil(model.loginItemMessage)
        }
    }

    func testPermissionsRefreshRetriesFailedOpenWithoutRestartingHealthyTransport() {
        withModel { model, transport, _ in
            transport.failStart = true
            model.reconnect()
            XCTAssertEqual(model.status, .error)
            XCTAssertFalse(transport.isRunning)
            transport.failStart = false
            model.refreshPermissions()
            XCTAssertEqual(transport.startCount, 2)
            XCTAssertTrue(transport.isRunning)
            XCTAssertNil(model.errorMessage)
            transport.onConnected?("Joy-Con (R)")
            XCTAssertEqual(model.status, .initializing)
            model.refreshPermissions()
            XCTAssertEqual(transport.startCount, 2)
        }
    }

    func testRemoteToggleReopensConnectionAndQuitPreventsRefreshRetry() {
        withModel { model, transport, _ in
            model.reconnect()
            transport.onConnected?("Joy-Con (R)")
            model.setRemoteEnabled(false)
            XCTAssertEqual(model.status, .paused)
            model.setRemoteEnabled(true)
            XCTAssertEqual(transport.startCount, 2)
            XCTAssertEqual(transport.stopCount, 2)
            XCTAssertNil(model.errorMessage)
            model.stop()
            model.refreshPermissions()
            XCTAssertEqual(transport.startCount, 2)
        }
    }

    private func withModel(_ body: (AppModel, FakeTransport, FakeLoginService) -> Void) {
        let suite = "ReleaseLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = FakeTransport()
        let service = FakeLoginService(status: .notRegistered)
        let model = AppModel(
            settings: RemoteSettings(defaults: defaults),
            transport: transport,
            loginItemManager: LoginItemManager(service: service),
            managesLoginItem: true
        )
        body(model, transport, service)
    }
}

@MainActor
private final class FakeLoginService: LoginItemService {
    var status: SMAppService.Status
    var registerCount = 0
    var unregisterCount = 0
    var failRegister = false
    var failUnregister = false

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        registerCount += 1
        if failRegister { throw NSError(domain: "test", code: 1) }
        status = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if failUnregister { throw NSError(domain: "test", code: 2) }
        status = .notRegistered
    }
}

private final class FakeTransport: JoyConTransport {
    var onConnected: ((String) -> Void)?
    var onDisconnected: (() -> Void)?
    var onRecovering: (() -> Void)?
    var onFrame: ((JoyConInputFrame) -> Void)?
    var onError: ((String) -> Void)?
    var isRunning = false
    var failStart = false
    var startCount = 0
    var stopCount = 0

    func start() {
        startCount += 1
        isRunning = !failStart
        if failStart { onError?("Simulated permission denial") }
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}
