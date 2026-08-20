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
//       -> PORT-NOTE: the shared `ECPolygon` (chart/line/poly.ts) is not ported as a shared shape; a local
//          minimal equivalent (`ThemeRiverBand` / `ThemeRiverBandShape`, below) reproduces the dual-edge
//          `points0`/`points1` band WITH the `smooth: 0.4` / `stackedOnSmooth: 0.4` Bézier smoothing, so
//          adjacent bands share an identical boundary curve (contiguous stream).
//   import * as graphic from '../../util/graphic';
//       -> `Polygon` is the ZRenderKit shape. `util/graphic` (Group, Rect, initProps/updateProps) is ported;
//          `updateProps` drives the band edge morph; a `graphic.Rect` clip provides the upstream entrance reveal.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> util/states.swift (ported); `setStatesStylesFromModel` + `toggleHoverEmphasis` wire the band hover/emphasis in render.
//   import {setLabelStyle, getLabelStatesModels} from '../../label/labelStyle';
//       -> `labelStyle.setLabelStyle` / `labelStyle.getLabelStatesModels` (SHARED LABEL CORE). The
//          per-layer band label now routes through the core (see the `setLabelStyle` block in render).
//   import {bind} from 'zrender/src/core/util';                    -> Swift closures.
//   import DataDiffer from '../../data/DataDiffer';
//       -> data/DataDiffer.swift (ported). The keyed diff (keyGetter = layer name) is now wired in render:
//          add → fresh layer group; update → reuse matched group + morph band edges
//          (updateProps); remove → group.remove(oldLayersGroups[idx]).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import ThemeRiverSeriesModel, { SERIES_TYPE_THEME_RIVER } from './ThemeRiverSeries';
//       -> sibling ThemeRiverSeries.swift (assumed).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { RectLike } from 'zrender/src/core/BoundingRect';      -> ZRenderKit.RectLike.
//   import { ColorString } from '../../util/types';                -> util/types (label-only; deferred).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> animation/basicTransition.swift (ported); NOW called on the band morph/update path (see the morph branch in render), mirroring upstream line 139, so cross-merge style transitions preserve the old style.

// upstream: type LayerSeries = ReturnType<ThemeRiverSeriesModel['getLayerSeries']>;
//   PORT-NOTE (sibling contract): `ThemeRiverSeriesModel.getLayerSeries()` is ASSUMED to return
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
    //   The old layer-series array, keyed by layer `name`, feeding the DataDiffer's `oldArr`.
    private var _layersSeries: [[String: Any]]?
    // upstream: private _layers: graphic.Group[] = [];
    //   VIEW REUSE (L5 fidelity): the per-layer band groups are PERSISTED across renders and diffed by
    //   layer NAME via `DataDiffer` (mirroring upstream): a persisted layer's band MORPHS its edges
    //   (updateProps shape), a NEW layer is added at final style, and a REMOVED layer's group is pulled
    //   off `group`. Each layer group holds one `ThemeRiverBand` as `childAt(0)` (upstream: one ECPolygon).
    //   Index-aligned with `_layersSeries` (the diff's `remove` reads `_layers[oldIdx]`).
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
        // VIEW REUSE + KEYED DIFF (upstream fidelity): upstream drives a `DataDiffer` keyed by layer name
        //   over `this._layersSeries || []` (old) and `layersSeries` (new). `add` builds a fresh per-layer
        //   `graphic.Group` holding one band; `update` reuses the matched old layer group, re-adds it (to
        //   preserve draw order) and MORPHS the band's edges via `updateProps({shape})`; `remove` pulls the
        //   stale layer group off `group`. Label + emphasis are wired on the add/update paths (shared label
        //   core + util/states). First render is revealed by the series-level grid clip below.
        // ------------------------------------------------------------------------------------------

        // upstream (ThemeRiverView.ts:102): the SERIES-level emphasis model, read once (themeRiver has no
        //   per-item loop model) — feeds the per-band hover wiring in `process`.
        let emphasisModel = seriesModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        // upstream: function keyGetter(item) { return item.name; }  — the layer name is the diff key.
        let keyGetter: DiffKeyGetter = { item, _ in
            ((item as? [String: Any])?["name"] as? String) ?? ""
        }
        // upstream: new DataDiffer(this._layersSeries || [], layersSeries, keyGetter, keyGetter)
        let dataDiffer = DataDiffer<Any>(
            (self._layersSeries ?? []).map { $0 as Any },
            layersSeries.map { $0 as Any },
            keyGetter, keyGetter
        )

        // upstream: const oldLayersGroups = self._layers;  (read inside process)
        let oldLayersGroups = self._layers
        // upstream: const newLayersGroups: graphic.Group[] = [];  (index-aligned with layersSeries)
        var newLayersGroups = [Group?](repeating: nil, count: layersSeries.count)

        // upstream: function process(status, idx, oldIdx?) { ... }
        //   status ∈ {add, update, remove}; idx = new index (add/update) or old index (remove).
        let process: (String, Int, Int?) -> Void = { status, idx, oldIdx in
            // upstream: if (status === 'remove') { group.remove(oldLayersGroups[idx]); return; }
            if status == "remove" {
                if idx >= 0 && idx < oldLayersGroups.count {
                    _ = group.remove(oldLayersGroups[idx])
                }
                return
            }

            // const indices = layersSeries[idx].indices;
            let indices = (layersSeries[idx]["indices"] as? [Int]) ?? []

            // const points0: number[] = [];  (top edge)  /  const points1: number[] = [];  (bottom edge)
            var points0: [VectorArray] = []
            var points1: [VectorArray] = []
            // let style;
            var styleBag: Any? = nil

            // for (; j < indices.length; j++) { ... }
            for i in indices {
                // const layout = data.getItemLayout(indices[j]);  == { layerIndex, x, y0, y }
                guard let layout = data.getItemLayout(i) as? [String: Any] else {
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
                styleBag = data.getItemVisual(i, "style")
            }

            // upstream ECPolygon smooths the top edge (points0) and the bottom edge (stackedOnPoints)
            //   as SEPARATE open splines joined by straight end caps. The `ThemeRiverBand` path reproduces
            //   that dual-edge smoothing so adjacent bands share an identical boundary curve (contiguous
            //   stream). `upperPoints` = points1 (far edge), `lowerPoints` = points0 (near edge).
            //   The item visual 'style' bag → typed `PathStyleProps` via the shared bridge (BarView).
            let bandStyle = barStyleFromDict(styleBag)

            let polygon: ThemeRiverBand
            if status == "add" {
                // upstream 'add' branch: new graphic.Group() holding a new ECPolygon.
                //   const layerGroup = newLayersGroups[idx] = new graphic.Group();
                let layerGroup = Group()

                var bandShape = ThemeRiverBandShape()
                bandShape.upperPoints = points1   // (x, y0 + y) — the band's far edge
                bandShape.lowerPoints = points0   // (x, y0)     — the band's near edge (== band below's far edge)
                bandShape.smooth = 0.4
                polygon = ThemeRiverBand(["shape": bandShape as PathShape])
                polygon.z2 = 0

                polygon.useStyle(bandStyle)

                // Name the band 'item' (per-datum element name, matching FunnelView/PieView).
                polygon.name = "item"

                // layerGroup.add(polygon);  group.add(layerGroup);
                _ = layerGroup.add(polygon)
                _ = group.add(layerGroup)
                newLayersGroups[idx] = layerGroup

                // Upstream reveals each new band with a left-to-right clip rectangle, not an opacity
                // fade. The clip owns the animator and removes itself when the reveal completes.
                if seriesModel.isAnimationEnabled() == true, let bounds = polygon.getBoundingRect() {
                    polygon.setClipPath(themeRiverGridClip(bounds, seriesModel) { [weak polygon] in
                        polygon?.removeClipPath()
                    })
                }
            }
            else {
                // upstream 'update' branch: reuse the matched old layer group and MORPH its band's edges.
                //   const layerGroup = oldLayersGroups[oldIdx];
                //   polygon = layerGroup.childAt(0) as ECPolygon;
                //   group.add(layerGroup);  newLayersGroups[idx] = layerGroup;
                let layerGroup = oldLayersGroups[oldIdx!]
                polygon = (layerGroup.childAt(0) as? ThemeRiverBand)!
                _ = group.add(layerGroup)   // re-add is a no-op if already a child (preserves order)
                newLayersGroups[idx] = layerGroup

                // upstream (ThemeRiverView.ts:139): saveOldStyle(polygon) on the update/morph path —
                //   capture the PREVIOUS render's style BEFORE the new `useStyle` overwrites it, so a
                //   merge-mode style transition (universalTransition's animateElementStyles) can tween
                //   old→new. Upstream calls it after `updateProps` (which does not touch style) but before
                //   the final `useStyle`; here `useStyle` runs first in the branch, so capture just ahead.
                saveOldStyle(polygon)
                polygon.useStyle(bandStyle)

                // The band's edges MORPH via updateProps({shape}). TRAP: the updateProps shape-array
                //   targets MUST be [[Double]] (matching ThemeRiverBandShape.animationGet) — a
                //   [VectorArray] target snaps (0 animators). The 2D-array interpolator indexes the START
                //   (current) shape row-by-row, so a per-layer time-sample COUNT change (rare — a merge-mode
                //   data reshape) can't interpolate element-wise: snap the shape in place instead of
                //   morphing (still identity-reuses the band + group, so no rebuild flash / duplication).
                let previousShape = polygon.shape as? ThemeRiverBandShape
                let prevCount = previousShape?.upperPoints.count ?? 0
                let geometryChanged: Bool = {
                    guard let previousShape, prevCount == points0.count,
                          previousShape.lowerPoints.count == points0.count else { return true }
                    for i in points0.indices {
                        if previousShape.upperPoints[i].x != points1[i].x
                            || previousShape.upperPoints[i].y != points1[i].y
                            || previousShape.lowerPoints[i].x != points0[i].x
                            || previousShape.lowerPoints[i].y != points0[i].y {
                            return true
                        }
                    }
                    return false
                }()
                if prevCount == points0.count, geometryChanged {
                    let upperD = points1.map { [$0.x, $0.y] }
                    let lowerD = points0.map { [$0.x, $0.y] }
                    updateProps(
                        polygon,
                        ["shape": ["upperPoints": upperD, "lowerPoints": lowerD, "smooth": 0.4] as [String: Any]],
                        seriesModel
                    )
                }
                else if prevCount != points0.count {
                    var bandShape = ThemeRiverBandShape()
                    bandShape.upperPoints = points1
                    bandShape.lowerPoints = points0
                    bandShape.smooth = 0.4
                    polygon.shape = bandShape
                }
            }

            // Per-layer label via the SHARED LABEL CORE (labelStyle.setLabelStyle), faithful to upstream
            //   ThemeRiverView: route the layer/series name through the core (it creates/updates the band's
            //   textContent ZRText and its emphasis/blur/select states, honouring label:{show:false}), then
            //   override the textConfig with { position: null, local: true } and place the label element
            //   manually at the band's left-edge vertical center.
            //   const textLayout = data.getItemLayout(indices[0]);
            let textLayout = indices.first.flatMap { data.getItemLayout($0) as? [String: Any] }
            //   const labelModel = seriesModel.getModel('label');  const margin = labelModel.get('margin');
            let labelModel = seriesModel.getModel("label")
            let margin = numOpt(labelModel.get("margin")) ?? 0

            // inheritColor: style.fill — the band's solid fill color as a color string (BarView bridge:
            //   the visual 'style' bag stores fill as a `ZRColor.color("#…")` or a raw String).
            let inheritFill: String? = {
                guard let d = styleBag as? [String: Any] else { return nil }
                if let str = d["fill"] as? String { return str }
                if let zr = d["fill"] as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
                return nil
            }()

            // upstream keys/labels the band by indices[j - 1] (the layer's LAST data index after the loop);
            //   the layer name is identical across the layer's indices, so this is the band's series name.
            if let last = indices.last {
                // setLabelStyle(polygon, getLabelStatesModels(seriesModel), { labelDataIndex, defaultText,
                //   inheritColor }, { normal: { verticalAlign: 'middle' } });
                var opt = SetLabelStyleOpt()
                opt.labelFetcher = seriesModel
                opt.labelDataIndex = Double(last)
                // defaultText: data.getName(indices[j - 1]) — the layer/series name (no label formatter →
                //   getFormattedLabel returns nil and the core falls back to this default text).
                opt.defaultText = data.getName(last)
                opt.inheritColor = inheritFill

                var normalSpec = TextStyleProps()
                normalSpec.verticalAlign = .middle

                labelStyle.setLabelStyle(
                    polygon,
                    labelStyle.getLabelStatesModels(seriesModel),
                    opt,
                    [.normal: normalSpec]
                )

                // polygon.setTextConfig({ position: null, local: true });
                //   Merge-onto the config setLabelStyle just wrote (createTextConfig set position/distance):
                //   drop the position so the band positions its label manually, and apply the host transform.
                var tc = polygon.textConfig ?? ElementTextConfig()
                tc.position = nil
                tc.local = true
                polygon.setTextConfig(tc)

                // const labelEl = polygon.getTextContent();
                //   labelEl.x = textLayout.x - margin;  labelEl.y = textLayout.y0 + textLayout.y / 2;
                if let labelEl = polygon.getTextContent(), let tl = textLayout {
                    labelEl.x = (numOpt(tl["x"]) ?? 0) - margin
                    labelEl.y = (numOpt(tl["y0"]) ?? 0) + (numOpt(tl["y"]) ?? 0) / 2
                }
            }

            // upstream: data.setItemGraphicEl(idx, polygon). ThemeRiver's interactive item index is
            // the LAYER index (0...layerCount-1), not the last raw datum index in that layer. Keeping
            // this mapping exact is load-bearing for highlight/downplay and deterministic hover actions.
            data.setItemGraphicEl(idx, polygon)

            // upstream (ThemeRiverView.ts:168-171): the band's hover wiring — state styles + the
            //   highDown-dispatcher mark. Runs on both the add and update paths.
            states.setStatesStylesFromModel(polygon, seriesModel)
            states.toggleHoverEmphasis(polygon, focus, blurScope, isDisabled)
        }

        // upstream: dataDiffer.add(bind(process,this,'add')).update(...).remove(...).execute();
        dataDiffer
            .add { newIdx in process("add", newIdx, nil) }
            .update { newIdx, oldIdx in process("update", newIdx, oldIdx) }
            .remove { oldIdx in process("remove", oldIdx, nil) }
            .execute()

        // this._layersSeries = layersSeries;  this._layers = newLayersGroups;
        //   Every new-array index is visited by add or update (DataDiffer oneToOne), so `newLayersGroups`
        //   is fully populated and index-aligned with `layersSeries` — compactMap just drops the Optional.
        self._layersSeries = layersSeries
        self._layers = newLayersGroups.compactMap { $0 }
    }

    // The base `ChartView.remove`/`dispose` carry (ecModel, api); upstream ThemeRiverView does not
    //   override them (default ChartView.remove clears the group), so neither is overridden here.
}

// upstream createGridClipShape(rect, seriesModel, cb): reveal a new band from left to right.
private func themeRiverGridClip(
    _ rect: BoundingRect, _ seriesModel: ThemeRiverSeriesModel, _ cb: @escaping () -> Void
) -> Rect {
    var initial = RectShape()
    initial.x = rect.x - 10
    initial.y = rect.y - 10
    initial.width = 0
    initial.height = rect.height + 20
    let clip = Rect(["shape": initial as PathShape])
    initProps(
        clip,
        ["shape": [
            "x": rect.x - 50,
            "width": rect.width + 100,
            "height": rect.height + 20
        ] as [String: Any]],
        seriesModel, nil, cb
    )
    return clip
}

// A minimal port of echarts `ECPolygon` (chart/line/poly.ts) specialised for theme-river bands: the
//   upper edge and lower edge are each smoothed as an OPEN Bézier spline (endpoints anchored) and joined
//   by straight vertical caps. Because each edge is smoothed independently of the other, a band's upper
//   edge and the next band's lower edge (the same points) trace an identical curve → the stacked stream
//   is contiguous with no gaps and no rounded end-cap blobs (the single-Polygon-ring artifact).
struct ThemeRiverBandShape: PathShape {
    // Both edges in ascending-x (left→right) order, one point per time sample.
    var upperPoints: [VectorArray] = []
    var lowerPoints: [VectorArray] = []
    var smooth: Double = 0.4

    // Keyed access for animateTo({shape:{...}}) — the line/area morph (LineView reuse). Both edges
    //   are exposed as `[[Double]]` for the Animator's 2D-array interpolation (mirrors PolylineShape).
    func animationGet(_ key: String) -> Any? {
        switch key {
        case "upperPoints": return upperPoints.map { [$0.x, $0.y] }
        case "lowerPoints": return lowerPoints.map { [$0.x, $0.y] }
        case "smooth": return smooth
        default: return nil
        }
    }
    mutating func animationSet(_ key: String, _ value: Any?) {
        func toPts(_ v: Any?) -> [VectorArray]? {
            if let arr = v as? [[Double]] { return arr.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) } }
            if let arr = v as? [VectorArray] { return arr }
            return nil
        }
        switch key {
        case "upperPoints": if let p = toPts(value) { upperPoints = p }
        case "lowerPoints": if let p = toPts(value) { lowerPoints = p }
        case "smooth": if let v = value as? Double { smooth = v }
        default: break
        }
    }
}

final class ThemeRiverBand: Path {
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "themeRiverBand"
    }

    public override func getDefaultShape() -> PathShape {
        return ThemeRiverBandShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let s = shape as! ThemeRiverBandShape
        let upper = s.upperPoints
        let lower = s.lowerPoints
        guard upper.count >= 2, lower.count == upper.count else {
            // Degenerate (single sample or mismatched edges): fall back to a straight closed ring.
            let ring = upper + lower.reversed()
            guard ring.count >= 2 else { return }
            _ = ctx.moveTo(ring[0][0], ring[0][1])
            for i in 1..<ring.count { _ = ctx.lineTo(ring[i][0], ring[i][1]) }
            _ = ctx.closePath()
            return
        }

        // Upper edge, left→right, smoothed as an open spline.
        drawSmoothOpen(ctx, upper, s.smooth, moveToFirst: true)
        // Right cap: straight down to the lower edge.
        let lowerRev = Array(lower.reversed())   // right→left
        _ = ctx.lineTo(lowerRev[0][0], lowerRev[0][1])
        // Lower edge, right→left, smoothed as an open spline (same geometry as the band below's upper edge).
        drawSmoothOpen(ctx, lowerRev, s.smooth, moveToFirst: false)
        // Left cap + close.
        _ = ctx.closePath()
    }

    private func drawSmoothOpen(_ ctx: PathProxy, _ pts: [VectorArray], _ smooth: Double, moveToFirst: Bool) {
        if moveToFirst { _ = ctx.moveTo(pts[0][0], pts[0][1]) }
        if smooth != 0 && !smooth.isNaN && pts.count >= 2 {
            let cps = smoothBezier(pts, smooth, false, nil)
            for i in 0..<(pts.count - 1) {
                let cp1 = cps[i * 2]
                let cp2 = cps[i * 2 + 1]
                let p = pts[i + 1]
                _ = ctx.bezierCurveTo(cp1[0], cp1[1], cp2[0], cp2[1], p[0], p[1])
            }
        } else {
            for i in 1..<pts.count { _ = ctx.lineTo(pts[i][0], pts[i][1]) }
        }
    }
}

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
