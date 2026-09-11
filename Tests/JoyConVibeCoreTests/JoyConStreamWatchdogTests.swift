import XCTest
@testable import JoyConVibeCore

final class JoyConStreamWatchdogTests: XCTestCase {
    func testRequestsRecoveryWhenStartupProducesNoStandardReports() {
        var watchdog = JoyConStreamWatchdog(
            startupGrace: 1.0,
            stallTimeout: 1.0,
            retryInterval: 0.5
        )

        watchdog.start(at: 10)

        XCTAssertFalse(watchdog.shouldRecover(at: 10.99))
        XCTAssertTrue(watchdog.shouldRecover(at: 11.0))
        XCTAssertFalse(watchdog.shouldRecover(at: 11.49))
        XCTAssertTrue(watchdog.shouldRecover(at: 11.5))
    }

    func testStandardReportsPostponeRecoveryUntilTheStreamStalls() {
        var watchdog = JoyConStreamWatchdog(
            startupGrace: 1.0,
            stallTimeout: 0.8,
            retryInterval: 0.5
        )

        watchdog.start(at: 20)
        watchdog.recordStandardReport(at: 20.7)

        XCTAssertFalse(watchdog.shouldRecover(at: 21.49))
        XCTAssertTrue(watchdog.shouldRecover(at: 21.5))

        watchdog.recordStandardReport(at: 21.6)
        XCTAssertFalse(watchdog.shouldRecover(at: 22.39))
        XCTAssertTrue(watchdog.shouldRecover(at: 22.4))
    }

    func testRestartResetsThePreviousStreamDeadline() {
        var watchdog = JoyConStreamWatchdog(
            startupGrace: 1.0,
            stallTimeout: 0.8,
            retryInterval: 0.5
        )

        watchdog.start(at: 30)
        watchdog.recordStandardReport(at: 30.5)
        watchdog.start(at: 40)

        XCTAssertFalse(watchdog.shouldRecover(at: 40.99))
        XCTAssertTrue(watchdog.shouldRecover(at: 41.0))
    }
}
