// INTERACTION TEST for the parallel-axis BRUSH (axisAreaSelect) — component/axis/parallelAxisAction.swift +
// coord/parallel/Parallel.eachActiveState/hasAxisBrushed + chart/parallel/parallelVisual dimming.
//
// Dispatching `axisAreaSelect` with a value interval on ONE parallel axis sets that ParallelAxisModel's
// activeIntervals; the full update() then re-runs `parallelVisual`, which walks `Parallel.eachActiveState`
// (now non-trivial): each data line whose value on the brushed axis is INSIDE the interval resolves to
// 'active' (activeOpacity = 1) and each line OUTSIDE resolves to 'inactive' (inactiveOpacity = 0.05, i.e.
// DIMMED). With no selection every line is 'normal' (lineStyle.opacity = 0.45).
//
// Named ZZ… so it registers after the base render tests (deterministic ordering; no class re-registration).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ParallelAxisBrushTests: XCTestCase {

    private func makeChart() -> ECharts {
        let ec = ECharts(width: 520, height: 380)
        // 4 value axes × 3 data lines. Axis 0 (dim 0) values: line0=12, line1=24, line2=6.
        ec.setOption([
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any],
                ["dim": 3, "name": "Score"]  as [String: Any]
            ],
            "parallel": ["left": "10%", "right": "12%",
                         "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "parallel",
                        "lineStyle": ["width": 2] as [String: Any],
                        "data": [
                            [12.0, 230.0,  8.0, 90.0],   // line 0 — axis-0 value 12 (inside [10,30])
                            [24.0, 140.0, 15.0, 60.0],   // line 1 — axis-0 value 24 (inside [10,30])
                            [ 6.0, 320.0,  3.0, 75.0]    // line 2 — axis-0 value  6 (OUTSIDE [10,30])
                        ]] as [String: Any]]
        ])
        return ec
    }

    // Read the per-line opacity that `parallelVisual` writes onto the item visual style (this is the value
    //   the ParallelView polyline then paints with — set synchronously by the visual stage, independent of
    //   any enter animation).
    private func itemOpacity(_ ec: ECharts, _ dataIndex: Int) -> Double? {
        let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
        let style = data.getItemVisual(dataIndex, "style") as? [String: Any]
        if let d = style?["opacity"] as? Double { return d }
        if let i = style?["opacity"] as? Int { return Double(i) }
        if let n = style?["opacity"] as? NSNumber { return n.doubleValue }
        return nil
    }

    func testAxisAreaSelectDimsLinesOutsideInterval() {
        let ec = makeChart()

        // BEFORE any selection: no axis brushed → every line is 'normal' → lineStyle.opacity (0.45).
        for i in 0..<3 {
            XCTAssertEqual(itemOpacity(ec, i) ?? -1, 0.45, accuracy: 1e-9,
                "line \(i) must start at the normal lineStyle.opacity (0.45) with no selection")
        }

        // Select the value interval [10, 30] on parallel axis 0 (dim 0 = "Price").
        var p = Payload(type: "axisAreaSelect")
        p.other["parallelAxisIndex"] = 0
        p.other["intervals"] = [[10.0, 30.0]]
        ec.dispatchAction(p)

        // The action populated the axis model's activeIntervals (asc-normalized).
        let axisModel = ec.getModel()!.getComponent("parallelAxis", 0) as! ParallelAxisModel
        XCTAssertEqual(axisModel.activeIntervals.count, 1,
            "axisAreaSelect must set exactly one active interval on the brushed axis")
        XCTAssertEqual(axisModel.activeIntervals[0][0], 10.0, accuracy: 1e-9)
        XCTAssertEqual(axisModel.activeIntervals[0][1], 30.0, accuracy: 1e-9)
        // Only axis 0 is brushed; the other axes stay clear.
        for idx in 1..<4 {
            let other = ec.getModel()!.getComponent("parallelAxis", Double(idx)) as! ParallelAxisModel
            XCTAssertTrue(other.activeIntervals.isEmpty,
                "axis \(idx) must NOT be brushed by an axis-0 axisAreaSelect")
        }

        // getActiveState classification on the brushed axis model.
        XCTAssertEqual(axisModel.getActiveState(12.0), "active",  "12 is inside [10,30]")
        XCTAssertEqual(axisModel.getActiveState(24.0), "active",  "24 is inside [10,30]")
        XCTAssertEqual(axisModel.getActiveState(6.0),  "inactive", "6 is outside [10,30]")

        // AFTER selection: lines 0 & 1 (axis-0 value inside) → activeOpacity (1); line 2 (outside) → DIMMED
        //   to inactiveOpacity (0.05).
        XCTAssertEqual(itemOpacity(ec, 0) ?? -1, 1.0, accuracy: 1e-9,
            "line 0 (axis-0 value 12, inside) stays fully opaque (active)")
        XCTAssertEqual(itemOpacity(ec, 1) ?? -1, 1.0, accuracy: 1e-9,
            "line 1 (axis-0 value 24, inside) stays fully opaque (active)")
        XCTAssertEqual(itemOpacity(ec, 2) ?? -1, 0.05, accuracy: 1e-9,
            "line 2 (axis-0 value 6, OUTSIDE) must be dimmed to inactiveOpacity")

        // The dimming reaches the actual rendered Polyline element (not just the visual store).
        let dimmedEl = ec.getModel()!.getSeriesByIndex(0)!.getData().getItemGraphicEl(2)
        XCTAssertNotNil(dimmedEl, "line 2 must have a rendered Polyline")
        if let pl = dimmedEl as? ZRenderKit.Polyline {
            XCTAssertEqual(pl.pathStyle.opacity ?? -1, 0.05, accuracy: 1e-9,
                "the out-of-interval Polyline element must paint at the dimmed opacity")
        }

        // CLEAR the selection (empty intervals) → every line returns to 'normal' (0.45).
        var clear = Payload(type: "axisAreaSelect")
        clear.other["parallelAxisIndex"] = 0
        clear.other["intervals"] = [[Double]]()
        ec.dispatchAction(clear)

        XCTAssertTrue(axisModel.activeIntervals.isEmpty,
            "clearing with empty intervals must drop the active interval")
        for i in 0..<3 {
            XCTAssertEqual(itemOpacity(ec, i) ?? -1, 0.45, accuracy: 1e-9,
                "line \(i) must return to the normal opacity after clearing the selection")
        }
    }
}
