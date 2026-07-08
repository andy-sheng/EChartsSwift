// Treemap box aspect + squarify orientation parity.
//
// The treemap inner box comes from the merged defaultOption box params
// (left/right = tokens.size.l = 20, top/bottom = tokens.size.xxxl = 50) applied to the
// container via getBoxLayoutParams + getLayoutRect. A regression had these as 16/40, which
// produced a 428x240 box; the correct tokens give 420x220 for a 460x320 container.
//
// The box aspect is load-bearing: with the "treemap-three" data (top nodes 30 / 22 / 14),
// squarify lays node0 (value 30) as a full-height LEFT COLUMN, then must STACK node1 (22) and
// node2 (14) in the remaining right rect (they share an x-range and split by y). With the wrong
// 428x240 box, the remaining rect became landscape (width < height flips), so node1/node2 were
// laid side-by-side as COLUMNS instead — the exact bug this test guards.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class TreemapBoxAspectTests: XCTestCase {

    private func option() -> [String: Any] {
        [
            "series": [[
                "type": "treemap",
                "animation": false,
                "data": [
                    ["name": "P", "value": 30.0, "children": [
                        ["name": "P1", "value": 18.0],
                        ["name": "P2", "value": 12.0]
                    ]],
                    ["name": "Q", "value": 22.0, "children": [
                        ["name": "Q1", "value": 22.0]
                    ]],
                    ["name": "R", "value": 14.0]
                ]
            ] as [String: Any]]
        ]
    }

    private func layoutOf(_ node: TreeNode) -> (x: Double, y: Double, w: Double, h: Double) {
        let d = (node.getLayout() as? [String: Any]) ?? [:]
        return (
            (d["x"] as? Double) ?? .nan,
            (d["y"] as? Double) ?? .nan,
            (d["width"] as? Double) ?? .nan,
            (d["height"] as? Double) ?? .nan
        )
    }

    func test_box_aspect_and_node1_node2_stacked() {
        // Container 460x320 matches the `treemap-three` gallery demo.
        let ec = EChartsSlim(width: 460, height: 320)
        ec.setOption(option())

        guard let series = ec.getModel()?.getSeriesByType("treemap").first as? TreemapSeriesModel else {
            return XCTFail("no treemap series model")
        }

        // Box: 460 - 2*20 = 420 wide, 320 - 2*50 = 220 tall. Must be landscape (width >= height).
        guard let box = series.layoutInfo else { return XCTFail("no layoutInfo box") }
        XCTAssertEqual(box.width, 420, accuracy: 0.5, "treemap inner box width (container - 2*tokens.size.l)")
        XCTAssertEqual(box.height, 220, accuracy: 0.5, "treemap inner box height (container - 2*tokens.size.xxxl)")
        XCTAssertGreaterThanOrEqual(box.width, box.height, "box must be landscape so the second row stacks")

        guard let viewRoot = series.getViewRoot(), viewRoot.children.count == 3 else {
            return XCTFail("expected 3 top-level treemap nodes")
        }
        let p = layoutOf(viewRoot.children[0])   // value 30 -> left column
        let q = layoutOf(viewRoot.children[1])   // value 22
        let r = layoutOf(viewRoot.children[2])   // value 14

        // node0 (P) is the left column; node1/node2 sit to its right.
        XCTAssertGreaterThan(q.x, p.x + p.w - 1, "Q should start to the right of node0's column")

        // Discriminator: Q and R are STACKED, not columned.
        //  stacked  => they SHARE an x-range (same x + same width) and split by Y.
        //  columned => they would SHARE a y-range (same y + same height) and split by X.
        XCTAssertEqual(q.x, r.x, accuracy: 0.5, "stacked: Q and R share the same x")
        XCTAssertEqual(q.w, r.w, accuracy: 0.5, "stacked: Q and R share the same width")
        XCTAssertNotEqual(q.y, r.y, accuracy: 0.5, "stacked: Q and R split along y")
        // Guard against the columned failure mode explicitly.
        XCTAssertFalse(abs(q.y - r.y) < 0.5 && abs(q.h - r.h) < 0.5,
                       "Q and R must NOT be side-by-side columns (shared y-range)")
    }
}
