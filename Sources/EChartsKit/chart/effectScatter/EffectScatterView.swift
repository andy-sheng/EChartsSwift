// Ported from echarts/src/chart/effectScatter/EffectScatterView.ts — keep in sync with upstream.
//
// Upstream EffectScatterView delegates ENTIRELY to `SymbolDraw(EffectSymbol)` — the SAME SymbolDraw
// enter/update/leave diff as ScatterView, but each symbol is an `EffectSymbol` (helper/EffectSymbol) that
// renders the base symbol PLUS the animated expanding-ring RIPPLE (the `rippleEffect` option: period /
// scale / brushType / number, shown on 'render' or 'emphasis'). It also runs the `pointsLayout` stage and a
// `createCoordSysClipAreaSimply` clip shape.
//
// PORT SCOPE (L2): now routed through the shared SymbolDraw with the ported `EffectSymbol` ctor
//   (chart/helper/EffectSymbolElement.swift) — the base symbol goes through Symbol (colour / label /
//   emphasis hover-scale / symbolRotate / offset / entrance scale-in) and the ripple rings are the
//   faithful EffectSymbol.startEffectAnimation. DEVIATION (identical to ScatterView): `pointsLayout` is
//   inlined per coord system as `getSymbolPoint`. DEFERRED: pointsLayout stage / updateTransform (roam) /
//   clipShape (createCoordSysClipAreaSimply) — documented PORT-NOTEs.

import Foundation
import ZRenderKit

// upstream imports (all deferred except createSymbol / ChartView / SeriesData / Cartesian2D / Polar):
//   import SymbolDraw from '../helper/SymbolDraw';                 -> SymbolDraw (chart/helper/SymbolDraw.swift).
//   import EffectSymbol from '../helper/EffectSymbol';             -> EffectSymbol (chart/helper/EffectSymbolElement.swift).
//   import * as matrix from 'zrender/src/core/matrix';            -> only used by updateTransform (roam, deferred).
//   import pointsLayout from '../../layout/points';                -> PORT-NOTE (deferred): requires layout/points (not ported; the per-datum placement is inlined below).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { StageHandlerProgressExecutor } from '../../util/types';  -> type-only.
//   import { createCoordSysClipAreaSimply } from '../helper/createClipPathFromCoordSys';
//       -> PORT-NOTE: createCoordSysClipAreaSimply IS ported (chart/helper/createClipPathFromCoordSys.swift);
//          this static view deliberately omits the clip shape (deviation, matches ScatterView).
//   import { SymbolDrawUpdateOpt } from '../helper/baseDraw';      -> SymbolDrawUpdateOpt (chart/helper/SymbolDraw.swift).

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

    // upstream: init() { this._symbolDraw = new SymbolDraw(EffectSymbol); }
    //   The shared SymbolDraw drives per-point EffectSymbol elements (enter/update/leave diff); each
    //   EffectSymbol builds the base symbol + animated ripple rings.
    private var _data: SeriesData?
    private var _symbolDraw: SymbolDraw?

    // upstream: render(seriesModel, ecModel, api) {
    //     const data = seriesModel.getData();
    //     const effectSymbolDraw = this._symbolDraw;
    //     effectSymbolDraw.updateData(data, createSymbolDrawOpt(seriesModel));
    //     this.group.add(effectSymbolDraw.group);
    // }
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let data = seriesModel.getData()
        let store = data.getStore()

        // Symbol-visual stages (visual/symbol.ts): populate the data + per-item symbol / symbolSize /
        //   symbolRotate / symbolOffset / symbolKeepAspect visuals from the series option, which
        //   SymbolDraw/Symbol (and EffectSymbol's ripple) read. Run inline here (the port invokes visual
        //   stages from the view). EffectScatterSeriesModel sets hasSymbolVisual = true.
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        // Per-datum point placement. Upstream `pointsLayout` (layout/points.ts) is generic over the coord
        //   system: it maps `coordSys.dimensions` to data dims and calls `coordSys.dataToPoint(point)`.
        //   The static render below inlines that for the two coord systems wired so far — cartesian2d and
        //   polar. Each branch returns a `(Int) -> [Double]` that yields the [x, y] pixel for datum i.
        //   PORT-NOTE (deferred): requires geo/singleAxis/calendar/matrix coord systems (not ported); effectScatter on those is deferred.
        let pointAt: (Int) -> [Double]
        if let coord = seriesModel.coordinateSystem as? Cartesian2D {
            let baseAxis = coord.getBaseAxis()
            let valueAxis = coord.getOtherAxis(baseAxis)
            // PORT-NOTE: `mapDimension` is force-unwrapped — a series' base/value dims are always present.
            //   Same unmarked idiom as LineView/ScatterView (their identical `mapDimension(...)!` derivation).
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
            // PORT-NOTE (deferred): requires geo/singleAxis/calendar/matrix coord systems (not ported).
            return
        }

        // upstream: `effectSymbolDraw.updateData(data, createSymbolDrawOpt(seriesModel));
        //            this.group.add(effectSymbolDraw.group);`
        //   The shared SymbolDraw owns its group (added once) and diffs old→new data into EffectSymbol
        //   elements — each builds the base Symbol child + the animated ripple ring group.
        let symbolDraw = self._symbolDraw ?? SymbolDraw({ data, idx, scope, opts in
            EffectSymbol(data, idx, scope, opts)
        })
        if self._symbolDraw == nil {
            self._symbolDraw = symbolDraw
            _ = self.group.add(symbolDraw.group)
        }

        // pointsLayout stores per-item layouts upstream; the port computes points on the fly per coord
        //   system, so feed them to SymbolDraw via getSymbolPoint.
        var opt = SymbolDrawUpdateOpt()
        opt.getSymbolPoint = { i in pointAt(i) }
        symbolDraw.updateData(data, opt)

        // PORT-NOTE (deferred): pointsLayout stage / updateTransform (roam) / _updateGroupTransform (matrix.clone of
        //   getRoamTransform) require the roam/layout-stage seam (not ported); clipShape (createCoordSysClipAreaSimply)
        //   is deliberately omitted here (deviation, matches ScatterView) — all deferred.
        self._data = data
    }
}

// export default EffectScatterView;  -> `open class EffectScatterView` above.

// upstream helper (not exported):
//   function createSymbolDrawOpt(seriesModel): SymbolDrawUpdateOpt {
//       return { clipShape: createCoordSysClipAreaSimply(seriesModel) };
//   }
// PORT-NOTE: createCoordSysClipAreaSimply IS ported (chart/helper/createClipPathFromCoordSys.swift);
//   this static view deliberately omits the clipShape from the render opt (deviation, matches ScatterView).

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `scatterToNumber` coercion in chart/scatter/ScatterView.swift.
private func effectScatterToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
