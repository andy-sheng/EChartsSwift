import XCTest
@testable import EChartsKit

final class TypedDataStoreTests: XCTestCase {
    private func store(_ rows: [[Any]], _ types: [DataStoreDimensionType]) -> DataStore {
        let store = DataStore()
        store.initData(DefaultDataProvider(rows), types.map { DataStoreDimensionDefine(type: $0) })
        return store
    }

    func testTypedColumnsRetainNanInt32AndOrdinalSemanticsAcrossAppendAndClone() {
        let original = store([[1.25, 4_294_967_297.0, "A"], [Double.nan, -2.9, "B"]], [.float, .int, .ordinal])
        XCTAssertEqual(original.getNumeric(0, 0), 1.25)
        XCTAssertTrue(original.getNumeric(0, 1).isNaN)
        XCTAssertEqual(original.getNumeric(1, 0), 1)
        XCTAssertEqual(original.getNumeric(1, 1), -2)
        XCTAssertEqual(original.get(2, 0) as? String, "A")
        let copy = original.clone()
        original.modify([0]) { [$0[0] as! Double * 2] }
        XCTAssertEqual(copy.getNumeric(0, 0), 1.25)
        XCTAssertEqual(original.getNumeric(0, 0), 2.5)
        _ = original.appendValues([[3.5, Double.infinity, "C"]])
        XCTAssertEqual(original.getNumeric(0, 2), 3.5)
        XCTAssertEqual(original.getNumeric(1, 2), 0)
        XCTAssertEqual(copy.count(), 2)
        let meta = OrdinalMeta(needCollect: true, deduplication: true)
        original.collectOrdinalMeta(2, meta)
        XCTAssertEqual(original.getNumeric(2, 2), 2)
        XCTAssertEqual(copy.get(2, 0) as? String, "A")
    }

    func testRangeFilteringRawIndexExtentAndMappingPreserveSource() {
        let original = store([[0.0, 10.0], [1.0, Double.nan], [2.0, 30.0], [3.0, 40.0]], [.float, .time])
        let filtered = original.selectRange([0: [1, 2]])
        XCTAssertEqual(filtered.count(), 2)
        XCTAssertEqual(filtered.getRawIndex(0), 1)
        XCTAssertTrue(filtered.getNumeric(1, 0).isNaN)
        XCTAssertEqual(filtered.getNumeric(1, 1), 30)
        XCTAssertEqual(filtered.getDataExtent(1, nil), [30, 30])
        XCTAssertEqual(original.count(), 4)
        let mapped = filtered.map([1]) { [($0[0] as! Double) + 5] }
        XCTAssertEqual(mapped.getNumeric(1, 1), 35)
        XCTAssertEqual(original.getNumeric(1, 2), 30)
        XCTAssertTrue(original.getNumeric(-1, 0).isNaN)
        XCTAssertTrue(original.getNumeric(0, 99).isNaN)
    }

    func testTypedArrayProviderAndAppendUseDirectColumnStorage() {
        let source = createSource([1.0, 10.0, 2.0, 20.0], SourceMetaRawOption(dimensions: ["x", "y"]), SOURCE_FORMAT_TYPED_ARRAY)
        let provider = DefaultDataProvider(source, 2)
        let store = DataStore()
        store.initData(provider, [.init(type: .float), .init(type: .float)])
        XCTAssertEqual(store.count(), 2)
        XCTAssertEqual(store.getNumeric(1, 1), 20)
        _ = store.appendData([3.0, 30.0])
        XCTAssertEqual(store.count(), 3)
        XCTAssertEqual(store.getNumeric(0, 2), 3)
        XCTAssertEqual(store.getNumeric(1, 2), 30)
        XCTAssertEqual(store.getDataExtent(1, nil), [10, 30])
    }
}
