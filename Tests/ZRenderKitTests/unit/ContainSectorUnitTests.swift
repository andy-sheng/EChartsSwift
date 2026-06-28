// Ported from zrender/test/ut/spec/contain/Sector.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream `describe('Path', ...)` — Sector containment regression tests. A `Sector` is built with a
// fixed shape/style and `sector.contain(x, y)` is asserted FALSY for a set of points outside it.
//
// Construction maps to the Swift API:
//   - `new Sector({ shape: {...}, style: {...} })` → `Sector(["shape": SectorShape, "style": PathStyleProps])`.
//   - `cornerRadius: 5` → `SectorShape.cornerRadius = .number(5)` (CornerRadius tagged enum).
//   - `fill`/`stroke` color strings → `ZRColor.string(...)`.
// `expect(...).toBeFalsy()` → XCTAssertFalse.
final class ContainSectorUnitTests: XCTestCase {

    // upstream: it('Should not contain the point.')
    func test_Should_not_contain_the_point() throws {
        var shape = SectorShape()
        shape.clockwise = true
        shape.cornerRadius = .number(5)
        shape.cx = 1150.5
        shape.cy = 625.5
        shape.startAngle = -1.5707963267948966
        shape.endAngle = 4.71238898038469
        shape.r = 218.92499999999998
        shape.r0 = 93.825

        var style = PathStyleProps()
        style.fill = .string("rgba(218,29,35,1)")
        style.lineJoin = "bevel"
        style.lineWidth = 2
        style.opacity = 1
        style.shadowBlur = 0
        style.shadowColor = "rgba(0,0,0,0.2)"
        style.shadowOffsetX = 0
        style.shadowOffsetY = 0
        style.stroke = .string("rgba(255,255,255,1)")

        let sector = Sector(["shape": shape, "style": style])

        XCTAssertFalse(sector.contain(1146, 619))
        XCTAssertFalse(sector.contain(471, 613))
        XCTAssertFalse(sector.contain(491, 705))
        XCTAssertFalse(sector.contain(1922, 594))
        XCTAssertFalse(sector.contain(1949, 738))
        XCTAssertFalse(sector.contain(1142, 49))
        XCTAssertFalse(sector.contain(1163, 1185))
        XCTAssertFalse(sector.contain(269, 508))
    }
}
