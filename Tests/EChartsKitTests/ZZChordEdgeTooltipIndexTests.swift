// Reproduction for the demo-gallery SIGTRAP at ChordSeries.swift:247
//   `nodeData.graph!.getEdgeByIndex(Int(dataIndex))!`
// reached from TooltipView.tryShow -> ChordSeriesModel.formatTooltip on a hover.
//
// Drives the REAL pointer path (`_injectPointerForTest`, the same entry the gallery's mouseMoved
// reaches) over a grid covering the whole canvas, so the dispatcher's `findEventDispatcher` ancestor
// walk is exercised — asking the series to format a tooltip for each element's own stamped ecData
// (as a first version of this test did) bypasses exactly that walk and finds nothing.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ZZChordEdgeTooltipIndexTests: XCTestCase {

    private static let chordOption: [String: Any] = [
        "tooltip": [:] as [String: Any],
        "legend": [:] as [String: Any],
        "series": [
            [
                "type": "chord", "clockwise": false,
                "label": ["show": true] as [String: Any],
                "lineStyle": ["color": "target"] as [String: Any],
                "data": [["name": "A"], ["name": "B"], ["name": "C"], ["name": "D"]] as [[String: Any]],
                "links": [
                    ["source": "A", "target": "B", "value": 40.0] as [String: Any],
                    ["source": "A", "target": "C", "value": 20.0] as [String: Any],
                    ["source": "B", "target": "D", "value": 20.0] as [String: Any]
                ]
            ] as [String: Any]
        ]
    ]

    private func makeView(animation: Bool) -> EChartsView {
        let v = EChartsView(width: 640, height: 420)
        var opt = Self.chordOption
        opt["animation"] = animation
        v.setOption(opt)
        _ = v.zr.storage.getDisplayList(true)
        return v
    }

    /// Sweep the pointer across the canvas. Any trap inside the tooltip build path takes the process
    /// down, so reaching the end of the sweep IS the assertion.
    private func hoverSweep(_ v: EChartsView, step: Double = 7) {
        var y = 1.0
        while y < 420 {
            var x = 1.0
            while x < 640 {
                v._injectPointerForTest(type: "mousemove", zrX: x, zrY: y)
                x += step
            }
            y += step
        }
    }

    func testHoverSweepDoesNotCrash() {
        hoverSweep(makeView(animation: false))
    }

    func testHoverSweepAfterLegendToggleDoesNotCrash() {
        let v = makeView(animation: false)
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        v.ec.dispatchAction(off)
        _ = v.zr.storage.getDisplayList(true)
        hoverSweep(v)
    }

    // The gallery runs with animation ON: elements the filter removed linger for their leave
    // transition, still carrying pre-filter indices.
    func testHoverSweepAfterLegendToggleWithAnimationDoesNotCrash() {
        let v = makeView(animation: true)
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        v.ec.dispatchAction(off)
        _ = v.zr.storage.getDisplayList(true)
        hoverSweep(v)
    }

    /// Hover FIRST (so the tooltip has live state pinned to a pre-filter index), then filter, then
    /// hover again — the order a user actually produces.
    func testHoverThenToggleThenHoverDoesNotCrash() {
        let v = makeView(animation: true)
        hoverSweep(v, step: 23)
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        v.ec.dispatchAction(off)
        _ = v.zr.storage.getDisplayList(true)
        hoverSweep(v, step: 7)
    }
}
