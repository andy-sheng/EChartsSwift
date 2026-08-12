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
        let ec = ECharts(width: 400, height: 300)
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

    func testIntervalZeroShowsAllInteriorWhenHideOverlapOff() {
        let ec = ECharts(width: 400, height: 300)
        // Default: no hideOverlap. interval:0 → a label element for every category; the global
        //   `hideOverlap` pass does NOT run, so the interior (non-extreme) labels all overprint and
        //   stay shown. `fixMinMaxLabelShow` still runs unconditionally and may hide ONLY the extreme
        //   (min/max) labels when they overlap their inner neighbour (see AxisMinMaxLabelShowTests).
        ec.setOption(denseCategoryOption(hideOverlap: nil))

        let labels = collectAxisLabels(ec.getRoot()) { $0.hasPrefix("Category-Label") }
        XCTAssertEqual(labels.count, 20, "interval:0 emits a label element for every category")

        // Only the two extreme-value labels ("Category-Label-0" / "Category-Label-19") may be hidden by
        //   fixMinMaxLabelShow; every interior label must remain visible (no global overlap pass runs).
        let hiddenTexts = Set(labels.filter { $0.ignore }.compactMap { $0.textStyle.text })
        for t in hiddenTexts {
            XCTAssertTrue(t == "Category-Label-0" || t == "Category-Label-19",
                          "only the min/max label may be hidden with hideOverlap off, not interior \(t)")
        }
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
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(option)

        let cats = Set(["A", "B", "C", "D"])
        let labels = collectAxisLabels(ec.getRoot()) { cats.contains($0) }
        XCTAssertEqual(labels.count, 4)
        XCTAssertEqual(labels.filter { $0.ignore }.count, 0,
                       "a sparse axis has no overlap, so hideOverlap hides nothing")
    }

    func testDefaultIntegerMarginMatchesExplicitDoubleMargin() {
        func option(margin: Double?) -> [String: Any] {
            var axisLabel: [String: Any] = ["interval": 0]
            if let margin { axisLabel["margin"] = margin }
            return [
                "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                "xAxis": [
                    "type": "category",
                    "data": ["A", "B", "C", "D"],
                    "axisLabel": axisLabel
                ] as [String: Any],
                "yAxis": ["type": "value"] as [String: Any],
                "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
            ]
        }

        func categoryLabelYs(margin: Double?) -> [Double] {
            let ec = ECharts(width: 400, height: 300)
            ec.setOption(option(margin: margin))
            let categories = Set(["A", "B", "C", "D"])
            return collectAxisLabels(ec.getRoot()) { categories.contains($0) }
                .sorted { ($0.textStyle.text ?? "") < ($1.textStyle.text ?? "") }
                .map(\.y)
        }

        let defaultMarginYs = categoryLabelYs(margin: nil) // axisDefault stores `margin` as Int(8).
        let explicitEightYs = categoryLabelYs(margin: 8.0)
        let explicitZeroYs = categoryLabelYs(margin: 0.0)

        XCTAssertEqual(defaultMarginYs.count, 4)
        XCTAssertEqual(defaultMarginYs, explicitEightYs,
                       "the default Int(8) margin must lay out identically to explicit Double(8)")
        for (defaultY, zeroY) in zip(defaultMarginYs, explicitZeroYs) {
            XCTAssertEqual(defaultY - zeroY, 8.0, accuracy: 1e-9,
                           "bottom-axis labels must sit eight points outside the axis by default")
        }
    }

    func testContainLabelUsesDefaultIntegerMargin() {
        func gridRect(margin: Double?) -> BoundingRect {
            var axisLabel: [String: Any] = [:]
            if let margin { axisLabel["margin"] = margin }
            let ec = ECharts(width: 400, height: 300)
            ec.setOption([
                "grid": [
                    "left": 20.0, "top": 20.0, "right": 20.0, "bottom": 20.0,
                    "containLabel": true
                ] as [String: Any],
                "xAxis": ["type": "category", "data": ["A", "B", "C"], "axisLabel": axisLabel] as [String: Any],
                "yAxis": ["type": "value", "axisLabel": axisLabel] as [String: Any],
                "series": [["type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]]
            ])
            return ((ec.getModel()?.getComponent("grid", 0) as? GridModel)?.coordinateSystem as! Grid).getRect()
        }

        let defaultRect = gridRect(margin: nil) // axisDefault stores `margin` as Int(8).
        let explicitRect = gridRect(margin: 8.0)
        XCTAssertEqual(defaultRect.x, explicitRect.x, accuracy: 1e-9)
        XCTAssertEqual(defaultRect.y, explicitRect.y, accuracy: 1e-9)
        XCTAssertEqual(defaultRect.width, explicitRect.width, accuracy: 1e-9)
        XCTAssertEqual(defaultRect.height, explicitRect.height, accuracy: 1e-9)
    }

    func testDefaultIntegerTickLengthMatchesExplicitDoubleLength() {
        func tickLengths(length: Double?) -> [Double] {
            var axisTick: [String: Any] = ["show": true]
            if let length { axisTick["length"] = length }
            let ec = ECharts(width: 400, height: 300)
            ec.setOption([
                "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                "xAxis": [
                    "type": "category",
                    "data": ["A", "B", "C", "D"],
                    "axisTick": axisTick
                ] as [String: Any],
                "yAxis": ["type": "value"] as [String: Any],
                "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
            ])

            var result: [Double] = []
            _ = ec.getRoot().traverse { el in
                if let line = el as? Line,
                   let anid = line.anid, anid.hasPrefix("ticks_"),
                   let shape = line.shape as? LineShape {
                    result.append(hypot(shape.x2 - shape.x1, shape.y2 - shape.y1))
                }
                return false
            }
            return result.sorted()
        }

        let defaultLengths = tickLengths(length: nil) // axisDefault stores `length` as Int(5).
        let explicitLengths = tickLengths(length: 5.0)
        XCTAssertFalse(defaultLengths.isEmpty)
        XCTAssertEqual(defaultLengths, explicitLengths)
        XCTAssertTrue(defaultLengths.allSatisfy { abs($0 - 5.0) < 1e-9 },
                      "default major ticks must extend five points from the axis")
    }

    func testDefaultIntegerNameGapMatchesExplicitDoubleGap() {
        func axisNamePositions(gap: Double?) -> [String: (Double, Double)] {
            var xAxis: [String: Any] = ["type": "value", "name": "x"]
            var yAxis: [String: Any] = ["type": "value", "name": "y"]
            if let gap {
                xAxis["nameGap"] = gap
                yAxis["nameGap"] = gap
            }
            let ec = ECharts(width: 400, height: 300)
            ec.setOption([
                "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                "xAxis": xAxis,
                "yAxis": yAxis,
                "series": [["type": "line", "data": [[0.0, 0.0], [1.0, 1.0]]] as [String: Any]]
            ])

            var result: [String: (Double, Double)] = [:]
            _ = ec.getRoot().traverse { el in
                if let text = el as? ZRText, text.anid == "name",
                   let value = text.textStyle.text {
                    result[value] = (text.x, text.y)
                }
                return false
            }
            return result
        }

        let defaultPositions = axisNamePositions(gap: nil) // axisDefault stores `nameGap` as Int(15).
        let explicitPositions = axisNamePositions(gap: 15.0)
        XCTAssertEqual(defaultPositions.count, 2)
        guard let defaultX = defaultPositions["x"], let explicitX = explicitPositions["x"],
              let defaultY = defaultPositions["y"], let explicitY = explicitPositions["y"] else {
            XCTFail("both value axes must render their end names")
            return
        }
        XCTAssertEqual(defaultX.0, explicitX.0, accuracy: 1e-9)
        XCTAssertEqual(defaultX.1, explicitX.1, accuracy: 1e-9)
        XCTAssertEqual(defaultY.0, explicitY.0, accuracy: 1e-9)
        XCTAssertEqual(defaultY.1, explicitY.1, accuracy: 1e-9)
    }
}
