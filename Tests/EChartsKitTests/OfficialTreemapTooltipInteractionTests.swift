import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialTreemapTooltipInteractionTests: XCTestCase {
    private func formattedTooltip(
        demo: EChartsDemo,
        seriesIndex: Int = 0,
        dataIndex: Int = 0
    ) throws -> String {
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)))
        let seriesOptions = try XCTUnwrap(demo.option["series"] as? [[String: Any]])
        let seriesTooltip = seriesOptions[seriesIndex]["tooltip"] as? [String: Any]
        let componentTooltip = demo.option["tooltip"] as? [String: Any]
        let formatter = try XCTUnwrap(
            (seriesTooltip?["formatter"] ?? componentTooltip?["formatter"])
                as? (TooltipCallbackDataParams) -> String
        )
        return formatter(series.getDataParams(Double(dataIndex)))
    }

    func testDiskTreemapsShowBreadcrumbUnitsAndGrouping() throws {
        for demo in [
            EChartsDemoRegistry.official_treemap_disk,
            EChartsDemoRegistry.official_treemap_show_parent,
        ] {
            let text = try formattedTooltip(demo: demo)
            XCTAssertFalse(text.contains("<div"), text)
            XCTAssertFalse(text.contains("&nbsp;"), text)
            XCTAssertTrue(text.contains("Disk Usage: "), text)
            XCTAssertTrue(text.contains(" KB"), text)
            XCTAssertTrue(text.contains(","), text)
        }
    }

    func testVisualTreemapShowsEveryOfficialMetric() throws {
        let text = try formattedTooltip(
            demo: EChartsDemoRegistry.official_treemap_visual,
            dataIndex: 2
        )
        XCTAssertTrue(text.contains("2012 Amount:"), text)
        XCTAssertTrue(text.contains("2011 Amount:"), text)
        XCTAssertTrue(text.contains("Change From 2011:"), text)
        XCTAssertTrue(text.contains("$"), text)
        XCTAssertTrue(text.contains("%"), text)
    }

    func testObamaTreemapUsesModeSpecificAmountsAndPerHousehold() throws {
        for seriesIndex in 0..<3 {
            let text = try formattedTooltip(
                demo: EChartsDemoRegistry.official_treemap_obama,
                seriesIndex: seriesIndex,
                dataIndex: 2
            )
            XCTAssertTrue(text.contains("2012 Amount:"), text)
            XCTAssertTrue(text.contains("Per Household:"), text)
            XCTAssertTrue(text.contains("2011 Amount:"), text)
            XCTAssertTrue(text.contains("Change From 2011:"), text)
            XCTAssertTrue(text.contains("$"), text)
            XCTAssertTrue(text.contains("%"), text)
        }
    }
}
