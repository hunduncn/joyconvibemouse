import XCTest
@testable import JoyConVibeCore

final class RemoteActionMapperTests: XCTestCase {
    func testDefaultBindingsMatchTheFinalDocumentedLayout() {
        let bindings = RemoteButtonBinding.defaultBindings

        XCTAssertEqual(bindings[.r], .init(primary: .function, withSL: .usePrimary))
        XCTAssertEqual(bindings[.sr], .init(primary: .returnKey, withSL: .newLine))
        XCTAssertEqual(bindings[.a], .init(primary: .escape, withSL: .interrupt))
        XCTAssertEqual(bindings[.b], .init(primary: .rightClick, withSL: .usePrimary))
        XCTAssertEqual(bindings[.x], .init(primary: .deleteBackward, withSL: .usePrimary))
        XCTAssertEqual(bindings[.y], .init(primary: .leftClick, withSL: .usePrimary))
        XCTAssertEqual(bindings[.plus], .init(primary: .switchApplication, withSL: .usePrimary))
        XCTAssertEqual(bindings[.home], .init(primary: .showStatus, withSL: .commandSymbols))
        XCTAssertEqual(bindings[.stick], .init(primary: .tab, withSL: .reverseTab))
        XCTAssertEqual(
            RemoteStickVerticalBinding.defaultBinding,
            .init(primary: .scroll, withSL: .arrowKeys)
        )
    }

    func testFinalButtonLayoutAndNoRepeatForR() {
        var mapper = RemoteActionMapper()
        let pressed = JoyConInputFrame(
            buttons: [.r, .zr, .sr, .sl, .a, .b, .x, .y, .plus, .home],
            stick: .zero
        )

        let actions = mapper.process(frame: pressed, timestamp: 1)
        XCTAssertTrue(actions.contains(.keyTap(.function)))
        XCTAssertTrue(actions.contains(.keyTap(.returnKey)))
        XCTAssertTrue(actions.contains(.keyTap(.deleteBackward)))
        XCTAssertTrue(actions.contains(.keyTap(.escape)))
        XCTAssertTrue(actions.contains(.mouseButton(.left, isDown: true)))
        XCTAssertTrue(actions.contains(.mouseButton(.right, isDown: true)))
        XCTAssertTrue(actions.contains(.switchApplication))
        XCTAssertTrue(actions.contains(.showStatus))
        XCTAssertEqual(actions.filter { $0 == .keyTap(.function) }.count, 1)

        let heldActions = mapper.process(frame: pressed, timestamp: 1.1)
        XCTAssertFalse(heldActions.contains(.keyTap(.function)))
        XCTAssertFalse(heldActions.contains(.keyTap(.returnKey)))

        let released = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 1.2
        )
        XCTAssertTrue(released.contains(.mouseButton(.left, isDown: false)))
        XCTAssertTrue(released.contains(.mouseButton(.right, isDown: false)))
    }

    func testZRIsReservedForPointerAndSRDefaultsToReturn() {
        var mapper = RemoteActionMapper()

        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.zr], stick: .zero),
            timestamp: 2
        ).isEmpty)
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 2.1
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sr], stick: .zero),
            timestamp: 2.2
        ), [.keyTap(.returnKey)])
    }

    func testStickScrollsAndHorizontalDirectionRepeats() {
        var mapper = RemoteActionMapper()
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 10
        )

        let scrollActions = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: StickPosition(x: 0, y: 1)),
            timestamp: 10.016
        )
        XCTAssertTrue(scrollActions.contains { action in
            if case let .scroll(points) = action { return points > 0 }
            return false
        })

        let leftActions = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: StickPosition(x: -1, y: 0)),
            timestamp: 11
        )
        XCTAssertEqual(leftActions, [.keyTap(.leftArrow)])
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: StickPosition(x: -1, y: 0)),
            timestamp: 11.2
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: StickPosition(x: -1, y: 0)),
            timestamp: 11.4
        ), [.keyTap(.leftArrow)])
    }

    func testResetReleasesHeldMouseButtons() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a]?.primary = .leftClick
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.a, .b], stick: .zero),
            timestamp: 1,
            buttonBindings: bindings
        )
        let released = mapper.reset()
        XCTAssertEqual(released.count, 2)
        XCTAssertTrue(released.contains(.mouseButton(.left, isDown: false)))
        XCTAssertTrue(released.contains(.mouseButton(.right, isDown: false)))
    }

    func testCustomMappingsOverrideDefaultsAndSupportHeldModifiers() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.r]?.primary = .space
        bindings[.a]?.primary = .commandModifier
        bindings[.b]?.primary = .returnKey

        let pressed = mapper.process(
            frame: JoyConInputFrame(buttons: [.r, .a, .b], stick: .zero),
            timestamp: 1,
            buttonBindings: bindings
        )
        XCTAssertTrue(pressed.contains(.keyTap(.space)))
        XCTAssertTrue(pressed.contains(.keyTap(.returnKey)))
        XCTAssertTrue(pressed.contains(.keyModifier(.command, isDown: true)))
        XCTAssertFalse(pressed.contains(.keyTap(.function)))

        let released = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 1.1,
            buttonBindings: bindings
        )
        XCTAssertTrue(released.contains(.keyModifier(.command, isDown: false)))
    }

    func testDuplicateMouseMappingsReleaseOnlyAfterTheLastPhysicalButton() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a]?.primary = .leftClick
        bindings[.b]?.primary = .leftClick

        let bothPressed = mapper.process(
            frame: JoyConInputFrame(buttons: [.a, .b], stick: .zero),
            timestamp: 2,
            buttonBindings: bindings
        )
        XCTAssertEqual(
            bothPressed.filter { $0 == .mouseButton(.left, isDown: true) }.count,
            1
        )

        let oneReleased = mapper.process(
            frame: JoyConInputFrame(buttons: [.b], stick: .zero),
            timestamp: 2.1,
            buttonBindings: bindings
        )
        XCTAssertFalse(oneReleased.contains(.mouseButton(.left, isDown: false)))

        let allReleased = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 2.2,
            buttonBindings: bindings
        )
        XCTAssertTrue(allReleased.contains(.mouseButton(.left, isDown: false)))
    }

    func testResetReleasesHeldCustomModifier() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a]?.primary = .optionModifier

        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.a], stick: .zero),
            timestamp: 3,
            buttonBindings: bindings
        )

        XCTAssertEqual(mapper.reset(), [.keyModifier(.option, isDown: false)])
    }

    func testDeleteRepeatsWhenMappedToAnotherButton() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.r]?.primary = .deleteBackward

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.r], stick: .zero),
            timestamp: 4,
            buttonBindings: bindings
        ), [.keyTap(.deleteBackward)])
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.r], stick: .zero),
            timestamp: 4.3,
            buttonBindings: bindings
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.r], stick: .zero),
            timestamp: 4.43,
            buttonBindings: bindings
        ), [.keyTap(.deleteBackward)])
    }

    func testSLHomeCyclesCommandSymbolsByReplacingPreviousSymbol() {
        var mapper = RemoteActionMapper()

        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 5
        ).isEmpty)

        let expectedSymbols = ["/", "@", "$", "!", "/"]
        for (offset, symbol) in expectedSymbols.enumerated() {
            let pressTime = 5.1 + Double(offset) * 0.2
            let pressed = mapper.process(
                frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
                timestamp: pressTime
            )
            if offset == 0 {
                XCTAssertEqual(pressed, [.typeText(symbol)])
            } else {
                XCTAssertEqual(pressed, [.keyShortcut(.deleteBackward, modifiers: []), .typeText(symbol)])
            }
            XCTAssertTrue(mapper.process(
                frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
                timestamp: pressTime + 0.05
            ).isEmpty)
        }
    }

    func testSLHomeSymbolIsCommittedWhenSLIsReleased() {
        var mapper = RemoteActionMapper()
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
            timestamp: 6
        )
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 6.1
        )

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
            timestamp: 6.2
        ), [.typeText("/")])
    }

    func testSLHomeSymbolIsCommittedAfterTimeoutOrOtherInput() {
        var mapper = RemoteActionMapper()
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
            timestamp: 7
        )
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 7.05
        )

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .sr], stick: .zero),
            timestamp: 7.2
        ), [.keyShortcut(.returnKey, modifiers: [.shift])])
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 7.25
        )
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
            timestamp: 7.3
        ), [.typeText("/")])

        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 7.35
        )
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 8.5
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .home], stick: .zero),
            timestamp: 8.6
        ), [.typeText("/")])
    }

    func testZRSLHomeKeepsHomeMappingAndPrecisionChordSeparate() {
        var mapper = RemoteActionMapper()

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.zr, .sl, .home], stick: .zero),
            timestamp: 9
        ), [.showStatus])
    }

    func testSLAgentLayerEmitsNewlineInterruptAndReverseTabShortcuts() {
        var mapper = RemoteActionMapper()

        let actions = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .sr, .a, .stick], stick: .zero),
            timestamp: 10
        )

        XCTAssertTrue(actions.contains(.keyShortcut(.returnKey, modifiers: [.shift])))
        XCTAssertTrue(actions.contains(.keyShortcut(.c, modifiers: [.control])))
        XCTAssertTrue(actions.contains(.keyShortcut(.tab, modifiers: [.shift])))
        XCTAssertFalse(actions.contains(.keyTap(.returnKey)))
        XCTAssertFalse(actions.contains(.keyTap(.escape)))
        XCTAssertFalse(actions.contains(.keyTap(.tab)))
    }

    func testSLAgentLayerTurnsVerticalStickIntoRepeatingArrowKeys() {
        var mapper = RemoteActionMapper()
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 11
        )

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(
                buttons: [.sl],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 11.1
        ), [.keyTap(.upArrow)])
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(
                buttons: [.sl],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 11.3
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(
                buttons: [.sl],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 11.5
        ), [.keyTap(.upArrow)])
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(
                buttons: [.sl],
                stick: StickPosition(x: 0, y: -1)
            ),
            timestamp: 11.6
        ), [.keyTap(.downArrow)])
    }

    func testZRDisablesSLAgentLayerAndPreservesNormalMappingsAndScroll() {
        var mapper = RemoteActionMapper()
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [.zr, .sl], stick: .zero),
            timestamp: 12
        )

        let actions = mapper.process(
            frame: JoyConInputFrame(
                buttons: [.zr, .sl, .sr, .a, .stick],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 12.1
        )

        XCTAssertTrue(actions.contains(.keyTap(.returnKey)))
        XCTAssertTrue(actions.contains(.keyTap(.escape)))
        XCTAssertTrue(actions.contains(.keyTap(.tab)))
        XCTAssertTrue(actions.contains { action in
            if case .scroll = action { return true }
            return false
        })
        XCTAssertFalse(actions.contains(.keyShortcut(.c, modifiers: [.control])))
    }

    func testPrimaryAndSLMappingsAreAConfigurablePair() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.sr]?.withSL = .space

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sr], stick: .zero),
            timestamp: 13,
            buttonBindings: bindings
        ), [.keyTap(.returnKey)])
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 13.1,
            buttonBindings: bindings
        )
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .sr], stick: .zero),
            timestamp: 13.2,
            buttonBindings: bindings
        ), [.keyTap(.space)])
    }

    func testUsePrimaryKeepsTheNormalActionAvailableInsideSLLayer() {
        var mapper = RemoteActionMapper()

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .x], stick: .zero),
            timestamp: 14
        ), [.keyTap(.deleteBackward)])
    }

    func testCustomSLMappingReplacesTheDefaultSemanticAction() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a]?.withSL = .space
        bindings[.home]?.withSL = .showStatus

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .a, .home], stick: .zero),
            timestamp: 15,
            buttonBindings: bindings
        ), [.keyTap(.space), .showStatus])
    }

    func testHeldPrimaryMouseActionStillReleasesAfterSLLayerIsEntered() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a] = .init(primary: .leftClick, withSL: .interrupt)

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.a], stick: .zero),
            timestamp: 16,
            buttonBindings: bindings
        ), [.mouseButton(.left, isDown: true)])
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.a, .sl], stick: .zero),
            timestamp: 16.1,
            buttonBindings: bindings
        ).isEmpty)
        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl], stick: .zero),
            timestamp: 16.2,
            buttonBindings: bindings
        ), [.mouseButton(.left, isDown: false)])
    }

    func testReleasingSLFirstDoesNotBackfillThePrimaryAction() {
        var mapper = RemoteActionMapper()
        var bindings = RemoteButtonBinding.defaultBindings
        bindings[.a] = .init(primary: .leftClick, withSL: .interrupt)

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(buttons: [.sl, .a], stick: .zero),
            timestamp: 17,
            buttonBindings: bindings
        ), [.keyShortcut(.c, modifiers: [.control])])
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [.a], stick: .zero),
            timestamp: 17.1,
            buttonBindings: bindings
        ).isEmpty)
        XCTAssertTrue(mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 17.2,
            buttonBindings: bindings
        ).isEmpty)
    }

    func testVerticalStickModesAreBoundAndConfigurableTogether() {
        var mapper = RemoteActionMapper()
        let binding = RemoteStickVerticalBinding(primary: .arrowKeys, withSL: .scroll)

        XCTAssertEqual(mapper.process(
            frame: JoyConInputFrame(
                buttons: [],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 18,
            stickVerticalBinding: binding
        ), [.keyTap(.upArrow)])
        _ = mapper.process(
            frame: JoyConInputFrame(buttons: [], stick: .zero),
            timestamp: 18.1,
            stickVerticalBinding: binding
        )
        let slActions = mapper.process(
            frame: JoyConInputFrame(
                buttons: [.sl],
                stick: StickPosition(x: 0, y: 1)
            ),
            timestamp: 18.2,
            stickVerticalBinding: binding
        )
        XCTAssertTrue(slActions.contains { action in
            if case let .scroll(points) = action { return points > 0 }
            return false
        })
        XCTAssertFalse(slActions.contains(.keyTap(.upArrow)))
    }
}
