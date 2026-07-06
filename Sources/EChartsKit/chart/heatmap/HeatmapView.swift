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
//   import { toggleHoverEmphasis } from '../../util/states';          -> PORT-TODO: `util/states` NOT ported
//     (states/emphasis prerequisite); the ensureState/toggleHoverEmphasis block is deferred.
//   import HeatmapLayer from './HeatmapLayer';                        -> PORT-TODO: canvas-blur layer NOT ported
//     (geo/large-mode only — `_renderOnGeo`, deferred per the heatmap milestone scope).
//   import * as zrUtil from 'zrender/src/core/util';                 -> stdlib / `util` (ZRenderKit).
//   import ChartView from '../../view/Chart';                        -> `ChartView` (view/Chart.swift).
//   import HeatmapSeriesModel, { HeatmapDataItemOption } from './HeatmapSeries';  -> `HeatmapSeriesModel` (sibling).
//   import type GlobalModel from '../../model/Global';               -> `GlobalModel`.
//   import type ExtensionAPI from '../../core/ExtensionAPI';         -> `ExtensionAPI`.
//   import type VisualMapModel from '../../component/visualMap/VisualMapModel';  -> `VisualMapModel`.
//   import type PiecewiseModel / ContinuousModel;                    -> PORT-TODO: geo-path only (deferred).
//   import { GeoLikeCoordSys, isCoordinateSystemType, isGeoLikeCoordSys } from '../../coord/CoordinateSystem';
//     -> `isCoordinateSystemType` used implicitly via the `as? Cartesian2D` downcast; geo helpers deferred.
//   import { StageHandlerProgressParams, Dictionary, OptionDataValue } from '../../util/types';  -> util/types.swift.
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D'; -> `Cartesian2D`.
//   import type Calendar from '../../coord/calendar/Calendar';        -> PORT-TODO: calendar coord NOT wired for heatmap.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//     -> PORT-TODO: `label/labelStyle` NOT ported; the label block is deferred (same as BarView).
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
//   large/progressive path are PORT-TODOs; the matrix/calendar branches are PORT-TODOs (those coord
//   systems are not wired for heatmap yet).

// upstream: function getIsInPiecewiseRange(dataExtent, pieceList, selected) { ... }
// upstream: function getIsInContinuousRange(dataExtent, range) { ... }
// PORT-TODO: both range-test helpers feed `_renderOnGeo` (the canvas-blur layer). Deferred with it.

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
    // PORT-TODO: `HeatmapLayer` (canvas-blur, geo/large mode) NOT ported — `_renderOnGeo` deferred.

    // upstream: private _progressiveEls: Element[];
    private var _progressiveEls: [Element]?

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

        _ = self.group.removeAll()

        // const coordSys = seriesModel.coordinateSystem;
        // if (coordSys.type === 'cartesian2d' || 'calendar' || 'matrix') { this._renderOnGridLike(...); }
        // else if (isGeoLikeCoordSys(coordSys)) { this._renderOnGeo(...); }
        if seriesModel.coordinateSystem is Cartesian2D {
            self._renderOnGridLike(seriesModel, api, 0, seriesModel.getData().count(), false)
        }
        else if let calendar = seriesModel.coordinateSystem as? Calendar {
            self._renderOnCalendar(seriesModel, calendar)
        }
        else {
            // PORT-TODO: matrix `_renderOnGridLike` branch and the geo `_renderOnGeo` (blurred
            //   `HeatmapLayer`) path are deferred.
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

        for idx in 0..<data.count() {
            let point = calendar.dataToPoint(data.get(dateDim, idx))
            guard point.count >= 2, point[0].isFinite, point[1].isFinite else { continue }

            if data.hasItemOption {
                borderRadius = data.getItemModel(idx).get(["itemStyle", "borderRadius"])
            }

            var shape = RectShape()
            shape.x = point[0] - cw / 2
            shape.y = point[1] - ch / 2
            shape.width = cw
            shape.height = ch
            if let r = heatmapRectRadius(borderRadius) { shape.r = r }

            let rect = Rect(["shape": shape as PathShape])
            rect.useStyle(heatmapStyleFromDict(data.getItemVisual(idx, "style")))
            _ = group.add(rect)
            data.setItemGraphicEl(idx, rect)
        }
    }

    // upstream: incrementalPrepareRender(seriesModel, ecModel, api) { this.group.removeAll(); }
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        _ = self.group.removeAll()
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

        // upstream reads the emphasis/blur/select item styles + label state models here.
        // PORT-TODO: emphasis/blur/select item styles + `getLabelStatesModels` + focus/blurScope/
        //   emphasisDisabled are deferred (`util/states` + `label/labelStyle` not ported).

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
                idx += 1
                continue
            }

            // const point = coordSys.dataToPoint([dataDimX, dataDimY]);
            let point = coordSys.dataToPoint([xVal, yVal] as [ScaleDataValue])

            // Optimization for large dataset — if (data.hasItemOption) re-read per-item styles/borderRadius.
            if data.hasItemOption {
                let itemModel = data.getItemModel(idx)
                // PORT-TODO: per-item emphasis/blur/select item styles + label state models deferred
                //   (states/label subsystems not ported).
                // borderRadius = itemModel.get(['itemStyle', 'borderRadius']);
                borderRadius = itemModel.get(["itemStyle", "borderRadius"])
            }

            // rect = new graphic.Rect({ shape: { x, y, width, height }, style });
            var shape = RectShape()
            shape.x = point[0] - width / 2
            shape.y = point[1] - height / 2
            shape.width = width
            shape.height = height
            // rect.shape.r = borderRadius;
            if let r = heatmapRectRadius(borderRadius) {
                shape.r = r
            }

            let rect = Rect(["shape": shape as PathShape])

            // upstream: setLabelStyle(...) — the value label on each cell.
            // PORT-TODO: label block deferred (`label/labelStyle` + `getRawValue` not ported).

            // el.useStyle(style) — the fill color the visualMap encoding wrote + the itemStyle border.
            // PORT-TODO: the item visual 'style' is a `[String: Any]` bag (visual/style.swift); ZRenderKit
            //   `useStyle` takes a typed `PathStyleProps`. `heatmapStyleFromDict` bridges the common paint
            //   keys (fill/stroke/lineWidth/opacity/...) — same deviation as BarView.
            rect.useStyle(heatmapStyleFromDict(style))

            // upstream: ensureState('emphasis'|'blur'|'select') + toggleHoverEmphasis + incremental id +
            //   hover layer. PORT-TODO: states/emphasis + incremental id deferred.

            _ = group.add(rect)
            // data.setItemGraphicEl(idx, rect);
            data.setItemGraphicEl(idx, rect)

            // if (this._progressiveEls) { this._progressiveEls.push(rect); }
            if self._progressiveEls != nil {
                self._progressiveEls!.append(rect)
            }

            idx += 1
        }

        _ = useIncremental
    }

    // upstream: _renderOnGeo(geo, seriesModel, visualMapModel, api) { ... }
    // PORT-TODO: the geo/large blurred `HeatmapLayer` (canvas) path is NOT ported (per the heatmap
    //   milestone scope — the cartesian colored-Rect path above is the deliverable). It needs
    //   `HeatmapLayer` (canvas gradient blur), `visualMapModel.targetVisuals.inRange/outOfRange` color
    //   mappers/normalizers, `geo.getViewRect`/`getRoamTransform`, and `getIsInContinuousRange`/
    //   `getIsInPiecewiseRange`.
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
