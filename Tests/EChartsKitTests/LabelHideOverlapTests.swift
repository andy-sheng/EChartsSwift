// L2c tests for the global label layout stage:
//   - labelLayoutHelper.labelIntersect: rect fast-path overlap / disjoint / ignore short-circuit.
//   - labelLayoutHelper.hideOverlap: two overlapping labels → the lower-priority one is hidden
//     (ignore = true), disjoint labels are both kept.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LabelHideOverlapTests: XCTestCase {

    // A LabelLayoutData with pre-populated axis-aligned geometry (bypasses the label recompute:
    // `labelIntersect` reads the geometry directly, it does not call `ensureLabelLayoutWithGeometry`).
    private func geom(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> LabelLayoutData {
        let d = LabelLayoutData(label: ZRText())
        d.rect = BoundingRect(x, y, w, h)
        d.localRect = BoundingRect(x, y, w, h)
        d.transform = nil
        d.axisAligned = true
        d.geomIgnore = false
        // Clear the dirty flag so any lazy path treats the geometry as computed.
        labelLayoutHelper.setLabelLayoutDirty(d, false)
        return d
    }

    func testLabelIntersectOverlap() {
        XCTAssertTrue(labelLayoutHelper.labelIntersect(geom(0, 0, 10, 10), geom(5, 5, 10, 10)),
                      "overlapping axis-aligned label rects intersect")
    }

    func testLabelIntersectDisjoint() {
        XCTAssertFalse(labelLayoutHelper.labelIntersect(geom(0, 0, 10, 10), geom(100, 100, 10, 10)),
                       "far-apart label rects do not intersect")
    }

    func testLabelIntersectIgnoredShortCircuits() {
        let a = geom(0, 0, 10, 10)
        let b = geom(5, 5, 10, 10)
        // upstream labelLayoutHelper.ts:595-598 gates on the LIVE element (`layoutInfo.label.ignore`),
        //   NOT the `geomIgnore` geometry snapshot — `fixMinMaxLabelShow`/`hideOverlap` flip
        //   `label.ignore` after geometry is computed, so the snapshot goes stale.
        b.label.ignore = true
        XCTAssertFalse(labelLayoutHelper.labelIntersect(a, b),
                       "an ignored label never counts as intersecting")
    }

    // A real measured label (non-zero bounding rect) at a global position.
    private func label(_ text: String, _ x: Double, _ y: Double) -> ZRText {
        var st = TextStyleProps()
        st.text = text
        st.font = "18px Arial"
        let t = ZRText()
        t.useStyle(st)
        t.x = x
        t.y = y
        return t
    }

    func testHideOverlapHidesLowerPriorityLabel() {
        // Two identical labels at the SAME position fully overlap.
        let a = LabelLayoutData(label: label("Overlap", 100, 100), priority: 2)
        let b = LabelLayoutData(label: label("Overlap", 100, 100), priority: 1)

        labelLayoutHelper.hideOverlap([a, b])

        // The higher-priority label (a) is processed first and displayed; the lower-priority label (b)
        // overlaps it and is hidden.
        XCTAssertFalse(a.label.ignore, "higher-priority label stays visible")
        XCTAssertTrue(b.label.ignore, "lower-priority overlapping label is hidden")
    }

    func testHideOverlapKeepsDisjointLabels() {
        let a = LabelLayoutData(label: label("Left", 0, 0), priority: 2)
        let b = LabelLayoutData(label: label("Right", 1000, 1000), priority: 1)

        labelLayoutHelper.hideOverlap([a, b])

        XCTAssertFalse(a.label.ignore, "disjoint label a stays visible")
        XCTAssertFalse(b.label.ignore, "disjoint label b stays visible")
    }

    func testHideOverlapSetsEmphasisIgnoreFalse() {
        // A hidden label keeps an `emphasis` state that shows it on hover (ignore = false there).
        let a = LabelLayoutData(label: label("Same", 50, 50), priority: 2)
        let b = LabelLayoutData(label: label("Same", 50, 50), priority: 1)

        labelLayoutHelper.hideOverlap([a, b])

        XCTAssertTrue(b.label.ignore)
        XCTAssertEqual(b.label.ensureState("emphasis").ignore, false,
                       "hidden label is shown again on emphasis")
    }
}
