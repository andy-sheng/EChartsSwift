import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression for the demo-gallery SIGTRAP: hovering a chord RIBBON crashed in
// createEmphasisDefaultState → liftZRColor → color.liftColor (force-unwrap of a failed parse).
// The ribbon's rendered STROKE legitimately carries the lineStyle sentinel "source" (upstream
// leaves it unresolved too — only fill is resolved by applyEdgeFill), so the default-emphasis
// stroke lift must tolerate an unparseable color instead of trapping.
final class ChordRibbonHoverCrashTests: XCTestCase {
    func testHoverChordRibbonDoesNotCrash() {
        let v = EChartsView(width: 460, height: 380)
        v.setOption([
            "series": [["type": "chord",
                        "data": [["name": "a"] as [String: Any], ["name": "b"] as [String: Any],
                                 ["name": "c"] as [String: Any]],
                        "links": [["source": "a", "target": "b", "value": 5.0] as [String: Any],
                                  ["source": "b", "target": "c", "value": 3.0] as [String: Any]]]
                        as [String: Any]]
        ])
        _ = v.zr.storage.getDisplayList(true)
        let series = v.ec.getModel()!.getSeriesByIndex(0)! as! ChordSeriesModel
        guard let ribbon = series.getEdgeData().getItemGraphicEl(0) as? Path else {
            XCTFail("chord must render edge ribbons"); return
        }

        // Hover a point INSIDE the ribbon: sample its bounding rect for a contained point (ribbon
        // geometry is a curved band; scan a coarse grid through the real hit-test).
        guard let rect = ribbon.getBoundingRect() else {
            XCTFail("ribbon has a bounding rect"); return
        }
        var hit: (Double, Double)? = nil
        outer: for iy in 1..<10 {
            for ix in 1..<10 {
                let lx = rect.x + rect.width * Double(ix) / 10
                let ly = rect.y + rect.height * Double(iy) / 10
                let g = ribbon.transformCoordToGlobal(lx, ly)
                if ribbon.contain(g[0], g[1]) { hit = (g[0], g[1]); break outer }
            }
        }
        guard let (px, py) = hit else {
            XCTFail("could not find a point inside the ribbon"); return
        }

        // Before the fix this line SIGTRAPped (Unexpectedly found nil in liftColor).
        v._injectPointerForTest(type: "mousemove", zrX: px, zrY: py)

        XCTAssertTrue(ribbon.currentStates.contains("emphasis"),
                      "hovering the ribbon enters emphasis without crashing")
        v._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(ribbon.currentStates.contains("emphasis"), "mouseout restores")
    }
}
