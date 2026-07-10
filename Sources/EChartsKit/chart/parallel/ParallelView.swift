// Ported (STATIC SUBSET) from echarts/src/chart/parallel/ParallelView.ts — keep in sync with upstream.
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
//       PORT-TODO: graphic.updateProps / graphic.initProps (enter/update animation) NOT ported — the
//       static render sets final geometry directly (same deviation as RadarView / FunnelView / GraphView).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> `states` (util/states.swift). Hover emphasis IS wired: each parallel line carries its
//       emphasis/blur/select lineStyle state styles and is a highDown dispatcher (see updateElCommon).
//       PORT-TODO: the parallelAxis brush-based highlight/fade interaction remains DEFERRED per the
//       phase brief.
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
//   import { saveOldStyle } from '../../animation/basicTransition'; -> PORT-TODO: update-transition NOT ported (DEFERRED).
//   import Element from 'zrender/src/Element';                     -> Element (ZRenderKit); progressive path DEFERRED.
//   import { getIncrementalId } from '../../util/model';           -> PORT-TODO: progressive/large path DEFERRED.

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
    // PORT-TODO: progressive/large render path DEFERRED — kept for structural parity.
    private var _progressiveEls: [Element] = []

    // Persistent per-item polylines (index-keyed) so a merge-mode setOption VALUE change MORPHS each
    //   line (its shape.points slide) instead of rebuild-and-snap. The static port has no `data.diff`
    //   add/update/remove pipeline, so `_prevItemCount` gates morph-vs-rebuild: a same-count value
    //   change morphs the persisted lines; an item add/remove (or coord loss) rebuilds fresh (keeping
    //   the opacity-fade entrance). Reset to `[]` / `-1` whenever a branch wipes `_dataGroup`.
    private var _lines: [Polyline] = []
    private var _prevItemCount: Int = -1

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

        let data = seriesModel.getData()
        // const oldData = this._data;
        //   PORT-TODO: full `data.diff(oldData)` add/update/remove pipeline still DEFERRED. The reuse
        //   slice below implements the upstream `update` path (updateProps shape morph) for the
        //   same-item-count case; a count change falls back to the static rebuild (`add` path only).
        // const coordSys = seriesModel.coordinateSystem;
        guard let coordSys = seriesModel.coordinateSystem as? Parallel else {
            // PORT-TODO: no parallel coord attached — nothing to render. Drop persisted lines so a later
            //   coord re-attach rebuilds fresh (can't morph against a stale group).
            _ = dataGroup.removeAll()
            self._lines = []
            self._prevItemCount = -1
            self._data = data
            return
        }
        let dimensions = coordSys.dimensions
        let seriesScope = makeSeriesScope(seriesModel)

        let itemCount = data.count()
        // MORPH iff we already drew a line per current item and the item COUNT is unchanged (only values
        //   moved). Then reuse each persisted polyline and animate its shape.points to the new geometry
        //   (upstream's `update` closure: updateProps(line, {shape:{points}})). Otherwise rebuild fresh.
        let canMorph = !self._lines.isEmpty && self._prevItemCount == itemCount && self._lines.count == itemCount

        if canMorph {
            for dataIndex in 0..<itemCount {
                let line = self._lines[dataIndex]
                let points = createLinePoints(data, dataIndex, dimensions, coordSys)
                // Re-apply style/emphasis (parallelVisual may have re-dimmed the line via item-visual
                //   `style.opacity`; color/state styles may have changed) WITHOUT the enter fade — the
                //   line is already on-screen, so land its final opacity directly.
                updateElCommon(line, data, dataIndex, seriesScope, seriesModel, morph: true)
                data.setItemGraphicEl(dataIndex, line)
                // Morph the polyline: target as [[Double]] (Animator 2D-array interpolation shape) — a
                //   [VectorArray] target SNAPS (0 animators). PolylineShape.animationGet/Set("points")
                //   already round-trips [[Double]].
                let ptsD = points.map { [$0.x, $0.y] }
                updateProps(line, ["shape": ["points": ptsD]], seriesModel, dataIndex)
            }
        } else {
            // Rebuild fresh: wipe the group, drop stale lines, replay the `add` path (with enter fade).
            _ = dataGroup.removeAll()
            self._lines = []
            for dataIndex in 0..<itemCount {
                let line = addEl(data, dataGroup, dataIndex, dimensions, coordSys)
                updateElCommon(line, data, dataIndex, seriesScope, seriesModel, morph: false)
                self._lines.append(line)
            }
        }
        self._prevItemCount = itemCount

        // First create
        // upstream:
        //   if (!this._initialized) {
        //       this._initialized = true;
        //       const clipPath = createGridClipShape(coordSys, seriesModel, function () { … removeClipPath … });
        //       dataGroup.setClipPath(clipPath);
        //   }
        // PORT-TODO: the enter clip-reveal animation (createGridClipShape + setClipPath + removeClipPath)
        //   is DEFERRED (graphic.initProps / clip-path animation not ported). `_initialized` is still
        //   flipped for structural parity.
        if !self._initialized {
            self._initialized = true
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
        // PORT-TODO: progressive/large render path DEFERRED; base bookkeeping kept for parity.
        self._initialized = true
        self._data = nil
        _ = self._dataGroup.removeAll()
        self._lines = []
        self._prevItemCount = -1
    }

    // upstream: incrementalRender(taskParams, seriesModel, ecModel)
    open override func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream:
        //   const data = seriesModel.getData();
        //   const coordSys = seriesModel.coordinateSystem;
        //   const progressiveEls = this._progressiveEls = [];
        //   for (let dataIndex = taskParams.start; dataIndex < taskParams.end; dataIndex++) {
        //       const line = addEl(data, this._dataGroup, dataIndex, coordSys.dimensions, coordSys);
        //       line.incremental = getIncrementalId(seriesModel);
        //       updateElCommon(line, data, dataIndex, makeSeriesScope(seriesModel));
        //       progressiveEls.push(line);
        //   }
        // PORT-TODO: progressive/large render path DEFERRED (getIncrementalId / line.incremental /
        //   StageHandlerProgressParams start/end streaming not ported). No-op for the static subset.
    }

    // upstream: remove() { this._dataGroup && this._dataGroup.removeAll(); this._data = null; }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self._dataGroup.removeAll()
        self._data = nil
        self._lines = []
        self._prevItemCount = -1
    }
}

// upstream: function createGridClipShape(coordSys: Parallel, seriesModel: ParallelSeriesModel, cb: () => void)
// PORT-TODO: enter clip-reveal (Rect clip growing along the layout axis) is DEFERRED — depends on
//   graphic.initProps (animation not ported). Left unported; see the `_initialized` block in `render`.

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
    _ seriesScope: ParallelDrawSeriesScope,
    _ seriesModel: ParallelSeriesModel,
    morph: Bool = false
) {
    // el.useStyle(data.getItemVisual(dataIndex, 'style'));
    // el.style.fill = null;
    var style = barStyleFromDict(data.getItemVisual(dataIndex, "style"))
    style.fill = nil
    // ENTRANCE ANIMATION (port deviation): upstream ParallelView reveals lines via a growing clip-path
    //   (createGridClipShape + setClipPath, DEFERRED — clip-path animation not ported). Approximate the
    //   enter with the shared opacity-fade infra (FunnelView/HeatmapView idiom): capture the final opacity
    //   BEFORE zeroing it (invisible-line guard), build the line at opacity 0, then animate toward the
    //   final opacity via `initProps` (instant `attr` when animation is off — `Path.attrKV`'s partial
    //   "style"-dict merge lands the final opacity so the line is never left invisible).
    // On a MORPH reuse the line is already on-screen: skip the zero/fade and land the final opacity
    //   directly so brush/emphasis re-dimming (parallelVisual's item-visual `style.opacity`) still lands.
    let finalOpacity = style.opacity ?? 1.0
    if !morph {
        style.opacity = 0
    }
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
    //   when focus is set). Same idiom as GraphView edges / RadarView polygons. The per-state area/line
    //   `ensureState(...).ignore` niceties in the radar path have no parallel analogue here.
    let itemModel = data.getItemModel(dataIndex)
    let emphasisModel = itemModel.getModel(["emphasis"])
    states.setStatesStylesFromModel(el, itemModel, "lineStyle")
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)

    // Enter-fade toward the captured final opacity (see the opacity note above where it was zeroed). On
    //   a morph reuse the style already carries the final opacity (no zeroing), so no fade is scheduled.
    if !morph {
        initProps(el, ["style": ["opacity": finalOpacity] as [String: Any]], seriesModel, dataIndex)
    }
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
