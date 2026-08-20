// Parallel polylines use the upstream clip reveal when animation is on. The individual lines stay at
// their final opacity; animation is carried by the data group's clip rect rather than a style fade.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ParallelTransitionTests: XCTestCase {
    private func firstClipRect(_ el: Element) -> Rect? {
        if let clip = el.getClipPath() as? Rect { return clip }
        if let group = el as? Group {
            for child in group.children() {
                if let clip = firstClipRect(child) { return clip }
            }
        }
        return nil
    }

    private func firstLine(_ el: Element) -> ZRenderKit.Polyline? {
        if let p = el as? ZRenderKit.Polyline { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstLine(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "parallelAxis": [
                ["dim": 0, "name": "Price"]  as [String: Any],
                ["dim": 1, "name": "Amount"] as [String: Any],
                ["dim": 2, "name": "Volume"] as [String: Any]
            ],
            "parallel": ["left": "10%", "right": "12%", "top": "10%", "bottom": "10%"] as [String: Any],
            "series": [["type": "parallel",
                        "lineStyle": ["width": 2] as [String: Any],
                        "data": [
                            [12.0, 230.0,  8.0],
                            [24.0, 140.0, 15.0]
                        ]] as [String: Any]]
        ]
    }
    func test_parallel_clip_reveals_when_animation_on() {
        let ec = ECharts(width: 520, height: 380); ec.setOption(option(true))
        guard let clip = firstClipRect(ec.getRoot()) else { return XCTFail("no parallel clip rect") }
        guard let animator = clip.animators.first(where: { $0.targetName == "shape" }) else {
            return XCTFail("parallel clip should have a shape animator when animation is on")
        }
        XCTAssertNotNil(animator.getTrack("width") ?? animator.getTrack("height"),
                        "parallel clip should reveal along its layout axis")
    }
    func test_line_final_opacity_when_animation_off() {
        let ec = ECharts(width: 520, height: 380); ec.setOption(option(false))
        guard let line = firstLine(ec.getRoot()) else { return XCTFail("no parallel polyline") }
        XCTAssertEqual(line.animators.count, 0, "no animator when animation off")
        XCTAssertGreaterThan(line.pathStyle.opacity ?? 0, 0.0,
            "line must be at final (visible) opacity when off — not invisible")
    }
}
