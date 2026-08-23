import XCTest
import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialMapIcelandPieInteractionTests: XCTestCase {
    func testEveryGeoPieUsesOfficialPercentTooltipFormatter() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-map-iceland-pie"))
        let expected = [
            "Category C: 18 (18%)",
            "Category C: 28 (28%)",
            "Category C: 26 (26%)",
            "Category C: 35 (35%)",
        ]

        for seriesIndex in 0..<expected.count {
            let view = EChartsView(width: demo.width, height: demo.height)
            view.setOption(demo.option)
            _ = view.zr.storage.getDisplayList(true)
            let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)))
            let dataIndex = series.getData().indexOfName("Category C")
            let sector = try XCTUnwrap(series.getData().getItemGraphicEl(dataIndex) as? Sector)
            let shape = try XCTUnwrap(sector.shape as? SectorShape)
            let angle = (shape.startAngle + shape.endAngle) / 2
            let radius = (shape.r0 + shape.r) / 2
            view._injectPointerForTest(
                type: "mousemove",
                zrX: shape.cx + cos(angle) * radius,
                zrY: shape.cy + sin(angle) * radius
            )
            XCTAssertEqual(view.tooltipView?.contentEl?.textStyle?.text, expected[seriesIndex])
            view.dispose()
        }
    }
}
