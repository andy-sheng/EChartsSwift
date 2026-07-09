// Graph `layout:"force"` — the iterative physics simulation (forceLayout.swift + forceHelper.swift)
// settles synchronously for the static render. These tests assert the settled node positions are
// finite and spread out (not collapsed at the origin/center), and that the layout is deterministic
// (index-seeded, no Date/random).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GraphForceLayoutTests: XCTestCase {

    private func forceOption() -> [String: Any] {
        [
            "animation": false,
            "series": [[
                "type": "graph", "layout": "force",
                "left": "10%", "right": "10%", "top": "10%", "bottom": "10%",
                "symbolSize": 12.0,
                "force": ["repulsion": 120.0, "edgeLength": 60.0, "gravity": 0.1] as [String: Any],
                "data": [
                    ["name": "n0"], ["name": "n1"], ["name": "n2"], ["name": "n3"],
                    ["name": "n4"], ["name": "n5"], ["name": "n6"], ["name": "n7"]
                ],
                "edges": [
                    ["source": "n0", "target": "n1"], ["source": "n0", "target": "n2"],
                    ["source": "n0", "target": "n3"], ["source": "n1", "target": "n4"],
                    ["source": "n2", "target": "n5"], ["source": "n3", "target": "n6"],
                    ["source": "n4", "target": "n7"], ["source": "n5", "target": "n7"],
                    ["source": "n6", "target": "n7"]
                ]
            ]]
        ]
    }

    private func graphSeries(_ ec: ECharts) -> GraphSeriesModel? {
        var series: GraphSeriesModel?
        ec.getModel()?.eachSeriesByType("graph") { s, _ in series = s as? GraphSeriesModel }
        return series
    }

    private func nodePoints(_ ec: ECharts) -> [[Double]] {
        guard let s = graphSeries(ec) else { return [] }
        let graph = s.getGraph()
        var pts: [[Double]] = []
        graph.eachNode { node, _ in
            if let a = node.getLayout() as? [Double] { pts.append(a) }
            else if let a = node.getLayout() as? [Any] {
                pts.append(a.map { (($0 as? Double) ?? Double(($0 as? Int) ?? 0)) })
            }
        }
        return pts
    }

    // The force layout must produce FINITE, SPREAD node positions — not all NaN, not all collapsed
    // at a single point (the failure mode when the simulation never runs).
    func test_force_layout_produces_finite_spread_positions() {
        let ec = ECharts(width: 460, height: 360)
        ec.setOption(forceOption())

        let pts = nodePoints(ec)
        XCTAssertEqual(pts.count, 8, "should have 8 node layouts")

        // All coordinates finite.
        for p in pts {
            XCTAssertEqual(p.count, 2, "each node layout is [x, y]")
            XCTAssertTrue(p[0].isFinite && p[1].isFinite, "node position must be finite, got \(p)")
        }

        // Spread: the bounding box of the settled nodes must have real extent on both axes
        // (a collapsed/never-run layout would have ~0 spread).
        let xs = pts.map { $0[0] }, ys = pts.map { $0[1] }
        let spreadX = xs.max()! - xs.min()!
        let spreadY = ys.max()! - ys.min()!
        XCTAssertGreaterThan(spreadX, 20.0, "nodes should spread horizontally (got \(spreadX))")
        XCTAssertGreaterThan(spreadY, 20.0, "nodes should spread vertically (got \(spreadY))")

        // Not all at one point: at least some pairwise distance is substantial.
        var maxDist = 0.0
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dx = pts[i][0] - pts[j][0], dy = pts[i][1] - pts[j][1]
                maxDist = Swift.max(maxDist, (dx * dx + dy * dy).squareRoot())
            }
        }
        XCTAssertGreaterThan(maxDist, 40.0, "nodes must not collapse to a single point")
    }

    // Deterministic: two independent runs of the same option produce identical settled positions
    // (index-seeded initial cloud — no Date.now / Math.random).
    func test_force_layout_is_deterministic() {
        let ec1 = ECharts(width: 460, height: 360); ec1.setOption(forceOption())
        let ec2 = ECharts(width: 460, height: 360); ec2.setOption(forceOption())

        let a = nodePoints(ec1), b = nodePoints(ec2)
        XCTAssertEqual(a.count, b.count)
        for i in 0..<a.count {
            XCTAssertEqual(a[i][0], b[i][0], accuracy: 1e-9, "x[\(i)] deterministic")
            XCTAssertEqual(a[i][1], b[i][1], accuracy: 1e-9, "y[\(i)] deterministic")
        }
    }

    // A `fixed` node with explicit x/y stays put through the simulation (force honors n.fixed).
    func test_force_layout_honors_fixed_node() {
        var opt = forceOption()
        var series = (opt["series"] as! [[String: Any]])
        var data = series[0]["data"] as! [[String: Any]]
        // Pin n0 at an explicit location and mark it fixed.
        data[0] = ["name": "n0", "x": 123.0, "y": 77.0, "fixed": true]
        series[0]["data"] = data
        // initLayout 'none' -> simpleLayout seeds n0 at [x, y]; fixed keeps it there.
        opt["series"] = series

        let ec = ECharts(width: 460, height: 360)
        ec.setOption(opt)

        let pts = nodePoints(ec)
        XCTAssertEqual(pts[0][0], 123.0, accuracy: 1e-6, "fixed node keeps its x")
        XCTAssertEqual(pts[0][1], 77.0, accuracy: 1e-6, "fixed node keeps its y")
    }
}
