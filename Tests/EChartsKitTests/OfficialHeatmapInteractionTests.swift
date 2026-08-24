import XCTest
import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialHeatmapInteractionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(EChartsXAxisModel.self)
        ComponentModel.registerClass(EChartsYAxisModel.self)
        ComponentModel.registerClass(HeatmapSeriesModel.self)
    }

    func testCalendarVerticalTooltipPreservesOfficialDateFormatter() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-calendar-vertical"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(2))
        let cell = try XCTUnwrap(series.getData().getItemGraphicEl(182) as? Displayable)
        let bounds = try XCTUnwrap(cell.getBoundingRect())
        let point = cell.transformCoordToGlobal(
            bounds.x + bounds.width / 2,
            bounds.y + bounds.height / 2
        )
        XCTAssertTrue(view.zr.handler.findHover(point[0], point[1]).target === cell)

        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])

        XCTAssertEqual(view.tooltipView?.contentEl?.textStyle?.text, "2017-07-02: 125")
    }

    func testContinuousVisualMapHidesOutOfRangeHeatmapCellAndLabel() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-heatmap-cartesian"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)

        let visualMap = try XCTUnwrap(
            view.ec.getModel()?.getComponent("visualMap", 0) as? ContinuousModel
        )
        var payload = Payload(type: "selectDataRange")
        payload.other["visualMapId"] = visualMap.id
        payload.other["selected"] = [0.0, 8.0]
        view.ec.dispatchAction(payload)
        _ = view.ec.getRoot().traverse { element in
            _ = element.stopAnimation(nil, true)
            return false
        }

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let data = series.getData()
        let highValueIndex = try XCTUnwrap((0..<data.count()).first { index in
            guard let row = series.getRawValue(Double(index)) as? [Any], row.count > 2,
                  let value = row[2] as? NSNumber else { return false }
            return value.doubleValue > 8
        })
        let cell = try XCTUnwrap(data.getItemGraphicEl(highValueIndex) as? Rect)
        let label = try XCTUnwrap(cell.getTextContent())

        XCTAssertEqual(cell.pathStyle?.opacity ?? 1, 0, accuracy: 1e-9)
        XCTAssertEqual(label.textStyle?.opacity ?? 1, 0, accuracy: 1e-9)

        var restore = Payload(type: "selectDataRange")
        restore.other["visualMapId"] = visualMap.id
        restore.other["selected"] = [0.0, 10.0]
        view.ec.dispatchAction(restore)
        _ = view.ec.getRoot().traverse { element in
            _ = element.stopAnimation(nil, true)
            return false
        }

        let restoredSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let restoredCell = try XCTUnwrap(
            restoredSeries.getData().getItemGraphicEl(highValueIndex) as? Rect
        )
        XCTAssertEqual(restoredCell.pathStyle?.opacity ?? 1, 1, accuracy: 1e-9)
        XCTAssertEqual(
            restoredCell.getTextContent()?.textStyle?.opacity ?? 1,
            1,
            accuracy: 1e-9
        )
    }
}
