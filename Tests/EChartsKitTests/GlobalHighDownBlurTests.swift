import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Regression: hovering a highDown dispatcher must ALSO drive the focus/blur pass — upstream binds
// `handleGlobalMouseOverForHighDown` / `handleGlobalMouseOutForHighDown` (echarts.ts:2327/2334) on the
// zr mouseover/mouseout, which call `blurSeries` (focus semantics: 'self'/'series'/index-arrays fade
// every non-focused element to the default blur opacity ×0.1) and `allLeaveBlur` on mouseout. A binding
// that only calls `enterEmphasisWhenMouseOver` highlights the hovered element but never blurs the rest
// (reported: chord focus-adjacency and sunburst focus-ancestor had no visible effect).
final class GlobalHighDownBlurTests: XCTestCase {
    private func finishStateTransition(_ el: Element) {
        for animator in el.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(300, 300) { clip.ondestroy() }
        }
    }

    private func opacity(_ el: Element?) -> Double? {
        return (el as? Path)?.pathStyle?.opacity
    }

    private func sectorMidPoint(_ sector: Sector) -> (x: Double, y: Double) {
        let s = sector.shape as! SectorShape
        let a = (s.startAngle + s.endAngle) / 2
        let r = (s.r + s.r0) / 2
        return (s.cx + cos(a) * r, s.cy + sin(a) * r)
    }

    func testPieFocusSelfBlursSiblingsAndMouseOutRestores() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["series": [["type": "pie", "radius": ["0%", "70%"],
                                 "emphasis": ["focus": "self"],
                                 "data": [["name": "A", "value": 60] as [String: Any],
                                          ["name": "B", "value": 40]]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let data = v.ec.getModel()!.getSeriesByIndex(0)!.getData()
        let s0 = data.getItemGraphicEl(0) as! Sector
        let s1 = data.getItemGraphicEl(1) as! Sector
        XCTAssertEqual(opacity(s1) ?? 1, 1, accuracy: 1e-9, "baseline: sibling fully opaque")

        // Hover sector 0 → sector 1 must enter blur AND render faded (default blur = opacity ×0.1).
        let p0 = sectorMidPoint(s0)
        v._injectPointerForTest(type: "mousemove", zrX: p0.x, zrY: p0.y)

        XCTAssertTrue(s0.currentStates.contains("emphasis"), "hovered sector enters emphasis")
        XCTAssertTrue(s1.currentStates.contains("blur"),
                      "focus:'self' must blur the non-hovered sibling (states=\(s1.currentStates))")
        finishStateTransition(s1)
        XCTAssertEqual(opacity(s1) ?? 1, 0.1, accuracy: 1e-6,
                       "blurred sibling must RENDER faded, got opacity=\(String(describing: opacity(s1)))")

        // Move off the pie entirely → allLeaveBlur must restore the sibling.
        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(s1.currentStates.contains("blur"), "mouseout must leave blur")
        finishStateTransition(s1)
        XCTAssertEqual(opacity(s1) ?? 1, 1, accuracy: 1e-6, "opacity restored after mouseout")
    }

    // MULTI-series focus:'series' — the blur must target the HOVERED element's series. Regression for
    // the setItemGraphicEl seriesIndex-hardcoded-0 gap: hovering a series-1 bar ran the fan-out against
    // series 0's identity, keeping the OTHER series bright and blurring the hovered one (inverted).
    func testBarFocusSeriesBlursOtherSeriesNotOwn() {
        let v = EChartsView(width: 480, height: 360)
        v.setOption(["animation": false,
                     "xAxis": ["type": "category", "data": ["A", "B"]] as [String: Any],
                     "yAxis": ["type": "value"],
                     "series": [["type": "bar", "data": [10, 20],
                                 "emphasis": ["focus": "series"]] as [String: Any],
                                ["type": "bar", "data": [15, 25],
                                 "emphasis": ["focus": "series"]] as [String: Any]]])
        _ = v.zr.storage.getDisplayList(true)
        let model = v.ec.getModel()!
        let bar0 = model.getSeriesByIndex(0)!.getData().getItemGraphicEl(0) as! Rect
        let bar1 = model.getSeriesByIndex(1)!.getData().getItemGraphicEl(0) as! Rect

        // Hover a SERIES-1 bar.
        let s = bar1.shape as! RectShape
        v._injectPointerForTest(type: "mousemove", zrX: s.x + s.width / 2, zrY: s.y + s.height / 2)

        XCTAssertTrue(bar1.currentStates.contains("emphasis"), "hovered series-1 bar enters emphasis")
        XCTAssertFalse(bar1.currentStates.contains("blur"), "hovered bar's OWN series must stay bright")
        XCTAssertTrue(bar0.currentStates.contains("blur"),
                      "focus:'series' must blur the OTHER series (states=\(bar0.currentStates))")

        v._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(bar0.currentStates.contains("blur"), "mouseout restores the other series")
    }
}
