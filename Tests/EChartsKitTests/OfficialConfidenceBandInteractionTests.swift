import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialConfidenceBandInteractionTests: XCTestCase {
    func testAxisHoverShowsOnlyDateAndUnshiftedPercentage() throws {
        let demo = EChartsDemoRegistry.official_confidence_band
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)

        let actualSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(2))
        let points = try XCTUnwrap(
            actualSeries.getData().getLayout("points") as? [Double],
            "the actual-value series must expose its line-point layout"
        )
        let point = Array(points[(45 * 2)...(45 * 2 + 1)])

        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])

        XCTAssertEqual(view.tooltipView?.isShown(), true)
        XCTAssertEqual(view.tooltipView?.contentEl?.textStyle?.text, "2012-10-12\n-4.6%")
    }
}
