// Ported (STATIC SUBSET) from echarts/src/chart/radar/RadarView.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';                 -> `Polyline` / `Polygon` / `Group` (ZRenderKit).
//       PORT-TODO: graphic.initProps / graphic.updateProps (enter/update animation) NOT ported — the
//       static render sets final geometry directly (same deviation as FunnelView/PieView/SunburstView/
//       GraphView/TreeView). `getInitialPoints` (collapse-to-center enter animation) is therefore DROPPED.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported — emphasis/select/blur state styles + hover dispatcher
//       DEFERRED (per CONVENTIONS §5).
//   import * as zrUtil from 'zrender/src/core/util';               -> `zrUtil.defaults` inlined (radarDefaults) / map dropped.
//   import * as symbolUtil from '../../util/symbol';               -> `symbol` namespace (util/symbol.swift).
//       DEVIATION: the vertex symbol is built inline with `symbol.createSymbol` (same deviation as
//       ScatterView / GraphView / TreeView); the `RadarSymbol.__dimIdx` tag + per-symbol enter/update
//       diff (`updateSymbols`) + emphasis states are DEFERRED.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import RadarSeriesModel, { RadarSeriesDataItemOption, SERIES_TYPE_RADAR } from './RadarSeries';
//       -> sibling RadarSeries.swift (assumed ported alongside coord/radar + radarLayout).
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import { ColorString } from '../../util/types';                -> type-only (label inheritColor; labels DEFERRED).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import { VectorArray } from 'zrender/src/core/vector';         -> VectorArray (ZRenderKit).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> PORT-TODO: label/labelStyle NOT ported — vertex value labels DEFERRED.
//   import ZRImage from 'zrender/src/graphic/Image';               -> PORT-TODO: image-symbol branch DEFERRED (inline createSymbol only).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> PORT-TODO: update-transition NOT ported (DEFERRED).

// type RadarSymbol = ReturnType<typeof symbolUtil.createSymbol> & { __dimIdx: number };
//   PORT-TODO: the `__dimIdx` tag is only used by the DEFERRED vertex-label path; symbols are drawn
//   untagged in the static render.

// upstream: class RadarView extends ChartView { static readonly type = SERIES_TYPE_RADAR; readonly type = SERIES_TYPE_RADAR; ... }
open class RadarView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_RADAR;  /  readonly type = SERIES_TYPE_RADAR;
    public static let radarType = SERIES_TYPE_RADAR
    open override var type: String {
        get { SERIES_TYPE_RADAR }
        set { /* readonly upstream */ }
    }

    // upstream: private _data: SeriesData<RadarSeriesModel>;
    private var _data: SeriesData?

    // upstream: render(seriesModel: RadarSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: RadarSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! RadarSeriesModel

        // const polar = seriesModel.coordinateSystem;
        //   PORT-TODO: `polar` (the radar coord) is only read by `getInitialPoints` — the collapse-to-
        //   center enter animation — which is DROPPED with graphic.initProps (animation DEFERRED). The
        //   final vertex positions come from `data.getItemLayout(idx)` (the radarLayout stage already
        //   stored the closed point ring via data.setItemLayout), so the coord is not needed here.
        let group = self.group

        let data = seriesModel.getData()
        // const oldData = this._data;  — PORT-TODO: diff against previous render DEFERRED (rebuild below).

        // -------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream runs a `data.diff(oldData)` add/update/remove pipeline
        //   (create polyline+polygon+symbolGroup per new item, morph points on update, remove on leave)
        //   then a second `data.eachItemGraphicEl` pass that styles line/area/symbols and wires emphasis.
        //   The diff + enter/update/remove animation (initProps/updateProps/saveOldStyle) + emphasis
        //   states (setStatesStylesFromModel/ensureState/toggleHoverEmphasis) + vertex value labels
        //   (setLabelStyle) are all DEFERRED (see PORT-TODOs), so the group is rebuilt from scratch each
        //   render: per data item, one Polyline (outline) + one Polygon (area fill) + one symbol per
        //   vertex, all read from `data.getItemLayout(idx)` (exactly what the diff pipeline consumes).
        // -------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // Series-level fallbacks for the vertex symbol type/size (the visual stage that populates the
        //   per-item 'symbol'/'symbolSize' visuals falls back to the series option when absent).
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 4.0

        for idx in 0..<data.count() {
            // const points = data.getItemLayout(idx);  → closed ring `[[x,y], … , [x,y]]` (last == first copy).
            // if (!points) { return; }
            guard let points = radarPointsFromLayout(data.getItemLayout(idx)), points.count > 0 else {
                continue
            }

            // const itemModel = data.getItemModel<RadarSeriesDataItemOption>(idx);
            let itemModel = data.getItemModel(idx)

            // Radar uses the visual encoded from itemStyle.
            // const itemStyle = data.getItemVisual(idx, 'style');  const color = itemStyle.fill;
            let itemStyle = data.getItemVisual(idx, "style") as? [String: Any]
            let color = itemStyle?["fill"]

            // const itemGroup = new graphic.Group();  const symbolGroup = new graphic.Group();
            //   itemGroup.add(polyline); itemGroup.add(polygon); itemGroup.add(symbolGroup);
            let itemGroup = Group()
            let symbolGroup = Group()

            // --- polyline: new graphic.Polyline(); shape.points = points ------------------------------
            var polylineShape = PolylineShape()
            polylineShape.points = points
            var polylineProps: ElementProps = [:]
            polylineProps["shape"] = polylineShape as PathShape
            let polyline = Polyline(polylineProps)

            // --- polygon: new graphic.Polygon(); shape.points = points --------------------------------
            var polygonShape = PolygonShape()
            polygonShape.points = points
            var polygonProps: ElementProps = [:]
            polygonProps["shape"] = polygonShape as PathShape
            let polygon = Polygon(polygonProps)

            // polyline.useStyle(zrUtil.defaults(
            //     itemModel.getModel('lineStyle').getLineStyle(), { fill: 'none', stroke: color }));
            //   `getLineStyle()` already carries PathStyleProps-keyed values (stroke/lineWidth/opacity/…);
            //   `defaults` fills the missing `stroke` with `color`; `fill: 'none'` maps to a nil fill.
            var lineStyleDict = itemModel.getModel("lineStyle").getLineStyle()
            if lineStyleDict["stroke"] == nil, let color = color { lineStyleDict["stroke"] = color }
            var polylineStyle = barStyleFromDict(lineStyleDict)
            polylineStyle.fill = nil   // upstream default `fill: 'none'`
            polyline.useStyle(polylineStyle)
            // The Polyline vertices close into a pentagon; `useStyle` runs `createStyle` which lays the
            // style over DEFAULT_PATH_STYLE (fill '#000') via `extendPathStyle`, and that helper SKIPS a
            // nil `fill` — so the intended `fill: 'none'` is dropped and the outline fills solid black
            // UNDER the area polygon (visual-parity trap class 1). Clear it directly to bypass the merge.
            polyline.pathStyle.fill = nil

            // setStatesStylesFromModel(polyline, itemModel, 'lineStyle');
            // setStatesStylesFromModel(polygon, itemModel, 'areaStyle');
            //   Populate each shape's emphasis/blur/select state styles from the item's lineStyle/areaStyle
            //   models. The hover dispatcher (toggleHoverEmphasis on itemGroup below) then restyles them.
            states.setStatesStylesFromModel(polyline, itemModel, "lineStyle")
            states.setStatesStylesFromModel(polygon, itemModel, "areaStyle")

            // const areaStyleModel = itemModel.getModel('areaStyle');
            // const polygonIgnore = areaStyleModel.isEmpty() && areaStyleModel.parentModel.isEmpty();
            // polygon.ignore = polygonIgnore;
            let areaStyleModel = itemModel.getModel("areaStyle")
            let polygonIgnore = areaStyleModel.isEmpty() && (areaStyleModel.parentModel?.isEmpty() ?? true)
            polygon.ignore = polygonIgnore

            // zrUtil.each(['emphasis', 'select', 'blur'], function (stateName) { … ensureState … });
            //   PORT-TODO: per-state area/line/item styles + `ensureState(stateName).ignore` DEFERRED
            //   (util/states not ported).

            // polygon.useStyle(zrUtil.defaults(
            //     itemModel.getModel('areaStyle').getAreaStyle(),
            //     { fill: color, opacity: 0.7, decal: itemStyle.decal }));
            //   PORT-TODO: `decal: itemStyle.decal` NOT applied (decal/pattern out of scope).
            var areaStyleDict = areaStyleModel.getAreaStyle()
            if areaStyleDict["fill"] == nil, let color = color { areaStyleDict["fill"] = color }
            if areaStyleDict["opacity"] == nil { areaStyleDict["opacity"] = 0.7 }
            polygon.useStyle(barStyleFromDict(areaStyleDict))
            // Same class-1 guard: when the area has no explicit fill (and no series color), don't let the
            // default black survive the createStyle merge.
            if areaStyleDict["fill"] == nil { polygon.pathStyle.fill = nil }

            // itemGroup.add(polyline);  itemGroup.add(polygon);  itemGroup.add(symbolGroup);
            //   (upstream child order: polyline=childAt(0), polygon=childAt(1), symbolGroup=childAt(2)).
            _ = itemGroup.add(polyline)
            _ = itemGroup.add(polygon)
            _ = itemGroup.add(symbolGroup)

            // --- symbols: updateSymbols(polyline.shape.points, points, symbolGroup, data, idx) --------
            //   Upstream draws one symbol per vertex over `points.length - 1` (the last point is the
            //   closing copy of the first, so it is skipped). Each `createSymbol('… ', -1,-1,2,2)` is
            //   scaled to `symbolSize/2` and centered on the vertex via setPosition; the static build
            //   inlines that as `createSymbol(type, x - w/2, y - h/2, w, h)` (same deviation as Scatter/
            //   Graph). PORT-TODO: symbolRotate / z2:100 / emphasis scale / vertex value labels DEFERRED.
            let symbolType = (data.getItemVisual(idx, "symbol") as? String) ?? seriesSymbol
            if symbolType != "none" {
                let (sizeW, sizeH) = symbol.normalizeSymbolSize(
                    data.getItemVisual(idx, "symbolSize") ?? seriesSymbolSize
                )
                // symbolPath.useStyle(itemStyle); symbolPath.setColor(color); — fill routed through createSymbol.
                var fill: ZRenderKit.ZRColor? = nil
                if let cs = radarColorString(color) { fill = .string(cs) }

                let count = points.count - 1   // skip the closing duplicate vertex
                for i in 0..<count {
                    let pt = points[i]
                    let el = symbol.createSymbol(
                        symbolType, pt.x - sizeW / 2, pt.y - sizeH / 2, sizeW, sizeH, fill
                    )
                    if let path = el as? Path {
                        path.name = "vertex"
                        // PORT-TODO: symbolPath.style.strokeNoScale = true — not applied (same deviation as
                        //   Scatter/Graph; the symbol style is set inside createSymbol via setColor).
                        _ = symbolGroup.add(path)
                    }
                    // PORT-TODO: setLabelStyle(symbolPath, …) — vertex value label DEFERRED (labelStyle not ported).
                }
            }

            // const emphasisModel = itemModel.getModel('emphasis');
            // toggleHoverEmphasis(itemGroup, emphasisModel.get('focus'), emphasisModel.get('blurScope'),
            //     emphasisModel.get('disabled'));
            //   Marks the whole itemGroup (line + area + vertex symbols) a highDown dispatcher; a hover
            //   over any child resolves up to this group and drives the series row into emphasis.
            //   PORT-TODO: the per-state symbol itemStyle clone (symbolPath.ensureState(...).style) and the
            //   per-state polygon.ignore toggle are still deferred (styling niceties, not the dispatcher).
            let emphasisModel = itemModel.getModel(["emphasis"])
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(itemGroup, focus, blurScope, isDisabled)

            // group.add(itemGroup);  data.setItemGraphicEl(idx, itemGroup);
            _ = group.add(itemGroup)
            data.setItemGraphicEl(idx, itemGroup)
        }

        // this._data = data;
        self._data = data
    }

    // upstream: remove() { this.group.removeAll(); this._data = null; }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.group.removeAll()
        self._data = nil
    }
}

// export default RadarView;  -> `open class RadarView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// `data.getItemLayout(idx)` stores the radarLayout point ring — an array of `[x, y]` vertices (stored as
//   `[VectorArray]`, `[[Double]]`, or `[[Any]]`). Coerce to `[VectorArray]`. Returns nil when there is no
//   layout (upstream `!points`).
private func radarPointsFromLayout(_ v: Any?) -> [VectorArray]? {
    if let pts = v as? [VectorArray] { return pts }
    if let arr = v as? [[Double]] {
        return arr.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
    }
    if let arr = v as? [Any] {
        var out: [VectorArray] = []
        out.reserveCapacity(arr.count)
        for e in arr {
            guard let p = radarNumberArray(e), p.count >= 2 else { return nil }
            out.append(VectorArray(p[0], p[1]))
        }
        return out
    }
    return nil
}

// Coerce a dynamic `[x, y]`-ish array (stored as `[Double]`, `[Any]`, or `[NSNumber]`) to `[Double]`.
private func radarNumberArray(_ v: Any?) -> [Double]? {
    if let d = v as? [Double] { return d }
    if let p = v as? VectorArray { return [p.x, p.y] }
    if let arr = v as? [Any] { return arr.map { radarToNumber($0) } }
    return nil
}

// The palette color lands under the item visual style as an EChartsKit `ZRColor.color(String)` or a raw
//   `String`. Bridge both to a solid color string (same bridge as ScatterView / GraphView / TreeView).
//   Gradient / pattern out of scope.
private func radarColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// `store.get(...)`-style numeric coercion for a dynamic layout value.
private func radarToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
