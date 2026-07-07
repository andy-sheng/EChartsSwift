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
//     → `Circle`/`Polygon`/`Polyline`/`CompoundPath`/`ZRText` are ZRenderKit shapes. PORT-TODO: `util/graphic`
//       (initProps/updateProps/Circle helpers) is NOT ported; the shapes are built directly.
//   import MapDraw from '../../component/helper/MapDraw';
//     → PORT-TODO: `component/helper/MapDraw` is NOT ported. Upstream `MapView.render` delegates ALL region
//       drawing to a persistent `MapDraw` instance (which also owns the roam controller, the SVG map path,
//       the visualMap-encoded region fill, emphasis/select/blur states, and event/tooltip triggers). For
//       this STATIC render the GeoJSON region subset of `MapDraw._buildGeoJSON` (with the SERIES-DATA
//       colouring branch that `GeoView` omits) is inlined below (`_buildGeoJSON`), and the rest is deferred
//       (see the DEFERRED block). This mirrors how `GeoView.swift` inlines the geo-component subset.
//   import ChartView from '../../view/Chart';                     → `ChartView` (view/Chart.swift).
//   import MapSeries, { getMainMapSeries, MapDataItemOption, mapSeriesNeedsDrawMap, SERIES_TYPE_MAP }
//       from './MapSeries';   → assumed sibling `MapSeriesModel` / free functions (see block below).
//   import GlobalModel from '../../model/Global';                 → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';           → `ExtensionAPI`.
//   import { Payload, DisplayState, ECElement, RoamPayload } from '../../util/types';  → util/types.swift.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//     → PORT-TODO: label/labelStyle NOT ported. A minimal plain-text reproduction is inlined
//       (`_updateSymbolLabel` / `_resetLabelForRegion`), the same deviation as FunnelView/GeoView.
//   import { setStatesFlag, Z2_EMPHASIS_LIFT } from '../../util/states';
//     → PORT-TODO: util/states NOT ported (states/emphasis deferred). `Z2_EMPHASIS_LIFT` (== 10) is
//       inlined as a local constant; `setStatesFlag` (the region↔symbol hover link) is deferred.
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
    // PORT-TODO: MapDraw NOT ported. The GeoJSON region backdrop (with data colouring) is built directly
    //   in `_buildGeoJSON`; this slot (and the roam controller / SVG map it owns) is deferred.

    // upstream: render(mapModel: MapSeries, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    //   The base override is typed `(SeriesModel, ...)`; narrow `model` to `MapSeriesModel` (cf. FunnelView).
    open override func render(
        _ mapModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let mapModel = mapModelBase as! MapSeriesModel

        // upstream: Not render if it is a toggleSelect action from self.
        //   if (payload && payload.type === 'mapToggleSelect' && payload.from === this.uid) { return; }
        // PORT-TODO (DEFERRED — select states/actions): `mapToggleSelect` is a select action; select is
        //   deferred, so this early-out never triggers here (kept for provenance).
        if payload.type == "mapToggleSelect",
           let from = payload.other["from"] as? String, from == self.uid {
            return
        }

        let group = self.group
        _ = group.removeAll()

        // upstream: if (mapModel.getHostGeoModel()) { return; }
        //   When the series is hosted on a standalone `geo` component, the regions are drawn by `GeoView`
        //   (this view only contributes symbols in that case, which upstream also skips here).
        if mapModel.getHostGeoModel() != nil {
            return
        }

        // upstream keeps a persistent `_mapDraw` and, on `geoRoam`, calls `mapDraw.resetForLabelLayout()`
        //   / short-circuits a self-roam. STATIC render: no roam, no persistent MapDraw — the group is
        //   rebuilt from scratch each render (matching GeoView / FunnelView).
        // PORT-TODO (DEFERRED — roam): the `payload.type === 'geoRoam'` self-roam short-circuit and
        //   `resetForLabelLayout` are omitted (no RoamController / transformGroup yet).

        // upstream: if (mapSeriesNeedsDrawMap(mapModel)) { mapDraw.draw(...); } else { this._clearMapDraw(); }
        if mapSeriesNeedsDrawMap(mapModel) {
            self._buildGeoJSON(mapModel, ecModel, api)
        }

        // upstream: mapModel.get('showLegendSymbol') && ecModel.getComponent('legend') && this._renderSymbols(mapModel);
        if mapJsTruthy(mapModel.get("showLegendSymbol")) && ecModel.getComponent("legend") != nil {
            self._renderSymbols(mapModel)
        }
    }

    // ================================================================================================
    // Inlined static subset of `MapDraw._buildGeoJSON` (component/helper/MapDraw.ts) — the SERIES-MAP
    // variant. Identical geometry projection to `GeoView._buildGeoJSON`, but each region is FILLED with
    // the per-region series data-item colour: `regionModel` comes from `data.getItemModel(dataIdx)` (not
    // `getRegionModel`), and when the fill is encoded by a visualMap (`isVisualEncodedByVisualMap`) the
    // region gets `data.getItemVisual(dataIdx, 'style').fill`. Falls back to the region `itemStyle`
    // (`getFixedItemStyle` → `areaColor`).
    //
    // PORT-TODO (DEFERRED — faithful to a STATIC render; separate upstream subsystems):
    //   - ROAM: `transformGroup` / `RoamController` / `viewCoordSys` local transform. Here the view
    //     transform is folded into `Geo.dataToPoint` (no roam), so points land at final pixels directly.
    //   - `projectionStream` (d3-style clip/resample) / `projectPolys`: only the per-point projection is
    //     used (inside `dataToPoint`).
    //   - EMPHASIS/SELECT/BLUR states + event/tooltip/state triggers (`applyOptionStyleForRegion`'s
    //     `ensureState(...)`, `setDefaultStateProxy`, `resetEventTriggerForRegion` &c.) — deferred. Only
    //     the NORMAL itemStyle + data fill is drawn.
    //   - `decal` (`createOrUpdatePatternFromDecal`) — pattern/decal bridge deferred.
    // ================================================================================================
    private func _buildGeoJSON(_ mapModel: MapSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {

        let geo = mapModel.coordinateSystem as! Geo
        let data = mapModel.getData()

        // upstream: const isVisualEncodedByVisualMap = data && data.getVisual('visualMeta')
        //     && data.getVisual('visualMeta').length > 0;
        let visualMeta = data.getVisual("visualMeta")
        let isVisualEncodedByVisualMap = (visualMeta as? [Any])?.isEmpty == false

        // upstream: geo.dataToPoint applies projection.project then the view transform. Skip nil points.
        func projectRing(_ ring: [[Double]]) -> [VectorArray] {
            var out: [VectorArray] = []
            for p in ring {
                if let np = geo.dataToPoint(p, false), np.count >= 2 {
                    out.append(VectorArray(np[0], np[1]))
                }
            }
            return out
        }

        // upstream: regionsGroupByName / regionsInfoByName caches — reuse a region group (and its cached
        //   dataIdx + region model) for duplicated `properties.name`.
        var regionsGroupByName: [String: Group] = [:]
        var regionInfoByName: [String: (dataIdx: Int, regionModel: Model)] = [:]

        for region in geo.regions {
            guard let gjRegion = region as? GeoJSONRegion else {
                continue
            }
            let regionName = region.name

            let regionGroup: Group
            let dataIdx: Int
            let regionModel: Model
            if let existing = regionsGroupByName[regionName] {
                regionGroup = existing
                let info = regionInfoByName[regionName]!
                dataIdx = info.dataIdx
                regionModel = info.regionModel
            }
            else {
                // upstream: regionGroup = new graphic.Group(); regionsGroup.add(regionGroup);
                regionGroup = Group()
                _ = self.group.add(regionGroup)

                // upstream: dataIdx = data ? data.indexOfName(regionName) : null;
                //           regionModel = data.getItemModel(dataIdx)   // (map series, non-geo branch)
                dataIdx = data.indexOfName(regionName)
                regionModel = data.getItemModel(dataIdx)

                // upstream: const silent = regionModel.get('silent', true); silent != null && (regionGroup.silent = silent);
                if let silent = regionModel.get("silent", true), !(silent is NSNull) {
                    regionGroup.silent = mapJsTruthy(silent)
                }

                regionsGroupByName[regionName] = regionGroup
                regionInfoByName[regionName] = (dataIdx, regionModel)
            }

            // upstream: const polygonSubpaths = []; const polylineSubpaths = [];
            var polygonSubpaths: [Path] = []
            var polylineSubpaths: [Path] = []

            for geometry in gjRegion.geometries {
                if geometry.type == "polygon", let polyGeo = geometry as? GeoJSONPolygonGeometry {
                    // upstream: let polys = [geometry.exterior].concat(geometry.interiors || []);
                    var polys: [[[Double]]] = [polyGeo.exterior]
                    polys.append(contentsOf: polyGeo.interiors ?? [])
                    for poly in polys {
                        var shape = PolygonShape()
                        shape.points = projectRing(poly)
                        polygonSubpaths.append(Polygon(["shape": shape as PathShape]))
                    }
                }
                else if let lineGeo = geometry as? GeoJSONLineStringGeometry {
                    for points in lineGeo.points {
                        var shape = PolylineShape()
                        shape.points = projectRing(points)
                        polylineSubpaths.append(Polyline(["shape": shape as PathShape]))
                    }
                }
            }

            // upstream: const centerPt = transformPoint(region.getCenter(), projection && projection.project);
            let centerRaw = geo.dataToPoint(gjRegion.getCenter(), false)

            // upstream: createCompoundPath(subpaths, isLine?) — one CompoundPath, styled + labelled.
            //   Returns the created path plus its resolved solid-fill string (used as the label's
            //   `inheritColor`), or nil when there are no subpaths.
            @discardableResult
            func createCompoundPath(_ subpaths: [Path], _ isLine: Bool) -> (path: CompoundPath, fill: String?)? {
                if subpaths.isEmpty {
                    return nil
                }
                var cpShape = CompoundPathShape()
                cpShape.paths = subpaths
                let compoundPath = CompoundPath(["shape": cpShape as PathShape])
                compoundPath.culling = true
                compoundPath.segmentIgnoreThreshold = 1
                _ = regionGroup.add(compoundPath)

                // upstream: applyOptionStyleForRegion(api, data, isVisualEncodedByVisualMap, compoundPath, dataIdx, regionModel);
                //   STATIC subset: NORMAL itemStyle + (visualMap) data fill; emphasis/select/blur states DEFERRED.
                var normalStyle = mapGetFixedItemStyle(regionModel.getModel("itemStyle"))
                // upstream: if (data) { const style = data.getItemVisual(dataIndex, 'style');
                //     if (isVisualEncodedByVisualMap && style.fill) { normalStyle.fill = style.fill; } }
                if dataIdx >= 0,
                   let style = data.getItemVisual(dataIdx, "style") as? [String: Any] {
                    if isVisualEncodedByVisualMap, let fill = style["fill"], !(fill is NSNull) {
                        normalStyle["fill"] = fill
                    }
                    // PORT-TODO (DEFERRED — decal): `normalStyle.decal = createOrUpdatePatternFromDecal(...)`.
                }

                var pathStyle = mapPathStyleFromDict(normalStyle)
                // upstream: el.style.strokeNoScale = true;
                pathStyle.strokeNoScale = true

                // upstream: fixLineStyle — for a "line" compound, stroke = stroke || fill; fill = null.
                if isLine {
                    if pathStyle.stroke == nil { pathStyle.stroke = pathStyle.fill }
                    pathStyle.fill = nil
                }

                // ENTRANCE ANIMATION (opacity fade-in): mirror FunnelView's piece fade — set the
                //   construction-time opacity to 0, then animate (or, with animation OFF, instantly
                //   `attr`) toward the FINAL opacity via `initProps`. The partial ["style":["opacity":…]]
                //   dict merges per-key on BOTH the animate and animation-OFF paths (Path.attrKV), so
                //   the region always ends at its final (visible) opacity. Without capturing the final
                //   opacity first the region would stay invisible.
                let finalOpacity = pathStyle.opacity ?? 1.0
                pathStyle.opacity = 0
                compoundPath.useStyle(pathStyle)
                initProps(
                    compoundPath,
                    ["style": ["opacity": finalOpacity] as [String: Any]],
                    mapModel,
                    dataIdx
                )

                // The region's resolved solid fill (polygon) or stroke (line) — the label's
                //   `inheritColor` so `label.color: 'inherit'` picks up the region colour.
                let fill = isLine
                    ? mapColorString(normalStyle["stroke"]) ?? mapColorString(normalStyle["fill"])
                    : mapColorString(normalStyle["fill"])
                return (compoundPath, fill)
            }

            // upstream: createCompoundPath(polygonSubpaths); createCompoundPath(polylineSubpaths, true);
            let polyResult = createCompoundPath(polygonSubpaths, false)
            let lineResult = createCompoundPath(polylineSubpaths, true)

            // upstream: resetLabelForRegion(...) attaches the region-name label as the compound path's
            //   textContent (via `setLabelStyle`). Prefer the polygon el; fall back to the polyline el.
            //   `_ = centerRaw` — with the label attached to the el (default position "inside"), the
            //   painter centres it in the el's bounding rect, so the explicit centroid is no longer used.
            _ = centerRaw
            if let target = polyResult ?? lineResult {
                self._resetLabelForRegion(
                    mapModel, data, regionModel, regionName, dataIdx, target.fill, target.path
                )
            }
        }
    }

    // upstream: resetLabelForRegion (map-series subset). The region-name label is drawn when
    //   (1) the series data value is NaN, or (2) the region has no legend symbol (mapSymbolLayout stamped
    //   `itemLayout.showLabel`). (Case "geo component" is handled by GeoView, not here.)
    //
    // Retrofitted onto the SHARED LABEL CORE (`labelStyle.setLabelStyle`): the label is attached as the
    //   region compound-path el's `textContent` (via `el.setTextContent` + `el.textConfig`), replacing
    //   the previous standalone-`ZRText`-at-centroid reproduction. `setLabelStyle` owns text/font/fill/
    //   position and honours `label.show` (per state) itself — the painter renders `textContent`
    //   automatically at the configured position (default "inside" → centred in the el's bounding rect).
    private func _resetLabelForRegion(
        _ mapModel: MapSeriesModel,
        _ data: SeriesData,
        _ regionModel: Model,
        _ regionName: String,
        _ dataIdx: Int,
        _ inheritColor: String?,
        _ el: Element
    ) {
        // upstream: const isDataNaN = data && isNaN(data.get(data.mapDimension('value'), dataIdx) as number);
        let valueDim = data.mapDimension("value")
        let rawValue = (dataIdx >= 0 && valueDim != nil) ? data.get(valueDim!, dataIdx) : nil
        let isDataNaN = (mapToNumber(rawValue) ?? Double.nan).isNaN

        // upstream: const itemLayout = data && data.getItemLayout(dataIdx);
        let itemLayout = (dataIdx >= 0 ? data.getItemLayout(dataIdx) : nil) as? [String: Any]
        let showLabel = mapJsTruthy(itemLayout?["showLabel"])

        // upstream: if ((isGeoModel || isDataNaN) || (itemLayout && itemLayout.showLabel)) { ...draw... }
        //   isGeoModel is false in this (map series) view. When neither condition holds, remove any label.
        guard isDataNaN || showLabel else {
            // upstream else-branch: el.removeTextContent(); el.removeTextConfig();
            el.removeTextContent()
            el.removeTextConfig()
            return
        }

        // upstream: const query = !isGeoModel(...) ? dataIdx : regionName;   (map series → dataIdx)
        //           if (!data || dataIdx >= 0) { labelFetcher = mapOrGeoModel; }
        var opt = SetLabelStyleOpt()
        opt.defaultText = regionName
        if dataIdx >= 0 {
            opt.labelFetcher = mapModel
            opt.labelDataIndex = Double(dataIdx)
        }
        // `label.color: 'inherit'` resolves to the region's fill.
        opt.inheritColor = inheritColor

        // upstream: setLabelStyle(el, getLabelStatesModels(regionModel), { labelFetcher, labelDataIndex,
        //   defaultText: regionName }, specifiedTextOpt). `setLabelStyle` attaches the label as `el`'s
        //   textContent (default position "inside" via createTextConfig) and honours per-state `show`.
        let labelStatesModels = labelStyle.getLabelStatesModels(regionModel)
        labelStyle.setLabelStyle(el, labelStatesModels, opt)
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
            if let fill = mapColorString(seriesStyle?["fill"]) {
                circleStyle.fill = .string(fill)
            }
            circle.useStyle(circleStyle)

            circle.silent = true
            // upstream: z2: 8 + (!offset ? Z2_EMPHASIS_LIFT + 1 : 0)  (Z2_EMPHASIS_LIFT == 10)
            let z2EmphasisLift = 10.0   // PORT-TODO: util/states.Z2_EMPHASIS_LIFT not ported (== 10).
            circle.z2 = 8 + (offset == 0 ? z2EmphasisLift + 1 : 0)

            // upstream: only the series holding the FIRST value on a region (offset 0) renders the label.
            if offset == 0 {
                self._renderSymbolLabel(mapModel, originalData, originalDataIndex, circle, point)
            }

            _ = group.add(circle)
        }
    }

    // upstream label branch of `_renderSymbols` (the `if (!offset) {...}` block). STATIC subset: draws the
    //   region-name label under the symbol. The region↔symbol hover link (`onHoverStateChange`/`setStatesFlag`)
    //   and the emphasis/select label states are DEFERRED (states subsystem).
    private func _renderSymbolLabel(
        _ mapModel: MapSeriesModel,
        _ originalData: SeriesData,
        _ originalDataIndex: Int,
        _ circle: Circle,
        _ point: [Double]
    ) {
        // upstream: const fullData = getMainMapSeries(mapModel.seriesGroup).getData();
        //           const name = originalData.getName(originalDataIndex);
        //           const fullIndex = fullData.indexOfName(name);
        // `mapModel.seriesGroup.f` must not be empty here (upstream note), so force-unwrap the main series.
        let fullData = getMainMapSeries(mapModel.seriesGroup!)!.getData()
        let name = originalData.getName(originalDataIndex)
        let fullIndex = fullData.indexOfName(name)

        // upstream: const itemModel = originalData.getItemModel(originalDataIndex);
        //           const labelModel = itemModel.getModel('label');
        let itemModel = originalData.getItemModel(originalDataIndex)
        let labelModel = itemModel.getModel("label")
        _ = point   // label now positioned relative to the `circle` el, not the raw point.

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
        // upstream: (circle as ECElement).disableLabelAnimation = true;  → animation DEFERRED (no-op).

        // upstream: if (!labelModel.get('position')) { circle.setTextConfig({ position: 'bottom' }); }
        //   setLabelStyle's createTextConfig defaults position to "inside"; override to "bottom" when the
        //   label model specifies no position (so the label sits below the symbol point, as upstream).
        let posOpt = labelModel.get("position")
        if (posOpt == nil || posOpt is NSNull), var cfg = circle.textConfig {
            cfg.position = "bottom"
            circle.textConfig = cfg
        }
    }

    // ------------------------------------------------------------------------------------------------
    // DEFERRED interaction hooks (roam / select / events) — documented no-ops for surface parity.
    // ------------------------------------------------------------------------------------------------

    // upstream: __updateOnOwnRoam(payload, model, api) { mapDraw.__updateOnOwnRoam(model); }
    // PORT-TODO (DEFERRED — roam): no MapDraw/transformGroup to re-transform.

    // upstream: remove() { this._clearMapDraw(); this.group.removeAll(); }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // STATIC: nothing persistent to tear down (no MapDraw).
        _ = self.group.removeAll()
    }

    // upstream: dispose() { this._clearMapDraw(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self.group.removeAll()
    }

    // upstream: private _clearMapDraw() { this._mapDraw && this._mapDraw.remove(); this._mapDraw = null; }
    // PORT-TODO (DEFERRED — MapDraw): no persistent draw to clear.
}

// export default MapView;  → `open class MapView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of MapView.ts upstream. `mapGetFixedItemStyle`
// reproduces MapDraw.getFixedItemStyle; the rest mirror the file-private helpers
// in GeoView.swift (dynamic-option coercions, the style-bag → PathStyleProps
// bridge). Delete each when its real sibling lands (util/graphic, util/states)
// and call it directly.
// ============================================================================

// upstream (MapDraw.ts): function getFixedItemStyle(model) { const itemStyle = model.getItemStyle();
//   const areaColor = model.get('areaColor'); if (areaColor != null) { itemStyle.fill = areaColor; } return itemStyle; }
private func mapGetFixedItemStyle(_ model: Model) -> [String: Any] {
    var itemStyle = model.getItemStyle()
    let areaColor = model.get("areaColor")
    if let areaColor = areaColor, !(areaColor is NSNull) {
        itemStyle["fill"] = areaColor
    }
    return itemStyle
}

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

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic itemStyle bag
///   ([String: Any]) onto the typed `PathStyleProps`. Same deviation as GeoView.geoPathStyleFromDict;
///   numbers via `mapToNumber` (Int-drop trap). Delete when the graphic bridge lands.
private func mapPathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern (ZRColor non-string); only the String form
    //   (incl. the sentinel 'none') is mapped here.
    if let v = mapColorString(dict["fill"]) { s.fill = .string(v) }
    if let v = mapColorString(dict["stroke"]) { s.stroke = .string(v) }
    if let v = mapToNumber(dict["lineWidth"]) { s.lineWidth = v }
    if let v = dict["lineCap"] as? String { s.lineCap = v }
    if let v = dict["lineJoin"] as? String { s.lineJoin = v }
    if let v = mapToNumber(dict["miterLimit"]) { s.miterLimit = v }
    if let v = mapToNumber(dict["opacity"]) { s.opacity = v }
    if let v = mapToNumber(dict["fillOpacity"]) { s.fillOpacity = v }
    if let v = mapToNumber(dict["strokeOpacity"]) { s.strokeOpacity = v }
    if let v = mapToNumber(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = mapToNumber(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = mapToNumber(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = mapToNumber(dict["lineDashOffset"]) { s.lineDashOffset = v }
    // PORT-TODO: `lineDash` (number[] | false) mapping deferred (LineDash enum bridge).
    return s
}

/// Bridge a visual/style paint value (raw `String` or EChartsKit `ZRColor`) to a solid color string.
///   Mirrors GeoView.geoColorString (gradient/pattern out of scope).
private func mapColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}
