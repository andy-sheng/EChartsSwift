// Ported from echarts/test/ut/spec/model/timelineMediaOptions.test.ts — keep in sync with upstream
//
// Every case is driven through `createChart()`, `chart.setOption()`, `chart.resize()` and reads
// results via `getECModel(chart)` + `series.getData().get('y', 0)` + legend/timeline component
// option. OptionManager's media-query + timeline resolution IS ported, but these assertions all
// require the full ECharts instance (resize -> media re-query, the series data pipeline, and the
// legend/timeline component models). Deferred to Phase 6; each upstream `it` kept as an XCTSkip.

import XCTest
@testable import EChartsKit

final class TimelineMediaOptionsUnitTests: XCTestCase {

    private static let reason =
        "Needs createChart + resize (media re-query) + Scheduler + series data pipeline + legend/timeline component models — Phase 6."

    private func skip() throws { throw XCTSkip(TimelineMediaOptionsUnitTests.reason) }

    // describe parse_timeline_media_option
    func test_parse_media_has_baseOption_has_default() throws { try skip() }
    func test_parse_media_no_baseOption_has_default() throws { try skip() }
    func test_parse_media_no_baseOption_no_default() throws { try skip() }
    func test_parse_timeline_media_has_baseOption() throws { try skip() }
    func test_parse_timeline_media_no_baseOption() throws { try skip() }
    func test_parse_timeline_has_baseOption() throws { try skip() }
    func test_parse_timeline_has_baseOption_compat() throws { try skip() }
    func test_parse_timeline_no_baseOption() throws { try skip() }

    // describe timeline_onceMore
    func test_timeline_setOptionOnceMore_baseOption() throws { try skip() }
    func test_timeline_setOptionOnceMore_substitudeTimelineOptions() throws { try skip() }
}
