// StateMachineryTests.swift — exercises the ported Element state machinery
// (ensureState / useState / useStates / clearStates / toggleState + stateTransition), the engine
// behind test/state.html. Self-contained: @testable import only, drives the transition animators'
// clips at deterministic timestamps (no wall clock), exactly like AnimationSmokeTests.

import XCTest
@testable import ZRenderKit

final class StateMachineryTests: XCTestCase {

    /// Build the state.html rect: shape {-50,-50,100,100} at (100,100), red, with the 6 states and an
    /// (non-additive, for deterministic endpoints) cubicOut stateTransition.
    private func makeStatefulRect() -> Rect {
        var rs = RectShape(); rs.x = -50; rs.y = -50; rs.width = 100; rs.height = 100
        let r = Rect(); r.setShape(rs)
        r.x = 100; r.y = 100
        var st = PathStyleProps(); st.fill = .string("red"); st.shadowColor = "rgba(0,0,0,0.5)"
        r.useStyle(st)

        r.ensureState("moveRight").x = 200
        r.ensureState("moveDown").y = 200
        r.ensureState("rotate").rotation = 2
        r.ensureState("enlarge").shape = ["x": -100.0, "y": -100.0, "width": 200.0, "height": 200.0]
        r.ensureState("changeFill").style = ["fill": "green"]   // raw string (html: 'green'); color tween
        r.ensureState("shadow").style = ["shadowBlur": 20.0]

        var transition = ElementAnimateConfig()
        transition.duration = 1000
        transition.additive = false   // endpoints are identical to additive; simpler to assert
        transition.easing = .named("cubicOut")
        r.stateTransition = transition
        return r
    }

    private var clock: Double = 0
    /// Drive every running animator on `el` to completion (steps each clip from `clock` to clock+ms).
    private func drive(_ el: Element, _ ms: Double = 1000) {
        let start = clock
        let anims = el.animators
        for a in anims { _ = a.getClip()?.step(start, 0) }      // first step pins _startTime = start
        clock = start + ms
        for a in anims { _ = a.getClip()?.step(clock, ms) }     // jump to end → final keyframe
    }

    private func rectWidth(_ r: Rect) -> Double? { (r.shape as? RectShape)?.width }

    func test_toggle_transform_state_applies_and_restores() throws {
        let r = makeStatefulRect()
        XCTAssertEqual(r.x, 100)
        XCTAssertFalse(r.hasState())

        // Toggle moveRight ON → animates x 100 -> 200.
        r.toggleState("moveRight", true)
        XCTAssertTrue(r.hasState())
        XCTAssertEqual(r.currentStates, ["moveRight"])
        drive(r)
        XCTAssertEqual(r.x, 200, accuracy: 1e-6, "moveRight should animate x to 200")

        // Toggle moveRight OFF → restores x -> 100 (normal).
        r.toggleState("moveRight", false)
        XCTAssertFalse(r.hasState())
        XCTAssertEqual(r.currentStates, [])
        drive(r)
        XCTAssertEqual(r.x, 100, accuracy: 1e-6, "removing moveRight should restore x to 100")
    }

    func test_toggle_shape_state_enlarge() throws {
        let r = makeStatefulRect()
        XCTAssertEqual(rectWidth(r), 100)

        r.toggleState("enlarge", true)
        drive(r)
        XCTAssertEqual(rectWidth(r) ?? 0, 200, accuracy: 1e-6, "enlarge should animate shape.width to 200")

        r.toggleState("enlarge", false)
        drive(r)
        XCTAssertEqual(rectWidth(r) ?? 0, 100, accuracy: 1e-6, "removing enlarge should restore shape.width to 100")
    }

    func test_toggle_style_state_shadow() throws {
        let r = makeStatefulRect()
        XCTAssertEqual(r.pathStyle.shadowBlur ?? 0, 0)

        r.toggleState("shadow", true)
        drive(r)
        XCTAssertEqual(r.pathStyle.shadowBlur ?? 0, 20, accuracy: 1e-6, "shadow should animate shadowBlur to 20")

        r.toggleState("shadow", false)
        drive(r)
        XCTAssertEqual(r.pathStyle.shadowBlur ?? 0, 0, accuracy: 1e-6, "removing shadow should restore shadowBlur to 0")
    }

    /// fill color state (red -> green) — exercises the color tween through the ZRColor↔string bridge.
    private func fillString(_ r: Rect) -> String? {
        if case .some(.string(let s)) = r.pathStyle.fill { return s }
        return nil
    }

    func test_toggle_fill_color_state() throws {
        let r = makeStatefulRect()
        XCTAssertEqual(fillString(r), "red")

        r.toggleState("changeFill", true)
        drive(r)
        // At completion the fill is the target green (the tween emits an rgba string; parse-compare it).
        let applied = try XCTUnwrap(color.parse(fillString(r) ?? ""))
        let green = try XCTUnwrap(color.parse("green"))
        for i in 0..<3 { XCTAssertEqual(applied[i], green[i], accuracy: 1.0, "changeFill should reach green (channel \(i))") }

        r.toggleState("changeFill", false)
        drive(r)
        let restored = try XCTUnwrap(color.parse(fillString(r) ?? ""))
        let red = try XCTUnwrap(color.parse("red"))
        for i in 0..<3 { XCTAssertEqual(restored[i], red[i], accuracy: 1.0, "removing changeFill should restore red (channel \(i))") }
    }

    func test_additive_accumulation_then_clearStates() throws {
        let r = makeStatefulRect()

        // Stack two states: moveRight (x) then enlarge (shape). Both stay active (keepCurrentStates).
        r.toggleState("moveRight", true)
        drive(r)
        r.toggleState("enlarge", true)
        drive(r)
        XCTAssertEqual(r.currentStates, ["moveRight", "enlarge"])
        XCTAssertEqual(r.x, 200, accuracy: 1e-6, "moveRight stays applied while enlarge is added")
        XCTAssertEqual(rectWidth(r) ?? 0, 200, accuracy: 1e-6, "enlarge applied on top of moveRight")

        // clearStates → everything restores to normal.
        r.clearStates()
        XCTAssertFalse(r.hasState())
        drive(r)
        XCTAssertEqual(r.x, 100, accuracy: 1e-6, "clearStates restores x")
        XCTAssertEqual(rectWidth(r) ?? 0, 100, accuracy: 1e-6, "clearStates restores shape.width")
    }

    func test_useStates_merges_and_restores_dropped() throws {
        let r = makeStatefulRect()

        // Apply moveRight + moveDown together.
        r.useStates(["moveRight", "moveDown"])
        drive(r)
        XCTAssertEqual(r.x, 200, accuracy: 1e-6)
        XCTAssertEqual(r.y, 200, accuracy: 1e-6)

        // Switch to just moveDown → x should drop back to normal (100), y stays 200.
        r.useStates(["moveDown"])
        drive(r)
        XCTAssertEqual(r.x, 100, accuracy: 1e-6, "dropping moveRight restores x to normal")
        XCTAssertEqual(r.y, 200, accuracy: 1e-6, "moveDown still keeps y at 200")
    }
}
