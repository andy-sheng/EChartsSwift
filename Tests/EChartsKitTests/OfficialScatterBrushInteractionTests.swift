import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialScatterBrushInteractionTests: XCTestCase {
    private func visualFill(_ data: SeriesData, index: Int) -> String? {
        guard let style = data.getItemVisual(index, "style") as? [String: Any] else { return nil }
        if let value = style["fill"] as? String { return value }
        if let value = style["fill"] as? EChartsKit.ZRColor,
           case let .color(color) = value { return color }
        return nil
    }

    private func renderedFill(_ data: SeriesData, index: Int) -> String? {
        guard let path = (data.getItemGraphicEl(index) as? Symbol)?.getSymbolPath(),
              let fill = path.pathStyle.fill else { return nil }
        if case let .string(color) = fill { return color }
        return nil
    }

    private func selectedIndices(_ params: ECEventParams?, seriesIndex: Int) -> [Int] {
        guard let event = params as? ECActionEvent,
              let batches = event.eventData["batch"] as? [[String: Any]],
              let selected = batches.first?["selected"] as? [[String: Any]],
              let series = selected.first(where: { item in
                  let value = item["seriesIndex"]
                  return (value as? Int) == seriesIndex
                      || (value as? Double) == Double(seriesIndex)
              }) else { return [] }
        if let values = series["dataIndex"] as? [Int] { return values }
        return (series["dataIndex"] as? [Double])?.map(Int.init) ?? []
    }

    func testWeightBrushDragSelectsSubsetInsteadOfDimmingEverything() {
        let demo = EChartsDemoRegistry.official_scatter_weight
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        var selectedEvent: ECEventParams?
        _ = view.on("brushselected") { selectedEvent = $0 }

        var arm = Payload(type: "takeGlobalCursor")
        arm.other["key"] = "brush"
        arm.other["brushOption"] = [
            "brushType": "rect", "brushMode": "single",
        ] as [String: Any]
        view.ec.dispatchAction(arm)
        XCTAssertNotNil(view._injectBrushDragForTest(
            targetType: "grid", componentIndex: 0, brushType: "rect"
        ))

        let femaleCount = view.ec.getModel()?.getSeriesByIndex(0)?.getData().count() ?? 0
        let selected = selectedIndices(selectedEvent, seriesIndex: 0)
        XCTAssertFalse(selected.isEmpty, "real weight brush must select some Female points")
        XCTAssertLessThan(selected.count, femaleCount, "real weight brush must leave some points outside")

        guard let femaleData = view.ec.getModel()?.getSeriesByIndex(0)?.getData(),
              let selectedIndex = selected.first,
              let outsideIndex = (0..<femaleData.count()).first(where: { !selected.contains($0) }) else {
            XCTFail("expected one selected and one outside Female datum")
            return
        }
        XCTAssertNotEqual(
            visualFill(femaleData, index: selectedIndex),
            visualFill(femaleData, index: outsideIndex),
            "brush visual encoding must preserve a selected fill and dim an outside fill"
        )
        XCTAssertEqual(
            renderedFill(femaleData, index: selectedIndex),
            visualFill(femaleData, index: selectedIndex),
            "the rendered selected symbol must consume its encoded brush fill"
        )
        XCTAssertEqual(
            renderedFill(femaleData, index: outsideIndex),
            visualFill(femaleData, index: outsideIndex),
            "the rendered outside symbol must consume its encoded brush fill"
        )
    }
}
