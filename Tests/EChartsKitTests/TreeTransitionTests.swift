// Entering tree node symbols scale in when the series has animation on, and are at full scale with no
// animator when off. L2 UPDATE: the tree node symbols now go through the shared SymbolDraw/Symbol, whose
// `_createSymbol` builds the symbol Path at a fixed 2×2 size and scales it by `symbolSize/2`, so the item
// Path's resting scaleX is `symbolSize/2` (NOT 1) and the entrance animates scaleX 0 → symbolSize/2. The
// option below uses symbolSize 10, so the final/resting scaleX is 5. The node symbol Path is named "item"
// (Symbol._createSymbol); the edge BezierCurve/TreePath is left un-animated.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class TreeTransitionTests: XCTestCase {

    // First node symbol = the "item"-named Path (skips edges, which are BezierCurve/TreePath, unnamed).
    private func firstSymbol(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "item" { return p }
        if let g = el as? Group { for c in g.children() { if let hit = firstSymbol(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [[
                "type": "tree",
                "layout": "orthogonal",
                "symbolSize": 10,
                "data": [[
                    "name": "root",
                    "children": [
                        ["name": "A", "children": [
                            ["name": "A1"] as [String: Any],
                            ["name": "A2"] as [String: Any]
                        ]] as [String: Any],
                        ["name": "B", "children": [
                            ["name": "B1"] as [String: Any]
                        ]] as [String: Any]
                    ]
                ] as [String: Any]]
            ] as [String: Any]]
        ]
    }

    func test_node_scales_in_when_animation_on() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(true))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no tree node symbol") }
        XCTAssertGreaterThan(sym.animators.count, 0, "node should have a scale-in animator when animation on")
        // initProps' `enter` config sets setToFinal:true (basicTransition.swift), so the live property reads
        // its FINAL value synchronously; the animator's own keyframe track carries the 0→1 scale-in.
        let animator = sym.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(animator, "an animator should carry a scaleX track (the 0→size/2 scale-in)")
        XCTAssertEqual(sym.scaleX, 5.0, accuracy: 1e-9, "setToFinal jumps the live property to its final value (symbolSize/2)")
        // Prove the track carries a genuine 0→size/2 delta (not a no-op): step to t=0 then t=1.
        if let track = animator?.getTrack("scaleX") {
            track.step(sym, 0.0)
            XCTAssertEqual(sym.scaleX, 0.0, accuracy: 1e-9, "scaleX track starts at 0 (real scale-in delta)")
            track.step(sym, 1.0)
            XCTAssertEqual(sym.scaleX, 5.0, accuracy: 1e-9, "scaleX track ends at symbolSize/2")
        }
    }

    func test_node_full_scale_when_animation_off() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(false))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no tree node symbol") }
        XCTAssertEqual(sym.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(sym.scaleX, 5.0, accuracy: 1e-9, "node at full scale (symbolSize/2) immediately when animation off")
    }
}
