// Proves the manual `el.animate(key).when(...).start()` form routes the value-type `style` / `shape`
// sub-bags through the reference accessors (Path.animate override), so the keyed track interpolates
// the LIVE struct field — not just `animateTo({...})` (covered by ShapeAnimationWiringTests). This is
// what the migrated `poly` (looping `animate('style', true).when(t,{strokePercent}))`) and `curves`
// (`animate('shape').when(t,{r/k/n})`) demos rely on to mirror their zrender test/*.html calls.

import XCTest
@testable import ZRenderKit

final class AnimateKeyRoutingTests: XCTestCase {

    // poly: `outline.animate('style', true).when(2000, {strokePercent: 1}).start('linear')`
    func test_style_strokePercent_animates_through_animate_key() throws {
        let line = Polyline()
        var shp = PolylineShape()
        shp.points = [VectorArray(0, 0), VectorArray(100, 0)]
        line.setShape(shp)
        var st = PathStyleProps()
        st.stroke = .string("#000"); st.lineWidth = 2; st.strokePercent = 0
        line.useStyle(st)

        let anim = line.animate("style", true).when(2000, ["strokePercent": 1.0])
        _ = anim.start(.named("linear"))

        XCTAssertEqual(line.animators.count, 1, "expected one style animator from animate('style')")
        guard let clip = line.animators.first?.getClip() else {
            return XCTFail("no clip — style track was inert (animate('style') not routed to the accessor)")
        }

        _ = clip.step(0, 0)
        XCTAssertEqual(line.pathStyle.strokePercent ?? -1, 0.0, accuracy: 1e-9, "baseline at t=0")
        _ = clip.step(1000, 1000)
        XCTAssertEqual(line.pathStyle.strokePercent ?? -1, 0.5, accuracy: 1e-6, "50% of linear 0→1")
        _ = clip.step(2000, 1000)
        XCTAssertEqual(line.pathStyle.strokePercent ?? -1, 1.0, accuracy: 1e-9, "end → 1")
    }

    // curves: `shape.animate('shape').when(time, { r: [...] })` (Rose radii array track)
    func test_shape_field_animates_through_animate_key() throws {
        let rose = Rose()
        var s = RoseShape()
        s.cx = 0; s.cy = 0; s.r = [10]; s.k = 1; s.n = 1
        rose.setShape(s)

        let anim = rose.animate("shape").when(1000, ["r": [110.0]])
        _ = anim.start(.named("linear"))

        XCTAssertEqual(rose.animators.count, 1, "expected one shape animator from animate('shape')")
        guard let clip = rose.animators.first?.getClip() else {
            return XCTFail("no clip — shape track was inert (animate('shape') not routed to the accessor)")
        }

        _ = clip.step(0, 0)
        XCTAssertEqual((rose.shape as? RoseShape)?.r.first ?? -1, 10.0, accuracy: 1e-9, "baseline at t=0")
        _ = clip.step(500, 500)
        XCTAssertEqual((rose.shape as? RoseShape)?.r.first ?? -1, 60.0, accuracy: 1e-6, "50% of 10→110")
        _ = clip.step(1000, 500)
        XCTAssertEqual((rose.shape as? RoseShape)?.r.first ?? -1, 110.0, accuracy: 1e-9, "end → 110")
    }
}
