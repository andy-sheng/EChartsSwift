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

// Coverage for Symbol.fadeOut's ANIMATED leave path (upstream Symbol.ts fadeOut): removeElement with
// scaleX/scaleY -> 0 + style.opacity -> 0 on the "leave" scope, whose callback (which detaches the
// Symbol from its group) must fire only when the animation completes. It needs a real zr — without one
// `animateOrSetProps` deliberately settles the leave synchronously (see basicTransition's zr-less note),
// which is the branch every other headless test takes.
#if canImport(QuartzCore) && canImport(CoreGraphics)
import CoreGraphics
import NativePainter
@testable import ZRenderKit

final class SymbolFadeOutLeaveTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(ScatterSeriesModel.self) }

    private func firstSymbol(_ ec: ECharts) -> Symbol? {
        var out: Symbol?
        _ = ec.getRoot().traverse { el in
            if out == nil, let s = el as? Symbol { out = s }
            return false
        }
        return out
    }

    func test_fadeOut_leave_is_animated_and_removes_only_on_completion() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": true,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 16.0,
                        "data": [[10.0, 10.0], [20.0, 20.0]]] as [String: Any]]
        ])

        let painter = CALayerPainter(size: CGSize(width: 400, height: 300))
        let proxy = NativeHandlerProxy()
        let zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        defer { zr.dispose() }
        zr.add(ec.getRoot())   // every element gets a non-nil __zr → the leave really animates

        guard let sym = firstSymbol(ec), let path = sym.getSymbolPath() else {
            return XCTFail("no symbol")
        }
        let parent = sym.parent as? Group
        let seriesModel = ec.getModel()?.getSeriesByIndex(0)
        XCTAssertNotNil(seriesModel)

        var removed = false
        sym.fadeOut({ removed = true; _ = parent?.remove(sym) }, seriesModel)

        guard let leave = path.animators.first(where: { $0.scope == "leave" }) else {
            return XCTFail("fadeOut should install a leave-scoped animator on the symbol path")
        }
        XCTAssertFalse(removed, "the removal callback must wait for the leave animation")
        XCTAssertTrue(sym.silent && path.silent, "fading symbols stop taking hover")

        guard let clip = leave.getClip() else { return XCTFail("leave animator has no clip") }
        _ = clip.step(0, 0)
        XCTAssertTrue(clip.step(200, 200), "the leave uses the 200ms remove duration")
        XCTAssertEqual(path.scaleX, 0.0, accuracy: 1e-6, "leave tweens scaleX -> 0")
        XCTAssertEqual(path.scaleY, 0.0, accuracy: 1e-6, "leave tweens scaleY -> 0")
        XCTAssertEqual(path.pathStyle.opacity ?? -1, 0.0, accuracy: 1e-6, "leave tweens style.opacity -> 0")
    }

    /// Without a zr (the headless oracle and every other test) the leave is settled synchronously by
    /// `animateOrSetProps`, so the callback fires at once and the symbol leaves the scene immediately —
    /// otherwise removed symbols would linger forever.
    func test_fadeOut_without_zr_settles_synchronously() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": true,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 16.0,
                        "data": [[10.0, 10.0]]] as [String: Any]]
        ])
        guard let sym = firstSymbol(ec), let path = sym.getSymbolPath() else {
            return XCTFail("no symbol")
        }
        let parent = sym.parent as? Group
        var removed = false
        sym.fadeOut({ removed = true; _ = parent?.remove(sym) }, ec.getModel()?.getSeriesByIndex(0))
        XCTAssertTrue(removed, "zr-less leave must still fire the removal callback")
        XCTAssertEqual(path.scaleX, 0.0, accuracy: 1e-9)
        XCTAssertEqual(path.scaleY, 0.0, accuracy: 1e-9)
    }
}
#endif
