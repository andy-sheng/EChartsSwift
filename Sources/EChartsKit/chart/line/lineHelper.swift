// Ported from echarts/src/chart/line/helper.ts — keep in sync with upstream
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
// import {isDimensionStacked} from '../../data/helper/dataStackHelper';  -> `isDimensionStacked`
// import {isNumber, map} from 'zrender/src/core/util';                   -> `util.map` (isNumber: see lineIsNumber)
// import type Polar from '../../coord/polar/Polar';                      -> coord/polar/Polar.swift
// import type Cartesian2D from '../../coord/cartesian/Cartesian2D';      -> coord/cartesian/Cartesian2D.swift
// import SeriesData from '../../data/SeriesData';                        -> data/SeriesData.swift
// import Axis from '../../coord/Axis';                                   -> coord/Axis.swift
// import type { LineSeriesOption } from './LineSeries';                  -> chart/line/LineSeries.swift

// ---------------------------------------------------------------------------
// PORT-LOCAL (not an upstream symbol).
//
// Upstream types the line's coordinate system as the UNION `Cartesian2D | Polar`, and calls the
// members both types happen to share (`type` / `dimensions` / `getBaseAxis` / `getOtherAxis` /
// `getAxis` / `dataToPoint` / `getArea`). Swift has no union type, and in this port `Polar` conforms
// only to `CoordinateSystemMaster` (not `CoordinateSystem`), so there is no common protocol to name.
// This enum IS that union: every call site below stays byte-identical to upstream
// (`coordSys.getBaseAxis()`, `coordSys.dataToPoint(...)`, `coordSys.type`, …).
// ---------------------------------------------------------------------------
public enum LineCoordSys {
    case cartesian2d(Cartesian2D)
    case polar(Polar)

    /// `seriesModel.coordinateSystem` is `Any?` in this port — narrow it to the union (nil for any
    /// other coord system, which is exactly upstream's "line is only supported on cartesian2d/polar").
    public static func from(_ coordSys: Any?) -> LineCoordSys? {
        if let cartesian = coordSys as? Cartesian2D {
            return .cartesian2d(cartesian)
        }
        if let polar = coordSys as? Polar {
            return .polar(polar)
        }
        return nil
    }

    public var type: String {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.type
        case .polar(let coordSys): return coordSys.type
        }
    }

    public var dimensions: [DimensionName] {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.dimensions
        case .polar(let coordSys): return coordSys.dimensions
        }
    }

    public func getBaseAxis() -> Axis {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.getBaseAxis()
        case .polar(let coordSys): return coordSys.getBaseAxis()
        }
    }

    public func getOtherAxis(_ axis: Axis) -> Axis {
        switch self {
        case .cartesian2d(let coordSys):
            // upstream: `coordSys.getOtherAxis(baseAxis as any)` — the `as any` is upstream's own
            //   escape hatch for the same union problem.
            return coordSys.getOtherAxis(axis as! Axis2D)
        case .polar(let coordSys):
            return coordSys.getOtherAxis(axis)
        }
    }

    public func getAxis(_ dim: DimensionName) -> Axis? {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.getAxis(dim)
        case .polar(let coordSys): return coordSys.getAxis(dim)
        }
    }

    public func dataToPoint(_ data: [ScaleDataValue]) -> [Double] {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.dataToPoint(data)
        case .polar(let coordSys): return coordSys.dataToPoint(data)
        }
    }

    public func getArea() -> CoordinateSystemClipArea {
        switch self {
        case .cartesian2d(let coordSys): return coordSys.getArea() as Cartesian2DArea
        case .polar(let coordSys): return coordSys.getArea()
        }
    }

    /// `isCoordinateSystemType<Cartesian2D>(coordSys, 'cartesian2d')` — the narrowing side of the union.
    public var asCartesian2D: Cartesian2D? {
        if case .cartesian2d(let coordSys) = self { return coordSys }
        return nil
    }

    public var asPolar: Polar? {
        if case .polar(let coordSys) = self { return coordSys }
        return nil
    }
}

// upstream: interface CoordInfo { ... }
public struct CoordInfo {
    public var dataDimsForPoint: [DimensionName?]
    public var valueStart: Double
    public var valueAxisDim: String
    public var baseAxisDim: String
    public var stacked: Bool
    public var valueDim: DimensionName?
    public var baseDim: DimensionName?
    public var baseDataOffset: Int
    public var stackedOverDimension: String?
}

// upstream: export function prepareDataCoordInfo(coordSys, data, valueOrigin?): CoordInfo
public func prepareDataCoordInfo(
    _ coordSys: LineCoordSys,
    _ data: SeriesData,
    _ valueOrigin: Any? = nil
) -> CoordInfo {
    let baseAxis = coordSys.getBaseAxis()
    let valueAxis = coordSys.getOtherAxis(baseAxis)
    let valueStart = getValueStart(valueAxis, valueOrigin)

    let baseAxisDim = baseAxis.dim
    let valueAxisDim = valueAxis.dim
    let valueDim = data.mapDimension(valueAxisDim)
    let baseDim = data.mapDimension(baseAxisDim)
    let baseDataOffset = (valueAxisDim == "x" || valueAxisDim == "radius") ? 1 : 0

    // const dims = map(coordSys.dimensions, function (coordDim) { return data.mapDimension(coordDim); });
    var dims: [DimensionName?] = util.map(coordSys.dimensions) { coordDim, _ in
        return data.mapDimension(coordDim)
    }

    var stacked = false
    let stackResultDim = data.getCalculationInfo("stackResultDimension") as? String
    if dims.count > 0, let d0 = dims[0], isDimensionStacked(data, d0) { // jshint ignore:line
        stacked = true
        dims[0] = stackResultDim
    }
    if dims.count > 1, let d1 = dims[1], isDimensionStacked(data, d1) { // jshint ignore:line
        stacked = true
        dims[1] = stackResultDim
    }

    return CoordInfo(
        dataDimsForPoint: dims,
        valueStart: valueStart,
        valueAxisDim: valueAxisDim,
        baseAxisDim: baseAxisDim,
        stacked: stacked,
        valueDim: valueDim,
        baseDim: baseDim,
        baseDataOffset: baseDataOffset,
        stackedOverDimension: data.getCalculationInfo("stackedOverDimension") as? String
    )
}

// upstream: function getValueStart(valueAxis: Axis, valueOrigin)
private func getValueStart(_ valueAxis: Axis, _ valueOrigin: Any?) -> Double {
    var valueStart: Double = 0
    let extent = valueAxis.scale.getExtent()

    if let origin = valueOrigin as? String, origin == "start" {
        valueStart = extent[0]
    }
    else if let origin = valueOrigin as? String, origin == "end" {
        valueStart = extent[1]
    }
    // If origin is specified as a number, use it as
    // valueStart directly
    else if let originNum = lineHelperToNumberOpt(valueOrigin), !originNum.isNaN {
        valueStart = originNum
    }
    // auto
    else {
        // Both positive
        if extent[0] > 0 {
            valueStart = extent[0]
        }
        // Both negative
        else if extent[1] < 0 {
            valueStart = extent[1]
        }
        // If is one positive, and one negative, onZero shall be true
    }

    return valueStart
}

// upstream: export function getStackedOnPoint(dataCoordInfo, coordSys, data, idx): number[]
public func getStackedOnPoint(
    _ dataCoordInfo: CoordInfo,
    _ coordSys: LineCoordSys,
    _ data: SeriesData,
    _ idx: Int
) -> [Double] {
    var value = Double.nan
    if dataCoordInfo.stacked, let stackedOverDim = data.getCalculationInfo("stackedOverDimension") as? String {
        value = lineHelperToNumber(data.get(stackedOverDim, idx))
    }
    if value.isNaN {
        value = dataCoordInfo.valueStart
    }

    let baseDataOffset = dataCoordInfo.baseDataOffset
    var stackedData: [ScaleDataValue] = [0, 0]
    stackedData[baseDataOffset] = dataCoordInfo.baseDim.map { data.get($0, idx) as Any } ?? Double.nan
    stackedData[1 - baseDataOffset] = value

    return coordSys.dataToPoint(stackedData)
}

// upstream: export function isPointIllegal(xOrY: number, yOrX: number)
public func isPointIllegal(_ xOrY: Double, _ yOrX: Double) -> Bool {
    // NOTE:
    //  - `NaN` point x/y may be generated by, e.g.,
    //    original series data `NaN`, '-', `null`, `undefined`,
    //    negative values in LogScale.
    //  - `Infinite` point x/y may be generated by, e.g.,
    //    original series data `Infinite`, `0` in LogScale.
    return !xOrY.isFinite || !yOrX.isFinite
}

// ---------------------------------------------------------------------------
// PORT-LOCAL numeric coercion (not upstream). `data.get(...)` returns `ParsedValue` (Any); numeric
// series data is stored as `Double`, but option bags can carry bare `Int` literals — never read a
// numeric through a bare `as? Double` (the Int-vs-Double option-read trap).
// ---------------------------------------------------------------------------
func lineHelperToNumber(_ v: Any?) -> Double {
    return lineHelperToNumberOpt(v) ?? Double.nan
}

func lineHelperToNumberOpt(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let f as Float: return Double(f)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}
