// Phase 51 regression test — the CoordinateSystem protocol WITNESSES for Cartesian2D's `getAxis` /
// `getOtherAxis`. Before the fix these concrete methods took the narrower `Axis2D` param/return, so they
// did NOT witness the protocol requirements (`getAxis(_ dim: DimensionName?) -> Axis?`, `getOtherAxis(_
// baseAxis: Axis) -> Axis?`) — a call through a `CoordinateSystem`-typed reference hit the nil-returning
// DEFAULT, silently blocking the marker helpers. This proves the protocol dispatch now resolves.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZCoordWitnessTests: XCTestCase {

    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    func testCartesianAxisWitnessesResolveThroughProtocol() {
        let view = EChartsView(width: 400, height: 260)
        view.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [3.0, 5, 4]] as [String: Any]]
        ])
        var series: SeriesModel?
        view.ec.getModel()?.eachSeries { s, _ in if series == nil { series = s } }
        guard let coord = series?.coordinateSystem as? CoordinateSystem else {
            XCTFail("bar series must have a CoordinateSystem-typed coordinate system"); return
        }

        // Through the PROTOCOL type: getAxis resolves both dims (was nil via the unwitnessed default).
        let yAxis = coord.getAxis("y")
        let xAxis = coord.getAxis("x")
        XCTAssertNotNil(yAxis, "coordSys.getAxis(\"y\") must resolve through the protocol witness")
        XCTAssertNotNil(xAxis, "coordSys.getAxis(\"x\") must resolve through the protocol witness")

        // getOtherAxis(baseAxis) resolves to the opposite axis.
        guard let base = xAxis else { return }
        let other = coord.getOtherAxis(base)
        XCTAssertNotNil(other, "coordSys.getOtherAxis(xAxis) must resolve through the protocol witness")
        XCTAssertEqual((other as? Axis2D)?.dim, "y", "getOtherAxis(x) → the y axis")
    }
}
