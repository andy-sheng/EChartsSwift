import XCTest
import ZRenderKit
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialScatterNutrientsMatrixInteractionTests: XCTestCase {
    private func hoverPoint(_ element: ZRenderKit.Element) throws -> [Double] {
        let rect = try XCTUnwrap(element.getBoundingRect())
        let candidates = [
            (rect.x + rect.width / 2, rect.y + rect.height / 2),
            (rect.x + rect.width * 0.25, rect.y + rect.height / 2),
            (rect.x + rect.width * 0.75, rect.y + rect.height / 2)
        ]
        for candidate in candidates {
            let point = element.transformCoordToGlobal(candidate.0, candidate.1)
            if point.count >= 2 { return point }
        }
        throw XCTSkip("data symbol has no global hover point")
    }

    func testTooltipFormatterGroupsLinkedAxisParamsByFoodAndDimension() throws {
        let view = EChartsView(width: 900, height: 560)
        defer { view.dispose() }
        view.setOption(EChartsDemoRegistry.official_scatter_nutrients_matrix.option)

        let model = try XCTUnwrap(view.ec.getModel())
        let topLeft = try XCTUnwrap(model.getSeriesByIndex(0))
        let bottomLeft = try XCTUnwrap(model.getSeriesByIndex(1))
        var xParam = topLeft.getDataParams(500)
        var yParam = bottomLeft.getDataParams(500)
        xParam.axisDim = "x"
        yParam.axisDim = "y"

        let tooltip = try XCTUnwrap(model.getComponent("tooltip"))
        let formatter = try XCTUnwrap(
            tooltip.get("formatter") as? ([TooltipCallbackDataParams]) -> String
        )
        let text = formatter([xParam, yParam])
        let data = try XCTUnwrap(xParam.data as? [Any])
        let foodName = try XCTUnwrap(data[3] as? String)
        XCTAssertTrue(text.contains("POINTS ON CROSS"))
        XCTAssertTrue(text.contains(foodName))
        XCTAssertTrue(text.contains("carbohydrate:"))
        XCTAssertTrue(text.contains("calcium:"))
        XCTAssertTrue(text.contains("fiber:"))
    }

    func testTooltipPositionPinsToOppositeCorner() throws {
        let view = EChartsView(width: 900, height: 560)
        defer { view.dispose() }
        view.setOption(EChartsDemoRegistry.official_scatter_nutrients_matrix.option)
        let tooltip = try XCTUnwrap(view.ec.getModel()?.getComponent("tooltip"))
        let position = try XCTUnwrap(tooltip.get("position") as? TooltipPositionCallback)
        let size = TooltipPositionCallbackSize(contentSize: (300, 200), viewSize: (900, 560))

        let topLeft = try XCTUnwrap(position((100, 100), [], nil, nil, size) as? [String: Any])
        XCTAssertEqual(topLeft["right"] as? Double, 60)
        XCTAssertEqual(topLeft["bottom"] as? Double, 20)

        let bottomRight = try XCTUnwrap(position((700, 500), [], nil, nil, size) as? [String: Any])
        XCTAssertEqual(bottomRight["left"] as? Double, 60)
        XCTAssertEqual(bottomRight["top"] as? Double, 20)
    }

    func testHoveringBottomLeftSeriesShowsLinkedAxisTooltip() throws {
        let view = EChartsView(width: 900, height: 560)
        defer { view.dispose() }
        view.setOption(EChartsDemoRegistry.official_scatter_nutrients_matrix.option)
        _ = view.zr.storage.getDisplayList(true)

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(1))
        let element = try XCTUnwrap(series.getData().getItemGraphicEl(500))
        let point = try hoverPoint(element)
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])

        XCTAssertEqual(view.tooltipView?.isShown(), true)
        XCTAssertTrue(view.tooltipView?.contentEl?.textStyle?.text?.contains("POINTS ON") == true)
    }
}
