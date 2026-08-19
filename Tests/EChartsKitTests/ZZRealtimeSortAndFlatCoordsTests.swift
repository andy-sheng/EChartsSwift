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
            "animationDuration": 0.0,
            "animationDurationUpdate": 2000.0,
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

    func testRealtimeSortKeepsCategoryRowIdentityAcrossReorderedDatasetUpdate() {
        let v = EChartsView(width: 600, height: 400)
        let initial: [[Any]] = [[30.0, "C"], [20.0, "B"], [10.0, "A"]]
        v.setOption([
            "animation": true,
            "animationDuration": 0.0,
            "animationDurationUpdate": 2000.0,
            "animationEasingUpdate": "linear",
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["C", "B", "A"], "inverse": true] as [String: Any],
            "series": [[
                "type": "bar", "realtimeSort": true,
                "encode": ["x": 0.0, "y": 1.0] as [String: Any],
                "label": ["show": true, "valueAnimation": true, "precision": 1.0] as [String: Any],
                "data": initial
            ] as [String: Any]]
        ])
        let global = v.ec.getModel()!
        let series = global.getSeriesByIndex(0)!
        let oldData = series.getData()
        XCTAssertTrue(series.parentModel === global)
        XCTAssertEqual(global.getShallow("animationDurationUpdate") as? Double, 2000)
        XCTAssertEqual(series.getShallow("animationDurationUpdate") as? Double, 2000)
        let oldIds = (0..<oldData.count()).map { oldData.getId($0) }
        let oldElementsById = Dictionary(uniqueKeysWithValues: (0..<oldData.count()).compactMap { index in
            oldData.getItemGraphicEl(index).map { (oldData.getId(index), ObjectIdentifier($0)) }
        })

        // Reverse the visible ranking (C,B,A -> A,B,C) while also changing the raw row order.
        let updated: [[Any]] = [[50.0, "A"], [10.0, "C"], [25.0, "B"]]
        v.setOption(["series": [["type": "bar", "data": updated] as [String: Any]]], notMerge: false)
        XCTAssertNotNil(v.ec.getZr(), "the realtime-sort rendered listener requires the live zrender host")

        let newData = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let newIds = (0..<newData.count()).map { newData.getId($0) }
        XCTAssertEqual(Set(oldIds), Set(newIds), "category names must key row identity across reorder")
        XCTAssertGreaterThan(animatedBars(v), 0, "reused bars should animate instead of re-entering at duration zero")

        let rect = newData.getItemGraphicEl(0) as! Rect
        let finalWidth = (rect.shape as! RectShape).width
        guard let label = rect.getTextContent() else {
            return XCTFail("valueAnimation test requires an attached bar label")
        }
        let finalText = label.textStyle?.text
        // Start all clips at the same synthetic timestamp; otherwise an unstepped clip treats the
        // later 50% sample as its own t=0, which cannot model one rendered frame.
        _ = v.ec.getRoot().traverse { el in
            for animator in el.animators { _ = animator.getClip()?.step(0, 0) }
            return false
        }
        for animator in label.animators { _ = animator.getClip()?.step(0, 0) }
        let startWidth = (rect.shape as! RectShape).width
        XCTAssertNotEqual(startWidth, finalWidth, "the first animation tick must restore the previous bar width")
        for animator in rect.animators { _ = animator.getClip()?.step(1000, 1000) }
        let middleWidth = (rect.shape as! RectShape).width
        XCTAssertNotEqual(middleWidth, startWidth)
        XCTAssertNotEqual(middleWidth, finalWidth)

        let startText = label.textStyle?.text
        XCTAssertNotEqual(startText, finalText, "valueAnimation labels must start from the previous value")
        for animator in label.animators { _ = animator.getClip()?.step(1000, 1000) }
        let middleText = label.textStyle?.text
        XCTAssertNotEqual(middleText, startText)
        XCTAssertNotEqual(middleText, finalText, "the label must roll continuously with the 2s bar tween")

        // Advance every bar to 50%, then emit the zrender `rendered` event. At this point A is wider
        // than B/C, so realtimeSort must dispatch changeAxisOrder and place raw ordinal A (2) first.
        _ = v.ec.getRoot().traverse { el in
            for animator in el.animators { _ = animator.getClip()?.step(1000, 1000) }
            return false
        }
        v.zr.refresh()
        v.zr.flush()
        let currentSeries = v.ec.getModel()!.getSeriesByIndex(0)!
        let coord = currentSeries.coordinateSystem as! Cartesian2D
        let ordinal = coord.getBaseAxis().scale as! OrdinalScale
        XCTAssertEqual(ordinal.getRawOrdinalNumber(0), 2,
                       "rendered listener must replace the category order as bars cross")

        let sortedData = currentSeries.getData()
        let sortedElementsById = Dictionary(uniqueKeysWithValues: (0..<sortedData.count()).compactMap { index in
            sortedData.getItemGraphicEl(index).map { (sortedData.getId(index), ObjectIdentifier($0)) }
        })
        XCTAssertEqual(sortedElementsById, oldElementsById,
                       "an order-only action must reuse each category's bar instead of leaving fading ghosts")
        var labeledBarCount = 0
        _ = v.ec.getRoot().traverse { element in
            if element is Rect, element.getTextContent() != nil {
                labeledBarCount += 1
            }
            return false
        }
        XCTAssertEqual(labeledBarCount, 3,
                       "a three-row race must keep exactly three live labeled bars after sorting")
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
