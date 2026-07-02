// Ported from echarts/src/coord/cartesian/Grid.ts — keep in sync with upstream
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

/**
 * Grid is a region which contains at most 4 cartesian systems
 *
 * TODO Default cartesian
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import {isObject, each, indexOf, retrieve3, keys, assert, eqNaN, find, retrieve2, hasOwn} from 'zrender/src/core/util';
//       -> ZRenderKit caseless enum `util` (`util.isObject` / `util.each` / `util.indexOf` / ...). `hasOwn`
//          on a `HashMap` is always true for enumerated keys, so it is dropped where iterating keys.
//   import {BoxLayoutReferenceResult, createBoxLayoutReference, getLayoutRect, LayoutRect} from '../../util/layout';
//       -> util/layout.swift (SIBLING — NOT yet landed). Referenced by its conventional public API:
//          free-function module -> caseless enum `layout` (`layout.createBoxLayoutReference` /
//          `layout.getLayoutRect`); the types `LayoutRect` / `BoxLayoutReferenceResult` stay top-level.
//          PORT-TODO: reconcile the exact namespacing once util/layout.swift lands.
//   import {
//       createScaleByModel, getScaleValuePositionKind, isNameLocationCenter, shouldAxisShow,
//       retrieveAxisBreaksOption, determineAxisType, isOnAxisZeroDiscouraged,
//       SCALE_VALUE_POSITION_KIND_OUTSIDE, getTickValueOutermost, isAxisOnBand,
//   } from '../../coord/axisHelper';
//       -> coord/axisHelper.swift caseless enum `axisHelper` (+ top-level `SCALE_VALUE_POSITION_KIND_OUTSIDE`).
//   import Cartesian2D, {cartesian2DDimensions} from './Cartesian2D';
//       -> coord/cartesian/Cartesian2D.swift (SIBLING — NOT yet landed). Conventional API: `Cartesian2D`
//          (open class : Cartesian<Axis2D>, CoordinateSystem) with `master`/`model`/`addAxis`/`getAxis`/
//          `getBaseAxis`/`getOtherAxis`/`dataToPoint`/`pointToData`/`containPoint`/`calcAffineTransform`;
//          plus top-level `cartesian2DDimensions: [DimensionName]`.
//   import Axis2D from './Axis2D';                                          -> coord/cartesian/Axis2D.swift (landed)
//   import {ParsedModelFinder, ParsedModelFinderKnown, SINGLE_REFERRING} from '../../util/model';
//       -> util/modelUtil.swift: `ParsedModelFinder`/`ParsedModelFinderKnown` = [String: Any];
//          `SINGLE_REFERRING` = `model.SINGLE_REFERRING`.
//   import GridModel, {COORD_SYS_TYPE_CARTESIAN_2D, GridOption, OUTER_BOUNDS_CLAMP_DEFAULT, OUTER_BOUNDS_DEFAULT}
//       from './GridModel';                                                 -> coord/cartesian/GridModel.swift (landed)
//   import CartesianAxisModel from './AxisModel';                           -> coord/cartesian/AxisModel.swift (landed)
//   import GlobalModel from '../../model/Global';                           -> GlobalModel (model/Global.swift)
//   import ExtensionAPI from '../../core/ExtensionAPI';                     -> ExtensionAPI (core/ExtensionAPI.swift)
//   import { Dictionary } from 'zrender/src/core/types';                    -> `[String: T]` (CONVENTIONS §1)
//   import {CoordinateSystemMaster} from '../CoordinateSystem';             -> coord/CoordinateSystem.swift
//   import { NullUndefined, ScaleDataValue } from '../../util/types';       -> util/types.swift (NullUndefined -> Optional §6)
//   import {findAxisModels, createCartesianAxisViewCommonPartBuilder, updateCartesianAxisViewCommonPartBuilder}
//       from './cartesianAxisHelper';
//       -> coord/cartesian/cartesianAxisHelper.swift (SIBLING — NOT yet landed). `findAxisModels(seriesModel)`
//          returns `{xAxisModel, yAxisModel}`; the two `*CommonPartBuilder` builders belong to the AxisBuilder
//          (component/axis) label path that is stubbed here (see below).
//   import { AxisBaseOptionCommon, NumericAxisBaseOptionCommon } from '../axisCommonTypes';
//       -> option interfaces dropped (dynamic option bag, CONVENTIONS §2).
//   import { AxisBaseModel } from '../AxisBaseModel';                       -> coord/AxisBaseModel.swift
//   import { isIntervalOrLogScale, isOrdinalScale } from '../../scale/helper';  -> `helper.*` (scale/helper.swift)
//   import { scaleCalcAlign } from '../axisAlignTicks';                     -> top-level `scaleCalcAlign` (coord/axisAlignTicks.swift)
//   import IntervalScale from '../../scale/Interval';                       -> IntervalScale (scale/Interval.swift)
//   import LogScale from '../../scale/Log';                                 -> LogScale (scale/LogScale.swift)
//   import { BoundingRect, expandOrShrinkRect, WH, XY } from '../../util/graphic';
//       -> BoundingRect (ZRenderKit); `expandOrShrinkRect`/`WH`/`XY` (util/graphic.swift SIBLING) are used
//          only in the stubbed AxisBuilder label-overlap path below.
//   import {AxisBuilderSharedContext, resolveAxisNameOverlapDefault, moveIfOverlapByLinearLabels, getLabelInner}
//       from '../../component/axis/AxisBuilder';
//       -> component/axis/AxisBuilder (Phase 6b, OUT OF SCOPE). The label-overlap path is PORT-TODO stubbed.
//   import { error, log } from '../../util/log';                            -> `log.error` / `log.log` (util/log.swift)
//   import { AxisTickLabelComputingKind } from '../axisTickLabelBuilder';   -> coord/axisTickLabelBuilder.swift
//   import { injectCoordSysByOption } from '../../core/CoordinateSystem';
//       -> core/CoordinateSystemManager.swift: `injectCoordSysByOption(_ opt: InjectCoordSysByOptionOpt)`.
//   import { mathMax, parsePositionSizeOption } from '../../util/number';   -> `number.mathMax` / `number.parsePositionSizeOption`
//   import { scaleCalcNice } from '../axisNiceTicks';                       -> `scaleCalcNice(ScaleCalcNiceAxisLike)` (coord/axisNiceTicks.swift)
//   import { createDimNameMap } from '../../data/helper/SeriesDataSchema';  -> `createDimNameMap` (data/helper/SeriesDataSchema.swift)
//   import type Axis from '../Axis';                                        -> coord/Axis.swift (`open class Axis`)
//   import {AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE, scaleRawExtentInfoEnableBoxCoordSysUsage,
//       scaleRawExtentInfoCreate} from '../scaleRawExtentInfo';             -> coord/scaleRawExtentInfo.swift
//   import { hasBreaks } from '../../scale/break';                          -> top-level `hasBreaks` (scale/break.swift)
//   import { associateSeriesWithAxis } from '../axisStatistics';            -> `associateSeriesWithAxis` (coord/axisStatistics.swift)
//
// ============================================================================
// PORT-TODO (CROSS-SIBLING HIERARCHY): Upstream `CartesianAxisModel implements AxisBaseModel<...>`, i.e. it
//   IS an `AxisBaseModel`. In the current Swift port hierarchy, `CartesianAxisModel: ComponentModel,
//   AxisModelCommonMixin` is a *sibling* of `AxisBaseModel: ComponentModel` (both conform to the same mixin
//   protocol) rather than a subclass. Grid relies on the upstream relation in two places:
//     - `axis.model = axisModel` (base `Axis.model: AxisBaseModel!`), and
//     - `axisHelper.isAxisOnBand(axis.scale, axisModel)` (param typed `AxisBaseModel`).
//   These are written faithfully below; they type-check once the integrator aligns
//   `CartesianAxisModel` to subclass `AxisBaseModel` (matching upstream's `implements`).
// ============================================================================
//
// PORT-TODO (AXIS NAME CLASH): coord/axisStatistics.swift still declares a placeholder `public protocol Axis`
//   alongside the real `open class Axis` in coord/Axis.swift. Until the integrator removes that placeholder,
//   the bare name `Axis` is ambiguous in this module; this file therefore uses the concrete `Axis2D`
//   for local axis references and only names `Axis` where the `CoordinateSystemMaster` protocol requires it.


// upstream: type Cartesian2DDimensionName = 'x' | 'y';  (no string union -> String alias)
public typealias Cartesian2DDimensionName = String

// upstream: type FinderAxisIndex = {xAxisIndex?: number, yAxisIndex?: number};
public struct FinderAxisIndex {
    public var xAxisIndex: Double?
    public var yAxisIndex: Double?
    public init(xAxisIndex: Double? = nil, yAxisIndex: Double? = nil) {
        self.xAxisIndex = xAxisIndex
        self.yAxisIndex = yAxisIndex
    }
}

// upstream: type AxesMap = { x: Axis2D[], y: Axis2D[] };
//   Although typed `Axis2D[]`, upstream uses it as a `Record<number, Axis2D>` (sparse, index-keyed via
//   `axesMap[dim][idx]`, iterated by `keys()`/`each()`). Ported as a pair of `HashMap<Axis2D>` to preserve
//   the index-keyed access AND the ascending insertion order that upstream's numeric-object `keys()` relies
//   on. `axesMap[dim]` subscript mirrors the dynamic `axesMap[dimName]` access.
struct AxesMap {
    var x: HashMap<Axis2D> = createHashMap()
    var y: HashMap<Axis2D> = createHashMap()
    subscript(_ dim: Cartesian2DDimensionName) -> HashMap<Axis2D> {
        return dim == "x" ? self.x : self.y
    }
}

// upstream: type ParsedOuterBoundsContain = 'all' | 'axisLabel';  (String alias)
typealias ParsedOuterBoundsContain = String

// margin is [top, right, bottom, left]
// upstream: const XY_TO_MARGIN_IDX = [[3, 1], [0, 2]] as const;
let XY_TO_MARGIN_IDX: [[Int]] = [
    [3, 1], // xyIdx 0 => 'x'
    [0, 2]  // xyIdx 1 => 'y'
]

// upstream: class Grid implements CoordinateSystemMaster { ... }
//   Reference type (holds shared mutable axis/coord graph) -> `final class` (CONVENTIONS §2/§4).
public final class Grid: CoordinateSystemMaster {

    // FIXME:TS where used (different from registered type 'cartesian2d')?
    // upstream: readonly type: string = 'grid';
    public let type: String = "grid"

    private var _coordsMap: [String: Cartesian2D] = [:]
    private var _coordsList: [Cartesian2D] = []
    private var _axesMap: AxesMap = AxesMap()
    private var _axesList: [Axis2D] = []
    // upstream: private _rect: LayoutRect;  (assigned in `resize`, before any `getRect`) -> IUO.
    private var _rect: LayoutRect!

    // upstream: readonly model: GridModel;
    public let model: GridModel
    // upstream: readonly axisPointerEnabled = true;
    //   Witnesses the optional `CoordinateSystemMaster.axisPointerEnabled: Bool?`.
    public var axisPointerEnabled: Bool? { return true }

    // Injected:
    // upstream: name: string;  (assigned in `Grid.create`)
    public var name: String = ""

    // For deciding which dimensions to use when creating list data
    // upstream: static dimensions = cartesian2DDimensions;
    public static let dimensions: [DimensionName] = cartesian2DDimensions
    // upstream: readonly dimensions = cartesian2DDimensions;
    //   Witnesses `CoordinateSystemMaster.dimensions: [DimensionName] { get set }` (upstream readonly).
    public var dimensions: [DimensionName] = cartesian2DDimensions
    // upstream: static dimIdxMap = createDimNameMap(cartesian2DDimensions);
    public static let dimIdxMap: HashMap<DimensionIndex> = createDimNameMap(cartesian2DDimensions)

    // PORT-TODO: `CoordinateSystemMaster.boxCoordinateSystem` (optional, default nil) is not used by Grid.

    // upstream: constructor(gridModel: GridModel, ecModel: GlobalModel, api: ExtensionAPI)
    public init(_ gridModel: GridModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.model = gridModel
        self._initCartesian(gridModel, ecModel, api)
        // upstream sets `this.model = gridModel` after `_initCartesian`; Swift requires all stored
        // properties initialized before calling instance methods, so `model` is set first.
    }

    // upstream: getRect(): LayoutRect
    //   PORT-TODO: upstream returns the concrete `LayoutRect`; the optional protocol requirement
    //   `CoordinateSystemMaster.getRect(): RectLike?` therefore resolves to its nil default when Grid is
    //   viewed as `CoordinateSystemMaster`. Reconcile if external (axisPointer, Phase 6b) needs it.
    public func getRect() -> LayoutRect {
        return self._rect
    }

    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {

        let axesMap = self._axesMap

        util.each(self._axesList) { axis, _ in
            scaleRawExtentInfoCreate(axis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)
            let scale = axis.scale
            if helper.isOrdinalScale(scale) {
                // upstream: scale.setSortInfo(axis.model.get('categorySortInfo'))
                (scale as! OrdinalScale).setSortInfo(axis.model.get("categorySortInfo") as? OrdinalSortInfo)
            }
        }

        // upstream: function updateAxisTicks(axes: Record<number, Axis2D>)
        func updateAxisTicks(_ axes: HashMap<Axis2D>) {
            // Axis is added in order of axisIndex.
            let axesIndices = axes.keys()
            var axisNeedsAlign: [Axis2D] = []

            var i = axesIndices.count - 1
            while i >= 0 { // Reverse order
                let axis = axes.get(axesIndices[i])!  // upstream: axes[+axesIndices[i]]
                if axis.__alignTo != nil {
                    axisNeedsAlign.append(axis)
                }
                else {
                    // PORT-TODO: upstream `scaleCalcNice(axis)`; the landed `scaleCalcNice` takes a
                    //   `ScaleCalcNiceAxisLike` (its own `axis` is re-derived from `model.axis` internally).
                    scaleCalcNice(ScaleCalcNiceAxisLike(scale: axis.scale, model: axis.model))
                }
                i -= 1
            }
            util.each(axisNeedsAlign) { axis, _ in
                if incapableOfAlignNeedFallback(axis, axis.__alignTo as! Axis2D) {
                    scaleCalcNice(ScaleCalcNiceAxisLike(scale: axis.scale, model: axis.model))
                }
                else {
                    // upstream: scaleCalcAlign(axis, axis.__alignTo.scale as IntervalScale | LogScale)
                    scaleCalcAlign(axis, axis.__alignTo!.scale)
                }
            }
        }

        updateAxisTicks(axesMap.x)
        updateAxisTicks(axesMap.y)

        // Key: axisDim_axisIndex, value: boolean, whether onZero target.
        var onZeroRecords: [String: Bool] = [:]  // {} as Dictionary<boolean>

        axesMap.x.each { xAxis, _ in
            fixAxisOnZero(axesMap, "y", xAxis, &onZeroRecords)
        }
        axesMap.y.each { yAxis, _ in
            fixAxisOnZero(axesMap, "x", yAxis, &onZeroRecords)
        }

        // Resize again if containLabel is enabled
        // FIXME It may cause getting wrong grid size in data processing stage
        self.resize(self.model, api)
    }

    /**
     * Resize the grid.
     *
     * [NOTE]
     * If both "grid.containLabel/grid.contain" and pixel-required-data-processing (such as, "dataSampling")
     * exist, circular dependency occurs in logic.
     * The final compromised sequence is:
     *  1. Calculate "axis.extent" (pixel extent) and AffineTransform based on only "grid layout options".
     *      Not accurate if "grid.containLabel/grid.contain" is required, but it is a compromise to avoid
     *      circular dependency.
     *  2. Perform "series data processing" (where "dataSampling" requires "axis.extent").
     *  3. Calculate "scale.extent" (data extent) based on "processed series data".
     *  4. Modify "axis.extent" for "grid.containLabel/grid.contain":
     *      4.1. Calculate "axis labels" based on "scale.extent".
     *      4.2. Modify "axis.extent" by the bounding rects of "axis labels and names".
     */
    public func resize(_ gridModel: GridModel, _ api: ExtensionAPI, _ beforeDataProcessing: Bool? = nil) {

        let layoutRef = layout.createBoxLayoutReference(gridModel, api)
        let gridRect = layout.getLayoutRect(gridModel.getBoxLayoutParams(), layoutRef.refContainer)
        self._rect = gridRect
        // PENDING: whether to support that if the input `coord` is out of the base coord sys,
        //  do not render anything. At present, the behavior is undefined.

        let axesMap = self._axesMap
        let coordsList = self._coordsList

        let optionContainLabel = gridModel.get("containLabel") // No `.get(, true)` for backward compat.

        // NOTE: The axis pixel extent is also required by some estimation, e.g., in coord sys update stage,
        // bars on 'time'/'value' axis need it to calculate the supplementary scale extent to avoid edge bars
        // overflowing the axis (see `barGrid.ts`). Therefore, axis pixel extent need to be set early, even
        // may not be accurate.
        updateAllAxisExtentTransByGridRect(axesMap, gridRect)

        if !(beforeDataProcessing ?? false) {
            let axisBuilderSharedCtx = createAxisBiulders(gridRect, coordsList, axesMap, optionContainLabel, api)

            var noPxChange: Bool = false  // upstream: `let noPxChange: boolean;` (may stay undefined)
            // JS truthiness of the dynamic `containLabel` option.
            let optionContainLabelTruthy = (optionContainLabel as? Bool) ?? false
            if optionContainLabelTruthy {
                if legacyLayOutGridByContainLabel != nil {
                    // console.time('legacyLayOutGridByContainLabel');
                    legacyLayOutGridByContainLabel!(self._axesList, gridRect)
                    updateAllAxisExtentTransByGridRect(axesMap, gridRect)
                    // console.timeEnd('legacyLayOutGridByContainLabel');
                }
                else {
                    if __DEV__ {
                        log.log("Specified `grid.containLabel` but no `use(LegacyGridContainLabel)`;"
                            + "use `grid.outerBounds` instead.",
                            true
                        )
                    }
                    noPxChange = layOutGridByOuterBounds(
                        gridRect.clone(), "axisLabel", nil, gridRect, axesMap, axisBuilderSharedCtx, layoutRef
                    )
                }
            }
            else {
                let outer = prepareOuterBounds(gridModel, gridRect, layoutRef)
                if let outerBoundsRect = outer.outerBoundsRect {
                    // console.time('layOutGridByOuterBounds');
                    noPxChange = layOutGridByOuterBounds(
                        outerBoundsRect, outer.parsedOuterBoundsContain, outer.outerBoundsClamp,
                        gridRect, axesMap, axisBuilderSharedCtx, layoutRef
                    )
                    // console.timeEnd('layOutGridByOuterBounds');
                }
            }

            // console.time('buildAxesView_determine');
            createOrUpdateAxesView(
                gridRect,
                axesMap,
                AxisTickLabelComputingKind.determine,
                nil,
                noPxChange,
                layoutRef
            )
            // console.timeEnd('buildAxesView_determine');

            util.each(self._coordsList) { coord, _ in
                // Calculate affine matrix to accelerate the data to point transform.
                // If all the axes scales are time or value.
                coord.calcAffineTransform()
            }
        } // End of beforeDataProcessing
    }

    // upstream: getAxis(dim: Cartesian2DDimensionName, axisIndex?: number): Axis2D
    public func getAxis(_ dim: Cartesian2DDimensionName, _ axisIndex: Double? = nil) -> Axis2D? {
        let axesMapOnDim = self._axesMap[dim]
        // upstream: if (axesMapOnDim != null) — the struct always has both maps (empty after rollback),
        //   so a missing index simply returns nil.
        return axesMapOnDim.get(axisIndex ?? 0)  // upstream: axesMapOnDim[axisIndex || 0]
    }

    // upstream: getAxes(): Axis2D[] — witnesses the optional `CoordinateSystemMaster.getAxes(): Axis[]?`.
    public func getAxes() -> [Axis]? {
        return self._axesList  // upstream: this._axesList.slice()
    }

    /**
     * Usage:
     *      grid.getCartesian(xAxisIndex, yAxisIndex);
     *      grid.getCartesian(xAxisIndex);
     *      grid.getCartesian(null, yAxisIndex);
     *      grid.getCartesian({xAxisIndex: ..., yAxisIndex: ...});
     *
     * When only xAxisIndex or yAxisIndex given, find its first cartesian.
     */
    // upstream overloads: getCartesian(finder) / getCartesian(xAxisIndex?, yAxisIndex?)
    public func getCartesian(_ finder: FinderAxisIndex) -> Cartesian2D? {
        // upstream `isObject(xAxisIndex)` branch: unpack the finder object.
        return self._getCartesian(finder.xAxisIndex, finder.yAxisIndex)
    }
    public func getCartesian(_ xAxisIndex: Double? = nil, _ yAxisIndex: Double? = nil) -> Cartesian2D? {
        return self._getCartesian(xAxisIndex, yAxisIndex)
    }
    private func _getCartesian(_ xAxisIndex: Double?, _ yAxisIndex: Double?) -> Cartesian2D? {
        if xAxisIndex != nil && yAxisIndex != nil {
            let key = "x\(Int(xAxisIndex!))y\(Int(yAxisIndex!))"  // upstream: 'x' + xAxisIndex + 'y' + yAxisIndex
            return self._coordsMap[key]
        }

        let coordList = self._coordsList
        for i in 0..<coordList.count {
            if coordList[i].getAxis("x")?.index == xAxisIndex
                || coordList[i].getAxis("y")?.index == yAxisIndex
            {
                return coordList[i]
            }
        }
        return nil
    }

    public func getCartesians() -> [Cartesian2D] {
        return Array(self._coordsList)  // upstream: this._coordsList.slice()
    }

    /**
     * @implements
     */
    // upstream: convertToPixel(ecModel, finder, value: ScaleDataValue | ScaleDataValue[]): number | number[]
    //   Witnesses `CoordinateSystemMaster.convertToPixel(...)`; the protocol's trailing `opt` is unused here.
    public func convertToPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: CoordinateSystemDataCoord, _ opt: Any? = nil
    ) -> Any? {
        _ = opt
        let target = self._findConvertTarget(finder)

        return target.cartesian != nil
            ? target.cartesian!.dataToPoint(value, nil)  // value as ScaleDataValue[]
            : target.axis != nil
            ? target.axis!.toGlobalCoord(target.axis!.dataToCoord(value))  // value as ScaleDataValue
            : nil
    }

    /**
     * @implements
     */
    // upstream: convertFromPixel(ecModel, finder, value: number | number[]): number | number[]
    //   PORT-TODO: `CoordinateSystemMaster.convertFromPixel` erased the `number | number[]` input to
    //   `[Double]`. The single-axis branch (`value as number`) therefore reads the leading element as the
    //   scalar proxy (a single-axis pixel value is passed as a 1-element array).
    public func convertFromPixel(
        _ ecModel: GlobalModel, _ finder: ParsedModelFinder, _ value: [Double], _ opt: Any? = nil
    ) -> Any? {
        _ = opt
        let target = self._findConvertTarget(finder)

        return target.cartesian != nil
            ? target.cartesian!.pointToData(value, nil)  // value as number[]
            : target.axis != nil
            ? (target.axis!.coordToData(target.axis!.toLocalCoord(value.first ?? Double.nan)) as Any?)  // value as number
            : nil
    }

    // upstream: private _findConvertTarget(finder: ParsedModelFinderKnown): {cartesian: Cartesian2D, axis: Axis2D}
    private func _findConvertTarget(_ finder: ParsedModelFinderKnown) -> (cartesian: Cartesian2D?, axis: Axis2D?) {
        let seriesModel = finder["seriesModel"] as? SeriesModel
        // NOTE: `SINGLE_REFERRING` is `model.SINGLE_REFERRING` (util/modelUtil.swift), but the `model`
        //   namespace enum is shadowed by this class's `model: GridModel` property inside instance methods,
        //   so it is module-qualified as `EChartsKit.model.*` (same pattern as scaleRawExtentInfo.swift).
        let xAxisModel = (finder["xAxisModel"] as? CartesianAxisModel)
            ?? (seriesModel.flatMap {
                $0.getReferringComponents("xAxis", EChartsKit.model.SINGLE_REFERRING).models.first as? CartesianAxisModel
            })
        let yAxisModel = (finder["yAxisModel"] as? CartesianAxisModel)
            ?? (seriesModel.flatMap {
                $0.getReferringComponents("yAxis", EChartsKit.model.SINGLE_REFERRING).models.first as? CartesianAxisModel
            })
        let gridModel = finder["gridModel"] as? GridModel
        let coordsList = self._coordsList
        var cartesian: Cartesian2D?
        var axis: Axis2D?

        if let seriesModel = seriesModel {
            cartesian = seriesModel.coordinateSystem as? Cartesian2D
            // upstream: indexOf(coordsList, cartesian) < 0 && (cartesian = null);
            if coordsList.firstIndex(where: { $0 === cartesian }) == nil {
                cartesian = nil
            }
        }
        else if let xAxisModel = xAxisModel, let yAxisModel = yAxisModel {
            cartesian = self.getCartesian(xAxisModel.componentIndex, yAxisModel.componentIndex)
        }
        else if let xAxisModel = xAxisModel {
            axis = self.getAxis("x", xAxisModel.componentIndex)
        }
        else if let yAxisModel = yAxisModel {
            axis = self.getAxis("y", yAxisModel.componentIndex)
        }
        // Lowest priority.
        else if let gridModel = gridModel {
            let grid = gridModel.coordinateSystem
            if grid === self {
                cartesian = self._coordsList.first  // upstream: this._coordsList[0]
            }
        }

        return (cartesian: cartesian, axis: axis)
    }

    /**
     * @implements
     */
    public func containPoint(_ point: [Double]) -> Bool {
        let coord = self._coordsList.first  // upstream: this._coordsList[0]
        if let coord = coord {
            return coord.containPoint(point)
        }
        // PORT-TODO: upstream implicitly returns `undefined` (falsy) when no coord exists.
        return false
    }

    /**
     * Initialize cartesian coordinate systems
     */
    private func _initCartesian(
        _ gridModel: GridModel, _ ecModel: GlobalModel, _ api: ExtensionAPI
    ) {
        let grid = self
        var axisPositionUsed: [String: Bool] = [
            "left": false,
            "right": false,
            "top": false,
            "bottom": false
        ]

        let axesMap = AxesMap()  // upstream: { x: {}, y: {} } as AxesMap (reference type; mutated through, not reassigned)
        var axesCount: [String: Double] = [
            "x": 0,
            "y": 0
        ]

        // upstream: function createAxisCreator(dimName) { return function (axisModel, idx) {...} }
        //   Declared before use in Swift; captures `grid`/`gridModel`/`axesMap`/`axesCount`/`axisPositionUsed`.
        func createAxisCreator(_ dimName: Cartesian2DDimensionName) -> EachComponentInMainTypeCallback {
            return { axisModelComp, idx in
                let axisModel = axisModelComp as! CartesianAxisModel
                if !isAxisUsedInTheGrid(axisModel, gridModel) {
                    return
                }

                var axisPosition = axisModel.get("position") as? String
                if dimName == "x" {
                    // Fix position
                    if axisPosition != "top" && axisPosition != "bottom" {
                        // Default bottom of X
                        axisPosition = (axisPositionUsed["bottom"] == true) ? "top" : "bottom"
                    }
                }
                else {
                    // Fix position
                    if axisPosition != "left" && axisPosition != "right" {
                        // Default left of Y
                        axisPosition = (axisPositionUsed["left"] == true) ? "right" : "left"
                    }
                }
                axisPositionUsed[axisPosition!] = true

                let axisType = axisHelper.determineAxisType(axisModel)
                let axis = Axis2D(
                    dimName,
                    axisHelper.createScaleByModel(axisModel, axisType, true),
                    [0, 0],
                    axisType,
                    axisPosition
                )

                // PORT-TODO (CROSS-SIBLING): `isAxisOnBand` / `axis.model = axisModel` require
                //   `CartesianAxisModel: AxisBaseModel` (see file header).
                axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel)
                axis.inverse = (axisModel.get("inverse") as? Bool) ?? false

                // Inject axis into axisModel
                axisModel.axis = axis

                // Inject axisModel into axis
                axis.model = axisModel

                // Inject grid info axis
                axis.grid = grid

                // Index of axis, can be used as key
                axis.index = idx

                grid._axesList.append(axis)

                axesMap[dimName].set(idx, axis)  // upstream: axesMap[dimName][idx] = axis
                axesCount[dimName]! += 1
            }
        }

        // Create axis
        ecModel.eachComponent("xAxis", createAxisCreator("x"), self)
        ecModel.eachComponent("yAxis", createAxisCreator("y"), self)

        if axesCount["x"]! == 0 || axesCount["y"]! == 0 {
            // Roll back when there no either x or y axis
            self._axesMap = AxesMap()  // {} as AxesMap
            self._axesList = []
            return
        }

        self._axesMap = axesMap

        // Create cartesian2d
        axesMap.x.each { xAxis, xAxisIndex in
            axesMap.y.each { yAxis, yAxisIndex in
                let key = "x" + xAxisIndex + "y" + yAxisIndex
                let cartesian = Cartesian2D(key)

                cartesian.master = self
                cartesian.model = gridModel

                self._coordsMap[key] = cartesian
                self._coordsList.append(cartesian)

                cartesian.addAxis(xAxis)
                cartesian.addAxis(yAxis)
            }
        }

        prepareAlignToInCoordSysCreate(axesMap.x)
        prepareAlignToInCoordSysCreate(axesMap.y)
    }

    /**
     * @param dim 'x' or 'y' or 'auto' or null/undefined
     */
    // upstream: getTooltipAxes(dim: Cartesian2DDimensionName | 'auto'): {baseAxes: Axis2D[], otherAxes: Axis2D[]}
    //   Witnesses `CoordinateSystemMaster.getTooltipAxes(_ dim: DimensionName): (baseAxes: [Axis], otherAxes: [Axis])?`.
    public func getTooltipAxes(_ dim: Cartesian2DDimensionName) -> (baseAxes: [Axis], otherAxes: [Axis])? {
        var baseAxes: [Axis2D] = []
        var otherAxes: [Axis2D] = []

        util.each(self.getCartesians()) { cartesian, _ in
            // upstream: (dim != null && dim !== 'auto') ? cartesian.getAxis(dim) : cartesian.getBaseAxis()
            //   `dim` is a non-optional String in the protocol, so the `!= null` guard drops.
            // Type annotation binds the concrete `Cartesian2D` overloads (returning `Axis2D`) rather
            //   than the `CoordinateSystem` protocol witnesses (returning `Axis?`).
            let baseAxis: Axis2D? = (dim != "auto")
                ? cartesian.getAxis(dim) : cartesian.getBaseAxis()
            let otherAxis: Axis2D? = baseAxis != nil ? cartesian.getOtherAxis(baseAxis!) : nil
            // upstream: indexOf(baseAxes, baseAxis) < 0 && baseAxes.push(baseAxis)
            if let baseAxis = baseAxis, baseAxes.firstIndex(where: { $0 === baseAxis }) == nil {
                baseAxes.append(baseAxis)
            }
            if let otherAxis = otherAxis, otherAxes.firstIndex(where: { $0 === otherAxis }) == nil {
                otherAxes.append(otherAxis)
            }
        }

        return (baseAxes: baseAxes, otherAxes: otherAxes)
    }


    // upstream: static create(ecModel: GlobalModel, api: ExtensionAPI): Grid[]
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Grid] {
        var grids: [Grid] = []
        // NOTE: explicit (non-trailing) closure with typed params to bind the per-mainType `eachComponent`
        //   overload (`EachComponentInMainTypeCallback`) rather than the all-components overload.
        ecModel.eachComponent("grid", { (gridModelComp: ComponentModel, idx: Double) in
            let gridModel = gridModelComp as! GridModel
            let grid = Grid(gridModel, ecModel, api)
            grid.name = "grid_\(Int(idx))"
            // dataSampling requires axis extent, so resize
            // should be performed in create stage.
            grid.resize(gridModel, api, true)

            gridModel.coordinateSystem = grid

            grids.append(grid)

            util.each(grid._axesList) { axis, _ in
                // upstream: scaleRawExtentInfoEnableBoxCoordSysUsage(axis, Grid.dimIdxMap)
                //   The landed impl takes `(scale, dim, coordSysDimIdxMap)`.
                scaleRawExtentInfoEnableBoxCoordSysUsage(axis.scale, axis.dim, Grid.dimIdxMap)
            }
        })

        // Inject the coordinateSystems into seriesModel
        ecModel.eachSeries({ seriesModel, _ in
            var xAxis: Axis2D?
            var yAxis: Axis2D?

            let coordSysProvider: CoordSysInjectionProvider = { _, _ in
                let axesModelMap = cartesianAxisHelper.findAxisModels(seriesModel)
                let xAxisModel = axesModelMap.xAxisModel
                let yAxisModel = axesModelMap.yAxisModel
                xAxis = xAxisModel.axis as? Axis2D
                yAxis = yAxisModel.axis as? Axis2D

                let gridModel = xAxisModel.getCoordSysModel()

                if __DEV__ {
                    if gridModel == nil {
                        // PORT-TODO: upstream `throw new Error(...)`; replicated as a dev-mode error log.
                        log.error(
                            "Grid \"\(util.retrieve3(xAxisModel.get("gridIndex"), xAxisModel.get("gridId"), 0) ?? 0)\" not found"
                        )
                    }
                    if (xAxisModel.getCoordSysModel() as AnyObject) !== (yAxisModel.getCoordSysModel() as AnyObject) {
                        // PORT-TODO: upstream `throw new Error('xAxis and yAxis must use the same grid')`.
                        log.error("xAxis and yAxis must use the same grid")
                    }
                }

                let grid = (gridModel as? GridModel)?.coordinateSystem as? Grid

                return grid?.getCartesian(
                    xAxisModel.componentIndex, yAxisModel.componentIndex
                )  // Cartesian2D? -> CoordinateSystem?
            }
            _ = injectCoordSysByOption(InjectCoordSysByOptionOpt(
                targetModel: seriesModel,
                coordSysType: COORD_SYS_TYPE_CARTESIAN_2D,
                coordSysProvider: coordSysProvider
            ))
            if let xAxis = xAxis, let yAxis = yAxis {
                associateSeriesWithAxis(xAxis, seriesModel, COORD_SYS_TYPE_CARTESIAN_2D)
                associateSeriesWithAxis(yAxis, seriesModel, COORD_SYS_TYPE_CARTESIAN_2D)
            }

        }, self)

        return grids
    }

}

/**
 * Check if the axis is used in the specified grid.
 */
func isAxisUsedInTheGrid(_ axisModel: CartesianAxisModel, _ gridModel: GridModel) -> Bool {
    // upstream: axisModel.getCoordSysModel() === gridModel
    return (axisModel.getCoordSysModel() as AnyObject) === gridModel
}

func fixAxisOnZero(
    _ axesMap: AxesMap,
    _ otherAxisDim: Cartesian2DDimensionName,
    _ axis: Axis2D,
    // Key: see `getOnZeroRecordKey`
    _ onZeroRecords: inout [String: Bool]
) {

    // upstream nested helper; declared before use in Swift.
    func getOnZeroRecordKey(_ axis: Axis2D) -> String {
        return axis.dim + "_" + "\(Int(axis.index))"
    }

    // onZero can not be enabled in these two situations:
    // 1. When any other axis is a category axis.
    // 2. When no axis is cross 0 point.
    let otherAxes = axesMap[otherAxisDim]

    var otherAxisOnZeroOf: Axis2D?

    axis.getAxesOnZeroOf = {
        // TODO: onZero of multiple axes.
        return otherAxisOnZeroOf != nil ? [otherAxisOnZeroOf!] : []
    }

    let axisModel = axis.model!
    let onZero = axisModel.get(["axisLine", "onZero"])
    let onZeroAxisIndex = axisModel.get(["axisLine", "onZeroAxisIndex"])

    // For historical reason, ec option `axisLine.onZero: undefined` leads to "not on zero"
    // while leaving `axisLine.onZero` unspecified causes "on zero". This inconsistency goes
    // against common sense, but is preserved for backward compatibility.
    // upstream: if (!onZero) return;  (JS falsy: undefined/null/false/0/'')
    if !isTruthy(onZero) {
        return
    }

    // If target axis is specified.
    if onZeroAxisIndex != nil && !(onZeroAxisIndex is NSNull) {
        if canOnZeroToAxis(onZero, otherAxes.get(onZeroAxisIndex)) {
            otherAxisOnZeroOf = otherAxes.get(onZeroAxisIndex)
        }
    }
    else {
        // Find the first available other axis.
        for idx in otherAxes.keys() {
            // upstream: hasOwn(otherAxes, idx) — always true for enumerated HashMap keys.
            if canOnZeroToAxis(onZero, otherAxes.get(idx))
                // Consider that two Y axes on one value axis,
                // if both onZero, the two Y axes overlap.
                && !(onZeroRecords[getOnZeroRecordKey(otherAxes.get(idx)!)] ?? false)
            {
                otherAxisOnZeroOf = otherAxes.get(idx)
                break
            }
        }
    }

    if let otherAxisOnZeroOf = otherAxisOnZeroOf {
        onZeroRecords[getOnZeroRecordKey(otherAxisOnZeroOf)] = true
    }
}

/**
 * CAVEAT: Must not be called before `CoordinateSystem#update` due to `__dontOnMyZero`.
 */
// upstream: canOnZeroToAxis(onZeroOption: AxisBaseOptionCommon['axisLine']['onZero'], axis: Axis2D | NullUndefined)
func canOnZeroToAxis(
    _ onZeroOption: Any?,
    _ axis: Axis2D?
) -> Bool {
    guard let axis = axis else {
        return false
    }
    let scale = axis.scale
    let kindEffective = axisHelper.getScaleValuePositionKind(scale, 0, false)

    var can = // upstream leading `axis &&` — non-nil here (guarded above)
        // PENDING: Historical behavior: `onZero` on 'category' and 'time' axis are always disabled
        // even if ec option gives `onZero: true`.
        axis.type != "category" && axis.type != "time"
        // NOTE: Although the portion out of "effective" portion may also cross zero
        // (see `SCALE_EXTENT_KIND_MAPPING`), that is commonly meaningless, so we use
        // `SCALE_EXTENT_KIND_EFFECTIVE`
        && kindEffective != SCALE_VALUE_POSITION_KIND_OUTSIDE

    if can && (onZeroOption as? String) == "auto"
        // Historically, "value" axis and "log" axis has been using `onZero: true` as the default.
        // It suitable for mathematic cases, even when dataZoom exists (e.g., `clip.html`), or cases
        // need to distinguish positive and negative data. However, it probably causes odd effect if
        // a "value axis" is laid on zero of a "base axis" in bar/candlestick, where the axis line
        // would likely cross shapes when `SCALE_EXTENT_KIND_MAPPING` is applied.
        // Therefore, we preserve backward compatibility of the default `onZero: true`, but exclude
        // cases that `containShape` is applied.
        && (
            axisHelper.isOnAxisZeroDiscouraged(axis)
            // || (
            //     // Avoid axis line cross series shape (typically, bar series on "value"/"time" axis) unexpectedly.
            //     kindEffective === SCALE_VALUE_POSITION_KIND_EDGE
            //     && getScaleValuePositionKind(scale, 0, true) === SCALE_VALUE_POSITION_KIND_INSIDE
            // )
        )
    {
        can = false
    }
    // falsy value of `onZeroOption` has been handled in the previous logic.
    return can
}

/**
 * [CAVEAT] This method is called before data processing stage.
 *  Do not rely on any info that is determined afterward.
 */
// upstream: prepareAlignToInCoordSysCreate(axes: Record<number, Axis2D>)
func prepareAlignToInCoordSysCreate(_ axes: HashMap<Axis2D>) {
    // Axis is added in order of axisIndex.
    let axesIndices = axes.keys()

    var alignTo: Axis2D?
    var axisNeedsAlign: [Axis2D] = []

    var i = axesIndices.count - 1
    while i >= 0 { // Reverse order
        let axis = axes.get(axesIndices[i])!  // upstream: axes[+axesIndices[i]]
        if
            helper.isIntervalOrLogScale(axis.scale)
            // NOTE: `scale.hasBreaks()` is not available at this moment. Check it later.
            && axisHelper.retrieveAxisBreaksOption(axis.model, axis.type, true) == nil
            // NOTE: `scale.getTicks()` is not available at this moment. Check it later.
        {
            // Request `alignTicks`.
            if isTruthy(axis.model.get("alignTicks"))
                && axis.model.get("interval") == nil
            {
                axisNeedsAlign.append(axis)
            }
            else {
                // `alignTo` the last one that does not request `alignTicks`
                // (This rule is retained for backward compat).
                alignTo = axis
            }
        }
        i -= 1
    }
    // If all axes has set alignTicks, pick the first one as alignTo.
    // PENDING. Should we find the axis that both set interval, min, max and align to this one?
    // PENDING. Should we allow specifying alignTo via ec option?
    if alignTo == nil {
        alignTo = axisNeedsAlign.popLast()  // upstream: axisNeedsAlign.pop()
    }
    if let alignTo = alignTo {
        util.each(axisNeedsAlign) { axis, _ in
            axis.__alignTo = alignTo
        }
    }
}

/**
 * This is just a defence code. They are unlikely to be actually `true`,
 * since these cases have been addressed in `prepareAlignToInCoordSysCreate`.
 *
 * Can not be called BEFORE "nice" performed.
 */
func incapableOfAlignNeedFallback(_ targetAxis: Axis2D, _ alignTo: Axis2D) -> Bool {
    return hasBreaks(targetAxis.scale)
        || hasBreaks(alignTo.scale)
        // Normally ticks length are more than 2 even when axis is blank.
        // But still guard for corner cases and possible changes.
        || alignTo.scale.getTicks().count < 2
}


func updateAxisTransform(_ axis: Axis2D, _ coordBase: Double) {
    let axisExtent = axis.getExtent()
    let axisExtentSum = axisExtent[0] + axisExtent[1]

    // Fast transform
    axis.toGlobalCoord = axis.dim == "x"
        ? { coord in
            return coord + coordBase
        }
        : { coord in
            return axisExtentSum - coord + coordBase
        }
    axis.toLocalCoord = axis.dim == "x"
        ? { coord in
            return coord - coordBase
        }
        : { coord in
            return axisExtentSum - coord + coordBase
        }
}

func updateAllAxisExtentTransByGridRect(_ axesMap: AxesMap, _ gridRect: LayoutRect) {
    axesMap.x.each { axis, _ in updateAxisExtentTransByGridRect(axis, gridRect.x, gridRect.width) }
    axesMap.y.each { axis, _ in updateAxisExtentTransByGridRect(axis, gridRect.y, gridRect.height) }
}

func updateAxisExtentTransByGridRect(_ axis: Axis2D, _ gridXY: Double, _ gridWH: Double) {
    let extent = [0, gridWH]
    let idx = axis.inverse ? 1 : 0
    axis.setExtent(extent[idx], extent[1 - idx])
    updateAxisTransform(axis, gridXY)
}

// upstream: export type LegacyLayOutGridByContainLabel = (axesList: Axis2D[], gridRect: LayoutRect) => void;
public typealias LegacyLayOutGridByContainLabel = (_ axesList: [Axis2D], _ gridRect: LayoutRect) -> Void
// upstream: let legacyLayOutGridByContainLabel: LegacyLayOutGridByContainLabel | NullUndefined;
var legacyLayOutGridByContainLabel: LegacyLayOutGridByContainLabel?
public func registerLegacyGridContainLabelImpl(_ impl: @escaping LegacyLayOutGridByContainLabel) {
    legacyLayOutGridByContainLabel = impl
}

// ============================================================================
// PORT-TODO (OUT OF SCOPE — component/axis AxisBuilder label-overlap path, Phase 6b):
//   `createAxisBiulders` / `layOutGridByOuterBounds` / `createOrUpdateAxesView` / `resolveAxisNameOverlapForGrid`
//   depend on `AxisBuilderSharedContext` / `AxisBuilder` (component/axis/AxisBuilder.ts), `expandOrShrinkRect`
//   / `XY` / `WH` (util/graphic.swift), and the `*CommonPartBuilder` helpers (cartesianAxisHelper.swift).
//   These are stubbed here per the phase scope; the axis-elements-building / outerBounds-shrink logic must be
//   ported when component/axis lands. The shared context is modeled as an opaque `Any?` placeholder so the
//   `resize` control flow (which threads it through) stays structurally faithful.
// ============================================================================

// Return noPxChange.
// upstream: layOutGridByOuterBounds(outerBoundsRect, outerBoundsContain, outerBoundsClamp, gridRect, axesMap,
//   axisBuilderSharedCtx: AxisBuilderSharedContext, layoutRef: BoxLayoutReferenceResult): boolean
func layOutGridByOuterBounds(
    _ outerBoundsRect: BoundingRect,
    _ outerBoundsContain: ParsedOuterBoundsContain,
    _ outerBoundsClamp: [Double]?,
    _ gridRect: LayoutRect,
    _ axesMap: AxesMap,
    _ axisBuilderSharedCtx: Any?,  // PORT-TODO: AxisBuilderSharedContext (component/axis, Phase 6b)
    _ layoutRef: BoxLayoutReferenceResult
) -> Bool {
    // PORT-TODO: full outerBounds shrink (createOrUpdateAxesView estimate + fillLabelNameOverflowOnOneDimension
    //   + fillMarginOnOneDimension + expandOrShrinkRect + updateAllAxisExtentTransByGridRect) needs the
    //   AxisBuilder-produced label/name rects. Stubbed: report no pixel change.
    _ = (outerBoundsRect, outerBoundsContain, outerBoundsClamp, gridRect, axesMap, axisBuilderSharedCtx, layoutRef)
    return true
}

// upstream: createAxisBiulders(gridRect, cartesians, axesMap, optionContainLabel, api): AxisBuilderSharedContext
func createAxisBiulders(
    _ gridRect: LayoutRect,
    _ cartesians: [Cartesian2D],
    _ axesMap: AxesMap,
    _ optionContainLabel: Any?,  // upstream: GridOption['containLabel']
    _ api: ExtensionAPI
) -> Any? {  // PORT-TODO: AxisBuilderSharedContext (component/axis, Phase 6b)
    // PORT-TODO: builds `axis.axisBuilder` via `createCartesianAxisViewCommonPartBuilder` for each shown axis
    //   and returns a `new AxisBuilderSharedContext(resolveAxisNameOverlapForGrid)`. Stubbed (no builders).
    _ = (gridRect, cartesians, axesMap, optionContainLabel, api)
    return nil
}

/**
 * Promote the axis-elements-building from "view render" stage to "coordinate system resize" stage.
 * This is aimed to resovle overlap across multiple axes, since currently it's hard to reconcile
 * multiple axes in "view render" stage.
 *
 * [CAUTION] But this promotion assumes that the subsequent "visual mapping" stage does not affect
 * this axis-elements-building; otherwise we have to refactor it again.
 */
// upstream: createOrUpdateAxesView(gridRect, axesMap, kind: AxisTickLabelComputingKind, outerBoundsContain,
//   noPxChange, layoutRef): void
func createOrUpdateAxesView(
    _ gridRect: LayoutRect,
    _ axesMap: AxesMap,
    // upstream `kind: AxisTickLabelComputingKind` (= 1 | 2) → `Double` (see AxisTickLabelComputingKind namespace).
    _ kind: Double,
    _ outerBoundsContain: ParsedOuterBoundsContain?,
    _ noPxChange: Bool,
    _ layoutRef: BoxLayoutReferenceResult
) {
    // PORT-TODO: updates each `axis.axisBuilder`, calls `build({axisTickLabel*}/{axisName}/{axisLine})`,
    //   and computes `nameMarginLevel`. Requires component/axis AxisBuilder. Stubbed as a no-op.
    _ = (gridRect, axesMap, kind, outerBoundsContain, noPxChange, layoutRef)
}

// upstream: prepareOuterBounds(gridModel, rawGridRect: BoundingRect, layoutRef): {outerBoundsRect, parsedOuterBoundsContain, outerBoundsClamp}
func prepareOuterBounds(
    _ gridModel: GridModel,
    _ rawGridRect: BoundingRect,
    _ layoutRef: BoxLayoutReferenceResult
) -> (outerBoundsRect: BoundingRect?, parsedOuterBoundsContain: ParsedOuterBoundsContain, outerBoundsClamp: [Double]) {
    var outerBoundsRect: BoundingRect?
    let optionOuterBoundsMode = gridModel.get("outerBoundsMode", true) as? String
    if optionOuterBoundsMode == "same" {
        outerBoundsRect = rawGridRect.clone()
    }
    else if optionOuterBoundsMode == nil || optionOuterBoundsMode == "auto" {
        // upstream: getLayoutRect(gridModel.get('outerBounds', true) || OUTER_BOUNDS_DEFAULT, layoutRef.refContainer)
        let outerBoundsOpt = gridModel.get("outerBounds", true)
        outerBoundsRect = layout.getLayoutRect(
            isTruthy(outerBoundsOpt) ? outerBoundsOpt : OUTER_BOUNDS_DEFAULT, layoutRef.refContainer
        )
    }
    else if optionOuterBoundsMode != "none" {
        if __DEV__ {
            log.error("Invalid grid[\(Int(gridModel.componentIndex))].outerBoundsMode.")
        }
    }

    let optionOuterBoundsContain = gridModel.get("outerBoundsContain", true) as? String
    var parsedOuterBoundsContain: ParsedOuterBoundsContain
    if optionOuterBoundsContain == nil || optionOuterBoundsContain == "auto" {
        parsedOuterBoundsContain = "all"
    }
    else if util.indexOf(["all", "axisLabel"], optionOuterBoundsContain!) < 0 {
        if __DEV__ {
            log.error("Invalid grid[\(Int(gridModel.componentIndex))].outerBoundsContain.")
        }
        parsedOuterBoundsContain = "all"
    }
    else {
        parsedOuterBoundsContain = optionOuterBoundsContain!
    }

    let outerBoundsClamp: [Double] = [
        number.parsePositionSizeOption(
            util.retrieve2(gridModel.get("outerBoundsClampWidth", true), OUTER_BOUNDS_CLAMP_DEFAULT[0]), rawGridRect.width
        ),
        number.parsePositionSizeOption(
            util.retrieve2(gridModel.get("outerBoundsClampHeight", true), OUTER_BOUNDS_CLAMP_DEFAULT[1]), rawGridRect.height
        )
    ]

    return (outerBoundsRect: outerBoundsRect, parsedOuterBoundsContain: parsedOuterBoundsContain, outerBoundsClamp: outerBoundsClamp)
}

// upstream: const resolveAxisNameOverlapForGrid: AxisBuilderSharedContext['resolveAxisNameOverlap'] = (...) => {...}
// PORT-TODO (OUT OF SCOPE): the axis-name overlap resolution against perpendicular axes needs component/axis
//   (`resolveAxisNameOverlapDefault` / `moveIfOverlapByLinearLabels` / `AxisBuilderSharedContext`). Deferred to Phase 6b.

// JS truthiness for a dynamic option value (used where upstream relies on `if (x)` / `!x`).
// PORT-TODO: falsy = nil / NSNull / false / 0 / "" / NaN (CONVENTIONS §6).
private func isTruthy(_ value: Any?) -> Bool {
    switch value {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}

// upstream: export default Grid;  -> `public final class Grid` above.
