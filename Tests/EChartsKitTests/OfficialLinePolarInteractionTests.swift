import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialLinePolarInteractionTests: XCTestCase {
    func testPolar2VisiblePetalHitUsesUpstreamFloat32PointAndSelectsItsAngle() throws {
        let demo = EChartsDemoRegistry.official_line_polar2
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let points = try XCTUnwrap(series.getData().getLayout("points") as? [Double])
        // Avoid a zero-radius center where angle is mathematically undefined and many data points
        // overlap. The visual scenario uses the same visible, non-degenerate rose-petal point.
        let dataIndex = 22
        let offset = dataIndex * 2
        XCTAssertGreaterThan(points.count, offset + 1)

        let point = [points[offset], points[offset + 1]]
        XCTAssertEqual(point[0], Double(Float(point[0])),
                       "upstream pointsLayout(forceStoreInTypedArray) stores x in Float32Array")
        XCTAssertEqual(point[1], Double(Float(point[1])),
                       "upstream pointsLayout(forceStoreInTypedArray) stores y in Float32Array")

        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])

        let collection = try XCTUnwrap(
            (view.ec.getModel()?.getComponent("axisPointer") as? AxisPointerModel)?
                .coordSysAxesInfo as? CollectionResult
        )
        let angleInfo = try XCTUnwrap(collection.axesInfo.values.first { $0.axis.dim == "angle" })
        let angleValue = try XCTUnwrap(angleInfo.axisPointerModel.get("value") as? Double)
        XCTAssertEqual(angleValue, 22, accuracy: 0.001,
                       "the exact official visible point must resolve through the same polar axis path as Web")
        XCTAssertTrue(view.tooltipView?.contentEl?.textStyle?.text?.contains("22") == true)
    }
}
