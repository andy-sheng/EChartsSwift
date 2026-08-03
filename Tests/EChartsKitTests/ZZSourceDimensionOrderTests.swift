// Dataset dimension order for objectRows / keyedColumns sources WITHOUT an explicit `dimensions`.
//
// Upstream derives the order with `Object.keys`, whose order the spec fixes: canonical array-index
// keys ascending numerically FIRST, then string keys in insertion order. Verified against real
// echarts in the WKWebView oracle: Object.keys({product:'A', 2016:85, 2015:43}) ==
// ["2015","2016","product"] — `product` LAST despite being written first.
//
// The port read `Array(dict.keys)` from a Swift `Dictionary`, whose per-process seeded hashing made
// the order RUN-TO-RUN NONDETERMINISTIC: the default `encode` (dim0→x, dim1→y) could bind different
// columns on different launches and draw a different chart from the same option. `jsPropertyKeyOrder`
// restores the derivable part exactly; the string portion (insertion order, unrecoverable from a
// `Dictionary`) falls back to a deterministic lexicographic order, with explicit `dataset.dimensions`
// as the faithful escape hatch.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ZZSourceDimensionOrderTests: XCTestCase {

    private func dimensionNames(_ source: Any) -> [String] {
        let s = createSource(source, SourceMetaRawOption(), nil)
        return (s.dimensionsDefine ?? []).compactMap { $0.name }
    }

    func testObjectRowsNumericKeysComeFirstAscending() {
        // The exact case verified against real echarts: numeric keys ascending, then the string key —
        // NOT literal/insertion order.
        let rows: [[String: Any]] = [
            ["product": "Matcha Latte", "2016": 85.8, "2015": 43.3],
            ["product": "Milk Tea", "2016": 73.4, "2015": 83.1],
        ]
        XCTAssertEqual(dimensionNames(rows), ["2015", "2016", "product"])
    }

    func testKeyedColumnsUseTheSameOrdering() {
        let cols: [String: Any] = [
            "product": ["a", "b"],
            "2016": [85.8, 73.4],
            "2015": [43.3, 83.1],
        ]
        XCTAssertEqual(dimensionNames(cols), ["2015", "2016", "product"])
    }

    func testOrderIsDeterministicAcrossManyDictionaryInstances() {
        // Many distinct Dictionary instances (fresh hashing each) must all derive the same order.
        // Before the fix this was the failure mode: same option, different chart per process.
        var seen = Set<[String]>()
        for i in 0..<50 {
            var row: [String: Any] = [:]
            // Vary insertion order per iteration.
            let keys = ["alpha", "beta", "3", "10", "2", "gamma"]
            for k in (i % 2 == 0 ? keys : keys.reversed()) { row[k] = 1.0 }
            seen.insert(dimensionNames([row]))
        }
        XCTAssertEqual(seen.count, 1, "one option must derive exactly one dimension order")
        XCTAssertEqual(seen.first, ["2", "3", "10", "alpha", "beta", "gamma"],
                       "numeric ascending (2 < 3 < 10, numerically not lexically), then strings")
    }

    func testExplicitDimensionsAreNeverReordered() {
        let rows: [[String: Any]] = [["b": 1.0, "a": 2.0]]
        let s = createSource(rows, SourceMetaRawOption(dimensions: ["b", "a"]), nil)
        XCTAssertEqual((s.dimensionsDefine ?? []).compactMap { $0.name }, ["b", "a"],
                       "the escape hatch: a declared order is authoritative and untouched")
    }

    func testNonCanonicalNumericStringsStayInTheStringPortion() {
        // "01" and "-1" are NOT canonical array indices in JS; they enumerate with the string keys.
        let rows: [[String: Any]] = [["01": 1.0, "5": 1.0, "-1": 1.0]]
        XCTAssertEqual(dimensionNames(rows), ["5", "-1", "01"])
    }
}
