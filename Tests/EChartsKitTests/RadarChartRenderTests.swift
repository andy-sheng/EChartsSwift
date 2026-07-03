// END-TO-END RENDER TEST for the Phase-12 radar vertical: the radar COORDINATE SYSTEM (Radar +
// IndicatorAxis, the first non-cartesian coord sys wired) + the `radar` component backdrop
// (RadarComponentView draws one axis Line per indicator + merged split-line/area Paths) + RadarView
// (one Polyline outline + one Polygon area per data item, vertex positions from the radarLayout stage).
// Drives EChartsSlim with a real radar option and asserts BOTH the backdrop (axis Lines) and the
// series geometry (Polyline outlines + Polygon areas) reach the ZRenderKit scene graph.
//
// This also guards the full radar pipeline wiring: the coord-sys creator register (Radar.create builds
// one IndicatorAxis per indicator model), the coord-sys update stage (scaleCalcAlign fixes each axis to
// the split number), and the radarLayout stage (data.setItemLayout stores the closed point ring that
// RadarView reads back). Without any of these the series would render empty.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class RadarChartRenderTests: XCTestCase {
    func testRadarRendersBackdropAndSeries() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption([
            "radar": [
                "center": ["50%", "55%"],
                "radius": "65%",
                "indicator": [
                    ["name": "Sales", "max": 6500.0],
                    ["name": "Administration", "max": 16000.0],
                    ["name": "Information Technology", "max": 30000.0],
                    ["name": "Customer Support", "max": 38000.0],
                    ["name": "Development", "max": 52000.0]
                ]
            ] as [String: Any],
            "series": [[
                "type": "radar",
                "data": [
                    ["name": "Allocated Budget",
                     "value": [4200.0, 3000.0, 20000.0, 35000.0, 50000.0],
                     "areaStyle": ["opacity": 0.3] as [String: Any]] as [String: Any],
                    ["name": "Actual Spending",
                     "value": [5000.0, 14000.0, 28000.0, 26000.0, 42000.0],
                     "areaStyle": ["opacity": 0.3] as [String: Any]] as [String: Any]
                ]
            ] as [String: Any]]
        ])

        var axisLines = 0     // radar backdrop: one axis Line per indicator (AxisBuilder)
        var polylines = 0     // series outline: one Polyline per data item (RadarView)
        var polygons = 0      // series area: one Polygon per data item (RadarView)
        _ = ec.getRoot().traverse { el in
            if el is ZRenderKit.Polyline { polylines += 1 }
            else if el is ZRenderKit.Polygon { polygons += 1 }
            else if el is ZRenderKit.Line { axisLines += 1 }
            return false
        }

        XCTAssertGreaterThan(axisLines, 0, "radar backdrop → per-indicator axis Lines")
        XCTAssertGreaterThan(polylines, 0, "radar series → Polyline outlines")
        XCTAssertGreaterThan(polygons, 0, "radar series → Polygon area fills")
    }
}
