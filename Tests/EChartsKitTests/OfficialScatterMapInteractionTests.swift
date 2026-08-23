import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialScatterMapInteractionTests: XCTestCase {
    func testTooltipUsesPM25DimensionInsteadOfLatitude() throws {
        let view = EChartsView(width: 640, height: 420)
        defer { view.dispose() }
        view.setOption(EChartsDemoRegistry.official_scatter_map.option)

        let model = try XCTUnwrap(view.ec.getModel())
        let series = try XCTUnwrap(model.getSeriesByIndex(0))
        let params = series.getDataParams(95)
        XCTAssertEqual(params.name, "三亚")
        let values = try XCTUnwrap(params.value as? [Any])
        XCTAssertEqual(values[1] as? Double, 18.252847)
        XCTAssertEqual(values[2] as? Double, 54)

        let tooltip = try XCTUnwrap(model.getComponent("tooltip"))
        let formatter = try XCTUnwrap(
            tooltip.get("formatter") as? (TooltipCallbackDataParams) -> String
        )
        XCTAssertEqual(formatter(params), "三亚 : 54")
    }
}
