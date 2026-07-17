// Ported from echarts/src/chart/radar/RadarView.ts — keep in sync with upstream.
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
//       graphic.initProps IS wired for the enter animation: `getInitialPoints` (collapse-to-center) is
//       ported faithfully as a `points`-array grow (see `buildRadarItem`). graphic.updateProps (update
//       morph) + the `data.diff(oldData)` add/update/remove pipeline ARE wired (see `render`): a merge-mode
//       refresh REUSES each retained itemGroup and tweens its polyline/polygon `shape.points` (the reset fix).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> `states` (util/states.swift). Wired: each item's polyline/polygon carry their emphasis/blur/
//       select line/area state styles and the whole itemGroup is a highDown dispatcher (focus:self blurs
//       the other polygons). PORT-NOTE (deferred): the per-state symbol itemStyle clone + per-state
//       polygon.ignore toggle remain deferred (styling niceties, not the dispatcher).
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
//       -> label/labelStyle.swift (setLabelStyle + getLabelStatesModels ARE ported). PORT-NOTE (deferred):
//          the vertex value-label block (upstream RadarView.ts:235-265) remains DEFERRED — it needs the
//          per-symbol `__dimIdx` tag + a symbolGroup styling loop (neither ported; symbols are drawn
//          untagged by buildRadarSymbols) to source defaultText via
//          getStore().get(getDimensionIndex(__dimIdx), idx) and pass it through SetLabelStyleOpt.
//   import ZRImage from 'zrender/src/graphic/Image';               -> PORT-NOTE: image-symbol branch DEFERRED (inline createSymbol only).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> saveOldStyle IS ported
//       (basicTransition.swift) and IS wired: the data.diff `.update` path calls it on the reused
//       polyline/polygon before the styling pass restyles (so a color change can tween).

// type RadarSymbol = ReturnType<typeof symbolUtil.createSymbol> & { __dimIdx: number };
//   PORT-NOTE (deferred): the `__dimIdx` tag is only used by the DEFERRED vertex-label path; symbols are drawn
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

        // const polar = seriesModel.coordinateSystem;  — the radar coord, read for the collapse-to-center
        //   entrance (`getInitialPoints`). The final vertex positions come from `data.getItemLayout(idx)`.
        let group = self.group
        let data = seriesModel.getData()
        // const oldData = this._data;
        let oldData = self._data

        // ENTRANCE center (upstream `getInitialPoints` collapses the ring onto [polar.cx, polar.cy]).
        let radarCoord = seriesModel.radarCoordinateSystem
        let radarCx = radarCoord?.cx ?? 0
        let radarCy = radarCoord?.cy ?? 0

        // -------------------------------------------------------------------------------------------
        // upstream: data.diff(oldData).add(...).update(...).remove(...).execute();  then a styling pass.
        //   The per-data-item polyline/polygon/symbolGroup lifecycle is diffed against the previous render:
        //     add    → build the itemGroup + collapse-to-center `initProps` entrance (points grow from cx,cy)
        //     update → REUSE the retained itemGroup (from `oldData.getItemGraphicEl`) and `updateProps` the
        //              polyline/polygon `shape.points` to their new vertices (the data ring SLIDES) — this
        //              is the reset-on-update fix: a merge-mode setOption tweens instead of rebuilding and
        //              replaying the enter grow. The vertex symbols morph/rebuild within the reused group.
        //     remove → drop the itemGroup.
        //   (Replaces the prior count-gated morph deviation with the faithful keyed diff, so a per-item add
        //   or remove is handled per-item — only the changed rings enter/leave, the rest tween.)
        // -------------------------------------------------------------------------------------------
        data.diff(oldData)
            .add { newIdx in
                if let itemGroup = self.buildRadarItem(data, seriesModel, newIdx, radarCx, radarCy) {
                    _ = group.add(itemGroup)
                    data.setItemGraphicEl(newIdx, itemGroup)
                }
            }
            .update { newIdx, oldIdx in
                // const itemGroup = oldData.getItemGraphicEl(oldIdx) as graphic.Group;
                if let itemGroup = oldData?.getItemGraphicEl(oldIdx) as? Group {
                    self.updateRadarItem(itemGroup, data, seriesModel, newIdx)
                    _ = group.add(itemGroup)
                    data.setItemGraphicEl(newIdx, itemGroup)
                }
                // Fallback: a matched item whose old graphic el is missing (e.g. previously skipped for a
                //   missing layout) — build it fresh with the entrance.
                else if let itemGroup = self.buildRadarItem(data, seriesModel, newIdx, radarCx, radarCy) {
                    _ = group.add(itemGroup)
                    data.setItemGraphicEl(newIdx, itemGroup)
                }
            }
            .remove { oldIdx in
                // .remove(idx => group.remove(oldData.getItemGraphicEl(idx)))
                if let itemGroup = oldData?.getItemGraphicEl(oldIdx) {
                    _ = group.remove(itemGroup)
                }
            }
            .execute()

        // upstream: `data.eachItemGraphicEl((itemGroup, idx) => { ... styling ... })` — a SEPARATE pass over
        //   the CURRENT items styles line + area (+ emphasis/blur/select states, polygon.ignore) and wires
        //   each itemGroup as a highDown dispatcher. Runs for both freshly-added and updated items.
        data.eachItemGraphicEl { el, idx in
            guard let itemGroup = el as? Group,
                  let polyline = itemGroup.childAt(0) as? Polyline,
                  let polygon = itemGroup.childAt(1) as? Polygon else { return }
            let itemModel = data.getItemModel(idx)
            let color = (data.getItemVisual(idx, "style") as? [String: Any])?["fill"]

            self.applyRadarItemStyles(polyline, polygon, itemModel, color)

            // const emphasisModel = itemModel.getModel('emphasis');
            // toggleHoverEmphasis(itemGroup, focus, blurScope, disabled);
            let emphasisModel = itemModel.getModel(["emphasis"])
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(itemGroup, focus, blurScope, isDisabled)
        }

        // this._data = data;
        self._data = data
    }

    // upstream diff `.add`: build a fresh radar item (itemGroup with polyline=childAt(0), polygon=childAt(1),
    //   symbolGroup=childAt(2)) with the collapse-to-center entrance. Returns nil for a missing layout
    //   (upstream `if (!points) return;`). Styling is applied by the post-diff `eachItemGraphicEl` pass.
    private func buildRadarItem(
        _ data: SeriesData, _ seriesModel: RadarSeriesModel, _ idx: Int, _ radarCx: Double, _ radarCy: Double
    ) -> Group? {
        // const points = data.getItemLayout(idx);  if (!points) { return; }
        guard let points = radarPointsFromLayout(data.getItemLayout(idx)), points.count > 0 else {
            return nil
        }

        // const itemGroup = new graphic.Group();  const symbolGroup = new graphic.Group();
        let itemGroup = Group()
        let symbolGroup = Group()

        // --- polyline / polygon: shape.points = points --------------------------------------------
        var polylineShape = PolylineShape()
        polylineShape.points = points
        let polyline = Polyline(["shape": polylineShape as PathShape])
        polyline.name = "radarPolyline"

        var polygonShape = PolygonShape()
        polygonShape.points = points
        let polygon = Polygon(["shape": polygonShape as PathShape])
        polygon.name = "radarPolygon"

        // ENTRANCE points-grow (faithful upstream `getInitialPoints`): seed the live shape with the ring
        //   collapsed onto the radar center, then initProps the `points` back out to the real vertex ring.
        //   Passing `[[Double]]` under the "shape" sub-bag drives the keyed points animator (a full shape
        //   struct would snap). When animation is off, initProps snaps straight to the final ring.
        let finalPoints: [[Double]] = points.map { [$0.x, $0.y] }
        let collapsedPoints: [[Double]] = points.map { _ in [radarCx, radarCy] }
        for shapeEl in [polyline, polygon] {
            _ = shapeEl.attr(["shape": ["points": collapsedPoints] as [String: Any]])
            initProps(shapeEl, ["shape": ["points": finalPoints] as [String: Any]], seriesModel, idx)
        }

        // itemGroup.add(polyline); itemGroup.add(polygon); itemGroup.add(symbolGroup);  (child order matters)
        _ = itemGroup.add(polyline)
        _ = itemGroup.add(polygon)
        _ = itemGroup.add(symbolGroup)

        // --- symbols: one per vertex (skip the closing duplicate), scale-in entrance ---------------
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 4.0
        let symbolType = (data.getItemVisual(idx, "symbol") as? String) ?? seriesSymbol
        if symbolType != "none" {
            let (sizeW, sizeH) = symbol.normalizeSymbolSize(
                data.getItemVisual(idx, "symbolSize") ?? seriesSymbolSize
            )
            var fill: ZRenderKit.ZRColor? = nil
            if let cs = radarColorString((data.getItemVisual(idx, "style") as? [String: Any])?["fill"]) {
                fill = .string(cs)
            }
            buildRadarSymbols(points, symbolType, sizeW, sizeH, fill, symbolGroup,
                              seriesModel, idx, animateIn: true)
        }

        return itemGroup
    }

    // upstream diff `.update`: reuse the retained itemGroup — `updateProps` the polyline/polygon shape.points
    //   to the new vertex ring (the morph), and morph/rebuild the vertex symbols. Styling is (re)applied by
    //   the post-diff `eachItemGraphicEl` pass. Mirrors the prior morph body; only the source of the reused
    //   elements changed (from the persisted arrays to `oldData.getItemGraphicEl` + childAt).
    private func updateRadarItem(
        _ itemGroup: Group, _ data: SeriesData, _ seriesModel: RadarSeriesModel, _ idx: Int
    ) {
        // const target = { shape: { points: data.getItemLayout(newIdx) } };  if (!target.shape.points) return;
        guard let points = radarPointsFromLayout(data.getItemLayout(idx)), points.count > 0 else {
            return
        }
        guard let polyline = itemGroup.childAt(0) as? Polyline,
              let polygon = itemGroup.childAt(1) as? Polygon,
              let symbolGroup = itemGroup.childAt(2) as? Group else {
            return
        }

        // upstream: saveOldStyle(polygon); saveOldStyle(polyline); — snapshot the pre-restyle style so the
        //   post-diff styling pass's `useStyle` can tween a color change through the style transition.
        saveOldStyle(polygon)
        saveOldStyle(polyline)

        // MORPH the shape points. Target as `[[Double]]` — the shape the Animator's 2D-array interpolation
        //   consumes; a `[VectorArray]` target is not recognised and SNAPS (schedules 0 animators) instead.
        let finalPoints: [[Double]] = points.map { [$0.x, $0.y] }
        updateProps(polyline, ["shape": ["points": finalPoints] as [String: Any]], seriesModel, idx)
        updateProps(polygon, ["shape": ["points": finalPoints] as [String: Any]], seriesModel, idx)

        // Vertex symbols: re-run the visual fallbacks and morph each symbol's SymbolShape x/y to the new
        //   vertex (skip the closing duplicate). A symbol-type/count change per item rebuilds this item's
        //   symbol group fresh. (updateSymbols upstream simply rerenders all; the port reuses when it can.)
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 4.0
        let color = (data.getItemVisual(idx, "style") as? [String: Any])?["fill"]
        let symbolType = (data.getItemVisual(idx, "symbol") as? String) ?? seriesSymbol
        let vertexCount = points.count - 1
        var fill: ZRenderKit.ZRColor? = nil
        if let cs = radarColorString(color) { fill = .string(cs) }
        let (sizeW, sizeH) = symbol.normalizeSymbolSize(
            data.getItemVisual(idx, "symbolSize") ?? seriesSymbolSize
        )
        let existing = symbolGroup.childrenRef().compactMap { $0 as? Path }
        let canMorphSymbols = symbolType != "none"
            && existing.count == vertexCount
            && existing.allSatisfy { $0.shape is SymbolShape }
        if canMorphSymbols {
            for i in 0..<vertexCount {
                let pt = points[i]
                let path = existing[i]
                path.originX = pt.x
                path.originY = pt.y
                updateProps(path, ["shape": [
                    "x": pt.x - sizeW / 2, "y": pt.y - sizeH / 2,
                    "width": sizeW, "height": sizeH
                ] as [String: Any]], seriesModel, idx)
            }
        } else {
            _ = symbolGroup.removeAll()
            if symbolType != "none" {
                buildRadarSymbols(points, symbolType, sizeW, sizeH, fill, symbolGroup,
                                  seriesModel, idx, animateIn: false)
            }
        }
    }

    // Shared line/area styling (color, lineStyle, areaStyle, emphasis/blur/select state styles,
    //   polygon.ignore) — used by both the rebuild and the morph path so a value change restyles too.
    private func applyRadarItemStyles(
        _ polyline: Polyline, _ polygon: Polygon, _ itemModel: Model, _ color: Any?
    ) {
        // polyline.useStyle(zrUtil.defaults(
        //     itemModel.getModel('lineStyle').getLineStyle(), { fill: 'none', stroke: color }));
        var lineStyleDict = itemModel.getModel("lineStyle").getLineStyle()
        if lineStyleDict["stroke"] == nil, let color = color { lineStyleDict["stroke"] = color }
        var polylineStyle = barStyleFromDict(lineStyleDict)
        polylineStyle.fill = nil   // upstream default `fill: 'none'`
        polyline.useStyle(polylineStyle)
        // The Polyline vertices close into a pentagon; `useStyle` runs `createStyle` which lays the style
        // over DEFAULT_PATH_STYLE (fill '#000') via `extendPathStyle`, and that helper SKIPS a nil `fill`
        // — so the intended `fill: 'none'` is dropped and the outline fills solid black UNDER the area
        // polygon (visual-parity trap class 1). Clear it directly to bypass the merge.
        polyline.pathStyle.fill = nil

        // setStatesStylesFromModel(polyline, itemModel, 'lineStyle');
        // setStatesStylesFromModel(polygon, itemModel, 'areaStyle');
        states.setStatesStylesFromModel(polyline, itemModel, "lineStyle")
        states.setStatesStylesFromModel(polygon, itemModel, "areaStyle")

        // const areaStyleModel = itemModel.getModel('areaStyle');
        // const polygonIgnore = areaStyleModel.isEmpty() && areaStyleModel.parentModel.isEmpty();
        let areaStyleModel = itemModel.getModel("areaStyle")
        let polygonIgnore = areaStyleModel.isEmpty() && (areaStyleModel.parentModel?.isEmpty() ?? true)
        polygon.ignore = polygonIgnore

        // polygon.useStyle(zrUtil.defaults(
        //     itemModel.getModel('areaStyle').getAreaStyle(),
        //     { fill: color, opacity: 0.7, decal: itemStyle.decal }));
        //   PORT-NOTE (deferred): `decal: itemStyle.decal` NOT applied (requires decal/pattern rendering, out of scope).
        var areaStyleDict = areaStyleModel.getAreaStyle()
        if areaStyleDict["fill"] == nil, let color = color { areaStyleDict["fill"] = color }
        if areaStyleDict["opacity"] == nil { areaStyleDict["opacity"] = 0.7 }
        polygon.useStyle(barStyleFromDict(areaStyleDict))
        // Same class-1 guard: when the area has no explicit fill (and no series color), don't let the
        // default black survive the createStyle merge.
        if areaStyleDict["fill"] == nil { polygon.pathStyle.fill = nil }
    }

    // Build one vertex symbol per ring point (skipping the closing duplicate) into `symbolGroup`. On a
    //   fresh rebuild the symbols scale-in from 0 (upstream Symbol.ts entrance); on a morph rebuild
    //   (symbol count/type changed) they appear at full scale.
    private func buildRadarSymbols(
        _ points: [VectorArray], _ symbolType: String, _ sizeW: Double, _ sizeH: Double,
        _ fill: ZRenderKit.ZRColor?, _ symbolGroup: Group, _ seriesModel: SeriesModel, _ idx: Int,
        animateIn: Bool
    ) {
        let count = points.count - 1   // skip the closing duplicate vertex
        guard count > 0 else { return }
        for i in 0..<count {
            let pt = points[i]
            let el = symbol.createSymbol(symbolType, pt.x - sizeW / 2, pt.y - sizeH / 2, sizeW, sizeH, fill)
            if let path = el as? Path {
                path.name = "vertex"
                // upstream: symbolPath.attr({ z2: 100 }) — lift the vertex markers above the radar axis lines.
                path.z2 = 100
                path.originX = pt.x
                path.originY = pt.y
                if animateIn {
                    // upstream Symbol.ts first-create scale-in entrance, centered on the vertex point.
                    path.scaleX = 0
                    path.scaleY = 0
                    initProps(path, ["scaleX": 1.0, "scaleY": 1.0], seriesModel, idx)
                }
                _ = symbolGroup.add(path)
            }
        }
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
