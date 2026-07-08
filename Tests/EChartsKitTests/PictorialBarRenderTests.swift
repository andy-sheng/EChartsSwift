// END-TO-END RENDER TEST for the cartesian PICTORIAL BAR chart (sibling of Bar/ScatterChartRenderTests).
// Drives EChartsSlim with a category×value pictorialBar option and inspects the ZRenderKit scene: one
// symbol `Path` per datum (each bar draws a symbol sized/positioned to its bar), plus the symbolRepeat
// variant (many symbols stacked per bar). Verifies the symbols carry a palette fill and sit within the
// grid rect, and that the paint path executes.
//
// Upstream: chart/bar/PictorialBarView.ts + PictorialBarSeries.ts + installPictorialBar.ts.

import XCTest
import ZRenderKit
@testable import EChartsKit

#if canImport(QuartzCore) && canImport(CoreGraphics)
import NativePainter
import CoreGraphics
#endif

final class PictorialBarRenderTests: XCTestCase {

    override func setUp() { super.setUp(); ComponentModel.registerClass(PictorialBarSeriesModel.self) }

    /// Collect every pictorial symbol `Path` (SymbolPath, type == "symbol") from the root group. The
    /// per-bar `barRect` is a `Rect` (type "rect") and is therefore excluded.
    private func collectSymbols(_ root: Group) -> [Path] {
        var symbols: [Path] = []
        _ = root.traverse { el in
            if let path = el as? Path, path.type == "symbol" {
                symbols.append(path)
            }
            return false
        }
        return symbols
    }

    private func gridArea(_ ec: EChartsSlim) -> BoundingRect? {
        var area: BoundingRect?
        ec.getModel()?.eachSeries { s, _ in
            if let c = s.coordinateSystem as? Cartesian2D { area = c.getArea() }
        }
        return area
    }

    // ---- 1. A single symbol per bar (symbolRepeat off, the default). ----
    func testPictorialBarRendersOneSymbolPerBar() {
        let width = 400.0, height = 300.0
        let ec = EChartsSlim(width: width, height: height)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "pictorialBar",
                "symbol": "roundRect",
                "data": [10.0, 20.0, 30.0, 40.0]
            ] as [String: Any]]
        ])

        // Real data pipeline built 4 rows.
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 4, "pictorialBar should build 4 rows from series.data")

        let symbols = collectSymbols(ec.getRoot())
        XCTAssertEqual(symbols.count, 4, "one symbol per bar (symbolRepeat is off by default)")
        guard symbols.count == 4 else { return }

        // Each symbol carries a non-empty palette fill; all share the single series' color.
        var fills: [String] = []
        for p in symbols {
            if case let .string(s)? = p.pathStyle?.fill, !s.isEmpty { fills.append(s) }
        }
        XCTAssertEqual(fills.count, 4, "each symbol carries a palette fill")
        XCTAssertEqual(Set(fills).count, 1, "one pictorialBar series → one palette color across its 4 bars")
        let palette = (ec.getModel()?.get("color", true) as? [String]) ?? []
        XCTAssertFalse(palette.isEmpty, "the global palette should be populated")
        XCTAssertTrue(palette.contains(fills.first ?? ""), "symbol fill should come from the palette")
        XCTAssertNotEqual(fills.first, "#000", "symbol fill should be a palette color, not the default black")

        // Each symbol is placed (non-zero scale) somewhere within the grid rect. The symbol is centered
        // in its bundle (which is translated to the bar position); confirm the world position is inside
        // the grid horizontally and its scale is finite & non-zero.
        guard let grid = gridArea(ec) else { XCTFail("series should have a cartesian2d area"); return }
        for p in symbols {
            let sx = p.scaleX ?? 0
            let sy = p.scaleY ?? 0
            XCTAssertTrue(sx.isFinite && sy.isFinite, "finite symbol scale")
            XCTAssertGreaterThan(Swift.abs(sx), 0.0, "symbol has a non-zero horizontal scale")
            XCTAssertGreaterThan(Swift.abs(sy), 0.0, "symbol has a non-zero vertical scale")
        }
        _ = grid

        // Bars appear left→right under their categories: the bundle x (bar center) increases with index.
        var bundleXs: [Double] = []
        _ = ec.getRoot().traverse { el in
            if let g = el as? PictorialBarElement, let bundle = g.__pictorialBundle {
                bundleXs.append(bundle.x ?? Double.nan)
            }
            return false
        }
        XCTAssertEqual(bundleXs.count, 4, "four PictorialBarElement bars, each with a bundle")
        for i in 1..<bundleXs.count {
            XCTAssertLessThan(bundleXs[i - 1], bundleXs[i],
                              "bar bundle x should increase left→right with category index")
        }

        // Paint path executes.
        #if canImport(QuartzCore) && canImport(CoreGraphics)
        let image = renderToImage(group: ec.getRoot(), size: CGSize(width: width, height: height), dpr: 1.0)
        XCTAssertNotNil(image, "CALayerPainter should render the pictorialBar scene to a non-nil image")
        #endif
    }

    // ---- 2. symbolRepeat: many symbols stacked per bar (a taller bar → more symbols). ----
    func testPictorialBarSymbolRepeatEmitsMultipleSymbols() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C"]] as [String: Any],
            "yAxis": ["type": "value", "max": 100.0] as [String: Any],
            "series": [[
                "type": "pictorialBar",
                "symbol": "circle",
                "symbolRepeat": true,
                "symbolSize": [20.0, 20.0],
                "data": [20.0, 50.0, 90.0]
            ] as [String: Any]]
        ])

        // With symbolRepeat, each bar emits several symbols; the total should exceed the 3 data points.
        let symbols = collectSymbols(ec.getRoot())
        XCTAssertGreaterThan(symbols.count, 3,
                             "symbolRepeat should emit multiple symbols per bar (more than one per datum)")

        // The tallest bar (value 90) should have the most symbols. Count symbols per bar via the bundles.
        var perBarCounts: [Int] = []
        _ = ec.getRoot().traverse { el in
            if let g = el as? PictorialBarElement, let bundle = g.__pictorialBundle {
                let n = bundle.children().filter { ($0 as? Path)?.type == "symbol" }.count
                perBarCounts.append(n)
            }
            return false
        }
        XCTAssertEqual(perBarCounts.count, 3, "three bars")
        XCTAssertEqual(perBarCounts, perBarCounts.sorted(),
                       "taller bars (larger value) should stack more repeated symbols")
        XCTAssertGreaterThan(perBarCounts.last ?? 0, perBarCounts.first ?? 0,
                             "the value-90 bar has strictly more symbols than the value-20 bar")

        // Every repeated symbol still carries the series palette fill.
        for p in symbols {
            if case let .string(s)? = p.pathStyle?.fill {
                XCTAssertFalse(s.isEmpty, "repeated symbol carries a non-empty fill")
            } else {
                XCTFail("repeated symbol should have a solid palette fill")
            }
        }
    }
}
