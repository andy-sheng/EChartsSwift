// Shared Core Graphics snapshot; no concrete painter or window is required.
import Foundation
import ZRenderKit
#if canImport(CoreGraphics)
import CoreGraphics

public func renderToImage(group: Element, size: CGSize, dpr: Double? = nil,
                          backgroundColor: CGColor? = nil) -> CGImage? {
    installNativePlatformAPI()
    installSVGPatternRasterizer()
    let scale = dpr ?? defaultDPR()
    guard scale.isFinite, scale > 0, size.width.isFinite, size.height.isFinite,
          size.width >= 0, size.height >= 0 else { return nil }
    let width = Int((size.width * scale).rounded())
    let height = Int((size.height * scale).rounded())
    guard let ctx = CGContext(
        data: nil, width: max(width, 1), height: max(height, 1),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    if let backgroundColor {
        ctx.setFillColor(backgroundColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: scale, y: -scale)
    renderScene(group, into: CGRenderer(ctx, flipped: true))
    return ctx.makeImage()
}
#endif
