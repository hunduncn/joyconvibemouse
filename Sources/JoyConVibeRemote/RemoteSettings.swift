import Combine
import Foundation
import JoyConVibeCore

@MainActor
final class RemoteSettings: ObservableObject {
    private enum Key {
        static let enabled = "remote.enabled"
        static let sensitivity = "pointer.sensitivity"
        static let horizontalSensitivityMultiplier = "pointer.horizontalSensitivityMultiplier"
        static let accelerationStrength = "pointer.accelerationStrength"
        static let stabilizationStrength = "pointer.stabilizationStrength"
        static let precisionMultiplier = "pointer.precisionMultiplier"
        static let invertHorizontal = "pointer.invertHorizontal"
        static let invertVertical = "pointer.invertVertical"
        static let launchAtLogin = "app.launchAtLogin"

        static func buttonMapping(_ button: JoyConButton) -> String {
            "mapping.button.\(button.rawValue)"
        }

        static func slButtonMapping(_ button: JoyConButton) -> String {
            "mapping.button.\(button.rawValue).sl"
        }

        static let stickVerticalPrimary = "mapping.stick.vertical.primary"
        static let stickVerticalSL = "mapping.stick.vertical.sl"
    }

    private let defaults: UserDefaults

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    // Pointer tuning changes continuously while a slider is dragged. These
    // values are deliberately not @Published: publishing every tick used to
    // invalidate the entire console, including every mapping picker, and made
    // the slider and pointer event stream compete for the main thread.
    var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: Key.sensitivity) } }
    var horizontalSensitivityMultiplier: Double {
        didSet { defaults.set(horizontalSensitivityMultiplier, forKey: Key.horizontalSensitivityMultiplier) }
    }
    var accelerationStrength: Double {
        didSet { defaults.set(accelerationStrength, forKey: Key.accelerationStrength) }
    }
    var stabilizationStrength: Double {
        didSet { defaults.set(stabilizationStrength, forKey: Key.stabilizationStrength) }
    }
    var precisionMultiplier: Double {
        didSet { defaults.set(precisionMultiplier, forKey: Key.precisionMultiplier) }
    }
    var invertHorizontal: Bool {
        didSet { defaults.set(invertHorizontal, forKey: Key.invertHorizontal) }
    }
    var invertVertical: Bool {
        didSet { defaults.set(invertVertical, forKey: Key.invertVertical) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }
    @Published private(set) var buttonBindings: [JoyConButton: RemoteButtonBinding]
    @Published private(set) var stickVerticalBinding: RemoteStickVerticalBinding

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        sensitivity = defaults.object(forKey: Key.sensitivity) as? Double ?? 1
        horizontalSensitivityMultiplier = defaults.object(
            forKey: Key.horizontalSensitivityMultiplier
        ) as? Double ?? 1.40
        accelerationStrength = defaults.object(forKey: Key.accelerationStrength) as? Double ?? 1
        stabilizationStrength = defaults.object(forKey: Key.stabilizationStrength) as? Double ?? 1
        precisionMultiplier = defaults.object(forKey: Key.precisionMultiplier) as? Double ?? 0.35
        invertHorizontal = defaults.object(forKey: Key.invertHorizontal) as? Bool ?? false
        invertVertical = defaults.object(forKey: Key.invertVertical) as? Bool ?? false
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? true
        buttonBindings = Dictionary(uniqueKeysWithValues: RemoteButtonAction.configurableButtons.map { button in
            let defaultBinding = RemoteButtonBinding.defaultBindings[button]
                ?? RemoteButtonBinding(primary: .none, withSL: .usePrimary)
            let storedPrimary = defaults.string(forKey: Key.buttonMapping(button))
                .flatMap(RemoteButtonAction.init(rawValue:))
            let storedSL = defaults.string(forKey: Key.slButtonMapping(button))
                .flatMap(RemoteButtonAction.init(rawValue:))
            return (
                button,
                RemoteButtonBinding(
                    primary: storedPrimary ?? defaultBinding.primary,
                    withSL: storedSL ?? defaultBinding.withSL
                )
            )
        })
        let defaultStick = RemoteStickVerticalBinding.defaultBinding
        stickVerticalBinding = RemoteStickVerticalBinding(
            primary: defaults.string(forKey: Key.stickVerticalPrimary)
                .flatMap(RemoteStickVerticalAction.init(rawValue:))
                ?? defaultStick.primary,
            withSL: defaults.string(forKey: Key.stickVerticalSL)
                .flatMap(RemoteStickVerticalAction.init(rawValue:))
                ?? defaultStick.withSL
        )
    }

    func pointerSettings(screenWidthPoints: Double) -> PointerSettings {
        PointerSettings(
            sensitivity: sensitivity,
            horizontalSensitivityMultiplier: horizontalSensitivityMultiplier,
            accelerationStrength: accelerationStrength,
            stabilizationStrength: stabilizationStrength,
            precisionMultiplier: precisionMultiplier,
            invertHorizontal: invertHorizontal,
            invertVertical: invertVertical,
            screenWidthPoints: screenWidthPoints
        )
    }

    func binding(for button: JoyConButton) -> RemoteButtonBinding {
        buttonBindings[button]
            ?? RemoteButtonBinding.defaultBindings[button]
            ?? RemoteButtonBinding(primary: .none, withSL: .usePrimary)
    }

    func setPrimaryMapping(_ action: RemoteButtonAction, for button: JoyConButton) {
        guard RemoteButtonAction.configurableButtons.contains(button) else { return }
        var binding = binding(for: button)
        binding.primary = action
        buttonBindings[button] = binding
        defaults.set(action.rawValue, forKey: Key.buttonMapping(button))
    }

    func setSLMapping(_ action: RemoteButtonAction, for button: JoyConButton) {
        guard RemoteButtonAction.configurableButtons.contains(button) else { return }
        var binding = binding(for: button)
        binding.withSL = action
        buttonBindings[button] = binding
        defaults.set(action.rawValue, forKey: Key.slButtonMapping(button))
    }

    func setStickVerticalPrimary(_ action: RemoteStickVerticalAction) {
        stickVerticalBinding.primary = action
        defaults.set(action.rawValue, forKey: Key.stickVerticalPrimary)
    }

    func setStickVerticalSL(_ action: RemoteStickVerticalAction) {
        stickVerticalBinding.withSL = action
        defaults.set(action.rawValue, forKey: Key.stickVerticalSL)
    }

    func resetButtonMappings() {
        for button in RemoteButtonAction.configurableButtons {
            defaults.removeObject(forKey: Key.buttonMapping(button))
            defaults.removeObject(forKey: Key.slButtonMapping(button))
        }
        defaults.removeObject(forKey: Key.stickVerticalPrimary)
        defaults.removeObject(forKey: Key.stickVerticalSL)
        buttonBindings = RemoteButtonBinding.defaultBindings
        stickVerticalBinding = .defaultBinding
    }
}
