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
import CoreGraphics
@testable import EChartsKit
@testable import ZRenderKit
import NativePainter

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

    func testChordFLabelReturnsAfterRapidLegendOffOnAndPointerLeave() throws {
        let view = EChartsView(width: 640, height: 420)
        let officialOption: [String: Any] = [
            "animation": true,
            "animationDuration": 0.0,
            "animationDurationUpdate": 500.0,
            "legend": [:] as [String: Any],
            "series": [[
                "type": "chord",
                "data": ["A", "B", "C", "D", "E", "F", "G"].map {
                    ["name": $0] as [String: Any]
                },
                "label": [
                    "show": true,
                    "position": "inside",
                    "color": "#fff",
                    "fontWeight": "bold"
                ] as [String: Any],
                "links": [
                    ["source": "A", "target": "B", "value": 14.0],
                    ["source": "A", "target": "C", "value": 8.0],
                    ["source": "B", "target": "C", "value": 20.0],
                    ["source": "B", "target": "E", "value": 15.0],
                    ["source": "C", "target": "B", "value": 8.0],
                    ["source": "C", "target": "E", "value": 3.0],
                    ["source": "D", "target": "A", "value": 12.0],
                    ["source": "D", "target": "B", "value": 3.0],
                    ["source": "E", "target": "A", "value": 15.0],
                    ["source": "E", "target": "C", "value": 5.0],
                    ["source": "F", "target": "C", "value": 5.0],
                    ["source": "G", "target": "A", "value": 6.0],
                    ["source": "G", "target": "B", "value": 8.0],
                    ["source": "G", "target": "D", "value": 4.0]
                ] as [[String: Any]]
            ] as [String: Any]]
        ]
        view.setOption(officialOption)

        func clickLegendItem(_ name: String, movePointer: Bool = true) {
            // LegendView rebuilds every item synchronously after legendToggleSelect. Resolve the NEW
            // hit rect and drive the same live Handler path as AppKit for every click; dispatching
            // directly to the old group hides bugs caused by stale hover/press targets.
            XCTAssertNotNil(
                view._injectLegendClickForTest(name: name, movePointer: movePointer),
                "legend item \(name) must be hit-testable"
            )
        }

        func finishAllAnimations() {
            var elements: [Element] = []
            func collect(_ element: Element) {
                elements.append(element)
                if let text = element.getTextContent() { collect(text) }
                if let guide = element.getTextGuideLine() { collect(guide) }
                if let group = element as? Group {
                    for child in group.children() { collect(child) }
                }
            }
            collect(view.ec.getRoot())
            var seen = Set<ObjectIdentifier>()
            let clips = elements.flatMap(\.animators).compactMap { $0.getClip() }.filter {
                seen.insert(ObjectIdentifier($0)).inserted
            }
            for clip in clips {
                clip.resetForDeterministicSampling()
                if clip.sampleForDeterministicRendering(at: 1_000_000_000) {
                    clip.ondestroy()
                }
            }
        }

        finishAllAnimations()
        clickLegendItem("F")
        XCTAssertFalse((view.ec.getModel()?.getComponent("legend") as? LegendModel)?.isSelected("F") ?? true)
        // A real second click at the same screen point does not emit another mouseMoved event. The
        // first click has already rebuilt LegendView, so Handler._hovered still references the old F
        // item while mousedown/up/click hit-test the new one. It can also happen before F's leave fade
        // completes, leaving the old and newly added pieces alive at the same time.
        clickLegendItem("F", movePointer: false)
        XCTAssertTrue((view.ec.getModel()?.getComponent("legend") as? LegendModel)?.isSelected("F") ?? false)

        // Match the screenshot: after the second click the pointer leaves the rebuilt F legend item
        // and moves onto empty canvas BEFORE the new F label's enter fade has completed. Downplay must
        // not freeze the in-flight opacity at zero.
        view._injectPointerForTest(type: "mousemove", zrX: 1, zrY: 1)
        finishAllAnimations()

        view._injectGlobalOutForTest()
        finishAllAnimations()

        let data = try XCTUnwrap(
            (view.ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)?.getData()
        )
        let labels = (0..<data.count()).reduce(into: [String: ZRText?]()) { result, idx in
            let name = data.getName(idx)
            let piece = data.getItemGraphicEl(idx) as? ChordPiece
            result[name] = piece?.getTextContent()
        }

        XCTAssertEqual(Set(labels.keys), Set(["A", "B", "C", "D", "E", "F", "G"]))
        for name in ["A", "B", "C", "D", "E", "F", "G"] {
            let label = try XCTUnwrap(labels[name] ?? nil,
                                      "reselected chord node \(name) must own a label")
            XCTAssertEqual(label.textStyle?.text, name)
            XCTAssertFalse(label.ignore, "reselected chord label \(name) must be visible")
            XCTAssertFalse(label.invisible, "reselected chord label \(name) must be paintable")
            XCTAssertFalse(label.currentStates.contains("blur"),
                           "leaving the legend must restore chord label \(name) from blur")
            XCTAssertFalse(label.currentStates.contains("emphasis"),
                           "leaving the legend must restore chord label \(name) from emphasis")
            XCTAssertGreaterThan(label.textStyle?.opacity ?? 1, 0.99,
                                 "leaving the legend must restore chord label \(name) opacity")
            let idx = try XCTUnwrap((0..<data.count()).first { data.getName($0) == name })
            let piece = try XCTUnwrap(data.getItemGraphicEl(idx) as? ChordPiece)
            XCTAssertGreaterThan(label.z2, piece.z2,
                                 "reselected chord label \(name) must paint above its sector")
        }

        // Structural state can look correct while NativePainter still omits a stale/rebuilt text
        // child. The fully settled F-label pixels must match a fresh chart. (The whole chart is not
        // byte-identical because removing/re-adding F legitimately changes equal-z ribbon insertion
        // order, which only affects a few antialiased overlap pixels.)
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let subject = try XCTUnwrap(renderToImage(
            group: view.ec.getRoot(), size: CGSize(width: 640, height: 420), dpr: 1,
            backgroundColor: white
        ))
        var controlOption = officialOption
        controlOption["animation"] = false
        let controlEC = ECharts(width: 640, height: 420)
        controlEC.setOption(controlOption)
        let control = try XCTUnwrap(renderToImage(
            group: controlEC.getRoot(), size: CGSize(width: 640, height: 420), dpr: 1,
            backgroundColor: white
        ))

        func fLabel(_ ec: ECharts) throws -> ZRText {
            let data = try XCTUnwrap((ec.getModel()?.getSeriesByIndex(0) as? ChordSeriesModel)?.getData())
            let idx = try XCTUnwrap((0..<data.count()).first { data.getName($0) == "F" })
            let piece = try XCTUnwrap(data.getItemGraphicEl(idx) as? ChordPiece)
            return try XCTUnwrap(piece.getTextContent())
        }
        let subjectF = try fLabel(view.ec)
        let controlF = try fLabel(controlEC)
        XCTAssertEqual(subjectF.z2, controlF.z2,
                       "downplay must restore the rebuilt F label's normal z2")
        XCTAssertEqual(subjectF.transform, controlF.transform)
        let subjectRun = try XCTUnwrap(subjectF.childrenRef().compactMap { $0 as? TSpan }.first)
        let controlRun = try XCTUnwrap(controlF.childrenRef().compactMap { $0 as? TSpan }.first)
        XCTAssertEqual(subjectRun.z2, controlRun.z2)
        XCTAssertEqual(subjectRun.tspanStyle?.text, controlRun.tspanStyle?.text)
        XCTAssertEqual(subjectRun.tspanStyle?.opacity, controlRun.tspanStyle?.opacity)
        XCTAssertEqual(subjectRun.transform, controlRun.transform)

        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { raw in
                let ctx = CGContext(
                    data: raw.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return bytes
        }
        let subjectPixels = pixels(subject)
        let controlPixels = pixels(control)
        let fRun = try XCTUnwrap(controlF.childrenRef().compactMap { $0 as? TSpan }.first)
        let fBounds = try XCTUnwrap(fRun.getBoundingRect()).clone()
        fBounds.applyTransform(fRun.transform)
        let minX = max(0, Int(floor(fBounds.x)) - 2)
        let maxX = min(subject.width - 1, Int(ceil(fBounds.x + fBounds.width)) + 2)
        let minY = max(0, Int(floor(fBounds.y)) - 2)
        let maxY = min(subject.height - 1, Int(ceil(fBounds.y + fBounds.height)) + 2)
        var fDifferingBytes = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let base = (y * subject.width + x) * 4
                fDifferingBytes += zip(subjectPixels[base..<(base + 4)], controlPixels[base..<(base + 4)])
                    .lazy.filter { $0 != $1 }.count
            }
        }
        XCTAssertEqual(fDifferingBytes, 0,
                       "F off/on/downplay must repaint the F label exactly like a fresh chart")
    }
}
