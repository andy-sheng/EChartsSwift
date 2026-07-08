// Tests for the large-mode fast path (chart/helper/LargeSymbolDraw):
//   - a `large: true` scatter past its largeThreshold renders as ONE LargeSymbolPath for N points
//     (NOT N Symbol groups) whose packed `points` shape carries every datum.
//   - findDataIndex maps a local pixel to the nearest point's data index (rect hit-test, top-down).
//   - contain() caches that index in hoverDataIdx (the tooltip/hover hook upstream reads).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LargeSymbolDrawTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(ScatterSeriesModel.self) }

    private func largePaths(_ ec: EChartsSlim) -> [LargeSymbolPath] {
        var out: [LargeSymbolPath] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? LargeSymbolPath { out.append(p) }
            return false
        }
        return out
    }

    private func symbolGroups(_ ec: EChartsSlim) -> [Symbol] {
        var out: [Symbol] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Symbol { out.append(s) }
            return false
        }
        return out
    }

    // A large scatter draws ONE path for N points — not N Symbol groups.
    func testLargeScatterBuildsOnePathForNPoints() {
        let n = 500
        var data: [[Double]] = []
        for i in 0..<n {
            data.append([Double(i % 100), Double((i * 7) % 100)])
        }
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "large": true, "largeThreshold": 100,
                        "symbolSize": 6.0, "data": data] as [String: Any]]
        ])

        let paths = largePaths(ec)
        XCTAssertEqual(paths.count, 1, "large mode → exactly ONE LargeSymbolPath for the whole series")
        XCTAssertEqual(symbolGroups(ec).count, 0, "large mode must NOT create per-point Symbol groups")

        guard let shape = paths.first?.shape as? LargeSymbolPathShape else {
            return XCTFail("LargeSymbolPath must carry a LargeSymbolPathShape")
        }
        XCTAssertEqual(shape.points.count, n * 2, "packed points array holds (x,y) for every datum")
        // The path must actually emit geometry for the point cloud (not an empty proxy).
        let proxy = paths[0].getUpdatedPathProxy(false)
        XCTAssertGreaterThan(proxy.len(), 0, "buildPath emits the point-cloud geometry into the PathProxy")
    }

    // Below the threshold, a large:true series still uses the normal per-point SymbolDraw.
    func testBelowThresholdStaysNormalSymbolDraw() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "large": true, "largeThreshold": 2000,
                        "symbolSize": 10.0,
                        "data": [[10.0, 10.0], [20.0, 20.0], [30.0, 30.0]]] as [String: Any]]
        ])
        XCTAssertEqual(largePaths(ec).count, 0, "3 points < largeThreshold → not a LargeSymbolPath")
        XCTAssertEqual(symbolGroups(ec).count, 3, "below threshold → normal per-point Symbol groups")
    }

    // findDataIndex maps a local pixel to the nearest point's data index (rect hit-test, top-down).
    func testFindDataIndexMapsPixelToDataIndex() {
        let path = LargeSymbolPath()
        var shape = LargeSymbolPathShape()
        // Three points at distinct pixels; symbol rect is max(size, 4) = 10.
        shape.points = [10, 10, 50, 50, 90, 20]
        shape.size = [10, 10]
        path.setShape(shape)
        // Give it a symbol proxy so buildPath/getBoundingRect are exercisable too.
        if let proxy = symbol.createSymbol("circle", 0, 0, 0, 0) as? Path {
            path.setSymbolProxy(proxy, isEmptyBrush: false, symbolType: "circle")
        }

        // Dead-centre of each point → its index.
        XCTAssertEqual(path.findDataIndex(10, 10), 0)
        XCTAssertEqual(path.findDataIndex(50, 50), 1)
        XCTAssertEqual(path.findDataIndex(90, 20), 2)
        // Near a point but within its rect (±5) → still that index.
        XCTAssertEqual(path.findDataIndex(53, 47), 1, "within the point's rect → that point")
        // Far from every point → -1.
        XCTAssertEqual(path.findDataIndex(200, 200), -1, "outside every point rect → no hit")

        // contain() (identity transform) caches the found index in hoverDataIdx (the tooltip hook).
        XCTAssertTrue(path.contain(50, 50))
        XCTAssertEqual(path.hoverDataIdx, 1)
        XCTAssertFalse(path.contain(200, 200))
        XCTAssertEqual(path.hoverDataIdx, -1, "a miss resets hoverDataIdx to -1")
    }

    // The derived bounding rect ignores stroke and spans the point cloud inflated by the symbol size.
    func testBoundingRectSpansPointCloud() {
        let path = LargeSymbolPath()
        var shape = LargeSymbolPathShape()
        shape.points = [10, 10, 90, 70]
        shape.size = [8, 8]
        path.setShape(shape)
        guard let rect = path.getBoundingRect() else { return XCTFail("no rect") }
        // minX-w/2 .. maxX+w/2 → [6, 94]; width = (90-10) + 8 = 88.
        XCTAssertEqual(rect.x, 6, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 6, accuracy: 1e-9)
        XCTAssertEqual(rect.width, 88, accuracy: 1e-9)
        XCTAssertEqual(rect.height, 68, accuracy: 1e-9)
    }
}
