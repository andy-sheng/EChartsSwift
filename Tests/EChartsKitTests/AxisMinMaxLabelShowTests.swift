// End-to-end wiring test for the axis min/max tick-label special-casing (AxisBuilder.fixMinMaxLabelShow,
// wired into layOutAxisTickLabel). Upstream runs it UNCONDITIONALLY after the tick labels are built and,
// respecting `axisLabel.showMinLabel` / `showMaxLabel`, force-hides or force-keeps the first / last tick
// labels (resolving overlap with their inner neighbour). See echarts/src/component/axis/AxisBuilder.ts.

import XCTest
import ZRenderKit
@testable import EChartsKit

final class AxisMinMaxLabelShowTests: XCTestCase {

    // Other suites register empty-data `series.bar` doubles into the GLOBAL registry; re-register the
    // real model so this suite (which needs the real category-axis data pipeline) is order-independent.
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    private func option(_ cats: [String], axisLabel: [String: Any]?) -> [String: Any] {
        var xAxis: [String: Any] = ["type": "category", "data": cats]
        if let al = axisLabel { xAxis["axisLabel"] = al }
        return [
            "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": xAxis,
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": cats.map { _ in 10.0 }] as [String: Any]]
        ]
    }

    // Axis tick labels are `ZRText` with `anid` prefixed `label_` (see buildAxisLabel). Both the x and
    // y axis emit them, so restrict to the category texts under test (`among`).
    private func labelText(_ root: Group, ignored: Bool, among: Set<String>) -> Set<String> {
        var out: Set<String> = []
        _ = root.traverse { el in
            if let t = el as? ZRText, let anid = t.anid, anid.hasPrefix("label_"),
               let text = t.textStyle.text, among.contains(text), t.ignore == ignored {
                out.insert(text)
            }
            return false
        }
        return out
    }

    // showMinLabel:false → the first (min) tick label is force-hidden; showMaxLabel:false → last hidden.
    func testShowMinMaxLabelFalseHidesEnds() {
        let cats = ["A", "B", "C", "D", "E"]
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(cats, axisLabel: ["showMinLabel": false, "showMaxLabel": false]))

        let visible = labelText(ec.getRoot(), ignored: false, among: Set(cats))
        let hidden = labelText(ec.getRoot(), ignored: true, among: Set(cats))
        XCTAssertTrue(hidden.contains("A"), "showMinLabel:false must hide the first tick label")
        XCTAssertTrue(hidden.contains("E"), "showMaxLabel:false must hide the last tick label")
        XCTAssertEqual(visible, ["B", "C", "D"], "the interior labels stay shown")
    }

    // showMinLabel:false alone hides only the first; the last stays shown.
    func testShowMinLabelFalseKeepsMax() {
        let cats = ["A", "B", "C", "D", "E"]
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(cats, axisLabel: ["showMinLabel": false]))

        let visible = labelText(ec.getRoot(), ignored: false, among: Set(cats))
        let hidden = labelText(ec.getRoot(), ignored: true, among: Set(cats))
        XCTAssertEqual(hidden, ["A"], "only the min label is hidden")
        XCTAssertTrue(visible.contains("E"), "the max label stays shown when only showMinLabel is false")
    }

    // Default (no showMinLabel/showMaxLabel): a sparse axis keeps every label, min & max included.
    func testDefaultKeepsMinMaxOnSparseAxis() {
        let cats = ["A", "B", "C", "D", "E"]
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(cats, axisLabel: nil))

        let hidden = labelText(ec.getRoot(), ignored: true, among: Set(cats))
        let visible = labelText(ec.getRoot(), ignored: false, among: Set(cats))
        XCTAssertTrue(hidden.isEmpty, "a sparse axis hides nothing by default")
        XCTAssertEqual(visible, Set(cats), "every label (min & max included) stays shown by default")
    }

    // Default behaviour keeps the min & max labels shown even when the auto interval would otherwise
    // drop them: with `interval:0` every category emits a label, and fixMinMaxLabelShow force-keeps the
    // extremes (they are only ever hidden when they actually overlap the inner neighbour). Here A..H are
    // short and well-spaced (8 labels / 300px ≈ 37px band), so the extremes do not overlap → kept.
    func testDefaultKeepsMinMaxWithIntervalZero() {
        let cats = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option(cats, axisLabel: ["interval": 0]))

        let visible = labelText(ec.getRoot(), ignored: false, among: Set(cats))
        XCTAssertTrue(visible.contains("A"), "min label kept by default even with interval:0")
        XCTAssertTrue(visible.contains("H"), "max label kept by default even with interval:0")
    }
}
