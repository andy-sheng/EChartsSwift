// Ported from echarts/src/chart/parallel/ParallelView.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';                 -> `Polyline` / `Group` / `Rect` (ZRenderKit).
//       graphic.updateProps / graphic.initProps ARE ported (animation/basicTransition.swift).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> `states` (util/states.swift). Hover emphasis IS wired: each parallel line carries its
//       emphasis/blur/select lineStyle state styles and is a highDown dispatcher (see updateElCommon).
//       TODO: the parallelAxis brush-based highlight/fade interaction requires
//       component/brush selector interaction (not ported).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import ParallelSeriesModel, { ParallelSeriesDataItemOption } from './ParallelSeries';
//       -> sibling ParallelSeries.swift (assumed ported alongside coord/parallel).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { StageHandlerProgressParams, ParsedValue, Payload } from '../../util/types';  -> util/types.swift.
//   import Parallel from '../../coord/parallel/Parallel';          -> sibling coord/parallel/Parallel.swift.
//   import { OptionAxisType } from '../../coord/axisCommonTypes';  -> OptionAxisType (= String, axisHelper.swift).
//   import { numericToNumber } from '../../util/number';           -> `number.numericToNumber`.
//   import { eqNaN } from 'zrender/src/core/util';                 -> `util.eqNaN` (ZRenderKit).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> `saveOldStyle` (basicTransition.swift).
//   import Element from 'zrender/src/Element';                     -> Element (ZRenderKit).
//   import { getIncrementalId } from '../../util/model';           -> `model.getIncrementalId` (modelUtil.swift).

// upstream: const DEFAULT_SMOOTH = 0.3;
private let DEFAULT_SMOOTH: Double = 0.3

// upstream: interface ParallelDrawSeriesScope { smooth: number }
private struct ParallelDrawSeriesScope {
    var smooth: Double
}

// upstream: class ParallelView extends ChartView { static type = 'parallel'; type = ParallelView.type; ... }
open class ParallelView: ChartView {

    // upstream: static type = 'parallel';  /  type = ParallelView.type;
    public static let parallelType = "parallel"
    open override var type: String {
        get { ParallelView.parallelType }
        set { /* readonly upstream */ }
    }

    // upstream: private _dataGroup = new graphic.Group();
    private let _dataGroup = Group()

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?

    // upstream: private _initialized = false;
    private var _initialized = false

    // upstream: private _progressiveEls: Element[];
    private var _progressiveEls: [Element] = []

    // upstream: init() { this.group.add(this._dataGroup); }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self.group.add(self._dataGroup)
    }

    /**
     * @override
     */
    // upstream: render(seriesModel: ParallelSeriesModel, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: ParallelSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! ParallelSeriesModel

        let dataGroup = self._dataGroup

        // Clear previously rendered progressive elements.
        self._progressiveEls = []
        _ = dataGroup.removeAll()

        let data = seriesModel.getData()
        let oldData = self._data
        // const coordSys = seriesModel.coordinateSystem;
        //   `coordinateSystem` is `Any?` on SeriesModel; narrow to Parallel. Without a parallel coord
        //   attached there is nothing to render — the group is already emptied, so just persist `data`.
        guard let coordSys = seriesModel.coordinateSystem as? Parallel else {
            self._data = data
            return
        }
        let dimensions = coordSys.dimensions
        let seriesScope = makeSeriesScope(seriesModel)

        // upstream:
        //   data.diff(oldData)
        //       .add(add).update(update).remove(remove).execute();
        data.diff(oldData)
            .add { newDataIndex in
                // upstream `add`: create a fresh line for the new datum.
                let line = addEl(data, dataGroup, newDataIndex, dimensions, coordSys)
                updateElCommon(line, data, newDataIndex, seriesScope)
            }
            .update { newDataIndex, oldDataIndex in
                // upstream `update`: reuse the old line, morph its points, save its old style for the
                //   style transition, then re-apply the common visual/state styling.
                guard let oldData = oldData,
                      let line = oldData.getItemGraphicEl(oldDataIndex) as? Polyline else {
                    // No reusable element (missing old graphic el) — fall back to an `add`.
                    let line = addEl(data, dataGroup, newDataIndex, dimensions, coordSys)
                    updateElCommon(line, data, newDataIndex, seriesScope)
                    return
                }
                _ = dataGroup.add(line)

                let points = createLinePoints(data, newDataIndex, dimensions, coordSys)
                data.setItemGraphicEl(newDataIndex, line)

                // graphic.updateProps(line, {shape: {points: points}}, seriesModel, newDataIndex);
                //   Target `shape.points` as [[Double]] (Animator 2D-array interpolation shape) — a
                //   [VectorArray] target SNAPS (0 animators). PolylineShape.animationGet/Set("points")
                //   round-trips [[Double]].
                let ptsD = points.map { [$0.x, $0.y] }
                updateProps(line, ["shape": ["points": ptsD]], seriesModel, newDataIndex)

                saveOldStyle(line)

                updateElCommon(line, data, newDataIndex, seriesScope)
            }
            .remove { oldDataIndex in
                // upstream `remove`: drop the old line from the group. (The group was already emptied
                //   by removeAll() above, so this is typically a no-op — kept for structural fidelity.)
                guard let oldData = oldData,
                      let line = oldData.getItemGraphicEl(oldDataIndex) else {
                    return
                }
                _ = dataGroup.remove(line)
            }
            .execute()

        // First create
        // upstream:
        //   if (!this._initialized) {
        //       this._initialized = true;
        //       const clipPath = createGridClipShape(coordSys, seriesModel, function () {
        //           setTimeout(function () { dataGroup.removeClipPath(); });
        //       });
        //       dataGroup.setClipPath(clipPath);
        //   }
        if !self._initialized {
            self._initialized = true
            let clipPath = createGridClipShape(
                coordSys, seriesModel, {
                    // Callback invoked when the clip-reveal animation completes (or immediately when
                    //   animation is off). Upstream defers via setTimeout(...) to the next tick; the
                    //   port drops the line clip once the reveal finishes.
                    dataGroup.removeClipPath()
                }
            )
            dataGroup.setClipPath(clipPath)
        }

        // this._data = data;
        self._data = data
    }

    // upstream: incrementalPrepareRender(seriesModel, ecModel, api)
    open override func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream:
        //   this._initialized = true; this._data = null; this._dataGroup.removeAll();
        self._initialized = true
        self._data = nil
        _ = self._dataGroup.removeAll()
    }

    // upstream: incrementalRender(taskParams, seriesModel, ecModel)
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        let seriesModel = seriesModelBase as! ParallelSeriesModel
        // const data = seriesModel.getData();
        let data = seriesModel.getData()
        // const coordSys = seriesModel.coordinateSystem;
        guard let coordSys = seriesModel.coordinateSystem as? Parallel else {
            return
        }
        // const progressiveEls: Element[] = this._progressiveEls = [];
        self._progressiveEls = []
        let dimensions = coordSys.dimensions
        let seriesScope = makeSeriesScope(seriesModel)

        // for (let dataIndex = taskParams.start; dataIndex < taskParams.end; dataIndex++) { ... }
        let start = Int(params.start)
        let end = Int(params.end)
        for dataIndex in start..<end {
            let line = addEl(data, self._dataGroup, dataIndex, dimensions, coordSys)
            // line.incremental = getIncrementalId(seriesModel);
            line.incremental = model.getIncrementalId(seriesModel)
            updateElCommon(line, data, dataIndex, seriesScope)
            self._progressiveEls.append(line)
        }
    }

    // upstream: remove() { this._dataGroup && this._dataGroup.removeAll(); this._data = null; }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self._dataGroup.removeAll()
        self._data = nil
    }
}

// upstream: function createGridClipShape(coordSys: Parallel, seriesModel: ParallelSeriesModel, cb: () => void)
private func createGridClipShape(
    _ coordSys: Parallel, _ seriesModel: ParallelSeriesModel, _ cb: @escaping () -> Void
) -> Rect {
    // const parallelModel = coordSys.model;
    let parallelModel = coordSys.model!
    // const rect = coordSys.getRect();
    let rect = coordSys.getRect()
    // const rectEl = new graphic.Rect({ shape: { x, y, width, height } });
    var initialShape = RectShape()
    initialShape.x = rect.x
    initialShape.y = rect.y
    initialShape.width = rect.width
    initialShape.height = rect.height
    let rectEl = Rect(["shape": initialShape])

    // const dim = parallelModel.get('layout') === 'horizontal' ? 'width' : 'height';
    // rectEl.setShape(dim, 0);
    //   The generic `Path.setShape(key, value)` is inert for typed shapes (see Path.swift), so
    //   read-modify-write the value-typed RectShape wholesale (same idiom as createGridClipPath).
    let isHorizontal = (parallelModel.get("layout") as? String) == "horizontal"
    var shape = rectEl.shape as! RectShape
    if isHorizontal {
        shape.width = 0
    }
    else {
        shape.height = 0
    }
    rectEl.shape = shape

    // graphic.initProps(rectEl, { shape: { width: rect.width, height: rect.height } }, seriesModel, cb);
    //   Upstream passes `cb` in the `dataIndex` slot (animateOrSetProps shifts a function arg to `cb`);
    //   the port passes it directly in the `cb` slot. Shape props are a DICT so the animator diffs
    //   per-field (a struct value would just snap to the final shape).
    initProps(rectEl,
              ["shape": ["width": rect.width, "height": rect.height] as [String: Any]],
              seriesModel, nil, cb)
    return rectEl
}

// upstream: function createLinePoints(data, dataIndex, dimensions, coordSys): VectorArray[]
private func createLinePoints(
    _ data: SeriesData, _ dataIndex: Int, _ dimensions: [String], _ coordSys: Parallel
) -> [VectorArray] {
    var points: [VectorArray] = []
    for i in 0..<dimensions.count {
        let dimName = dimensions[i]
        // const value = data.get(data.mapDimension(dimName), dataIndex);
        let mapped = data.mapDimension(dimName)
        let value = mapped != nil ? data.get(mapped!, dataIndex) : nil
        if !isEmptyValue(value, coordSys.getAxis(dimName).type) {
            // `value` is guaranteed non-nil here (isEmptyValue rejects nil); force-unwrap so the call
            //   fits the `dataToPoint(_ value: ScaleDataValue, _ dim: DimensionName) -> [Double]` signature.
            //   The coord returns a `[Double]` pair; PolylineShape.points is `[VectorArray]`, so pack the
            //   pair into a `VectorArray` (SIMD2) — same as LineView.
            let pt = coordSys.dataToPoint(value!, dimName)
            points.append(VectorArray(pt[0], pt[1]))
        }
    }
    return points
}

// upstream: function addEl(data, dataGroup, dataIndex, dimensions, coordSys): graphic.Polyline
@discardableResult
private func addEl(
    _ data: SeriesData, _ dataGroup: Group, _ dataIndex: Int, _ dimensions: [String], _ coordSys: Parallel
) -> Polyline {
    let points = createLinePoints(data, dataIndex, dimensions, coordSys)
    // const line = new graphic.Polyline({ shape: {points: points}, /* silent: true, */ z2: 10 });
    var lineShape = PolylineShape()
    lineShape.points = points
    var lineProps: ElementProps = [:]
    lineProps["shape"] = lineShape as PathShape
    let line = Polyline(lineProps)
    line.z2 = 10
    _ = dataGroup.add(line)
    data.setItemGraphicEl(dataIndex, line)
    return line
}

// upstream: function makeSeriesScope(seriesModel: ParallelSeriesModel): ParallelDrawSeriesScope
private func makeSeriesScope(_ seriesModel: ParallelSeriesModel) -> ParallelDrawSeriesScope {
    // let smooth = seriesModel.get('smooth', true);
    var smoothAny: Any? = seriesModel.get("smooth", true)
    // smooth === true && (smooth = DEFAULT_SMOOTH);
    if (smoothAny as? Bool) == true {
        smoothAny = DEFAULT_SMOOTH
    }
    // smooth = numericToNumber(smooth);
    var smooth = number.numericToNumber(smoothAny)
    // eqNaN(smooth) && (smooth = 0);
    if util.eqNaN(smooth) {
        smooth = 0
    }

    return ParallelDrawSeriesScope(smooth: smooth)
}

// upstream: function updateElCommon(el: graphic.Polyline, data, dataIndex, seriesScope)
private func updateElCommon(
    _ el: Polyline,
    _ data: SeriesData,
    _ dataIndex: Int,
    _ seriesScope: ParallelDrawSeriesScope
) {
    // el.useStyle(data.getItemVisual(dataIndex, 'style'));
    // el.style.fill = null;
    var style = barStyleFromDict(data.getItemVisual(dataIndex, "style"))
    style.fill = nil
    el.useStyle(style)
    // `useStyle`→createStyle lays the style over DEFAULT_PATH_STYLE (fill '#000') and SKIPS the nil
    // `fill`, so `el.style.fill = null` is dropped and each polyline fills as a solid black polygon
    // (visual-parity trap class 1). Clear it directly so parallel lines render as thin strokes.
    el.pathStyle.fill = nil

    // el.setShape('smooth', seriesScope.smooth);
    //   The generic `Path.setShape(key, value)` is inert for typed shapes (see Path.swift), so set the
    //   `smooth` field on a fresh PolylineShape carrying the existing points and reassign via setShape.
    if var shape = el.shape as? PolylineShape {
        shape.smooth = seriesScope.smooth
        _ = el.setShape(shape as PathShape)
    }

    // const itemModel = data.getItemModel<ParallelSeriesDataItemOption>(dataIndex);
    // const emphasisModel = itemModel.getModel('emphasis');
    // setStatesStylesFromModel(el, itemModel, 'lineStyle');
    // toggleHoverEmphasis(el, emphasisModel.get('focus'), emphasisModel.get('blurScope'), emphasisModel.get('disabled'));
    //   Populate the line's emphasis/blur/select state styles from the item's lineStyle model, then mark
    //   the polyline a highDown dispatcher (so a hover over it drives it into emphasis, and blurs the rest
    //   when focus is set). Same idiom as GraphView edges / RadarView polygons.
    let itemModel = data.getItemModel(dataIndex)
    let emphasisModel = itemModel.getModel(["emphasis"])
    states.setStatesStylesFromModel(el, itemModel, "lineStyle")
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
}

// upstream: function isEmptyValue(val: ParsedValue, axisType: OptionAxisType)
//   return axisType === 'category' ? val == null : (val == null || isNaN(val as number));
private func isEmptyValue(_ val: ParsedValue?, _ axisType: OptionAxisType?) -> Bool {
    if axisType == "category" {
        return val == nil
    }
    // axisType === 'value'
    if val == nil {
        return true
    }
    return parallelToNumber(val).isNaN
}

// export default ParallelView;  -> `open class ParallelView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// `data.get(...)`-style numeric coercion for the `isNaN(val)` check in `isEmptyValue`. A non-numeric
//   (e.g. category ordinal string) coerces to NaN, matching JS `isNaN(val as number)`.
private func parallelToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
