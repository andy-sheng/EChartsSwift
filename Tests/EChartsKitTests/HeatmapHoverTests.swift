import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: heatmap had NO hover state — upstream HeatmapView wires every cell rect with
// setStatesStylesFromModel + toggleHoverEmphasis (HeatmapView.ts:329-333), so hovering a cell
// enters emphasis and (with no explicit emphasis.itemStyle) LIFTS the fill via the default
// state proxy, exactly like bar.
final class HeatmapHoverTests: XCTestCase {
    // Other suites register test doubles into the GLOBAL ComponentModel registry; re-register the real
    // axis + heatmap models so this suite is order-independent (same pattern as HeatmapMorphTests).
    override func setUp() {
        super.setUp()
        ComponentModel.registerClass(EChartsXAxisModel.self)
        ComponentModel.registerClass(EChartsYAxisModel.self)
        ComponentModel.registerClass(HeatmapSeriesModel.self)
    }

    private func fillString(_ el: Element?) -> String? {
        guard let p = el as? Path else { return nil }
        if case let .string(s)? = p.pathStyle?.fill { return s }
        return nil
    }

    private func makeView(emphasis: [String: Any]? = nil) -> EChartsView {
        let v = EChartsView(width: 480, height: 360)
        var series: [String: Any] = [
            "type": "heatmap",
            "data": [[0, 0, 5], [1, 0, 1], [0, 1, 3], [1, 1, 8]] as [[Double]]
        ]
        if let emphasis = emphasis { series["emphasis"] = emphasis }
        v.setOption(["animation": false,
                     "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                     "xAxis": ["type": "category", "data": ["a", "b"]] as [String: Any],
                     "yAxis": ["type": "category", "data": ["c", "d"]] as [String: Any],
                     "visualMap": [
                         "type": "continuous", "min": 0.0, "max": 10.0,
                         "inRange": ["color": ["#313695", "#fee090", "#a50026"]] as [String: Any]
                     ] as [String: Any],
                     "series": [series]])
        _ = v.zr.storage.getDisplayList(true)
        return v
    }

    private func hoverCell(_ v: EChartsView, _ rect: Rect) {
        let s = rect.shape as! RectShape
        v._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: s.y + s.height / 2)
    }

    func testHeatmapHoverLiftsFillAndRestores() {
        let v = makeView()
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let cell = data.getItemGraphicEl(0) as! Rect
        let normalFill = fillString(cell)
        XCTAssertNotNil(normalFill, "cell has a visualMap fill")

        hoverCell(v, cell)
        XCTAssertTrue(cell.currentStates.contains("emphasis"),
                      "hovering a heatmap cell must enter emphasis (states=\(cell.currentStates))")
        XCTAssertNotEqual(fillString(cell), normalFill,
                          "default emphasis must LIFT the cell fill — normal=\(normalFill ?? "nil") hover=\(fillString(cell) ?? "nil")")

        v._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        XCTAssertFalse(cell.currentStates.contains("emphasis"), "mouseout leaves emphasis")
        XCTAssertEqual(fillString(cell), normalFill, "fill restored after mouseout")
    }

    func testHeatmapExplicitEmphasisStyleApplies() {
        let v = makeView(emphasis: ["itemStyle": ["borderColor": "#333", "borderWidth": 2.0] as [String: Any]])
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let cell = data.getItemGraphicEl(0) as! Rect

        hoverCell(v, cell)
        XCTAssertTrue(cell.currentStates.contains("emphasis"))
        XCTAssertEqual(cell.pathStyle?.lineWidth, 2.0,
                       "explicit emphasis.itemStyle.borderWidth must render on hover")
    }
}
