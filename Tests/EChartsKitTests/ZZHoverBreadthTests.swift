// Phase 34 regression test — LIVE hover→emphasis breadth across SCATTER, PIE, and LINE.
//
// Modeled on ZZLiveHoverTests (bar): each test builds an EChartsView, grabs a per-datum element from
// the series data (`data.getItemGraphicEl(idx)`), injects a synthetic POINTER over it via
// `_injectPointerForTest`, and asserts the element enters the "emphasis" state through the REAL
// Handler hit-test + the EChartsView "mouseover" listener → states.enterEmphasisWhenMouseOver. A
// second mousemove off the element proves the "mouseout" leg clears emphasis.
//
// This proves the Phase-34 change: ScatterView / LineView / PieView now mark each per-datum element a
// highDown dispatcher (mirroring BarView), so hover-to-highlight (and thus item-tooltip) works for
// them, not just bars.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZHoverBreadthTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(ScatterSeriesModel.self)
        ComponentModel.registerClass(PieSeriesModel.self)
        ComponentModel.registerClass(LineSeriesModel.self)
    }

    // Center of a symbol/path element: its bounding rect center. Symbols carry no transform (position is
    // baked into the shape's absolute coords), so the local bounding rect is already grid-global.
    private func boundingCenter(_ el: Element) -> (Double, Double)? {
        guard let r = el.getBoundingRect() else { return nil }
        let cx = r.x + r.width / 2
        let cy = r.y + r.height / 2
        // Apply the element's computed transform → global (zr) coords. Bars/sectors bake position into
        //   their shape (local == global), but a scatter Symbol is a Group positioned via its transform
        //   (setPosition → group.x/y) with a local symbol-path rect, so the bare local center would miss.
        if let m = el.getComputedTransform() {
            return (m[0] * cx + m[2] * cy + m[4], m[1] * cx + m[3] * cy + m[5])
        }
        return (cx, cy)
    }

    // MARK: - Scatter

    func testScatterPointHoverEntersEmphasis() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 20.0,
                        "data": [[10.0, 10.0], [20.0, 20.0], [30.0, 30.0]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("scatter render must populate a symbol element for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "ScatterView must mark each symbol a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "scatter point 0 must not be in emphasis before any hover")

        guard let (cx, cy) = boundingCenter(el) else { XCTFail("no bounding rect"); return }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over scatter point 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off scatter point 0 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Pie

    func testPieSectorHoverEntersEmphasis() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "series": [["type": "pie", "radius": ["0%", "60%"],
                        "data": [
                            ["value": 40.0, "name": "A"] as [String: Any],
                            ["value": 30.0, "name": "B"] as [String: Any],
                            ["value": 20.0, "name": "C"] as [String: Any],
                            ["value": 10.0, "name": "D"] as [String: Any]
                        ]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0), let sector = el as? Sector else {
            XCTFail("pie render must populate a Sector element for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(sector),
                      "PieView must mark each sector a highDown dispatcher")
        XCTAssertTrue(sector.currentStates.isEmpty, "pie sector 0 must not be in emphasis before any hover")

        // A guaranteed-inside point: mid-angle, mid-radius. Sector points are (cx+r·cos θ, cy+r·sin θ).
        let s = sector.shape as! SectorShape
        let midAngle = (s.startAngle + s.endAngle) / 2
        let midR = (s.r + s.r0) / 2
        let cx = s.cx + midR * cos(midAngle)
        let cy = s.cy + midR * sin(midAngle)
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(sector.currentStates.contains("emphasis"),
                      "an injected pointer over pie sector 0 must drive it into emphasis")

        // (1,1) is inside the canvas but far from the pie center → resolves no sector.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(sector.currentStates.isEmpty,
                      "moving off pie sector 0 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Line (data-point symbols)

    func testLineSymbolHoverEntersEmphasis() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "symbol": "circle", "symbolSize": 16.0,
                        "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("line render must populate a symbol element for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "LineView must mark each data-point symbol a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "line symbol 0 must not be in emphasis before any hover")

        guard let (cx, cy) = boundingCenter(el) else { XCTFail("no bounding rect"); return }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over line symbol 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off line symbol 0 must clear its emphasis via the mouseout leg")
    }
}
