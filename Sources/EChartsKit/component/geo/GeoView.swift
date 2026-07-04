// Ported from echarts/src/component/geo/GeoView.ts — keep in sync with upstream
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
//   import MapDraw from '../helper/MapDraw';
//     → PORT-TODO: `component/helper/MapDraw` is NOT ported. Upstream `GeoView` delegates ALL region
//       drawing to a `MapDraw` instance (which also owns the roam controller, SVG map path, series-map
//       data/visualMap encoding, emphasis/select/blur states, and event/tooltip triggers). For this
//       STATIC render the GeoJSON region-backdrop subset of `MapDraw._buildGeoJSON` is inlined below
//       (`_buildGeoJSON`), and the rest is deferred (see the DEFERRED block). Reconcile when MapDraw lands.
//   import ComponentView from '../../view/Component';             → `ComponentView` (view/ComponentView.swift).
//   import GlobalModel from '../../model/Global';                 → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';           → `ExtensionAPI`.
//   import GeoModel from '../../coord/geo/GeoModel';              → `GeoModel` (sibling — see assumed API below).
//   import { Payload, ZRElementEvent, ECEventData, RoamPayload } from '../../util/types';
//     → `Payload` (util/types.swift). `ZRElementEvent`/`ECEventData`/`RoamPayload` are used only by the
//       DEFERRED click/roam handlers below.
//   import { getECData } from '../../util/innerStore';            → PORT-TODO: innerStore NOT ported (events deferred).
//   import { findEventDispatcher } from '../../util/event';       → PORT-TODO: util/event NOT ported (events deferred).
//   import Element from 'zrender/src/Element';                    → ZRenderKit `Element`.
//
// ── Assumed sibling API (coord/geo/Geo.swift, coord/geo/Region.swift, coord/geo/GeoModel.swift) ──
//   These siblings land alongside this view (the geo COORDINATE SYSTEM — the 7th — that PROJECTS a
//   [lng, lat] to a pixel). Their assumed surface, mirroring upstream Geo.ts / Region.ts / GeoModel.ts
//   (cf. CalendarView's assumed `Calendar` API):
//
//     open class GeoModel: ComponentModel {
//         var coordinateSystem: CoordinateSystemMaster?        // downcast to `Geo`
//         func getRegionModel(_ name: String) -> Model         // region option model
//         func getFormattedLabel(_ name: String, _ status: String) -> String?  // 'normal' | 'emphasis'
//     }
//     final class Geo: /* CoordinateSystemMaster */ {
//         let regions: [Region]
//         let resourceType: String                              // 'geoJSON' | 'geoSVG'
//         // Projects a data-unit coord ([lng, lat] or SVG-local) to a pixel; applies `projection`
//         // then the view transform. Returns nil when the projection rejects the point.
//         func dataToPoint(_ data: [Double], _ noRoam: Bool, _ out: [Double]?) -> [Double]?
//     }
//     class Region { let name: String; func getCenter() -> [Double] }   // center in DATA unit (lng/lat)
//     final class GeoJSONRegion: Region { let geometries: [GeoJSONGeometry] }
//     protocol GeoJSONGeometry { var type: String { get } }             // 'polygon' | 'linestring'
//     final class GeoJSONPolygonGeometry: GeoJSONGeometry {             // type == 'polygon'
//         var exterior: [[Double]]; var interiors: [[[Double]]]?
//     }
//     final class GeoJSONLineStringGeometry: GeoJSONGeometry {          // type == 'linestring'
//         var points: [[[Double]]]
//     }
//   `dataToPoint` is assumed to default `noRoam`/`out` (called `geo.dataToPoint(pt)` below); adjust the
//   call sites if the sibling omits the defaults.

// upstream: class GeoView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class GeoView: ComponentView {

    // upstream: static type = 'geo' as const;
    public static let type = "geo"
    // upstream: readonly type = GeoView.type;
    public let type = "geo"

    // upstream: private _mapDraw: MapDraw;
    // PORT-TODO: MapDraw NOT ported. The GeoJSON region backdrop is built directly in `_buildGeoJSON`;
    //   this slot (and the roam controller / SVG map it owns) is deferred.

    // upstream: private _api: ExtensionAPI;
    private var _api: ExtensionAPI?

    // upstream: private _model: GeoModel;
    private var _model: GeoModel?

    // upstream: focusBlurEnabled = true;
    // PORT-TODO: consulted by the emphasis/blur system (deferred with states); kept for surface parity.
    public var focusBlurEnabled = true

    // upstream: init(ecModel: GlobalModel, api: ExtensionAPI) { this._api = api; }
    public override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._api = api
    }

    // upstream: render(geoModel: GeoModel, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    //   The base override is typed `(ComponentModel, ...)`; narrow `model` to `GeoModel` (cf. CalendarView).
    public override func render(
        _ geoModelBase: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let geoModel = geoModelBase as! GeoModel
        self._model = geoModel

        // STATIC render deviation: upstream keeps a persistent `_mapDraw` and calls
        //   `mapDraw.draw(...)` (which diffs). Here the view group is rebuilt from scratch each render
        //   (matching CalendarView / FunnelView), so clear it first.
        _ = self.group.removeAll()

        // upstream: if (!geoModel.get('show')) { this._mapDraw && this._mapDraw.remove(); this._mapDraw = null; return; }
        if !jsTruthy(geoModel.get("show")) {
            return
        }

        // upstream: if (!this._mapDraw) { this._mapDraw = new MapDraw(api); }
        //           const mapDraw = this._mapDraw;
        //           mapDraw.draw(geoModel, ecModel, api, this, payload);
        // Replaced by the inlined static GeoJSON build (see `_buildGeoJSON`).
        let geo = geoModel.coordinateSystem as! Geo

        // upstream MapDraw.draw dispatches on `geo.resourceType`:
        //   'geoJSON' → _buildGeoJSON (ported below);  'geoSVG' → _buildSVG (DEFERRED).
        // PORT-TODO (DEFERRED — GeoSVGResource / geoSVG path): SVG maps render via `_buildSVG` upstream.
        //   Only the GeoJSON path is ported (per the port brief). A geoSVG geo renders nothing here.
        if geo.resourceType == "geoJSON" {
            self._buildGeoJSON(geo, geoModel, api)
        }

        // upstream: mapDraw.group.on('click', this._handleRegionClick, this);  → DEFERRED (events).
        // upstream: mapDraw.group.silent = geoModel.get('silent');
        if let silent = geoModel.get("silent"), !(silent is NSNull) {
            self.group.silent = jsTruthy(silent)
        }
        // upstream: this.group.add(mapDraw.group);  — regions are added straight onto `this.group` here.
        // upstream: this.updateSelectStatus(geoModel, ecModel, api);  → DEFERRED (select states).
    }

    // ================================================================================================
    // Inlined static subset of `MapDraw._buildGeoJSON` (component/helper/MapDraw.ts).
    //
    // For each GeoJSON region: project its polygon rings / linestrings through `Geo.dataToPoint`, draw
    // them as `ZRenderKit.Polygon` / `Polyline` subpaths wrapped in a `CompoundPath`, apply the region
    // `itemStyle` (via `getFixedItemStyle`), and draw the region-name label (`ZRText`) at the projected
    // centroid.
    //
    // PORT-TODO (DEFERRED — faithful to a STATIC render; separate upstream subsystems):
    //   - ROAM: the `transformGroup` + `applyViewCoordSysTransToElement` (pan/zoom) and the
    //     `RoamController`. Here the view transform is folded into `Geo.dataToPoint` (no roam), so points
    //     land at final pixels directly. `geo.shouldClip()` / `setClipPath` is likewise omitted.
    //   - `projectionStream` (d3-style clip/resample streams): only the per-point `projection.project`
    //     path (inside `dataToPoint`) is used; `projectPolys` is not reproduced.
    //   - series-map DATA: `data`/`isVisualEncodedByVisualMap`/`getItemVisual`/decal — the geo component
    //     backdrop has no series data; `regionModel` comes from `geoModel.getRegionModel`.
    //   - EMPHASIS/SELECT/BLUR states, event/tooltip/state triggers (`applyOptionStyleForRegion`'s
    //     `ensureState(...)`, `resetEventTriggerForRegion`, `resetTooltipForRegion`,
    //     `resetStateTriggerForRegion`) — deferred with states/events. Only the NORMAL itemStyle is drawn.
    // ================================================================================================
    private func _buildGeoJSON(_ geo: Geo, _ geoModel: GeoModel, _ api: ExtensionAPI) {

        // upstream: geo.dataToPoint applies projection.project then the view transform. Skip nil points
        //   (upstream `newPt && outPoints.push(newPt)` / `projection may return null point`).
        func projectRing(_ ring: [[Double]]) -> [VectorArray] {
            var out: [VectorArray] = []
            for p in ring {
                if let np = geo.dataToPoint(p, false), np.count >= 2 {
                    out.append(VectorArray(np[0], np[1]))
                }
            }
            return out
        }

        // upstream: regionsGroupByName = createHashMap(); regionsInfoByName = createHashMap();
        //   Consider duplicated `properties.name` across regions — reuse the same region group (and its
        //   cached region model) so a name is styled/labeled once.
        var regionsGroupByName: [String: Group] = [:]
        var regionModelByName: [String: Model] = [:]

        for region in geo.regions {
            // Only GeoJSON regions carry `geometries`. (geoSVG regions are handled by the deferred SVG path.)
            guard let gjRegion = region as? GeoJSONRegion else {
                continue
            }
            let regionName = region.name

            let regionGroup: Group
            let regionModel: Model
            if let existing = regionsGroupByName[regionName] {
                regionGroup = existing
                regionModel = regionModelByName[regionName]!
            }
            else {
                // upstream: regionGroup = new graphic.Group(); regionsGroup.add(regionGroup);
                regionGroup = Group()
                _ = self.group.add(regionGroup)

                // upstream (geo component, no data): regionModel = mapOrGeoModel.getRegionModel(regionName);
                regionModel = geoModel.getRegionModel(regionName)

                // upstream: const silent = regionModel.get('silent', true); silent != null && (regionGroup.silent = silent);
                if let silent = regionModel.get("silent", true), !(silent is NSNull) {
                    regionGroup.silent = jsTruthy(silent)
                }

                regionsGroupByName[regionName] = regionGroup
                regionModelByName[regionName] = regionModel
            }

            // upstream: const polygonSubpaths = []; const polylineSubpaths = [];
            var polygonSubpaths: [Path] = []
            var polylineSubpaths: [Path] = []

            for geometry in gjRegion.geometries {
                // Polygon and MultiPolygon
                if geometry.type == "polygon", let polyGeo = geometry as? GeoJSONPolygonGeometry {
                    // upstream: let polys = [geometry.exterior].concat(geometry.interiors || []);
                    //   (projectionStream branch DEFERRED — see block above.)
                    var polys: [[[Double]]] = [polyGeo.exterior]
                    polys.append(contentsOf: polyGeo.interiors ?? [])
                    for poly in polys {
                        // upstream: new graphic.Polygon(getPolyShape(poly));
                        var shape = PolygonShape()
                        shape.points = projectRing(poly)
                        polygonSubpaths.append(Polygon(["shape": shape as PathShape]))
                    }
                }
                // LineString and MultiLineString
                else if let lineGeo = geometry as? GeoJSONLineStringGeometry {
                    // upstream: let points = geometry.points; each(points, points => polylineSubpaths.push(...))
                    for points in lineGeo.points {
                        var shape = PolylineShape()
                        shape.points = projectRing(points)
                        polylineSubpaths.append(Polyline(["shape": shape as PathShape]))
                    }
                }
            }

            // upstream: const centerPt = transformPoint(region.getCenter(), projection && projection.project);
            let centerRaw = geo.dataToPoint(gjRegion.getCenter(), false)

            // upstream: createCompoundPath(subpaths, isLine?) — builds one CompoundPath over the subpaths,
            //   styles it, and resets its label.
            func createCompoundPath(_ subpaths: [Path], _ isLine: Bool) {
                if subpaths.isEmpty {
                    return
                }
                // upstream: new graphic.CompoundPath({ culling: true, segmentIgnoreThreshold: 1, shape: { paths } });
                var cpShape = CompoundPathShape()
                cpShape.paths = subpaths
                let compoundPath = CompoundPath(["shape": cpShape as PathShape])
                compoundPath.culling = true
                compoundPath.segmentIgnoreThreshold = 1
                _ = regionGroup.add(compoundPath)

                // upstream: applyOptionStyleForRegion(api, data, ..., compoundPath, dataIdx, regionModel);
                //   STATIC subset: only the NORMAL itemStyle (emphasis/select/blur states DEFERRED).
                let normalStyleModel = regionModel.getModel("itemStyle")
                let normalStyle = geoGetFixedItemStyle(normalStyleModel)
                var pathStyle = geoPathStyleFromDict(normalStyle)
                // upstream: el.style.strokeNoScale = true;
                pathStyle.strokeNoScale = true

                // upstream: fixLineStyle — for a "line" compound, stroke = stroke || fill; fill = null.
                if isLine {
                    if pathStyle.stroke == nil { pathStyle.stroke = pathStyle.fill }
                    pathStyle.fill = nil
                }

                compoundPath.useStyle(pathStyle)
            }

            // upstream: createCompoundPath(polygonSubpaths); createCompoundPath(polylineSubpaths, true);
            createCompoundPath(polygonSubpaths, false)
            createCompoundPath(polylineSubpaths, true)

            // upstream: resetLabelForRegion(...) is called per compound path (attaching the label as the
            //   path's textContent with a percent `textConfig.position`). STATIC reproduction: draw ONE
            //   standalone `ZRText` at the projected centroid per region (the region-name label). Only the
            //   NORMAL label is drawn; emphasis/select label states + formatter fetcher are DEFERRED.
            if !polygonSubpaths.isEmpty || !polylineSubpaths.isEmpty {
                self._resetLabelForRegion(geoModel, regionModel, regionName, centerRaw, regionGroup)
            }
        }
    }

    // upstream: resetLabelForRegion (STATIC subset). For the geo component the label is drawn when the
    //   region label model's `show` is truthy; text is the formatted region label (default: the region
    //   name), placed centered on the projected centroid.
    private func _resetLabelForRegion(
        _ geoModel: GeoModel,
        _ regionModel: Model,
        _ regionName: String,
        _ centerPt: [Double]?,
        _ regionGroup: Group
    ) {
        let labelModel = regionModel.getModel("label")
        // upstream drives visibility through the label states model; here honor the normal `show` flag.
        //   (GeoModel default `label.show` is false — labels are off unless enabled.)
        if !jsTruthy(labelModel.get("show")) {
            return
        }
        guard let centerPt = centerPt, centerPt.count >= 2 else {
            return
        }

        // upstream defaultText: regionName; label formatter via `getFormattedLabel(regionName, 'normal')`.
        let content = geoModel.getFormattedLabel(regionName, "normal") ?? regionName

        // PORT-TODO: minimal faithful reproduction of `setLabelStyle`'s NORMAL text style (text / font /
        //   fill / align), mirroring CalendarView.calendarCreateTextStyle + FunnelView._updateLabel.
        var style = TextStyleProps()
        style.text = content
        style.font = labelModel.getFont()
        style.fill = labelModel.getTextColor()
        // upstream specifiedTextOpt for `labelXY`: { normal: { align: 'center', verticalAlign: 'middle' } }.
        style.align = .center
        style.verticalAlign = .middle
        style.x = centerPt[0]
        style.y = centerPt[1]

        // upstream label z2 lift is handled by the states system; a plain backdrop label keeps a modest z2.
        let textEl = ZRText(["z2": 10.0])
        textEl.useStyle(style)
        // upstream: (el as ECElement).disableLabelAnimation = true;  → animation DEFERRED (no-op here).

        _ = regionGroup.add(textEl)
    }

    // ------------------------------------------------------------------------------------------------
    // DEFERRED interaction hooks (roam / select / events) — kept as documented no-ops for surface parity.
    // ------------------------------------------------------------------------------------------------

    // upstream: __updateOnOwnRoam(payload, model, api) { this._mapDraw && this._mapDraw.__updateOnOwnRoam(model); }
    // PORT-TODO (DEFERRED — roam): no MapDraw/transformGroup to re-transform. A no-op until roam lands.

    // upstream: private _handleRegionClick(e) { findEventDispatcher(...); this._api.dispatchAction({ type: 'geoToggleSelect', ... }); }
    // PORT-TODO (DEFERRED — events/select): region click → `geoToggleSelect` dispatch. Not wired.

    // upstream: updateSelectStatus(model, ecModel, api) { traverse group, enter/leaveSelect per isSelected }
    // PORT-TODO (DEFERRED — select states): select highlight traversal. Not wired.

    // upstream: findHighDownDispatchers(name) { return this._mapDraw && this._mapDraw.findHighDownDispatchers(...); }
    // PORT-TODO (DEFERRED — emphasis): hover-link dispatchers. Not wired.

    // upstream: dispose() { this._mapDraw && this._mapDraw.remove(); }
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // STATIC: nothing persistent to tear down (no MapDraw / roam controller).
        _ = self.group.removeAll()
    }
}

// export default GeoView;  → `public final class GeoView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of GeoView.ts upstream. `geoGetFixedItemStyle`
// reproduces MapDraw.getFixedItemStyle; the rest mirror the file-private helpers
// in CalendarView (dynamic-option coercions, the style-bag → PathStyleProps
// bridge). Delete each when its real sibling lands (util/graphic, util/states)
// and call it directly.
// ============================================================================

// upstream (MapDraw.ts): function getFixedItemStyle(model) { const itemStyle = model.getItemStyle();
//   const areaColor = model.get('areaColor'); if (areaColor != null) { itemStyle.fill = areaColor; } return itemStyle; }
private func geoGetFixedItemStyle(_ model: Model) -> [String: Any] {
    var itemStyle = model.getItemStyle()
    let areaColor = model.get("areaColor")
    if let areaColor = areaColor, !(areaColor is NSNull) {
        itemStyle["fill"] = areaColor
    }
    return itemStyle
}

/// Coerce a dynamic option value to Double, tolerating Int boxing (CONVENTIONS trap #1). Mirrors CalendarView.numOpt.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)`); mirrors CalendarView.jsTruthy (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic itemStyle bag
///   ([String: Any] — the `getItemStyle()` result, post `getFixedItemStyle`) onto the typed `PathStyleProps`.
///   Same deviation as CalendarView.calendarPathStyleFromDict; numbers via `numOpt` (Int-drop trap). Delete
///   when the graphic bridge lands.
private func geoPathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern (ZRColor non-string); only the String form
    //   (incl. the sentinel 'none') is mapped here.
    if let v = geoColorString(dict["fill"]) { s.fill = .string(v) }
    if let v = geoColorString(dict["stroke"]) { s.stroke = .string(v) }
    if let v = numOpt(dict["lineWidth"]) { s.lineWidth = v }
    if let v = dict["lineCap"] as? String { s.lineCap = v }
    if let v = dict["lineJoin"] as? String { s.lineJoin = v }
    if let v = numOpt(dict["miterLimit"]) { s.miterLimit = v }
    if let v = numOpt(dict["opacity"]) { s.opacity = v }
    if let v = numOpt(dict["fillOpacity"]) { s.fillOpacity = v }
    if let v = numOpt(dict["strokeOpacity"]) { s.strokeOpacity = v }
    if let v = numOpt(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = numOpt(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = numOpt(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = numOpt(dict["lineDashOffset"]) { s.lineDashOffset = v }
    // PORT-TODO: `lineDash` (number[] | false) mapping deferred (LineDash enum bridge).
    return s
}

/// Bridge a visual/style paint value (raw `String` or EChartsKit `ZRColor`) to a solid color string.
///   (gradient/pattern are out of the region-backdrop scope.) Mirrors CalendarView.colorString.
private func geoColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}
