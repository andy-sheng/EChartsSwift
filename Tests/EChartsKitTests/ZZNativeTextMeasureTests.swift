// The layout engine must size text with the SAME font the painter draws it with.
//
// zrender's `platform.measureText` fell back to the no-canvas ASCII width table
// (DEFAULT_TEXT_WIDTH_MAP: digit = 0.56em) because `createCanvas` is a stub, while the renderer laid
// glyphs out with CTLine. Everything sized from text — legend boxes, grid.containLabel, label
// truncation, calculateCategoryInterval's tick thinning — used numbers the painter never honoured.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit
import NativePainter

final class ZZNativeTextMeasureTests: XCTestCase {

    override func setUp() {
        super.setUp()
        installNativeTextMeasure()
    }

    func testMeasureMatchesCoreTextNotTheAsciiTable() {
        let font = "normal normal 12px sans-serif"
        let measured = platformApi.measureText("2015/1/9", font).width
        // Table value would be 8 digits*0.56*12 + '/'*0.28*12 … = 47.04; Helvetica advances 46.7109,
        // which is also exactly what the browser oracle reports for the same string.
        XCTAssertEqual(measured, 46.7109, accuracy: 0.01,
                       "sans-serif must measure as Helvetica, matching what makeBaseFont draws with")
        XCTAssertNotEqual(measured, 47.04, accuracy: 0.001, "must not be the ASCII width table")
    }

    func testFontSizeScales() {
        let w12 = platformApi.measureText("00000", "12px sans-serif").width
        let w24 = platformApi.measureText("00000", "24px sans-serif").width
        XCTAssertEqual(w24, w12 * 2, accuracy: 0.01, "advance scales linearly with px size")
    }

    func testEmptyAndUnknownFontAreSafe() {
        XCTAssertEqual(platformApi.measureText("", "12px sans-serif").width, 0)
        XCTAssertGreaterThan(platformApi.measureText("abc", nil).width, 0, "nil font falls back to DEFAULT_FONT")
        XCTAssertGreaterThan(platformApi.measureText("abc", "totally bogus").width, 0)
    }

    func testUnavailableNamedFamilyUsesBrowserDefaultSerifFallback() {
        let text = "xAxis represents temperature in °C"
        let missing = platformApi.measureText(text, "14px Microsoft YaHei").width
        let browserFallback = platformApi.measureText(text, "14px Times New Roman").width
        XCTAssertEqual(missing, browserFallback, accuracy: 0.01,
                       "a missing sole named CSS family must fall back like WebKit, not Core Text's Helvetica substitution")
    }

    func testCjkFallsBackToAFontThatHasTheGlyphs() {
        // Helvetica carries no CJK glyphs, so Core Text substitutes; a full-width char advances one em.
        // That happens to equal the ASCII table's per-char fontSize guess, so this asserts the
        // SUBSTITUTION works rather than trying to distinguish the two paths by width.
        let w = platformApi.measureText("国国", "12px sans-serif").width
        XCTAssertEqual(w, 24.0, accuracy: 0.01, "two full-width chars advance two ems")
        // A mixed string must be the sum of its parts — proves per-run substitution, not a per-char guess.
        let mixed = platformApi.measureText("国a", "12px sans-serif").width
        let latin = platformApi.measureText("a", "12px sans-serif").width
        XCTAssertEqual(mixed, 12.0 + latin, accuracy: 0.01,
                       "the latin half keeps Helvetica metrics (\(latin)pt), not a 12pt-per-char guess")
    }
}
