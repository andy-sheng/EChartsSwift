// Phase 36 regression test — the visual axisPointer CROSSHAIR (a vertical Line) actually APPEARS on
// hover at the hovered category's x-pixel, proven HEADLESSLY through the REAL pointer → globalListener →
// axisTrigger → axisPointer-model status/value → CartesianAxisPointer.render chain.
//
//     EChartsView._injectPointerForTest("mousemove", x, y)
//       -> zr.handler.mousemove(ZRRawEvent)                 (ZRenderKit Handler)
//       -> globalListener's mousemove listener (EChartsView._bindAxisPointerListeners)
//       -> axisTrigger(...)  -> updateModelActually writes axisPointerModel.status="show"/value
//       -> EChartsView._updateAxisPointers(ecModel)
//       -> CartesianAxisPointer.render(...) builds a Line crosshair Group on the LIVE zr
//
// It does NOT call render directly — the crosshair MUST be produced by the injected pointer travelling
// through the live Handler and the axisTrigger data core. A mousemove far off the grid then proves the
// crosshair is HIDDEN (status="hide" → group.hide()).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZAxisCrosshairTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    private func makeAxisBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": ["trigger": "axis"] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    // Every VISIBLE Line currently in view.zr (getDisplayList excludes elements under a hidden/ignored
    // group), i.e. the flattened display list — the crosshair Line is a leaf of the pointer Group that
    // BaseAxisPointer adds to the live zr.
    private func visibleLines(in view: EChartsView) -> [Line] {
        var out: [Line] = []
        for el in view.zr.storage.getDisplayList(true) {
            if let l = el as? Line, !l.ignore { out.append(l) }
        }
        return out
    }

    // A vertical crosshair Line at x ≈ bx spanning the grid's y-range (top 20 .. bottom 220).
    private func crosshairLine(in view: EChartsView, atX bx: Double) -> Line? {
        return visibleLines(in: view).first { l in
            guard let s = l.shape as? LineShape else { return false }
            let vertical = abs(s.x1 - s.x2) < 0.6           // x1 ≈ x2 → vertical
            let atBx = abs(s.x1 - bx) <= 1.0                // at the hovered category's x-pixel
            let yLo = Swift.min(s.y1, s.y2)
            let yHi = Swift.max(s.y1, s.y2)
            let spansGrid = yLo <= 30.0 && yHi >= 210.0     // spans the grid (top 20, bottom 220)
            return vertical && atBx && spansGrid
        }
    }

    func testAxisHoverShowsCrosshairLine() {
        let view = makeAxisBarView()

        // Grab bar 1's ("B") rendered Rect to compute its center x.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bar1El = data.getItemGraphicEl(1), let bar1 = bar1El as? Rect else {
            XCTFail("bar render must have populated a Rect element for data index 1 ('B')"); return
        }
        let s = bar1.shape as! RectShape
        let bx = s.x + s.width / 2       // x-pixel of category "B"
        let gy: Double = 120.0           // any y inside the grid (top 20, height 200)

        // Force the zr storage to flatten the echarts display list so `findHover`/containPoint work.
        _ = view.zr.storage.getDisplayList(true)

        // Precondition: no crosshair before any hover.
        XCTAssertNil(crosshairLine(in: view, atX: bx),
                     "no crosshair Line should exist before any hover")

        // ---- (1) Inject a mousemove at category "B" → the vertical crosshair Line must APPEAR. ----
        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)

        guard let line = crosshairLine(in: view, atX: bx) else {
            let lines = visibleLines(in: view).compactMap { ($0.shape as? LineShape).map {
                "(\($0.x1),\($0.y1))->(\($0.x2),\($0.y2))" } }
            XCTFail("hovering category B must draw a vertical crosshair Line at x≈\(bx); "
                    + "visible lines: \(lines)"); return
        }
        let ls = line.shape as! LineShape
        XCTAssertEqual(ls.x1, bx, accuracy: 1.0, "crosshair x1 must sit at category B's x-pixel")
        XCTAssertEqual(ls.x2, bx, accuracy: 1.0, "crosshair x2 must sit at category B's x-pixel")
        XCTAssertEqual(abs(ls.x1 - ls.x2), 0.0, accuracy: 0.6, "the crosshair must be vertical (x1≈x2)")

        // ---- (2) Inject a mousemove far OFF the grid → the crosshair must HIDE. ----
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        XCTAssertNil(crosshairLine(in: view, atX: bx),
                     "moving the pointer off the grid must hide the crosshair Line (status='hide')")
    }
}
