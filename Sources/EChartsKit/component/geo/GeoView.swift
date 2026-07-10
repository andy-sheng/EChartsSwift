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
    // Consulted by the emphasis/blur system. The geoSVG path now marks named regions as highDown
    //   dispatchers (see `_buildSVG`), so hover-to-highlight works for the geo component.
    public var focusBlurEnabled = true

    // upstream (MapDraw): private _svgDispatcherMap: HashMap<Element[], RegionName>;
    //   A named region may map to MULTIPLE SVG elements (a glyph + a label sharing one name). The map is
    //   the highDown-dispatcher lookup for `findHighDownDispatchers` (hover-link / highlight by name).
    var _svgDispatcherMap: [String: [Element]] = [:]

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
        if geo.resourceType == "geoJSON" {
            self._buildGeoJSON(geo, geoModel, api)
        }
        else if geo.resourceType == "geoSVG" {
            self._buildSVG(geo, geoModel, api)
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

    // ================================================================================================
    // Inlined subset of `MapDraw._buildSVG` (component/helper/MapDraw.ts) — the GEO COMPONENT variant.
    //
    // For a geoSVG map: fetch the pooled parsed-SVG graphic (`GeoSVGResource.useGraphic`), copy the geo
    // view's OVERALL transform (raw-svg-rect → view-rect, WITH roam pan/zoom folded in) onto a wrapper
    // group holding the parsed root, apply the region `itemStyle` (MERGED — for geoSVG the default
    // itemStyle carries a border but NO fill, so the SVG's authored `fill` is preserved) to each NAMED
    // Displayable, stamp the emphasis/select/blur itemStyle STATES, mark self-named regions as highDown
    // dispatchers (hover-to-highlight) with a NAME LABEL, and add the group to the view.
    //
    // ROAM (task c): upstream copies the RAW transform onto `_svgGroup` and applies the ROAM transform to
    //   the parent `_transformGroup` (net world transform = ROAM ∘ RAW). This driver has no separate
    //   transformGroup (the group is rebuilt each render — see the roamHelperGeo header), so we copy the
    //   combined OVERALL transform (== ROAM ∘ RAW; @see viewCoordSysUpdateOverallTrans) DIRECTLY onto the
    //   single svg wrapper group. On `geoRoam` the full `update()` re-seeds the view roam state
    //   (geoRoamApplyStateToView) and this method re-copies the fresh OVERALL trans → the SVG root pans/zooms.
    //
    // PORT-TODO (DEFERRED — faithful to a STATIC render):
    //   - series-map DATA: handled by MapView._buildSVG (the geo component backdrop has no series data).
    //   - `el.z2EmphasisLift = 0` (ECElement augmentation not ported) — the states engine may apply the
    //     default emphasis z2 lift to an SVG region on hover; harmless for the standard case.
    //   - event/tooltip triggers (`resetEventTriggerForRegion` / `resetTooltipForRegion`) — the geo custom
    //     `eventData` + tooltip config depend on innerStore.eventData / setTooltipConfig (deferred).
    // ================================================================================================
    private func _buildSVG(_ geo: Geo, _ geoModel: GeoModel, _ api: ExtensionAPI) {
        let mapName = geo.map
        guard let resource = geoSourceManager.getGeoResource(mapName) as? GeoSVGResource else {
            return
        }

        // upstream: viewCoordSysCopyTrans(this._svgGroup, viewCoordSys, VIEW_COORD_SYS_TRANS_RAW);
        //           this._useSVG(mapName) → svgGroup.add(svgGraphic.root)
        //   (see ROAM note above — OVERALL folds the roam transform into the single wrapper group.)
        let svgGraphic = resource.useGraphic(self.uid)
        let svgGroup = Group()
        _ = viewCoordSysCopyTrans(svgGroup, geo.view, VIEW_COORD_SYS_TRANS_OVERALL)
        _ = svgGroup.add(svgGraphic.root)

        // upstream: const svgDispatcherMap = this._svgDispatcherMap = createHashMap<Element[], RegionName>();
        var svgDispatcherMap: [String: [Element]] = [:]
        // upstream: let focusSelf = false;
        var focusSelf = false

        // upstream: each(named, namedItem => { ... })
        for namedItem in svgGraphic.named {
            // Note that we also allow different elements to share the same name (e.g. a city glyph and its
            //   label), so region option applies to each and their tooltip is defined once (upstream note).
            let regionName = namedItem.name
            let svgNodeTagLower = namedItem.svgNodeTagLower
            let el = namedItem.el
            let regionModel = geoModel.getRegionModel(regionName)

            // OPTION_STYLE_ENABLED tags (rect/circle/line/ellipse/polygon/polyline/path) → itemStyle.
            //   text/tspan/image can be named but are not styled by region option (upstream note).
            if OPTION_STYLE_ENABLED_SVG_TAGS.contains(svgNodeTagLower), let path = el as? Path {
                self._applyOptionStyleForRegionSVG(path, regionModel)
            }

            // upstream: if (el instanceof Displayable) { el.culling = true; }
            if let disp = el as? Displayable {
                disp.culling = true
            }

            // upstream: const silent = regionModel.get('silent', true); silent != null && (el.silent = silent);
            if let silent = regionModel.get("silent", true), !(silent is NSNull) {
                el.silent = jsTruthy(silent)
            }

            // upstream: (el as ECElement).z2EmphasisLift = 0;  → ECElement augmentation not ported (DEFERRED).

            // upstream: if (!namedItem.namedFrom) { ...label + event + state trigger... }
            if namedItem.namedFrom == nil {
                // upstream: LABEL_HOST_MAP (OPTION_STYLE_ENABLED + 'g') → label at the <g>/element center.
                if LABEL_HOST_SVG_TAGS.contains(svgNodeTagLower) {
                    self._resetLabelForRegionSVG(geoModel, regionModel, regionName, el)
                }

                // upstream: STATE_TRIGGER_TAG_MAP (OPTION_STYLE_ENABLED + 'g') → highDown dispatcher.
                if STATE_TRIGGER_SVG_TAGS.contains(svgNodeTagLower) {
                    let focus = self._resetStateTriggerForRegionSVG(geoModel, el, regionName, regionModel)
                    if let focusStr = focus as? String, focusStr == "self" {
                        focusSelf = true
                    }
                    svgDispatcherMap[regionName, default: []].append(el)
                }
            }
        }

        self._svgDispatcherMap = svgDispatcherMap

        // upstream: this._enableBlurEntireSVG(focusSelf, mapOrGeoModel);
        self._enableBlurEntireSVG(focusSelf, geoModel, svgGraphic)

        _ = self.group.add(svgGroup)
    }

    // upstream: applyOptionStyleForRegion (MapDraw.ts:617) — the geoSVG NORMAL style + emphasis/select/blur
    //   state styles for one named Displayable. The GEO component has no series data, so the visualMap fill
    //   branch is omitted here (see MapView._buildSVG for the data-encoded map-series variant).
    private func _applyOptionStyleForRegionSVG(_ path: Path, _ regionModel: Model) {
        let styleModel = regionModel.getModel("itemStyle")
        let itemStyle = geoGetFixedItemStyle(styleModel)
        var s = path.pathStyle ?? PathStyleProps()
        // MERGE (upstream `el.setStyle(normalStyle)`): only overwrite keys present in itemStyle, so a
        //   geoSVG shape keeps its authored SVG `fill` when the region option sets no color.
        if let v = geoColorString(itemStyle["fill"]) { s.fill = .string(v) }
        if let v = geoColorString(itemStyle["stroke"]) { s.stroke = .string(v) }
        if let v = numOpt(itemStyle["lineWidth"]) { s.lineWidth = v }
        if let v = numOpt(itemStyle["opacity"]) { s.opacity = v }
        if let v = numOpt(itemStyle["fillOpacity"]) { s.fillOpacity = v }
        if let v = numOpt(itemStyle["strokeOpacity"]) { s.strokeOpacity = v }
        // upstream: el.style.strokeNoScale = true;
        s.strokeNoScale = true
        path.useStyle(s)

        // upstream: el.ensureState('emphasis'/'select'/'blur').style = getFixedItemStyle(...) ;
        //           setDefaultStateProxy(el).
        //   `setStatesStylesFromModel` stamps ensureState(emphasis|blur|select).style = model.getItemStyle()
        //   (PORT DEVIATION, same as MapView._buildGeoJSON: the shared helper uses getItemStyle, not the
        //   map-specific getFixedItemStyle/areaColor fixup — adequate for the standard itemStyle case). The
        //   state proxy is (re)installed by toggleHoverEmphasis's child traverse below.
        states.setStatesStylesFromModel(path, regionModel)
        states.setDefaultStateProxy(path)
    }

    // upstream: resetStateTriggerForRegion (MapDraw.ts:821) — mark the named element a highDown dispatcher
    //   carrying the region's emphasis focus/blurScope, then enable the geo-component hover-link features
    //   (`enableComponentHighDownFeatures`, so highlight-by-name resolves this element). Returns the focus.
    @discardableResult
    private func _resetStateTriggerForRegionSVG(
        _ geoModel: GeoModel, _ el: Element, _ regionName: String, _ regionModel: Model
    ) -> InnerFocus? {
        // upstream: el.highDownSilentOnTouch = !!mapOrGeoModel.get('selectedMode');  → not ported (touch).
        let emphasisModel = regionModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
        // upstream: if (isGeoModel(mapOrGeoModel)) { enableComponentHighDownFeatures(el, geoModel, name); }
        states.enableComponentHighDownFeatures(el, geoModel, regionName)
        return focus
    }

    // upstream: resetLabelForRegion (MapDraw.ts:679) — the geoSVG variant (data==null, labelXY==null →
    //   position "inside"). Retrofitted onto the SHARED LABEL CORE (`labelStyle.setLabelStyle`): the label
    //   is attached as the named element's `textContent` (default position "inside" → centred in the
    //   element bounding rect), and per-state `show` is honoured by setLabelStyle itself.
    private func _resetLabelForRegionSVG(
        _ geoModel: GeoModel, _ regionModel: Model, _ regionName: String, _ el: Element
    ) {
        // upstream: isGeoModel(mapOrGeoModel) ⇒ always draw the label (no data → labelFetcher = geoModel,
        //   query = regionName). The port folds the geo formatter into `defaultText` (getFormattedLabel),
        //   so no Double labelDataIndex is needed for the name-keyed geo label.
        var opt = SetLabelStyleOpt()
        opt.defaultText = geoModel.getFormattedLabel(regionName, "normal") ?? regionName

        let labelStatesModels = labelStyle.getLabelStatesModels(regionModel)
        labelStyle.setLabelStyle(el, labelStatesModels, opt)
    }

    // upstream: _enableBlurEntireSVG (MapDraw.ts:481) — when a region focus is 'self', blur the ENTIRE SVG
    //   on emphasis (only for the geo component; series-map does not support it yet). Sets a `blur`-state
    //   opacity on every non-group SVG element (without overwriting a region-option blur opacity).
    private func _enableBlurEntireSVG(
        _ focusSelf: Bool, _ geoModel: GeoModel, _ svgGraphic: GeoSVGGraphicRecord
    ) {
        guard focusSelf else { return }
        // upstream: const blurStyle = mapOrGeoModel.getModel(['blur', 'itemStyle']).getItemStyle();
        let blurStyle = geoModel.getModel(["blur", "itemStyle"]).getItemStyle()
        let opacity = numOpt(blurStyle["opacity"])
        _ = svgGraphic.root.traverse { el in
            if !el.isGroup, let disp = el as? Displayable {
                states.setDefaultStateProxy(disp)
                // upstream: const style = el.ensureState('blur').style || {};
                let blurState = disp.ensureState("blur")
                // Only support `opacity` (not sure other props suit Text/TSpan/Image). Do not overwrite a
                //   region-option blur opacity already set.
                var st: [String: Any] = blurState.style ?? [:]
                if st["opacity"] == nil, let opacity = opacity {
                    st["opacity"] = opacity
                }
                blurState.style = st
                // Enable `stateTransition` (animation).
                _ = disp.ensureState("emphasis")
            }
            return false
        }
    }

    // upstream: findHighDownDispatchers(name, geoModel) — the geoSVG branch returns the dispatcher elements
    //   registered for a region name (hover-link / highlight-by-name). Exposed for the high-down driver.
    public override func findHighDownDispatchers(_ name: String?) -> [Element]? {
        guard let name = name else { return [] }
        return self._svgDispatcherMap[name] ?? []
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
