// Entering tree node symbols scale in (scaleX/scaleY 0→1) when the series has animation on, and are at
// full scale with no animator when off. Faithful to chart/helper/Symbol.ts first-create scale-in
// (same idiom as ScatterTransitionTests). The node symbol Path is named "item" (see TreeView.updateNode);
// the edge BezierCurve/TreePath is left un-animated.
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
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no tree node symbol") }
        XCTAssertGreaterThan(sym.animators.count, 0, "node should have a scale-in animator when animation on")
        // initProps' `enter` config sets setToFinal:true (basicTransition.swift), so the live property reads
        // its FINAL value synchronously; the animator's own keyframe track carries the 0→1 scale-in.
        let animator = sym.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(animator, "an animator should carry a scaleX track (the 0→1 scale-in)")
        XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "setToFinal jumps the live property to its final value")
        // Prove the track carries a genuine 0→1 delta (not a no-op): step to t=0 then t=1.
        if let track = animator?.getTrack("scaleX") {
            track.step(sym, 0.0)
            XCTAssertEqual(sym.scaleX, 0.0, accuracy: 1e-9, "scaleX track starts at 0 (real scale-in delta)")
            track.step(sym, 1.0)
            XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "scaleX track ends at 1")
        }
    }

    func test_node_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no tree node symbol") }
        XCTAssertEqual(sym.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "node at full scale immediately when animation off")
    }
}
