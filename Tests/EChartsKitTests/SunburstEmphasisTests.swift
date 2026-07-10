// Verifies SunburstPiece wires hover EMPHASIS / blur / select for its sectors
// (SunburstPiece.updateData → states.setStatesStylesFromModel + states.toggleHoverEmphasis, mirroring
//  upstream chart/sunburst/SunburstPiece.ts).
//
//   (1) Every drawn sector is a highDown dispatcher; a dispatchAction(highlight) targeting a node's
//       dataIndex drives that sector into the "emphasis" state, and downplay clears it.
//   (2) The sunburst-specific `emphasis.focus:'ancestor'` resolves to the node's ancestor index list
//       (node.getAncestorsIndices, the tree-adjacency analogue of graph 'adjacency'): highlighting a
//       leaf keeps its ancestor CHAIN bright and BLURS every unrelated sector.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SunburstEmphasisTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Canonical owner registration (idempotent; ECharts.installOnce also registers it).
        ComponentModel.registerClass(SunburstSeriesModel.self)
    }

    // The family-tree fixture shared with SunburstLabelTests, plus an `emphasis.focus` per test.
    private func option(focus: String) -> [String: Any] {
        [
            "animation": false,
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "emphasis": ["focus": focus] as [String: Any],
                        "data": [
                            ["name": "Grandpa", "children": [
                                ["name": "Uncle Leo", "value": 15.0, "children": [
                                    ["name": "Cousin Jack", "value": 2.0],
                                    ["name": "Cousin Mary", "value": 5.0]
                                ]],
                                ["name": "Father", "value": 10.0, "children": [
                                    ["name": "Me", "value": 5.0],
                                    ["name": "Brother Peter", "value": 1.0]
                                ]]
                            ]],
                            ["name": "Nancy", "children": [
                                ["name": "Uncle Nike", "value": 10.0, "children": [
                                    ["name": "Cousin Betty", "value": 1.0],
                                    ["name": "Cousin Jenny", "value": 2.0]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ]
    }

    private func idx(_ data: SeriesData, _ name: String) -> Int? {
        for i in 0..<data.count() where data.getName(i) == name { return i }
        return nil
    }

    private func isBlurred(_ el: Element?) -> Bool {
        el?.currentStates.contains("blur") ?? false
    }

    // ---- (1) highlight/downplay round-trip enters/clears emphasis on the targeted sector ----
    func testSunburstSectorHighlightEntersEmphasis() {
        let view = EChartsView(width: 400, height: 400)
        view.setOption(option(focus: "none"))

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()

        guard let leoIdx = idx(data, "Uncle Leo"),
              let jackIdx = idx(data, "Cousin Jack") else {
            XCTFail("sunburst must build named nodes"); return
        }
        guard let target = data.getItemGraphicEl(leoIdx),
              let other = data.getItemGraphicEl(jackIdx) else {
            XCTFail("sunburst render must populate sector elements"); return
        }

        // Every sector is marked a highDown dispatcher by toggleHoverEmphasis.
        XCTAssertTrue(states.isHighDownDispatcher(target),
                      "SunburstPiece must mark each sector a highDown dispatcher")
        XCTAssertTrue(target.currentStates.isEmpty, "no emphasis before highlight")

        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0
        hp.other["dataIndexInside"] = leoIdx
        view.ec.dispatchAction(hp)

        XCTAssertTrue(target.currentStates.contains("emphasis"),
                      "dispatch highlight must enter the emphasis state on the targeted sunburst sector")
        // focus:'none' → no fan-out; a different node is untouched.
        XCTAssertTrue(other.currentStates.isEmpty,
                      "a sector at a different dataIndex must NOT enter emphasis")

        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = leoIdx
        view.ec.dispatchAction(dp)

        XCTAssertTrue(target.currentStates.isEmpty,
                      "dispatch downplay must clear the emphasis state")
    }

    // ---- (2) focus:'ancestor' keeps the highlighted leaf's ancestor chain bright, blurs the rest ----
    func testSunburstAncestorFocusBlursUnrelated() {
        let view = EChartsView(width: 400, height: 400)
        view.setOption(option(focus: "ancestor"))

        let series = view.ec.getModel()!.getSeriesByIndex(0)!
        let data = series.getData()

        // Highlight "Me": ancestor chain = Grandpa → Father → Me (all bright); everything else blurs.
        guard let meIdx = idx(data, "Me"),
              let fatherIdx = idx(data, "Father"),
              let grandpaIdx = idx(data, "Grandpa"),
              let leoIdx = idx(data, "Uncle Leo"),
              let nancyIdx = idx(data, "Nancy") else {
            XCTFail("sunburst must build named nodes"); return
        }

        var hp = Payload(type: "highlight")
        hp.other["seriesIndex"] = 0.0
        hp.other["dataIndexInside"] = meIdx
        view.ec.dispatchAction(hp)

        XCTAssertFalse(isBlurred(data.getItemGraphicEl(meIdx)),
                       "highlighted leaf 'Me' must not be blurred")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(fatherIdx)),
                       "ancestor 'Father' must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(grandpaIdx)),
                       "ancestor 'Grandpa' must stay bright")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(leoIdx)),
                      "unrelated sibling-subtree node 'Uncle Leo' must be blurred")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(nancyIdx)),
                      "unrelated node 'Nancy' must be blurred")

        // downplay clears the blur everywhere.
        var dp = Payload(type: "downplay")
        dp.other["seriesIndex"] = 0.0
        dp.other["dataIndexInside"] = meIdx
        view.ec.dispatchAction(dp)
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(leoIdx)),
                       "downplay must clear the blur on 'Uncle Leo'")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(nancyIdx)),
                       "downplay must clear the blur on 'Nancy'")
    }

    // ---- (3) MOUSE hover (not dispatchAction) runs the focus fan-out — the reported bug ----
    // Default sunburst emphasis.focus is 'descendant': hovering "Uncle Leo" must keep Leo + his
    // children bright and BLUR every unrelated sector, with the blur RENDERED (sunburst default
    // blur.itemStyle.opacity = 0.2), then restore on mouseout.
    func testSunburstMouseHoverAppliesDescendantFocus() {
        let view = EChartsView(width: 400, height: 400)
        var opt = option(focus: "ancestor")
        var series0 = (opt["series"] as! [[String: Any]])[0]
        series0.removeValue(forKey: "emphasis")   // exercise the DEFAULT focus:'descendant'
        opt["series"] = [series0]
        view.setOption(opt)
        _ = view.zr.storage.getDisplayList(true)

        let data = view.ec.getModel()!.getSeriesByIndex(0)!.getData()
        guard let leoIdx = idx(data, "Uncle Leo"),
              let jackIdx = idx(data, "Cousin Jack"),
              let fatherIdx = idx(data, "Father"),
              let nancyIdx = idx(data, "Nancy"),
              let leo = data.getItemGraphicEl(leoIdx) as? Sector else {
            XCTFail("sunburst must build named sector nodes"); return
        }

        // Pointer at the mid-angle / mid-radius of Leo's sector (shape cx/cy are absolute).
        let s = leo.shape as! SectorShape
        let a = (s.startAngle + s.endAngle) / 2, r = (s.r + s.r0) / 2
        view._injectPointerForTest(type: "mousemove", zrX: s.cx + cos(a) * r, zrY: s.cy + sin(a) * r)

        XCTAssertTrue(leo.currentStates.contains("emphasis"), "hovered sector enters emphasis")
        XCTAssertFalse(isBlurred(leo), "hovered node must stay bright")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(jackIdx)),
                       "descendant 'Cousin Jack' must stay bright under focus:'descendant'")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(fatherIdx)),
                      "sibling 'Father' must blur on hover")
        XCTAssertTrue(isBlurred(data.getItemGraphicEl(nancyIdx)),
                      "unrelated subtree 'Nancy' must blur on hover")
        let nancyOpacity = (data.getItemGraphicEl(nancyIdx) as? Path)?.pathStyle?.opacity
        XCTAssertEqual(nancyOpacity ?? 1, 0.2, accuracy: 1e-6,
                       "blur must RENDER (sunburst default blur.itemStyle.opacity 0.2), got \(String(describing: nancyOpacity))")

        // Off the chart → allLeaveBlur restores everything.
        view._injectPointerForTest(type: "mousemove", zrX: 2, zrY: 2)
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(fatherIdx)), "mouseout clears blur")
        XCTAssertFalse(isBlurred(data.getItemGraphicEl(nancyIdx)), "mouseout clears blur")
    }
}
