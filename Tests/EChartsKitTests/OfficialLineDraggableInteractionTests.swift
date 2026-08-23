import XCTest
@testable import EChartsKit
@testable import ZRenderKit
import EChartsDemoCore

@MainActor
private final class LineDraggableTestChart: EChartsDemoChart {
    let view: EChartsView
    init(_ view: EChartsView) { self.view = view }

    func setOption(_ option: [String: Any], notMerge: Bool) {
        view.setOption(option, notMerge: notMerge)
    }
    func appendData(seriesIndex: Int, data: [Double]) {}
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {}
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) { body() }
    func dispatch(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        var action = Payload(type: type)
        action.other = payload.filter { $0.key != "type" }
        view.ec.dispatchAction(action)
        view.syncAfterAction()
    }
    func convertToPixel(_ finder: ModelFinder, _ value: CoordinateSystemDataCoord) -> Any? {
        view.ec.convertToPixel(finder, value)
    }
    func convertFromPixel(_ finder: ModelFinder, _ value: [Double]) -> Any? {
        view.ec.convertFromPixel(finder, value)
    }
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        view.on(event) { params in MainActor.assumeIsolated { handler(params) } }
    }
}

final class OfficialLineDraggableInteractionTests: XCTestCase {
    @MainActor
    func testNativeDriveInstallsAndDragsFiveGraphicHandles() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-line-draggable"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        let chart = LineDraggableTestChart(view)
        try XCTUnwrap(demo.drive)(chart)

        let handles = view.zr.storage.getDisplayList(true).filter {
            $0 is Circle && $0.draggable != .false && $0.invisible
        }
        XCTAssertEqual(handles.count, 5, "one invisible draggable graphic circle per line datum")

        let handle = try XCTUnwrap(handles.first)
        let bounds = try XCTUnwrap(handle.getBoundingRect())
        let start = handle.transformCoordToGlobal(
            bounds.x + bounds.width / 2, bounds.y + bounds.height / 2
        )
        let before = handle.x

        XCTAssertTrue(handle.contain(start[0], start[1]),
                      "graphic handle must contain its own transformed center; fill=\(String(describing: (handle as? Path)?.pathStyle?.fill))")
        let hovered = view.zr.handler.findHover(start[0], start[1]).target
        XCTAssertTrue(hovered === handle,
                      "graphic handle must be the top hit target; got \(String(describing: hovered.map { type(of: $0) })) z=\((hovered as? Displayable)?.z ?? -1), handle z=\(handle.z)")

        view._injectPointerForTest(type: "mousemove", zrX: start[0], zrY: start[1])
        XCTAssertTrue(view.tooltipView?.isShown() ?? false,
                      "hovering the invisible handle must dispatch showTip despite triggerOn:none")
        XCTAssertFalse(view.tooltipView?.contentEl?.textStyle?.text?.contains("<br") ?? true,
                       "native tooltip must translate the formatter's HTML break")

        view._injectPointerForTest(type: "mousedown", zrX: start[0], zrY: start[1])
        view._injectPointerForTest(type: "mousemove", zrX: start[0] + 42, zrY: start[1] + 24)
        view._injectPointerForTest(type: "mouseup", zrX: start[0] + 42, zrY: start[1] + 24)

        XCTAssertEqual(handle.x, before + 42, accuracy: 1e-6,
                       "the real Handler drag must move the graphic handle")
        let moved = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0)?.getData()
            .getRawDataItem(0) as? [Any])
        XCTAssertEqual(moved.count, 2)
        XCTAssertNotEqual((moved[0] as? NSNumber)?.doubleValue, 40,
                          "ondrag must convert the pixel position back into updated series data")
        let tooltipText = view.tooltipView?.contentEl?.textStyle?.text ?? ""
        XCTAssertFalse(tooltipText.contains("X: 40.00"),
                       "the tooltip must refresh to the dragged point's new coordinates")
    }
}
