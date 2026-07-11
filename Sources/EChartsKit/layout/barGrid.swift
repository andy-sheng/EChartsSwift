// Ported from echarts/src/layout/barGrid.ts — keep in sync with upstream
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
//   import { each, defaults, hasOwn, assert } from 'zrender/src/core/util';
//     -> `util.each` / `util.assert` (ZRenderKit); `defaults` inlined; `hasOwn(o, k)` -> `o[k] != nil` (CONVENTIONS §8)
//   import { mathAbs, mathMax, mathMin, parsePercent } from '../util/number';
//     -> `number.mathAbs` / `number.mathMax` / `number.mathMin` / `number.parsePercent` (util/number.swift)
//   import { isDimensionStacked } from '../data/helper/dataStackHelper';   -> `isDimensionStacked` (top-level free func)
//   import createRenderPlanner from '../chart/helper/createRenderPlanner'; -> `createRenderPlanner` (top-level free func)
//   import Axis2D from '../coord/cartesian/Axis2D';                        -> Axis2D
//   import Cartesian2D from '../coord/cartesian/Cartesian2D';              -> Cartesian2D
//   import { StageHandler, NullUndefined } from '../util/types';           -> StageHandler; NullUndefined -> nil (§6)
//   import { createFloat32Array } from '../util/vendor';                   -> `vendor.createFloat32Array`
//   import { makeCallOnlyOnce } from '../util/model';                      -> `model.makeCallOnlyOnce`
//   import { isOrdinalScale } from '../scale/helper';                      -> `helper.isOrdinalScale`
//   import { isCartesian2DInjectedAsDataCoordSys } from '../coord/cartesian/cartesianAxisHelper';
//     -> `cartesianAxisHelper.isCartesian2DInjectedAsDataCoordSys`
//   import type BaseBarSeriesModel from '../chart/bar/BaseBarSeries';      -> SeriesModel (BaseBarSeries not ported; bar-only scope)
//   import type BarSeriesModel from '../chart/bar/BarSeries';              -> SeriesModel
//   import { AxisContainShapeHandler, registerAxisContainShapeHandler } from '../coord/scaleRawExtentInfo';
//     -> AxisContainShapeHandler / registerAxisContainShapeHandler (coord/scaleRawExtentInfo.swift)
//   import { EChartsExtensionInstallRegisters } from '../extension';
//     -> EChartsExtensionInstallRegisters (stub registrar currently hosted by coord/axisStatistics.swift; Phase 6b)
//   import { eachAxisOnKey, eachSeriesOnAxisOnKey } from '../coord/axisStatistics';
//     -> eachAxisOnKey / eachSeriesOnAxisOnKey (top-level free funcs)
//   import { AxisBandWidthResult, calcBandWidth } from '../coord/axisBand';
//     -> AxisBandWidthResult / calcBandWidth (coord/axisBand.swift)
//   import { BaseBarSeriesSubType, getStartValue, requireAxisStatisticsForBaseBar } from './barCommon';
//     -> BaseBarSeriesSubType / getStartValue / requireAxisStatisticsForBaseBar (layout/barCommon.swift)
//   import { COORD_SYS_TYPE_CARTESIAN_2D } from '../coord/cartesian/GridModel';   -> COORD_SYS_TYPE_CARTESIAN_2D
//   import { createBandWidthBasedAxisContainShapeHandler, makeAxisStatKey2 } from '../chart/helper/axisSnippets';
//     -> chart/helper/axisSnippets.ts NOT yet ported (PREREQ). PORT-TODO stubs at the bottom mirror the
//        upstream one-liners so this file compiles; remove them and import the real symbols once
//        chart/helper/axisSnippets.swift lands.


// PORT-NOTE: `makeCallOnlyOnce()` is generic (`<Host: AnyObject>`); specialize to the registrar type,
//   matching coord/axisStatistics.swift.
private let callOnlyOnce: (EChartsExtensionInstallRegisters, () -> Void) -> Void = model.makeCallOnlyOnce()

private let STACK_PREFIX = "__ec_stack_"

// PORT-NOTE: `getSeriesStackId(seriesModel: BaseBarSeriesModel)`; `BaseBarSeries`/`BarSeries` are not
//   ported (bar-only scope), so `SeriesModel` is used directly — it exposes `get`/`seriesIndex`.
private func getSeriesStackId(_ seriesModel: SeriesModel) -> StackId {
    // ((seriesModel as BarSeriesModel).get('stack') || STACK_PREFIX + seriesModel.seriesIndex) as StackId
    if let stack = seriesModel.get("stack") as? String, !stack.isEmpty {
        return stack
    }
    return STACK_PREFIX + "\(Int(seriesModel.seriesIndex))"
}

private struct BarGridLayoutAxisInfo {
    var seriesInfo: [BarGridLayoutAxisSeriesInfo]
    // Calculated layout width for a single bars group.
    var bandWidthResult: AxisBandWidthResult
}

private struct BarGridLayoutAxisSeriesInfo {
    var barWidth: Double
    var barMaxWidth: Double
    var barMinWidth: Double
    var barGap: Any?              // number | string
    var defaultBarGap: Any?       // number | string | undefined
    var barCategoryGap: Any?      // number | string
    var stackId: StackId
}

// PORT-NOTE: upstream `type StackId = string & {_: 'barGridStackId'}` is a nominal-branded string; the
//   brand is dropped in Swift (aliased to String).
private typealias StackId = String


public struct BarGridLayoutOptionForCustomSeries {
    public var count: Double

    public var barWidth: Any?         // number | string
    public var barMaxWidth: Any?      // number | string
    public var barMinWidth: Any?      // number | string
    public var barGap: Any?           // number | string
    public var barCategoryGap: Any?   // number | string

    public init(
        count: Double,
        barWidth: Any? = nil,
        barMaxWidth: Any? = nil,
        barMinWidth: Any? = nil,
        barGap: Any? = nil,
        barCategoryGap: Any? = nil
    ) {
        self.count = count
        self.barWidth = barWidth
        self.barMaxWidth = barMaxWidth
        self.barMinWidth = barMinWidth
        self.barGap = barGap
        self.barCategoryGap = barCategoryGap
    }
}
// upstream: interface BarGridLayoutOption extends BarGridLayoutOptionForCustomSeries { axis: Axis2D }
public struct BarGridLayoutOption {
    public var count: Double
    public var barWidth: Any?
    public var barMaxWidth: Any?
    public var barMinWidth: Any?
    public var barGap: Any?
    public var barCategoryGap: Any?
    public var axis: Axis2D

    public init(
        count: Double,
        axis: Axis2D,
        barWidth: Any? = nil,
        barMaxWidth: Any? = nil,
        barMinWidth: Any? = nil,
        barGap: Any? = nil,
        barCategoryGap: Any? = nil
    ) {
        self.count = count
        self.axis = axis
        self.barWidth = barWidth
        self.barMaxWidth = barMaxWidth
        self.barMinWidth = barMinWidth
        self.barGap = barGap
        self.barCategoryGap = barCategoryGap
    }
}

// The layout of a bar group (may come from different series but on the same value on the base axis).
// The bars with the same `StackId` are stacked; otherwise they are placed side by side, following
// series declaration order.
// type BarWidthAndOffsetOnAxis = Record<StackId, BarGridLayoutResultItemInternal>;
private typealias BarWidthAndOffsetOnAxis = [StackId: BarGridLayoutResultItemInternal]
// export type BarGridColumnLayoutOnAxis = BarGridLayoutAxisInfo & { columnMap: BarWidthAndOffsetOnAxis };
public struct BarGridColumnLayoutOnAxis {
    fileprivate var seriesInfo: [BarGridLayoutAxisSeriesInfo]
    public var bandWidthResult: AxisBandWidthResult
    fileprivate var columnMap: BarWidthAndOffsetOnAxis
}

private struct BarGridLayoutResultItemInternal {
    var bandWidth: Double // == BarGridLayoutAxisInfo['bandWidthResult']['w']
    var offset: Double    // An offset with respect to `dataToPoint`
    var width: Double
}
// type BarGridLayoutResultItem = BarGridLayoutResultItemInternal & { offsetCenter: number };
public struct BarGridLayoutResultItem {
    public var bandWidth: Double
    public var offset: Double
    public var width: Double
    public var offsetCenter: Double
}
// export type BarGridLayoutResultForCustomSeries = BarGridLayoutResultItem[] | NullUndefined;
public typealias BarGridLayoutResultForCustomSeries = [BarGridLayoutResultItem]?

/**
 * Return null/undefined if not 'category' axis.
 *
 * PENDING: The layout on non-'category' axis relies on `bandWidth`, which is calculated
 * based on the `linearPositiveMinGap` of series data. This strategy is somewhat heuristic
 * and will not be public to custom series until required in future. Additionally, more ec
 * options may be introduced for that, because it requires `requireAxisStatistics` to be
 * called on custom series that requires this feature.
 */
public func computeBarLayoutForCustomSeries(_ opt: BarGridLayoutOption) -> BarGridLayoutResultForCustomSeries {
    if !helper.isOrdinalScale(opt.axis.scale) {
        return nil
    }

    let bandWidthResult = calcBandWidth(opt.axis)

    var params: [BarGridLayoutAxisSeriesInfo] = []
    var i = 0
    while Double(i) < opt.count {   // upstream: `i < opt.count || 0`
        // upstream: defaults({stackId: STACK_PREFIX + i}, opt) as BarGridLayoutAxisSeriesInfo
        // PORT-TODO: `defaults` merges `opt`'s (number | string) bar-size fields into a series-info
        //   whose fields are typed `number`; upstream relies on an unsafe cast. Custom series is not in
        //   the bar-chart scope, so string percents are not resolved here (coerced numerically only).
        params.append(BarGridLayoutAxisSeriesInfo(
            barWidth: barGridOptionSize(opt.barWidth),
            barMaxWidth: barGridOptionSize(opt.barMaxWidth),
            barMinWidth: barGridOptionSize(opt.barMinWidth),
            barGap: opt.barGap,
            defaultBarGap: nil,
            barCategoryGap: opt.barCategoryGap,
            stackId: STACK_PREFIX + "\(i)"
        ))
        i += 1
    }
    let widthAndOffsets = calcBarWidthAndOffset(BarGridLayoutAxisInfo(
        seriesInfo: params,
        bandWidthResult: bandWidthResult
    ))

    var result: [BarGridLayoutResultItem] = []
    var j = 0
    while Double(j) < opt.count {
        // const item = widthAndOffsets[STACK_PREFIX + i] as BarGridLayoutResultItem;
        // item.offsetCenter = item.offset + item.width / 2;
        let internalItem = widthAndOffsets[STACK_PREFIX + "\(j)"]!
        var item = BarGridLayoutResultItem(
            bandWidth: internalItem.bandWidth,
            offset: internalItem.offset,
            width: internalItem.width,
            offsetCenter: 0
        )
        item.offsetCenter = item.offset + item.width / 2
        result.append(item)
        j += 1
    }

    return result
}

/**
 * NOTICE: This layout is based on axis pixel extent and scale extent.
 *  It may be used on estimation, where axis pixel extent and scale extent
 *  are approximately set. But the result should not be cached since the
 *  axis pixel extent and scale extent may be changed finally.
 */
private func makeColumnLayoutOnAxisReal(
    _ baseAxis: Axis2D,
    _ seriesType: BaseBarSeriesSubType
) -> BarGridColumnLayoutOnAxis {
    let seriesInfoListOnAxis = createLayoutInfoListOnAxis(baseAxis, seriesType)
    // seriesInfoListOnAxis.columnMap = calcBarWidthAndOffset(seriesInfoListOnAxis);
    let columnMap = calcBarWidthAndOffset(seriesInfoListOnAxis)
    return BarGridColumnLayoutOnAxis(
        seriesInfo: seriesInfoListOnAxis.seriesInfo,
        bandWidthResult: seriesInfoListOnAxis.bandWidthResult,
        columnMap: columnMap
    )
}

private func createLayoutInfoListOnAxis(
    _ baseAxis: Axis2D,
    _ seriesType: BaseBarSeriesSubType
) -> BarGridLayoutAxisInfo {

    let axisStatKey = makeAxisStatKey2(seriesType, COORD_SYS_TYPE_CARTESIAN_2D)
    var seriesInfoOnAxis: [BarGridLayoutAxisSeriesInfo] = []
    let bandWidthResult = calcBandWidth(
        baseAxis,
        CalculateBandWidthOpt(fromStat: CalculateBandWidthOpt.FromStat(key: axisStatKey), min: 1)
    )

    eachSeriesOnAxisOnKey(baseAxis, axisStatKey, { seriesModel in
        seriesInfoOnAxis.append(BarGridLayoutAxisSeriesInfo(
            barWidth: number.parsePercent(seriesModel.get("barWidth"), bandWidthResult.w),
            barMaxWidth: number.parsePercent(seriesModel.get("barMaxWidth"), bandWidthResult.w),
            barMinWidth: number.parsePercent(
                // barMinWidth by default is 0.5 / 1 in cartesian. Because in value axis,
                // the auto-calculated bar width might be less than 0.5 / 1.
                seriesModel.get("barMinWidth") ?? (isInLargeMode(seriesModel) ? 0.5 : 1), bandWidthResult.w
            ),
            barGap: seriesModel.get("barGap"),
            defaultBarGap: seriesModel.get("defaultBarGap"),
            barCategoryGap: seriesModel.get("barCategoryGap"),
            stackId: getSeriesStackId(seriesModel)
        ))
    })

    return BarGridLayoutAxisInfo(
        seriesInfo: seriesInfoOnAxis,
        bandWidthResult: bandWidthResult
    )
}

/**
 * CAUTION: When multiple series are laid out on one axis, relevant ec options effect all series.
 * But for historical reason, these options are configured on each series option, which may
 * introduce confliction. The legacy implementation uses some options (e.g., `defaultBarGap`)
 * from the first declared series, and other options (e.g., `barGap`, `barCategoryGap`) from the last declared
 * series. Nevertheless, We remain this design to avoid breaking change.
 */
private func calcBarWidthAndOffset(
    _ seriesInfoOnAxis: BarGridLayoutAxisInfo
) -> BarWidthAndOffsetOnAxis {
    // interface StackInfo { width; maxWidth; minWidth? }
    //   Ported as a `final class` (reference), since upstream mutates the entries through the map
    //   (`stackMap[stackId].width = ...`) after retrieval (CONVENTIONS §4).
    final class StackInfo {
        var width: Double
        var maxWidth: Double
        var minWidth: Double?
        init(width: Double, maxWidth: Double) { self.width = width; self.maxWidth = maxWidth }
    }

    let bandWidth = seriesInfoOnAxis.bandWidthResult.w
    var remainedWidth = bandWidth
    var autoWidthCount: Double = 0
    var barCategoryGapOption: Any?   // number | string
    var barGapOption: Any?           // number | string
    var stackIdList: [StackId] = []
    var stackMap: [StackId: StackInfo] = [:]

    util.each(seriesInfoOnAxis.seriesInfo, { seriesInfo, idx in
        if idx == 0 {
            barGapOption = seriesInfo.defaultBarGap ?? 0
        }
        let stackId = seriesInfo.stackId

        if stackMap[stackId] == nil {   // !hasOwn(stackMap, stackId)
            autoWidthCount += 1
        }
        var stackItem = stackMap[stackId]
        if stackItem == nil {
            let created = StackInfo(width: 0, maxWidth: 0)
            stackMap[stackId] = created
            stackItem = created
            stackIdList.append(stackId)
        }

        var barWidth = seriesInfo.barWidth
        // upstream: `if (barWidth && !stackItem.width)`. `barWidth`/`barMaxWidth`/`barMinWidth` come from
        //   `parsePercent(seriesModel.get(...), bandWidth)`, which returns NaN when the option is absent.
        //   JS `if (barWidth)` treats NaN (and 0) as falsy; the previous `barWidth != 0` treated NaN as
        //   TRUTHY, which poisoned `stackItem.width`/`remainedWidth`/`autoWidth` to NaN (→ NaN bar width).
        //   `barGridTruthy` replicates JS number truthiness (0/NaN → false).
        if barGridTruthy(barWidth) && stackItem!.width == 0 {
            // See #6312, do not restrict width.
            stackItem!.width = barWidth
            barWidth = number.mathMin(remainedWidth, barWidth)
            remainedWidth -= barWidth
        }

        let barMaxWidth = seriesInfo.barMaxWidth
        if barGridTruthy(barMaxWidth) { stackItem!.maxWidth = barMaxWidth }
        let barMinWidth = seriesInfo.barMinWidth
        if barGridTruthy(barMinWidth) { stackItem!.minWidth = barMinWidth }
        let barGap = seriesInfo.barGap
        if barGap != nil { barGapOption = barGap }
        let barCategoryGap = seriesInfo.barCategoryGap
        if barCategoryGap != nil { barCategoryGapOption = barCategoryGap }
    })

    if barCategoryGapOption == nil {
        // More columns in one group
        // the spaces between group is smaller. Or the column will be too thin.
        barCategoryGapOption = "\(Int(number.mathMax(35 - Double(stackIdList.count) * 4, 15)))%"
    }

    let barCategoryGapNum = number.parsePercent(barCategoryGapOption, bandWidth)
    let barGapPercent = number.parsePercent(barGapOption, 1)

    var autoWidth = (remainedWidth - barCategoryGapNum)
        / (autoWidthCount + (autoWidthCount - 1) * barGapPercent)
    autoWidth = number.mathMax(autoWidth, 0)

    // Find if any auto calculated bar exceeded maxBarWidth
    util.each(stackIdList, { stackId, _ in
        let column = stackMap[stackId]!
        let maxWidth = column.maxWidth
        let minWidth = column.minWidth

        if column.width == 0 {
            var finalWidth = autoWidth
            if maxWidth != 0 && maxWidth < finalWidth {
                finalWidth = number.mathMin(maxWidth, remainedWidth)
            }
            // `minWidth` has higher priority. `minWidth` decide that whether the
            // bar is able to be visible. So `minWidth` should not be restricted
            // by `maxWidth` or `remainedWidth` (which is from `bandWidth`). In
            // the extreme cases for `value` axis, bars are allowed to overlap
            // with each other if `minWidth` specified.
            if let minWidth = minWidth, minWidth != 0, minWidth > finalWidth {
                finalWidth = minWidth
            }
            if finalWidth != autoWidth {
                column.width = finalWidth
                remainedWidth -= finalWidth + barGapPercent * finalWidth
                autoWidthCount -= 1
            }
        }
        else {
            // `barMinWidth/barMaxWidth` has higher priority than `barWidth`, as
            // CSS does. Because barWidth can be a percent value, where
            // `barMaxWidth` can be used to restrict the final width.
            var finalWidth = column.width
            if maxWidth != 0 {
                finalWidth = number.mathMin(finalWidth, maxWidth)
            }
            // `minWidth` has higher priority, as described above
            if let minWidth = minWidth, minWidth != 0 {
                finalWidth = number.mathMax(finalWidth, minWidth)
            }
            column.width = finalWidth
            remainedWidth -= finalWidth + barGapPercent * finalWidth
            autoWidthCount -= 1
        }
    })

    // Recalculate width again
    autoWidth = (remainedWidth - barCategoryGapNum)
        / (autoWidthCount + (autoWidthCount - 1) * barGapPercent)

    autoWidth = number.mathMax(autoWidth, 0)

    var widthSum: Double = 0
    var lastColumn: StackInfo?
    util.each(stackIdList, { stackId, _ in
        let column = stackMap[stackId]!
        if column.width == 0 {
            column.width = autoWidth
        }
        lastColumn = column
        widthSum += column.width * (1 + barGapPercent)
    })
    if let lastColumn = lastColumn {
        widthSum -= lastColumn.width * barGapPercent
    }

    var result: BarWidthAndOffsetOnAxis = [:]

    var offset = -widthSum / 2
    util.each(stackIdList, { stackId, _ in
        let column = stackMap[stackId]!
        result[stackId] = result[stackId] ?? BarGridLayoutResultItemInternal(
            bandWidth: bandWidth,
            offset: offset,
            width: column.width
        )
        offset += column.width * (1 + barGapPercent)
    })

    return result
}

public func createCrossSeriesLayoutHandler(_ seriesType: BaseBarSeriesSubType) -> StageHandler {
    var handler = StageHandler()

    handler.seriesType = seriesType

    handler.overallReset = { ecModel, _, _ in
        let axisStatKey = makeAxisStatKey2(seriesType, COORD_SYS_TYPE_CARTESIAN_2D)
        eachAxisOnKey(ecModel, axisStatKey, { axisBase in
            if __DEV__ {
                util.assert(axisBase is Axis2D)
            }
            let axis = axisBase as! Axis2D
            let columnLayout = makeColumnLayoutOnAxisReal(axis, seriesType)

            eachSeriesOnAxisOnKey(axis, axisStatKey, { seriesModel in
                let columnLayoutInfo = columnLayout.columnMap[getSeriesStackId(seriesModel)]!
                seriesModel.getData().setLayout([
                    "bandWidth": columnLayoutInfo.bandWidth,
                    "offset": columnLayoutInfo.offset,
                    "size": columnLayoutInfo.width
                ])
            })
        })
    }

    return handler
}


// TODO: Do not support stack in large mode yet.
public func createProgressiveLayout(_ seriesType: String) -> StageHandler {
    var handler = StageHandler()

    handler.seriesType = seriesType

    // PORT-TODO: upstream `plan: createRenderPlanner()`. The ported `createRenderPlanner()` yields a
    //   `(SeriesModel) -> StageHandlerPlanReturn?` (nil == no reset), but `StageHandler.plan`
    //   (`StageHandlerPlan`) has a NON-optional `StageHandlerPlanReturn` return in this port, so
    //   "no reset" cannot be represented without either forcing `.reset` (spurious re-plans) or
    //   relaxing the `StageHandlerPlan` typealias to an optional return. Left unwired until that
    //   typealias is relaxed; for the non-progressive bar path the `reset` stage still recomputes
    //   layout each pass, so basic rendering is unaffected. See util/types.swift `StageHandlerPlan`.
    _ = createRenderPlanner()
    handler.plan = nil

    handler.reset = { seriesModel, _, _, _ -> Any? in
        if !cartesianAxisHelper.isCartesian2DInjectedAsDataCoordSys(seriesModel) {
            return nil
        }

        let data = seriesModel.getData()

        let cartesian = seriesModel.coordinateSystem as! Cartesian2D
        let baseAxis = cartesian.getBaseAxis()
        let valueAxis = cartesian.getOtherAxis(baseAxis)
        // PORT-TODO: `mapDimension` returns `String?`; for a bar's value/base axis the mapped dim is
        //   always present, so it is force-unwrapped (upstream passes it straight into `getDimensionIndex`).
        let valueDimIdx = data.getDimensionIndex(data.mapDimension(valueAxis.dim)!)
        let baseDimIdx = data.getDimensionIndex(data.mapDimension(baseAxis.dim)!)
        let drawBackground = (seriesModel.get("showBackground", true) as? Bool) ?? false
        let valueDim = data.mapDimension(valueAxis.dim)
        let stackResultDim = data.getCalculationInfo("stackResultDimension") as? String
        let stacked = isDimensionStacked(data, valueDim!)
            && barGridTruthy(data.getCalculationInfo("stackedOnSeries"))
        let isValueAxisH = valueAxis.isHorizontal()

        let valueAxisStart = valueAxis.toGlobalCoord(valueAxis.dataToCoord(getStartValue(valueAxis)))

        let isLarge = isInLargeMode(seriesModel)
        let barMinHeight = (seriesModel.get("barMinHeight") as? Double) ?? 0

        // stackedDimIdx = stackResultDim && data.getDimensionIndex(stackResultDim)
        let stackedDimIdx: Double? = barGridTruthy(stackResultDim)
            ? data.getDimensionIndex(stackResultDim!) : nil

        // Layout info.
        let columnWidth = (data.getLayout("size") as? Double) ?? Double.nan
        let columnOffset = (data.getLayout("offset") as? Double) ?? Double.nan

        var exec = StageHandlerProgressExecutor()
        exec.progress = { params, data in
            let count = params.count
            // PORT-NOTE: large mode is simplified — arrays are always materialized (empty when
            //   inactive) rather than JS's `isLarge && createFloat32Array(...)` short-circuit; stacking
            //   is not supported in large mode (per upstream TODO).
            var largePoints = isLarge ? vendor.createFloat32Array(count * 3) : []
            var largeBackgroundPoints = (isLarge && drawBackground) ? vendor.createFloat32Array(count * 3) : []
            var largeDataIndices = isLarge ? vendor.createFloat32Array(count) : []
            // upstream: `const coordLayout = cartesian.master.getRect();` (master is `Grid`).
            // PORT: `Cartesian2D.master` is typed `CoordinateSystemMaster?`, whose optional
            //   `getRect(): RectLike?` requirement is NOT witnessed by `Grid.getRect(): LayoutRect`
            //   (so the protocol default nil is used → a nil unwrap crash here). Narrow to the concrete
            //   `Grid` — the same pattern every other `getRect` caller uses (installSimple.swift,
            //   CartesianAxisView.swift).
            let coordLayout = (cartesian.master as! Grid).getRect()
            let bgSize = isValueAxisH ? coordLayout.width : coordLayout.height

            let store = data.getStore()

            var idxOffset = 0

            let next = params.next
            while let dataIndexD = next?() {
                let dataIndex = Int(dataIndexD)
                let value = store.get(stacked ? stackedDimIdx! : valueDimIdx, dataIndex)
                let baseValue = barGridToNumber(store.get(baseDimIdx, dataIndex))
                var baseCoord = valueAxisStart
                var stackStartValue: Double = 0

                // Because of the barMinHeight, we can not use the value in
                // stackResultDimension directly.
                if stacked {
                    stackStartValue = barGridToNumber(value) - barGridToNumber(store.get(valueDimIdx, dataIndex))
                }

                var x: Double
                var y: Double
                var width: Double
                var height: Double

                if isValueAxisH {
                    let coord = cartesian.dataToPoint([value, baseValue])
                    if stacked {
                        baseCoord = cartesian.dataToPoint([stackStartValue, baseValue])[0]
                    }
                    x = baseCoord
                    y = coord[1] + columnOffset
                    width = coord[0] - baseCoord
                    height = columnWidth

                    if number.mathAbs(width) < barMinHeight {
                        width = (width < 0 ? -1 : 1) * barMinHeight
                    }
                }
                else {
                    let coord = cartesian.dataToPoint([baseValue, value])
                    if stacked {
                        baseCoord = cartesian.dataToPoint([baseValue, stackStartValue])[1]
                    }
                    x = coord[0] + columnOffset
                    y = baseCoord
                    width = columnWidth
                    height = coord[1] - baseCoord

                    if number.mathAbs(height) < barMinHeight {
                        // Include zero to has a positive bar
                        height = (height <= 0 ? -1 : 1) * barMinHeight
                    }
                }

                if !isLarge {
                    data.setItemLayout(dataIndex, ["x": x, "y": y, "width": width, "height": height])
                }
                else {
                    largePoints[idxOffset] = x
                    largePoints[idxOffset + 1] = y
                    largePoints[idxOffset + 2] = isValueAxisH ? width : height

                    if !largeBackgroundPoints.isEmpty {
                        largeBackgroundPoints[idxOffset] = isValueAxisH ? coordLayout.x : x
                        largeBackgroundPoints[idxOffset + 1] = isValueAxisH ? y : coordLayout.y
                        largeBackgroundPoints[idxOffset + 2] = bgSize
                    }

                    largeDataIndices[dataIndex] = dataIndexD
                }

                idxOffset += 3
            }

            if isLarge {
                var layout: [String: Any] = [
                    "largePoints": largePoints,
                    "largeDataIndices": largeDataIndices,
                    "valueAxisHorizontal": isValueAxisH
                ]
                if drawBackground {
                    layout["largeBackgroundPoints"] = largeBackgroundPoints
                }
                data.setLayout(layout)
            }
        }
        return exec
    }

    return handler
}

private func isInLargeMode(_ seriesModel: SeriesModel) -> Bool {
    return seriesModel.pipelineContext != nil && seriesModel.pipelineContext.large
}

private func barGridCreateAxisContainShapeHandler(_ seriesType: BaseBarSeriesSubType) -> AxisContainShapeHandler {
    // See also #6728, #4862, `test/bar-overflow-time-plot.html` `test/bar-overflow-plot2.html`
    // NOTE:
    //  Series shapes may overflow `bandWidth` when ec option is set like:
    //    - `barWidth` > 100%.
    //    - `barWidth` is set as absolute pixel values and `dataZoom` is used, since `bandWidth` is
    //      calculated on data space rather than pixel space.
    //  We originally used `calcShapeOverflowSupplement` to cover this case, but it still can not
    //  resolve pixel `barWidth` case perfectly. A thorough solution may introduce considerable complex,
    //  but may not necessary, since users can avoid it by proper ec option settings.
    //  Therefore, we use simply `createBandWidthBasedAxisContainShapeHandler` to calculate "containShape"
    //  only based on `bandWidth`.
    return createBandWidthBasedAxisContainShapeHandler(
        makeAxisStatKey2(seriesType, COORD_SYS_TYPE_CARTESIAN_2D)
    )
    // return function (axis, scale, ecModel) {
    //     if (!countSeriesOnAxisOnKey(axis, makeAxisStatKey2(seriesType, COORD_SYS_TYPE_CARTESIAN_2D))) {
    //         return; // Quick path - in most cases there is no bar on non-ordinal axis.
    //     }
    //     const columnLayout = makeColumnLayoutOnAxisReal(axis, seriesType);
    //     return calcShapeOverflowSupplement(columnLayout);
    // };
}

// /**
//  * @see [AXIS_CONTAIN_SHAPE_COMMON_STRATEGY] for more details.
//  */
// function calcShapeOverflowSupplement(
//     columnLayout: BarGridColumnLayoutOnAxis | NullUndefined
// ): number[] | NullUndefined {
//     if (columnLayout == null) {
//         return;
//     }
//     const bandWidthResult = columnLayout.bandWidthResult;
//     const invRatio = bandWidthResult.invRatio;
//     if (!isNullableNumberFinite(invRatio)) {
//         return; // No series data or no more than one distinct valid data values.
//     }
//     const barsBoundPx = initExtentForUnion();
//     const bandWidth = bandWidthResult.w;
//     // Union `-bandWidth / 2` and `bandWidth / 2` to provide extra space for visually preferred,
//     // Otherwise the bars on the edges may overlap with axis line.
//     // And it also includes `0`, which ensures `barsBoundPx[0] <= 0 <= barsBoundPx[1]`.
//     unionExtentFromNumber(barsBoundPx, -bandWidth / 2);
//     unionExtentFromNumber(barsBoundPx, bandWidth / 2);
//     // Shapes may overflow the `bandWidth`. For example, that might happen in `pictorialBar`.
//     // Therefore, we also involve shape size (mapped to data scale) in this expansion calculation.
//     each(columnLayout.columnMap, function (item) {
//         unionExtentFromNumber(barsBoundPx, item.offset);
//         unionExtentFromNumber(barsBoundPx, item.offset + item.width);
//     });
//     if (extentHasValue(barsBoundPx)) {
//         // Convert from pixel domain to data domain, since the `barsBoundPx` is calculated based on
//         // `minGap` and extent on data domain.
//         return [barsBoundPx[0] * invRatio, barsBoundPx[1] * invRatio];
//         // If AXIS_BAND_WIDTH_KIND_SINGULAR, extent expansion is not needed.
//     }
// }

public func registerBarGridAxisHandlers(_ registers: EChartsExtensionInstallRegisters) {
    callOnlyOnce(registers, {

        func register(_ seriesType: BaseBarSeriesSubType) {
            let axisStatKey = makeAxisStatKey2(seriesType, COORD_SYS_TYPE_CARTESIAN_2D)
            requireAxisStatisticsForBaseBar(
                registers,
                axisStatKey,
                seriesType,
                COORD_SYS_TYPE_CARTESIAN_2D
            )
            registerAxisContainShapeHandler(
                axisStatKey,
                barGridCreateAxisContainShapeHandler(seriesType)
            )
        }

        register("bar")
        register("pictorialBar")
    })
}


// ============================================================================
// PORT-NOTE: local port helpers (NOT in upstream barGrid.ts).
// ============================================================================

// `store.get(...)` returns `ParsedValue` (Any); numeric bar data is stored as `Double`. Mirrors the
//   upstream `+value` / `as number` numeric coercions in `createProgressiveLayout`'s `progress`.
private func barGridToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// JS truthiness for the dynamic option-bag values read via `getCalculationInfo` (`!!x`, `x && ...`).
private func barGridTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Coerce a custom-series bar-size option (`number | string`) to `Double`. Numbers pass through;
//   `nil`/strings collapse to `0` (so upstream's `if (barWidth && ...)` reads as falsy).
// PORT-TODO: string percents (e.g. "50%") are not resolved here — custom series is out of bar scope.
private func barGridOptionSize(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}


// ============================================================================
// PORT-TODO: stubs for `chart/helper/axisSnippets.ts` (PREREQ, not yet ported). Mirror the upstream
//   one-liners so this file compiles; remove them and import the real symbols from
//   chart/helper/axisSnippets.swift when it lands (as barCommon.swift does for its stub).
//
//   export function createBandWidthBasedAxisContainShapeHandler(axisStatKey): AxisContainShapeHandler
//   export function makeAxisStatKey2(seriesType, coordSysType): AxisStatKey
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
