import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialBarTooltipInteractionTests: XCTestCase {
    private func hover(
        demo: EChartsDemo,
        seriesIndex: Int,
        dataIndex: Int
    ) throws -> String {
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let series: SeriesModel = try XCTUnwrap(
            view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex))
        )
        let target: Displayable = try XCTUnwrap(
            series.getData().getItemGraphicEl(dataIndex) as? Displayable
        )
        let bounds: BoundingRect = try XCTUnwrap(target.getBoundingRect())
        var hit: [Double]?
        for y in 1..<20 where hit == nil {
            for x in 1..<20 {
                let localX = bounds.x + bounds.width * Double(x) / 20
                let localY = bounds.y + bounds.height * Double(y) / 20
                let point = target.transformCoordToGlobal(localX, localY)
                if target.contain(point[0], point[1]),
                   view.zr.handler.findHover(point[0], point[1]).target === target {
                    hit = point
                    break
                }
            }
        }
        let point = try XCTUnwrap(hit, "the requested bar must expose a real hit-testable point")
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
        let tooltip = try XCTUnwrap(view.tooltipView)
        XCTAssertTrue(tooltip.isShown())
        return try XCTUnwrap(tooltip.contentEl?.textStyle?.text)
    }

    func testWaterfallTooltipHidesPlaceholderSeries() throws {
        let text = try hover(
            demo: EChartsDemoRegistry.official_bar_waterfall,
            seriesIndex: 1,
            dataIndex: 3
        )
        XCTAssertEqual(text, "Transportation\nLife Cost : 200")
        XCTAssertFalse(text.contains("Placeholder"))
    }

    func testAccumulatedWaterfallTooltipChoosesIncomeOrExpense() throws {
        XCTAssertEqual(
            try hover(
                demo: EChartsDemoRegistry.official_bar_waterfall2,
                seriesIndex: 1,
                dataIndex: 5
            ),
            "Nov 6\nIncome : 135"
        )
        XCTAssertEqual(
            try hover(
                demo: EChartsDemoRegistry.official_bar_waterfall2,
                seriesIndex: 2,
                dataIndex: 4
            ),
            "Nov 5\nExpenses : 154"
        )
    }

    func testPolarRealEstateTooltipUsesOriginalCityRow() throws {
        let text = try hover(
            demo: EChartsDemoRegistry.official_bar_polar_real_estate,
            seriesIndex: 1,
            dataIndex: 9
        )
        XCTAssertEqual(text, "济南\nLowest：2000\nHighest：3000\nAverage：2500")
    }
}
