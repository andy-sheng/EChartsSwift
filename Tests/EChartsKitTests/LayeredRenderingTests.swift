// Per-zlevel LAYERED rendering (faithful to zrender canvas/Layer.ts). A chart that calls
// `configLayer(zlevel, {motionBlur})` — only the lines flying-trail effect does — makes CALayerPainter
// composite each distinct zlevel into its OWN sublayer, and motion-blur (previous frame retained at
// lastFrameAlpha) applies ONLY to the configured zlevel, so the effect trail fades on its own layer
// while the axes / other series (lower zlevel) stay crisp. Charts that never call configLayer keep the
// single-buffer fast path (unchanged). These tests exercise the painter logic headlessly + the
// EChartsView host wiring (LinesView effect → zr.configLayer, applied after _syncRoot like roam).
#if canImport(QuartzCore) && canImport(CoreGraphics)
import XCTest
import CoreGraphics
@testable import EChartsKit
@testable import ZRenderKit
import NativePainter

final class LayeredRenderingTests: XCTestCase {

    // A full-height filled Rect at x∈[x, x+w] on the given zlevel (full height → sampling only reasons
    // about the x column, sidestepping the y-flip).
    private func fullHeightRect(x: Double, w: Double, h: Double, fill: String, zlevel: Double) -> Rect {
        var s = RectShape(); s.x = x; s.y = 0; s.width = w; s.height = h
        let r = Rect(); r.setShape(s)
        var st = PathStyleProps(); st.fill = .string(fill); r.useStyle(st)
        r.zlevel = zlevel
        return r
    }

    // Alpha (0…255) of a device pixel, top-left origin. Full-height rects cover all rows, so any row works.
    private func alphaAt(_ img: CGImage, _ px: Int, _ py: Int) -> Int {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (py * w + px) * 4
        return Int(buf[i + 3])
    }

    // MARK: painter logic (headless)

    func testNoConfigLayerKeepsSingleLayerFastPath() {
        let painter = CALayerPainter(size: CGSize(width: 100, height: 100), dpr: 1)
        painter.refresh([
            fullHeightRect(x: 10, w: 20, h: 100, fill: "#3366ff", zlevel: 0),
            fullHeightRect(x: 60, w: 20, h: 100, fill: "#ff3333", zlevel: 1)
        ])
        // No configLayer → single rootLayer.contents bitmap, no per-zlevel sublayers.
        XCTAssertEqual(painter._testZSublayerCount, 0, "single-layer fast path builds no per-zlevel sublayers")
        XCTAssertNotNil(painter.rootLayer.contents, "single-layer path publishes rootLayer.contents")
    }

    func testConfigLayerSwitchesToPerZLevelPath() {
        let painter = CALayerPainter(size: CGSize(width: 100, height: 100), dpr: 1)
        painter.configLayer(1, LayerConfig(motionBlur: true, lastFrameAlpha: 0.9))
        painter.refresh([
            fullHeightRect(x: 10, w: 20, h: 100, fill: "#3366ff", zlevel: 0),
            fullHeightRect(x: 60, w: 20, h: 100, fill: "#ff3333", zlevel: 1)
        ])
        XCTAssertTrue(painter._testLayerConfigured(1), "zlevel 1 is motion-blur configured")
        XCTAssertEqual(painter._testZSublayerCount, 2, "two distinct zlevels → two sublayers")
        // Only the configured zlevel retains a frame for the next composite.
        XCTAssertTrue(painter._testHasRetainedFrame(1), "motion-blur zlevel retains its frame")
        XCTAssertFalse(painter._testHasRetainedFrame(0), "non-motion-blur zlevel does not retain")
    }

    /// The crux: on the motion-blur layer, a moved element leaves a fading trail — the retained frame
    /// after frame 2 has color at BOTH the OLD and the NEW column. A non-blur layer would show only NEW.
    func testTrailAccumulatesOnMotionBlurLayer() {
        let painter = CALayerPainter(size: CGSize(width: 100, height: 100), dpr: 1)
        painter.configLayer(1, LayerConfig(motionBlur: true, lastFrameAlpha: 0.9))

        // Frame 1: base rect at zlevel 0 (col ~15), effect dot at zlevel 1 (col ~15).
        painter.refresh([
            fullHeightRect(x: 10, w: 10, h: 100, fill: "#3366ff", zlevel: 0),
            fullHeightRect(x: 10, w: 10, h: 100, fill: "#ff3333", zlevel: 1)
        ])
        // Frame 2: base unchanged, effect dot MOVED to col ~65.
        painter.refresh([
            fullHeightRect(x: 10, w: 10, h: 100, fill: "#3366ff", zlevel: 0),
            fullHeightRect(x: 60, w: 10, h: 100, fill: "#ff3333", zlevel: 1)
        ])

        let trailImg = try? XCTUnwrap(painter._testRetainedFrameImage(1))
        guard let trail = trailImg ?? nil else { return XCTFail("motion-blur layer retained no frame") }
        // Both the old (15) and the new (65) columns carry color → the dot left a trail.
        XCTAssertGreaterThan(alphaAt(trail, 15, 50), 0, "faded OLD dot position still present (trail)")
        XCTAssertGreaterThan(alphaAt(trail, 65, 50), 0, "NEW dot position present")

        // The base (non-blur) layer only shows its current content — its retained frame is nil.
        XCTAssertFalse(painter._testHasRetainedFrame(0), "base layer does not accumulate a trail")
    }

    func testConfigLayerOffRevertsToSingleLayer() {
        let painter = CALayerPainter(size: CGSize(width: 100, height: 100), dpr: 1)
        painter.configLayer(1, LayerConfig(motionBlur: true, lastFrameAlpha: 0.9))
        painter.refresh([fullHeightRect(x: 60, w: 20, h: 100, fill: "#ff3333", zlevel: 1)])
        XCTAssertEqual(painter._testZSublayerCount, 1)
        // Turn the effect off → next refresh takes the single-layer path, sublayers torn down.
        painter.configLayer(1, LayerConfig(motionBlur: false))
        painter.refresh([fullHeightRect(x: 60, w: 20, h: 100, fill: "#ff3333", zlevel: 1)])
        XCTAssertFalse(painter._testLayerConfigured(1), "motionBlur:false clears the config")
        XCTAssertEqual(painter._testZSublayerCount, 0, "reverts to single-layer, sublayers removed")
    }

    // MARK: EChartsView host wiring

    func testLinesEffectConfiguresLayerViaHost() {
        let painter = CALayerPainter(size: CGSize(width: 480, height: 320), dpr: 1)
        let view = EChartsView(width: 480, height: 320, painter: painter)
        view.setOption([
            "xAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [[
                "type": "lines", "coordinateSystem": "cartesian2d", "zlevel": 1.0,
                "effect": ["show": true, "trailLength": 0.6, "symbol": "circle", "symbolSize": 8.0] as [String: Any],
                "data": [["coords": [[2.0, 2.0], [8.0, 12.0]]] as [String: Any]]
            ] as [String: Any]]
        ])
        // The host configured a motion-blur layer at the lines series' zlevel (1). lastFrameAlpha =
        //   clamp(trailLength/10 + 0.9) = clamp(0.06 + 0.9) = 0.96.
        XCTAssertTrue(painter._testLayerConfigured(1),
                      "lines series with effect+trailLength must configure a motion-blur layer at its zlevel")
    }

    func testLinesEffectOffDoesNotConfigureLayer() {
        let painter = CALayerPainter(size: CGSize(width: 480, height: 320), dpr: 1)
        let view = EChartsView(width: 480, height: 320, painter: painter)
        view.setOption([
            "xAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 20.0] as [String: Any],
            "series": [[
                "type": "lines", "coordinateSystem": "cartesian2d", "zlevel": 1.0,
                "data": [["coords": [[2.0, 2.0], [8.0, 12.0]]] as [String: Any]]
            ] as [String: Any]]
        ])
        XCTAssertFalse(painter._testLayerConfigured(1),
                       "lines series with NO effect must not motion-blur its layer")
    }
}
#endif
