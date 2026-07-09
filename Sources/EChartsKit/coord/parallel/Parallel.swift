// Ported from echarts/src/coord/parallel/Parallel.ts — keep in sync with upstream
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
 * Parallel Coordinates
 * <https://en.wikipedia.org/wiki/Parallel_coordinates>
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import {each, createHashMap, clone} from 'zrender/src/core/util';
//       -> `util.each` / `createHashMap` (util/modelUtil.swift shim) / `util.clone` (ZRenderKit).
//   import * as matrix from 'zrender/src/core/matrix';                    -> `matrix.*` (ZRenderKit; MatrixArray = [Double]).
//   import * as layoutUtil from '../../util/layout';                      -> `layout.*` (util/layout.swift).
//   import * as axisHelper from '../../coord/axisHelper';                 -> `axisHelper.*` (coord/axisHelper.swift).
//   import ParallelAxis from './ParallelAxis';
//       -> ParallelAxis (sibling ParallelAxis.swift). PORT-TODO: lands this phase — `class ParallelAxis:
//          Axis` with `axisIndex: Double`, injected `model: ParallelAxisModel`, `coordinateSystem: Parallel`.
//   import * as graphic from '../../util/graphic';
//       -> `graphic.applyTransform([coord,0], m)` maps to `vector.applyTransform(_ v:VectorArray, _ m:)`
//          (ZRenderKit). `graphic.BoundingRect` -> `LayoutRect` (= BoundingRect).
//   import {mathCeil, mathFloor, mathMax, mathMin, mathPI, round} from '../../util/number';
//       -> `number.mathCeil` / `number.mathFloor` / `number.mathMax` / `number.mathMin` / `number.mathPI`
//          / `number.round` (util/number.swift).
//   import sliderMove from '../../component/helper/sliderMove';
//       -> sliderMove (component/helper/sliderMove.swift). PORT-TODO: only used by the DEFERRED
//          `getSlidedAxisExpandWindow` (axis-drag interaction).
//   import ParallelModel, { COORD_SYS_TYPE_PARALLEL, ParallelLayoutDirection } from './ParallelModel';
//       -> ParallelModel + COORD_SYS_TYPE_PARALLEL + ParallelLayoutDirection (sibling ParallelModel.swift).
//          PORT-TODO: lands this phase — `class ParallelModel: ComponentModel` with `dimensions:
//          [DimensionName]`, `parallelAxisIndex: [Double]`, `coordinateSystem: Parallel`. Constant
//          `COORD_SYS_TYPE_PARALLEL = "parallel"`; `typealias ParallelLayoutDirection = String`.
//   import GlobalModel from '../../model/Global';                         -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                   -> ExtensionAPI.
//   import { Dictionary, DimensionName, ScaleDataValue } from '../../util/types';
//       -> `[String: T]` / DimensionName / ScaleDataValue (util/types.swift; ScaleDataValue = Any).
//   import { CoordinateSystem, CoordinateSystemMaster } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See the conformance note on the class below.
//   import ParallelAxisModel, { ParallelActiveState } from './AxisModel';
//       -> ParallelAxisModel + ParallelActiveState (sibling ParallelAxisModel.swift — named
//          `ParallelAxisModel.swift`, NOT `AxisModel.swift`, to avoid colliding with coord/cartesian's).
//          PORT-TODO: lands this phase; `typealias ParallelActiveState = String` ('normal'|'active'|'inactive').
//   import SeriesData from '../../data/SeriesData';                       -> SeriesData (data/SeriesData.swift).
//   import { scaleCalcNice } from '../axisNiceTicks';
//       -> scaleCalcNice + ScaleCalcNiceAxisLike (coord/axisNiceTicks.swift).
//   import { AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE, scaleRawExtentInfoCreate } from '../scaleRawExtentInfo';
//       -> scaleRawExtentInfoCreate / AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE (coord/scaleRawExtentInfo.swift).
//
// Static-render scope (CONVENTIONS §5 + task): the layout math + `dataToPoint` polyline mapping are ported
// in full; the brush / active-interval / axis-drag INTERACTION paths (`eachActiveState`, `hasAxisBrushed`,
// `getSlidedAxisExpandWindow`) are DEFERRED and stubbed with `// PORT-TODO`.

// upstream: interface ParallelCoordinateSystemLayoutInfo { ... }
//   Internal data bag → private struct (CONVENTIONS §4).
private struct ParallelCoordinateSystemLayoutInfo {
    var layout: ParallelLayoutDirection
    var pixelDimIndex: Int
    var layoutBase: Double
    var layoutLength: Double
    var axisBase: Double
    var axisLength: Double
    var axisExpandable: Bool
    var axisExpandWidth: Double
    var axisCollapseWidth: Double
    var axisExpandWindow: [Double]
    var axisCount: Double
    var winInnerIndices: [Double]
    var axisExpandWindow0Pos: Double
}

// upstream: export interface ParallelAxisLayoutInfo { ... }
//   Public data bag → struct (CONVENTIONS §4). All fields are value types, so `getAxisLayout`'s
//   `clone(...)` reduces to a plain value copy (see note there).
public struct ParallelAxisLayoutInfo {
    public var position: [Double]
    public var rotation: Double
    public var transform: MatrixArray
    public var axisNameAvailableWidth: Double
    public var axisLabelShow: Bool
    public var nameTruncateMaxWidth: Double?
    // upstream: tickDirection: -1 | 1;
    public var tickDirection: Double
    // upstream: labelDirection: -1 | 1;
    public var labelDirection: Double
    public init(
        position: [Double],
        rotation: Double,
        transform: MatrixArray,
        axisNameAvailableWidth: Double,
        axisLabelShow: Bool,
        nameTruncateMaxWidth: Double?,
        tickDirection: Double,
        labelDirection: Double
    ) {
        self.position = position
        self.rotation = rotation
        self.transform = transform
        self.axisNameAvailableWidth = axisNameAvailableWidth
        self.axisLabelShow = axisLabelShow
        self.nameTruncateMaxWidth = nameTruncateMaxWidth
        self.tickDirection = tickDirection
        self.labelDirection = labelDirection
    }
}

// upstream: type SlidedAxisExpandBehavior = 'none' | 'slide' | 'jump';
public typealias SlidedAxisExpandBehavior = String

// upstream: class Parallel implements CoordinateSystemMaster, CoordinateSystem { ... }
//   Reference type → `public final class`. Conforms to `CoordinateSystemMaster` only (dropping the
//   `CoordinateSystem` conformance) for the same reason as Polar/Single/Radar: Parallel's
//   `dataToPoint(value, dim)` carries a parallel-specific signature (a datum maps to a POINT on a named
//   axis) that does NOT match the `CoordinateSystem` protocol requirement `dataToPoint(data, opt?)`, and
//   every use site holds the concrete `Parallel` type (ParallelModel.coordinateSystem, series
//   `coordinateSystem as? Parallel`). `CoordinateSystemMaster` is what the coord-sys registry needs.
public final class Parallel: CoordinateSystemMaster {

    // upstream: readonly type = COORD_SYS_TYPE_PARALLEL;
    public let type = COORD_SYS_TYPE_PARALLEL

    /**
     * key: dimension
     */
    // upstream: private _axesMap = createHashMap<ParallelAxis>();
    private var _axesMap: HashMap<ParallelAxis> = createHashMap()

    /**
     * key: dimension
     * value: {position: [], rotation, }
     */
    // upstream: private _axesLayout: Dictionary<ParallelAxisLayoutInfo> = {};
    private var _axesLayout: [String: ParallelAxisLayoutInfo] = [:]

    /**
     * Always follow axis order.
     */
    // upstream: readonly dimensions: ParallelModel['dimensions'];
    //   Upstream is readonly; `CoordinateSystemMaster.dimensions` requires `{ get set }`, so `var`.
    public var dimensions: [DimensionName]

    // upstream: private _rect: graphic.BoundingRect;  (assigned in `resize`, before any `getRect`) -> IUO.
    private var _rect: LayoutRect!

    // upstream: private _model: ParallelModel;
    private var _model: ParallelModel

    // Inject
    // upstream: name: string;  (assigned by the creator: `coordSys.name = 'parallel_' + idx`).
    public var name: String = ""
    // upstream: model: ParallelModel;  (injected outside — assigned in the creator).
    //   NOTE: `CoordinateSystemMaster.model` requires `ComponentModel?`; ParallelModel is a
    //   `ComponentModel` subclass, so this concrete property both stores the model and witnesses that
    //   requirement (mirroring Single's `model: SingleAxisModel!`).
    public var model: ParallelModel!

    // upstream: boxCoordinateSystem?: CoordinateSystem  (CoordinateSystemMaster requirement).
    //   Not used by Parallel; satisfies the protocol (upstream leaves it unset → undefined).
    public var boxCoordinateSystem: CoordinateSystem?

    // upstream: axisPointerEnabled — not declared by Parallel; the optional protocol requirement resolves
    //   to nil for Parallel.

    // upstream: constructor(parallelModel, ecModel, api) {
    //     this.dimensions = parallelModel.dimensions;
    //     this._model = parallelModel;
    //     this._init(parallelModel, ecModel, api);
    // }
    public init(_ parallelModel: ParallelModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.dimensions = parallelModel.dimensions
        self._model = parallelModel

        self._init(parallelModel, ecModel, api)
    }

    // upstream: private _init(parallelModel, ecModel, api): void { ... }
    private func _init(_ parallelModel: ParallelModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {

        let dimensions = parallelModel.dimensions
        let parallelAxisIndex = parallelModel.parallelAxisIndex

        // each(dimensions, function (dim, idx) { ... }, this);
        util.each(dimensions) { (dim: DimensionName, idx: Int) in

            let axisIndex = parallelAxisIndex[idx]
            // const axisModel = ecModel.getComponent('parallelAxis', axisIndex) as ParallelAxisModel;
            let axisModel = ecModel.getComponent("parallelAxis", axisIndex) as! ParallelAxisModel

            let axisType = axisHelper.determineAxisType(axisModel)
            // const axis = this._axesMap.set(dim, new ParallelAxis(
            //     dim, createScaleByModel(axisModel, axisType, false), [0, 0], axisType, axisIndex
            // ));
            let axis = self._axesMap.set(dim, ParallelAxis(
                dim,
                axisHelper.createScaleByModel(axisModel, axisType, false),
                [0, 0],
                axisType,
                axisIndex
            ))

            // axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel);
            axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel)
            // axis.inverse = axisModel.get('inverse');
            axis.inverse = (axisModel.get("inverse") as? Bool) ?? false

            // Injection
            axisModel.axis = axis
            axis.model = axisModel
            // axis.coordinateSystem = axisModel.coordinateSystem = this;
            axis.coordinateSystem = self
            axisModel.coordinateSystem = self
        }
    }

    /**
     * Update axis scale after data processed
     */
    // upstream: update(ecModel, api): void { ... }  — witnesses `CoordinateSystemMaster.update`.
    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // each(this.dimensions, function (dim) { ... }, this);
        util.each(self.dimensions) { (dim: DimensionName, _: Int) in
            let axis = self._axesMap.get(dim)!
            scaleRawExtentInfoCreate(axis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)
            // upstream: scaleCalcNice(axis);  — the Swift `scaleCalcNice` takes a `ScaleCalcNiceAxisLike`
            //   bag (scale + model), mirroring the Single port.
            scaleCalcNice(ScaleCalcNiceAxisLike(scale: axis.scale, model: axis.model))
        }
    }

    // upstream: containPoint(point: number[]): boolean { ... }  — witnesses `CoordinateSystemMaster.containPoint`.
    public func containPoint(_ point: [Double]) -> Bool {
        let layoutInfo = self._makeLayoutInfo()
        let axisBase = layoutInfo.axisBase
        let layoutBase = layoutInfo.layoutBase
        let pixelDimIndex = layoutInfo.pixelDimIndex
        let pAxis = point[1 - pixelDimIndex]
        let pLayout = point[pixelDimIndex]

        return pAxis >= axisBase
            && pAxis <= axisBase + layoutInfo.axisLength
            && pLayout >= layoutBase
            && pLayout <= layoutBase + layoutInfo.layoutLength
    }

    // upstream: getModel(): ParallelModel { return this._model; }
    public func getModel() -> ParallelModel {
        return self._model
    }

    /**
     * Resize the parallel coordinate system.
     */
    // upstream: resize(parallelModel, api): void { ... }
    public func resize(_ parallelModel: ParallelModel, _ api: ExtensionAPI) {
        // const refContainer = layoutUtil.createBoxLayoutReference(parallelModel, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(parallelModel, api).refContainer
        // this._rect = layoutUtil.getLayoutRect(parallelModel.getBoxLayoutParams(), refContainer);
        self._rect = layout.getLayoutRect(parallelModel.getBoxLayoutParams(), refContainer)

        self._layoutAxes()
    }

    // upstream: getRect(): graphic.BoundingRect { return this._rect; }
    //   PORT-TODO: upstream returns the concrete `BoundingRect`; the optional protocol requirement
    //   `CoordinateSystemMaster.getRect(): RectLike?` therefore resolves to its nil default when Parallel is
    //   held as the protocol (mirroring Single.getRect). Concrete-typed holders get the real rect.
    public func getRect() -> LayoutRect {
        return self._rect
    }

    // upstream: private _makeLayoutInfo(): ParallelCoordinateSystemLayoutInfo { ... }
    private func _makeLayoutInfo() -> ParallelCoordinateSystemLayoutInfo {
        let parallelModel = self._model
        let rect = self._rect!
        // const xy = ['x', 'y'] as const;  const wh = ['width', 'height'] as const;
        //   `rect[xy[i]]` / `rect[wh[i]]` — BoundingRect has no string subscript; indexed via `rectXY`/`rectWH`.
        // const layout = parallelModel.get('layout');
        let layoutDir: ParallelLayoutDirection = (parallelModel.get("layout") as? String) ?? "horizontal"
        // const pixelDimIndex = layout === 'horizontal' ? 0 : 1;
        let pixelDimIndex = layoutDir == "horizontal" ? 0 : 1
        // const layoutLength = rect[wh[pixelDimIndex]];
        let layoutLength = rectWH(rect, pixelDimIndex)
        let layoutExtent: [Double] = [0, layoutLength]
        // const axisCount = this.dimensions.length;
        let axisCount = Double(self.dimensions.count)

        // const axisExpandWidth = restrict(parallelModel.get('axisExpandWidth'), layoutExtent);
        let axisExpandWidth = restrict(numOpt(parallelModel.get("axisExpandWidth")) ?? 0, layoutExtent)
        // const axisExpandCount = restrict(parallelModel.get('axisExpandCount') || 0, [0, axisCount]);
        let axisExpandCount = restrict(numOpt(parallelModel.get("axisExpandCount")) ?? 0, [0, axisCount])
        // const axisExpandable = parallelModel.get('axisExpandable') && axisCount > 3 && ... ;
        let axisExpandable = ((parallelModel.get("axisExpandable") as? Bool) ?? false)
            && axisCount > 3
            && axisCount > axisExpandCount
            && axisExpandCount > 1
            && axisExpandWidth > 0
            && layoutLength > 0

        // `axisExpandWindow` is According to the coordinates of [0, axisExpandLength],
        // for sake of consider the case that axisCollapseWidth is 0 (when screen is narrow),
        // where collapsed axes should be overlapped.
        // let axisExpandWindow = parallelModel.get('axisExpandWindow');
        var axisExpandWindow: [Double]? = numArrayOpt(parallelModel.get("axisExpandWindow"))
        var winSize: Double
        if axisExpandWindow == nil {  // if (!axisExpandWindow)
            winSize = restrict(axisExpandWidth * (axisExpandCount - 1), layoutExtent)
            // const axisExpandCenter = parallelModel.get('axisExpandCenter') || mathFloor(axisCount / 2);
            let axisExpandCenter = jsTruthyNum(numOpt(parallelModel.get("axisExpandCenter")))
                ?? number.mathFloor(axisCount / 2)
            // axisExpandWindow = [axisExpandWidth * axisExpandCenter - winSize / 2];
            var win = [axisExpandWidth * axisExpandCenter - winSize / 2]
            // axisExpandWindow[1] = axisExpandWindow[0] + winSize;
            win.append(win[0] + winSize)
            axisExpandWindow = win
        }
        else {
            // winSize = restrict(axisExpandWindow[1] - axisExpandWindow[0], layoutExtent);
            winSize = restrict(axisExpandWindow![1] - axisExpandWindow![0], layoutExtent)
            // axisExpandWindow[1] = axisExpandWindow[0] + winSize;
            axisExpandWindow![1] = axisExpandWindow![0] + winSize
        }

        // let axisCollapseWidth = (layoutLength - winSize) / (axisCount - axisExpandCount);
        var axisCollapseWidth = (layoutLength - winSize) / (axisCount - axisExpandCount)
        // Avoid axisCollapseWidth is too small.
        // axisCollapseWidth < 3 && (axisCollapseWidth = 0);
        if axisCollapseWidth < 3 { axisCollapseWidth = 0 }

        // Find the first and last indices > ewin[0] and < ewin[1].
        let winInnerIndices: [Double] = [
            number.mathFloor(number.round(axisExpandWindow![0] / axisExpandWidth, 1)) + 1,
            number.mathCeil(number.round(axisExpandWindow![1] / axisExpandWidth, 1)) - 1
        ]

        // Pos in ec coordinates.
        // const axisExpandWindow0Pos = axisCollapseWidth / axisExpandWidth * axisExpandWindow[0];
        let axisExpandWindow0Pos = axisCollapseWidth / axisExpandWidth * axisExpandWindow![0]

        return ParallelCoordinateSystemLayoutInfo(
            layout: layoutDir,
            pixelDimIndex: pixelDimIndex,
            // layoutBase: rect[xy[pixelDimIndex]],
            layoutBase: rectXY(rect, pixelDimIndex),
            layoutLength: layoutLength,
            // axisBase: rect[xy[1 - pixelDimIndex]],
            axisBase: rectXY(rect, 1 - pixelDimIndex),
            // axisLength: rect[wh[1 - pixelDimIndex]],
            axisLength: rectWH(rect, 1 - pixelDimIndex),
            axisExpandable: axisExpandable,
            axisExpandWidth: axisExpandWidth,
            axisCollapseWidth: axisCollapseWidth,
            axisExpandWindow: axisExpandWindow!,
            axisCount: axisCount,
            winInnerIndices: winInnerIndices,
            axisExpandWindow0Pos: axisExpandWindow0Pos
        )
    }

    // upstream: private _layoutAxes(): void { ... }
    private func _layoutAxes() {
        let rect = self._rect!
        let axes = self._axesMap
        let dimensions = self.dimensions
        let layoutInfo = self._makeLayoutInfo()
        let layoutDir = layoutInfo.layout

        // axes.each(function (axis) { ... });
        axes.each { (axis: ParallelAxis, _: String) in
            let axisExtent: [Double] = [0, layoutInfo.axisLength]
            let idx = axis.inverse ? 1 : 0
            axis.setExtent(axisExtent[idx], axisExtent[1 - idx])
        }

        // each(dimensions, function (dim, idx) { ... }, this);
        util.each(dimensions) { (dim: DimensionName, idx: Int) in
            // const posInfo = (layoutInfo.axisExpandable ? layoutAxisWithExpand : layoutAxisWithoutExpand)(idx, layoutInfo);
            let posInfo = (layoutInfo.axisExpandable
                ? layoutAxisWithExpand(Double(idx), layoutInfo)
                : layoutAxisWithoutExpand(Double(idx), layoutInfo)
            )

            // const positionTable = { horizontal: {x: posInfo.position, y: layoutInfo.axisLength},
            //                         vertical:   {x: 0,                 y: posInfo.position} };
            let positionTableX: Double
            let positionTableY: Double
            if layoutDir == "horizontal" {
                positionTableX = posInfo.position
                positionTableY = layoutInfo.axisLength
            }
            else {
                positionTableX = 0
                positionTableY = posInfo.position
            }
            // const rotationTable = { horizontal: mathPI / 2, vertical: 0 };
            let rotation = layoutDir == "horizontal" ? number.mathPI / 2 : 0

            // const position = [positionTable[layout].x + rect.x, positionTable[layout].y + rect.y];
            let position: [Double] = [
                positionTableX + rect.x,
                positionTableY + rect.y
            ]

            // const transform = matrix.create();
            // matrix.rotate(transform, transform, rotation);
            // matrix.translate(transform, transform, position);
            var transform = matrix.create()
            transform = matrix.rotate(transform, rotation)
            transform = matrix.translate(transform, VectorArray(position[0], position[1]))

            // TODO
            // tick layout info

            // TODO
            // update dimensions info based on axis order.

            self._axesLayout[dim] = ParallelAxisLayoutInfo(
                position: position,
                rotation: rotation,
                transform: transform,
                axisNameAvailableWidth: posInfo.axisNameAvailableWidth,
                axisLabelShow: posInfo.axisLabelShow,
                nameTruncateMaxWidth: posInfo.nameTruncateMaxWidth,
                tickDirection: 1,
                labelDirection: 1
            )
        }
    }

    /**
     * Get axis by dim.
     */
    // upstream: getAxis(dim: DimensionName): ParallelAxis { return this._axesMap.get(dim); }
    public func getAxis(_ dim: DimensionName) -> ParallelAxis {
        return self._axesMap.get(dim)!
    }

    /**
     * Convert a dim value of a single item of series data to Point.
     */
    // upstream: dataToPoint(value: ScaleDataValue, dim: DimensionName): number[] { ... }
    public func dataToPoint(_ value: ScaleDataValue, _ dim: DimensionName) -> [Double] {
        return self.axisCoordToPoint(
            self._axesMap.get(dim)!.dataToCoord(value),
            dim
        )
    }

    /**
     * Travel data for one time, get activeState of each data item.
     * @param start the start dataIndex that travel from.
     * @param end the next dataIndex of the last dataIndex will be travel.
     */
    // upstream: eachActiveState(data, callback, start?, end?): void { ... }
    //   Ported in full (parallel-axis-brush task): the active state of each datum is classified against the
    //   per-axis `ParallelAxisModel.getActiveState(value)` (populated by the `axisAreaSelect` action —
    //   component/axis/parallelAxisAction.swift). When no axis is brushed (`hasAxisBrushed() === false`)
    //   every datum is `'normal'` (the static-render behavior); once an axis has an active interval a datum
    //   is `'inactive'` as soon as ANY axis reports it out-of-interval, else `'active'`.
    public func eachActiveState(
        _ data: SeriesData,
        _ callback: (ParallelActiveState, Int) -> Void,
        _ start: Int? = nil,
        _ end: Int? = nil
    ) {
        // start == null && (start = 0); end == null && (end = data.count());
        let start = start ?? 0
        let end = end ?? data.count()

        // const axesMap = this._axesMap; const dimensions = this.dimensions;
        let axesMap = self._axesMap
        let dimensions = self.dimensions
        // const dataDimensions = [] as DimensionName[]; const axisModels = [] as ParallelAxisModel[];
        var dataDimensions: [DimensionName] = []
        var axisModels: [ParallelAxisModel] = []

        // each(dimensions, function (axisDim) {
        //     dataDimensions.push(data.mapDimension(axisDim));
        //     axisModels.push(axesMap.get(axisDim).model);
        // });
        //   Port deviation: a plain for-loop (upstream `each`) — `data.mapDimension` may be nil, so fall
        //   back to `axisDim` to keep `dataDimensions` aligned with `dimensions` for the `values[j]` index.
        //   `axesMap.get(axisDim)!.model` is always the injected `ParallelAxisModel` (see `_makeLayoutInfo`).
        for axisDim in dimensions {
            dataDimensions.append(data.mapDimension(axisDim) ?? axisDim)
            axisModels.append(axesMap.get(axisDim)!.model as! ParallelAxisModel)
        }

        // const hasActiveSet = this.hasAxisBrushed();
        let hasActiveSet = self.hasAxisBrushed()

        var dataIndex = start
        while dataIndex < end {
            var activeState: ParallelActiveState

            if !hasActiveSet {
                activeState = "normal"
            }
            else {
                activeState = "active"
                // const values = data.getValues(dataDimensions, dataIndex);
                let values = data.getValues(dataDimensions, dataIndex)
                for j in 0..<dimensions.count {
                    // const state = axisModels[j].getActiveState(values[j]);
                    let state = axisModels[j].getActiveState(j < values.count ? values[j] : nil)
                    if state == "inactive" {
                        activeState = "inactive"
                        break
                    }
                }
            }

            callback(activeState, dataIndex)
            dataIndex += 1
        }
    }

    /**
     * Whether has any activeSet.
     */
    // upstream: hasAxisBrushed(): boolean { ... }
    //   Ported in full: true as soon as ANY parallel axis has a non-`'normal'` active state (i.e. its
    //   `ParallelAxisModel.activeIntervals` is non-empty from an `axisAreaSelect` selection).
    public func hasAxisBrushed() -> Bool {
        let dimensions = self.dimensions
        let axesMap = self._axesMap
        var hasActiveSet = false

        for j in 0..<dimensions.count {
            if (axesMap.get(dimensions[j])!.model as! ParallelAxisModel).getActiveState() != "normal" {
                hasActiveSet = true
            }
        }

        return hasActiveSet
    }

    /**
     * Convert coords of each axis to Point.
     *  Return point. For example: [10, 20]
     */
    // upstream: axisCoordToPoint(coord: number, dim: DimensionName): number[] { ... }
    public func axisCoordToPoint(_ coord: Double, _ dim: DimensionName) -> [Double] {
        let axisLayout = self._axesLayout[dim]!
        // return graphic.applyTransform([coord, 0], axisLayout.transform);
        let out = vector.applyTransform(VectorArray(coord, 0), axisLayout.transform)
        return [out[0], out[1]]
    }

    /**
     * Get axis layout.
     */
    // upstream: getAxisLayout(dim: DimensionName): ParallelAxisLayoutInfo { return clone(this._axesLayout[dim]); }
    //   Upstream deep-clones so callers can mutate freely; `ParallelAxisLayoutInfo` is a struct of value-type
    //   fields (arrays included), so returning it yields an independent value copy — equivalent to `clone`.
    public func getAxisLayout(_ dim: DimensionName) -> ParallelAxisLayoutInfo {
        return self._axesLayout[dim]!
    }

    /**
     * @return {Object} {axisExpandWindow, delta, behavior: 'jump' | 'slide' | 'none'}.
     */
    // upstream: getSlidedAxisExpandWindow(point: number[]): {axisExpandWindow: number[], behavior: ...} { ... }
    // PORT-TODO: DEFERRED — axis-drag (expand-window slide) interaction (CONVENTIONS §5 + task). The full
    //   body converts the pointer position into a slid `axisExpandWindow` via `sliderMove` and the
    //   `axisExpandSlideTriggerArea` option. Not needed for static layout/polyline render; the stub returns
    //   the current window with `behavior: 'none'` (upstream's out-of-bounds result). Restore the full
    //   `_makeLayoutInfo`-based slide math (see upstream) when the interaction lands.
    public func getSlidedAxisExpandWindow(_ point: [Double]) -> (axisExpandWindow: [Double], behavior: SlidedAxisExpandBehavior) {
        let layoutInfo = self._makeLayoutInfo()
        return (axisExpandWindow: layoutInfo.axisExpandWindow, behavior: "none")
    }

    // TODO
    // convertToPixel
    // convertFromPixel
    // Note:
    // (1) Consider Parallel, the return type of `convertToPixel` could be number[][] (Point[]).
    // (2) In parallel coord sys, how to make `convertFromPixel` make sense?
    // Perhaps convert a point based on "a rensent most axis" is more meaningful rather than based on all axes?

    // ------------------------------------------------------------------------------------------------
    // Coordinate-system creator.
    //
    // PORT-NOTE: Upstream lives in `echarts/src/coord/parallel/parallelCreator.ts` as the free function
    //   `createParallelCoordSys(ecModel, api)` wrapped in `{create: createParallelCoordSys}`. Per the task,
    //   it is hosted here as `Parallel.create(ecModel, api)` (mirroring `Grid.create`). A thin
    //   `CoordinateSystemCreator` wrapper (`parallelCreator`) that forwards to this and registers via
    //   `CoordinateSystemManager.register(COORD_SYS_TYPE_PARALLEL, ...)` is a separate sibling file.
    // upstream imports (parallelCreator.ts):
    //   import ParallelSeriesModel from '../../chart/parallel/ParallelSeries';  -> ParallelSeriesModel.
    //   import { SINGLE_REFERRING } from '../../util/model';                     -> model.SINGLE_REFERRING.
    //   import { associateSeriesWithAxis } from '../axisStatistics';            -> associateSeriesWithAxis.
    // ------------------------------------------------------------------------------------------------

    // upstream: function createParallelCoordSys(ecModel, api): CoordinateSystemMaster[] { ... }
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Parallel] {
        // const coordSysList: CoordinateSystemMaster[] = [];
        var coordSysList: [Parallel] = []

        // ecModel.eachComponent(COMPONENT_TYPE_PARALLEL, function (parallelModel: ParallelModel, idx: number) { ... });
        ecModel.eachComponent(COMPONENT_TYPE_PARALLEL) { (comp: ComponentModel, idx: Double) in
            guard let parallelModel = comp as? ParallelModel else { return }

            // const coordSys = new Parallel(parallelModel, ecModel, api);
            let coordSys = Parallel(parallelModel, ecModel, api)

            // coordSys.name = 'parallel_' + idx;
            coordSys.name = "parallel_" + String(Int(idx))
            // coordSys.resize(parallelModel, api);
            coordSys.resize(parallelModel, api)

            // parallelModel.coordinateSystem = coordSys;
            parallelModel.coordinateSystem = coordSys
            // coordSys.model = parallelModel;
            coordSys.model = parallelModel

            // coordSysList.push(coordSys);
            coordSysList.append(coordSys)
        }

        // Inject the coordinateSystems into seriesModel
        // ecModel.eachSeries(function (seriesModel) { ... });
        ecModel.eachSeries { (seriesModel: SeriesModel, _: Double) in
            // if ((seriesModel as ParallelSeriesModel).get('coordinateSystem') === COORD_SYS_TYPE_PARALLEL) { ... }
            if (seriesModel.get("coordinateSystem") as? String) == COORD_SYS_TYPE_PARALLEL {
                // const parallelModel = seriesModel.getReferringComponents(
                //     COMPONENT_TYPE_PARALLEL, SINGLE_REFERRING).models[0] as ParallelModel;
                // NOTE: fully qualify `EChartsKit.model.SINGLE_REFERRING` — the bare `model` collides with
                //   Parallel's instance property `var model: ParallelModel!` in this (static) context
                //   (same disambiguation as Grid.swift).
                let parallelModel = seriesModel.getReferringComponents(
                    COMPONENT_TYPE_PARALLEL, EChartsKit.model.SINGLE_REFERRING
                ).models.first as? ParallelModel
                // const parallel = seriesModel.coordinateSystem = parallelModel.coordinateSystem;
                //   `coordinateSystem` is typed `CoordinateSystemMaster?` on the host model; narrow to the
                //   concrete `Parallel` (which exposes `dimensions` / `getAxis`).
                let parallel = parallelModel?.coordinateSystem as? Parallel
                seriesModel.coordinateSystem = parallel
                // if (parallel) { each(parallel.dimensions, function (dim) { ... }); }
                if let parallel = parallel {
                    util.each(parallel.dimensions) { (dim: DimensionName, _: Int) in
                        associateSeriesWithAxis(parallel.getAxis(dim), seriesModel, COORD_SYS_TYPE_PARALLEL)
                    }
                }
            }
        }

        // return coordSysList;
        return coordSysList
    }
}


// upstream: function restrict(len: number, extent: number[]): number { return mathMin(mathMax(len, extent[0]), extent[1]); }
private func restrict(_ len: Double, _ extent: [Double]) -> Double {
    return number.mathMin(number.mathMax(len, extent[0]), extent[1])
}

// upstream: interface ParallelAxisLayoutPositionInfo { position; axisNameAvailableWidth; axisLabelShow; nameTruncateMaxWidth?; }
private struct ParallelAxisLayoutPositionInfo {
    var position: Double
    var axisNameAvailableWidth: Double
    var axisLabelShow: Bool
    var nameTruncateMaxWidth: Double?
}

// upstream: function layoutAxisWithoutExpand(axisIndex, layoutInfo): ParallelAxisLayoutPositionInfo { ... }
private func layoutAxisWithoutExpand(
    _ axisIndex: Double,
    _ layoutInfo: ParallelCoordinateSystemLayoutInfo
) -> ParallelAxisLayoutPositionInfo {
    // const step = layoutInfo.layoutLength / (layoutInfo.axisCount - 1);
    let step = layoutInfo.layoutLength / (layoutInfo.axisCount - 1)
    return ParallelAxisLayoutPositionInfo(
        position: step * axisIndex,
        axisNameAvailableWidth: step,
        axisLabelShow: true,
        nameTruncateMaxWidth: nil
    )
}

// upstream: function layoutAxisWithExpand(axisIndex, layoutInfo): ParallelAxisLayoutPositionInfo { ... }
private func layoutAxisWithExpand(
    _ axisIndex: Double,
    _ layoutInfo: ParallelCoordinateSystemLayoutInfo
) -> ParallelAxisLayoutPositionInfo {
    let layoutLength = layoutInfo.layoutLength
    let axisExpandWidth = layoutInfo.axisExpandWidth
    let axisCount = layoutInfo.axisCount
    let axisCollapseWidth = layoutInfo.axisCollapseWidth
    let winInnerIndices = layoutInfo.winInnerIndices

    var position: Double
    var axisNameAvailableWidth = axisCollapseWidth
    var axisLabelShow = false
    var nameTruncateMaxWidth: Double? = nil

    if axisIndex < winInnerIndices[0] {
        position = axisIndex * axisCollapseWidth
        nameTruncateMaxWidth = axisCollapseWidth
    }
    else if axisIndex <= winInnerIndices[1] {
        position = layoutInfo.axisExpandWindow0Pos
            + axisIndex * axisExpandWidth - layoutInfo.axisExpandWindow[0]
        axisNameAvailableWidth = axisExpandWidth
        axisLabelShow = true
    }
    else {
        position = layoutLength - (axisCount - 1 - axisIndex) * axisCollapseWidth
        nameTruncateMaxWidth = axisCollapseWidth
    }

    return ParallelAxisLayoutPositionInfo(
        position: position,
        axisNameAvailableWidth: axisNameAvailableWidth,
        axisLabelShow: axisLabelShow,
        nameTruncateMaxWidth: nameTruncateMaxWidth
    )
}

// ---------------------------------------------------------------------------------------------------
// Local numeric-read helpers (not upstream). See CONVENTIONS INT-vs-DOUBLE trap: `[String: Any]`
// option bags store numbers as bare `Int` literals, so a plain `as? Double` SILENTLY DROPS them.
// ---------------------------------------------------------------------------------------------------

// Coerce a dynamic option value to a Double (Int | Double | NSNumber). `nil` if not numeric.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// JS truthy filter on a numeric option (mirrors `x || fallback`): 0 / NaN / nil are falsy → nil.
private func jsTruthyNum(_ v: Double?) -> Double? {
    guard let v = v else { return nil }
    if v == 0 || v.isNaN { return nil }
    return v
}

// Coerce a dynamic option value to a `[Double]` (e.g. `axisExpandWindow`). `nil` if absent/not an array.
private func numArrayOpt(_ v: Any?) -> [Double]? {
    guard let arr = v as? [Any] else { return nil }
    return arr.map { numOpt($0) ?? Double.nan }
}

// `rect[['x','y'][i]]` — BoundingRect has no string subscript; select by pixel-dim index.
private func rectXY(_ rect: LayoutRect, _ i: Int) -> Double {
    return i == 0 ? rect.x : rect.y
}

// `rect[['width','height'][i]]` — select by pixel-dim index.
private func rectWH(_ rect: LayoutRect, _ i: Int) -> Double {
    return i == 0 ? rect.width : rect.height
}

// export default Parallel;  -> `public final class Parallel` above.
