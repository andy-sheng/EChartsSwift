// END-TO-END RENDER TEST — the Phase 22 milestone proof that a cartesian heatmap option renders through
// ZRenderKit AND that heatmap + visualMap work together. Builds the slim driver (`ECharts`) with a
// category×category heatmap ([x, y, value] data) + a CONTINUOUS visualMap, runs the full setOption/update
// cycle, and inspects the produced scene graph: one `Rect` per data cell (the HeatmapView cartesian
// colored-Rect path), each carrying a fill the visualMap VISUAL stage encoded. The KEY assertion is that
// the cell fills VARY across the value range (>= 2 distinct colors) — proving the visualMap encoding
// colored the cells (a heatmap without visualMap would draw uncolored cells).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class HeatmapRenderTests: XCTestCase {

    // Other suites register test doubles into the GLOBAL ComponentModel registry (e.g. CartesianCoordTests
    // installs Test{X,Y}AxisModel, which — unlike the real Slim axis models — never merge the category
    // `boundaryGap: true` default, so their category axes are NOT onBand). Heatmap on cartesian REQUIRES two
    // onBand category axes (the faithful __DEV__ guard traps otherwise), so re-register the real Slim axis
    // models + the heatmap series model here to make this suite order-independent (same pattern as
    // BarChartRenderTests re-registering BarSeriesModel).
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(SlimXAxisModel.self)
        ComponentModel.registerClass(SlimYAxisModel.self)
        ComponentModel.registerClass(HeatmapSeriesModel.self)
    }

    /// A 5×3 category grid with an ascending value field, colored by a continuous visualMap.
    private func heatmapOption() -> [String: Any] {
        return [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri"]] as [String: Any],
            "yAxis": ["type": "category", "data": ["AM", "PM", "Eve"]] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 10.0,
                "calculable": true,
                "inRange": ["color": ["#313695", "#74add1", "#fee090", "#f46d43", "#a50026"]] as [String: Any]
            ] as [String: Any],
            "series": [[
                "type": "heatmap",
                "data": [
                    [0.0, 0.0, 1.0], [1.0, 0.0, 3.0], [2.0, 0.0, 5.0], [3.0, 0.0, 7.0], [4.0, 0.0, 9.0],
                    [0.0, 1.0, 2.0], [1.0, 1.0, 4.0], [2.0, 1.0, 6.0], [3.0, 1.0, 8.0], [4.0, 1.0, 10.0],
                    [0.0, 2.0, 0.0], [1.0, 2.0, 2.0], [2.0, 2.0, 4.0], [3.0, 2.0, 6.0], [4.0, 2.0, 8.0]
                ]
            ] as [String: Any]]
        ]
    }

    func testHeatmapRendersColoredCells() {
        let width = 400.0, height = 300.0
        let ec = ECharts(width: width, height: height)
        ec.setOption(heatmapOption())

        // The visualMap component resolved to the continuous subtype and loaded.
        var visualMapCount = 0
        ec.getModel()?.eachComponent("visualMap") { model, _ in
            XCTAssertEqual(model.type, "visualMap.continuous", "bare visualMap → continuous subtype")
            visualMapCount += 1
        }
        XCTAssertEqual(visualMapCount, 1, "one visualMap component should load")

        // The real data pipeline built the 15 cells.
        guard let seriesModel = firstSeries(ec) else { return XCTFail("no series model") }
        let data = seriesModel.getData()
        let cellCount = data.count()
        XCTAssertEqual(cellCount, 15, "heatmap should build 15 cell rows")

        // ---- 1. One Rect graphic element per data cell (HeatmapView.setItemGraphicEl). ----
        var cells: [Rect] = []
        for i in 0..<cellCount {
            if let rect = data.getItemGraphicEl(i) as? Rect {
                cells.append(rect)
            }
        }
        XCTAssertGreaterThan(cells.count, 0, "heatmap should emit at least one cell Rect")
        XCTAssertEqual(cells.count, cellCount, "one Rect per data cell")

        // Every cell Rect is also live in the scene graph (added to the root group).
        var rectsInScene = 0
        _ = ec.getRoot().traverse { el in
            if el is Rect { rectsInScene += 1 }
            return false
        }
        XCTAssertGreaterThanOrEqual(rectsInScene, cellCount, "cell Rects should be in the scene graph")

        // Cell geometry is finite and sized (band width/height + 0.5px).
        for r in cells {
            guard let s = r.shape as? RectShape else { XCTFail("cell should be a RectShape"); continue }
            XCTAssertTrue(s.x.isFinite && s.y.isFinite && s.width.isFinite && s.height.isFinite,
                          "finite cell geometry")
            XCTAssertGreaterThan(s.width, 0, "cell has positive width")
            XCTAssertGreaterThan(s.height, 0, "cell has positive height")
        }

        // ---- 2. Cells carry the visualMap-encoded fill, and those fills VARY across the value range. ----
        var fills: [String] = []
        for r in cells {
            guard let fill = r.pathStyle?.fill else {
                XCTFail("heatmap cell should have a fill from the visualMap encoding stage"); continue
            }
            if case let .string(s) = fill, !s.isEmpty {
                fills.append(s)
            } else {
                XCTFail("cell fill should be a non-empty solid color, got \(fill)")
            }
        }
        XCTAssertEqual(fills.count, cellCount, "every cell should carry an encoded fill")

        // The KEY assertion: heatmap + visualMap work together — the encoding mapped the value range to
        // MULTIPLE distinct gradient colors (a heatmap with no visualMap would leave cells uncolored, and a
        // single flat color would fail this).
        XCTAssertGreaterThanOrEqual(Set(fills).count, 2,
            "the visualMap encoding should color cells with >= 2 distinct fills across the value range")

        // Also confirm the encoded fill differs from the plain Rect default black — the encoding really ran.
        XCTAssertFalse(fills.allSatisfy { $0 == "#000" || $0 == "#000000" },
                       "cell fills should be visualMap colors, not the default black")
    }

    // MARK: helpers
    private func firstSeries(_ ec: ECharts) -> SeriesModel? {
        var found: SeriesModel?
        ec.getModel()?.eachSeries { s, _ in if found == nil { found = s } }
        return found
    }
}
