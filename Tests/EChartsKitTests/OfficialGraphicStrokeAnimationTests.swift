import XCTest
import ZRenderKit
import NativePainter
import EChartsDemoCore
@testable import EChartsKit

final class OfficialGraphicStrokeAnimationTests: XCTestCase {
    func testOfficialStrokeDemoCarriesAndRunsItsStyleKeyframes() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-graphic-stroke-animation"))
        let graphic = try XCTUnwrap(demo.option["graphic"] as? [String: Any])
        let elements = try XCTUnwrap(graphic["elements"] as? [[String: Any]])
        let animation = try XCTUnwrap(elements.first?["keyframeAnimation"] as? [String: Any])
        XCTAssertEqual(animation["duration"] as? Double, 3_000)
        XCTAssertEqual(animation["loop"] as? Bool, true)

        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)

        var text: ZRText?
        _ = view.ec.getRoot().traverse { element in
            if let candidate = element as? ZRText,
               candidate.textStyle?.text == "Apache ECharts" {
                text = candidate
            }
            return false
        }
        let renderedText = try XCTUnwrap(text)
        let styleAnimator = try XCTUnwrap(renderedText.animators.first {
            $0.scope == "keyframe"
                && $0.targetName == "style"
                && $0.getTrack("lineDash") != nil
                && $0.getTrack("lineDashOffset") != nil
                && $0.getTrack("fill") != nil
        })
        let clip = try XCTUnwrap(styleAnimator.getClip())

        clip.resetForDeterministicSampling()
        clip.sampleForDeterministicRendering(at: 0)
        XCTAssertEqual(try XCTUnwrap(renderedText.textStyle?.lineDashOffset), 0, accuracy: 1e-9)
        XCTAssertEqual(lineDashValues(renderedText), [0, 200])
        XCTAssertEqual(renderedText.textStyle?.fill, "rgba(0,0,0,0)")
        assertRenderedTextStroke(renderedText, dash: [0, 200], offset: 0)

        clip.resetForDeterministicSampling()
        clip.sampleForDeterministicRendering(at: 2_100)
        XCTAssertEqual(try XCTUnwrap(renderedText.textStyle?.lineDashOffset), 200, accuracy: 1e-9)
        XCTAssertEqual(lineDashValues(renderedText), [200, 0])
        XCTAssertEqual(renderedText.textStyle?.fill, "rgba(0,0,0,0)")
        assertRenderedTextStroke(renderedText, dash: [200, 0], offset: 200)

        clip.resetForDeterministicSampling()
        clip.sampleForDeterministicRendering(at: 2_700)
        XCTAssertNotEqual(renderedText.textStyle?.fill, "rgba(0,0,0,0)")
    }

    private func lineDashValues(_ text: ZRText) -> [Double]? {
        guard case .some(.values(let values)) = text.textStyle?.lineDash else { return nil }
        return values
    }

    private func assertRenderedTextStroke(
        _ text: ZRText,
        dash expectedDash: [Double],
        offset expectedOffset: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        text.update()
        guard let tspan = text.childrenRef().compactMap({ $0 as? TSpan }).first,
              let style = tspan.tspanStyle else {
            XCTFail("Expected the animated ZRText to produce a TSpan", file: file, line: line)
            return
        }
        let paint = TextStyle.from(style)
        XCTAssertEqual(paint.lineDash, expectedDash, file: file, line: line)
        XCTAssertEqual(paint.lineDashOffset, expectedOffset, accuracy: 1e-9, file: file, line: line)
    }
}
