import XCTest
import ZRenderKit
@testable import EChartsDemoCore
@testable import EChartsKit

final class OfficialCandlestickSH2015InteractionTests: XCTestCase {
    private func namedEasing(_ clip: Clip) -> String? {
        guard case .named(let name)? = clip.easing else { return nil }
        return name
    }

    func testRapidMouseWheelKeepsCandlesAndMovingAveragesOnRealtimeTransition() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-candlestick-sh-2015"))
        let view = EChartsView(width: demo.width, height: demo.height)
        defer { view.dispose() }
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        // Remove entrance animations so every animator observed below belongs to the real wheel update.
        _ = view.ec.getRoot().traverse { el in
            _ = el.stopAnimation(nil)
            return false
        }

        let candlestick = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0))
        let cartesian = try XCTUnwrap(candlestick.coordinateSystem as? Cartesian2D)
        let rect = cartesian.getArea()
        view._injectWheelForTest(
            zrDelta: 1,
            zrX: rect.x + rect.width / 2,
            zrY: rect.y + rect.height / 2
        )

        var candleClips: [Clip] = []
        var movingAverageClips: [Clip] = []
        _ = view.ec.getRoot().traverse { el in
            if let candle = el as? NormalBoxPath,
               let clip = candle.animators.first(where: {
                   $0.targetName == "shape" && $0.getTrack("points") != nil
               })?.getClip() {
                candleClips.append(clip)
            }
            if let line = el as? ECPolyline, line.name == "line",
               let clip = line.animators.first(where: { $0.getTrack("points") != nil })?.getClip() {
                movingAverageClips.append(clip)
            }
            return false
        }

        XCTAssertFalse(candleClips.isEmpty, "wheel dataZoom must morph reused candlestick point geometry")
        XCTAssertEqual(movingAverageClips.count, 4, "all four official moving averages must morph")
        for clip in candleClips + movingAverageClips {
            XCTAssertEqual(namedEasing(clip), "cubicOut")
            XCTAssertTrue(
                clip.sampleForDeterministicRendering(at: 100),
                "candles and moving averages must finish the same upstream 100ms realtime transition"
            )
        }
    }
}
