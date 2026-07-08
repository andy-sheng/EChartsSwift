// Unit tests for the ported zrender OrientedBoundingRect (rotated-rect SAT overlap test).
// The OBB drives echarts label `hideOverlap`: an intersection means one label must be hidden.

import XCTest
@testable import ZRenderKit

final class OrientedBoundingRectTests: XCTestCase {

    // Rotation matrix by `deg` about the origin (+ optional translation).
    // Point.transform: x' = m[0]x + m[2]y + m[4]; y' = m[1]x + m[3]y + m[5].
    private func rot(_ deg: Double, tx: Double = 0, ty: Double = 0) -> MatrixArray {
        let r = deg * Double.pi / 180
        return [cos(r), sin(r), -sin(r), cos(r), tx, ty]
    }

    func testAxisAlignedOverlap() {
        let a = OrientedBoundingRect(BoundingRect(0, 0, 10, 10))
        let b = OrientedBoundingRect(BoundingRect(5, 5, 10, 10))
        XCTAssertTrue(a.intersect(b), "two axis-aligned squares that overlap must intersect")
    }

    func testAxisAlignedDisjoint() {
        let a = OrientedBoundingRect(BoundingRect(0, 0, 10, 10))
        let b = OrientedBoundingRect(BoundingRect(100, 100, 10, 10))
        XCTAssertFalse(a.intersect(b), "far-apart squares must not intersect")
    }

    func testTouchingEdgeIsIntersection() {
        // Sharing the edge x == 10 counts as an intersection (touchThreshold defaults to 0).
        let a = OrientedBoundingRect(BoundingRect(0, 0, 10, 10))
        let b = OrientedBoundingRect(BoundingRect(10, 0, 10, 10))
        XCTAssertTrue(a.intersect(b), "rects touching on an edge intersect at touchThreshold 0")
    }

    func testRotatedOverlappingRects() {
        // A: wide thin horizontal bar centered at origin (x:-10..10, y:-1..1).
        let a = OrientedBoundingRect(BoundingRect(-10, -1, 20, 2))
        // B: the SAME bar rotated 90° → a vertical bar (x:-1..1, y:-10..10). They cross at the origin.
        let b = OrientedBoundingRect(BoundingRect(-10, -1, 20, 2), rot(90))
        XCTAssertTrue(a.intersect(b), "a horizontal bar and a crossing vertical (rotated) bar overlap")
    }

    func testRotatedDisjointRects() {
        // A near the origin, B rotated 45° AND translated far away → no overlap.
        let a = OrientedBoundingRect(BoundingRect(-10, -1, 20, 2))
        let b = OrientedBoundingRect(BoundingRect(-10, -1, 20, 2), rot(45, tx: 500, ty: 500))
        XCTAssertFalse(a.intersect(b), "a rotated rect translated far away is disjoint")
    }

    func testRotatedOverlapThatAxisAlignedRejectionWouldMiss() {
        // A tilted square whose axis-aligned bounding box overlaps A's box, and the rotated bodies
        // genuinely overlap near the shared region.
        let a = OrientedBoundingRect(BoundingRect(0, 0, 10, 10))
        let b = OrientedBoundingRect(BoundingRect(-5, -5, 10, 10), rot(45, tx: 8, ty: 8))
        XCTAssertTrue(a.intersect(b), "a 45°-rotated square straddling A's corner overlaps A")
    }
}
