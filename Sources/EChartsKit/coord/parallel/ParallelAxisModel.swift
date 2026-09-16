// Ported from echarts/src/coord/parallel/AxisModel.ts — keep in sync with upstream
//   NOTE: named ParallelAxisModel.swift (not AxisModel.swift) to avoid a SwiftPM object-name collision
//   with coord/cartesian/AxisModel.swift, coord/polar/PolarAxisModel and coord/single/SingleAxisModel
//   (duplicate basenames collide in one target).
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

// import * as zrUtil from 'zrender/src/core/util';                    -> util.* (ZRenderKit; `util.clone`)
// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift; via AxisBaseModel base)
// import makeStyleMapper from '../../model/mixin/makeStyleMapper';    -> makeStyleMapper (model/mixin/makeStyleMapper.swift, top-level func)
// import { AxisModelExtendedInCreator } from '../axisModelCreator';   -> AxisModelExtendedInCreator (coord/axisModelCreator.swift)
// import * as numberUtil from '../../util/number';                    -> number.* (util/number.swift; `number.asc`)
// import {AxisModelCommonMixin} from '../axisModelCommonMixin';       -> AxisModelCommonMixin (coord/axisModelCommonMixin.swift; via AxisBaseModel base)
// import ParallelAxis from './ParallelAxis';                          -> ParallelAxis (coord/parallel/ParallelAxis.swift; sibling)
// import { ZRColor, ParsedValue } from '../../util/types';            -> ZRColor / ParsedValue (util/types.swift)
// import { AxisBaseOption } from '../axisCommonTypes';                -> AxisBaseOption (dynamic option bag; coord/axisModelCreator.swift, [String: Any])
// import Parallel from './Parallel';                                  -> Parallel (coord/parallel/Parallel.swift; sibling)
// import { PathStyleProps } from 'zrender/src/graphic/Path';          -> PathStyleProps (ZRenderKit; style modeled as dynamic bag, see getAreaSelectStyle)

// upstream: // 'normal' means there is no "active intervals" existing.
// export type ParallelActiveState = 'normal' | 'active' | 'inactive';
//   no string unions in Swift → a `String` alias. The brush/active-interval SELECTION paths
//   that produce these states (parallelAxisAction / brushing) are DEFERRED (per the port task); only the
//   pure state-classification logic (`getActiveState`) is ported below.
public typealias ParallelActiveState = String

// upstream: export type ParallelAxisInterval = number[];
public typealias ParallelAxisInterval = [Double]

// upstream:
// type ParallelAreaSelectStyleKey = 'fill' | 'lineWidth' | 'stroke' | 'opacity';
// export type ParallelAreaSelectStyleProps = Pick<PathStyleProps, ParallelAreaSelectStyleKey> & {
//     width: number;   // Selected area width.
// };
//   `PathStyleProps` is a Swift struct (fixed fields) and cannot be produced from arbitrary
//   string keys mechanically (same reduction as makeStyleMapper). Modeled as the dynamic style bag
//   ([String: Any]); narrow at the (deferred) brush-render call sites.
public typealias ParallelAreaSelectStyleProps = [String: Any]

// upstream:
// export type ParallelAxisOption = AxisBaseOption & {
//     dim?: number | number[];       // 0, 1, 2, ...
//     parallelIndex?: number;
//     areaSelectStyle?: { width?, borderWidth?, borderColor?, color?, opacity? };
//     realtime?: boolean;            // Whether realtime update view when select.
// };
//   option interfaces modeled as the dynamic option bag ([String: Any]); the extra fields
//   (dim / parallelIndex / areaSelectStyle / realtime) are keyed accesses on the bag.
public typealias ParallelAxisOption = AxisBaseOption

// upstream:
// class ParallelAxisModel extends ComponentModel<ParallelAxisOption> {
//     static type: 'baseParallelAxis';
//     readonly type = ParallelAxisModel.type;
//     axis: ParallelAxis;
//     coordinateSystem: Parallel;               // Inject
//     ...
// }
// interface ParallelAxisModel extends AxisModelCommonMixin<ParallelAxisOption>, AxisModelExtendedInCreator {}
// zrUtil.mixin(ParallelAxisModel, AxisModelCommonMixin);
//
// mirrors the PolarAxisModel / CartesianAxisModel port. Upstream `extends ComponentModel`
//   declaration-merged with `AxisModelCommonMixin` + `AxisModelExtendedInCreator`. Per CONVENTIONS §2 the
//   Swift port subclasses `AxisBaseModel` (an `open class : ComponentModel, AxisModelCommonMixin`, which
//   supplies the `axis` slot + `needIncludeZero()`/`getCoordSysModel()` protocol extension), so
//   `zrUtil.mixin(ParallelAxisModel, AxisModelCommonMixin)` is replaced by that base-class conformance.
//
//   The AxisModelExtendedInCreator machinery (getCategories/getOrdinalMeta/updateAxisBreaks) and the
//   `axisDefault[axisType]` + extra-option merge are HOISTED onto this base (mirroring PolarAxisModel):
//   upstream `axisModelCreator(registers, 'parallel', ParallelAxisModel, defaultAxisOption)` generates a
//   per-axisType subclass of ParallelAxisModel; Swift can not synthesize that runtime subclass, so the
//   faithful reduction lives here, driven by `parallelAxisExtraOption`. `final` — upstream never
//   subclasses ParallelAxisModel by hand (only the generated creator subclasses, reduced away here).
public final class ParallelAxisModel: AxisBaseModel, AxisModelExtendedInCreator {

    // upstream: static type: 'baseParallelAxis'; readonly type = ParallelAxisModel.type;
    //   note / DEVIATION (direct-registration shortcut): upstream registers this base as
    //   'baseParallelAxis' and `axisModelCreator(registers, 'parallel', ParallelAxisModel, …)` synthesizes
    //   the per-axisType subclasses under mainType 'parallelAxis' (type 'parallelAxis.value', …). This port
    //   has no runtime axisModelCreator (it ignores BaseAxisModelClass), so — exactly as SingleAxisModel
    //   ('singleAxis') and the polar axis models do — ParallelAxisModel is registered DIRECTLY under
    //   mainType 'parallelAxis'. The mainType parsed from this `type` therefore matches what the coord
    //   (`getComponent('parallelAxis', …) as! ParallelAxisModel`) and referHelper expect; the upstream
    //   sub-type ('value'/'category'/…) is collapsed onto this one concrete class (whose per-axisType
    //   defaults are hoisted here via `parallelAxisExtraOption`).
    public override class var type: ComponentFullType { return "parallelAxis" }

    // upstream: axis: ParallelAxis;
    //   -> the `axis` slot is provided by the `AxisBaseModel` base (typed `Any`); narrow via
    //      `as? ParallelAxis` at use.

    // upstream: coordinateSystem: Parallel;  (Inject — injected by Parallel's constructor).
    //   `Parallel` (coord/parallel/Parallel.swift) is the parallel coordinate-system master;
    //   typed to that master (mirrors SingleAxisModel.coordinateSystem: Single).
    public var coordinateSystem: Parallel!

    /**
     * @readOnly
     */
    // upstream: activeIntervals: ParallelAxisInterval[] = [];
    public var activeIntervals: [ParallelAxisInterval] = []

    // upstream:
    // getAreaSelectStyle(): ParallelAreaSelectStyleProps {
    //     return makeStyleMapper([
    //         ['fill', 'color'], ['lineWidth', 'borderWidth'], ['stroke', 'borderColor'],
    //         ['width', 'width'], ['opacity', 'opacity']
    //     ])(this.getModel('areaSelectStyle')) as ParallelAreaSelectStyleProps;
    // }
    //   makeStyleMapper returns a `(Model, [String]?, [String]?) -> [String: Any]` closure (Swift closures
    //   cannot carry defaulted params → pass `nil` for excludes/includes).
    public func getAreaSelectStyle() -> ParallelAreaSelectStyleProps {
        return makeStyleMapper([
            ["fill", "color"],
            ["lineWidth", "borderWidth"],
            ["stroke", "borderColor"],
            ["width", "width"],
            ["opacity", "opacity"]
            // Option decal is in `DecalObject` but style.decal is in `PatternObject`.
            // So do not transfer decal directly.
        ])(self.getModel("areaSelectStyle"), nil, nil)
    }

    /**
     * The code of this feature is put on AxisModel but not ParallelAxis,
     * because axisModel can be alive after echarts updating but instance of
     * ParallelAxis having been disposed. this._activeInterval should be kept
     * when action dispatched (i.e. legend click).
     *
     * @param intervals `interval.length === 0` means set all active.
     */
    // upstream:
    // setActiveIntervals(intervals: ParallelAxisInterval[]): void {
    //     const activeIntervals = this.activeIntervals = zrUtil.clone(intervals);
    //     if (activeIntervals) {
    //         for (let i = activeIntervals.length - 1; i >= 0; i--) {
    //             numberUtil.asc(activeIntervals[i]);
    //         }
    //     }
    // }
    //   the CALLER of this (parallelAxisAction) is ported (component/axis/parallelAxisAction.swift
    //   → installParallelActions calls setActiveIntervals). `number.asc` returns a sorted copy (Swift Array is a value type), so the
    //   in-place sort is reproduced by writing the sorted element back.
    public func setActiveIntervals(_ intervals: [ParallelAxisInterval]) {
        var activeIntervals = util.clone(intervals)

        // Normalize
        // upstream `if (activeIntervals)` is always truthy for a non-nil array.
        var i = activeIntervals.count - 1
        while i >= 0 {
            activeIntervals[i] = number.asc(activeIntervals[i])
            i -= 1
        }

        self.activeIntervals = activeIntervals
    }

    /**
     * @param value When only attempting detect whether 'no activeIntervals set',
     *        `value` is not needed to be input.
     */
    // upstream:
    // getActiveState(value?: ParsedValue): ParallelActiveState {
    //     const activeIntervals = this.activeIntervals;
    //     if (!activeIntervals.length) { return 'normal'; }
    //     if (value == null || isNaN(+value)) { return 'inactive'; }
    //     if (activeIntervals.length === 1) {
    //         const interval = activeIntervals[0];
    //         if (interval[0] <= value && value <= interval[1]) { return 'active'; }
    //     }
    //     else {
    //         for (let i = 0, len = activeIntervals.length; i < len; i++) {
    //             if (activeIntervals[i][0] <= value && value <= activeIntervals[i][1]) { return 'active'; }
    //         }
    //     }
    //     return 'inactive';
    // }
    //   active-interval SELECTION (populating `activeIntervals`) is now ported via
    //   parallelAxisAction; this pure classifier reads them. `+value` (JS numeric coercion) → `numOpt(value)`; nil/non-numeric ⇒ NaN path.
    public func getActiveState(_ value: ParsedValue? = nil) -> ParallelActiveState {
        let activeIntervals = self.activeIntervals

        if activeIntervals.isEmpty {
            return "normal"
        }

        // upstream: value == null || isNaN(+value)
        guard let v = numOpt(value), !v.isNaN else {
            return "inactive"
        }

        // Simple optimization
        if activeIntervals.count == 1 {
            let interval = activeIntervals[0]
            if interval[0] <= v && v <= interval[1] {
                return "active"
            }
        }
        else {
            for i in 0..<activeIntervals.count {
                if activeIntervals[i][0] <= v && v <= activeIntervals[i][1] {
                    return "active"
                }
            }
        }

        return "inactive"
    }

    // ------------------------------------------------------------------------
    // Axis-model machinery upstream generated by `axisModelCreator(registers, 'parallel', ParallelAxisModel,
    // defaultAxisOption)` as a per-axisType subclass (defaultOption = merge(axisDefault[axisType],
    // parallelAxisExtraOption); ordinalMeta build for category axes; AxisModelExtendedInCreator
    // conformance). Swift can not synthesize that runtime subclass, so the faithful reduction lives on this
    // class — mirrors coord/polar/PolarAxisModel.
    // ------------------------------------------------------------------------

    // private __ordinalMeta: OrdinalMeta;
    private var __ordinalMeta: OrdinalMeta!

    // Merge `axisDefault[axisType]` + `parallelAxisExtraOption` UNDER the user option (user wins). This is
    //   the reduction of the generated subclass's `static defaultOption` + AxisModel.mergeDefaultAndTheme.
    public override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeDefaultAndTheme(option, ecModel)
        guard var target = self.option as? [String: Any] else { return }
        // axisType is resolved from the (already user-merged) option (data ⇒ category, else value).
        let axisType = getAxisType(target)
        if let ad = axisDefault.option[axisType] as? [String: Any] {
            var def: [String: Any] = [:]
            util.merge(&def, ad, true)
            util.merge(&def, parallelAxisExtraOption, true)
            // overwrite=false: user option wins over the defaults, nested dicts deep-merge.
            util.merge(&target, def, false)
        }
        // Normalize `type` so downstream (determineAxisType / scale creation) resolves consistently.
        target["type"] = getAxisType(target)
        self.option = target
    }

    // Build the ordinal meta once the option is finalized (category axes only). Mirrors AxisModel.optionUpdated.
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(newCptOption, isInit)
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            self.__ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }

    // AxisModelExtendedInCreator + AxisBaseModel.getCategories override.
    public override func getCategories(_ rawData: Bool? = nil) -> [OrdinalRawValue]? {
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

    // upstream (generated AxisModel in axisModelCreator):
    //   updateAxisBreaks(payload) {
    //     const axisBreakHelper = getAxisBreakHelper();
    //     return axisBreakHelper ? axisBreakHelper.updateModelAxisBreak(this, payload) : {breaks: []};
    //   }
    //   mirrors SingleAxisModel.updateAxisBreaks. `getAxisBreakHelper()` is a nil stub in this
    //   port (the optional axis-break helper module is not installed), so the fallback `{breaks: []}` is
    //   taken today; wiring the structure faithfully makes this auto-correct once that helper lands.
    public func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        let axisBreakHelper = getAxisBreakHelper()
        return axisBreakHelper != nil
            ? axisBreakHelper!.updateModelAxisBreak(self, payload)
            : AxisBreakUpdateResult(breaks: [])
    }
}

// upstream: JS numeric coercion (`+value`) + Int-vs-Double option-read guard (CONVENTIONS trap 1):
//   a bare `as? Double` returns nil on an `Int`/`NSNumber` and silently drops it. Coerce Int|Double|
//   NSNumber|String → Double; anything else (nil/bool-as-object/non-numeric string) → nil (⇒ 'inactive').
private func numOpt(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

// ============================================================================
// upstream location: echarts/src/component/parallel/install.ts (the parallel-axis extra defaults + the
//   axisModelCreator registration). Hoisted here (per the port task) so the parallel-axis component-model
//   defaults live alongside the model; keep in sync with `component/parallel/install.ts`.

// upstream (install.ts):
// const defaultAxisOption: ParallelAxisOption = {
//     type: 'value',
//     areaSelectStyle: {
//         width: 20, borderWidth: 1,
//         borderColor: 'rgba(160,197,232)', color: 'rgba(160,197,232)', opacity: 0.3
//     },
//     realtime: true,
//     z: 10
// };
//   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
//   (INT-vs-DOUBLE option-read trap).
public let parallelAxisExtraOption: ParallelAxisOption = [
    "type": "value",
    "areaSelectStyle": [
        // Selected area width.
        "width": 20.0,
        "borderWidth": 1.0,
        "borderColor": "rgba(160,197,232)",
        "color": "rgba(160,197,232)",
        "opacity": 0.3
    ] as [String: Any],
    // Whether realtime update view when select.
    "realtime": true,
    "z": 10.0
]

// upstream (install.ts):
//   registers.registerComponentModel(ParallelAxisModel);
//   axisModelCreator<ParallelAxisOption, typeof ParallelAxisModel>(
//       registers, 'parallel', ParallelAxisModel, defaultAxisOption
//   );
//
// the live registration is wired directly in ECharts.swift (registerClass(ParallelAxisModel) +
//   axisModelCreator 'parallel'); this helper mirrors that call pair so the parallelAxis component models get the parallel extra defaults
//   merged over `axisDefault[axisType]` (see coord/axisModelCreator.swift). Call it from the parallel
//   install once the extension registrar wiring lands.
//   NOTE: `axisModelCreator` currently ignores `BaseAxisModelClass` (it cannot subclass a runtime metatype
//   — see axisModelCreator.swift note), so the generated axis models are the file-scope `AxisModel`
//   rather than a ParallelAxisModel subclass; `ParallelAxisModel.self` is passed for API fidelity and to
//   reconcile once that wiring lands (the areaSelect/activeIntervals machinery then rides on the subclass).
//   Not done by this helper (wired elsewhere in ECharts.swift): `registerComponentView(ParallelAxisView)`
//   (registered as `parallelAxis`) and `installParallelActions` (the brush/axis-drag interaction) — both ported.
public func installParallelAxisModel(_ registers: EChartsExtensionInstallRegisters) {
    registers.registerComponentModel(ParallelAxisModel.type) { option, parentModel, ecModel in
        return ParallelAxisModel(option, parentModel, ecModel)
    }
    axisModelCreator(registers, "parallel", ParallelAxisModel.self, parallelAxisExtraOption)
}
// ============================================================================

// export default ParallelAxisModel;  -> `public final class ParallelAxisModel` above.
