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
//          `updateProps` drives the band edge morph. Only the `graphic.Rect` grid-clip reveal is still deferred.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> util/states.swift (ported); `setStatesStylesFromModel` + `toggleHoverEmphasis` wire the band hover/emphasis in render.
//   import {setLabelStyle, getLabelStatesModels} from '../../label/labelStyle';
//       -> `labelStyle.setLabelStyle` / `labelStyle.getLabelStatesModels` (SHARED LABEL CORE). The
//          per-layer band label now routes through the core (see the `setLabelStyle` block in render).
//   import {bind} from 'zrender/src/core/util';                    -> Swift closures.
//   import DataDiffer from '../../data/DataDiffer';
//       -> the add/remove diff is still collapsed, but the UPDATE path is faithful: persisted bands MORPH via updateProps (see render).
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
    //   Retained state for the (deferred) DataDiffer; unused by the STATIC rebuild but kept for
    //   structural fidelity / a future diff port.
    private var _layersSeries: [[String: Any]]?
    // upstream: private _layers: graphic.Group[] = [];
    //   VIEW REUSE (L5 fidelity): the per-layer band groups AND the bands themselves are PERSISTED across
    //   renders (the outer `group` is no longer wiped every time) so a merge-mode setOption value change
    //   MORPHS each band's edges (updateProps shape) instead of rebuild-and-snap. `_bandGroups` holds the
    //   per-layer child Groups (upstream `_layers`); `_bands` holds their single ThemeRiverBand each,
    //   index-keyed by drawable-layer order. `_prevSampleCounts` gates morph-vs-rebuild: a layer add/remove
    //   or a per-layer time-sample count change rebuilds fresh (the edge arrays interpolate element-wise,
    //   so the counts must match to morph); a same-shape value change morphs.
    private var _bandGroups: [Group] = []
    private var _bands: [ThemeRiverBand] = []
    private var _prevSampleCounts: [Int] = []

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
            self._bandGroups = []
            self._bands = []
            self._prevSampleCounts = []
            return
        }

        // group.x = 0;
        group.x = 0
        // group.y = rect.y + boundaryGap[0];
        //   boundaryGap[0] was resolved to a Double by themeRiverLayout (parsePercent). Read via numOpt
        //   so a bare Int does not silently drop (INT-vs-DOUBLE option-read trap).
        group.y = rect.y + (numOpt(boundaryGap.first) ?? 0)

        // ------------------------------------------------------------------------------------------
        // VIEW REUSE deviation from the earlier STATIC rebuild: upstream drives a `DataDiffer` (keyGetter =
        //   layer name) that adds / updates / removes per-layer `graphic.Group`s each holding one
        //   `ECPolygon`, then animates. The full add/remove diff is still collapsed, but the UPDATE path is
        //   now faithful: the per-layer bands are PERSISTED and, on a same-shape (same drawable-layer count
        //   AND same per-layer sample count) merge-mode value change, each band's edges MORPH via
        //   `updateProps({shape})` — the stream slides to the new values instead of rebuild-and-snap. A
        //   layer add/remove or a per-layer sample-count change rebuilds fresh (the edge arrays interpolate
        //   element-wise, so their lengths must be stable to morph), keeping the opacity-fade entrance.
        //   Label + emphasis are wired (shared label core + util/states); only the grid-clip reveal entrance remains deferred.
        // ------------------------------------------------------------------------------------------

        // Gather the drawable per-layer render info first (skipping empty layers), so the morph gate can
        //   compare the DRAWABLE band count + per-layer sample counts against the persisted bands.
        struct LayerRender { var points0: [VectorArray]; var points1: [VectorArray]; var styleBag: Any?; var indices: [Int] }
        var renders: [LayerRender] = []
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
            renders.append(LayerRender(points0: points0, points1: points1, styleBag: styleBag, indices: indices))
        }

        // Morph iff we already drew the same number of bands AND each band's time-sample count is unchanged
        //   (upperPoints/lowerPoints interpolate element-wise, so their lengths must match). Otherwise
        //   rebuild fresh — wipe the group and drop the persisted bands.
        let sampleCounts = renders.map { $0.points0.count }
        let canMorph = !_bands.isEmpty
            && _bands.count == renders.count
            && _prevSampleCounts == sampleCounts
        if !canMorph {
            _ = group.removeAll()
            _bandGroups = []
            _bands = []
        }

        // upstream (ThemeRiverView.ts:102): the SERIES-level emphasis model, read once outside the
        //   layer loop (themeRiver has no per-item loop model) — feeds the per-band hover wiring below.
        let emphasisModel = seriesModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        // for each drawable layer (the diff 'add'→rebuild / 'update'→morph collapse to this branch)
        for (layerIdx, r) in renders.enumerated() {
            let points0 = r.points0
            let points1 = r.points1
            let styleBag = r.styleBag
            let indices = r.indices

            // polygon = new ECPolygon({ shape: { points: points0, stackedOnPoints: points1,
            //   smooth: 0.4, stackedOnSmooth: 0.4, smoothConstraint: false }, z2: 0 });
            // upstream ECPolygon smooths the top edge (points0) and the bottom edge (stackedOnPoints)
            //   as SEPARATE open splines joined by straight end caps. The `ThemeRiverBand` path reproduces
            //   that dual-edge smoothing so adjacent bands share an identical boundary curve (contiguous
            //   stream). `upperPoints` = points1 (far edge), `lowerPoints` = points0 (near edge).
            //   The item visual 'style' bag → typed `PathStyleProps` via the shared bridge (BarView).
            var bandStyle = barStyleFromDict(styleBag)
            let finalOpacity = bandStyle.opacity ?? 1

            let polygon: ThemeRiverBand
            if canMorph {
                // upstream 'update' branch: reuse the layer's existing band and MORPH its edges. The band
                //   is already visible, so land the style at its final opacity (no re-fade), then schedule
                //   the shape-morph animator. TRAP: the updateProps shape-array targets MUST be [[Double]]
                //   (matching ThemeRiverBandShape.animationGet) — a [VectorArray] target snaps (0 animators).
                polygon = _bands[layerIdx]
                // upstream (ThemeRiverView.ts:139): saveOldStyle(polygon) on the update/morph path —
                //   capture the PREVIOUS render's style BEFORE the new `useStyle` overwrites it, so a
                //   merge-mode style transition (universalTransition's animateElementStyles) can tween
                //   old→new. Upstream calls it after `updateProps` (which does not touch style) but before
                //   the final `useStyle`; here `useStyle` runs first in the branch, so capture just ahead
                //   of it to preserve the same old→new endpoint.
                saveOldStyle(polygon)
                bandStyle.opacity = finalOpacity
                polygon.useStyle(bandStyle)
                let upperD = points1.map { [$0.x, $0.y] }
                let lowerD = points0.map { [$0.x, $0.y] }
                updateProps(
                    polygon,
                    ["shape": ["upperPoints": upperD, "lowerPoints": lowerD, "smooth": 0.4] as [String: Any]],
                    seriesModel
                )
            } else {
                // upstream 'add' branch: new graphic.Group() holding a new ECPolygon.
                //   const layerGroup = new graphic.Group();
                let layerGroup = Group()

                var bandShape = ThemeRiverBandShape()
                bandShape.upperPoints = points1   // (x, y0 + y) — the band's far edge
                bandShape.lowerPoints = points0   // (x, y0)     — the band's near edge (== band below's far edge)
                bandShape.smooth = 0.4
                polygon = ThemeRiverBand(["shape": bandShape as PathShape])
                polygon.z2 = 0

                // Entrance animation (OPACITY FADE, mirroring FunnelView/HeatmapView/MapView/TreemapView):
                //   set `style.opacity = 0` before `useStyle`, then animate toward the captured final
                //   opacity via `initProps({style:{opacity}})`. Capture the final opacity BEFORE zeroing so
                //   the band lands visible (the animation-off path relies on `Path.attrKV`'s partial-"style"-
                //   dict merge to actually set it — without it the band would stay invisible).
                bandStyle.opacity = 0
                polygon.useStyle(bandStyle)
                // Key the fade to the layer's last data index (the same index upstream labels / keys by).
                initProps(polygon, ["style": ["opacity": finalOpacity] as [String: Any]], seriesModel, indices.last)

                // Name the band 'item' (per-datum element name, matching FunnelView/PieView).
                polygon.name = "item"

                // layerGroup.add(polygon);  group.add(layerGroup);
                _ = layerGroup.add(polygon)
                _ = group.add(layerGroup)
                _bandGroups.append(layerGroup)
                _bands.append(polygon)
            }

            // Per-layer label via the SHARED LABEL CORE (labelStyle.setLabelStyle), faithful to upstream
            //   ThemeRiverView: route the layer/series name through the core (it creates/updates the band's
            //   textContent ZRText and its emphasis/blur/select states, honouring label:{show:false}), then
            //   override the textConfig with { position: null, local: true } and place the label element
            //   manually at the band's left-edge vertical center.
            //   const textLayout = data.getItemLayout(indices[0]);
            let textLayout = data.getItemLayout(indices[0]) as? [String: Any]
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

            // data.setItemGraphicEl(idx, polygon);  (upstream keys by the diff `idx`; the last data index
            //   of the layer is the closest static analogue — upstream also labels indices[j - 1]).
            if let last = indices.last {
                data.setItemGraphicEl(last, polygon)
            }

            // upstream (ThemeRiverView.ts:168-171): the band's hover wiring — state styles + the
            //   highDown-dispatcher mark. Runs on both the fresh-build and morph-reuse paths.
            states.setStatesStylesFromModel(polygon, seriesModel)
            states.toggleHoverEmphasis(polygon, focus, blurScope, isDisabled)

            // PORT-NOTE (deferred): entrance animation deviation.
            //   - Animation: DONE for the merge-mode UPDATE path (updateProps edge morph); the initial
            //     grid-clip reveal (`createGridClipShape`) is intentionally an opacity fade here (see the
            //     module-level note below). Faithful in outcome (band appears animated), not in mechanism.
            //   - Label: DONE — routed through the shared label core above (setLabelStyle + textConfig
            //     { position: null, local: true } + manual textLayout placement).
        }

        // this._layersSeries = layersSeries;  this._layers = <persisted band groups>;
        self._layersSeries = layersSeries
        self._prevSampleCounts = sampleCounts
    }

    // The base `ChartView.remove`/`dispose` carry (ecModel, api); upstream ThemeRiverView does not
    //   override them (default ChartView.remove clears the group), so neither is overridden here.
}

// PORT-NOTE (deferred — animation): upstream's module-level `createGridClipShape(rect, seriesModel, cb)`
//   builds a `graphic.Rect` clip that expands (width 0 → rect.width + 100) via `graphic.initProps` for
//   the grid-reveal entrance, removing itself on complete. Reproduce alongside the initProps/updateProps
//   animation port.

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
