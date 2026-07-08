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

    /// Depth-first collect EVERY ripple symbol path (named "ripple") in the ec render tree — one
    /// effectScatter series with `number: k` builds `k` sibling ripple rings per data point.
    private func findAllRipples(_ el: Element, into acc: inout [Path]) {
        if let p = el as? Path, p.name == "ripple" { acc.append(p) }
        if let g = el as? Group {
            for c in g.children() { findAllRipples(c, into: &acc) }
        }
    }

    /// The base symbol is now routed through the shared `SymbolDraw` with the ported `EffectSymbol`
    /// ctor: each datum becomes an `EffectSymbol` (a `Symbol` group) whose childAt(0) is the base symbol
    /// Path (name "item", resting scaleX == symbolSize/2, since Symbol scales a 2x2 shape) and whose
    /// childAt(1) is the ripple Group holding the `number` sibling rings.
    func test_base_symbol_routed_through_effect_symbol() throws {
        let view = makeView()   // symbolSize: 20 → resting scaleX == 10

        // Find the EffectSymbol group (the only Symbol subclass in the tree).
        var effectSymbol: EffectSymbol?
        func find(_ el: Element) {
            if let es = el as? EffectSymbol { effectSymbol = es; return }
            if let g = el as? Group { for c in g.children() { find(c); if effectSymbol != nil { return } } }
        }
        find(view.ec.getRoot())
        guard let es = effectSymbol else { return XCTFail("no EffectSymbol group found") }

        // childAt(0): the base symbol Path named "item" at resting scale symbolSize/2.
        guard let base = es.childAt(0) as? Path else { return XCTFail("EffectSymbol childAt(0) is not a Path") }
        XCTAssertEqual(base.name, "item", "base symbol path should be named \"item\"")
        XCTAssertEqual(base.scaleX, 10.0, accuracy: 1e-9, "base symbol resting scaleX == symbolSize/2")
        XCTAssertEqual(base.scaleY, 10.0, accuracy: 1e-9, "base symbol resting scaleY == symbolSize/2")

        // childAt(1): the ripple Group with `number: 3` sibling ripple rings scaled to symbolSize.
        guard let rippleGroup = es.childAt(1) as? Group else { return XCTFail("EffectSymbol childAt(1) is not a Group") }
        XCTAssertEqual(rippleGroup.children().count, 3, "ripple group should hold `rippleEffect.number` rings")
        XCTAssertEqual(rippleGroup.scaleX, 20.0, accuracy: 1e-9, "ripple group scaled to symbolSize width")
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

    /// Characterization guard: `EChartsView._syncRoot` (`zr.add(ec.getRoot())`) must reach every
    /// descendant of the render tree, including the ripple symbol nested under the effectScatter
    /// series group — `Group.addSelfToZr` (Group.swift:269) recurses into children, and `Element
    /// .addSelfToZr` (Element.swift:1289) is what registers each animator with `zr.animation`
    /// (ZRender.swift:209 `ZRender.add` → `addSelfToZr`). This is the prerequisite the host frame
    /// loop (CADisplayLink → zr.animation.update) depends on to actually tick the ripple clips.
    func test_ripple_animators_register_with_zr_animation_on_sync() throws {
        let view = makeView()               // setOption already ran _syncRoot()
        guard let ripple = findRipple(view.ec.getRoot()) else {
            return XCTFail("no ripple symbol path found")
        }
        // _syncRoot added ec.getRoot() to view.zr; Group.addSelfToZr recurses to every child,
        // so each ripple path's __zr must now be the live zr — which is what registered its
        // animators with zr.animation (the prerequisite for the host frame loop to tick them).
        XCTAssertTrue(ripple.__zr === view.zr,
                      "ripple path was not added to the live zr — animators never registered")
        XCTAssertEqual(ripple.animators.count, 2, "ripple should still carry both animators")
    }

    /// Proves the premise behind EChartsDemoGallery's `advanceAnimationsForStaticFrame`: the headless
    /// render never ticks the animation loop, so without advancing, every ripple ring in a series
    /// freezes at its t=0 initial state (scaleX 0.5) — a single opaque disc, not the staggered
    /// expanding rings echarts paints on first frame. Stepping each ring's transform clip to a common
    /// wall-clock time realizes the per-ring NEGATIVE delay stagger (`-k/number*period`), producing
    /// DISTINCT scaleX values across the `number: 3` rings.
    func test_advancing_ripple_clips_to_common_time_staggers_scaleX() throws {
        let view = makeView()   // number: 3, period: 4 (seconds → 4000ms)
        var ripples: [Path] = []
        findAllRipples(view.ec.getRoot(), into: &ripples)
        XCTAssertEqual(ripples.count, 3, "expected one ripple ring per `rippleEffect.number`")

        // Before advancing: every ring is frozen at its t=0 baseline — all scaleX 0.5 (one distinct
        // value). This is the frozen-disc regression the static render path must avoid.
        let baselineScaleX = Set(ripples.map { $0.scaleX })
        XCTAssertEqual(baselineScaleX, [0.5], "unadvanced rings should all sit at the t=0 baseline scaleX")

        // Advance every ring's transform clip to the same representative wall-clock time (mirrors
        // EChartsDemoGallery's advanceAnimationsForStaticFrame: step(0,0) to apply the delay offset,
        // then step(timeMs,timeMs) to reach the representative frame).
        let timeMs = 1000.0
        for ripple in ripples {
            let transform = ripple.animators.first { ($0.targetName ?? "") == "" }
            guard let clip = transform?.getClip() else {
                return XCTFail("ripple missing transform (scale) animator/clip")
            }
            _ = clip.step(0, 0)
            _ = clip.step(timeMs, timeMs)
        }

        let advancedScaleX = ripples.map { $0.scaleX }
        XCTAssertGreaterThan(Set(advancedScaleX).count, 1,
                              "advanced rings should have DISTINCT scaleX (staggered expansion), not one disc: \(advancedScaleX)")
    }
}
