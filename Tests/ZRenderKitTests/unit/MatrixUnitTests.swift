// Ported from zrender/test/ut/spec/core/matrix.test.ts — keep in sync with upstream

import XCTest
import simd
@testable import ZRenderKit

final class MatrixUnitTests: XCTestCase {

    // upstream: it('should rotate relative to a pivot point')
    func test_should_rotate_relative_to_a_pivot_point() throws {
        // upstream names this local `matrix`; renamed to `m` to avoid shadowing the
        // `matrix` enum namespace. The value-returning `matrix.rotate(a, rad, pivot)` replaces
        // upstream's out-param form `rotate(matrix, matrix, rad, pivot)` (CONVENTIONS §3).
        let m: MatrixArray = [
            0.9659258262890683, 0.25881904510252074, -0.25881904510252074, 0.9659258262890683,
            40.213201392710246, -26.96358986452364
        ]
        let rad = -0.2617993877991494
        let pivot = VectorArray(122.511, 139.243)

        let result = matrix.rotate(m, rad, pivot)

        XCTAssertEqual(result[0], 0.8660254037844387, accuracy: pow(10, -5))
        XCTAssertEqual(result[1], 0.49999999999999994, accuracy: pow(10, -5))
        XCTAssertEqual(result[2], -0.49999999999999994, accuracy: pow(10, -5))
        XCTAssertEqual(result[3], 0.8660254037844387, accuracy: pow(10, -5))
        XCTAssertEqual(result[4], 86.03486175696463, accuracy: pow(10, -5))
        XCTAssertEqual(result[5], -42.600475299156585, accuracy: pow(10, -5))
    }
}
