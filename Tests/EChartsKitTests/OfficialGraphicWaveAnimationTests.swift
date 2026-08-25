import XCTest
import ZRenderKit
import EChartsDemoCore
@testable import EChartsKit

final class OfficialGraphicWaveAnimationTests: XCTestCase {
    func testOfficialWaveDemoBuildsTheFullAnimatedCircleField() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-graphic-wave-animation"))
        XCTAssertEqual(demo.category, "graphic")
        XCTAssertTrue(demo.nativeSupported)

        let graphic = try XCTUnwrap(demo.option["graphic"] as? [String: Any])
        let elements = try XCTUnwrap(graphic["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.count, 160)

        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)

        var circles = 0
        var animatedCircles = 0
        _ = view.ec.getRoot().traverse { element in
            guard element is Circle else { return false }
            circles += 1
            if element.animators.contains(where: { $0.scope == "keyframe" }) {
                animatedCircles += 1
            }
            return false
        }

        XCTAssertEqual(circles, 160)
        XCTAssertEqual(animatedCircles, 160)
    }
}
