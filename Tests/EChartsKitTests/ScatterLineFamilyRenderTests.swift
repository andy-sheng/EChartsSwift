// END-TO-END RENDER TESTS for the effectScatter + lines verticals (Phase 18). Drives EChartsSlim with a
// cartesian option per chart and inspects the ZRenderKit scene:
//   - effectScatter: one static symbol `Path` per datum (name "item"), at a finite point, palette fill.
//   - lines: one Line/BezierCurve `Path` per data item (name "line"), at finite endpoints.
// The animated ripple (effectScatter) and moving-dot effect (lines) are documented PORT-TODOs, so only the
// static geometry is asserted.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ScatterLineFamilyRenderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(EffectScatterSeriesModel.self)
        ComponentModel.registerClass(LinesSeriesModel.self)
    }

    func testEffectScatterRendersOneSymbolPerDatum() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "effectScatter", "symbolSize": 14.0,
                        "data": [[10.0, 20.0], [20.0, 30.0], [30.0, 15.0], [40.0, 40.0]]] as [String: Any]]
        ])

        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 4, "effectScatter should build 4 rows from series.data")

        var symbols: [Path] = []
        _ = ec.getRoot().traverse { el in
            if let path = el as? Path, path.name == "item" { symbols.append(path) }
            return false
        }
        XCTAssertEqual(symbols.count, 4, "effectScatter should emit one static symbol per datum")

        // Each symbol sits at a finite position and carries a non-empty palette fill.
        var symbolFills: [String] = []
        for p in symbols {
            if let r = p.getBoundingRect() {
                XCTAssertTrue(r.x.isFinite && r.y.isFinite && r.width.isFinite && r.height.isFinite,
                              "symbol placed at a finite position")
            }
            if case let .string(s)? = p.pathStyle?.fill, !s.isEmpty { symbolFills.append(s) }
        }
        XCTAssertEqual(symbolFills.count, 4, "each symbol carries a palette fill")
        XCTAssertEqual(Set(symbolFills).count, 1, "one effectScatter series → one palette color")
    }

    func testLinesRendersOnePathPerSegment() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 50.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 50.0] as [String: Any],
            "series": [[
                "type": "lines",
                "coordinateSystem": "cartesian2d",
                "lineStyle": ["width": 2.0, "opacity": 1.0] as [String: Any],
                "data": [
                    ["coords": [[5.0, 5.0], [20.0, 30.0]]] as [String: Any],
                    ["coords": [[20.0, 30.0], [35.0, 10.0]]] as [String: Any],
                    // Curved segment → a BezierCurve rather than a straight Line.
                    ["coords": [[5.0, 40.0], [45.0, 40.0]],
                     "lineStyle": ["curveness": 0.3] as [String: Any]] as [String: Any]
                ]
            ] as [String: Any]]
        ])

        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 3, "lines should build one row per data item")

        var lines: [Path] = []
        _ = ec.getRoot().traverse { el in
            if let path = el as? Path, path.name == "line" { lines.append(path) }
            return false
        }
        XCTAssertEqual(lines.count, 3, "lines should emit one Line/BezierCurve per data item")

        // At least one straight Line and one BezierCurve (the curveness item bends into a quadratic curve).
        let straight = lines.filter { $0 is Line }.count
        let curved = lines.filter { $0 is BezierCurve }.count
        XCTAssertEqual(straight, 2, "two non-curved segments render as straight Lines")
        XCTAssertEqual(curved, 1, "the curveness segment renders as a BezierCurve")

        // Each line carries a finite-stroke, non-empty color.
        for p in lines {
            if case let .string(s)? = p.pathStyle?.stroke { XCTAssertFalse(s.isEmpty, "line stroke non-empty") }
        }
    }
}
