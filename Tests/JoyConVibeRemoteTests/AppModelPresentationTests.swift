import Combine
import XCTest
@testable import JoyConVibeRemote

@MainActor
final class AppModelPresentationTests: XCTestCase {
    func testIdenticalJoyConFramesDoNotContinuouslyRedrawTheConsole() {
        let suiteName = "AppModelPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = AppModel(settings: RemoteSettings(defaults: defaults))
        var redrawCount = 0
        let cancellable = model.objectWillChange.sink { redrawCount += 1 }

        for _ in 0..<120 {
            model.updateTelemetry(batteryLevel: 3, isCharging: false)
            model.updateStatus(.connected)
        }

        XCTAssertEqual(redrawCount, 2)
        withExtendedLifetime(cancellable) {}
    }

    func testDraggingPointerTuningDoesNotInvalidateTheWholeConsole() {
        let suiteName = "AppModelPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = RemoteSettings(defaults: defaults)
        var wholeConsoleInvalidations = 0
        let cancellable = settings.objectWillChange.sink {
            wholeConsoleInvalidations += 1
        }

        for step in 0..<120 {
            settings.sensitivity = 0.25 + (Double(step) * 0.01)
        }

        XCTAssertEqual(wholeConsoleInvalidations, 0)
        withExtendedLifetime(cancellable) {}
    }

    func testPanelHeightFollowsContentWithinScreenSafeLimits() {
        XCTAssertEqual(StatusPanelHeightPolicy.height(for: 180), 220)
        XCTAssertEqual(StatusPanelHeightPolicy.height(for: 487.2), 488)
        XCTAssertEqual(StatusPanelHeightPolicy.height(for: 900), 720)
    }
}
