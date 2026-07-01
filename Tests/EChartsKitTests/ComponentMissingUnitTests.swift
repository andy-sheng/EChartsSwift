// Ported from echarts/test/ut/spec/model/componentMissing.test.ts — keep in sync with upstream
//
// Every case constructs a real chart via `init(el)` + `use([PieChart, TitleComponent, ...])`
// and asserts on `console.error` calls emitted while resolving option components against the
// installed (registered) chart/component set. This needs the full `echarts` façade (init/use,
// the chart-view/component registry populated by `use`, and the setOption -> component-missing
// diagnostics) — all Phase 6. Deferred; each upstream `it` kept as an XCTSkip.

import XCTest
@testable import EChartsKit

final class ComponentMissingUnitTests: XCTestCase {

    private static let reason =
        "Needs echarts init()/use() facade + chart/component registry + setOption component-missing diagnostics — Phase 6."

    private func skip() throws { throw XCTSkip(ComponentMissingUnitTests.reason) }

    func test_shouldReportGridComponentMissing() throws { try skip() }
    func test_shouldReportDataZoomComponentMissing() throws { try skip() }
    func test_shouldNotReportTitleComponentMissing() throws { try skip() }
    func test_shouldReportFunnelSeriesMissing() throws { try skip() }
    func test_shouldNotReportPieSeriesMissing() throws { try skip() }
    func test_shouldNotReportVisualMapMissingWhenUsingTheme() throws { try skip() }
}
