import XCTest
@testable import ZRenderKit

final class CubicEasingTests: XCTestCase {
    func test_linear_cubic_bezier_is_identity() throws {
        let f = try XCTUnwrap(easing.createCubicEasingFunc("cubic-bezier(0, 0, 1, 1)"))
        XCTAssertEqual(f(0.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(f(0.25), 0.25, accuracy: 1e-3)
        XCTAssertEqual(f(0.5), 0.5, accuracy: 1e-3)
        XCTAssertEqual(f(1.0), 1.0, accuracy: 1e-9)
    }

    func test_ease_in_out_is_nonlinear_and_symmetric() throws {
        // cubic-bezier(0.42, 0, 0.58, 1) == CSS ease-in-out: slow start/end, fast middle.
        let f = try XCTUnwrap(easing.createCubicEasingFunc("cubic-bezier(0.42, 0, 0.58, 1)"))
        XCTAssertEqual(f(0.0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(f(1.0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(f(0.5), 0.5, accuracy: 1e-3, "symmetric curve passes through the midpoint")
        // Slow start: at t=0.25 the eased value is below linear 0.25.
        XCTAssertLessThan(f(0.25), 0.25, "ease-in-out starts slower than linear")
        // Fast finish region: at t=0.75 the eased value is above linear 0.75.
        XCTAssertGreaterThan(f(0.75), 0.75, "ease-in-out ends past linear before settling")
    }

    func test_back_overshoots_above_one() throws {
        // The "back" curve (negative/over-1 control points) overshoots past 1 before settling.
        let f = try XCTUnwrap(easing.createCubicEasingFunc("cubic-bezier(0.68, -0.55, 0.27, 1.55)"))
        let peak = stride(from: 0.0, through: 1.0, by: 0.02).map { f($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.0, "back easing should overshoot above 1")
        XCTAssertEqual(f(1.0), 1.0, accuracy: 1e-9, "but settle exactly at 1")
    }

    func test_non_cubic_string_returns_nil() {
        XCTAssertNil(easing.createCubicEasingFunc("cubicInOut"))
        XCTAssertNil(easing.createCubicEasingFunc("linear"))
    }
}
