import XCTest
import ZRenderKit
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialScatterClusteringInteractionTests: XCTestCase {
    private func colorString(_ color: ZRenderKit.ZRColor?) -> String? {
        guard case let .string(value)? = color else { return nil }
        return value
    }

    func testClickingHoveredClusterUsesUpdatedOutOfRangeVisual() throws {
        let demo = EChartsDemoRegistry.official_scatter_clustering
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let clusterThreePath = try XCTUnwrap(
            (series.getData().getItemGraphicEl(3) as? Symbol)?.childAt(0) as? Path
        )
        XCTAssertEqual(colorString(clusterThreePath.pathStyle.fill), "#ff994d")

        XCTAssertNotNil(view._injectPiecewiseVisualMapClickForTest(
            componentIndex: 0,
            pieceIndex: 3
        ))

        let updatedSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let updatedClusterThreePath = try XCTUnwrap(
            (updatedSeries.getData().getItemGraphicEl(3) as? Symbol)?.childAt(0) as? Path
        )
        XCTAssertTrue(updatedClusterThreePath.currentStates.contains("emphasis"))
        XCTAssertEqual(
            colorString(updatedClusterThreePath.pathStyle.fill),
            "rgba(0,0,0,0)",
            "the hovered cluster must emphasize the newly encoded outOfRange visual, not retain its old orange fill"
        )
    }
}
