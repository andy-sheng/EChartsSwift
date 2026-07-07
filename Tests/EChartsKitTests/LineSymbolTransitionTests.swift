// Entering line data-point symbols scale in (scaleX/scaleY 0→1) when the series has animation on, and
// are at full scale with no animator when off. Faithful to chart/helper/Symbol.ts first-create scale-in
// (LineView's inlined SymbolDraw pass). Mirrors ScatterTransitionTests; the line symbol is named "symbol".
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LineSymbolTransitionTests: XCTestCase {

    private func firstSymbol(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "symbol" { return p }
        if let g = el as? Group { for c in g.children() { if let hit = firstSymbol(c) { return hit } } }
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
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(true))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no line symbol") }
        XCTAssertGreaterThan(sym.animators.count, 0, "symbol should have a scale-in animator when animation on")
        let animator = sym.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(animator, "an animator should carry a scaleX track (the 0→1 scale-in)")
        XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "setToFinal jumps the live property to its final value immediately")
        // Prove the track carries a genuine 0→1 delta (not a no-op): step to t=0 restores the start.
        if let track = animator?.getTrack("scaleX") {
            track.step(sym, 0.0)
            XCTAssertEqual(sym.scaleX, 0.0, accuracy: 1e-9, "scaleX track starts at 0 (real scale-in delta)")
            track.step(sym, 1.0)
            XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "scaleX track ends at 1")
        }
    }

    func test_symbol_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(false))
        guard let sym = firstSymbol(ec.getRoot()) else { return XCTFail("no line symbol") }
        XCTAssertEqual(sym.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(sym.scaleX, 1.0, accuracy: 1e-9, "symbol at full scale immediately when animation off")
    }
}
