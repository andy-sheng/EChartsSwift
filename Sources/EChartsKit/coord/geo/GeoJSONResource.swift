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

// PORT-NOTE: `geoTypes.swift` has landed and now OWNS the support types once staged here — `GeoResource`,
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
        //   Only consumed by the stubbed-out fixNanhai/fixTextCoord/fixDiaoyuIsland fixers (PORT-NOTE
        //   below); silence the unused warning until those land.
        let mapName = self._mapName
        _ = mapName
        // const geoJSON = this._geoJSON;
        let geoJSON = self._geoJSON
        // let rawRegions;
        var rawRegions: [GeoJSONRegion]

        // https://jsperf.com/try-catch-performance-overhead
        // try { rawRegions = geoJSON ? parseGeoJson(geoJSON, nameProperty) : []; }
        // catch (e) { throw new Error('Invalid geoJson format\n' + e.message); }
        // PORT-NOTE: upstream wraps `parseGeoJson` in try/catch to rethrow as 'Invalid geoJson format'.
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
        // PORT-NOTE (deferred): requires the built-in GEO fixers `fixNanhai` / `fixTextCoord` /
        //   `fixDiaoyuIsland` (echarts/src/coord/geo/fix/*), NOT yet ported (out of this phase's scope).
        //   The calls are stubbed out; wire them when `fix/nanhai.swift` etc. land. `fixNanhai` must take
        //   `inout [GeoJSONRegion]` (it PUSHES synthesized regions; Swift arrays are value types).
        // fixNanhai(mapName, &rawRegions)

        // each(rawRegions, function (region) { ... }, this);
        util.each(rawRegions) { region, _ in
            // const regionName = region.name;
            let regionName = region.name

            // fixTextCoord(mapName, region);
            // fixTextCoord(mapName, region)   // PORT-NOTE (deferred): fix/textCoord not yet ported (see above).
            // fixDiaoyuIsland(mapName, region);
            // fixDiaoyuIsland(mapName, region)  // PORT-NOTE (deferred): fix/diaoyuIsland not yet ported (see above).

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
    // PORT-NOTE: the `new Function(...)` legacy fallback branch (no global JSON) is dropped; Swift
    //   always has JSONSerialization.
    if !util.isString(source) {
        return source
    }
    guard let str = source as? String, let data = str.data(using: .utf8) else {
        return source
    }
    return try? JSONSerialization.jsonObject(with: data, options: [])
}
