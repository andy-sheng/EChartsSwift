import XCTest
import ZRenderKit
import NativePainter
#if canImport(CoreGraphics)
import CoreGraphics

final class CGRectBatchTests: XCTestCase {
    private func context() -> CGContext {
        CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private func pixels(_ context: CGContext) -> Data {
        context.makeImage()!.dataProvider!.data! as Data
    }

    func testOpaqueCompoundBatchMatchesOneCompoundPathIncludingSubpixelEdges() {
        let rects = (0..<32).map { CGRect(x: 5.25 + Double($0) * 0.02, y: 8.2 + Double($0 % 7), width: 1.38, height: 40.5) }
        let packed = rects.flatMap { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
        let actual = context(), expected = context()
        var paint = PaintStyle(); paint.fill = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        CGRenderer(actual, flipped: false).fillBoostRects(packed, paint, compound: true)
        expected.setFillColor(paint.fill!)
        expected.addRects(rects); expected.fillPath()
        XCTAssertEqual(pixels(actual), pixels(expected))
    }

    func testIndependentOrTranslucentRectanglesKeepPerPointAlphaAccumulation() {
        let rect = CGRect(x: 5.25, y: 8.2, width: 3.38, height: 40.5)
        let packed = Array(repeating: [5.25, 8.2, 3.38, 40.5], count: 64).flatMap { $0 }
        for (compound, colorAlpha, opacity) in [(false, 1.0, 1.0), (true, 0.4, 1.0), (true, 1.0, 0.4)] {
            let actual = context(), expected = context()
            var paint = PaintStyle(); paint.fill = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: colorAlpha)
            paint.opacity = opacity
            actual.setAlpha(opacity); expected.setAlpha(opacity)
            CGRenderer(actual, flipped: false).fillBoostRects(packed, paint, compound: compound)
            expected.setFillColor(paint.fill!)
            for _ in 0..<64 { expected.fill(rect) }
            XCTAssertEqual(pixels(actual), pixels(expected))
        }
    }

    func testMissingValuesAndPartialFinalBatchDoNotDropValidBars() {
        var packed: [Double] = []
        for i in 0..<35 { packed += [Double(i * 2), 10, 2, i == 12 ? .nan : 20] }
        let actual = context(), expected = context()
        var paint = PaintStyle(); paint.fill = CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        CGRenderer(actual, flipped: false).fillBoostRects(packed, paint, compound: true)
        expected.setFillColor(paint.fill!)
        for i in 0..<35 where i != 12 { expected.fill(CGRect(x: i * 2, y: 10, width: 2, height: 20)) }
        XCTAssertEqual(pixels(actual), pixels(expected))
    }
}
#endif
