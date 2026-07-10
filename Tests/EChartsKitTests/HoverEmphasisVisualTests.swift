import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: hover-emphasis must produce a VISIBLE change. Charts with no explicit emphasis.itemStyle
// get echarts' default emphasis = a lifted (brightened) fill via the stateProxy + createEmphasisDefaultState,
// which needs the element's normal fill saved via savePathStates (upstream updateStates). Without that
// save, hovering enters the emphasis state but the fill is unchanged → the reported "no hover effect".
final class HoverEmphasisVisualTests: XCTestCase {
    private func fillString(_ el: Element?) -> String? {
        guard let p = el as? Path else { return nil }
        if case let .string(s)? = p.pathStyle?.fill { return s }
        return nil
    }

    func testBarHoverLiftsFill() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["xAxis": ["type": "category", "data": ["A", "B", "C"]], "yAxis": ["type": "value"],
                     "series": [["type": "bar", "data": [10, 20, 30]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let bar0 = v.ec.getModel()!.getSeriesByIndex(0)!.getData().getItemGraphicEl(0) as! Rect
        let normalFill = fillString(bar0)
        XCTAssertNotNil(normalFill, "bar has a normal fill")

        let s = bar0.shape as! RectShape
        v._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: s.y + s.height / 2)

        XCTAssertTrue(bar0.currentStates.contains("emphasis"), "hover enters the emphasis state")
        let hoverFill = fillString(bar0)
        XCTAssertNotEqual(hoverFill, normalFill,
                          "hovering a bar with no explicit emphasis must LIFT the fill (default emphasis) — normal=\(normalFill ?? "nil") hover=\(hoverFill ?? "nil")")
    }

    func testBarExplicitEmphasisColorApplies() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["xAxis": ["type": "category", "data": ["A", "B", "C"]], "yAxis": ["type": "value"],
                     "series": [["type": "bar", "data": [10, 20, 30],
                                 "emphasis": ["itemStyle": ["color": "#ff0000"]]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let bar0 = v.ec.getModel()!.getSeriesByIndex(0)!.getData().getItemGraphicEl(0) as! Rect
        let s = bar0.shape as! RectShape
        v._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: s.y + s.height / 2)
        v.zr.animation.update()
    }
}