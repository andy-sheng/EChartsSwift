// Ported from echarts/test/ut/spec/util/number.test.ts — keep in sync with upstream
// Behavioral oracle for EChartsKit `number` (echarts/src/util/number.ts).
//
// jest -> XCTest mapping (per task brief):
//   describe/it           -> XCTestCase / test_ methods
//   toBe / toEqual        -> XCTAssertEqual
//   toBeCloseTo(v, n)     -> XCTAssertEqual(.., accuracy: pow(10, -n))
//   toBeFinite            -> XCTAssert(x.isFinite)
//   NaN expectations      -> XCTAssert(x.isNaN) (NaN != NaN, so direct equality cannot be used)
//
// Surfaces referenced by the upstream spec that are NOT yet ported (model/coord) are
// XCTSkip-ed with a reason; everything reachable through the ported `number` namespace is exercised.

import XCTest
@testable import EChartsKit

final class NumberUnitTests: XCTestCase {

    // MARK: - helpers

    /// `toEqual` over Doubles that may be NaN / +-Infinity (jest treats NaN===NaN as equal here).
    private func assertNumEqual(_ actual: Double, _ expected: Double, _ msg: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        if expected.isNaN {
            XCTAssertTrue(actual.isNaN, "expected NaN, got \(actual). \(msg)", file: file, line: line)
        }
        else {
            XCTAssertEqual(actual, expected, "\(msg)", file: file, line: line)
        }
    }

    // MARK: - linearMap

    func test_linearMap_accuracyError() {
        // Should not be 17724.899999999998.
        XCTAssertEqual(number.linearMap(100, [0, 100], [-15918.3, 17724.9], true), 17724.9)
        // Should not be 83.55999999999999.
        XCTAssertEqual(number.linearMap(100, [0, 100], [-62.83, 83.56], true), 83.56)
    }

    func test_linearMap_clamp() {
        var range: [Double]

        // (1) normal order.
        range = [-15918.3, 17724.9]
        XCTAssertEqual(number.linearMap(100.1, [0, 100], range, true), range[1])
        XCTAssertEqual(number.linearMap(-2, [0, 100], range, true), range[0])
        XCTAssertEqual(number.linearMap(100, [0, 100], range, true), range[1])
        XCTAssertEqual(number.linearMap(0, [0, 100], range, true), range[0])

        // (2) inverse range
        range = [17724.9, -15918.3]
        XCTAssertEqual(number.linearMap(102, [0, 100], range, true), range[1])
        XCTAssertEqual(number.linearMap(-0.001, [0, 100], range, true), range[0])
        XCTAssertEqual(number.linearMap(100, [0, 100], range, true), range[1])
        XCTAssertEqual(number.linearMap(0, [0, 100], range, true), range[0])

        // (2) inverse domain
        range = [-15918.3, 17724.9]
        XCTAssertEqual(number.linearMap(102, [100, 0], range, true), range[0])
        XCTAssertEqual(number.linearMap(-0.001, [100, 0], range, true), range[1])
        XCTAssertEqual(number.linearMap(100, [100, 0], range, true), range[0])
        XCTAssertEqual(number.linearMap(0, [100, 0], range, true), range[1])

        // (3) inverse domain, inverse range
        range = [17724.9, -15918.3]
        XCTAssertEqual(number.linearMap(100.1, [100, 0], range, true), range[0])
        XCTAssertEqual(number.linearMap(-2, [100, 0], range, true), range[1])
        XCTAssertEqual(number.linearMap(100, [100, 0], range, true), range[0])
        XCTAssertEqual(number.linearMap(0, [100, 0], range, true), range[1])
    }

    func test_linearMap_noClamp() {
        var range: [Double]

        // (1) normal order.
        range = [-15918.3, 17724.9]
        XCTAssertEqual(number.linearMap(100.1, [0, 100], range, false), 17758.543199999996)
        XCTAssertEqual(number.linearMap(-2, [0, 100], range, false), -16591.164)
        XCTAssertEqual(number.linearMap(100, [0, 100], range, false), 17724.9)
        XCTAssertEqual(number.linearMap(0, [0, 100], range, false), -15918.3)

        // (2) inverse range
        range = [17724.9, -15918.3]
        XCTAssertEqual(number.linearMap(102, [0, 100], range, false), -16591.163999999997)
        XCTAssertEqual(number.linearMap(-0.001, [0, 100], range, false), 17725.236432)
        XCTAssertEqual(number.linearMap(100, [0, 100], range, false), -15918.3)
        XCTAssertEqual(number.linearMap(0, [0, 100], range, false), 17724.9)

        // (2) inverse domain
        range = [-15918.3, 17724.9]
        XCTAssertEqual(number.linearMap(102, [100, 0], range, false), -16591.164)
        XCTAssertEqual(number.linearMap(-0.001, [100, 0], range, false), 17725.236432)
        XCTAssertEqual(number.linearMap(100, [100, 0], range, false), -15918.3)
        XCTAssertEqual(number.linearMap(0, [100, 0], range, false), 17724.9)

        // (3) inverse domain, inverse range
        range = [17724.9, -15918.3]
        XCTAssertEqual(number.linearMap(100.1, [100, 0], range, false), 17758.5432)
        XCTAssertEqual(number.linearMap(-2, [100, 0], range, false), -16591.163999999997)
        XCTAssertEqual(number.linearMap(100, [100, 0], range, false), 17724.9)
        XCTAssertEqual(number.linearMap(0, [100, 0], range, false), -15918.3)
    }

    func test_linearMap_normal() {
        for clamp in [true, false] {
            // normal
            XCTAssertEqual(number.linearMap(40, [0, 100], [444, 555], clamp), 488.4)
            // inverse range
            XCTAssertEqual(number.linearMap(40, [0, 100], [555, 444], clamp), 510.6)
            // inverse domain and range
            XCTAssertEqual(number.linearMap(40, [100, 0], [555, 444], clamp), 488.4)
            // inverse domain
            XCTAssertEqual(number.linearMap(40, [100, 0], [444, 555], clamp), 510.6)
        }
    }

    func test_linearMap_zeroInterval() {
        for clamp in [true, false] {
            // zero domain interval
            XCTAssertEqual(
                number.linearMap(40, [1212222223.2323232, 1212222223.2323232], [444, 555], clamp),
                499.5) // half of range.
            // zero range interval
            XCTAssertEqual(
                number.linearMap(40, [0, 100], [1221212.1221372238, 1221212.1221372238], clamp),
                1221212.1221372238)
            // zero domain interval and range interval
            XCTAssertEqual(
                number.linearMap(40, [43.55454545, 43.55454545], [1221212.1221372238, 1221212.1221372238], clamp),
                1221212.1221372238)
        }
    }

    // MARK: - parseDate

    /// `+parseDate(x)` — the Date's ms-since-epoch timestamp.
    private func pd(_ value: Any?) -> Double {
        return number.parseDate(value).timeIntervalSince1970 * 1000
    }
    private func isInvalidDate(_ value: Any?) -> Bool {
        return number.parseDate(value).timeIntervalSince1970.isNaN
    }
    /// Independent local-time oracle, mirroring `+new Date('YYYY-MM-DDTHH:MM:SS.sss')` (no zone -> local).
    private func localTS(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int, _ ms: Int = 0) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        c.nanosecond = ms * 1_000_000
        return cal.date(from: c)!.timeIntervalSince1970 * 1000
    }

    func test_parseDate() {
        // Invalid Date
        XCTAssertTrue(isInvalidDate(nil))
        XCTAssertTrue(isInvalidDate("asdf"))
        XCTAssertTrue(isInvalidDate(Double.nan))
        XCTAssertTrue(isInvalidDate("-"))
        XCTAssertTrue(isInvalidDate("20120304"))

        // Input instance of Date or timestamp
        XCTAssertEqual(pd(Date(timeIntervalSince1970: 1330819200)), 1330819200000)
        XCTAssertEqual(pd(1330819200000.0), 1330819200000)
        XCTAssertEqual(pd(1330819199999.99), 1330819200000)
        XCTAssertEqual(pd(1330819200000.01), 1330819200000)

        // ISO string (local time when no zone)
        XCTAssertEqual(pd("2012-03"), localTS(2012, 3, 1, 0, 0, 0))
        XCTAssertEqual(pd("2012-03-04"), localTS(2012, 3, 4, 0, 0, 0))
        XCTAssertEqual(pd("2012-03-04 05"), localTS(2012, 3, 4, 5, 0, 0))
        XCTAssertEqual(pd("2012-03-04T05"), localTS(2012, 3, 4, 5, 0, 0))
        XCTAssertEqual(pd("2012-03-04 05:06"), localTS(2012, 3, 4, 5, 6, 0))
        XCTAssertEqual(pd("2012-03-04T05:06"), localTS(2012, 3, 4, 5, 6, 0))
        XCTAssertEqual(pd("2012-03-04 05:06:07"), localTS(2012, 3, 4, 5, 6, 7))
        XCTAssertEqual(pd("2012-03-04T05:06:07"), localTS(2012, 3, 4, 5, 6, 7))
        XCTAssertEqual(pd("2012-03-04T05:06:07.123"), localTS(2012, 3, 4, 5, 6, 7, 123))
        XCTAssertEqual(pd("2012-03-04T05:06:07,123"), localTS(2012, 3, 4, 5, 6, 7, 123))
        // upstream-documented quirk: '.12' is treated as '.012', '.1' as '.001'
        XCTAssertEqual(pd("2012-03-04T05:06:07.12"), localTS(2012, 3, 4, 5, 6, 7, 12))
        XCTAssertEqual(pd("2012-03-04T05:06:07.1"), localTS(2012, 3, 4, 5, 6, 7, 1))

        // Explicit time zone offsets (TZ-independent fixed values).
        // NOTE (faithfulness divergence, reported): upstream `+parseDate(...)` is an exact integer
        // ms because JS `Date` stores integer milliseconds; the Swift port returns a Foundation
        // `Date` (Double seconds), so `timeIntervalSince1970 * 1000` carries a sub-ms float artifact
        // (e.g. 1330808767123.0002). The *instant* is correct (rounds to the exact ms), so these are
        // asserted with a sub-ms accuracy. (The local-time cases above match exactly only because both
        // sides route through the same Foundation path and share the artifact.)
        let msAcc = 1e-3
        XCTAssertEqual(pd("2012-03-04T05:06:07.123+0800"), 1330808767123, accuracy: msAcc)
        XCTAssertEqual(pd("2012-03-04T05:06:07.123+08:00"), 1330808767123, accuracy: msAcc)
        XCTAssertEqual(pd("2012-03-04T05:06:07.123-0700"), 1330862767123, accuracy: msAcc)
        XCTAssertEqual(pd("2012-03-04T05:06:07.123-07:00"), 1330862767123, accuracy: msAcc)
        XCTAssertEqual(pd("2012-03-04T5:6:7.123-07:00"), 1330862767123, accuracy: msAcc)
        // '2012-03-04T05:06:07.123Z' and '.123000Z'
        XCTAssertEqual(pd("2012-03-04T05:06:07,123Z"), 1330837567123, accuracy: msAcc)
        XCTAssertEqual(pd("2012-03-04T05:06:07.123000Z"), 1330837567123, accuracy: msAcc)

        // Other string (local time)
        XCTAssertEqual(pd("2012"), localTS(2012, 1, 1, 0, 0, 0))
        XCTAssertEqual(pd("2012/03"), localTS(2012, 3, 1, 0, 0, 0))
        XCTAssertEqual(pd("2012/03/04"), localTS(2012, 3, 4, 0, 0, 0))
        XCTAssertEqual(pd("2012-3-4"), localTS(2012, 3, 4, 0, 0, 0))
        XCTAssertEqual(pd("2012/3"), localTS(2012, 3, 1, 0, 0, 0))
        XCTAssertEqual(pd("2012/3/4"), localTS(2012, 3, 4, 0, 0, 0))
        XCTAssertEqual(pd("2012/3/4 2:05"), localTS(2012, 3, 4, 2, 5, 0))
        XCTAssertEqual(pd("2012/03/04 2:05"), localTS(2012, 3, 4, 2, 5, 0))
        XCTAssertEqual(pd("2012/3/4 2:05:08"), localTS(2012, 3, 4, 2, 5, 8))
        XCTAssertEqual(pd("2012/03/04 2:05:08"), localTS(2012, 3, 4, 2, 5, 8))
        XCTAssertEqual(pd("2012/3/4 2:05:08.123"), localTS(2012, 3, 4, 2, 5, 8, 123))
        XCTAssertEqual(pd("2012/03/04 2:05:08.123"), localTS(2012, 3, 4, 2, 5, 8, 123))
    }

    // MARK: - reformIntervals

    private func interval(_ a: Double, _ b: Double, _ c0: Double, _ c1: Double) -> number.IntervalItem {
        return number.IntervalItem(interval: [a, b], close: [c0, c1])
    }
    private func assertIntervals(_ actual: [number.IntervalItem], _ expected: [number.IntervalItem],
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, "interval count", file: file, line: line)
        for i in 0..<Swift.min(actual.count, expected.count) {
            XCTAssertEqual(actual[i].interval, expected[i].interval, "interval[\(i)]", file: file, line: line)
            XCTAssertEqual(actual[i].close, expected[i].close, "close[\(i)]", file: file, line: line)
        }
    }

    func test_reformIntervals_basic() {
        let inf = Double.infinity
        // all
        assertIntervals(number.reformIntervals([
            interval(18, 62, 1, 1),
            interval(-inf, -70, 0, 0),
            interval(-70, -26, 1, 1),
            interval(-26, 18, 1, 1),
            interval(62, 150, 1, 1),
            interval(106, 150, 1, 1),
            interval(150, inf, 0, 0)
        ]), [
            interval(-inf, -70, 0, 0),
            interval(-70, -26, 1, 1),
            interval(-26, 18, 0, 1),
            interval(18, 62, 0, 1),
            interval(62, 150, 0, 1),
            interval(150, inf, 0, 0)
        ])

        // remove overlap
        assertIntervals(number.reformIntervals([
            interval(18, 62, 1, 1),
            interval(50, 150, 1, 1)
        ]), [
            interval(18, 62, 1, 1),
            interval(62, 150, 0, 1)
        ])

        // remove overlap on edge
        assertIntervals(number.reformIntervals([
            interval(18, 62, 1, 1),
            interval(62, 150, 1, 1)
        ]), [
            interval(18, 62, 1, 1),
            interval(62, 150, 0, 1)
        ])

        // remove included interval
        assertIntervals(number.reformIntervals([
            interval(30, 40, 1, 1),
            interval(42, 54, 1, 1),
            interval(45, 60, 1, 1),
            interval(18, 62, 1, 1)
        ]), [
            interval(18, 62, 1, 1)
        ])

        // remove edge
        assertIntervals(number.reformIntervals([
            interval(18, 62, 1, 1),
            interval(30, 62, 1, 1)
        ]), [
            interval(18, 62, 1, 1)
        ])
    }

    // MARK: - getPrecision / getPrecisionSafe

    private func precisionBasicCases(_ fn: (Any?) -> Double) {
        XCTAssertEqual(fn(10.0), 0)
        XCTAssertEqual(fn(1.0), 0)
        XCTAssertEqual(fn(0.0), 0)
        XCTAssertEqual(fn(100000000000000000000000000000.0), 0)
        XCTAssertEqual(fn(0.1), 1)
        XCTAssertEqual(fn(0.100), 1)
        XCTAssertEqual(fn(0.0032), 4)
        XCTAssertEqual(fn(0.0000000000034), 13)
        XCTAssertEqual(fn(1e+100), 0)
        XCTAssertEqual(fn(3.456E100), 0)
        XCTAssertEqual(fn(3.456E-100), 103)
        XCTAssertEqual(fn(3.4e-10), 11)
        XCTAssertEqual(fn(3.4e-0), 1)
        XCTAssertEqual(fn(3e-0), 0)
        XCTAssertEqual(fn(3e-1), 1)
        XCTAssertEqual(fn(3.4e0), 1)
        XCTAssertEqual(fn(3.45e1), 1)
        XCTAssertEqual(fn(3.45e-1), 3)
        XCTAssertEqual(fn(3.45e2), 0)
        XCTAssertEqual(fn(0.456e2), 1)
        XCTAssertEqual(fn(0.456e-2), 5)
        XCTAssertEqual(fn(0.4e2), 0)
        XCTAssertEqual(fn(0.4e-2), 3)
    }

    func test_getPrecision_basic() {
        precisionBasicCases(number.getPrecision)
    }
    func test_getPrecisionSafe_basicViaShared() {
        precisionBasicCases(number.getPrecisionSafe)
    }

    func test_getPrecision_equal_random() {
        func makeRandomNumber() -> Double {
            let p1 = String(Int((Double.random(in: 0..<1) * 100).rounded(.toNearestOrAwayFromZero)))
            let p2 = String(Int((Double.random(in: 0..<1) * 10000).rounded(.toNearestOrAwayFromZero)))
            let p3 = String(Int((Double.random(in: 0..<1) * 20).rounded(.toNearestOrAwayFromZero)) - 100)
            return number.numberCoerce(p1 + "." + p2 + "e" + p3)
        }
        for _ in 0..<500 {
            let num = makeRandomNumber()
            XCTAssertEqual(number.getPrecision(num), number.getPrecisionSafe(num),
                           "mismatch for \(num)")
        }
    }

    func test_getPrecisionSafe_basic() {
        XCTAssertEqual(number.getPrecisionSafe(10.0), 0)
        XCTAssertEqual(number.getPrecisionSafe(1.0), 0)
        XCTAssertEqual(number.getPrecisionSafe(0.0), 0)
        XCTAssertEqual(number.getPrecisionSafe(100000000000000000000000000000.0), 0)
        XCTAssertEqual(number.getPrecisionSafe(0.1), 1)
        XCTAssertEqual(number.getPrecisionSafe(0.100), 1)
        XCTAssertEqual(number.getPrecisionSafe(0.0032), 4)
        XCTAssertEqual(number.getPrecisionSafe(0.0000000000034), 13)
        XCTAssertEqual(number.getPrecisionSafe(1e+100), 0)
        XCTAssertEqual(number.getPrecisionSafe(3.456E100), 0)
        XCTAssertEqual(number.getPrecisionSafe(3.456E-100), 103)
        XCTAssertEqual(number.getPrecisionSafe(3.4e-10), 11)
        XCTAssertEqual(number.getPrecisionSafe(3.456e-100), 103)
        XCTAssertEqual(number.getPrecisionSafe(3.4e-0), 1)
        XCTAssertEqual(number.getPrecisionSafe(3e-0), 0)
        XCTAssertEqual(number.getPrecisionSafe(3e-1), 1)
        XCTAssertEqual(number.getPrecisionSafe(3.4e0), 1)
        XCTAssertEqual(number.getPrecisionSafe(3.45e1), 1)
        XCTAssertEqual(number.getPrecisionSafe(3.45e-1), 3)
        XCTAssertEqual(number.getPrecisionSafe(3.45e2), 0)
        XCTAssertEqual(number.getPrecisionSafe(0.456e2), 1)
        XCTAssertEqual(number.getPrecisionSafe(0.456e-2), 5)
        XCTAssertEqual(number.getPrecisionSafe(0.4e2), 0)
        XCTAssertEqual(number.getPrecisionSafe(0.4e-2), 3)
    }

    // MARK: - addSafe

    func test_addSafe_basic() {
        // Most of the test cases copied from bignumber.js / decimal.js (MIT).
        let nan = Double.nan
        let inf = Double.infinity
        let cases: [(Double, Double, Double)] = [
            (1, 0, 1), (1, -0.0, 1), (-1, 0, -1), (-1, -0.0, -1),
            (1, nan, nan), (-1, nan, nan), (0, nan, nan), (-0.0, nan, nan), (nan, nan, nan),
            (1, inf, inf), (1, -inf, -inf), (-1, inf, inf), (-1, -inf, -inf),
            (0, inf, inf), (0, -inf, -inf), (-0.0, inf, inf), (-0.0, -inf, -inf),
            (0, 1, 1), (0, -1, -1), (-0.0, 1, 1), (-0.0, -1, -1),
            (nan, 4534534.45435435, nan), (nan, 99999.999, nan),
            (inf, 354.345341, inf), (-inf, -inf, -inf), (inf, -999e99, inf),
            (1.21123e43, -inf, -inf), (-999.0, inf, inf), (657.342e-45, -inf, -inf),
            (1, inf, inf), (1, -inf, -inf),
            (nan, 4534534.45435435, nan), (nan, 99999.999, nan),
            (inf, 354.345341, inf), (1.21123e43, -inf, -inf), (657.342e-45, -inf, -inf),
            (inf, nan, nan), (-inf, nan, nan), (inf, inf, inf),
            (inf, -inf, nan), (-inf, inf, nan), (-inf, -inf, -inf),

            (0.1, 0.2, 0.3), (2.3, -0.3, 2), (33643.2, -15918.3, 17724.9),
            (146.39, -62.83, 83.56), (1.09, -0.13, 0.96), (1, 0, 1), (1, 1, 2),
            (1, -45, -44), (1, 22, 23), (1, 6.1915, 7.1915), (1, -1.02, -0.02),
            (1, 0.09, 1.09), (1, -0.0001, 0.9999), (1, 8e5, 800001),
            (1, 9E12, 9000000000001), (1, 1e-14, 1.00000000000001),
            (1, 3.345E-9, 1.000000003345), (1, -345.43e+4, -3454299),
            (1, -94.12E+0, -93.12), (0, 0, 0), (0, 0, 0), (3, -0.0, 3),
            (9.654, 0, 9.654), (0, 0.001, 0.001), (0, 111.1111111110000, 111.111111111),
            (-1, 1, 0), (-0.01, 0.01, 0), (54, -54, 0), (9.99, -9.99, 0),
            (0.00000, -0.000001, -0.000001),
            (0.0000023432495704937, -0.0000023432495704937, 0),
            (100, 100, 200), (-999.99, 0.01, -999.98), (10, 4, 14),
            (3.333, -4, -0.667), (-1, -0.1, -1.1), (43534.5435, 0.054645, 43534.598145),
            (99999, 1, 100000),

            (1, 0, 1), (1, 1, 2), (1, -45, -44), (1, 22, 23), (1, 6.1915, 7.1915),
            (1, -1.02, -0.02), (1, 0.09, 1.09), (1, -0.0001, 0.9999), (1, 8e5, 800001),
            (1, 9E12, 9000000000001), (1, 1e-14, 1.00000000000001),
            (1, 3.345E-9, 1.000000003345), (1, -345.43e+4, -3454299),
            (1, -94.12E+0, -93.12), (1, 4.001, 5.001), (0, 0, 0), (0, 0, 0), (0, 0, 0),
            (3, -0.0, 3), (9.654, 0, 9.654), (0, 0.001, 0.001),
            (0, 111.1111111110000, 111.111111111), (-1, 1, 0), (-0.01, 0.01, 0),
            (54, -54, 0), (9.99, -9.99, 0),
            (0.0000023432495704937, -0.0000023432495704937, 0), (100, 100, 200),
            (-999.99, 0.01, -999.98), (3.333, -4, -0.667), (-1, -0.1, -1.1),
            (43534.5435, 0.054645, 43534.598145), (99999, 1, 100000), (3e0, 4, 7),

            (-0.000000046, 0, -4.6e-8), (0, -5.1, -5.1), (1.3, 2, 3.3),
            (1.02, 1.2, 2.22), (3.0, 0, 3), (3, 31.9, 34.9),
            (0, -0.0000000000000712, -7.12e-14), (1.10, 5, 6.1),
            (4.2, -0.000000062, 4.199999938), (1, 0, 1), (-5.1, 1, -4.1), (0, -1, -1),
            (699, -4, 695), (0, -1, -1), (1.6, -27.2, -25.6), (0, -7, -7),
            (3.0, -4, -1), (0, -2.0, -2), (0, -3, -3), (-2, 1, -1), (-9, -1, -10),
            (2, -1.1, 0.9), (-5, -3, -8), (7, -37, -30), (-3, -5.0, -8),
            (1.2, -0.0000194, 1.1999806), (0, 5, 5), (0, 1, 1),
            (-0.000000000000214, 0, -2.14e-13), (0, 0, 0), (0, -1, -1), (-3, 156, 153),
            (231, 0.00000000408, 231.00000000408), (0, -1.7, -1.7), (-4.16, 0, -4.16),
            (0, 5.8, 5.8), (1.5, 5, 6.5), (4.0, -6.19, -2.19), (-1.46, -5.04, -6.5),
            (5.11, 6, 11.11), (-2.11, 0, -2.11), (0.0067, -5, -4.9933), (0, 2, 2),
            (1.0, -24.4, -23.4), (-0.000015, -6, -6.000015), (1.5, 0, 1.5),
            (4.1, -3, 1.1), (-2, -1, -3), (3, 1.5, 4.5), (-7.8, -3, -10.8),
            (-32, 17.6, -14.4), (0, 0, 0), (-47.4, -1, -48.4),
            (15.4, 0.000014, 15.400014), (7.2, 2.9, 10.1), (-86.5, -47.2, -133.7),
            (1.1, -31.4, -30.3), (-121, 3, -118), (-4, 3, -1), (-3.98, 1.2, -2.78),
            (-4.90, 0, -4.9), (2.28, 0, 2.28),
            (-0.0000000000051, -0.0000000000000000236, -5.1000236e-12), (1, -28, -27),
            (0, -3.12, -3.12), (7, 24.9, 31.9), (-7.8, 17, 9.2), (1, 1, 2),
            (0.00000000000000000016, -2, -1.99999999999999999984), (6, 8.5, 14.5),
            (1.10, -1, 0.1), (-1, 3.3, 2.3), (4, -1.3, 2.7), (0, 2.09, 2.09),
            (-1, 0, -1), (-1, 0, -1), (0, 8.1, 8.1), (-3, -4.96, -7.96),
            (9.73, 0, 9.73), (1, 0, 1), (-1, -3, -4), (3, -3.0, 0),
            (-2.78, -403, -405.78), (1, -0.00063, 0.99937), (2, 0, 2), (3, 7, 10),
            (-1, 0, -1), (-4.1, -4, -8.1), (-5, 7, 2),
            (-7, -0.00000000000000000511, -7.00000000000000000511),
            (0, 0.000000000000000000233, 2.33e-19), (1.2, -8.5, -7.3), (2, -2, 0),
            (-24, -5, -29), (-2.1, 0.0114, -2.0886), (8, -5, 3),
            (0.061, 12.1, 12.161), (0, 2.7, 2.7), (-0.00000871, 0, -0.00000871),
            (0, 0, 0), (2, -6.0, -4), (9, -1.2, 7.8), (7, 0, 7),
            (0, 0.000000000000000213, 2.13e-16), (2.5, 0, 2.5), (0, 0.00211, 0.00211),
            (6.4, -15.7, -9.3), (1.5, 0, 1.5), (-41, 0.113, -40.887), (-7.1, 2, -5.1),
            (6, -1.6, 4.4), (-1.2, 0, -1.2), (-3, 13.3, 10.3), (0, 0, 0),
            (0, -105, -105), (-0.52, -40.9, -41.42), (1, 0, 1), (0, 0, 0),
            (-5.1, -0.00024, -5.10024),
            (-0.000000000000027, 6, 5.999999999999973), (125, -2, 123), (2, -365, -363),
            (6.2, -55.1, -48.9), (4.9, -6, -1.1),
            (0.0000000482, 0.0000000019, 5.01e-8), (0, 1.7, 1.7), (78.3, 2.2, 80.5),
            (-53.9, 4.0, -49.9), (0, 2.1, 2.1), (-1.0, -143, -144), (-1, 2.2, 1.2),
            (1, 84.9, 85.9), (0, 26, 26),
            (51, 0.000000000000000757, 51.000000000000000757), (1.1, -3.67, -2.57),
            (-1.2, 1.30, 0.1), (-0.00000000000021, 0.0000000013, 1.29979e-9),
            (-1.6, -1, -2.6), (-2.0, 63, 61), (-3, 7, 4), (-221, 38, -183),
            (-1, 0, -1), (46.4, 2, 48.4), (0, 0, 0),
            (-1, -0.0000000853, -1.0000000853), (79, 0.000190, 79.00019),
            (0, -8.59, -8.59), (1, -1, 0),
            (0.000000000000000000110, -5.8, -5.79999999999999999989), (6, 3.86, 9.86),
            (-9, 8, -1), (-1.0, -45.9, -46.9), (-2, 1, -1), (17.3, 1, 18.3),
            (0, 0.23, 0.23), (1.14, 0, 1.14), (-1.99, -1, -2.99),
            (9, 0.0000000000000000000157, 9.0000000000000000000157), (-11, 89, 78),
            (0, -13.9, -13.9), (0.00000000000015, 86, 86.00000000000015), (278, -2, 276),
            (0, -2.18, -2.18), (0, -0.000000029, -2.9e-8),
            (-6, -0.0000000045, -6.0000000045), (0, -24.7, -24.7), (6.0, 124, 130),
            (0.00089, -0.117, -0.11611), (-0.94, 44, 43.06), (52.1, -4, 48.1),
            (0, -0.00000062, -6.2e-7), (2, -0.000000000242, 1.999999999758),
            (-6.2, 1, -5.2), (3.4, 1, 4.4), (-1.5, 3.8, 2.3), (3, -1.27, 1.73),
            (-1, 7, 6), (-2.29, -4.8, -7.09), (0, 0, 0),
            (-5, -0.0000000000000016, -5.0000000000000016), (2.0, -1.5, 0.5),
            (94.2, -1.4, 92.8),
            (37, -0.000000000000000000028, 36.999999999999999999972),
            (-0.00000000000000000750, 1, 0.9999999999999999925), (1.5, -1.7, -0.2),
            (-1, 20.0, 19), (2.6, 0, 2.6), (0, -28.4, -28.4), (-12.1, -14, -26.1),
            (1.7, 0.000000041, 1.700000041), (9.5, 4, 13.5), (2.8, 101, 103.8),
            (0.000000022, 0, 2.2e-8), (6, 28, 34), (7, -97, -90), (-1.7, -3, -4.7),
            (107, 6.2, 113.2), (-0.000000000000000118, -2, -2.000000000000000118),
            (-0.000000000000000451, -5.3, -5.300000000000000451), (0, -1, -1),
            (0.0000055, 145, 145.0000055), (0, -8, -8), (0, -2.7, -2.7), (-3, 0, -3),
            (-7, 7, 0), (-1.1, 0, -1.1), (-92, -1.4, -93.4), (-2.7, -3.25, -5.95),
            (68.5, 509, 577.5), (0, 0, 0), (22.6, -1, 21.6), (373, 0, 373), (0, -5, -5),
            (32.2, -7, 25.2), (-1, -1.7, -2.7), (-1.3, 0.0000000048, -1.2999999952),
            (5, -5, 0), (0, 11.9, 11.9), (-0.82, 25, 24.18), (0, 3.1, 3.1),
            (0.000024, 6, 6.000024), (10, -0.000000116, 9.999999884), (977, 0, 977),
            (13, -0.00000205, 12.99999795), (-7, -9.0, -16), (0, 1.05, 1.05), (1, 0, 1),
            (-10.1, 0, -10.1), (2.2, -0.000000000000061, 2.199999999999939),
            (0, -0.0000085, -0.0000085), (3, 3.5, 6.5), (1, 2.8, 3.8),
            (-2, -8.60, -10.6), (223, 9, 232), (-20.4, -213, -233.4), (0, 2, 2),
            (-2.9, -1.3, -4.2), (3.0, 0, 3),
            (-5, 0.00000000000000000011, -4.99999999999999999989),
            (-0.000088, 70.4, 70.399912), (-1, -505, -506), (0, -4, -4),
            (768, 1.1, 769.1), (2, 0, 2), (88, 1.4, 89.4),
            (7.8, 0.0000000000000025, 7.8000000000000025), (2.6, -3.20, -0.6),
            (-24, -2.6, -26.6), (0, -1, -1), (-6, 0.00059, -5.99941), (14, 4.1, 18.1),
            (-30.5, 1.48, -29.02), (-509, 5, -504), (-1, 3, 2),
            (1.3, 0.000103, 1.300103), (-2.8, 19.1, 16.3), (10.07, 0.581, 10.651),
            (3, -2, 1), (-29, 4, -25), (-3.80, -48.2, -52), (6, -21.3, -15.3),
            (3, -1.7, 1.3), (0, 0.00000000033, 3.3e-10), (0.49, 0, 0.49), (7, 1.1, 8.1),
            (1, -2.73, -1.73), (0, -3.89, -3.89), (1.27, 9, 10.27),
            (-0.00000000151, -25, -25.00000000151)
        ]
        for (a, b, expected) in cases {
            assertNumEqual(number.addSafe(a, b), expected, "addSafe(\(a), \(b))")
        }
    }

    // MARK: - getPercentWithPrecision

    func test_getPercentWithPrecision_basic() {
        XCTAssertEqual(number.getPercentWithPrecision([50.5, 49.5], 0, 0), 51)
        XCTAssertEqual(number.getPercentWithPrecision([50.5, 49.5], 1, 0), 49)

        XCTAssertEqual(number.getPercentWithPrecision([12.34, 34.56, 53.1], 0, 1), 12.3)
        XCTAssertEqual(number.getPercentWithPrecision([12.34, 34.56, 53.1], 1, 1), 34.6)
        XCTAssertEqual(number.getPercentWithPrecision([12.34, 34.56, 53.1], 2, 1), 53.1)

        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875], 0, 0), 17)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875], 1, 0), 48)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875], 2, 0), 26)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875], 3, 0), 9)
    }

    func test_getPercentWithPrecision_NaNData() {
        let nan = Double.nan
        // upstream uses '-' as a non-numeric marker; the ported [Double] signature represents it as NaN.
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875, nan], 0, 0), 17)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875, nan], 1, 0), 48)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875, nan], 2, 0), 26)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875, nan], 3, 0), 9)
        XCTAssertEqual(number.getPercentWithPrecision([1.678, 4.783, 2.664, 0.875, nan], 4, 0), 0)

        // upstream: [0, undefined, '-', null, NaN] — all non-numeric collapse to NaN.
        XCTAssertEqual(number.getPercentWithPrecision([0, nan, nan, nan, nan], 0, 0), 0)
        XCTAssertEqual(number.getPercentWithPrecision([0, nan, nan, nan, nan], 1, 0), 0)
        XCTAssertEqual(number.getPercentWithPrecision([0, nan, nan, nan, nan], 2, 0), 0)
        XCTAssertEqual(number.getPercentWithPrecision([0, nan, nan, nan, nan], 3, 0), 0)
        XCTAssertEqual(number.getPercentWithPrecision([0, nan, nan, nan, nan], 4, 0), 0)
    }

    // MARK: - quantityExponent

    func test_quantityExponent_basic() {
        XCTAssertEqual(number.quantityExponent(1), 0)
        XCTAssertEqual(number.quantityExponent(9), 0)
        XCTAssertEqual(number.quantityExponent(12), 1)
        XCTAssertEqual(number.quantityExponent(123), 2)
        XCTAssertEqual(number.quantityExponent(1234), 3)
        XCTAssertEqual(number.quantityExponent(1234.5678), 3)
        XCTAssertEqual(number.quantityExponent(10), 1)
        XCTAssertEqual(number.quantityExponent(1000), 3)
        XCTAssertEqual(number.quantityExponent(10000), 4)
    }
    func test_quantityExponent_decimals() {
        XCTAssertEqual(number.quantityExponent(0.1), -1)
        XCTAssertEqual(number.quantityExponent(0.001), -3)
        XCTAssertEqual(number.quantityExponent(0.00123), -3)
    }
    func test_quantityExponent_largeNumber() {
        XCTAssertEqual(number.quantityExponent(3.14e100), 100)
        XCTAssertEqual(number.quantityExponent(3.14e-100), -100)
    }
    func test_quantityExponent_zero() {
        XCTAssertEqual(number.quantityExponent(0), 0)
    }

    // MARK: - quantity

    func test_quantity_basic() {
        XCTAssertEqual(number.quantity(1), 1)
        XCTAssertEqual(number.quantity(9), 1)
        XCTAssertEqual(number.quantity(12), 10)
        XCTAssertEqual(number.quantity(123), 100)
        XCTAssertEqual(number.quantity(1234), 1000)
        XCTAssertEqual(number.quantity(1234.5678), 1000)
        XCTAssertEqual(number.quantity(10), 10)
        XCTAssertEqual(number.quantity(1000), 1000)
        XCTAssertEqual(number.quantity(10000), 10000)
    }
    func test_quantity_decimals() {
        XCTAssertEqual(number.quantity(0.2), 0.1)
        XCTAssertEqual(number.quantity(0.002), 0.001)
        XCTAssertEqual(number.quantity(0.00123), 0.001)
    }
    func test_quantity_zero() {
        XCTAssertEqual(number.quantity(0), 1)
    }

    // MARK: - nice

    func test_nice_extreme() {
        // Should not be 0.30000000000000004
        XCTAssertEqual(number.nice(0.3869394696651766, .round), 0.3)
        XCTAssertEqual(number.nice(0.3869394696651766), 0.5)
        XCTAssertEqual(number.nice(0.00003869394696651766, .round), 0.00003)
        XCTAssertEqual(number.nice(0.00003869394696651766, .none), 0.00005)
        XCTAssertEqual(number.nice(13, .round), 10)
        XCTAssertEqual(number.nice(13), 20)
        XCTAssertEqual(number.nice(3900000000000000000021, .round), 3000000000000000000000)
        XCTAssertEqual(number.nice(3900000000000000000021), 5000000000000000000000)
        XCTAssertEqual(number.nice(0.00000000000000000656939, .round), 0.000000000000000005)
        XCTAssertEqual(number.nice(0.00000000000000000656939), 0.00000000000000001)
        XCTAssertEqual(number.nice(0.10000000000000000656939, .round), 0.1)
        XCTAssertEqual(number.nice(0.10000000000000000656939), 0.2)
    }

    // MARK: - numeric (isNumeric / numericToNumber)

    private func testNumeric(_ rawVal: Any?, _ tarVal: Double, _ beNumeric: Bool,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(number.isNumeric(rawVal), beNumeric, "isNumeric(\(String(describing: rawVal)))",
                       file: file, line: line)
        assertNumEqual(number.numericToNumber(rawVal), tarVal,
                       "numericToNumber(\(String(describing: rawVal)))", file: file, line: line)
    }

    func test_numeric() {
        let inf = Double.infinity
        let nan = Double.nan
        let fullWidthSpace = String(UnicodeScalar(12288)!)

        testNumeric(123.0, 123, true)
        testNumeric("123", 123, true)
        testNumeric(-123.0, -123, true)
        testNumeric("555", 555, true)
        testNumeric("555.6", 555.6, true)
        testNumeric("0555.6", 555.6, true)
        testNumeric("-555.6", -555.6, true)
        testNumeric(" 555 ", 555, true)
        testNumeric(" -555 ", -555, true)
        testNumeric(1e3, 1000, true)
        testNumeric(-1e3, -1000, true)
        testNumeric("1e3", 1000, true)
        testNumeric("-1e3", -1000, true)
        testNumeric(" \r \n 555 \t ", 555, true)
        testNumeric(" \r \n -555.6 \t ", -555.6, true)
        testNumeric(inf, inf, true)
        testNumeric(-inf, -inf, true)
        testNumeric("Infinity", inf, true)
        testNumeric("-Infinity", -inf, true)

        testNumeric(nan, nan, false)
        testNumeric("NaN", nan, false)
        testNumeric("-NaN", nan, false)
        testNumeric(" NaN ", nan, false)
        testNumeric(true, nan, false)
        testNumeric(false, nan, false)
        testNumeric(nil, nan, false)
        testNumeric(Date(timeIntervalSince1970: 1339459200), nan, false)
        testNumeric([Any](), nan, false)
        testNumeric([String: Any](), nan, false)
        testNumeric("555a", nan, false)
        testNumeric("- 555", nan, false)
        testNumeric("0. 5", nan, false)
        testNumeric("0 .5", nan, false)
        testNumeric("0x11", nan, false)
        testNumeric("", nan, false)
        testNumeric("\n", nan, false)
        testNumeric("\n\r", nan, false)
        testNumeric("\t", nan, false)
        testNumeric(fullWidthSpace, nan, false)
        testNumeric({ () -> Void in }, nan, false)
    }

    // MARK: - getAcceptableTickPrecision

    func test_getAcceptableTickPrecision() {
        // We require `diff * pxSpan / dataSpan <= pxDiffAcceptable`.
        // The max `diff` is: `pow(10, -precision) / 2`.
        func calcMaxPxDiff(_ dataExtent: [Double], _ pxExtent: [Double], _ precision: Double) -> Double {
            return pow(10, -precision) / 2
                * Swift.abs(pxExtent[1] - pxExtent[0])
                / Swift.abs(dataExtent[1] - dataExtent[0])
        }

        let CASES: [[[Double]]] = [
            [[0, 1e-3], [0, 100]],
            [[0, 1e5], [0, 100]],
            [[0, 816.2050883836147], [0, 914.7923109827166]],
            [[0, 132.4279201671552], [0, 267.9399859644955]],
            [[0, 100.34020279327427], [0, 287.77043437322726]],
            [[0, 131.76288568225613], [0, 268.9583525845105]],
            [[0, 100.28571954202148], [0, 256.9972613326965]],
            [[0, 104.20905450687412], [0, 301.06863468545566]],
            [[0, 0.0000012212958760328775], [0, 30.161832948821356]],
            [[0, 1.0169256034269881e-7], [0, 293.5116394339741]],
            [[0, 0.0011105264071798859], [0, 222.30675252167865]],
            [[0, 0.00010498610084514804], [0, 264.6383246939843]]
        ]
        let NAN_CASES: [[[Double]]] = [
            [[0, 0], [0, 100]]
        ]

        for caseItem in CASES {
            let dataExtent = caseItem[0]
            let pxExtent = caseItem[1]
            let precision1 = number.getPixelPrecision(
                (dataExtent[0], dataExtent[1]),
                (pxExtent[0], pxExtent[1])
            )
            let precision2 = number.getAcceptableTickPrecision(
                dataExtent,
                pxExtent[1] - pxExtent[0],
                nil
            )
            let pxDiff1 = calcMaxPxDiff(dataExtent, pxExtent, precision1)
            let pxDiff2 = calcMaxPxDiff(dataExtent, pxExtent, precision2)
            XCTAssertTrue(pxDiff1.isFinite)   // May > 1 (bad case).
            XCTAssertLessThanOrEqual(pxDiff2, 1)
        }

        for caseItem in NAN_CASES {
            let dataExtent = caseItem[0]
            let pxExtent = caseItem[1]
            let precision2 = number.getAcceptableTickPrecision(
                dataExtent,
                pxExtent[1] - pxExtent[0],
                nil
            )
            let pxDiff2 = calcMaxPxDiff(dataExtent, pxExtent, precision2)
            XCTAssertTrue(pxDiff2.isNaN)
        }
    }
}
