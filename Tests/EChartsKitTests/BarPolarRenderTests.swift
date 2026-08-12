// END-TO-END RENDER TEST for polar-coordinate bar rendering (BarView.swift `_renderPolarBars`).
// Drives ECharts with the canonical bar-on-polar option (category angleAxis + value radiusAxis,
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

    private func makePolarBarChart() -> ECharts {
        let ec = ECharts(width: 380, height: 360)
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

    // ---------------------------------------------------------------------------------------------
    // TANGENTIAL bars (baseAxis.dim == 'radius': a category radiusAxis + value angleAxis) with
    // `roundCap: true` → `elementCreatorPolar` picks `SausagePath` (`(!isRadial && roundCap)`).
    // ---------------------------------------------------------------------------------------------

    private func makeTangentialBarChart(roundCap: Bool) -> ECharts {
        let ec = ECharts(width: 380, height: 360)
        ec.setOption([
            "polar": [String: Any](),
            "angleAxis": [String: Any](),
            "radiusAxis": ["type": "category", "data": ["a", "b", "c", "d", "e", "f"]] as [String: Any],
            "series": [["type": "bar", "coordinateSystem": "polar",
                        "roundCap": roundCap,
                        "data": values] as [String: Any]]
        ])
        return ec
    }

    /// Collect every bar element (BarView names each bar element "item") from the root group.
    private func collectItems(_ root: Group) -> [Path] {
        var out: [Path] = []
        _ = root.traverse { el in
            if let p = el as? Path, p.name == "item" { out.append(p) }
            return false
        }
        return out
    }

    func testTangentialRoundCapBarRendersSausagePerDatum() {
        let ec = makeTangentialBarChart(roundCap: true)
        let items = collectItems(ec.getRoot())

        XCTAssertEqual(items.count, values.count,
                       "a tangential polar bar with \(values.count) points → \(values.count) elements")
        guard items.count == values.count else { return }

        for el in items {
            XCTAssertEqual(el.type, "sausage", "roundCap tangential polar bars use SausagePath")
            XCTAssertTrue(el is SausagePath, "element should be a SausagePath instance")
        }

        let shapes = items.compactMap { $0.shape as? SausageShape }
        XCTAssertEqual(shapes.count, values.count, "every element carries a SausageShape")
        guard shapes.count == values.count else { return }

        // Geometry comes from layout/barPolar (read back via getLayoutPolar): a shared pole, a shared
        // baseline startAngle (value 0), a per-category radial band, and a per-value angular sweep.
        let cx0 = shapes[0].cx, cy0 = shapes[0].cy, start0 = shapes[0].startAngle
        for s in shapes {
            XCTAssertEqual(s.cx, cx0, accuracy: 1e-6, "all bars share the polar center x")
            XCTAssertEqual(s.cy, cy0, accuracy: 1e-6, "all bars share the polar center y")
            XCTAssertEqual(s.startAngle, start0, accuracy: 1e-6, "all tangential bars start at the value-0 angle")
            XCTAssertTrue(s.r.isFinite && s.r0.isFinite && s.cx.isFinite && s.cy.isFinite
                          && s.startAngle.isFinite && s.endAngle.isFinite, "finite sausage geometry")
            XCTAssertGreaterThan(s.r, s.r0, "each bar occupies a non-degenerate radial band")
            XCTAssertNotEqual(s.startAngle, s.endAngle, "each bar sweeps a non-zero angle")
        }
        // One radial band per radius-axis category.
        XCTAssertEqual(Set(shapes.map { $0.r0 }).count, values.count, "one radial band per category")

        // Larger value ⇒ larger angular sweep, pairwise.
        let sweep = shapes.map { abs($0.endAngle - $0.startAngle) }
        for i in 0..<values.count {
            for j in 0..<values.count where values[i] < values[j] {
                XCTAssertLessThan(sweep[i], sweep[j], "value \(values[i]) < \(values[j]) ⇒ shorter sweep")
            }
        }
    }

    func testRoundCapToggleRecreatesElementAsSector() {
        let ec = makeTangentialBarChart(roundCap: true)
        let before = collectItems(ec.getRoot()).filter { $0.type == "sausage" }
        XCTAssertEqual(before.count, values.count, "baseline: every bar is a sausage")
        guard let firstBefore = before.first else { return }

        // Merge-mode setOption flipping roundCap → `roundCapChanged` in `_renderPolarBars` must remove
        // the old element and create a fresh `Sector` (there is no sausage→sector tween).
        ec.setOption(["series": [["type": "bar", "coordinateSystem": "polar",
                                  "roundCap": false, "data": values] as [String: Any]]])

        let after = collectItems(ec.getRoot()).filter { $0.type == "sector" }
        XCTAssertEqual(after.count, values.count, "after roundCap:false every bar is a sector")
        XCTAssertFalse(after.contains(where: { $0 === firstBefore }),
                       "the element is recreated, not reused")
        for el in after {
            XCTAssertTrue(el is Sector, "recreated element should be a Sector instance")
        }
    }

    func testRadialPolarBarMiddleLabelsUseAutomaticSectorRotation() {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption([
            "polar": ["radius": [30.0, "80%"] as [Any]] as [String: Any],
            "radiusAxis": ["max": 4.0] as [String: Any],
            "angleAxis": [
                "type": "category", "data": ["a", "b", "c", "d"], "startAngle": 75.0
            ] as [String: Any],
            "series": [[
                "type": "bar", "coordinateSystem": "polar", "data": [2.0, 1.2, 2.4, 3.6],
                "label": ["show": true, "position": "middle", "formatter": "{b}: {c}"] as [String: Any]
            ] as [String: Any]],
            "animation": false
        ])

        let sectors = collectSectors(ec.getRoot())
        XCTAssertEqual(sectors.count, 4)
        let rotations = sectors.compactMap { $0.textConfig?.rotation }
        XCTAssertEqual(rotations.count, 4, "every visible polar bar label receives auto rotation")
        XCTAssertTrue(rotations.contains { abs($0) > 0.1 }, "polar labels must not all remain horizontal")
        XCTAssertGreaterThan(Set(rotations.map { ($0 * 1_000).rounded() }).count, 2,
                             "rotation follows each sector's own anchor angle")
    }

    func testTangentialPolarBarMiddleLabelsUseEachRingMidpoint() {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption([
            "polar": ["radius": [30.0, "80%"] as [Any]] as [String: Any],
            "angleAxis": ["max": 4.0, "startAngle": 75.0] as [String: Any],
            "radiusAxis": ["type": "category", "data": ["a", "b", "c", "d"]] as [String: Any],
            "series": [[
                "type": "bar", "coordinateSystem": "polar", "data": [2.0, 1.2, 2.4, 3.6],
                "label": ["show": true, "position": "middle", "formatter": "{b}: {c}"] as [String: Any]
            ] as [String: Any]],
            "animation": false
        ])

        let sectors = collectSectors(ec.getRoot())
        XCTAssertEqual(sectors.count, 4)
        _ = ec.getStorage().getDisplayList(true)
        let labelPoints = sectors.compactMap { sector -> String? in
            guard let t = sector.getTextContent()?.innerTransformable else { return nil }
            return "\((t.x * 10).rounded())|\((t.y * 10).rounded())"
        }
        XCTAssertEqual(labelPoints.count, 4)
        XCTAssertEqual(Set(labelPoints).count, 4,
                       "each tangential ring label must use its own sector midpoint, not one shared bbox point")
    }
}

#if canImport(QuartzCore) && canImport(CoreGraphics)
import CoreGraphics
import NativePainter
#endif
