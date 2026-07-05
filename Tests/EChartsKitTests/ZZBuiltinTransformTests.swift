// Phase 28 regression tests — BUILT-IN filter/sort data transforms wired via install.
//
// These drive both built-ins through a real `EChartsSlim.setOption` WITHOUT any manual
// `registerExternalTransform` call. Creating an `EChartsSlim` runs `installOnce()`, which calls
// `transformInstall` and registers `echarts:filter` / `echarts:sort` (callable as bare "filter"/"sort").
// If the install wiring regresses, `applyDataTransform` throws "Can not find transform on type ..."
// and these tests fail — proving the transforms are auto-registered.
//
// Option-dict style mirrors ZZDatasetProbeTests. The series `datasetIndex` is an Int literal (not 1.0)
// to keep exercising the Phase-27 Int-boxed index-read coercion in queryComponents.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZBuiltinTransformTests: XCTestCase {

    // Built-in `filter`: keep rows whose dim-1 value > 15. NO manual registration.
    func testBuiltinFilterTransform() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "dataset": [
                ["source": [
                    ["A", 10.0],
                    ["B", 20.0],
                    ["C", 30.0],
                    ["D", 12.0]
                ] as [Any]] as [String: Any],
                // Bare "filter" resolves only if the built-in is auto-installed (echarts: namespace).
                ["transform": ["type": "filter",
                               "config": ["dimension": 1, "gt": 15] as [String: Any]] as [String: Any]] as [String: Any]
            ],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            // Int literal (not 1.0) — exercises the Int-boxed datasetIndex coercion.
            "series": [["type": "bar", "datasetIndex": 1] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        print("BUILTIN-TRANSFORM filter row count = \(count)")
        // Rows passing `dim1 > 15`: B(20), C(30) -> 2.
        XCTAssertEqual(count, 2, "built-in filter should keep the 2 rows with dim-1 value > 15")
    }

    // Built-in `sort`: order desc by dim-1. First row must be the max. NO manual registration.
    func testBuiltinSortTransform() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "dataset": [
                ["source": [
                    ["A", 10.0],
                    ["B", 30.0],
                    ["C", 20.0]
                ] as [Any]] as [String: Any],
                ["transform": ["type": "sort",
                               "config": ["dimension": 1, "order": "desc"] as [String: Any]] as [String: Any]] as [String: Any]
            ],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "datasetIndex": 1] as [String: Any]]
        ])
        var count = -1
        var firstName = ""
        var firstValue: Double = .nan
        ec.getModel()?.eachSeries { s, _ in
            let data = s.getData()
            count = data.count()
            if count > 0 {
                firstName = data.getName(0)
                // Value dimension for a cartesian bar is 'y' (dim-1 of the source).
                let v = data.get("y", 0)
                firstValue = (v as? Double) ?? Double((v as? Int) ?? 0)
            }
        }
        print("BUILTIN-TRANSFORM sort count = \(count) firstName = \(firstName) firstValue = \(firstValue)")
        XCTAssertEqual(count, 3, "sort keeps all rows")
        // desc by dim-1 -> B(30), C(20), A(10). First row is the max: name "B", value 30.
        XCTAssertEqual(firstName, "B", "first row after desc sort should be the max-valued row")
        XCTAssertEqual(firstValue, 30.0, accuracy: 1e-9, "first row value after desc sort should be the max")
    }
}
