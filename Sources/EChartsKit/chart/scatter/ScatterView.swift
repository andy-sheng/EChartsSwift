// Ported (STATIC SUBSET) from echarts/src/chart/scatter/ScatterView.ts — keep in sync with upstream.
//
// Upstream ScatterView delegates ENTIRELY to `SymbolDraw`/`LargeSymbolDraw` (helper/SymbolDraw +
// helper/LargeSymbolDraw), driven by the `pointsLayout` stage and a `createCoordSysClipAreaSimply`
// clip shape. NONE of those are ported yet (SymbolDraw enter/update/leave diff, LargeSymbolDraw,
// layout/points, helper/createClipPathFromCoordSys, incremental pipeline — all documented PORT-NOTEs).
//
// This is a DELIBERATE DEVIATION: a STATIC faithful render inlines the per-point symbol placement the
// same way `LineView` inlines `dataToPoint` per datum — guard the cartesian coord system, derive the
// base/value dims, then for each datum compute the point via `coord.dataToPoint`, build the symbol with
// `symbol.createSymbol`, color it from the item visual style, and add it to the group. Enough for a
// scatter series to render end-to-end (matching the echarts.js reference in EChartsDemoGallery).

import Foundation
import ZRenderKit

// upstream imports (all deferred except createSymbol / ChartView / SeriesData / Cartesian2D):
//   import SymbolDraw from '../helper/SymbolDraw';                 -> SymbolDraw is ported (chart/helper/SymbolDraw.swift); this static view does not use it.
//   import LargeSymbolDraw from '../helper/LargeSymbolDraw';       -> LargeSymbolDraw is ported (chart/helper/LargeSymbolDraw.swift); this static view does not use it.
//   import pointsLayout from '../../layout/points';                -> PORT-NOTE (deferred): layout/points.ts not ported; points are computed inline per coord system below.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import { getIncrementalId } from '../../util/model';           -> PORT-NOTE (deferred): incremental/progressive render pipeline not wired for this static view.
//   import { createCoordSysClipAreaSimply } from '../helper/createClipPathFromCoordSys';
//       -> PORT-NOTE: createCoordSysClipAreaSimply IS ported (chart/helper/createClipPathFromCoordSys.swift); this static view deliberately omits the clip shape (deviation).
//   import { ISymbolDraw, SymbolDrawUpdateOpt } from '../helper/baseDraw';  -> SymbolDrawUpdateOpt is ported (chart/helper/SymbolDraw.swift); ISymbolDraw modeled implicitly (no separate baseDraw file).

// upstream: class ScatterView extends ChartView { static readonly type = 'scatter'; type = ScatterView.type; ... }
open class ScatterView: ChartView {

    // upstream: static readonly type = 'scatter';  /  type = ScatterView.type;
    //   Instance `type` string used as the chart-view factory key. The base `ChartView.type` is a
    //   settable stored `var` (default "chart"), so it is assigned in `init` (can't override a
    //   read-write stored property with a read-only computed one).
    public static let type = "scatter"

    public override init() {
        super.init()
        self.type = ScatterView.type
    }

    // L2: the shared `SymbolDraw` (chart/helper) drives per-point symbols (enter/update/leave diff,
    //   emphasis hover-scale, symbolRotate/offset/keepAspect, symbol labels). The large-mode fast path
    //   (`large: true` past `largeThreshold`) instead routes to `LargeSymbolDraw` (a SINGLE path that
    //   paints every point). PORT-NOTE (deferred): the incremental/progressive pipeline is single-pass here.
    private var _data: SeriesData?
    private var _symbolDraw: SymbolDraw?
    // upstream: private _largeSymbolDraw: LargeSymbolDraw; private _isLargeDraw: boolean;
    private var _largeSymbolDraw: LargeSymbolDraw?
    private var _isLargeDraw: Bool = false

    // upstream: render(seriesModel, ecModel, api) {
    //     const data = seriesModel.getData();
    //     const symbolDraw = this._updateSymbolDraw(data, seriesModel);
    //     symbolDraw.updateData(data, createSymbolDrawOpt(seriesModel));
    //     this._finished = true;
    // }
    //   DEVIATION: SymbolDraw.updateData (enter/update/leave diff) is inlined as an eager placement loop.
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let data = seriesModel.getData()
        let store = data.getStore()

        // Symbol-visual stages (visual/symbol.ts): populate the data + per-item symbol / symbolSize /
        //   symbolRotate / symbolOffset / symbolKeepAspect visuals from the series option, which
        //   SymbolDraw/Symbol read. Run inline here (the port invokes visual stages from the view).
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        // Per-datum point placement. Upstream `pointsLayout` (layout/points.ts) is generic over the coord
        //   system: it maps `coordSys.dimensions` to data dims and calls `coordSys.dataToPoint(point)`.
        //   The static render below inlines that for the two coord systems wired so far — cartesian2d and
        //   polar. Each branch returns a `(Int) -> [Double]` that yields the [x, y] pixel for datum i.
        //   PORT-NOTE (deferred): singleAxis/calendar/matrix scatter (those coord systems not ported); geo is handled below.
        // POTENTIAL-BUG (upstream/echarts/src/layout/points.ts:50-56): a STACKED scatter series substitutes
        //   the stacked base/value dim with `stackResultDimension` (via isDimensionStacked) before
        //   dataToPoint. We read the raw store dims, so a stacked scatter would place points at
        //   un-stacked positions. isDimensionStacked IS ported (data/helper/dataStackHelper.swift) but is
        //   not wired here; stacked scatter is rare. Wire the substitution when needed.
        let pointAt: (Int) -> [Double]
        if let coord = seriesModel.coordinateSystem as? Cartesian2D {
            let baseAxis = coord.getBaseAxis()
            let valueAxis = coord.getOtherAxis(baseAxis)
            // POTENTIAL-BUG: `mapDimension` is force-unwrapped — a scatter's base/value dims are always present
            //   (same derivation as LineView), but a malformed dataset with no mapped dim would SIGTRAP.
            let baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim)!)
            let valueDimIdx = data.getDimensionIndex(data.mapDimension(valueAxis.dim)!)
            let isValueAxisH = valueAxis.isHorizontal()
            pointAt = { i in
                let baseVal = scatterToNumber(store.get(baseDimIdx, i))
                let value = scatterToNumber(store.get(valueDimIdx, i))
                return isValueAxisH ? coord.dataToPoint([value, baseVal]) : coord.dataToPoint([baseVal, value])
            }
        }
        else if let coord = seriesModel.coordinateSystem as? Polar {
            // Polar dims are ["radius", "angle"] (polarDimensions); `dataToPoint([radiusVal, angleVal])`
            //   dispatches radius→dataToRadius and angle→dataToAngle in that order. Map the data dims by
            //   the coord dim name (mirrors pointsLayout's `map(coordSys.dimensions, data.mapDimension)`).
            let radiusDimIdx = data.getDimensionIndex(data.mapDimension("radius")!)
            let angleDimIdx = data.getDimensionIndex(data.mapDimension("angle")!)
            pointAt = { i in
                let radiusVal = scatterToNumber(store.get(radiusDimIdx, i))
                let angleVal = scatterToNumber(store.get(angleDimIdx, i))
                return coord.dataToPoint([radiusVal, angleVal])
            }
        }
        else if let geo = seriesModel.coordinateSystem as? Geo {
            // Geo scatter: each datum is [lng, lat]; project via geo.dataToPoint (projection + view
            //   transform). The geo coord dims are ["lng", "lat"]; fall back to the first two store dims.
            let lngIdx = data.mapDimension("lng").map { data.getDimensionIndex($0) } ?? 0
            let latIdx = data.mapDimension("lat").map { data.getDimensionIndex($0) } ?? 1
            pointAt = { i in
                let lng = scatterToNumber(store.get(lngIdx, i))
                let lat = scatterToNumber(store.get(latIdx, i))
                return geo.dataToPoint([lng, lat], false) ?? [Double.nan, Double.nan]
            }
        }
        else if let cal = seriesModel.coordinateSystem as? Calendar {
            // Calendar scatter (pointsLayout generic path): the coord dims are ["time", "value"]; the
            //   'time' dim (the date) locates the day cell. `dataToPoint(date)` returns the cell center;
            //   with the default clamp it returns NaN for dates outside this calendar's `range`, so a
            //   `calendarIndex`-routed series only draws the days that fall in its own panel.
            let timeIdx = data.mapDimension("time").map { data.getDimensionIndex($0) } ?? 0
            pointAt = { i in cal.dataToPoint(store.get(timeIdx, i)) }
        }
        else {
            // PORT-NOTE (deferred): singleAxis/matrix scatter (those coord systems not ported).
            return
        }

        // upstream `_updateSymbolDraw`: `isLargeDraw = pipelineContext.large` — for a scatter series
        //   that is `large: true` and past its `largeThreshold`. The Scheduler pipeline context is not
        //   ported, so derive it inline here (`large && count >= largeThreshold`).
        let large = (seriesModel.get("large") as? Bool) ?? false
        let largeThreshold = scatterAsInt(seriesModel.get("largeThreshold")) ?? 2000
        let isLargeDraw = large && store.count() >= largeThreshold

        if isLargeDraw {
            // upstream: symbolDraw = this._largeSymbolDraw = new LargeSymbolDraw(); (swap views on toggle)
            if self._largeSymbolDraw == nil || self._isLargeDraw != isLargeDraw {
                self._symbolDraw?.remove()
                self._symbolDraw = nil
                _ = self.group.removeAll()
                let lsd = LargeSymbolDraw()
                self._largeSymbolDraw = lsd
                _ = self.group.add(lsd.group)
            }
            self._isLargeDraw = true
            let largeDraw = self._largeSymbolDraw!

            // upstream `pointsLayout` stores the packed `points` (Float32Array [x0,y0,x1,y1,...]) as the
            //   'points' data layout; the port computes points on the fly, so build + stash the packed
            //   array here so LargeSymbolDraw.updateData can read `data.getLayout('points')` faithfully.
            var packed = [Double](repeating: 0, count: store.count() * 2)
            for i in 0..<store.count() {
                let p = pointAt(i)
                packed[i * 2] = p.count > 0 ? p[0] : Double.nan
                packed[i * 2 + 1] = p.count > 1 ? p[1] : Double.nan
            }
            data.setLayout("points", packed)

            var opt = SymbolDrawUpdateOpt()
            opt.getSymbolPoint = { i in pointAt(i) }
            largeDraw.updateData(data, opt)
            self._data = data
            return
        }

        // Toggle back from large → normal: drop the large draw + reset the group.
        if self._isLargeDraw {
            self._largeSymbolDraw?.remove()
            self._largeSymbolDraw = nil
            _ = self.group.removeAll()
            self._isLargeDraw = false
        }

        // upstream: `const symbolDraw = this._updateSymbolDraw(data, seriesModel);
        //            symbolDraw.updateData(data, createSymbolDrawOpt(seriesModel));`
        //   The shared SymbolDraw owns its own group (added once to the view group) and diffs old→new
        //   data into Symbol elements — each Symbol handles its style, emphasis hover-scale,
        //   symbolRotate/offset/keepAspect, entrance scale-in and the per-point label.
        let symbolDraw = self._symbolDraw ?? SymbolDraw()
        if self._symbolDraw == nil {
            self._symbolDraw = symbolDraw
            _ = self.group.add(symbolDraw.group)
        }

        // pointsLayout stores per-item layouts upstream; the port computes points on the fly per coord
        //   system, so feed them to SymbolDraw via getSymbolPoint.
        var opt = SymbolDrawUpdateOpt()
        opt.getSymbolPoint = { i in pointAt(i) }
        symbolDraw.updateData(data, opt)

        // PORT-NOTE (deferred): incrementalPrepareRender/incrementalRender/updateTransform, plus the
        //   clipShape (createCoordSysClipAreaSimply) — deferred with the incremental pipeline.
        self._data = data
    }
}

// `largeThreshold` (and friends) box as Int OR Double (the Int-vs-Double option-read trap); coerce.
private func scatterAsInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}

// export default ScatterView;  -> `open class ScatterView` above.

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `lineToNumber` coercion in chart/line/LineView.swift.
private func scatterToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
