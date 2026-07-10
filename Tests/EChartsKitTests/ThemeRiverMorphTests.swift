// Transition-fidelity tail: ThemeRiverView now persists its per-layer bands and MORPHS each band's
// edges (updateProps shape) on a same-shape (same drawable-layer count + same per-layer time-sample
// count) merge-mode setOption value change instead of rebuild-and-snap. This asserts a band ELEMENT is
// identity-reused and schedules a shape-morph animator, and that a layer/sample-count change rebuilds
// fresh (no stale duplication). Models on LineMorphTests.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ThemeRiverMorphTests: XCTestCase {

    // Collect every ThemeRiverBand (name "item") across the chart views' groups.
    private func bands(_ ec: ECharts) -> [ThemeRiverBand] {
        var out: [ThemeRiverBand] = []
        for v in ec.testChartViews {
            _ = v.group.traverse({ el in
                if let b = el as? ThemeRiverBand, b.name == "item" { out.append(b) }
                return false
            })
        }
        return out
    }

    private func firstBand(_ ec: ECharts) -> ThemeRiverBand? { bands(ec).first }

    // A themeRiver on a time-type singleAxis: 2 layers (Alpha/Beta) over 3 time samples. Rows are
    // [date, value, layerName].
    private func option(_ values: [Double]) -> [String: Any] {
        // values: [A0, A1, A2, B0, B1, B2]
        return ["animation": true,
                "singleAxis": ["type": "time", "left": "10%", "right": "10%",
                               "top": "10%", "bottom": "10%"] as [String: Any],
                "series": [["type": "themeRiver", "animation": true,
                            "data": [
                                ["2020-01-01", values[0], "Alpha"],
                                ["2020-01-02", values[1], "Alpha"],
                                ["2020-01-03", values[2], "Alpha"],
                                ["2020-01-01", values[3], "Beta"],
                                ["2020-01-02", values[4], "Beta"],
                                ["2020-01-03", values[5], "Beta"]
                            ]] as [String: Any]]
        ]
    }

    func testBandMorphsOnValueChange() {
        let ec = ECharts(width: 500, height: 400)
        ec.setOption(option([10, 15, 12, 8, 6, 11]))
        let band = firstBand(ec)
        XCTAssertNotNil(band, "themeRiver render produced a named band")
        XCTAssertEqual(bands(ec).count, 2, "two layers → two bands")
        // Clear the first render's fade-in animators.
        _ = ec.testChartViews.first?.group.traverse({ el in _ = el.stopAnimation(nil); return false })

        // Merge-mode value change: same layers + same time samples, values differ → the band morphs.
        ec.setOption(["series": [["type": "themeRiver",
                                  "data": [
                                    ["2020-01-01", 20, "Alpha"],
                                    ["2020-01-02", 5,  "Alpha"],
                                    ["2020-01-03", 18, "Alpha"],
                                    ["2020-01-01", 14, "Beta"],
                                    ["2020-01-02", 9,  "Beta"],
                                    ["2020-01-03", 3,  "Beta"]
                                  ]] as [String: Any]]])

        // (1) The SAME band instance is reused (not rebuilt).
        XCTAssertTrue(band === firstBand(ec), "band reused across the value change (not rebuilt)")
        // (2) It carries a shape-morph animator.
        XCTAssertGreaterThan(band!.animators.count, 0,
                             "band must schedule a shape-morph animator on a same-shape value change")
    }

    // A layer/sample-count change rebuilds fresh — no stale duplication (the reuse-safety invariant).
    func testLayerCountChangeRebuildsWithoutDuplication() {
        let ec = ECharts(width: 500, height: 400)
        ec.setOption(option([10, 15, 12, 8, 6, 11]))
        XCTAssertEqual(bands(ec).count, 2, "two layers initially")

        // Add a third layer AND change the sample count (4 samples per layer) → full rebuild.
        ec.setOption(["series": [["type": "themeRiver",
                                  "data": [
                                    ["2020-01-01", 10, "Alpha"], ["2020-01-02", 15, "Alpha"],
                                    ["2020-01-03", 12, "Alpha"], ["2020-01-04", 9, "Alpha"],
                                    ["2020-01-01", 8, "Beta"],  ["2020-01-02", 6, "Beta"],
                                    ["2020-01-03", 11, "Beta"], ["2020-01-04", 7, "Beta"],
                                    ["2020-01-01", 5, "Gamma"], ["2020-01-02", 9, "Gamma"],
                                    ["2020-01-03", 7, "Gamma"], ["2020-01-04", 4, "Gamma"]
                                  ]] as [String: Any]]])

        XCTAssertEqual(bands(ec).count, 3,
                       "a layer/sample-count change rebuilds exactly one band per layer, no duplicates")
    }
}
