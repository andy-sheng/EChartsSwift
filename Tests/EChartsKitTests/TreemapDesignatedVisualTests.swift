// Upstream treemap resolves per-node visual priority
//   `thisNode > thisLevel > parentNodeDesignated > seriesModel`
// with a trick (TreemapSeries.getInitialData): `designatedVisualItemStyle` is a LIVE-SHARED object
// used as the `itemStyle` of `designatedVisualModel`, which every node item model is (transitively)
// parented onto. `treemapVisual.buildVisuals` writes the parent-designated visual into that bag,
// reads `nodeItemStyleModel.get(visualName)` (which now observes the write through the parent chain),
// then clears the key again.
//
// This regression test locks the write-through: the bag must be a REFERENCE type stored as-is in the
// option tree. If it is ever retyped back to a Swift `[String: Any]` (value semantics), or if some
// `Model.getModel`/`util.clone` seam deep-copies the option, the aliasing is severed silently and the
// "parentNodeDesignated" priority tier disappears — with no build error and no other failing test.
import XCTest
@testable import EChartsKit

final class TreemapDesignatedVisualTests: XCTestCase {

    private func option() -> [String: Any] {
        [
            "series": [[
                "type": "treemap",
                "animation": false,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                // Series-level itemStyle color: the LOWEST priority tier, must win only while the
                // designated bag is empty.
                "itemStyle": ["color": "#abcdef"],
                "data": [
                    ["name": "nodeA", "value": 10.0, "children": [
                        ["name": "nodeA1", "value": 4.0],
                        ["name": "nodeA2", "value": 6.0]
                    ]]
                ]
            ] as [String: Any]]
        ]
    }

    func test_designatedVisualItemStyle_writes_are_observed_through_node_item_models() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option())

        guard let series = ec.getModel()?.getSeriesByType("treemap").first as? TreemapSeriesModel else {
            return XCTFail("no treemap series model")
        }
        let data = series.getData()
        guard let tree = data.tree else { return XCTFail("no treemap tree") }

        // Any real (dataIndex >= 0) node whose datum carries no own itemStyle.color: it must resolve
        // through the parent chain, i.e. through `designatedVisualModel`.
        var node: TreeNode?
        for i in 0..<data.count() {
            if let n = tree.getNodeByDataIndex(i), n.depth > 0 {
                node = n
                break
            }
        }
        guard let leaf = node else { return XCTFail("no non-root treemap node") }

        func resolvedColor() -> String? {
            return leaf.getModel()?.getModel("itemStyle").get("color") as? String
        }

        // Baseline: bag empty → the series-level itemStyle color is what the node sees.
        XCTAssertEqual(resolvedColor(), "#abcdef",
                       "with an empty designated bag the node must fall through to the series itemStyle")

        // The parent-designated tier: a write into the live-shared bag must be observed immediately by
        // an item model created AFTER the write (this is exactly what buildVisuals does per node).
        series.designatedVisualItemStyle["color"] = "#123456"
        XCTAssertEqual(resolvedColor(), "#123456",
                       "a write into designatedVisualItemStyle must be observed through designatedVisualModel "
                       + "(reference aliasing) — a value-typed bag silently drops it")

        // ... and clearing the key restores the series-level value (buildVisuals clears it after reading).
        series.designatedVisualItemStyle["color"] = nil
        XCTAssertEqual(resolvedColor(), "#abcdef",
                       "removing the key must restore the series-level itemStyle color")
    }
}
