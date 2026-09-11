import Foundation

public struct JoyConReportParser: Sendable {
    public private(set) var gyroCalibration: GyroCalibration
    public private(set) var stickCalibration: StickCalibration

    public init(
        gyroCalibration: GyroCalibration = .fallback,
        stickCalibration: StickCalibration = .fallback
    ) {
        self.gyroCalibration = gyroCalibration
        self.stickCalibration = stickCalibration
    }

    public mutating func decode(reportID: UInt8, bytes: [UInt8]) -> JoyConDecodedReport? {
        let payload = Self.payload(reportID: reportID, bytes: bytes)

        switch reportID {
        case 0x21:
            let reply = parseSPIReply(payload: payload)
            if let reply {
                apply(reply: reply)
            }
            guard let reply else { return nil }
            // 0x21 is a subcommand reply used during initialization. Although
            // its header resembles a standard input report, exposing it as a
            // frame can turn reply bytes into phantom button presses at launch.
            return JoyConDecodedReport(spiReply: reply)
        case 0x30:
            guard let frame = parseStandardFrame(payload: payload, includeIMU: true) else { return nil }
            return JoyConDecodedReport(frame: frame)
        default:
            return nil
        }
    }

    public mutating func apply(reply: SPIFlashReply) {
        switch reply.address {
        case 0x6020:
            if let calibration = Self.parseGyroCalibration(reply.data) {
                gyroCalibration = calibration
            }
        case 0x6046:
            if let calibration = Self.parseRightStickCalibration(reply.data) {
                stickCalibration = calibration
            }
        default:
            break
        }
    }

    private static func payload(reportID: UInt8, bytes: [UInt8]) -> ArraySlice<UInt8> {
        // IOHID backends differ on whether the report ID is included in the
        // buffer. Avoid checking only the first byte because the Joy-Con timer
        // can legitimately equal 0x21 or 0x30.
        if reportID == 0x30, bytes.count >= 49, bytes.first == reportID {
            return bytes.dropFirst()
        }
        if reportID == 0x21,
           bytes.count >= 20,
           bytes.first == reportID,
           bytes[13] & 0x80 != 0,
           bytes[14] == 0x10
        {
            return bytes.dropFirst()
        }
        return bytes[...]
    }

    private func parseStandardFrame(
        payload: ArraySlice<UInt8>,
        includeIMU: Bool
    ) -> JoyConInputFrame? {
        let data = Array(payload)
        guard data.count >= 11 else { return nil }

        let rightButtons = data[2]
        let sharedButtons = data[3]
        var buttons = Set<JoyConButton>()

        Self.insert(.y, if: rightButtons & 0x01 != 0, into: &buttons)
        Self.insert(.x, if: rightButtons & 0x02 != 0, into: &buttons)
        Self.insert(.b, if: rightButtons & 0x04 != 0, into: &buttons)
        Self.insert(.a, if: rightButtons & 0x08 != 0, into: &buttons)
        Self.insert(.sr, if: rightButtons & 0x10 != 0, into: &buttons)
        Self.insert(.sl, if: rightButtons & 0x20 != 0, into: &buttons)
        Self.insert(.r, if: rightButtons & 0x40 != 0, into: &buttons)
        Self.insert(.zr, if: rightButtons & 0x80 != 0, into: &buttons)
        Self.insert(.plus, if: sharedButtons & 0x02 != 0, into: &buttons)
        Self.insert(.stick, if: sharedButtons & 0x04 != 0, into: &buttons)
        Self.insert(.home, if: sharedButtons & 0x10 != 0, into: &buttons)

        let rawStick = Self.decodeStick(data[8], data[9], data[10])
        let stick = normalizedStick(rawStick)

        var gyroSamples: [GyroSample] = []
        if includeIMU, data.count >= 48 {
            for offset in stride(from: 12, through: 36, by: 12) {
                let x = Self.int16(data, offset)
                let y = Self.int16(data, offset + 2)
                let z = Self.int16(data, offset + 4)

                let gx = Self.int16(data, offset + 6)
                let gy = Self.int16(data, offset + 8)
                let gz = Self.int16(data, offset + 10)
                gyroSamples.append(
                    GyroSample(
                        degreesPerSecond: Vector3(
                            x: (Double(gx) - gyroCalibration.offset.x) * gyroCalibration.coefficient.x,
                            y: (Double(gy) - gyroCalibration.offset.y) * gyroCalibration.coefficient.y,
                            z: (Double(gz) - gyroCalibration.offset.z) * gyroCalibration.coefficient.z
                        ),
                        acceleration: Vector3(
                            x: Double(x),
                            y: Double(y),
                            z: Double(z)
                        )
                    )
                )
            }
        }

        let batteryByte = data[1]
        let batteryLevel: Int
        switch batteryByte & 0xE0 {
        case 0x80: batteryLevel = 4
        case 0x60: batteryLevel = 3
        case 0x40: batteryLevel = 2
        case 0x20: batteryLevel = 1
        default: batteryLevel = 0
        }

        return JoyConInputFrame(
            buttons: buttons,
            stick: stick,
            gyroSamples: gyroSamples,
            batteryLevel: batteryLevel,
            isCharging: batteryByte & 0x10 != 0
        )
    }

    private func parseSPIReply(payload: ArraySlice<UInt8>) -> SPIFlashReply? {
        let data = Array(payload)
        guard data.count >= 19 else { return nil }
        let acknowledged = data[12] & 0x80 != 0
        guard acknowledged, data[13] == 0x10 else { return nil }

        let address = UInt32(data[14])
            | (UInt32(data[15]) << 8)
            | (UInt32(data[16]) << 16)
            | (UInt32(data[17]) << 24)
        let length = Int(data[18])
        guard data.count >= 19 + length else { return nil }
        return SPIFlashReply(address: address, data: Array(data[19..<(19 + length)]))
    }

    private func normalizedStick(_ raw: (x: UInt16, y: UInt16)) -> StickPosition {
        let deltaX = Double(raw.x) - stickCalibration.centerX
        let deltaY = Double(raw.y) - stickCalibration.centerY
        let xRange = deltaX < 0 ? stickCalibration.negativeRangeX : stickCalibration.positiveRangeX
        let yRange = deltaY < 0 ? stickCalibration.negativeRangeY : stickCalibration.positiveRangeY
        let x = max(-1, min(1, deltaX / xRange))
        let y = max(-1, min(1, deltaY / yRange))
        return StickPosition(x: x, y: y)
    }

    private static func insert(
        _ button: JoyConButton,
        if condition: Bool,
        into buttons: inout Set<JoyConButton>
    ) {
        if condition { buttons.insert(button) }
    }

    private static func decodeStick(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> (x: UInt16, y: UInt16) {
        let x = UInt16(first) | ((UInt16(second) & 0x0F) << 8)
        let y = (UInt16(second) >> 4) | (UInt16(third) << 4)
        return (x, y)
    }

    private static func parseGyroCalibration(_ data: [UInt8]) -> GyroCalibration? {
        guard data.count >= 24 else { return nil }
        let offset = Vector3(
            x: Double(int16(data, 12)),
            y: Double(int16(data, 14)),
            z: Double(int16(data, 16))
        )
        let sensitivity = Vector3(
            x: Double(int16(data, 18)),
            y: Double(int16(data, 20)),
            z: Double(int16(data, 22))
        )
        let denominatorX = sensitivity.x - offset.x
        let denominatorY = sensitivity.y - offset.y
        let denominatorZ = sensitivity.z - offset.z
        guard abs(denominatorX) > 1, abs(denominatorY) > 1, abs(denominatorZ) > 1 else { return nil }

        return GyroCalibration(
            offset: offset,
            coefficient: Vector3(
                x: 936 / denominatorX,
                y: 936 / denominatorY,
                z: 936 / denominatorZ
            )
        )
    }

    private static func parseRightStickCalibration(_ data: [UInt8]) -> StickCalibration? {
        guard data.count >= 9 else { return nil }
        let value0 = UInt16(data[0]) | ((UInt16(data[1]) & 0x0F) << 8)
        let value1 = (UInt16(data[1]) >> 4) | (UInt16(data[2]) << 4)
        let value2 = UInt16(data[3]) | ((UInt16(data[4]) & 0x0F) << 8)
        let value3 = (UInt16(data[4]) >> 4) | (UInt16(data[5]) << 4)
        let value4 = UInt16(data[6]) | ((UInt16(data[7]) & 0x0F) << 8)
        let value5 = (UInt16(data[7]) >> 4) | (UInt16(data[8]) << 4)

        return StickCalibration(
            centerX: Double(value0),
            centerY: Double(value1),
            negativeRangeX: Double(value2),
            positiveRangeX: Double(value4),
            negativeRangeY: Double(value3),
            positiveRangeY: Double(value5)
        )
    }

    private static func int16(_ data: [UInt8], _ offset: Int) -> Int16 {
        let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        return Int16(bitPattern: raw)
    }
}
