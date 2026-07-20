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
    // PORT-TODO: PORTING.md section 7 — an upstream `ArrayLike<number>` fed by a `Float32Array`
    //   (`vendor.createFloat32Array` in layout/barGrid) should be `ContiguousArray<Double>`. Kept
    //   `[Double]` to match `util/vendor.createFloat32Array`'s current return type (vendor.swift:75)
    //   and the `getLayout("largePoints")` boxing; migrate this, `LargeBarPath.largeDataIndices` and
    //   `createFloat32Array` together in a dedicated pass — NOT as a side effect of this lane.
    //   `[Double]` on a large-data hot path is the shape that has previously produced O(n^2) bridging.
    public var points: [Double] = []
    public init() {}
    // points are not tweened (the whole shape is replaced via setShape) → default no-op animation.
}

// upstream: class LargePath extends Path<LargePathProps> (bar/BarView.ts:1100). One Path drawing every
//   bar of a large series. `type = 'largeBar'`.
public final class LargeBarPath: Path {
    // upstream: baseDimIdx (0 when the value axis is vertical, 1 when horizontal), largeDataIndices, barWidth.
    public var baseDimIdx: Int = 0
    // PORT-TODO: PORTING.md section 7 — upstream `Float32Array` buffer; should be
    //   `ContiguousArray<Double>` (see the note on `LargeBarPathShape.points`).
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
//   LargeBarPath, styles them from the series visual, wires the throttled hit-test, and (in the
//   progressive/incremental path) stamps `incremental` + collects the new els into `progressiveEls`.
func barCreateLarge(
    _ seriesModel: BarSeriesModel,
    _ group: ZRenderKit.Group,
    _ progressiveEls: inout [Element]?,
    _ incremental: Bool = false
) {
    // TODO support polar
    let data = seriesModel.getData()
    // upstream: const baseDimIdx = data.getLayout('valueAxisHorizontal') ? 1 : 0;
    let valueAxisHorizontal = (data.getLayout("valueAxisHorizontal") as? Bool) ?? false
    let baseDimIdx = valueAxisHorizontal ? 1 : 0
    let largeDataIndices = (data.getLayout("largeDataIndices") as? [Double]) ?? []
    let barWidth = (data.getLayout("size") as? Double) ?? 0

    let backgroundModel = seriesModel.getModel("backgroundStyle")
    let bgPointsOpt = data.getLayout("largeBackgroundPoints") as? [Double]
    // upstream: const incrementalId = incremental ? getIncrementalId(seriesModel) : 0;
    let incrementalId = incremental ? model.getIncrementalId(seriesModel) : 0

    // upstream: background LargePath (showBackground) — draw first (z2 0), then the data path (z2 1).
    if let bgPoints = bgPointsOpt {
        let bgEl = LargeBarPath()
        var bgShape = LargeBarPathShape()
        bgShape.points = bgPoints
        bgEl.setShape(bgShape)
        bgEl.incremental = incrementalId
        bgEl.silent = true
        bgEl.z2 = 0
        bgEl.baseDimIdx = baseDimIdx
        bgEl.largeDataIndices = largeDataIndices
        bgEl.barWidth = barWidth
        bgEl.useStyle(barStyleFromDict(backgroundModel.getItemStyle(nil, nil)))
        _ = group.add(bgEl)

        // upstream: progressiveEls && progressiveEls.push(bgEl);
        progressiveEls?.append(bgEl)
    }

    // upstream: the data LargePath.
    let el = LargeBarPath()
    var shape = LargeBarPathShape()
    shape.points = (data.getLayout("largePoints") as? [Double]) ?? []
    el.setShape(shape)
    el.incremental = incrementalId
    el.ignoreCoarsePointer = true
    el.z2 = 1
    el.baseDimIdx = baseDimIdx
    el.largeDataIndices = largeDataIndices
    el.barWidth = barWidth
    _ = group.add(el)
    // upstream: el.useStyle(data.getVisual('style')); el.style.stroke = null;
    let globalStyle = data.getVisual("style") as? [String: Any]
    el.useStyle(barStyleFromDict(globalStyle))
    // Stroke is rendered first to avoid overlapping with fill. See #20465
    el.pathStyle?.stroke = nil
    // Enable tooltip and user mouse/touch event handlers.
    innerStore.getECData(el).seriesIndex = seriesModel.seriesIndex

    // upstream: if (!seriesModel.get('silent')) { el.on('mousedown'|'mousemove', largePathUpdateDataIndex); }
    if !((seriesModel.get("silent") as? Bool) ?? false) {
        _ = el.on("mousedown", largePathHitHandler)
        _ = el.on("mousemove", largePathHitHandler)
    }

    // upstream: progressiveEls && progressiveEls.push(el);
    progressiveEls?.append(el)
}

// upstream: the non-progressive `createLarge(seriesModel, this.group)` call in `_renderLarge`.
//   Delegates to the full port with no `progressiveEls` collection and `incremental = false`.
func barCreateLarge(_ seriesModel: BarSeriesModel, _ group: ZRenderKit.Group) {
    var noProgressive: [Element]? = nil
    barCreateLarge(seriesModel, group, &noProgressive, false)
}

// upstream binds ONE module-level handler on both events (`el.on('mousedown', largePathUpdateDataIndex)`),
//   relying on `this` being the element the listener is bound to. `Element.on` forwards `context ?? self`
//   as the handler's `thisCtx` (Element.swift:1597), so `thisCtx` IS that element — a single shared
//   handler mirrors upstream exactly, with no per-element closure allocation.
// LEAK WARNING: `Eventful`'s handler record holds `ctx` STRONGLY (Core/Eventful.swift, `EventHandler.ctx`)
//   and `Element.on` passes `context ?? self`, so binding ANY listener makes the element self-retain
//   (el -> _eventful -> handler.ctx -> el). Dropping the path from the group is therefore NOT enough to
//   free it — at 500k bars each orphaned `LargeBarPath` pins its whole packed `points` array (~12 MB per
//   re-render). `BarView._clear` MUST `off()` the outgoing large paths before `group.removeAll()`; it
//   does. (A `[weak el]` capture never helped: the cycle is through `ctx`, not the closure.)
// PORT-TODO (framework): `EventHandler.ctx` should be held weakly/unowned in the `context ?? self` case
//   — upstream JS GC collects that self-cycle freely. Track separately; it affects every `Element.on`.
private let largePathHitHandler: EventCallback = { thisCtx, args in
    guard let largePath = thisCtx as? LargeBarPath,
          let event = args.first as? ZRElementEvent else { return nil }
    largePathUpdateDataIndex(largePath, event)
    return nil
}

// Use throttle to avoid frequently traverse to find dataIndex.
// upstream (bar/BarView.ts:1194): const largePathUpdateDataIndex = throttle(function (this: LargePath,
//   event: ZRElementEvent) { ... }, 30, false). The Swift `ThrottledFunction` is nullary (scope/args
//   dropped), so the latest `(largePath, event)` pair is stashed in a module slot before triggering the
//   shared throttle — mirroring upstream's single module-level throttled fn running `fn.apply(scope,
//   args)` with the most-recent call's `this`/args when its timer fires.
private var largePathPendingHit: (largePath: LargeBarPath, event: ZRElementEvent)?

private let largePathHitThrottle: ThrottledFunction = throttleUtil.throttle({
    guard let pending = largePathPendingHit else { return }
    let largePath = pending.largePath
    // upstream: const dataIndex = largePathFindDataIndex(largePath, event.offsetX, event.offsetY);
    let dataIndex = largePathFindDataIndex(
        largePath,
        pending.event.offsetX,
        pending.event.offsetY
    )
    // upstream: getECData(largePath).dataIndex = dataIndex >= 0 ? dataIndex : null;
    innerStore.getECData(largePath).dataIndex = dataIndex >= 0 ? Double(dataIndex) : nil
    // Release the strong reference to the hovered LargeBarPath so a re-rendered path
    //   (BarView._clear drops it from the group) can deallocate promptly.
    largePathPendingHit = nil
}, 30, false)

let largePathUpdateDataIndex: (LargeBarPath, ZRElementEvent) -> Void = { largePath, event in
    largePathPendingHit = (largePath, event)
    largePathHitThrottle()
}

// upstream: function largePathFindDataIndex(largePath, x, y) (bar/BarView.ts:1201). Walks the packed
//   3-per-bar points, standardizing a negative value-dim size, and returns the datum's `largeDataIndices`
//   entry when (x, y) falls inside the bar rect — else -1.
func largePathFindDataIndex(_ largePath: LargeBarPath, _ x: Double, _ y: Double) -> Int {
    let baseDimIdx = largePath.baseDimIdx
    let valueDimIdx = 1 - baseDimIdx
    guard let shape = largePath.shape as? LargeBarPathShape else { return -1 }
    let points = shape.points
    let largeDataIndices = largePath.largeDataIndices
    let barWidth = largePath.barWidth

    // PORT-NOTE: upstream bounds the loop by `points.length / 3` alone and reads `largeDataIndices[i]`
    //   — an out-of-range typed-array read yields `undefined` in JS (harmless), but traps in Swift.
    //   `points` and `largeDataIndices` come from two independent `getLayout(...) as? [Double]` reads
    //   (either of which can fall through to `[]`), so bound by BOTH.
    let len = Swift.min(points.count / 3, largeDataIndices.count)
    for i in 0..<len {
        let ii = i * 3
        var size = [0.0, 0.0]
        var startPoint = [0.0, 0.0]
        size[baseDimIdx] = barWidth
        size[valueDimIdx] = points[ii + 2]
        startPoint[baseDimIdx] = points[ii + baseDimIdx]
        startPoint[valueDimIdx] = points[ii + valueDimIdx]
        if size[valueDimIdx] < 0 {
            startPoint[valueDimIdx] += size[valueDimIdx]
            size[valueDimIdx] = -size[valueDimIdx]
        }

        if x >= startPoint[0] && x <= startPoint[0] + size[0]
            && y >= startPoint[1] && y <= startPoint[1] + size[1] {
            // `Int(Double)` traps on NaN/infinity AND on any FINITE value outside `Int`'s range (a
            //   Float32 slot can legitimately hold ~3.4e38, far past Int64.max — `isFinite` would let
            //   that through and still trap). `Int(exactly:)` on the truncated value is total: it
            //   covers all three cases and degrades to "no datum", matching the JS `undefined` an
            //   out-of-range typed-array read yields.
            let idx = largeDataIndices[i]
            return Int(exactly: idx.rounded(.towardZero)) ?? -1
        }
    }

    return -1
}
