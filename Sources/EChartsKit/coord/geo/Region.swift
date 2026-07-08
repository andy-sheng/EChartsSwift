// Ported from echarts/src/coord/geo/Region.ts — keep in sync with upstream
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
//   import BoundingRect from 'zrender/src/core/BoundingRect';           -> BoundingRect (ZRenderKit).
//   import * as vec2 from 'zrender/src/core/vector';                    -> `vector.*` (ZRenderKit); VectorArray = SIMD2<Double>.
//   import * as polygonContain from 'zrender/src/contain/polygon';      -> `polygon.*` (ZRenderKit).
//   import { GeoJSON, GeoProjection, GeoSVGGraphicRoot } from './geoTypes';
//                                                                       -> geoTypes not yet ported; see notes below.
//   import * as matrix from 'zrender/src/core/matrix';                  -> `matrix.*` (ZRenderKit).
//   import type Element from 'zrender/src/Element';                     -> Element (ZRenderKit).
//   import { each } from 'zrender/src/core/util';                       -> plain Swift loops (comment: upstream each).
//   import type { RegionOption } from './GeoModel';                     -> represented via [String: Any] properties bag.

// PORT-TODO: point/ring representation. Upstream point arrays are `number[]` (a [lng, lat]
// position). Ported as `[Double]` (ring = `[[Double]]`, rings = `[[[Double]]]`) to match the
// downstream consumer (GeoView). The zrender math helpers (vector.*, polygon.contain) take
// VectorArray = SIMD2<Double>, so points are converted at those call sites.

// PORT-TODO: geoTypes.GeoProjection not yet ported. Minimal shape used by getBoundingRect /
// updateBBoxFromPoints. `project` may return a null point (see updateBBoxFromPoints guard),
// hence the Optional return.
public protocol GeoProjection: AnyObject {
    func project(_ point: [Double]) -> [Double]?
    // upstream: unproject(point) — inverse of project; may return a null point.
    func unproject(_ point: [Double]) -> [Double]?
}

// const TMP_TRANSFORM = [] as number[];
// PORT-TODO: matrix scratch used only by GeoSVGRegion.calcCenter (deferred SVG-map path).
private let TMP_TRANSFORM: MatrixArray = []

// was: transformPoints(points: number[][], transform) — mutates each point in place.
// vector.applyTransform is value-returning (CONVENTIONS §3), so reassign each element.
private func transformPoints(_ points: inout [[Double]], _ transform: MatrixArray) {
    for p in 0..<points.count {
        let v = vector.applyTransform(VectorArray(points[p][0], points[p][1]), transform)
        points[p] = [v[0], v[1]]
    }
}
// was: updateBBoxFromPoints(points, min, max, projection) — mutates min/max in place.
// min/max are distinct from each point `p`, so `inout` is safe here (no aliasing hazard).
private func updateBBoxFromPoints(
    _ points: [[Double]],
    _ min: inout VectorArray,
    _ max: inout VectorArray,
    _ projection: GeoProjection?
) {
    for i in 0..<points.count {
        var p: [Double]? = points[i]
        if let projection = projection {
            // projection may return null point.
            p = projection.project(points[i])
        }
        if let p = p, p[0].isFinite && p[1].isFinite {
            let pv = VectorArray(p[0], p[1])
            min = vector.min(min, pv)
            max = vector.max(max, pv)
        }
    }
}

private func centroid(_ points: [[Double]]) -> [Double] {
    var signedArea: Double = 0
    var cx: Double = 0
    var cy: Double = 0
    let len = points.count
    var x0 = points[len - 1][0]
    var y0 = points[len - 1][1]
    // Polygon should been closed.
    for i in 0..<len {
        let x1 = points[i][0]
        let y1 = points[i][1]
        let a = x0 * y1 - x1 * y0
        signedArea += a
        cx += (x0 + x1) * a
        cy += (y0 + y1) * a
        x0 = x1
        y0 = y1
    }

    // was: signedArea ? [...] : [points[0][0] || 0, points[0][1] || 0]
    if signedArea != 0 {
        return [cx / signedArea / 3, cy / signedArea / 3, signedArea]
    }
    else {
        let px = points[0][0]
        let py = points[0][1]
        return [px != 0 && !px.isNaN ? px : 0, py != 0 && !py.isNaN ? py : 0]
    }
}

// PORT-TODO: upstream `abstract class Region`. Swift has no abstract classes; `calcCenter`
// is a subclass responsibility (fatalError fallback), `type` is an overridable computed prop.
open class Region {

    public let name: String
    // readonly type: 'geoJSON' | 'geoSVG';  (subclasses override)
    open var type: String { fatalError("Region.type is abstract") }

    // upstream: protected  (Swift has no `protected`; use internal)
    internal var _center: [Double]?
    internal var _rect: BoundingRect?

    public init(_ name: String) {
        self.name = name
    }

    public func setCenter(_ center: [Double]) {
        self._center = center
    }

    /**
     * Get center point in data unit. That is,
     * for GeoJSONRegion, the unit is lat/lng,
     * for GeoSVGRegion, the unit is SVG local coord.
     */
    public func getCenter() -> [Double] {
        var center = self._center
        if center == nil {
            // In most cases there are no need to calculate this center.
            // So calculate only when called.
            center = self.calcCenter()
            self._center = center
        }
        return center!
    }

    open func calcCenter() -> [Double] {
        fatalError("Region.calcCenter is abstract")
    }
}

// PORT-TODO: geoTypes union `GeoJSONRegion['geometries']` — a common contract so a
// geometries list can hold both polygon and linestring geometries.
public protocol GeoJSONGeometry: AnyObject {
    var type: String { get }
}

public final class GeoJSONPolygonGeometry: GeoJSONGeometry {
    public let type = "polygon"
    public var exterior: [[Double]]
    public var interiors: [[[Double]]]?
    public init(_ exterior: [[Double]], _ interiors: [[[Double]]]?) {
        self.exterior = exterior
        self.interiors = interiors
    }
}
public final class GeoJSONLineStringGeometry: GeoJSONGeometry {
    public let type = "linestring"
    public var points: [[[Double]]]
    public init(_ points: [[[Double]]]) {
        self.points = points
    }
}
public final class GeoJSONRegion: Region {

    public override var type: String { "geoJSON" }

    public let geometries: [GeoJSONGeometry]

    // Injected outside.
    // PORT-TODO: upstream `properties: GeoJSON['features'][0]['properties'] & { echartsStyle? }`.
    // Represented as a dynamic bag ([String: Any]).
    public var properties: [String: Any] = [:]

    public init(
        _ name: String,
        _ geometries: [GeoJSONGeometry],
        _ cp: [Double]?
    ) {
        self.geometries = geometries
        super.init(name)

        // this._center = cp && [cp[0], cp[1]];
        self._center = cp != nil ? [cp![0], cp![1]] : nil
    }

    public override func calcCenter() -> [Double] {
        let geometries = self.geometries
        var largestGeo: GeoJSONPolygonGeometry?
        var largestGeoSize: Double = 0
        for i in 0..<geometries.count {
            // const geo = geometries[i] as GeoJSONPolygonGeometry;
            let geoPolygon = geometries[i] as? GeoJSONPolygonGeometry
            let exterior = geoPolygon?.exterior
            // Simple trick to use points count instead of polygon area as region size.
            // Ignore linestring
            let size = exterior != nil ? Double(exterior!.count) : 0
            if size > largestGeoSize {
                largestGeo = geoPolygon
                largestGeoSize = size
            }
        }
        if let largestGeo = largestGeo {
            return centroid(largestGeo.exterior)
        }

        // from bounding rect by default.
        let rect = self.getBoundingRect()
        return [
            rect.x + rect.width / 2,
            rect.y + rect.height / 2
        ]
    }

    @discardableResult
    public func getBoundingRect(_ projection: GeoProjection? = nil) -> BoundingRect {
        var rect = self._rect
        // Always recalculate if using projection.
        if let rect = rect, projection == nil {
            return rect
        }

        var min = VectorArray(Double.infinity, Double.infinity)
        var max = VectorArray(-Double.infinity, -Double.infinity)
        let geometries = self.geometries

        // upstream: each(geometries, geo => { ... })
        for geo in geometries {
            if geo.type == "polygon" {
                let geo = geo as! GeoJSONPolygonGeometry
                // Doesn't consider hole
                updateBBoxFromPoints(geo.exterior, &min, &max, projection)
            }
            else {
                let geo = geo as! GeoJSONLineStringGeometry
                for points in geo.points {
                    updateBBoxFromPoints(points, &min, &max, projection)
                }
            }
        }
        // Normalie invalid bounding.
        if !(min[0].isFinite && min[1].isFinite && max[0].isFinite && max[1].isFinite) {
            min[0] = 0; min[1] = 0; max[0] = 0; max[1] = 0
        }
        rect = BoundingRect(
            min[0], min[1], max[0] - min[0], max[1] - min[1]
        )
        if projection == nil {
            self._rect = rect
        }

        return rect!
    }

    public func contain(_ coord: [Double]) -> Bool {
        let rect = self.getBoundingRect()
        let geometries = self.geometries
        if !rect.contain(coord[0], coord[1]) {
            return false
        }
        loopGeo: for i in 0..<geometries.count {
            let geo = geometries[i]
            // Only support polygon.
            if geo.type != "polygon" {
                continue
            }
            let polyGeo = geo as! GeoJSONPolygonGeometry
            let exterior = polyGeo.exterior
            let interiors = polyGeo.interiors
            if polygon.contain(exterior.map { VectorArray($0[0], $0[1]) }, coord[0], coord[1]) {
                // Not in the region if point is in the hole.
                for k in 0..<(interiors != nil ? interiors!.count : 0) {
                    if polygon.contain(interiors![k].map { VectorArray($0[0], $0[1]) }, coord[0], coord[1]) {
                        continue loopGeo
                    }
                }
                return true
            }
        }
        return false
    }

    /**
     * Transform the raw coords to target bounding.
     * @param x
     * @param y
     * @param width
     * @param height
     */
    public func transformTo(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        var rect = self.getBoundingRect()
        let aspect = rect.width / rect.height
        var width = width
        var height = height
        if width == 0 {
            width = aspect * height
        }
        else if height == 0 {
            height = width / aspect
        }
        let target = BoundingRect(x, y, width, height)
        let transform = rect.calculateTransform(target)
        let geometries = self.geometries
        for i in 0..<geometries.count {
            let geo = geometries[i]
            if geo.type == "polygon" {
                let geo = geo as! GeoJSONPolygonGeometry
                transformPoints(&geo.exterior, transform)
                // upstream: each(geo.interiors, interior => transformPoints(interior, transform));
                if geo.interiors != nil {
                    for interiorIdx in 0..<geo.interiors!.count {
                        transformPoints(&geo.interiors![interiorIdx], transform)
                    }
                }
            }
            else {
                let geo = geo as! GeoJSONLineStringGeometry
                for pointsIdx in 0..<geo.points.count {
                    transformPoints(&geo.points[pointsIdx], transform)
                }
            }
        }
        rect = self._rect!
        rect.copy(target)
        // Update center
        self._center = [
            rect.x + rect.width / 2,
            rect.y + rect.height / 2
        ]
    }

    public func cloneShallow(_ name: String?) -> GeoJSONRegion {
        // name == null && (name = this.name);
        let name = name ?? self.name
        let newRegion = GeoJSONRegion(name, self.geometries, self._center)
        newRegion._rect = self._rect
        // PORT-TODO: upstream `newRegion.transformTo = null;` (avoid to be called). Swift methods
        // cannot be nulled; guard with a flag instead.
        newRegion._transformToDisabled = true
        return newRegion
    }

    // PORT-TODO: see cloneShallow — replaces upstream `transformTo = null`.
    internal var _transformToDisabled = false
}

public final class GeoSVGRegion: Region {

    public override var type: String { "geoSVG" }

    // Can only be used to calculate, but not be modified.
    // Because this el may not belong to this view,
    // but been displaying on some other view.
    private let _elOnlyForCalculate: Element

    public init(
        _ name: String,
        _ elOnlyForCalculate: Element
    ) {
        self._elOnlyForCalculate = elOnlyForCalculate
        super.init(name)
    }

    public override func calcCenter() -> [Double] {
        let el = self._elOnlyForCalculate
        // Upstream walks up the parent chain multiplying local transforms until reaching the
        //   GeoSVGGraphicRoot, inverts the accumulated matrix, and applies it to the bounding-rect
        //   center — yielding the center in the ROOT (data-unit / SVG-local) coord.
        guard let rect = el.getBoundingRect() else {
            return [0, 0]
        }
        var center = VectorArray(
            rect.x + rect.width / 2,
            rect.y + rect.height / 2
        )

        // const mat = matrix.identity(TMP_TRANSFORM);
        var mat = matrix.identity()
        _ = TMP_TRANSFORM   // provenance: upstream reuses this scratch buffer.

        var target: Transformable? = el
        // while (target && !(target as GeoSVGGraphicRoot).isGeoSVGGraphicRoot) { ... }
        while let t = target, !((t as? GeoSVGGraphicRoot)?.isGeoSVGGraphicRoot ?? false) {
            // matrix.mul(mat, target.getLocalTransform(), mat);  -> out = localTransform * mat
            mat = matrix.mul(t.getLocalTransform(), mat)
            target = t.parent
        }

        // matrix.invert(mat, mat);
        if let inv = matrix.invert(mat) {
            mat = inv
        }

        // vec2.applyTransform(center, center, mat);
        center = vector.applyTransform(center, mat)

        return [center[0], center[1]]
    }

}
