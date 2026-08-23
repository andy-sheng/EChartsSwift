import XCTest
import EChartsDemoCore

final class InteractionTimerHarnessTests: XCTestCase {
    func testSnapshotCanCaptureDemoIntervalsForExplicitLogicalTicks() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-scatter-symbol-morph"))
        let page = try XCTUnwrap(
            echartsHTMLPage(demo, snapshot: true, captureIntervals: true)
        )

        XCTAssertTrue(page.contains("var __captureIntervals = true;"))
        XCTAssertTrue(page.contains("window.__capturedIntervals.push(body);"))
        XCTAssertTrue(page.contains("setInterval(function ()"), "official timer body stays in page")
    }

    func testOrdinarySnapshotDoesNotEnableIntervalCapture() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-scatter-symbol-morph"))
        let page = try XCTUnwrap(echartsHTMLPage(demo, snapshot: true))

        XCTAssertTrue(page.contains("var __captureIntervals = false;"))
    }
}
