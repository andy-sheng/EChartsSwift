// A series hidden by the legend must FADE OUT, not vanish.
//
// Upstream reaches "this view has no series any more" from two different places and treats them
// differently: `prepare()` runs prepareView + a hard dispose sweep at setOption time, BEFORE any
// filtering, so only a view whose MODEL disappeared is disposed (echarts.ts:1754-1769); `renderSeries`
// runs AFTER filtering and for a view left non-alive calls ONLY `chart.remove(ecModel, api)`
// (echarts.ts:2445-2449) — the animated teardown, with the view kept so the fade can play.
//
// The port runs both passes together inside render(), i.e. after filtering, and used to apply the full
// disposal to both cases: `v.remove` duly started the fade-out animators and the next lines yanked the
// group out of the scene graph and disposed the view, so a legend click snapped instead of fading.
//
// NOTE this must be driven through EChartsView, not a bare ECharts: `animateOrSetProps` settles a leave
// synchronously when `el.__zr == nil` (a deliberate headless adaptation), so a zr-less harness reports
// no animator no matter what the port does.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ZZFilteredSeriesFadeOutTests: XCTestCase {

    private func makeScatter() -> EChartsView {
        let v = EChartsView(width: 600, height: 400)
        v.setOption([
            "animation": true,
            "legend": ["data": ["S1", "S2"]] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "scatter", "name": "S1", "data": [[1.0, 2.0], [2.0, 3.0], [3.0, 1.0]]] as [String: Any],
                ["type": "scatter", "name": "S2", "data": [[1.5, 4.0], [2.5, 2.0], [3.5, 5.0]]] as [String: Any]
            ]
        ])
        _ = v.zr.storage.getDisplayList(true)
        return v
    }

    private func symbolCensus(_ v: EChartsView) -> (total: Int, animated: Int) {
        var total = 0, animated = 0
        _ = v.ec.getRoot().traverse { el in
            guard el is Symbol else { return false }
            total += 1
            if !el.animators.isEmpty { animated += 1 }
            return false
        }
        return (total, animated)
    }

    func testHidingASeriesFadesItsSymbolsInsteadOfRemovingThem() {
        let v = makeScatter()
        XCTAssertEqual(symbolCensus(v).total, 6, "two 3-point scatter series render six symbols")

        var off = Payload(type: "legendToggleSelect"); off.other["name"] = "S2"
        v.ec.dispatchAction(off)

        let c = symbolCensus(v)
        // The hidden series' symbols must still be in the scene graph, mid-fade — dropping straight to
        // the survivors' count is the bug.
        XCTAssertEqual(c.total, 6, "the hidden series' symbols stay in the scene graph while they fade")
        XCTAssertGreaterThanOrEqual(c.animated, 3, "the three hidden symbols carry leave animators")
    }

    /// The other half of the split: a view whose MODEL is gone must still be disposed outright, so the
    /// fix cannot be "never dispose anything".
    func testRemovingASeriesFromTheOptionStillDisposesItsView() {
        let v = makeScatter()
        v.setOption([
            "animation": true,
            "legend": ["data": ["S1"]] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "scatter", "name": "S1", "data": [[1.0, 2.0], [2.0, 3.0], [3.0, 1.0]]] as [String: Any]
            ]
        ], notMerge: true)
        _ = v.zr.storage.getDisplayList(true)
        XCTAssertEqual(symbolCensus(v).total, 3,
                       "a series deleted from the option leaves no symbols behind")
    }
}
