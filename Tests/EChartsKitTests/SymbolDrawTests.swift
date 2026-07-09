// L2 tests for the shared SymbolDraw / Symbol helper (chart/helper) driving scatter symbols:
//   - each datum → a Symbol (Group) carrying a single symbol Path child (name "item").
//   - the series `symbolSize` reaches the symbol via the symbolVisual stage (path scaleX == size/2).
//   - a series `symbolRotate` reaches the symbol path's rotation.
//   - the Symbol group is the highDown dispatcher (emphasis wiring lives on the group, not the path).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class SymbolDrawTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(ScatterSeriesModel.self) }

    private func symbolGroups(_ ec: ECharts) -> [Symbol] {
        var out: [Symbol] = []
        _ = ec.getRoot().traverse { el in
            if let s = el as? Symbol { out.append(s) }
            return false
        }
        return out
    }

    func testEachDatumBecomesASymbolGroupWithAPathChild() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 16.0,
                        "data": [[10.0, 10.0], [20.0, 20.0], [30.0, 30.0]]] as [String: Any]]
        ])

        let syms = symbolGroups(ec)
        XCTAssertEqual(syms.count, 3, "3 data → 3 Symbol groups")
        for s in syms {
            guard let path = s.getSymbolPath() else { XCTFail("Symbol must carry a symbol Path child"); continue }
            XCTAssertEqual(path.name, "item")
            // symbolSize 16 flows through the symbolVisual stage → the path rests at scaleX = size/2 = 8.
            XCTAssertEqual(path.scaleX, 8.0, accuracy: 1e-9, "series symbolSize 16 → path scaleX 8 (size/2)")
            XCTAssertEqual(path.scaleY, 8.0, accuracy: 1e-9)
            // The Symbol group is the highDown dispatcher (emphasis wiring on the group).
            XCTAssertTrue(states.isHighDownDispatcher(s), "the Symbol group is the highDown dispatcher")
        }
    }

    func testSeriesSymbolRotateReachesThePath() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 12.0, "symbolRotate": 45.0,
                        "data": [[10.0, 10.0]]] as [String: Any]]
        ])

        guard let path = symbolGroups(ec).first?.getSymbolPath() else {
            return XCTFail("no symbol path")
        }
        // upstream Symbol._updateCommon: symbolPath.rotation = symbolRotate * PI / 180.
        XCTAssertEqual(path.rotation, 45.0 * Double.pi / 180, accuracy: 1e-9,
                       "series symbolRotate 45 → path rotation 45° in radians")
    }

    func testPerItemSymbolSizeOverridesSeries() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            // One datum pins its own symbolSize via the object form → dataSymbolTask per-item visual.
            "series": [["type": "scatter", "symbolSize": 10.0,
                        "data": [["value": [10.0, 10.0], "symbolSize": 30.0] as [String: Any],
                                 [20.0, 20.0]]] as [String: Any]]
        ])

        let syms = symbolGroups(ec)
        XCTAssertEqual(syms.count, 2)
        let scales = syms.compactMap { $0.getSymbolPath()?.scaleX }.sorted()
        // series default 10 → scaleX 5; per-item 30 → scaleX 15.
        XCTAssertEqual(scales, [5.0, 15.0], "per-item symbolSize overrides the series default")
    }
}
