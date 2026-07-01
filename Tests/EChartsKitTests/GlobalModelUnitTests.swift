// Ported from echarts/test/ut/spec/model/Global.test.ts — keep in sync with upstream
//
// Every case in this spec is driven through `createChart()` + `chart.setOption()` and reads
// results via `getECModel(chart).getComponent(...)` and `series.getData().get('y', 0)`. That
// requires the full ECharts instance (ChartView map, the Scheduler, and the series data
// pipeline / getInitialData) — none of which exist until Phase 6. GlobalModel.mergeOption and
// the component id/name mapping engine (util/model mappingToExists) ARE ported, but they are
// unreachable in isolation here because the assertions all hinge on chart-level plumbing.
//
// Each upstream `it` is preserved as an XCTSkip so the deferral is explicit and accounted for.
// When Phase 6 lands `createChart`, replace each skip with the faithful port.

import XCTest
@testable import EChartsKit

final class GlobalModelUnitTests: XCTestCase {

    private static let reason =
        "Needs createChart + ChartView map + Scheduler + series data pipeline (getData/getInitialData) — Phase 6."

    private func skip() throws { throw XCTSkip(GlobalModelUnitTests.reason) }

    // describe idNoNameNo
    func test_idNoNameNo_sameTypeNotMerge() throws { try skip() }
    func test_idNoNameNo_sameTypeMergeFull() throws { try skip() }
    func test_idNoNameNo_sameTypeMergePartial() throws { try skip() }
    func test_idNoNameNo_differentTypeMerge() throws { try skip() }

    // describe idSpecified
    func test_idSpecified_sameTypeNotMerge() throws { try skip() }
    func test_idSpecified_sameTypeMerge() throws { try skip() }
    func test_idSpecified_differentTypeNotMerge() throws { try skip() }
    func test_idSpecified_differentTypeMergeFull() throws { try skip() }
    func test_idSpecified_differentTypeMergePartial1() throws { try skip() }
    func test_idSpecified_differentTypeMergePartial2() throws { try skip() }
    func test_idSpecified_mergePartialDoNotMapToOtherId() throws { try skip() }
    func test_idSpecified_idDuplicate() throws { try skip() }
    func test_idSpecified_nameTheSameButIdNotTheSame() throws { try skip() }

    // describe noIdButNameExists
    func test_noIdButNameExists_sameTypeNotMerge() throws { try skip() }
    func test_noIdButNameExists_sameTypeMerge() throws { try skip() }
    func test_noIdButNameExists_differentTypeNotMerge() throws { try skip() }
    func test_noIdButNameExists_differentTypeMergePartialOneMapTwo() throws { try skip() }
    func test_noIdButNameExists_differentTypeMergePartialTwoMapOne() throws { try skip() }
    func test_noIdButNameExists_mergePartialCanMapToOtherName() throws { try skip() }

    // describe ohters
    func test_ohters_aBugCase() throws { try skip() }
    func test_ohters_color() throws { try skip() }
    func test_ohters_innerId() throws { try skip() }
}
