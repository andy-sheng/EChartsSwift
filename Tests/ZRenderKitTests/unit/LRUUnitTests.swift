// Ported from zrender/test/ut/spec/core/LRU.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

final class LRUUnitTests: XCTestCase {

    // upstream: it('Basic')
    func test_Basic() throws {
        let lru = LRU<String>(5)

        for i in 0..<5 {
            // upstream: lru.put(i, 'val' + i). `i` is an Int variable (not a literal), so the
            // ExpressibleByIntegerLiteral conversion does not apply — use `.number(Double(i))`.
            lru.put(.number(Double(i)), "val\(i)")
        }
        XCTAssertEqual(lru.len(), 5)

        XCTAssertEqual(lru.get(3), "val3")
        XCTAssertEqual(lru.get(4), "val4")
        XCTAssertEqual(lru.get(0), "val0")
        XCTAssertEqual(lru.get(1), "val1")

        lru.put(6, "val6")
        XCTAssertNil(lru.get(2))
        lru.put(7, "val7")
        XCTAssertNil(lru.get(3))

        lru.clear()
        XCTAssertEqual(lru.len(), 0)
        XCTAssertNil(lru.get(1))
    }
}
