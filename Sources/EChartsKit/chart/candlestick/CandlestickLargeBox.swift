// CandlestickLargeBox — port of chart/candlestick/CandlestickView.ts's large-mode draw path
// (`LargeBoxPath` + `createLarge` + `setLargeStyle`). When a candlestick series is large
// (`pipelineContext.large`), it is drawn NOT as one NormalBoxPath per candle but as THREE
// `LargeBoxPath`s — one per sign (up +1 / down -1 / doji 0) — each stroking every matching candle as a
// single vertical low→high line over the flat `largePoints` buffer (`[sign, x, yLow, yHigh, ...]`,
// produced by candlestickLayout.swift's `largeProgress`). This is the SAME representation echarts'
// canvas large mode paints (thin high-low lines, not full bodies), so the native pane now matches the
// web pane's large render. The port previously stubbed `createLarge` to a no-op; once updateStreamModes
// activates `pipelineContext.large`, that stub left the candles blank — this file replaces it.
import Foundation
import ZRenderKit

// upstream: class LargeBoxPathShape { points: ArrayLike<number>; }
public struct LargeBoxPathShape: PathShape {
    public var points: [Double] = []
    public init() {}
}

// upstream: class LargeBoxPath extends Path — one path per sign; `buildPath` strokes a vertical line
//   (moveTo(x, yLow) → lineTo(x, yHigh)) for every 4-tuple whose leading `sign` equals `__sign`.
public final class LargeBoxPath: Path {
    public var __sign: Double = 0

    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "largeCandlestickBox"
    }

    public override func getDefaultShape() -> PathShape {
        return LargeBoxPathShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        guard let shape = shapeIn as? LargeBoxPathShape else { return }
        let points = shape.points
        var i = 0
        while i + 3 < points.count {
            let sign = points[i]; i += 1
            if sign == self.__sign {
                let x = points[i]; i += 1
                _ = ctx.moveTo(x, points[i]); i += 1
                _ = ctx.lineTo(x, points[i]); i += 1
            } else {
                i += 3
            }
        }
    }

    // A stroked vertical line of width `lineWidth` is geometrically a filled rect of that width — so the
    //   large candlestick takes the same per-primitive fill "boost" the scatter/bar large paths use,
    //   sidestepping Core Graphics' super-linear `strokePath`/`fillPath` over one N-sub-path path. The
    //   painter fills each rect with `style.fill`, so setLargeStyle puts the border color THERE (not on
    //   stroke); `boostLineWidth` is the line/rect width. Always boostable (a candle line is a rect).
    public var boostLineWidth: Double = 1

    public override func largeSymbolBoostRects() -> [Double]? {
        guard let shape = self.shape as? LargeBoxPathShape else { return nil }
        let points = shape.points
        guard !points.isEmpty else { return nil }
        let w = boostLineWidth <= 0 ? 1 : boostLineWidth
        let hw = w / 2
        var out = [Double]()
        out.reserveCapacity(points.count)   // ~1 rect (4 numbers) per 4-number candle
        var i = 0
        while i + 3 < points.count {
            let sign = points[i]; i += 1
            if sign == self.__sign {
                let x = points[i]; i += 1
                let y0 = points[i]; i += 1
                let y1 = points[i]; i += 1
                if x.isNaN || y0.isNaN || y1.isNaN { continue }
                let top = Swift.min(y0, y1)
                out.append(x - hw); out.append(top); out.append(w); out.append(Swift.abs(y1 - y0))
            } else {
                i += 3
            }
        }
        return out
    }
}

// upstream: function createLarge(seriesModel, group, ...) — three LargeBoxPaths (sign 1 / -1 / 0) over
//   the shared `largePoints`, each styled by `setLargeStyle`.
func candlestickCreateLarge(_ seriesModel: CandlestickSeriesModel, _ group: ZRenderKit.Group) {
    let data = seriesModel.getData()
    let largePoints = (data.getLayout("largePoints") as? [Double]) ?? []
    for sign in [1.0, -1.0, 0.0] {
        let el = LargeBoxPath()
        var shape = LargeBoxPathShape()
        shape.points = largePoints
        el.setShape(shape)
        el.__sign = sign
        el.ignoreCoarsePointer = true
        candlestickSetLargeStyle(sign, el, seriesModel)
        _ = group.add(el)
    }
}

// upstream: function setLargeStyle(sign, el, seriesModel, data) — stroke = borderColor (fallback color),
//   fill = null. Here the color also feeds the fill-boost (`boostFill`), and `borderWidth` drives both
//   the stroke width and the boost rect width.
private func candlestickSetLargeStyle(_ sign: Double, _ el: LargeBoxPath, _ seriesModel: CandlestickSeriesModel) {
    // upstream: borderColor = getBorderColor(sign) || getColor(sign). getBorderColor can return a JS
    //   `null` — bridged here as NSNull, which Swift's `??` would NOT treat as nil — so normalize it.
    let bc = getBorderColor(sign, seriesModel)
    let borderColorVal: Any? = (bc == nil || bc is NSNull) ? getColor(sign, seriesModel) : bc
    // The boost fills each candle line as a rect, so the color must live on `fill` (upstream strokes it;
    //   here fill == stroke color, stroke stays nil — a 1px line and a 1px-wide filled rect are identical).
    let fill = zrPaintFromStyleValue(borderColorVal)
    let itemStyleModel = seriesModel.getModel("itemStyle")
    let lineWidth = (itemStyleModel.get("borderWidth") as? Double) ?? 1
    let opacity = (itemStyleModel.get("opacity") as? Double) ?? 1

    var style = PathStyleProps()
    style.fill = fill
    style.stroke = nil
    style.lineWidth = lineWidth
    style.opacity = opacity
    el.useStyle(style)
    el.boostLineWidth = lineWidth
}
