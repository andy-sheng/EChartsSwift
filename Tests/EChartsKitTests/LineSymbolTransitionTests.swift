// Entering line data-point symbols scale in when the series has animation on, and are at full scale
// with no scale-in animator when off. Faithful to upstream LineView._initSymbolLabelAnimation
// (LineView.ts:1078): SymbolDraw.updateData is called with `disableAnimation: true` (the symbol PATH
// gets no scale-in of its own), and the entrance is driven by animating the Symbol GROUP's
// scaleX/scaleY 0→1 with a per-position DELAY (so symbols pop in left-to-right with the clip sweep).
// The symbol path rests at scaleX == symbolSize/2 (20 → 10); the group rests at scaleX == 1.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LineSymbolTransitionTests: XCTestCase {

    // The symbol PATH (name "item"), whose resting scaleX is symbolSize/2.
    private func firstSymbolPath(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "item" { return p }
        if let g = el as? Group { for c in g.children() { if let hit = firstSymbolPath(c) { return hit } } }
        return nil
    }

    // The Symbol GROUP (a `Symbol` wrapping the "item" path) — the element _initSymbolLabelAnimation scales.
    private func firstSymbolGroup(_ el: Element) -> Symbol? {
        if let s = el as? Symbol { return s }
        if let g = el as? Group { for c in g.children() { if let hit = firstSymbolGroup(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "xAxis": ["type": "category", "data": ["A", "B", "C"]],
            "yAxis": ["type": "value"],
            "series": [["type": "line", "symbolSize": 20, "data": [10.0, 20.0, 30.0]]]
        ]
    }

    func test_symbol_scales_in_when_animation_on() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(true))
        guard let group = firstSymbolGroup(ec.getRoot()) else { return XCTFail("no line symbol group") }
        // The GROUP carries the scale-in animator (0→1); the path itself is not animated (disableAnimation).
        XCTAssertGreaterThan(group.animators.count, 0, "symbol group should have a scale-in animator when animation on")
        let animator = group.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(animator, "an animator should carry a scaleX track (the 0→1 group scale-in)")
        XCTAssertEqual(group.scaleX ?? -1, 1.0, accuracy: 1e-9, "setToFinal jumps the group scaleX to its final value (1)")
        // Prove the track carries a genuine 0→1 delta (not a no-op): step to t=0 restores the start.
        if let track = animator?.getTrack("scaleX") {
            track.step(group, 0.0)
            XCTAssertEqual(group.scaleX ?? -1, 0.0, accuracy: 1e-9, "scaleX track starts at 0 (real scale-in delta)")
            track.step(group, 1.0)
            XCTAssertEqual(group.scaleX ?? -1, 1.0, accuracy: 1e-9, "scaleX track ends at 1")
        }
        // The symbol path still rests at symbolSize/2 = 10 (its size is not animated).
        if let path = firstSymbolPath(ec.getRoot()) {
            XCTAssertEqual(path.scaleX ?? -1, 10.0, accuracy: 1e-9, "symbol path at symbolSize/2")
        }
    }

    func test_symbol_full_scale_when_animation_off() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(false))
        guard let group = firstSymbolGroup(ec.getRoot()) else { return XCTFail("no line symbol group") }
        XCTAssertEqual(group.animators.count, 0, "no scale-in animator when animation off")
        XCTAssertEqual(group.scaleX ?? -1, 1.0, accuracy: 1e-9, "group at full scale (1) when animation off")
        // Path rests at symbolSize/2 = 10.
        guard let path = firstSymbolPath(ec.getRoot()) else { return XCTFail("no line symbol path") }
        XCTAssertEqual(path.scaleX ?? -1, 10.0, accuracy: 1e-9, "symbol path at full scale (symbolSize/2) when animation off")
    }
}
