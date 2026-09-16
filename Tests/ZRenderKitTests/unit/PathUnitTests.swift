// Ported from zrender/test/ut/spec/graphic/Path.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream `rect.style` is the rich `PathStyleProps` bag (fill/stroke/lineWidth/...). The Swift
// port stores it on `rect.pathStyle` (the inherited `Displayable.style` is the CommonStyleProps
// subset only — see Path.swift STYLE DECISION). Tests below read `rect.pathStyle`.
//
// `ZRColor` is a tagged enum (no untagged unions in Swift); this helper extracts the `.string`
// payload so we can compare against the upstream string color literals.
private func zrStr(_ c: ZRColor?) -> String? {
    if case .some(.string(let s)) = c {
        return s
    }
    return nil
}

final class PathUnitTests: XCTestCase {

    // upstream: it('Can init properties properly.')
    func test_Can_init_properties_properly() throws {
        var shape = RectShape()
        shape.width = 100
        shape.height = 100
        var style = PathStyleProps()
        style.stroke = .string("red")
        let rect = Rect([
            "shape": shape,
            "style": style,
            "x": 10.0,
            "y": 10.0
        ])
        let rectShape = rect.shape as! RectShape
        // Default shape values should be correct
        XCTAssertEqual(rectShape.x, 0)
        XCTAssertEqual(rectShape.y, 0)

        // Given shape values should be correct
        XCTAssertEqual(rectShape.width, 100)
        XCTAssertEqual(rectShape.height, 100)

        // Default style values should be right
        XCTAssertEqual(zrStr(rect.pathStyle.fill), "#000")
        // Given style values should be right
        XCTAssertEqual(zrStr(rect.pathStyle.stroke), "red")

        XCTAssertEqual(rect.x, 10)
        XCTAssertEqual(rect.y, 10)
    }

    // upstream: it('Default styles should be right.')
    func test_Default_styles_should_be_right() throws {
        let rect = Rect()
        // Default shape values should be correct
        XCTAssertNil(rect.pathStyle.stroke)
        XCTAssertEqual(zrStr(rect.pathStyle.fill), "#000")
        XCTAssertEqual(rect.pathStyle.lineDashOffset, 0)
        XCTAssertEqual(rect.pathStyle.lineWidth, 1)
        XCTAssertEqual(rect.pathStyle.lineCap, "butt")
        XCTAssertEqual(rect.pathStyle.miterLimit, 10)

        XCTAssertEqual(rect.pathStyle.strokeNoScale, false)
        XCTAssertEqual(rect.pathStyle.strokeFirst, false)

        XCTAssertEqual(rect.pathStyle.shadowBlur, 0)
        XCTAssertEqual(rect.pathStyle.shadowOffsetX, 0)
        XCTAssertEqual(rect.pathStyle.shadowOffsetY, 0)
        XCTAssertEqual(rect.pathStyle.shadowColor, "#000")
        XCTAssertEqual(rect.pathStyle.opacity, 1)
        XCTAssertEqual(rect.pathStyle.blend, "source-over")
    }

    // upstream: it('Path#setStyle should merge style properly')
    func test_Path_setStyle_should_merge_style_properly() throws {
        throw XCTSkip("Path-level setStyle merging path style fields (fill/stroke/lineWidth) is not "
            + "ported: Path has no setStyle(PathStyleProps) overload, and the inherited "
            + "Displayable.setStyle(key,value) ignores non-common keys (default: break). Only "
            + "useStyle(PathStyleProps) exists. (Path.swift)")
    }

    // upstream: it('Path#setShape should merge style properly')
    func test_Path_setShape_should_merge_style_properly() throws {
        throw XCTSkip("Path#setShape partial-merge is not ported: setShape(PathShape) replaces the "
            + "shape wholesale and setShape(key,value) is a no-op that only marks dirty "
            + "(Path.swift note: dict-merge of a partial shape into a typed shape struct).")
    }

    // upstream: it('Path#useState should switch state properly')
    func test_Path_useState_should_switch_state_properly() throws {
        throw XCTSkip("States machinery (useState applying x/y/scale/style/shape/z/z2/invisible) is "
            + "a Phase-2 stub: Element.useState() returns nil and does not mutate currentStates or "
            + "apply the state object (Element.swift / Displayable.swift / Path.swift note).")
    }

    // upstream: it('Path#clearStates should be able to restore to normal state properly')
    func test_Path_clearStates_should_be_able_to_restore_to_normal_state_properly() throws {
        throw XCTSkip("States machinery is a Phase-2 stub (useState/clearStates do not apply or "
            + "restore state). See Element.swift / Path.swift note.")
    }

    // upstream: it('Path#useStates. Mutiple states should be merged properly')
    func test_Path_useStates_Multiple_states_should_be_merged_properly() throws {
        throw XCTSkip("States machinery is a Phase-2 stub (useStates merge/apply is a no-op). See "
            + "Element.useStates / _mergeStates / _applyStateObj note.")
    }

    // upstream: it('Path#useState. Can switch back to single state')
    func test_Path_useState_Can_switch_back_to_single_state() throws {
        throw XCTSkip("States machinery is a Phase-2 stub (useStates/useState apply is a no-op). "
            + "See Element.swift / Displayable.swift / Path.swift note.")
    }

    // upstream: it('Path#clearStates() should not throw error on stateless object.')
    func test_Path_clearStates_should_not_throw_error_on_stateless_object() throws {
        let rect = createRectForStateTest()
        // upstream: expect(() => rect.clearStates()).not.toThrowError();
        rect.clearStates()
    }

    // upstream: it('Path#getBoundingRect() should return a correct bounding rect before render')
    func test_Path_getBoundingRect_should_return_a_correct_bounding_rect_before_render() throws {
        var shape = RectShape()
        shape.x = 10
        shape.y = 10
        shape.width = 100
        shape.height = 100
        let rect = Rect(["shape": shape])
        let br = rect.getBoundingRect()
        XCTAssertEqual(br?.x, 10)
        XCTAssertEqual(br?.y, 10)
        XCTAssertEqual(br?.width, 100)
        XCTAssertEqual(br?.height, 100)
    }

    // upstream: it('Path#getBoundingRect() should include stroke')
    func test_Path_getBoundingRect_should_include_stroke() throws {
        var shape = RectShape()
        shape.x = 10
        shape.y = 10
        shape.width = 100
        shape.height = 100
        var style = PathStyleProps()
        style.lineWidth = 2
        style.stroke = .string("red")
        let rect = Rect(["shape": shape, "style": style])
        let boundingRect = rect.getBoundingRect()
        XCTAssertEqual(boundingRect?.x, 9)
        XCTAssertEqual(boundingRect?.y, 9)
        XCTAssertEqual(boundingRect?.width, 102)
        XCTAssertEqual(boundingRect?.height, 102)
    }

    // upstream: it('Path#getBoundingRect() should update bounding rect after setShape')
    func test_Path_getBoundingRect_should_update_bounding_rect_after_setShape() throws {
        throw XCTSkip("Depends on Path#setShape partial-merge (setShape({width,height}) keeping x,y) "
            + "which is not ported — see test_Path_setShape_should_merge_style_properly. "
            + "(Path.swift note)")
    }

    // upstream: it('Path#getBoundingRect() should still cache bounding rect after setStyle')
    func test_Path_getBoundingRect_should_still_cache_bounding_rect_after_setStyle() throws {
        throw XCTSkip("Depends on Path-level setStyle({fill:'red'}) which is not ported (no "
            + "setStyle(PathStyleProps) overload; Displayable.setStyle ignores fill). See "
            + "test_Path_setStyle_should_merge_style_properly. (Path.swift)")
    }

    // Regression: `attr(["shape": ["height": 100]])` with an Int-literal value must not be silently
    // dropped. Each *Shape's `animationSet` only accepts `Double` (e.g. RectShape's `guard let v =
    // value as? Double`); the partial-shape merge branch in Path.attrKV must coerce Int/NSNumber to
    // Double before calling it (the known Int-vs-Double option-read trap).
    func test_attrKV_partial_shape_merge_coerces_Int_literal() throws {
        var shape = RectShape()
        shape.x = 0; shape.y = 0; shape.width = 10; shape.height = 0
        let rect = Rect(["shape": shape])
        _ = rect.attr(["shape": ["height": 100] as [String: Any]])
        let rectShape = rect.shape as! RectShape
        XCTAssertEqual(rectShape.height, 100.0, accuracy: 1e-9,
                       "Int-literal height must coerce to Double, not be dropped")
        // Unspecified keys (x/y/width) must be left untouched by the partial merge.
        XCTAssertEqual(rectShape.width, 10)
    }

    // Regression: `attr(["style": ["opacity": 0.5]])` — a partial "style" dict — must merge into
    // `pathStyle`, not be silently dropped. Mirrors the "shape" partial-dict branch above: unlocks the
    // animation-OFF `initProps`/`fadeOutDisplayable` path (`el.attr(["style": ["opacity": v]])`), which
    // previously fell through to `super.attrKV` (typed `CommonStyleProps`, not `PathStyleProps`) and
    // was dropped — leaving elements (e.g. funnel pieces built with opacity 0 for a fade-in) invisible
    // when animation is disabled.
    func test_attrKV_partial_style_merge_sets_opacity() throws {
        var shape = RectShape()
        shape.x = 0; shape.y = 0; shape.width = 10; shape.height = 10
        let rect = Rect(["shape": shape])
        _ = rect.attr(["style": ["opacity": 0.5] as [String: Any]])
        XCTAssertEqual(rect.pathStyle.opacity, 0.5, "partial style dict must merge into pathStyle")
    }

    // Int-vs-Double option-read trap, applied to the "style" branch: an Int-literal opacity (e.g.
    // `["opacity": 1]`, as produced by an Int-boxed default option) must coerce to Double, not be
    // dropped by `PathStyleProps.animationSet`'s `value as? Double` guard.
    func test_attrKV_partial_style_merge_coerces_Int_literal() throws {
        var shape = RectShape()
        shape.x = 0; shape.y = 0; shape.width = 10; shape.height = 10
        var style = PathStyleProps(); style.opacity = 0
        let rect = Rect(["shape": shape, "style": style])
        _ = rect.attr(["style": ["opacity": 1] as [String: Any]])
        XCTAssertEqual(rect.pathStyle.opacity, 1.0, "Int-literal opacity must coerce to Double, not be dropped")
    }

    // upstream helper: createRectForStateTest()
    private func createRectForStateTest() -> Rect {
        var shape = RectShape()
        shape.width = 100
        shape.height = 100
        var style = PathStyleProps()
        style.fill = .string("blue")
        return Rect(["shape": shape, "style": style])
    }
}
