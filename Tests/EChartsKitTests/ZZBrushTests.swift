// Phase 44 regression test — the RECT brush data core (component/brush: BrushModel + selector +
// visualEncoding). Proves that dispatching a `brush` action with a rectangular area over a cartesian
// bar chart (a) SELECTS the in-rect bars (they keep their palette fill — `inBrush` state) and (b) DIMS
// the out-of-rect bars (their fill is recolored to the brush `outOfBrush` color — `outOfBrush` state).
//
// Uses BAR (not scatter): the slim driver only populates `data.getItemLayout` for series with a layout
// stage (bar's progressive layout writes {x,y,width,height}); scatter computes points inline in its view,
// so its item layout is nil at brush-visual time. The brush rect selector reads getItemLayout, so bar is
// the series that exercises it end-to-end. The brush visual writes the state color into the item-visual
// `style[drawType]` (i.e. `style.fill` for a bar) — the same channel the bar draw reads.
//
// NOTE: a dispatchAction re-runs the full update() which REBUILDS each series' SeriesData, so the data
// object must be re-fetched AFTER the dispatch to observe the brushed fills.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZBrushTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeBrushBarChart() -> EChartsView {
        let view = EChartsView(width: 400, height: 260)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "brush": ["xAxisIndex": 0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6]] as [String: Any]]
        ])
        return view
    }

    private func seriesData(_ view: EChartsView) -> SeriesData? {
        var found: SeriesModel?
        view.ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found?.getData()
    }

    private func barX(_ data: SeriesData, _ idx: Int) -> (x: Double, width: Double)? {
        guard let bag = data.getItemLayout(idx) as? [String: Any],
              let x = bag["x"] as? Double, let w = bag["width"] as? Double else { return nil }
        return (x, w)
    }

    // The bar's drawn fill, normalized to a comparable string ("#5070dd" whether stored as a raw String
    // or an EChartsKit `ZRColor.color(...)`).
    private func fill(_ data: SeriesData, _ idx: Int) -> String? {
        guard let style = data.getItemVisual(idx, "style") as? [String: Any] else { return nil }
        let v = style["fill"]
        if let str = v as? String { return str }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }

    // ---- (1) a rect brush over the first two bars: in-rect bars keep their fill, out-of-rect bars dim ----
    func testRectBrushSelectsInsideDimsOutside() {
        let view = makeBrushBarChart()
        guard let data0 = seriesData(view) else { XCTFail("no bar series"); return }
        XCTAssertEqual(data0.count(), 5, "bar chart should build 5 rows")

        // Bar item layout is populated by the render() layout stage; derive the brush rect from the real
        // pixel spans (no hard-coded pixels).
        guard let b0 = barX(data0, 0), let b1 = barX(data0, 1), let b2 = barX(data0, 2) else {
            XCTFail("bar item layout must exist after render"); return
        }
        let cut = (b1.x + b1.width + b2.x) / 2.0     // between bar1's right edge and bar2's left edge
        let xLo = b0.x - 5.0
        XCTAssertLessThan(cut, b2.x, "cut must fall before bar 2")

        let paletteFill = fill(data0, 0)
        XCTAssertNotNil(paletteFill, "a bar must carry a palette fill before brushing")

        // Dispatch a rect brush. `range` is a PIXEL box [[x0,x1],[y0,y1]]; y spans the plot so every bar's
        // rect overlaps vertically. The bar rects at x >= cut (bars 2,3,4) fall outside → outOfBrush.
        var bp = Payload(type: "brush")
        bp.other["areas"] = [[
            "brushType": "rect",
            "range": [[xLo, cut], [0.0, 260.0]]
        ] as [String: Any]]
        view.ec.dispatchAction(bp)

        // Re-fetch: the dispatch rebuilt the series data. The brush fills live on the new object.
        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }

        // In-rect bars (0,1) keep the palette fill.
        XCTAssertEqual(fill(data, 0), paletteFill, "in-brush bar 0 keeps its palette fill")
        XCTAssertEqual(fill(data, 1), paletteFill, "in-brush bar 1 keeps its palette fill")

        // Out-of-rect bars (2,3,4) are recolored to the shared outOfBrush (dim) color.
        let dim = fill(data, 2)
        XCTAssertNotNil(dim, "an out-of-brush bar must carry a fill")
        XCTAssertNotEqual(dim, paletteFill, "out-of-brush bar 2 must be dimmed away from the palette fill")
        XCTAssertEqual(fill(data, 3), dim, "bar 3 also out → same dim fill")
        XCTAssertEqual(fill(data, 4), dim, "bar 4 also out → same dim fill")
    }

    // ---- (1b) a live drag (mousedown → mouseup) over the first two bars dims the rest ----
    func testLiveBrushDragDimsOutside() {
        let view = makeBrushBarChart()
        guard let data0 = seriesData(view) else { XCTFail("no bar series"); return }
        guard let b0 = barX(data0, 0), let b1 = barX(data0, 1), let b2 = barX(data0, 2) else {
            XCTFail("bar layout"); return
        }
        let cut = (b1.x + b1.width + b2.x) / 2.0
        let paletteFill = fill(data0, 0)

        // Drag a rectangle from (left of bar0, top) to (cut, bottom) — the live `_bindBrush` state machine.
        view._injectPointerForTest(type: "mousedown", zrX: b0.x - 5.0, zrY: 10.0)
        view._injectPointerForTest(type: "mousemove", zrX: cut, zrY: 250.0)
        view._injectPointerForTest(type: "mouseup", zrX: cut, zrY: 250.0)

        guard let data = seriesData(view) else { XCTFail("no series after drag"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "in-brush bar 0 keeps its palette fill after a live drag")
        XCTAssertEqual(fill(data, 1), paletteFill, "in-brush bar 1 keeps its palette fill after a live drag")
        let dim = fill(data, 2)
        XCTAssertNotEqual(dim, paletteFill, "out-of-brush bar 2 dimmed by the live drag")
        XCTAssertEqual(fill(data, 3), dim, "bar 3 dimmed")
        XCTAssertEqual(fill(data, 4), dim, "bar 4 dimmed")
    }

    // ---- (1c) a lineX brush (1-D x-band) selects a column of bars, dims the rest ----
    func testLineXBrushSelectsColumn() {
        let view = makeBrushBarChart()
        guard let data0 = seriesData(view) else { XCTFail("no bar series"); return }
        guard let b0 = barX(data0, 0), let b1 = barX(data0, 1), let b2 = barX(data0, 2) else {
            XCTFail("bar layout"); return
        }
        let cut = (b1.x + b1.width + b2.x) / 2.0
        let paletteFill = fill(data0, 0)

        // A lineX area is a 1-D pixel band [x0, x1] — no y bounds. Bars whose x falls in the band select.
        var bp = Payload(type: "brush")
        bp.other["areas"] = [["brushType": "lineX", "range": [b0.x - 5.0, cut]] as [String: Any]]
        view.ec.dispatchAction(bp)

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "in-band bar 0 keeps its fill")
        XCTAssertEqual(fill(data, 1), paletteFill, "in-band bar 1 keeps its fill")
        let dim = fill(data, 2)
        XCTAssertNotEqual(dim, paletteFill, "out-of-band bar 2 must be dimmed")
        XCTAssertEqual(fill(data, 3), dim, "bar 3 dimmed")
        XCTAssertEqual(fill(data, 4), dim, "bar 4 dimmed")
    }

    // ---- (1d) a polygon brush selects the bars whose rect its outline encloses ----
    func testPolygonBrushSelects() {
        let view = makeBrushBarChart()
        guard let data0 = seriesData(view) else { XCTFail("no bar series"); return }
        guard let b0 = barX(data0, 0), let b1 = barX(data0, 1), let b2 = barX(data0, 2) else {
            XCTFail("bar layout"); return
        }
        let cut = (b1.x + b1.width + b2.x) / 2.0
        let paletteFill = fill(data0, 0)

        // A polygon (a quadrilateral) enclosing the x-range of bars 0 & 1 over the full plot height.
        var bp = Payload(type: "brush")
        bp.other["areas"] = [["brushType": "polygon",
                              "range": [[b0.x - 5.0, 0.0], [cut, 0.0], [cut, 260.0], [b0.x - 5.0, 260.0]]
                             ] as [String: Any]]
        view.ec.dispatchAction(bp)

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "bar 0 inside the polygon keeps its fill")
        XCTAssertEqual(fill(data, 1), paletteFill, "bar 1 inside the polygon keeps its fill")
        let dim = fill(data, 2)
        XCTAssertNotEqual(dim, paletteFill, "bar 2 outside the polygon must be dimmed")
        XCTAssertEqual(fill(data, 4), dim, "bar 4 dimmed")
    }

    // ---- (2) empty brush (areas: []) leaves every bar at the palette fill (no dim) ----
    func testEmptyBrushLeavesAllNormal() {
        let view = makeBrushBarChart()
        guard let data0 = seriesData(view) else { XCTFail("no series"); return }
        let paletteFill = fill(data0, 0)

        var bp = Payload(type: "brush")
        bp.other["areas"] = [[String: Any]]()   // no area brushed → brushVisual applies nothing
        view.ec.dispatchAction(bp)

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        for i in 0..<data.count() {
            XCTAssertEqual(fill(data, i), paletteFill,
                           "with no brush area, bar \(i) keeps the shared palette fill")
        }
    }
}
