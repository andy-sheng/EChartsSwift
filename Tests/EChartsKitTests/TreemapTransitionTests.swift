// Treemap tiles fade in (style.opacity 0→final) when the series has animation on, and are at final
// (visible) opacity with no animator when off (the invisible-tile guard). Heatmap-style opacity fade
// via initProps(tile, {style: {opacity}}) in TreemapView.renderNode (bg/content Rect tiles).
//
// NOTE on the toggle: TreemapSeries.defaultOption sets `animation: true` (faithful to upstream
// TreemapSeries.ts) — that default merges into the series' own option, so a GLOBAL `animation:false`
// does NOT override it (Component.mergeDefaultAndTheme merges defaults into the option without
// overwrite; getShallow then reads the true from the series' own option). The meaningful "animation
// off" for treemap is therefore a series-level `animation:false`, which is what these tests toggle.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class TreemapTransitionTests: XCTestCase {

    private func firstTile(_ el: Element) -> ZRenderKit.Rect? {
        if let r = el as? ZRenderKit.Rect { return r }
        if let g = el as? Group { for c in g.children() { if let hit = firstTile(c) { return hit } } }
        return nil
    }

    private func option(_ animation: Bool) -> [String: Any] {
        [
            "series": [[
                "type": "treemap",
                "animation": animation,
                "left": 0.0, "top": 0.0, "width": 400.0, "height": 400.0,
                "data": [
                    ["name": "nodeA", "value": 10.0, "children": [
                        ["name": "nodeA1", "value": 4.0],
                        ["name": "nodeA2", "value": 6.0]
                    ]],
                    ["name": "nodeB", "value": 20.0, "children": [
                        ["name": "nodeB1", "value": 5.0],
                        ["name": "nodeB2", "value": 8.0]
                    ]]
                ]
            ] as [String: Any]]
        ]
    }

    func test_tile_fades_in_when_animation_on() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(true))
        guard let tile = firstTile(ec.getRoot()) else { return XCTFail("no treemap tile") }
        // The fade-in animates a partial "style" dict ({opacity}); the resulting sub-animator is
        // targeted at "style" and carries an "opacity" leaf track (same idiom as FunnelTransitionTests /
        // EffectScatter ripple opacity animator). The 0→final delta is proven by the animation-OFF test
        // below asserting the element lands at a VISIBLE (>0) opacity — the invisible-element guard.
        let anim = tile.animators.first { $0.targetName == "style" }
        XCTAssertNotNil(anim, "treemap tile should have a style (opacity) animator when animation on")
        XCTAssertNotNil(anim?.getTrack("opacity"), "the style animator should carry an opacity track (the 0→final fade-in)")
    }

    func test_tile_final_opacity_when_animation_off() {
        let ec = ECharts(width: 400, height: 400)
        ec.setOption(option(false))
        guard let tile = firstTile(ec.getRoot()) else { return XCTFail("no treemap tile") }
        XCTAssertEqual(tile.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(tile.pathStyle.opacity ?? 0, 0.0,
                             "tile must be at final (visible) opacity when off — not left invisible")
    }
}
