// Ported from echarts/src/coord/cartesian/Cartesian2D.ts — keep in sync with upstream
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
import ZRenderKit  // upstream: BoundingRect, matrix.invert, vector.applyTransform (zrender/src/core/*)
// import BoundingRect from 'zrender/src/core/BoundingRect';           -> BoundingRect (ZRenderKit)
// import Cartesian from './Cartesian';                                -> Cartesian (coord/cartesian/Cartesian.swift)
// import { ScaleDataValue } from '../../util/types';                  -> ScaleDataValue (util/types.swift)
// import Axis2D from './Axis2D';                                      -> Axis2D (coord/cartesian/Axis2D.swift)
// import { CoordinateSystem } from '../CoordinateSystem';             -> CoordinateSystem (coord/CoordinateSystem.swift)
// import GridModel, { COORD_SYS_TYPE_CARTESIAN_2D } from './GridModel';
//   -> GridModel / COORD_SYS_TYPE_CARTESIAN_2D (coord/cartesian/GridModel.swift, same module)
// import Grid from './Grid';                                          -> Grid (coord/cartesian/Grid.swift, sibling this tier)
// import Scale from '../../scale/Scale';                              -> Scale (scale/Scale.swift)
// import { invert } from 'zrender/src/core/matrix';                   -> matrix.invert (ZRenderKit)
// import { applyTransform } from 'zrender/src/core/vector';           -> vector.applyTransform (ZRenderKit)
// import { getScaleExtentForMappingUnsafe } from '../../scale/scaleMapper';
//   -> getScaleExtentForMappingUnsafe (scale/scaleMapper.swift)
// import { hasBreaks } from '../../scale/break';                      -> hasBreaks (scale/break.swift)


// upstream: export const cartesian2DDimensions = ['x', 'y'];
// note (CONVENTIONS §2): module-level exported const kept as a top-level `public let`, matching the
//   sibling `COORD_SYS_TYPE_CARTESIAN_2D` in GridModel.swift (not wrapped in a caseless-enum namespace).
public let cartesian2DDimensions: [DimensionName] = ["x", "y"]

// upstream: function canCalculateAffineTransform(scale: Scale): boolean
//   Module-private helper -> `fileprivate func` (CONVENTIONS §2).
fileprivate func canCalculateAffineTransform(_ scale: Scale) -> Bool {
    // Only supported on linear space.
    return (scale.type == "interval" || scale.type == "time") && !hasBreaks(scale)
}

// upstream: `interface Cartesian2DArea extends BoundingRect {}` — a BoundingRect returned by `getArea`.
public typealias Cartesian2DArea = BoundingRect

// upstream: BoundingRect is the concrete return of `getArea`, which the `CoordinateSystem` interface
//   types as `CoordinateSystemClipArea`. BoundingRect already exposes `x/y/width/height/contain`, so the
//   conformance is empty. Retroactive conformance is declared here (nearest user); move to ZRenderKit
//   or a shared coord file if another coord system needs it.
extension BoundingRect: CoordinateSystemClipArea {}

// upstream: class Cartesian2D extends Cartesian<Axis2D> implements CoordinateSystem
open class Cartesian2D: Cartesian<Axis2D>, CoordinateSystem {

    // upstream: readonly type = COORD_SYS_TYPE_CARTESIAN_2D;
    //   Overrides the get-only computed `type` on the `Cartesian` base (TS field re-declaration).
    public override var type: String { COORD_SYS_TYPE_CARTESIAN_2D }

    // upstream: readonly dimensions = cartesian2DDimensions;
    // `CoordinateSystem.dimensions` is `{ get set }`, so this is a `var` (not the upstream
    //   `readonly`); initialized to the shared `cartesian2DDimensions`.
    public var dimensions: [DimensionName] = cartesian2DDimensions

    // upstream: master: Grid;  (injected outside; a `CoordinateSystemMaster`)
    // concrete upstream type is `Grid`; stored as the protocol type `CoordinateSystemMaster?`
    //   to satisfy `CoordinateSystem.master` cleanly. Narrow via `as? Grid` at call sites.
    public var master: CoordinateSystemMaster?

    // upstream: model: GridModel;  (injected outside; a `ComponentModel`)
    // concrete upstream type is `GridModel`; stored as the protocol type `ComponentModel?`
    //   to satisfy `CoordinateSystem.model` cleanly. Narrow via `as? GridModel` at call sites.
    public var model: ComponentModel?

    private var _transform: [Double]?
    private var _invTransform: [Double]?

    // upstream: constructor is inherited from Cartesian (constructor(name: string)).
    public override init(_ name: String?) {
        super.init(name)
    }

    /**
     * Calculate an affine transform matrix if two axes are time or value.
     * It's mainly for accelartion on the large time series data.
     */
    public func calcAffineTransform() {
        // upstream: this._transform = this._invTransform = null;
        self._transform = nil
        self._invTransform = nil

        let xAxisScale = self.getAxis("x")!.scale
        let yAxisScale = self.getAxis("y")!.scale

        if !canCalculateAffineTransform(xAxisScale) || !canCalculateAffineTransform(yAxisScale) {
            return
        }

        let xScaleExtent = getScaleExtentForMappingUnsafe(xAxisScale, nil)
        let yScaleExtent = getScaleExtentForMappingUnsafe(yAxisScale, nil)

        let start = self.dataToPoint([xScaleExtent[0], yScaleExtent[0]])
        let end = self.dataToPoint([xScaleExtent[1], yScaleExtent[1]])

        let xScaleSpan = xScaleExtent[1] - xScaleExtent[0]
        let yScaleSpan = yScaleExtent[1] - yScaleExtent[0]

        // upstream: if (!xScaleSpan || !yScaleSpan)
        if xScaleSpan == 0 || yScaleSpan == 0 {
            return
        }
        // Accelerate data to point calculation on the special large time series data.
        let scaleX = (end[0] - start[0]) / xScaleSpan
        let scaleY = (end[1] - start[1]) / yScaleSpan
        let translateX = start[0] - xScaleExtent[0] * scaleX
        let translateY = start[1] - yScaleExtent[0] * scaleY

        let m: [Double] = [scaleX, 0, 0, scaleY, translateX, translateY]
        self._transform = m
        // upstream: this._invTransform = invert([], m);
        self._invTransform = matrix.invert(m)
    }

    /**
     * Base axis will be used on stacking and series such as 'bar', 'pictorialBar', etc.
     */
    // upstream signature: getBaseAxis(): Axis2D. Covariant return (Axis2D <: Axis) also satisfies
    //   `CoordinateSystem.getBaseAxis(): Axis`.
    public func getBaseAxis() -> Axis2D {
        // FIXME:
        //  (1) We should allow series (e.g., bar) to specify a base axis when
        //      both axes are type "value", rather than force to xAxis or angleAxis.
        //      NOTE: At present BoxplotSeries has its own overide `getBaseAxis`.
        //      `CoordinateSystem['getBaseAxis']` probably should not exist, since it
        //      may introduce inconsistency with `Series['getBaseAxis']`.
        //  (2) "base axis" info is required in "createSeriesData" stage for "stack",
        //      (see `dataStackHelper.ts` for details). Currently it is hard coded there.
        return self.getAxesByScale("ordinal").first
            ?? self.getAxesByScale("time").first
            ?? self.getAxis("x")!
    }

    // upstream: containPoint(point: number[]): boolean
    public func containPoint(_ point: [Double]) -> Bool {
        let axisX = self.getAxis("x")!
        let axisY = self.getAxis("y")!
        return axisX.contain(axisX.toLocalCoord(point[0]))
            && axisY.contain(axisY.toLocalCoord(point[1]))
    }

    // upstream: containData(data: ScaleDataValue[]): boolean
    public func containData(_ data: [ScaleDataValue]) -> Bool {
        return self.getAxis("x")!.containData(data[0])
            && self.getAxis("y")!.containData(data[1])
    }

    // upstream: containZone(data1: ScaleDataValue[], data2: ScaleDataValue[]): boolean
    public func containZone(_ data1: [ScaleDataValue], _ data2: [ScaleDataValue]) -> Bool {
        let zoneDiag1 = self.dataToPoint(data1)
        let zoneDiag2 = self.dataToPoint(data2)
        let area = self.getArea()
        let zone = BoundingRect(
            zoneDiag1[0],
            zoneDiag1[1],
            zoneDiag2[0] - zoneDiag1[0],
            zoneDiag2[1] - zoneDiag1[1])
        return area.intersect(zone)
    }

    // upstream: dataToPoint(data: ScaleDataValue[], clamp?: boolean, out?: number[]): number[]
    // this is the `CoordinateSystem.dataToPoint` witness — its signature follows the ported
    //   protocol (`data: CoordinateSystemDataCoord`, `opt: Any?` = the upstream `clamp`, `out` dropped
    //   per CONVENTIONS §3). `data` is force-cast to `[ScaleDataValue]` (upstream always passes an array).
    public func dataToPoint(_ data: CoordinateSystemDataCoord, _ opt: Any? = nil) -> [Double] {
        let data = data as! [ScaleDataValue]
        let clamp = opt as? Bool
        var out: [Double] = [0, 0]
        let xVal = data[0]
        let yVal = data[1]
        // [CAVEAT]: Do not add time consuming operation within and before fast path.
        // Fast path.
        if let transform = self._transform,
            // It's supported that if data is like `[Inifity, 123]`, where only Y pixel calculated.
            // upstream: xVal != null && isFinite(xVal as number) && yVal != null && isFinite(yVal as number)
            let xNum = cartesian2DFiniteNumber(xVal),
            let yNum = cartesian2DFiniteNumber(yVal) {
            let r = vector.applyTransform(VectorArray(xNum, yNum), transform)
            return [r[0], r[1]]
        }

        let xAxis = self.getAxis("x")!
        let yAxis = self.getAxis("y")!
        out[0] = xAxis.toGlobalCoord(xAxis.dataToCoord(xVal, clamp))
        out[1] = yAxis.toGlobalCoord(yAxis.dataToCoord(yVal, clamp))
        return out
    }

    // Swift specialization of the same dataToPoint algorithm for numeric layout buffers.
    // A value-returning VectorArray avoids boxing a two-element [Any] and allocating an output
    // Array for every datum. The protocol entry point above still accepts category/date strings.
    public func dataToPoint(_ data: VectorArray, _ clamp: Bool? = nil) -> VectorArray {
        let xVal = data[0]
        let yVal = data[1]
        if let transform = self._transform, xVal.isFinite, yVal.isFinite {
            return vector.applyTransform(data, transform)
        }

        let xAxis = self.getAxis("x")!
        let yAxis = self.getAxis("y")!
        return VectorArray(
            xAxis.toGlobalCoord(xAxis.dataToCoord(xVal, clamp)),
            yAxis.toGlobalCoord(yAxis.dataToCoord(yVal, clamp))
        )
    }

    // upstream: clampData(data: ScaleDataValue[], out?: number[]): number[]
    public func clampData(_ data: [ScaleDataValue]) -> [Double]? {
        let xScale = self.getAxis("x")!.scale
        let yScale = self.getAxis("y")!.scale
        let xAxisExtent = xScale.getExtent()
        let yAxisExtent = yScale.getExtent()
        let x = xScale.parse(data[0])
        let y = yScale.parse(data[1])
        var out: [Double] = [0, 0]
        out[0] = Swift.min(
            Swift.max(Swift.min(xAxisExtent[0], xAxisExtent[1]), x),
            Swift.max(xAxisExtent[0], xAxisExtent[1])
        )
        out[1] = Swift.min(
            Swift.max(Swift.min(yAxisExtent[0], yAxisExtent[1]), y),
            Swift.max(yAxisExtent[0], yAxisExtent[1])
        )

        return out
    }

    // upstream: pointToData(point: number[], clamp?: boolean, out?: number[]): number[]
    // `CoordinateSystem.pointToData` witness — `opt: Any?` = upstream `clamp`, `out` dropped;
    //   return typed `Any?` per the protocol (the value is always a `[Double]`).
    public func pointToData(_ point: [Double], _ opt: Any? = nil) -> Any? {
        let clamp = opt as? Bool
        var out: [Double] = [0, 0]
        if let invTransform = self._invTransform {
            let r = vector.applyTransform(VectorArray(point[0], point[1]), invTransform)
            return [r[0], r[1]]
        }
        let xAxis = self.getAxis("x")!
        let yAxis = self.getAxis("y")!
        out[0] = xAxis.coordToData(xAxis.toLocalCoord(point[0]), clamp)
        out[1] = yAxis.coordToData(yAxis.toLocalCoord(point[1]), clamp)
        return out
    }

    // upstream: getOtherAxis(axis: Axis2D): Axis2D
    // upstream param/return are `Axis2D`; kept faithful. Because the param is more specific
    //   than the protocol's `getOtherAxis(baseAxis: Axis)`, this does not satisfy that (optional)
    //   requirement — the protocol default is used at protocol dispatch; concrete callers get the real one.
    public func getOtherAxis(_ axis: Axis2D) -> Axis2D {
        return self.getAxis(axis.dim == "x" ? "y" : "x")!
    }

    // Phase 51: the PROTOCOL-WITNESSING overloads for `CoordinateSystem.getAxis(_:)` / `getOtherAxis(_:)`.
    //   The concrete methods above take the NARROWER `Axis2D` (param/return), which does NOT witness the
    //   protocol requirements (`getAxis(_ dim: DimensionName?) -> Axis?`, `getOtherAxis(_ baseAxis: Axis)
    //   -> Axis?`) — so a call through a `CoordinateSystem`-typed reference hit the nil-returning DEFAULT
    //   (the [[swift-protocol-witness-trap]]), silently blocking markers (markerHelper reads
    //   `coordSys.getAxis`/`getOtherAxis`). These delegating overloads satisfy the protocol; concrete
    //   callers still bind the exact-match `Axis2D` versions above.
    public func getAxis(_ dim: DimensionName?) -> Axis? {
        guard let dim = dim else { return nil }
        return self.getAxis(dim) as Axis?
    }
    public func getOtherAxis(_ baseAxis: Axis) -> Axis? {
        guard let a = baseAxis as? Axis2D else { return nil }
        return self.getOtherAxis(a) as Axis?
    }

    /**
     * Get rect area of cartesian.
     * Area will have a contain function to determine if a point is in the coordinate system.
     */
    // upstream: getArea(tolerance?: number): Cartesian2DArea
    // Concrete-typed callers use this overload directly and receive the real `Cartesian2DArea`
    //   (BoundingRect). See the explicit protocol witness below for protocol-dispatched callers.
    public func getArea(_ tolerance: Double? = nil) -> Cartesian2DArea {
        let tolerance = tolerance ?? 0

        let xExtent = self.getAxis("x")!.getGlobalExtent()
        let yExtent = self.getAxis("y")!.getGlobalExtent()
        let x = Swift.min(xExtent[0], xExtent[1]) - tolerance
        let y = Swift.min(yExtent[0], yExtent[1]) - tolerance
        let width = Swift.max(xExtent[0], xExtent[1]) - x + tolerance
        let height = Swift.max(yExtent[0], yExtent[1]) - y + tolerance

        return BoundingRect(x, y, width, height)
    }

    // explicit `CoordinateSystem.getArea` protocol witness. Swift does not accept the
    //   covariant `Cartesian2DArea` return of the overload above as a witness for the protocol
    //   requirement `getArea(_:) -> CoordinateSystemClipArea?` (existential erasure is not covariance),
    //   so without this the protocol default (returning nil) would be dispatched for cartesian2d —
    //   breaking protocol-typed callers like createClipPathFromCoordSys. This overload provides the
    //   witness, delegating to the concrete implementation. (Zero-arg calls resolve to the default-arg
    //   overload above, so concrete callers are unaffected.)
    public func getArea(_ tolerance: Double?) -> CoordinateSystemClipArea? {
        let rect: Cartesian2DArea = self.getArea(tolerance)
        return rect
    }
}

// upstream: `xVal != null && isFinite(xVal as number)` — extracts a finite Double from a `ScaleDataValue`
//   (Any). Returns nil when the value is null/undefined, non-numeric, or non-finite (NaN/Inf), which
//   routes `dataToPoint` to the slow (per-axis) path exactly as upstream does.
fileprivate func cartesian2DFiniteNumber(_ value: ScaleDataValue?) -> Double? {
    guard let num = value as? Double, num.isFinite else {
        return nil
    }
    return num
}

// upstream: export default Cartesian2D;  -> `open class Cartesian2D` above.
