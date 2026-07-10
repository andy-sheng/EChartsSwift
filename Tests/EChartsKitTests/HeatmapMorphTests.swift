import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail: HeatmapView now PERSISTS its per-cell rects and MORPHS them on a same-cell-
// count merge-mode value change (the fill tweens to the new visualMap color) instead of rebuilding and
// snapping. Mirrors LineMorphTests. Asserts: (1) a cell Rect is identity-reused across the value change,
// (2) it schedules a color/shape-morph animator, and (3) a cell-count change rebuilds without duplication.
final class HeatmapMorphTests: XCTestCase {

    // Other suites register test doubles into the GLOBAL ComponentModel registry (their category axes are
    // NOT onBand → the faithful __DEV__ guard traps). Re-register the real axis + heatmap models here so
    // this suite is order-independent (same pattern as HeatmapRenderTests).
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(EChartsXAxisModel.self)
        ComponentModel.registerClass(EChartsYAxisModel.self)
        ComponentModel.registerClass(HeatmapSeriesModel.self)
    }

    private func baseOption(_ data: [[Double]], xCats: [String]) -> [String: Any] {
        return [
            "animation": true,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": xCats] as [String: Any],
            "yAxis": ["type": "category", "data": ["AM", "PM", "Eve"]] as [String: Any],
            "visualMap": [
                "type": "continuous", "min": 0.0, "max": 10.0, "calculable": true,
                "inRange": ["color": ["#313695", "#74add1", "#fee090", "#f46d43", "#a50026"]] as [String: Any]
            ] as [String: Any],
            "series": [[
                "type": "heatmap", "animation": true, "data": data
            ] as [String: Any]]
        ]
    }

    private func firstSeries(_ ec: ECharts) -> SeriesModel? {
        var found: SeriesModel?
        ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }

    // Count the cell Rects (named "item") live in the chart views' groups.
    private func cellCount(_ ec: ECharts) -> Int {
        var n = 0
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in if (el as? Rect)?.name == "item" { n += 1 }; return false })
        }
        return n
    }

    private func clearAnimators(_ ec: ECharts) {
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false })
        }
    }

    func testCellMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 300)
        // 3×3 grid, ascending values (cell 0 = value 1).
        let v1: [[Double]] = [
            [0, 0, 1], [1, 0, 3], [2, 0, 5],
            [0, 1, 2], [1, 1, 4], [2, 1, 6],
            [0, 2, 0], [1, 2, 2], [2, 2, 4]
        ]
        ec.setOption(baseOption(v1, xCats: ["Mon", "Tue", "Wed"]))
        guard let s1 = firstSeries(ec) else { return XCTFail("no series model") }
        let cell0 = s1.getData().getItemGraphicEl(0) as? Rect
        XCTAssertNotNil(cell0, "first render produced cell 0 Rect")

        // Clear the first render's enter/fade-in animators.
        clearAnimators(ec)
        XCTAssertEqual(cell0?.animators.count, 0, "animators cleared before the value change")

        // Merge-mode value change, SAME cell count, DIFFERENT values → the cell fill morphs.
        let v2: [[Double]] = [
            [0, 0, 9], [1, 0, 7], [2, 0, 5],
            [0, 1, 8], [1, 1, 6], [2, 1, 4],
            [0, 2, 10], [1, 2, 8], [2, 2, 6]
        ]
        ec.setOption(["series": [["type": "heatmap", "data": v2] as [String: Any]]])

        guard let s2 = firstSeries(ec) else { return XCTFail("no series model after merge") }
        let cell0b = s2.getData().getItemGraphicEl(0) as? Rect

        // (1) The SAME cell Rect instance is reused (not rebuilt).
        XCTAssertNotNil(cell0b)
        XCTAssertTrue(cell0 === cell0b, "cell Rect reused across the value change (not rebuilt)")

        // (2) It schedules a color/shape-morph animator (fill tweens current → new visualMap color).
        XCTAssertGreaterThan(cell0b!.animators.count, 0,
                             "cell must schedule a morph animator on a same-count value change")
    }

    func testCellCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 400, height: 300)
        let v1: [[Double]] = [
            [0, 0, 1], [1, 0, 3],
            [0, 1, 2], [1, 1, 4],
            [0, 2, 0], [1, 2, 2]
        ]
        ec.setOption(baseOption(v1, xCats: ["Mon", "Tue"]))
        XCTAssertEqual(cellCount(ec), 6, "6 cells on first render")

        // Grow the grid (3 x-categories → 9 cells): a cell-count change rebuilds fresh, no stale duplicates.
        let v2: [[Double]] = [
            [0, 0, 1], [1, 0, 3], [2, 0, 5],
            [0, 1, 2], [1, 1, 4], [2, 1, 6],
            [0, 2, 0], [1, 2, 2], [2, 2, 4]
        ]
        ec.setOption([
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed"]] as [String: Any],
            "series": [["type": "heatmap", "data": v2] as [String: Any]]
        ])
        XCTAssertEqual(cellCount(ec), 9, "a cell-count change rebuilds 9 cells, no duplication")
    }
}
