// END-TO-END RENDER TEST for the Phase-16 themeRiver (streamgraph) vertical on the SINGLE coordinate
// system: SingleAxisView draws the axis backdrop (an axisLine Line across the coord rect) and
// ThemeRiverView draws one filled Polygon band per named layer, positioned by the themeRiverLayout stage
// (each datum → {layerIndex,x,y0,y} band point via Single.dataToPoint). Drives EChartsSlim with a real
// themeRiver option on a singleAxis and asserts BOTH the singleAxis backdrop (an axis Line) AND the layer
// stream bands (one Polygon per layer) reach the ZRenderKit scene graph, plus a GEOMETRY guard: every
// band has a non-empty finite point ring that lands inside the chart view rect.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ThemeRiverRenderTests: XCTestCase {
    func testThemeRiverRendersAxisBackdropAndLayerBands() {
        let w = 520.0, h = 380.0
        let ec = EChartsSlim(width: w, height: h)
        // 3 named layers (Alpha/Beta/Gamma) over 5 time points (0…4) on a value-type singleAxis.
        ec.setOption([
            "singleAxis": ["type": "value", "left": "10%", "right": "10%",
                           "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "themeRiver",
                        "data": [
                            [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                            [3.0, 18.0, "Alpha"], [4.0, 14.0, "Alpha"],
                            [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"],
                            [3.0,  9.0, "Beta"],  [4.0, 13.0, "Beta"],
                            [0.0,  5.0, "Gamma"], [1.0,  9.0, "Gamma"], [2.0,  7.0, "Gamma"],
                            [3.0,  4.0, "Gamma"], [4.0, 10.0, "Gamma"]
                        ]] as [String: Any]]
        ])

        var axisLines = 0        // singleAxis backdrop: axisLine / tick / splitLine Line elements
        var bands: [ZRenderKit.Polygon] = [] // one filled band Polygon per layer (named "item")
        _ = ec.getRoot().traverse { el in
            if el.name == "item", let poly = el as? ZRenderKit.Polygon {
                bands.append(poly)
            }
            else if el is ZRenderKit.Line {
                axisLines += 1
            }
            return false
        }

        // Backdrop: the singleAxis reaches the scene graph as at least one Line (axisLine + ticks).
        XCTAssertGreaterThan(axisLines, 0, "singleAxis backdrop → axis Line(s)")

        // One band Polygon per named layer (3 layers: Alpha/Beta/Gamma).
        XCTAssertEqual(bands.count, 3, "themeRiver → one Polygon band per layer")

        // GEOMETRY GUARD: every band has a non-empty, finite point ring. Each of the 5 time points
        // contributes a top vertex (points0, forward) + a bottom vertex (points1, reversed) → 10 vertices.
        // The `x` of each vertex comes straight from Single.dataToPoint, so it must land inside the coord
        // rect's horizontal span [0, width]; the `y0`/`y0+y` values are group-local (the series group is
        // translated by group.y = rect.y + boundaryGap), so only finiteness + within-height are checked
        // after adding the group's y offset.
        for band in bands {
            guard let shape = band.shape as? ZRenderKit.PolygonShape,
                  let points = shape.points else {
                return XCTFail("band Polygon must carry a ZRenderKit.PolygonShape with points")
            }
            XCTAssertGreaterThan(points.count, 0, "band ring must be non-empty")
            XCTAssertEqual(points.count, 10, "5 time points → 10-vertex band ring (top + bottom)")
            // The series group carries the vertical offset; walk up the parent chain to accumulate it.
            var groupY = 0.0
            var node: Transformable? = band.parent
            while let n = node {
                groupY += n.y
                node = n.parent
            }
            for p in points {
                XCTAssertTrue(p.x.isFinite && p.y.isFinite, "band vertex must be finite")
                XCTAssertTrue(p.x >= -1 && p.x <= w + 1, "band x \(p.x) within view width \(w)")
                let gy = p.y + groupY   // add the accumulated series-group y offset
                XCTAssertTrue(gy >= -1 && gy <= h + 1, "band y \(gy) within view height \(h)")
            }
        }
    }
}
