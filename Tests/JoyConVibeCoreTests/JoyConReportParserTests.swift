import XCTest
@testable import JoyConVibeCore

final class JoyConReportParserTests: XCTestCase {
    func testParsesRightJoyConButtonsStickBatteryAndIMU() throws {
        var parser = JoyConReportParser()
        var payload = [UInt8](repeating: 0, count: 48)
        payload[1] = 0x90 // Full and charging.
        payload[2] = 0xFF // All right-side buttons.
        payload[3] = 0x16 // Plus, stick, and Home.
        payload[8] = 0x00
        payload[9] = 0x08
        payload[10] = 0x80 // Stick center: 2048, 2048.
        putInt16(1000, in: &payload, at: 12)
        putInt16(-2000, in: &payload, at: 14)
        putInt16(3000, in: &payload, at: 16)
        putInt16(100, in: &payload, at: 18)
        putInt16(-200, in: &payload, at: 20)
        putInt16(300, in: &payload, at: 22)

        let decoded = try XCTUnwrap(parser.decode(reportID: 0x30, bytes: [0x30] + payload))
        let frame = try XCTUnwrap(decoded.frame)

        XCTAssertEqual(frame.buttons, Set(JoyConButton.allCases))
        XCTAssertEqual(frame.stick.x, 0, accuracy: 0.001)
        XCTAssertEqual(frame.stick.y, 0, accuracy: 0.001)
        XCTAssertEqual(frame.batteryLevel, 4)
        XCTAssertTrue(frame.isCharging)
        XCTAssertEqual(frame.gyroSamples.count, 3)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.x, 6.103, accuracy: 0.001)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.y, -12.206, accuracy: 0.001)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.z, 18.309, accuracy: 0.001)
        XCTAssertEqual(frame.gyroSamples[0].acceleration, Vector3(x: 1000, y: -2000, z: 3000))
    }

    func testFactoryGyroCalibrationIsAppliedFromSPIReply() throws {
        var parser = JoyConReportParser()
        var calibration = [UInt8](repeating: 0, count: 24)
        putInt16(10, in: &calibration, at: 12)
        putInt16(20, in: &calibration, at: 14)
        putInt16(30, in: &calibration, at: 16)
        putInt16(946, in: &calibration, at: 18)
        putInt16(956, in: &calibration, at: 20)
        putInt16(966, in: &calibration, at: 22)

        let reply = makeSPIReply(address: 0x6020, data: calibration)
        let decodedReply = try XCTUnwrap(parser.decode(reportID: 0x21, bytes: reply))
        XCTAssertEqual(decodedReply.spiReply?.address, 0x6020)
        XCTAssertNil(
            decodedReply.frame,
            "Initialization replies must never be exposed as user input frames"
        )

        var payload = [UInt8](repeating: 0, count: 48)
        payload[8] = 0x00
        payload[9] = 0x08
        payload[10] = 0x80
        putInt16(11, in: &payload, at: 18)
        putInt16(21, in: &payload, at: 20)
        putInt16(31, in: &payload, at: 22)

        let frame = try XCTUnwrap(parser.decode(reportID: 0x30, bytes: payload)?.frame)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.x, 1, accuracy: 0.0001)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.y, 1, accuracy: 0.0001)
        XCTAssertEqual(frame.gyroSamples[0].degreesPerSecond.z, 1, accuracy: 0.0001)
    }

    func testRejectsTruncatedReports() {
        var parser = JoyConReportParser()
        XCTAssertNil(parser.decode(reportID: 0x30, bytes: [0x30, 0x00]))
        XCTAssertNil(parser.decode(reportID: 0x21, bytes: [0x21, 0x00]))
        XCTAssertNil(parser.decode(reportID: 0x3F, bytes: [0x00]))
    }

    func testTimerEqualToReportIDIsNotMistakenForEmbeddedReportID() throws {
        var parser = JoyConReportParser()
        var payload = [UInt8](repeating: 0, count: 48)
        payload[0] = 0x30 // Timer byte, not an embedded report ID.
        payload[1] = 0x80
        payload[2] = 0x08
        payload[8] = 0x00
        payload[9] = 0x08
        payload[10] = 0x80

        let frame = try XCTUnwrap(parser.decode(reportID: 0x30, bytes: payload)?.frame)
        XCTAssertTrue(frame.buttons.contains(.a))
        XCTAssertEqual(frame.batteryLevel, 4)
    }

    private func makeSPIReply(address: UInt32, data: [UInt8]) -> [UInt8] {
        var payload = [UInt8](repeating: 0, count: 19 + data.count)
        payload[12] = 0x90
        payload[13] = 0x10
        payload[14] = UInt8(address & 0xFF)
        payload[15] = UInt8((address >> 8) & 0xFF)
        payload[16] = UInt8((address >> 16) & 0xFF)
        payload[17] = UInt8((address >> 24) & 0xFF)
        payload[18] = UInt8(data.count)
        payload.replaceSubrange(19..<(19 + data.count), with: data)
        return [0x21] + payload
    }

    private func putInt16(_ value: Int16, in data: inout [UInt8], at offset: Int) {
        let bits = UInt16(bitPattern: value)
        data[offset] = UInt8(bits & 0xFF)
        data[offset + 1] = UInt8(bits >> 8)
    }
}
