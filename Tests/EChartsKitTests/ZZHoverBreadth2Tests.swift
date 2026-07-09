// Phase 38 regression test — LIVE hover→emphasis breadth across CANDLESTICK, BOXPLOT, FUNNEL, RADAR.
//
// Modeled on ZZHoverBreadthTests (scatter/pie/line): each test builds an EChartsView, grabs a per-datum
// element from the series data (`data.getItemGraphicEl(idx)`), injects a synthetic POINTER over it via
// `_injectPointerForTest`, and asserts the element enters the "emphasis" state through the REAL Handler
// hit-test + the EChartsView "mouseover" listener → states.enterEmphasisWhenMouseOver. A second mousemove
// off the element proves the "mouseout" leg clears emphasis.
//
// This proves the Phase-38 change: CandlestickView / BoxplotView / FunnelView / RadarView now mark each
// per-datum element (radar: the per-series itemGroup) a highDown dispatcher, so hover-to-highlight (and
// thus item-tooltip) works for them, not just bar/scatter/line/pie.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZHoverBreadth2Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Series model classes (idempotent global registry). RadarModel (the radar coord host component)
        // is auto-registered by ECharts, but re-registering is harmless.
        ComponentModel.registerClass(CandlestickSeriesModel.self)
        ComponentModel.registerClass(BoxplotSeriesModel.self)
        ComponentModel.registerClass(FunnelSeriesModel.self)
        ComponentModel.registerClass(RadarSeriesModel.self)
        ComponentModel.registerClass(RadarModel.self)
    }

    // Center of a path element: its bounding rect center. These per-item paths bake their absolute grid
    // coords into the shape (no group transform), so the local bounding rect is already grid-global.
    private func boundingCenter(_ el: Element) -> (Double, Double)? {
        guard let r = el.getBoundingRect() else { return nil }
        return (r.x + r.width / 2, r.y + r.height / 2)
    }

    // Find the first descendant Path with the given name (radar vertex symbols live under a nested group).
    private func firstDescendant(_ el: Element, named name: String) -> Path? {
        var found: Path? = nil
        if let g = el as? Group {
            _ = g.traverse { child in
                if found == nil, let p = child as? Path, p.name == name { found = p }
                return false
            }
        }
        return found
    }

    // MARK: - Candlestick

    func testCandlestickHoverEntersEmphasis() {
        let view = EChartsView(width: 520, height: 340)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value", "scale": true] as [String: Any],
            "series": [["type": "candlestick",
                        "data": [[20.0, 34.0, 18.0, 38.0], [34.0, 28.0, 25.0, 40.0],
                                 [28.0, 42.0, 26.0, 45.0], [42.0, 38.0, 35.0, 48.0],
                                 [38.0, 50.0, 36.0, 55.0], [50.0, 46.0, 44.0, 58.0]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("candlestick render must populate a NormalBoxPath for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "CandlestickView must mark each candle a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "candle 0 must not be in emphasis before any hover")

        guard let (cx, cy) = boundingCenter(el) else { XCTFail("no bounding rect"); return }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over candle 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off candle 0 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Boxplot

    func testBoxplotHoverEntersEmphasis() {
        let view = EChartsView(width: 520, height: 340)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["G1", "G2", "G3", "G4", "G5"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot",
                        "data": [[10.0, 22.0, 28.0, 35.0, 50.0], [15.0, 25.0, 33.0, 40.0, 55.0],
                                 [8.0, 18.0, 24.0, 30.0, 44.0], [20.0, 30.0, 38.0, 46.0, 60.0],
                                 [12.0, 20.0, 27.0, 36.0, 48.0]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("boxplot render must populate a BoxPath for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "BoxplotView must mark each box a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "box 0 must not be in emphasis before any hover")

        guard let (cx, cy) = boundingCenter(el) else { XCTFail("no bounding rect"); return }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over box 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off box 0 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Funnel

    func testFunnelHoverEntersEmphasis() {
        let view = EChartsView(width: 460, height: 340)
        view.setOption([
            "series": [["type": "funnel", "left": "10%", "top": 20.0, "width": "80%", "height": 300.0,
                        "data": [["value": 100.0, "name": "Show"] as [String: Any],
                                 ["value": 80.0, "name": "Click"] as [String: Any],
                                 ["value": 60.0, "name": "Visit"] as [String: Any],
                                 ["value": 40.0, "name": "Inquiry"] as [String: Any],
                                 ["value": 20.0, "name": "Order"] as [String: Any]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("funnel render must populate a Polygon for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "FunnelView must mark each piece a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "funnel piece 0 must not be in emphasis before any hover")

        guard let (cx, cy) = boundingCenter(el) else { XCTFail("no bounding rect"); return }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over funnel piece 0 must drive it into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off funnel piece 0 must clear its emphasis via the mouseout leg")
    }

    // MARK: - Radar (per-series itemGroup dispatcher; hover a vertex symbol)

    func testRadarHoverEntersEmphasis() {
        let view = EChartsView(width: 400, height: 340)
        view.setOption([
            "radar": ["indicator": [
                ["name": "A", "max": 100.0] as [String: Any],
                ["name": "B", "max": 100.0] as [String: Any],
                ["name": "C", "max": 100.0] as [String: Any],
                ["name": "D", "max": 100.0] as [String: Any],
                ["name": "E", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [["type": "radar", "symbol": "circle", "symbolSize": 20.0,
                        "areaStyle": [:] as [String: Any],
                        "data": [["value": [60.0, 70.0, 80.0, 50.0, 65.0]] as [String: Any]]] as [String: Any]]
        ])

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let el = data.getItemGraphicEl(0) else {
            XCTFail("radar render must populate an itemGroup for data index 0"); return
        }
        XCTAssertTrue(states.isHighDownDispatcher(el),
                      "RadarView must mark each series itemGroup a highDown dispatcher")
        XCTAssertTrue(el.currentStates.isEmpty, "radar row 0 must not be in emphasis before any hover")

        // Hover a vertex symbol (its center is grid-global). The Handler hit resolves the symbol → walks
        // up to the itemGroup dispatcher.
        guard let vertex = firstDescendant(el, named: "vertex"),
              let (cx, cy) = boundingCenter(vertex) else {
            XCTFail("radar render must produce vertex symbol paths"); return
        }
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: cy)
        XCTAssertTrue(el.currentStates.contains("emphasis"),
                      "an injected pointer over a radar vertex must drive the itemGroup into emphasis")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertTrue(el.currentStates.isEmpty,
                      "moving off the radar vertex must clear the itemGroup emphasis via the mouseout leg")
    }
}
