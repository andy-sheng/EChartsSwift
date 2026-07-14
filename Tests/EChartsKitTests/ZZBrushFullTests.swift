// Brush component — the FULL port (selector.ts / BrushTargetManager.ts / BrushController.ts /
// BrushView.ts), beyond the rect-on-a-grid fragment covered by ZZBrushTests.
//
// What this proves, headlessly:
//   (1) a RECT area dispatched on a cartesian SCATTER selects exactly the in-rect data indices
//       (this is the case that used to silently select NOTHING: scatter's `brushSelector` reads
//       `data.getItemLayout(dataIndex)`, which was never populated until layout/points.ts was ported).
//   (2) a POLYGON area selects exactly the points its outline encloses (scatter-map-brush's shape).
//   (3) a POLYGON area on a GEO coordinate system, dispatched in DATA space (`coordRange` of
//       [lng,lat] vertices), selects the right regions' points — the BrushTargetManager geo target +
//       the polygon coordConvert.
//   (4) `brushSelected` / `brushEnd` reach the chart event bus with the upstream payload shape.
//   (5) the COVER actually renders: BrushView's BrushController paints a cover into the zr.
//   (6) `lineX` on a cartesian scatter (the 1-D band selector).
//
// Selection is read back two ways, and they must agree: the `brushselected` event batch (raw data
// indices) and the item-visual `inBrush`/`outOfBrush` encoding (the dim).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZBrushFullTests: XCTestCase {

    // ---------------------------------------------------------------- fixtures

    /// A cartesian scatter with 5 points on a value/value grid whose pixel geometry is easy to reason about.
    private func makeScatterView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "brush": ["xAxisIndex": 0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "series": [[
                "type": "scatter",
                "data": [[10.0, 10.0], [20.0, 20.0], [50.0, 50.0], [80.0, 80.0], [90.0, 90.0]]
            ] as [String: Any]]
        ])
        return view
    }

    private func firstSeries(_ view: EChartsView) -> SeriesModel? {
        var found: SeriesModel?
        view.ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }

    private func seriesData(_ view: EChartsView) -> SeriesData? {
        return firstSeries(view)?.getData()
    }

    /// The pixel point the layout stage stored for a datum (what the brush selector tests against).
    private func point(_ view: EChartsView, _ idx: Int) -> [Double]? {
        guard let data = seriesData(view) else { return nil }
        return data.getItemLayout(idx) as? [Double]
    }

    private func fill(_ data: SeriesData, _ idx: Int) -> String? {
        guard let style = data.getItemVisual(idx, "style") as? [String: Any] else { return nil }
        let v = style["fill"]
        if let str = v as? String { return str }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }

    /// The dataIndices reported by the `brushselected` event for series 0.
    ///   An action event is a copy of the payload: everything beyond type/componentType/seriesIndex
    ///   lives in `ECActionEvent.eventData` (the payload's dynamic bag) — upstream `params.batch`.
    private func selectedFromEvent(_ paramsIn: ECEventParams?) -> [Int] {
        guard let params = paramsIn as? ECActionEvent else { return [] }
        guard let batch = params.eventData["batch"] as? [[String: Any]],
              let first = batch.first,
              let selected = first["selected"] as? [[String: Any]],
              let s0 = selected.first(where: { ($0["seriesIndex"] as? Int) == 0 }),
              let indices = s0["dataIndex"] as? [Int] else { return [] }
        return indices
    }

    private func dispatchBrush(_ view: EChartsView, _ areas: [[String: Any]]) -> ECEventParams? {
        var got: ECEventParams?
        _ = view.on("brushselected") { params in got = params }
        var p = Payload(type: "brush")
        p.other["areas"] = areas
        view.ec.dispatchAction(p)
        return got
    }

    // ---- (0) The layout stage that the whole scatter brush depends on ----
    func testScatterItemLayoutIsPopulated() {
        let view = makeScatterView()
        guard let data = seriesData(view) else { XCTFail("no scatter series"); return }
        XCTAssertEqual(data.count(), 5)
        for i in 0..<5 {
            guard let p = point(view, i) else {
                XCTFail("scatter datum \(i) must have an item layout (layout/points.ts) — without it the "
                        + "brush selector reads nil and selects nothing"); return
            }
            XCTAssertFalse(p[0].isNaN || p[1].isNaN, "datum \(i) layout must be a real pixel point")
        }
        // x is monotonic in the data (10..90) -> monotonic in pixels.
        XCTAssertLessThan(point(view, 0)![0], point(view, 4)![0])
    }

    // ---- (1) RECT on a cartesian scatter ----
    func testRectBrushOnScatterSelectsInsidePoints() {
        let view = makeScatterView()
        guard let data0 = seriesData(view) else { XCTFail("no series"); return }
        let paletteFill = fill(data0, 0)
        XCTAssertNotNil(paletteFill)

        // A pixel rect covering the first three points (data x = 10, 20, 50) but not x = 80, 90.
        let p2 = point(view, 2)!    // x=50
        let p3 = point(view, 3)!    // x=80
        let cut = (p2[0] + p3[0]) / 2.0

        let params = dispatchBrush(view, [[
            "brushType": "rect",
            "range": [[0.0, cut], [0.0, 300.0]]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1, 2],
                       "the rect must select exactly the three points left of the cut")

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "in-brush point 0 keeps its palette fill")
        XCTAssertEqual(fill(data, 2), paletteFill, "in-brush point 2 keeps its palette fill")
        let dim = fill(data, 3)
        XCTAssertNotEqual(dim, paletteFill, "out-of-brush point 3 is dimmed to the outOfBrush color")
        XCTAssertEqual(fill(data, 4), dim, "point 4 dimmed too")
    }

    // ---- (2) POLYGON on a cartesian scatter ----
    func testPolygonBrushOnScatterSelectsEnclosedPoints() {
        let view = makeScatterView()
        guard let data0 = seriesData(view) else { XCTFail("no series"); return }
        let paletteFill = fill(data0, 0)

        // A quadrilateral around the first two points only (data x = 10, 20).
        let p1 = point(view, 1)!    // x=20
        let p2 = point(view, 2)!    // x=50
        let cut = (p1[0] + p2[0]) / 2.0

        let params = dispatchBrush(view, [[
            "brushType": "polygon",
            "range": [[0.0, 0.0], [cut, 0.0], [cut, 300.0], [0.0, 300.0]]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1],
                       "the polygon must enclose exactly points 0 and 1")

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertEqual(fill(data, 1), paletteFill, "point 1 inside the polygon keeps its fill")
        XCTAssertNotEqual(fill(data, 2), paletteFill, "point 2 outside the polygon is dimmed")
    }

    // ---- (3) lineX on a cartesian scatter (the 1-D band selector) ----
    func testLineXBrushOnScatterSelectsBand() {
        let view = makeScatterView()
        let p1 = point(view, 1)!
        let p2 = point(view, 2)!
        let cut = (p1[0] + p2[0]) / 2.0

        // A lineX area's range is a 1-D pixel band [x0, x1] — no y bounds at all.
        let params = dispatchBrush(view, [[
            "brushType": "lineX",
            "range": [0.0, cut]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1],
                       "the lineX band must select the two points inside it, regardless of their y")
    }

    // ---- (4) the cover actually renders (BrushView + BrushController) ----
    func testBrushCoverIsRendered() {
        let view = makeScatterView()
        let p2 = point(view, 2)!

        _ = dispatchBrush(view, [[
            "brushType": "rect",
            "range": [[0.0, p2[0]], [0.0, 300.0]]
        ] as [String: Any]])

        // The BrushController mounts its cover group directly on the zr (upstream `zr.add(this.group)`),
        // NOT into the ec render group — so look for it there.
        var coverRects: [Rect] = []
        for root in view.zr.storage.getRoots() {
            _ = (root as? Group)?.traverse { el in
                if let r = el as? Rect, r.name == "main" { coverRects.append(r) }
                return false
            }
        }
        XCTAssertFalse(coverRects.isEmpty,
                       "the brush COVER must be painted into the zr (BrushView -> BrushController.updateCovers)")
        guard let main = coverRects.first, let shape = main.shape as? RectShape else {
            XCTFail("the cover's 'main' element must be a Rect with a RectShape"); return
        }
        XCTAssertGreaterThan(shape.width, 0, "the cover rect must have the dragged width")
        XCTAssertEqual(shape.width, p2[0], accuracy: 1.0,
                       "the cover rect must span the brushed pixel range (clipped to the grid panel)")
    }

    // ---- (5) brushEnd carries the areas ----
    func testBrushEndEventFires() {
        let view = makeScatterView()
        var ended: ECEventParams?
        _ = view.on("brushend") { params in ended = params }

        var p = Payload(type: "brushEnd")
        p.other["areas"] = [["brushType": "rect", "range": [[0.0, 100.0], [0.0, 300.0]]] as [String: Any]]
        view.ec.dispatchAction(p)

        XCTAssertNotNil(ended, "'brushEnd' must reach the chart event bus as 'brushend'")
        XCTAssertNotNil((ended as? ECActionEvent)?.eventData["areas"],
                        "the brushEnd payload carries the areas")
    }

    // ---- (6) POLYGON on a GEO coord system, dispatched in DATA space (scatter-map-brush) ----
    private func makeToyGeoJSON() -> [String: Any] {
        func feature(_ name: String, _ lng0: Double, _ lng1: Double) -> [String: Any] {
            return [
                "type": "Feature",
                "properties": ["name": name] as [String: Any],
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [[[lng0, 0.0], [lng1, 0.0], [lng1, 10.0], [lng0, 10.0], [lng0, 0.0]]]
                ] as [String: Any]
            ]
        }
        return [
            "type": "FeatureCollection",
            "features": [
                feature("West", 0.0, 10.0),
                feature("Central", 10.0, 20.0),
                feature("East", 20.0, 30.0)
            ] as [Any]
        ]
    }

    func testPolygonBrushOnGeoSelectsPointsInCoordRange() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 300)
        view.setOption([
            "geo": ["map": "toy", "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0] as [String: Any],
            "brush": ["geoIndex": 0, "brushType": "polygon"] as [String: Any],
            "series": [[
                "type": "scatter",
                "coordinateSystem": "geo",
                // 5 points spread across the three regions (lng, lat):
                //   0,1 in West (lng 2, 6) | 2 in Central (lng 15) | 3,4 in East (lng 22, 28)
                "data": [[2.0, 5.0], [6.0, 5.0], [15.0, 5.0], [22.0, 5.0], [28.0, 5.0]]
            ] as [String: Any]]
        ])

        guard let data0 = seriesData(view) else { XCTFail("no geo scatter series"); return }
        XCTAssertEqual(data0.count(), 5)
        // The geo layout stage must have projected each [lng,lat] to a pixel point.
        for i in 0..<5 {
            guard let p = data0.getItemLayout(i) as? [Double], !p[0].isNaN else {
                XCTFail("geo scatter datum \(i) must have a projected item layout"); return
            }
        }
        let paletteFill = fill(data0, 0)

        // A polygon in DATA space (lng/lat) enclosing West + Central only (lng 0..20).
        // `coordRange` is the geo-space input; BrushTargetManager's polygon coordConvert projects each
        // vertex through Geo.dataToPoint to build the pixel `range`.
        let params = dispatchBrush(view, [[
            "brushType": "polygon",
            "geoIndex": 0,
            "coordRange": [[-1.0, -1.0], [20.0, -1.0], [20.0, 11.0], [-1.0, 11.0]]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1, 2],
                       "the geo polygon (lng -1..20) must select the West + Central points, not the East ones")

        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "in-brush geo point 0 keeps its palette fill")
        XCTAssertNotEqual(fill(data, 3), paletteFill, "geo point 3 (East) is outside the polygon -> dimmed")
        XCTAssertEqual(fill(data, 4), fill(data, 3), "geo point 4 (East) dimmed too")
    }

    // ---- (7) a RECT area bound to the geo coord in DATA space ----
    func testRectBrushOnGeoCoordRange() {
        ECharts.registerMap("toy", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 300)
        view.setOption([
            "geo": ["map": "toy", "top": 40.0, "left": 40.0, "right": 40.0, "bottom": 40.0] as [String: Any],
            "brush": ["geoIndex": 0] as [String: Any],
            "series": [[
                "type": "scatter",
                "coordinateSystem": "geo",
                "data": [[2.0, 5.0], [6.0, 5.0], [15.0, 5.0], [22.0, 5.0], [28.0, 5.0]]
            ] as [String: Any]]
        ])

        // coordRange for a rect is [[lngMin, lngMax], [latMin, latMax]].
        let params = dispatchBrush(view, [[
            "brushType": "rect",
            "geoIndex": 0,
            "coordRange": [[-1.0, 20.0], [-1.0, 11.0]]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1, 2],
                       "the geo rect (lng -1..20) must select the West + Central points")
    }

    // ---- (8) the LIVE drag: arm the brush cursor, then drag on the zr (BrushController's pointer flow) ----
    func testLiveDragThroughBrushControllerSelects() {
        let view = makeScatterView()
        guard let data0 = seriesData(view) else { XCTFail("no series"); return }
        let paletteFill = fill(data0, 0)
        let p2 = point(view, 2)!    // data x = 50
        let p3 = point(view, 3)!    // data x = 80
        let cut = (p2[0] + p3[0]) / 2.0

        // Arm the paint cursor exactly as upstream's toolbox brush button does:
        //   dispatchAction({type:'takeGlobalCursor', key:'brush', brushOption:{brushType:'rect', brushMode:'single'}})
        var arm = Payload(type: "takeGlobalCursor")
        arm.other["key"] = "brush"
        arm.other["brushOption"] = ["brushType": "rect", "brushMode": "single"] as [String: Any]
        view.ec.dispatchAction(arm)

        var brushEnded = false
        _ = view.on("brushend") { _ in brushEnded = true }

        // Drag a rectangle over the first three points.
        view._injectPointerForTest(type: "mousedown", zrX: 55.0, zrY: 25.0)
        view._injectPointerForTest(type: "mousemove", zrX: cut, zrY: 215.0)
        view._injectPointerForTest(type: "mouseup", zrX: cut, zrY: 215.0)

        XCTAssertTrue(brushEnded, "the drag must end with a 'brushEnd' action from BrushView._onBrush")

        guard let data = seriesData(view) else { XCTFail("no series after drag"); return }
        XCTAssertEqual(fill(data, 0), paletteFill, "dragged-over point 0 stays selected (inBrush)")
        XCTAssertEqual(fill(data, 2), paletteFill, "dragged-over point 2 stays selected (inBrush)")
        XCTAssertNotEqual(fill(data, 3), paletteFill, "point 3 outside the dragged rect is dimmed")

        // The brush model now carries the area the drag produced, converted back to DATA space
        // (BrushTargetManager.setOutputRanges -> coordRange).
        var brushModel: BrushModel?
        view.ec.getModel()?.eachComponent("brush") { m, _ in brushModel = m as? BrushModel }
        guard let areas = brushModel?.areas, let area = areas.first else {
            XCTFail("the drag must have produced a brush area on the model"); return
        }
        XCTAssertEqual(area["brushType"] as? String, "rect")
        XCTAssertNotNil(area["coordRange"], "the dragged pixel range must be converted back to a data coordRange")
    }

    // ---- (9) the toolbox brush BUTTON is what arms the cursor in the official examples ----
    //   `brush: { toolbox: [...] }` -> brushPreprocessor injects toolbox.feature.brush.type ->
    //   ToolboxBrushFeature renders those icons -> clicking one dispatches `takeGlobalCursor`.
    func testToolboxBrushButtonArmsTheBrush() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "toolbox": ["feature": [String: Any]()] as [String: Any],
            "brush": ["toolbox": ["rect", "polygon", "clear"], "xAxisIndex": 0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "series": [["type": "scatter", "data": [[10.0, 10.0], [90.0, 90.0]]] as [String: Any]]
        ])

        // The preprocessor must have injected the button list onto the toolbox feature option.
        guard let toolbox = view.ec.getModel()?.getComponent("toolbox") else {
            XCTFail("a toolbox component must exist"); return
        }
        let types = toolbox.get(["feature", "brush", "type"]) as? [Any]
        XCTAssertEqual(types?.compactMap { $0 as? String }, ["rect", "polygon", "clear"],
                       "brushPreprocessor must turn `brush.toolbox` into toolbox.feature.brush.type")

        // The LIVE feature instance owned by the rendered ToolboxView (its `render` caches the current
        //   brushType, which is what makes a second click on the active tool a toggle-OFF).
        func liveBrushFeature() -> ToolboxBrushFeature? {
            var found: ToolboxBrushFeature?
            for cv in view.ec._componentsViews {
                if let tv = cv as? ToolboxView, let f = tv._features["brush"] as? ToolboxBrushFeature {
                    found = f
                }
            }
            return found
        }
        guard let feature = liveBrushFeature() else {
            XCTFail("the ToolboxView must have instantiated the registered 'brush' feature"); return
        }

        // Click the 'rect' button.
        feature.onclick(view.ec.getModel()!, view.ec.api, "rect")

        var brushModel: BrushModel?
        view.ec.getModel()?.eachComponent("brush") { m, _ in brushModel = m as? BrushModel }
        XCTAssertEqual(brushModel?.brushType, "rect",
                       "clicking the toolbox 'rect' button must arm the brush paint cursor (takeGlobalCursor)")

        // Clicking the SAME (active) tool again toggles the brush off.
        guard let feature2 = liveBrushFeature() else { XCTFail("feature"); return }
        feature2.onclick(view.ec.getModel()!, view.ec.api, "rect")
        view.ec.getModel()?.eachComponent("brush") { m, _ in brushModel = m as? BrushModel }
        XCTAssertNil(brushModel?.brushType, "clicking the active tool again disarms the brush")
    }

    // ---- (10) CANDLESTICK brushSelector (candlestick-brush): selects via each candle's brushRect ----
    func testRectBrushOnCandlestickSelectsCandles() {
        let view = EChartsView(width: 500, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 400.0, "height": 200.0] as [String: Any],
            "brush": ["xAxisIndex": 0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "candlestick",
                // [open, close, low, high]
                "data": [[10.0, 20.0, 5.0, 25.0], [20.0, 15.0, 12.0, 26.0],
                         [15.0, 22.0, 14.0, 28.0], [22.0, 18.0, 16.0, 30.0]]
            ] as [String: Any]]
        ])

        guard let data0 = seriesData(view) else { XCTFail("no candlestick series"); return }
        guard let l0 = data0.getItemLayout(0) as? CandlestickItemLayout,
              let l2 = data0.getItemLayout(2) as? CandlestickItemLayout else {
            XCTFail("candlestickLayout must have produced a CandlestickItemLayout (with its brushRect)"); return
        }
        let cut = (l0.brushRect.x + l0.brushRect.width + l2.brushRect.x) / 2.0
        let paletteFill = fill(data0, 0)

        let params = dispatchBrush(view, [[
            "brushType": "rect",
            "range": [[0.0, cut], [0.0, 300.0]]
        ] as [String: Any]])

        XCTAssertEqual(selectedFromEvent(params), [0, 1],
                       "the rect must select the first two candles (matched against their brushRect)")
        guard let data = seriesData(view) else { XCTFail("no series after dispatch"); return }
        XCTAssertNotEqual(fill(data, 2), paletteFill, "candle 2 outside the rect is dimmed")
    }
}
