// Proves the lines-series flying-trail effect (chart/lines/EffectLine.swift, faithful to
// chart/helper/EffectLine.ts + EffectPolyline.ts) builds a moving `createSymbol` symbol with a real
// LOOPING animator when `effect.show` is true — and that with the effect OFF the render is unchanged
// (no effect symbol). Headless: no zr tick, so the clip is stepped directly at synthetic times, the
// EffectScatterAnimationTests / AnimationSmokeTests pattern.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class EffectLineAnimationTests: XCTestCase {

    private func makeView(effect: Bool, polyline: Bool = false) -> EChartsView {
        var series: [String: Any] = [
            "type": "lines",
            "coordinateSystem": "cartesian2d",
            "polyline": polyline,
            "lineStyle": ["width": 2.0, "opacity": 1.0] as [String: Any],
            "data": polyline
                ? [["coords": [[2.0, 2.0], [8.0, 12.0], [14.0, 6.0]]] as [String: Any]]
                : [["coords": [[2.0, 2.0], [8.0, 12.0]]] as [String: Any]]
        ]
        if effect {
            series["effect"] = [
                "show": true, "period": 4.0, "symbol": "circle", "symbolSize": 8.0, "color": "#ff0000"
            ] as [String: Any]
        }
        let option: [String: Any] = [
            "xAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [series]
        ]
        let view = EChartsView(width: 400, height: 300)
        view.setOption(option)
        return view
    }

    /// Depth-first find the first effect trail symbol (named "effectSymbol") in the ec render tree.
    private func findEffectSymbol(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "effectSymbol" { return p }
        if let g = el as? Group {
            for c in g.children() { if let hit = findEffectSymbol(c) { return hit } }
        }
        return nil
    }

    func test_effect_symbol_and_animator_created_when_show_true() throws {
        let view = makeView(effect: true)
        guard let sym = findEffectSymbol(view.ec.getRoot()) else {
            return XCTFail("no effect trail symbol found (expected name == \"effectSymbol\")")
        }
        // One looping transform animator drives the position along the line.
        XCTAssertGreaterThanOrEqual(sym.animators.count, 1, "expected a trail-position animator")
        // The symbol is scaled to symbolSize (8) not the unit 1x1 it's built at.
        XCTAssertEqual(sym.scaleX, 8.0, accuracy: 1e-9, "effect symbol should scale to symbolSize")
        XCTAssertEqual(sym.scaleY, 8.0, accuracy: 1e-9, "effect symbol should scale to symbolSize")
    }

    func test_no_effect_symbol_when_show_false() throws {
        let view = makeView(effect: false)
        XCTAssertNil(findEffectSymbol(view.ec.getRoot()),
                     "effect OFF must render no trail symbol (unchanged from the static line)")
    }

    /// The animator must register with the live zr on _syncRoot — the prerequisite for the host frame
    /// loop (and the headless advanceAnimationsForStaticFrame) to actually tick the trail.
    func test_effect_animator_registers_with_zr_on_sync() throws {
        let view = makeView(effect: true)
        guard let sym = findEffectSymbol(view.ec.getRoot()) else {
            return XCTFail("no effect trail symbol found")
        }
        XCTAssertTrue(sym.__zr === view.zr, "effect symbol was not added to the live zr — animator never registered")
    }

    /// Stepping the trail animator's clip to different wall-clock times moves the symbol ALONG the line
    /// (distinct positions), proving it is a real moving trail and not a frozen dot — the same premise
    /// as advanceAnimationsForStaticFrame for the static PNG oracle.
    func test_advancing_clip_moves_symbol_along_the_line() throws {
        let view = makeView(effect: true)
        guard let sym = findEffectSymbol(view.ec.getRoot()) else {
            return XCTFail("no effect trail symbol found")
        }
        guard let clip = sym.animators.first?.getClip() else {
            return XCTFail("effect symbol missing animator clip")
        }
        // period 4s → 4000ms. t=0 baseline is the line start (2,2 in data space → pixel start).
        _ = clip.step(0, 0)
        let startPos = (sym.x, sym.y)
        // Advance a quarter period → the symbol should have moved partway toward the end point.
        _ = clip.step(1000, 1000)
        let midPos = (sym.x, sym.y)
        XCTAssertTrue(startPos.0 != midPos.0 || startPos.1 != midPos.1,
                      "advancing the clip should move the trail symbol along the line: \(startPos) vs \(midPos)")
    }

    /// Polyline lines drive the EffectPolyline arc-length walk; it must still build a moving symbol.
    func test_polyline_effect_symbol_created_and_moves() throws {
        let view = makeView(effect: true, polyline: true)
        guard let sym = findEffectSymbol(view.ec.getRoot()) else {
            return XCTFail("no effect trail symbol found for polyline lines")
        }
        guard let clip = sym.animators.first?.getClip() else {
            return XCTFail("polyline effect symbol missing animator clip")
        }
        _ = clip.step(0, 0)
        let a = (sym.x, sym.y)
        _ = clip.step(2000, 2000)
        let b = (sym.x, sym.y)
        XCTAssertTrue(a.0 != b.0 || a.1 != b.1, "polyline trail symbol should move along the polyline")
    }
}
