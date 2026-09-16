// Ported from echarts/src/coord/geo/geoSourceManager.ts — keep in sync with upstream
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
//   import { createHashMap } from 'zrender/src/core/util';       -> `createHashMap` (modelUtil.swift shim).
//   import { GeoSVGResource } from './GeoSVGResource';           -> GeoSVGResource (sibling; SVG path DEFERRED).
//   import { GeoJSON, GeoJSONSourceInput, GeoResource, GeoSpecialAreas, NameMap, GeoSVGSourceInput }
//       from './geoTypes';                                       -> geoTypes.swift sibling (see GeoJSONResource.swift).
//   import { GeoJSONResource } from './GeoJSONResource';         -> GeoJSONResource (sibling, GeoJSONResource.swift).

// type MapInput = GeoJSONMapInput | SVGMapInput;
//   interface GeoJSONMapInput { geoJSON; specialAreas; }
//   interface GeoJSONMapInputCompat extends GeoJSONMapInput { geoJson; }
//   interface SVGMapInput { svg; }
// These object-shaped inputs are read dynamically from the `[String: Any]` `rawDef` bag below
// (CONVENTIONS §: dynamic option bag → `[String: Any]`), so no Swift structs are declared for them.

// const storage = createHashMap<GeoResource>();
private let storage: HashMap<GeoResource> = createHashMap()

// export default { registerMap, getGeoResource, getMapForUser, load };
//   (object literal → caseless enum namespace; call sites read `geoSourceManager.load(...)` etc.)
public enum geoSourceManager {

    /**
     * Compatible with previous `echarts.registerMap`.
     *
     * @usage
     * ```js
     *
     * echarts.registerMap('USA', geoJson, specialAreas);
     *
     * echarts.registerMap('USA', {
     *     geoJson: geoJson,
     *     specialAreas: {...}
     * });
     * echarts.registerMap('USA', {
     *     geoJSON: geoJson,
     *     specialAreas: {...}
     * });
     *
     * echarts.registerMap('airport', {
     *     svg: svg
     * }
     * ```
     *
     * Note:
     * Do not support that register multiple geoJSON or SVG
     * one map name. Because different geoJSON and SVG have
     * different unit. It's not easy to make sure how those
     * units are mapping/normalize.
     * If intending to use multiple geoJSON or SVG, we can
     * use multiple geo coordinate system.
     */
    // registerMap: function (mapName, rawDef: MapInput | GeoJSONSourceInput, rawSpecialAreas?): void
    public static func registerMap(
        _ mapName: String,
        _ rawDef: Any?,
        _ rawSpecialAreas: GeoSpecialAreas? = nil
    ) {
        var rawSpecialAreas = rawSpecialAreas
        // The MapInput variants are object literals; `rawDef` may also BE the geoJSON directly.
        let rawDefDict = rawDef as? [String: Any]

        // if ((rawDef as SVGMapInput).svg) {
        //     const resource = new GeoSVGResource(mapName, (rawDef as SVGMapInput).svg);
        //     storage.set(mapName, resource);
        // }
        if let svg = rawDefDict?["svg"], jsTruthy(svg) {
            let resource = GeoSVGResource(mapName, svg)
            storage.set(mapName, resource)
        }
        else {
            // Recommend:
            //     echarts.registerMap('eu', { geoJSON: xxx, specialAreas: xxx });
            // Backward compatibility:
            //     echarts.registerMap('eu', geoJSON, specialAreas);
            //     echarts.registerMap('eu', { geoJson: xxx, specialAreas: xxx });
            // let geoJSON = (rawDef as GeoJSONMapInputCompat).geoJson || (rawDef as GeoJSONMapInput).geoJSON;
            var geoJSON: Any? = firstTruthy(rawDefDict?["geoJson"], rawDefDict?["geoJSON"])
            // if (geoJSON && !(rawDef as GeoJSON).features) {
            //     rawSpecialAreas = (rawDef as GeoJSONMapInput).specialAreas;
            // }
            // else { geoJSON = rawDef as GeoJSONSourceInput; }
            if geoJSON != nil && !(rawDefDict?["features"] != nil) {
                rawSpecialAreas = rawDefDict?["specialAreas"] as? GeoSpecialAreas
            }
            else {
                geoJSON = rawDef
            }
            // const resource = new GeoJSONResource(mapName, geoJSON, rawSpecialAreas);
            let resource = GeoJSONResource(mapName, geoJSON, rawSpecialAreas)
            // storage.set(mapName, resource);
            storage.set(mapName, resource)
        }
    }

    // getGeoResource(mapName): GeoResource
    public static func getGeoResource(_ mapName: String) -> GeoResource? {
        // return storage.get(mapName);
        return storage.get(mapName)
    }

    /**
     * Only for exporting to users.
     * **MUST NOT** used internally.
     */
    // getMapForUser: function (mapName): ReturnType<GeoJSONResource['getMapForUser']>
    public static func getMapForUser(_ mapName: String) -> GeoMapForUser? {
        // const resource = storage.get(mapName);
        let resource = storage.get(mapName)
        // Do not support return SVG until some real requirement come.
        // return resource && resource.type === 'geoJSON' && (resource as GeoJSONResource).getMapForUser();
        if let resource = resource, resource.type == "geoJSON", let jsonResource = resource as? GeoJSONResource {
            return jsonResource.getMapForUser()
        }
        return nil
    }

    // load: function (mapName, nameMap, nameProperty): ReturnType<GeoResource['load']>
    // upstream returns `undefined` when the map is not registered (`if (!resource) return;`);
    //   callers (e.g. `Geo`'s constructor: `source.regions`) then dereference it unchecked and crash.
    //   The ported `Geo.init` mirrors that by reading `source.regions` NON-optionally, so this returns a
    //   NON-optional `GeoResourceLoadResult` — the missing-map case yields an EMPTY result (after the
    //   dev-only error) rather than `undefined`. Deliberate language-difference: no unwrapped-undefined
    //   deref, and the caller path is unchanged for the map-registered (normal) case.
    public static func load(
        _ mapName: String,
        _ nameMap: NameMap?,
        _ nameProperty: String?
    ) -> GeoResourceLoadResult {
        // const resource = storage.get(mapName);
        let resource = storage.get(mapName)

        // if (!resource) { if (__DEV__) { console.error(...); } return; }
        guard let resource = resource else {
            if __DEV__ {
                log.error(
                    "Map " + mapName + " not exists. The GeoJSON of the map must be provided."
                )
            }
            return GeoResourceLoadResult(
                boundingRect: BoundingRect(0, 0, 0, 0),
                regions: [],
                regionsMap: createHashMap()
            )
        }

        // return resource.load(nameMap, nameProperty);
        return resource.load(nameMap, nameProperty)
    }

}

// JS `a || b` (falsy-coalescing): pick `a` when truthy, else `b`.
private func firstTruthy(_ a: Any?, _ b: Any?) -> Any? {
    return jsTruthy(a) ? a : b
}

// JS truthiness on a dynamic value (nil/NSNull/false/0/""/NaN are falsy). Mirrors the
//   private `jsTruthy` helpers used elsewhere in the port (see coord/axisTickLabelBuilder.swift).
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let n as NSNumber:
        if n === kCFBooleanTrue { return true }
        if n === kCFBooleanFalse { return false }
        let d = n.doubleValue
        return d != 0 && !d.isNaN
    case let s as String: return !s.isEmpty
    default: return true
    }
}
