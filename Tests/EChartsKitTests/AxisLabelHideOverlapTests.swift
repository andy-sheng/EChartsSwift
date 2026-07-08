// End-to-end wiring test for the axis category-label overlap pass (AxisBuilder.layOutAxisTickLabel →
// labelLayoutHelper.hideOverlap). A dense category axis (20 long labels squeezed into a 300px axis)
// overprints without overlap resolution; with `axisLabel.hideOverlap: true` the overlapping labels are
// set `ignore = true` so the visible subset no longer overlaps. `axisLabel.interval: 0` forces every
// category to emit a label element (no "auto" thinning); with hideOverlap off, all remain shown.

import XCTest
import ZRenderKit
@testable import EChartsKit

final class AxisLabelHideOverlapTests: XCTestCase {

    // Other suites register empty-data `series.bar` doubles into the GLOBAL registry; re-register the
    // real model so this suite (which needs the real category-axis data pipeline) is order-independent.
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    // 20 long category labels over a 300px-wide axis. `interval: 0` disables the "auto" thinning so a
    // label element is emitted for EVERY category (the overlap must then be resolved by hideOverlap).
    private func denseCategoryOption(hideOverlap: Bool?) -> [String: Any] {
        let cats = (0..<20).map { "Category-Label-\($0)" }
        var axisLabel: [String: Any] = ["interval": 0]
        if let h = hideOverlap { axisLabel["hideOverlap"] = h }
        return [
            "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats, "axisLabel": axisLabel] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": cats.map { _ in 10.0 }] as [String: Any]]
        ]
    }

    // Axis tick labels are `ZRText` with `anid` prefixed `label_` (see buildAxisLabel). Both the x and
    // y axis emit them, so filter by the label text to isolate the axis under test.
    private func collectAxisLabels(_ root: Group, textMatch: (String) -> Bool) -> [ZRText] {
        var out: [ZRText] = []
        _ = root.traverse { el in
            if let t = el as? ZRText, let anid = t.anid, anid.hasPrefix("label_"),
               let text = t.textStyle.text, textMatch(text) {
                out.append(t)
            }
            return false
        }
        return out
    }

    func testDenseAxisHidesOverlappingLabels() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(denseCategoryOption(hideOverlap: true))

        let labels = collectAxisLabels(ec.getRoot()) { $0.hasPrefix("Category-Label") }
        XCTAssertEqual(labels.count, 20, "interval:0 emits a label element for every category")

        let visible = labels.filter { !$0.ignore }
        let hidden = labels.filter { $0.ignore }
        XCTAssertGreaterThan(hidden.count, 0, "dense overlapping labels: hideOverlap must hide some")
        XCTAssertGreaterThan(visible.count, 0, "a non-empty subset of labels stays visible")

        // The surviving (visible) labels must be pairwise non-overlapping — recompute each label's
        // global geometry from its live post-render transform and cross-check with `labelIntersect`
        // using the same touch threshold hideOverlap applied.
        let geoms = visible.map { LabelLayoutData(label: $0) }
        for g in geoms { _ = labelLayoutHelper.ensureLabelLayoutWithGeometry(g) }
        for i in 0..<geoms.count {
            for j in (i + 1)..<geoms.count {
                XCTAssertFalse(
                    labelLayoutHelper.labelIntersect(
                        geoms[i], geoms[j], nil, BoundingRectIntersectOpt(touchThreshold: 0.05)
                    ),
                    "visible axis labels must not overlap after hideOverlap (\(i) vs \(j))"
                )
            }
        }
    }

    func testIntervalZeroShowsAllWhenHideOverlapOff() {
        let ec = EChartsSlim(width: 400, height: 300)
        // Default: no hideOverlap. interval:0 → all labels generated AND shown (overprint allowed).
        ec.setOption(denseCategoryOption(hideOverlap: nil))

        let labels = collectAxisLabels(ec.getRoot()) { $0.hasPrefix("Category-Label") }
        XCTAssertEqual(labels.count, 20, "interval:0 emits a label element for every category")
        let hidden = labels.filter { $0.ignore }
        XCTAssertEqual(hidden.count, 0,
                       "interval:0 with hideOverlap off shows every label (no overlap pass runs)")
    }

    // A SPARSE axis (few short labels, plenty of room) is unchanged even with hideOverlap on: nothing
    // overlaps, so nothing is hidden.
    func testSparseAxisKeepsAllLabels() {
        let option: [String: Any] = [
            "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": ["A", "B", "C", "D"],
                "axisLabel": ["interval": 0, "hideOverlap": true] as [String: Any]
            ] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ]
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option)

        let cats = Set(["A", "B", "C", "D"])
        let labels = collectAxisLabels(ec.getRoot()) { cats.contains($0) }
        XCTAssertEqual(labels.count, 4)
        XCTAssertEqual(labels.filter { $0.ignore }.count, 0,
                       "a sparse axis has no overlap, so hideOverlap hides nothing")
    }
}
