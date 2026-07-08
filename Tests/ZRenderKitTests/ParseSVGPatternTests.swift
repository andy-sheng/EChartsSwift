// Proves the ported `parseSVG` resolves an SVG `<pattern>` paint server: a `<pattern>` defines a
// tiled graphic referenced via `fill="url(#id)"`. Upstream leaves `<pattern>` as a TODO; the port
// rasterizes the pattern content group to an image tile through the `svgPatternRasterizer` renderer
// seam (installed by NativePainter) and hands the shape a `ZRColor.pattern` fill.

import XCTest
@testable import ZRenderKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import NativePainter

final class ParseSVGPatternTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Install the native rasterizer seam so `<pattern>` resolves to an image-tile Pattern.
        installSVGPatternRasterizer()
    }

    private func parse(_ svg: String) -> SVGParserResult {
        return parseSVG(svg, SVGParserOption(ignoreViewBox: true, ignoreRootClip: true))
    }

    func test_pattern_fill_resolves_to_a_Pattern() throws {
        let svg = """
        <svg width="40" height="40">
          <defs>
            <pattern id="p" width="8" height="8">
              <rect x="0" y="0" width="8" height="8" fill="#ff0000"/>
            </pattern>
          </defs>
          <rect x="0" y="0" width="40" height="40" fill="url(#p)"/>
        </svg>
        """
        let result = parse(svg)
        let rect = try XCTUnwrap(result.root.childrenRef().first as? Rect,
                                 "the pattern-filled <rect> is the first child")

        // The referencing shape carries a Pattern fill (not a solid color / not the default black).
        guard case let .pattern(pattern)? = rect.pathStyle.fill else {
            return XCTFail("expected a Pattern fill on the rect, got \(String(describing: rect.pathStyle.fill))")
        }
        XCTAssertFalse(pattern.image.isEmpty, "the rasterized tile is carried as a data URI")
        XCTAssertTrue(pattern.image.hasPrefix("data:image/png;base64,"),
                      "the tile is a PNG data URI produced by the seam")
        XCTAssertEqual(pattern.repeat, .repeat)
    }

    #if canImport(CoreGraphics)
    func test_pattern_fill_renders_non_empty() throws {
        let svg = """
        <svg width="40" height="40">
          <defs>
            <pattern id="p" width="8" height="8">
              <rect x="0" y="0" width="8" height="8" fill="#ff0000"/>
            </pattern>
          </defs>
          <rect x="0" y="0" width="40" height="40" fill="url(#p)"/>
        </svg>
        """
        let result = parse(svg)
        let image = try XCTUnwrap(
            renderToImage(group: result.root, size: CGSize(width: 40, height: 40), dpr: 1),
            "the pattern-filled scene rasterizes to an image"
        )
        XCTAssertTrue(hasColoredPixels(image), "the tiled pattern fill produces non-empty (opaque) pixels")
    }

    /// True if the image has any pixel with non-zero alpha (something was actually painted).
    private func hasColoredPixels(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return false
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var i = 3
        while i < buf.count {
            if buf[i] != 0 { return true }
            i += 4
        }
        return false
    }
    #endif
}
