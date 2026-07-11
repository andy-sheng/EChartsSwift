// Ported (STATIC SUBSET) from echarts/src/chart/heatmap/HeatmapView.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import * as graphic from '../../util/graphic';                    -> `Rect` is the ZRenderKit shape.
//     PORT-TODO: `graphic.traverseElements` not ported; `eachRendered` traverses the group directly.
//   import { toggleHoverEmphasis } from '../../util/states';          -> `util/states` (util/states.swift);
//     `toggleHoverEmphasis` is now wired at the cell (see `_renderOnGridLike`, alongside setStatesStylesFromModel).
//   import HeatmapLayer from './HeatmapLayer';                        -> PORT-TODO: canvas-blur layer NOT ported
//     (geo/large-mode only — `_renderOnGeo`, deferred per the heatmap milestone scope).
//   import * as zrUtil from 'zrender/src/core/util';                 -> stdlib / `util` (ZRenderKit).
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import HeatmapSeriesModel, { HeatmapDataItemOption } from './HeatmapSeries';  -> `HeatmapSeriesModel` (sibling).
//   import type GlobalModel from '../../model/Global';               -> `GlobalModel`.
//   import type ExtensionAPI from '../../core/ExtensionAPI';         -> `ExtensionAPI`.
//   import type VisualMapModel from '../../component/visualMap/VisualMapModel';  -> `VisualMapModel`.
//   import type PiecewiseModel / ContinuousModel;                    -> component/visualMap/{PiecewiseModel,ContinuousModel}.swift (ported; only needed by the deferred geo path).
//   import { GeoLikeCoordSys, isCoordinateSystemType, isGeoLikeCoordSys } from '../../coord/CoordinateSystem';
//     -> `isCoordinateSystemType` used implicitly via the `as? Cartesian2D` downcast; geo helpers deferred.
//   import { StageHandlerProgressParams, Dictionary, OptionDataValue } from '../../util/types';  -> util/types.swift.
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D`.
//   import type Calendar from '../../coord/calendar/Calendar';        -> coord/calendar/Calendar.swift (ported; not wired into heatmap yet).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//     -> `labelStyle.setLabelStyle` / `labelStyle.getLabelStatesModels` (label/labelStyle.swift); the
//        per-cell value label is wired in `_renderOnGridLike` (same pattern as BarView).
//   import type Element from 'zrender/src/Element';                   -> `Element` (ZRenderKit).
//   import type Matrix from '../../coord/matrix/Matrix';              -> PORT-TODO: matrix coord NOT wired for heatmap.
//   import { calcBandWidth } from '../../coord/axisBand';             -> `calcBandWidth` (coord/axisBand.swift).
//   import { getIncrementalId } from '../../util/model';              -> PORT-TODO: incremental pipeline deferred.
//
// PORT SCOPE (per the heatmap milestone): the CARTESIAN2D colored-Rect path of `_renderOnGridLike` is the
//   deliverable. One `Rect` per data item is placed at the cell (centered on `coord.dataToPoint([x, y])`,
//   sized to the axis band width/height + 0.5px), FILLED with the per-datum color the visualMap encoding
//   already wrote into the item visual `style` (visual/style + component/visualMap/visualEncoding →
//   `data.getItemVisual(idx, 'style')`). The blurred canvas `HeatmapLayer` (`_renderOnGeo`) and the
//   large/progressive path are PORT-TODOs; the matrix/calendar coord branches are not wired for heatmap
//   yet (the coord systems themselves are ported: coord/matrix/Matrix.swift, coord/calendar/Calendar.swift).

// upstream: function getIsInContinuousRange(dataExtent, range) { ... }
//   Returns a predicate over a NORMALIZED value (0..1): true iff it lands inside the visualMap
//   `range` mapped into normalized space. Feeds `_renderOnGeo` (the blurred HeatmapLayer).
private func getIsInContinuousRange(_ dataExtent: [Double], _ rangeIn: [Double]) -> (Double) -> Bool {
    let dataSpan = dataExtent[1] - dataExtent[0]
    // range = [(range[0]-dataExtent[0])/dataSpan, (range[1]-dataExtent[0])/dataSpan];
    let r0 = (rangeIn[0] - dataExtent[0]) / dataSpan
    let r1 = (rangeIn[1] - dataExtent[0]) / dataSpan
    // return function (val) { return val >= range[0] && val <= range[1]; };
    return { val in val >= r0 && val <= r1 }
}

// upstream: function getIsInPiecewiseRange(dataExtent, pieceList, selected) { ... }
//   `pieceList` is each piece's `[lo, hi]` interval; `selected` is a per-piece-index selected flag.
//   The upstream `lastIndex` scan optimization is dropped (a plain scan is result-identical).
private func getIsInPiecewiseRange(
    _ dataExtent: [Double], _ pieceList: [[Double]], _ selected: [Bool]
) -> (Double) -> Bool {
    let dataSpan = dataExtent[1] - dataExtent[0]
    // pieceList = map(pieceList, piece => ({ interval: [(lo-e0)/span, (hi-e0)/span] }));
    let normed = pieceList.map { p -> [Double] in
        [(p[0] - dataExtent[0]) / dataSpan, (p[1] - dataExtent[0]) / dataSpan]
    }
    let len = normed.count
    return { val in
        for i in 0..<len {
            let interval = normed[i]
            if interval[0] <= val && val <= interval[1] {
                return i < selected.count ? selected[i] : true
            }
        }
        return false
    }
}

// upstream: class HeatmapView extends ChartView { static readonly type = 'heatmap'; type = HeatmapView.type; ... }
open class HeatmapView: ChartView {

    // upstream: static readonly type = 'heatmap';  /  readonly type = HeatmapView.type;
    //   The base `ChartView.type` is a settable stored `var` (default "chart"), so it is assigned in
    //   `init` (can't override a read-write stored property with a read-only computed one) — same as
    //   ScatterView.
    public static let type = "heatmap"

    public override init() {
        super.init()
        self.type = HeatmapView.type
    }

    // upstream: private _hmLayer: HeatmapLayer;
    //   The canvas-blur layer used by the geo path (`_renderOnGeo`) — ported as `HeatmapLayer`
    //   (chart/heatmap/HeatmapBlurLayer.swift). Cached across renders like upstream.
    private var _hmLayer: HeatmapLayer?

    // upstream: private _progressiveEls: Element[];
    private var _progressiveEls: [Element]?

    // Persistent per-cell rects for the CARTESIAN grid morph path (L5 transition fidelity). Keyed by
    //   DATA index. On a merge-mode setOption value change that keeps the same cell count, the existing
    //   cell Rect is REUSED and its fill (and geometry, if the grid resized) is `updateProps`-morphed to
    //   the new visualMap color instead of `group.removeAll()`-rebuilding and snapping. `_prevCellCount`
    //   (the DATA count of the previous cartesian render) gates morph-vs-rebuild; a cell-count change (or
    //   a first render / incremental render / a non-cartesian branch) rebuilds fresh and resets these.
    private var _cellRects: [Int: Rect] = [:]
    private var _prevCellCount: Int = -1

    // Drop the persistent cartesian cell state — called when a non-cartesian branch (calendar/geo) or an
    //   incremental render wipes the group, so a later cartesian render can't reuse detached rects.
    private func _resetCellState() {
        self._cellRects = [:]
        self._prevCellCount = -1
    }

    // upstream: render(seriesModel, ecModel, api) { ... }
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: HeatmapSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModel as! HeatmapSeriesModel

        // let visualMapOfThisSeries;
        // ecModel.eachComponent('visualMap', function (visualMap) {
        //     visualMap.eachTargetSeries(function (targetSeries) {
        //         if (targetSeries === seriesModel) { visualMapOfThisSeries = visualMap; }
        //     });
        // });
        var visualMapOfThisSeries: VisualMapModel? = nil
        ecModel.eachComponent("visualMap") { (componentModel: ComponentModel, _ idx: Double) in
            guard let visualMap = componentModel as? VisualMapModel else { return }
            visualMap.eachTargetSeries { targetSeries in
                if targetSeries === seriesModel {
                    visualMapOfThisSeries = visualMap
                }
            }
        }

        // if (__DEV__) { if (!visualMapOfThisSeries) { throw new Error('Heatmap must use with visualMap'); } }
        if __DEV__ {
            if visualMapOfThisSeries == nil {
                // Swift `render` cannot throw; reproduce the dev-only guard with an assertion (traps in
                //   debug, no-op in release). Return after so nothing is drawn (the encoding never ran,
                //   so items have no color — matching upstream aborting on the throw).
                assertionFailure("Heatmap must use with visualMap")
                return
            }
        }

        // Clear previously rendered progressive elements.
        self._progressiveEls = nil

        // const coordSys = seriesModel.coordinateSystem;
        // if (coordSys.type === 'cartesian2d' || 'calendar' || 'matrix') { this._renderOnGridLike(...); }
        // else if (isGeoLikeCoordSys(coordSys)) { this._renderOnGeo(...); }
        if seriesModel.coordinateSystem is Cartesian2D {
            // NOTE: the cartesian path does NOT `group.removeAll()` up front — it morphs the persistent
            //   cell rects when the cell count is unchanged (see `_renderOnGridLike`), and only wipes on a
            //   rebuild (cell-count change / first render).
            self._renderOnGridLike(seriesModel, api, 0, seriesModel.getData().count(), false)
        }
        else if let calendar = seriesModel.coordinateSystem as? Calendar {
            // Non-cartesian branches rebuild fresh: wipe the group and drop the cartesian cell state.
            _ = self.group.removeAll()
            self._resetCellState()
            self._renderOnCalendar(seriesModel, calendar)
        }
        else if let geo = seriesModel.coordinateSystem as? Geo {
            _ = self.group.removeAll()
            self._resetCellState()
            // else if (isGeoLikeCoordSys(coordSys)) { this._renderOnGeo(coordSys, seriesModel, vm, api); }
            if let vm = visualMapOfThisSeries {
                self._renderOnGeo(geo, seriesModel, vm, api)
            }
        }
        else {
            // PORT-TODO: matrix `_renderOnGridLike` branch is deferred.
            _ = self.group.removeAll()
            self._resetCellState()
        }
    }

    // Calendar heatmap: one visualMap-colored cell Rect per datum, sized to the calendar cell and
    //   centered on `calendar.dataToPoint(date)`. (The cartesian _renderOnGridLike equivalent for the
    //   calendar coord — the day cell replaces the x/y band cell.)
    private func _renderOnCalendar(_ seriesModel: SeriesModel, _ calendar: Calendar) {
        let group = self.group
        let data = seriesModel.getData()
        let cw = calendar.getCellWidth()
        let ch = calendar.getCellHeight()
        let dateDim = data.getDimension(0)   // dim 0 = the date/time value
        var borderRadius = seriesModel.get(["itemStyle", "borderRadius"])

        // Hover wiring params (upstream shares the _renderOnGridLike state block; HeatmapView.ts:202-210).
        var stateModel: Model = seriesModel
        var emphasisModel = seriesModel.getModel(["emphasis"])
        var focus: InnerFocus? = emphasisModel.get("focus")
        var blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        var emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        for idx in 0..<data.count() {
            let point = calendar.dataToPoint(data.get(dateDim, idx))
            guard point.count >= 2, point[0].isFinite, point[1].isFinite else { continue }

            if data.hasItemOption {
                // Per-item re-read (upstream HeatmapView.ts:290-308 — the shared grid-like state block).
                let itemModel = data.getItemModel(idx)
                stateModel = itemModel
                emphasisModel = itemModel.getModel(["emphasis"])
                focus = emphasisModel.get("focus")
                blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
                emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
                borderRadius = itemModel.get(["itemStyle", "borderRadius"])
            }

            var shape = RectShape()
            shape.x = point[0] - cw / 2
            shape.y = point[1] - ch / 2
            shape.width = cw
            shape.height = ch
            if let r = heatmapRectRadius(borderRadius) { shape.r = r }

            let rect = Rect(["shape": shape as PathShape])
            // Entrance animation (opacity fade-in) — same as the cartesian cell path.
            var cellStyle = heatmapStyleFromDict(data.getItemVisual(idx, "style"))
            let finalOpacity = cellStyle.opacity ?? 1
            cellStyle.opacity = 0
            rect.useStyle(cellStyle)
            initProps(rect, ["style": ["opacity": finalOpacity] as [String: Any]], seriesModel, idx)
            rect.name = "item"
            // upstream (HeatmapView.ts:329-333): the calendar cell gets the same hover wiring.
            states.setStatesStylesFromModel(rect, stateModel)
            states.toggleHoverEmphasis(rect, focus, blurScope, emphasisDisabled)
            _ = group.add(rect)
            data.setItemGraphicEl(idx, rect)
        }
    }

    // upstream: incrementalPrepareRender(seriesModel, ecModel, api) { this.group.removeAll(); }
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        _ = self.group.removeAll()
        // Incremental mode appends rects untracked; drop the morph state so a later full render rebuilds.
        self._resetCellState()
    }

    // upstream: incrementalRender(params, seriesModel, ecModel, api) { ... }
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModel as! HeatmapSeriesModel
        // const coordSys = seriesModel.coordinateSystem;
        // if (coordSys) { if (isGeoLikeCoordSys) { this.render(...); } else { ...; this._renderOnGridLike(...); } }
        if seriesModel.coordinateSystem is Cartesian2D {
            self._progressiveEls = []
            // params.start/.end are `Double` (TaskProgressParams); the grid loop indexes `Int`.
            self._renderOnGridLike(seriesModel, api, Int(params.start), Int(params.end), true)
        }
        else {
            // PORT-TODO: geo incremental → `this.render(...)`; matrix/calendar deferred.
        }
    }

    // upstream: eachRendered(cb) { graphic.traverseElements(this._progressiveEls || this.group, cb); }
    open override func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // PORT-TODO: `util/graphic.traverseElements` not ported. When `_progressiveEls` exists, visit each
        //   (incremental mode); otherwise traverse the group via `Group.traverse` (children only — same
        //   note as BarView.eachRendered / view/Chart.swift).
        if let progressiveEls = self._progressiveEls {
            for el in progressiveEls {
                _ = cb(el)
            }
        }
        else {
            self.group.traverse(cb)
        }
    }

    // upstream: _renderOnGridLike(seriesModel, api, start, end, useIncremental?) { ... }
    //   Only the CARTESIAN2D branch is ported (matrix/calendar deferred).
    func _renderOnGridLike(
        _ seriesModel: HeatmapSeriesModel,
        _ api: ExtensionAPI,
        _ start: Int,
        _ end: Int,
        _ useIncremental: Bool
    ) {
        // const coordSys = seriesModel.coordinateSystem as Cartesian2D | Calendar | Matrix;
        // const isCartesian2d = isCoordinateSystemType<Cartesian2D>(coordSys, 'cartesian2d');
        guard let coordSys = seriesModel.coordinateSystem as? Cartesian2D else {
            // PORT-TODO: matrix/calendar `_renderOnGridLike` branches deferred.
            return
        }

        // if (isCartesian2d) { ... }
        // const xAxis = coordSys.getAxis('x'); const yAxis = coordSys.getAxis('y');
        let xAxis = coordSys.getAxis("x")!
        let yAxis = coordSys.getAxis("y")!

        if __DEV__ {
            // if (!(xAxis.type === 'category' && yAxis.type === 'category')) throw 'two category axes'
            if !(xAxis.type == "category" && yAxis.type == "category") {
                assertionFailure("Heatmap on cartesian must have two category axes")
            }
            // if (!(xAxis.onBand && yAxis.onBand)) throw 'two axes with boundaryGap true'
            if !(xAxis.onBand && yAxis.onBand) {
                assertionFailure("Heatmap on cartesian must have two axes with boundaryGap true")
            }
        }

        // add 0.5px to avoid the gaps
        // width = calcBandWidth(xAxis).w + .5;  height = calcBandWidth(yAxis).w + .5;
        let width = calcBandWidth(xAxis).w + 0.5
        let height = calcBandWidth(yAxis).w + 0.5
        // xAxisExtent = xAxis.scale.getExtent();  yAxisExtent = yAxis.scale.getExtent();
        let xAxisExtent = xAxis.scale.getExtent()
        let yAxisExtent = yAxis.scale.getExtent()

        let group = self.group
        let data = seriesModel.getData()

        // ── Morph decision (L5 transition fidelity, cartesian only) ──────────────────────────────
        //   A full (non-incremental) render REUSES the persistent per-cell rects when the cell count is
        //   unchanged (a merge-mode value change → same cells, new colors). Then per cell the fill (and
        //   geometry, if the grid resized) is `updateProps`-morphed toward its new value. Otherwise (first
        //   render, cell-count change, or incremental) rebuild fresh: wipe the group and drop the state.
        let canMorph = !useIncremental && !self._cellRects.isEmpty && self._prevCellCount == data.count()
        if !useIncremental && !canMorph {
            _ = group.removeAll()
            self._cellRects = [:]
        }

        // upstream reads the emphasis/blur/select item styles + focus/blurScope/emphasisDisabled here
        //   (HeatmapView.ts:202-210). The three per-state style bags are applied via
        //   `setStatesStylesFromModel` at the cell (mirrors BarView.updateStyle).
        //   `getLabelStatesModels` is read per cell (from `stateModel`) with the label block below.
        var stateModel: Model = seriesModel
        var emphasisModel = seriesModel.getModel(["emphasis"])
        var focus: InnerFocus? = emphasisModel.get("focus")
        var blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        var emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        // let borderRadius = seriesModel.get(['itemStyle', 'borderRadius']);
        var borderRadius = seriesModel.get(["itemStyle", "borderRadius"])

        // const dataDims = isCartesian2d ? [mapDimension('x'), mapDimension('y'), mapDimension('value')] : ...
        // PORT-TODO: `mapDimension` is force-unwrapped — a heatmap's x/y/value dims are always present.
        let dataDimX = data.mapDimension("x")!
        let dataDimY = data.mapDimension("y")!
        let dataDimValue = data.mapDimension("value")!

        // for (let idx = start; idx < end; idx++) { ... }
        var idx = start
        while idx < end {
            // const style = data.getItemVisual(idx, 'style');
            let style = data.getItemVisual(idx, "style")

            // isCartesian2d branch:
            // const dataDimX = data.get(dataDims[0], idx); const dataDimY = data.get(dataDims[1], idx);
            let xVal = heatmapToNumber(data.get(dataDimX, idx))
            let yVal = heatmapToNumber(data.get(dataDimY, idx))
            let value = heatmapToNumber(data.get(dataDimValue, idx))

            // Ignore empty data and out of extent data
            // if (isNaN(value) || isNaN(x) || isNaN(y) || x < xExtent[0] || x > xExtent[1]
            //     || y < yExtent[0] || y > yExtent[1]) continue;
            if value.isNaN
                || xVal.isNaN
                || yVal.isNaN
                || xVal < xAxisExtent[0]
                || xVal > xAxisExtent[1]
                || yVal < yAxisExtent[0]
                || yVal > yAxisExtent[1] {
                // On morph, a cell that WAS valid but is now empty/out-of-extent must be removed so it
                //   doesn't linger with its old color.
                if let old = self._cellRects[idx] {
                    _ = group.remove(old)
                    self._cellRects[idx] = nil
                }
                idx += 1
                continue
            }

            // const point = coordSys.dataToPoint([dataDimX, dataDimY]);
            let point = coordSys.dataToPoint([xVal, yVal] as [ScaleDataValue])

            // Optimization for large dataset — if (data.hasItemOption) re-read per-item styles/borderRadius.
            if data.hasItemOption {
                // upstream (HeatmapView.ts:290-308): per-item re-read of the emphasis params + state
                //   styles (`stateModel` feeds setStatesStylesFromModel below).
                let itemModel = data.getItemModel(idx)
                stateModel = itemModel
                emphasisModel = itemModel.getModel(["emphasis"])
                focus = emphasisModel.get("focus")
                blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
                emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
                // borderRadius = itemModel.get(['itemStyle', 'borderRadius']);
                borderRadius = itemModel.get(["itemStyle", "borderRadius"])
            }

            // Cell geometry (grid position fixed by the coord; band width/height + 0.5px).
            let cellX = point[0] - width / 2
            let cellY = point[1] - height / 2

            // el.useStyle(style) — the fill color the visualMap encoding wrote + the itemStyle border.
            // PORT-TODO: the item visual 'style' is a `[String: Any]` bag (visual/style.swift); ZRenderKit
            //   `useStyle` takes a typed `PathStyleProps`. `heatmapStyleFromDict` bridges the common paint
            //   keys (fill/stroke/lineWidth/opacity/...) — same deviation as BarView.
            var cellStyle = heatmapStyleFromDict(style)
            let finalOpacity = cellStyle.opacity ?? 1
            // Extract the visualMap-encoded fill as a color STRING (the shape the Animator's color-tween
            //   path consumes) so it can be morphed via `updateProps({style:{fill:...}})`.
            let fillColorStr: String? = { if case let .string(s)? = cellStyle.fill { return s }; return nil }()

            if canMorph, let rect = self._cellRects[idx] {
                // ── MORPH the reused cell (merge-mode value change) ──────────────────────────────────
                //   For heatmap the meaningful transition is the FILL COLOR (and geometry if the grid
                //   resized). Apply the non-animated paint keys (stroke/lineWidth/borderRadius) instantly
                //   while PRESERVING the current fill/opacity, then `updateProps` tweens fill (current →
                //   new visualMap color), opacity, and the rect geometry to the new value.
                var instantStyle = cellStyle
                instantStyle.fill = rect.pathStyle?.fill        // keep current color — animate it below
                instantStyle.opacity = rect.pathStyle?.opacity  // keep current opacity — animate it below
                rect.useStyle(instantStyle)
                // Corner radii are not tweened (RectShape.animationSet omits `r`); set instantly on the
                //   shape struct (setShape(key,value) is a no-op for typed shapes, so mutate + replace).
                if var rectShape = rect.shape as? RectShape {
                    rectShape.r = heatmapRectRadius(borderRadius)
                    _ = rect.setShape(rectShape)
                }

                var styleProps: [String: Any] = ["opacity": finalOpacity]
                if let fc = fillColorStr { styleProps["fill"] = fc }
                updateProps(
                    rect,
                    [
                        "shape": ["x": cellX, "y": cellY, "width": width, "height": height] as [String: Any],
                        "style": styleProps
                    ],
                    seriesModel, idx
                )
                // Keep the reused cell's hover wiring current (upstream re-runs the state block each
                //   render pass — HeatmapView.ts:329-333).
                states.setStatesStylesFromModel(rect, stateModel)
                states.toggleHoverEmphasis(rect, focus, blurScope, emphasisDisabled)
                data.setItemGraphicEl(idx, rect)
                idx += 1
                continue
            }

            // ── BUILD a fresh cell (first render / rebuild / newly-valid cell on morph) ───────────────
            // rect = new graphic.Rect({ shape: { x, y, width, height }, style });
            var shape = RectShape()
            shape.x = cellX
            shape.y = cellY
            shape.width = width
            shape.height = height
            // rect.shape.r = borderRadius;
            if let r = heatmapRectRadius(borderRadius) {
                shape.r = r
            }

            let rect = Rect(["shape": shape as PathShape])

            // upstream (HeatmapView.ts:308-327): setLabelStyle(...) — the value label on each cell.
            //   `labelStatesModels` comes from `stateModel` (the seriesModel, or the itemModel when
            //   `hasItemOption`), matching upstream's getLabelStatesModels(seriesModel|itemModel).
            //   defaultText = the raw value dim `rawValue[2]` coerced to a string (JS `rawValue[2] + ''`
            //   == format._strOrNil), falling back to '-'. -> labelStyle + dataFormat.getRawValue ported.
            let labelStatesModels = labelStyle.getLabelStatesModels(stateModel)
            var defaultLabelText = "-"
            if let rawArr = seriesModel.getRawValue(Double(idx)) as? [Any],
               rawArr.count > 2,
               !(rawArr[2] is NSNull),
               let s = format._strOrNil(rawArr[2]) {
                defaultLabelText = s
            }
            var labelOpt = SetLabelStyleOpt()
            labelOpt.labelFetcher = seriesModel
            labelOpt.labelDataIndex = Double(idx)
            labelOpt.defaultOpacity = cellStyle.opacity
            labelOpt.defaultText = defaultLabelText
            labelStyle.setLabelStyle(rect, labelStatesModels, labelOpt)

            // Entrance animation (opacity fade-in, mirroring FunnelPiece): construct the cell at opacity 0,
            //   then `initProps({style:{opacity}})` toward the intended (visualMap-encoded) final opacity.
            //   With series animation off, `initProps` falls back to an instant `attr` of the partial
            //   "style" dict (Path.attrKV merge) so the cell lands at its final, VISIBLE opacity.
            cellStyle.opacity = 0
            rect.useStyle(cellStyle)
            initProps(rect, ["style": ["opacity": finalOpacity] as [String: Any]], seriesModel, idx)

            // Name the cell 'item' (matches PieView/BarView/FunnelView per-datum element name; upstream
            //   leaves it unset — a harmless, non-load-bearing addition for hit-testing/debug parity).
            rect.name = "item"

            // upstream (HeatmapView.ts:329-333): ensureState('emphasis'|'blur'|'select').style +
            //   toggleHoverEmphasis — the cell's hover wiring (setStatesStylesFromModel covers the three
            //   ensureState style assignments). PORT-TODO: incremental id + hover layer deferred.
            states.setStatesStylesFromModel(rect, stateModel)
            states.toggleHoverEmphasis(rect, focus, blurScope, emphasisDisabled)

            _ = group.add(rect)
            // Persist the cell for a later morph (cartesian full-render path only).
            if !useIncremental {
                self._cellRects[idx] = rect
            }
            // data.setItemGraphicEl(idx, rect);
            data.setItemGraphicEl(idx, rect)

            // if (this._progressiveEls) { this._progressiveEls.push(rect); }
            if self._progressiveEls != nil {
                self._progressiveEls!.append(rect)
            }

            idx += 1
        }

        // Record the DATA count driving the next morph-vs-rebuild decision (full cartesian render only).
        if !useIncremental {
            self._prevCellCount = data.count()
        }
    }

    // upstream: _renderOnGeo(geo, seriesModel, visualMapModel, api) { ... }
    //   The geo/large blurred `HeatmapLayer` path: each datum's [lng,lat,value] is projected to a
    //   viewport pixel, stamped as a radial-alpha blob by `HeatmapLayer`, and the accumulated alpha
    //   is colorized by the visualMap gradient into a `CGImage`, blitted via a single `ZRImage`.
    func _renderOnGeo(
        _ geo: Geo,
        _ seriesModel: HeatmapSeriesModel,
        _ visualMapModel: VisualMapModel,
        _ api: ExtensionAPI
    ) {
        // const inRangeVisuals = visualMapModel.targetVisuals.inRange;
        // const outOfRangeVisuals = visualMapModel.targetVisuals.outOfRange;
        guard let inRangeVisuals = visualMapModel.targetVisuals["inRange"] as? [String: VisualMapping],
              let colorMappingIn = inRangeVisuals["color"] else {
            // Data range must have color visuals — nothing to colorize.
            return
        }
        let outOfRangeVisuals = visualMapModel.targetVisuals["outOfRange"] as? [String: VisualMapping]
        let colorMappingOut = outOfRangeVisuals?["color"]

        let data = seriesModel.getData()

        // const hmLayer = this._hmLayer || (this._hmLayer = new HeatmapLayer());
        let hmLayer = self._hmLayer ?? HeatmapLayer()
        self._hmLayer = hmLayer
        // hmLayer.blurSize/pointSize/minOpacity/maxOpacity = seriesModel.get(...)
        hmLayer.blurSize = heatmapGetNumber(seriesModel.get("blurSize"), 30)
        hmLayer.pointSize = heatmapGetNumber(seriesModel.get("pointSize"), 20)
        hmLayer.minOpacity = heatmapGetNumber(seriesModel.get("minOpacity"), 0)
        hmLayer.maxOpacity = heatmapGetNumber(seriesModel.get("maxOpacity"), 1)

        // const rect = geo.getViewRect().clone(); rect.applyTransform(geo.getRoamTransform());
        let rect = geo.getViewRect().clone()
        let roamTransform = geo.getRoamTransform()
        rect.applyTransform(roamTransform)

        // Clamp on viewport
        let x = Swift.max(rect.x, 0)
        let y = Swift.max(rect.y, 0)
        let x2 = Swift.min(rect.width + rect.x, api.getWidth())
        let y2 = Swift.min(rect.height + rect.y, api.getHeight())
        let width = x2 - x
        let height = y2 - y

        // const dims = [mapDimension('lng'), mapDimension('lat'), mapDimension('value')];
        let dims: [Any] = [
            data.mapDimension("lng") as Any,
            data.mapDimension("lat") as Any,
            data.mapDimension("value") as Any
        ]

        // const points = data.mapArray(dims, (lng, lat, value) => { const pt = geo.dataToPoint([lng, lat]);
        //   pt[0] -= x; pt[1] -= y; pt.push(value); return pt; });
        let points: [[Double]] = data.mapArray(dims) { args -> Any? in
            let lng = heatmapToNumber(args.count > 0 ? args[0] : nil)
            let lat = heatmapToNumber(args.count > 1 ? args[1] : nil)
            let value = heatmapToNumber(args.count > 2 ? args[2] : nil)
            let pt = geo.dataToPoint([lng, lat] as Any) ?? [0, 0]
            let px = (pt.count > 0 ? pt[0] : 0) - x
            let py = (pt.count > 1 ? pt[1] : 0) - y
            return [px, py, value]
        }.compactMap { $0 as? [Double] }

        // const dataExtent = visualMapModel.getExtent();
        let dataExtent = visualMapModel.getExtent()

        // const isInRange = type === 'visualMap.continuous' ? getIsInContinuousRange(...) : getIsInPiecewiseRange(...);
        let isInRange: (Double) -> Bool
        if visualMapModel.type == "visualMap.continuous", let cm = visualMapModel as? ContinuousModel {
            let range = heatmapCoerceDoubleArray(cm.get("range")) ?? dataExtent
            isInRange = getIsInContinuousRange(dataExtent, range)
        }
        else if let pm = visualMapModel as? PiecewiseModel {
            var pieceIntervals: [[Double]] = []
            var selected: [Bool] = []
            for piece in pm.getPieceList() {
                let interval = heatmapCoerceDoubleArray(piece["interval"]) ?? [Double.nan, Double.nan]
                pieceIntervals.append(interval)
                // upstream: selected[i] keyed by piece INDEX. The port keys `option.selected` by the
                //   piece map key; best-effort look up by index string, defaulting to selected (true).
                // PORT-TODO: exact selected-key parity with PiecewiseModel.getSelectedMapKey.
                let idx = Int(heatmapToNumber(piece["index"]))
                let sel = (pm.get("selected") as? [String: Any])?[String(idx)]
                selected.append((sel as? Bool) ?? true)
            }
            isInRange = getIsInPiecewiseRange(dataExtent, pieceIntervals, selected)
        }
        else {
            isInRange = { _ in true }
        }

        // hmLayer.update(points, width, height, inRangeVisuals.color.getNormalizer(),
        //   { inRange: ...getColorMapper(), outOfRange: ...getColorMapper() }, isInRange);
        let normalizer = colorMappingIn.getNormalizer()
        let noopMapper: ColorMapper = { _, _, _ in [0.0, 0.0, 0.0, 0.0] as Any }
        let colorFunc: [String: ColorMapper] = [
            "inRange": colorMappingIn.getColorMapper?() ?? noopMapper,
            "outOfRange": colorMappingOut?.getColorMapper?() ?? noopMapper
        ]

        let cgImage = hmLayer.update(
            points,
            Int(width.rounded()),
            Int(height.rounded()),
            { (v: Double) in normalizer(v) },
            colorFunc,
            isInRange
        )
        guard let cgImage = cgImage else {
            // Empty viewport / no colorized output.
            return
        }

        // const img = new graphic.Image({ style: { width, height, x, y, image: hmLayer.canvas }, silent: true });
        var style = ImageStyleProps()
        style.width = width
        style.height = height
        style.x = x
        style.y = y
        style.image = .image(cgImage)
        let img = ZRImage()
        img.useStyle(style)
        img.silent = true
        // this.group.add(img);
        _ = self.group.add(img)
    }
}

// seriesModel.get(...) option numbers box Int OR Double (INT-vs-DOUBLE trap) — coerce with a default.
private func heatmapGetNumber(_ v: Any?, _ fallback: Double) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return fallback
}

// Coerce an option value to `[Double]` (visualMap `range` / a piece `interval`), boxing Int/Double.
private func heatmapCoerceDoubleArray(_ v: Any?) -> [Double]? {
    if let arr = v as? [Double] { return arr }
    if let arr = v as? [Any] {
        let nums = arr.map { e -> Double in
            if let d = e as? Double { return d }
            if let i = e as? Int { return Double(i) }
            if let n = e as? NSNumber { return n.doubleValue }
            return Double.nan
        }
        return nums
    }
    return nil
}

// export default HeatmapView;  -> `open class HeatmapView` above.

// `data.get(...)` returns `ParsedValue` (Any); numeric heatmap data (and category ordinal numbers) are
//   stored as `Double`. Mirrors `scatterToNumber` in chart/scatter/ScatterView.swift.
private func heatmapToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// upstream: `rect.shape.r = borderRadius` where borderRadius is `number | number[]`. Bridge the option
//   value (Int-boxed defaults must not be read as `Double` — see the INT-vs-DOUBLE trap) to `RectRadius`.
private func heatmapRectRadius(_ v: Any?) -> RectRadius? {
    if let d = v as? Double { return .number(d) }
    if let i = v as? Int { return .number(Double(i)) }
    if let n = v as? NSNumber { return .number(n.doubleValue) }
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] {
        let nums = arr.compactMap { e -> Double? in
            if let d = e as? Double { return d }
            if let i = e as? Int { return Double(i) }
            if let n = e as? NSNumber { return n.doubleValue }
            return nil
        }
        if nums.count == arr.count { return .array(nums) }
    }
    return nil
}

// PORT-TODO: `util/graphic`-level `useStyle(dict)` bridge — the item visual 'style' is a `[String: Any]`
//   bag (visual/style.swift, with the visualMap-encoded `fill`); ZRenderKit `Path.useStyle` takes a typed
//   `PathStyleProps`. Maps the common paint keys so cells are actually colored. Gradient/pattern fills,
//   decal, and lineDash are not bridged yet. Same deviation as BarView's `barStyleFromDict`.
private func heatmapStyleFromDict(_ style: Any?) -> PathStyleProps {
    var s = PathStyleProps()
    guard let d = style as? [String: Any] else { return s }
    // The visual/style stage stores paint colors as EChartsKit `ZRColor` (the visualMap-encoded color is
    //   `.color("#...")`) OR as a raw `String`. Bridge both to the ZRenderKit `ZRColor.string` (solid
    //   colors only; gradient/pattern out of scope for the static render).
    func colorString(_ v: Any?) -> String? {
        if let str = v as? String { return str }
        if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
        return nil
    }
    if let v = colorString(d["fill"]) { s.fill = .string(v) }
    if let v = colorString(d["stroke"]) { s.stroke = .string(v) }
    if let v = d["opacity"] as? Double { s.opacity = v }
    if let v = d["fillOpacity"] as? Double { s.fillOpacity = v }
    if let v = d["strokeOpacity"] as? Double { s.strokeOpacity = v }
    if let v = d["lineWidth"] as? Double { s.lineWidth = v }
    if let v = d["lineCap"] as? String { s.lineCap = v }
    if let v = d["lineJoin"] as? String { s.lineJoin = v }
    if let v = d["miterLimit"] as? Double { s.miterLimit = v }
    if let v = d["shadowBlur"] as? Double { s.shadowBlur = v }
    if let v = d["shadowColor"] as? String { s.shadowColor = v }
    if let v = d["shadowOffsetX"] as? Double { s.shadowOffsetX = v }
    if let v = d["shadowOffsetY"] as? Double { s.shadowOffsetY = v }
    return s
}
