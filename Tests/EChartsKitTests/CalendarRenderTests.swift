// END-TO-END RENDER TEST for the Phase-20 CALENDAR coordinate system (the 6th coord system) + its
// component view. Drives ECharts with a calendar option (a one-month range) and asserts the calendar
// BACKDROP reaches the ZRenderKit scene graph: the month/grid outline (Polylines from _renderLines), the
// day-cell Rect(s), and the day/week/month/year label texts (ZRText). Also guards the coord-sys wiring:
// CoordinateSystemManager.register("calendar", ...) → Calendar.create builds the coord, CalendarView
// reads its cell geometry (Calendar.dataToRect / getRangeInfo) back. Without any of these the backdrop
// would render empty.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class CalendarRenderTests: XCTestCase {
    func testCalendarRendersBackdrop() {
        let ec = ECharts(width: 520, height: 300)
        ec.setOption([
            "calendar": [
                "top": 60.0, "left": 40.0, "right": 40.0,
                "cellSize": ["auto", 24.0] as [Any],
                "range": "2017-02",
                "dayLabel": ["firstDay": 1] as [String: Any],
                "monthLabel": ["show": true] as [String: Any],
                "yearLabel": ["show": true] as [String: Any]
            ] as [String: Any]
        ])

        var polylines = 0   // month/grid outline (_renderLines)
        var rects = 0       // day-rect background (_renderDayRect)
        var texts = 0       // day/week/month/year labels
        _ = ec.getRoot().traverse { el in
            if el is ZRenderKit.Polyline { polylines += 1 }
            else if el is ZRenderKit.Rect { rects += 1 }
            else if el is ZRenderKit.ZRText { texts += 1 }
            return false
        }

        // The calendar backdrop draws its month outline as Polylines and a day-rect background, plus
        // month/week/year label texts — all from the Calendar coord cell geometry.
        XCTAssertGreaterThan(polylines + rects, 0, "calendar backdrop → grid outline Polylines / day Rects")
        XCTAssertGreaterThan(texts, 0, "calendar backdrop → day/month/year label texts")
    }
}
