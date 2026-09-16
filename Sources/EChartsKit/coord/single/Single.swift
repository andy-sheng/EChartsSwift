// Ported from echarts/src/coord/single/Single.ts — keep in sync with upstream
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
 * Single coordinates system.
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import SingleAxis from './SingleAxis';                                 -> SingleAxis (sibling, this batch).
//   import * as axisHelper from '../axisHelper';                           -> `axisHelper.*` (coord/axisHelper.swift).
//   import {createBoxLayoutReference, getLayoutRect} from '../../util/layout';
//       -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` (util/layout.swift).
//   import { CoordinateSystem, CoordinateSystemMaster } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See the CoordinateSystem-drop note on the class below.
//   import GlobalModel from '../../model/Global';                          -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                    -> ExtensionAPI.
//   import BoundingRect from 'zrender/src/core/BoundingRect';              -> BoundingRect / LayoutRect (ZRenderKit; LayoutRect = BoundingRect).
//   import SingleAxisModel, { COORD_SYS_TYPE_SINGLE } from './AxisModel';  -> SingleAxisModel + COORD_SYS_TYPE_SINGLE.
//       coord/single/AxisModel.ts is ported as `SingleAxisModel.swift` (named that way — a
//       second `AxisModel.swift` would collide with coord/cartesian's). It
//       exports the constant `COORD_SYS_TYPE_SINGLE = "single"` and `open class SingleAxisModel:
//       AxisBaseModel` (a `ComponentModel`, with `coordinateSystem: Single`).
//   import { ParsedModelFinder, ParsedModelFinderKnown } from '../../util/model';
//       -> ParsedModelFinder / ParsedModelFinderKnown (`[String: Any]`, util/modelUtil.swift).
//   import { ScaleDataValue } from '../../util/types';                     -> ScaleDataValue (util/types.swift; = Any).
//   import { scaleCalcNice } from '../axisNiceTicks';                      -> scaleCalcNice + ScaleCalcNiceAxisLike (coord/axisNiceTicks.swift).
//   import { AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE, scaleRawExtentInfoCreate } from '../scaleRawExtentInfo';
//       -> scaleRawExtentInfoCreate / AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE (coord/scaleRawExtentInfo.swift).

// upstream: export const singleDimensions = ['single'];
public let singleDimensions: [DimensionName] = ["single"]

/**
 * Create a single coordinates system.
 */
// upstream: class Single implements CoordinateSystem, CoordinateSystemMaster { ... }
//   Reference type → `public final class`. Conforms to `CoordinateSystemMaster` only (dropping the
//   `CoordinateSystem` conformance) for the same reason as Polar/Radar: Single's `dataToPoint(val, ...)`
//   / `pointToData(point, ...)` carry single-axis-specific signatures that do NOT match the
//   `CoordinateSystem` protocol requirements (`dataToPoint(data, opt?)` / `pointToData(point, opt?)`),
//   and every use site holds the concrete `Single` type (SingleAxisModel.coordinateSystem,
//   series `coordinateSystem as? Single`). Those converters are therefore plain concrete methods.
//   `CoordinateSystemMaster` is what the coord-sys registry / axisPointer / tooltip need.
public final class Single: CoordinateSystemMaster {

    // upstream: readonly type = COORD_SYS_TYPE_SINGLE;
    //   `COORD_SYS_TYPE_SINGLE` ("single") is defined in the sibling SingleAxisModel.swift.
    public let type = COORD_SYS_TYPE_SINGLE

    // upstream: readonly dimension = 'single';
    public let dimension: DimensionName = "single"

    /**
     * Add it just for draw tooltip.
     */
    // upstream: readonly dimensions = singleDimensions;
    //   Upstream is readonly; `CoordinateSystemMaster.dimensions` requires `{ get set }`, so `var`.
    public var dimensions: [DimensionName] = singleDimensions

    // upstream: name: string;  (assigned by singleCreator: `single.name = 'single_' + idx`).
    public var name: String = ""

    // upstream: axisPointerEnabled: boolean = true;
    //   Witnesses `CoordinateSystemMaster.axisPointerEnabled: Bool?` (optional in the protocol).
    public var axisPointerEnabled: Bool? = true

    // upstream: model: SingleAxisModel;  (injected outside — assigned in `init`).
    //   PROTOCOL-WITNESS FIX (mirrors Grid/Cartesian2D): a stored `var model: SingleAxisModel!` does NOT
    //   witness `CoordinateSystemMaster.model: ComponentModel? { get set }` — Optional is invariant, so
    //   `SingleAxisModel?` ≠ `ComponentModel?`, and `coordSys.model` dispatched through the
    //   `CoordinateSystemMaster` existential hit the nil-returning default extension. That silently broke
    //   axisPointer `modelHelper.collect` (`guard let coordSysModel = coordSys.model` always failed →
    //   empty `coordSysAxesInfo` → NO axis tooltip for themeRiver). Store the concrete model privately and
    //   expose a settable `var model: ComponentModel?` that actually witnesses the requirement;
    //   `singleAxisModel` keeps the concrete-typed accessor for internal use.
    private var _singleAxisModel: SingleAxisModel!
    public var singleAxisModel: SingleAxisModel! { _singleAxisModel }
    public var model: ComponentModel? {
        get { return _singleAxisModel }
        set { _singleAxisModel = newValue as? SingleAxisModel }
    }

    // upstream: boxCoordinateSystem?: CoordinateSystem  (CoordinateSystemMaster requirement).
    //   Not used by Single; satisfies the protocol (upstream leaves it unset → undefined).
    public var boxCoordinateSystem: CoordinateSystem?

    // upstream: private _axis: SingleAxis;  (assigned in `_init`, before any accessor) -> IUO.
    private var _axis: SingleAxis!

    // upstream: private _rect: BoundingRect;  (assigned in `resize`, before any `getRect`) -> IUO.
    //   `LayoutRect` (= BoundingRect) is what `getLayoutRect` returns.
    private var _rect: LayoutRect!

    // upstream: constructor(axisModel: SingleAxisModel, ecModel: GlobalModel, api: ExtensionAPI) {
    //     this.model = axisModel;
    //     this._init(axisModel, ecModel, api);
    // }
    public init(_ axisModel: SingleAxisModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._singleAxisModel = axisModel
        self._init(axisModel, ecModel, api)
    }

    /**
     * Initialize single coordinate system.
     */
    // upstream: _init(axisModel, ecModel, api) { ... }
    public func _init(_ axisModel: SingleAxisModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {

        // const dim = this.dimension;
        let dim = self.dimension

        // const axisType = axisHelper.determineAxisType(axisModel);
        let axisType = axisHelper.determineAxisType(axisModel)
        // const axis = new SingleAxis(dim, createScaleByModel(...), [0, 0], axisType, axisModel.get('position'));
        let axis = SingleAxis(
            dim,
            axisHelper.createScaleByModel(axisModel, axisType, true),
            [0, 0],
            axisType,
            axisModel.get("position") as? SingleAxisPosition
        )

        // axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel);
        axis.onBand = axisHelper.isAxisOnBand(axis.scale, axisModel)
        // axis.inverse = axisModel.get('inverse');
        axis.inverse = (axisModel.get("inverse") as? Bool) ?? false
        // axis.orient = axisModel.get('orient');
        //   `orient` is 'horizontal' | 'vertical' in the dynamic bag; parse into the LayoutOrient enum.
        axis.orient = LayoutOrient(rawValue: (axisModel.get("orient") as? String) ?? "horizontal") ?? .horizontal

        // axisModel.axis = axis;
        axisModel.axis = axis
        // axis.model = axisModel;
        axis.model = axisModel
        // axis.coordinateSystem = this;
        axis.coordinateSystem = self
        // this._axis = axis;
        self._axis = axis
    }

    /**
     * Update axis scale after data processed
     */
    // upstream: update(ecModel, api) { ... }
    //   Witnesses `CoordinateSystemMaster.update`.
    public func update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let axis = self._axis!
        scaleRawExtentInfoCreate(axis, AXIS_EXTENT_INFO_BUILD_FROM_COORD_SYS_UPDATE)
        // BUGFIX (category single axis), mirrors coord/cartesian/Grid.update: an ordinal scale whose
        //   extent froze blank ([inf,-inf]) at scale-init (before its ordinalMeta collected its
        //   `data` categories) must be re-derived to [0, n-1] here — otherwise `dataToCoord` returns NaN
        //   and BOTH the axis tick labels AND any scatter placed on the single axis vanish. Same
        //   port-specific ordinal-meta timing workaround the Grid path already applies.
        if let ordinal = axis.scale as? OrdinalScale {
            ordinal.setSortInfo(axis.model.get("categorySortInfo") as? OrdinalSortInfo)
            ordinal.recomputeExtentFromOrdinalMetaIfBlank()
        }
        scaleCalcNice(ScaleCalcNiceAxisLike(scale: axis.scale, model: axis.model))
    }

    /**
     * Resize the single coordinate system.
     */
    // upstream: resize(axisModel, api) { ... }
    public func resize(_ axisModel: SingleAxisModel, _ api: ExtensionAPI) {
        // const refContainer = createBoxLayoutReference(axisModel, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(axisModel, api).refContainer
        // this._rect = getLayoutRect(axisModel.getBoxLayoutParams(), refContainer);
        self._rect = layout.getLayoutRect(axisModel.getBoxLayoutParams(), refContainer)

        self._adjustAxis()
    }

    // upstream: getRect() { return this._rect; }
    //   upstream returns the concrete `BoundingRect`; the optional protocol requirement
    //   `CoordinateSystemMaster.getRect(): RectLike?` therefore resolves to its nil default when Single is
    //   held as the protocol (mirroring Grid.getRect). Concrete-typed holders get the real rect.
    public func getRect() -> LayoutRect {
        return self._rect
    }

    // upstream: private _adjustAxis() { ... }
    private func _adjustAxis() {

        let rect = self._rect!
        let axis = self._axis!

        let isHorizontal = axis.isHorizontal()
        let extent: [Double] = isHorizontal ? [0, rect.width] : [0, rect.height]
        let idx = axis.inverse ? 1 : 0

        axis.setExtent(extent[idx], extent[1 - idx])

        self._updateAxisTransform(axis, isHorizontal ? rect.x : rect.y)
    }

    // upstream: private _updateAxisTransform(axis: SingleAxis, coordBase: number) { ... }
    private func _updateAxisTransform(_ axis: SingleAxis, _ coordBase: Double) {

        let axisExtent = axis.getExtent()
        let extentSum = axisExtent[0] + axisExtent[1]
        let isHorizontal = axis.isHorizontal()

        // axis.toGlobalCoord = isHorizontal
        //     ? function (coord) { return coord + coordBase; }
        //     : function (coord) { return extentSum - coord + coordBase; };
        axis.toGlobalCoord = isHorizontal
            ? { coord in coord + coordBase }
            : { coord in extentSum - coord + coordBase }

        // axis.toLocalCoord = isHorizontal
        //     ? function (coord) { return coord - coordBase; }
        //     : function (coord) { return extentSum - coord + coordBase; };
        axis.toLocalCoord = isHorizontal
            ? { coord in coord - coordBase }
            : { coord in extentSum - coord + coordBase }
    }

    /**
     * Get axis.
     */
    // upstream: getAxis() { return this._axis; }
    public func getAxis() -> SingleAxis {
        return self._axis
    }

    /**
     * Get axis, add it just for draw tooltip.
     */
    // upstream: getBaseAxis() { return this._axis; }
    public func getBaseAxis() -> SingleAxis {
        return self._axis
    }

    // upstream: getAxes() { return [this._axis]; }
    //   Witnesses `CoordinateSystemMaster.getAxes() -> [Axis]?` (optional in the protocol; never nil here).
    public func getAxes() -> [Axis]? {
        return [self._axis]
    }

    // upstream: getTooltipAxes() { return { baseAxes: [this.getAxis()], otherAxes: [] }; }
    //   Witnesses `CoordinateSystemMaster.getTooltipAxes(_:) -> (…)?`. Upstream takes NO `dim` argument
    //   (single has a single axis) — the protocol's `dim` param is accepted and ignored.
    public func getTooltipAxes(_ dim: DimensionName) -> (baseAxes: [Axis], otherAxes: [Axis])? {
        return (
            baseAxes: [self.getAxis()],
            // Empty otherAxes
            otherAxes: [] as [Axis]
        )
    }

    /**
     * If contain point.
     */
    // upstream: containPoint(point: number[]) { ... }
    public func containPoint(_ point: [Double]) -> Bool {
        let rect = self.getRect()
        let axis = self.getAxis()
        let orient = axis.orient
        if orient == .horizontal {
            return axis.contain(axis.toLocalCoord(point[0]))
                && (point[1] >= rect.y && point[1] <= (rect.y + rect.height))
        }
        else {
            // NOTE: faithful to upstream — the vertical branch tests `point[0]` against `rect.y`
            //   (not `rect.x`); preserved verbatim.
            return axis.contain(axis.toLocalCoord(point[1]))
                && (point[0] >= rect.y && point[0] <= (rect.y + rect.height))
        }
    }

    // upstream: pointToData(point: number[], reserved?: null, out?: number[]) { ... }
    //   `reserved`/`out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    @discardableResult
    public func pointToData(_ point: [Double]) -> [Double] {
        let axis = self.getAxis()
        // out[0] = axis.coordToData(axis.toLocalCoord(point[axis.orient === 'horizontal' ? 0 : 1]));
        let out0 = axis.coordToData(axis.toLocalCoord(
            point[axis.orient == .horizontal ? 0 : 1]
        ))
        return [out0]
    }

    /**
     * Convert the series data to concrete point.
     * Can be [val] | val
     */
    // upstream: dataToPoint(val: ScaleDataValue | ScaleDataValue[], reserved?, out?) { ... }
    //   `reserved`/`out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func dataToPoint(_ val: Any) -> [Double] {
        let axis = self.getAxis()
        let rect = self.getRect()
        let idx = axis.orient == .horizontal ? 0 : 1

        // if (val instanceof Array) { val = val[0]; }
        var value: Any = val
        if let arr = val as? [Any] {
            value = arr.isEmpty ? Double.nan : arr[0]
        }

        var out: [Double] = [0, 0]
        // out[idx] = axis.toGlobalCoord(axis.dataToCoord(+val));
        out[idx] = axis.toGlobalCoord(axis.dataToCoord(singlePlus(value)))
        // out[1 - idx] = idx === 0 ? (rect.y + rect.height / 2) : (rect.x + rect.width / 2);
        out[1 - idx] = idx == 0 ? (rect.y + rect.height / 2) : (rect.x + rect.width / 2)
        return out
    }

    // upstream: convertToPixel(ecModel, finder, value) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? this.dataToPoint(value) : null;
    // }
    //   Witnesses `CoordinateSystemMaster.convertToPixel`; `value: CoordinateSystemDataCoord` (= Any).
    public func convertToPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? self.dataToPoint(value) : nil
    }

    // upstream: convertFromPixel(ecModel, finder, pixel) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? this.pointToData(pixel) : null;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ pixelValue: [Double],
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? self.pointToData(pixelValue) : nil
    }
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown): Single {
//     const seriesModel = finder.seriesModel;
//     const singleModel = finder.singleAxisModel as SingleAxisModel;
//     return singleModel && singleModel.coordinateSystem
//         || seriesModel && seriesModel.coordinateSystem as Single;
// }
//   `finder` is `[String: Any]` → field access via subscript. note: references sibling `SingleAxisModel`.
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> Single? {
    let seriesModel = finder["seriesModel"] as? SeriesModel
    let singleModel = finder["singleAxisModel"] as? SingleAxisModel
    // singleModel && singleModel.coordinateSystem || seriesModel && seriesModel.coordinateSystem
    //   `SingleAxisModel.coordinateSystem` is typed `CoordinateSystemMaster?` (mirroring PolarModel),
    //   so narrow to the concrete `Single`.
    if let singleModel = singleModel, let cs = singleModel.coordinateSystem as? Single {
        return cs
    }
    return seriesModel?.coordinateSystem as? Single
}

// JS unary `+val`: coerce a data value to a Double (number stays, numeric string parses, else NaN).
// Kept explicit (rather than a bare `as? Double`) to tolerate the Int / NSNumber boxing used by dynamic
// values — the recurring Int-vs-Double numeric-read trap.
private func singlePlus(_ v: Any) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

// export default Single;  -> `public final class Single` above.
