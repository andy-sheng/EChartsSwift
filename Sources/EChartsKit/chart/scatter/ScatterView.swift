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

    // PORT-TODO: `_finished` / `_isLargeDraw` / `_symbolDraw` (incremental + large-draw state) omitted —
    //   SymbolDraw/LargeSymbolDraw not ported. The static render below replaces `_updateSymbolDraw` +
    //   `symbolDraw.updateData` entirely.
    private var _data: SeriesData?

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
        else {
            // PORT-TODO: geo/singleAxis/calendar/matrix scatter deferred.
            return
        }

        let group = self.group
        group.removeAll()

        // Series-level fallbacks for symbol type/size (the visual/symbol.ts stage that populates the
        //   per-item 'symbol'/'symbolSize' visuals is a PORT-TODO; fall back to the series option).
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 10.0

        // The palette color for a scatter lands under the item visual style's `fill` key. Bridge the
        //   EChartsKit `ZRColor.color(String)` (or a raw String) to a solid color string — same bridge as
        //   LineView's `colorString`. Gradient/pattern out of scope.
        func colorString(_ v: Any?) -> String? {
            if let str = v as? String { return str }
            if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
            return nil
        }
        // Series-level style fallback (visual/style.ts writes the palette color into the series visual
        //   `style` bag; item-level visuals override it when present).
        let seriesStyle = data.getVisual("style") as? [String: Any]

        for i in 0..<data.count() {
            let point = pointAt(i)
            if point.count < 2 || !point[0].isFinite || !point[1].isFinite { continue }

            let symbolType = (data.getItemVisual(i, "symbol") as? String) ?? seriesSymbol
            let (sizeW, sizeH) = symbol.normalizeSymbolSize(data.getItemVisual(i, "symbolSize") ?? seriesSymbolSize)

            // Resolve the fill color: item visual style first, then the series visual style.
            let itemStyle = (data.getItemVisual(i, "style") as? [String: Any]) ?? seriesStyle
            var fill: ZRenderKit.ZRColor? = nil
            if let cs = colorString(itemStyle?["fill"]) {
                fill = .string(cs)
            }

            // upstream (inside SymbolDraw): createSymbol places the symbol centered on the point
            //   (`x - size/2`, `y - size/2`, size, size). PORT-TODO: symbolRotate/symbolOffset/
            //   symbolKeepAspect + emphasis scale not applied (SymbolDraw states deferred).
            let el = symbol.createSymbol(
                symbolType, point[0] - sizeW / 2, point[1] - sizeH / 2, sizeW, sizeH, fill
            )
            if let path = el as? Path {
                path.name = "item"
                _ = group.add(path)
            }
        }

        // PORT-TODO: SymbolDraw enter/update/leave diff, LargeSymbolDraw, incrementalPrepareRender/
        //   incrementalRender/updateTransform, clipShape (createCoordSysClipAreaSimply), symbolRotate/
        //   symbolOffset/symbolKeepAspect, emphasis scale — all deferred with the SymbolDraw helpers.
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
