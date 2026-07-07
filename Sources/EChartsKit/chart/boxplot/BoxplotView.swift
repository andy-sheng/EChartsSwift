// Ported from echarts/src/chart/boxplot/BoxplotView.ts — keep in sync with upstream
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
//   import ChartView from '../../view/Chart';                             -> ChartView (view/Chart.swift).
//   import * as graphic from '../../util/graphic';                        -> initProps/updateProps (DEFERRED, see below).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-TODO: emphasis/hover states DEFERRED per task scope.
//   import Path, { PathProps } from 'zrender/src/graphic/Path';           -> Path / PathProps (ZRenderKit).
//   import BoxplotSeriesModel, { SERIES_TYPE_BOXPLOT, BoxplotDataItemOption } from './BoxplotSeries';
//       -> sibling BoxplotSeries.swift (SERIES_TYPE_BOXPLOT / BoxplotSeriesModel).
//   import GlobalModel from '../../model/Global';                         -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                   -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                       -> SeriesData.
//   import { BoxplotItemLayout } from './boxplotLayout';                  -> sibling boxplotLayout.swift.
//   import { saveOldStyle } from '../../animation/basicTransition';       -> PORT-TODO: animation DEFERRED.
//   import { resolveNormalBoxClipping } from '../helper/whiskerBoxCommon';-> PORT-TODO: clipping DEFERRED.
//   import { createClipPath, SHAPE_CLIP_KIND_*, updateClipPath } from '../helper/createClipPathFromCoordSys';
//       -> PORT-TODO: clipping DEFERRED (see render()).
//   import { map } from 'zrender/src/core/util';                         -> Swift Array.map (transInit).


// upstream: class BoxplotView extends ChartView
open class BoxplotView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_BOXPLOT; readonly type = SERIES_TYPE_BOXPLOT;
    public static let type = SERIES_TYPE_BOXPLOT

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?

    // upstream: render(seriesModel, ecModel, api)
    open override func render(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed param `seriesModel: BoxplotSeriesModel`.
        let seriesModel = seriesModel as! BoxplotSeriesModel

        let data = seriesModel.getData()
        let group = self.group
        // let oldData = this._data;   -> unused below (the diff machinery is DEFERRED).

        // There is no old data only when first rendering or switching from
        // stream mode to normal mode, where previous elements should be removed.
        // PORT-TODO: `data.diff(oldData)` incremental enter/update/remove is DEFERRED — we clear the
        //   group and rebuild every datum from scratch each render (same static strategy as LineView).
        //   Preserved upstream structure for the diffable surface; see the commented `.diff()` chain below.
        if self._data == nil {
            _ = group.removeAll()
        }
        _ = group.removeAll()

        let constDim = seriesModel.getWhiskerBoxesLayout() == "horizontal" ? 1 : 0
        // upstream: needClip / coordSys / clipArea / clipPath — clipping is DEFERRED.
        // PORT-TODO: `needClip = seriesModel.get('clip', true)`, `createClipPath(...)`, and
        //   `resolveNormalBoxClipping(clipArea, itemLayout)` (SHAPE_CLIP_KIND_* + updateClipPath) DEFERRED.

        // upstream (diff chain), ported as a straight loop over every datum:
        //   data.diff(oldData)
        //     .add(newIdx => { if (data.hasValue(newIdx)) { ...createNormalBox(..., true)... } })
        //     .update(...).remove(...).execute();
        for newIdx in 0..<data.count() {
            if data.hasValue(newIdx) {
                let itemLayout = data.getItemLayout(newIdx) as! BoxplotItemLayout

                // PORT-TODO: clipKind (resolveNormalBoxClipping) DEFERRED — always treated as NOT_CLIPPED.

                let symbolEl = createNormalBox(itemLayout, data, newIdx, constDim, true)
                // PORT-TODO: updateClipPath(partiallyClipped, symbolEl, clipPath) DEFERRED.

                data.setItemGraphicEl(newIdx, symbolEl)
                _ = group.add(symbolEl)
            }
        }

        self._data = data
    }

    // upstream: remove(ecModel: GlobalModel)
    // PORT-TODO: the ported ChartView.remove signature is `(ecModel, api)`; the `api` param is unused
    //   here (dropped upstream). Faithful body below.
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let group = self.group
        let data = self._data
        self._data = nil
        data?.eachItemGraphicEl({ el, _ in
            _ = group.remove(el)
        })
    }
}

// upstream: class BoxPathShape { points: number[][]; }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker (see Sector.swift).
//   `points` is the layout `ends` array: the 4 body corners followed by the whisker/median line endpoints.
public struct BoxPathShape: PathShape {
    public var points: [[Double]] = []

    public init() {}

    // Keyed access for animateTo({shape: {points}}) — mirrors PolygonShape. `points` is a 2D array the
    //   Animator's 2D-array interpolation consumes.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "points": return points
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "points":
            if let arr = value as? [[Double]] { points = arr }
        default: break
        }
    }
}

// upstream: interface BoxPathProps extends PathProps { shape?: Partial<BoxPathShape> }
// PORT-TODO: the typed-props interface collapses onto the dynamic PathProps bag (see Sector.swift).
public typealias BoxPathProps = PathProps

// upstream: class BoxPath extends Path<BoxPathProps>
public final class BoxPath: Path {

    // upstream: readonly type = 'boxplotBoxPath'; shape: BoxPathShape;

    // upstream: constructor(opts?: BoxPathProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "boxplotBoxPath"
    }

    public override func getDefaultShape() -> PathShape {
        return BoxPathShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! BoxPathShape
        let ends = shape.points

        // Faithful C-style walk: `i` is mutated across the two loops (CONVENTIONS §7 — kept as `while`).
        var i = 0
        _ = ctx.moveTo(ends[i][0], ends[i][1])
        i += 1
        while i < 4 {
            _ = ctx.lineTo(ends[i][0], ends[i][1])
            i += 1
        }
        _ = ctx.closePath()

        while i < ends.count {
            _ = ctx.moveTo(ends[i][0], ends[i][1])
            i += 1
            _ = ctx.lineTo(ends[i][0], ends[i][1])
            i += 1
        }
    }
}

// upstream: function createNormalBox(itemLayout, data, dataIndex, constDim, isInit?)
private func createNormalBox(
    _ itemLayout: BoxplotItemLayout,
    _ data: SeriesData,
    _ dataIndex: Int,
    _ constDim: Int,
    _ isInit: Bool = false
) -> BoxPath {
    let ends = itemLayout.ends

    let el = BoxPath()
    var shape = BoxPathShape()
    shape.points = isInit
        ? transInit(ends, constDim, itemLayout)
        : ends
    el.setShape(shape)

    updateNormalBoxData(itemLayout, el, data, dataIndex, isInit)

    return el
}

// upstream: function updateNormalBoxData(itemLayout, el, data, dataIndex, isInit?)
private func updateNormalBoxData(
    _ itemLayout: BoxplotItemLayout,
    _ el: BoxPath,
    _ data: SeriesData,
    _ dataIndex: Int,
    _ isInit: Bool = false
) {
    // upstream:
    //   const seriesModel = data.hostModel;
    //   const updateMethod = graphic[isInit ? 'initProps' : 'updateProps'];
    //   updateMethod(el, {shape: {points: itemLayout.ends}}, seriesModel, dataIndex);
    //   FAITHFUL POINTS-GROW: `el` was built with the COLLAPSED points (transInit collapses the box ends
    //   to itemLayout.initBaseline along constDim — see createNormalBox). initProps/updateProps then
    //   tweens the box's points-array shape from that collapsed start to the final `itemLayout.ends`.
    //   `points` MUST be passed as the raw [[Double]] dict value (NOT a full BoxPathShape struct — a
    //   struct snaps to final) so the Animator's 2D-array interpolation carries collapsed → final. When
    //   the series has animation off, animateOrSetProps assigns the final points instantly (visible box).
    let pointsProp: [String: Any] = ["shape": ["points": itemLayout.ends] as [String: Any]]
    if isInit {
        initProps(el, pointsProp, data.hostModel, dataIndex)
    } else {
        updateProps(el, pointsProp, data.hostModel, dataIndex)
    }

    // upstream: el.useStyle(data.getItemVisual(dataIndex, 'style')); el.style.strokeNoScale = true;
    //   The item visual 'style' is a `[String: Any]` bag; bridge it to a typed PathStyleProps
    //   (reusing the bar-render bridge) and set strokeNoScale before useStyle.
    var st = barStyleFromDict(data.getItemVisual(dataIndex, "style"))
    st.strokeNoScale = true
    el.useStyle(st)

    // upstream: el.z2 = 100;
    el.z2 = 100

    // upstream:
    //   const itemModel = data.getItemModel(dataIndex);
    //   const emphasisModel = itemModel.getModel('emphasis');
    //   setStatesStylesFromModel(el, itemModel);
    //   toggleHoverEmphasis(el, emphasisModel.get('focus'), emphasisModel.get('blurScope'), emphasisModel.get('disabled'));
    //   Marks `el` a highDown dispatcher carrying its emphasis-state itemStyle so a hover restyles it.
    let itemModel = data.getItemModel(dataIndex)
    let emphasisModel = itemModel.getModel(["emphasis"])
    states.setStatesStylesFromModel(el, itemModel)
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
}

// upstream: function transInit(points: number[][], dim: number, itemLayout: BoxplotItemLayout)
private func transInit(_ points: [[Double]], _ dim: Int, _ itemLayout: BoxplotItemLayout) -> [[Double]] {
    return points.map { point in
        var point = point   // point.slice()
        point[dim] = itemLayout.initBaseline
        return point
    }
}

// export default BoxplotView;  -> `open class BoxplotView` above.
