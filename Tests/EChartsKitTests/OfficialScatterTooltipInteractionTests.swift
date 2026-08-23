import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialScatterTooltipInteractionTests: XCTestCase {
    private func formattedTooltip(
        demo: EChartsDemo,
        seriesIndex: Int,
        dataIndex: Int
    ) throws -> String {
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)))
        let baseOption = demo.option["baseOption"] as? [String: Any]
        let tooltip = try XCTUnwrap(
            (demo.option["tooltip"] as? [String: Any])
                ?? (baseOption?["tooltip"] as? [String: Any])
        )
        let formatter = try XCTUnwrap(
            tooltip["formatter"] as? (TooltipCallbackDataParams) -> String
        )
        return formatter(series.getDataParams(Double(dataIndex)))
    }

    func testWeightTooltipPreservesBothDimensionsAndUnits() throws {
        let demo = EChartsDemoRegistry.official_scatter_weight
        let female = try formattedTooltip(demo: demo, seriesIndex: 0, dataIndex: 130)
        XCTAssertTrue(female.contains("Female"), female)
        XCTAssertTrue(female.contains("162.8cm"), female)
        XCTAssertTrue(female.contains("58kg"), female)

        let male = try formattedTooltip(demo: demo, seriesIndex: 1, dataIndex: 123)
        XCTAssertTrue(male.contains("Male"), male)
        XCTAssertTrue(male.contains("177.8cm"), male)
        XCTAssertTrue(male.contains("116.4kg"), male)
    }

    func testLifeExpectancyTooltipPreservesEverySchemaDimension() throws {
        let text = try formattedTooltip(
            demo: EChartsDemoRegistry.official_scatter_life_expectancy_timeline,
            seriesIndex: 0,
            dataIndex: 9
        )
        XCTAssertTrue(text.contains("国家：Japan"), text)
        XCTAssertTrue(text.contains("人均寿命：36.4岁"), text)
        XCTAssertTrue(text.contains("人均收入：1050美元"), text)
        XCTAssertTrue(text.contains("总人口：30294378"), text)
    }
}
