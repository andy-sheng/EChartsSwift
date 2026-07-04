// Ported (STATIC SUBSET) from echarts/src/chart/effectScatter/EffectScatterView.ts — keep in sync with upstream.
//
// Upstream EffectScatterView delegates ENTIRELY to `SymbolDraw(EffectSymbol)` — i.e. the SAME SymbolDraw
// enter/update/leave diff as ScatterView, but each symbol is an `EffectSymbol` (helper/EffectSymbol) that
// renders the base symbol PLUS the animated expanding-ring RIPPLE (the `rippleEffect` option: period /
// scale / brushType / number, shown on 'render' or 'emphasis'). It also runs the `pointsLayout` stage and a
// `createCoordSysClipAreaSimply` clip shape. NONE of those are ported yet (SymbolDraw diff, EffectSymbol,
// layout/points, helper/createClipPathFromCoordSys — all documented PORT-TODOs).
//
// This is a DELIBERATE DEVIATION (identical to ScatterView): a STATIC faithful render inlines the per-point
// symbol placement the same way `LineView` inlines `dataToPoint` per datum — guard the cartesian (or polar)
// coord system, derive the base/value dims, then for each datum compute the point via `coord.dataToPoint`,
// build the symbol with `symbol.createSymbol`, color it from the item visual style, and add it to the group.
//
// PORT-TODO (RIPPLE — CONVENTIONS §5, render is STATIC ONLY): the animated expanding-ring effect (the whole
//   reason effectScatter differs from scatter) lives in helper/EffectSymbol and is ANIMATED — DEFERRED. This
//   view draws ONLY the static base symbols, so an effectScatter renders identically to a scatter until
//   EffectSymbol + the animation clip land.

import Foundation
import ZRenderKit

// upstream imports (all deferred except createSymbol / ChartView / SeriesData / Cartesian2D / Polar):
//   import SymbolDraw from '../helper/SymbolDraw';                 -> PORT-TODO: helper/SymbolDraw not ported.
//   import EffectSymbol from '../helper/EffectSymbol';             -> PORT-TODO: helper/EffectSymbol not ported (RIPPLE, animated).
//   import * as matrix from 'zrender/src/core/matrix';            -> only used by updateTransform (roam, deferred).
//   import pointsLayout from '../../layout/points';                -> PORT-TODO: layout/points not ported.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { StageHandlerProgressExecutor } from '../../util/types';  -> type-only.
//   import { createCoordSysClipAreaSimply } from '../helper/createClipPathFromCoordSys';
//       -> PORT-TODO: helper/createClipPathFromCoordSys not ported (clipShape omitted).
//   import { SymbolDrawUpdateOpt } from '../helper/baseDraw';      -> PORT-TODO: helper/baseDraw not ported.

// upstream: class EffectScatterView extends ChartView { static readonly type = 'effectScatter'; type = ...; ... }
open class EffectScatterView: ChartView {

    // upstream: static readonly type = 'effectScatter';  /  readonly type = EffectScatterView.type;
    //   Instance `type` string used as the chart-view factory key. The base `ChartView.type` is a settable
    //   stored `var` (default "chart"), so it is assigned in `init` (can't override a read-write stored
    //   property with a read-only computed one).
    public static let type = "effectScatter"

    public override init() {
        super.init()
        self.type = EffectScatterView.type
    }

    // PORT-TODO: upstream `init()` builds `this._symbolDraw = new SymbolDraw(EffectSymbol)`. SymbolDraw +
    //   EffectSymbol (the animated RIPPLE) are not ported; the static render below replaces
    //   `effectSymbolDraw.updateData` entirely with an eager placement loop.
    private var _data: SeriesData?

    // upstream: render(seriesModel, ecModel, api) {
    //     const data = seriesModel.getData();
    //     const effectSymbolDraw = this._symbolDraw;
    //     effectSymbolDraw.updateData(data, createSymbolDrawOpt(seriesModel));
    //     this.group.add(effectSymbolDraw.group);
    // }
    //   DEVIATION: SymbolDraw(EffectSymbol).updateData (enter/update/leave diff + animated ripple) is inlined
    //   as an eager STATIC placement loop — the same structure as ScatterView. The ripple is DEFERRED.
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let data = seriesModel.getData()
        let store = data.getStore()

        // Per-datum point placement. Upstream `pointsLayout` (layout/points.ts) is generic over the coord
        //   system: it maps `coordSys.dimensions` to data dims and calls `coordSys.dataToPoint(point)`.
        //   The static render below inlines that for the two coord systems wired so far — cartesian2d and
        //   polar. Each branch returns a `(Int) -> [Double]` that yields the [x, y] pixel for datum i.
        //   PORT-TODO: geo/singleAxis/calendar/matrix effectScatter deferred (those coord systems not ported).
        let pointAt: (Int) -> [Double]
        if let coord = seriesModel.coordinateSystem as? Cartesian2D {
            let baseAxis = coord.getBaseAxis()
            let valueAxis = coord.getOtherAxis(baseAxis)
            // PORT-TODO: `mapDimension` is force-unwrapped — a series' base/value dims are always present
            //   (same derivation as LineView/ScatterView).
            let baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim)!)
            let valueDimIdx = data.getDimensionIndex(data.mapDimension(valueAxis.dim)!)
            let isValueAxisH = valueAxis.isHorizontal()
            pointAt = { i in
                let baseVal = effectScatterToNumber(store.get(baseDimIdx, i))
                let value = effectScatterToNumber(store.get(valueDimIdx, i))
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
                let radiusVal = effectScatterToNumber(store.get(radiusDimIdx, i))
                let angleVal = effectScatterToNumber(store.get(angleDimIdx, i))
                return coord.dataToPoint([radiusVal, angleVal])
            }
        }
        else {
            // PORT-TODO: geo/singleAxis/calendar/matrix effectScatter deferred.
            return
        }

        let group = self.group
        group.removeAll()

        // Series-level fallbacks for symbol type/size (the visual/symbol.ts stage that populates the
        //   per-item 'symbol'/'symbolSize' visuals is a PORT-TODO; fall back to the series option).
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 10.0

        // The palette color for an effectScatter lands under the item visual style's `fill` key. Bridge the
        //   EChartsKit `ZRColor.color(String)` (or a raw String) to a solid color string — same bridge as
        //   ScatterView/LineView's `colorString`. Gradient/pattern out of scope.
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

            // upstream (inside SymbolDraw(EffectSymbol)): createSymbol places the base symbol centered on the
            //   point (`x - size/2`, `y - size/2`, size, size); EffectSymbol wraps that with the animated
            //   ripple rings. PORT-TODO: the RIPPLE (rippleEffect) + symbolRotate/symbolOffset/
            //   symbolKeepAspect + emphasis scale not applied (EffectSymbol / SymbolDraw states deferred).
            let el = symbol.createSymbol(
                symbolType, point[0] - sizeW / 2, point[1] - sizeH / 2, sizeW, sizeH, fill
            )
            if let path = el as? Path {
                path.name = "item"
                _ = group.add(path)
            }
        }

        // PORT-TODO: SymbolDraw enter/update/leave diff, EffectSymbol RIPPLE (animated), pointsLayout /
        //   updateTransform (roam), _updateGroupTransform (matrix.clone of getRoamTransform), clipShape
        //   (createCoordSysClipAreaSimply), symbolRotate/symbolOffset/symbolKeepAspect, emphasis scale —
        //   all deferred with the SymbolDraw/EffectSymbol helpers.
        self._data = data
    }
}

// export default EffectScatterView;  -> `open class EffectScatterView` above.

// upstream helper (not exported):
//   function createSymbolDrawOpt(seriesModel): SymbolDrawUpdateOpt {
//       return { clipShape: createCoordSysClipAreaSimply(seriesModel) };
//   }
// PORT-TODO: helper/createClipPathFromCoordSys not ported — clipShape omitted from the static render.

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `scatterToNumber` coercion in chart/scatter/ScatterView.swift.
private func effectScatterToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
