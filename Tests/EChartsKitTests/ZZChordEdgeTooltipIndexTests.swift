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

// Chord ribbons must TWEEN to their new layout, not snap. `updateProps` only builds an animator when
// the shape props are a per-key bag; passing the ChordPathShape struct made the animator take it as one
// discrete leaf, so the ribbons jumped while the node arcs (which pass a dict) animated.
private let ChordPathShapeAnimKeys = ["s1", "s2", "sStartAngle", "sEndAngle",
                                      "t1", "t2", "tStartAngle", "tEndAngle", "cx", "cy", "r"]

final class ZZChordEdgeUpdateAnimationTests: XCTestCase {
    func testRibbonsGetAShapeAnimatorOnLegendToggle() {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption([
            "animation": true,
            "legend": [:] as [String: Any],
            "series": [["type": "chord", "clockwise": false,
                        "data": [["name": "A"], ["name": "B"], ["name": "C"], ["name": "D"]] as [[String: Any]],
                        "links": [["source": "A", "target": "B", "value": 40.0] as [String: Any],
                                  ["source": "A", "target": "C", "value": 20.0] as [String: Any],
                                  ["source": "B", "target": "D", "value": 20.0] as [String: Any]]] as [String: Any]]
        ])
        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        ec.dispatchAction(off)

        var ribbons = 0, animated = 0, withShapeTrack = 0
        _ = ec.getRoot().traverse { el in
            guard el is ChordEdge else { return false }
            ribbons += 1
            if !el.animators.isEmpty { animated += 1 }
            // A per-key bag yields a "shape"-targeted animator; the whole-struct form yielded none at
            // all. Which individual keys get a track depends on which values actually changed, so the
            // invariant is the shape-targeted animator plus at least one live track.
            if let a = el.animators.first(where: { $0.targetName == "shape" }),
               ChordPathShapeAnimKeys.contains(where: { a.getTrack($0) != nil }) { withShapeTrack += 1 }
            return false
        }
        XCTAssertGreaterThan(ribbons, 0, "the surviving links must still render ribbons")
        XCTAssertEqual(animated, ribbons, "every surviving ribbon must be tweening to its new layout")
        XCTAssertEqual(withShapeTrack, ribbons,
                       "the animator must carry per-key shape tracks — a whole-struct prop yields no tween")
    }
}
