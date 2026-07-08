// L3 Roam — SANKEY pan/zoom end-to-end. Builds a `roam:true` sankey through EChartsView, injects a real
// drag / wheel through the live Handler, and asserts the sankey's VIEW GROUP actually SHIFTS (pan) and
// SCALES (zoom). Sankey is not on a coord system, so the roam is a transform on the main group — see
// roamHelperViewGroup.swift. (Upstream sankey supports roam via a View coord sys; the port applies the
// group transform, mirroring tree/treemap.)
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZSankeyRoamTests: XCTestCase {

    private func makeSankeyView(roam: Any? = true) -> EChartsView {
        let view = EChartsView(width: 460, height: 360)
        var series: [String: Any] = [
            "type": "sankey", "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
            "nodeWidth": 20.0, "nodeGap": 8.0,
            "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
            "links": [["source": "a", "target": "b", "value": 5.0],
                      ["source": "a", "target": "c", "value": 3.0],
                      ["source": "b", "target": "d", "value": 4.0],
                      ["source": "c", "target": "d", "value": 2.0]]
        ]
        if let roam = roam { series["roam"] = roam }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func sankeySeries(_ view: EChartsView) -> SankeySeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? SankeySeriesModel
    }

    private func sankeyGroup(_ view: EChartsView) -> Group? {
        guard let sm = sankeySeries(view),
              let v = view.ec.api.getViewOfSeriesModel(sm) as? SankeyView else { return nil }
        return v._mainGroupForTest
    }

    func testDragPansGroup() {
        let view = makeSankeyView()
        guard let g = sankeyGroup(view) else { return XCTFail("sankey view group must exist after render") }
        let beforeX = g.x, beforeY = g.y, beforeScale = g.scaleX

        let cx = 230.0, cy = 180.0
        let dx = 30.0, dy = 45.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)

        guard let after = sankeyGroup(view) else { return XCTFail("sankey view group must still exist after pan") }
        print("SANKEY-ROAM pan: group (\(beforeX),\(beforeY)) -> (\(after.x),\(after.y))")
        XCTAssertEqual(after.x - beforeX, dx, accuracy: 0.5, "group must shift by dx")
        XCTAssertEqual(after.y - beforeY, dy, accuracy: 0.5, "group must shift by dy")
        XCTAssertEqual(after.scaleX, beforeScale, accuracy: 1e-6, "a pure pan must not scale")
    }

    func testWheelZoomsGroup() {
        let view = makeSankeyView()
        guard let g = sankeyGroup(view) else { return XCTFail("sankey view group must exist after render") }
        XCTAssertEqual(g.scaleX, 1, accuracy: 1e-6, "the untouched sankey group must be unscaled")

        view._injectWheelForTest(zrDelta: 3, zrX: 230, zrY: 180)

        guard let after = sankeyGroup(view) else { return XCTFail("sankey view group must still exist after zoom") }
        print("SANKEY-ROAM zoom: scale -> \(after.scaleX)")
        XCTAssertEqual(after.scaleX, 1.2, accuracy: 0.02, "wheel-in scales the group by ~1.2x")
        XCTAssertEqual(after.scaleY, 1.2, accuracy: 0.02, "scaleY must match scaleX (uniform zoom)")
    }

    func testNoRoamOptionIsInert() {
        let view = makeSankeyView(roam: nil)   // sankey default roam:false.
        guard let g = sankeyGroup(view) else { return XCTFail("sankey view group must exist after render") }
        let beforeX = g.x, beforeY = g.y
        view._injectPointerForTest(type: "mousedown", zrX: 230, zrY: 180)
        view._injectPointerForTest(type: "mousemove", zrX: 280, zrY: 230)
        view._injectPointerForTest(type: "mouseup", zrX: 280, zrY: 230)
        guard let after = sankeyGroup(view) else { return XCTFail("sankey view group must still exist") }
        XCTAssertEqual(after.x, beforeX, accuracy: 1e-6, "roam:off sankey must not pan (x)")
        XCTAssertEqual(after.y, beforeY, accuracy: 1e-6, "roam:off sankey must not pan (y)")
    }
}
