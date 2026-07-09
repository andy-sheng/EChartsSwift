// Regression: hovering a line/scatter data point must ENLARGE the symbol and RESTORE it on mouse-out.
//
// Bug (fixed): the emphasis scale was applied via `animateTo(target, { duration: 0 })` (the
// stateTransition-off path). A 0-duration Animator scheduled a `life: 0` Clip that only an
// animation-loop tick could resolve, so the emphasis scaleX never applied (symbol did not grow); and
// `Track.prepare` computed `kf.percent = kf.time / maxTime = 0/0 = NaN`, so the following downplay
// interpolated to NaN and left the symbol scale at NaN (invisible) with no restore. Animator.start()
// now settles duration-0 animators to their final value immediately. See Animator.swift start().
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class SymbolHoverScaleTests: XCTestCase {
    func testLineSymbolEmphasisEnlargesAndDownplayRestores() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "line", "data": [10.0, 20.0, 15.0, 25.0],
                 "symbol": "circle", "symbolSize": 10.0] as [String: Any]
            ]
        ])

        let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
        guard let group = data.getItemGraphicEl(1) as? Symbol,
              let path = group.getSymbolPath() else {
            XCTFail("no line Symbol at idx 1"); return
        }

        // symbolSize 10 → resting half-size 5; default hoverScale = max(1.1, 3/5) = 1.1 → 5 * 1.1 = 5.5.
        let rest = path.scaleX ?? .nan
        XCTAssertEqual(rest, 5.0, accuracy: 1e-9, "resting symbol scaleX should be symbolSize/2")

        group.highlight()
        let hovered = path.scaleX ?? .nan
        XCTAssertTrue(hovered.isFinite, "emphasis scaleX must not be NaN")
        XCTAssertGreaterThan(hovered, rest, "hover must ENLARGE the symbol, not shrink it")
        XCTAssertEqual(hovered, 5.5, accuracy: 1e-9, "emphasis scaleX = halfSize * hoverScale (5 * 1.1)")

        group.downplay()
        let restored = path.scaleX ?? .nan
        XCTAssertTrue(restored.isFinite, "downplay scaleX must not be NaN")
        XCTAssertEqual(restored, rest, accuracy: 1e-9, "mouse-out must RESTORE the resting scale")
    }
}
