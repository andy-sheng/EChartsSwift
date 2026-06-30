// Ported from echarts/test/ut/spec/scale/interval.test.ts — keep in sync with upstream
// Behavioral oracle for EChartsKit scale `helper.intervalScaleNiceTicks`
// (echarts/src/scale/helper.ts). This is the FIRST oracle for the Phase-5a scale math.
//
// The upstream spec drives most assertions through `createChart(...)` (full ECharts/model),
// `CartesianAxisModel`, and `scaleCalcNice2` (coord/axisNiceTicks) — NONE of which are ported
// yet (model/coord are Phase 5c). Those portions are XCTSkip-ed with a reason. The portion that
// calls `intervalScaleNiceTicks` directly (and its invariants) IS exercised here, because that
// is the now-translated module under test.

import XCTest
@testable import EChartsKit

final class ScaleIntervalUnitTests: XCTestCase {

    // MARK: - extreme

    func test_extreme_ticks_min_max() throws {
        throw XCTSkip("Requires createChart + CartesianAxisModel + axis.scale.getTicks (model/coord — Phase 5c, not ported).")
    }

    func test_extreme_ticks_small_value() throws {
        throw XCTSkip("Requires createChart + getViewLabels + scale.getLabel(precision) through a full axis (model/coord — Phase 5c, not ported).")
    }

    // MARK: - ticks (intervalScaleNiceTicks portion is portable)

    /// Faithful port of the `intervalScaleNiceTicks(...)` half of upstream `doSingleTestDeal`.
    /// The second half — `new IntervalScale()` + `new CartesianAxisModel(...)` + `scaleCalcNice2(...)`
    /// + `getTicks()` precision checks — depends on model/coord (Phase 5c) and is omitted (see class doc).
    private func doSingleTestNiceTicks(_ extent: [Double], _ splitNumber: Double,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let span = extent[1] - extent[0]
        let result = helper.intervalScaleNiceTicks(extent, span, splitNumber)
        let intervalPrecision = result.intervalPrecision
        let resultInterval = result.interval
        let niceTickExtent = result.niceTickExtent

        XCTAssertTrue(resultInterval.isFinite, "interval finite. extent=\(extent) split=\(splitNumber)",
                      file: file, line: line)
        XCTAssertTrue(intervalPrecision.isFinite, "intervalPrecision finite. extent=\(extent)",
                      file: file, line: line)
        XCTAssertTrue(niceTickExtent[0].isFinite, "niceTickExtent[0] finite. extent=\(extent)",
                      file: file, line: line)
        XCTAssertTrue(niceTickExtent[1].isFinite, "niceTickExtent[1] finite. extent=\(extent)",
                      file: file, line: line)

        XCTAssertGreaterThanOrEqual(niceTickExtent[0], extent[0],
                                    "niceTickExtent[0] >= extent[0]. extent=\(extent)", file: file, line: line)
        XCTAssertLessThanOrEqual(niceTickExtent[1], extent[1],
                                 "niceTickExtent[1] <= extent[1]. extent=\(extent)", file: file, line: line)
    }

    func test_ticks_cases() {
        doSingleTestNiceTicks([-4.487313802559083e-9, -3.371319349409791e-9], 5)
        doSingleTestNiceTicks([3.7210923755786733e-8, 176.4352516752083], 1)
        doSingleTestNiceTicks([1550932.3941785, 1550932.3941786], 5)
        doSingleTestNiceTicks([-3711126.9907707, -3711126.990770699], 5)
    }

    func test_ticks_randomCover() {
        func randomSign() -> Double {
            return (Double.random(in: 0..<1) - 0.5) > 0 ? 1 : -1
        }
        func randomNumber(_ quantity: Double) -> Double {
            return randomSign() * (1 + Double.random(in: 0..<1)) * pow(10, randomSign() * quantity)
        }
        func doRandomTest(_ count: Int, _ splitNumber: Double, _ quantity: Double) {
            for _ in 0..<count {
                var extent = [Double](repeating: 0, count: 2)
                extent[0] = randomNumber(quantity)
                extent[1] = extent[0] + randomNumber(quantity)
                if extent[1] == extent[0] {
                    extent[1] = extent[0] + 1
                }
                if extent[0] > extent[1] {
                    extent.reverse()
                }
                doSingleTestNiceTicks(extent, splitNumber)
            }
        }
        doRandomTest(500, 5, 10)
        doRandomTest(200, 1, 10)
    }
}
