// L3 Roam — TREEMAP pan/zoom end-to-end. Builds a treemap through EChartsView, injects a real drag /
// wheel through the live Handler, and asserts upstream's rootRect interaction contract: pan dispatches
// `treemapMove`, zoom dispatches `treemapRender`, and treemapLayout persists the changed tree-root layout
// while the container group itself remains unscaled.
//
//     _injectPointerForTest("mousedown"/"mousemove"/"mouseup", ...)   (drag)
//       -> zr Handler -> RoamController -> TreemapView._onPan/_onZoom
//       -> ec.dispatchAction({type:'treemapMove'|'treemapRender', rootRect})
//       -> updateView -> treemapLayoutReset(rootRect) -> tile re-layout.
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

    /// The treemap's live container group stays at the authored layout transform during roam.
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

    private func rootRect(_ view: EChartsView, seriesIndex: Int = 0) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard let series = view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)) as? TreemapSeriesModel,
              let layout = series.getData().tree?.root.getLayout() as? [String: Any],
              let x = (layout["x"] as? NSNumber)?.doubleValue,
              let y = (layout["y"] as? NSNumber)?.doubleValue,
              let width = (layout["width"] as? NSNumber)?.doubleValue,
              let height = (layout["height"] as? NSNumber)?.doubleValue else { return nil }
        return (x, y, width, height)
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

    // Upstream `_onPan` moves rootRect and never transforms/scales the container group.
    func testDragMovesRootRect() throws {
        let view = makeTreemapView()   // roam defaults true for treemap.
        let group = try XCTUnwrap(treemapGroup(view))
        let beforeGroup = (group.x, group.y, group.scaleX, group.scaleY)
        let before = try XCTUnwrap(rootRect(view))

        let cx = 200.0, cy = 200.0
        let dx = 35.0, dy = -25.0
        view._injectPointerForTest(type: "mousedown", zrX: cx, zrY: cy)
        view._injectPointerForTest(type: "mousemove", zrX: cx + dx, zrY: cy + dy)
        view._injectPointerForTest(type: "mouseup", zrX: cx + dx, zrY: cy + dy)

        let after = try XCTUnwrap(rootRect(view))
        XCTAssertEqual(after.x - before.x, dx, accuracy: 0.5)
        XCTAssertEqual(after.y - before.y, dy, accuracy: 0.5)
        XCTAssertEqual(after.width, before.width, accuracy: 1e-6)
        XCTAssertEqual(after.height, before.height, accuracy: 1e-6)
        XCTAssertEqual(group.x, beforeGroup.0, accuracy: 1e-6)
        XCTAssertEqual(group.y, beforeGroup.1, accuracy: 1e-6)
        XCTAssertEqual(group.scaleX, beforeGroup.2, accuracy: 1e-6)
        XCTAssertEqual(group.scaleY, beforeGroup.3, accuracy: 1e-6)
    }

    // Upstream `_onZoom` scales rootRect by the wheel factor around the pointer; text/group scale stays 1.
    func testWheelZoomsRootRect() throws {
        let view = makeTreemapView()
        let group = try XCTUnwrap(treemapGroup(view))
        let before = try XCTUnwrap(rootRect(view))

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 200)

        let after = try XCTUnwrap(rootRect(view))
        XCTAssertEqual(after.width / before.width, 1.2, accuracy: 0.02)
        XCTAssertEqual(after.height / before.height, 1.2, accuracy: 0.02)
        XCTAssertEqual(group.scaleX, 1, accuracy: 1e-6)
        XCTAssertEqual(group.scaleY, 1, accuracy: 1e-6)
    }

    // A treemap with `roam:false` must leave rootRect unchanged.
    func testNoRoamOptionIsInert() throws {
        let view = makeTreemapView(roam: false)
        let before = try XCTUnwrap(rootRect(view))
        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mousemove", zrX: 260, zrY: 240)
        view._injectPointerForTest(type: "mouseup", zrX: 260, zrY: 240)
        let after = try XCTUnwrap(rootRect(view))
        XCTAssertEqual(after.x, before.x, accuracy: 1e-6)
        XCTAssertEqual(after.y, before.y, accuracy: 1e-6)
        XCTAssertEqual(after.width, before.width, accuracy: 1e-6)
        XCTAssertEqual(after.height, before.height, accuracy: 1e-6)
    }

    func testNamedTreemapBreadcrumbUsesTheLastPaintedCenterThroughoutOnePanFrame() throws {
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

        let series = try XCTUnwrap(treemapSeries(view))
        let treemapView = try XCTUnwrap(view.ec.api.getViewOfSeriesModel(series) as? TreemapView)
        let prePanCenter = try XCTUnwrap(treemapView.findTarget(200, 200)?.node.name)
        XCTAssertEqual(breadcrumbTail(view), prePanCenter,
                       "upstream breadcrumb tail starts at the painted viewport-center node")

        view._injectPointerForTest(type: "mousedown", zrX: 200, zrY: 200)
        for fraction in [0.25, 0.5, 0.75, 1.0] {
            view._injectPointerForTest(
                type: "mousemove", zrX: 200 + 30 * fraction, zrY: 200 + 20 * fraction
            )
        }
        view._injectPointerForTest(type: "mouseup", zrX: 230, zrY: 220)

        XCTAssertEqual(
            breadcrumbTail(view), prePanCenter,
            "synchronous moves in one frame must keep Web's last-painted center target"
        )

        view.zr.refreshImmediately(true)
        let pannedCenter = try XCTUnwrap(treemapView.findTarget(200, 200)?.node.name)

        view._injectPointerForTest(type: "mousedown", zrX: 230, zrY: 220)
        view._injectPointerForTest(type: "mousemove", zrX: 200, zrY: 200)
        view._injectPointerForTest(type: "mouseup", zrX: 200, zrY: 200)

        XCTAssertEqual(
            breadcrumbTail(view), pannedCenter,
            "the inverse drag must start from the center target of the newly painted panned frame"
        )

        view._injectWheelForTest(zrDelta: 3, zrX: 200, zrY: 200)
        view._injectWheelForTest(zrDelta: -3, zrX: 200, zrY: 200)
        _ = view.zr.storage.getDisplayList(true)
        // After the inverse interactions and the next zrender frame, both the rendered breadcrumb and
        // an independent hit query settle on the restored center target.
        XCTAssertEqual(breadcrumbTail(view), treemapView.findTarget(200, 200)?.node.name)
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

        XCTAssertNotNil(view._injectLegendClickForTest(name: "Second"),
                        "the second legend item must be clicked through the real hit-tested path")
        _ = view.zr.storage.getDisplayList(true)
        XCTAssertEqual(legendSwatchFill(view, name: "Second"), "#b6d634",
                       "the newly active legend swatch must retain the second series palette colour")
        let secondSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(1) as? TreemapSeriesModel)
        let secondView = try XCTUnwrap(view.ec.api.getViewOfSeriesModel(secondSeries) as? TreemapView)
        XCTAssertEqual(breadcrumbTail(view), secondView.findTarget(250, 220)?.node.name)
        let secondBefore = try XCTUnwrap(rootRect(view, seriesIndex: 1))

        view._injectPointerForTest(type: "mousedown", zrX: 250, zrY: 220)
        view._injectPointerForTest(type: "mousemove", zrX: 285, zrY: 200)
        view._injectPointerForTest(type: "mouseup", zrX: 285, zrY: 200)

        let secondAfter = try XCTUnwrap(rootRect(view, seriesIndex: 1))
        XCTAssertNil(rootRect(view, seriesIndex: 0),
                     "the filtered first series must not receive the visible series roam layout")
        XCTAssertEqual(secondAfter.x - secondBefore.x, 35, accuracy: 0.5,
                       "roam must follow the newly visible second series")
        XCTAssertEqual(secondAfter.y - secondBefore.y, -20, accuracy: 0.5)
    }
}
