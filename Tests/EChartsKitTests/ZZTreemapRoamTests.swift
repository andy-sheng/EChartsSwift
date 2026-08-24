// L3 Roam — TREEMAP pan/zoom end-to-end. Builds a treemap through EChartsView, injects a real drag /
// wheel through the live Handler, and asserts the treemap's CONTAINER GROUP actually SHIFTS (pan) and
// SCALES (zoom). Treemap is not on a coord system, so the roam is a transform on the container group
// (DEVIATION from upstream's rootRect re-layout — see roamHelperViewGroup.swift).
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController uniform fan-out -> 'pan' -> updateTreemapRoamControllerSimply
//       -> ec.dispatchAction({type:'treemapRoam', dx, dy}) -> treemapRoam action accumulates the pan
//          -> full update() re-renders -> TreemapView re-applies the state to _containerGroup (shifted).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZTreemapRoamTests: XCTestCase {

    /// A small 2-level treemap. `roam` defaults to `true` for treemap; the inert test overrides it false.
    private func makeTreemapView(roam: Any? = nil) -> EChartsView {
        let view = EChartsView(width: 400, height: 400)
        var series: [String: Any] = [
            "type": "treemap", "left": "5%", "top": 20.0, "width": "90%", "height": 320.0,
            "data": [
                ["name": "nodeA", "value": 10.0, "children": [
                    ["name": "nodeA1", "value": 4.0],
                    ["name": "nodeA2", "value": 6.0]
                ]] as [String: Any],
                ["name": "nodeB", "value": 20.0, "children": [
                    ["name": "nodeB1", "value": 5.0],
                    ["name": "nodeB2", "value": 8.0]
                ]] as [String: Any]
            ]
        ]
        if let roam = roam { series["roam"] = roam }
        view.setOption(["series": [series]])
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    private func treemapSeries(_ view: EChartsView) -> TreemapSeriesModel? {
        return view.ec.getModel()?.getSeriesByIndex(0) as? TreemapSeriesModel
    }

    /// The treemap's live container group (carries the roam transform: position + scale).
    private func treemapGroup(_ view: EChartsView) -> Group? {
        guard let sm = treemapSeries(view),
              let v = view.ec.api.getViewOfSeriesModel(sm) as? TreemapView else { return nil }
        return v._containerGroupForTest
    }

    private func treemapGroup(_ view: EChartsView, seriesIndex: Int) -> Group? {
        guard let sm = view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)) as? TreemapSeriesModel,
              let v = view.ec.api.getViewOfSeriesModel(sm) as? TreemapView else { return nil }
        return v._containerGroupForTest
    }

    private func legendSwatchFill(_ view: EChartsView, name: String) -> String? {
        for legendView in view.ec._componentsViews.compactMap({ $0 as? LegendView }) {
            for item in legendView.getContentGroup().children().compactMap({ $0 as? Group }) {
                var matches = false
                item.traverse { element in
                    if let text = element as? ZRText, text.textStyle?.text == name { matches = true }
                    return false
                }
                guard matches else { continue }
                for path in item.children().compactMap({ $0 as? Path }) {
                    if case let .string(fill)? = path.pathStyle.fill { return fill }
                }
            }
        }
        return nil
    }

    private func breadcrumbTail(_ view: EChartsView) -> String? {
        view.zr.storage.getDisplayList(true).compactMap { displayable -> (Double, String)? in
            guard let eventData = innerStore.getECData(displayable).eventData,
                  (eventData["selfType"] as? String) == "breadcrumb",
                  let nodeData = eventData["nodeData"] as? [String: Any],
                  let name = nodeData["name"] as? String else { return nil }
            return (displayable.getBoundingRect()?.x ?? -.infinity, name)
        }.max(by: { $0.0 < $1.0 })?.1
    }

    // A drag over the treemap must shift its container group by exactly the drag delta (pan).
    func testDragPansGroup() {
        let view = makeTreemapView()   // roam defaults true for treemap.
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeX = g.x, beforeY = g.y, beforeScale = g.scaleX

        let cx = 200.0, cy = 200.0
        let dx = 35.0, dy = -25.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)

        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist after pan") }
        print("TREEMAP-ROAM pan: group (\(beforeX),\(beforeY)) -> (\(after.x),\(after.y))")
        XCTAssertEqual(after.x - beforeX, dx, accuracy: 0.5, "group must shift by dx")
        XCTAssertEqual(after.y - beforeY, dy, accuracy: 0.5, "group must shift by dy")
        XCTAssertEqual(after.scaleX, beforeScale, accuracy: 1e-6, "a pure pan must not scale")
    }

    // A wheel over the treemap must scale its container group by the zoom factor (delta 3 → factor 1.2).
    func testWheelZoomsGroup() {
        let view = makeTreemapView()
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeScale = g.scaleX
        XCTAssertEqual(beforeScale, 1, accuracy: 1e-6, "the untouched treemap group must be unscaled")

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 200)

        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist after zoom") }
        print("TREEMAP-ROAM zoom: scale \(beforeScale) -> \(after.scaleX)")
        XCTAssertEqual(after.scaleX, 1.2, accuracy: 0.02, "wheel-in scales the group by ~1.2x")
        XCTAssertEqual(after.scaleY, 1.2, accuracy: 0.02, "scaleY must match scaleX (uniform zoom)")
    }

    // A treemap with `roam:false` must be inert to a drag (group does not move).
    func testNoRoamOptionIsInert() {
        let view = makeTreemapView(roam: false)
        guard let g = treemapGroup(view) else { return XCTFail("treemap container group must exist after render") }
        let beforeX = g.x, beforeY = g.y
        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mousemove", zrX: 260, zrY: 240)
        view._injectPointerForTest(type: "mouseup", zrX: 260, zrY: 240)
        guard let after = treemapGroup(view) else { return XCTFail("treemap container group must still exist") }
        XCTAssertEqual(after.x, beforeX, accuracy: 1e-6, "roam:false treemap must not pan (x)")
        XCTAssertEqual(after.y, beforeY, accuracy: 1e-6, "roam:false treemap must not pan (y)")
    }

    func testNamedTreemapBreadcrumbTailTracksViewportCenter() throws {
        let view = EChartsView(width: 400, height: 400)
        view.setOption(["series": [[
            "type": "treemap", "name": "Named Tree",
            "left": 20.0, "top": 20.0, "width": 360.0, "height": 320.0,
            "data": [
                ["name": "left", "value": 10.0],
                ["name": "right", "value": 30.0, "children": [
                    ["name": "right-a", "value": 20.0],
                    ["name": "right-b", "value": 10.0]
                ]] as [String: Any]
            ]
        ] as [String: Any]]])
        _ = view.zr.storage.getDisplayList(true)

        XCTAssertEqual(breadcrumbTail(view), "Named Tree",
                       "the first frame must use the named view root as the stable breadcrumb tail")

        let series = try XCTUnwrap(treemapSeries(view))
        let treemapView = try XCTUnwrap(view.ec.api.getViewOfSeriesModel(series) as? TreemapView)
        let preRoamCenterNode = try XCTUnwrap(treemapView.findTarget(200, 200)?.node)
        XCTAssertFalse(preRoamCenterNode.name.isEmpty,
                       "the pre-roam viewport center must resolve to a concrete tile")

        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mousemove", zrX: 230, zrY: 220)
        view._injectPointerForTest(type: "mouseup", zrX: 230, zrY: 220)
        _ = view.zr.storage.getDisplayList(true)

        XCTAssertEqual(breadcrumbTail(view), preRoamCenterNode.name,
                       "roam render breadcrumbs must use the prior display-list center like the browser")

        view._injectPointerForTest(type: "mousedown", zrX: 230, zrY: 220)
        view._injectPointerForTest(type: "mousemove", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mouseup", zrX: 200, zrY: 200)

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 200)
        view._injectWheelForTest(zrDelta: -3, zrX: 200, zrY: 200)
        _ = view.zr.storage.getDisplayList(true)
        XCTAssertEqual(breadcrumbTail(view), "Named Tree",
                       "an inverse zoom that restores identity must clear the transient deep breadcrumb")
    }

    func testLegendSwitchRebindsRoamControllerToVisibleTreemapSeries() throws {
        let view = EChartsView(width: 500, height: 400)
        view.setOption([
            "legend": [
                "selectedMode": "single",
                "selected": ["First": true, "Second": false]
            ] as [String: Any],
            "series": [
                [
                    "type": "treemap", "name": "First",
                    "left": 20.0, "top": 50.0, "width": 460.0, "height": 320.0,
                    "data": [["name": "first-node", "value": 10.0]]
                ] as [String: Any],
                [
                    "type": "treemap", "name": "Second",
                    "left": 20.0, "top": 50.0, "width": 460.0, "height": 320.0,
                    "data": [["name": "second-node", "value": 20.0]]
                ] as [String: Any]
            ]
        ])
        _ = view.zr.storage.getDisplayList(true)

        let firstBefore = try XCTUnwrap(treemapGroup(view, seriesIndex: 0)).x
        XCTAssertNotNil(view._injectLegendClickForTest(name: "Second"),
                        "the second legend item must be clicked through the real hit-tested path")
        _ = view.zr.storage.getDisplayList(true)
        XCTAssertEqual(legendSwatchFill(view, name: "Second"), "#b6d634",
                       "the newly active legend swatch must retain the second series palette colour")
        XCTAssertEqual(breadcrumbTail(view), "Second",
                       "switching to an untouched named treemap must show its root breadcrumb")
        let secondBefore = try XCTUnwrap(treemapGroup(view, seriesIndex: 1)).x

        view._injectPointerForTest(type: "mousedown", zrX: 250, zrY: 220)
        view._injectPointerForTest(type: "mousemove", zrX: 285, zrY: 200)
        view._injectPointerForTest(type: "mouseup", zrX: 285, zrY: 200)

        XCTAssertEqual(try XCTUnwrap(treemapGroup(view, seriesIndex: 0)).x, firstBefore,
                       accuracy: 1e-6, "the hidden first series must stay untouched")
        XCTAssertEqual(try XCTUnwrap(treemapGroup(view, seriesIndex: 1)).x - secondBefore, 35,
                       accuracy: 0.5, "roam must follow the newly visible second series")
    }
}
