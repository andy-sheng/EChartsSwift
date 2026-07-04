// Ported from echarts/src/coord/single/AxisModel.ts — keep in sync with upstream
//   NOTE: named SingleAxisModel.swift (not AxisModel.swift) to avoid a SwiftPM object-name collision
//   with coord/cartesian/AxisModel.swift and coord/polar/PolarAxisModel (duplicate basenames collide
//   in one target).
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

// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift)
// import { AxisModelExtendedInCreator } from '../axisModelCreator';   -> AxisModelExtendedInCreator (coord/axisModelCreator.swift)
// import {AxisModelCommonMixin} from '../axisModelCommonMixin';       -> AxisModelCommonMixin (coord/axisModelCommonMixin.swift, protocol)
// import Single from './Single';                                      -> Single (coord/single/Single.swift; coord-sys master, sibling this phase)
// import SingleAxis from './SingleAxis';                              -> SingleAxis (coord/single/SingleAxis.swift; sibling this phase)
// import { AxisBaseOption } from '../axisCommonTypes';                -> AxisBaseOption (dynamic option bag, see axisModelCreator.swift; PORT-TODO)
// import {
//     BoxLayoutOptionMixin, ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin, LayoutOrient
// } from '../../util/types';                                          -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import { AxisBaseModel } from '../AxisBaseModel';                   -> AxisBaseModel (coord/AxisBaseModel.swift)
// import { mixin } from 'zrender/src/core/util';                      -> util.mixin (ZRenderKit) — replaced by AxisBaseModel base conformance below.


// PENDING: For historical reason,
//  in ec option:
//    It can only declare as `series:{coordinateSystem: "singleAxis", ...}`
//    rather than 'single'. Therefore every `.get('coordinateSystem')` must
//    match "singleAxis". (See `referHelper.ts`)
//    And the component name can only be `singleAxis: {...}`.
//  But the internal convention uses 'singe' as coordinate system name
//  and dimension name.
// upstream: export const COORD_SYS_TYPE_SINGLE = 'single';
public let COORD_SYS_TYPE_SINGLE = "single"
// upstream: export const COORD_SYS_TYPE_SINGLE_AXIS_COMPATIBLE = 'singleAxis';
public let COORD_SYS_TYPE_SINGLE_AXIS_COMPATIBLE = "singleAxis"
// upstream: export const COMPONENT_TYPE_SINGLE_AXIS = 'singleAxis';
public let COMPONENT_TYPE_SINGLE_AXIS = "singleAxis"

// upstream: export type SingleAxisPosition = 'top' | 'bottom' | 'left' | 'right';
//   PORT-TODO: no string unions in Swift → a `String` alias (option is read from the dynamic bag).
public typealias SingleAxisPosition = String

// upstream:
// export type SingleAxisOption = AxisBaseOption & BoxLayoutOptionMixin & {
//     mainType?: 'singleAxis'
//     position?: SingleAxisPosition
//     orient?: LayoutOrient
// } & ComponentOnCalendarOptionMixin & ComponentOnMatrixOptionMixin;
//   PORT-TODO: option interfaces modeled as the dynamic option bag ([String: Any]); the extra fields
//   (mainType/position/orient plus the box-layout / calendar / matrix mixins) are keyed accesses on the bag.
public typealias SingleAxisOption = AxisBaseOption

// upstream:
// class SingleAxisModel extends ComponentModel<SingleAxisOption>
//     implements AxisBaseModel<SingleAxisOption> { ... }
// interface SingleAxisModel extends AxisModelCommonMixin<SingleAxisOption>, AxisModelExtendedInCreator {}
// mixin(SingleAxisModel, AxisModelCommonMixin.prototype);
//
// PORT-TODO: mirrors the CartesianAxisModel port (coord/cartesian/AxisModel.swift). Upstream `extends
//   ComponentModel implements AxisBaseModel<T>` where `AxisBaseModel` is a TS interface merging
//   ComponentModel + AxisModelCommonMixin + AxisModelExtendedInCreator + the `axis` slot. Per CONVENTIONS
//   §2 the Swift port models `AxisBaseModel` as a real `open class AxisBaseModel: ComponentModel,
//   AxisModelCommonMixin`, so `SingleAxisModel` subclasses it (inheriting ComponentModel + the
//   AxisModelCommonMixin conformance + the `axis` slot). `mixin(SingleAxisModel, AxisModelCommonMixin)`
//   is replaced by that base-class conformance. `AxisModelExtendedInCreator` (getCategories /
//   getOrdinalMeta / updateAxisBreaks) is NOT implemented here — like CartesianAxisModel it is provided
//   by the subclass `axisModelCreator` generates from this class (see integration notes / install).
public final class SingleAxisModel: AxisBaseModel {

    // static type = COMPONENT_TYPE_SINGLE_AXIS;
    // type = SingleAxisModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return COMPONENT_TYPE_SINGLE_AXIS }

    // static readonly layoutMode = 'box';
    public override class var layoutMode: Any? { return "box" }

    // axis: SingleAxis;
    //   -> the `axis` slot is provided by the `AxisBaseModel` base (typed `Any` until coord/single/SingleAxis
    //      lands; narrow via `as? SingleAxis` at use).

    // coordinateSystem: Single;
    //   PORT-TODO: upstream types this the concrete `Single` (a `CoordinateSystemMaster`), injected by
    //   singleCreator once the coordinate system is built. `Single` (coord/single/Single.swift) is a
    //   sibling this phase; typed here as `CoordinateSystemMaster?` (mirroring PolarModel), narrow via
    //   `as? Single` at use (see singleCreator.swift).
    public var coordinateSystem: CoordinateSystemMaster?

    // getCoordSysModel() { return this; }
    //   The single coordinate system and single axis are the same model, so the axis model IS its own
    //   coord-sys model. `AxisModelCommonMixin.getCoordSysModel()` returns `Any?`, so `self` is returned.
    public func getCoordSysModel() -> Any? {
        return self
    }

    // static defaultOption: SingleAxisOption = { ... }
    //   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
    //   (INT-vs-DOUBLE option-read trap).
    public override class var defaultOption: ModelOption? {
        return [

            "left": "5%",
            "top": "5%",
            "right": "5%",
            "bottom": "5%",

            "type": "value",

            "position": "bottom",

            "orient": "horizontal",

            "axisLine": [
                "show": true,
                "lineStyle": [
                    "width": 1.0,
                    "type": "solid"
                ] as [String: Any]
            ] as [String: Any],

            // Single coordinate system and single axis is the,
            // which is used as the parent tooltip model.
            // same model, so we set default tooltip show as true.
            "tooltip": [
                "show": true
            ] as [String: Any],

            "axisTick": [
                "show": true,
                "length": 6.0,
                "lineStyle": [
                    "width": 1.0
                ] as [String: Any]
            ] as [String: Any],

            "axisLabel": [
                "show": true,
                "interval": "auto"
            ] as [String: Any],

            "splitLine": [
                "show": true,
                "lineStyle": [
                    "type": "dashed",
                    "opacity": 0.2
                ] as [String: Any]
            ] as [String: Any],

            "jitter": 0.0,
            "jitterOverlap": true,
            "jitterMargin": 2.0,
        ] as [String: Any]
    }
}

// export default SingleAxisModel;  -> `public final class SingleAxisModel` above.
