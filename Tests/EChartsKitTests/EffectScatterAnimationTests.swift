// Proves the effectScatter ripple builds real LOOPING animators (faithful to
// chart/helper/EffectSymbol.ts) instead of the old static concentric rings, and that stepping
// their clips interpolates scaleX (0.5 → rippleScale/2) and opacity (→ 0). Headless: no zr tick,
// clips are stepped directly at synthetic times — the AnimationSmokeTests / ShapeAnimationWiringTests
// pattern.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class EffectScatterAnimationTests: XCTestCase {

    /// A single-point effectScatter so ring 0's delay is exactly 0 (effectOffset = idx/count = 0),
    /// letting the clip step cleanly from t=0.
    private func makeView() -> EChartsView {
        let option: [String: Any] = [
            "xAxis": ["type": "value"],
            "yAxis": ["type": "value"],
            "series": [[
                "type": "effectScatter",
                "symbolSize": 20,
                "rippleEffect": ["scale": 2.5, "number": 3, "period": 4, "brushType": "fill"],
                "data": [[1.0, 1.0]]
            ]]
        ]
        let view = EChartsView(width: 400, height: 300)
        view.setOption(option)
        return view
    }

    /// Depth-first find the first ripple symbol path (named "ripple") in the ec render tree.
    private func findRipple(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "ripple" { return p }
        if let g = el as? Group {
            for c in g.children() { if let hit = findRipple(c) { return hit } }
        }
        return nil
    }

    func test_ripple_has_looping_scale_and_opacity_animators() throws {
        let view = makeView()
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found (expected name == \"ripple\")")
        }

        // Two animators: transform (scaleX/scaleY) + style (opacity).
        XCTAssertEqual(ripple.animators.count, 2, "expected transform + style ripple animators")

        let transform = ripple.animators.first { ($0.targetName ?? "") == "" }
        let style = ripple.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(transform, "missing transform (scale) animator")
        XCTAssertNotNil(style, "missing style (opacity) animator")

        // Baseline: ripple starts at scaleX 0.5.
        XCTAssertEqual(ripple.scaleX, 0.5, accuracy: 1e-9, "ripple should start at scaleX 0.5")

        // Step the transform clip to 50% of a 4000ms period → halfway from 0.5 to rippleScale/2 (1.25).
        guard let tClip = transform?.getClip() else { return XCTFail("no transform clip") }
        _ = tClip.step(0, 0)
        _ = tClip.step(2000, 2000)
        XCTAssertEqual(ripple.scaleX, (0.5 + 1.25) / 2, accuracy: 1e-3, "scaleX should tween 0.5 → 1.25")

        // Step the style clip to 100% → opacity 0.
        guard let sClip = style?.getClip() else { return XCTFail("no style clip") }
        _ = sClip.step(0, 0)
        _ = sClip.step(4000, 4000)
        XCTAssertEqual(ripple.pathStyle.opacity ?? -1, 0.0, accuracy: 1e-3, "opacity should tween to 0")
    }

    /// Faithful port of EffectSymbol.startEffectAnimation's `ripplePath.attr({ style: { strokeNoScale:
    ///   true }, silent: true, ... })` — the ripple must be non-interactive (so hover/click reaches the
    ///   base symbol, not the z2:99 ring) and must not thicken its stroke as it scales up.
    func test_ripple_is_silent_and_has_strokeNoScale() throws {
        let view = makeView()
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found (expected name == \"ripple\")")
        }
        XCTAssertTrue(ripple.silent, "ripple path must be silent so it doesn't intercept hover/hit-testing")
        XCTAssertEqual(ripple.pathStyle.strokeNoScale, true, "ripple style must set strokeNoScale to keep lineWidth constant under scale")
    }

    /// Same assertions for the `brushType: "stroke"` ripple variant.
    func test_stroke_ripple_is_silent_and_has_strokeNoScale() throws {
        let option: [String: Any] = [
            "xAxis": ["type": "value"],
            "yAxis": ["type": "value"],
            "series": [[
                "type": "effectScatter",
                "symbolSize": 20,
                "rippleEffect": ["scale": 2.5, "number": 3, "period": 4, "brushType": "stroke"],
                "data": [[1.0, 1.0]]
            ]]
        ]
        let view = EChartsView(width: 400, height: 300)
        view.setOption(option)
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found (expected name == \"ripple\")")
        }
        XCTAssertTrue(ripple.silent, "stroke ripple path must be silent")
        XCTAssertEqual(ripple.pathStyle.strokeNoScale, true, "stroke ripple style must set strokeNoScale")
    }
}
