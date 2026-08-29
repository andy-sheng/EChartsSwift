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
        ComponentModel.registerClass(ScatterSeriesModel.self)
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

    func testCoordinateMarkLineHasUnwrappedValueLabel() {
        let view = makeChart(["data": [["yAxis": 8.0] as [String: Any]]])
        let texts = labelTexts(view)
        XCTAssertTrue(texts.contains("8"),
                      "a fixed yAxis markLine must show its numeric value; got \(texts)")
        XCTAssertFalse(texts.contains { $0.contains("Optional(") },
                       "dynamic option values must not leak Swift Optional syntax into labels")
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

    func testAverageMarkLineRoundsDecimalTieLikeJavaScriptToFixed() {
        let view = EChartsView(width: 460, height: 300)
        let values: [Double] = [
            2.0, 4.9, 7.0, 23.2, 25.6, 76.7,
            135.6, 162.2, 32.6, 20.0, 6.4, 3.3
        ] // mean = 41.625; JS `(41.625).toFixed(2)` -> "41.63".
        view.setOption([
            "xAxis": ["type": "category", "data": values.indices.map(String.init)] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar", "data": values,
                "markLine": ["data": [["type": "average"] as [String: Any]] as [Any]]
            ] as [String: Any]]
        ])
        let texts = labelTexts(view)
        XCTAssertTrue(texts.contains("41.63"), "decimal ties must round like JS toFixed; got \(texts)")
        XCTAssertFalse(texts.contains("41.62"))
    }

    // ---- an average markLine draws its two end symbols (default symbol: ['circle','arrow']) ----
    func testMarkLineEndSymbolsRender() {
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        let fromCount = allElements(view).filter { ($0 as? Path)?.name == "from" }.count
        let toCount = allElements(view).filter { ($0 as? Path)?.name == "to" }.count
        XCTAssertEqual(fromCount, 1, "a markLine draws one 'from' end symbol (circle)")
        XCTAssertEqual(toCount, 1, "a markLine draws one 'to' end symbol (arrow)")
    }

    func testMarkLineEntranceLabelFollowsGrowingEndpoint() {
        let view = makeChart(["data": [["type": "average"] as [String: Any]]])
        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let model = MarkerModel.getMarkerModelFromSeries(series, "markLine"),
              let lineGroup = model.getData().getItemGraphicEl(0) as? ECLine,
              let line = lineGroup.getLinePath(),
              let animator = line.animators.first(where: { $0.targetName == "shape" }),
              let clip = animator.getClip(),
              let label = lineGroup.getTextContent() else {
            return XCTFail("markLine must expose an animated line and attached label")
        }

        _ = clip.step(0, 0)
        let startX = label.x
        _ = clip.step(500, 500)
        let middleX = label.x
        _ = clip.step(1000, 500)
        let endX = label.x

        XCTAssertGreaterThan(middleX, startX,
                             "markLine end label must move with the growing line head")
        XCTAssertGreaterThan(endX, middleX,
                             "markLine end label must reach the final endpoint at animation end")
    }

    func testMarkLineArrowFollowsRelayoutAnimationAfterLegendToggle() {
        let view = EChartsView(width: 640, height: 420)
        view.setOption([
            "animationDuration": 0.0,
            "animationDurationUpdate": 1000.0,
            "legend": [:] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Highest", "type": "line", "data": [10.0, 11, 13, 11, 12, 12, 9]] as [String: Any],
                [
                    "name": "Lowest", "type": "line", "data": [1.0, -2, 2, 5, 3, 2, 0],
                    "markLine": ["data": [["type": "average"] as [String: Any]] as [Any]]
                ] as [String: Any]
            ]
        ])

        var toggle = Payload(type: "legendToggleSelect")
        toggle.other["name"] = "Highest"
        view.ec.dispatchAction(toggle)

        guard let lowest = view.ec.getModel()?.getSeriesByIndex(1),
              let model = MarkerModel.getMarkerModelFromSeries(lowest, "markLine"),
              let lineGroup = model.getData().getItemGraphicEl(0) as? ECLine,
              let line = lineGroup.getLinePath() as? Line,
              let arrow = lineGroup.childOfName("to") as? Path,
              let animator = line.animators.first(where: { $0.targetName == "shape" }),
              let clip = animator.getClip() else {
            return XCTFail("legend relayout must keep an animated markLine and its to-arrow")
        }

        _ = clip.step(0, 0)
        let start = line.pointAt(1)
        XCTAssertEqual(arrow.x, start[0], accuracy: 1e-6,
                       "at animation start the arrow x must stay on the current line endpoint")
        XCTAssertEqual(arrow.y, line.pointAt(1)[1], accuracy: 1e-6,
                       "at animation start the arrow must stay on the current line endpoint")

        _ = clip.step(500, 500)
        let middle = line.pointAt(1)
        XCTAssertEqual(arrow.x, middle[0], accuracy: 1e-6,
                       "during relayout the arrow x must follow the animated line endpoint")
        XCTAssertEqual(arrow.y, middle[1], accuracy: 1e-6,
                       "during relayout the arrow must follow the animated line endpoint")

        _ = clip.step(1000, 500)
        let end = line.pointAt(1)
        XCTAssertEqual(arrow.x, end[0], accuracy: 1e-6,
                       "at animation end the arrow x must reach the final line endpoint")
        XCTAssertEqual(arrow.y, end[1], accuracy: 1e-6,
                       "at animation end the arrow must reach the final line endpoint")
        XCTAssertGreaterThan(abs(end[1] - start[1]), 1,
                             "legend toggle must produce a genuine markLine relayout")
        XCTAssertGreaterThan(middle[1], min(start[1], end[1]),
                             "500ms must be a genuine midpoint, not the start or end")
        XCTAssertLessThan(middle[1], max(start[1], end[1]),
                          "500ms must be a genuine midpoint, not the start or end")
    }

    func testPairedStatisticMarkLineRenders() {
        let view = makeChart(["data": [[
            ["symbol": "none", "x": "90%", "yAxis": "max"] as [String: Any],
            [
                "symbol": "circle",
                "label": ["position": "start", "formatter": "Max"] as [String: Any],
                "type": "max"
            ] as [String: Any]
        ] as [Any]]])
        let bodies = markLineBodies(view)
        XCTAssertEqual(bodies.count, 1,
                       "a two-endpoint pair mixing pixel x and a max statistic must render one markLine")
        if let shape = bodies.first?.shape as? LineShape {
            XCTAssertTrue(shape.x1.isFinite && shape.y1.isFinite && shape.x2.isFinite && shape.y2.isFinite,
                          "paired markLine endpoints must resolve to finite screen coordinates")
        }
        let series = view.ec.getModel()?.getSeriesByIndex(0)
        let lineModel = series.flatMap { MarkerModel.getMarkerModelFromSeries($0, "markLine") }
        let rawLineItem = lineModel?.getData().getRawDataItem(0)
        XCTAssertEqual(lineModel?.getData().getItemModel(0).get(["label", "formatter"]) as? String, "Max",
                       "the merged line-data item must retain the endpoint label formatter; raw=\(String(describing: rawLineItem))")
        let texts = labelTexts(view)
        XCTAssertTrue(texts.contains("Max"),
                      "the paired endpoint's label formatter must survive normalization; got \(texts)")
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

    func testMarkAreaShowsStartItemName() {
        let view = makeAreaChart(["data": [[
            ["name": "Morning Peak", "xAxis": "B"] as [String: Any],
            ["xAxis": "D"] as [String: Any]
        ] as [[String: Any]]]])

        XCTAssertTrue(labelTexts(view).contains("Morning Peak"),
                      "markArea's default visible label must use the merged area's name")
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

    func testMarkPointEntranceScalesPinButKeepsAttachedValueVisible() {
        let view = makePointChart(["data": [["type": "max"] as [String: Any]]])
        guard let symbolGroup = allElements(view).compactMap({ $0 as? Symbol }).first,
              let pin = symbolGroup.childAt(0) as? Displayable else {
            return XCTFail("markPoint must render a symbol path")
        }

        XCTAssertTrue(pin.animators.contains { animator in
            animator.getTrack("scaleX") != nil && animator.getTrack("scaleY") != nil
        }, "markPoint pin must have a scale entrance animator")
        XCTAssertGreaterThan(pin.getTextContent()?.textStyle?.opacity ?? 0, 0,
                             "upstream keeps the attached markPoint value visible while the pin scales in")
    }

    func testScatterMarkerEntranceUsesScatterHostAnimationModel() {
        let view = EChartsView(width: 460, height: 300)
        view.setOption([
            "animation": true,
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value", "min": 140.0, "max": 200.0] as [String: Any],
            "yAxis": ["type": "value", "min": 40.0, "max": 120.0] as [String: Any],
            "series": [[
                "type": "scatter",
                "data": [[160.0, 55.0], [172.0, 78.0], [184.0, 105.0]],
                "markPoint": ["data": [["type": "max"] as [String: Any]]] as [String: Any],
                "markLine": ["data": [["type": "average"] as [String: Any]]] as [String: Any]
            ] as [String: Any]]
        ])

        guard let symbol = allElements(view).compactMap({ $0 as? Symbol }).first,
              let pin = symbol.childAt(0) as? Displayable else {
            return XCTFail("scatter markPoint must render a symbol path")
        }
        XCTAssertTrue(pin.animators.contains { animator in
            animator.getTrack("scaleX") != nil && animator.getTrack("scaleY") != nil
        }, "scatter markPoint must inherit the scatter series' entrance animation")
        XCTAssertTrue(markLineBodies(view).contains { line in
            line.animators.contains { $0.targetName == "shape" }
        }, "scatter markLine must inherit the scatter series' entrance animation")
    }
}
