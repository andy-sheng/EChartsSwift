// Ported from echarts/src/coord/Axis.ts — keep in sync with upstream
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

// import {each, map} from 'zrender/src/core/util';                    -> ZRenderKit caseless enum `util` (`util.each`, `util.map`)
// import {linearMap} from '../util/number';                           -> EChartsKit `number.linearMap` (util/number.swift)
// import {
//     createAxisTicks, createAxisLabels, calculateCategoryInterval,
//     AxisLabelsComputingContext, AxisTickLabelComputingKind,
//     createAxisLabelsComputingContext, AxisLabelInfoDetermined,
// } from './axisTickLabelBuilder';                                     -> top-level free funcs/types (coord/axisTickLabelBuilder.swift)
//   PORT-TODO: coord/axisTickLabelBuilder.swift is a sibling landing this phase (mutually recursive with
//   this file). This file references its conventional public API:
//     - createAxisTicks(_ axis: Axis, _ axisModel: AxisBaseModel, _ opt: CreateAxisTicksOpt?) -> (ticks: [ScaleTick], ...)
//     - createAxisLabels(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> (labels: [AxisLabelInfoDetermined], ...)
//     - calculateCategoryInterval(_ axis: Axis, _ ctx: AxisLabelsComputingContext) -> Double
//     - createAxisLabelsComputingContext(_ kind: AxisTickLabelComputingKind) -> AxisLabelsComputingContext
//     - types AxisLabelsComputingContext / AxisTickLabelComputingKind (`.determine`) / AxisLabelInfoDetermined
//   Reconcile the exact shapes once that sibling lands.
// import Scale, { ScaleGetTicksOpt } from '../scale/Scale';           -> Scale / ScaleGetTicksOpt (scale/Scale.swift)
// import { DimensionName, NullUndefined, ScaleDataValue, ScaleTick } from '../util/types';
//                                                                     -> util/types.swift (DimensionName / ScaleDataValue / ScaleTick; NullUndefined -> nil, CONVENTIONS §6)
// import OrdinalScale from '../scale/Ordinal';                        -> OrdinalScale (scale/Ordinal.swift)
// import Model from '../model/Model';                                 -> Model (model/Model.swift)
// import {
//     AxisBaseOption, AxisTickOptionUnion, CategoryAxisBaseOption,
//     CategoryTickLabelSplitBuildingOption, OptionAxisType
// } from './axisCommonTypes';                                         -> coord/axisCommonTypes.swift
//   PORT-TODO: axisCommonTypes.swift currently only exports `AxisScaleType`; the option interfaces
//   (AxisBaseOption / AxisTickOptionUnion / CategoryAxisBaseOption / CategoryTickLabelSplitBuildingOption)
//   land with the axis-option layer. Per CONVENTIONS §2 the generic `Model<Opt>` slots collapse to the
//   dynamic `Model` bag, so those option types are only needed as generic params (dropped) — except
//   `OptionAxisType`, referenced below by the `type` property (upstream: 'value'|'category'|'time'|'log').
// import { AxisBaseModel } from './AxisBaseModel';                    -> AxisBaseModel (coord/AxisBaseModel.swift — open class : ComponentModel)
// import { isOrdinalScale } from '../scale/helper';                   -> helper.isOrdinalScale (scale/helper.swift)
// import { calcBandWidth } from './axisBand';                         -> calcBandWidth (coord/axisBand.swift, top-level free func)
// import { getTickValueOutermost } from './axisHelper';               -> getTickValueOutermost (coord/axisHelper.swift, top-level free func)
//   PORT-TODO: coord/axisHelper.swift is a sibling landing this phase; conventional API:
//     getTickValueOutermost(_ scale: Scale, _ tick: ScaleTick) -> Double
//
// PORT-TODO (NAME CLASH — integration): coord/axisStatistics.swift currently owns a shared
//   `public protocol Axis` placeholder (its own comment: "MUST be removed when the real modules land
//   (coord/Axis.ts, ...)"). This file lands the real `class Axis`; the placeholder protocol must be
//   removed by the integrator so `calcBandWidth(_ axis: Axis)` / axisStatistics bind to this class
//   (which supplies `model`/`scale`/`dim`/`onBand`/`getExtent`).

// upstream: const NORMALIZED_EXTENT = [0, 1] as [number, number];
private let NORMALIZED_EXTENT: [Double] = [0, 1]

// upstream: export interface AxisTickCoord { ... }
// Object-literal data bag → struct (CONVENTIONS §4).
public struct AxisTickCoord {
    public var coord: Double
    // upstream: tickValue: ScaleTick['value'];
    public var tickValue: Double
    // `true` if onBand fixed.
    public var onBand: Bool?
    public init(coord: Double, tickValue: Double, onBand: Bool? = nil) {
        self.coord = coord
        self.tickValue = tickValue
        self.onBand = onBand
    }
}

// upstream: object-literal `opt` bag of `getTicksCoords` → struct (CONVENTIONS §4).
public struct GetTicksCoordsOpt {
    // upstream: tickModel?: Model<CategoryTickLabelSplitBuildingOption>  → `Model` (generic dropped)
    public var tickModel: Model?
    // upstream: breakTicks?: ScaleGetTicksOpt['breakTicks']
    public var breakTicks: String?
    // upstream: pruneByBreak?: ScaleGetTicksOpt['pruneByBreak']
    public var pruneByBreak: ParamPruneByBreak?
    public init(
        tickModel: Model? = nil,
        breakTicks: String? = nil,
        pruneByBreak: ParamPruneByBreak? = nil
    ) {
        self.tickModel = tickModel
        self.breakTicks = breakTicks
        self.pruneByBreak = pruneByBreak
    }
}

// upstream: the anonymous `{coord, tick}[]` produced/mutated inside `getTicksCoords`/`fixOnBandTicksCoords`.
//   Modeled as a struct; `fixOnBandTicksCoords` receives it `inout` to reproduce the in-place mutation
//   (JS mutates the array/items directly).
private struct PreTicksCoordItem {
    var coord: Double
    var tick: ScaleTick
}

/**
 * Base class of Axis.
 *
 * Lifetime: recreate for each main process.
 * [NOTICE]: Some caches is stored on the axis instance (e.g., `axisTickLabelBuilder.ts`, `scaleRawExtentInfo.ts`),
 *  which is based on this lifetime.
 */
// upstream: class Axis { ... } — subclassed (Axis2D, SingleAxis, ...) → `open class` (CONVENTIONS §2).
open class Axis {

    /**
     * Axis type
     *  - 'category'
     *  - 'value'
     *  - 'time'
     *  - 'log'
     */
    // upstream: type: OptionAxisType;
    // Set by each concrete subclass (no base default) → implicitly-unwrapped.
    // PORT-TODO: `OptionAxisType` ('value'|'category'|'time'|'log') is defined in axisCommonTypes.swift
    //   which currently only exports `AxisScaleType`; expand that sibling with `OptionAxisType`.
    public var type: OptionAxisType!

    // Axis dimension. Such as 'x', 'y', 'z', 'angle', 'radius'.
    // The name must be globally unique across different coordinate systems.
    // But they may be not enumerable, e.g., in Radar and Parallel, axis
    // number is not static.
    // upstream: readonly dim: DimensionName;
    public let dim: DimensionName

    // Axis scale
    public var scale: Scale

    // Make sure that `extent[0] > extent[1]` only if `inverse: true`.
    // The unit is pixel, but not necessarily the global pixel,
    //  probably need to transform (usually rotate) to global pixel.
    // upstream: private _extent: [number, number];
    private var _extent: [Double]

    // Injected outside
    // upstream: model: AxisBaseModel;
    public var model: AxisBaseModel!
    // NOTICE: Must ensure `true` is only available on 'category' axis.
    // upstream: onBand: CategoryAxisBaseOption['boundaryGap'] = false;
    public var onBand: Bool = false
    // Make sure that `extent[0] > extent[1]` only if `inverse: true`.
    // `inverse` can be inferred by `extent` unless `extent[0] === extent[1]`.
    // upstream: inverse: AxisBaseOption['inverse'] = false;
    public var inverse: Bool = false

    // To be injected outside. May change - do not use it outside of echarts.
    // upstream: __alignTo: Axis | NullUndefined;
    public var __alignTo: Axis?


    // upstream: constructor(dim: DimensionName, scale: Scale, extent: [number, number])
    public init(_ dim: DimensionName, _ scale: Scale, _ extent: [Double]?) {
        self.dim = dim
        self.scale = scale
        self._extent = extent ?? [0, 0]  // upstream: extent || [0, 0]
    }

    /**
     * If axis extent contain given coord
     */
    open func contain(_ coord: Double) -> Bool {
        let extent = self._extent
        let min = Swift.min(extent[0], extent[1])
        let max = Swift.max(extent[0], extent[1])
        return coord >= min && coord <= max
    }

    /**
     * If axis extent contain given data
     */
    open func containData(_ data: ScaleDataValue) -> Bool {
        return self.scale.contain(self.scale.parse(data))
    }

    /**
     * Get coord extent.
     */
    open func getExtent() -> [Double] {
        return Array(self._extent)  // upstream: this._extent.slice()
    }

    /**
     * Set coord extent
     */
    open func setExtent(_ start: Double, _ end: Double) {
        // upstream: const extent = this._extent; extent[0] = start; extent[1] = end;
        //   (mutates the shared array in place — reproduced by writing through the stored property).
        self._extent[0] = start
        self._extent[1] = end
    }

    /**
     * Convert data to coord. Data is the rank if it has an ordinal scale
     */
    open func dataToCoord(_ data: ScaleDataValue, _ clamp: Bool? = nil) -> Double {
        let scale = self.scale
        let data = scale.normalize(scale.parse(data))
        return number.linearMap(data, NORMALIZED_EXTENT, makeExtentWithBands(self), clamp)
    }

    /**
     * Convert coord to data. Data is the rank if it has an ordinal scale
     */
    open func coordToData(_ coord: Double, _ clamp: Bool? = nil) -> Double {
        let t = number.linearMap(coord, makeExtentWithBands(self), NORMALIZED_EXTENT, clamp)
        return self.scale.scale(t)
    }

    /**
     * Convert pixel point to data in axis
     */
    open func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> Double {
        // Should be implemented in derived class if necessary.
        return Double.nan  // PORT-TODO: upstream `return;` (undefined) — base stub, overridden in derived class
    }

    /**
     * Different from `zrUtil.map(axis.getTicks(), axis.dataToCoord, axis)`,
     * `axis.getTicksCoords` considers `onBand`, which is used by
     * `boundaryGap:true` of category axis and splitLine and splitArea.
     * @param opt.tickModel default: axis.model.getModel('axisTick')
     */
    open func getTicksCoords(_ opt: GetTicksCoordsOpt? = nil) -> [AxisTickCoord] {
        let opt = opt ?? GetTicksCoordsOpt()
        let tickModel = opt.tickModel ?? self.getTickModel()

        // upstream: createAxisTicks(this, tickModel as AxisBaseModel, {breakTicks, pruneByBreak})
        var ticksOpt = ScaleGetTicksOpt()
        ticksOpt.breakTicks = opt.breakTicks
        ticksOpt.pruneByBreak = opt.pruneByBreak
        let result = createAxisTicks(self, tickModel, ticksOpt)
        var preTicksCoords = util.map(result.ticks) { (tick: ScaleTick, _: Int) in
            return PreTicksCoordItem(
                coord: self.dataToCoord(axisHelper.getTickValueOutermost(self.scale, tick)),
                tick: tick
            )
        }

        // upstream: (tickModel as Model<CategoryAxisBaseOption['axisTick']>).get('alignWithLabel')
        let alignWithLabel = (tickModel.get("alignWithLabel") as? Bool) ?? false

        let onBandModified = fixOnBandTicksCoords(
            self,
            &preTicksCoords,
            alignWithLabel
        )

        return util.map(preTicksCoords) { item, _ in
            return AxisTickCoord(
                coord: item.coord,
                tickValue: item.tick.value,
                onBand: onBandModified
            )
        }
    }

    open func getMinorTicksCoords() -> [[AxisTickCoord]] {
        if helper.isOrdinalScale(self.scale) {
            // Category axis doesn't support minor ticks
            return []
        }

        let minorTickModel = self.model.getModel("minorTick")
        // upstream: let splitNumber = minorTickModel.get('splitNumber');
        var splitNumber: Double = (minorTickModel.get("splitNumber") as? Double) ?? Double.nan
        // Protection.
        if !(splitNumber > 0 && splitNumber < 100) {
            splitNumber = 5
        }
        let minorTicks = self.scale.getMinorTicks(splitNumber)
        let minorTicksCoords = util.map(minorTicks) { minorTicksGroup, _ in
            return util.map(minorTicksGroup) { minorTick, _ in
                return AxisTickCoord(
                    coord: self.dataToCoord(minorTick),
                    tickValue: minorTick
                )
            }
        }
        return minorTicksCoords
    }

    open func getViewLabels(_ ctx: AxisLabelsComputingContext? = nil) -> [AxisLabelInfoDetermined] {
        let ctx = ctx ?? createAxisLabelsComputingContext(AxisTickLabelComputingKind.determine)
        return createAxisLabels(self, ctx).labels
    }

    open func getLabelModel() -> Model {
        return self.model.getModel("axisLabel")
    }

    /**
     * Notice here we only get the default tick model. For splitLine
     * or splitArea, we should pass the splitLineModel or splitAreaModel
     * manually when calling `getTicksCoords`.
     * In GL, this method may be overridden to:
     * `axisModel.getModel('axisTick', grid3DModel.getModel('axisTick'));`
     */
    open func getTickModel() -> Model {
        return self.model.getModel("axisTick")
    }

    /**
     * @deprecated Use `calcBandWidth` instead.
     */
    open func getBandWidth() -> Double {
        return calcBandWidth(self, CalculateBandWidthOpt(min: 1)).w
        // NOTICE: Do not add logic here. Implement everthing in `calcBandWidth`.
    }

    /**
     * Get axis rotate, by degree.
     */
    // upstream: getRotate: () => number;  (a function-typed field injected outside)
    public var getRotate: (() -> Double)!

    /**
     * Only be called in category axis.
     * Can be overridden, consider other axes like in 3D.
     * @return Auto interval for category axis tick and label
     */
    open func calculateCategoryInterval(_ ctx: AxisLabelsComputingContext? = nil) -> Double {
        let ctx = ctx ?? createAxisLabelsComputingContext(AxisTickLabelComputingKind.determine)
        return EChartsKit.calculateCategoryInterval(self, ctx)
    }

}

func makeExtentWithBands(_ axis: Axis) -> [Double] {
    var extent = axis.getExtent()
    if axis.onBand {
        let size = extent[1] - extent[0]
        let margin = size / (axis.scale as! OrdinalScale).count() / 2
        extent[0] += margin
        extent[1] -= margin
    }
    return extent
}

/**
 * `axis.onBand: true` (i.e., `boundaryGap: true` in ec option) and `CategoryTickLabelSplitIntervalOption`
 *  affects `axisTick`/`axisLabel`/`splitLine`/`splitArea`.
 *
 * Currently, the visual result is best only when `axisTick/splitLine/splitArea.interval === 0`.
 * The typical case is:
 *      |---|---|---|     <= This is the input `preTicksCoords`
 *      0   1   2   3        (having been added half band width by `makeExtentWithBands`).
 *    |---|---|---|---|  <= This is the result.
 *      0   1   2   3
 *
 * When `interval > 0`, the visual result may be odd for `axisLabel` and `customValues`, but acceptable
 * for `axisTick` `splitLine` and `splitArea`:
 *      |---~---|---~---~---|---|    <= This is the input `preTicksCoords`; `interval: 2; min: 1; max: 7`.
 *      ₁   ₂   3   ₄   ₅   6   ₇       Subscript numbers (`₀`, `₁`, `₃`) indicate axis labels are hidden
 *                                      (by default settings) due to off-interval.
 *                                      A tilde (`~`) indicates a tick ignored due to off-interval.
 *    |---~---|---~---~---|---~---|  <= This is the result.
 *      ₁   ₂   3   ₄   ₅   6   ₇
 *
 * NOTE:
 *  - A inappropriate result may cause misleading (e.g., split 2 bars of a single data item when there
 *    are two bar series).
 *  - See also #11176 #11186 .
 * PENDING:
 *  - The show/hide of `axisLabel` may be optimized when `interval > 1 and be an even number`,
 *    but that may introduce complex and still not perfect in odd number, and may not necessary if
 *    `axisTick: {show: false}` and `axisLabel` can auto hidden when overlapping.
 */
private func fixOnBandTicksCoords(
    _ axis: Axis,
    _ preTicksCoords: inout [PreTicksCoordItem],
    _ alignWithLabel: Bool
    // return: whether coords are modified according to `onBand`.
) -> Bool {
    let ticksLen = preTicksCoords.count

    if !axis.onBand || alignWithLabel || ticksLen == 0 {
        return false
    }

    // Assume:
    //  - If `onBand: true`, `bandWidth` has been calculated by `ticksLen + 1` rather than `ticksLen`.
    //  - If `interval > 0`, some ticks may be ignored, but `ticksCoords` has always included boundary
    //    ticks of axis extent, and be `offInterval: true` if off-interval.
    //  - No need to consider breaks, since axis break is not supported in category axis.
    let bandWidth = calcBandWidth(axis).w
    if bandWidth == 0 || bandWidth.isNaN {  // upstream: if (!bandWidth) — 0/NaN are falsy
        return false
    }

    // upstream: each(preTicksCoords, function (ticksItem) { ticksItem.coord -= bandWidth / 2; });
    //   Swift value-type array → index loop to mutate items in place.
    for i in 0..<preTicksCoords.count {
        preTicksCoords[i].coord -= bandWidth / 2
    }

    let dataExtent = axis.scale.getExtent()
    let oldLast = preTicksCoords[ticksLen - 1]
    if oldLast.tick.offInterval == true {
        preTicksCoords.removeLast()  // upstream: preTicksCoords.pop()
    }
    preTicksCoords.append(PreTicksCoordItem(
        coord: oldLast.coord + bandWidth,
        tick: ScaleTick(value: dataExtent[1] + 1)
    ))

    return true
}

// upstream: export default Axis;  -> `open class Axis` above.
