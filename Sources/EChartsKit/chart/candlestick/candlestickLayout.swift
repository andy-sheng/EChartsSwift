// Ported from echarts/src/chart/candlestick/candlestickLayout.ts — keep in sync with upstream
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
//   import {subPixelOptimize} from '../../util/graphic';   -> ZRenderKit `subPixelOptimizeNS.subPixelOptimize`
//       (util/graphic re-exports zrender's single-scalar `subPixelOptimize`).
//   import createRenderPlanner from '../helper/createRenderPlanner';   -> `createRenderPlanner` (sibling).
//   import {mathMax, mathMin, parsePercent} from '../../util/number';  -> `number.mathMax/mathMin/parsePercent`.
//   import {map, retrieve2} from 'zrender/src/core/util';              -> `util.map` / `util.retrieve2`.
//   import { DimensionIndex, StageHandler, StageHandlerProgressParams } from '../../util/types';
//   import CandlestickSeriesModel, { SERIES_TYPE_CANDLESTICK, CandlestickDataItemOption } from './CandlestickSeries';
//   import SeriesData from '../../data/SeriesData';                    -> SeriesData.
//   import { RectLike } from 'zrender/src/core/BoundingRect';          -> ZRenderKit `RectLike` (protocol; see below).
//   import DataStore from '../../data/DataStore';                      -> DataStore.
//   import { createFloat32Array } from '../../util/vendor';            -> `vendor.createFloat32Array`.
//   import { makeCallOnlyOnce } from '../../util/model';               -> `model.makeCallOnlyOnce`.
//   import { requireAxisStatistics } from '../../coord/axisStatistics';  -> `requireAxisStatistics`.
//   import { EChartsExtensionInstallRegisters } from '../../extension';  -> `EChartsExtensionInstallRegisters`.
//   import { registerAxisContainShapeHandler } from '../../coord/scaleRawExtentInfo';
//   import { createBandWidthBasedAxisContainShapeHandler, createMetricsNonOrdinalLinearPositiveMinGap,
//            makeAxisStatKey } from '../helper/axisSnippets';
//       -> chart/helper/axisSnippets.ts NOT ported; the three used helpers are provided as local
//          PORT-NOTE (deferred) stubs at the bottom (mirrors layout/barGrid.swift + layout/barCommon.swift).
//   import { calcBandWidth } from '../../coord/axisBand';              -> `calcBandWidth` (coord/axisBand.swift).

// const callOnlyOnce = makeCallOnlyOnce();
// PORT-NOTE: `makeCallOnlyOnce()` is generic (`<Host: AnyObject>`); specialize to the registrar type
//   (same as layout/barGrid.swift).
private let callOnlyOnce: (EChartsExtensionInstallRegisters, () -> Void) -> Void = model.makeCallOnlyOnce()

// upstream: export interface CandlestickItemLayout { sign; initBaseline; ends: number[][]; brushRect: RectLike }
//   The layout output consumed by the (separately-staged) `NormalBoxPath` custom shape in CandlestickView
//   and by `brushSelector`. A plain data bag → `struct` (value data, no identity).
public struct CandlestickItemLayout {
    // 0 for doji (hasDojiColor), 1 for positive, -1 for negative.
    public var sign: Double
    public var initBaseline: Double
    // 8 points: body corners (0..3, closed quad) + whisker ends (4..7: highest, ocHigh, lowest, ocLow).
    public var ends: [[Double]]
    // upstream `RectLike` (== `{x,y,width,height}`). `RectLike` (ZRenderKit) is an AnyObject protocol;
    //   modeled by the file-local `CandlestickBrushRect` (raw, non-normalized — unlike `BoundingRect`).
    public var brushRect: RectLike

    public init(sign: Double, initBaseline: Double, ends: [[Double]], brushRect: RectLike) {
        self.sign = sign
        self.initBaseline = initBaseline
        self.ends = ends
        self.brushRect = brushRect
    }
}

// upstream: export interface CandlestickLayoutMeta { candleWidth: number; isSimpleBox: boolean }
//   Stored via `data.setLayout({candleWidth, isSimpleBox})` and read back by key (getLayout('isSimpleBox')
//   / getLayout('candleWidth')), so it is persisted as loose kv pairs rather than a struct.
public struct CandlestickLayoutMeta {
    public var candleWidth: Double
    public var isSimpleBox: Bool
}

// A minimal `RectLike`-conforming holder for `brushRect`. Upstream `makeBrushRect` returns a raw
//   `{x,y,width,height}` object literal (width/height may be negative on inverted axes), so — unlike
//   `BoundingRect` (which normalizes negatives) — this stores the values verbatim.
public final class CandlestickBrushRect: RectLike {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// upstream: export const candlestickLayout: StageHandler = { seriesType, plan, reset }
public let candlestickLayout: StageHandler = {
    var handler = StageHandler()

    handler.seriesType = SERIES_TYPE_CANDLESTICK

    // PORT-NOTE (deferred): upstream `plan: createRenderPlanner()`. Left unwired due to the optional-return
    //   mismatch of `StageHandler.plan` — `createRenderPlanner()` yields a nil-for-no-reset plan, but the
    //   `StageHandlerPlan` typealias has a NON-optional return here, so "no reset" cannot be represented
    //   without relaxing that typealias (same deviation as layout/barGrid.swift `handler.plan = nil`). The
    //   `reset` stage still recomputes layout each pass, so the non-progressive render is unaffected.
    _ = createRenderPlanner()
    handler.plan = nil

    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: CandlestickSeriesModel`.
        let seriesModel = seriesModelBase as! CandlestickSeriesModel

        let coordSys = seriesModel.coordinateSystem as! Cartesian2D
        let data = seriesModel.getData()
        let candleWidth = calculateCandleWidth(seriesModel, data)
        let cDimIdx = seriesModel.getWhiskerBoxesLayout() == "horizontal" ? 0 : 1
        let vDimIdx = 1 - cDimIdx
        let coordDims = ["x", "y"]
        let cDimI = data.getDimensionIndex(data.mapDimension(coordDims[cDimIdx])!)
        // const vDimsI = map(data.mapDimensionsAll(coordDims[vDimIdx]), data.getDimensionIndex, data);
        let vDimsI = util.map(data.mapDimensionsAll(coordDims[vDimIdx])) { dim, _ in
            data.getDimensionIndex(dim)
        }
        let openDimI = vDimsI.count > 0 ? vDimsI[0] : -1
        let closeDimI = vDimsI.count > 1 ? vDimsI[1] : -1
        let lowestDimI = vDimsI.count > 2 ? vDimsI[2] : -1
        let highestDimI = vDimsI.count > 3 ? vDimsI[3] : -1

        // data.setLayout({ candleWidth, isSimpleBox: candleWidth <= 1.3 } as CandlestickLayoutMeta);
        data.setLayout([
            "candleWidth": candleWidth,
            // The value is experimented visually.
            "isSimpleBox": candleWidth <= 1.3
        ] as [String: Any])

        if cDimI < 0 || vDimsI.count < 4 {
            return nil
        }

        // ----- normalProgress -----
        func normalProgress(_ params: StageHandlerProgressParams, _ data: SeriesData) {
            // getPoint / addBodyEnd / makeBrushRect / subPixelOptimizePoint — nested helpers upstream.
            func getPoint(_ val: Double, _ axisDimVal: Double) -> [Double] {
                // const p = []; p[cDimIdx] = axisDimVal; p[vDimIdx] = val;
                var p: [Double] = [0, 0]
                p[cDimIdx] = axisDimVal
                p[vDimIdx] = val
                return (axisDimVal.isNaN || val.isNaN)
                    ? [Double.nan, Double.nan]
                    : coordSys.dataToPoint(p)
            }

            func addBodyEnd(_ ends: inout [[Double]], _ point: [Double], _ start: Int) {
                var point1 = point   // point.slice()
                var point2 = point   // point.slice()

                point1[cDimIdx] = subPixelOptimizeNS.subPixelOptimize(
                    point1[cDimIdx] + candleWidth / 2, 1, false
                )
                point2[cDimIdx] = subPixelOptimizeNS.subPixelOptimize(
                    point2[cDimIdx] - candleWidth / 2, 1, true
                )

                // start ? ends.push(point1, point2) : ends.push(point2, point1);
                if start != 0 {
                    ends.append(point1)
                    ends.append(point2)
                }
                else {
                    ends.append(point2)
                    ends.append(point1)
                }
            }

            func makeBrushRect(_ lowestVal: Double, _ highestVal: Double, _ axisDimVal: Double) -> CandlestickBrushRect {
                var pmin = getPoint(lowestVal, axisDimVal)
                var pmax = getPoint(highestVal, axisDimVal)

                pmin[cDimIdx] -= candleWidth / 2
                pmax[cDimIdx] -= candleWidth / 2

                return CandlestickBrushRect(
                    x: pmin[0],
                    y: pmin[1],
                    width: vDimIdx != 0 ? candleWidth : pmax[0] - pmin[0],
                    height: vDimIdx != 0 ? pmax[1] - pmin[1] : candleWidth
                )
            }

            func subPixelOptimizePoint(_ point: [Double]) -> [Double] {
                var point = point
                point[cDimIdx] = subPixelOptimizeNS.subPixelOptimize(point[cDimIdx], 1)
                return point
            }

            // let dataIndex; const store = data.getStore();
            let store = data.getStore()
            while let dataIndexD = params.next?() {
                let dataIndex = Int(dataIndexD)

                let axisDimVal = candlestickNum(store.get(cDimI, dataIndex))
                let openVal = candlestickNum(store.get(openDimI, dataIndex))
                let closeVal = candlestickNum(store.get(closeDimI, dataIndex))
                let lowestVal = candlestickNum(store.get(lowestDimI, dataIndex))
                let highestVal = candlestickNum(store.get(highestDimI, dataIndex))

                let ocLow = number.mathMin(openVal, closeVal)
                let ocHigh = number.mathMax(openVal, closeVal)

                let ocLowPoint = getPoint(ocLow, axisDimVal)
                let ocHighPoint = getPoint(ocHigh, axisDimVal)
                let lowestPoint = getPoint(lowestVal, axisDimVal)
                let highestPoint = getPoint(highestVal, axisDimVal)

                var ends: [[Double]] = []
                addBodyEnd(&ends, ocHighPoint, 0)
                addBodyEnd(&ends, ocLowPoint, 1)

                ends.append(subPixelOptimizePoint(highestPoint))
                ends.append(subPixelOptimizePoint(ocHighPoint))
                ends.append(subPixelOptimizePoint(lowestPoint))
                ends.append(subPixelOptimizePoint(ocLowPoint))

                let itemModel = data.getItemModel(dataIndex)
                let hasDojiColor = candlestickTruthy(itemModel.get(["itemStyle", "borderColorDoji"]))
                data.setItemLayout(dataIndex, CandlestickItemLayout(
                    sign: getSign(store, dataIndex, openVal, closeVal, closeDimI, hasDojiColor),
                    initBaseline: openVal > closeVal
                        ? ocHighPoint[vDimIdx] : ocLowPoint[vDimIdx], // open point.
                    ends: ends,
                    brushRect: makeBrushRect(lowestVal, highestVal, axisDimVal)
                ))
            }
        }

        // ----- largeProgress -----
        // PORT-NOTE (deferred): the large-mode layout produces the flat `largePoints` buffer consumed only
        //   by the DEFERRED large draw path (`LargeBoxPath` in CandlestickView), which is not yet ported.
        //   Ported here for structural fidelity; it is unreachable on the normal render path.
        func largeProgress(_ params: StageHandlerProgressParams, _ data: SeriesData) {
            // Structure: [sign, x, yhigh, ylow, sign, x, yhigh, ylow, ...]
            var points = vendor.createFloat32Array(params.count * 4)
            var offset = 0
            var point: [Double]?
            // PORT-NOTE: upstream reuses scratch `tmpIn`/`tmpOut` arrays with `dataToPoint(tmpIn, null, tmpOut)`
            //   (out-param). The ported `dataToPoint` is value-returning (CONVENTIONS §3), so a fresh 2-vec
            //   is built per call instead.
            var tmpIn: [Double] = [0, 0]
            let store = data.getStore()
            let hasDojiColor = candlestickTruthy(seriesModel.get(["itemStyle", "borderColorDoji"]))

            while let dataIndexD = params.next?() {
                let dataIndex = Int(dataIndexD)
                let axisDimVal = candlestickNum(store.get(cDimI, dataIndex))
                let openVal = candlestickNum(store.get(openDimI, dataIndex))
                let closeVal = candlestickNum(store.get(closeDimI, dataIndex))
                let lowestVal = candlestickNum(store.get(lowestDimI, dataIndex))
                let highestVal = candlestickNum(store.get(highestDimI, dataIndex))

                if axisDimVal.isNaN || lowestVal.isNaN || highestVal.isNaN {
                    points[offset] = Double.nan; offset += 1
                    offset += 3
                    continue
                }

                points[offset] = getSign(store, dataIndex, openVal, closeVal, closeDimI, hasDojiColor); offset += 1

                tmpIn[cDimIdx] = axisDimVal

                tmpIn[vDimIdx] = lowestVal
                point = coordSys.dataToPoint(tmpIn)
                points[offset] = point != nil ? point![0] : Double.nan; offset += 1
                points[offset] = point != nil ? point![1] : Double.nan; offset += 1
                tmpIn[vDimIdx] = highestVal
                point = coordSys.dataToPoint(tmpIn)
                points[offset] = point != nil ? point![1] : Double.nan; offset += 1
            }

            data.setLayout("largePoints", points)
        }

        // return { progress: seriesModel.pipelineContext.large ? largeProgress : normalProgress };
        var executor = StageHandlerProgressExecutor()
        executor.progress = seriesModel.pipelineContext.large ? largeProgress : normalProgress
        return executor
    }

    return handler
}()

/**
 * Get the sign of a single data.
 *
 * @returns 0 for doji with hasDojiColor: true,
 *          1 for positive,
 *          -1 for negative.
 */
// upstream: function getSign(store, dataIndex, openVal, closeVal, closeDimI, hasDojiColor): -1 | 1 | 0
private func getSign(
    _ store: DataStore, _ dataIndex: Int, _ openVal: Double, _ closeVal: Double, _ closeDimI: DimensionIndex,
    _ hasDojiColor: Bool
) -> Double {
    var sign: Double
    if openVal > closeVal {
        sign = -1
    }
    else if openVal < closeVal {
        sign = 1
    }
    else {
        sign = hasDojiColor
            // When doji color is set, use it instead of color/color0.
            ? 0
            : (dataIndex > 0
                // If close === open, compare with close of last record
                ? (candlestickNum(store.get(closeDimI, dataIndex - 1)) <= closeVal ? 1 : -1)
                // No record of previous, set to be positive
                : 1
            )
    }

    return sign
}

// upstream: function calculateCandleWidth(seriesModel: CandlestickSeriesModel, data: SeriesData)
private func calculateCandleWidth(_ seriesModel: CandlestickSeriesModel, _ data: SeriesData) -> Double {
    // upstream: SeriesModel.getBaseAxis() returns Axis2D (via WhiskerBoxCommonMixin); the port's
    //   `getBaseAxis()` returns `Any?` (base signature), so downcast.
    let baseAxis = seriesModel.getBaseAxis() as! Axis

    let bandWidth = calcBandWidth(
        baseAxis,
        CalculateBandWidthOpt(
            fromStat: CalculateBandWidthOpt.FromStat(key: makeAxisStatKey(SERIES_TYPE_CANDLESTICK)),
            min: 1
        )
    ).w

    // PORT-NOTE: the option bag stores explicit-null defaults as `NSNull()` (codebase convention;
    //   see BarSeries.swift). `retrieve2` checks `!= nil`, so `NSNull` would wrongly win over the
    //   fallback; `candlestickDenull` collapses `NSNull` -> nil first (JS `null` == nil, CONVENTIONS §6).
    let barMaxWidth = number.parsePercent(
        util.retrieve2(candlestickDenull(seriesModel.get("barMaxWidth")), bandWidth as Any),
        bandWidth
    )
    let barMinWidth = number.parsePercent(
        util.retrieve2(candlestickDenull(seriesModel.get("barMinWidth")), 1.0 as Any),
        bandWidth
    )
    let barWidth = candlestickDenull(seriesModel.get("barWidth"))

    // return barWidth != null ? parsePercent(barWidth, bandWidth)
    //     : mathMax(mathMin(bandWidth / 2, barMaxWidth), barMinWidth);
    if barWidth != nil {
        return number.parsePercent(barWidth, bandWidth)
    }
    // Put max outer to ensure bar visible in spite of overlap.
    return number.mathMax(number.mathMin(bandWidth / 2, barMaxWidth), barMinWidth)
}

// upstream: export function registerCandlestickAxisHandlers(registers: EChartsExtensionInstallRegisters)
public func registerCandlestickAxisHandlers(_ registers: EChartsExtensionInstallRegisters) {
    callOnlyOnce(registers, {
        let axisStatKey = makeAxisStatKey(SERIES_TYPE_CANDLESTICK)
        requireAxisStatistics(
            registers,
            AxisStatKeyedClient(
                key: axisStatKey,
                seriesType: SERIES_TYPE_CANDLESTICK,
                getMetrics: createMetricsNonOrdinalLinearPositiveMinGap
            )
        )
        registerAxisContainShapeHandler(
            axisStatKey,
            createBandWidthBasedAxisContainShapeHandler(axisStatKey)
        )
    })
}

// ============================================================================
// PORT-NOTE: local helpers (NOT in upstream candlestickLayout.ts).
// ============================================================================

// `store.get(...)` returns `ParsedValue` (Any); numeric candlestick values are stored as `Double`.
//   Mirrors the upstream `store.get(...) as number` coercions.
private func candlestickNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// Collapse the option-bag's `NSNull()` (explicit-null default) to Swift nil, so JS `x != null`
//   checks (`retrieve2`, `barWidth != null`) behave faithfully (CONVENTIONS §6). Not an upstream symbol.
private func candlestickDenull(_ v: Any?) -> Any? {
    return v is NSNull ? nil : v
}

// JS truthiness for `!!itemModel.get(['itemStyle', 'borderColorDoji'])` (nil/''/false/0/NaN are falsy).
private func candlestickTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    default: return true
    }
}

// ============================================================================
// PORT-NOTE (deferred): stubs for `chart/helper/axisSnippets.ts` (PREREQ, not yet ported). Mirror the
//   upstream one-liners so this file compiles; remove them and import the real symbols from
//   chart/helper/axisSnippets.swift when it lands (same pattern as layout/barGrid.swift +
//   layout/barCommon.swift).
//
//   export function makeAxisStatKey(seriesType): AxisStatKey
//   export function createBandWidthBasedAxisContainShapeHandler(axisStatKey): AxisContainShapeHandler
//   export function createMetricsNonOrdinalLinearPositiveMinGap(axis): AxisStatMetrics
// ============================================================================

private func makeAxisStatKey(_ seriesType: ComponentSubType) -> AxisStatKey {
    return seriesType + AXIS_STAT_KEY_DELIMITER
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

private func createMetricsNonOrdinalLinearPositiveMinGap(_ axis: Axis) -> AxisStatMetrics? {
    registerMetricImplLiPosMinGap()
    return AxisStatMetrics(
        // non-category scale do not use `liPosMinGap` to calculate `bandWidth`.
        liPosMinGap: !helper.isOrdinalScale(axis.scale)
    )
}
