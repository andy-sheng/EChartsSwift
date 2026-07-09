// Hover-EMPHASIS regression for the RADAR and PARALLEL verticals.
//
// Both upstream views wire the standard states engine: each data item's element is a highDown
// dispatcher carrying its emphasis/blur/select state styles (RadarView → the per-item Group holding
// the polyline + polygon + vertex symbols; ParallelView → each data Polyline). Proves headlessly
// (no UIView / pointer host) that:
//   (1) the render marks each data element a highDown dispatcher, and
//   (2) `ec.dispatchAction(Payload(type:"highlight"))` (seriesIndex + dataIndexInside) lands the
//       "emphasis" state on the targeted element, isolated to that data index, and `downplay` clears it.
// Mirrors ZZEmphasisTests (bar) round-trip; the click/hover live path uses the SAME dispatcher gate.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZRadarParallelHoverTests: XCTestCase {

    // ---- RADAR: each item Group is a dispatcher; highlight enters emphasis, downplay clears ----
    func testRadarPolygonHoverEntersEmphasis() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption([
            "radar": [
                "center": ["50%", "55%"],
                "radius": "65%",
                "indicator": [
                    ["name": "Sales", "max": 6500.0],
                    ["name": "Administration", "max": 16000.0],
                    ["name": "Information Technology", "max": 30000.0],
                    ["name": "Customer Support", "max": 38000.0],
                    ["name": "Development", "max": 52000.0]
                ]
            ] as [String: Any],
            "series": [[
                "type": "radar",
                "data": [
                    ["name": "Allocated Budget",
                     "value": [4200.0, 3000.0, 20000.0, 35000.0, 50000.0],
                     "areaStyle": ["opacity": 0.3] as [String: Any]] as [String: Any],
                    ["name": "Actual Spending",
                     "value": [5000.0, 14000.0, 28000.0, 26000.0, 42000.0],
                     "areaStyle": ["opacity": 0.3] as [String: Any]] as [String: Any]
                ]
            ] as [String: Any]]
        ])

        let series = ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        let target = data.getItemGraphicEl(0)
        let other = data.getItemGraphicEl(1)
        XCTAssertNotNil(target, "radar render must populate an item Group for data index 0")
        XCTAssertNotNil(other, "radar render must populate an item Group for data index 1")

        XCTAssertTrue(states.isHighDownDispatcher(target!),
                      "RadarView must mark each item Group a highDown dispatcher")
        XCTAssertTrue(target!.currentStates.isEmpty, "no emphasis before highlight")

        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0
        hp.other["dataIndexInside"] = 0
        ec.dispatchAction(hp)

        XCTAssertTrue(target!.currentStates.contains("emphasis"),
                      "highlight must enter emphasis on the radar item at data index 0")
        XCTAssertTrue(other!.currentStates.isEmpty,
                      "sibling radar polygon at a different dataIndex must NOT enter emphasis")

        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = 0
        ec.dispatchAction(dp)
        XCTAssertTrue(target!.currentStates.isEmpty, "downplay must clear the radar emphasis")
    }

    // ---- PARALLEL: each data Polyline is a dispatcher; highlight enters emphasis, downplay clears ----
    func testParallelLineHoverEntersEmphasis() {
        let ec = ECharts(width: 520, height: 380)
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
                            [12.0, 230.0,  8.0, 90.0],
                            [24.0, 140.0, 15.0, 60.0],
                            [ 6.0, 320.0,  3.0, 75.0]
                        ]] as [String: Any]]
        ])

        let series = ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()
        let target = data.getItemGraphicEl(0)
        let other = data.getItemGraphicEl(1)
        XCTAssertNotNil(target, "parallel render must populate a Polyline for data index 0")
        XCTAssertNotNil(other, "parallel render must populate a Polyline for data index 1")

        XCTAssertTrue(states.isHighDownDispatcher(target!),
                      "ParallelView must mark each data Polyline a highDown dispatcher")
        XCTAssertTrue(target!.currentStates.isEmpty, "no emphasis before highlight")

        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0
        hp.other["dataIndexInside"] = 0
        ec.dispatchAction(hp)

        XCTAssertTrue(target!.currentStates.contains("emphasis"),
                      "highlight must enter emphasis on the parallel line at data index 0")
        XCTAssertTrue(other!.currentStates.isEmpty,
                      "sibling parallel line at a different dataIndex must NOT enter emphasis")

        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = 0
        ec.dispatchAction(dp)
        XCTAssertTrue(target!.currentStates.isEmpty, "downplay must clear the parallel emphasis")
    }
}
