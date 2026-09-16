// Ported from echarts/src/coord/geo/geoTypes.ts — keep in sync with upstream
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

// import BoundingRect from 'zrender/src/core/BoundingRect';             -> BoundingRect (ZRenderKit)
// import { HashMap } from 'zrender/src/core/util';                      -> [String: T] (a `HashMap` shim also exists in util/modelUtil.swift)
// import { Group } from '../../util/graphic';                           -> Group (ZRenderKit)
// import { Region } from './Region';                                    -> Region (coord/geo/Region.swift)
//
// `Region` (coord/geo/Region.swift) is ported — it is the geo region primitive that a
//   `GeoResource.load` yields (drawn as filled polygon rings). It is referenced structurally below.

// upstream: export type GeoSVGSourceInput = string | Document | SVGElement;
//   `Document`/`SVGElement` are DOM types (SVG-map path, deferred per the phase brief) -> erased to `Any`.
public typealias GeoSVGSourceInput = Any
// upstream: export type GeoJSONSourceInput = string | GeoJSON | GeoJSONCompressed;
//   union erased to `Any` (dynamic source blob; narrowed by the loader once parseGeoJson lands).
public typealias GeoJSONSourceInput = Any

// upstream: export interface NameMap { [regionName: string]: string }
public typealias NameMap = [String: String]

// upstream:
// export interface GeoSpecialAreas {
//     [areaName: string]: { left: number; top: number; width?: number; height?: number; }
// }
public struct GeoSpecialArea {
    public var left: Double
    public var top: Double
    public var width: Double?
    public var height: Double?
    public init(left: Double, top: Double, width: Double? = nil, height: Double? = nil) {
        self.left = left
        self.top = top
        self.width = width
        self.height = height
    }
}
public typealias GeoSpecialAreas = [String: GeoSpecialArea]

// Currently only `FeatureCollection` is supported in `parseGeoJson`?
// upstream: export interface GeoJSON extends GeoJSONFeatureCollection<GeoJSONGeometry> {}
public typealias GeoJSON = GeoJSONFeatureCollection
// upstream:
// export interface GeoJSONCompressed extends GeoJSONFeatureCollection<GeoJSONGeometryCompressed> {
//     UTF8Encoding?: boolean;
//     UTF8Scale?: number;
// }
//   generic geometry arg (`GeoJSONGeometry` vs `GeoJSONGeometryCompressed`) erased; both feature
//   collections carry `features: [GeoJSONFeature]` whose `geometry` is the dynamic geometry bag below.
public struct GeoJSONCompressed {
    public var type: String                 // 'FeatureCollection'
    public var features: [GeoJSONFeature]
    public var UTF8Encoding: Bool?
    public var UTF8Scale: Double?
    public init(type: String = "FeatureCollection", features: [GeoJSONFeature] = [],
                UTF8Encoding: Bool? = nil, UTF8Scale: Double? = nil) {
        self.type = type
        self.features = features
        self.UTF8Encoding = UTF8Encoding
        self.UTF8Scale = UTF8Scale
    }
}

// upstream:
// interface GeoJSONFeatureCollection<G> {
//     type: 'FeatureCollection';
//     features: GeoJSONFeature<G>[];
// }
//   generic geometry arg `G` erased (the geometry union is a dynamic bag; see below).
public struct GeoJSONFeatureCollection {
    public var type: String                 // 'FeatureCollection'
    public var features: [GeoJSONFeature]
    public init(type: String = "FeatureCollection", features: [GeoJSONFeature] = []) {
        self.type = type
        self.features = features
    }
}

// upstream:
// interface GeoJSONFeature<G = GeoJSONGeometry> {
//     type: 'Feature';
//     id?: string | number;
//     properties: { name?: string; cp?: number[]; [key: string]: any; };
//     geometry: G;
// }
//   `id` (string | number) erased to `Any?`; `properties` is a dynamic bag ([String: Any]); `geometry` is
//   the dynamic geometry union (`GeoJSONGeometry`, modeled as `[String: Any]` — see the union note).
public struct GeoJSONFeature {
    public var type: String                 // 'Feature'
    public var id: Any?                      // string | number
    public var properties: [String: Any]    // { name?; cp?: number[]; [key: string]: any }
    public var geometry: [String: Any]      // GeoJSONGeometry (dynamic union bag)
    public init(type: String = "Feature", id: Any? = nil,
                properties: [String: Any] = [:], geometry: [String: Any] = [:]) {
        self.type = type
        self.id = id
        self.properties = properties
        self.geometry = geometry
    }
}

// upstream:
// type GeoJSONGeometry =
//     GeoJSONGeometryPoint | GeoJSONGeometryMultiPoint | GeoJSONGeometryLineString
//     | GeoJSONGeometryMultiLineString | GeoJSONGeometryPolygon | GeoJSONGeometryMultiPolygon;
//     // Do not support `GeometryCollection` yet.
// type GeoJSONGeometryCompressed =
//     GeoJSONGeometryPolygonCompressed | GeoJSONGeometryMultiPolygonCompressed
//     | GeoJSONGeometryLineStringCompressed | GeoJSONGeometryMultiLineStringCompressed;
//
// Swift has no anonymous tagged union. The GeoJSON geometry variants are discriminated by
//   their `type` string field at parse time (`parseGeoJson`, coord/geo/parseGeoJson.swift). Modeled as a dynamic
//   `[String: Any]` bag (the `GeoJSONFeature.geometry` field). The concrete per-variant shapes are kept
//   below as documented comments (coordinates typings preserved) so the future parser can switch on `type`:
//
//   interface GeoJSONGeometryPoint                 { type: 'Point';           coordinates: number[]; }          -> coordinates: [Double]
//   interface GeoJSONGeometryMultiPoint            { type: 'MultiPoint';      coordinates: number[][]; }        -> coordinates: [[Double]]
//   interface GeoJSONGeometryLineString            { type: 'LineString';      coordinates: number[][]; }        -> coordinates: [[Double]]
//   interface GeoJSONGeometryLineStringCompressed  { type: 'LineString';      coordinates: string; encodeOffsets: number[]; }
//   interface GeoJSONGeometryMultiLineString       { type: 'MultiLineString'; coordinates: number[][][]; }      -> coordinates: [[[Double]]]
//   interface GeoJSONGeometryMultiLineStringCompressed { type: 'MultiLineString'; coordinates: string[]; encodeOffsets: number[][]; }
//   interface GeoJSONGeometryPolygon               { type: 'Polygon';         coordinates: number[][][]; }      -> coordinates: [[[Double]]]
//   interface GeoJSONGeometryPolygonCompressed     { type: 'Polygon';         coordinates: string[]; encodeOffsets: number[][]; }
//   interface GeoJSONGeometryMultiPolygon          { type: 'MultiPolygon';    coordinates: number[][][][]; }    -> coordinates: [[[[Double]]]]
//   interface GeoJSONGeometryMultiPolygonCompressed{ type: 'MultiPolygon';    coordinates: string[][]; encodeOffsets: number[][][]; }
//   // interface GeoJSONGeometryGeometryCollection { type: 'GeometryCollection'; geometries: GeoJSONGeometry[]; } // not supported yet
//
// `GeoJSONGeometry` is ALREADY declared in coord/geo/Region.swift (forward-hoisted before
//   geoTypes landed) as a class-based protocol (`GeoJSONPolygonGeometry` / `GeoJSONLineStringGeometry`
//   conform) — that is the PARSED geometry contract used by `parseGeoJSON` / `GeoJSONRegion`, NOT the raw
//   GeoJSON JSON union above. To avoid a redeclaration collision, it is NOT re-emitted here. The raw JSON
//   union (this upstream type) is consumed as a dynamic `[String: Any]` bag (see `GeoJSONFeature.geometry`).
//   Consolidate ownership here once Region.swift is re-pointed. The compressed union is likewise a raw bag:
public typealias GeoJSONGeometryCompressed = [String: Any]

// upstream:
// export interface GeoResource {
//     readonly type: 'geoJSON' | 'geoSVG';
//     load(nameMap, nameProperty): { boundingRect; regions; regionsMap; };
// }
//   `type` is a string discriminant ('geoJSON' | 'geoSVG'). The `load` result triple (`GeoResourceLoadResult`)
//   is ALREADY declared in coord/geo/GeoJSONResource.swift (forward-hoisted before geoTypes landed; its
//   `regionsMap` is `HashMap<Region>`), so it is NOT re-emitted here — this protocol references it.
//   NOTE: signature matches the existing implementer `GeoJSONResource` (nameMap / nameProperty are Optional
//   there, per the upstream "can be null/undefined" doc-comments on `GeoJSONResource.load`).
public protocol GeoResource: AnyObject {
    var type: String { get }                // 'geoJSON' | 'geoSVG'
    func load(_ nameMap: NameMap?, _ nameProperty: String?) -> GeoResourceLoadResult
}

// upstream:
// export interface GeoSVGGraphicRoot extends Group { isGeoSVGGraphicRoot: boolean; }
//   SVG-map path deferred per the phase brief. Group is a `final class` (ZRenderKit); adding a
//   stored `isGeoSVGGraphicRoot` flag requires a subclass. Modeled as a protocol contract for now.
public protocol GeoSVGGraphicRoot: AnyObject {
    var isGeoSVGGraphicRoot: Bool { get set }
}

/**
 * Geo stream interface compatitable with d3-geo
 * See the API detail in https://github.com/d3/d3-geo#streams
 */
// upstream: export interface ProjectionStream { point; lineStart; lineEnd; polygonStart; polygonEnd; sphere; }
public protocol ProjectionStream: AnyObject {
    func point(_ x: Double, _ y: Double)
    func lineStart()
    func lineEnd()
    func polygonStart()
    func polygonEnd()
    /**
     * Not supported yet.
     */
    func sphere()
}

// upstream:
// export interface GeoProjection {
//     project(point: number[]): number[]
//     unproject(point: number[]): number[]
//     /**
//      * Projection stream compatitable to d3-geo projection stream.
//      *
//      * When rotate projection is used. It may have antimeridian artifacts.
//      * So we need to introduce the fule projection stream to do antimeridian clipping.
//      *
//      * project will be ignored if projectStream is given.
//      */
//     stream?(outStream: ProjectionStream): ProjectionStream
// }
//
// `GeoProjection` is ALREADY declared in coord/geo/Region.swift (forward-hoisted before geoTypes
//   landed) with a MINIMAL shape — `func project(_ point: [Double]) -> [Double]?` (Optional return; no
//   `unproject` / `stream`) — because `Region.updateBBoxFromPoints` needs it and relies on the null-point
//   guard. To avoid a redeclaration collision it is NOT re-emitted here. Consolidate the full upstream
//   contract (add `unproject` + the optional `stream(_:)` returning `ProjectionStream?`, and widen `project`
//   to non-optional per upstream) into THIS file once Region.swift's usage is reconciled.
