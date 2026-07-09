// Legend show/hide for charts whose legend controls DATA ITEMS (not whole series): pie / funnel /
// radar. Their legend entries are the data-item NAMES (pie slice names / radar polygon names), not the
// series name, so the series-level legendFilter never matched them and a legend click did nothing.
// The dataFilter processor (echarts/src/processor/dataFilter.ts, registered per-series in each chart's
// install.ts) drops the individual data items whose name is unselected. Regression for that gap.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class LegendDataItemFilterTests: XCTestCase {

    private func pieDataNames(_ ec: EChartsSlim) -> [String] {
        let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
        return (0..<data.count()).map { data.getName($0) }
    }

    // Sum of every slice's laid-out sweep angle; a full doughnut fills 2π regardless of slice count.
    private func pieAngleSum(_ ec: EChartsSlim) -> Double {
        let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
        var sum = 0.0
        for idx in 0..<data.count() {
            if let layout = data.getItemLayout(idx) as? [String: Any],
               let angle = layout["angle"] as? Double, !angle.isNaN {
                sum += angle
            }
        }
        return sum
    }

    private func makePieWithLegend() -> EChartsSlim {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "legend": ["data": ["A", "B", "C", "D"]] as [String: Any],
            "series": [
                ["type": "pie", "radius": ["40%", "70%"],
                 "data": [
                    ["name": "A", "value": 10.0] as [String: Any],
                    ["name": "B", "value": 20.0] as [String: Any],
                    ["name": "C", "value": 30.0] as [String: Any],
                    ["name": "D", "value": 40.0] as [String: Any]
                 ]] as [String: Any]
            ]
        ])
        return ec
    }

    func testPieLegendToggleFiltersSliceAndRelayouts() {
        let ec = makePieWithLegend()
        XCTAssertEqual(pieDataNames(ec).sorted(), ["A", "B", "C", "D"], "all four slices present initially")
        XCTAssertEqual(pieAngleSum(ec), .pi * 2, accuracy: 1e-6, "four slices fill the full circle")

        // Legend item click on "B" → dispatchAction(legendToggleSelect, name:B).
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "B"
        ec.dispatchAction(off)

        let names = pieDataNames(ec)
        XCTAssertEqual(names.sorted(), ["A", "C", "D"], "toggling B off must filter that slice out of getData()")
        XCTAssertFalse(names.contains("B"), "slice B is gone")
        // Remaining slices re-layout to still fill 360° (2π).
        XCTAssertEqual(pieAngleSum(ec), .pi * 2, accuracy: 1e-6, "remaining slices re-layout to fill the full circle")

        let legend = ec.getModel()!.getComponent("legend") as? LegendModel
        XCTAssertEqual(legend?.isSelected("B"), false)
        XCTAssertEqual(legend?.isSelected("A"), true)

        // Click again → restored.
        var on = Payload(type: "legendToggleSelect"); on.other["name"] = "B"
        ec.dispatchAction(on)
        XCTAssertEqual(pieDataNames(ec).sorted(), ["A", "B", "C", "D"], "toggling B back on restores the slice")
        XCTAssertEqual(pieAngleSum(ec), .pi * 2, accuracy: 1e-6, "restored pie fills the full circle again")
    }

    func testRadarLegendToggleHidesPolygon() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "legend": ["data": ["A", "B", "C"]] as [String: Any],
            "radar": ["indicator": [
                ["name": "i1", "max": 100.0] as [String: Any],
                ["name": "i2", "max": 100.0] as [String: Any],
                ["name": "i3", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [
                ["type": "radar", "data": [
                    ["name": "A", "value": [10.0, 20.0, 30.0]] as [String: Any],
                    ["name": "B", "value": [40.0, 50.0, 60.0]] as [String: Any],
                    ["name": "C", "value": [70.0, 80.0, 90.0]] as [String: Any]
                ]] as [String: Any]
            ]
        ])

        func radarNames() -> [String] {
            let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
            return (0..<data.count()).map { data.getName($0) }
        }

        XCTAssertEqual(radarNames().sorted(), ["A", "B", "C"], "all three radar polygons present initially")

        // Toggle the "B" polygon off via a legend item click.
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "B"
        ec.dispatchAction(off)
        let names = radarNames()
        XCTAssertEqual(names.sorted(), ["A", "C"], "toggling B off hides that radar polygon's data item")
        XCTAssertFalse(names.contains("B"))

        // Toggle back on → restored.
        var on = Payload(type: "legendToggleSelect"); on.other["name"] = "B"
        ec.dispatchAction(on)
        XCTAssertEqual(radarNames().sorted(), ["A", "B", "C"], "toggling B back on restores the polygon")
    }
}
