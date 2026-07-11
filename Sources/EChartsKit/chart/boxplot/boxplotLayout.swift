// Ported from echarts/src/chart/boxplot/boxplotLayout.ts — keep in sync with upstream
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
//   import { isArray } from 'zrender/src/core/util';                    -> `util.isArray` (ZRenderKit Core/util.swift).
//   import {mathMax, mathMin, parsePercent} from '../../util/number';   -> `number.mathMax/mathMin/parsePercent`.
//   import type GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import BoxplotSeriesModel, { SERIES_TYPE_BOXPLOT } from './BoxplotSeries';  -> sibling BoxplotSeries.swift.
//   import { countSeriesOnAxisOnKey, eachAxisOnKey, eachSeriesOnAxisOnKey, requireAxisStatistics }
//       from '../../coord/axisStatistics';                             -> top-level free symbols (coord/axisStatistics.swift).
//   import { createSimpleOverallStageHandler, makeCallOnlyOnce } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` / `model.makeCallOnlyOnce` (util/modelUtil.swift).
//   import { EChartsExtensionInstallRegisters } from '../../extension'; -> EChartsExtensionInstallRegisters (registrar).
//   import Axis from '../../coord/Axis';                                -> Axis (coord/Axis.swift).
//   import { registerAxisContainShapeHandler } from '../../coord/scaleRawExtentInfo';
//       -> `registerAxisContainShapeHandler` (coord/scaleRawExtentInfo.swift).
//   import { calcBandWidth } from '../../coord/axisBand';               -> `calcBandWidth` (coord/axisBand.swift).
//   import { createBandWidthBasedAxisContainShapeHandler, createMetricsNonOrdinalLinearPositiveMinGap,
//       makeAxisStatKey } from '../helper/axisSnippets';
//       -> PORT-TODO: chart/helper/axisSnippets.ts NOT ported. Mirrored below as private stubs (same
//          convention as barGrid.swift / barCommon.swift). Remove and import the real symbols from
//          chart/helper/axisSnippets.swift when it lands.

// upstream: const callOnlyOnce = makeCallOnlyOnce();
private let callOnlyOnce: (EChartsExtensionInstallRegisters, () -> Void) -> Void = model.makeCallOnlyOnce()

// upstream:
//   export interface BoxplotItemLayout {
//       ends: number[][]
//       initBaseline: number
//   }
// Exposed for the boxplot View (deferred stage) — the BoxPath custom shape reads `ends` (the 4 body
// corners + whisker/median line endpoints) and `initBaseline`. Stored via `data.setItemLayout`.
public struct BoxplotItemLayout {
    public var ends: [[Double]]
    public var initBaseline: Double
    public init(ends: [[Double]], initBaseline: Double) {
        self.ends = ends
        self.initBaseline = initBaseline
    }
}

// upstream:
//   export const boxplotLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_BOXPLOT, boxplotLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; upstream `boxplotLayout` is `(ecModel)` (1-arg). Adapt with a thin wrapper that
// drops the (unused) api/payload, keeping `boxplotLayout` byte-faithful (1-arg) below.
public let boxplotLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_BOXPLOT,
    { ecModel, _, _ in boxplotLayout(ecModel) }
)

// Exposed for the driver to call directly (mirrors how the pie/bar layout handlers are invoked
// directly), matching upstream's module-private `function boxplotLayout(ecModel)`.
public func boxplotLayout(_ ecModel: GlobalModel) {
    let axisStatKey = makeAxisStatKey(SERIES_TYPE_BOXPLOT)
    eachAxisOnKey(ecModel, axisStatKey) { axis in
        let seriesCount = countSeriesOnAxisOnKey(axis, axisStatKey)
        if seriesCount == 0 {
            return
        }
        let baseResult = calculateBase(axis, seriesCount)
        eachSeriesOnAxisOnKey(axis, axisStatKey) { seriesModelBase in
            // upstream typed callback param `seriesModel: BoxplotSeriesModel`.
            let seriesModel = seriesModelBase as! BoxplotSeriesModel
            let seriesIndex = Int(seriesModel.seriesIndex)
            layoutSingleSeries(
                seriesModel,
                baseResult.boxOffsetList[seriesIndex]!,
                baseResult.boxWidthList[seriesIndex]!
            )
        }
    }
}

// upstream:
//   type BaseCalculationResult = {
//       boxOffsetList: Record<seriesIndex, number>;
//       boxWidthList: Record<seriesIndex, number>;
//   };
// The `Record<seriesIndex, number>` (a sparse JS array indexed by `seriesIndex`) is modeled as
// `[Int: Double]` keyed by `seriesIndex`.
private struct BaseCalculationResult {
    var boxOffsetList: [Int: Double]
    var boxWidthList: [Int: Double]
}

/**
 * Calculate offset and box width for each series.
 */
private func calculateBase(_ baseAxis: Axis, _ seriesCount: Double) -> BaseCalculationResult {
    var boxWidthList: [Int: Double] = [:]
    var boxOffsetList: [Int: Double] = [:]
    var boundList: [Int: [Double]] = [:]

    let bandWidth = calcBandWidth(
        baseAxis,
        CalculateBandWidthOpt(
            fromStat: CalculateBandWidthOpt.FromStat(key: makeAxisStatKey(SERIES_TYPE_BOXPLOT)),
            min: 1
        )
    ).w

    eachSeriesOnAxisOnKey(baseAxis, makeAxisStatKey(SERIES_TYPE_BOXPLOT)) { seriesModel in
        // let boxWidthBound = seriesModel.get('boxWidth');
        // if (!isArray(boxWidthBound)) { boxWidthBound = [boxWidthBound, boxWidthBound]; }
        var boxWidthBound: [Any?]
        let raw = seriesModel.get("boxWidth")
        if let arr = raw as? [Any?] {
            boxWidthBound = arr
        }
        else if let arr = raw as? [Any] {
            boxWidthBound = arr.map { $0 as Any? }
        }
        else {
            boxWidthBound = [raw, raw]
        }
        boundList[Int(seriesModel.seriesIndex)] = [
            parsePercentOr0(boxWidthBound[0], bandWidth),
            parsePercentOr0(boxWidthBound[1], bandWidth)
        ]
    }

    let availableWidth = bandWidth * 0.8 - 2
    let boxGap = availableWidth / seriesCount * 0.3
    let boxWidth = (availableWidth - boxGap * (seriesCount - 1)) / seriesCount
    var base = boxWidth / 2 - availableWidth / 2

    eachSeriesOnAxisOnKey(baseAxis, makeAxisStatKey(SERIES_TYPE_BOXPLOT)) { seriesModel in
        let seriesIndex = Int(seriesModel.seriesIndex)
        boxOffsetList[seriesIndex] = base
        base += boxGap + boxWidth

        boxWidthList[seriesIndex] = number.mathMin(
            number.mathMax(boxWidth, boundList[seriesIndex]![0]),
            boundList[seriesIndex]![1]
        )
    }

    return BaseCalculationResult(
        boxOffsetList: boxOffsetList,
        boxWidthList: boxWidthList
    )
}

/**
 * Calculate points location for each series.
 */
private func layoutSingleSeries(_ seriesModel: BoxplotSeriesModel, _ offset: Double, _ boxWidth: Double) {
    // upstream `const coordSys = seriesModel.coordinateSystem;` narrowed to the concrete Cartesian2D
    //   (the base `coordinateSystem` is `Any?` in the port).
    let coordSys = seriesModel.coordinateSystem as! Cartesian2D
    let data = seriesModel.getData()
    let halfWidth = boxWidth / 2
    let cDimIdx = seriesModel.getWhiskerBoxesLayout() == "horizontal" ? 0 : 1
    let vDimIdx = 1 - cDimIdx
    let coordDims = ["x", "y"]
    let cDim = data.mapDimension(coordDims[cDimIdx])
    let vDims = data.mapDimensionsAll(coordDims[vDimIdx])

    if cDim == nil || vDims.count < 5 {
        return
    }

    // upstream nested functions (defined after the loop in the source, but hoisted in JS). Ported as
    //   nested funcs capturing `data`, `coordSys`, `cDimIdx`, `vDimIdx`, `offset`, `halfWidth`.
    func getPoint(_ axisDimVal: Double, _ dim: String, _ dataIndex: Int) -> [Double] {
        let val = boxplotToNumber(data.get(dim, dataIndex))
        var p: [Any] = [0, 0]
        p[cDimIdx] = axisDimVal
        p[vDimIdx] = val
        var point: [Double]
        if axisDimVal.isNaN || val.isNaN {
            point = [Double.nan, Double.nan]
        }
        else {
            point = coordSys.dataToPoint(p)
            point[cDimIdx] += offset
        }
        return point
    }

    func addBodyEnd(_ ends: inout [[Double]], _ point: [Double], _ start: Bool) {
        var point1 = point   // point.slice()
        var point2 = point   // point.slice()
        point1[cDimIdx] += halfWidth
        point2[cDimIdx] -= halfWidth
        if start {
            ends.append(point1)
            ends.append(point2)
        }
        else {
            ends.append(point2)
            ends.append(point1)
        }
    }

    func layEndLine(_ ends: inout [[Double]], _ endCenter: [Double]) {
        var from = endCenter   // endCenter.slice()
        var to = endCenter     // endCenter.slice()
        from[cDimIdx] -= halfWidth
        to[cDimIdx] += halfWidth
        ends.append(from)
        ends.append(to)
    }

    for dataIndex in 0..<data.count() {
        let axisDimVal = boxplotToNumber(data.get(cDim!, dataIndex))

        let median = getPoint(axisDimVal, vDims[2], dataIndex)
        let end1 = getPoint(axisDimVal, vDims[0], dataIndex)
        let end2 = getPoint(axisDimVal, vDims[1], dataIndex)
        let end4 = getPoint(axisDimVal, vDims[3], dataIndex)
        let end5 = getPoint(axisDimVal, vDims[4], dataIndex)

        var ends: [[Double]] = []
        addBodyEnd(&ends, end2, false)
        addBodyEnd(&ends, end4, true)

        ends.append(end1)
        ends.append(end2)
        ends.append(end5)
        ends.append(end4)
        layEndLine(&ends, end1)
        layEndLine(&ends, end5)
        layEndLine(&ends, median)

        data.setItemLayout(dataIndex, BoxplotItemLayout(
            ends: ends,
            initBaseline: median[vDimIdx]
        ))
    }
}

// upstream:
//   export function registerBoxplotAxisHandlers(registers: EChartsExtensionInstallRegisters) { ... }
public func registerBoxplotAxisHandlers(_ registers: EChartsExtensionInstallRegisters) {
    callOnlyOnce(registers) {
        let axisStatKey = makeAxisStatKey(SERIES_TYPE_BOXPLOT)
        requireAxisStatistics(
            registers,
            AxisStatKeyedClient(
                key: axisStatKey,
                seriesType: SERIES_TYPE_BOXPLOT,
                getMetrics: createMetricsNonOrdinalLinearPositiveMinGap
            )
        )
        registerAxisContainShapeHandler(
            axisStatKey,
            createBandWidthBasedAxisContainShapeHandler(axisStatKey)
        )
    }
}


// ============================================================================
// PORT-NOTE: local port helpers (NOT in upstream boxplotLayout.ts).
// ============================================================================

// `data.get(...)` returns `ParsedValue` (Any); boxplot's 5-number data is stored as `Double`. Mirrors
//   the upstream `as number` numeric coercions in `layoutSingleSeries`/`getPoint`.
private func boxplotToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// upstream `parsePercent(boxWidthBound[i], bandWidth) || 0`: JS `x || 0` collapses a falsy result
//   (0 or NaN) to 0. `parsePercent` returns a `number`; map NaN -> 0 (0 is already 0).
private func parsePercentOr0(_ option: Any?, _ percentBase: Double) -> Double {
    let p = number.parsePercent(option, percentBase)
    return p.isNaN ? 0 : p
}


// ============================================================================
// PORT-TODO: stubs for `chart/helper/axisSnippets.ts` (PREREQ, not yet ported). Mirror the upstream
//   one-liners so this file compiles; remove them and import the real symbols from
//   chart/helper/axisSnippets.swift when it lands (as barGrid.swift / barCommon.swift do for their stubs).
//
//   export function makeAxisStatKey(seriesType): AxisStatKey
//   export function createMetricsNonOrdinalLinearPositiveMinGap(axis): AxisStatMetrics
//   export function createBandWidthBasedAxisContainShapeHandler(axisStatKey): AxisContainShapeHandler
// ============================================================================

private func makeAxisStatKey(_ seriesType: ComponentSubType) -> AxisStatKey {
    return seriesType + AXIS_STAT_KEY_DELIMITER
}

private func createMetricsNonOrdinalLinearPositiveMinGap(_ axis: Axis) -> AxisStatMetrics? {
    registerMetricImplLiPosMinGap()
    return AxisStatMetrics(
        // non-category scale do not use `liPosMinGap` to calculate `bandWidth`.
        liPosMinGap: !helper.isOrdinalScale(axis.scale)
    )
}

private func createBandWidthBasedAxisContainShapeHandler(_ axisStatKey: AxisStatKey) -> AxisContainShapeHandler {
    // [AXIS_CONTAIN_SHAPE_COMMON_STRATEGY]: expand `Scale` extent by half bandWidth.
    return { axis, ecModel in
        let bandWidthResult = calcBandWidth(axis, CalculateBandWidthOpt(fromStat: CalculateBandWidthOpt.FromStat(key: axisStatKey)))
        if number.isNullableNumberFinite(bandWidthResult.w2) {
            return [-bandWidthResult.w2 / 2, bandWidthResult.w2 / 2]
        }
        return nil
    }
}
