// NativePainter — installs the `svgPatternRasterizer` renderer seam declared by ZRenderKit's
// parseSVG. ZRenderKit has no pixel backend, so it delegates rasterizing an SVG `<pattern>` content
// group to a raster tile across this seam. The native backend rasterizes the group with the same
// immediate-mode `CGRenderer` route used for snapshots (`renderToImage`) and encodes the result as a
// PNG `data:` URI — the exact `string`/data-URI arm that `CGRenderer.tilePattern` later decodes and
// tiles as a repeating `Pattern` fill.

import Foundation
#if canImport(CoreGraphics) && canImport(QuartzCore)
import CoreGraphics
import QuartzCore
#if canImport(ImageIO)
import ImageIO
#endif
import ZRenderKit

// Install once; idempotent. Referenced (not re-run) on every call.
private let _installOnce: Void = {
    svgPatternRasterizer = { group, width, height in
        #if canImport(ImageIO)
        let size = CGSize(width: width, height: height)
        // Transparent-background tile so the repeat leaves gaps between marks (matches an SVG pattern
        // whose content does not fill the whole tile).
        guard let img = renderToImage(group: group, size: size) else { return nil }
        return cgImageToPNGDataURI(img)
        #else
        return nil
        #endif
    }
}()

/// Install NativePainter's `svgPatternRasterizer` so `parseSVG` can resolve `<pattern>` paint servers
/// to image-tile `Pattern` fills. Idempotent. Called automatically the first time a `CALayerPainter`
/// is constructed (see `CALayerPainter.init`); call it directly if you parse SVG before any painter
/// exists.
public func installSVGPatternRasterizer() {
    _ = _installOnce
}

#if canImport(ImageIO)
/// Encode a `CGImage` to a base64 PNG `data:` URI (decoded back by `loadCGImage`).
private func cgImageToPNGDataURI(_ img: CGImage) -> String? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return "data:image/png;base64," + (data as Data).base64EncodedString()
}
#endif

#endif
