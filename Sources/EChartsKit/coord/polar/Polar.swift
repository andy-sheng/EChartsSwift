// Ported from echarts/src/coord/polar/Polar.ts — keep in sync with upstream
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
//   import RadiusAxis from './RadiusAxis';                             -> RadiusAxis (sibling, this phase).
//   import AngleAxis from './AngleAxis';                               -> AngleAxis (sibling, this phase).
//   import PolarModel, { COORD_SYS_TYPE_POLAR } from './PolarModel';   -> PolarModel + COORD_SYS_TYPE_POLAR.
//       coord/polar/PolarModel.swift is ported. This file references its
//       conventional public API: the constant `COORD_SYS_TYPE_POLAR = "polar"` and the class
//       `PolarModel` (a `ComponentModel` conforming to `CoordinateSystemHostModel`, so
//       `.coordinateSystem: CoordinateSystemMaster?`).
//   import { CoordinateSystem, CoordinateSystemMaster, CoordinateSystemClipArea } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See the CoordinateSystem-drop note on the class below.
//   import GlobalModel from '../../model/Global';                      -> GlobalModel.
//   import { ParsedModelFinder, ParsedModelFinderKnown } from '../../util/model';
//       -> ParsedModelFinder / ParsedModelFinderKnown (`[String: Any]`, util/modelUtil.swift).
//   import { ScaleDataValue } from '../../util/types';                 -> ScaleDataValue (util/types.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';                -> ExtensionAPI.

// upstream: export const polarDimensions = ['radius', 'angle'];
public let polarDimensions: [DimensionName] = ["radius", "angle"]

// upstream:
//   interface Polar { update(ecModel: GlobalModel, api: ExtensionAPI): void }
//   class Polar implements CoordinateSystem, CoordinateSystemMaster { ... }
//
//   Reference type → `public final class`. Conforms to `CoordinateSystemMaster` only (dropping the
//   `CoordinateSystem` conformance) for the same reason as Radar: Polar's `dataToPoint(data, clamp?,
//   out?)` / `pointToData(point, clamp?, out?)` carry polar-specific signatures that do NOT match the
//   `CoordinateSystem` protocol requirements (`dataToPoint(data, opt?)` / `pointToData(point, opt?)`),
//   and every use site holds the concrete `Polar` type (PolarModel.coordinateSystem `as? Polar`,
//   series `coordinateSystem as? Polar`). The polar-specific converters are therefore plain concrete
//   methods. `CoordinateSystemMaster` is what the coord-sys registry/axisPointer needs.
//
//   The `interface Polar { update(...) }` declaration merges an `update` method that upstream attaches
//   per-instance via `polarCreator` (`polar.update = updatePolarScale`). Swift can not rebind a method,
//   so the injected function is stored in `updateHook` (set by polarCreator) and the `update` override
//   below dispatches to it — this is the witness for `CoordinateSystemMaster.update`.
public final class Polar: CoordinateSystemMaster {

    // upstream: readonly name: string;
    public let name: String

    // upstream: readonly dimensions = polarDimensions;
    //   Upstream is readonly; `CoordinateSystemMaster.dimensions` requires `{ get set }`, so `var`.
    public var dimensions: [DimensionName] = polarDimensions

    // upstream: readonly type = COORD_SYS_TYPE_POLAR;
    public let type = COORD_SYS_TYPE_POLAR

    /**
     * x of polar center
     */
    // upstream: cx = 0;
    public var cx: Double = 0

    /**
     * y of polar center
     */
    // upstream: cy = 0;
    public var cy: Double = 0

    // upstream: private _radiusAxis = new RadiusAxis();
    private let _radiusAxis = RadiusAxis()

    // upstream: private _angleAxis = new AngleAxis();
    private let _angleAxis = AngleAxis()

    // upstream: axisPointerEnabled = true;
    //   Witnesses `CoordinateSystemMaster.axisPointerEnabled: Bool?` (optional in the protocol).
    public var axisPointerEnabled: Bool? = true

    // upstream: model: PolarModel;
    //   The protocol requirement is `ComponentModel?`. Swift does not allow a mutable property with the
    //   narrower `PolarModel!` type to witness it covariantly; doing so silently selected the protocol
    //   extension's nil-returning default whenever Polar was used as `CoordinateSystemMaster`, which made
    //   upstream axis-pointer collection skip every polar coordinate system. Keep the existential slot
    //   at the protocol's exact type, just as Grid/Single do; polarCreator still injects a PolarModel.
    public var model: ComponentModel?

    // upstream: boxCoordinateSystem?: CoordinateSystem  (CoordinateSystemMaster requirement).
    //   Not used by Polar; satisfies the protocol (upstream leaves it unset → undefined).
    public var boxCoordinateSystem: CoordinateSystem?

    // upstream: `polar.update = updatePolarScale;` (per-instance method injection in polarCreator).
    //   Stored as a function here; invoked by the `update` override below.
    public var updateHook: ((Polar, GlobalModel, ExtensionAPI) -> Void)?

    // upstream: interface Polar { update(ecModel, api): void }  (implementation injected as above).
    //   Witnesses `CoordinateSystemMaster.update`; dispatches to the injected `updateHook`.
    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.updateHook?(self, ecModel, api)
    }

    // upstream: constructor(name: string) {
    //     this.name = name || '';
    //     this._radiusAxis.polar = this._angleAxis.polar = this;
    // }
    public init(_ name: String?) {
        self.name = name ?? ""  // upstream: name || ''

        self._radiusAxis.polar = self
        self._angleAxis.polar = self
    }

    /**
     * If contain coord
     */
    // upstream: containPoint(point: number[]) {
    //     const coord = this.pointToCoord(point);
    //     return this._radiusAxis.contain(coord[0]) && this._angleAxis.contain(coord[1]);
    // }
    public func containPoint(_ point: [Double]) -> Bool {
        let coord = self.pointToCoord(point)
        return self._radiusAxis.contain(coord[0])
            && self._angleAxis.contain(coord[1])
    }

    /**
     * If contain data
     */
    // upstream: containData(data: number[]) {
    //     return this._radiusAxis.containData(data[0]) && this._angleAxis.containData(data[1]);
    // }
    public func containData(_ data: [Double]) -> Bool {
        return self._radiusAxis.containData(data[0])
            && self._angleAxis.containData(data[1])
    }

    // upstream: getAxis(dim: 'radius' | 'angle') {
    //     const key = ('_' + dim + 'Axis') as '_radiusAxis' | '_angleAxis';
    //     return this[key];
    // }
    public func getAxis(_ dim: DimensionName) -> Axis {
        return dim == "radius" ? self._radiusAxis : self._angleAxis
    }

    // upstream: getAxes() { return [this._radiusAxis, this._angleAxis]; }
    //   Witnesses `CoordinateSystemMaster.getAxes() -> [Axis]?` (optional in the protocol; never nil here).
    public func getAxes() -> [Axis]? {
        return [self._radiusAxis, self._angleAxis]
    }

    /**
     * Get axes by type of scale
     */
    // upstream: getAxesByScale(scaleType: 'ordinal' | 'interval' | 'time' | 'log') {
    //     const axes = [];
    //     const angleAxis = this._angleAxis;
    //     const radiusAxis = this._radiusAxis;
    //     angleAxis.scale.type === scaleType && axes.push(angleAxis);
    //     radiusAxis.scale.type === scaleType && axes.push(radiusAxis);
    //     return axes;
    // }
    public func getAxesByScale(_ scaleType: String) -> [Axis] {
        var axes: [Axis] = []
        let angleAxis = self._angleAxis
        let radiusAxis = self._radiusAxis
        // upstream: `axis.scale.type === scaleType`. `Scale.type` is `AxisScaleType` (= String);
        //   the IUO auto-promotes to Optional here, so a not-yet-injected (nil) scale type compares
        //   false, matching JS `undefined === scaleType`.
        if angleAxis.scale.type == scaleType { axes.append(angleAxis) }
        if radiusAxis.scale.type == scaleType { axes.append(radiusAxis) }
        return axes
    }

    // upstream: getAngleAxis() { return this._angleAxis; }
    public func getAngleAxis() -> AngleAxis {
        return self._angleAxis
    }

    // upstream: getRadiusAxis() { return this._radiusAxis; }
    public func getRadiusAxis() -> RadiusAxis {
        return self._radiusAxis
    }

    // upstream: getOtherAxis(axis: AngleAxis | RadiusAxis): AngleAxis | RadiusAxis {
    //     const angleAxis = this._angleAxis;
    //     return axis === angleAxis ? this._radiusAxis : angleAxis;
    // }
    public func getOtherAxis(_ axis: Axis) -> Axis {
        let angleAxis = self._angleAxis
        return axis === angleAxis ? self._radiusAxis : angleAxis
    }

    /**
     * Base axis will be used on stacking.
     */
    // upstream: getBaseAxis() {
    //     return this.getAxesByScale('ordinal')[0] || this.getAxesByScale('time')[0] || this.getAngleAxis();
    // }
    public func getBaseAxis() -> Axis {
        return self.getAxesByScale("ordinal").first
            ?? self.getAxesByScale("time").first
            ?? self.getAngleAxis()
    }

    // upstream: getTooltipAxes(dim: 'radius' | 'angle' | 'auto') {
    //     const baseAxis = (dim != null && dim !== 'auto') ? this.getAxis(dim) : this.getBaseAxis();
    //     return { baseAxes: [baseAxis], otherAxes: [this.getOtherAxis(baseAxis)] };
    // }
    //   Witnesses `CoordinateSystemMaster.getTooltipAxes(_:) -> (…)?` (optional; never nil here). `dim`
    //   is a non-optional `DimensionName`, so upstream's `dim != null` is always true.
    public func getTooltipAxes(_ dim: DimensionName) -> (baseAxes: [Axis], otherAxes: [Axis])? {
        let baseAxis = (dim != "auto") ? self.getAxis(dim) : self.getBaseAxis()
        return (
            baseAxes: [baseAxis],
            otherAxes: [self.getOtherAxis(baseAxis)]
        )
    }

    /**
     * Convert a single data item to (x, y) point.
     * Parameter data is an array which the first element is radius and the second is angle
     */
    // upstream: dataToPoint(data: ScaleDataValue[], clamp?: boolean, out?: number[]) {
    //     return this.coordToPoint([
    //         // Must be the same order as polarDimensions
    //         this._radiusAxis.dataToRadius(data[0], clamp),
    //         this._angleAxis.dataToAngle(data[1], clamp)
    //     ], out);
    // }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func dataToPoint(_ data: [ScaleDataValue], _ clamp: Bool? = nil) -> [Double] {
        return self.coordToPoint([
            // Must be the same order as polarDimensions
            self._radiusAxis.dataToRadius(data[0], clamp),
            self._angleAxis.dataToAngle(data[1], clamp)
        ])
    }

    /**
     * Convert a (x, y) point to data
     */
    // upstream: pointToData(point: number[], clamp?: boolean, out?: number[]) {
    //     out = out || [];
    //     const coord = this.pointToCoord(point);
    //     // Must be the same order as polarDimensions
    //     out[0] = this._radiusAxis.radiusToData(coord[0], clamp);
    //     out[1] = this._angleAxis.angleToData(coord[1], clamp);
    //     return out;
    // }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> [Double] {
        let coord = self.pointToCoord(point)
        // Must be the same order as polarDimensions
        return [
            self._radiusAxis.radiusToData(coord[0], clamp),
            self._angleAxis.angleToData(coord[1], clamp)
        ]
    }

    /**
     * Convert a (x, y) point to (radius, angle) coord
     */
    // upstream: pointToCoord(point: number[]) { ... }
    public func pointToCoord(_ point: [Double]) -> [Double] {
        var dx = point[0] - self.cx
        var dy = point[1] - self.cy
        let angleAxis = self.getAngleAxis()
        let extent = angleAxis.getExtent()
        var minAngle = Swift.min(extent[0], extent[1])
        var maxAngle = Swift.max(extent[0], extent[1])
        // Fix fixed extent in polarCreator
        // FIXME
        // upstream: angleAxis.inverse ? (minAngle = maxAngle - 360) : (maxAngle = minAngle + 360);
        if angleAxis.inverse {
            minAngle = maxAngle - 360
        }
        else {
            maxAngle = minAngle + 360
        }

        let radius = (dx * dx + dy * dy).squareRoot()
        dx /= radius
        dy /= radius

        var radian = atan2(-dy, dx) / Double.pi * 180

        // move to angleExtent
        let dir: Double = radian < minAngle ? 1 : -1
        while radian < minAngle || radian > maxAngle {
            radian += dir * 360
        }

        return [radius, radian]
    }

    /**
     * Convert a (radius, angle) coord to (x, y) point
     */
    // upstream: coordToPoint(coord: number[], out?: number[]) {
    //     out = out || [];
    //     const radius = coord[0];
    //     const radian = coord[1] / 180 * Math.PI;
    //     out[0] = Math.cos(radian) * radius + this.cx;
    //     // Inverse the y
    //     out[1] = -Math.sin(radian) * radius + this.cy;
    //     return out;
    // }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func coordToPoint(_ coord: [Double]) -> [Double] {
        let radius = coord[0]
        let radian = coord[1] / 180 * Double.pi
        let x = cos(radian) * radius + self.cx
        // Inverse the y
        let y = -sin(radian) * radius + self.cy
        return [x, y]
    }

    /**
     * Get ring area of cartesian.
     * Area will have a contain function to determine if a point is in the coordinate system.
     */
    // upstream: getArea(): PolarArea { ... }
    public func getArea() -> PolarArea {

        let angleAxis = self.getAngleAxis()
        let radiusAxis = self.getRadiusAxis()

        // upstream: const radiusExtent = radiusAxis.getExtent().slice();
        //           radiusExtent[0] > radiusExtent[1] && radiusExtent.reverse();
        var radiusExtent = radiusAxis.getExtent()
        if radiusExtent[0] > radiusExtent[1] { radiusExtent.reverse() }
        let angleExtent = angleAxis.getExtent()

        let RADIAN = Double.pi / 180
        // upstream: const EPSILON = 1e-4;  (used by PolarArea.contain — see PolarArea below).
        return PolarArea(
            cx: self.cx,
            cy: self.cy,
            r0: radiusExtent[0],
            r: radiusExtent[1],
            startAngle: -angleExtent[0] * RADIAN,
            endAngle: -angleExtent[1] * RADIAN,
            clockwise: angleAxis.inverse,
            // As the bounding box
            x: self.cx - radiusExtent[1],
            y: self.cy - radiusExtent[1],
            width: radiusExtent[1] * 2,
            height: radiusExtent[1] * 2
        )
    }

    // upstream: convertToPixel(ecModel: GlobalModel, finder: ParsedModelFinder, value: ScaleDataValue[]) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? this.dataToPoint(value) : null;
    // }
    //   Witnesses `CoordinateSystemMaster.convertToPixel`; `value: CoordinateSystemDataCoord` erased to
    //   `Any` → narrowed back to `[ScaleDataValue]`.
    public func convertToPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? self.dataToPoint((value as? [ScaleDataValue]) ?? []) : nil
    }

    // upstream: convertFromPixel(ecModel: GlobalModel, finder: ParsedModelFinder, pixel: number[]) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? this.pointToData(pixel) : null;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ pixelValue: [Double],
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? self.pointToData(pixelValue) : nil
    }
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown) {
//     const seriesModel = finder.seriesModel;
//     const polarModel = finder.polarModel as PolarModel;
//     return polarModel && polarModel.coordinateSystem
//         || seriesModel && seriesModel.coordinateSystem as Polar;
// }
//   `finder` is `[String: Any]` → field access via subscript. note: references sibling `PolarModel`.
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> Polar? {
    let seriesModel = finder["seriesModel"] as? SeriesModel
    let polarModel = finder["polarModel"] as? PolarModel
    // polarModel && polarModel.coordinateSystem || seriesModel && seriesModel.coordinateSystem
    if let polarModel = polarModel, let cs = polarModel.coordinateSystem {
        return cs as? Polar
    }
    return seriesModel?.coordinateSystem as? Polar
}

// upstream: interface PolarArea extends CoordinateSystemClipArea {
//     cx: number; cy: number; r0: number; r: number
//     startAngle: number; endAngle: number; clockwise: boolean
// }
//   The object literal returned by `getArea` (with an inline `contain`) → `final class` conforming to
//   `CoordinateSystemClipArea` (its `contain` closes over the area's own cx/cy/r/r0, so it must be an
//   instance method, not the polar's).
public final class PolarArea: CoordinateSystemClipArea {
    public var cx: Double
    public var cy: Double
    public var r0: Double
    public var r: Double
    public var startAngle: Double
    public var endAngle: Double
    public var clockwise: Bool
    // As the bounding box (CoordinateSystemClipArea requirements)
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        cx: Double, cy: Double, r0: Double, r: Double,
        startAngle: Double, endAngle: Double, clockwise: Bool,
        x: Double, y: Double, width: Double, height: Double
    ) {
        self.cx = cx
        self.cy = cy
        self.r0 = r0
        self.r = r
        self.startAngle = startAngle
        self.endAngle = endAngle
        self.clockwise = clockwise
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    // upstream: contain(x: number, y: number) { ... }
    public func contain(_ x: Double, _ y: Double) -> Bool {
        // upstream: const EPSILON = 1e-4;  (captured in the object literal's closure scope).
        let EPSILON = 1e-4
        // It's a ring shape.
        // Start angle and end angle don't matter
        let dx = x - self.cx
        let dy = y - self.cy
        let d2 = dx * dx + dy * dy
        let r = self.r
        let r0 = self.r0

        // minus a tiny value 1e-4 in double side to avoid being clipped unexpectedly
        // r == r0 contain nothing
        return r != r0 && (d2 - EPSILON) <= r * r && (d2 + EPSILON) >= r0 * r0
    }
}

// export default Polar;  -> `public final class Polar` above.
