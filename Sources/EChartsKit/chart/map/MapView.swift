// Ported from echarts/src/chart/map/MapView.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import * as graphic from '../../util/graphic';
//     → `Circle` is a ZRenderKit shape; `util/graphic` (initProps/updateProps) is ported.
//   import MapDraw from '../../component/helper/MapDraw';
//     → `MapDraw` (component/helper/MapDraw.swift) — roam controller + `_transformGroup`, GeoJSON +
//       geoSVG builds, the visualMap-encoded region fill + decal, the emphasis/select/blur states, and
//       the event/tooltip/state triggers — with TWO documented gaps: the `GeoProjection.stream`
//       clip/resample path (`projectionStream` is nil, `projectPolys` dormant) and the name-keyed geo
//       `labelFetcher` (replaced by an eager `getFormattedLabel`); see the PORT-TODOs in MapDraw.swift.
//     → SWITCHOVER DONE: `MapView.render` now owns a persistent `_mapDraw` and delegates the whole
//       region backdrop to `MapDraw.draw` (upstream lifecycle: `resetForLabelLayout` on `geoRoam`, the
//       self-roam short-circuit, `_clearMapDraw` on remove/dispose, `__updateOnOwnRoam`). The previously
//       inlined static subset (`_buildGeoJSON` / `_buildSVG` / `_morphGeoJSON` / `_resetLabelForRegion`
//       and their file-tail helpers) is DELETED — it was a duplicate of MapDraw (PORTING §2).
//
//       ── BEHAVIOUR CHANGES the switchover deliberately accepts (all in the direction of upstream) ──
//       (1) REGION FILL MORPH DROPPED. The deleted `_morphGeoJSON` was a port INVENTION (an L5 feature):
//           it kept a name-keyed cache of the region `CompoundPath`s and `updateProps`-tweened their
//           visualMap fill across a merge-mode value change. Upstream `MapDraw._buildGeoJSON`
//           (MapDraw.ts:297) simply does `regionsGroup.removeAll()` and rebuilds every region path, so
//           regions are neither identity-reused nor colour-tweened. Retired with the switchover;
//           `MapMorphTests.testRegionFillMorphsOnValueChange` was rewritten to assert the rebuild.
//       (2) REGION ENTRANCE FADE DROPPED. The deleted `createCompoundPath` did an
//           `initProps({ style: { opacity: 0 } })` fade-in. Upstream MapDraw.ts contains NO `initProps` /
//           `updateProps` call at all — map regions appear at their final opacity. Retired with the
//           switchover; `MapTransitionTests.test_region_fades_in_when_animation_on` was inverted.
//       (3) REGION LABEL POSITIONING moved to MapDraw's `labelXY` percent-offset form. `_buildGeoJSON`
//           always passes the region `centerPt` as `labelXY` (MapDraw.ts:368), and
//           `resetLabelForRegion` then OVERWRITES `el.textConfig.position` with a two-element percent
//           STRING ARRAY (`['x%','y%']`, MapDraw.ts:742) plus a `layoutRect`. Consequence: an explicit
//           `label.position: 'top'` no longer reaches `textConfig.position` for a geoJSON REGION (it is
//           still honoured for the legend-symbol label below, and for SVG regions, which pass
//           `labelXY == nil`). This is faithful; `MapLabelTests` was updated to the array shape.
//   import ChartView from '../../view/Chart';                     → `ChartView` (view/Chart.swift).
//   import MapSeries, { getMainMapSeries, MapDataItemOption, mapSeriesNeedsDrawMap, SERIES_TYPE_MAP }
//       from './MapSeries';   → assumed sibling `MapSeriesModel` / free functions (see block below).
//   import GlobalModel from '../../model/Global';                 → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';           → `ExtensionAPI`.
//   import { Payload, DisplayState, ECElement, RoamPayload } from '../../util/types';  → util/types.swift.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//     → label/labelStyle is ported (label/labelStyle.swift) and used directly by `_renderSymbolLabel`
//       (the REGION labels are owned by `MapDraw.resetLabelForRegion`).
//   import { setStatesFlag, Z2_EMPHASIS_LIFT } from '../../util/states';
//     → util/states.swift is ported (`setStatesFlag`, `Z2_EMPHASIS_LIFT`). In this view
//       `Z2_EMPHASIS_LIFT` (== 10) is still inlined as a local constant; the `setStatesFlag` region↔symbol
//       hover link IS now ported (see `_renderSymbolLabel`, via `getHighDownInner(regionGroup).onHoverStateChange`).
//
// ── Assumed sibling API (chart/map/MapSeries.swift — lands in a later phase, like PieSeries/GeoModel) ──
//   These are the members of the map SERIES model + its module free functions that `MapView` /
//   `mapSymbolLayout` touch, mirroring upstream `chart/map/MapSeries.ts`:
//
//     public let SERIES_TYPE_MAP = "map"
//     struct MapSeriesGroup { var f: [MapSeriesModel]; var r: [MapSeriesModel] }   // f: filtered-in series
//     open class MapSeriesModel: SeriesModel {
//         var originalData: SeriesData                              // pre-shallow-clone data (symbol layout)
//         var seriesGroup: MapSeriesGroup?                          // group of series sharing one map/geo
//         // coordinateSystem (inherited `Any?`) is a `Geo` for a map series (geoCreator wires it).
//         func getHostGeoModel() -> GeoModel?                       // non-nil ⇒ drawn by GeoView, not here
//         func getRegionModel(_ name: String) -> Model             // region option model (data-less path)
//         // getData()/getFormattedLabel(...) are inherited (SeriesModel + DataFormatMixin).
//     }
//     func getMainMapSeries(_ mapSeriesGroup: MapSeriesGroup) -> MapSeriesModel?  // == group.f[0]; label owner
//     func mapSeriesNeedsDrawMap(_ mapSeries: MapSeriesModel) -> Bool             // this series draws the map
//   Adjust the call sites if the sibling's surface differs (cf. GeoView's assumed-Geo block).

// upstream: class MapView extends ChartView
open class MapView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_MAP;  /  readonly type = SERIES_TYPE_MAP;
    public static let mapType = SERIES_TYPE_MAP
    open override var type: String {
        get { SERIES_TYPE_MAP }
        set { /* readonly upstream */ }
    }

    // upstream: private _mapDraw: MapDraw;
    private var _mapDraw: MapDraw?

    // upstream: render(mapModel: MapSeries, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    //   The base override is typed `(SeriesModel, ...)`; narrow `model` to `MapSeriesModel` (cf. FunnelView).
    open override func render(
        _ mapModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let mapModel = mapModelBase as! MapSeriesModel

        // upstream: Not render if it is a toggleSelect action from self.
        //   if (payload && payload.type === 'mapToggleSelect' && payload.from === this.uid) { return; }
        // PORT-NOTE (deferred — select states/actions): `mapToggleSelect` is a select action. The guard
        //   itself IS ported faithfully below; it only fires once select-action dispatch lands (select
        //   actions are not yet dispatched, so `payload.type` is never 'mapToggleSelect' in practice).
        if payload.type == "mapToggleSelect",
           let from = payload.other["from"] as? String, from == self.uid {
            return
        }

        // upstream: const group = this.group; group.removeAll();
        //   Only the direct children of the view group are dropped — the persistent `_mapDraw.group`
        //   (with its `_transformGroup` / region subtree) survives and is re-added below, as upstream.
        let group = self.group
        _ = group.removeAll()

        // upstream: if (mapModel.getHostGeoModel()) { return; }
        //   When the series is hosted on a standalone `geo` component, the regions are drawn by `GeoView`
        //   (this view only contributes symbols in that case, which upstream also skips here).
        if mapModel.getHostGeoModel() != nil {
            return
        }

        // upstream: let mapDraw = this._mapDraw;
        //           if (mapDraw && payload && payload.type === 'geoRoam') { mapDraw.resetForLabelLayout(); }
        var mapDraw = self._mapDraw
        if let mapDraw = mapDraw, payload.type == "geoRoam" {
            mapDraw.resetForLabelLayout()
        }

        // upstream: Not update map if it is a roam action from self.
        //   if (!(payload && payload.type === 'geoRoam' && payload.componentType === 'series'
        //         && payload.seriesId === mapModel.id)) { ... } else { mapDraw && group.add(mapDraw.group); }
        //   PORT-NOTE: the port's `Payload` is a non-Optional struct; the driver passes `Payload(type: "")`
        //   as the "no payload" sentinel, and dynamic payload fields live in `payload.other`.
        //   roamHelperGeo now emits these exact upstream fields and invokes `__updateOnOwnRoam` before the
        //   transform-only series pass, so a self-roam keeps the persistent MapDraw instead of rebuilding it.
        let isSelfRoam = payload.type == "geoRoam"
            && (payload.other["componentType"] as? String) == "series"
            && (payload.other["seriesId"] as? String) == mapModel.id
        if !isSelfRoam {
            // upstream: if (mapSeriesNeedsDrawMap(mapModel)) { mapDraw = mapDraw || (this._mapDraw = new MapDraw(api));
            //     group.add(mapDraw.group); mapDraw.draw(mapModel, ecModel, api, this, payload); }
            //   else { this._clearMapDraw(); }
            if mapSeriesNeedsDrawMap(mapModel) {
                if mapDraw == nil {
                    let created = MapDraw(api)
                    self._mapDraw = created
                    mapDraw = created
                }
                _ = group.add(mapDraw!.group)
                // upstream `payload` is nullable and `MapDraw.draw` keys its "no animation" flag off it;
                //   map the driver's `Payload(type: "")` sentinel back to `nil` so a plain render animates.
                mapDraw!.draw(mapModel, ecModel, api, self, payload.type.isEmpty ? nil : payload)
            }
            else {
                self._clearMapDraw()
            }
        }
        else {
            // upstream: mapDraw && group.add(mapDraw.group);
            if let mapDraw = mapDraw {
                _ = group.add(mapDraw.group)
            }
        }

        // upstream: mapModel.get('showLegendSymbol') && ecModel.getComponent('legend') && this._renderSymbols(mapModel);
        if mapJsTruthy(mapModel.get("showLegendSymbol")) && ecModel.getComponent("legend") != nil {
            self._renderSymbols(mapModel)
        }
    }

    // upstream: private _renderSymbols(mapModel: MapSeries): void
    //   Draws the per-region legend-coloured symbol markers (small circles) at the layout points computed
    //   by `mapSymbolLayout`. Only regions with a numeric value AND a layout `point` are drawn.
    private func _renderSymbols(_ mapModel: MapSeriesModel) {
        // upstream: const originalData = mapModel.originalData;
        //   `originalData` is `SeriesData!` (IUO); annotate the binding type so it force-unwraps to
        //   `SeriesData` (the IUO-bound-to-`let` trap infers Optional otherwise — see SwiftPM traps memo).
        let originalData: SeriesData = mapModel.originalData
        let group = self.group

        // upstream: originalData.each(originalData.mapDimension('value'), function (value, originalDataIndex) {...})
        guard let valueDim = originalData.mapDimension("value") else {
            return
        }
        originalData.each(valueDim as Any) { [weak self] args in
            guard let self = self else { return }
            // args == [value, originalDataIndex]
            let value = mapToNumber(args[0]) ?? Double.nan
            let originalDataIndex = Int((args[1] as? Double) ?? -1)

            // upstream: if (isNaN(value)) { return; }
            if value.isNaN {
                return
            }

            // upstream: const layout = originalData.getItemLayout(originalDataIndex);
            //           if (!layout || !layout.point) { return; }  // Not exists in map
            guard let layout = originalData.getItemLayout(originalDataIndex) as? [String: Any],
                  let point = layout["point"] as? [Double], point.count >= 2 else {
                return
            }
            // upstream: const offset = layout.offset;
            let offset = mapToNumber(layout["offset"]) ?? 0

            // upstream: const circle = new graphic.Circle({ style: { fill: ... }, shape: {...}, silent: true, z2: ... });
            var cs = CircleShape()
            // upstream: cx: point[0] + offset * 9, cy: point[1], r: 3
            cs.cx = point[0] + offset * 9
            cs.cy = point[1]
            cs.r = 3
            let circle = Circle(["shape": cs])

            // upstream fill: mapModel.getData().getVisual('style').fill  (series legend colour, not per-item)
            var circleStyle = PathStyleProps()
            let seriesStyle = mapModel.getData().getVisual("style") as? [String: Any]
            if let fill = zrPaintFromStyleValue(seriesStyle?["fill"]) {
                circleStyle.fill = fill
            }
            circle.useStyle(circleStyle)

            circle.silent = true
            // upstream: z2: 8 + (!offset ? Z2_EMPHASIS_LIFT + 1 : 0)  (Z2_EMPHASIS_LIFT == 10)
            let z2EmphasisLift = 10.0   // PORT-NOTE: mirrors util/states.Z2_EMPHASIS_LIFT (== 10), inlined here.
            circle.z2 = 8 + (offset == 0 ? z2EmphasisLift + 1 : 0)

            // upstream: only the series holding the FIRST value on a region (offset 0) renders the label.
            if offset == 0 {
                self._renderSymbolLabel(mapModel, originalData, originalDataIndex, circle)
            }

            _ = group.add(circle)
        }
    }

    // upstream label branch of `_renderSymbols` (the `if (!offset) {...}` block). STATIC subset: draws the
    //   region-name label under the symbol AND wires the region↔symbol hover link
    //   (`regionGroup.onHoverStateChange` → `setStatesFlag(circle, toState)`).
    private func _renderSymbolLabel(
        _ mapModel: MapSeriesModel,
        _ originalData: SeriesData,
        _ originalDataIndex: Int,
        _ circle: Circle
    ) {
        // upstream: const fullData = getMainMapSeries(mapModel.seriesGroup).getData();
        //           const name = originalData.getName(originalDataIndex);
        //           const fullIndex = fullData.indexOfName(name);
        // PORT-NOTE (PORTING §12): upstream's optimistic typing assumes `mapModel.seriesGroup.f` is
        //   non-empty here; mirror the assumption with a `guard` rather than a force-unwrap pair, which
        //   would be a latent SIGTRAP on every `showLegendSymbol` render with a legend present.
        guard let seriesGroup = mapModel.seriesGroup,
              let mainSeries = getMainMapSeries(seriesGroup) else {
            return
        }
        let fullData = mainSeries.getData()
        let name = originalData.getName(originalDataIndex)
        let fullIndex = fullData.indexOfName(name)

        // upstream: const itemModel = originalData.getItemModel(originalDataIndex);
        //           const labelModel = itemModel.getModel('label');
        let itemModel = originalData.getItemModel(originalDataIndex)
        let labelModel = itemModel.getModel("label")

        // upstream: const regionGroup = fullData.getItemGraphicEl(fullIndex);
        //   The region GROUP built by `MapDraw._buildGeoJSON` / `MapDraw._buildSVG` and bound via
        //   `resetEventTriggerForRegion` → `data.setItemGraphicEl`.
        let regionGroup = fullData.getItemGraphicEl(fullIndex)

        // upstream: setLabelStyle(circle, getLabelStatesModels(itemModel), {
        //   labelFetcher: { getFormattedLabel(idx, state) { return mapModel.getFormattedLabel(fullIndex, state); } },
        //   defaultText: name });
        //   `setLabelStyle` attaches the label as the circle's textContent and honours per-state `show`.
        //   The labelFetcher wrapper (idx → fullIndex) is achieved here by fetching with mapModel and
        //   passing `labelDataIndex = fullIndex` (getLabelText calls getFormattedLabel(labelDataIndex, …)).
        var opt = SetLabelStyleOpt()
        opt.defaultText = name
        opt.labelFetcher = mapModel
        opt.labelDataIndex = Double(fullIndex)

        let labelStatesModels = labelStyle.getLabelStatesModels(itemModel)
        labelStyle.setLabelStyle(circle, labelStatesModels, opt)
        // upstream: (circle as ECElement).disableLabelAnimation = true;
        innerStore.getECElementProps(circle).disableLabelAnimation = true

        // upstream: if (!labelModel.get('position')) { circle.setTextConfig({ position: 'bottom' }); }
        //   setLabelStyle's createTextConfig defaults position to "inside"; override to "bottom" when the
        //   label model specifies no position (so the label sits below the symbol point, as upstream).
        let posOpt = labelModel.get("position")
        if (posOpt == nil || posOpt is NSNull), var cfg = circle.textConfig {
            cfg.position = "bottom"
            circle.textConfig = cfg
        }

        // upstream: (regionGroup as ECElement).onHoverStateChange = function (toState) {
        //     setStatesFlag(circle, toState);
        //   };
        //   When the region GROUP's hover state changes (emphasis/blur/normal/select), forward the flag to
        //   the legend-symbol circle so the symbol reacts to the region hover (setStatesFlag is flag-only —
        //   the render pipeline / state proxy applies it, mirroring upstream `util/states.setStatesFlag`).
        if let regionGroup = regionGroup {
            states.getHighDownInner(regionGroup).onHoverStateChange = { [weak circle] toState in
                guard let circle = circle else { return }
                states.setStatesFlag(circle, toState)
            }
        }
    }

    /**
     * @implements RoamHostView['__updateOnOwnRoam']
     */
    // upstream: __updateOnOwnRoam(payload: RoamPayload, model: MapSeries, api: ExtensionAPI): void
    //   The performance shortcut the `geoRoam` action calls to re-transform the region `_transformGroup`
    //   directly (via `MapDraw.__updateOnOwnRoam` → `applyViewCoordSysTransToElement`), with no data /
    //   visual processing. (roamHelperGeo currently registers the full-`update` deviation, so this is
    //   reachable only once `update: 'updateTransform'` routing lands — see the note there.)
    public func __updateOnOwnRoam(
        _ payload: RoamPayload, _ componentOrSeries: ComponentModel, _ api: ExtensionAPI
    ) {
        guard let model = componentOrSeries as? MapSeriesModel else { return }
        let mapDraw = self._mapDraw
        if mapSeriesNeedsDrawMap(model), let mapDraw = mapDraw {
            mapDraw.__updateOnOwnRoam(model)
        }
    }

    // upstream: remove() { this._clearMapDraw(); this.group.removeAll(); }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clearMapDraw()
        _ = self.group.removeAll()
    }

    // upstream: dispose() { this._clearMapDraw(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clearMapDraw()
    }

    // upstream: private _clearMapDraw() { this._mapDraw && this._mapDraw.remove(); this._mapDraw = null; }
    private func _clearMapDraw() {
        self._mapDraw?.remove()
        self._mapDraw = nil
    }
}

// upstream: `class MapView extends ChartView` also `@implements RoamHostView['__updateOnOwnRoam']`
//   (a structural implement, not a declared `implements`). Declared here as a real conformance so the
//   roam dispatcher can find it; the signature matches `RoamHostView` EXACTLY (util/types.swift) —
//   narrowing the model param would silently fail to witness it (MEMORY: protocol-witness trap).
extension MapView: RoamHostView {}

// export default MapView;  → `open class MapView` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of MapView.ts upstream: the dynamic-option
// coercions (`if (x)` truthiness / Int-vs-Double reads) this view still needs.
// The style-bag → PathStyleProps bridge + `getFixedItemStyle` moved out with the
// region build (they now live in MapDraw.swift, the real upstream home).
// ============================================================================

/// Coerce a dynamic option / ParsedValue to Double, tolerating Int boxing (CONVENTIONS trap #1).
private func mapToNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)`); mirrors GeoView.jsTruthy (CONVENTIONS §6).
private func mapJsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}
