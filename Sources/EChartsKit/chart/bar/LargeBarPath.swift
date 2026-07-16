// LargeBarPath — port of chart/bar/BarView.ts's `LargePath` + `createLarge` (the bar large-mode
// fast path). When a bar series is large (`pipelineContext.large`), every bar is drawn by ONE
// `LargeBarPath` whose shape carries the packed `largePoints` the barGrid layout already produced
// (`[x, y, sizeAlongValueAxis]` per datum) — instead of one Rect element per bar (`_renderNormal`,
// ~71s for 500k bars). Upstream's `LargePath.buildPath` emits `ctx.rect(...)` per bar into the
// canvas path; here that same geometry backs the renderer-agnostic boost hook
// (`largeSymbolBoostRects`) so the native painter fills each bar with its own `ctx.fill(rect)` —
// N cheap primitive fills, NOT one super-linear N-sub-path `fillPath` (see LargeSymbolDraw's boost
// and the base `Path.largeSymbolBoostRects()` doc).
import Foundation
import ZRenderKit

// upstream: interface LagePathShape { points: ArrayLike<number>; } (bar/BarView.ts:1096) — the packed
//   `largePoints`, 3 numbers per bar: `[startX, startY, sizeAlongValueAxis]`.
public struct LargeBarPathShape: PathShape {
    public var points: [Double] = []
    public init() {}
    // points are not tweened (the whole shape is replaced via setShape) → default no-op animation.
}

// upstream: class LargePath extends Path<LargePathProps> (bar/BarView.ts:1100). One Path drawing every
//   bar of a large series. `type = 'largeBar'`.
public final class LargeBarPath: Path {
    // upstream: baseDimIdx (0 when the value axis is vertical, 1 when horizontal), largeDataIndices, barWidth.
    public var baseDimIdx: Int = 0
    public var largeDataIndices: [Double] = []
    public var barWidth: Double = 0

    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        self.type = "largeBar"
    }

    public override func getDefaultShape() -> PathShape {
        return LargeBarPathShape()
    }

    // upstream buildPath (bar/BarView.ts:1117): for each `[startX, startY, valueSize]` triple emit
    //   `ctx.rect(startPoint[0], startPoint[1], size[0], size[1])` where the base dim gets `barWidth`
    //   and the value dim gets the triple's third number. Kept faithful for hit-test / bounds paths;
    //   the painter draws via `largeSymbolBoostRects()` (below), never this mega-path, during paint.
    public override func buildPath(_ path: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        guard let shape = shapeIn as? LargeBarPathShape else { return }
        let points = shape.points
        let valueDimIdx = 1 - self.baseDimIdx
        var i = 0
        while i + 2 < points.count {
            var size = [0.0, 0.0]
            var startPoint = [0.0, 0.0]
            size[self.baseDimIdx] = self.barWidth
            size[valueDimIdx] = points[i + 2]
            startPoint[self.baseDimIdx] = points[i + self.baseDimIdx]
            startPoint[valueDimIdx] = points[i + valueDimIdx]
            _ = path.rect(startPoint[0], startPoint[1], size[0], size[1])
            i += 3
        }
    }

    // Bars ARE rects, so the boost (per-datum fill) always applies — return the same rectangles the
    //   buildPath loop would emit, packed `[x, y, w, h, ...]` and standardized (a negative value-dim
    //   size, e.g. a bar below the baseline, is normalized to a positive-extent CGRect so the painter's
    //   `ctx.fill(rect)` fills it; canvas `fillRect` accepts negatives directly, Core Graphics does not).
    public override func largeSymbolBoostRects() -> [Double]? {
        guard let shape = self.shape as? LargeBarPathShape else { return nil }
        let points = shape.points
        guard !points.isEmpty else { return nil }
        let valueDimIdx = 1 - self.baseDimIdx
        var out = [Double]()
        out.reserveCapacity(points.count / 3 * 4)
        var i = 0
        while i + 2 < points.count {
            var size = [0.0, 0.0]
            var startPoint = [0.0, 0.0]
            size[self.baseDimIdx] = self.barWidth
            size[valueDimIdx] = points[i + 2]
            startPoint[self.baseDimIdx] = points[i + self.baseDimIdx]
            startPoint[valueDimIdx] = points[i + valueDimIdx]
            var x = startPoint[0], y = startPoint[1], w = size[0], h = size[1]
            if w < 0 { x += w; w = -w }
            if h < 0 { y += h; h = -h }
            out.append(x); out.append(y); out.append(w); out.append(h)
            i += 3
        }
        return out
    }

    // Derive bounds straight from the packed points (mirrors LargeSymbolPath's "ignore stroke, derive
    //   from points+size" rect) so a bounds request (e.g. a gradient/clip) never triggers the mega-path
    //   PathProxy build. Bar-large uses a solid fill, so this is not hit during its paint.
    public override func getBoundingRect() -> BoundingRect? {
        guard let shape = self.shape as? LargeBarPathShape else { return nil }
        let points = shape.points
        guard points.count >= 3 else { return BoundingRect(0, 0, 0, 0) }
        let valueDimIdx = 1 - self.baseDimIdx
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        var i = 0
        while i + 2 < points.count {
            var size = [0.0, 0.0]
            var startPoint = [0.0, 0.0]
            size[self.baseDimIdx] = self.barWidth
            size[valueDimIdx] = points[i + 2]
            startPoint[self.baseDimIdx] = points[i + self.baseDimIdx]
            startPoint[valueDimIdx] = points[i + valueDimIdx]
            let x0 = Swift.min(startPoint[0], startPoint[0] + size[0])
            let x1 = Swift.max(startPoint[0], startPoint[0] + size[0])
            let y0 = Swift.min(startPoint[1], startPoint[1] + size[1])
            let y1 = Swift.max(startPoint[1], startPoint[1] + size[1])
            minX = Swift.min(minX, x0); maxX = Swift.max(maxX, x1)
            minY = Swift.min(minY, y0); maxY = Swift.max(maxY, y1)
            i += 3
        }
        return BoundingRect(minX, minY, maxX - minX, maxY - minY)
    }
}

// upstream: function createLarge(seriesModel, group, progressiveEls?, incremental?) (bar/BarView.ts:1137).
//   Reads the barGrid layout (`largePoints` / `largeDataIndices` / `size` / `valueAxisHorizontal` /
//   `largeBackgroundPoints`), builds the background LargeBarPath (if `showBackground`) then the data
//   LargeBarPath, and styles them from the series visual. `progressiveEls`/`incremental` are the
//   progressive path (not driven here — the native harness has no incremental pipeline).
func barCreateLarge(_ seriesModel: BarSeriesModel, _ group: ZRenderKit.Group) {
    let data = seriesModel.getData()
    // upstream: const baseDimIdx = data.getLayout('valueAxisHorizontal') ? 1 : 0;
    let valueAxisHorizontal = (data.getLayout("valueAxisHorizontal") as? Bool) ?? false
    let baseDimIdx = valueAxisHorizontal ? 1 : 0
    let largeDataIndices = (data.getLayout("largeDataIndices") as? [Double]) ?? []
    let barWidth = (data.getLayout("size") as? Double) ?? 0

    // upstream: background LargePath (showBackground) — draw first (z2 0), then the data path (z2 1).
    if let bgPoints = data.getLayout("largeBackgroundPoints") as? [Double], !bgPoints.isEmpty {
        let bgEl = LargeBarPath()
        var bgShape = LargeBarPathShape()
        bgShape.points = bgPoints
        bgEl.setShape(bgShape)
        bgEl.baseDimIdx = baseDimIdx
        bgEl.largeDataIndices = largeDataIndices
        bgEl.barWidth = barWidth
        bgEl.silent = true
        bgEl.z2 = 0
        let bgModel = seriesModel.getModel("backgroundStyle")
        bgEl.useStyle(barStyleFromDict(bgModel.getItemStyle(nil, nil)))
        _ = group.add(bgEl)
    }

    // upstream: the data LargePath.
    let el = LargeBarPath()
    var shape = LargeBarPathShape()
    shape.points = (data.getLayout("largePoints") as? [Double]) ?? []
    el.setShape(shape)
    el.baseDimIdx = baseDimIdx
    el.largeDataIndices = largeDataIndices
    el.barWidth = barWidth
    el.ignoreCoarsePointer = true
    el.z2 = 1
    // upstream: el.useStyle(data.getVisual('style')); el.style.stroke = null;
    let globalStyle = data.getVisual("style") as? [String: Any]
    el.useStyle(barStyleFromDict(globalStyle))
    el.pathStyle?.stroke = nil   // stroke rendered first would overlap the fill; large mode fills only
    let ecData = innerStore.getECData(el)
    ecData.seriesIndex = seriesModel.seriesIndex
    _ = group.add(el)
}
