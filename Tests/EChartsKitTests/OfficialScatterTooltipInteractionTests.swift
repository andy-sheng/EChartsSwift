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

    func testWorldPopulationTooltipPreservesOfficialArrayFormatting() throws {
        let text = try formattedTooltip(
            demo: EChartsDemoRegistry.official_scatter_world_population,
            seriesIndex: 0,
            dataIndex: 84
        )
        XCTAssertTrue(text.contains("Kyrgyzstan"), text)
        XCTAssertTrue(text.contains("75,41,5,392,580.undefined"), text)
    }

    func testAnscombeStringFormatterUsesJavaScriptArrayCoercion() throws {
        let demo = EChartsDemoRegistry.official_scatter_anscombe_quartet
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)

        let expected = ["14,9.96", "14,8.1", "14,8.84", "8,7.04"]
        for seriesIndex in expected.indices {
            let series = try XCTUnwrap(
                view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex))
            )
            XCTAssertEqual(format._str(series.getDataParams(5).value), expected[seriesIndex])
        }
    }

    func testAqiTooltipPreservesEveryPollutantDimension() throws {
        let text = try formattedTooltip(
            demo: EChartsDemoRegistry.official_scatter_aqi_color,
            seriesIndex: 1,
            dataIndex: 15
        )
        XCTAssertTrue(text.contains("上海 16日：轻度污染"), text)
        XCTAssertTrue(text.contains("AQI指数：134"), text)
        XCTAssertTrue(text.contains("PM2.5：83"), text)
        XCTAssertTrue(text.contains("PM10：167"), text)
        XCTAssertTrue(text.contains("一氧化碳（CO）：1.16"), text)
        XCTAssertTrue(text.contains("二氧化氮（NO2）：57"), text)
        XCTAssertTrue(text.contains("二氧化硫（SO2）：43"), text)
    }
}
