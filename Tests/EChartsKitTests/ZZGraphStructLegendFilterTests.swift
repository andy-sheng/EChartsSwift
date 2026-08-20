// Legend filtering for NODE+EDGE series (chord / graph / sankey): hiding a node must also drop the
// edges that touch it, and the layout must be recomputed over what is left.
//
// Upstream wires this through `linkSeriesData`: it wraps the node data's CHANGABLE_METHODS
// (`filterSelf` / `selectRange`) with `changeInjection`, which calls `struct.update()` — i.e.
// `Graph.update()` (data/Graph.ts:271), which re-maps every node's dataIndex AND runs
// `edgeData.filterSelf(edge => edge.node1.dataIndex >= 0 && edge.node2.dataIndex >= 0)`.
//
// The port stores wrapped-method injections in a side table instead of rebinding the method, and
// `transferProperties` did not carry that table onto clones — while `legendDataFilter` filters
// `seriesModel.getData()`, which after the data task IS a clone. So the injection never fired:
// `Graph.update()` ran only once, at graph construction. Symptoms: the hidden node's ribbons keep
// being drawn, and the remaining arcs keep their pre-click angles.
//
// Found by a structural native/web scene sweep, not by pixels — official-chord-simple scores 0.12%
// on the PNG oracle because the phantom ribbon happens to land under other geometry.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ZZGraphStructLegendFilterTests: XCTestCase {

    private func chordOption(animation: Bool = false) -> [String: Any] {
        return [
            "animation": animation,
            "legend": [:] as [String: Any],
            "series": [
                [
                    "type": "chord",
                    "clockwise": false,
                    "label": ["show": true] as [String: Any],
                    "data": [
                        ["name": "A"] as [String: Any],
                        ["name": "B"] as [String: Any],
                        ["name": "C"] as [String: Any],
                        ["name": "D"] as [String: Any]
                    ],
                    "links": [
                        ["source": "A", "target": "B", "value": 40.0] as [String: Any],
                        ["source": "A", "target": "C", "value": 20.0] as [String: Any],
                        ["source": "B", "target": "D", "value": 20.0] as [String: Any]
                    ]
                ] as [String: Any]
            ]
        ]
    }

    private func makeChord() -> ECharts {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption(chordOption())
        return ec
    }

    private func series(_ ec: ECharts) -> ChordSeriesModel {
        ec.getModel()!.getSeriesByIndex(0) as! ChordSeriesModel
    }

    private func nodeNames(_ ec: ECharts) -> [String] {
        let d = series(ec).getData()
        return (0..<d.count()).map { d.getName($0) }
    }

    private func sweep(_ ec: ECharts, _ name: String) -> Double {
        let d = series(ec).getData()
        guard let idx = (0..<d.count()).first(where: { d.getName($0) == name }),
              let layout = d.graph?.getNodeByIndex(idx)?.getLayout() as? [String: Any],
              let s = layout["startAngle"] as? Double,
              let e = layout["endAngle"] as? Double else { return .nan }
        return abs(e - s)
    }

    /// Total sweep of every visible node arc. Not 2π: chord pads between arcs (`padAngle` defaults to
    /// 3°), and the number of pads changes with the number of visible nodes — so assertions are made on
    /// each node's SHARE of this total, which is padding-independent.
    private func arcSweepSum(_ ec: ECharts) -> Double {
        let d = series(ec).getData()
        guard let graph = d.graph else { return .nan }
        var sum = 0.0
        graph.eachNode { node, _ in
            guard let layout = node.getLayout() as? [String: Any],
                  let s = layout["startAngle"] as? Double,
                  let e = layout["endAngle"] as? Double,
                  s.isFinite, e.isFinite else { return }
            sum += abs(e - s)
        }
        return sum
    }

    func testChordLegendToggleFiltersTouchingEdges() {
        let ec = makeChord()
        XCTAssertEqual(nodeNames(ec).sorted(), ["A", "B", "C", "D"])
        XCTAssertEqual(series(ec).getEdgeData().count(), 3, "three links initially")

        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        ec.dispatchAction(off)

        XCTAssertEqual(nodeNames(ec).sorted(), ["A", "B", "C"], "node D filtered out")
        // The heart of it: B→D touches the hidden node, so upstream's Graph.update() drops it.
        XCTAssertEqual(series(ec).getEdgeData().count(), 2,
                       "the B→D link must be filtered out with node D — a ribbon to a hidden node is a phantom")
    }

    func testChordLegendToggleRelayoutsRemainingArcs() {
        let ec = makeChord()
        // A node's arc is proportional to the sum of its edge values. Links: A-B 40, A-C 20, B-D 20, so
        // every edge is counted at both ends: total 160, A = 60 -> A owns 0.375 of the ring.
        XCTAssertEqual(sweep(ec, "A") / arcSweepSum(ec), 60.0 / 160.0, accuracy: 1e-9,
                       "A owns 60/160 of the ring while all four nodes are visible")

        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "D"
        ec.dispatchAction(off)

        // Hiding D removes the B-D link, so the total drops to 2*(40+20) = 120 and A now owns 60/120.
        // This only holds if the layout re-runs over the FILTERED graph; keeping the 4-node angles
        // leaves A at 0.375.
        XCTAssertEqual(sweep(ec, "A") / arcSweepSum(ec), 60.0 / 120.0, accuracy: 1e-9,
                       "with D and the B→D link gone, A must be re-laid out to half the ring")
    }

    func testChordLegendToggleKeepsRemovedArcAliveForLeaveFade() throws {
        let view = EChartsView(width: 640, height: 420)
        var option = chordOption(animation: true)
        option["animationDurationUpdate"] = 500.0
        view.setOption(option)

        let oldData = try XCTUnwrap((view.ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)?.getData())
        let dIndex = try XCTUnwrap((0..<oldData.count()).first { oldData.getName($0) == "D" })
        let dPiece = try XCTUnwrap(oldData.getItemGraphicEl(dIndex) as? ChordPiece)
        XCTAssertNotNil(dPiece.__zr)

        var off = Payload(type: "legendToggleSelect")
        off.other["name"] = "D"
        view.ec.dispatchAction(off)

        XCTAssertNotNil(dPiece.parent,
                        "the removed D arc must remain attached until its leave fade completes")
        let leave = try XCTUnwrap(dPiece.animators.first { $0.scope == "leave" })
        let clip = try XCTUnwrap(leave.getClip())
        clip.resetForDeterministicSampling()
        _ = clip.sampleForDeterministicRendering(at: 0)
        XCTAssertEqual(dPiece.pathStyle.opacity ?? -1, 1, accuracy: 1e-9,
                       "the leave animation must begin from the visible arc, not snap to opacity 0")
    }

    func testChordLegendToggleInterpolatesRemainingArcAndRibbon() throws {
        let view = EChartsView(width: 640, height: 420)
        var option = chordOption(animation: true)
        option["animationDuration"] = 0.0
        option["animationDurationUpdate"] = 500.0
        option["animationEasingUpdate"] = "linear"
        view.setOption(option)

        var off = Payload(type: "legendToggleSelect")
        off.other["name"] = "D"
        view.ec.dispatchAction(off)

        let chordSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)
        let data = chordSeries.getData()
        let aIndex = try XCTUnwrap((0..<data.count()).first { data.getName($0) == "A" })
        let aPiece = try XCTUnwrap(data.getItemGraphicEl(aIndex) as? ChordPiece)
        let arcClip = try XCTUnwrap(aPiece.animators.first { $0.targetName == "shape" }?.getClip())
        arcClip.resetForDeterministicSampling()
        _ = arcClip.sampleForDeterministicRendering(at: 0)
        let arcStart = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        _ = arcClip.sampleForDeterministicRendering(at: 250)
        let arcMiddle = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        _ = arcClip.sampleForDeterministicRendering(at: 500)
        let arcEnd = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        XCTAssertNotEqual(arcStart, arcEnd, accuracy: 1e-9)
        XCTAssertEqual(arcMiddle, (arcStart + arcEnd) / 2, accuracy: 1e-6,
                       "remaining chord arcs must visibly interpolate after a legend toggle")

        let edgeData = chordSeries.getEdgeData()
        let edge = try XCTUnwrap((0..<edgeData.count()).lazy
            .compactMap { edgeData.getItemGraphicEl($0) as? ChordEdge }.first)
        let edgeClip = try XCTUnwrap(edge.animators.first { $0.targetName == "shape" }?.getClip())
        edgeClip.resetForDeterministicSampling()
        _ = edgeClip.sampleForDeterministicRendering(at: 0)
        let ribbonStart = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        _ = edgeClip.sampleForDeterministicRendering(at: 250)
        let ribbonMiddle = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        _ = edgeClip.sampleForDeterministicRendering(at: 500)
        let ribbonEnd = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        XCTAssertNotEqual(ribbonStart, ribbonEnd, accuracy: 1e-9)
        XCTAssertEqual(ribbonMiddle, (ribbonStart + ribbonEnd) / 2, accuracy: 1e-6,
                       "remaining chord ribbons must visibly interpolate with the arcs")
    }

    func testChordRealLegendClickSequenceKeepsUpdateAnimation() throws {
        let view = EChartsView(width: 640, height: 420)
        var option = chordOption(animation: true)
        option["animationDuration"] = 0.0
        option["animationDurationUpdate"] = 500.0
        option["animationEasingUpdate"] = "linear"
        view.setOption(option)

        let oldData = try XCTUnwrap((view.ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)?.getData())
        let oldDIndex = try XCTUnwrap((0..<oldData.count()).first { oldData.getName($0) == "D" })
        let oldDPiece = try XCTUnwrap(oldData.getItemGraphicEl(oldDIndex) as? ChordPiece)

        // LegendView dispatchSelectAction sends these three actions synchronously for a data legend
        // item. Keep this exact sequence here: a lone legendToggleSelect does not reproduce clicks.
        var downplay = Payload(type: "downplay")
        downplay.other["name"] = "D"
        view.ec.dispatchAction(downplay)
        var toggle = Payload(type: "legendToggleSelect")
        toggle.other["name"] = "D"
        view.ec.dispatchAction(toggle)
        var highlight = Payload(type: "highlight")
        highlight.other["name"] = "D"
        view.ec.dispatchAction(highlight)

        let chordSeries = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)
        let data = chordSeries.getData()
        let aIndex = try XCTUnwrap((0..<data.count()).first { data.getName($0) == "A" })
        let aPiece = try XCTUnwrap(data.getItemGraphicEl(aIndex) as? ChordPiece)
        let arcClip = try XCTUnwrap(aPiece.animators.first { $0.targetName == "shape" }?.getClip(),
                                    "the post-click highlight must not discard the arc update animator")
        arcClip.resetForDeterministicSampling()
        _ = arcClip.sampleForDeterministicRendering(at: 0)
        let start = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        _ = arcClip.sampleForDeterministicRendering(at: 250)
        let middle = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        _ = arcClip.sampleForDeterministicRendering(at: 500)
        let end = try XCTUnwrap(aPiece.shape as? SectorShape).endAngle
        XCTAssertNotEqual(start, end, accuracy: 1e-9)
        XCTAssertEqual(middle, (start + end) / 2, accuracy: 1e-6)

        let edgeData = chordSeries.getEdgeData()
        let edge = try XCTUnwrap((0..<edgeData.count()).lazy
            .compactMap { edgeData.getItemGraphicEl($0) as? ChordEdge }.first)
        let ribbonClip = try XCTUnwrap(edge.animators.first { $0.targetName == "shape" }?.getClip(),
                                       "the post-click highlight must not discard the ribbon animator")
        ribbonClip.resetForDeterministicSampling()
        _ = ribbonClip.sampleForDeterministicRendering(at: 0)
        let ribbonStart = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        _ = ribbonClip.sampleForDeterministicRendering(at: 250)
        let ribbonMiddle = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        _ = ribbonClip.sampleForDeterministicRendering(at: 500)
        let ribbonEnd = try XCTUnwrap(edge.shape as? ChordPathShape).sEndAngle
        XCTAssertNotEqual(ribbonStart, ribbonEnd, accuracy: 1e-9)
        XCTAssertEqual(ribbonMiddle, (ribbonStart + ribbonEnd) / 2, accuracy: 1e-6)

        let leaveClip = try XCTUnwrap(oldDPiece.animators.first { $0.scope == "leave" }?.getClip())
        leaveClip.resetForDeterministicSampling()
        _ = leaveClip.sampleForDeterministicRendering(at: 0)
        XCTAssertEqual(oldDPiece.pathStyle.opacity ?? -1, 1, accuracy: 1e-9,
                       "post-click highlight must not pre-dim the removed chord arc before its leave fade")
    }
}
