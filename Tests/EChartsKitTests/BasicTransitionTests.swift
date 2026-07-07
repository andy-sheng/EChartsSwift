// Faithful port checks for animation/basicTransition.ts: getAnimationConfig reads the series'
// animation option (enabled/disabled, enter vs update durations, Int coercion), and initProps
// animates a shape when enabled but sets it instantly when disabled (the no-op branch).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class BasicTransitionTests: XCTestCase {

    // A minimal SeriesModel carrying just the animation options through a real GlobalModel.
    private func seriesModel(_ extra: [String: Any] = [:]) -> SeriesModel {
        var opt: [String: Any] = ["type": "bar", "data": [1.0]]
        for (k, v) in extra { opt[k] = v }
        // A bar series needs a cartesian coordinate system to resolve against (setOption crashes
        // with "xAxis \"0\" not found" otherwise) — mirrors the xAxis/yAxis pair every other
        // EChartsSlim-backed test in this target supplies (see BarChartRenderTests.barChartOption).
        let full: [String: Any] = [
            "xAxis": ["type": "category", "data": ["A"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [opt]
        ]
        let ec = EChartsSlim(width: 200, height: 200)
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
        var s = RectShape(); s.x = 0; s.y = 0; s.width = 10; s.height = 100
        rect.shape = s
        // initProps toward the final shape; enabled → an animator is created.
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
}
