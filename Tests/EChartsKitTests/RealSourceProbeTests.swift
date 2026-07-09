// Phase 6c payoff: render through the REAL BarSeriesModel/LineSeriesModel getInitialData
// (createSeriesData -> SourceManager.getSource from the option's own series.data), with NO test double.
// This is the proof that the ported SourceManager removed the getInitialData crutch.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class RealDataPipelineTests: XCTestCase {
    // `ComponentModel.registerClass` is a GLOBAL registry; other suites (EChartsSmokeTests,
    // CartesianCoordTests) register empty-data `series.bar` doubles that persist across tests. Since
    // this suite deliberately exercises the REAL models, re-register them so the test is order-independent.
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
        ComponentModel.registerClass(LineSeriesModel.self)
    }

    func testRealBarNoDouble() {
        let ec = ECharts(width: 400, height: 300)   // registers the REAL BarSeriesModel via installOnce
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 4, "real getInitialData should build 4 rows from series.data")
        var rects = 0
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect, r.name == "item" { rects += 1 }
            return false
        }
        XCTAssertEqual(rects, 4, "the real data pipeline should render 4 bars without a data double")
    }

    func testRealLineNoDouble() {
        let ec = ECharts(width: 480, height: 320)
        ec.setOption([
            "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "data": [820.0, 932.0, 901.0, 934.0, 1290.0, 1330.0]] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 6, "real getInitialData should build 6 rows from series.data")
        var polys = 0
        _ = ec.getRoot().traverse { el in
            if let p = el as? Polyline, p.name == "line" { polys += 1 }
            return false
        }
        XCTAssertEqual(polys, 1, "the real data pipeline should render the line without a data double")
    }
}
