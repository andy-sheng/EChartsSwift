import XCTest
import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialBarGradientInteractionTests: XCTestCase {
    func testHoverAppliesAndRestoresGradientFill() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-bar-gradient"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let bar = try XCTUnwrap(series.getData().getItemGraphicEl(10) as? Rect)
        assertGradient(bar.pathStyle.fill, colors: ["#83bff6", "#188df0", "#188df0"])

        let shape = try XCTUnwrap(bar.shape as? RectShape)
        view._injectPointerForTest(
            type: "mousemove",
            zrX: shape.x + shape.width / 2,
            zrY: shape.y + shape.height / 2
        )
        finishStateTransition(bar)

        XCTAssertTrue(bar.currentStates.contains("emphasis"))
        assertGradient(bar.pathStyle.fill, colors: ["#2378f7", "#2378f7", "#83bff6"])

        view._injectGlobalOutForTest()
        finishStateTransition(bar)
        XCTAssertTrue(bar.currentStates.isEmpty)
        assertGradient(bar.pathStyle.fill, colors: ["#83bff6", "#188df0", "#188df0"])
    }

    private func finishStateTransition(_ element: Element) {
        for animator in element.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(1_000, 1_000) { clip.ondestroy() }
        }
    }

    private func assertGradient(
        _ paint: ZRenderKit.ZRColor?,
        colors: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .linearGradient(let gradient)? = paint else {
            XCTFail("expected a linear-gradient fill, got \(String(describing: paint))", file: file, line: line)
            return
        }
        XCTAssertEqual(
            gradient.colorStops.map { color.parse($0.color) },
            colors.map { color.parse($0) },
            file: file,
            line: line
        )
    }
}
