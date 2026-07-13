// Regression: toggling a legend item on a STACKED chart must re-run the stack calculation on the
// remaining (still-selected) series, so the y-axis extent shrinks and the surviving bands reflow.
//
// Root cause this guards: the data-processor stage order. Upstream runs legendFilter (SERIES_FILTER
// 800) BEFORE dataStack (DATASTACK 900) — dataStack.ts itself notes "Should be executed after series
// is filtered". If dataStack runs first, it stacks EVERY series (incl. the about-to-be-hidden one),
// and legendFilter merely drops that series from the render set afterwards: the survivors keep their
// stale stackResult (still stacked over the hidden series), so the axis never rescales and the chart
// "doesn't re-layout" after a legend click.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class StackedLegendRelayoutTests: XCTestCase {

    /// The niced value-axis max (data extent, not pixels) of the y-axis the first visible series sits on.
    private func yScaleMax(_ ec: ECharts) -> Double {
        var maxVal = Double.nan
        ec.getModel()!.eachSeries { s, _ in
            if maxVal.isNaN, let c = s.coordinateSystem as? Cartesian2D,
               let yAxis = c.getAxis("y") {
                maxVal = yAxis.scale.getExtent()[1]
            }
        }
        return maxVal
    }

    func testHidingBottomStackedSeriesRescalesYAxis() {
        let ec = ECharts(width: 600, height: 400)
        ec.setOption([
            "legend": ["data": ["Base", "Top"]] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "Base", "type": "line", "stack": "Total", "areaStyle": [:] as [String: Any],
                 "data": [500.0, 500.0, 500.0]] as [String: Any],
                ["name": "Top", "type": "line", "stack": "Total", "areaStyle": [:] as [String: Any],
                 "data": [100.0, 100.0, 100.0]] as [String: Any]
            ]
        ])

        // Both visible: stack tops out at Base+Top = 600 → axis max ≈ 600.
        let maxBefore = yScaleMax(ec)
        XCTAssertGreaterThan(maxBefore, 550, "with both series the stacked max is ~600 (got \(maxBefore))")

        // Hide the BOTTOM series. "Top" must now restack onto nothing (its own value 100), so the
        // y-axis extent must collapse to ~100.
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "Base"
        ec.dispatchAction(off)

        let maxAfter = yScaleMax(ec)
        XCTAssertLessThan(maxAfter, 300,
            "hiding the bottom stacked series must re-run dataStack on the survivor and shrink the "
            + "y-axis extent to ~100 (got \(maxAfter)); a stale ~600 means dataStack ran before legendFilter")
    }

    // The exact user-reported shape: a multi-series stacked AREA chart; clicking a MIDDLE legend item
    // hides that band and the bands ABOVE it must drop down to close the gap (the total shrinks).
    func testHidingMiddleStackedSeriesReflowsBandsAbove() {
        let ec = ECharts(width: 700, height: 440)
        ec.setOption([
            "legend": ["data": ["A", "B", "C"]] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false,
                      "data": ["Mon", "Tue", "Wed"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "A", "type": "line", "stack": "Total", "areaStyle": [:] as [String: Any],
                 "data": [100.0, 100.0, 100.0]] as [String: Any],
                ["name": "B", "type": "line", "stack": "Total", "areaStyle": [:] as [String: Any],
                 "data": [500.0, 500.0, 500.0]] as [String: Any],   // the big MIDDLE band
                ["name": "C", "type": "line", "stack": "Total", "areaStyle": [:] as [String: Any],
                 "data": [100.0, 100.0, 100.0]] as [String: Any]
            ]
        ])

        // A + B + C = 700 stacked.
        XCTAssertGreaterThan(yScaleMax(ec), 650, "full stack ≈ 700")

        // Hide the middle band B. A + C = 200 remain; C must restack onto A (not onto the hidden B),
        // so the axis extent must collapse from ~700 to ~200. A stale ~700 = the bug (C floats over the
        // now-invisible B, nothing re-layouts).
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "B"
        ec.dispatchAction(off)
        let maxAfter = yScaleMax(ec)
        XCTAssertLessThan(maxAfter, 350,
            "hiding the MIDDLE band must reflow the band above it and shrink the axis to ~200 "
            + "(got \(maxAfter))")

        // Toggle B back on → fully restored to ~700 (idempotent restore path).
        var on = Payload(type: "legendToggleSelect"); on.other["name"] = "B"
        ec.dispatchAction(on)
        XCTAssertGreaterThan(yScaleMax(ec), 650, "toggling B back on restores the full ~700 stack")
    }
}
