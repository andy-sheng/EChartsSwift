// Two independent findings from the corpus animation probe.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

/// A `realtimeSort` (bar-racing) chart must animate its bars to their new ranks.
///
/// Upstream splits the layout into two targets driven by DIFFERENT animation models: growth along the
/// value direction uses the series model, movement along the base axis uses the AXIS model
/// (BarView.ts:850-895). The port collapsed both into one `el.setShape(layout)` under a note claiming
/// that was "equivalent" — true only while initProps/updateProps were no-op shims. Once they became
/// real animations the collapse meant a bar-race chart never animated at all.
final class ZZRealtimeSortAnimationTests: XCTestCase {

    private func makeRace() -> EChartsView {
        let v = EChartsView(width: 600, height: 400)
        v.setOption([
            "animation": true,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["A", "B", "C"], "inverse": true] as [String: Any],
            "series": [
                ["type": "bar", "realtimeSort": true,
                 "animationDurationUpdate": 300.0,
                 "data": [10.0, 20.0, 30.0]] as [String: Any]
            ]
        ])
        _ = v.zr.storage.getDisplayList(true)
        return v
    }

    private func animatedBars(_ v: EChartsView) -> Int {
        var n = 0
        _ = v.ec.getRoot().traverse { el in
            if el is Rect, !el.animators.isEmpty { n += 1 }
            return false
        }
        return n
    }

    func testRealtimeSortBarsAnimateOnDataUpdate() {
        let v = makeRace()
        // New values that reorder the ranking — the bar-race stimulus.
        v.setOption([
            "series": [
                ["type": "bar", "realtimeSort": true,
                 "animationDurationUpdate": 300.0,
                 "data": [45.0, 15.0, 25.0]] as [String: Any]
            ]
        ], notMerge: false)
        _ = v.zr.storage.getDisplayList(true)
        XCTAssertGreaterThan(animatedBars(v), 0,
                             "realtimeSort bars must tween to their new layout, not snap")
    }
}

/// `lines` with the flat numeric coord format must survive a re-render.
///
/// `_processFlatCoordsArray` bakes `startOffset = _flatCoords.length` into every offset it emits, but
/// `mergeOption` REPLACES `_flatCoords` with the freshly parsed array rather than concatenating
/// (LinesSeries.ts:183-184). Re-applying such an option therefore leaves every offset pointing past the
/// end of the array it indexes. Upstream reads `undefined` → NaN → the lines just do not draw; the port
/// trapped and killed the process.
final class ZZLinesFlatCoordsReapplyTests: XCTestCase {

    /// Flat format: pointCount | x | y | … per segment.
    private static let flat: [Double] = [
        2, 100, 100, 200, 200,
        3, 10, 10, 20, 40, 30, 10
    ]

    func testReapplyingAFlatCoordsOptionDoesNotTrap() {
        let v = EChartsView(width: 400, height: 300)
        let opt: [String: Any] = [
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "lines", "coordinateSystem": "cartesian2d",
                 "polyline": true, "data": Self.flat] as [String: Any]
            ]
        ]
        v.setOption(opt)
        _ = v.zr.storage.getDisplayList(true)
        // Before the fix this second apply trapped with Index out of range inside getLineCoords.
        v.setOption(opt, notMerge: false)
        _ = v.zr.storage.getDisplayList(true)
    }
}
