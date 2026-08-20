// Ported from echarts/src/component/helper/MapDraw.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';          → `util` / `HashMap` (util/modelUtil.swift shim).
//   import RoamController from './RoamController';            → `RoamController` (sibling file).
//   import * as graphic from '../../util/graphic';            → util/graphic.swift free funcs (`setTooltipConfig`)
//                                                                + the ZRenderKit shape classes (Group/Rect/Polygon/Polyline/CompoundPath).
//   import { toggleHoverEmphasis, enableComponentHighDownFeatures, setDefaultStateProxy } from '../../util/states';
//                                                             → `states.*` (util/states.swift).
//   import geoSourceManager from '../../coord/geo/geoSourceManager';  → `geoSourceManager`.
//   import {getUID} from '../../util/component';              → `component.getUID` (util/componentUtil.swift).
//   import ExtensionAPI / GeoModel / MapSeries / GlobalModel / Geo / Model / SeriesData → same names
//     (`MapSeriesModel` for MapSeries — the Swift class name already chosen in chart/map/MapSeries.swift).
//   import { Payload, ECElement, InnerFocus, ... } from '../../util/types';  → util/types.swift.
//   import GeoView / MapView                                  → see the `fromView` PORT-NOTE on `draw`.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';  → `labelStyle.*`.
//   import { getECData } from '../../util/innerStore';        → `innerStore.getECData`.
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';  → `createOrUpdatePatternFromDecal`.
//   import ZRText, {TextStyleProps} from 'zrender/src/graphic/Text';    → ZRenderKit `ZRText`/`TextStyleProps`.
//   import View, { applyViewCoordSysTransToElement, VIEW_COORD_SYS_TRANS_RAW, VIEW_COORD_SYS_TRANS_ROAM,
//                  viewCoordSysCopyTrans, viewCoordSysCopyViewRect } from '../../coord/View';
//                                                             → coord/View.swift (all top-level free funcs).
//   import { GeoSVGGraphicRecord, GeoSVGResource } from '../../coord/geo/GeoSVGResource';  → same names.
//   import Displayable / Element from 'zrender';              → ZRenderKit.
//   import { GeoJSONRegion } from '../../coord/geo/Region';   → `GeoJSONRegion` (+ `GeoJSONPolygonGeometry` /
//                                                                `GeoJSONLineStringGeometry` for the union).
//   import { SVGNodeTagLower } from 'zrender/src/tool/parseSVG';  → `SVGNodeTagLower` (typealias String).
//   import { makeInner } from '../../util/model';             → `model.makeInner`.
//   import { GeoProjection, ProjectionStream } from '../../coord/geo/geoTypes';  → geoTypes.swift / Region.swift.
//   import { MapOrGeoModel } from '../../coord/geo/geoCreator';  → `MapOrGeoModel` (= `ComponentModel`).
//   import { updateRoamControllerSimply } from './roamHelper';
//     → `updateGeoRoamControllerSimply` (component/helper/roamHelperGeo.swift — the GEO/MAP slice of
//       roamHelper; it already bakes in upstream's MapDraw `isInSelf` (`coordinateSystem.containPoint`)
//       and the `false`/`true` roam-type-default/zoomOnMouseWheel tail args, so those params are not
//       re-passed here. `clipRect` IS passed (the helper grew the `clipRect:` param + `isInClip`).)
//   import { transformableGetLocalTransform } from 'zrender/src/core/Transformable';  → ZRenderKit.
//   import { applyTransform } from 'zrender/src/core/vector';  → `vector.applyTransform` (value-returning, §10).

// upstream: interface RegionsGroup extends graphic.Group {}
//   An empty interface extension — a plain alias here.
private typealias RegionsGroup = Group

// upstream: type RegionModel = ReturnType<GeoModel['getRegionModel']> | ReturnType<MapSeries['getRegionModel']>;
//   Both Swift getters return `Model`, so the union collapses.
private typealias RegionModel = Model

// upstream: type RegionName = string;
private typealias RegionName = String

/**
 * Only these tags enable use `itemStyle` if they are named in SVG.
 * Other tags like <text> <tspan> <image> might not suitable for `itemStyle`.
 * They will not be considered to be styled until some requirements come.
 */
// upstream: const OPTION_STYLE_ENABLED_TAGS + the three `createHashMap` lookups built from it.
//   A `Set` is the same membership lookup (`map.get(tag) != null` → `set.contains(tag)`).
// PORT-NOTE (scope): all of these are module-private in upstream TS and are file-private here. The
//   names are generic enough to collide with a future sibling geo/region port if left module-`internal`.
private let OPTION_STYLE_ENABLED_TAGS: [SVGNodeTagLower] = [
    "rect", "circle", "line", "ellipse", "polygon", "polyline", "path"
]
private let OPTION_STYLE_ENABLED_TAG_MAP: Set<SVGNodeTagLower> = Set(OPTION_STYLE_ENABLED_TAGS)
private let STATE_TRIGGER_TAG_MAP: Set<SVGNodeTagLower> = Set(OPTION_STYLE_ENABLED_TAGS + ["g"])
private let LABEL_HOST_MAP: Set<SVGNodeTagLower> = Set(OPTION_STYLE_ENABLED_TAGS + ["g"])

// upstream: const mapLabelRaw = makeInner<{ ignore: boolean }, ZRText>();
private final class MapLabelRaw {
    var ignore: Bool = false
    init() {}
}
private let mapLabelRaw: (ZRText) -> MapLabelRaw = model.makeInner { MapLabelRaw() }

// upstream: function getFixedItemStyle(model: Model<GeoItemStyleOption>) { ... }
private func getFixedItemStyle(_ model: Model) -> [String: Any] {
    var itemStyle = model.getItemStyle()
    let areaColor = model.get("areaColor")

    // If user want the color not to be changed when hover,
    // they should both set areaColor and color to be null.
    if let areaColor = areaColor, !(areaColor is NSNull) {
        itemStyle["fill"] = areaColor
    }

    return itemStyle
}

// Only stroke can be used for line.
// Using fill in style if stroke not exits.
// TODO Not sure yet. Perhaps a separate `lineStyle`?
// upstream: function fixLineStyle(styleHost: { style: graphic.Path['style'] })
//   PORT-NOTE: upstream's one duck-typed function covers BOTH the live `path.style` and each
//   `path.states[name].style` bag. Swift types those differently (`PathStyleProps` vs `[String: Any]`),
//   so it is emitted as two overloads with identical semantics.
private func fixLineStyle(_ styleHost: Path) {
    guard var style = styleHost.pathStyle else { return }
    if style.stroke == nil { style.stroke = style.fill }
    style.fill = nil
    styleHost.pathStyle = style
}
private func fixLineStyle(_ styleHost: ElementState) {
    guard var style = styleHost.style else { return }
    let stroke = style["stroke"]
    if stroke == nil || stroke is NSNull { style["stroke"] = style["fill"] }
    style["fill"] = NSNull()
    styleHost.style = style
}

// upstream: class MapDraw
// CONVENTIONS §4: TS `class` → Swift `final class` (reference identity — it owns a live scene subtree).
public final class MapDraw {

    // upstream: private uid: string;
    private var uid: String

    // upstream: private _controller: RoamController;
    //   PORT-NOTE: upstream constructs it optimistically from `api.getZr()`. The Swift `getZr()` is
    //   Optional (a model-only ExtensionAPI has no zr), so this is an IUO — explicitly annotated
    //   (MEMORY: a `let`-bound IUO infers `Optional`), and every use is nil-guarded.
    private var _controller: RoamController!

    // upstream: readonly group: graphic.Group;
    public let group: Group

    /**
     * This flag is used to make sure that only one among
     * `pan`, `zoom`, `click` can occurs, otherwise 'selected'
     * action may be triggered when `pan`, which is unexpected.
     */
    // upstream: private _mouseDownFlag: boolean;
    private var _mouseDownFlag: Bool = false

    // upstream: private _transformGroup: graphic.Group;
    private var _transformGroup: Group

    // upstream: private _regionsGroup: RegionsGroup;
    private var _regionsGroup: RegionsGroup

    // upstream: private _regionsGroupByName: zrUtil.HashMap<RegionsGroup>;
    private var _regionsGroupByName: HashMap<RegionsGroup>?

    // upstream: private _svgMapName: string;
    private var _svgMapName: String?

    // upstream: private _svgGroup: graphic.Group;
    private var _svgGroup: Group

    // upstream: private _svgGraphicRecord: GeoSVGGraphicRecord;
    private var _svgGraphicRecord: GeoSVGGraphicRecord?

    // A name may correspond to multiple graphics.
    // Used as event dispatcher.
    // upstream: private _svgDispatcherMap: zrUtil.HashMap<Element[], RegionName>;
    private var _svgDispatcherMap: HashMap<[Element]>?

    // upstream: constructor(api: ExtensionAPI)
    public init(_ api: ExtensionAPI) {
        let group = Group()
        self.group = group
        let transformGroup = Group()
        self._transformGroup = transformGroup
        _ = group.add(transformGroup)
        self.uid = component.getUID("ec_map_draw")

        let regionsGroup = Group()
        self._regionsGroup = regionsGroup
        let svgGroup = Group()
        self._svgGroup = svgGroup
        _ = transformGroup.add(regionsGroup)
        _ = transformGroup.add(svgGroup)

        if let zr = api.getZr() {
            self._controller = RoamController(zr)
        }
    }

    // upstream: draw(mapOrGeoModel, ecModel, api, fromView: MapView | GeoView, payload): void
    //   PORT-NOTE (registry TRAP 1 — the `MapView | GeoView` union): `MapView` extends `ChartView` while
    //   `GeoView` extends `ComponentView`, and this port has NO common base for the two. `fromView` is
    //   UNUSED by upstream's body (it is only forwarded to `_updateMapSelectHandler`, which ignores it),
    //   so it is typed `AnyObject?` rather than inventing a protocol that risks the witness trap.
    public func draw(
        _ mapOrGeoModel: MapOrGeoModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ fromView: AnyObject?,
        _ payload: Payload?
    ) {
        // Map series has data. GEO model that controlled by map series
        // will be assigned with map data. Other GEO model has no data.
        // upstream: let data = (mapOrGeoModel as MapSeries).getData && (mapOrGeoModel as MapSeries).getData();
        var data: SeriesData? = (mapOrGeoModel as? MapSeriesModel)?.getData()
        if isGeoModel(mapOrGeoModel) {
            ecModel.eachComponent(
                QueryConditionKindA(mainType: "series", subType: "map"),
                { cmpt, _ in
                    guard let mapSeries = cmpt as? MapSeriesModel else { return }
                    if data == nil && mapSeries.getHostGeoModel() === mapOrGeoModel {
                        data = mapSeries.getData()
                    }
                }
            )
        }

        // upstream: const geo = mapOrGeoModel.coordinateSystem;
        //   PORT-NOTE: `MapOrGeoModel` erases to `ComponentModel`, which declares no `coordinateSystem`
        //   (each subclass does). `geoRoamHostCoordSys` (roamHelperGeo.swift) is the already-ported
        //   GeoModel/MapSeriesModel dispatch for exactly this — reuse it (PORTING §2).
        //   PORT-NOTE (§12): `Geo.view` is `View!` (genuinely nilable), so it is folded into the guard
        //   rather than force-unwrapped — matching `__updateOnOwnRoam` below.
        guard let geo = geoRoamHostCoordSys(mapOrGeoModel), let viewCoordSys = geo.view else {
            return
        }

        let regionsGroup = self._regionsGroup
        let transformGroup = self._transformGroup

        // No animation when first draw or in action
        let isFirstDraw = regionsGroup.childAt(0) == nil || payload != nil

        var clipRect: BoundingRect?
        if geo.shouldClip() == true {
            clipRect = viewCoordSysCopyViewRect(nil, viewCoordSys)
            var clipShape = RectShape()
            clipShape.x = clipRect!.x
            clipShape.y = clipRect!.y
            clipShape.width = clipRect!.width
            clipShape.height = clipRect!.height
            self.group.setClipPath(Rect(["shape": clipShape as PathShape]))
        }
        else {
            self.group.removeClipPath()
        }

        applyViewCoordSysTransToElement(
            transformGroup,
            VIEW_COORD_SYS_TRANS_ROAM,
            viewCoordSys,
            isFirstDraw ? nil : mapOrGeoModel
        )

        // upstream: const isVisualEncodedByVisualMap = data && data.getVisual('visualMeta')
        //     && data.getVisual('visualMeta').length > 0;
        var isVisualEncodedByVisualMap = false
        if let data = data, let visualMeta = data.getVisual("visualMeta") as? [Any] {
            isVisualEncodedByVisualMap = visualMeta.count > 0
        }

        if geo.resourceType == "geoJSON" {
            self._buildGeoJSON(viewCoordSys, api, geo, mapOrGeoModel, data, isVisualEncodedByVisualMap)
        }
        else if geo.resourceType == "geoSVG" {
            self._buildSVG(viewCoordSys, api, geo, mapOrGeoModel, data, isVisualEncodedByVisualMap)
        }

        // upstream: updateRoamControllerSimply(mapOrGeoModel, api, this._controller,
        //     (e, x, y) => mapOrGeoModel.coordinateSystem.containPoint([x, y]),
        //     clipRect, () => { mapDraw._mouseDownFlag = false; }, false, true);
        //   The ported `updateGeoRoamControllerSimply` already bakes in the `isInSelf` predicate and the
        //   two tail args; its 4th param is the port's `onDispatched` seam, which is the natural home for
        //   upstream's `onMouseDownOrPointerDown`-ish `_mouseDownFlag` reset. `clipRect` is passed through
        //   to `RoamOption.isInClip` (the roam limit for a clipped geo), as upstream does.
        if let controller = self._controller {
            updateGeoRoamControllerSimply(mapOrGeoModel, api, controller, clipRect: clipRect, { [weak self] in
                self?._mouseDownFlag = false
            })
        }

        self._updateMapSelectHandler(mapOrGeoModel, regionsGroup, api, fromView)
    }

    // upstream: __updateOnOwnRoam(mapOrGeoModel: MapOrGeoModel): void
    public func __updateOnOwnRoam(_ mapOrGeoModel: MapOrGeoModel) {
        guard let geo = geoRoamHostCoordSys(mapOrGeoModel), let view = geo.view else {
            return
        }
        applyViewCoordSysTransToElement(
            self._transformGroup,
            VIEW_COORD_SYS_TRANS_ROAM,
            view,
            nil
        )
    }

    // upstream: private _buildGeoJSON(viewCoordSys, api, geo, mapOrGeoModel, data, isVisualEncodedByVisualMap)
    private func _buildGeoJSON(
        _ viewCoordSys: View,
        _ api: ExtensionAPI,
        _ geo: Geo,
        _ mapOrGeoModel: MapOrGeoModel,
        _ data: SeriesData?,
        _ isVisualEncodedByVisualMap: Bool
    ) {
        let regionsGroupByName: HashMap<RegionsGroup> = createHashMap()
        self._regionsGroupByName = regionsGroupByName
        // upstream: regionsInfoByName = createHashMap<{ dataIdx; regionModel }, string>()
        let regionsInfoByName: HashMap<RegionInfo> = createHashMap()
        let regionsGroup = self._regionsGroup
        let projection = geo.projection
        // upstream: const projectionStream = projection && projection.stream;
        //   PORT-TODO: the ported `GeoProjection` protocol (coord/geo/Region.swift) has NO `stream`
        //   member yet (see the consolidation PORT-NOTE in geoTypes.swift), so the d3-style
        //   clip/resample stream path is unreachable; `projectPolys` below is ported and dormant.
        let projectionStream: ((ProjectionStream) -> ProjectionStream)? = nil

        let transMt = transformableGetLocalTransform(
            viewCoordSysCopyTrans(nil, viewCoordSys, VIEW_COORD_SYS_TRANS_RAW)
        )

        func transformPoint(_ point: [Double]?, _ project: ((([Double]) -> [Double]?))?) -> [Double]? {
            var point = point
            if let project = project, let p = point {
                // projection may return null point.
                point = project(p)
            }
            guard let p = point, p.count >= 2 else { return nil }
            let v = vector.applyTransform(VectorArray(p[0], p[1]), transMt)
            return [v.x, v.y]
        }

        func transformPolygonPoints(_ inPoints: [[Double]]) -> [VectorArray] {
            var outPoints: [VectorArray] = []
            // If projectionStream is provided. Use it instead of single point project.
            let project = (projectionStream == nil) ? projection?.project : nil
            for i in 0..<inPoints.count {
                if let newPt = transformPoint(inPoints[i], project) {
                    outPoints.append(VectorArray(newPt[0], newPt[1]))
                }
            }
            return outPoints
        }

        _ = regionsGroup.removeAll()

        // Only when the resource is GeoJSON, there is `geo.regions`.
        for regionBase in geo.regions {
            guard let region = regionBase as? GeoJSONRegion else { continue }
            let regionName = region.name

            // Consider in GeoJson properties.name may be duplicated, for example,
            // there is multiple region named "United Kindom" or "France" (so many
            // colonies). And it is not appropriate to merge them in geo, which
            // will make them share the same label and bring trouble in label
            // location calculation.
            var regionGroup = regionsGroupByName.get(regionName)
            let existingInfo = regionsInfoByName.get(regionName)
            var dataIdx: Int? = existingInfo?.dataIdx
            var regionModel: RegionModel? = existingInfo?.regionModel

            if regionGroup == nil {
                let newGroup: RegionsGroup = Group()
                regionGroup = regionsGroupByName.set(regionName, newGroup)
                _ = regionsGroup.add(newGroup)

                dataIdx = data != nil ? data!.indexOfName(regionName) : nil
                // PORT-NOTE: `indexOfName` returns -1 on a miss (the common case: a GeoJSON has hundreds
                //   of regions, the series data a handful). Upstream builds a `Model` over `undefined`
                //   and continues; here `getItemModel(-1)` would trap, so the miss yields a nil model
                //   (every consumer below is `regionModel?` / guard-let). The geo branch goes through the
                //   safe `getRegionModel` dispatcher rather than a force cast on `mainType == "geo"`.
                regionModel = isGeoModel(mapOrGeoModel)
                    ? getRegionModel(mapOrGeoModel, regionName)
                    : ((data != nil && (dataIdx ?? -1) >= 0) ? data!.getItemModel(dataIdx!) : nil)

                // upstream: const silent = regionModel.get('silent', true); silent != null && (regionGroup.silent = silent);
                if let silent = regionModel?.get("silent", true), !(silent is NSNull) {
                    newGroup.silent = jsTruthy(silent)
                }

                regionsInfoByName.set(regionName, RegionInfo(dataIdx: dataIdx, regionModel: regionModel))
            }
            let theRegionGroup = regionGroup!

            var polygonSubpaths: [Path] = []
            var polylineSubpaths: [Path] = []

            for geometry in region.geometries {
                // Polygon and MultiPolygon
                if geometry.type == "polygon", let polyGeo = geometry as? GeoJSONPolygonGeometry {
                    // upstream: let polys = [geometry.exterior].concat(geometry.interiors || []);
                    var polys: [[[Double]]] = [polyGeo.exterior]
                    polys.append(contentsOf: polyGeo.interiors ?? [])
                    // upstream: if (projectionStream) { polys = projectPolys(polys, projectionStream); }
                    //   (see the `projectionStream` PORT-TODO above.)
                    for poly in polys {
                        var shape = PolygonShape()
                        shape.points = transformPolygonPoints(poly)
                        polygonSubpaths.append(Polygon(["shape": shape as PathShape]))
                    }
                }
                // LineString and MultiLineString
                else if let lineGeo = geometry as? GeoJSONLineStringGeometry {
                    let points = lineGeo.points
                    // upstream: if (projectionStream) { points = projectPolys(points, projectionStream, true); }
                    for pts in points {
                        var shape = PolylineShape()
                        shape.points = transformPolygonPoints(pts)
                        polylineSubpaths.append(Polyline(["shape": shape as PathShape]))
                    }
                }
            }

            let centerPt = transformPoint(region.getCenter(), projection?.project)

            func createCompoundPath(_ subpaths: [Path], _ isLine: Bool) {
                if subpaths.isEmpty {
                    return
                }
                var cpShape = CompoundPathShape()
                cpShape.paths = subpaths
                let compoundPath = CompoundPath(["shape": cpShape as PathShape])
                compoundPath.culling = true
                compoundPath.segmentIgnoreThreshold = 1
                _ = theRegionGroup.add(compoundPath)

                applyOptionStyleForRegion(
                    api, data, isVisualEncodedByVisualMap, compoundPath, dataIdx, regionModel
                )
                resetLabelForRegion(
                    mapOrGeoModel, data, compoundPath, regionName, regionModel, dataIdx, centerPt
                )

                if isLine {
                    fixLineStyle(compoundPath)
                    for (_, state) in compoundPath.states {
                        fixLineStyle(state)
                    }
                }
            }

            createCompoundPath(polygonSubpaths, false)
            createCompoundPath(polylineSubpaths, true)
        }

        // Ensure children have been added to `regionGroup` before calling them.
        regionsGroupByName.each { regionGroup, regionName in
            guard let info = regionsInfoByName.get(regionName) else { return }

            resetEventTriggerForRegion(
                mapOrGeoModel, data, regionGroup, regionName, info.regionModel, info.dataIdx
            )
            resetTooltipForRegion(
                mapOrGeoModel, data, regionGroup, regionName, info.regionModel
            )
            resetStateTriggerForRegion(
                mapOrGeoModel, regionGroup, regionName, info.regionModel
            )
        }
    }

    // upstream: private _buildSVG(viewCoordSys, api, geo, mapOrGeoModel, data, isVisualEncodedByVisualMap)
    private func _buildSVG(
        _ viewCoordSys: View,
        _ api: ExtensionAPI,
        _ geo: Geo,
        _ mapOrGeoModel: MapOrGeoModel,
        _ data: SeriesData?,
        _ isVisualEncodedByVisualMap: Bool
    ) {
        let mapName = geo.map

        _ = viewCoordSysCopyTrans(self._svgGroup, viewCoordSys, VIEW_COORD_SYS_TRANS_RAW)

        if self._svgResourceChanged(mapName) {
            self._freeSVG()
            self._useSVG(mapName)
        }

        let svgDispatcherMap: HashMap<[Element]> = createHashMap()
        self._svgDispatcherMap = svgDispatcherMap

        guard let svgGraphicRecord = self._svgGraphicRecord else {
            return
        }

        var focusSelf = false
        for namedItem in svgGraphicRecord.named {
            // Note that we also allow different elements have the same name.
            // For example, a glyph of a city and the label of the city have
            // the same name and their tooltip info can be defined in a single
            // region option.

            let regionName = namedItem.name
            let svgNodeTagLower = namedItem.svgNodeTagLower
            let el = namedItem.el

            let dataIdx: Int? = data != nil ? data!.indexOfName(regionName) : nil
            let regionModel = getRegionModel(mapOrGeoModel, regionName)

            if OPTION_STYLE_ENABLED_TAG_MAP.contains(svgNodeTagLower),
               let disp = el as? Displayable {
                applyOptionStyleForRegion(api, data, isVisualEncodedByVisualMap, disp, dataIdx, regionModel)
            }

            if let disp = el as? Displayable {
                disp.culling = true
            }

            // upstream: const silent = regionModel.get('silent', true); silent != null && (el.silent = silent);
            if let silent = regionModel?.get("silent", true), !(silent is NSNull) {
                el.silent = jsTruthy(silent)
            }

            // We do not know how the SVG like so we'd better not to change z2.
            // Otherwise it might bring some unexpected result. For example,
            // an area hovered that make some inner city can not be clicked.
            // upstream: (el as ECElement).z2EmphasisLift = 0;
            //   PORT-TODO: no scene-graph class conforms to `ECElement` yet (util/types.swift models the
            //   TS interface augmentation as a protocol), so this is a no-op cast — the states engine may
            //   still apply the default emphasis z2 lift to an SVG region on hover.
            if let ec = el as? ECElement {
                ec.z2EmphasisLift = 0
            }

            // If self named:
            if namedItem.namedFrom == nil {
                // label should batter to be displayed based on the center of <g>
                // if it is named rather than displayed on each child.
                if LABEL_HOST_MAP.contains(svgNodeTagLower) {
                    resetLabelForRegion(mapOrGeoModel, data, el, regionName, regionModel, dataIdx, nil)
                }

                resetEventTriggerForRegion(
                    mapOrGeoModel, data, el, regionName, regionModel, dataIdx
                )

                resetTooltipForRegion(
                    mapOrGeoModel, data, el, regionName, regionModel
                )

                if STATE_TRIGGER_TAG_MAP.contains(svgNodeTagLower) {
                    let focus = resetStateTriggerForRegion(mapOrGeoModel, el, regionName, regionModel)
                    if let focusStr = focus as? String, focusStr == "self" {
                        focusSelf = true
                    }
                    var els = svgDispatcherMap.get(regionName) ?? svgDispatcherMap.set(regionName, [])
                    els.append(el)
                    svgDispatcherMap.set(regionName, els)
                }
            }
        }

        self._enableBlurEntireSVG(focusSelf, mapOrGeoModel)
    }

    // upstream: private _enableBlurEntireSVG(focusSelf: boolean, mapOrGeoModel: MapOrGeoModel): void
    private func _enableBlurEntireSVG(
        _ focusSelf: Bool,
        _ mapOrGeoModel: MapOrGeoModel
    ) {
        // It's a little complicated to support blurring the entire geoSVG in series-map.
        // So do not support it until some requirements come.
        // At present, in series-map, only regions can be blurred.
        if focusSelf && isGeoModel(mapOrGeoModel) {
            let blurStyle = mapOrGeoModel.getModel(["blur", "itemStyle"]).getItemStyle()
            // Only support `opacity` here. Because not sure that other props are suitable for
            // all of the elements generated by SVG (especially for Text/TSpan/Image/... ).
            let opacity = blurStyle["opacity"]
            _ = self._svgGraphicRecord?.root.traverse { el in
                if !el.isGroup, let disp = el as? Displayable {
                    // PENDING: clear those settings to SVG elements when `_freeSVG`.
                    // (Currently it happen not to be needed.)
                    states.setDefaultStateProxy(disp)
                    // PORT-NOTE: upstream `const style = el.ensureState('blur').style || {}` mutates a
                    //   THROWAWAY `{}` when the state has no style bag and never assigns it back — see
                    //   its own comment below. So only write back when a bag already exists; otherwise
                    //   elements that never went through `applyOptionStyleForRegion` (text/tspan/image)
                    //   would wrongly pick up the geo blur opacity.
                    let blurState = disp.ensureState("blur")
                    if var style = blurState.style {
                        // Do not overwrite the region style that already set from region option.
                        if style["opacity"] == nil, let opacity = opacity, !(opacity is NSNull) {
                            style["opacity"] = opacity
                        }
                        blurState.style = style
                    }
                    // If `ensureState('blur').style = {}`, there will be default opacity.

                    // Enable `stateTransition` (animation).
                    _ = disp.ensureState("emphasis")
                }
                return false
            }
        }
    }

    // upstream: remove(): void
    public func remove() {
        _ = self._regionsGroup.removeAll()
        self._regionsGroupByName = nil
        _ = self._svgGroup.removeAll()
        self._freeSVG()
        self._controller?.disable()
    }

    // upstream: findHighDownDispatchers(name: string, geoModel: GeoModel): Element[]
    public func findHighDownDispatchers(_ name: String?, _ geoModel: GeoModel) -> [Element]? {
        guard let name = name else {
            return []
        }

        guard let geo = geoModel.coordinateSystem as? Geo else {
            return nil
        }

        if geo.resourceType == "geoJSON" {
            if let regionsGroupByName = self._regionsGroupByName {
                let regionGroup = regionsGroupByName.get(name)
                return regionGroup != nil ? [regionGroup!] : []
            }
        }
        else if geo.resourceType == "geoSVG" {
            // upstream: return this._svgDispatcherMap && this._svgDispatcherMap.get(name) || [];
            guard let svgDispatcherMap = self._svgDispatcherMap else { return [] }
            return svgDispatcherMap.get(name) ?? []
        }
        // upstream: implicit `return undefined` for an un-built / other resource type.
        return nil
    }

    // upstream: private _svgResourceChanged(mapName: string): boolean
    private func _svgResourceChanged(_ mapName: String) -> Bool {
        return self._svgMapName != mapName
    }

    // upstream: private _useSVG(mapName: string): void
    private func _useSVG(_ mapName: String) {
        let resource = geoSourceManager.getGeoResource(mapName)
        if let resource = resource, resource.type == "geoSVG", let svgResource = resource as? GeoSVGResource {
            let svgGraphic = svgResource.useGraphic(self.uid)
            _ = self._svgGroup.add(svgGraphic.root)
            self._svgGraphicRecord = svgGraphic
            self._svgMapName = mapName
        }
    }

    // upstream: private _freeSVG(): void
    private func _freeSVG() {
        guard let mapName = self._svgMapName else {
            return
        }

        let resource = geoSourceManager.getGeoResource(mapName)
        if let resource = resource, resource.type == "geoSVG", let svgResource = resource as? GeoSVGResource {
            svgResource.freeGraphic(self.uid)
        }
        self._svgGraphicRecord = nil
        self._svgDispatcherMap = nil
        _ = self._svgGroup.removeAll()
        self._svgMapName = nil
    }

    /**
     * FIXME: this is a temporarily workaround.
     * When `geoRoam` the elements need to be reset in `MapView['render']`, because the props like
     * `ignore` might have been modified by `LabelManager`, and `LabelManager#addLabelsOfSeries`
     * will subsequently cache `defaultAttr` like `ignore`. If do not do this reset, the modified
     * props will have no chance to be restored.
     * Note: This reset should be after `clearStates` in `renderSeries` because `useStates` in
     * `renderSeries` will cache the modified `ignore` to `el._normalState`.
     * TODO:
     * Use clone/immutable in `LabelManager`?
     */
    // upstream: resetForLabelLayout()
    public func resetForLabelLayout() {
        _ = self.group.traverse { el in
            if let label = el.getTextContent() {
                label.ignore = mapLabelRaw(label).ignore
            }
            return false
        }
    }

    // upstream: private _updateMapSelectHandler(mapOrGeoModel, regionsGroup, api, fromView): void
    private func _updateMapSelectHandler(
        _ mapOrGeoModel: MapOrGeoModel,
        _ regionsGroup: RegionsGroup,
        _ api: ExtensionAPI,
        _ fromView: AnyObject?
    ) {
        _ = regionsGroup.off("mousedown")
        _ = regionsGroup.off("click")

        if jsTruthy(mapOrGeoModel.get("selectedMode")) {

            // PORT-NOTE (§12 / repo convention): `regionsGroup` is a strong descendant of `self.group`,
            //   which `self` owns, so a strong capture here closes a retain cycle that leaks the whole
            //   region scene subtree per chart/setOption. Capture weakly (as RoamController/LineDraw do).
            _ = regionsGroup.on("mousedown", { [weak self] _, _ in
                self?._mouseDownFlag = true
                return nil
            })

            _ = regionsGroup.on("click", { [weak self] _, _ in
                guard let self = self, self._mouseDownFlag else {
                    return nil
                }
                self._mouseDownFlag = false
                return nil
            })
        }
    }
}

// export default MapDraw;  → `public final class MapDraw` above.

// upstream: the inline `{ dataIdx, regionModel }` record stored in `regionsInfoByName`.
//   Named here because Swift generics need a concrete type for the HashMap value.
private final class RegionInfo {
    var dataIdx: Int?
    var regionModel: RegionModel?
    init(dataIdx: Int?, regionModel: RegionModel?) {
        self.dataIdx = dataIdx
        self.regionModel = regionModel
    }
}

// upstream: function applyOptionStyleForRegion(api, data, isVisualEncodedByVisualMap, el, dataIndex, regionModel)
private func applyOptionStyleForRegion(
    _ api: ExtensionAPI,
    _ data: SeriesData?,
    _ isVisualEncodedByVisualMap: Bool,
    _ el: Displayable,
    _ dataIndex: Int?,
    _ regionModel: Model?
) {
    // All of the path are using `itemStyle`, because
    // (1) Some SVG also use fill on polyline (The different between
    // polyline and polygon is "open" or "close" but not fill or not).
    // (2) For the common props like opacity, if some use itemStyle
    // and some use `lineStyle`, it might confuse users.
    // (3) Most SVG use <path>, where can not detect whether to draw a "line"
    // or a filled shape, so use `itemStyle` for <path>.
    // PORT-NOTE: upstream's `regionModel` is never null, so the styles are read unconditionally. Here a
    //   region with no data item / no geo region option yields a nil model — fall back to empty style
    //   bags rather than returning early, so the state machinery (ensureState + setDefaultStateProxy)
    //   below is still installed and hover/select/blur stay alive on such an element.
    let normalStyleModel = regionModel?.getModel("itemStyle")
    let emphasisStyleModel = regionModel?.getModel(["emphasis", "itemStyle"])
    let blurStyleModel = regionModel?.getModel(["blur", "itemStyle"])
    let selectStyleModel = regionModel?.getModel(["select", "itemStyle"])

    // NOTE: DON'T use 'style' in visual when drawing map.
    // This component is used for drawing underlying map for both geo component and map series.
    var normalStyle = normalStyleModel.map { getFixedItemStyle($0) } ?? [:]
    let emphasisStyle = emphasisStyleModel.map { getFixedItemStyle($0) } ?? [:]
    let selectStyle = selectStyleModel.map { getFixedItemStyle($0) } ?? [:]
    let blurStyle = blurStyleModel.map { getFixedItemStyle($0) } ?? [:]

    // Update the itemStyle if has data visual
    // PORT-NOTE: no `dataIndex >= 0` guard — upstream has none, and `getItemVisual(-1, ...)` falls
    //   through to the SERIES-level visual (SeriesData.swift:1128 is index-safe), which is how a region
    //   with no matching data item still gets the series style/decal under visualMap encoding.
    if let data = data, let dataIndex = dataIndex {
        // Only visual color of each item will be used. It can be encoded by visualMap
        // But visual color of series is used in symbol drawing

        // Visual color for each series is for the symbol draw
        let style = data.getItemVisual(dataIndex, "style") as? [String: Any]
        let decal = data.getItemVisual(dataIndex, "decal")
        if isVisualEncodedByVisualMap, let fill = style?["fill"], !(fill is NSNull) {
            normalStyle["fill"] = fill
        }
        if let decal = decal, !(decal is NSNull) {
            normalStyle["decal"] = createOrUpdatePatternFromDecal(decal, api)
        }
    }

    // SVG text, tspan and image can be named but not supporeted
    // to be styled by region option yet.
    // upstream: el.setStyle(normalStyle); el.style.strokeNoScale = true;
    //   PORT-NOTE: `Displayable.setStyle` takes the typed `CommonStyleProps` and `strokeNoScale` lives on
    //   `PathStyleProps`, so the dynamic itemStyle bag is MERGED into the element's existing path style
    //   (upstream `setStyle` is a merge — a geoSVG shape must keep its authored `fill` when the region
    //   option sets no color). Non-`Path` displayables (SVG <text>/<image>) keep their style untouched,
    //   matching the "not supported to be styled by region option yet" note above.
    mapDrawSetStyleForRegion(el, normalStyle)

    el.ensureState("emphasis").style = emphasisStyle
    el.ensureState("select").style = selectStyle
    el.ensureState("blur").style = blurStyle

    // Enable blur
    states.setDefaultStateProxy(el)
}

// upstream: function resetLabelForRegion(mapOrGeoModel, data, el, regionName, regionModel, dataIdx, labelXY)
private func resetLabelForRegion(
    _ mapOrGeoModel: MapOrGeoModel,
    _ data: SeriesData?,
    _ el: Element,
    _ regionName: String,
    _ regionModel: RegionModel?,
    // Exist only if `viewBuildCtx.data` exists.
    _ dataIdx: Int?,
    // If labelXY not provided, use `textConfig.position: 'inside'`
    _ labelXY: [Double]?
) {
    guard let regionModel = regionModel else { return }

    // upstream: const isDataNaN = data && isNaN(data.get(data.mapDimension('value'), dataIdx) as number);
    //   PORT-NOTE: the value read goes through `mapDrawToNumber` (MEMORY: Int-vs-Double option/store trap —
    //   `as? Double` returns nil for an Int/NSNumber-boxed store value, which would make EVERY region
    //   report NaN and draw a label). A missing `value` dimension is `isNaN(undefined)` upstream → true.
    var isDataNaN = false
    if let data = data, let dataIdx = dataIdx {
        if let valueDim = data.mapDimension("value") {
            let v = data.get(valueDim, dataIdx)
            isDataNaN = (mapDrawToNumber(v) ?? Double.nan).isNaN
        }
        else {
            isDataNaN = true
        }
    }
    // upstream: const itemLayout = data && data.getItemLayout(dataIdx);
    var showLabelFromLayout = false
    if let data = data, let dataIdx = dataIdx,
       let itemLayout = data.getItemLayout(dataIdx) as? [String: Any] {
        showLabelFromLayout = jsTruthy(itemLayout["showLabel"])
    }

    // In the following cases label will be drawn
    // 1. In map series and data value is NaN
    // 2. In geo component
    // 3. Region has no series legendIcon, which will be add a showLabel flag in mapSymbolLayout
    if (isGeoModel(mapOrGeoModel) || isDataNaN) || showLabelFromLayout {

        // upstream: const query = !isGeoModel(mapOrGeoModel) ? dataIdx : regionName;
        //   PORT-TODO (behavioural gap): `SetLabelStyleOpt.labelDataIndex` is a `Double?` (the numeric-index
        //   form only), so a NAME-keyed geo query is not representable. For the geo component the formatted
        //   region label is resolved eagerly here for the NORMAL state only and passed as `defaultText`
        //   (same deviation as GeoView's inlined subset), so a per-state `formatter` under
        //   `emphasis` / `select` / `blur` is silently ignored on geo-component regions. Fix by widening
        //   `SetLabelStyleOpt` with a name-keyed `labelQuery`, or by resolving all four states eagerly
        //   (`getFormattedLabel(regionName, state)`) into per-state `specifiedTextOpt` entries.
        //   The map-series branch keeps the faithful `labelFetcher` + numeric `labelDataIndex`.
        var opt = SetLabelStyleOpt()
        opt.defaultText = regionName

        // Consider dataIdx not found.
        if data == nil || (dataIdx ?? -1) >= 0 {
            if isGeoModel(mapOrGeoModel) {
                if let geoModel = mapOrGeoModel as? GeoModel,
                   let formatted = geoModel.getFormattedLabel(regionName, "normal") {
                    opt.defaultText = formatted
                }
            }
            else {
                opt.labelFetcher = mapOrGeoModel as? DataFormatMixin
                if let dataIdx = dataIdx {
                    opt.labelDataIndex = Double(dataIdx)
                }
            }
        }

        // upstream: const specifiedTextOpt = labelXY ? { normal: { align: 'center', verticalAlign: 'middle' } } : null;
        var specifiedTextOpt: [DisplayState: TextStyleProps]?
        if labelXY != nil {
            var normal = TextStyleProps()
            normal.align = .center
            normal.verticalAlign = .middle
            specifiedTextOpt = [.normal: normal]
        }

        // Caveat: must be called after `setDefaultStateProxy(el);` called.
        // because textContent will be assign with `el.stateProxy` inside.
        labelStyle.setLabelStyle(
            el,
            labelStyle.getLabelStatesModels(regionModel),
            opt,
            specifiedTextOpt
        )

        let textEl = el.getTextContent()
        if let textEl = textEl {
            mapLabelRaw(textEl).ignore = textEl.ignore

            // upstream: `el.getBoundingRect()` is non-null; the Swift accessor is Optional, so the
            //   block is skipped (rather than force-unwrapped) when it has no rect (PORTING §12).
            if el.textConfig != nil, let labelXY = labelXY, labelXY.count >= 2,
               let rect = el.getBoundingRect()?.clone() {
                // Compute a relative offset based on the el bounding rect.
                // Need to make sure the percent position base on the same rect in normal and
                // emphasis state. Otherwise if using boundingRect of el, but the emphasis state
                // has borderWidth (even 0.5px), the text position will be changed obviously
                // if the position is very big like ['1234%', '1345%'].
                el.textConfig!.layoutRect = rect
                el.textConfig!.position = [
                    "\((labelXY[0] - rect.x) / rect.width * 100)%",
                    "\((labelXY[1] - rect.y) / rect.height * 100)%"
                ]
            }
        }

        // PENDING:
        // If labelLayout is enabled (test/label-layout.html), el.dataIndex should be specified.
        // But el.dataIndex is also used to determine whether user event should be triggered,
        // where el.seriesIndex or el.dataModel must be specified. At present for a single el
        // there is not case that "only label layout enabled but user event disabled", so here
        // we depends `resetEventTriggerForRegion` to do the job of setting `el.dataIndex`.

        // upstream: (el as ECElement).disableLabelAnimation = true;
        innerStore.getECElementProps(el).disableLabelAnimation = true
    }
    else {
        el.removeTextContent()
        el.removeTextConfig()
        innerStore.getECElementProps(el).disableLabelAnimation = nil
    }
}

// upstream: function resetEventTriggerForRegion(mapOrGeoModel, data, eventTrigger, regionName, regionModel, dataIdx)
private func resetEventTriggerForRegion(
    _ mapOrGeoModel: MapOrGeoModel,
    _ data: SeriesData?,
    _ eventTrigger: Element,
    _ regionName: String,
    _ regionModel: RegionModel?,
    // Exist only if `viewBuildCtx.data` exists.
    _ dataIdx: Int?
) {
    // setItemGraphicEl, setHoverStyle after all polygons and labels
    // are added to the regionGroup
    if let data = data {
        // FIXME: when series-map use a SVG map, and there are duplicated name specified
        // on different SVG elements, after `data.setItemGraphicEl(...)`:
        // (1) all of them will be mounted with `dataIndex`, `seriesIndex`, so that tooltip
        // can be triggered only mouse hover. That's correct.
        // (2) only the last element will be kept in `data`, so that if trigger tooltip
        // by `dispatchAction`, only the last one can be found and triggered. That might be
        // not correct. We will fix it in future if anyone demanding that.
        // PORT-NOTE: `indexOfName` returns -1 for a region with no matching data item (the normal case
        //   for a map series over a full GeoJSON). Upstream's `this._graphicEls[-1] = el` is harmless JS;
        //   the Swift `sparseSet` would trap on `arr[-1] = el`, so skip the stamp. `dataIndex: -1` means
        //   "no data item" and the stamp is only consumed by tooltip/highlight index lookups.
        if let dataIdx = dataIdx, dataIdx >= 0 {
            data.setItemGraphicEl(dataIdx, eventTrigger)
        }
    }
    // series-map will not trigger "geoselectchange" no matter it is
    // based on a declared geo component. Because series-map will
    // trigger "selectchange". If it trigger both the two events,
    // If users call `chart.dispatchAction({type: 'toggleSelect'})`,
    // it not easy to also fire event "geoselectchanged".
    else {
        // Package custom mouse event for geo component
        var eventData: ECEventData = [:]
        eventData["componentType"] = "geo"
        eventData["componentIndex"] = mapOrGeoModel.componentIndex
        eventData["geoIndex"] = mapOrGeoModel.componentIndex
        eventData["name"] = regionName
        // upstream: (regionModel && regionModel.option) || {}
        eventData["region"] = regionModel?.option ?? [:]
        innerStore.getECData(eventTrigger).eventData = eventData
    }
}

// upstream: function resetTooltipForRegion(mapOrGeoModel, data, el, regionName, regionModel)
private func resetTooltipForRegion(
    _ mapOrGeoModel: MapOrGeoModel,
    _ data: SeriesData?,
    _ el: Element,
    _ regionName: String,
    _ regionModel: RegionModel?
) {
    if data == nil {
        setTooltipConfig(
            el: el,
            componentModel: mapOrGeoModel,
            itemName: regionName,
            itemTooltipOption: regionModel?.get("tooltip")
        )
    }
}

// upstream: function resetStateTriggerForRegion(mapOrGeoModel, el, regionName, regionModel): InnerFocus
@discardableResult
private func resetStateTriggerForRegion(
    _ mapOrGeoModel: MapOrGeoModel,
    _ el: Element,
    _ regionName: String,
    _ regionModel: RegionModel?
) -> InnerFocus? {
    // upstream: el.highDownSilentOnTouch = !!mapOrGeoModel.get('selectedMode');
    //   (see the ECElement PORT-TODO in `_buildSVG` — no scene-graph class conforms yet.)
    if let ec = el as? ECElement {
        ec.highDownSilentOnTouch = jsTruthy(mapOrGeoModel.get("selectedMode"))
    }
    guard let regionModel = regionModel else { return nil }
    let emphasisModel = regionModel.getModel("emphasis")
    let focus: InnerFocus? = emphasisModel.get("focus")
    let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
    // upstream `emphasisModel.get('disabled')` is used as a JS boolean — route through `jsTruthy` so an
    //   Int-boxed `1`/`0` in the option bag is not silently read as `false` (MEMORY: boxed-option trap).
    let isDisabled = jsTruthy(emphasisModel.get("disabled"))
    states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
    if isGeoModel(mapOrGeoModel), let geoModel = mapOrGeoModel as? GeoModel {
        states.enableComponentHighDownFeatures(el, geoModel, regionName)
    }

    return focus
}

// upstream: function projectPolys(rings, createStream, isLine?)
//   PORT-TODO (dormant): reachable only once `GeoProjection.stream` lands (see the `projectionStream`
//   PORT-TODO in `_buildGeoJSON`). Ported now so the stream path is a one-line wiring when it does.
private func projectPolys(
    _ rings: [[[Double]]],   // Polygons include exterior and interiors. Or polylines.
    _ createStream: (ProjectionStream) -> ProjectionStream,
    _ isLine: Bool = false
) -> [[[Double]]] {
    let collector = PolyCollector()
    let stream = createStream(collector)
    if !isLine { stream.polygonStart() }
    for ring in rings {
        stream.lineStart()
        for i in 0..<ring.count {
            stream.point(ring[i][0], ring[i][1])
        }
        stream.lineEnd()
    }
    if !isLine { stream.polygonEnd() }
    return collector.polygons
}

// upstream: the inline `{ polygonStart, polygonEnd, lineStart, lineEnd, point, sphere }` object literal
//   passed to `createStream`. `ProjectionStream` is a protocol here, so it needs a named conformer.
private final class PolyCollector: ProjectionStream {
    var polygons: [[[Double]]] = []
    private var curPoly: [[Double]] = []

    // upstream: function startPolygon() { curPoly = []; }
    func polygonStart() { self.curPoly = [] }
    func lineStart() { self.curPoly = [] }
    // upstream: function endPolygon() { if (curPoly.length) { polygons.push(curPoly); curPoly = []; } }
    func polygonEnd() {
        if !self.curPoly.isEmpty {
            self.polygons.append(self.curPoly)
            self.curPoly = []
        }
    }
    func lineEnd() { self.polygonEnd() }
    func point(_ x: Double, _ y: Double) {
        // May have NaN values from stream.
        if x.isFinite && y.isFinite {
            self.curPoly.append([x, y])
        }
    }
    func sphere() {}
}

// upstream: function isGeoModel(mapOrGeoModel): mapOrGeoModel is GeoModel { return mapOrGeoModel.mainType === 'geo'; }
private func isGeoModel(_ mapOrGeoModel: MapOrGeoModel) -> Bool {
    return mapOrGeoModel.mainType == "geo"
}

// upstream: `mapOrGeoModel.getRegionModel(regionName)` — the union `GeoModel | MapSeries` both declare it,
//   but `MapOrGeoModel` is the erased `ComponentModel` in this port (geoCreator.swift), so dispatch here.
private func getRegionModel(_ mapOrGeoModel: MapOrGeoModel, _ regionName: String) -> RegionModel? {
    if let geoModel = mapOrGeoModel as? GeoModel {
        return geoModel.getRegionModel(regionName)
    }
    if let mapSeries = mapOrGeoModel as? MapSeriesModel {
        return mapSeries.getRegionModel(regionName)
    }
    return nil
}


// ============================================================================
// PORT-NOTE helpers — NOT part of MapDraw.ts upstream. They bridge the dynamic
// `[String: Any]` itemStyle bag (`Model.getItemStyle()`) onto the typed
// `PathStyleProps`, reproducing upstream's duck-typed `el.setStyle(styleBag)`
// MERGE. Mirrors the (private) `mapPathStyleFromDict` in MapView.swift —
// delete both when the `util/graphic` `useStyle` dict bridge lands.
// ============================================================================

/// upstream `el.setStyle(normalStyle); el.style.strokeNoScale = true;` for a region element.
private func mapDrawSetStyleForRegion(_ el: Displayable, _ dict: [String: Any]) {
    guard let path = el as? Path else {
        // SVG <text>/<tspan>/<image>: "not supported to be styled by region option yet" (upstream note).
        return
    }
    var s = path.pathStyle ?? PathStyleProps()
    if let v = zrPaintFromStyleValue(dict["fill"]) { s.fill = v }
    if let v = zrPaintFromStyleValue(dict["stroke"]) { s.stroke = v }
    if let v = mapDrawToNumber(dict["lineWidth"]) { s.lineWidth = v }
    if let v = dict["lineCap"] as? String { s.lineCap = v }
    if let v = dict["lineJoin"] as? String { s.lineJoin = v }
    if let v = mapDrawToNumber(dict["miterLimit"]) { s.miterLimit = v }
    if let v = mapDrawToNumber(dict["opacity"]) { s.opacity = v }
    if let v = mapDrawToNumber(dict["fillOpacity"]) { s.fillOpacity = v }
    if let v = mapDrawToNumber(dict["strokeOpacity"]) { s.strokeOpacity = v }
    if let v = mapDrawToNumber(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = mapDrawToNumber(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = mapDrawToNumber(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = mapDrawToNumber(dict["lineDashOffset"]) { s.lineDashOffset = v }
    if let pat = dict["decal"] as? ZRenderKit.Pattern { s.decal = pat }
    if let dash = dict["lineDash"] as? [Double] { s.lineDash = .values(dash) }
    else if let dashi = dict["lineDash"] as? [Int] { s.lineDash = .values(dashi.map { Double($0) }) }
    else if let b = dict["lineDash"] as? Bool, b == false { s.lineDash = .`false` }
    // upstream: el.style.strokeNoScale = true;
    s.strokeNoScale = true
    path.useStyle(s)
}

/// Coerce a dynamic option value to Double, tolerating Int boxing (MEMORY: Int-vs-Double option-read trap).
private func mapDrawToNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)`) — CONVENTIONS §6.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}
