// Ported from echarts/src/coord/polar/AxisModel.ts — keep in sync with upstream
//   NOTE: named PolarAxisModel.swift (not AxisModel.swift) to avoid a SwiftPM object-name collision
//   with coord/cartesian/AxisModel.swift (duplicate basenames collide in one target).
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

// import * as zrUtil from 'zrender/src/core/util';                    -> util.* (ZRenderKit)
// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift)
// import { AxisModelExtendedInCreator } from '../axisModelCreator';   -> AxisModelExtendedInCreator (coord/axisModelCreator.swift)
// import {AxisModelCommonMixin} from '../axisModelCommonMixin';       -> AxisModelCommonMixin (coord/axisModelCommonMixin.swift, protocol)
// import { AxisBaseOption } from '../axisCommonTypes';                -> AxisBaseOption (dynamic option bag, see axisModelCreator.swift; note)
// import AngleAxis from './AngleAxis';                                -> AngleAxis (coord/polar/AngleAxis.swift; sibling this phase — note: `axis` slot typed `Any` via AxisBaseModel)
// import RadiusAxis from './RadiusAxis';                              -> RadiusAxis (coord/polar/RadiusAxis.swift; sibling this phase — same)
// import { AxisBaseModel } from '../AxisBaseModel';                   -> AxisBaseModel (coord/AxisBaseModel.swift)
// import { SINGLE_REFERRING } from '../../util/model';                -> model.SINGLE_REFERRING (util/modelUtil.swift)

// upstream:
// export type AngleAxisOption = AxisBaseOption & {
//     mainType?: 'angleAxis';
//     polarIndex?: number;   // Index of host polar component
//     polarId?: string;      // Id of host polar component
//     startAngle?: number;
//     endAngle?: number;
//     clockwise?: boolean;
//     axisLabel?: AxisBaseOption['axisLabel']
// };
//   option interfaces modeled as the dynamic option bag ([String: Any]); the extra fields
//   (polarIndex/polarId/startAngle/endAngle/clockwise/axisLabel) are keyed accesses on the bag.
public typealias AngleAxisOption = AxisBaseOption

// upstream:
// export type RadiusAxisOption = AxisBaseOption & {
//     mainType?: 'radiusAxis';
//     polarIndex?: number;
//     polarId?: string;
// };
public typealias RadiusAxisOption = AxisBaseOption

// upstream: type PolarAxisOption = AngleAxisOption | RadiusAxisOption;
//   -> union erased; both alias the shared dynamic option bag.
public typealias PolarAxisOption = AxisBaseOption

// upstream:
// class PolarAxisModel<T extends PolarAxisOption = PolarAxisOption> extends ComponentModel<T>
//     implements AxisBaseModel<T> { ... }
// interface PolarAxisModel<T> extends AxisModelCommonMixin<T>, AxisModelExtendedInCreator {}
// zrUtil.mixin(PolarAxisModel, AxisModelCommonMixin);
//
// mirrors the CartesianAxisModel port (coord/cartesian/AxisModel.swift). Upstream `extends
//   ComponentModel implements AxisBaseModel<T>` where `AxisBaseModel` is a TS interface merging
//   ComponentModel + AxisModelCommonMixin + AxisModelExtendedInCreator + the `axis` slot. Per CONVENTIONS
//   §2 the Swift port models `AxisBaseModel` as a real `open class AxisBaseModel: ComponentModel,
//   AxisModelCommonMixin`, so `PolarAxisModel` subclasses it (inheriting ComponentModel + the
//   AxisModelCommonMixin conformance + the `axis` slot). `zrUtil.mixin(PolarAxisModel, AxisModelCommonMixin)`
//   is replaced by that base-class conformance. Not `final` — upstream subclasses it into
//   AngleAxisModel / RadiusAxisModel below.
open class PolarAxisModel: AxisBaseModel, AxisModelExtendedInCreator {

    // static type = 'polarAxis';
    public override class var type: ComponentFullType { return "polarAxis" }

    // axis: AngleAxis | RadiusAxis;
    //   -> the `axis` slot is provided by the `AxisBaseModel` base (typed `Any` until coord/polar/AngleAxis
    //      + RadiusAxis land; narrow via `as? AngleAxis` / `as? RadiusAxis` at use).

    // getCoordSysModel(): ComponentModel {
    //     return this.getReferringComponents('polar', SINGLE_REFERRING).models[0];
    // }
    //   upstream returns the concrete host `ComponentModel` (a PolarModel). The
    //   `AxisModelCommonMixin.getCoordSysModel()` protocol requirement returns `Any?`, so the return is
    //   left as the raw `models[0]` (a `ComponentModel`), narrowed to `PolarModel` at the call site
    //   (mirrors CartesianAxisModel.getCoordSysModel → GridModel).
    public func getCoordSysModel() -> Any? {
        let models = self.getReferringComponents("polar", model.SINGLE_REFERRING).models
        return models.first
    }

    // ------------------------------------------------------------------------
    // Axis-model machinery upstream generated by `axisModelCreator(registers, 'angle'|'radius', ...)`
    // as a per-axisType subclass of AngleAxisModel/RadiusAxisModel (defaultOption merge over
    // `axisDefault[axisType]` + the polar extra option; ordinalMeta build for category axes;
    // AxisModelExtendedInCreator conformance). Swift can not synthesize that runtime subclass, so the
    // faithful reduction lives on this base — driven by the overridable `polarAxisExtraOption` the
    // concrete AngleAxisModel/RadiusAxisModel supply (angle/radius extra defaults from
    // component/polar/install.ts). Mirrors coord/axisModelCreator.swift `AxisModel` + the EChartsXAxisModel
    // stand-in pattern that drives the cartesian path.
    // ------------------------------------------------------------------------

    // The polar extra default option for this axis kind (startAngle/clockwise/… for angle, splitNumber
    //   for radius). Overridden by AngleAxisModel/RadiusAxisModel; empty on the base.
    open class var polarAxisExtraOption: AxisBaseOption { return [:] }

    // private __ordinalMeta: OrdinalMeta;
    private var __ordinalMeta: OrdinalMeta!

    // Merge `axisDefault[axisType]` + the polar extra option UNDER the user option (user wins). This is
    //   the reduction of the generated subclass's `static defaultOption` + AxisModel.mergeDefaultAndTheme.
    open override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeDefaultAndTheme(option, ecModel)
        guard var target = self.option as? [String: Any] else { return }
        // axisType is resolved from the (already user-merged) option (data ⇒ category, else value).
        let axisType = getAxisType(target)
        if let ad = axisDefault.option[axisType] as? [String: Any] {
            var def: [String: Any] = [:]
            util.merge(&def, ad, true)
            util.merge(&def, Swift.type(of: self).polarAxisExtraOption, true)
            // overwrite=false: user option wins over the defaults, nested dicts deep-merge.
            util.merge(&target, def, false)
        }
        // Normalize `type` so downstream (determineAxisType / scale creation) resolves consistently.
        target["type"] = getAxisType(target)
        self.option = target
    }

    // Build the ordinal meta once the option is finalized (category axes only). Mirrors AxisModel.optionUpdated.
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(newCptOption, isInit)
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            self.__ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }

    // AxisModelExtendedInCreator + AxisBaseModel.getCategories override.
    open override func getCategories(_ rawData: Bool? = nil) -> [OrdinalRawValue]? {
        let opt = self.option as? [String: Any]
        if (opt?["type"] as? String) == "category" {
            if rawData == true {
                return opt?["data"] as? [OrdinalRawValue]
            }
            return self.__ordinalMeta?.categories
        }
        return nil
    }

    public func getOrdinalMeta() -> OrdinalMeta {
        return self.__ordinalMeta ?? OrdinalMeta.createByAxisModel(self)
    }

    // upstream (generated AxisModel):
    //   updateAxisBreaks(payload) {
    //       const axisBreakHelper = getAxisBreakHelper();
    //       return axisBreakHelper ? axisBreakHelper.updateModelAxisBreak(this, payload) : {breaks: []};
    //   }
    //   Mirrors SingleAxisModel/axisModelCreator; getAxisBreakHelper() returns nil until the axis-break
    //   feature installer lands, so this stays inert until then but now dispatches faithfully once wired.
    public func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        let axisBreakHelper = getAxisBreakHelper()
        return axisBreakHelper != nil
            ? axisBreakHelper!.updateModelAxisBreak(self, payload)
            : AxisBreakUpdateResult(breaks: [])
    }
}

// upstream:
// export class AngleAxisModel extends PolarAxisModel<AngleAxisOption> {
//     static type = 'angleAxis';
//     type = AngleAxisModel.type;
//     axis: AngleAxis;
// }
public final class AngleAxisModel: PolarAxisModel {
    // static type = 'angleAxis'; type = AngleAxisModel.type;
    public override class var type: ComponentFullType { return "angleAxis" }
    // axis: AngleAxis;  -> inherited `axis` slot (AxisBaseModel), narrowed via `as? AngleAxis` at use.
    // upstream: axisModelCreator(registers, 'angle', AngleAxisModel, angleAxisExtraOption).
    public override class var polarAxisExtraOption: AxisBaseOption { return angleAxisExtraOption }
}

// upstream:
// export class RadiusAxisModel extends PolarAxisModel<RadiusAxisOption> {
//     static type = 'radiusAxis';
//     type = RadiusAxisModel.type;
//     axis: RadiusAxis;
// }
public final class RadiusAxisModel: PolarAxisModel {
    // static type = 'radiusAxis'; type = RadiusAxisModel.type;
    public override class var type: ComponentFullType { return "radiusAxis" }
    // axis: RadiusAxis;  -> inherited `axis` slot (AxisBaseModel), narrowed via `as? RadiusAxis` at use.
    // upstream: axisModelCreator(registers, 'radius', RadiusAxisModel, radiusAxisExtraOption).
    public override class var polarAxisExtraOption: AxisBaseOption { return radiusAxisExtraOption }
}

// ============================================================================
// upstream location: echarts/src/component/polar/install.ts (the angle/radius axis extra defaults + the
//   axisModelCreator registration). Hoisted here (per the port task) so the angle/radius component-model
//   defaults live alongside their models; keep in sync with `component/polar/install.ts`.

// upstream (install.ts):
// const angleAxisExtraOption: AngleAxisOption = {
//     startAngle: 90,
//     clockwise: true,
//     splitNumber: 12,
//     // A round axis is not suitable for `containShape` in most cases.
//     containShape: false,
//     axisLabel: { rotate: 0 }
// };
//   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
//   (INT-vs-DOUBLE option-read trap).
public let angleAxisExtraOption: AngleAxisOption = [
    "startAngle": 90.0,
    "clockwise": true,
    "splitNumber": 12.0,
    // A round axis is not suitable for `containShape` in most cases.
    "containShape": false,
    "axisLabel": ["rotate": 0.0] as [String: Any]
]

// upstream (install.ts):
// const radiusAxisExtraOption: RadiusAxisOption = { splitNumber: 5 };
public let radiusAxisExtraOption: RadiusAxisOption = [
    "splitNumber": 5.0
]

// upstream (install.ts): the model registration for angleAxis and radiusAxis:
//   axisModelCreator(registers, 'angle', AngleAxisModel, angleAxisExtraOption);
//   axisModelCreator(registers, 'radius', RadiusAxisModel, radiusAxisExtraOption);
//
// the real registration belongs in the ported component/polar/install.swift (not this phase).
//   This helper mirrors that call pair so the angle/radius component models get the polar extra defaults
//   merged over `axisDefault[axisType]` (see coord/axisModelCreator.swift). Call it from the polar
//   install once the extension registrar wiring lands (Phase 6b).
//   NOTE: `axisModelCreator` currently ignores `BaseAxisModelClass` (it cannot subclass a runtime metatype
//   — see axisModelCreator.swift note), so the generated axis models are the file-scope `AxisModel`
//   rather than AngleAxisModel/RadiusAxisModel; `AngleAxisModel.self` / `RadiusAxisModel.self` are passed
//   for API fidelity and to reconcile once that wiring lands.
public func installPolarAxisModels(_ registers: EChartsExtensionInstallRegisters) {
    // Model and view for angleAxis and radiusAxis
    axisModelCreator(registers, "angle", AngleAxisModel.self, angleAxisExtraOption)
    axisModelCreator(registers, "radius", RadiusAxisModel.self, radiusAxisExtraOption)
}
// ============================================================================
