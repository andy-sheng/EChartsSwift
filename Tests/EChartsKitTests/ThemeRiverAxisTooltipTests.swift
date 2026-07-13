// Regression: a themeRiver with `tooltip: { trigger: 'axis' }` must show the combined axis tooltip on
// hover — the same end-to-end pointer → globalListener → axisTrigger → showTip → TooltipView chain the
// cartesian ZZAxisTooltipTests proves, but on the SINGLE coordinate system.
//
// Two gaps used to break this (native pane showed NO tooltip while echarts.js did):
//   1. modelHelper.collectSeriesInfo only associated `Cartesian2D` series with their axes; a themeRiver
//      (Single coord sys) was never added to the singleAxis' `seriesModels`, so axisTrigger had no series
//      to snap → empty dataByCoordSys → no tooltip.
//   2. ThemeRiverSeries.formatTooltip returned nil, so even once associated each row would be blank.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ThemeRiverAxisTooltipTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(ThemeRiverSeriesModel.self)
        ComponentModel.registerClass(TooltipModel.self)
        ComponentModel.registerClass(AxisPointerModel.self)
    }

    func testThemeRiverAxisHoverShowsCombinedTooltip() {
        let view = EChartsView(width: 520, height: 380)
        view.setOption([
            // trigger:"axis" — ONE combined tooltip listing every layer's value at the hovered time.
            "tooltip": ["trigger": "axis"] as [String: Any],
            "singleAxis": ["type": "value", "left": "10%", "right": "10%",
                           "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "themeRiver", "data": [
                [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                [3.0, 18.0, "Alpha"], [4.0, 14.0, "Alpha"],
                [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"],
                [3.0,  9.0, "Beta"],  [4.0, 13.0, "Beta"],
                [0.0,  5.0, "Gamma"], [1.0,  9.0, "Gamma"], [2.0,  7.0, "Gamma"],
                [3.0,  4.0, "Gamma"], [4.0, 10.0, "Gamma"]
            ]] as [String: Any]]
        ])

        // Hover at time value 2.0 (a data point every layer shares), vertically centered in the coord rect.
        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        guard let single = series.coordinateSystem as? Single else {
            XCTFail("themeRiver series must sit on a Single coordinate system"); return
        }
        let rect = single.getRect()
        let px = single.dataToPoint(2.0)[0]
        let py = rect.y + rect.height / 2

        _ = view.zr.storage.getDisplayList(true)
        XCTAssertNil(view.tooltipView, "no tooltip view should exist before any hover")

        view._injectPointerForTest(type: "mousemove", zrX: px, zrY: py)

        guard let tv = view.tooltipView else {
            XCTFail("hovering a themeRiver axis chart must lazily create the TooltipView"); return
        }
        XCTAssertTrue(tv.isShown(), "the combined axis tooltip must be shown after hovering the river")

        let content = tv.contentEl?.textStyle?.text ?? ""
        // At time 2 every layer is listed with its value: Alpha 12, Beta 11, Gamma 7.
        XCTAssertTrue(content.contains("Alpha"), "axis tooltip must list layer 'Alpha' — got:\n\(content)")
        XCTAssertTrue(content.contains("Beta"),  "axis tooltip must list layer 'Beta' — got:\n\(content)")
        XCTAssertTrue(content.contains("Gamma"), "axis tooltip must list layer 'Gamma' — got:\n\(content)")
        XCTAssertTrue(content.contains("12"),    "axis tooltip must show Alpha's value 12 — got:\n\(content)")
        XCTAssertTrue(content.contains("11"),    "axis tooltip must show Beta's value 11 — got:\n\(content)")

        // Move far off the coordinate system → the tooltip must hide (hideTip).
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(tv.isShown(), "moving the pointer off the coord must hide the axis tooltip")
    }
}
