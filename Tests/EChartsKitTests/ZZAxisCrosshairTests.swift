// Phase 36 regression test — the visual axisPointer CROSSHAIR (a vertical Line) actually APPEARS on
// hover at the hovered category's x-pixel, proven HEADLESSLY through the REAL pointer → globalListener →
// axisTrigger → axisPointer-model status/value → CartesianAxisPointer.render chain.
//
//     EChartsView._injectPointerForTest("mousemove", x, y)
//       -> zr.handler.mousemove(ZRRawEvent)                 (ZRenderKit Handler)
//       -> globalListener's mousemove listener (EChartsView._bindAxisPointerListeners)
//       -> axisTrigger(...)  -> updateModelActually writes axisPointerModel.status="show"/value
//       -> EChartsView._updateAxisPointers(ecModel)
//       -> CartesianAxisPointer.render(...) builds a Line crosshair Group on the LIVE zr
//
// It does NOT call render directly — the crosshair MUST be produced by the injected pointer travelling
// through the live Handler and the axisTrigger data core. A mousemove far off the grid then proves the
// crosshair is HIDDEN (status="hide" → group.hide()).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZAxisCrosshairTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(ScatterSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    private func makeAxisBarView() -> EChartsView {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": ["trigger": "axis"] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        return view
    }

    // Every VISIBLE Line currently in view.zr (getDisplayList excludes elements under a hidden/ignored
    // group), i.e. the flattened display list — the crosshair Line is a leaf of the pointer Group that
    // BaseAxisPointer adds to the live zr.
    private func visibleLines(in view: EChartsView) -> [Line] {
        var out: [Line] = []
        for el in view.zr.storage.getDisplayList(true) {
            if let l = el as? Line, !l.ignore { out.append(l) }
        }
        return out
    }

    // A vertical crosshair Line at x ≈ bx spanning the grid's y-range (top 20 .. bottom 220).
    private func crosshairLine(in view: EChartsView, atX bx: Double) -> Line? {
        return visibleLines(in: view).first { l in
            guard let s = l.shape as? LineShape else { return false }
            let vertical = abs(s.x1 - s.x2) < 0.6           // x1 ≈ x2 → vertical
            let atBx = abs(s.x1 - bx) <= 1.0                // at the hovered category's x-pixel
            let yLo = Swift.min(s.y1, s.y2)
            let yHi = Swift.max(s.y1, s.y2)
            let spansGrid = yLo <= 30.0 && yHi >= 210.0     // spans the grid (top 20, bottom 220)
            return vertical && atBx && spansGrid
        }
    }

    func testAxisHoverShowsCrosshairLine() {
        let view = makeAxisBarView()

        // Grab bar 1's ("B") rendered Rect to compute its center x.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bar1El = data.getItemGraphicEl(1), let bar1 = bar1El as? Rect else {
            XCTFail("bar render must have populated a Rect element for data index 1 ('B')"); return
        }
        let s = bar1.shape as! RectShape
        let bx = s.x + s.width / 2       // x-pixel of category "B"
        let gy: Double = 120.0           // any y inside the grid (top 20, height 200)

        // Force the zr storage to flatten the echarts display list so `findHover`/containPoint work.
        _ = view.zr.storage.getDisplayList(true)

        // Precondition: no crosshair before any hover.
        XCTAssertNil(crosshairLine(in: view, atX: bx),
                     "no crosshair Line should exist before any hover")

        // ---- (1) Inject a mousemove at category "B" → the vertical crosshair Line must APPEAR. ----
        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)

        guard let line = crosshairLine(in: view, atX: bx) else {
            let lines = visibleLines(in: view).compactMap { ($0.shape as? LineShape).map {
                "(\($0.x1),\($0.y1))->(\($0.x2),\($0.y2))" } }
            XCTFail("hovering category B must draw a vertical crosshair Line at x≈\(bx); "
                    + "visible lines: \(lines)"); return
        }
        let ls = line.shape as! LineShape
        XCTAssertEqual(ls.x1, bx, accuracy: 1.0, "crosshair x1 must sit at category B's x-pixel")
        XCTAssertEqual(ls.x2, bx, accuracy: 1.0, "crosshair x2 must sit at category B's x-pixel")
        XCTAssertEqual(abs(ls.x1 - ls.x2), 0.0, accuracy: 0.6, "the crosshair must be vertical (x1≈x2)")

        // ---- (2) Inject a mousemove far OFF the grid → the crosshair must HIDE. ----
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)

        XCTAssertNil(crosshairLine(in: view, atX: bx),
                     "moving the pointer off the grid must hide the crosshair Line (status='hide')")
    }

    // Regression for the UPDATE path (`BaseAxisPointer.updatePointerEl`), which the test above never
    // reaches: the first hover BUILDS the pointer group, every later hover REUSES it and only re-applies
    // `{shape}` through `updateProps` — which is memoized by `propsEqual` against `_lastProps`. A memo or
    // shape-merge defect there would freeze the crosshair at the first hovered category while the
    // appear/hide test stayed green.
    func testCrosshairFollowsHoverToNextCategory() {
        let view = makeAxisBarView()

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        guard let bEl = data.getItemGraphicEl(1) as? Rect,
              let cEl = data.getItemGraphicEl(2) as? Rect else {
            XCTFail("bar render must have populated Rect elements for data indices 1 ('B') and 2 ('C')")
            return
        }
        let bShape = bEl.shape as! RectShape
        let cShape = cEl.shape as! RectShape
        let bx = bShape.x + bShape.width / 2
        let cx = cShape.x + cShape.width / 2
        let gy: Double = 120.0

        _ = view.zr.storage.getDisplayList(true)

        // (1) Hover B — builds the pointer group.
        view._injectPointerForTest(type: "mousemove", zrX: bx, zrY: gy)
        XCTAssertNotNil(crosshairLine(in: view, atX: bx), "hovering B must draw the crosshair at B")

        // (2) Hover C — REUSES the group and goes through updatePointerEl; the Line must MOVE to C.
        view._injectPointerForTest(type: "mousemove", zrX: cx, zrY: gy)

        guard let moved = crosshairLine(in: view, atX: cx) else {
            let lines = visibleLines(in: view).compactMap { ($0.shape as? LineShape).map {
                "(\($0.x1),\($0.y1))->(\($0.x2),\($0.y2))" } }
            XCTFail("hovering category C must move the crosshair to x≈\(cx) (was \(bx)); "
                    + "visible lines: \(lines)"); return
        }
        let ms = moved.shape as! LineShape
        XCTAssertEqual(ms.x1, cx, accuracy: 1.0, "the reused crosshair must re-apply its shape at C's x")
        XCTAssertNil(crosshairLine(in: view, atX: bx),
                     "the crosshair must not remain at B's x-pixel after hovering C")
    }

    func testCrossAxisPointerRunsWhenTooltipTriggerIsNone() {
        let view = EChartsView(width: 400, height: 300)
        view.setOption([
            "tooltip": [
                "trigger": "none",
                "axisPointer": ["type": "cross"] as [String: Any]
            ] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
        ])
        let bar = view.ec.getModel()!.getSeriesByIndex(0)!.getData().getItemGraphicEl(1) as! Rect
        let shape = bar.shape as! RectShape
        let x = shape.x + shape.width / 2
        _ = view.zr.storage.getDisplayList(true)

        view._injectPointerForTest(type: "mousemove", zrX: x, zrY: 120)

        XCTAssertNotNil(crosshairLine(in: view, atX: x),
                        "axisPointer type:'cross' must react even when tooltip.trigger is 'none'")
        XCTAssertFalse(view.tooltipView?.isShown() ?? false,
                       "cross-only pointer must not invent a floating axis tooltip")
    }

    func testPolarCrossAxisPointerRendersAngleLineAndRadiusCircle() {
        let view = EChartsView(width: 420, height: 360)
        view.setOption([
            "tooltip": [
                "trigger": "axis",
                "axisPointer": ["type": "cross"] as [String: Any]
            ] as [String: Any],
            "polar": [
                "center": ["50%", "54%"],
                "radius": "70%"
            ] as [String: Any],
            "angleAxis": ["type": "value", "startAngle": 0.0] as [String: Any],
            "radiusAxis": ["type": "value", "min": 0.0, "max": 10.0] as [String: Any],
            "series": [[
                "type": "scatter",
                "coordinateSystem": "polar",
                "data": [[2.0, 0.0], [4.0, 90.0], [6.0, 180.0], [8.0, 270.0]]
            ] as [String: Any]]
        ])

        let polar = view.ec.getModel()!.getSeriesByIndex(0)!.coordinateSystem as! Polar
        let hoverPoint = polar.coordToPoint([
            polar.getRadiusAxis().dataToCoord(4.0),
            polar.getAngleAxis().dataToCoord(90.0)
        ])
        let beforeHover = Set(view.zr.storage.getDisplayList(true).map(ObjectIdentifier.init))
        view._injectPointerForTest(type: "mousemove", zrX: hoverPoint[0], zrY: hoverPoint[1])

        let displayList = view.zr.storage.getDisplayList(true)
        let axisStates: [String] = ((view.ec.getModel()!.getComponent("axisPointer") as? AxisPointerModel)?
            .coordSysAxesInfo as? CollectionResult)?.axesInfo.values.map {
                "\($0.axis.dim):\(String(describing: $0.axisPointerModel.get("status"))):\(String(describing: $0.axisPointerModel.get("value"))):series=\($0.seriesModels.count):trigger=\($0.triggerTooltip)"
            } ?? []
        let pointerLines = displayList.compactMap { $0 as? Line }.filter { line in
            guard !beforeHover.contains(ObjectIdentifier(line)) else { return false }
            guard let shape = line.shape as? LineShape else { return false }
            let dx = shape.x2 - shape.x1
            let dy = shape.y2 - shape.y1
            let length = hypot(dx, dy)
            guard length > 20 else { return false }
            let cross = abs((polar.cx - shape.x1) * dy - (polar.cy - shape.y1) * dx)
            return cross / length < 1.0
        }
        let pointerCircles = displayList.compactMap { $0 as? ZRenderKit.Circle }.filter { circle in
            guard !beforeHover.contains(ObjectIdentifier(circle)) else { return false }
            guard let shape = circle.shape as? CircleShape else { return false }
            return abs(shape.cx - polar.cx) < 0.5
                && abs(shape.cy - polar.cy) < 0.5
                && shape.r > 0
                && shape.r < polar.getRadiusAxis().getExtent().max()!
        }

        XCTAssertFalse(pointerLines.isEmpty,
                       "polar angle axis pointer must render the upstream center-spanning Line; states=\(axisStates), hover=\(hoverPoint), center=[\(polar.cx),\(polar.cy)]")
        XCTAssertFalse(pointerCircles.isEmpty,
                       "polar radius axis pointer must render the upstream concentric Circle")
        if let pointerLine = pointerLines.first {
            guard case let .string(fill)? = pointerLine.pathStyle.fill else {
                XCTFail("the upstream polar line pointer must carry an explicit fill:'none'")
                return
            }
            XCTAssertEqual(fill, "none")
        }
        if let pointerCircle = pointerCircles.first {
            guard case let .string(fill)? = pointerCircle.pathStyle.fill else {
                XCTFail("the upstream polar radius pointer must carry an explicit fill:'none'")
                return
            }
            XCTAssertEqual(fill, "none",
                           "a radius-axis pointer is an outlined circle, never a default black disk")
        }
        XCTAssertTrue(view.tooltipView?.isShown() ?? false,
                      "the same real polar mousemove must also show the axis tooltip; states=\(axisStates)")

        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        let afterLeave = view.zr.storage.getDisplayList(true)
        if let pointerLine = pointerLines.first {
            XCTAssertFalse(afterLeave.contains { $0 === pointerLine },
                           "moving outside the polar area must hide the angle pointer group")
        }
        if let pointerCircle = pointerCircles.first {
            XCTAssertFalse(afterLeave.contains { $0 === pointerCircle },
                           "moving outside the polar area must hide the radius pointer group")
        }
    }
}
