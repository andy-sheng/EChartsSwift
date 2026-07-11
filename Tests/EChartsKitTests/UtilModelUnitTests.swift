// Ported from echarts/test/ut/spec/util/model.test.ts — keep in sync with upstream
// Behavioral oracle for EChartsKit `modelUtil` (echarts/src/util/model.ts):
//   - compressBatches
//   - removeDuplicates
//
// jest -> XCTest mapping as elsewhere. Notes on faithful divergences:
//   * `compressBatches` builds its result from `[String: ...]` dictionaries, whose key
//     iteration order is UNSPECIFIED in Swift (documented PORT-NOTE at modelUtil.swift and
//     clazz.swift). Upstream relies on JS objects iterating integer-like keys in ascending
//     numeric order, which is why the expected arrays are sorted. We therefore compare the
//     result in an order-NORMALIZED canonical form (sort seriesId + sort dataIndex). The
//     *content* (which seriesIds / dataIndices survive) is still asserted faithfully; only the
//     dictionary-order nondeterminism is normalized away. See the port-status report.
//   * `removeDuplicates_no_resolve_has_value` distinguishes JS `undefined` from `null` (both are
//     kept because `undefined + '' === 'undefined'` and `null + '' === 'null'` are distinct
//     keys). Swift collapses both to `nil` (CONVENTIONS §6), so the case is XCTSkip-ed.

import XCTest
@testable import EChartsKit

// Reference-type test items (upstream items are JS objects mutated in place by `resolve`).
private final class Item1 {
    var name: String
    var name2: String?
    var extraNum: Double?
    init(name: String, extraNum: Double? = nil) { self.name = name; self.extraNum = extraNum }
}
private final class Item2 {
    var value: Double
    init(_ value: Double) { self.value = value }
}

final class UtilModelUnitTests: XCTestCase {

    // MARK: - compressBatches

    // Two overloads so scalar dataIndex (`item(3, 4)`) and array dataIndex (`item(3, [5])`) both
    // land as `Double` / `[Double]` (an untyped Int literal would fail the Double casts below).
    private func item(_ seriesId: Double, _ dataIndex: Double) -> BatchItem {
        return BatchItem(seriesId: seriesId, dataIndex: dataIndex)
    }
    private func item(_ seriesId: Double, _ dataIndex: [Double]) -> BatchItem {
        return BatchItem(seriesId: seriesId, dataIndex: dataIndex)
    }

    private func jsInt(_ x: Double) -> String {
        return x == x.rounded() ? String(Int64(x)) : String(x)
    }

    /// Order-normalized canonical form of a batch: "sid:[i,i];sid:[i]" with both levels sorted.
    /// seriesId is normalized to its JS-string form (compressBatches output stringifies it, while
    /// the expected `item(...)` builders keep it numeric).
    private func canon(_ items: [BatchItem]) -> String {
        return items.map { it -> String in
            let sid: String
            if let s = it.seriesId as? String { sid = s }
            else if let n = it.seriesId as? Double { sid = jsInt(n) }
            else { sid = "?" }
            let dis = (it.dataIndex as? [Double] ?? []).sorted().map { jsInt($0) }.joined(separator: ",")
            return "\(sid):[\(dis)]"
        }.sorted().joined(separator: ";")
    }

    private func assertBatches(
        _ actual: ([BatchItem], [BatchItem]),
        _ expectedA: [BatchItem],
        _ expectedB: [BatchItem],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(canon(actual.0), canon(expectedA), "batchA", file: file, line: line)
        XCTAssertEqual(canon(actual.1), canon(expectedB), "batchB", file: file, line: line)
    }

    func test_compressBatches_base() {
        // Remove duplicate between A and B
        assertBatches(
            model.compressBatches(
                [item(3, 4), item(3, 5), item(4, 5)],
                [item(4, 6), item(4, 5), item(3, 3), item(3, 4)]
            ),
            [item(3, [5])],
            [item(3, [3]), item(4, [6])]
        )

        // Compress
        assertBatches(
            model.compressBatches(
                [item(3, 4), item(3, 6), item(3, 5), item(4, 5)],
                [item(4, 6), item(4, 5), item(3, 3), item(3, 4), item(4, 7)]
            ),
            [item(3, [5, 6])],
            [item(3, [3]), item(4, [6, 7])]
        )

        // Remove duplicate in themselves
        assertBatches(
            model.compressBatches(
                [item(3, 4), item(3, 6), item(3, 5), item(4, 5)],
                [item(4, 6), item(4, 5), item(3, 3), item(3, 4), item(4, 7), item(4, 6)]
            ),
            [item(3, [5, 6])],
            [item(3, [3]), item(4, [6, 7])]
        )

        // dataIndex is array
        assertBatches(
            model.compressBatches(
                [item(3, [4, 5, 8]), item(4, 4), item(3, [5, 7, 7])],
                [item(3, [8, 9])]
            ),
            [item(3, [4, 5, 7]), item(4, [4])],
            [item(3, [9])]
        )

        // empty
        assertBatches(
            model.compressBatches(
                [item(3, [4, 5, 8]), item(4, 4), item(3, [5, 7, 7])],
                []
            ),
            [item(3, [4, 5, 7, 8]), item(4, [4])],
            []
        )
        assertBatches(
            model.compressBatches(
                [],
                [item(3, [4, 5, 8]), item(4, 4), item(3, [5, 7, 7])]
            ),
            [],
            [item(3, [4, 5, 7, 8]), item(4, [4])]
        )

        // should not has empty array
        assertBatches(
            model.compressBatches(
                [item(3, [4, 5, 8])],
                [item(3, [4, 5, 8])]
            ),
            [],
            []
        )
    }

    // MARK: - removeDuplicates

    func test_removeDuplicates_resolve1() {
        var countRecord: [Double] = []
        let resolve1: (Item1, Double) -> Void = { item, count in
            countRecord.append(count)
            item.name2 = item.name + (count > 0 ? String(Int(count - 1)) : "")
        }
        var arr: [Item1?] = [
            Item1(name: "y"),
            Item1(name: "b"),
            Item1(name: "y"),
            Item1(name: "t"),
            Item1(name: "y"),
            Item1(name: "z"),
            Item1(name: "t"),
        ]
        let arrLengthOriginal = arr.count
        let arrNamesOriginal = arr.map { $0!.name }
        model.removeDuplicates(&arr, { $0!.name }, resolve1)

        XCTAssertEqual(countRecord, [0, 0, 1, 0, 2, 0, 1])
        XCTAssertEqual(arr.count, arrLengthOriginal)
        XCTAssertEqual(arr.map { $0!.name }, arrNamesOriginal)
        XCTAssertEqual(arr.map { $0!.name2 }, ["y", "b", "y0", "t", "y1", "z", "t0"])
    }

    func test_removeDuplicates_no_resolve_has_value() throws {
        throw XCTSkip("""
        Upstream keeps BOTH `undefined` and `null` because `undefined + '' === 'undefined'` and \
        `null + '' === 'null'` are distinct keys. Swift collapses both to `nil` (CONVENTIONS §6), \
        so the two entries would dedupe to one — the case cannot be ported faithfully.
        """)
    }

    func test_removeDuplicates_priority() {
        var arr: [Item1?] = [
            Item1(name: "y", extraNum: 100),
            Item1(name: "b", extraNum: 101),
            Item1(name: "y", extraNum: 102),
            Item1(name: "t", extraNum: 103),
            Item1(name: "y", extraNum: 104),
            Item1(name: "z", extraNum: 105),
            Item1(name: "t", extraNum: 106),
        ]
        model.removeDuplicates(&arr, { $0!.name }, nil as ((Item1, Double) -> Void)?)
        XCTAssertEqual(arr.count, 4)
        XCTAssertEqual(arr.map { $0!.name }, ["y", "b", "t", "z"])
        XCTAssertEqual(arr.map { $0!.extraNum }, [100, 101, 103, 105])
    }

    func test_removeDuplicates_edges_cases() {
        func run(_ inputValues: [Double], _ expectValues: [Double]) {
            var inputArr: [Item2?] = inputValues.map { Item2($0) }
            model.removeDuplicates(&inputArr, { "\($0!.value)" }, nil as ((Item2, Double) -> Void)?)
            XCTAssertEqual(inputArr.map { $0!.value }, expectValues)
        }
        run([], [])
        run([1], [1])
        run([1, 2, 3], [1, 2, 3])
        run([1, 2, 2, 3], [1, 2, 3])
        run([1, 1, 2], [1, 2])
        run([1, 2, 2], [1, 2])
        run([2, 2, 2], [2])
        run([5, 5], [5])
    }
}
