// L1c tests for the pie label collision + leader-line subsystem:
//   - labelLayoutHelper.shiftLayoutOnXY: overlapping labels are pushed apart along an axis.
//   - labelGuideHelper.limitTurnAngle: a sharp elbow is relaxed toward the segment; a straight
//     3-point line is left untouched.
//   - End-to-end: a many-slice pie's outer labels do not vertically overlap after avoidOverlap,
//     and every outer label owns a 3-point leader line.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class PieLabelLayoutTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(PieSeriesModel.self) }

    // Minimal ShiftLayoutItem: a rect + a backing ZRText whose y is shifted alongside.
    private final class Item: labelLayoutHelper.ShiftLayoutItem {
        let rect: BoundingRect
        let label: ZRText
        init(_ y: Double, _ h: Double) {
            self.rect = BoundingRect(0, y, 20, h)
            let t = ZRText()
            t.y = y
            self.label = t
        }
    }

    func testShiftLayoutOnXYSeparatesOverlappingLabelsOnY() {
        // Two 20-tall labels both starting at y=0 fully overlap.
        let a = Item(0, 20)
        let b = Item(0, 20)
        let adjusted = labelLayoutHelper.shiftLayoutOnXY([a, b], 1, -1000, 1000)
        XCTAssertTrue(adjusted, "overlapping labels should be adjusted")

        // After the shift the two rects must not overlap on Y (one sits entirely below the other).
        let (lo, hi) = a.rect.y <= b.rect.y ? (a, b) : (b, a)
        XCTAssertGreaterThanOrEqual(hi.rect.y, lo.rect.y + lo.rect.height - 1e-6,
                                    "shifted labels must not overlap on Y")
        // The label element's y moves in lock-step with its rect.
        XCTAssertEqual(a.label.y, a.rect.y, accuracy: 1e-9)
        XCTAssertEqual(b.label.y, b.rect.y, accuracy: 1e-9)
    }

    func testShiftLayoutOnXYNoOpForSingleOrDisjoint() {
        // A single label is never adjusted.
        XCTAssertFalse(labelLayoutHelper.shiftLayoutOnXY([Item(0, 20)], 1, -1000, 1000))
        // Two already-disjoint labels within bounds are not adjusted.
        XCTAssertFalse(labelLayoutHelper.shiftLayoutOnXY([Item(0, 20), Item(50, 20)], 1, -1000, 1000))
    }

    func testLimitTurnAngleLeavesStraightLineUntouched() {
        // A straight horizontal 3-point line: the turn is 180°, well above any minTurnAngle.
        var pts: [[Double]] = [[0, 0], [10, 0], [20, 0]]
        labelGuideHelper.limitTurnAngle(&pts, 90)
        XCTAssertEqual(pts[1][0], 10, accuracy: 1e-9, "straight line elbow x unchanged")
        XCTAssertEqual(pts[1][1], 0, accuracy: 1e-9, "straight line elbow y unchanged")
    }

    func testLimitTurnAngleRelaxesSharpElbow() {
        // A sharp hairpin: pt0 and pt2 nearly coincide in direction from pt1 → tiny turn angle.
        // limitTurnAngle(minTurnAngle=90) must move the elbow (pt1) to open the angle.
        var pts: [[Double]] = [[0, 0], [10, 0.5], [0, 1]]
        let before = pts[1]
        labelGuideHelper.limitTurnAngle(&pts, 90)
        XCTAssertNotEqual(pts[1][0], before[0], "sharp elbow x should be relaxed")
    }

    func testManySlicePieOuterLabelsDoNotOverlapAndOwnLeaderLines() {
        let ec = ECharts(width: 500, height: 400)
        // Many small adjacent slices force vertical crowding on one side → avoidOverlap must act.
        var data: [[String: Any]] = []
        for i in 0..<10 {
            data.append(["value": Double(10 + i), "name": "item-\(i)"])
        }
        ec.setOption([
            "series": [["type": "pie", "radius": "55%",
                        "label": ["show": true, "position": "outer"] as [String: Any],
                        "data": data] as [String: Any]]
        ])

        var sectors: [Sector] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Sector { sectors.append(s) }
            return false
        }
        XCTAssertEqual(sectors.count, 10)

        // Collect visible outer labels with their global rects; every outer label owns a 3-point line.
        var rects: [BoundingRect] = []
        for s in sectors {
            guard let label = s.getTextContent(), !label.ignore else { continue }
            guard let guide = s.getTextGuideLine(), !guide.ignore else {
                XCTFail("a visible outer pie label must own a visible leader line"); continue
            }
            XCTAssertEqual((guide.shape as? PolylineShape)?.points?.count, 3)
            let r = BoundingRect(0, 0, 0, 0)
            labelLayoutHelper.computeLabelGlobalRect(r, label)
            rects.append(r)
        }
        XCTAssertGreaterThan(rects.count, 4, "most slices should show an outer label")

        // No two labels on the same horizontal side may vertically overlap (avoidOverlap guarantee).
        // Group by side using the label x relative to the chart center (~250).
        func check(_ side: [BoundingRect]) {
            let sorted = side.sorted { $0.y < $1.y }
            for i in 1..<max(sorted.count, 1) where sorted.count >= 2 {
                XCTAssertGreaterThanOrEqual(
                    sorted[i].y, sorted[i - 1].y + sorted[i - 1].height - 0.5,
                    "outer labels on one side must not vertically overlap")
            }
        }
        check(rects.filter { $0.x + $0.width / 2 < 250 })
        check(rects.filter { $0.x + $0.width / 2 >= 250 })
    }

    func testLeftOuterLabelRebuildsTSpanWithRightAlignment() {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption([
            "series": [[
                "type": "pie",
                "radius": "30%",
                "center": ["50%", "25%"],
                "label": ["formatter": "{b}: {c} ({d}%)"] as [String: Any],
                "data": [
                    ["name": "Milk Tea", "value": 56.5] as [String: Any],
                    ["name": "Matcha Latte", "value": 51.1] as [String: Any],
                    ["name": "Cheese Cocoa", "value": 40.1] as [String: Any],
                    ["name": "Walnut Brownie", "value": 25.2] as [String: Any]
                ]
            ] as [String: Any]]
        ])

        let cheeseTSpan = ec.getStorage().getDisplayList(true).compactMap { $0 as? TSpan }.first {
            $0.tspanStyle.text?.contains("Cheese Cocoa") == true
        }
        XCTAssertEqual(cheeseTSpan?.tspanStyle.textAlign, "right",
                       "a left-side outer label must extend away from the pie")
    }
}
