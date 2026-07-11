// Ported from echarts/src/coord/geo/parseGeoJson.ts — keep in sync with upstream
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

/**
 * Parse and decode geo json
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                                     -> `util.*` (ZRenderKit).
//   import { GeoJSONLineStringGeometry, GeoJSONPolygonGeometry, GeoJSONRegion } from './Region';
//                                                                                        -> Region.swift (sibling).
//   import { GeoJSONCompressed, GeoJSON } from './geoTypes';                             -> geoTypes not ported;
//     GeoJSON / GeoJSONCompressed are dynamic JSON bags -> [String: Any] (CONVENTIONS: dynamic option bag).

// MARK: - dynamic JSON coercion helpers
// PORT-NOTE: geoTypes is ported, but GeoJSON structures are dynamic JSON bags and arrive as parsed JSON
// ([String: Any] / nested [Any] with NSNumber leaves). These helpers coerce that dynamic bag into the
// typed numeric arrays / VectorArray rings the ported logic below consumes. INT-vs-DOUBLE trap:
// go through NSNumber.doubleValue so Int-boxed JSON numbers do not drop to nil.
private func asDouble(_ v: Any) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let f = v as? Float { return Double(f) }
    return 0 // PORT-NOTE: non-numeric leaf
}

private func asDoubleOrNil(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    if v is [Any] || v is String { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let f = v as? Float { return Double(f) }
    return nil
}

// Replicates JS truthiness for the checks upstream performs (`if (!json.UTF8Encoding)`,
// `if (!encodeOffsets)`). CONVENTIONS §6: replicate truthiness explicitly.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = asDoubleOrNil(v) { return d != 0 && !d.isNaN }
    if let s = v as? String { return !s.isEmpty }
    return true // arrays / objects are truthy
}

private func doubleArray1(_ v: Any?) -> [Double] {
    return (v as? [Any])?.map { asDouble($0) } ?? []
}
private func doubleArray2(_ v: Any?) -> [[Double]] {
    return (v as? [Any])?.map { doubleArray1($0) } ?? []
}
private func doubleArray3(_ v: Any?) -> [[[Double]]] {
    return (v as? [Any])?.map { doubleArray2($0) } ?? []
}

// number[] position -> [Double] point (Region stores rings as [[Double]]; see Region.swift note).
private func toPoint(_ v: Any) -> [Double] {
    if let p = v as? [Double] { return p }
    if let p = v as? [Any] { return p.map { asDouble($0) } }
    return [0, 0] // PORT-NOTE: malformed position
}
// number[][] ring -> [[Double]].
private func toRing(_ v: Any?) -> [[Double]] {
    return (v as? [Any])?.map { toPoint($0) } ?? []
}
// number[][][] rings -> [[[Double]]].
private func toRings(_ v: Any?) -> [[[Double]]] {
    return (v as? [Any])?.map { toRing($0) } ?? []
}

// MARK: - decode

private func decode(_ json: [String: Any]) -> [String: Any] {
    if !jsTruthy(json["UTF8Encoding"]) {
        return json
    }
    var jsonCompressed = json
    var encodeScale = asDoubleOrNil(jsonCompressed["UTF8Scale"])
    if encodeScale == nil {
        encodeScale = 1024
    }
    let encodeScaleVal = encodeScale!

    var features = (jsonCompressed["features"] as? [[String: Any]]) ?? []
    // upstream: zrUtil.each(features, feature => { ... })
    for idx in 0..<features.count {
        var feature = features[idx]
        guard var geometry = feature["geometry"] as? [String: Any] else {
            continue
        }
        let encodeOffsets = geometry["encodeOffsets"]
        let coordinates = geometry["coordinates"]

        // Geometry may be appeded manually in the script after json loaded.
        // In this case this geometry is usually not encoded.
        if !jsTruthy(encodeOffsets) {
            continue
        }

        switch geometry["type"] as? String ?? "" {
        case "LineString":
            geometry["coordinates"] =
                decodeRing(coordinates as? String ?? "", doubleArray1(encodeOffsets), encodeScaleVal)
        case "Polygon":
            geometry["coordinates"] =
                decodeRings(coordinates as? [String] ?? [], doubleArray2(encodeOffsets), encodeScaleVal)
        case "MultiLineString":
            geometry["coordinates"] =
                decodeRings(coordinates as? [String] ?? [], doubleArray2(encodeOffsets), encodeScaleVal)
        case "MultiPolygon":
            let coords = (coordinates as? [[String]]) ?? []
            let offsets = doubleArray3(encodeOffsets)
            var decoded: [[[[Double]]]] = []
            // upstream: zrUtil.each(coordinates, (rings, idx) => decodeRings(rings, encodeOffsets[idx], scale))
            for ridx in 0..<coords.count {
                decoded.append(decodeRings(coords[ridx], offsets[ridx], encodeScaleVal))
            }
            geometry["coordinates"] = decoded
        default:
            break
        }

        feature["geometry"] = geometry
        features[idx] = feature
    }
    jsonCompressed["features"] = features
    // Has been decoded
    jsonCompressed["UTF8Encoding"] = false

    return jsonCompressed
}

private func decodeRings(
    _ rings: [String],
    _ encodeOffsets: [[Double]],
    _ encodeScale: Double
) -> [[[Double]]] {
    var result: [[[Double]]] = []
    for c in 0..<rings.count {
        result.append(decodeRing(
            rings[c],
            encodeOffsets[c],
            encodeScale
        ))
    }
    return result
}

private func decodeRing(
    _ coordinate: String,
    _ encodeOffsets: [Double],
    _ encodeScale: Double
) -> [[Double]] {
    var result: [[Double]] = []
    var prevX = encodeOffsets[0]
    var prevY = encodeOffsets[1]

    // charCodeAt returns UTF-16 code units; the echarts encoding stays in the BMP.
    let chars = Array(coordinate.utf16)
    var i = 0
    // upstream steps `i += 2` up to `coordinate.length`; a malformed odd-length string would read
    // `charCodeAt(len)` = NaN (garbage, no throw). Bound the pair read to avoid a Swift index trap.
    while i + 1 < chars.count {
        var xi = Int(chars[i]) - 64
        var yi = Int(chars[i + 1]) - 64
        // ZigZag decoding
        xi = (xi >> 1) ^ (-(xi & 1))
        yi = (yi >> 1) ^ (-(yi & 1))
        // Delta deocding
        let x = Double(xi) + prevX
        let y = Double(yi) + prevY

        prevX = x
        prevY = y
        // Dequantize
        result.append([x / encodeScale, y / encodeScale])
        i += 2
    }

    return result
}

public func parseGeoJSON(_ geoJson: [String: Any], _ nameProperty: String?) -> [GeoJSONRegion] {

    let geoJson = decode(geoJson)

    let features = (geoJson["features"] as? [[String: Any]]) ?? []

    return util.map(util.filter(features) { featureObj, _ in
        // Output of mapshaper may have geometry null
        let geometry = featureObj["geometry"] as? [String: Any]
        let properties = featureObj["properties"] as? [String: Any]
        let coordLen = (geometry?["coordinates"] as? [Any])?.count ?? 0
        return geometry != nil
            && properties != nil
            && coordLen > 0
    }) { featureObj, _ in
        let properties = featureObj["properties"] as! [String: Any]
        let geo = featureObj["geometry"] as! [String: Any]

        var geometries: [GeoJSONGeometry] = []
        switch geo["type"] as? String ?? "" {
        case "Polygon":
            let coordinates = toRings(geo["coordinates"])
            // According to the GeoJSON specification.
            // First must be exterior, and the rest are all interior(holes).
            geometries.append(GeoJSONPolygonGeometry(coordinates[0], Array(coordinates.dropFirst())))
        case "MultiPolygon":
            // upstream: zrUtil.each(geo.coordinates, function (item) { ... })
            let coords = (geo["coordinates"] as? [Any]) ?? []
            for item in coords {
                let itemRings = toRings(item) // item: number[][][]
                if itemRings.count > 0 { // if (item[0])
                    geometries.append(GeoJSONPolygonGeometry(itemRings[0], Array(itemRings.dropFirst())))
                }
            }
        case "LineString":
            geometries.append(GeoJSONLineStringGeometry([toRing(geo["coordinates"])]))
        case "MultiLineString":
            geometries.append(GeoJSONLineStringGeometry(toRings(geo["coordinates"])))
        default:
            break
        }

        // properties[nameProperty || 'name']
        let nameKey = jsTruthy(nameProperty) ? nameProperty! : "name"
        let name = (properties[nameKey] as? String) ?? ""
        // properties.cp
        let cpAny = properties["cp"]
        let cp: [Double]? = (cpAny is [Any]) ? doubleArray1(cpAny) : nil

        let region = GeoJSONRegion(
            name,
            geometries,
            cp
        )
        region.properties = properties
        return region
    }
}
