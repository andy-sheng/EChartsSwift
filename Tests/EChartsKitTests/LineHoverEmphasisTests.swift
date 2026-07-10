import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: hovering a line series highlighted neither the polyline nor the area polygon —
// upstream LineView (LineView.ts:827-900) wires setStatesStylesFromModel(polyline,'lineStyle') /
// (polygon,'areaStyle') + toggleHoverEmphasis on both, and links every data symbol's
// onHoverStateChange to _changePolyState so hovering a point also flips the line + area into
// emphasis (LineView.ts:893-900, 1029-1033).
final class LineHoverEmphasisTests: XCTestCase {
    private var option: [String: Any] {
        ["animation": false,
         "xAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
         "yAxis": ["type": "value"],
         "series": [["type": "line", "data": [10, 20, 30],
                     "areaStyle": [String: Any](),
                     "emphasis": ["focus": "series",
                                  "lineStyle": ["width": 6.0] as [String: Any],
                                  "areaStyle": ["opacity": 1.0] as [String: Any]] as [String: Any]]
                    as [String: Any]]]
    }

    private func findPoly(_ v: EChartsView) -> (line: Polyline?, area: ThemeRiverBand?) {
        var line: Polyline?; var area: ThemeRiverBand?
        _ = v.ec.getRoot().traverse { el in
            if el.name == "line", let p = el as? Polyline { line = p }
            if el.name == "area", let a = el as? ThemeRiverBand { area = a }
            return false
        }
        return (line, area)
    }

    func testHoverSymbolEmphasizesLineAndArea() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(option)
        _ = v.zr.storage.getDisplayList(true)
        let (lineOpt, areaOpt) = findPoly(v)
        guard let polyline = lineOpt, let area = areaOpt else {
            XCTFail("line + area elements must render"); return
        }
        XCTAssertEqual(polyline.pathStyle?.lineWidth, 2, "baseline lineWidth")
        XCTAssertEqual(area.pathStyle?.opacity ?? 1, 0.7, accuracy: 1e-9, "baseline area opacity")

        // Hover the middle data symbol.
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        guard let sym = data.getItemGraphicEl(1) else { XCTFail("symbol el"); return }
        v._injectPointerForTest(type: "mousemove", zrX: sym.x, zrY: sym.y)

        XCTAssertTrue(polyline.currentStates.contains("emphasis"),
                      "hovering a data symbol must flip the polyline into emphasis (states=\(polyline.currentStates))")
        XCTAssertEqual(polyline.pathStyle?.lineWidth, 6,
                       "emphasis.lineStyle.width must RENDER on the polyline")
        XCTAssertTrue(area.currentStates.contains("emphasis"),
                      "hovering a data symbol must flip the area into emphasis (states=\(area.currentStates))")
        XCTAssertEqual(area.pathStyle?.opacity ?? 0, 1.0, accuracy: 1e-6,
                       "emphasis.areaStyle.opacity must RENDER on the area")

        // Mouse out → both restore.
        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(polyline.currentStates.contains("emphasis"), "mouseout restores the line")
        XCTAssertEqual(polyline.pathStyle?.lineWidth, 2, "lineWidth restored")
        XCTAssertEqual(area.pathStyle?.opacity ?? 0, 0.7, accuracy: 1e-6, "area opacity restored")
    }

    func testHoverPolylineDirectlyEmphasizes() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(option)
        _ = v.zr.storage.getDisplayList(true)
        guard let polyline = findPoly(v).line,
              let shape = polyline.shape as? PolylineShape,
              let points = shape.points, points.count >= 2 else {
            XCTFail("polyline with points must render"); return
        }
        // Pointer on the segment midpoint between the first two vertices.
        let p0 = points[0], p1 = points[1]
        v._injectPointerForTest(type: "mousemove", zrX: (p0.x + p1.x) / 2, zrY: (p0.y + p1.y) / 2)
        XCTAssertTrue(polyline.currentStates.contains("emphasis"),
                      "hovering the line itself must enter emphasis (states=\(polyline.currentStates))")
        XCTAssertEqual(polyline.pathStyle?.lineWidth, 6, "emphasis.lineStyle.width must render")
    }
}
