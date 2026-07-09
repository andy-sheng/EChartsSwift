import XCTest
@testable import EChartsKit

// L5-4: on a merge-mode setOption, renderComponents/renderSeries now wrap each (reused) view's
// render with clearStates (before — reset stale states) and, for series, re-apply the model's
// select state after render via states.updateSeriesElementSelection (echarts.ts:2499/2515). This
// makes a SELECTED datum survive a data-update re-render, which without the re-apply would snap
// back to unselected because the reused element was cleared by clearStates first.
//
// (An API-dispatched `highlight` intentionally persists across setOption via the element's
// __highByOuter flag — faithful to upstream — so it is not asserted here.)
final class L5StatesOnReuseTests: XCTestCase {
    func testSelectPersistsAcrossMergeReRender() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(["series": [["type": "pie", "selectedMode": true,
                                  "data": [["value": 1, "name": "a"], ["value": 2, "name": "b"]]]]])
        let series = ec.getModel()!.getSeriesByIndex(0)!
        let el0 = series.getData().getItemGraphicEl(0)
        XCTAssertNotNil(el0, "pie render populated the sector element for index 0")

        // Select sector 0.
        var sp = Payload(type: "select")
        sp.other["seriesIndex"] = 0.0
        sp.other["dataIndexInside"] = 0
        ec.dispatchAction(sp)
        XCTAssertTrue(el0!.currentStates.contains("select"), "select entered the select state")

        // Merge-mode setOption with new data: clearStates resets the reused sector, then
        // updateSeriesElementSelection re-applies the still-selected state from the model.
        ec.setOption(["series": [["type": "pie", "selectedMode": true,
                                  "data": [["value": 3, "name": "a"], ["value": 4, "name": "b"]]]]])

        let el0after = ec.getModel()!.getSeriesByIndex(0)!.getData().getItemGraphicEl(0)
        XCTAssertNotNil(el0after)
        XCTAssertTrue(el0after!.currentStates.contains("select"),
                      "selected sector must remain selected across a merge-mode setOption re-render")
    }
}
