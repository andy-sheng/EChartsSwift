// Marker static-geometry + style tests (markLine / markArea / markPoint). The Phase-51 axis witnesses
// + the now-implemented `SeriesModel.indicesOfNearest` resolve both coordinate markers ({yAxis:v}) and
// statistic markers (min/max/average). markPoint renders via the real SymbolDraw (symbol + value label);
// markLine via a static LineDraw stand-in (dashed lineStyle + circle/arrow end symbols + value label);
// markArea via its Polygon band. These assert the RESOLVED geometry: the average markLine y equals the
// data-mean pixel, the markArea rect spans the two value pixels, the max markPoint sits at the max datum.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZMarkerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeChart(_ markLine: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6], "markLine": markLine] as [String: Any]]
        ])
        return view
    }

    // Collect the markLine bodies from the live display list. A markLine line is a ZRenderKit `Line`
    //   (with a `percent`-growable shape, like upstream's ECLinePath) named "line"; series bars are
    //   Rects and axis lines are Lines but unnamed, so filter by the markLine body name.
    private func markLineBodies(_ view: EChartsView) -> [Line] {
        _ = view.zr.storage.getDisplayList(true)
        return view.zr.storage.getDisplayList(false).compactMap { $0 as? Line }.filter { $0.name == "line" }
    }

    // All rendered label texts. markLine labels are ZRText group children; markPoint labels are attached
    //   to the symbol Path as textContent — collect both from the live scene graph.
    private func labelTexts(_ view: EChartsView) -> [String] {
        var out: [String] = []
        for el in allElements(view) {
            if let t = (el as? ZRText)?.textStyle?.text { out.append(t) }
            if let t = el.getTextContent()?.textStyle?.text { out.append(t) }
        }
        return out
    }

    // Walk the whole live scene graph (getDisplayList flattens away Groups, so Symbol/Line groups are
    //   only reachable by traversing the storage roots).
    private func allElements(_ view: EChartsView) -> [Element] {
        _ = view.zr.storage.getDisplayList(true)
        var out: [Element] = []
        for root in view.zr.storage.getRoots() {
            if let g = root as? Group {
                _ = g.traverse { el in out.append(el); return false }
            }
            else {
                out.append(root)
            }
        }
        return out
    }

    // ---- a coordinate markLine at yAxis:8 renders one horizontal reference Polyline ----
    func testCoordinateMarkLineRenders() {
        // The markLine component must be auto-enabled (preprocessor) and its view registered.
        let view = makeChart(["data": [["yAxis": 8.0] as [String: Any]]])
        XCTAssertNotNil(view.ec.getModel()?.getComponent("markLine"),
                        "a series markLine must auto-enable the master markLine component")

        let lines = markLineBodies(view)
        XCTAssertGreaterThanOrEqual(lines.count, 1, "a {yAxis:8} markLine must render a reference Line")

        // The line is horizontal: both endpoints share ~the same y (the pixel for value 8), and it spans
        // a meaningful x width across the grid.
        guard let shape = lines.first?.shape as? LineShape else {
            XCTFail("markLine Line must carry a LineShape"); return
        }
        let y0 = shape.y1, y1 = shape.y2
        XCTAssertEqual(y0, y1, accuracy: 1.0, "a {yAxis:v} markLine must be horizontal (equal endpoint y)")
        // value 8 of [0,20] over a 240px plot from top=20 → y ≈ 20 + (1 - 8/20)*240 = 20 + 144 = 164.
        XCTAssertEqual(y0, 164.0, accuracy: 12.0, "the line sits at the pixel for value 8 on the y-axis")
        let xSpan = abs(shape.x2 - shape.x1)
        XCTAssertGreaterThan(xSpan, 100.0, "the markLine spans across the grid width")
    }

    // ---- a STATISTIC markLine (type:'average') renders at the computed average value ----
    func testAverageMarkLineRenders() {
        // data [5,9,7,12,6] → average = 7.8. Line pixel y ≈ 20 + (1 - 7.8/20)*240 ≈ 166.4.
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        let lines = markLineBodies(view)
        XCTAssertGreaterThanOrEqual(lines.count, 1, "a type:'average' markLine must render a reference line")
        guard let shape = lines.first?.shape as? LineShape else {
            XCTFail("average markLine must carry a LineShape"); return
        }
        let y0 = shape.y1, y1 = shape.y2
        XCTAssertEqual(y0, y1, accuracy: 1.0, "an average markLine is horizontal")
        XCTAssertEqual(y0, 166.4, accuracy: 12.0, "the line sits at the pixel for the average value 7.8")
    }

    // ---- no markLine option → no markLine component, no reference Polyline ----
    func testNoMarkLineNoComponent() {
        let view = makeChart([String: Any]())   // empty markLine → no data → submodel skipped
        // With no data the master component may still exist (preprocessor injects it), but it renders nothing.
        XCTAssertEqual(markLineBodies(view).count, 0, "an empty markLine must not draw any reference line")
    }

    // ---- an average markLine carries its default value LABEL at the line end ----
    // data [5,9,7,12,6] → average 7.8 → round(7.8, 10) = "7.8".
    func testAverageMarkLineHasValueLabel() {
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        let texts = labelTexts(view)
        XCTAssertTrue(texts.contains("7.8"),
                      "the average markLine default label shows the rounded value 7.8; got \(texts)")
    }

    // ---- an average markLine draws its two end symbols (default symbol: ['circle','arrow']) ----
    func testMarkLineEndSymbolsRender() {
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        let fromCount = allElements(view).filter { ($0 as? Path)?.name == "from" }.count
        let toCount = allElements(view).filter { ($0 as? Path)?.name == "to" }.count
        XCTAssertEqual(fromCount, 1, "a markLine draws one 'from' end symbol (circle)")
        XCTAssertEqual(toCount, 1, "a markLine draws one 'to' end symbol (arrow)")
    }

    // ================= markArea =================

    private func makeAreaChart(_ markArea: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6], "markArea": markArea] as [String: Any]]
        ])
        return view
    }

    private func polygons(_ view: EChartsView) -> [ZRenderKit.Polygon] {
        _ = view.zr.storage.getDisplayList(true)
        return view.zr.storage.getDisplayList(false).compactMap { $0 as? ZRenderKit.Polygon }
    }

    // ---- a {yAxis:8}..{yAxis:12} markArea renders one rectangle spanning those two value pixels ----
    func testMarkAreaRectSpansTwoValues() {
        // value→pixel over [0,20] on a 240px plot from top=20: y = 20 + (1 − v/20)*240.
        //   v=8  → 164 ;  v=12 → 116.  The band spans y∈[116,164], full grid width x∈[50,430].
        let view = makeAreaChart(["data": [[
            ["yAxis": 8.0] as [String: Any],
            ["yAxis": 12.0] as [String: Any]
        ] as [[String: Any]]]])

        let polys = polygons(view)
        XCTAssertGreaterThanOrEqual(polys.count, 1, "a two-point markArea must render a rectangle Polygon")
        guard let shape = polys.first?.shape as? PolygonShape, let pts = shape.points, pts.count >= 4 else {
            XCTFail("markArea Polygon must carry a >=4-point rect shape"); return
        }
        let xs = pts.map { $0[0] }, ys = pts.map { $0[1] }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        XCTAssertEqual(minY, 116.0, accuracy: 12.0, "rect top edge sits at the pixel for value 12")
        XCTAssertEqual(maxY, 164.0, accuracy: 12.0, "rect bottom edge sits at the pixel for value 8")
        XCTAssertEqual(minX, 50.0, accuracy: 8.0, "rect spans from the grid left")
        XCTAssertEqual(maxX, 430.0, accuracy: 8.0, "rect spans to the grid right")
    }

    // ================= markPoint =================

    private func makePointChart(_ markPoint: [String: Any]) -> EChartsView {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E"]] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [["type": "bar", "data": [5.0, 9, 7, 12, 6], "markPoint": markPoint] as [String: Any]]
        ])
        return view
    }

    // ---- a markPoint type:'max' sits at the max datum (value 12 at category index 3) ----
    func testMarkPointMaxSitsAtMaxDatum() {
        // max = 12 at category "D" (index 3). Pixel: y = 20 + (1 − 12/20)*240 = 116.
        //   category band = 380/5 = 76, center of index 3 = 50 + 76*3 + 38 = 316.
        let view = makePointChart(["data": [["type": "max"] as [String: Any]]])

        let symbols: [Symbol] = allElements(view).compactMap { $0 as? Symbol }
        XCTAssertEqual(symbols.count, 1, "a single type:'max' markPoint emits one Symbol")
        guard let sym = symbols.first else { return }
        XCTAssertEqual(sym.x, 316.0, accuracy: 8.0, "the max markPoint anchors on the max datum's column (index 3)")
        XCTAssertEqual(sym.y, 116.0, accuracy: 12.0, "the max markPoint anchors on the pixel for value 12")

        // Its default label shows the value 12.
        let texts = labelTexts(view)
        XCTAssertTrue(texts.contains("12"),
                      "the max markPoint default label shows the value 12; got \(texts)")
    }
}
