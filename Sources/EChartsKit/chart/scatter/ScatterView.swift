// Ported (STATIC SUBSET) from echarts/src/chart/scatter/ScatterView.ts — keep in sync with upstream.
//
// Upstream ScatterView delegates ENTIRELY to `SymbolDraw`/`LargeSymbolDraw` (helper/SymbolDraw +
// helper/LargeSymbolDraw), driven by the `pointsLayout` stage and a `createCoordSysClipAreaSimply`
// clip shape. NONE of those are ported yet (SymbolDraw enter/update/leave diff, LargeSymbolDraw,
// layout/points, helper/createClipPathFromCoordSys, incremental pipeline — all documented PORT-TODOs).
//
// This is a DELIBERATE DEVIATION: a STATIC faithful render inlines the per-point symbol placement the
// same way `LineView` inlines `dataToPoint` per datum — guard the cartesian coord system, derive the
// base/value dims, then for each datum compute the point via `coord.dataToPoint`, build the symbol with
// `symbol.createSymbol`, color it from the item visual style, and add it to the group. Enough for a
// scatter series to render end-to-end (matching the echarts.js reference in EChartsDemoGallery).

import Foundation
import ZRenderKit

// upstream imports (all deferred except createSymbol / ChartView / SeriesData / Cartesian2D):
//   import SymbolDraw from '../helper/SymbolDraw';                 -> PORT-TODO: helper/SymbolDraw not ported.
//   import LargeSymbolDraw from '../helper/LargeSymbolDraw';       -> PORT-TODO: helper/LargeSymbolDraw not ported.
//   import pointsLayout from '../../layout/points';                -> PORT-TODO: layout/points not ported.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import { getIncrementalId } from '../../util/model';           -> PORT-TODO: incremental pipeline not ported.
//   import { createCoordSysClipAreaSimply } from '../helper/createClipPathFromCoordSys';
//       -> PORT-TODO: helper/createClipPathFromCoordSys not ported (clipShape omitted).
//   import { ISymbolDraw, SymbolDrawUpdateOpt } from '../helper/baseDraw';  -> PORT-TODO: helper/baseDraw not ported.

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

    // L2: the shared `SymbolDraw` (chart/helper) now drives per-point symbols (enter/update/leave diff,
    //   emphasis hover-scale, symbolRotate/offset/keepAspect, symbol labels). `_isLargeDraw` /
    //   LargeSymbolDraw + the incremental pipeline remain PORT-TODO (large mode deferred).
    private var _data: SeriesData?
    private var _symbolDraw: SymbolDraw?

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
        //   PORT-TODO: geo/singleAxis/calendar/matrix scatter deferred (those coord systems not ported).
        // PORT-TODO (upstream/echarts/src/layout/points.ts:50-56): a STACKED scatter series substitutes
        //   the stacked base/value dim with `stackResultDimension` (via isDimensionStacked) before
        //   dataToPoint. We read the raw store dims, so a stacked scatter would place points at
        //   un-stacked positions. Stacked scatter is rare; wire the substitution when stacking lands.
        let pointAt: (Int) -> [Double]
        if let coord = seriesModel.coordinateSystem as? Cartesian2D {
            let baseAxis = coord.getBaseAxis()
            let valueAxis = coord.getOtherAxis(baseAxis)
            // PORT-TODO: `mapDimension` is force-unwrapped — a scatter's base/value dims are always present
            //   (same derivation as LineView).
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
        else {
            // PORT-TODO: singleAxis/calendar/matrix scatter deferred.
            return
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

        // PORT-TODO: LargeSymbolDraw (large mode), incrementalPrepareRender/incrementalRender/
        //   updateTransform, clipShape (createCoordSysClipAreaSimply) — deferred with the incremental
        //   pipeline + large-draw helpers.
        self._data = data
    }
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
