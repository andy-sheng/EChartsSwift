import XCTest
import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialPiePatternInteractionTests: XCTestCase {
    func testHoverAndSelectionRestorePatternFill() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-pie-pattern"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let pie = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let emailIndex = pie.getData().indexOfName("Email")
        var sector = try XCTUnwrap(pie.getData().getItemGraphicEl(emailIndex) as? Sector)
        assertPattern(sector.pathStyle.fill)

        let shape = try XCTUnwrap(sector.shape as? SectorShape)
        let angle = (shape.startAngle + shape.endAngle) / 2
        let radius = (shape.r0 + shape.r) / 2
        let x = shape.cx + cos(angle) * radius
        let y = shape.cy + sin(angle) * radius
        view._injectPointerForTest(type: "mousemove", zrX: x, zrY: y)
        finishStateTransition(sector)
        XCTAssertTrue(sector.currentStates.contains("emphasis"))

        view._injectGlobalOutForTest()
        finishStateTransition(sector)
        XCTAssertTrue(sector.currentStates.isEmpty)
        assertPattern(sector.pathStyle.fill)

        click(view, x: x, y: y)
        sector = try XCTUnwrap(pie.getData().getItemGraphicEl(emailIndex) as? Sector)
        finishStateTransition(sector)
        XCTAssertTrue(pie.isSelected(Double(emailIndex)))
        assertPattern(sector.pathStyle.fill)

        let selectedShape = try XCTUnwrap(sector.shape as? SectorShape)
        let selectedX = selectedShape.cx + cos(angle) * radius
        let selectedY = selectedShape.cy + sin(angle) * radius
        click(view, x: selectedX, y: selectedY)
        sector = try XCTUnwrap(pie.getData().getItemGraphicEl(emailIndex) as? Sector)
        finishStateTransition(sector)
        XCTAssertFalse(pie.isSelected(Double(emailIndex)))
        assertPattern(sector.pathStyle.fill)
    }

    private func click(_ view: EChartsView, x: Double, y: Double) {
        view._injectPointerForTest(type: "mousemove", zrX: x, zrY: y)
        view._injectPointerForTest(type: "mousedown", zrX: x, zrY: y)
        view._injectPointerForTest(type: "mouseup", zrX: x, zrY: y)
        view._injectPointerForTest(type: "click", zrX: x, zrY: y)
    }

    private func finishStateTransition(_ element: Element) {
        for animator in element.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(1_000, 1_000) { clip.ondestroy() }
        }
    }

    private func assertPattern(
        _ paint: ZRenderKit.ZRColor?, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .pattern? = paint else {
            XCTFail("expected a pattern fill, got \(String(describing: paint))", file: file, line: line)
            return
        }
    }
}
