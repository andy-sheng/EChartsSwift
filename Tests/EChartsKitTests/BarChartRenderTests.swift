// END-TO-END RENDER TEST — the milestone proof that an ECharts option renders a bar chart through
// ZRenderKit. Builds the slim driver (`EChartsSlim`) with a cartesian bar option, runs the full
// setOption/update cycle, and inspects the produced ZRenderKit scene graph (the root `Group`): four
// bar `Rect`s, each within the grid rect, with monotonic heights, left→right x order, and palette
// fills. If NativePainter's `CALayerPainter` is reachable, the paint path is also exercised via
// `renderToImage`.
//
// Phase 6c: uses the REAL `BarSeriesModel` — its `getInitialData → createSeriesData →
// SourceManager.getSource()` now builds the data straight from the option's own `series.data`
// ([10,20,30,40] on a category axis → the four [categoryIndex, value] rows). No test double.

import XCTest
import ZRenderKit
@testable import EChartsKit

#if canImport(QuartzCore) && canImport(CoreGraphics)
import NativePainter
import CoreGraphics
#endif

final class BarChartRenderTests: XCTestCase {

    // Other suites register empty-data `series.bar` doubles into the GLOBAL ComponentModel registry;
    // re-register the real model so this test (which uses the real data pipeline) is order-independent.
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    // Grid option: left 50, top 20, width 300, height 200 (the B4 grid-layout fix is applied, so the
    // grid rect really is {50, 20, 300, 200} — see CartesianCoordTests).
    private func barChartOption() -> [String: Any] {
        return [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ]
    }

    /// Collect every bar `Rect` (BarView names each bar element "item") from the root group.
    private func collectBars(_ root: Group) -> [Rect] {
        var bars: [Rect] = []
        _ = root.traverse { el in
            if let rect = el as? Rect, rect.name == "item" {
                bars.append(rect)
            }
            return false
        }
        return bars
    }

    func testBarChartRendersFourBars() {
        let width = 400.0, height = 300.0
        let ec = EChartsSlim(width: width, height: height)
        ec.setOption(barChartOption())

        // ---- 1. Four bar Rects were emitted. ----
        let bars = collectBars(ec.getRoot())
        XCTAssertEqual(bars.count, 4, "a bar chart with 4 data points should emit 4 bar Rects")
        guard bars.count == 4 else { return }

        // Read each bar's shape rect.
        struct BarRect { let x, y, w, h: Double; let rect: Rect }
        func shapeOf(_ r: Rect) -> BarRect {
            let s = r.shape as! RectShape
            return BarRect(x: s.x, y: s.y, w: s.width, h: s.height, rect: r)
        }
        let shapes = bars.map(shapeOf)

        // ---- 2. The grid rect the bars must live within. Read it from the series' injected
        //         coordinate system (authoritative), not from the option. ----
        var gridArea: BoundingRect?
        ec.getModel()?.eachSeries { s, _ in
            if let c = s.coordinateSystem as? Cartesian2D { gridArea = c.getArea() }
        }
        guard let grid = gridArea else {
            XCTFail("series should have a cartesian2d coordinate system with an area"); return
        }
        let gx = grid.x, gy = grid.y, gw = grid.width, gh = grid.height
        let tol = 0.5
        for b in shapes {
            // Normalize the (possibly negative-height, drawn-upward) rect to top/bottom/left/right.
            let left = Swift.min(b.x, b.x + b.w)
            let right = Swift.max(b.x, b.x + b.w)
            let top = Swift.min(b.y, b.y + b.h)
            let bottom = Swift.max(b.y, b.y + b.h)
            XCTAssertGreaterThanOrEqual(left, gx - tol, "bar left within grid")
            XCTAssertLessThanOrEqual(right, gx + gw + tol, "bar right within grid")
            XCTAssertGreaterThanOrEqual(top, gy - tol, "bar top within grid")
            XCTAssertLessThanOrEqual(bottom, gy + gh + tol, "bar bottom within grid")
            XCTAssertTrue(b.h.isFinite && b.w.isFinite && b.x.isFinite && b.y.isFinite, "finite geometry")
        }

        // ---- 3. x positions increase left→right (categories A,B,C,D). ----
        // Bars are added in data-index order; keep that order and confirm x is strictly increasing.
        for i in 1..<shapes.count {
            XCTAssertLessThan(shapes[i - 1].x, shapes[i].x,
                              "bar x positions should increase left→right with category index")
        }
        // Each bar sits under its category: its center x is nearer that category's tick than any other.
        // (Cross-check the first is at the left band and the last at the right band.)
        XCTAssertLessThan(shapes.first!.x, gx + gw / 2, "first category bar in the left half")
        XCTAssertGreaterThan(shapes.last!.x, gx + gw / 2, "last category bar in the right half")

        // ---- 4. Bar HEIGHTS are monotonic with the data (10<20<30<40 → taller bars). ----
        // Height is drawn upward (negative height in the rect), so compare magnitudes.
        let magnitudes = shapes.map { Swift.abs($0.h) }
        for i in 1..<magnitudes.count {
            XCTAssertGreaterThan(magnitudes[i], magnitudes[i - 1],
                                 "bar heights should grow with data value (bar for 40 is tallest)")
        }
        // The tallest bar corresponds to the rightmost (value 40) category.
        XCTAssertEqual(magnitudes.firstIndex(of: magnitudes.max()!), magnitudes.count - 1,
                       "the last (value 40) bar is the tallest")

        // ---- 5. Fill colors come from the palette (non-empty strings). ----
        for b in shapes {
            guard let fill = b.rect.pathStyle?.fill else {
                XCTFail("bar should have a fill from the visual/palette stage"); continue
            }
            if case let .string(s) = fill {
                XCTAssertFalse(s.isEmpty, "bar fill color should be a non-empty palette color")
            } else {
                XCTFail("bar fill should be a solid color string, got \(fill)")
            }
        }
        // All four bars share the single series' palette color (one series → one color).
        let fills: [String] = shapes.compactMap {
            if case let .string(s) = ($0.rect.pathStyle?.fill ?? .string("")) { return s }
            return nil
        }
        XCTAssertEqual(fills.count, 4)
        XCTAssertEqual(Set(fills).count, 1, "one bar series → one palette color across its 4 bars")

        // The fill must be a REAL palette color from the ecModel `color` option — not the Rect default
        // (#000) nor an arbitrary value. Confirm it is a member of the global palette.
        let palette = (ec.getModel()?.get("color", true) as? [String]) ?? []
        XCTAssertFalse(palette.isEmpty, "the global color palette should be populated")
        if let barFill = fills.first {
            XCTAssertTrue(palette.contains(barFill),
                          "bar fill \(barFill) should come from the palette \(palette.prefix(3))…")
            XCTAssertNotEqual(barFill, "#000", "bar fill should be a palette color, not the default black")
        }

        // ---- 6. (Optional) paint path executes: render the scene to an image. ----
        #if canImport(QuartzCore) && canImport(CoreGraphics)
        let image = renderToImage(
            group: ec.getRoot(),
            size: CGSize(width: width, height: height),
            dpr: 1.0
        )
        XCTAssertNotNil(image, "CALayerPainter should render the bar scene to a non-nil image")
        if let image = image {
            XCTAssertEqual(image.width, Int(width), "rendered image width")
            XCTAssertEqual(image.height, Int(height), "rendered image height")
        }
        #endif

    }

    // MARK: - Ported upstream bar/axis unit specs (need createChart / orchestrator → skipped)

    // The only bar/axis-adjacent specs under `test/ut/spec` (`api/getVisual.test.ts` — bar item color
    // from the palette via `chart.getVisual`; `series/aria-columns-exclude.test.ts`) drive a full
    // `echarts` instance via `createChart(...)` (ChartView map + Scheduler + data pipeline), which is
    // Phase 6b and not ported. The bar-visual palette behavior that `getVisual` asserts is exercised
    // DIRECTLY by assertion (5) above (bars carry a non-empty palette fill), so this is a documented
    // skip rather than a duplicate.
    func test_api_getVisual_barColorFromPalette() throws {
        throw XCTSkip("Needs createChart + ChartView map + Scheduler + data pipeline (chart.getVisual) — Phase 6b. "
            + "Bar palette-fill behavior is covered directly by testBarChartRendersFourBars assertion 5.")
    }
}
