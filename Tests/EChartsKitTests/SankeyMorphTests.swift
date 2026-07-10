// Transition-fidelity: SankeyView now persists its node rects (keyed by node index) and link ribbons
// (keyed by edge index) and MORPHS them on a same-count merge-mode value change (the sankey layout
// re-places node boxes / re-sizes ribbon bands) instead of removeAll-rebuilding (snap). This asserts a
// node rect ELEMENT is reused across the value change and schedules a shape-morph animator, and that a
// node/link-count change rebuilds fresh with no duplication.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SankeyMorphTests: XCTestCase {

    // All node rects (name == "node") across the chart views' groups.
    private func nodeRects(_ ec: ECharts) -> [ZRenderKit.Rect] {
        var out: [ZRenderKit.Rect] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if el.name == "node", let r = el as? ZRenderKit.Rect { out.append(r) }
                return false
            })
        }
        return out
    }

    // All link ribbons (SankeyPath) across the chart views' groups.
    private func linkPaths(_ ec: ECharts) -> [SankeyPath] {
        var out: [SankeyPath] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let p = el as? SankeyPath { out.append(p) }
                return false
            })
        }
        return out
    }

    private func option(_ links: [[String: Any]]) -> [String: Any] {
        ["animation": true,
         "series": [["type": "sankey",
                     "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                     "nodeWidth": 20.0, "nodeGap": 8.0,
                     "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                     "links": links] as [String: Any]]]
    }

    private let linksA: [[String: Any]] = [
        ["source": "a", "target": "b", "value": 5.0],
        ["source": "a", "target": "c", "value": 3.0],
        ["source": "b", "target": "d", "value": 4.0],
        ["source": "c", "target": "d", "value": 2.0]]
    // Same nodes + links, different values → different node throughput (heights) + ribbon widths.
    private let linksB: [[String: Any]] = [
        ["source": "a", "target": "b", "value": 1.0],
        ["source": "a", "target": "c", "value": 9.0],
        ["source": "b", "target": "d", "value": 2.0],
        ["source": "c", "target": "d", "value": 8.0]]

    func testNodeAndLinkMorphOnValueChange() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption(option(linksA))

        let rectsBefore = nodeRects(ec)
        XCTAssertFalse(rectsBefore.isEmpty, "sankey first render produced node rects")
        let capturedRect = rectsBefore[0]
        let capturedLink = linkPaths(ec).first

        // Clear the first render's entrance (opacity fade) animators.
        for v in ec.testChartViews { _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false }) }

        // Merge-mode value change: same 4 nodes + 4 links, values changed → morph.
        ec.setOption(["series": [["type": "sankey", "links": linksB] as [String: Any]]])

        // (1) The SAME node rect instance is reused (not rebuilt).
        let rectsAfter = nodeRects(ec)
        XCTAssertEqual(rectsAfter.count, rectsBefore.count, "same node count → no rebuild/duplication")
        XCTAssertTrue(rectsAfter.contains(where: { $0 === capturedRect }),
                      "a node rect instance is reused across the value change")
        if let cl = capturedLink {
            XCTAssertTrue(linkPaths(ec).contains(where: { $0 === cl }),
                          "a link ribbon instance is reused across the value change")
        }

        // (2) The morph scheduled shape animators (node boxes re-placed + ribbons re-sized).
        let nodeAnimators = rectsAfter.reduce(0) { $0 + $1.animators.count }
        let linkAnimators = linkPaths(ec).reduce(0) { $0 + $1.animators.count }
        XCTAssertGreaterThan(nodeAnimators + linkAnimators, 0,
                             "a same-count value change must schedule shape-morph animators")
    }

    // A node/link-count change rebuilds fresh — no stale duplication.
    func testCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption(option(linksA))
        XCTAssertEqual(nodeRects(ec).count, 4)

        // Add a fifth node + a link into it → node/edge count changes → rebuild fresh.
        let opt2: [String: Any] = ["series": [["type": "sankey",
            "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"], ["name": "e"]],
            "links": linksA + [["source": "d", "target": "e", "value": 6.0]]] as [String: Any]]]
        ec.setOption(opt2)
        XCTAssertEqual(nodeRects(ec).count, 5, "count change rebuilds a single set of node rects, no duplicate")
        XCTAssertEqual(linkPaths(ec).count, 5, "count change rebuilds a single set of link ribbons, no duplicate")
    }
}
