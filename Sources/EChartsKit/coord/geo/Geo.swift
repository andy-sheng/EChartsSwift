// Ported from echarts/src/coord/geo/Geo.ts — keep in sync with upstream
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

// upstream imports mapped:
//   import * as zrUtil from 'zrender/src/core/util';                    -> ZRenderKit.util (isString / retrieve2 / createHashMap).
//   import View, { useLegacyViewCoordSysCenterBase, viewCoordSysCopyViewRect, viewCoordSysSetBoundingRect }
//       from '../View';                                                 -> coord/View.swift (ported sibling).
//   import geoSourceManager from './geoSourceManager';
//       -> PORT-TODO: coord/geo/geoSourceManager.ts is a sibling NOT yet landed. This file references its
//          conventional public API: a caseless namespace `geoSourceManager` with
//          `.load(map, nameMap?, nameProperty?) -> GeoSourceLoadResult` and `.getGeoResource(map) -> GeoResource?`.
//   import { GeoJSONRegion, Region } from './Region';
//       -> PORT-TODO: coord/geo/Region.ts sibling NOT yet landed. Referenced API: `Region` (base, `.type: String`,
//          `.getCenter() -> [Double]`) and `GeoJSONRegion` (`.contain([Double]) -> Bool`,
//          `.getBoundingRect(_ projection: GeoProjection?) -> BoundingRect`).
//   import { GeoProjection, GeoResource, NameMap } from './geoTypes';
//       -> PORT-TODO: coord/geo/geoTypes.ts sibling NOT yet landed. Referenced API: `GeoProjection`
//          (`project([Double]) -> [Double]?` / `unproject([Double]) -> [Double]?`), `GeoResource` (`.type: String`),
//          `NameMap` (== `[String: String]`).
//   import GlobalModel from '../../model/Global';                       -> GlobalModel.
//   import { ParsedModelFinder, ParsedModelFinderKnown, SINGLE_REFERRING } from '../../util/model';
//       -> ParsedModelFinder / ParsedModelFinderKnown (`[String: Any]`). SINGLE_REFERRING used only by the
//          getReferringComponents fallback in `getCoordSys` (PORT-TODO below).
//   import type GeoModel from './GeoModel';
//       -> PORT-TODO: coord/geo/GeoModel.ts sibling NOT yet landed (a `ComponentModel` whose
//          `.coordinateSystem` is a `Geo`).
//   import { resizeGeoType } from './geoCreator';
//       -> PORT-TODO: coord/geo/geoCreator.ts sibling NOT yet landed. `resize` is injected there
//          (`geo.resize = resizeGeo`); modeled here as the stored closure `resize` (see Polar.updateHook precedent).
//   import { warn } from '../../util/log';                              -> log.warn.
//   import type ExtensionAPI from '../../core/ExtensionAPI';            -> core/ExtensionAPI.swift.
//   import { CoordinateSystemMaster, GeoLikeCoordSys } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See CONFORMANCE note on the class below.
//   import BoundingRect from 'zrender/src/core/BoundingRect';           -> ZRenderKit.
//   import Transformable from 'zrender/src/core/Transformable';         -> ZRenderKit.
//   import { MatrixArray } from 'zrender/src/core/matrix';              -> ZRenderKit.
//   import { NullUndefined } from 'zrender/src/core/types';             -> Optional (CONVENTIONS §6).

// -----------------------------------------------------------------------------------------------------
// PORT SCOPE (CONVENTIONS §5, and per task brief): the geo COORDINATE SYSTEM (the projection) — the
//   GeoJSON path + the raw-rect -> view-rect linear transform (via `View`), and `projection.project` when
//   a projection is configured. ROAM (pan/zoom) interaction and the SVG-map path (GeoSVGResource) are
//   DEFERRED behind // PORT-TODO. `resize` (regions-bbox fit) is INJECTED by geoCreator (deferred sibling).
// -----------------------------------------------------------------------------------------------------

// upstream:
//   const GEO_DEFAULT_PARAMS: { [type in GeoResource['type']]: { aspectScale; invertLongitute } } = {
//       'geoJSON': { aspectScale: 0.75, invertLongitute: true },
//       'geoSVG':  { aspectScale: 1,    invertLongitute: false }
//   } as const;
private struct GeoDefaultParams {
    let aspectScale: Double
    let invertLongitute: Bool
}
private let GEO_DEFAULT_PARAMS: [String: GeoDefaultParams] = [
    "geoJSON": GeoDefaultParams(aspectScale: 0.75, invertLongitute: true),
    "geoSVG": GeoDefaultParams(aspectScale: 1, invertLongitute: false)
]

// upstream: export const geo2DDimensions: ['lng', 'lat'] = ['lng', 'lat'];
public let geo2DDimensions: [DimensionName] = ["lng", "lat"]

/**
 * upstream: constructor `opt` bag:
 *   { projection?, nameMap?, nameProperty?, aspectScale?, api, ecModel, clip? }
 */
public struct GeoConstructorOption {
    public var projection: GeoProjection?
    // Specify name alias
    public var nameMap: NameMap?
    public var nameProperty: String?
    public var aspectScale: Double?
    public var api: ExtensionAPI
    public var ecModel: GlobalModel
    public var clip: Bool?

    public init(
        projection: GeoProjection? = nil,
        nameMap: NameMap? = nil,
        nameProperty: String? = nil,
        aspectScale: Double? = nil,
        api: ExtensionAPI,
        ecModel: GlobalModel,
        clip: Bool? = nil
    ) {
        self.projection = projection
        self.nameMap = nameMap
        self.nameProperty = nameProperty
        self.aspectScale = aspectScale
        self.api = api
        self.ecModel = ecModel
        self.clip = clip
    }
}

/**
 * upstream: class Geo extends Transformable // See VIEW_COORD_SYS_TRANS_OVERALL_BACKWARD_COMPATIBILITY
 *   implements CoordinateSystemMaster, GeoLikeCoordSys
 *
 * CONFORMANCE note (CONVENTIONS §2, following the Polar/Radar/View precedent): the
 *   `CoordinateSystemMaster` / `GeoLikeCoordSys` protocol conformances are DROPPED here. Geo's
 *   `dataToPoint(data: number[] | string, noRoam?, out?)` / `pointToData(point, reserved?, out?)` /
 *   `getArea(tolerance?)` carry geo-specific signatures that do NOT match the protocol requirements
 *   (`dataToPoint(data, opt?)` / `pointToData(point, opt?)` / `getArea(tolerance?) -> CoordinateSystemClipArea?`),
 *   and every consumer in this phase holds the concrete `Geo` type. `Transformable` subclassing is
 *   preserved because VIEW_COORD_SYS_TRANS_OVERALL is copied onto the Geo instance itself for backward
 *   compatibility (View passes `self` as legacyGeo → view.lgGeo = geo; see View.legacyCopyOverallTrans).
 *   PORT-TODO: re-add protocol conformance + CoordinateSystemManager registration when geoCreator lands.
 */
public final class Geo: Transformable, CoordinateSystemMaster {

    // upstream: dimensions: ['lng', 'lat'] = geo2DDimensions;
    public var dimensions: [DimensionName] = geo2DDimensions

    // upstream: type = 'geo';
    public let type = "geo"

    // upstream: readonly map: string;
    public let map: String

    // upstream: readonly resourceType: GeoResource['type'];
    public let resourceType: String?

    // upstream: readonly view: View;
    //   IUO: assigned in init phase 2 (needs `self` as legacyGeo). Auto-nil counts as initialized
    //   before super.init(); reassigned after super.init().
    public private(set) var view: View!

    // upstream: readonly name: string;
    public let name: String

    // upstream: private _nameCoordMap: HashMap<number[]> = createHashMap<number[], string>();
    private let _nameCoordMap: HashMap<[Double]> = createHashMap()

    // upstream: private _regionsMap: HashMap<Region>;
    private let _regionsMap: HashMap<Region>

    // upstream: private _clip: boolean;
    private let _clip: Bool?

    // upstream: readonly regions: Region[];
    public let regions: [Region]

    // upstream: readonly aspectScale: number;
    public let aspectScale: Double

    // upstream: projection: GeoProjection;
    public var projection: GeoProjection?

    // upstream: model: GeoModel | NullUndefined;  // Injected outside.
    public var model: GeoModel?

    // upstream: resize: resizeGeoType;  // Injected outside (by geoCreator: `geo.resize = resizeGeo`).
    //   PORT-TODO: geoCreator (deferred) assigns this. Signature mirrors `resizeGeo(this: Geo, geoModel, api)`.
    //   `geoModel` is `MapOrGeoModel` (map series model | GeoModel) — erased to `ComponentModel` here.
    public var resize: ((Geo, ComponentModel, ExtensionAPI) -> Void)!

    // upstream: constructor(name, map, opt) { super(); ... }
    public init(_ name: String, _ map: String, _ opt: GeoConstructorOption) {

        self.name = name

        // upstream: let projection = opt.projection;
        var projection = opt.projection

        // upstream: const source = geoSourceManager.load(map, opt.nameMap, opt.nameProperty);
        let source = geoSourceManager.load(map, opt.nameMap, opt.nameProperty)
        // upstream: const resource = geoSourceManager.getGeoResource(map);
        let resource = geoSourceManager.getGeoResource(map)
        // upstream: const resourceType = this.resourceType = resource ? resource.type : null;
        let resourceType = resource != nil ? resource!.type : nil
        self.resourceType = resourceType
        // upstream: const regions = this.regions = source.regions;
        let regions = source.regions
        self.regions = regions
        // upstream: const defaultParams = GEO_DEFAULT_PARAMS[resource.type];
        //   (upstream assumes `resource` is non-null here.)
        let defaultParams = GEO_DEFAULT_PARAMS[resource!.type]!
        // upstream: this._clip = opt.clip;
        self._clip = opt.clip

        // upstream: const invertLongitute = projection ? false : defaultParams.invertLongitute;
        //   NOTE: uses the ORIGINAL projection (before the __DEV__ nulling below).
        let invertLongitute = (projection != nil) ? false : defaultParams.invertLongitute

        // upstream: this.map = map;
        self.map = map
        // upstream: this._regionsMap = source.regionsMap;
        self._regionsMap = source.regionsMap

        // upstream __DEV__ block: validate projection against source type.
        if __DEV__ {
            if projection != nil {
                if resourceType == "geoSVG" {
                    log.warn("Map \(map) with SVG source can't use projection. Only GeoJSON source supports projection.")
                    projection = nil
                }
                // upstream: if (!(projection.project && projection.unproject)) { warn(...); projection = null; }
                //   PORT-TODO: `GeoProjection` requires both `project` and `unproject`, so this check is
                //   vacuous in Swift — the protocol guarantees both members exist.
            }
        }
        // upstream: this.projection = projection;
        self.projection = projection

        // upstream:
        //   let boundingRect;
        //   if (projection) {
        //       for (i ...) { const regionRect = (regions[i] as GeoJSONRegion).getBoundingRect(projection);
        //           boundingRect = boundingRect || regionRect.clone(); boundingRect.union(regionRect); }
        //   } else { boundingRect = source.boundingRect; }
        var boundingRect: BoundingRect?
        if let projection = projection {
            // Can't reuse the raw bounding rect
            for i in 0..<regions.count {
                let regionRect = (regions[i] as! GeoJSONRegion).getBoundingRect(projection)
                if boundingRect == nil {
                    boundingRect = regionRect.clone()
                }
                boundingRect!.union(regionRect)
            }
        }
        else {
            boundingRect = source.boundingRect
        }

        // aspectScale and invertLongitute actually is the parameters default raw projection.
        // So we ignore them if projection is given.
        // upstream: this.aspectScale = projection ? 1 : zrUtil.retrieve2(opt.aspectScale, defaultParams.aspectScale);
        //   NOTE: uses the FINAL projection.
        self.aspectScale = (projection != nil)
            ? 1
            : ZRenderKit.util.retrieve2(opt.aspectScale, defaultParams.aspectScale)!

        super.init()

        // upstream: this.view = new View(invertLongitute, useLegacyViewCoordSysCenterBase(opt.ecModel, opt.api), this);
        self.view = View(
            invertLongitute,
            useLegacyViewCoordSysCenterBase(opt.ecModel, opt.api),
            self
        )

        // upstream: viewCoordSysSetBoundingRect(this.view, boundingRect.x, boundingRect.y, boundingRect.width, boundingRect.height);
        let br = boundingRect!
        viewCoordSysSetBoundingRect(self.view, br.x, br.y, br.width, br.height)
    }

    // upstream: getRegion(name) { return this._regionsMap.get(name); }
    public func getRegion(_ name: String) -> Region? {
        return self._regionsMap.get(name)
    }

    // upstream: getRegionByCoord(coord) {
    //     const regions = this.regions;
    //     for (i ...) { const region = regions[i];
    //         if (region.type === 'geoJSON' && (region as GeoJSONRegion).contain(coord)) { return regions[i]; } }
    // }
    public func getRegionByCoord(_ coord: [Double]) -> Region? {
        let regions = self.regions
        for i in 0..<regions.count {
            let region = regions[i]
            if region.type == "geoJSON" && (region as! GeoJSONRegion).contain(coord) {
                return regions[i]
            }
        }
        return nil
    }

    /**
     * Add geoCoord for indexing by name
     */
    // upstream: addGeoCoord(name, geoCoord) { this._nameCoordMap.set(name, geoCoord); }
    public func addGeoCoord(_ name: String, _ geoCoord: [Double]) {
        self._nameCoordMap.set(name, geoCoord)
    }

    /**
     * Get geoCoord by name
     */
    // upstream: getGeoCoord(name) {
    //     const region = this._regionsMap.get(name);
    //     return this._nameCoordMap.get(name) || (region && region.getCenter());
    // }
    public func getGeoCoord(_ name: String) -> [Double]? {
        let region = self._regionsMap.get(name)
        // Calculate center only on demand.
        return self._nameCoordMap.get(name) ?? region?.getCenter()
    }

    // upstream: dataToPoint(data: number[] | string, noRoam?, out?) {
    //     if (zrUtil.isString(data)) { data = this.getGeoCoord(data); }
    //     if (data) {
    //         const projection = this.projection;
    //         if (projection) { data = projection.project(data); }
    //         return data && this.view.dataToPoint(data, noRoam, out);
    //     }
    // }
    //   `data: number[] | string` -> `Any?`; `out?` perf out-param dropped (CONVENTIONS §3).
    //   Returns nil when `data`/projected point is falsy (upstream returns undefined).
    @discardableResult
    public func dataToPoint(_ data: Any?, _ noRoam: Bool? = nil) -> [Double]? {
        var coord: [Double]?
        if ZRenderKit.util.isString(data) {
            // Map area name to geoCoord
            coord = self.getGeoCoord(data as! String)
        }
        else {
            coord = data as? [Double]
        }
        if var c = coord {                          // upstream: if (data)
            let projection = self.projection
            if let projection = projection {
                // projection may return null point.
                guard let projected = projection.project(c) else {
                    return nil                      // upstream: data && ... -> null
                }
                c = projected
            }
            return self.view.dataToPoint(c, noRoam)
        }
        return nil
    }

    // upstream: pointToData(point, reserved?, out?) {
    //     const projection = this.projection;
    //     if (projection) { point = projection.unproject(point); }
    //     return point && this.view.pointToData(point, out);
    // }
    @discardableResult
    public func pointToData(_ point: [Double], _ reserved: Any? = nil) -> [Double]? {
        var point = point
        let projection = self.projection
        if let projection = projection {
            // projection may return null point.
            guard let unprojected = projection.unproject(point) else {
                return nil                          // upstream: point && ... -> null/undefined
            }
            point = unprojected
        }
        // FIXME (upstream): if no `point`, should return [NaN, NaN], rather than undefined.
        return self.view.pointToData(point)
    }

    // upstream: convertToPixel(ecModel, finder, value: number[]) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToPoint(value) : null;
    // }
    public func convertToPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: [Double]
    ) -> [Double]? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToPoint(value) : nil
    }

    // upstream: convertFromPixel(ecModel, finder, pixel: number[]) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.pointToData(pixel) : null;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ pixel: [Double]
    ) -> [Double]? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.pointToData(pixel) : nil
    }

    // upstream: containPoint(point) { return this.view.containPoint(point); }
    public func containPoint(_ point: [Double]) -> Bool {
        return self.view.containPoint(point)
    }

    // upstream: getArea(tolerance?) {
    //     tolerance = tolerance || 0;
    //     const rect = viewCoordSysCopyViewRect(null, this.view);
    //     rect.x -= tolerance; rect.y -= tolerance;
    //     rect.width += 2 * tolerance; rect.height += 2 * tolerance;
    //     return rect;
    // }
    public func getArea(_ tolerance: Double? = nil) -> BoundingRect {
        let tolerance = tolerance ?? 0              // upstream: tolerance || 0
        let rect = viewCoordSysCopyViewRect(nil, self.view)
        rect.x -= tolerance
        rect.y -= tolerance
        rect.width += 2 * tolerance
        rect.height += 2 * tolerance
        return rect
    }

    // upstream: shouldClip() { return this._clip; }
    public func shouldClip() -> Bool? {
        return self._clip
    }

    /**
     * @implements CoordinateSystem['getBoundingRect']
     */
    // upstream: getBoundingRect() { return this.view.getBoundingRect(); }
    public func getBoundingRect() -> BoundingRect {
        return self.view.getBoundingRect()
    }

    /**
     * @implements CoordinateSystem['getViewRect']
     */
    // upstream: getViewRect() { return this.view.getViewRect(); }
    public func getViewRect() -> BoundingRect {
        return self.view.getViewRect()
    }

    /**
     * @implements CoordinateSystem['getRoamTransform']
     */
    // upstream: getRoamTransform() { return this.view.getRoamTransform(); }
    public func getRoamTransform() -> MatrixArray {
        return self.view.getRoamTransform()
    }
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown): Geo {
//     const geoModel = finder.geoModel as GeoModel;
//     const seriesModel = finder.seriesModel;
//     return geoModel
//         ? geoModel.coordinateSystem
//         : seriesModel
//         ? (seriesModel.coordinateSystem as Geo // For map series.
//             || ((seriesModel.getReferringComponents('geo', SINGLE_REFERRING).models[0] || {}) as GeoModel).coordinateSystem)
//         : null;
// }
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> Geo? {
    let geoModel = finder["geoModel"] as? GeoModel
    let seriesModel = finder["seriesModel"] as? SeriesModel
    if let geoModel = geoModel {
        return geoModel.coordinateSystem as? Geo
    }
    if let seriesModel = seriesModel {
        // For map series.
        if let cs = seriesModel.coordinateSystem as? Geo {
            return cs
        }
        // upstream fallback: seriesModel.getReferringComponents('geo', SINGLE_REFERRING).models[0].coordinateSystem
        // PORT-TODO: `getReferringComponents(_, SINGLE_REFERRING)` referring-resolution fallback is deferred.
        return nil
    }
    return nil
}

// export default Geo;  -> `public final class Geo` above.
