import Foundation

/// Detects when the Joy-Con stops producing full `0x30` input reports.
///
/// Calling `shouldRecover` also rate-limits recovery attempts, so a stalled
/// controller can be reconfigured repeatedly without flooding Bluetooth.
public struct JoyConStreamWatchdog: Sendable {
    private let startupGrace: TimeInterval
    private let stallTimeout: TimeInterval
    private let retryInterval: TimeInterval
    private var nextRecoveryAt: TimeInterval?

    public init(
        startupGrace: TimeInterval = 1.25,
        stallTimeout: TimeInterval = 0.9,
        retryInterval: TimeInterval = 1.0
    ) {
        self.startupGrace = startupGrace
        self.stallTimeout = stallTimeout
        self.retryInterval = retryInterval
    }

    public mutating func start(at timestamp: TimeInterval) {
        nextRecoveryAt = timestamp + startupGrace
    }

    public mutating func recordStandardReport(at timestamp: TimeInterval) {
        nextRecoveryAt = timestamp + stallTimeout
    }

    public mutating func shouldRecover(at timestamp: TimeInterval) -> Bool {
        guard let nextRecoveryAt, timestamp >= nextRecoveryAt - 1e-9 else { return false }
        self.nextRecoveryAt = timestamp + retryInterval
        return true
    }
}
