// Regression tests for the COMPONENT-ITEM tooltip — upstream `TooltipView._showComponentItemTooltip`
// (TooltipView.ts:740-800), reached from `_tryShow`'s `cmptDispatcher` branch (TooltipView.ts:493-504).
//
// A component item is an element that carries `ecData.tooltipConfig` (stamped by `setTooltipConfig`,
// util/graphic.swift) instead of a series `dataIndex`: legend items, graphic elements, toolbox icons,
// geo/map regions, matrix cells, timeline ticks, axis names/labels. The PROVIDER side (setTooltipConfig
// + 7 component views) was already ported; this is the READER side, which was a documented deferral —
// so before this port hovering a legend item produced NOTHING, no matter what `legend.tooltip` said.
//
// Every test therefore asserts on the STRING that ends up in the live `ZRText` box, not merely that the
// config round-trips.
//
// Covered:
//   (1) end-to-end: HOVERING a legend item through the real pointer stack shows the item's name
//   (2) the `{formatter: tooltipOpt.content}` cascade layer — the default content IS the item name
//   (3) the COMPONENT's own `tooltip` option layer (`ecModel.getComponent(mainType, index)`) outranks
//       that default-content layer
//   (4) the config's OWN option (`itemTooltipOption`) outranks the component's
//   (5) `formatterParams` (incl. the `formatterParamsExtra` keys appended to `$vars`) really reaches a
//       STRING formatter's `{a}`/`{b}` aliases …
//   (6) … and a FUNCTION formatter, spelled at `ComponentItemTooltipLabelFormatterParams`
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTooltipComponentItemTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    // ------------------------------------------------------------------------
    // Fixtures
    // ------------------------------------------------------------------------

    /// A chart with a legend. `legendTooltip` becomes `legend.tooltip` (upstream `LegendView` only
    /// stamps a `tooltipConfig` on the item hit-rect when `legendItemModel.getModel('tooltip').get('show')`).
    private func makeLegendView(
        legendTooltip: [String: Any],
        globalTooltip: [String: Any] = ["trigger": "item"]
    ) -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        var legend: [String: Any] = ["data": ["Alpha", "Beta"]]
        legend["tooltip"] = legendTooltip
        view.setOption([
            "tooltip": globalTooltip,
            "legend": legend,
            "grid": ["left": 50.0, "top": 60.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Alpha", "type": "line", "data": [1.0, 2.0, 3.0]] as [String: Any],
                ["name": "Beta", "type": "line", "data": [3.0, 2.0, 1.0]] as [String: Any]
            ]
        ])
        return view
    }

    /// The rendered element whose `ecData.tooltipConfig.name` is `name` (the legend item's hit-rect).
    private func findTooltipConfigEl(_ view: EChartsView, named name: String) -> Element? {
        for el in view.zr.storage.getDisplayList(true) {
            if innerStore.getECData(el).tooltipConfig?.name == name {
                return el
            }
        }
        return nil
    }

    /// The tooltip text currently in the live `ZRText` box (nil when no tooltip is up).
    private func tooltipText(_ view: EChartsView) -> String? {
        guard let tv = view.tooltipView, tv.isShown() else { return nil }
        return tv.contentEl?.textStyle?.text
    }

    // ------------------------------------------------------------------------
    // (1) END-TO-END: hovering a legend item shows the component tooltip.
    // ------------------------------------------------------------------------
    func testHoveringLegendItemShowsComponentTooltipWithItemName() {
        let view = makeLegendView(legendTooltip: ["show": true])
        _ = view.zr.storage.getDisplayList(true)

        guard let hitRect = findTooltipConfigEl(view, named: "Alpha") else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on the 'Alpha' item when legend.tooltip.show")
            return
        }
        guard let rect = hitRect.getBoundingRect() else {
            XCTFail("the legend hit-rect must have a bounding rect to hover")
            return
        }
        let center = hitRect.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])

        // Upstream default content for a component item is the item name (`setTooltipConfig` sets
        //   `content: itemName`, and `_showComponentItemTooltip` pushes `{formatter: tooltipOpt.content}`
        //   as the bottom cascade layer).
        XCTAssertEqual(tooltipText(view), "Alpha",
                       "hovering the legend item must show the COMPONENT tooltip with the item's name")
    }

    // The same hover, but with a `legend.tooltip.formatter` no SERIES tooltip could ever produce — this
    //   pins that the content really came from the COMPONENT-item branch (`_showComponentItemTooltip`)
    //   and not from the series item branch that happens to share the name "Alpha".
    func testHoveringLegendItemUsesTheLegendTooltipFormatter() {
        let view = makeLegendView(legendTooltip: ["show": true, "formatter": "LEGEND-TIP:{a}"])
        _ = view.zr.storage.getDisplayList(true)

        guard let hitRect = findTooltipConfigEl(view, named: "Beta"),
              let rect = hitRect.getBoundingRect() else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on the 'Beta' item")
            return
        }
        let center = hitRect.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])

        XCTAssertEqual(tooltipText(view), "LEGEND-TIP:Beta",
                       "the hovered legend item's tooltip must come from the legend's own tooltip option")
    }

    // A component item that is NOT hovered must not leave a tooltip behind, and an element with no
    //   tooltipConfig at all must not produce one (guards the new dispatcher branch against firing on
    //   every hover).
    func testHoveringNothingShowsNoComponentTooltip() {
        let view = makeLegendView(legendTooltip: ["show": true])
        _ = view.zr.storage.getDisplayList(true)
        // The very top-left corner is outside the grid and outside the legend.
        view._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 292)
        XCTAssertNil(tooltipText(view), "hovering empty canvas must not show a component tooltip")
    }

    func testGlobalOutHidesComponentTooltipWithoutHighDownDispatcher() {
        let stamped = stampComponentItem(legendTooltip: ["show": true], itemName: "MapRegion")
        XCTAssertEqual(showComponentTooltip(stamped), "MapRegion")

        stamped.view._injectGlobalOutForTest()

        XCTAssertNil(tooltipText(stamped.view),
                     "leaving the canvas must hide a component tooltip even when its element is not "
                     + "a high-down dispatcher")
        XCTAssertFalse(stamped.view.tooltipView?._shownAsCmptItem ?? true)
    }

    // ------------------------------------------------------------------------
    // (1b) THE AXIS RACE. With `tooltip.trigger:'axis'` (the most common tooltip config) the axis leg
    //   runs `axisTrigger` on EVERY zr mousemove; over a legend item — outside any coordinate system —
    //   `dispatchTooltipActually` dispatches `hideTip`, which `EChartsView._realDispatchAxisPointer`
    //   turns into `tooltipView.hide()`. zrender fires `mouseover` only when the target CHANGES, so the
    //   component tooltip goes up on the first move and, without upstream's `showTip`/`from: this.uid`
    //   protection, is destroyed on the second and never comes back.
    //   Upstream: `_showComponentItemTooltip` ends with `dispatchAction({type:'showTip', from: this.uid})`
    //   ("If not dispatch showTip, tip may be hide triggered by axis."); this port's stand-in is
    //   `TooltipView._shownAsCmptItem`, read by the `hideTip` arm.
    // ------------------------------------------------------------------------
    func testComponentTooltipSurvivesTheAxisLegHideTipUnderTriggerAxis() {
        let view = makeLegendView(
            legendTooltip: ["show": true],
            globalTooltip: ["trigger": "axis"]
        )
        _ = view.zr.storage.getDisplayList(true)

        guard let hitRect = findTooltipConfigEl(view, named: "Alpha"),
              let rect = hitRect.getBoundingRect() else {
            XCTFail("LegendView must stamp an ecData.tooltipConfig on the 'Alpha' item")
            return
        }
        let center = hitRect.transformCoordToGlobal(rect.x + rect.width / 2, rect.y + rect.height / 2)

        // First move: element `mouseover` fires → the component tooltip goes up.
        view._injectPointerForTest(type: "mousemove", zrX: center[0], zrY: center[1])
        XCTAssertEqual(tooltipText(view), "Alpha",
                       "the component tooltip must show on the first move even under trigger:'axis' "
                       + "(_showComponentItemTooltip deliberately does NOT gate on `trigger`)")

        // Second move INSIDE the same element: no `mouseover` this time, only the axis leg's mousemove
        //   → axisTrigger → hideTip. It must NOT tear down the component tooltip.
        view._injectPointerForTest(type: "mousemove", zrX: center[0] + 1, zrY: center[1])
        XCTAssertEqual(tooltipText(view), "Alpha",
                       "the axis leg's per-mousemove hideTip must not destroy the COMPONENT-item tooltip")

        // …and a third, to pin that the guard is not a one-shot.
        view._injectPointerForTest(type: "mousemove", zrX: center[0] + 2, zrY: center[1])
        XCTAssertEqual(tooltipText(view), "Alpha")

        // Leaving the element DOES hide it (zr `mouseout` calls `hide()` directly, which also clears the
        //   `_shownAsCmptItem` stand-in) — the guard must not strand a visible box.
        view._injectPointerForTest(type: "mouseout", zrX: 2, zrY: 292)
        XCTAssertFalse(view.tooltipView?._shownAsCmptItem ?? false,
                       "leaving the component item must retire the `from: this.uid` stand-in")
    }

    // ------------------------------------------------------------------------
    // Fixture for the cascade tests: stamp a tooltipConfig by hand onto a plain element, exactly the
    //   way the 7 ported component views do, then drive the READER directly.
    // ------------------------------------------------------------------------
    private struct Stamped {
        let view: EChartsView
        let el: Element
    }

    private func stampComponentItem(
        legendTooltip: [String: Any],
        itemName: String = "Alpha",
        itemTooltipOption: Any? = nil,
        formatterParamsExtra: KeyValuePairs<String, Any>? = nil
    ) -> Stamped {
        let view = makeLegendView(legendTooltip: legendTooltip)
        let legendModel = view.ec.getModel()!.getComponent("legend")!
        var shape = RectShape()
        shape.x = 10; shape.y = 10; shape.width = 40; shape.height = 20
        let el = Rect(["shape": shape as PathShape])
        setTooltipConfig(
            el: el,
            componentModel: legendModel,
            itemName: itemName,
            itemTooltipOption: itemTooltipOption,
            formatterParamsExtra: formatterParamsExtra
        )
        view.zr.add(el)
        _ = view.zr.storage.getDisplayList(true)
        return Stamped(view: view, el: el)
    }

    private func showComponentTooltip(_ s: Stamped) -> String? {
        // `_ensureTooltipView` is private; a hover anywhere builds the view, so reach the same entry the
        //   host does by asking for the view via a first pointer move, then call the ported reader.
        s.view._injectPointerForTest(type: "mousemove", zrX: 30, zrY: 20)
        guard let tv = s.view.tooltipView else {
            XCTFail("hovering the stamped element must have built the TooltipView")
            return nil
        }
        tv._showComponentItemTooltip(el: s.el, point: [30, 20])
        return tooltipText(s.view)
    }

    // ------------------------------------------------------------------------
    // (2) The default content layer: `tooltipModelCascade.push({ formatter: tooltipOpt.content })`.
    // ------------------------------------------------------------------------
    func testComponentTooltipDefaultsToTheItemName() {
        let s = stampComponentItem(legendTooltip: ["show": true], itemName: "MyItem")
        XCTAssertEqual(showComponentTooltip(s), "MyItem",
                       "with no formatter anywhere, the component tooltip content is the item name")
    }

    // ------------------------------------------------------------------------
    // (3) The COMPONENT's own tooltip option (cascade layer 2 — `ecModel.getComponent(mainType, index)`)
    //     outranks the default-content layer.
    // ------------------------------------------------------------------------
    func testComponentOwnTooltipOptionOutranksDefaultContentLayer() {
        let s = stampComponentItem(
            legendTooltip: ["show": true, "formatter": "LEG:{a}"],
            itemName: "MyItem"
        )
        // `{a}` is `$vars[0]` == 'name' (setTooltipConfig seeds `$vars: ['name']`).
        XCTAssertEqual(showComponentTooltip(s), "LEG:MyItem",
                       "the owning component's `tooltip.formatter` must be found through the cascade "
                       + "(this is the `ecModel.getComponent(ecData.componentMainType, ecData.componentIndex)` layer)")
    }

    // ------------------------------------------------------------------------
    // (4) The config's OWN option (cascade layer 1) outranks the component's.
    // ------------------------------------------------------------------------
    func testItemTooltipOptionOutranksComponentOption() {
        let s = stampComponentItem(
            legendTooltip: ["show": true, "formatter": "LEG:{a}"],
            itemName: "MyItem",
            itemTooltipOption: ["formatter": "ITEM:{a}"] as [String: Any]
        )
        XCTAssertEqual(showComponentTooltip(s), "ITEM:MyItem",
                       "the element's own tooltipConfig option is the TOP cascade layer")
    }

    // The `String` shorthand for `itemTooltipOption` (upstream: "In each data item tooltip can be
    //   simply write: tooltip: 'Something you need to know'").
    func testItemTooltipOptionStringShorthandIsAFixedFormatter() {
        let s = stampComponentItem(
            legendTooltip: ["show": true],
            itemName: "MyItem",
            itemTooltipOption: "JUST TEXT"
        )
        XCTAssertEqual(showComponentTooltip(s), "JUST TEXT",
                       "a STRING itemTooltipOption is the fixed formatter for the item")
    }

    // ------------------------------------------------------------------------
    // (5) formatterParams — the `formatterParamsExtra` keys are appended to `$vars`, so they are
    //     addressable as `{b}`, `{c}`, … in a STRING formatter (this is what toolbox's `title` and
    //     matrix's `xyLocator` rely on).
    // ------------------------------------------------------------------------
    func testStringFormatterSeesFormatterParamsExtraThroughVars() {
        let s = stampComponentItem(
            legendTooltip: ["show": true],
            itemName: "MyItem",
            itemTooltipOption: ["formatter": "{a}|{b}"] as [String: Any],
            formatterParamsExtra: ["title": "TITLE!"]
        )
        XCTAssertEqual(showComponentTooltip(s), "MyItem|TITLE!",
                       "`$vars` is ['name', 'title'], so {a} is the item name and {b} the extra param")
    }

    // ------------------------------------------------------------------------
    // (6) A FUNCTION formatter receives the component's `formatterParams`, NOT a CallbackDataParams.
    //     (Upstream passes `clone(subTooltipModel.get('formatterParams'))` straight to the formatter.)
    // ------------------------------------------------------------------------
    func testFunctionFormatterReceivesComponentItemFormatterParams() {
        var seen: ComponentItemTooltipLabelFormatterParams?
        let formatter: (ComponentItemTooltipLabelFormatterParams) -> String = { params in
            seen = params
            return "FN>>" + params.componentType + ":" + params.name
        }
        let s = stampComponentItem(
            legendTooltip: ["show": true],
            itemName: "MyItem",
            itemTooltipOption: ["formatter": formatter] as [String: Any],
            formatterParamsExtra: ["title": "TITLE!"]
        )
        XCTAssertEqual(showComponentTooltip(s), "FN>>legend:MyItem",
                       "the function formatter's return value must BE the component tooltip content")
        XCTAssertEqual(seen?.componentType, "legend",
                       "formatterParams.componentType is the owning component's mainType")
        XCTAssertEqual(seen?.name, "MyItem")
        XCTAssertEqual(seen?.vars, ["name", "title"],
                       "formatterParamsExtra keys are appended to $vars, in insertion order")
        XCTAssertEqual(seen?.other["title"] as? String, "TITLE!")
        XCTAssertEqual(seen?.other["legendIndex"] as? Double, 0,
                       "setTooltipConfig stamps `<mainType>Index` onto the params")
    }

    // (6b) The formatter lands on `CommonTooltipOption<Any>` (`ecData.tooltipConfig.option.common`),
    //   whose own PORT-NOTE tells a user to spell the closure `TooltipFormatterCallback<FormatterParams>`
    //   — i.e. at `Any` here. Swift dynamic casts between function types are EXACT, so that documented
    //   spelling must be accepted too or the formatter is silently ignored.
    func testFunctionFormatterSpelledAtAnyIsAlsoAccepted() {
        let formatter: (Any) -> String = { params in
            guard let p = params as? ComponentItemTooltipLabelFormatterParams else { return "WRONG-TYPE" }
            return "ANY>>" + p.name
        }
        let s = stampComponentItem(
            legendTooltip: ["show": true],
            itemName: "MyItem",
            itemTooltipOption: ["formatter": formatter] as [String: Any]
        )
        XCTAssertEqual(showComponentTooltip(s), "ANY>>MyItem",
                       "a formatter spelled at the option's own generic parameter (`Any`) must not be dropped")
    }

    func testAsyncArityFunctionFormatterSpelledAtAnyIsAlsoAccepted() {
        let formatter: TooltipFormatterCallback<Any> = { params, _, _ in
            guard let p = params as? ComponentItemTooltipLabelFormatterParams else { return "WRONG-TYPE" }
            return "ASYNC>>" + p.name
        }
        let s = stampComponentItem(
            legendTooltip: ["show": true],
            itemName: "MyItem",
            itemTooltipOption: ["formatter": formatter] as [String: Any]
        )
        XCTAssertEqual(showComponentTooltip(s), "ASYNC>>MyItem")
    }
}
