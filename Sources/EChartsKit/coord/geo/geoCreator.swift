// Ported from echarts/src/coord/geo/geoCreator.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` (ZRenderKit) / `createHashMap` (shim).
//   import Geo, { geo2DDimensions } from './Geo';                  -> Geo + geo2DDimensions (sibling, Geo.swift).
//   import * as layout from '../../util/layout';                   -> `layout.*` (util/layout.swift).
//   import * as numberUtil from '../../util/number';               -> `number.*` (util/number.swift).
//   import geoSourceManager from './geoSourceManager';             -> `geoSourceManager.*` (geoSourceManager.swift).
//   import GeoModel, { GeoCommonOptionMixin, GeoOption, RegionOption } from './GeoModel';
//       -> GeoModel + RegionOption (sibling, GeoModel.swift). `GeoCommonOptionMixin`/`GeoOption` are
//          type-only; dynamic option reads go through `model.get(...)`.
//   import MapSeries, { buildAllMapSeriesGroups, mapSeriesGroupHasOwnGeo, MapSeriesOption, SERIES_TYPE_MAP }
//       from '../../chart/map/MapSeries';                          -> MapSeries + helpers (NOT yet ported; see PORT-TODOs).
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { CoordinateSystemCreator } from '../CoordinateSystem'; -> CoordinateSystemCreator (coord/CoordinateSystem.swift).
//   import { NameMap } from './geoTypes';                          -> NameMap (geoTypes.swift; = [String: String]).
//   import type Model / GlobalModel / ComponentModel;             -> Model / GlobalModel / ComponentModel.
//   import * as vector from 'zrender/src/core/vector';             -> `vector.*` (ZRenderKit).
//   import { injectCoordSysByOption } from '../../core/CoordinateSystem';
//       -> `injectCoordSysByOption` + `InjectCoordSysByOptionOpt` (core/CoordinateSystemManager.swift).
//   import { SINGLE_REFERRING } from '../../util/model';           -> `model.SINGLE_REFERRING` (util/modelUtil.swift).
//   import type { GeoJSONRegion } from './Region';                -> GeoJSONRegion (sibling, Region.swift).
//   import { RoamOptionMixin } from '../../util/types';            -> type-only; roam is DEFERRED.
//   import { viewCoordSysSetBoundingRect, viewCoordSysSetRoamOptionFromModel, viewCoordSysSetViewRect }
//       from '../View';                                            -> View helpers (coord/View.swift).

// export type resizeGeoType = typeof resizeGeo;
// export type MapOrGeoModel = (GeoModel | MapSeries) & ComponentModel<GeoOption | MapSeriesOption>;
// PORT-TODO: `MapOrGeoModel` is the union `GeoModel | MapSeries` (both are ComponentModel). Modeled as
//   the common base `ComponentModel` (matches Geo's `resize` closure param type); dynamic option reads
//   go through `.get(...)`.
public typealias MapOrGeoModel = ComponentModel

/**
 * Resize method bound to the geo
 */
// upstream: function resizeGeo(this: Geo, geoModel: MapOrGeoModel, api: ExtensionAPI): void
//   `this` is the Geo the method is injected onto (see `geo.resize = resizeGeo` in `create`); ported as
//   an explicit leading `geo` parameter — Geo's `resize` is a stored closure `(Geo, ComponentModel,
//   ExtensionAPI) -> Void` (see Geo.swift), so call sites pass `geo` as the first argument.
func resizeGeo(_ geo: Geo, _ geoModel: MapOrGeoModel, _ api: ExtensionAPI) {

    // const viewCoordSys = this.view;
    let viewCoordSys = geo.view!
    // const boundingCoords = geoModel.get('boundingCoords');
    let boundingCoords = asCoordPairs(geoModel.get("boundingCoords"))
    // if (boundingCoords != null) { ... }
    if boundingCoords != nil {
        // let leftTop = boundingCoords[0];  let rightBottom = boundingCoords[1];
        //   A short inner array yields NaN (like JS `undefined`), which the isFinite check below skips —
        //   avoids a Swift index trap on malformed boundingCoords.
        let ltRaw = boundingCoords![0], rbRaw = boundingCoords![1]
        var leftTop = VectorArray(ltRaw.count > 0 ? ltRaw[0] : .nan, ltRaw.count > 1 ? ltRaw[1] : .nan)
        var rightBottom = VectorArray(rbRaw.count > 0 ? rbRaw[0] : .nan, rbRaw.count > 1 ? rbRaw[1] : .nan)
        // if (!(isFinite(leftTop[0]) && isFinite(leftTop[1])
        //     && isFinite(rightBottom[0]) && isFinite(rightBottom[1]))) { console.error(...); }
        if !(
            leftTop[0].isFinite && leftTop[1].isFinite
            && rightBottom[0].isFinite && rightBottom[1].isFinite
        ) {
            if __DEV__ {
                log.error("Invalid boundingCoords")
            }
        }
        else {
            // Sample around the lng/lat rect and use projection to calculate actual bounding rect.
            // const projection = this.projection;
            let projection = geo.projection
            if let projection = projection { // if (projection)
                // const xMin = leftTop[0]; const yMin = leftTop[1];
                let xMin = leftTop[0]
                let yMin = leftTop[1]
                // const xMax = rightBottom[0]; const yMax = rightBottom[1];
                let xMax = rightBottom[0]
                let yMax = rightBottom[1]
                // leftTop = [Infinity, Infinity]; rightBottom = [-Infinity, -Infinity];
                leftTop = VectorArray(Double.infinity, Double.infinity)
                rightBottom = VectorArray(-Double.infinity, -Double.infinity)

                // TODO better way?
                // const sampleLine = (x0, y0, x1, y1) => { ... };
                let sampleLine = { (x0: Double, y0: Double, x1: Double, y1: Double) in
                    // const dx = x1 - x0; const dy = y1 - y0;
                    let dx = x1 - x0
                    let dy = y1 - y0
                    // for (let i = 0; i <= 100; i++) { ... }
                    for i in 0...100 {
                        // const p = i / 100;
                        let p = Double(i) / 100
                        // const pt = projection.project([x0 + dx * p, y0 + dy * p]);
                        //   (GeoProjection.project returns an Optional; skip degenerate points.)
                        if let pt = projection.project([x0 + dx * p, y0 + dy * p]) {
                            // vector.min(leftTop, leftTop, pt);  -> value-returning per CONVENTIONS §3
                            leftTop = vector.min(leftTop, VectorArray(pt[0], pt[1]))
                            // vector.max(rightBottom, rightBottom, pt);
                            rightBottom = vector.max(rightBottom, VectorArray(pt[0], pt[1]))
                        }
                    }
                }
                // Top
                sampleLine(xMin, yMin, xMax, yMin)
                // Right
                sampleLine(xMax, yMin, xMax, yMax)
                // Bottom
                sampleLine(xMax, yMax, xMin, yMax)
                // Left
                sampleLine(xMin, yMax, xMax, yMin)
            }

            // viewCoordSysSetBoundingRect(viewCoordSys, leftTop[0], leftTop[1],
            //     rightBottom[0] - leftTop[0], rightBottom[1] - leftTop[1]);
            viewCoordSysSetBoundingRect(
                viewCoordSys,
                leftTop[0],
                leftTop[1],
                rightBottom[0] - leftTop[0],
                rightBottom[1] - leftTop[1]
            )
        }
    }

    // const rect = viewCoordSys.getBoundingRect();
    let rect = viewCoordSys.getBoundingRect()

    // const centerOption = geoModel.get('layoutCenter');
    let centerOption = geoModel.get("layoutCenter") as? [Any]
    // const sizeOption = geoModel.get('layoutSize');
    let sizeOption = geoModel.get("layoutSize")

    // Laying out geo on Cartesian works theoretically but not supported yet.
    // Currently, we only support to lay out on matrix/calendar.
    // const {refContainer} = layout.createBoxLayoutReference(geoModel, api);
    let refContainer = layout.createBoxLayoutReference(geoModel, api).refContainer

    // const aspect = rect.width / rect.height * this.aspectScale;
    let aspect = rect.width / rect.height * geo.aspectScale

    // let useCenterAndSize = false;
    var useCenterAndSize = false
    // let center: number[]; let size: number;
    var center: [Double] = []
    var size: Double = 0

    // if (centerOption && sizeOption) { ... }
    //   JS `&&`: a falsy layoutSize (nil / 0 / "") means "absent" → fall through to left/top/width/height
    //   layout (not a size-0 viewRect). `??`/`!= nil` would wrongly treat a boxed 0 as present.
    if let centerOption = centerOption, geoOptTruthy(sizeOption) {
        // center = [parsePercent(centerOption[0], refContainer.width) + refContainer.x,
        //           parsePercent(centerOption[1], refContainer.height) + refContainer.y];
        center = [
            number.parsePercent(centerOption.count > 0 ? centerOption[0] : nil, refContainer.width) + refContainer.x,
            number.parsePercent(centerOption.count > 1 ? centerOption[1] : nil, refContainer.height) + refContainer.y
        ]
        // size = parsePercent(sizeOption, Math.min(refContainer.width, refContainer.height));
        size = number.parsePercent(sizeOption, Swift.min(refContainer.width, refContainer.height))

        // if (!isNaN(center[0]) && !isNaN(center[1]) && !isNaN(size)) { useCenterAndSize = true; }
        if !center[0].isNaN && !center[1].isNaN && !size.isNaN {
            useCenterAndSize = true
        }
        else {
            if __DEV__ {
                log.warn("Given layoutCenter or layoutSize data are invalid. Use left/top/width/height instead.")
            }
        }
    }

    // let viewRect: layout.LayoutRect;
    let viewRect: LayoutRect
    // if (useCenterAndSize) { ... }
    if useCenterAndSize {
        // viewRect = {} as layout.LayoutRect;   (LayoutRect === BoundingRect)
        viewRect = BoundingRect(0, 0, 0, 0)
        // if (aspect > 1) { viewRect.width = size; viewRect.height = size / aspect; }
        // else { viewRect.height = size; viewRect.width = size * aspect; }
        if aspect > 1 {
            // Width is same with size
            viewRect.width = size
            viewRect.height = size / aspect
        }
        else {
            viewRect.height = size
            viewRect.width = size * aspect
        }
        // viewRect.y = center[1] - viewRect.height / 2;
        viewRect.y = center[1] - viewRect.height / 2
        // viewRect.x = center[0] - viewRect.width / 2;
        viewRect.x = center[0] - viewRect.width / 2
    }
    else {
        // Use left/top/width/height
        // const boxLayoutOption = geoModel.getBoxLayoutParams() as Parameters<typeof layout.getLayoutRect>[0];
        // boxLayoutOption.aspect = aspect;
        // PORT-TODO: `aspect` is not a field of `BoxLayoutOptionMixin`; upstream augments the cast bag.
        //   Rebuilt as a `[String: Any]` bag (+ aspect) so `layout.getLayoutRect`'s dynamic overload
        //   reads it, preserving upstream behavior.
        let box = geoModel.getBoxLayoutParams()
        var boxLayoutOption: [String: Any] = [:]
        if let v = box.left { boxLayoutOption["left"] = v }
        if let v = box.top { boxLayoutOption["top"] = v }
        if let v = box.right { boxLayoutOption["right"] = v }
        if let v = box.bottom { boxLayoutOption["bottom"] = v }
        if let v = box.width { boxLayoutOption["width"] = v }
        if let v = box.height { boxLayoutOption["height"] = v }
        boxLayoutOption["aspect"] = aspect

        // viewRect = layout.getLayoutRect(boxLayoutOption, refContainer);
        let viewRectVar = layout.getLayoutRect(boxLayoutOption, refContainer)
        // viewRect = layout.applyPreserveAspect(geoModel, viewRect, aspect);
        // PORT-TODO: `layout.applyPreserveAspect` is NOT yet ported (see layout.swift header). Call is
        //   kept as a reference; wire it once ported:
        //     viewRectVar = layout.applyPreserveAspect(geoModel, viewRectVar, aspect)
        viewRect = viewRectVar
    }

    // viewCoordSysSetViewRect(viewCoordSys, viewRect.x, viewRect.y, viewRect.width, viewRect.height);
    viewCoordSysSetViewRect(viewCoordSys, viewRect.x, viewRect.y, viewRect.width, viewRect.height)
    // viewCoordSysSetRoamOptionFromModel(viewCoordSys, geoModel);
    // PORT-TODO: roam (pan/zoom) is DEFERRED and `viewCoordSysSetRoamOptionFromModel` (coord/View.ts) is
    //   NOT yet ported in View.swift. Wire it once ported:
    //     viewCoordSysSetRoamOptionFromModel(viewCoordSys, geoModel)
}

// Back compat for ECharts2, where the coord map is set on map series:
// {type: 'map', geoCoord: {'cityA': [116.46,39.92], 'cityA': [119.12,24.61]}},
// function setGeoCoords(geo: Geo, model: MapSeries)
// PORT-TODO: `MapSeries` (chart/map/MapSeries.ts) is NOT yet ported. `setGeoCoords` is only reachable
//   from the map-series branch in `create` (also stubbed below); wire it when MapSeries lands:
//     private func setGeoCoords(_ geo: Geo, _ model: MapSeries) {
//         // zrUtil.each(model.get('geoCoord'), (geoCoord, name) => geo.addGeoCoord(name, geoCoord));
//         if let geoCoords = model.get("geoCoord") as? [String: Any] {
//             for (name, geoCoordAny) in geoCoords {
//                 if let geoCoord = asCoordPair(geoCoordAny) { geo.addGeoCoord(name, geoCoord) }
//             }
//         }
//     }

// class GeoCreator implements CoordinateSystemCreator
public final class GeoCreator: CoordinateSystemCreator {

    // For deciding which dimensions to use when creating list data
    // dimensions = geo2DDimensions;
    public var dimensions: [DimensionName]? = geo2DDimensions

    public init() {}

    // create(ecModel: GlobalModel, api: ExtensionAPI): Geo[]
    // upstream returns `Geo[]`; the `CoordinateSystemCreator` protocol requires `[CoordinateSystemMaster]`
    //   (Geo conforms upstream), so the `[Geo]` list is upcast on return (same idiom as Grid/Polar creators).
    // PORT-TODO: `Geo` currently does NOT conform to `CoordinateSystemMaster` (dropped in Geo.swift with a
    //   PORT-TODO: "re-add protocol conformance ... when geoCreator lands"). Re-add that conformance (and the
    //   `geoModel.coordinateSystem = geo` assignment below both depend on it) for this to compile — see
    //   integrationNotes.
    public func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // const geoList = [] as Geo[];
        var geoList: [Geo] = []

        // function getCommonGeoProperties(model: Model<GeoCommonOptionMixin>) { return { nameProperty,
        //     aspectScale, projection, clip }; }
        //   Assembled directly into `GeoConstructorOption` (Geo's typed init bag) together with the
        //   per-call `nameMap` + `api`/`ecModel`, mirroring upstream `zrUtil.extend({nameMap, api, ecModel},
        //   getCommonGeoProperties(model))`.
        func buildGeoConstructorOption(_ model: ComponentModel, _ nameMap: NameMap?) -> GeoConstructorOption {
            return GeoConstructorOption(
                // projection: model.get('projection'),
                projection: model.get("projection") as? GeoProjection,
                // nameMap: geoModel.get('nameMap')  /  zrUtil.mergeAll(nameMapList)
                nameMap: nameMap,
                // nameProperty: model.get('nameProperty'),
                nameProperty: model.get("nameProperty") as? String,
                // aspectScale: model.get('aspectScale'),
                aspectScale: asNumberOpt(model.get("aspectScale")),
                api: api,
                ecModel: ecModel,
                // clip: model.getShallow('clip', true),
                clip: model.getShallow("clip", true) as? Bool
            )
        }

        // FIXME Create each time may be slow
        // ecModel.eachComponent('geo', function (geoModel: GeoModel, idx) { ... });
        ecModel.eachComponent("geo") { (geoModelComp: ComponentModel, idx: Double) in
            guard let geoModel = geoModelComp as? GeoModel else { return }
            // const mapName = geoModel.get('map');
            let mapName = (geoModel.get("map") as? String) ?? ""

            // const geo = new Geo(mapName + idx, mapName, zrUtil.extend({
            //     nameMap: geoModel.get('nameMap'), api, ecModel,
            // }, getCommonGeoProperties(geoModel)));
            let geo = Geo(
                mapName + String(Int(idx)),
                mapName,
                buildGeoConstructorOption(geoModel, geoModel.get("nameMap") as? NameMap)
            )

            // geoList.push(geo);
            geoList.append(geo)

            // setGeoCoords(geo, geoModel);   (commented out upstream)

            // geoModel.coordinateSystem = geo;
            geoModel.coordinateSystem = geo
            // geo.model = geoModel;
            geo.model = geoModel

            // Inject resize method
            // geo.resize = resizeGeo;
            geo.resize = resizeGeo

            // geo.resize(geoModel, api);   (Geo.resize is a stored closure taking `geo` first — see resizeGeo)
            geo.resize(geo, geoModel, api)
        }

        // ecModel.eachSeries(function (seriesModel) { injectCoordSysByOption({...}); });
        ecModel.eachSeries { (seriesModel: SeriesModel, _: Double) in
            _ = injectCoordSysByOption(InjectCoordSysByOptionOpt(
                targetModel: seriesModel,
                coordSysType: "geo",
                // coordSysProvider() { ... }
                coordSysProvider: { _, _ in
                    // const geoModel = seriesModel.subType === SERIES_TYPE_MAP
                    //     ? (seriesModel as MapSeries).getHostGeoModel()
                    //     : seriesModel.getReferringComponents('geo', SINGLE_REFERRING).models[0] as GeoModel;
                    // PORT-TODO: the `subType === SERIES_TYPE_MAP` branch uses `MapSeries` (not yet ported);
                    //   only the geo-referring branch (`getReferringComponents('geo', ...)`) is wired here.
                    //   Restore the map branch when MapSeries lands:
                    //     if seriesModel.subType == SERIES_TYPE_MAP {
                    //         geoModel = (seriesModel as? MapSeries)?.getHostGeoModel()
                    //     } else { ... }
                    let geoModel = seriesModel.getReferringComponents(
                        "geo", model.SINGLE_REFERRING
                    ).models.first as? GeoModel
                    // return geoModel && geoModel.coordinateSystem;
                    return geoModel?.coordinateSystem as? CoordinateSystem
                },
                allowNotFound: true
            ))
        }

        // If has map series
        // zrUtil.each(buildAllMapSeriesGroups(ecModel, true), function (mapSeriesGroup, groupKey) { ... });
        // PORT-TODO: the entire map-series-group path depends on `MapSeries` + `buildAllMapSeriesGroups`
        //   + `mapSeriesGroupHasOwnGeo` + `SERIES_TYPE_MAP` (chart/map/MapSeries.ts), which are NOT yet
        //   ported. The faithful translation is preserved below as a reference block; un-stub it when
        //   MapSeries lands. (Also relies on `setGeoCoords`, stubbed above, and `geo.resize`/GeoConstructorOption.)
        /*
        for (groupKey, mapSeriesGroup) in buildAllMapSeriesGroups(ecModel, true) {
            // NOTE: Swift Dictionary order is unspecified (upstream iterates object insertion order);
            //   the per-group work is independent so ordering does not affect the created geos.
            // if (!mapSeriesGroupHasOwnGeo(groupKey)) { return; }
            if !mapSeriesGroupHasOwnGeo(groupKey) {
                continue
            }

            // const firstDeclaredMapSeries = mapSeriesGroup.r[0];
            let firstDeclaredMapSeries = mapSeriesGroup.r[0]
            // const nameMapList: NameMap[] = [];
            var nameMapList: [NameMap] = []

            // zrUtil.each(mapSeriesGroup.r, function (mapSeries) { ... });
            util.each(mapSeriesGroup.r) { mapSeries, _ in
                // nameMapList.push(mapSeries.get('nameMap'));
                nameMapList.append((mapSeries.get("nameMap") as? NameMap) ?? [:])
                // MAP_SERIES_GROUP must not be set here, as series filtering is not performed.
                // Clear it first, including series to be filtered.
                // mapSeries.seriesGroup = null;
                mapSeries.seriesGroup = nil
            }

            // const mapType = groupKey.slice(1);
            let mapType = String(groupKey.dropFirst())
            // const geo = new Geo(mapType, mapType, zrUtil.extend({
            //     nameMap: zrUtil.mergeAll(nameMapList), api, ecModel,
            // }, getCommonGeoProperties(firstDeclaredMapSeries)));
            //   zrUtil.mergeAll(nameMapList) with overwrite=false → first-declared source wins per key.
            var mergedNameMap: NameMap = [:]
            for nm in nameMapList { for (k, v) in nm where mergedNameMap[k] == nil { mergedNameMap[k] = v } }
            let geo = Geo(mapType, mapType, buildGeoConstructorOption(firstDeclaredMapSeries, mergedNameMap))

            // let scaleLimit: RoamOptionMixin['scaleLimit'];  (roam DEFERRED; computed but not applied here)
            var scaleLimit: Any? = nil
            util.each(mapSeriesGroup.r) { mapSeries, _ in
                scaleLimit = util.retrieve2(scaleLimit, mapSeries.get("scaleLimit"))
            }
            _ = scaleLimit

            // geoList.push(geo);
            geoList.append(geo)

            // Inject resize method
            // geo.resize = resizeGeo;
            geo.resize = resizeGeo
            // geo.resize(firstDeclaredMapSeries, api);
            geo.resize(geo, firstDeclaredMapSeries, api)

            // zrUtil.each(mapSeriesGroup.r, function (mapSeries) {
            //     mapSeries.coordinateSystem = geo; setGeoCoords(geo, mapSeries);
            // });
            util.each(mapSeriesGroup.r) { mapSeries, _ in
                mapSeries.coordinateSystem = geo
                setGeoCoords(geo, mapSeries)
            }
        }
        */

        // return geoList;
        return geoList.map { $0 as CoordinateSystemMaster }
    }

    /**
     * Fill given regions array
     */
    // getFilledRegions(originRegionArr, mapName, nameMap, nameProperty): RegionOption[]
    public func getFilledRegions(
        _ originRegionArr: [RegionOption]?,
        _ mapName: String,
        _ nameMap: NameMap?,
        _ nameProperty: String?
    ) -> [RegionOption] {
        // Not use the original
        // const regionsArr = (originRegionArr || []).slice();
        var regionsArr = originRegionArr ?? []

        // const dataNameMap = zrUtil.createHashMap();
        // PORT-TODO: upstream `dataNameMap` stores the RegionOption OBJECT (JS reference) so the later
        //   `zrUtil.merge(regionOption, ...)` writes back into `regionsArr`. `RegionOption` is a Swift
        //   value dict, so we store the INDEX into `regionsArr` and mutate through it to preserve the
        //   in-place write-back semantics.
        let dataNameMap: HashMap<Int> = createHashMap()
        // for (let i = 0; i < regionsArr.length; i++) { dataNameMap.set(regionsArr[i].name, regionsArr[i]); }
        for i in 0..<regionsArr.count {
            dataNameMap.set(regionsArr[i]["name"] as? String, i)
        }

        // const source = geoSourceManager.load(mapName, nameMap, nameProperty);
        let source = geoSourceManager.load(mapName, nameMap, nameProperty)
        // zrUtil.each(source.regions, function (region) { ... });
        util.each(source.regions) { region, _ in
            // const name = region.name;
            let name = region.name
            // let regionOption = dataNameMap.get(name);
            var idx = dataNameMap.get(name)
            // apply specified echarts style in GeoJSON data
            // const specifiedGeoJSONRegionStyle = (region as GeoJSONRegion).properties
            //     && (region as GeoJSONRegion).properties.echartsStyle;
            let specifiedGeoJSONRegionStyle = (region as? GeoJSONRegion)?.properties["echartsStyle"] as? [String: Any]
            // if (!regionOption) { regionOption = { name: name }; regionsArr.push(regionOption); }
            if idx == nil {
                var regionOption: RegionOption = ["name": name]
                regionsArr.append(regionOption)
                idx = regionsArr.count - 1
                dataNameMap.set(name, idx!)
                // specifiedGeoJSONRegionStyle && zrUtil.merge(regionOption, specifiedGeoJSONRegionStyle);
                if let style = specifiedGeoJSONRegionStyle {
                    _ = util.merge(&regionOption, style)
                    regionsArr[idx!] = regionOption
                }
            }
            else {
                // specifiedGeoJSONRegionStyle && zrUtil.merge(regionOption, specifiedGeoJSONRegionStyle);
                if let style = specifiedGeoJSONRegionStyle {
                    var regionOption = regionsArr[idx!]
                    _ = util.merge(&regionOption, style)
                    regionsArr[idx!] = regionOption
                }
            }
        }

        // return regionsArr;
        return regionsArr
    }
}

// const geoCreator = new GeoCreator();
// export default geoCreator;
public let geoCreator = GeoCreator()

// Coerce a dynamic option value to a `[[Double], [Double]]` pair-of-coords (e.g. `boundingCoords`),
// tolerating Int-boxed numbers in the `[String: Any]` bag (the recurring Int-vs-Double option-read trap).
private func asCoordPairs(_ v: Any?) -> [[Double]]? {
    guard let arr = v as? [Any] else { return nil }
    var out: [[Double]] = []
    for item in arr {
        guard let pair = asCoordPair(item) else { return nil }
        out.append(pair)
    }
    return out
}

private func asCoordPair(_ v: Any?) -> [Double]? {
    guard let arr = v as? [Any] else {
        return v as? [Double]
    }
    var out: [Double] = []
    for item in arr {
        if let d = asNumberOpt(item) { out.append(d) }
        else { return nil }
    }
    return out
}

// Int|Double coercion for dynamic option numerics (see the polar/calendar creators' `asNumberOpt`).
private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// JS truthiness for a dynamic option value (nil / NSNull / false / 0 / NaN / "" are falsy).
// Used for the `centerOption && sizeOption` layout guard.
private func geoOptTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil, is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
