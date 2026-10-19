// Options the engine used to trap on (forced casts, `Int(NaN)`, out-of-range indexing) where upstream
// either tolerates the input or fails inside the page that set it. Each must now render without
// trapping, as Apache ECharts does where it tolerates the input, and otherwise leave the part it
// cannot read undrawn. Named ZZ… so it registers after the base render tests.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class ZZMalformedOptionTests: XCTestCase {

    private func texts(_ root: Group) -> [String] {
        var out: [String] = []
        _ = root.traverse { el in
            if let t = el as? ZRText, let s = t.textStyle?.text { out.append(s) }
            return false
        }
        return out
    }

    private func count<T>(_ type: T.Type, in root: Group) -> Int {
        var n = 0
        _ = root.traverse { el in
            if el is T { n += 1 }
            return false
        }
        return n
    }

    // categoryFilter: a numeric `category` that is not an index of `categories`, with a legend.
    //   Upstream resolves it to `undefined`, which no legend has deselected: the node stays.
    func testGraphNodeCategoryOutsideCategoriesKeepsTheNode() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "legend": ["data": ["A", "B"]] as [String: Any],
            "series": [[
                "type": "graph", "layout": "none",
                "categories": [["name": "A"], ["name": "B"]],
                "data": [
                    ["name": "n1", "x": 10.0, "y": 10.0, "category": 0.0],
                    ["name": "n2", "x": 50.0, "y": 40.0, "category": 5.0],
                    ["name": "n3", "x": 80.0, "y": 20.0, "category": 1.5]
                ] as [[String: Any]],
                "links": [["source": "n1", "target": "n2"]]
            ] as [String: Any]]
        ])
        let data = ec.getModel()!.getSeriesByIndex(0)!.getData()
        XCTAssertEqual(data.count(), 3, "nodes whose category is not one of the categories are not filtered out")
    }

    // realtimeSort with fewer bars than categories: the tick past the sorted bars differs from the
    //   view's order (upstream reads `undefined` there) instead of indexing past the sort info.
    func testRealtimeSortWithFewerBarsThanCategories() {
        let v = EChartsView(width: 400, height: 300)
        v.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["a", "b", "c", "d"], "inverse": true] as [String: Any],
            "series": [["type": "bar", "realtimeSort": true, "data": [10.0, 20.0, 0.0]] as [String: Any]]
        ])
        v.zr.flush()
        // The same values again: the zero bar ranks below the empty fourth tick, so the order counts as
        //   changed, and the sorted bars agree with the view up to that fourth tick.
        v.setOption(["series": [["type": "bar", "data": [10.0, 20.0, 0.0]] as [String: Any]]], notMerge: false)
        v.zr.flush()
        XCTAssertEqual(v.ec.getModel()!.getSeriesByIndex(0)!.getData().count(), 3)
    }

    // realtimeSort over rows: the ordinal numbers of the sort info are not categories. Upstream writes
    //   them as stray keys; they are not recorded as ticks here instead of being used as indices.
    func testRealtimeSortOverRowsDoesNotIndexByNonOrdinals() {
        let v = EChartsView(width: 400, height: 300)
        v.setOption([
            "animation": false,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
            "series": [["type": "bar", "realtimeSort": true,
                        "data": [[1.0, 7.0], [3.0, 9.0], [5.0, 4.0]]] as [String: Any]]
        ])
        v.zr.flush()
        XCTAssertEqual(v.ec.getModel()!.getSeriesByIndex(0)!.getData().count(), 3)
    }

    // pictorialBar: a `symbolMargin` / `symbolBoundingData` it cannot read makes the repeat count
    //   NaN; upstream's `index < NaN` loop repeats nothing, which is what is drawn.
    func testPictorialBarWithUnreadableSpacingRepeatsNothing() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["data": ["a", "b", "c"]] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [[
                "type": "pictorialBar", "symbol": "rect", "symbolRepeat": true,
                "data": [
                    ["value": 10.0, "symbolMargin": "abc"] as [String: Any],
                    ["value": 20.0, "symbolBoundingData": [1.0]] as [String: Any],
                    ["value": 30.0] as [String: Any]
                ]
            ] as [String: Any]]
        ])
        XCTAssertNotNil(ec.getModel()!.getSeriesByIndex(0))
        XCTAssertGreaterThan(count(ZRenderKit.Path.self, in: ec.getRoot()), 0, "the readable bar still repeats its symbol")
    }

    // calendar: `dayLabel: false` (or a `firstDay` that is no number) makes the first day of the week
    //   NaN, and every weekday index with it. Sunday, the default, instead.
    func testCalendarWithDayLabelThatIsNotAnObject() {
        for dayLabel in [false as Any, ["firstDay": "abc"] as [String: Any]] {
            let ec = ECharts(width: 520, height: 300)
            ec.setOption([
                "calendar": ["range": "2024-02", "dayLabel": dayLabel, "monthLabel": 3.0, "yearLabel": "x"] as [String: Any],
                "visualMap": ["show": false, "min": 0.0, "max": 5.0] as [String: Any],
                "series": [["type": "heatmap", "coordinateSystem": "calendar",
                            "data": [["2024-02-02", 3.0]]] as [String: Any]]
            ])
            XCTAssertGreaterThan(count(ZRenderKit.Polyline.self, in: ec.getRoot()), 0, "the month outline is drawn")
        }
    }

    // An empty date string matches TIME_REG with every group undefined: upstream makes an Invalid
    //   Date of it (`new Date(NaN, …)`), not a trap in the date conversion.
    func testEmptyDateIsAnInvalidDate() {
        XCTAssertTrue(number.parseDate("").timeIntervalSince1970.isNaN)
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "time"] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                ["type": "line", "data": [["2024-01-01", 1.0], ["", 2.0], ["2024-01-03", 3.0]]] as [String: Any],
                ["type": "scatter", "data": ["", ["value": ""]] as [Any]] as [String: Any]
            ]
        ])
        XCTAssertEqual(ec.getModel()!.getSeriesByIndex(0)!.getData().count(), 3)
    }

    // A parallel series given as one object (as any other series may be): the preprocessor finds it
    //   and creates the parallel component its axes render in.
    func testParallelSeriesAsOneObject() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "parallelAxis": [["dim": 0.0, "name": "first"], ["dim": 1.0, "name": "second"]],
            "series": ["type": "parallel", "data": [[1.0, 2.0], [3.0, 4.0]]] as [String: Any]
        ])
        XCTAssertNotNil(ec.getModel()!.getComponent("parallel", 0))
        XCTAssertTrue(texts(ec.getRoot()).contains("first"), "the axes are drawn")
    }

    // A parallel axis whose `parallelIndex` names no parallel component draws no axis.
    func testParallelAxisWithoutItsParallelDrawsNothing() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "parallelAxis": [["dim": 0.0, "name": "first"], ["dim": 1.0, "name": "stray", "parallelIndex": 3.0]],
            "series": [["type": "parallel", "data": [[1.0, 2.0], [3.0, 4.0]]] as [String: Any]]
        ])
        XCTAssertFalse(texts(ec.getRoot()).contains("stray"))
    }

    // visualMap pieces that, once overlaps are cut away, bound no stretch leave a line no color stop:
    //   upstream reads the first stop of an empty list. The line keeps its own color.
    func testLineVisualMapWithNoBoundedPieceKeepsItsColor() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "category", "data": ["a", "b", "c", "d"]] as [String: Any],
            "yAxis": [:] as [String: Any],
            "visualMap": ["show": false, "pieces": [["gt": 0.0, "color": "red"], ["gt": 10.0, "color": "blue"]]] as [String: Any],
            "series": [["type": "line", "data": [5.0, 15.0, 25.0, 8.0]] as [String: Any]]
        ])
        var line: ECPolyline?
        _ = ec.getRoot().traverse { el in
            if let p = el as? ECPolyline, p.name == "line" { line = p }
            return false
        }
        guard let stroke = line?.pathStyle.stroke else { return XCTFail("the line is drawn") }
        if case .linearGradient = stroke { XCTFail("no gradient without a color stop") }
    }

    // showTip on a series that does not map the cartesian dims (`lines` keeps its points in `coords`):
    //   the point is [NaN, NaN] as upstream's length-preserving map makes it, not a short value list.
    func testShowTipOnALinesSeries() {
        let v = EChartsView(width: 400, height: 300)
        v.setOption([
            "animation": false,
            "tooltip": [:] as [String: Any],
            "xAxis": [:] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [["type": "lines", "coordinateSystem": "cartesian2d",
                        "data": [["coords": [[0.0, 0.0], [10.0, 10.0]]], ["coords": [[5.0, 1.0], [2.0, 8.0]]]]] as [String: Any]]
        ])
        for dataIndex in [0, 1, 999] {
            var payload = Payload(type: "showTip")
            payload.other["seriesIndex"] = 0
            payload.other["dataIndex"] = dataIndex
            v.ec.dispatchAction(payload)
        }
        v.ec.dispatchAction(Payload(type: "hideTip"))
    }

    // An axis label formatter closure of the other axis kind's type: a category formatter takes a
    //   value axis's numbers (its first parameter is `Any`, as in JS); a value formatter on a category
    //   axis, or a closure of any other type, keeps the default labels instead of trapping on the cast.
    func testAxisLabelFormatterOfTheOtherAxisType() {
        let categoryFormatter: AxisLabelCategoryFormatter = { value, _, _ in "c:\(value)" }
        let valueFormatter: AxisLabelValueFormatter = { value, _, _ in "v:\(value)" }
        let otherFormatter: (Double) -> String = { "o:\($0)" }

        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "animation": false,
            "xAxis": ["type": "category", "data": ["Mon", "Tue"], "axisLabel": ["formatter": valueFormatter]] as [String: Any],
            "yAxis": ["type": "value", "axisLabel": ["formatter": categoryFormatter]] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0]] as [String: Any]]
        ])
        var labels = texts(ec.getRoot())
        XCTAssertTrue(labels.contains("Mon"), "category axis keeps its names: \(labels)")
        XCTAssertTrue(labels.contains { $0.hasPrefix("c:") }, "value axis labels come from the category formatter: \(labels)")

        ec.setOption([
            "xAxis": ["type": "category", "data": ["Mon", "Tue"], "axisLabel": ["formatter": otherFormatter]] as [String: Any],
            "yAxis": ["type": "value", "axisLabel": ["formatter": otherFormatter]] as [String: Any]
        ], notMerge: false)
        labels = texts(ec.getRoot())
        XCTAssertTrue(labels.contains("Mon"), "\(labels)")
        XCTAssertFalse(labels.contains { $0.hasPrefix("o:") }, "\(labels)")
    }
}
