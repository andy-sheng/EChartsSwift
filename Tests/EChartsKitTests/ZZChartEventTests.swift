// The CHART-LEVEL EVENT SYSTEM, proven HEADLESSLY through the REAL pointer stack.
//
// `myChart.on('click', handler)` — upstream `class ECharts extends Eventful` + `MessageCenter` +
// `_initEvents` (echarts.ts:1290), which turns a zrender ELEMENT event into a CHART event carrying the
// `getDataParams()` params (seriesIndex / dataIndex / name / value / componentType / …).
//
// These tests do NOT call the packer directly. The click is injected as a synthetic pointer event and
// must travel the whole chain:
//
//     EChartsView._injectPointerForTest("click", x, y)
//       -> zr.handler.click(ZRRawEvent)                       (ZRenderKit Handler)
//       -> handler.findHover(x, y) hit-tests the bar          (real hit-testing over the display list)
//       -> element "click" trigger
//       -> ECharts._initZrEvents' MOUSE_EVENT_NAMES handler   (the ported _initEvents fan-out)
//       -> findEventDispatcher walks up to the ECData-bearing element
//       -> seriesModel.getDataParams(dataIndex, dataType)     (the upstream param packing)
//       -> ECharts.trigger("click", params)                   (Eventful bus)
//       -> the user's handler
//
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZChartEventTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    private func makeBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "name": "S1", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        // Flatten the display list so `findHover` can hit-test the bars.
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    /// The center of bar `i`'s rendered Rect (its shape coords are grid-global).
    private func barCenter(_ view: EChartsView, _ i: Int) -> (x: Double, y: Double)? {
        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let el = series.getData().getItemGraphicEl(i) as? Rect,
              let s = el.shape as? RectShape else { return nil }
        return (s.x + s.width / 2, s.y + s.height / 2)
    }

    /// A REAL click is a pointer SEQUENCE: zrender's `Handler` drops a bare 'click' whose `_downPoint`
    /// is nil (or which moved more than 4px since mousedown — that is a pan, not a click). The native
    /// host sends mousedown → mouseup → click (EChartsHostView.mouseUp), so the test does the same.
    private func clickAt(_ view: EChartsView, _ x: Double, _ y: Double) {
        view._injectPointerForTest(type: "mousedown", zrX: x, zrY: y)
        view._injectPointerForTest(type: "mouseup", zrX: x, zrY: y)
        view._injectPointerForTest(type: "click", zrX: x, zrY: y)
    }

    // ---- (1) A click on a bar fires 'click' with the upstream param shape. ----
    func testClickOnBarFiresChartEventWithDataParams() {
        let view = makeBarView()

        var fired: [ECEventParams] = []
        view.on("click") { params in fired.append(params) }

        guard let p = barCenter(view, 1) else {
            XCTFail("the bar render must have produced a Rect for data index 1"); return
        }

        clickAt(view, p.x, p.y)

        XCTAssertEqual(fired.count, 1, "clicking bar 1 must fire exactly one 'click' chart event")
        guard let params = fired.first else { return }

        XCTAssertEqual(params.type, "click")
        XCTAssertEqual(params.componentType, "series")
        XCTAssertEqual(params.componentSubType, "bar")
        XCTAssertEqual(params.seriesType, "bar")
        XCTAssertEqual(params.seriesIndex, 0)
        XCTAssertEqual(params.seriesName, "S1")
        XCTAssertEqual(params.dataIndex, 1)
        XCTAssertEqual(params.name, "B", "the category name of data index 1")
        XCTAssertEqual(params.value as? Double, 20.0)
        XCTAssertEqual(params.componentIndex, 0)
        XCTAssertNotNil(params.event, "the packed event must carry the originating zr ElementEvent")
    }

    // ---- (2) Each bar reports ITS OWN dataIndex (the packer is not stamping a constant). ----
    func testClickOnEachBarReportsItsOwnDataIndex() {
        let view = makeBarView()

        var seen: [(Double?, String?, Double?)] = []
        view.on("click") { params in
            seen.append((params.dataIndex, params.name, params.value as? Double))
        }

        for i in 0..<3 {
            guard let p = barCenter(view, i) else {
                XCTFail("no Rect for data index \(i)"); return
            }
            clickAt(view, p.x, p.y)
        }

        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen.map { $0.0 }, [0, 1, 2])
        XCTAssertEqual(seen.map { $0.1 }, ["A", "B", "C"])
        XCTAssertEqual(seen.map { $0.2 }, [10.0, 20.0, 30.0])
    }

    // ---- (3) A click on EMPTY canvas fires nothing (no ECData on the target → no params). ----
    func testClickOnEmptyCanvasFiresNoEvent() {
        let view = makeBarView()
        var fired = 0
        view.on("click") { _ in fired += 1 }

        // (1,1) is inside the canvas but far outside the grid → findHover resolves no bar.
        clickAt(view, 1, 1)

        XCTAssertEqual(fired, 0, "a click that hits no data element must not fire a chart 'click'")
    }

    // ---- (4) The event QUERY filter (ECEventProcessor) selects by component / data. ----
    func testEventQueryFiltersByDataIndexAndComponentType() {
        let view = makeBarView()

        var onlyBar2 = 0
        view.on("click", ["dataIndex": 2]) { _ in onlyBar2 += 1 }
        var onlySeries = 0
        view.on("click", "series") { _ in onlySeries += 1 }
        var onlyXAxis = 0
        view.on("click", "xAxis") { _ in onlyXAxis += 1 }

        for i in 0..<3 {
            guard let p = barCenter(view, i) else { XCTFail("no Rect for \(i)"); return }
            clickAt(view, p.x, p.y)
        }

        XCTAssertEqual(onlyBar2, 1, "the {dataIndex: 2} query must match only the third bar")
        XCTAssertEqual(onlySeries, 3, "the 'series' query must match all three bar clicks")
        XCTAssertEqual(onlyXAxis, 0, "the 'xAxis' query must not match a series click")
    }

    // ---- (5) `mouseover` is on the same bus (the whole MOUSE_EVENT_NAMES fan-out, not just click). ----
    func testMouseoverAlsoFiresOnTheChartBus() {
        let view = makeBarView()
        var overs: [Double?] = []
        view.on("mouseover") { params in overs.append(params.dataIndex) }

        guard let p = barCenter(view, 0) else { XCTFail("no Rect for 0"); return }
        view._injectPointerForTest(type: "mousemove", zrX: p.x, zrY: p.y)

        XCTAssertEqual(overs, [0], "hovering bar 0 must fire 'mouseover' on the chart bus with dataIndex 0")
    }

    // ---- (6) The ACTION round trip: dispatchAction → MessageCenter → the public bus. ----
    //      Upstream `doDispatchAction` ends with `messageCenter.trigger(eventObj.type, eventObj)`, and
    //      `_initEvents` re-publishes every registered public event type onto the user bus.
    func testDispatchActionEmitsItsEventOnTheChartBus() {
        let view = makeBarView()

        var highlights: [(Double?, Double?)] = []
        view.on("highlight") { params in
            highlights.append((params.seriesIndex, params.dataIndex))
        }
        var updated = 0
        view.on("updated") { _ in updated += 1 }

        var payload = Payload(type: "highlight")
        payload.other["seriesIndex"] = 0.0
        payload.other["dataIndex"] = 2.0
        view.ec.dispatchAction(payload)

        XCTAssertEqual(highlights.count, 1, "the 'highlight' action must publish a 'highlight' chart event")
        XCTAssertEqual(highlights.first?.0, 0)
        XCTAssertEqual(highlights.first?.1, 2)
        XCTAssertEqual(updated, 1, "a non-silent dispatchAction must also trigger 'updated'")
    }

    // ---- (7) `off` unbinds; a silent dispatch emits nothing. ----
    func testOffUnbindsAndSilentDispatchEmitsNothing() {
        let view = makeBarView()
        var fired = 0
        view.on("click") { _ in fired += 1 }
        view.off("click")

        guard let p = barCenter(view, 0) else { XCTFail("no Rect for 0"); return }
        clickAt(view, p.x, p.y)
        XCTAssertEqual(fired, 0, "off('click') must unbind the handler")

        var highlights = 0
        view.on("highlight") { _ in highlights += 1 }
        var payload = Payload(type: "highlight")
        payload.other["seriesIndex"] = 0.0
        payload.other["dataIndex"] = 1.0
        view.ec.dispatchAction(payload, DispatchActionOpt(silent: true))
        XCTAssertEqual(highlights, 0, "a silent dispatchAction must not publish its event")
    }

    // ---- (8) containPixel — the coord-system hit test that belongs to this family. ----
    func testContainPixel() {
        let view = makeBarView()
        // grid: left 50, top 20, 300x200 → inside (200,100), outside (10,10).
        XCTAssertTrue(view.ec.containPixel(["gridIndex": 0], [200, 100]),
                      "a point inside the grid must be contained by it")
        XCTAssertFalse(view.ec.containPixel(["gridIndex": 0], [10, 10]),
                       "a point outside the grid must not be contained by it")
    }
}
