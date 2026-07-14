// universalTransition (animation/universalTransition.swift + morphTransitionHelper.swift + core/lifecycle.swift):
// two series that share an `id` (or `universalTransition.seriesKey`) and set `universalTransition: true`
// MORPH into each other across a setOption, instead of cross-fading. This is the option shape of the
// official `map-bar-morph` example (a `map` series flipped to a `bar` series with `setOption(opt, true)`),
// reduced to a 3-region toy map so the test is self-contained.
//
// What is asserted: the incoming series' Paths are real zrender morph targets (`isMorphing` /
// `isCombineMorphing`), the morph runs in BOTH directions (map→bar and bar→map), stepping the animation
// clip actually moves the path geometry from the source shape to the target shape, and a series WITHOUT
// `universalTransition` does not morph (the feature is opt-in, not always-on).
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class UniversalTransitionTests: XCTestCase {

    // 3 side-by-side square regions (same shape as GeoRenderTests' toy map).
    private func makeToyGeoJSON() -> [String: Any] {
        func feature(_ name: String, _ lng0: Double, _ lng1: Double) -> [String: Any] {
            [
                "type": "Feature",
                "properties": ["name": name] as [String: Any],
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [[[lng0, 0.0], [lng1, 0.0], [lng1, 10.0], [lng0, 10.0], [lng0, 0.0]]]
                ] as [String: Any]
            ]
        }
        return [
            "type": "FeatureCollection",
            "features": [feature("West", 0.0, 10.0),
                         feature("Central", 10.0, 20.0),
                         feature("East", 20.0, 30.0)] as [Any]
        ]
    }

    private let names = ["West", "Central", "East"]
    private let values: [Double] = [500000.0, 2000000.0, 9000000.0]

    /// `mapOption` — the example's map half (series id 'population', universalTransition on).
    private func mapOption(_ universalTransition: Bool = true) -> [String: Any] {
        let data: [Any] = zip(names, values).map { ["name": $0.0, "value": $0.1] as [String: Any] }
        return [
            "animation": true,
            "series": [[
                "id": "population",
                "type": "map",
                "map": "toyUT",
                "animationDurationUpdate": 1000.0,
                "universalTransition": universalTransition,
                "data": data
            ] as [String: Any]]
        ]
    }

    /// `barOption` — the example's bar half (same series id, same data order).
    private func barOption(_ universalTransition: Bool = true) -> [String: Any] {
        [
            "animation": true,
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": names] as [String: Any],
            "animationDurationUpdate": 1000.0,
            "series": [[
                "id": "population",
                "type": "bar",
                "data": values,
                "universalTransition": universalTransition
            ] as [String: Any]]
        ]
    }

    private func paths<T: Path>(_ ec: ECharts, _ type: T.Type) -> [T] {
        var found: [T] = []
        _ = ec.getRoot().traverse { el in
            if let p = el as? T { found.append(p) }
            return false
        }
        return found
    }

    // map → bar: every bar Rect is a live morph target whose source is its state's polygon.
    func test_map_to_bar_morphs() throws {
        ECharts.registerMap("toyUT", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 320)
        view.setOption(mapOption())                     // myChart.setOption(mapOption)
        view.setOption(barOption(), notMerge: true)     // setInterval → myChart.setOption(barOption, true)

        let bars = paths(view.ec, Rect.self)
        XCTAssertEqual(bars.count, names.count, "one bar per data item")
        for bar in bars {
            XCTAssertTrue(isMorphing(bar) || isCombineMorphing(bar),
                          "each bar must MORPH from its map region (universalTransition), not cross-fade")
        }

        // Stepping the morph clip moves the geometry from the region polygon to the bar rect.
        let probe = bars[0]
        let clip = try XCTUnwrap(probe.animators.first?.getClip(), "no morph animator on the bar")
        _ = clip.step(0, 0)
        let atStart = try XCTUnwrap(probe.getBoundingRect())
        _ = clip.step(500, 500)
        let atMid = try XCTUnwrap(probe.getBoundingRect())
        _ = clip.step(1000, 500)
        let atEnd = try XCTUnwrap(probe.getBoundingRect())

        XCTAssertEqual(probe.__morphT, 1.0, accuracy: 1e-9, "the morph runs to completion")
        XCTAssertNotEqual(atStart.width, atMid.width, "geometry must move while the morph runs")
        XCTAssertNotEqual(atMid.width, atEnd.width, "geometry must keep moving to the bar shape")
        // The end state is the bar's own rect (its final shape), the start state is not.
        let barShape = try XCTUnwrap(probe.shape as? RectShape)
        XCTAssertEqual(atEnd.width, Swift.abs(barShape.width), accuracy: 1e-6,
                       "the morph lands exactly on the bar's final rect")
        XCTAssertNotEqual(atStart.width, Swift.abs(barShape.width), accuracy: 1e-6,
                          "the morph starts from the map region, not from the bar")
    }

    // bar → map: the round trip morphs too (the region CompoundPaths become morph targets).
    func test_bar_to_map_morphs() throws {
        ECharts.registerMap("toyUT", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 320)
        view.setOption(barOption())
        view.setOption(mapOption(), notMerge: true)

        let regions = paths(view.ec, CompoundPath.self)
        XCTAssertEqual(regions.count, names.count, "one region CompoundPath per feature")
        for region in regions {
            XCTAssertTrue(isMorphing(region) || isCombineMorphing(region),
                          "each map region must MORPH back from its bar")
        }
    }

    // MANY-TO-ONE (`combineMorph`): the `scatter-aggregate-bar` shape — two scatter series
    // (dataGroupId 'female'/'male') collapse into ONE bar series whose items carry the matching
    // `groupId` and whose `universalTransition.seriesKey` is the array of both old series' keys.
    func test_many_to_one_combine_morphs() throws {
        let view = EChartsView(width: 520, height: 320)
        view.setOption([
            "animation": true,
            "xAxis": ["scale": true] as [String: Any],
            "yAxis": ["scale": true] as [String: Any],
            "series": [
                ["type": "scatter", "id": "female", "dataGroupId": "female",
                 "animationDurationUpdate": 1000.0,
                 "universalTransition": ["enabled": true] as [String: Any],
                 "data": [[161.2, 51.6], [167.5, 59.0], [159.5, 49.2]]] as [String: Any],
                ["type": "scatter", "id": "male", "dataGroupId": "male",
                 "animationDurationUpdate": 1000.0,
                 "universalTransition": ["enabled": true] as [String: Any],
                 "data": [[174.0, 65.6], [175.3, 71.8], [193.5, 80.7]]] as [String: Any]
            ]
        ])
        view.setOption([
            "animation": true,
            "xAxis": ["type": "category", "data": ["Female", "Male"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "animationDurationUpdate": 1000.0,
            "series": [[
                "type": "bar", "id": "total",
                "universalTransition": ["enabled": true,
                                        "seriesKey": ["female", "male"],
                                        "divideShape": "clone"] as [String: Any],
                "data": [["value": 162.7, "groupId": "female"] as [String: Any],
                         ["value": 180.9, "groupId": "male"] as [String: Any]]
            ] as [String: Any]]
        ], notMerge: true)

        let bars = paths(view.ec, Rect.self)
        XCTAssertEqual(bars.count, 2, "two aggregated bars")
        for bar in bars {
            // 3 symbols → 1 bar is the `combineMorph` branch of applyMorphAnimation (fromIsMany).
            XCTAssertTrue(isCombineMorphing(bar),
                          "each bar must COMBINE-morph from its group's 3 scatter symbols")
        }
    }

    // ONE-TO-MANY (`separateMorph`): the `bar-drilldown` shape — one bar (groupId 'fruits') splits
    // into the child series' bars (dataGroupId 'fruits'), keyed parent→child.
    func test_one_to_many_separate_morphs() throws {
        let view = EChartsView(width: 520, height: 320)
        view.setOption([
            "animation": true,
            "xAxis": ["type": "category", "data": ["Fruits", "Veg"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "animationDurationUpdate": 1000.0,
            "series": [["type": "bar", "id": "main",
                        "universalTransition": true,
                        "data": [["value": 6.0, "groupId": "fruits"] as [String: Any],
                                 ["value": 4.0, "groupId": "veg"] as [String: Any]]] as [String: Any]]
        ])
        view.setOption([
            "animation": true,
            "xAxis": ["type": "category", "data": ["Apple", "Pear", "Plum"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "animationDurationUpdate": 1000.0,
            "series": [["type": "bar", "id": "main",
                        "dataGroupId": "fruits",
                        "universalTransition": true,
                        "data": [3.0, 2.0, 1.0]] as [String: Any]]
        ], notMerge: true)

        let bars = paths(view.ec, Rect.self)
        // The 3 child bars morph out of the parent 'fruits' bar (which `removeEl` detached as the morph
        // source). The unmatched 'veg' parent bar is still in the group, fading out (a 'leave'-scoped
        // animator) — that is the normal basicTransition leave, not a morph.
        let morphing = bars.filter { isMorphing($0) || isCombineMorphing($0) }
        XCTAssertEqual(morphing.count, 3, "each child bar must SEPARATE-morph out of the parent bar")
        for leftover in bars where !(isMorphing(leftover) || isCombineMorphing(leftover)) {
            XCTAssertNotNil(leftover.animators.first { $0.scope == "leave" },
                            "a non-morphing leftover must be an element on its way out (fade-out)")
        }
    }

    // Opt-in: without `universalTransition` the same option flip does NOT morph.
    func test_no_morph_without_universal_transition() {
        ECharts.registerMap("toyUT", makeToyGeoJSON())

        let view = EChartsView(width: 520, height: 320)
        view.setOption(mapOption(false))
        view.setOption(barOption(false), notMerge: true)

        let bars = paths(view.ec, Rect.self)
        XCTAssertGreaterThan(bars.count, 0, "bars still render")
        for bar in bars {
            XCTAssertFalse(isMorphing(bar) || isCombineMorphing(bar),
                           "universalTransition is opt-in — no morph without it")
        }
    }
}
