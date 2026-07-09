// END-TO-END RENDER TESTS for the Phase-8 chart verticals: funnel (Polygon trapezoids), candlestick
// (NormalBoxPath body+whiskers), boxplot (BoxPath box+median+whiskers). Each drives ECharts with a
// real option and asserts one shape per datum reaches the ZRenderKit scene. Also guards the ZRenderKit
// getOutsideStroke __zr nil-unwrap fix (funnel labels exercise the outside-label color path).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class NewChartsRenderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(FunnelSeriesModel.self)
        ComponentModel.registerClass(CandlestickSeriesModel.self)
        ComponentModel.registerClass(BoxplotSeriesModel.self)
    }

    func testFunnelRendersTrapezoids() {
        let ec = ECharts(width: 460, height: 340)
        ec.setOption([
            "series": [["type": "funnel", "left": "10%", "top": 20.0, "width": "80%", "height": 300.0,
                        "data": [["value": 100.0, "name": "Show"], ["value": 80.0, "name": "Click"],
                                 ["value": 60.0, "name": "Visit"], ["value": 40.0, "name": "Inquiry"],
                                 ["value": 20.0, "name": "Order"]]] as [String: Any]]
        ])
        var polys: [ZRenderKit.Polygon] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? ZRenderKit.Polygon, p.name == "item" { polys.append(p) }
            return false
        }
        XCTAssertEqual(polys.count, 5, "5 funnel stages → 5 trapezoid Polygons")
        // Distinct palette fills (funnel is colorBy:data).
        var fills = Set<String>()
        for p in polys { if case let .string(s)? = p.pathStyle?.fill { fills.insert(s) } }
        XCTAssertEqual(fills.count, 5, "each funnel stage gets a distinct palette color")
    }

    func testCandlestickRendersBoxes() {
        let ec = ECharts(width: 520, height: 340)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D", "E", "F"]] as [String: Any],
            "yAxis": ["type": "value", "scale": true] as [String: Any],
            "series": [["type": "candlestick",
                        "data": [[20.0, 34.0, 18.0, 38.0], [34.0, 28.0, 25.0, 40.0],
                                 [28.0, 42.0, 26.0, 45.0], [42.0, 38.0, 35.0, 48.0],
                                 [38.0, 50.0, 36.0, 55.0], [50.0, 46.0, 44.0, 58.0]]] as [String: Any]]
        ])
        var boxes = 0
        _ = ec.getRoot().traverse { el in
            if el is NormalBoxPath { boxes += 1 }
            return false
        }
        XCTAssertEqual(boxes, 6, "6 K-line sessions → 6 NormalBoxPath candles")
    }

    func testBoxplotRendersBoxes() {
        let ec = ECharts(width: 520, height: 340)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["G1", "G2", "G3", "G4", "G5"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot",
                        "data": [[10.0, 22.0, 28.0, 35.0, 50.0], [15.0, 25.0, 33.0, 40.0, 55.0],
                                 [8.0, 18.0, 24.0, 30.0, 44.0], [20.0, 30.0, 38.0, 46.0, 60.0],
                                 [12.0, 20.0, 27.0, 36.0, 48.0]]] as [String: Any]]
        ])
        var boxes = 0
        _ = ec.getRoot().traverse { el in
            if el is BoxPath { boxes += 1 }
            return false
        }
        XCTAssertEqual(boxes, 5, "5 groups → 5 BoxPath boxes")
    }
}
