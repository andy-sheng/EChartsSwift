// Ported from echarts/src/component/marker/markerHelper.ts — keep in sync with upstream
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
// import * as numberUtil from '../../util/number';                 -> EChartsKit `number` (util/number.swift)
// import {isDimensionStacked} from '../../data/helper/dataStackHelper'; -> EChartsKit `isDimensionStacked`
// import SeriesModel from '../../model/Series';                     -> EChartsKit `SeriesModel`
// import SeriesData from '../../data/SeriesData';                   -> EChartsKit `SeriesData`
// import { MarkerStatisticType, MarkerPositionOption } from './MarkerModel'; -> sibling MarkerModel.swift
// import { indexOf, curry, clone, isArray } from 'zrender/src/core/util'; -> ZRenderKit `util.*` (curry replicated inline)
// import Axis from '../../coord/Axis';                              -> EChartsKit `Axis` (coord/Axis.swift)
// import { CoordinateSystem } from '../../coord/CoordinateSystem';  -> EChartsKit `CoordinateSystem` (coord/CoordinateSystem.swift)
// import { ScaleDataValue, ParsedValue, DimensionLoose, DimensionName } from '../../util/types'; -> util/types.swift
// import { parseDataValue } from '../../data/helper/dataValueHelper'; -> EChartsKit `dataValueHelper.parseDataValue`
// import SeriesDimensionDefine from '../../data/SeriesDimensionDefine'; -> EChartsKit `SeriesDimensionDefine`

// interface MarkerAxisInfo { valueDataDim; valueAxis; baseAxis; baseDataDim }
// PORT-TODO: upstream fields are non-optional (`{} as MarkerAxisInfo` then filled). Modeled with
//   optional fields because it is built incrementally (CONVENTIONS §6).
struct MarkerAxisInfo {
    var valueDataDim: DimensionName?
    var valueAxis: Axis?
    var baseAxis: Axis?
    var baseDataDim: DimensionName?
}

// export type MarkerDimValueGetter<TMarkerItemOption> = (item, dimName, dataIndex, dimIndex) => ParsedValue;
public typealias MarkerDimValueGetter = (
    _ item: MarkerPositionOption,
    _ dimName: String,
    _ dataIndex: Double,
    _ dimIndex: Double
) -> ParsedValue

// Coord systems that expose `containData` / `containZone` (currently Cartesian2D and Polar upstream).
// Upstream types these as optional augmentations on the coord sys; the port exposes them as
// retroactive-conformance protocols so `dataFilter`/`zoneFilter` can feature-detect via `as?`.
public protocol CoordinateSystemWithContainData: AnyObject {
    func containData(_ data: [ScaleDataValue]) -> Bool
}
public protocol CoordinateSystemWithContainZone: AnyObject {
    func containZone(_ data1: [ScaleDataValue], _ data2: [ScaleDataValue]) -> Bool
}

// Free-function module -> caseless enum namespace named after the file (CONVENTIONS §2).
public enum markerHelper {

    // function hasXOrY(item) { return !(isNaN(parseFloat(item.x)) && isNaN(parseFloat(item.y))); }
    static func hasXOrY(_ item: MarkerPositionOption) -> Bool {
        return !(parseFloat(item.x).isNaN && parseFloat(item.y).isNaN)
    }

    // function hasXAndY(item) { return !isNaN(parseFloat(item.x)) && !isNaN(parseFloat(item.y)); }
    static func hasXAndY(_ item: MarkerPositionOption) -> Bool {
        return !parseFloat(item.x).isNaN && !parseFloat(item.y).isNaN
    }

    // JS `parseFloat(x as string)`: coerce the dynamic value to string, then parse a leading float.
    private static func parseFloat(_ x: Any?) -> Double {
        return number.parseFloatLeading(number.jsString(x))
    }

    static func markerTypeCalculatorWithExtent(
        _ markerType: MarkerStatisticType,
        _ data: SeriesData,
        _ axisDim: String,
        _ otherDataDim: String,
        _ targetDataDim: String,
        _ otherCoordIndex: Double,
        _ targetCoordIndex: Double
    ) -> (coordArr: [ParsedValue], coordArrValue: ParsedValue) {   // upstream: [ParsedValue[], ParsedValue]
        // PORT-TODO: upstream builds a sparse `ParsedValue[]` via index assignment (`coordArr[i] = ...`);
        //   Swift arrays are not sparse, so it is pre-sized to 2 (cartesian/polar have 2 coord dims).
        var coordArr: [ParsedValue] = [Double.nan, Double.nan]

        let stacked = isDimensionStacked(data, targetDataDim /* , otherDataDim */)
        let calcDataDim = stacked
            ? ((data.getCalculationInfo("stackResultDimension") as? String) ?? targetDataDim)
            : targetDataDim

        let value = numCalculate(data, calcDataDim, markerType)

        let seriesModel = data.hostModel as! SeriesModel
        // const dataIndex = seriesModel.indicesOfNearest(axisDim, calcDataDim, value)[0];
        // PORT-TODO: `SeriesModel.indicesOfNearest` is currently stubbed to `[]` (depends on the not-
        //   yet-wired coord/Axis `dataToCoord`); `[0]` would be undefined. Fallback to index 0 so the
        //   statistic path does not crash — revisit once `indicesOfNearest` lands.
        let dataIndex = seriesModel.indicesOfNearest(axisDim, calcDataDim, value).first ?? 0
        let idx = Int(dataIndex)

        coordArr[Int(otherCoordIndex)] = data.get(otherDataDim, idx) as Any
        coordArr[Int(targetCoordIndex)] = data.get(calcDataDim, idx) as Any
        let coordArrValue = data.get(targetDataDim, idx) as Any
        // Make it simple, do not visit all stacked value to count precision.
        var precision = number.getPrecision(data.get(targetDataDim, idx))
        precision = Swift.min(precision, 20)
        if precision >= 0 {
            // coordArr[targetCoordIndex] = +(coordArr[targetCoordIndex] as number).toFixed(precision);
            let raw = (coordArr[Int(targetCoordIndex)] as? Double) ?? Double.nan
            coordArr[Int(targetCoordIndex)] = toFixedNumber(raw, Int(precision))
        }

        return (coordArr, coordArrValue)
    }

    // JS `+(x.toFixed(precision))` — format to `precision` decimals then reparse to a number.
    // PORT-TODO: JS `Number.prototype.toFixed` rounding (half-away-from-zero on the decimal string)
    //   is approximated by `%.*f` formatting (which rounds half-to-even in some locales).
    private static func toFixedNumber(_ x: Double, _ precision: Int) -> Double {
        if x.isNaN || x.isInfinite {
            return x
        }
        let str = String(format: "%.\(precision)f", x)
        return Double(str) ?? x
    }

    // TODO Specified percent
    // const markerTypeCalculator = { min: curry(...), max: curry(...), average: curry(...), median: curry(...) };
    //   `curry(markerTypeCalculatorWithExtent, 'min')` binds the first arg. Replicated as closures
    //   keyed by the statistic name (JS object lookup `markerTypeCalculator[type]`).
    typealias MarkerTypeCalculator = (
        _ data: SeriesData, _ axisDim: String, _ otherDataDim: String, _ targetDataDim: String,
        _ otherCoordIndex: Double, _ targetCoordIndex: Double
    ) -> (coordArr: [ParsedValue], coordArrValue: ParsedValue)

    static let markerTypeCalculator: [String: MarkerTypeCalculator] = [
        "min": { markerTypeCalculatorWithExtent(.min, $0, $1, $2, $3, $4, $5) },
        "max": { markerTypeCalculatorWithExtent(.max, $0, $1, $2, $3, $4, $5) },
        "average": { markerTypeCalculatorWithExtent(.average, $0, $1, $2, $3, $4, $5) },
        "median": { markerTypeCalculatorWithExtent(.median, $0, $1, $2, $3, $4, $5) }
    ]

    /**
     * Transform markPoint data item to format used in List by do the following
     * 1. Calculate statistic like `max`, `min`, `average`
     * 2. Convert `item.xAxis`, `item.yAxis` to `item.coord` array
     */
    public static func dataTransform(
        _ seriesModel: SeriesModel,
        _ itemInput: MarkerPositionOption?
    ) -> MarkerPositionOption? {
        // if (!item) { return; }
        guard var item = itemInput else {
            return nil
        }

        let data = seriesModel.getData()
        let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
        // const dims = coordSys && coordSys.dimensions;
        let dims = coordSys?.dimensions

        // 1. If not specify the position with pixel directly
        // 2. If `coord` is not a data array. Which uses `xAxis`, `yAxis` to specify the coord on each dimension

        // parseFloat first because item.x and item.y can be percent string like '20%'
        // if (!hasXAndY(item) && !isArray(item.coord) && isArray(dims))
        // `item.coord` is a typed optional array -> `isArray(item.coord)` ≡ `item.coord != nil`;
        //   `dims` is a typed optional array -> `isArray(dims)` ≡ `dims != nil`.
        if !hasXAndY(item) && !(item.coord != nil) && (dims != nil) {
            let axisInfo = getAxisInfo(item, data, coordSys!, seriesModel)

            // Clone the option
            // Transform the properties xAxis, yAxis, radiusAxis, angleAxis, geoCoord to value
            item = util.clone(item)

            // if (item.type && markerTypeCalculator[item.type] && axisInfo.baseAxis && axisInfo.valueAxis)
            if let type = item.type,
               let calc = markerTypeCalculator[type.rawValue],
               axisInfo.baseAxis != nil && axisInfo.valueAxis != nil {
                let otherCoordIndex = util.indexOf(dims, axisInfo.baseAxis!.dim)
                let targetCoordIndex = util.indexOf(dims, axisInfo.valueAxis!.dim)

                let coordInfo = calc(
                    data, axisInfo.valueAxis!.dim, axisInfo.baseDataDim ?? "", axisInfo.valueDataDim ?? "",
                    otherCoordIndex, targetCoordIndex
                )
                item.coord = coordInfo.coordArr.map { $0 as Any? }   // coordInfo[0]
                // Force to use the value of calculated value.
                // let item use the value without stack.
                item.value = coordInfo.coordArrValue   // coordInfo[1]
            }
            else {
                // FIXME Only has one of xAxis and yAxis.
                item.coord = [
                    item.xAxis != nil ? item.xAxis : item.radiusAxis,
                    item.yAxis != nil ? item.yAxis : item.angleAxis
                ]
            }
        }
        // x y is provided
        // if (item.coord == null || !isArray(dims))   (`isArray(dims)` ≡ `dims != nil`)
        if item.coord == nil || !(dims != nil) {
            item.coord = []
            let baseAxis = seriesModel.getBaseAxis() as? Axis
            // if (baseAxis && item.type && markerTypeCalculator[item.type])
            if let baseAxis = baseAxis, let type = item.type, markerTypeCalculator[type.rawValue] != nil {
                let otherAxis = coordSys?.getOtherAxis(baseAxis)
                if let otherAxis = otherAxis {
                    item.value = numCalculate(data, data.mapDimension(otherAxis.dim) ?? "", type)
                }
            }
        }
        else {
            // Each coord support max, min, average
            var coord = item.coord!
            for i in 0..<2 {
                // if (markerTypeCalculator[coord[i] as MarkerStatisticType])
                if let key = coord[i] as? String, markerTypeCalculator[key] != nil,
                   let type = MarkerStatisticType(rawValue: key) {
                    coord[i] = numCalculate(data, data.mapDimension(dims![i]) ?? "", type)
                }
            }
            item.coord = coord
        }
        return item
    }

    static func getAxisInfo(
        _ item: MarkerPositionOption,
        _ data: SeriesData,
        _ coordSys: CoordinateSystem,
        _ seriesModel: SeriesModel
    ) -> MarkerAxisInfo {
        // PORT-TODO: `coordSys.getAxis`/`getOtherAxis` are called through the `CoordinateSystem`
        //   protocol, but the concrete `Cartesian2D` declares more-specific signatures
        //   (`getAxis(_:DimensionName)`, `getOtherAxis(_:Axis2D)->Axis2D`) that do NOT witness the
        //   protocol's optional-param requirements (see coord/cartesian/Cartesian2D.swift notes), so
        //   the protocol-default (nil-returning) is dispatched here. Axis resolution is therefore
        //   effectively deferred until the coord-system protocol witnesses are reconciled.
        var ret = MarkerAxisInfo()   // {} as MarkerAxisInfo

        if item.valueIndex != nil || item.valueDim != nil {
            // ret.valueDataDim = item.valueIndex != null ? data.getDimension(item.valueIndex) : item.valueDim;
            ret.valueDataDim = item.valueIndex != nil
                ? data.getDimension(item.valueIndex!) : item.valueDim
            ret.valueAxis = coordSys.getAxis(dataDimToCoordDim(seriesModel, (ret.valueDataDim ?? "") as DimensionLoose))
            ret.baseAxis = ret.valueAxis != nil ? coordSys.getOtherAxis(ret.valueAxis!) : nil
            ret.baseDataDim = ret.baseAxis != nil ? data.mapDimension(ret.baseAxis!.dim) : nil
        }
        else {
            ret.baseAxis = seriesModel.getBaseAxis() as? Axis
            ret.valueAxis = ret.baseAxis != nil ? coordSys.getOtherAxis(ret.baseAxis!) : nil
            ret.baseDataDim = ret.baseAxis != nil ? data.mapDimension(ret.baseAxis!.dim) : nil
            ret.valueDataDim = ret.valueAxis != nil ? data.mapDimension(ret.valueAxis!.dim) : nil
        }

        return ret
    }

    // function dataDimToCoordDim(seriesModel, dataDim): DimensionName
    private static func dataDimToCoordDim(_ seriesModel: SeriesModel, _ dataDim: DimensionLoose) -> DimensionName? {
        let dimItem = seriesModel.getData().getDimensionInfo(dataDim)
        // return dimItem && dimItem.coordDim;
        return dimItem.coordDim
    }

    /**
     * Filter data which is out of coordinateSystem range
     * [dataFilter description]
     */
    public static func dataFilter(
        // Currently only polar and cartesian has containData.
        _ coordSys: Any?,
        _ item: MarkerPositionOption
    ) -> Bool {
        // Always return true if there is no coordSys
        // return (coordSys && coordSys.containData && item.coord && !hasXOrY(item))
        //     ? coordSys.containData(item.coord) : true;
        if let cs = coordSys as? CoordinateSystemWithContainData, item.coord != nil, !hasXOrY(item) {
            return cs.containData(scaleDataValues(item.coord!))
        }
        return true
    }

    public static func zoneFilter(
        // Currently only polar and cartesian has containData.
        _ coordSys: Any?,
        _ item1: MarkerPositionOption,
        _ item2: MarkerPositionOption
    ) -> Bool {
        // Always return true if there is no coordSys
        // return (coordSys && coordSys.containZone && item1.coord && item2.coord && !hasXOrY(item1) && !hasXOrY(item2))
        //     ? coordSys.containZone(item1.coord, item2.coord) : true;
        if let cs = coordSys as? CoordinateSystemWithContainZone,
           item1.coord != nil, item2.coord != nil, !hasXOrY(item1), !hasXOrY(item2) {
            return cs.containZone(scaleDataValues(item1.coord!), scaleDataValues(item2.coord!))
        }
        return true
    }

    // `item.coord` is `[Any?]`; `containData`/`containZone` take `[ScaleDataValue]` (Any). Coerce,
    // dropping nils (upstream passes the coord array straight through).
    private static func scaleDataValues(_ coord: [Any?]) -> [ScaleDataValue] {
        return coord.map { ($0 as Any) as ScaleDataValue }
    }

    public static func createMarkerDimValueGetter(
        _ inCoordSys: Bool,
        _ dims: [SeriesDimensionDefine]
    ) -> MarkerDimValueGetter {
        return inCoordSys
            ? { item, dimName, dataIndex, dimIndex in
                let rawVal: Any? = Int(dimIndex) < 2
                    // x, y, radius, angle
                    ? (item.coord != nil && Int(dimIndex) < item.coord!.count ? item.coord![Int(dimIndex)] : nil)
                    : item.value
                return dataValueHelper.parseDataValue(rawVal, ParseDataValueOpt(type: dims[Int(dimIndex)].type))
            }
            : { item, dimName, dataIndex, dimIndex in
                return dataValueHelper.parseDataValue(item.value, ParseDataValueOpt(type: dims[Int(dimIndex)].type))
            }
    }

    public static func numCalculate(
        _ data: SeriesData,
        _ valueDataDim: String,
        _ type: MarkerStatisticType
    ) -> Double {
        if type == .average {
            var sum = 0.0
            var count = 0.0
            data.each(valueDataDim) { args in
                // function (val: number, idx) { if (!isNaN(val)) { sum += val; count++; } }
                let val = (args[0] as? Double) ?? Double.nan
                if !val.isNaN {
                    sum += val
                    count += 1
                }
            }
            return sum / count
        }
        else if type == .median {
            return data.getMedian(valueDataDim)
        }
        else {
            // max & min
            return data.getDataExtent(valueDataDim)[type == .max ? 1 : 0]
        }
    }
}

// Retroactive conformances so `dataFilter`/`zoneFilter` can feature-detect `containData`/`containZone`
// on the concrete coord systems that implement them (upstream models these as optional augmentations).
extension Cartesian2D: CoordinateSystemWithContainData {}
extension Cartesian2D: CoordinateSystemWithContainZone {}
