import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// LARGE-mode wiring for the `lines` series: `large` + `largeThreshold` reach `pipelineContext.large`
// (Scheduler.updateStreamModes), the `linesLayout` STAGE packs the flat `linesPoints` buffer from it,
// and LinesView's large branch draws that buffer through ONE `LargeLinesPath` (chart/helper/LargeLineDraw)
// instead of one element per item.
//
// The buffer LAYOUT is load-bearing: `LargeLinesPath.buildPath` / `findDataIndex` read 4 slots per
// iteration guarded only by `while i < segs.count`, so a non-polyline buffer whose length is not a
// multiple of 4 indexes past the end and TRAPS in Swift. These tests pin that invariant, including for
// an item whose coord count is not 2.
final class LinesLargeDrawTests: XCTestCase {

    private func largePaths(_ ec: ECharts) -> [LargeLinesPath] {
        var out: [LargeLinesPath] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let p = el as? LargeLinesPath { out.append(p) }
                return false
            })
        }
        return out
    }

    private func namedLineCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if el is LargeLinesPath { return false }
                if el is Path { n += 1 }
                return false
            })
        }
        return n
    }

    private func option(_ data: [[String: Any]], large: Bool, polyline: Bool) -> [String: Any] {
        return [
            "animation": false,
            "xAxis": ["type": "value"],
            "yAxis": ["type": "value"],
            "series": [[
                "type": "lines",
                "animation": false,
                "coordinateSystem": "cartesian2d",
                "polyline": polyline,
                "large": large,
                "largeThreshold": 2,
                "data": data
            ] as [String: Any]]
        ]
    }

    private func twoPointData(_ n: Int) -> [[String: Any]] {
        return (0..<n).map { i in
            ["coords": [[Double(i), 0.0], [Double(i), 10.0]]] as [String: Any]
        }
    }

    // Non-polyline large mode → exactly ONE LargeLinesPath whose segs are 4 slots per item.
    func testLargeNonPolylineDrawsOneBufferPath() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(twoPointData(3), large: true, polyline: false))

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 1, "large mode collapses the whole series into ONE LargeLinesPath")

        let shape = paths[0].shape as? LargeLinesPathShape
        XCTAssertNotNil(shape)
        XCTAssertEqual(shape?.segs.count, 3 * 4,
                       "non-polyline linesPoints packs exactly [x0,y0,x1,y1] per item")
        XCTAssertEqual((shape?.segs.count ?? 1) % 4, 0, "LAYOUT INVARIANT: segs is a multiple of 4")
    }

    func testLargePathCarriesSeriesBlendMode() {
        let ec = ECharts(width: 400, height: 300)
        var opt = option(twoPointData(3), large: true, polyline: false)
        var series = (opt["series"] as? [[String: Any]]) ?? []
        series[0]["blendMode"] = "lighter"
        series[0]["lineStyle"] = ["opacity": 0.05, "width": 0.5] as [String: Any]
        opt["series"] = series
        ec.setOption(opt)

        let path = largePaths(ec).first
        XCTAssertEqual(path?.pathStyle.blend, "lighter",
                       "series blendMode must reach the batched path painter")
    }

    func testCompletedProgressiveLargeRenderKeepsBatchPaths() {
        let ec = ECharts(width: 400, height: 300)
        var opt = option(twoPointData(5_003), large: true, polyline: false)
        var series = (opt["series"] as? [[String: Any]]) ?? []
        series[0]["progressive"] = 5_001.0
        series[0]["progressiveThreshold"] = 2.0
        series[0]["blendMode"] = "lighter"
        opt["series"] = series
        ec.setOption(opt)

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 2,
                       "completed static render should preserve the two progressive batch strokes")
        XCTAssertEqual((paths[0].shape as? LargeLinesPathShape)?.segs.count, 5_001 * 4)
        XCTAssertEqual((paths[1].shape as? LargeLinesPathShape)?.segs.count, 2 * 4)
    }

    func testCompletedProgressiveLargePolylineKeepsBatchPaths() {
        let ec = ECharts(width: 400, height: 300)
        let data: [[String: Any]] = (0..<5_003).map { i in
            ["coords": [[Double(i), 0.0], [Double(i), 10.0]]] as [String: Any]
        }
        var opt = option(data, large: true, polyline: true)
        var series = (opt["series"] as? [[String: Any]]) ?? []
        series[0]["progressive"] = 5_001.0
        series[0]["progressiveThreshold"] = 2.0
        series[0]["blendMode"] = "lighter"
        opt["series"] = series
        ec.setOption(opt)

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 2,
                       "completed polyline render should preserve progressive additive batches")
        XCTAssertEqual((paths[0].shape as? LargeLinesPathShape)?.segs.count, 5_001 * 5)
        XCTAssertEqual((paths[1].shape as? LargeLinesPathShape)?.segs.count, 2 * 5)
    }

    // An item with a coord count OTHER than 2 must NOT shift the packing: upstream's fixed-size
    // Float32Array silently drops the overflow, keeping segs a multiple of 4. Appending would both
    // mis-pair every later segment and trap in buildPath.
    // The fixture OVERFLOWS on purpose: 3 items → a 3*4 = 12-slot buffer, but 3 coords each means 18
    // writes are attempted. Without linesLayout's bound guard this traps
    // (`ContiguousArrayBuffer.swift: Fatal error: Index out of range`).
    func testNonTwoCoordItemKeepsBufferAligned() {
        let ec = ECharts(width: 400, height: 300)
        let data: [[String: Any]] = (0..<3).map { i in
            ["coords": [[Double(i), 0.0], [Double(i), 5.0], [Double(i), 10.0]]] as [String: Any]
        }

        ec.setOption(option(data, large: true, polyline: false))

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 1)
        let segs = (paths[0].shape as? LargeLinesPathShape)?.segs ?? []
        XCTAssertEqual(segs.count, data.count * 4,
                       "the buffer stays FIXED-SIZE (4 per item) regardless of per-item coord counts")
        XCTAssertEqual(segs.count % 4, 0, "LAYOUT INVARIANT holds with non-2-coord items")

        // And it actually paints without trapping (buildPath walks the whole buffer).
        let ctx = PathProxy()
        paths[0].buildPath(ctx, paths[0].shape, false)
    }

    // Polyline large mode → the buffer is count-PREFIXED: [len, x,y * len] per item.
    func testLargePolylineBufferIsCountPrefixed() {
        let ec = ECharts(width: 400, height: 300)
        let data: [[String: Any]] = [
            ["coords": [[0.0, 0.0], [1.0, 1.0], [2.0, 0.0]]],
            ["coords": [[3.0, 0.0], [4.0, 2.0]]],
            ["coords": [[5.0, 1.0], [6.0, 3.0], [7.0, 1.0], [8.0, 4.0]]]
        ]
        ec.setOption(option(data, large: true, polyline: true))

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 1)
        let shape = paths[0].shape as? LargeLinesPathShape
        XCTAssertEqual(shape?.polyline, true, "the large path is told it is drawing polylines")

        // segCount + totalCoordsCount * 2 == 3 + (3 + 2 + 4) * 2
        XCTAssertEqual(shape?.segs.count, 3 + 9 * 2)
        // The per-item length prefixes sit where the packing says they do.
        let segs = shape?.segs ?? []
        XCTAssertEqual(segs.first, 3, "first item's coord-count prefix")
        XCTAssertEqual(segs[1 + 3 * 2], 2, "second item's coord-count prefix")
        XCTAssertEqual(segs[1 + 3 * 2 + 1 + 2 * 2], 4, "third item's coord-count prefix")
    }

    // Below largeThreshold the large path must NOT be taken, even with `large: true`.
    func testBelowThresholdStaysNormal() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option(twoPointData(1), large: true, polyline: false))
        XCTAssertEqual(largePaths(ec).count, 0,
                       "count < largeThreshold keeps the per-item LineDraw path")
        XCTAssertGreaterThan(namedLineCount(ec), 0, "per-item elements are drawn instead")
    }

    // Toggling large ↔ normal across setOption calls swaps the draw cleanly in BOTH directions:
    // no per-item leftovers under the large path, and no stale LargeLinesPath after flipping back.
    func testLargeNormalToggleSwapsDrawsCleanly() {
        let ec = ECharts(width: 400, height: 300)

        // normal first — per-item elements, no large path.
        ec.setOption(option(twoPointData(3), large: false, polyline: false))
        XCTAssertEqual(largePaths(ec).count, 0)
        let normalCount = namedLineCount(ec)
        XCTAssertGreaterThan(normalCount, 0)

        // → large: one buffer path, and the per-item elements are gone.
        ec.setOption(option(twoPointData(3), large: true, polyline: false))
        XCTAssertEqual(largePaths(ec).count, 1, "flip to large installs the LargeLinesPath")
        XCTAssertEqual(namedLineCount(ec), 0, "flip to large tears down the per-item elements")

        // → back to normal: the large path is gone and the per-item elements are re-entered fresh
        //   (this is what LineDraw.reset() buys — a diff against stale pre-large data would otherwise
        //   tween them from the wrong state).
        ec.setOption(option(twoPointData(3), large: false, polyline: false))
        XCTAssertEqual(largePaths(ec).count, 0, "flip back to normal drops the LargeLinesPath")
        XCTAssertEqual(namedLineCount(ec), normalCount,
                       "flip back to normal restores exactly the per-item elements")
    }
}
