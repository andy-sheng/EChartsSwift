// Phase 27 regression tests — dataset + transform data path.
// Guards the dataset -> series source wiring AND the Int-boxed `datasetIndex` option-read trap
// (a Swift Int literal index must resolve through queryComponents, not silently drop to no dataset).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZDatasetProbeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    // Series with NO own data -> must read rows from `dataset.source` via the wired SourceManager.
    func testSeriesReadsFromDatasetSource() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "dataset": [
                ["source": [
                    ["product", "count"],
                    ["A", 10.0],
                    ["B", 20.0],
                    ["C", 30.0]
                ] as [Any]] as [String: Any]
            ],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar"] as [String: Any]]   // no `data` -> use dataset
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        print("DATASET-PROBE series row count = \(count)")
        XCTAssertEqual(count, 3, "series should read 3 rows from dataset.source header-detected data")
    }

    // Root dataset + filter transform -> transformed dataset feeds the series.
    func testDatasetFilterTransform() throws {
        // Register a simple built-in-style 'myFilter' transform that keeps rows whose 2nd col >= 20.
        try registerExternalTransform(ExternalDataTransform(
            type: "echarts:zzfilter",
            transform: { params in
                let up = params.upstream
                let n = Int(up.count())
                var rows: [Any] = []
                var i = 0
                while i < n {
                    let v = up.retrieveValue(Double(i), 1)
                    let dv = (v as? Double) ?? Double((v as? Int) ?? 0)
                    if dv >= 20.0 {
                        rows.append(up.getRawDataItemSafe(Double(i)) as Any)
                    }
                    i += 1
                }
                return ExternalDataTransformResultItem(data: rows)
            }
        ))

        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "dataset": [
                ["source": [
                    ["A", 10.0],
                    ["B", 20.0],
                    ["C", 30.0]
                ] as [Any]] as [String: Any],
                ["transform": ["type": "zzfilter"] as [String: Any]] as [String: Any]
            ],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            // Int literal (not 1.0) — exercises the Int-boxed datasetIndex coercion in queryComponents.
            "series": [["type": "bar", "datasetIndex": 1] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        print("DATASET-PROBE transform row count = \(count)")
        XCTAssertEqual(count, 2, "filter transform should keep the 2 rows with value >= 20")
    }
}

// A getRawData item accessor that doesn't throw (built-in path); falls back to retrieveValue rows.
extension ExternalSource {
    func getRawDataItemSafe(_ i: Double) -> Any? {
        return (try? getRawDataItem(i)) ?? nil
    }
}
