// Unit test for the ported blur `HeatmapLayer` (chart/heatmap/HeatmapBlurLayer.swift) — the smooth
// gradient heat-blob renderer used by the geo heatmap path (`HeatmapView._renderOnGeo`).
//
// Mirrors upstream's `HeatmapLayer.update(points, w, h, normalize, colorFunc, isInRange)`: a set of
// [x, y, value] points is stamped as radial-alpha blobs, then the accumulated alpha is colorized by
// the visualMap gradient (`color.fastLerp` — the SAME function upstream's `colorFunc[state]` uses).
// The KEY assertions: the layer produces a non-empty COLORED output (opaque pixels), those colors
// span the gradient (>= 2 distinct rgb values across the value range), a single hot point lands its
// blob near the point (falloff shape), and the produced buffer wraps as a `CGImage`.
import XCTest
import CoreGraphics
import ZRenderKit
@testable import EChartsKit

final class HeatmapBlurLayerTests: XCTestCase {

    // A blue → yellow → red gradient (rgba arrays, matching the visualMap color-mapper `out` format).
    private let gradientColors: [[Double]] = [
        [49, 54, 149, 1],     // #313695 (cold)
        [255, 255, 191, 1],   // #ffffbf (mid)
        [165, 0, 38, 1]       // #a50026 (hot)
    ]

    // A ColorMapper equivalent to the visualMap `color` handler's fast (rgb-array) path.
    private func makeColorMapper() -> ColorMapper {
        let colors = gradientColors
        return { value, _isNormalized, out in
            let v = (value as? Double) ?? 0
            return (color.fastLerp(v, colors, out) ?? [0, 0, 0, 0]) as Any
        }
    }

    func testProducesNonEmptyColoredBlobs() {
        let layer = HeatmapLayer()
        layer.pointSize = 8
        layer.blurSize = 12
        layer.minOpacity = 0
        layer.maxOpacity = 1

        let mapper = makeColorMapper()
        let colorFunc: [String: ColorMapper] = ["inRange": mapper, "outOfRange": mapper]
        // value in [0, 10] → normalized alpha in [0, 1].
        let normalize: (Double) -> Double = { v in Swift.max(0, Swift.min(1, v / 10)) }
        let points: [[Double]] = [
            [30, 30, 10],   // hot
            [70, 50, 5],    // mid
            [50, 90, 2]     // cold
        ]

        let img = layer.update(points, 120, 120, normalize, colorFunc, { _ in true })

        XCTAssertNotNil(img, "the layer must produce a CGImage of the colorized canvas")
        XCTAssertEqual(layer.width, 120)
        XCTAssertEqual(layer.height, 120)
        XCTAssertEqual(layer.pixels.count, 120 * 120 * 4)

        var opaqueCount = 0
        var distinctColors = Set<UInt32>()
        for i in stride(from: 0, to: layer.pixels.count, by: 4) {
            let a = layer.pixels[i + 3]
            if a > 0 {
                opaqueCount += 1
                let key = (UInt32(layer.pixels[i]) << 16)
                    | (UInt32(layer.pixels[i + 1]) << 8)
                    | UInt32(layer.pixels[i + 2])
                distinctColors.insert(key)
            }
        }

        XCTAssertGreaterThan(opaqueCount, 0, "the heat blobs must produce opaque colored pixels")
        XCTAssertGreaterThanOrEqual(
            distinctColors.count, 2,
            "the visualMap gradient must map different accumulated alphas to different colors"
        )
    }

    func testSingleBlobIsHottestAtCenter() {
        let layer = HeatmapLayer()
        layer.pointSize = 6
        layer.blurSize = 10
        let mapper = makeColorMapper()
        let colorFunc: [String: ColorMapper] = ["inRange": mapper, "outOfRange": mapper]
        let normalize: (Double) -> Double = { _ in 1 }  // full alpha stamp

        let cx = 50, cy = 50
        _ = layer.update([[Double(cx), Double(cy), 1]], 100, 100, normalize, colorFunc, { _ in true })

        func alphaAt(_ x: Int, _ y: Int) -> Int {
            Int(layer.pixels[(y * layer.width + x) * 4 + 3])
        }
        // Center is opaque; a point well outside pointSize+blurSize is transparent.
        XCTAssertGreaterThan(alphaAt(cx, cy), 0, "blob center must be opaque")
        XCTAssertEqual(alphaAt(cx, cy), 255, "blob center (alpha 1) must colorize to full opacity")
        XCTAssertEqual(alphaAt(5, 5), 0, "far-away pixels must remain transparent")
        // Falloff: the center is at least as opaque as a pixel near the blur edge.
        XCTAssertGreaterThanOrEqual(alphaAt(cx, cy), alphaAt(cx + 14, cy), "alpha must fall off outward")
    }

    func testEmptyCanvasReturnsNil() {
        let layer = HeatmapLayer()
        let mapper = makeColorMapper()
        let colorFunc: [String: ColorMapper] = ["inRange": mapper, "outOfRange": mapper]
        let img = layer.update([[10, 10, 1]], 0, 0, { _ in 1 }, colorFunc, { _ in true })
        XCTAssertNil(img, "a zero-size canvas produces no image (upstream guards getImageData)")
    }
}
