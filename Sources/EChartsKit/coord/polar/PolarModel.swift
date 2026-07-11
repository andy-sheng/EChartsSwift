// Ported from echarts/src/coord/polar/PolarModel.ts — keep in sync with upstream
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

// import {
//     ComponentOption, CircleLayoutOptionMixin, ComponentOnCalendarOptionMixin,
//     ComponentOnMatrixOptionMixin
// } from '../../util/types';                                          -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift)
// import type Polar from './Polar';                                   -> Polar (coord/polar/Polar.swift — coord-sys master; sibling this phase.
//                                                                        Typed via `CoordinateSystemMaster?` below, mirroring GridModel/RadarModel.)
// import { AngleAxisModel, RadiusAxisModel } from './AxisModel';      -> AngleAxisModel / RadiusAxisModel (coord/polar/PolarAxisModel.swift)

// upstream:
// export interface PolarOption extends
//     ComponentOption, CircleLayoutOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin {
//     mainType?: 'polar';
// }
//   PORT-NOTE: `PolarOption` describes the dynamic option shape; modeled as the dynamic option bag
//   ([String: Any]) per CONVENTIONS §2 — no standalone Swift struct emitted.

// upstream: export const COORD_SYS_TYPE_POLAR = 'polar';
public let COORD_SYS_TYPE_POLAR = "polar"
// upstream: export const COMPONENT_TYPE_POLAR = COORD_SYS_TYPE_POLAR;
public let COMPONENT_TYPE_POLAR = COORD_SYS_TYPE_POLAR

// upstream:
// class PolarModel extends ComponentModel<PolarOption> { ... }
//   Component reference type (like GridModel) -> `final class : ComponentModel, CoordinateSystemHostModel`.
//   NOTE: upstream `PolarModel` does not explicitly `implements CoordinateSystemHostModel`, but its
//   `coordinateSystem: Polar` member matches that interface (Polar is a CoordinateSystemMaster); the
//   conformance is declared here so `coordinateSystem` satisfies the required contract (mirrors GridModel).
public final class PolarModel: ComponentModel, CoordinateSystemHostModel {

    // static type = COORD_SYS_TYPE_POLAR;
    // type = PolarModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return COORD_SYS_TYPE_POLAR }

    // static dependencies = ['radiusAxis', 'angleAxis'];
    public override class var dependencies: [String] { return ["radiusAxis", "angleAxis"] }

    // coordinateSystem: Polar;
    //   PORT-NOTE: upstream types this the concrete `Polar` (a `CoordinateSystemMaster`), injected and
    //   non-null once the coordinate system is built. `Polar` (coord/polar/Polar.swift) is a sibling this
    //   phase; typed here as the `CoordinateSystemMaster?` required by `CoordinateSystemHostModel`
    //   (narrow via `as? Polar` at use).
    public var coordinateSystem: CoordinateSystemMaster?

    // upstream (overloaded):
    // findAxisModel(axisType: 'angleAxis'): AngleAxisModel
    // findAxisModel(axisType: 'radiusAxis'): RadiusAxisModel
    // findAxisModel(axisType: 'angleAxis' | 'radiusAxis'): AngleAxisModel | RadiusAxisModel { ... }
    //   -> string-union param erased to String; union return erased to the shared base `PolarAxisModel?`.
    public func findAxisModel(_ axisType: String) -> PolarAxisModel? {
        // let foundAxisModel;
        var foundAxisModel: PolarAxisModel?
        // const ecModel = this.ecModel;
        let ecModel = self.ecModel

        // ecModel.eachComponent(axisType, function (this: PolarModel, axisModel) {
        //     if (axisModel.getCoordSysModel() === this) { foundAxisModel = axisModel; }
        // }, this);
        //   NOTE: upstream binds the callback's `this` to this PolarModel via the 3rd `context` arg; Swift
        //   closures capture, so `self` is compared directly (`=== this`).
        //   PORT-TODO: `getCoordSysModel()` is the override on `PolarAxisModel`. The axis models actually
        //   instantiated by `axisModelCreator` are the file-scope `AxisModel` (coord/axisModelCreator.swift)
        //   — a subclass of `AxisBaseModel`, NOT of `PolarAxisModel` — so the `as? PolarAxisModel` narrowing
        //   fails until the creator's dynamic-subclass wiring lands (Phase 6b registrar). See the
        //   protocol-witness/creator gap in axisModelCreator.swift; reconcile once it is resolved.
        ecModel?.eachComponent(axisType, { axisModel, _ in
            if let polarAxisModel = axisModel as? PolarAxisModel,
               let coordSysModel = polarAxisModel.getCoordSysModel(),
               (coordSysModel as AnyObject) === self {
                foundAxisModel = polarAxisModel
            }
        })
        // return foundAxisModel;
        return foundAxisModel
    }

    // static defaultOption: PolarOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 0,
            "center": ["50%", "50%"],
            "radius": "80%"
        ] as [String: Any]
    }
}

// export default PolarModel;  -> `public final class PolarModel` above.
