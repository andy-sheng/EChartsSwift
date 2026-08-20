// Upstream themeRiver reveals a new band through an animated left-to-right clip rectangle. The band
// itself stays at final opacity; disabling animation removes the clip entirely.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ThemeRiverTransitionTests: XCTestCase {
    private func firstBand(_ el: Element) -> ThemeRiverBand? {
        if let b = el as? ThemeRiverBand { return b }
        if let g = el as? Group { for c in g.children() { if let h = firstBand(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        ["animation": animation,
         "singleAxis": ["type": "value", "left": "10%", "right": "10%",
                        "top": "10%", "bottom": "10%"] as [String: Any],
         "series": [["type": "themeRiver",
                     "data": [
                        [0.0, 10.0, "Alpha"], [1.0, 15.0, "Alpha"], [2.0, 12.0, "Alpha"],
                        [0.0,  8.0, "Beta"],  [1.0,  6.0, "Beta"],  [2.0, 11.0, "Beta"]
                     ]] as [String: Any]]
        ]
    }
    func test_band_uses_horizontal_clip_reveal_when_animation_on() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(true))
        guard let band = firstBand(ec.getRoot()) else { return XCTFail("no themeRiver band") }
        guard let clip = band.getClipPath() as? ZRenderKit.Rect else {
            return XCTFail("themeRiver band should carry the upstream clip reveal")
        }
        XCTAssertNotNil(clip.animators.first { $0.targetName == "shape" })
        XCTAssertTrue(band.animators.isEmpty, "the band itself must not opacity-fade")
    }
    func test_band_final_opacity_when_animation_off() {
        let ec = ECharts(width: 400, height: 400); ec.setOption(option(false))
        guard let band = firstBand(ec.getRoot()) else { return XCTFail("no themeRiver band") }
        XCTAssertEqual(band.animators.count, 0, "no animator when animation off")
        XCTAssertNil(band.getClipPath(), "no reveal clip when animation is disabled")
        XCTAssertGreaterThan(band.pathStyle.opacity ?? 0, 0.0, "band must be at final (visible) opacity when off — not invisible")
    }
}
