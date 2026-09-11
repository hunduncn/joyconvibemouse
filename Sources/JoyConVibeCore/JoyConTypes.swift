import Foundation

public enum JoyConButton: String, CaseIterable, Hashable, Sendable {
    case a
    case b
    case x
    case y
    case sr
    case sl
    case r
    case zr
    case plus
    case home
    case stick
}

public struct Vector3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

public struct StickPosition: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = StickPosition(x: 0, y: 0)
}

public struct GyroSample: Equatable, Sendable {
    /// Calibrated angular velocity in degrees per second.
    public var degreesPerSecond: Vector3
    /// Accelerometer reading in the Joy-Con sensor coordinate system.
    /// Only its direction is used to compensate for the controller's roll.
    public var acceleration: Vector3

    public init(
        degreesPerSecond: Vector3,
        acceleration: Vector3 = .zero
    ) {
        self.degreesPerSecond = degreesPerSecond
        self.acceleration = acceleration
    }
}

public struct JoyConInputFrame: Equatable, Sendable {
    public var buttons: Set<JoyConButton>
    public var stick: StickPosition
    public var gyroSamples: [GyroSample]
    public var batteryLevel: Int
    public var isCharging: Bool

    public init(
        buttons: Set<JoyConButton>,
        stick: StickPosition,
        gyroSamples: [GyroSample] = [],
        batteryLevel: Int = 0,
        isCharging: Bool = false
    ) {
        self.buttons = buttons
        self.stick = stick
        self.gyroSamples = gyroSamples
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
    }
}

public struct SPIFlashReply: Equatable, Sendable {
    public var address: UInt32
    public var data: [UInt8]

    public init(address: UInt32, data: [UInt8]) {
        self.address = address
        self.data = data
    }
}

public struct JoyConDecodedReport: Equatable, Sendable {
    public var frame: JoyConInputFrame?
    public var spiReply: SPIFlashReply?

    public init(frame: JoyConInputFrame? = nil, spiReply: SPIFlashReply? = nil) {
        self.frame = frame
        self.spiReply = spiReply
    }
}

public struct GyroCalibration: Equatable, Sendable {
    public var offset: Vector3
    public var coefficient: Vector3

    public init(offset: Vector3, coefficient: Vector3) {
        self.offset = offset
        self.coefficient = coefficient
    }

    public static let fallback = GyroCalibration(
        offset: .zero,
        coefficient: Vector3(x: 0.06103, y: 0.06103, z: 0.06103)
    )
}

public struct StickCalibration: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var negativeRangeX: Double
    public var positiveRangeX: Double
    public var negativeRangeY: Double
    public var positiveRangeY: Double

    public init(
        centerX: Double,
        centerY: Double,
        negativeRangeX: Double,
        positiveRangeX: Double,
        negativeRangeY: Double,
        positiveRangeY: Double
    ) {
        self.centerX = centerX
        self.centerY = centerY
        self.negativeRangeX = max(negativeRangeX, 1)
        self.positiveRangeX = max(positiveRangeX, 1)
        self.negativeRangeY = max(negativeRangeY, 1)
        self.positiveRangeY = max(positiveRangeY, 1)
    }

    public static let fallback = StickCalibration(
        centerX: 2048,
        centerY: 2048,
        negativeRangeX: 1700,
        positiveRangeX: 1700,
        negativeRangeY: 1700,
        positiveRangeY: 1700
    )
}

public struct PointerSettings: Equatable, Sendable {
    public var sensitivity: Double
    public var horizontalSensitivityMultiplier: Double
    public var accelerationStrength: Double
    public var stabilizationStrength: Double
    public var precisionMultiplier: Double
    public var invertHorizontal: Bool
    public var invertVertical: Bool
    public var screenWidthPoints: Double

    public init(
        sensitivity: Double = 1,
        horizontalSensitivityMultiplier: Double = 1.40,
        accelerationStrength: Double = 1,
        stabilizationStrength: Double = 1,
        precisionMultiplier: Double = 0.35,
        invertHorizontal: Bool = false,
        invertVertical: Bool = false,
        screenWidthPoints: Double = 1920
    ) {
        self.sensitivity = sensitivity
        self.horizontalSensitivityMultiplier = horizontalSensitivityMultiplier
        self.accelerationStrength = accelerationStrength
        self.stabilizationStrength = stabilizationStrength
        self.precisionMultiplier = precisionMultiplier
        self.invertHorizontal = invertHorizontal
        self.invertVertical = invertVertical
        self.screenWidthPoints = screenWidthPoints
    }
}

public struct PointerDelta: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

public enum RemoteKey: Equatable, Sendable {
    case c
    case function
    case returnKey
    case space
    case tab
    case deleteBackward
    case escape
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
}

public enum RemoteModifier: String, CaseIterable, Equatable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
}

public enum RemoteButtonAction: String, CaseIterable, Equatable, Sendable {
    case usePrimary
    case none
    case function
    case returnKey
    case space
    case tab
    case deleteBackward
    case escape
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case commandModifier
    case optionModifier
    case controlModifier
    case shiftModifier
    case leftClick
    case rightClick
    case switchApplication
    case showStatus
    case newLine
    case interrupt
    case reverseTab
    case commandSymbols

    public static let configurableButtons: [JoyConButton] = [
        .r, .sr, .a, .b, .x, .y, .plus, .home, .stick
    ]

    public static let primaryChoices = allCases.filter {
        ![.usePrimary, .newLine, .interrupt, .reverseTab, .commandSymbols].contains($0)
    }

    public static let slChoices = allCases
}

public struct RemoteButtonBinding: Equatable, Sendable {
    public var primary: RemoteButtonAction
    public var withSL: RemoteButtonAction

    public init(primary: RemoteButtonAction, withSL: RemoteButtonAction) {
        self.primary = primary
        self.withSL = withSL
    }

    public func resolved(isSLActive: Bool) -> RemoteButtonAction {
        guard isSLActive, withSL != .usePrimary else { return primary }
        return withSL
    }

    public static let defaultBindings: [JoyConButton: RemoteButtonBinding] = [
        .r: .init(primary: .function, withSL: .usePrimary),
        .sr: .init(primary: .returnKey, withSL: .newLine),
        .a: .init(primary: .escape, withSL: .interrupt),
        .b: .init(primary: .rightClick, withSL: .usePrimary),
        .x: .init(primary: .deleteBackward, withSL: .usePrimary),
        .y: .init(primary: .leftClick, withSL: .usePrimary),
        .plus: .init(primary: .switchApplication, withSL: .usePrimary),
        .home: .init(primary: .showStatus, withSL: .commandSymbols),
        .stick: .init(primary: .tab, withSL: .reverseTab)
    ]
}

public enum RemoteStickVerticalAction: String, CaseIterable, Equatable, Sendable {
    case usePrimary
    case none
    case scroll
    case arrowKeys

    public static let primaryChoices = allCases.filter { $0 != .usePrimary }
    public static let slChoices = allCases
}

public struct RemoteStickVerticalBinding: Equatable, Sendable {
    public var primary: RemoteStickVerticalAction
    public var withSL: RemoteStickVerticalAction

    public init(primary: RemoteStickVerticalAction, withSL: RemoteStickVerticalAction) {
        self.primary = primary
        self.withSL = withSL
    }

    public func resolved(isSLActive: Bool) -> RemoteStickVerticalAction {
        guard isSLActive, withSL != .usePrimary else { return primary }
        return withSL
    }

    public static let defaultBinding = RemoteStickVerticalBinding(
        primary: .scroll,
        withSL: .arrowKeys
    )
}

public enum RemoteMouseButton: Equatable, Sendable {
    case left
    case right
}

public enum RemoteAction: Equatable, Sendable {
    case keyTap(RemoteKey)
    case keyShortcut(RemoteKey, modifiers: Set<RemoteModifier>)
    case keyModifier(RemoteModifier, isDown: Bool)
    case typeText(String)
    case mouseButton(RemoteMouseButton, isDown: Bool)
    case scroll(points: Double)
    case switchApplication
    case showStatus
}
