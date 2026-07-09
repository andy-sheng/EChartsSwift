import XCTest
import ZRenderKit
@testable import EChartsKit

// A bar series whose data is supplied via a DataStore directly, bypassing the UNPORTED
// `SourceManager.getSource` (data/helper/sourceManager.ts — Phase 6b). This mirrors the
// `CartesianCoordTests` double: it lets the FULL ECharts update cycle run end-to-end so we can
// observe the grid + axis views emit elements. (Real bar Rects additionally need populated data
// values, which requires the data-source layer — see the test notes.)
private final class SmokeBarSeriesModel: BarSeriesModel {
    override class var type: ComponentFullType { return "series.bar" }
    override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let d = SeriesData(["x", "y"], self)
        d.initData(DataStore())
        return d
    }
}

final class EChartsSmokeTests: XCTestCase {
    // `registerClass` is a PROCESS-GLOBAL registration keyed by ComponentFullType ("series.bar"):
    // registering SmokeBarSeriesModel overwrites the real BarSeriesModel for EVERY later test in the
    // process. Its getInitialData returns an EMPTY DataStore, so without this restore, every
    // subsequently-run bar chart silently loses its data (no bars, no transitions). Restore the real
    // BarSeriesModel in tearDown so test order can not corrupt other suites (see the
    // swiftpm-port-mechanical-traps precedent).
    override func tearDown() {
        ComponentModel.registerClass(BarSeriesModel.self)
        super.tearDown()
    }

    func testBarChartCycleRunsAndEmitsAxisElements() {
        let ec = ECharts(width: 400, height: 300)
        // Override the real (SourceManager-backed) bar model with the DataStore-backed double.
        ComponentModel.registerClass(SmokeBarSeriesModel.self)

        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ])

        var rectCount = 0
        var lineOrPolyCount = 0
        var textCount = 0
        var total = 0
        _ = ec.getRoot().traverse { el in
            total += 1
            let name = String(describing: type(of: el))
            if el is Rect { rectCount += 1 }
            if name.contains("Line") || name.contains("Polyline") || name.contains("Path") { lineOrPolyCount += 1 }
            if name.contains("Text") || name.contains("TSpan") { textCount += 1 }
            return false
        }
        print("ECHARTS-SMOKE total=\(total) rects=\(rectCount) lines/paths=\(lineOrPolyCount) texts=\(textCount)")
        print("ECHARTS-SMOKE displayList=\(ec.getStorage().getDisplayList(true).count)")

        // The cycle must complete and produce a non-empty scene graph (grid rect + axis groups).
        XCTAssertGreaterThan(total, 0, "the update cycle should populate the root group")
        XCTAssertNotNil(ec.getModel()?.getComponent("grid", 0), "grid model was instantiated")
    }
}
