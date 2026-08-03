// number.round / roundStr must reproduce JS Number.prototype.toFixed, TIES INCLUDED.
// String(format:) rounds ties to even on the exact binary value; toFixed rounds ties away from zero.
// AxisProxy rounds the dataZoom percent→ordinal window through round(x, 0), so at a *.5 tie the
// native window ended one category earlier than real echarts (grid-multiple: 0.75*(3079-1)=2308.5 →
// printf 2308, JS 2309) and the last bar/candle of the window vanished.
// Reference values pinned with node: (2308.5).toFixed(0)=2309 (2307.5)=2308 (-2308.5)=-2309
// (1.005).toFixed(2)="1.00" (0.125).toFixed(2)="0.13" (-0.0004).toFixed(2)="-0.00" (-0.4).toFixed(0)="-0"
import XCTest
@testable import EChartsKit

final class ZZNumberRoundTiesTests: XCTestCase {
    func testTiesRoundAwayFromZeroLikeToFixed() {
        XCTAssertEqual(number.round(2308.5, 0), 2309, "the exact tie that shifted grid-multiple's dataZoom window")
        XCTAssertEqual(number.round(2307.5, 0), 2308, "ties round UP, not to even (printf agrees here by luck)")
        XCTAssertEqual(number.round(-2308.5, 0), -2309, "away from zero on the negative side")
        XCTAssertEqual(number.roundStr(0.125, 2), "0.13", "0.125 is exactly representable — a true tie")
    }

    func testNonTiesKeepJsBehaviour() {
        // 1.005 is really 1.00499999… in binary; JS's own PENDING comment: toFixed(2) is "1.00".
        XCTAssertEqual(number.roundStr(1.005, 2), "1.00")
        XCTAssertEqual(number.roundStr(1.0049, 2), "1.00")
        XCTAssertEqual(number.roundStr(1.006, 2), "1.01")
        XCTAssertEqual(number.roundStr(5.0, 2), "5.00", "plain formatting unchanged")
        XCTAssertEqual(number.round(3.14159, 2), 3.14)
    }

    func testSignOfZeroResults() {
        XCTAssertEqual(number.roundStr(-0.0004, 2), "-0.00", "JS keeps the value's sign")
        XCTAssertEqual(number.roundStr(-0.4, 0), "-0")
        XCTAssertEqual(number.roundStr(0.0004, 2), "0.00")
        XCTAssertEqual(number.roundStr(-0.0, 2), "0.00", "literal -0 prints unsigned in JS")
    }

    func testCarryPropagation() {
        XCTAssertEqual(number.roundStr(9.995, 2), "9.99", "9.995 is 9.99499… in binary — below the tie, JS gives 9.99")
        XCTAssertEqual(number.roundStr(0.375, 2), "0.38", "0.375 is an exact tie — carry inside the fraction")
        XCTAssertEqual(number.roundStr(9.9951, 2), "10.00", "carry across the decimal point into the integer")
        XCTAssertEqual(number.roundStr(99.999, 2), "100.00")
        XCTAssertEqual(number.round(0.5, 0), 1)
        XCTAssertEqual(number.round(1.5, 0), 2)
        XCTAssertEqual(number.round(2.5, 0), 3, "printf would give 2 — the distinguishing case")
    }
}
