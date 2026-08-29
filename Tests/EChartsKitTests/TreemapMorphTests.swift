import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// Transition-fidelity tail (batch-A morph idiom): TreemapView now persists its per-node graphic
// elements and MORPHS on updates and drill navigation instead of rebuild-and-snap. A
// value change re-lays-out the squarify rects, so each node group slides and its bg/content rect
// resizes (updateProps shape) to the new slot. This asserts a node rect is identity-reused across the
// change and carries a shape-morph animator, and that a node-count change keeps the matching tile
// while removing stale tiles after the transition.
final class TreemapMorphTests: XCTestCase {

    // All treemap tile rects across the chart views, in a stable pre-order.
    private func allRects(_ ec: ECharts) -> [ZRenderKit.Rect] {
        var out: [ZRenderKit.Rect] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let r = el as? ZRenderKit.Rect { out.append(r) }
                return false
            })
        }
        return out
    }

    private func stopAllAnimation(_ ec: ECharts) {
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false })
        }
    }

    private func rectGeometry(_ rect: ZRenderKit.Rect) -> [Double] {
        let shape = rect.shape as! RectShape
        return [shape.x, shape.y, shape.width, shape.height]
    }

    private func sampleAnimations(_ ec: ECharts, at milliseconds: Double) {
        var clips: [Clip] = []
        var seen = Set<ObjectIdentifier>()
        for view in ec.testChartViews {
            _ = view.group.traverse({ element in
                for animator in element.animators {
                    guard let clip = animator.getClip(), seen.insert(ObjectIdentifier(clip)).inserted else {
                        continue
                    }
                    clips.append(clip)
                }
                return false
            })
        }
        for clip in clips {
            clip.resetForDeterministicSampling()
            _ = clip.sampleForDeterministicRendering(at: milliseconds)
        }
    }

    private func node(named name: String, in series: TreemapSeriesModel) -> TreeNode? {
        guard let tree = series.getData().tree else { return nil }
        var result: TreeNode?
        let visit: TreeTraverseCallback = { candidate in
            if result == nil, candidate.name == name { result = candidate }
            return result == nil ? nil : false
        }
        tree.root.eachNode(["attr": "children", "order": "preorder"], visit)
        return result
    }

    private func series(_ data: [[String: Any]]) -> [String: Any] {
        [
            "animation": true,
            "series": [[
                "type": "treemap",
                "animation": true,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "roam": false, "nodeClick": false, "breadcrumb": ["show": false],
                "data": data
            ] as [String: Any]]
        ]
    }

    func testTileMorphsOnValueChange() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(series([
            ["name": "a", "value": 10.0],
            ["name": "b", "value": 20.0],
            ["name": "c", "value": 30.0]
        ]))
        let before = allRects(ec)
        XCTAssertGreaterThan(before.count, 0, "treemap produced node rects")
        // Clear the first render's enter/opacity animators so we measure only the morph.
        stopAllAnimation(ec)

        // Merge-mode value change, SAME node count → the tiles morph (re-laid-out to new sizes).
        ec.setOption(["series": [[
            "type": "treemap",
            "data": [
                ["name": "a", "value": 30.0],
                ["name": "b", "value": 5.0],
                ["name": "c", "value": 15.0]
            ]
        ] as [String: Any]]])

        let after = allRects(ec)
        // (1) A node rect is identity-reused across the value change (not rebuilt).
        let beforeSet = Set(before.map { ObjectIdentifier($0) })
        let reused = after.filter { beforeSet.contains(ObjectIdentifier($0)) }
        XCTAssertGreaterThan(reused.count, 0, "at least one node rect reused across the value change")

        // (2) A reused rect carries a shape-morph animator (the tile slides/resizes).
        let morphing = reused.contains { rect in
            rect.animators.contains { $0.targetName == "shape" }
        }
        XCTAssertTrue(morphing, "a reused node rect must schedule a shape-morph animator on a same-count value change")
    }

    func testNodeCountChangeReusesMatchingTileWithoutDuplication() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(series([
            ["name": "a", "value": 10.0],
            ["name": "b", "value": 20.0],
            ["name": "c", "value": 30.0]
        ]))
        let firstRects = allRects(ec)
        let firstCount = firstRects.count
        let firstIDs = Set(firstRects.map(ObjectIdentifier.init))
        XCTAssertGreaterThan(firstCount, 0)

        // Two fewer nodes: matching raw indices remain alive while stale tiles leave.
        ec.setOption(["series": [[
            "type": "treemap",
            "data": [
                ["name": "a", "value": 10.0]
            ]
        ] as [String: Any]]])

        let transitionRects = allRects(ec)
        XCTAssertGreaterThan(
            transitionRects.filter { firstIDs.contains(ObjectIdentifier($0)) }.count,
            0,
            "a node-count shrink must retain its matching tile"
        )
        let leaving = transitionRects.filter { rect in
            firstIDs.contains(ObjectIdentifier(rect))
                && rect.animators.contains(where: {
                    $0.scope == "treemap-transition" && $0.targetName == "style" && $0.getClip() != nil
                })
        }
        XCTAssertFalse(leaving.isEmpty, "stale tiles must leave through the shared treemap transition")
        XCTAssertGreaterThan(transitionRects.count, 0, "the surviving node still renders")
    }

    func testRootToNodeMorphsRetainedTilesWhenVisibleNodeCountChanges() throws {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(series([
            ["name": "A", "value": 60.0, "children": [
                ["name": "A1", "value": 20.0],
                ["name": "A2", "value": 40.0, "children": [
                    ["name": "A21", "value": 10.0], ["name": "A22", "value": 30.0]
                ]]
            ]],
            ["name": "B", "value": 40.0, "children": [
                ["name": "B1", "value": 15.0], ["name": "B2", "value": 25.0]
            ]]
        ]))
        stopAllAnimation(ec)
        let before = allRects(ec)
        let beforeIDs = Set(before.map { ObjectIdentifier($0) })
        let beforeGeometry: [ObjectIdentifier: [Double]] = Swift.Dictionary(uniqueKeysWithValues: before.map {
            (ObjectIdentifier($0), rectGeometry($0))
        })
        let seriesModel = try XCTUnwrap(ec.getModel()?.getSeriesByIndex(0) as? TreemapSeriesModel)
        let target = try XCTUnwrap(node(named: "A2", in: seriesModel))

        var payload = Payload(type: "treemapRootToNode")
        payload.other["seriesId"] = seriesModel.id
        payload.other["targetNode"] = target
        ec.dispatchAction(payload)

        let retained = allRects(ec).filter { beforeIDs.contains(ObjectIdentifier($0)) }
        XCTAssertFalse(retained.isEmpty, "zoom navigation must retain matching raw-index tiles")
        let morphing = try XCTUnwrap(retained.first(where: { rect in
            rect.animators.contains(where: {
                $0.scope == "treemap-transition" && $0.targetName == "shape" && $0.getClip() != nil
            })
        }), "a geometrically changed retained tile must carry a live treemap transition clip")
        let oldGeometry = try XCTUnwrap(beforeGeometry[ObjectIdentifier(morphing)])

        XCTAssertEqual(rectGeometry(morphing), oldGeometry,
                       "dispatch must leave the first visible frame at the old tile geometry")
        sampleAnimations(ec, at: 0)
        XCTAssertEqual(rectGeometry(morphing), oldGeometry,
                       "the first drill-down frame must start at the old tile geometry")
        sampleAnimations(ec, at: 450)
        let midpointGeometry = rectGeometry(morphing)
        XCTAssertNotEqual(midpointGeometry, oldGeometry,
                          "the midpoint must leave the old tile geometry")
        sampleAnimations(ec, at: 900)
        XCTAssertNotEqual(rectGeometry(morphing), midpointGeometry,
                          "the final drill-down frame must continue from the midpoint to its target")
    }
}
