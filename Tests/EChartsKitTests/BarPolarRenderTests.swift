// END-TO-END RENDER TEST for polar-coordinate bar rendering (BarView.swift `_renderPolarBars`).
// Drives EChartsSlim with the canonical bar-on-polar option (category angleAxis + value radiusAxis,
// mirrors the gallery `bar-polar-radial` demo) and asserts each datum becomes a ZRenderKit `Sector`
// (named "item") in the scene graph, centered on the polar pole, extending radially from r0 (value 0)
// to a per-value r, colored from the palette, and carrying the emphasis (highDown) state wiring.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class BarPolarRenderTests: XCTestCase {

    // Other suites register empty-data `series.bar` doubles into the GLOBAL registry; re-register the
    // real model so this test (real data pipeline) is order-independent (matches BarChartRenderTests).
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    private let values: [Double] = [4, 7, 5, 9, 6, 8]

    private func makePolarBarChart() -> EChartsSlim {
        let ec = EChartsSlim(width: 380, height: 360)
        ec.setOption([
            "polar": [String: Any](),
            "angleAxis": ["type": "category", "data": ["a", "b", "c", "d", "e", "f"]] as [String: Any],
            "radiusAxis": [String: Any](),
            "series": [["type": "bar", "coordinateSystem": "polar",
                        "data": values] as [String: Any]]
        ])
        return ec
    }

    /// Collect every bar `Sector` (BarView names each bar element "item") from the root group.
    private func collectSectors(_ root: Group) -> [Sector] {
        var out: [Sector] = []
        _ = root.traverse { el in
            if let s = el as? Sector, s.name == "item" { out.append(s) }
            return false
        }
        return out
    }

    func testPolarBarRendersSectorPerDatum() {
        let ec = makePolarBarChart()
        let sectors = collectSectors(ec.getRoot())

        // ---- 1. One Sector per datum. ----
        XCTAssertEqual(sectors.count, values.count, "a polar bar with \(values.count) points → \(values.count) Sectors")
        guard sectors.count == values.count else { return }

        // Read each sector's shape.
        let shapes = sectors.map { $0.shape as! SectorShape }

        // ---- 2. All share the polar pole (cx, cy) and a common inner radius r0; each grows radially. ----
        let cx0 = shapes[0].cx, cy0 = shapes[0].cy, r0base = shapes[0].r0
        for s in shapes {
            XCTAssertEqual(s.cx, cx0, accuracy: 1e-6, "all bars share the polar center x")
            XCTAssertEqual(s.cy, cy0, accuracy: 1e-6, "all bars share the polar center y")
            XCTAssertEqual(s.r0, r0base, accuracy: 1e-6, "all bars share the inner radius r0 (value 0)")
            XCTAssertTrue(s.r.isFinite && s.cx.isFinite && s.cy.isFinite
                          && s.startAngle.isFinite && s.endAngle.isFinite, "finite sector geometry")
            XCTAssertGreaterThan(s.r, s.r0, "bar extends outward from r0 to r")
            // A non-degenerate angular band.
            XCTAssertNotEqual(s.startAngle, s.endAngle, "bar spans a non-zero angular band")
        }

        // ---- 3. Radius increases with the datum value (the value-9 bar is the longest). ----
        let maxIdx = values.firstIndex(of: values.max()!)!
        let longest = shapes.map { $0.r }.firstIndex(of: shapes.map { $0.r }.max()!)!
        XCTAssertEqual(longest, maxIdx, "the largest value maps to the longest (largest r) bar")
        // Larger value ⇒ larger r, pairwise.
        for i in 0..<values.count {
            for j in 0..<values.count where values[i] < values[j] {
                XCTAssertLessThan(shapes[i].r, shapes[j].r, "value \(values[i]) < \(values[j]) ⇒ shorter bar")
            }
        }

        // ---- 4. Fills come from the palette (non-empty solid color, not the #000 default). ----
        for s in sectors {
            guard let fill = s.pathStyle?.fill, case let .string(c) = fill else {
                XCTFail("polar bar Sector should carry a solid palette fill"); continue
            }
            XCTAssertFalse(c.isEmpty, "sector fill should be a non-empty palette color")
            XCTAssertNotEqual(c, "#000", "sector fill should be a palette color, not default black")
        }

        // ---- 5. Emphasis wiring: each bar is a highDown dispatcher with an emphasis state (hover). ----
        for s in sectors {
            XCTAssertNotNil(s.states["emphasis"], "each polar bar carries an emphasis state (setStatesStylesFromModel)")
        }

        // ---- 6. Paint path executes. ----
        #if canImport(QuartzCore) && canImport(CoreGraphics)
        let image = renderToImage(group: ec.getRoot(), size: CGSize(width: 380, height: 360), dpr: 1.0)
        XCTAssertNotNil(image, "CALayerPainter should render the polar-bar scene to a non-nil image")
        #endif
    }
}

#if canImport(QuartzCore) && canImport(CoreGraphics)
import CoreGraphics
import NativePainter
#endif
