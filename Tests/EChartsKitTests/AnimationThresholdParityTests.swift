import XCTest
@testable import EChartsKit

final class AnimationThresholdParityTests: XCTestCase {
    func testIntegerDefaultAnimationThresholdDisablesLargeSeriesAnimation() {
        let ec = ECharts(width: 480, height: 320)
        let points: [[Double]] = (0...2000).map { [Double($0), Double($0 % 10)] }
        ec.setOption([
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "data": points as [Any]] as [String: Any]]
        ])
        guard let series = ec.getModel()?.getSeriesByIndex(0) else {
            return XCTFail("scatter series was not created")
        }
        XCTAssertEqual(series.get("animationThreshold") as? Int, 2000,
                       "the upstream default is intentionally Int-boxed in the option bag")
        XCTAssertEqual(series.isAnimationEnabled(), false,
                       "2001 points must exceed the default threshold exactly as echarts.js does")
    }
}
