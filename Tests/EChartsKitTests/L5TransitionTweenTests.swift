import XCTest
@testable import EChartsKit
@testable import ZRenderKit

// L5-5: with view reuse in place (Tasks 1-2), a merge-mode setOption that changes data must make the
// diff-based views (bar/pie/scatter via data.diff + updateProps) schedule UPDATE-tween animators on
// the reused elements — the visible "bars grow / points slide / sectors sweep" morphing. We zero the
// first render's enter-animators, apply the data change, then assert new animators were scheduled on
// the series subtrees.
final class L5TransitionTweenTests: XCTestCase {

    private func chartAnimatorCount(_ ec: EChartsSlim) -> Int {
        var n = 0
        for v in ec.testChartViews { _ = v.group.traverse({ el in n += el.animators.count; return false }) }
        return n
    }

    private func stopAllChartAnimations(_ ec: EChartsSlim) {
        for v in ec.testChartViews { _ = v.group.traverse({ el in _ = el.stopAnimation(nil); return false }) }
    }

    private func assertTweenScheduled(_ name: String, _ option: [String: Any], update: [String: Any],
                                      file: StaticString = #filePath, line: UInt = #line) {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option)
        stopAllChartAnimations(ec)                          // clear the first render's enter animators
        XCTAssertEqual(chartAnimatorCount(ec), 0, "\(name): baseline animators not cleared", file: file, line: line)
        ec.setOption(update)                                // merge-mode data change
        XCTAssertGreaterThan(chartAnimatorCount(ec), 0,
            "\(name): no update-tween animator scheduled on data-change reuse", file: file, line: line)
    }

    func testBarTweens() {
        assertTweenScheduled("bar",
            ["xAxis": ["type": "category", "data": ["a", "b", "c"]], "yAxis": ["type": "value"],
             "series": [["type": "bar", "data": [1, 2, 3]]]],
            update: ["series": [["type": "bar", "data": [8, 5, 9]]]])
    }
    func testScatterTweens() {
        assertTweenScheduled("scatter",
            ["xAxis": ["type": "value"], "yAxis": ["type": "value"],
             "series": [["type": "scatter", "data": [[1, 1], [2, 2], [3, 3]]]]],
            update: ["series": [["type": "scatter", "data": [[1, 5], [2, 8], [3, 2]]]]])
    }
    func testPieTweens() {
        assertTweenScheduled("pie",
            ["series": [["type": "pie", "data": [["value": 1, "name": "a"], ["value": 2, "name": "b"]]]]],
            update: ["series": [["type": "pie", "data": [["value": 5, "name": "a"], ["value": 2, "name": "b"]]]]])
    }
}
