// Regression test for the ADVANCED `tooltip.position` forms ported into
// `TooltipView._updatePosition` (upstream TooltipView.ts:905 + `calcTooltipPosition` at :1168):
//
//   (a) the FUNCTION position callback — `TooltipPositionCallback` (util/types.swift) read out of the
//       option bag, invoked with upstream's five arguments (point, params, content el, hovered rect,
//       {contentSize, viewSize}) and its return value routed back through the array / box-layout /
//       string dispatch.
//   (b) the STRING position keywords 'inside' / 'top' / 'bottom' / 'left' / 'right', which anchor the
//       box on the HOVERED element's transformed bounding rect (upstream's `el`) — now threaded from
//       `e.target` on the hover path and `findPointFromSeries`'s `pointInfo.el` on the showTip path.
//
// The assertions are on the REAL rendered box position (`TooltipRichContent.el.x/y` after `moveTo`),
// not on "it compiled": each test drives the live pointer/action stack and checks the box actually
// landed where the position expression asks.
//
// Position math note: `TooltipRichContent.moveTo` offsets the ZRText by `borderWidth + shadowOuterSize`
// (a rich box draws its border/shadow outside the text origin). The fixtures set
// `shadowBlur/shadowOffsetX/shadowOffsetY = 0` so `shadowOuterSize` is 0 and the only offset left is the
// hard-coded `style.borderWidth = 1` that `setContent` applies — hence the `+ boxBorderWidth` terms.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipPositionTests: XCTestCase {

    // The `style.borderWidth` `TooltipRichContent.setContent` hard-codes on the ZRText.
    private let boxBorderWidth: Double = 1

    private let viewWidth: Double = 400
    private let viewHeight: Double = 300

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    /// A 3-bar chart whose `tooltip` carries `positionOption` as its `position`, with the box shadow
    /// zeroed so the rendered `el.x/y` is exactly `computed + borderWidth`.
    private func makeBarView(position positionOption: Any?) -> EChartsView {
        var tooltip: [String: Any] = [
            "shadowBlur": 0.0,
            "shadowOffsetX": 0.0,
            "shadowOffsetY": 0.0
        ]
        if let positionOption = positionOption {
            tooltip["position"] = positionOption
        }
        let view = EChartsView(width: viewWidth, height: viewHeight)
        view.setOption([
            "tooltip": tooltip,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    /// Bar 0's rendered `Rect`, and the centre point to hover.
    private func bar0(_ view: EChartsView) -> (el: Rect, cx: Double, cy: Double)? {
        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let el = series.getData().getItemGraphicEl(0) as? Rect,
              let shape = el.shape as? RectShape else {
            return nil
        }
        return (el, shape.x + shape.width / 2, shape.y + shape.height / 2)
    }

    /// `el.getBoundingRect().clone()` + `applyTransform(el.transform)` — exactly what `_updatePosition`
    /// hands to `calcTooltipPosition` / the position callback.
    private func hoveredRect(_ el: Element) -> BoundingRect {
        let rect = el.getBoundingRect()!.clone()
        rect.applyTransform(el.transform)
        return rect
    }

    /// `confineTooltipPosition` (TooltipView.ts:1150) — `confine` defaults to true in richText mode.
    private func confine(_ x: Double, _ y: Double, _ size: (w: Double, h: Double)) -> (x: Double, y: Double) {
        var x = Swift.min(x + size.w, viewWidth) - size.w
        var y = Swift.min(y + size.h, viewHeight) - size.h
        x = Swift.max(x, 0)
        y = Swift.max(y, 0)
        return (x, y)
    }

    // ------------------------------------------------------------------------
    // (a) The FUNCTION position callback.
    // ------------------------------------------------------------------------
    func testFunctionPositionCallbackIsInvokedWithUpstreamArgsAndPlacesTheBox() {
        // Recorded callback arguments (a class box so the escaping closure can write them back).
        final class Recorder {
            var calls = 0
            var point: (Double, Double) = (.nan, .nan)
            var params: Any?
            var contentEl: Any?
            var rect: RectLike?
            var contentSize: (Double, Double) = (.nan, .nan)
            var viewSize: (Double, Double) = (.nan, .nan)
        }
        let rec = Recorder()

        let callback: TooltipPositionCallback = { point, params, el, rect, size in
            rec.calls += 1
            rec.point = point
            rec.params = params
            rec.contentEl = el
            rec.rect = rect
            rec.contentSize = size.contentSize
            rec.viewSize = size.viewSize
            return [40.0, 60.0]
        }

        let view = makeBarView(position: callback as TooltipPositionCallback)
        guard let bar = bar0(view) else { XCTFail("bar 0 must render a Rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)

        guard let tv = view.tooltipView, let contentEl = tv.contentEl else {
            XCTFail("hovering bar 0 must create + show the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "the tooltip must be shown on hover")

        // (1) The callback must actually have been read out of the option bag and invoked.
        XCTAssertEqual(rec.calls, 1, "the `position` callback must be invoked exactly once per show")

        // (2) upstream arg 1: `[x, y]` — the mouse point.
        XCTAssertEqual(rec.point.0, bar.cx, accuracy: 1e-6, "callback arg 1 must be the mouse x")
        XCTAssertEqual(rec.point.1, bar.cy, accuracy: 1e-6, "callback arg 1 must be the mouse y")

        // (3) upstream arg 2: `params` — the hovered datum's CallbackDataParams (item trigger).
        guard let params = rec.params as? CallbackDataParams else {
            XCTFail("callback arg 2 must be the datum's CallbackDataParams, got \(String(describing: rec.params))")
            return
        }
        XCTAssertEqual(params.dataIndex, 0, "params must describe the HOVERED datum")
        XCTAssertEqual(params.name, "A", "params must describe the HOVERED datum")

        // (4) upstream arg 3: `content.el` — the richText host's ZRText (upstream: DIV | ZRText).
        XCTAssertTrue(rec.contentEl as AnyObject === contentEl,
                      "callback arg 3 must be the tooltip content element (`content.el`)")

        // (5) upstream arg 4: `rect` — the HOVERED element's transformed bounding rect.
        let barRect = hoveredRect(bar.el)
        guard let rect = rec.rect else { XCTFail("callback arg 4 (rect) must not be nil on an item hover"); return }
        XCTAssertEqual(rect.x, barRect.x, accuracy: 1e-6, "callback rect must be the hovered element's rect")
        XCTAssertEqual(rect.y, barRect.y, accuracy: 1e-6, "callback rect must be the hovered element's rect")
        XCTAssertEqual(rect.width, barRect.width, accuracy: 1e-6, "callback rect must be the hovered element's rect")
        XCTAssertEqual(rect.height, barRect.height, accuracy: 1e-6, "callback rect must be the hovered element's rect")

        // (6) upstream arg 5: `{ contentSize, viewSize }`.
        XCTAssertEqual(rec.viewSize.0, viewWidth, accuracy: 1e-6, "size.viewSize must be the chart view size")
        XCTAssertEqual(rec.viewSize.1, viewHeight, accuracy: 1e-6, "size.viewSize must be the chart view size")
        let boxRect = contentEl.getBoundingRect()!
        XCTAssertEqual(rec.contentSize.0, boxRect.width, accuracy: 1e-6,
                       "size.contentSize must be the popup content size (`content.getSize()`)")
        XCTAssertEqual(rec.contentSize.1, boxRect.height, accuracy: 1e-6,
                       "size.contentSize must be the popup content size (`content.getSize()`)")
        XCTAssertTrue(rec.contentSize.0 > 0 && rec.contentSize.1 > 0, "the content size must be measured, not 0")

        // (7) THE BEHAVIOUR: the returned `[40, 60]` must place the box (upstream routes the callback's
        //     return through the same array branch, then `confineTooltipPosition`).
        let expected = confine(40, 60, (boxRect.width, boxRect.height))
        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "the box must be placed at the x the position callback returned")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "the box must be placed at the y the position callback returned")
    }

    /// The callback's return value goes through the SAME dispatch as a literal option, so returning a
    /// box-layout object must lay the box out with `getLayoutRect` (upstream's `isObject` branch).
    func testFunctionPositionCallbackMayReturnABoxLayoutObject() {
        let callback: TooltipPositionCallback = { _, _, _, _, _ in
            return ["left": 12.0, "top": 7.0] as [String: Any]
        }
        let view = makeBarView(position: callback as TooltipPositionCallback)
        guard let bar = bar0(view) else { XCTFail("bar 0 must render a Rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)

        guard let contentEl = view.tooltipView?.contentEl else {
            XCTFail("hovering bar 0 must create + show the TooltipView"); return
        }
        XCTAssertEqual(contentEl.x, 12 + boxBorderWidth, accuracy: 1e-6,
                       "a box-layout object returned by the callback must be laid out by getLayoutRect")
        XCTAssertEqual(contentEl.y, 7 + boxBorderWidth, accuracy: 1e-6,
                       "a box-layout object returned by the callback must be laid out by getLayoutRect")
    }

    // ------------------------------------------------------------------------
    // (b) The STRING position keywords, anchored on the hovered element's rect.
    // ------------------------------------------------------------------------

    /// 'top' — horizontally centred on the hovered bar, sitting ABOVE it by `ceil(SQRT2*borderWidth)+8`.
    func testStringPositionTopAnchorsOnTheHoveredElementRect() {
        let view = makeBarView(position: "top")
        guard let bar = bar0(view) else { XCTFail("bar 0 must render a Rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)

        guard let contentEl = view.tooltipView?.contentEl else {
            XCTFail("hovering bar 0 must create + show the TooltipView"); return
        }
        let boxRect = contentEl.getBoundingRect()!
        let size = (w: boxRect.width, h: boxRect.height)
        let rect = hoveredRect(bar.el)
        // upstream `calcTooltipPosition`, 'top': offset = ceil(SQRT2 * tooltip.borderWidth) + 8 (= 10 for
        //   the default borderWidth 1).
        let offset = ceil(2.0.squareRoot() * 1.0) + 8
        let expected = confine(rect.x + rect.width / 2 - size.w / 2, rect.y - size.h - offset, size)

        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "position:'top' must centre the box on the hovered element's rect")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "position:'top' must lift the box above the hovered element's rect")

        // Semantic cross-check (independent of the formula): centred on the bar, and fully above it.
        XCTAssertEqual(contentEl.x - boxBorderWidth + size.w / 2, rect.x + rect.width / 2, accuracy: 1e-6,
                       "position:'top' must be horizontally centred on the bar")
        XCTAssertTrue(contentEl.y - boxBorderWidth + size.h <= rect.y,
                      "position:'top' must sit entirely above the bar (box bottom \(contentEl.y + size.h) vs bar top \(rect.y))")

        // And it must NOT be the default pointer-relative placement (which offsets by gap 20 from the mouse).
        XCTAssertNotEqual(contentEl.x, bar.cx + 20 + boxBorderWidth, accuracy: 1e-6,
                          "position:'top' must override the default refixTooltipPosition placement")
    }

    /// 'inside' — centred on the hovered element's rect in BOTH axes.
    func testStringPositionInsideCentersOnTheHoveredElementRect() {
        let view = makeBarView(position: "inside")
        guard let bar = bar0(view) else { XCTFail("bar 0 must render a Rect"); return }

        view._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)

        guard let contentEl = view.tooltipView?.contentEl else {
            XCTFail("hovering bar 0 must create + show the TooltipView"); return
        }
        let boxRect = contentEl.getBoundingRect()!
        let size = (w: boxRect.width, h: boxRect.height)
        let rect = hoveredRect(bar.el)
        let expected = confine(rect.x + rect.width / 2 - size.w / 2, rect.y + rect.height / 2 - size.h / 2, size)

        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "position:'inside' must centre the box on the hovered element's rect (x)")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "position:'inside' must centre the box on the hovered element's rect (y)")
    }

    /// A string keyword must be INERT when nothing is hovered (upstream: `isString(positionExpr) && el`),
    /// falling through to the default `refixTooltipPosition` — proven here by the axis-trigger path,
    /// which passes no `el`.
    func testStringPositionFallsBackToRefixWhenNoElement() {
        let view = makeBarView(position: "left")
        guard let bar = bar0(view) else { XCTFail("bar 0 must render a Rect"); return }
        guard let tooltipView = view.tooltipView ?? {
            view._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)
            return view.tooltipView
        }() else {
            XCTFail("a hover must create the TooltipView"); return
        }

        // Drive the AXIS branch directly: it has no hovered element, so `rect` is nil and the string
        // keyword cannot apply — upstream lands in the `refixTooltipPosition` else-branch.
        tooltipView._showAxisTooltip([], x: 100, y: 100)
        guard let contentEl = tooltipView.contentEl else { XCTFail("no tooltip content"); return }
        let boxRect = contentEl.getBoundingRect()!
        // refixTooltipPosition with gapH/gapV 20 (no align set): 100 + 20 unless it would overflow.
        let expectedX = (100 + boxRect.width + 20 + 2 > viewWidth) ? 100 - boxRect.width - 20 : 120
        let expectedY = (100 + boxRect.height + 20 > viewHeight) ? 100 - boxRect.height - 20 : 120
        let expected = confine(expectedX, expectedY, (boxRect.width, boxRect.height))
        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "a string position with no hovered element must fall back to refixTooltipPosition")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "a string position with no hovered element must fall back to refixTooltipPosition")
    }

    /// The showTip ACTION path threads `findPointFromSeries`'s `pointInfo.el`, so the keywords work
    /// without a pointer too.
    func testStringPositionOnTheShowTipActionUsesPointInfoEl() {
        let view = makeBarView(position: "inside")

        var payload = Payload(type: "showTip")
        payload.other["seriesIndex"] = 0
        payload.other["dataIndex"] = 2
        view.ec.dispatchAction(payload)

        guard let tv = view.tooltipView, let contentEl = tv.contentEl else {
            XCTFail("showTip must create + show the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "showTip must show the tooltip")

        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let bar2 = series.getData().getItemGraphicEl(2) else {
            XCTFail("bar 2 must render an element"); return
        }
        let boxRect = contentEl.getBoundingRect()!
        let size = (w: boxRect.width, h: boxRect.height)
        let rect = hoveredRect(bar2)
        let expected = confine(rect.x + rect.width / 2 - size.w / 2, rect.y + rect.height / 2 - size.h / 2, size)

        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "showTip + position:'inside' must anchor on pointInfo.el's rect (x)")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "showTip + position:'inside' must anchor on pointInfo.el's rect (y)")
    }

    // ------------------------------------------------------------------------
    // (c) `TryShowParams.positionDefault` — upstream `manuallyShowTip` passes `positionDefault: 'bottom'`
    //     on the seriesIndex branch ("When manully trigger, the mouse is not on the el, so we'd better to
    //     position tooltip on the bottom of the el"). It is applied as `buildTooltipModel`'s
    //     `defaultTooltipOption`, i.e. the BASE model UNDER the global option — so it takes effect when no
    //     `position` is configured, and is outranked when one is.
    // ------------------------------------------------------------------------
    func testShowTipActionDefaultsToPositionBottomOnTheDatumRect() {
        let view = makeBarView(position: nil)   // NO explicit tooltip.position

        var payload = Payload(type: "showTip")
        payload.other["seriesIndex"] = 0
        payload.other["dataIndex"] = 2
        view.ec.dispatchAction(payload)

        guard let tv = view.tooltipView, let contentEl = tv.contentEl else {
            XCTFail("showTip must create + show the TooltipView"); return
        }
        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let bar2 = series.getData().getItemGraphicEl(2) as? Rect,
              let shape = bar2.shape as? RectShape else {
            XCTFail("bar 2 must render a Rect"); return
        }
        let boxRect = contentEl.getBoundingRect()!
        let size = (w: boxRect.width, h: boxRect.height)
        let rect = hoveredRect(bar2)
        // upstream `calcTooltipPosition`, 'bottom'.
        let offset = ceil(2.0.squareRoot() * 1.0) + 8
        let expected = confine(rect.x + rect.width / 2 - size.w / 2, rect.y + rect.height + offset, size)

        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "an action-driven showTip must default to position:'bottom' on the datum's rect (x)")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "an action-driven showTip must default to position:'bottom' on the datum's rect (y)")

        // It must NOT be the pointer-relative `refixTooltipPosition` gap-20 fallback.
        let pointerX = shape.x + shape.width / 2
        XCTAssertNotEqual(contentEl.x, pointerX + 20 + boxBorderWidth, accuracy: 1e-6,
                          "positionDefault:'bottom' must override the refixTooltipPosition placement")

        // And a HOVER (not action-driven) must NOT get the 'bottom' default — upstream only passes
        // positionDefault from `manuallyShowTip`.
        let hoverView = makeBarView(position: nil)
        guard let bar = bar0(hoverView) else { XCTFail("bar 0 must render a Rect"); return }
        hoverView._injectPointerForTest(type: "mousemove", zrX: bar.cx, zrY: bar.cy)
        guard let hoverEl = hoverView.tooltipView?.contentEl else {
            XCTFail("hovering bar 0 must show the tooltip"); return
        }
        let hoverBox = hoverEl.getBoundingRect()!
        let hoverExpectedX = (bar.cx + hoverBox.width + 20 + 2 > viewWidth) ? bar.cx - hoverBox.width - 20 : bar.cx + 20
        let hoverExpectedY = (bar.cy + hoverBox.height + 20 > viewHeight) ? bar.cy - hoverBox.height - 20 : bar.cy + 20
        let hoverExpected = confine(hoverExpectedX, hoverExpectedY, (hoverBox.width, hoverBox.height))
        XCTAssertEqual(hoverEl.x, hoverExpected.x + boxBorderWidth, accuracy: 1e-6,
                       "a HOVER show must keep the pointer-relative default placement (no positionDefault)")
        XCTAssertEqual(hoverEl.y, hoverExpected.y + boxBorderWidth, accuracy: 1e-6,
                       "a HOVER show must keep the pointer-relative default placement (no positionDefault)")
    }

    /// An explicit `tooltip.position` must still WIN over `positionDefault` — upstream layers the default
    /// UNDER the global option (`buildTooltipModel`, TooltipView.ts:1080-1082).
    func testExplicitPositionOutranksThePositionDefault() {
        // `testStringPositionOnTheShowTipActionUsesPointInfoEl` already asserts position:'inside' lands
        // centred; re-assert here that it is NOT the 'bottom' default.
        let view = makeBarView(position: "inside")

        var payload = Payload(type: "showTip")
        payload.other["seriesIndex"] = 0
        payload.other["dataIndex"] = 2
        view.ec.dispatchAction(payload)

        guard let contentEl = view.tooltipView?.contentEl,
              let series = view.ec.getModel()?.getSeriesByIndex(0),
              let bar2 = series.getData().getItemGraphicEl(2) else {
            XCTFail("showTip must show the tooltip on bar 2"); return
        }
        let boxRect = contentEl.getBoundingRect()!
        let size = (w: boxRect.width, h: boxRect.height)
        let rect = hoveredRect(bar2)
        let insideExpected = confine(rect.x + rect.width / 2 - size.w / 2,
                                     rect.y + rect.height / 2 - size.h / 2, size)
        XCTAssertEqual(contentEl.y, insideExpected.y + boxBorderWidth, accuracy: 1e-6,
                       "an explicit position:'inside' must outrank positionDefault:'bottom'")
    }

    // ------------------------------------------------------------------------
    // (d) `trigger:'axis'` must hand the position callback the REAL per-series `cbParamsList`
    //     (upstream TooltipView.ts:578-614), not an empty array.
    // ------------------------------------------------------------------------
    func testAxisTriggerPositionCallbackReceivesTheRealCbParamsList() {
        final class Recorder { var params: Any?; var calls = 0 }
        let rec = Recorder()
        let callback: TooltipPositionCallback = { _, params, _, _, _ in
            rec.calls += 1
            rec.params = params
            return [30.0, 50.0]
        }

        let view = EChartsView(width: viewWidth, height: viewHeight)
        view.setOption([
            "tooltip": [
                "trigger": "axis",
                "position": (callback as TooltipPositionCallback),
                "shadowBlur": 0.0, "shadowOffsetX": 0.0, "shadowOffsetY": 0.0
            ] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        _ = view.zr.storage.getDisplayList(true)

        guard let series = view.ec.getModel()?.getSeriesByIndex(0),
              let bar1 = series.getData().getItemGraphicEl(1) as? Rect,
              let shape = bar1.shape as? RectShape else {
            XCTFail("bar 1 must render a Rect"); return
        }
        view._injectPointerForTest(type: "mousemove", zrX: shape.x + shape.width / 2, zrY: 120)

        guard let contentEl = view.tooltipView?.contentEl else {
            XCTFail("hovering an axis chart must show the combined tooltip"); return
        }
        XCTAssertGreaterThan(rec.calls, 0, "the axis path must invoke the `position` callback")

        // THE REGRESSION: upstream's ARRAY arm carries one entry per series that HAS a datum at the
        // hovered axis value. Before this fix the axis path substituted an invented empty array.
        guard let list = rec.params as? [CallbackDataParams] else {
            XCTFail("trigger:'axis' must pass the ARRAY arm of the params union, got \(String(describing: rec.params))")
            return
        }
        XCTAssertEqual(list.count, 1, "one series has a datum at the hovered axis value")
        XCTAssertEqual(list[0].dataIndex, 1, "the params must describe the HOVERED axis datum ('B')")
        XCTAssertEqual(list[0].name, "B", "the params must describe the HOVERED axis datum ('B')")
        XCTAssertEqual(list[0].seriesIndex, 0)

        // And the callback's return value must still place the box.
        let boxRect = contentEl.getBoundingRect()!
        let expected = confine(30, 50, (boxRect.width, boxRect.height))
        XCTAssertEqual(contentEl.x, expected.x + boxBorderWidth, accuracy: 1e-6,
                       "the axis position callback's return must place the box")
        XCTAssertEqual(contentEl.y, expected.y + boxBorderWidth, accuracy: 1e-6,
                       "the axis position callback's return must place the box")
    }
}
