import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialDatasetLinkInteractionTests: XCTestCase {
    private func finishStateTransition(_ element: Element) {
        for animator in element.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(300, 300) { clip.ondestroy() }
        }
    }

    private func finishPieStateTransitions(_ pie: SeriesModel) throws {
        for index in 0..<pie.getData().count() {
            let sector = try XCTUnwrap(pie.getData().getItemGraphicEl(index))
            finishStateTransition(sector)
            if let label = sector.getTextContent() { finishStateTransition(label) }
            if let guide = sector.getTextGuideLine() { finishStateTransition(guide) }
        }
    }

    private func hoverPieItem(_ index: Int, pie: SeriesModel, view: EChartsView) throws {
        let sector = try XCTUnwrap(pie.getData().getItemGraphicEl(index) as? Sector)
        let shape = try XCTUnwrap(sector.shape as? SectorShape)
        let angle = (shape.startAngle + shape.endAngle) / 2
        let radius = (shape.r0 + shape.r) / 2
        view._injectPointerForTest(
            type: "mousemove",
            zrX: shape.cx + cos(angle) * radius,
            zrY: shape.cy + sin(angle) * radius
        )
    }

    func testPieLabelsReturnToNormalWhenPointerLeavesChart() throws {
        let view = EChartsView(width: 640, height: 420)
        view.setOption(EChartsDemoRegistry.official_dataset_link.option)
        _ = view.zr.storage.getDisplayList(true)

        let pie = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(4))
        let hoveredSector = try XCTUnwrap(pie.getData().getItemGraphicEl(0) as? Sector)
        let hoveredShape = try XCTUnwrap(hoveredSector.shape as? SectorShape)
        let angle = (hoveredShape.startAngle + hoveredShape.endAngle) / 2
        let radius = (hoveredShape.r0 + hoveredShape.r) / 2
        view._injectPointerForTest(
            type: "mousemove",
            zrX: hoveredShape.cx + cos(angle) * radius,
            zrY: hoveredShape.cy + sin(angle) * radius
        )

        let blurredSector = try XCTUnwrap(pie.getData().getItemGraphicEl(1))
        let blurredLabel = try XCTUnwrap(blurredSector.getTextContent())
        finishStateTransition(blurredSector)
        finishStateTransition(blurredLabel)
        XCTAssertTrue(blurredLabel.currentStates.contains("blur"))
        XCTAssertEqual(blurredLabel.textStyle?.opacity ?? 1, 0.1, accuracy: 1e-9)

        let exitEvent = ZRRawEvent()
        exitEvent.type = "mouseout"
        exitEvent.zrEventControl = "only_globalout"
        view.zr.handler.mouseout(exitEvent)

        for index in 0..<pie.getData().count() {
            let sector = try XCTUnwrap(pie.getData().getItemGraphicEl(index))
            let label = try XCTUnwrap(sector.getTextContent())
            finishStateTransition(sector)
            finishStateTransition(label)
            XCTAssertTrue(sector.currentStates.isEmpty,
                          "pie sector \(index) must return to normal; states=\(sector.currentStates)")
            XCTAssertTrue(label.currentStates.isEmpty,
                          "pie label \(index) must return to normal; states=\(label.currentStates)")
            XCTAssertEqual(label.textStyle?.opacity ?? 0, 1, accuracy: 1e-9,
                           "pie label \(index) must become fully visible after leaving the chart")
        }
    }

    func testPieLabelsReturnToNormalAfterMovingAcrossEverySliceThenLeaving() throws {
        let view = EChartsView(width: 640, height: 420)
        view.setOption(EChartsDemoRegistry.official_dataset_link.option)
        _ = view.zr.storage.getDisplayList(true)

        let pie = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(4))
        for index in 0..<pie.getData().count() {
            try hoverPieItem(index, pie: pie, view: view)
            try finishPieStateTransitions(pie)
        }

        view._injectGlobalOutForTest()
        try finishPieStateTransitions(pie)

        for index in 0..<pie.getData().count() {
            let sector = try XCTUnwrap(pie.getData().getItemGraphicEl(index))
            let label = try XCTUnwrap(sector.getTextContent())
            XCTAssertTrue(sector.currentStates.isEmpty,
                          "pie sector \(index) must restore after cross-slice hover")
            XCTAssertTrue(label.currentStates.isEmpty,
                          "pie label \(index) must restore after cross-slice hover")
            XCTAssertEqual(label.textStyle?.opacity ?? 0, 1, accuracy: 1e-9,
                           "pie label \(index) must be fully visible after cross-slice hover")
        }
    }

    @MainActor
    func testAxisPointerDriveReencodesPieForHoveredYear() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-dataset-link"))
        let drive = try XCTUnwrap(demo.drive)
        let chart = DatasetLinkChartSpy()
        drive(chart)

        var event = ECActionEvent(type: "updateAxisPointer")
        event.eventData["axesInfo"] = [["axisDim": "x", "axisIndex": 0.0, "value": 3.0]]
        try XCTUnwrap(chart.handlers["updateAxisPointer"])(event)

        let series = try XCTUnwrap(chart.lastOption["series"] as? [[String: Any]])
        let pie = try XCTUnwrap(series.first)
        XCTAssertEqual(pie["id"] as? String, "pie")
        let encode = try XCTUnwrap(pie["encode"] as? [String: Any])
        XCTAssertEqual(encode["value"] as? Double, 4.0)
        XCTAssertEqual(encode["tooltip"] as? Double, 4.0)
        let label = try XCTUnwrap(pie["label"] as? [String: Any])
        XCTAssertEqual(label["formatter"] as? String, "{b}: {@[4]} ({d}%)")
    }

    func testLineHoverPublishesUpdateAxisPointerWithHoveredYear() throws {
        let view = EChartsView(width: 640, height: 420)
        view.setOption(EChartsDemoRegistry.official_dataset_link.option)
        _ = view.zr.storage.getDisplayList(true)

        var hoveredAxisValue: Double?
        view.on("updateAxisPointer") { event in
            guard let axesInfo = event["axesInfo"] as? [[String: Any]],
                  let value = axesInfo.first?["value"] else { return }
            hoveredAxisValue = (value as? Double) ?? (value as? Int).map(Double.init)
        }

        let line = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let symbol = try XCTUnwrap(line.getData().getItemGraphicEl(3))
        let bounds = try XCTUnwrap(symbol.getBoundingRect())
        let point = symbol.transformCoordToGlobal(
            bounds.x + bounds.width / 2,
            bounds.y + bounds.height / 2
        )
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])

        XCTAssertEqual(hoveredAxisValue ?? -1, 3.0, accuracy: 1e-9,
                       "hovering the 2015 symbol must publish axis category index 3")
    }
}

@MainActor
private final class DatasetLinkChartSpy: EChartsDemoChart {
    var handlers: [String: @MainActor (ECEventParams) -> Void] = [:]
    var lastOption: [String: Any] = [:]

    func setOption(_ option: [String: Any], notMerge: Bool) { lastOption = option }
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func dispatch(_ payload: [String: Any]) {}
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        handlers[event] = handler
    }
}
