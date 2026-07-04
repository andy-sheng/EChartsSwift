// END-TO-END RENDER TEST for the Phase-15 sankey (flow) chart vertical: a Rect per node + a filled
// ribbon SankeyPath per edge, laid out by the coordless sankey box-layout stage (columns by depth).
// Drives EChartsSlim with a real sankey option and asserts BOTH node Rects and edge ribbon Paths reach
// the ZRenderKit scene graph, plus a GEOMETRY guard: node x-positions must increase with depth (the
// source column sits left of the target column), which is exactly what sankeyLayout must compute.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SankeyRenderTests: XCTestCase {
    func testSankeyRendersNodesEdgesAndColumnOrder() {
        let ec = EChartsSlim(width: 460, height: 360)
        ec.setOption([
            "series": [["type": "sankey",
                        "left": "5%", "right": "20%", "top": "5%", "bottom": "5%",
                        "nodeWidth": 20.0, "nodeGap": 8.0,
                        "data": [["name": "a"], ["name": "b"], ["name": "c"], ["name": "d"]],
                        "links": [["source": "a", "target": "b", "value": 5.0],
                                  ["source": "a", "target": "c", "value": 3.0],
                                  ["source": "b", "target": "d", "value": 4.0],
                                  ["source": "c", "target": "d", "value": 2.0]]] as [String: Any]]
        ])

        var nodeRects = 0
        var ribbons = 0
        // Map each node's label text → its local rect x (columns increase with depth).
        var nodeXByName: [String: Double] = [:]
        _ = ec.getRoot().traverse { el in
            if let path = el as? SankeyPath, path.shape is SankeyPathShape {
                ribbons += 1
            }
            else if el.name == "node", let rect = el as? ZRenderKit.Rect, let shape = rect.shape as? RectShape {
                nodeRects += 1
                if let name = rect.getTextContent()?.textStyle?.text {
                    nodeXByName[name] = shape.x
                }
            }
            return false
        }

        XCTAssertGreaterThan(nodeRects, 0, "sankey nodes → Rects")
        XCTAssertGreaterThan(ribbons, 0, "sankey edges → ribbon SankeyPaths")

        // GEOMETRY GUARD: 'a' is a source (depth 0), 'd' is the sink (deepest column). The layout must
        // place the source column strictly left of the target column.
        guard let xa = nodeXByName["a"], let xd = nodeXByName["d"] else {
            return XCTFail("expected node rects labeled 'a' and 'd' (got \(nodeXByName.keys.sorted()))")
        }
        XCTAssertLessThan(xa, xd, "source column ('a') must be left of the sink column ('d')")
    }
}
