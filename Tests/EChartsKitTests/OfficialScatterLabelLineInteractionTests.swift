import XCTest
@testable import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialScatterLabelLineInteractionTests: XCTestCase {
    func testAttachedLabelLineUsesItsOwnDefaultBlurState() throws {
        let demo = EChartsDemoRegistry.official_scatter_label_align_right
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        var host: Element?
        var guide: Polyline?
        _ = view.ec.getRoot().traverse { candidate in
            if guide == nil, let line = candidate.getTextGuideLine() {
                host = candidate
                guide = line
            }
            return false
        }
        let target = try XCTUnwrap(host)
        let labelLine = try XCTUnwrap(guide)
        XCTAssertNil(labelLine.states["blur"]?.style?["opacity"])
        let resolvedBlur = try XCTUnwrap(labelLine.stateProxy?("blur", ["blur"]))
        XCTAssertEqual(try XCTUnwrap(resolvedBlur.style?["opacity"] as? Double), 0.1, accuracy: 0.0001)

        states.enterBlur(target)
        states.applyElementStates(target)
        _ = labelLine.stopAnimation(nil, true)
        XCTAssertTrue(labelLine.currentStates.contains("blur"))
        XCTAssertEqual(try XCTUnwrap(labelLine.pathStyle?.opacity), 0.1, accuracy: 0.0001)

        states.leaveBlur(target)
        states.applyElementStates(target)
        _ = labelLine.stopAnimation(nil, true)
        XCTAssertFalse(labelLine.currentStates.contains("blur"))
        XCTAssertEqual(try XCTUnwrap(labelLine.pathStyle?.opacity), 1, accuracy: 0.0001)
    }
}
