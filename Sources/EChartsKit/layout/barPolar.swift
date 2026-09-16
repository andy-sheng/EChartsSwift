// Ported from echarts/src/layout/barPolar.ts — keep in sync with upstream
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
//   import {mathAbs, mathMax, mathMin, mathPI, parsePercent} from '../util/number';
//     -> `number.mathAbs` / `number.mathMax` / `number.mathMin` / `Double.pi` / `number.parsePercent`.
//   import {isDimensionStacked} from '../data/helper/dataStackHelper';   -> `isDimensionStacked` (free func).
//   import type BarSeriesModel from '../chart/bar/BarSeries';            -> `SeriesModel` (bar-only scope).
//   import type Polar from '../coord/polar/Polar';                       -> `Polar`.
//   import AngleAxis from '../coord/polar/AngleAxis';                    -> `AngleAxis`.
//   import RadiusAxis from '../coord/polar/RadiusAxis';                  -> `RadiusAxis`.
//   import GlobalModel from '../model/Global';                           -> `GlobalModel`.
//   import { Dictionary } from '../util/types';                          -> `[String: T]`.
//   import { calcBandWidth } from '../coord/axisBand';                   -> `calcBandWidth` (coord/axisBand.swift).
//   import { createBandWidthBasedAxisContainShapeHandler, makeAxisStatKey2 } from '../chart/helper/axisSnippets';
//     -> TODO: chart/helper/axisSnippets.ts NOT yet ported (PREREQ). The stubs at the
//        bottom mirror the upstream one-liners so this file compiles (same convention as barGrid.swift).
//   import { createSimpleOverallStageHandler, makeCallOnlyOnce } from '../util/model';
//     -> `model.makeCallOnlyOnce`; the overall stage handler is invoked directly by the ECharts driver
//        (see ECharts.swift layout stage), so `createSimpleOverallStageHandler` collapses to the bare
//        `barLayoutPolar(ecModel)` free function exported below (same as `pieLayout` / `boxplotLayout`).
//   import { EChartsExtensionInstallRegisters } from '../extension';     -> stub registrar (axisStatistics.swift).
//   import { registerAxisContainShapeHandler } from '../coord/scaleRawExtentInfo';
//     -> `registerAxisContainShapeHandler`.
//   import { getStartValue, requireAxisStatisticsForBaseBar, SERIES_TYPE_BAR } from './barCommon';
//     -> `getStartValue` / `requireAxisStatisticsForBaseBar` / `SERIES_TYPE_BAR`.
//   import { eachAxisOnKey, eachSeriesOnAxisOnKey } from '../coord/axisStatistics';
//     -> `eachAxisOnKey` / `eachSeriesOnAxisOnKey`.
//   import { COORD_SYS_TYPE_POLAR } from '../coord/polar/PolarModel';    -> `COORD_SYS_TYPE_POLAR`.
//   import type Axis from '../coord/Axis';                               -> `Axis`.
//   import { assert, each } from 'zrender/src/core/util';                -> `util.assert` / `util.each`.


// `makeCallOnlyOnce()` is generic (`<Host: AnyObject>`); specialize to the registrar type,
//   matching barGrid.swift / axisStatistics.swift.
private let callOnlyOnce: (EChartsExtensionInstallRegisters, () -> Void) -> Void = model.makeCallOnlyOnce()

// upstream: type PolarAxis = AngleAxis | RadiusAxis; (dev assert only).

// upstream: interface StackInfo { width; maxWidth }
//   Reference semantics (mutated through the map after retrieval, like barGrid's StackInfo) → `final class`.
private final class StackInfo {
    var width: Double = 0
    var maxWidth: Double = 0
}

// upstream: interface BarWidthAndOffset { width; offset }
private struct BarWidthAndOffset {
    var width: Double
    var offset: Double
}

// upstream: type StackId = string;
private typealias StackId = String

// upstream: type BarWidthAndOffsetOnAxis = Record<StackId, BarWidthAndOffset>;
private typealias BarWidthAndOffsetOnAxis = [StackId: BarWidthAndOffset]

// upstream: type LastStackCoords = Record<StackId, {p: number, n: number}[]>;
//   `{p, n}` is mutated in place → `final class`; the outer per-baseValue array is sparse (indexed by the
//   category ordinal), modeled as `[Int: LastStackCoord]`.
private final class LastStackCoord {
    var p: Double
    var n: Double
    init(p: Double, n: Double) { self.p = p; self.n = n }
}
private typealias LastStackCoords = [StackId: [Int: LastStackCoord]]

private let STACK_PREFIX = "__ec_stack_"

// upstream: function getSeriesStackId(seriesModel) { return seriesModel.get('stack') || '__ec_stack_' + seriesModel.seriesIndex; }
private func getSeriesStackId(_ seriesModel: SeriesModel) -> StackId {
    if let stack = seriesModel.get("stack") as? String, !stack.isEmpty {
        return stack
    }
    return STACK_PREFIX + "\(Int(seriesModel.seriesIndex))"
}

// upstream: export const barLayoutPolarStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_BAR, barLayoutPolar);
//   Exposed as a bare `(GlobalModel) -> Void` invoked by the ECharts driver (see the import note above).
public func barLayoutPolar(_ ecModel: GlobalModel) {
    let axisStatKey = makeAxisStatKey2(SERIES_TYPE_BAR, COORD_SYS_TYPE_POLAR)

    eachAxisOnKey(ecModel, axisStatKey, { axis in
        if __DEV__ {
            util.assert((axis is AngleAxis) || (axis is RadiusAxis))
        }

        let barWidthAndOffset = calcRadialBar(axis, SERIES_TYPE_BAR)

        var lastStackCoords: LastStackCoords = [:]
        eachSeriesOnAxisOnKey(axis, axisStatKey, { seriesModel in
            layoutPerAxisPerSeries(axis, seriesModel, barWidthAndOffset, &lastStackCoords)
        })
    })
}

private func layoutPerAxisPerSeries(
    _ baseAxis: Axis,
    _ seriesModel: SeriesModel,
    _ barWidthAndOffset: BarWidthAndOffsetOnAxis,
    _ lastStackCoords: inout LastStackCoords
) {
    let data = seriesModel.getData()
    let stackId = getSeriesStackId(seriesModel)
    guard let columnLayoutInfo = barWidthAndOffset[stackId] else {
        return
    }
    let columnOffset = columnLayoutInfo.offset
    let columnWidth = columnLayoutInfo.width
    // const polar = seriesModel.coordinateSystem as Polar;
    guard let polar = seriesModel.coordinateSystem as? Polar else {
        return
    }
    let valueAxis = polar.getOtherAxis(baseAxis)

    let cx = polar.cx
    let cy = polar.cy

    let barMinHeight = (seriesModel.get("barMinHeight") as? Double) ?? 0
    let barMinAngle = (seriesModel.get("barMinAngle") as? Double) ?? 0

    if lastStackCoords[stackId] == nil {
        lastStackCoords[stackId] = [:]
    }

    // POTENTIAL-BUG: `mapDimension` returns `String?`; for a bar's value/base axis the mapped dim is
    //   always present (matches barGrid.swift), so force-unwrapped.
    let valueDim = data.mapDimension(valueAxis.dim)!
    let baseDim = data.mapDimension(baseAxis.dim)!
    let stacked = isDimensionStacked(data, valueDim /* , baseDim */)
    // clampLayout = baseAxis.dim !== 'radius' || !seriesModel.get('roundCap', true)
    let roundCap = (seriesModel.get("roundCap", true) as? Bool) ?? false
    let clampLayout = baseAxis.dim != "radius" || !roundCap

    let valueAxisStart = valueAxis.dataToCoord(getStartValue(valueAxis))

    let len = data.count()
    for idx in 0..<len {
        let value = polarToNumber(data.get(valueDim, idx))
        let baseValue = polarToNumber(data.get(baseDim, idx))
        // `baseValue` indexes lastStackCoords per category (ordinal number).
        let baseValueKey = Int(baseValue)

        let sign = value >= 0 ? "p" : "n"
        var baseCoord = valueAxisStart

        // Because of the barMinHeight, we can not use the value in
        // stackResultDimension directly.
        if stacked {
            // FIXME: follow the same logic in `barGrid.ts`:
            //  Use stackResultDimension, and lastStackCoords is not needed.
            if lastStackCoords[stackId]![baseValueKey] == nil {
                lastStackCoords[stackId]![baseValueKey] = LastStackCoord(
                    p: valueAxisStart, // Positive stack
                    n: valueAxisStart  // Negative stack
                )
            }
            // Should also consider #4243
            let coord = lastStackCoords[stackId]![baseValueKey]!
            baseCoord = (sign == "p") ? coord.p : coord.n
        }

        var r0: Double
        var r: Double
        var startAngle: Double
        var endAngle: Double

        // radial sector
        if valueAxis.dim == "radius" {
            var radiusSpan = valueAxis.dataToCoord(value) - valueAxisStart
            let angle = baseAxis.dataToCoord(baseValue)

            if number.mathAbs(radiusSpan) < barMinHeight {
                radiusSpan = (radiusSpan < 0 ? -1 : 1) * barMinHeight
            }

            r0 = baseCoord
            r = baseCoord + radiusSpan
            startAngle = angle - columnOffset
            endAngle = startAngle - columnWidth

            if stacked {
                lastStackCoords[stackId]![baseValueKey].map { sign == "p" ? ($0.p = r) : ($0.n = r) }
            }
        }
        // tangential sector
        else {
            var angleSpan = valueAxis.dataToCoord(value, clampLayout) - valueAxisStart
            let radius = baseAxis.dataToCoord(baseValue)

            if number.mathAbs(angleSpan) < barMinAngle {
                angleSpan = (angleSpan < 0 ? -1 : 1) * barMinAngle
            }

            r0 = radius + columnOffset
            r = r0 + columnWidth
            startAngle = baseCoord
            endAngle = baseCoord + angleSpan

            if stacked {
                lastStackCoords[stackId]![baseValueKey].map { sign == "p" ? ($0.p = endAngle) : ($0.n = endAngle) }
            }
        }

        data.setItemLayout(idx, [
            "cx": cx,
            "cy": cy,
            "r0": r0,
            "r": r,
            // Consider that positive angle is anti-clockwise,
            // while positive radian of sector is clockwise
            "startAngle": -startAngle * Double.pi / 180,
            "endAngle": -endAngle * Double.pi / 180,
            //  Keep the same logic with bar in catesion: use end value to
            //  control direction. Notice that if clockwise is true (by
            //  default), the sector will always draw clockwisely, no matter
            //  whether endAngle is greater or less than startAngle.
            "clockwise": startAngle >= endAngle
        ] as [String: Any])
    }
}

/**
 * Calculate bar width and offset for radial bar charts
 */
private func calcRadialBar(_ axis: Axis, _ seriesType: String) -> BarWidthAndOffsetOnAxis {
    let axisStatKey = makeAxisStatKey2(seriesType, COORD_SYS_TYPE_POLAR)

    let bandWidth = calcBandWidth(
        axis,
        CalculateBandWidthOpt(fromStat: CalculateBandWidthOpt.FromStat(key: axisStatKey), min: 1)
    ).w

    var remainedWidth = bandWidth
    var autoWidthCount: Double = 0
    var categoryGapOption: Any? = "20%"
    var gapOption: Any? = "30%"
    var stacks: [StackId: StackInfo] = [:]
    var stackIdList: [StackId] = []

    eachSeriesOnAxisOnKey(axis, axisStatKey, { seriesModel in
        let stackId = getSeriesStackId(seriesModel)

        if stacks[stackId] == nil {
            autoWidthCount += 1
            let created = StackInfo()
            stacks[stackId] = created
            stackIdList.append(stackId)
        }
        let stackItem = stacks[stackId]!

        var barWidth = number.parsePercent(seriesModel.get("barWidth"), bandWidth)
        let barMaxWidth = number.parsePercent(seriesModel.get("barMaxWidth"), bandWidth)
        let barGapOption = seriesModel.get("barGap")
        let barCategoryGapOption = seriesModel.get("barCategoryGap")

        // upstream: `if (barWidth && !stacks[stackId].width)`. `parsePercent` returns NaN when absent;
        //   JS treats NaN (and 0) as falsy → `polarTruthy` replicates it (matches barGrid's barGridTruthy).
        if polarTruthy(barWidth) && stackItem.width == 0 {
            barWidth = number.mathMin(remainedWidth, barWidth)
            stackItem.width = barWidth
            remainedWidth -= barWidth
        }

        if polarTruthy(barMaxWidth) { stackItem.maxWidth = barMaxWidth }
        // For historical design, use the last series declared that.
        if barGapOption != nil { gapOption = barGapOption }
        if barCategoryGapOption != nil { categoryGapOption = barCategoryGapOption }
    })

    var result: BarWidthAndOffsetOnAxis = [:]

    let categoryGap = number.parsePercent(categoryGapOption, bandWidth)
    let barGapPercent = number.parsePercent(gapOption, 1)

    var autoWidth = (remainedWidth - categoryGap)
        / (autoWidthCount + (autoWidthCount - 1) * barGapPercent)
    autoWidth = number.mathMax(autoWidth, 0)

    // Find if any auto calculated bar exceeded maxBarWidth
    util.each(stackIdList, { stackId, _ in
        let column = stacks[stackId]!
        var maxWidth = column.maxWidth
        if maxWidth != 0 && maxWidth < autoWidth {
            maxWidth = number.mathMin(maxWidth, remainedWidth)
            if column.width != 0 {
                maxWidth = number.mathMin(maxWidth, column.width)
            }
            remainedWidth -= maxWidth
            column.width = maxWidth
            autoWidthCount -= 1
        }
    })

    // Recalculate width again
    autoWidth = (remainedWidth - categoryGap)
        / (autoWidthCount + (autoWidthCount - 1) * barGapPercent)
    autoWidth = number.mathMax(autoWidth, 0)

    var widthSum: Double = 0
    var lastColumn: StackInfo?
    util.each(stackIdList, { stackId, _ in
        let column = stacks[stackId]!
        if column.width == 0 {
            column.width = autoWidth
        }
        lastColumn = column
        widthSum += column.width * (1 + barGapPercent)
    })
    if let lastColumn = lastColumn {
        widthSum -= lastColumn.width * barGapPercent
    }

    var offset = -widthSum / 2
    util.each(stackIdList, { stackId, _ in
        let column = stacks[stackId]!
        if result[stackId] == nil {
            result[stackId] = BarWidthAndOffset(width: column.width, offset: offset)
        }
        offset += column.width * (1 + barGapPercent)
    })

    return result
}

// upstream: export function registerBarPolarAxisHandlers(registers, seriesType)
public func registerBarPolarAxisHandlers(
    _ registers: EChartsExtensionInstallRegisters,
    _ seriesType: String  // Currently only 'bar' is supported.
) {
    callOnlyOnce(registers, {
        let axisStatKey = makeAxisStatKey2(seriesType, COORD_SYS_TYPE_POLAR)
        requireAxisStatisticsForBaseBar(
            registers,
            axisStatKey,
            seriesType,
            COORD_SYS_TYPE_POLAR
        )
        registerAxisContainShapeHandler(
            axisStatKey,
            createBandWidthBasedAxisContainShapeHandler(axisStatKey)
        )
    })
}


// ============================================================================
// local port helpers (NOT in upstream barPolar.ts).
// ============================================================================

// `data.get(...)` returns `ParsedValue` (Any); numeric bar data is stored as `Double`. Mirrors the
//   upstream `as number` numeric coercions (matches barGrid.swift `barGridToNumber`).
private func polarToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// JS truthiness for the dynamic option-bag / parsePercent values (`!!x`, `x && ...`) — 0/NaN → false.
private func polarTruthy(_ v: Double) -> Bool {
    return v != 0 && !v.isNaN
}


// ============================================================================
// TODO: stubs for `chart/helper/axisSnippets.ts` (PREREQ, not yet ported). Mirror the
//   upstream one-liners so this file compiles; remove them and import the real symbols from
//   chart/helper/axisSnippets.swift when it lands (same convention as barGrid.swift's identical stubs —
//   these must stay behavior-identical to barGrid's copies).
// ============================================================================

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

private func makeAxisStatKey2(_ seriesType: ComponentSubType, _ coordSysType: String) -> AxisStatKey {
    return seriesType + AXIS_STAT_KEY_DELIMITER + coordSysType
}
