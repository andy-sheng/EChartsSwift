// NativePainter — installs a Core Text backing for ZRenderKit's `platform.measureText` seam
// (upstream zrender/src/core/platform.ts). Companion to NativePlatformAPI.swift's `loadImage`
// override; merged the same way, via `setPlatformAPI`'s per-key partial merge.
//
// WHY. `DefaultPlatformAPI.createCanvas()` is a stub returning nil, so `measureText` always took
// upstream's NO-CANVAS fallback: the hardcoded ASCII width-ratio table `DEFAULT_TEXT_WIDTH_MAP`
// (digit = 0.56em, '/' = 0.28em). That table is upstream's approximation for环境 without a canvas —
// but this port DOES have real font metrics, it just never wired them up. Two consequences:
//
//   1. Measurement disagreed with RENDERING. The renderer lays glyphs out with `makeCTFont()` +
//      CTLine; the layout engine sized labels from the table. Every consumer of text width — legend
//      sizing, `grid.containLabel`, label overflow/truncation, and `calculateCategoryInterval` —
//      was working off numbers the painter never honoured.
//   2. It surfaced as a corpus-wide oracle divergence. `calculateCategoryInterval` computes
//      `interval = floor(maxLabelWidth * 1.3 / unitSpan)`; a systematic ~0.5-0.7% width error flips
//      that floor at integer boundaries, so the whole category-axis label SET shifts (different
//      dates, count off by one). Baselines agreed only by floor luck; a dataZoom action moved the
//      quotient onto a boundary and the divergence appeared (candlestick-sh-2015, custom-ohlc).
//
// FONT RESOLUTION IS SHARED WITH THE PAINTER — `measuringCTFont(for:)` funnels into the same
// `parseCSSFont` + `makeBaseFont` the renderer uses, so measurement and rendering can never drift
// apart again. That self-consistency is the invariant; matching any particular reference platform's
// font choice is a separate question, handled in `makeBaseFont`.

import Foundation
#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
import ZRenderKit

/// Resolve a zrender font shorthand ("normal normal 12px sans-serif") to the CTFont the PAINTER
/// would draw it with. Cached: measurement is on the layout hot path (per label, per render).
private final class MeasuringFontCache {
    static let shared = MeasuringFontCache()
    private var cache: [String: CTFont] = [:]
    private let lock = NSLock()

    func font(for fontString: String) -> CTFont {
        lock.lock(); defer { lock.unlock() }
        if let f = cache[fontString] { return f }
        let parsed = parseCSSFont(fontString)
        let size = parsed.size != 0 ? parsed.size : DEFAULT_FONT_SIZE
        var f = makeBaseFont(parsed.family ?? DEFAULT_FONT_FAMILY, size: CGFloat(size))
        var traits: CTFontSymbolicTraits = []
        if parsed.bold { traits.insert(.traitBold) }
        if parsed.italic { traits.insert(.traitItalic) }
        if !traits.isEmpty,
           let styled = CTFontCreateCopyWithSymbolicTraits(f, CGFloat(size), nil, traits, traits) {
            f = styled
        }
        cache[fontString] = f
        return f
    }
}

/// Typographic advance of `text` in `font`, i.e. what the painter's own `CTLineCreateWithAttributedString`
/// will advance by — the Core Text analogue of canvas `ctx.measureText(text).width`.
func nativeMeasureTextWidth(_ text: String, _ font: String?) -> Double {
    if text.isEmpty { return 0 }
    let ctFont = MeasuringFontCache.shared.font(for: font ?? DEFAULT_FONT)
    let attr = NSAttributedString(
        string: text,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): ctFont]
    )
    let line = CTLineCreateWithAttributedString(attr)
    return Double(CTLineGetTypographicBounds(line, nil, nil, nil))
}

private let _installMeasureOnce: Void = {
    setPlatformAPI(PartialPlatformAPI(measureText: { text, font in
        TextMetrics(width: nativeMeasureTextWidth(text, font))
    }))
}()

/// Install the Core Text backing for `platform.measureText`. Idempotent.
///
/// Called from `installNativePlatformAPI()` so every consumer that already installs the native
/// platform backing gets real metrics, and separately from `ECharts`'s own bootstrap — the headless
/// paths (scene-graph oracle, tests) never build a `CALayerPainter`, and text measurement must not
/// depend on a painter having been constructed.
public func installNativeTextMeasure() {
    _ = _installMeasureOnce
}

#endif
