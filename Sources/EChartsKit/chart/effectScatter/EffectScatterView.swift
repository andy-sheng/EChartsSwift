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
//   inlined per coord system as `getSymbolPoint`. Ported: clipShape (createCoordSysClipAreaSimply, bridged
//   to SymbolClipShape) / updateTransform (roam re-layout) / _updateGroupTransform (roam group matrix) /
//   remove. DEFERRED: matrix coord system (not ported) hits the else-branch early return.

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
        else if let geo = seriesModel.coordinateSystem as? Geo {
            // Geo effectScatter (mirrors ScatterView): each datum is [lng, lat]; project via
            //   geo.dataToPoint (projection + view transform). The geo coord dims are ["lng", "lat"];
            //   fall back to the first two store dims.
            let lngIdx = data.mapDimension("lng").map { data.getDimensionIndex($0) } ?? 0
            let latIdx = data.mapDimension("lat").map { data.getDimensionIndex($0) } ?? 1
            pointAt = { i in
                let lng = effectScatterToNumber(store.get(lngIdx, i))
                let lat = effectScatterToNumber(store.get(latIdx, i))
                return geo.dataToPoint([lng, lat], false) ?? [Double.nan, Double.nan]
            }
        }
        else if let cal = seriesModel.coordinateSystem as? Calendar {
            // Calendar effectScatter (mirrors ScatterView): the 'time' dim locates the day cell, and
            //   `dataToPoint(date)` returns its center (NaN for dates outside this calendar's range, so
            //   a `calendarIndex`-routed series only ripples the days in its own panel).
            let timeIdx = data.mapDimension("time").map { data.getDimensionIndex($0) } ?? 0
            pointAt = { i in cal.dataToPoint(store.get(timeIdx, i)) }
        }
        else if let single = seriesModel.coordinateSystem as? Single {
            // singleAxis effectScatter — upstream `pointsLayout` `dimLen === 1` branch (layout/points.ts):
            //   `coordSys.dimensions` is ["single"], so exactly ONE store dim (the value on the single axis)
            //   is mapped and `coordSys.dataToPoint(x)` places it on the axis, centering the cross span.
            let singleDim = single.dimensions.first ?? "single"
            let dimIdx = data.mapDimension(singleDim).map { data.getDimensionIndex($0) } ?? 0
            pointAt = { i in
                let x = effectScatterToNumber(store.get(dimIdx, i))
                return single.dataToPoint(x)
            }
        }
        else {
            // PORT-NOTE (deferred): matrix coord system not ported.
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

        // upstream: `effectSymbolDraw.updateData(data, createSymbolDrawOpt(seriesModel))` — the render opt
        //   carries the coord-area clipShape (createCoordSysClipAreaSimply). pointsLayout stores per-item
        //   layouts upstream; the port computes points on the fly per coord system, so ALSO feed them to
        //   SymbolDraw via getSymbolPoint (deviation).
        var opt = createSymbolDrawOpt(seriesModel)
        opt.getSymbolPoint = { i in pointAt(i) }
        symbolDraw.updateData(data, opt)

        // PORT-NOTE (deferred): pointsLayout stage (layout/points.ts) is inlined as getSymbolPoint above.
        self._data = data
    }

    // upstream: updateTransform(seriesModel, ecModel, api) {
    //     const data = seriesModel.getData();
    //     this.group.dirty();
    //     const res = pointsLayout('').reset(seriesModel, ecModel, api) as StageHandlerProgressExecutor;
    //     if (res.progress) { res.progress({ start: 0, end: data.count(), count: data.count() }, data); }
    //     this._symbolDraw.updateLayout(createSymbolDrawOpt(seriesModel));
    // }
    //   Called on roam pan/zoom to reposition ripples without a full render. Upstream re-runs pointsLayout
    //   to recompute each datum's stored point; the port computes points on the fly via the getSymbolPoint
    //   closure SymbolDraw captured at updateData time — that closure reads the live coordSys (a reference
    //   type whose roam transform is updated in place), so `updateLayout` re-reads the roamed positions.
    open override func updateTransform(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) -> Bool? {
        _ = seriesModel.getData()
        self.group.dirty()
        self._symbolDraw?.updateLayout(createSymbolDrawOpt(seriesModel))
        // upstream returns void (no `{update: true}`); base modeled as `Bool?` → nil.
        return nil
    }

    // upstream: _updateGroupTransform(seriesModel) {
    //     const coordSys = seriesModel.coordinateSystem;
    //     if (coordSys && coordSys.getRoamTransform) {
    //         this.group.transform = matrix.clone(coordSys.getRoamTransform());
    //         this.group.decomposeTransform();
    //     }
    // }
    //   Applies the coord system's roam transform to the whole symbol group. `getRoamTransform` is an
    //   optional coord-sys method (protocol default returns nil); the `coordSys.getRoamTransform` truthy
    //   guard maps to the non-nil result.
    private func _updateGroupTransform(_ seriesModel: SeriesModel) {
        guard let coordSys = seriesModel.coordinateSystem as? CoordinateSystem,
              let roam = coordSys.getRoamTransform() else {
            return
        }
        self.group.transform = matrix.clone(roam)
        self.group.decomposeTransform()
    }

    // upstream: remove(ecModel, api) { this._symbolDraw && this._symbolDraw.remove(true); }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._symbolDraw?.remove(true)
    }
}

// upstream helper (not exported): createSymbolDrawOpt(seriesModel) -> { clipShape: createCoordSysClipAreaSimply(seriesModel) }.
//   createCoordSysClipAreaSimply IS ported (chart/helper/createClipPathFromCoordSys.swift) and returns a
//   `CoordinateSystemClipArea?`; SymbolDraw's opt wants a `SymbolClipShape?`. The two protocols share the
//   `contain(x, y)` contract, so bridge via EffectScatterClipShape below (matches the `clip: true` default).
private func createSymbolDrawOpt(_ seriesModel: SeriesModel) -> SymbolDrawUpdateOpt {
    var opt = SymbolDrawUpdateOpt()
    if let area = createCoordSysClipAreaSimply(seriesModel) {
        opt.clipShape = EffectScatterClipShape(area: area)
    }
    return opt
}

// Bridges a `CoordinateSystemClipArea` (from createCoordSysClipAreaSimply) into the `SymbolClipShape`
//   SymbolDraw's `symbolNeedsDraw` gate expects — both declare `contain(_:_:) -> Bool`.
private struct EffectScatterClipShape: SymbolClipShape {
    let area: CoordinateSystemClipArea
    func contain(_ x: Double, _ y: Double) -> Bool { area.contain(x, y) }
}

// export default EffectScatterView;  -> `open class EffectScatterView` above.

// `store.get(...)` returns `ParsedValue` (Any); numeric series data is stored as `Double`. Mirrors the
//   `scatterToNumber` coercion in chart/scatter/ScatterView.swift.
private func effectScatterToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
