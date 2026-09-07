import XCTest
import ZRenderKit
@testable import EChartsKit

final class NumericCoordinatePerformanceTests: XCTestCase {
    func testBandExtentsTrackResizeScaleRangeAndInverseWithoutCachedState() {
        let scale = OrdinalScale(OrdinalScaleSetting(ordinalMeta: ["a", "b", "c", "d"], extent: [0, 3]))
        let axis = Axis("x", scale, [0, 400]); axis.onBand = true
        XCTAssertEqual(axis.dataToCoord(0.0), 50)
        XCTAssertEqual(axis.dataToCoord(3.0), 350)
        XCTAssertEqual(axis.coordToData(50), 0)
        axis.setExtent(400, 0)
        XCTAssertEqual(axis.dataToCoord(0.0), 350)
        XCTAssertEqual(axis.dataToCoord(3.0), 50)
        scale.setExtent(1, 2)
        XCTAssertEqual(axis.dataToCoord(1.0), 300)
        XCTAssertEqual(axis.dataToCoord(2.0), 100)
        axis.onBand = false
        XCTAssertEqual(axis.dataToCoord(1.0), 400)
        XCTAssertEqual(axis.dataToCoord(2.0), 0)
    }

    func testNumericCartesianMatchesProtocolForAffineFallbackClampAndNonFiniteValues() {
        let xScale = IntervalScale(); xScale.setExtent(-10, 10)
        let yScale = IntervalScale(); yScale.setExtent(0, 100)
        let xAxis = Axis2D("x", xScale, [0, 400])
        let yAxis = Axis2D("y", yScale, [200, 0])
        xAxis.toGlobalCoord = { $0 + 20 }; yAxis.toGlobalCoord = { $0 + 30 }
        let cartesian = Cartesian2D("test")
        cartesian.addAxis(xAxis); cartesian.addAxis(yAxis)
        for affine in [false, true] {
            if affine { cartesian.calcAffineTransform() }
            for clamp in [false, true] {
                for values: [Double] in [[-10, 0], [10, 100], [0, 50], [-20, 150], [.nan, 50], [2, .infinity]] {
                    let expected = cartesian.dataToPoint(values as Any, clamp)
                    let actual = cartesian.dataToPoint(VectorArray(values[0], values[1]), clamp)
                    for i in 0..<2 {
                        if expected[i].isNaN { XCTAssertTrue(actual[i].isNaN) }
                        else { XCTAssertEqual(actual[i], expected[i]) }
                    }
                }
            }
        }
    }
}
