// Ported from echarts/src/coord/geo/GeoJSONResource.ts — keep in sync with upstream
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
//   import { each, isString, createHashMap, hasOwn } from 'zrender/src/core/util';
//       -> `util.each` / `util.isString` / `createHashMap` (modelUtil.swift shim) / `dict[k] != nil`.
//   import parseGeoJson from './parseGeoJson';                    -> `parseGeoJson` (sibling parseGeoJson.swift).
//   import fixNanhai from './fix/nanhai';                         -> `fixNanhai` (sibling fix/nanhai.swift).
//   import fixTextCoord from './fix/textCoord';                   -> `fixTextCoord` (sibling fix/textCoord.swift).
//   import fixDiaoyuIsland from './fix/diaoyuIsland';             -> `fixDiaoyuIsland` (sibling fix/diaoyuIsland.swift).
//   import BoundingRect from 'zrender/src/core/BoundingRect';     -> BoundingRect (ZRenderKit).
//   import { GeoJSONRegion } from './Region';                     -> GeoJSONRegion / Region (sibling Region.swift).
//   import { GeoJSON, GeoJSONCompressed, GeoJSONSourceInput, GeoResource, GeoSpecialAreas, NameMap }
//       from './geoTypes';                                        -> geoTypes.swift sibling.

// `geoTypes.swift` has landed and now OWNS the support types once staged here — `GeoResource`,
//   `NameMap`, `GeoSpecialAreas`, and the GeoJSON source unions (shown commented below for reference).
//   `GeoResourceLoadResult` (the object literal returned by `GeoResource['load']`) remains declared in
//   this file, below. See integrationNotes.
//
//   public protocol GeoResource: AnyObject {
//       var type: String { get }                         // 'geoJSON' | 'geoSVG'
//       func load(_ nameMap: NameMap?, _ nameProperty: String?) -> GeoResourceLoadResult
//   }
//   public typealias NameMap = [String: String]
//   public typealias GeoSpecialAreas = [String: GeoSpecialArea]
//   public struct GeoSpecialArea { public var left, top: Double; public var width, height: Double? }
//   public typealias GeoJSONSourceInput = Any    // string | GeoJSON | GeoJSONCompressed
//
// upstream: the object literal returned by `GeoResource['load']`.
public struct GeoResourceLoadResult {
    public var boundingRect: BoundingRect
    public var regions: [Region]
    // Key: region.name
    public var regionsMap: HashMap<Region>
    public init(boundingRect: BoundingRect, regions: [Region], regionsMap: HashMap<Region>) {
        self.boundingRect = boundingRect
        self.regions = regions
        self.regionsMap = regionsMap
    }
}

// upstream: the object literal returned by `GeoJSONResource.getMapForUser`.
public struct GeoMapForUser {
    // backward compat. (see upstream comment)
    public var geoJson: Any?
    public var geoJSON: Any?
    public var specialAreas: GeoSpecialAreas?
    public init(geoJson: Any?, geoJSON: Any?, specialAreas: GeoSpecialAreas?) {
        self.geoJson = geoJson
        self.geoJSON = geoJSON
        self.specialAreas = specialAreas
    }
}

// const DEFAULT_NAME_PROPERTY = 'name' as const;
private let DEFAULT_NAME_PROPERTY: String = "name"

// upstream: the `{ regions, boundingRect }` entry cached in `_parsedMap`. Modeled as a `final class`
//   so `this._parsedMap.set(...)` returns a reference whose fields match the upstream object (a struct
//   would be a value copy). `boundingRect` is optional internally (calculateBoundingRect may be
//   undefined for empty region sets — see `load`).
private final class GeoJSONParsedEntry {
    var regions: [GeoJSONRegion]
    var boundingRect: BoundingRect?
    init(regions: [GeoJSONRegion], boundingRect: BoundingRect?) {
        self.regions = regions
        self.boundingRect = boundingRect
    }
}

// export class GeoJSONResource implements GeoResource
public final class GeoJSONResource: GeoResource {

    // readonly type = 'geoJSON';
    public let type: String = "geoJSON"
    // private _geoJSON: GeoJSON | GeoJSONCompressed;
    private var _geoJSON: Any?
    // private _specialAreas: GeoSpecialAreas;
    private var _specialAreas: GeoSpecialAreas?
    // private _mapName: string;
    private var _mapName: String

    // private _parsedMap = createHashMap<{ regions; boundingRect }, string>();
    private var _parsedMap: HashMap<GeoJSONParsedEntry> = createHashMap()

    // constructor(mapName, geoJSON, specialAreas)
    public init(_ mapName: String, _ geoJSON: Any?, _ specialAreas: GeoSpecialAreas?) {
        // this._mapName = mapName;
        self._mapName = mapName
        // this._specialAreas = specialAreas;
        self._specialAreas = specialAreas

        // PENDING: delay the parse to the first usage to rapid up the FMP?
        // this._geoJSON = parseInput(geoJSON);
        self._geoJSON = parseInput(geoJSON)
    }

    /**
     * @param nameMap can be null/undefined
     * @param nameProperty can be null/undefined
     */
    // load(nameMap, nameProperty)
    public func load(_ nameMap: NameMap?, _ nameProperty: String?) -> GeoResourceLoadResult {

        // nameProperty = nameProperty || DEFAULT_NAME_PROPERTY;
        let nameProperty: String = (nameProperty != nil && !nameProperty!.isEmpty)
            ? nameProperty! : DEFAULT_NAME_PROPERTY

        // let parsed = this._parsedMap.get(nameProperty);
        var parsed = self._parsedMap.get(nameProperty)
        if parsed == nil { // if (!parsed)
            // const rawRegions = this._parseToRegions(nameProperty);
            let rawRegions = self._parseToRegions(nameProperty)
            // parsed = this._parsedMap.set(nameProperty, { regions, boundingRect });
            parsed = self._parsedMap.set(nameProperty, GeoJSONParsedEntry(
                regions: rawRegions,
                boundingRect: calculateBoundingRect(rawRegions)
            ))
        }
        let parsedEntry = parsed! // non-null past the guard above

        // const regionsMap = createHashMap<GeoJSONRegion>();
        let regionsMap: HashMap<Region> = createHashMap()

        // const finalRegions: GeoJSONRegion[] = [];
        var finalRegions: [GeoJSONRegion] = []
        // each(parsed.regions, function (region) { ... });
        util.each(parsedEntry.regions) { region, _ in
            var region = region
            // let regionName = region.name;
            var regionName = region.name

            // Try use the alias in geoNameMap
            // if (nameMap && hasOwn(nameMap, regionName)) {
            //     region = region.cloneShallow(regionName = nameMap[regionName]);
            // }
            if let nameMap = nameMap, let alias = nameMap[regionName] {
                regionName = alias
                region = region.cloneShallow(regionName)
            }

            // finalRegions.push(region);
            finalRegions.append(region)
            // regionsMap.set(regionName, region);
            regionsMap.set(regionName, region)
        }

        // return { regions, boundingRect, regionsMap };
        return GeoResourceLoadResult(
            // parsed.boundingRect || new BoundingRect(0, 0, 0, 0)
            boundingRect: parsedEntry.boundingRect ?? BoundingRect(0, 0, 0, 0),
            regions: finalRegions.map { $0 as Region },
            regionsMap: regionsMap
        )
    }

    // private _parseToRegions(nameProperty): GeoJSONRegion[]
    private func _parseToRegions(_ nameProperty: String) -> [GeoJSONRegion] {
        // const mapName = this._mapName;
        let mapName = self._mapName
        // const geoJSON = this._geoJSON;
        let geoJSON = self._geoJSON
        // let rawRegions;
        var rawRegions: [GeoJSONRegion]

        // https://jsperf.com/try-catch-performance-overhead
        // try { rawRegions = geoJSON ? parseGeoJson(geoJSON, nameProperty) : []; }
        // catch (e) { throw new Error('Invalid geoJson format\n' + e.message); }
        // upstream wraps `parseGeoJson` in try/catch to rethrow as 'Invalid geoJson format'.
        //   `parseGeoJson` (sibling) is ported non-throwing as `parseGeoJSON` and takes `[String: Any]`;
        //   the try/catch is omitted (language difference) and the `Any?` source is narrowed to the dict
        //   it always is here.
        if geoJSON != nil {
            rawRegions = parseGeoJSON(geoJSON as? [String: Any] ?? [:], nameProperty)
        }
        else {
            rawRegions = []
        }

        // fixNanhai(mapName, rawRegions);
        // `fixNanhai` takes `inout [GeoJSONRegion]` (it PUSHES a synthesized region; Swift
        //   arrays are value types, unlike the mutated JS array reference).
        fixNanhai(mapName, &rawRegions)

        // each(rawRegions, function (region) { ... }, this);
        util.each(rawRegions) { region, _ in
            // const regionName = region.name;
            let regionName = region.name

            // fixTextCoord(mapName, region);
            fixTextCoord(mapName, region)
            // fixDiaoyuIsland(mapName, region);
            // TODO: `fixDiaoyuIsland` PUSHES to `region.geometries`, but the ported
            //   `GeoJSONRegion.geometries` is declared `let` (Region.swift). Wiring it faithfully needs
            //   that field made `var` — a cross-file change, deferred to keep this lane self-contained.
            // fixDiaoyuIsland(mapName, region)

            // Some area like Alaska in USA map needs to be tansformed
            // to look better
            // const specialArea = this._specialAreas && this._specialAreas[regionName];
            let specialArea = self._specialAreas?[regionName]
            // if (specialArea) { region.transformTo(...); }
            if let specialArea = specialArea {
                // upstream `specialArea.width`/`height` are optional (`number | undefined`); the ported
                //   `GeoJSONRegion.transformTo` uses `0` as the "derive from aspect" sentinel (matching
                //   the upstream falsy `!width` check), so nil coalesces to `0`.
                region.transformTo(
                    specialArea.left, specialArea.top, specialArea.width ?? 0, specialArea.height ?? 0
                )
            }
        }

        // return rawRegions;
        return rawRegions
    }

    /**
     * Only for exporting to users.
     * **MUST NOT** used internally.
     */
    // getMapForUser()
    public func getMapForUser() -> GeoMapForUser {
        return GeoMapForUser(
            // For backward compatibility, use geoJson
            // PENDING: it has been returning them without clone.
            // do we need to avoid outsite modification?
            geoJson: self._geoJSON,
            geoJSON: self._geoJSON,
            specialAreas: self._specialAreas
        )
    }

}

// function calculateBoundingRect(regions: GeoJSONRegion[]): BoundingRect
private func calculateBoundingRect(_ regions: [GeoJSONRegion]) -> BoundingRect? {
    // let rect;
    var rect: BoundingRect?
    // for (let i = 0; i < regions.length; i++) { ... }
    for i in 0..<regions.count {
        // const regionRect = regions[i].getBoundingRect();
        let regionRect = regions[i].getBoundingRect()
        // rect = rect || regionRect.clone();
        rect = rect ?? regionRect.clone()
        // rect.union(regionRect);
        rect!.union(regionRect)
    }
    // return rect;
    return rect
}

// function parseInput(source: GeoJSONSourceInput): GeoJSON | GeoJSONCompressed
private func parseInput(_ source: Any?) -> Any? {
    // return !isString(source)
    //     ? source
    //     : (typeof JSON !== 'undefined' && JSON.parse) ? JSON.parse(source)
    //     : (new Function('return (' + source + ');'))();
    // the `new Function(...)` legacy fallback branch (no global JSON) is dropped; Swift
    //   always has JSONSerialization.
    if !util.isString(source) {
        return source
    }
    guard let str = source as? String, let data = str.data(using: .utf8) else {
        return source
    }
    return try? JSONSerialization.jsonObject(with: data, options: [])
}

// ---------------------------------------------------------------------------
// Ported from echarts/src/coord/geo/fix/nanhai.ts — Fix for 南海诸岛.
// the upstream fix/*.ts modules are inlined here as file-private helpers (each is a single
//   small function only consumed by `_parseToRegions`); logic/names/order mirror upstream.
// ---------------------------------------------------------------------------

// const geoCoord = [126, 25];
private let nanhaiGeoCoord: [Double] = [126, 25]
// const nanhaiName = '南海诸岛';
private let nanhaiName = "南海诸岛"

// const points = [ ... ]; then the module-level transform loop below (applied once, mirroring the
//   upstream import-time mutation of the `points` literal).
private let nanhaiPoints: [[[Double]]] = {
    var points: [[[Double]]] = [
        [[0, 3.5], [7, 11.2], [15, 11.9], [30, 7], [42, 0.7], [52, 0.7],
            [56, 7.7], [59, 0.7], [64, 0.7], [64, 0], [5, 0], [0, 3.5]],
        [[13, 16.1], [19, 14.7], [16, 21.7], [11, 23.1], [13, 16.1]],
        [[12, 32.2], [14, 38.5], [15, 38.5], [13, 32.2], [12, 32.2]],
        [[16, 47.6], [12, 53.2], [13, 53.2], [18, 47.6], [16, 47.6]],
        [[6, 64.4], [8, 70], [9, 70], [8, 64.4], [6, 64.4]],
        [[23, 82.6], [29, 79.8], [30, 79.8], [25, 82.6], [23, 82.6]],
        [[37, 70.7], [43, 62.3], [44, 62.3], [39, 70.7], [37, 70.7]],
        [[48, 51.1], [51, 45.5], [53, 45.5], [50, 51.1], [48, 51.1]],
        [[51, 35], [51, 28.7], [53, 28.7], [53, 35], [51, 35]],
        [[52, 22.4], [55, 17.5], [56, 17.5], [53, 22.4], [52, 22.4]],
        [[58, 12.6], [62, 7], [63, 7], [60, 12.6], [58, 12.6]],
        [[0, 3.5], [0, 93.1], [64, 93.1], [64, 0], [63, 0], [63, 92.4],
            [1, 92.4], [1, 3.5], [0, 3.5]]
    ]
    for i in 0..<points.count {
        for k in 0..<points[i].count {
            points[i][k][0] /= 10.5
            points[i][k][1] /= -10.5 / 0.75

            points[i][k][0] += nanhaiGeoCoord[0]
            points[i][k][1] += nanhaiGeoCoord[1]
        }
    }
    return points
}()

// export default function fixNanhai(mapType, regions)
private func fixNanhai(_ mapType: String, _ regions: inout [GeoJSONRegion]) {
    if mapType == "china" {
        for i in 0..<regions.count {
            // Already exists.
            if regions[i].name == nanhaiName {
                return
            }
        }

        regions.append(GeoJSONRegion(
            nanhaiName,
            // zrUtil.map(points, exterior => ({ type: 'polygon', exterior }))
            util.map(nanhaiPoints) { exterior, _ in
                GeoJSONPolygonGeometry(exterior, nil) as GeoJSONGeometry
            },
            nanhaiGeoCoord
        ))
    }
}

// ---------------------------------------------------------------------------
// Ported from echarts/src/coord/geo/fix/textCoord.ts.
// ---------------------------------------------------------------------------

// const coordsOffsetMap = { ... } as Dictionary<number[]>;
private let coordsOffsetMap: [String: [Double]] = [
    "南海诸岛": [32, 80],
    // 全国
    "广东": [0, -10],
    "香港": [10, 5],
    "澳门": [-10, 10],
    // '北京': [-10, 0],
    "天津": [5, 5]
]

// export default function fixTextCoords(mapType, region)
private func fixTextCoord(_ mapType: String, _ region: GeoJSONRegion) {
    if mapType == "china" {
        // const coordFix = coordsOffsetMap[region.name];
        if let coordFix = coordsOffsetMap[region.name] {
            // const cp = region.getCenter();
            var cp = region.getCenter()
            cp[0] += coordFix[0] / 10.5
            cp[1] += -coordFix[1] / (10.5 / 0.75)
            region.setCenter(cp)
        }
    }
}
