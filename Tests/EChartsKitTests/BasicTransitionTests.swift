// Faithful port checks for animation/basicTransition.ts: getAnimationConfig reads the series'
// animation option (enabled/disabled, enter vs update durations, Int coercion), and initProps
// animates a shape when enabled but sets it instantly when disabled (the no-op branch).
#if canImport(QuartzCore) && canImport(CoreGraphics)
import XCTest
import CoreGraphics
@testable import EChartsKit
@testable import ZRenderKit
import NativePainter

final class BasicTransitionTests: XCTestCase {

    // A minimal SeriesModel carrying just the animation options through a real GlobalModel.
    private func seriesModel(_ extra: [String: Any] = [:]) -> SeriesModel {
        var opt: [String: Any] = ["type": "bar", "data": [1.0]]
        for (k, v) in extra { opt[k] = v }
        // A bar series needs a cartesian coordinate system to resolve against (setOption crashes
        // with "xAxis \"0\" not found" otherwise) — mirrors the xAxis/yAxis pair every other
        // ECharts-backed test in this target supplies (see BarChartRenderTests.barChartOption).
        let full: [String: Any] = [
            "xAxis": ["type": "category", "data": ["A"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [opt]
        ]
        let ec = ECharts(width: 200, height: 200)
        ec.setOption(full)
        return ec.getModel()!.getSeriesByType("bar").first!
    }

    func test_getAnimationConfig_disabled_returns_nil() {
        let m = seriesModel(["animation": false])
        XCTAssertNil(getAnimationConfig(.enter, m, 0, nil))
    }

    func test_getAnimationConfig_enter_and_update_durations() {
        let m = seriesModel([:])   // default animation on
        let enter = getAnimationConfig(.enter, m, 0, nil)
        let update = getAnimationConfig(.update, m, 0, nil)
        XCTAssertEqual(enter?.duration, 1000, "enter uses animationDuration default 1000")
        XCTAssertEqual(update?.duration, 500, "update uses animationDurationUpdate default 500")
    }

    func test_getAnimationConfig_coerces_int_duration() {
        let m = seriesModel(["animationDuration": 800])   // Int literal
        XCTAssertEqual(getAnimationConfig(.enter, m, 0, nil)?.duration, 800,
                       "Int-literal animationDuration must coerce, not drop to default")
    }

    func test_initProps_animates_shape_when_enabled() {
        let m = seriesModel([:])
        let rect = Rect()
        // Start with a REAL delta from the target (height 0 → 100) — a zero-delta initProps would
        // only create an animator via the `force` flag, which upstream reserves for cb/during, not
        // for guaranteeing a full-duration animator on unchanged values.
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 0
        rect.shape = s
        // initProps toward the final shape; enabled → an animator is created (genuinely, from the delta).
        initProps(rect, ["shape": ["height": 100.0] as [String: Any]], m, 0, nil, nil)
        XCTAssertEqual(rect.animators.count, 1, "enabled animation should create one shape animator")
    }

    func test_initProps_sets_instantly_when_disabled() {
        let m = seriesModel(["animation": false])
        let rect = Rect()
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 0
        rect.shape = s
        initProps(rect, ["shape": ["height": 100.0] as [String: Any]], m, 0, nil, nil)
        XCTAssertEqual(rect.animators.count, 0, "disabled animation should not create an animator")
        XCTAssertEqual((rect.shape as? RectShape)?.height ?? -1, 100.0, accuracy: 1e-9,
                       "disabled animation should set the final shape immediately (attr branch)")
    }

    /// upstream: `animateOrSetProps` passes a truthy `removeOpt || {}` into `getAnimationConfig` for
    /// the leave path, forcing its extraOpts branch (hardcoded 200ms / cubicOut), independent of the
    /// series' `animationDuration` (default 1000ms here). Prove the leave-fade clip is short: stepped
    /// to t=100 (50% of 200ms) it should be well underway, and by t=200 (100% of 200ms) it should be
    /// essentially done (opacity ~0) — which would NOT be true yet at t=200 of a 1000ms fade (only 20%
    /// through, opacity would still be ~0.5+ under cubicOut).
    func test_leave_fade_uses_short_duration() throws {
        let m = seriesModel([:])   // default animation on, animationDuration 1000ms

        let painter = CALayerPainter(size: CGSize(width: 200, height: 200))
        let proxy = NativeHandlerProxy()
        let zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        defer { zr.dispose() }

        let group = Group()
        let rect = Rect()
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 10
        rect.shape = s
        var style = PathStyleProps(); style.opacity = 1.0
        rect.pathStyle = style
        _ = group.add(rect)
        zr.add(group)   // rect.__zr becomes non-nil (isElementRemoved would otherwise short-circuit)

        removeElementWithFadeOut(rect, m, 0)

        guard let leaveAnimator = rect.animators.first(where: { $0.scope == "leave" }) else {
            return XCTFail("expected a leave-scoped animator on the fading rect")
        }
        guard let clip = leaveAnimator.getClip() else {
            return XCTFail("expected the leave animator to have started a clip")
        }
        _ = clip.step(0, 0)
        let finishedAt200 = clip.step(200, 200)
        XCTAssertTrue(finishedAt200, "a 200ms leave-fade should be complete by t=200, not 5x slower")
        XCTAssertEqual(rect.pathStyle.opacity ?? -1, 0.0, accuracy: 1e-3,
                       "opacity should have fully tweened to 0 by t=200 under the upstream 200ms leave duration")
    }
}
#endif
