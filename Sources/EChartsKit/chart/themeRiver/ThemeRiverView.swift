// Ported from echarts/src/chart/themeRiver/ThemeRiverView.ts — keep in sync with upstream
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
//   import {ECPolygon} from '../line/poly';
//       -> PORT-TODO: `ECPolygon` (the line chart's dual-edge `points`/`stackedOnPoints` smoothed area
//          polygon) is NOT ported. A STATIC theme-river band is reproduced here with a plain
//          `ZRenderKit.Polygon` whose ring traces the top edge (points0) forward then the bottom edge
//          (points1) back — the same closed area ECPolygon fills, minus the `smooth: 0.4` /
//          `stackedOnSmooth: 0.4` Bézier smoothing (smoothing deferred).
//   import * as graphic from '../../util/graphic';
//       -> `Polygon` is the ZRenderKit shape. PORT-TODO: `util/graphic` (Group, Rect, initProps/
//          updateProps) — the `graphic.Rect` clip + `updateProps` are on the deferred animation path.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported (states/emphasis deferred).
//   import {setLabelStyle, getLabelStatesModels} from '../../label/labelStyle';
//       -> PORT-TODO: label/labelStyle NOT ported (the per-layer label is deferred — see block below).
//   import {bind} from 'zrender/src/core/util';                    -> Swift closures.
//   import DataDiffer from '../../data/DataDiffer';
//       -> PORT-TODO: the add/update/remove diff is collapsed into a from-scratch rebuild (STATIC render).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import ThemeRiverSeriesModel, { SERIES_TYPE_THEME_RIVER } from './ThemeRiverSeries';
//       -> sibling ThemeRiverSeries.swift (assumed).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { RectLike } from 'zrender/src/core/BoundingRect';      -> ZRenderKit.RectLike.
//   import { ColorString } from '../../util/types';                -> util/types (label-only; deferred).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> PORT-TODO: NOT ported (deferred).

// upstream: type LayerSeries = ReturnType<ThemeRiverSeriesModel['getLayerSeries']>;
//   PORT-TODO (sibling contract): `ThemeRiverSeriesModel.getLayerSeries()` is ASSUMED to return
//   `[[String: Any]]`, one dictionary per layer with keys:
//     - "name":    String   (the layer / series name — the diff key)
//     - "indices": [Int]    (data indices of that layer, sorted by the `single` (time) dimension)
//   mirroring upstream's `{ name: string, indices: number[] }[]`. If the ported ThemeRiverSeries
//   returns a typed struct instead, adjust the accesses in `render` accordingly.

// upstream: class ThemeRiverView extends ChartView
open class ThemeRiverView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_THEME_RIVER;  /  readonly type = SERIES_TYPE_THEME_RIVER;
    public static let themeRiverType = SERIES_TYPE_THEME_RIVER
    open override var type: String {
        get { SERIES_TYPE_THEME_RIVER }
        set { /* readonly upstream */ }
    }

    // upstream: private _layersSeries: LayerSeries;
    //   Retained state for the (deferred) DataDiffer; unused by the STATIC rebuild but kept for
    //   structural fidelity / a future diff port.
    private var _layersSeries: [[String: Any]]?
    // upstream: private _layers: graphic.Group[] = [];
    private var _layers: [Group] = []

    // upstream: render(seriesModel: ThemeRiverSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: ThemeRiverSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! ThemeRiverSeriesModel
        // const data = seriesModel.getData();
        let data = seriesModel.getData()

        // const group = this.group;
        let group = self.group

        // const layersSeries = seriesModel.getLayerSeries();
        let layersSeries = seriesModel.getLayerSeries()

        // const layoutInfo = data.getLayout('layoutInfo');
        //   layoutInfo == { rect: RectLike, boundaryGap: (string|number)[] } (set by themeRiverLayout).
        //   Stored as a `[String: Any]` bag (SeriesData layout convention).
        guard let layoutInfo = data.getLayout("layoutInfo") as? [String: Any],
              // const rect = layoutInfo.rect;
              let rect = layoutInfo["rect"] as? RectLike,
              // const boundaryGap = layoutInfo.boundaryGap;
              let boundaryGap = layoutInfo["boundaryGap"] as? [Any]
        else {
            // An unlaid-out series can not be positioned; render nothing (upstream assumes layout ran).
            _ = group.removeAll()
            self._layersSeries = layersSeries
            self._layers = []
            return
        }

        // group.x = 0;
        group.x = 0
        // group.y = rect.y + boundaryGap[0];
        //   boundaryGap[0] was resolved to a Double by themeRiverLayout (parsePercent). Read via numOpt
        //   so a bare Int does not silently drop (INT-vs-DOUBLE option-read trap).
        group.y = rect.y + (numOpt(boundaryGap.first) ?? 0)

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream drives a `DataDiffer` (keyGetter = layer name) that adds /
        //   updates / removes per-layer `graphic.Group`s each holding one `ECPolygon`, then animates
        //   (`updateProps` / grid clip) and attaches an emphasis-aware label. The diff + ECPolygon +
        //   smoothing + label + emphasis + animation are all deferred (see the import PORT-TODOs), so
        //   the group is rebuilt from scratch and every layer is drawn as a plain filled band.
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        var newLayersGroups: [Group] = []

        // for each layer (upstream: dataDiffer.add/update, both run `process`)
        for layer in layersSeries {
            // const indices = layersSeries[idx].indices;
            guard let indices = layer["indices"] as? [Int], !indices.isEmpty else {
                continue
            }

            // const points0: number[] = [];  (top edge)  /  const points1: number[] = [];  (bottom edge)
            var points0: [VectorArray] = []
            var points1: [VectorArray] = []
            // let style;
            var styleBag: Any? = nil

            // for (; j < indices.length; j++) { ... }
            for idx in indices {
                // const layout = data.getItemLayout(indices[j]);  == { layerIndex, x, y0, y }
                guard let layout = data.getItemLayout(idx) as? [String: Any] else {
                    continue
                }
                // const x = layout.x;  const y0 = layout.y0;  const y = layout.y;
                let x = numOpt(layout["x"]) ?? 0
                let y0 = numOpt(layout["y0"]) ?? 0
                let y = numOpt(layout["y"]) ?? 0

                // points0.push(x, y0);
                points0.append(VectorArray(x, y0))
                // points1.push(x, y0 + y);
                points1.append(VectorArray(x, y0 + y))

                // style = data.getItemVisual(indices[j], 'style');
                styleBag = data.getItemVisual(idx, "style")
            }

            // upstream 'add' branch: new graphic.Group() holding a new ECPolygon; the 'update' branch
            //   reuses the old group's child. Both collapse to: build the band group fresh.
            //   const layerGroup = new graphic.Group();
            let layerGroup = Group()

            // polygon = new ECPolygon({ shape: { points: points0, stackedOnPoints: points1,
            //   smooth: 0.4, stackedOnSmooth: 0.4, smoothConstraint: false }, z2: 0 });
            //   STATIC reproduction: a plain Polygon whose ring is the top edge forward + the bottom
            //   edge reversed (the closed area ECPolygon fills; smoothing deferred).
            var polygonShape = PolygonShape()
            polygonShape.points = points0 + points1.reversed()
            polygonShape.smooth = 0
            let polygon = Polygon(["shape": polygonShape as PathShape])
            polygon.z2 = 0

            // polygon.useStyle(style);
            //   The item visual 'style' bag → typed `PathStyleProps` via the shared bridge (BarView).
            polygon.useStyle(barStyleFromDict(styleBag))

            // Name the band 'item' (per-datum element name, matching FunnelView/PieView; upstream leaves
            //   it unset — harmless, for hit-testing/debug parity).
            polygon.name = "item"

            // layerGroup.add(polygon);  group.add(layerGroup);
            _ = layerGroup.add(polygon)
            _ = group.add(layerGroup)
            newLayersGroups.append(layerGroup)

            // data.setItemGraphicEl(idx, polygon);  (upstream keys by the diff `idx`; the last data index
            //   of the layer is the closest static analogue — upstream also labels indices[j - 1]).
            if let last = indices.last {
                data.setItemGraphicEl(last, polygon)
            }

            // PORT-TODO (DEFERRED):
            //   - Animation: `polygon.setClipPath(createGridClipShape(...))` grid-reveal + `updateProps`
            //     + `saveOldStyle` (basicTransition / initProps). `createGridClipShape` is NOT ported.
            //   - Label: `setLabelStyle(polygon, getLabelStatesModels(seriesModel), { labelDataIndex,
            //     defaultText: data.getName(indices[j-1]), inheritColor: style.fill }, { normal:
            //     { verticalAlign: 'middle' } })` + `setTextConfig({ position: null, local: true })` +
            //     positioning the text at `(textLayout.x - margin, textLayout.y0 + textLayout.y / 2)`.
            //   - Emphasis / states: `setStatesStylesFromModel(polygon, seriesModel)` +
            //     `toggleHoverEmphasis(polygon, focus, blurScope, disabled)`.
        }

        // this._layersSeries = layersSeries;  this._layers = newLayersGroups;
        self._layersSeries = layersSeries
        self._layers = newLayersGroups
    }

    // The base `ChartView.remove`/`dispose` carry (ecModel, api); upstream ThemeRiverView does not
    //   override them (default ChartView.remove clears the group), so neither is overridden here.
}

// PORT-TODO (DEFERRED — animation): upstream's module-level `createGridClipShape(rect, seriesModel, cb)`
//   builds a `graphic.Rect` clip that expands (width 0 → rect.width + 100) via `graphic.initProps` for
//   the grid-reveal entrance, removing itself on complete. Reproduce alongside the initProps/updateProps
//   animation port.

// export default ThemeRiverView;  -> `open class ThemeRiverView` above.

// upstream numbers are all `number`; option/layout bags store bare Int literals. Read numerics through
//   this (Int|Double|NSNumber → Double) so an Int is never silently dropped by `as? Double`
//   (INT-vs-DOUBLE option-read trap). Local to this file.
private func numOpt(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}
