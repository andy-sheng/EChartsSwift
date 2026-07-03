// Ported from echarts/src/coord/radar/RadarModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                    -> ZRenderKit `util` (util.map / util.merge / util.clone / util.defaults / util.isString / util.isFunction / util.mixin)
// import axisDefault from '../axisDefault';                           -> axisDefault (coord/axisDefault.swift; caseless enum, `axisDefault.option["value"]`)
// import Model from '../../model/Model';                              -> Model (model/Model.swift)
// import {AxisModelCommonMixin} from '../axisModelCommonMixin';       -> AxisModelCommonMixin (coord/axisModelCommonMixin.swift, T2 protocol)
// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift)
// import {
//     ComponentOption, CircleLayoutOptionMixin, LabelOption, ColorString,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin
// } from '../../util/types';                                          -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import { AxisBaseOption, CategoryAxisBaseOption, ValueAxisBaseOption } from '../axisCommonTypes';
//                                                                     -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import { AxisBaseModel } from '../AxisBaseModel';                   -> AxisBaseModel (coord/AxisBaseModel.swift — open class : ComponentModel, AxisModelCommonMixin)
// import type Radar from './Radar';                                  -> Radar (coord/radar/Radar.swift — NOT yet ported; the coord-sys master. Typed via `CoordinateSystemMaster?` below.)
// import {CoordinateSystemHostModel} from '../../coord/CoordinateSystem'; -> CoordinateSystemHostModel (coord/CoordinateSystem.swift)
// import tokens from '../../visual/tokens';                           -> PORT-TODO: visual/tokens.ts not ported yet; the `tokens.color.*` values are inlined verbatim as resolved constants.
//                                                                        tokens.color.neutral20 = '#cfd2d7'; tokens.color.axisLabel = '#54555a' (= color.neutral70)
// import { getUID } from '../../util/component';                      -> component.getUID (util/componentUtil.swift); see the `model.uid` PORT-TODO below.

// upstream: const valueAxisDefault = axisDefault.value;
private let valueAxisDefault: [String: Any] = (axisDefault.option["value"] as? [String: Any]) ?? [:]

// upstream: export const COORD_SYS_TYPE_RADAR = 'radar';
public let COORD_SYS_TYPE_RADAR = "radar"
// upstream: export const COMPONENT_TYPE_RADAR = COORD_SYS_TYPE_RADAR;
public let COMPONENT_TYPE_RADAR = COORD_SYS_TYPE_RADAR
// upstream: export const SERIES_TYPE_RADAR = COORD_SYS_TYPE_RADAR;
public let SERIES_TYPE_RADAR = COORD_SYS_TYPE_RADAR

// upstream: export const RADAR_DEFAULT_SPLIT_NUMBER = 5;
public let RADAR_DEFAULT_SPLIT_NUMBER: Double = 5

// upstream: function defaultsShow(opt: object, show: boolean) { return zrUtil.defaults({show: show}, opt); }
private func defaultsShow(_ opt: [String: Any], _ show: Bool) -> [String: Any] {
    var target: [String: Any] = ["show": show]
    return util.defaults(&target, opt)
}

// upstream:
// export interface RadarIndicatorOption {
//     name?: string
//     /** @deprecated Use `name` instead. */
//     text?: string
//     min?: number
//     max?: number
//     color?: ColorString
//     axisType?: 'value' | 'log'
// }
//   PORT-TODO: option interface describes the dynamic per-indicator option shape; modeled as the
//   dynamic option bag ([String: Any]), keyed access via util.* / Model.get (CONVENTIONS §2).

// upstream:
// export interface RadarOption extends ComponentOption, CircleLayoutOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin {
//     mainType?: 'radar'
//     startAngle?: number
//     clockwise?: boolean
//     shape?: 'polygon' | 'circle'
//     axisLine?: AxisBaseOption['axisLine']
//     axisTick?: AxisBaseOption['axisTick']
//     axisLabel?: AxisBaseOption['axisLabel']
//     splitLine?: AxisBaseOption['splitLine']
//     splitArea?: AxisBaseOption['splitArea']
//     axisName?: { show?: boolean; formatter?: string | ((name?, indicatorOpt?) => string) } & LabelOption
//     axisNameGap?: number
//     triggerEvent?: boolean
//     scale?: boolean
//     splitNumber?: number
//     boundaryGap?: CategoryAxisBaseOption['boundaryGap'] | ValueAxisBaseOption['boundaryGap']
//     indicator?: RadarIndicatorOption[]
// }
//   PORT-TODO: `RadarOption` describes the dynamic option shape; modeled as the dynamic option bag
//   ([String: Any]) per CONVENTIONS §2 — no standalone Swift struct emitted.

// upstream: export type InnerIndicatorAxisOption = AxisBaseOption & { showName?: boolean };
//   -> dynamic option bag ([String: Any]).

// upstream: `type nameFormatter = string | ((name?: string, indicatorOpt?: InnerIndicatorAxisOption) => string)`.
//   The function branch of `axisName.formatter`, erased to a Swift closure type (CONVENTIONS §8).
public typealias RadarAxisNameFormatter = (_ name: String?, _ indicatorOpt: [String: Any]?) -> String

// upstream:
// class RadarModel extends ComponentModel<RadarOption> implements CoordinateSystemHostModel { ... }
//   Component reference type (like GridModel) -> `final class : ComponentModel, CoordinateSystemHostModel`.
public final class RadarModel: ComponentModel, CoordinateSystemHostModel {

    // static readonly type = COMPONENT_TYPE_RADAR;
    // readonly type = RadarModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return COMPONENT_TYPE_RADAR }

    // coordinateSystem: Radar;
    //   PORT-TODO: upstream types this the concrete `Radar` (a `CoordinateSystemMaster`), injected and
    //   non-null once the coordinate system is built. `Radar` (coord/radar/Radar.swift) is NOT yet ported;
    //   typed here as the `CoordinateSystemMaster?` required by `CoordinateSystemHostModel` (narrow via
    //   `as? Radar` at use, once Radar lands).
    public var coordinateSystem: CoordinateSystemMaster?

    // private _indicatorModels: AxisBaseModel<InnerIndicatorAxisOption>[];
    //   IUO: assigned in `optionUpdated` before any `getIndicatorModels` call. Type annotated to avoid
    //   the IUO-bound-to-`let` inference trap (CONVENTIONS).
    private var _indicatorModels: [AxisBaseModel]!

    // optionUpdated() { ... }
    //   PORT-TODO: upstream overrides `optionUpdated()` with NO params, but `ComponentModel.optionUpdated`
    //   is `(newCptOption, isInit)`. Swift overrides must match the signature, so the two params are
    //   accepted and ignored (as upstream does implicitly).
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        _ = (newCptOption, isInit)

        let boundaryGap = self.get("boundaryGap")
        let splitNumber = self.get("splitNumber")
        let clockwise = self.get("clockwise")
        let scale = self.get("scale")
        let axisLine = self.get("axisLine")
        let axisTick = self.get("axisTick")
        // let axisType = this.get('axisType');
        let axisLabel = self.get("axisLabel")
        let nameTextStyle = self.get("axisName")
        let showName = self.get(["axisName", "show"])
        let nameFormatter = self.get(["axisName", "formatter"])
        let nameGap = self.get("axisNameGap")
        let triggerEvent = self.get("triggerEvent")

        // upstream: const indicatorModels = zrUtil.map(this.get('indicator') || [], function (indicatorOpt) {...}, this)
        //   NOTE: upstream mutates each `indicatorOpt` (the very object in `this.option.indicator`) in place;
        //   the mutated array is written back to `self.option` after the map (JS mutates by reference).
        var indicator = (self.get("indicator") as? [Any]) ?? []   // this.get('indicator') || []
        let indicatorModels: [AxisBaseModel] = util.map(indicator) { (indicatorOptRaw: Any, i: Int) -> AxisBaseModel in
            var indicatorOpt = (indicatorOptRaw as? [String: Any]) ?? [:]

            // PENDING
            // if (indicatorOpt.max != null && indicatorOpt.max > 0 && !indicatorOpt.min) { indicatorOpt.min = 0; }
            if let maxV = radarNumOpt(indicatorOpt["max"]), maxV > 0, !isTruthy(indicatorOpt["min"]) {
                indicatorOpt["min"] = 0.0
            }
            // else if (indicatorOpt.min != null && indicatorOpt.min < 0 && !indicatorOpt.max) { indicatorOpt.max = 0; }
            else if let minV = radarNumOpt(indicatorOpt["min"]), minV < 0, !isTruthy(indicatorOpt["max"]) {
                indicatorOpt["max"] = 0.0
            }
            // Write the in-place mutation back into the option array (upstream mutates `indicatorOpt` by ref).
            indicator[i] = indicatorOpt

            // let iNameTextStyle = nameTextStyle;
            var iNameTextStyle = nameTextStyle
            // if (indicatorOpt.color != null) { iNameTextStyle = zrUtil.defaults({color: indicatorOpt.color}, nameTextStyle); }
            if let color = indicatorOpt["color"], !(color is NSNull) {
                var t: [String: Any] = ["color": color]
                iNameTextStyle = util.defaults(&t, (nameTextStyle as? [String: Any]) ?? [:])
            }

            // Use same configuration
            // const innerIndicatorOpt = zrUtil.merge(zrUtil.clone(indicatorOpt), { ... } as InnerIndicatorAxisOption, false);
            var mergeTarget: [String: Any] = util.clone(indicatorOpt)
            // The merge source object; per CONVENTIONS §6 an `undefined`-valued key is omitted (reading a
            //   missing key ≡ reading `undefined`). Keys with `false`/`0`/`""` values are preserved.
            var source: [String: Any] = [:]
            func put(_ key: String, _ value: Any?) {
                if let value = value, !(value is NSNull) {
                    source[key] = value
                }
            }
            put("boundaryGap", boundaryGap)
            put("splitNumber", splitNumber)
            put("clockwise", clockwise)
            put("scale", scale)
            put("axisLine", axisLine)
            put("axisTick", axisTick)
            // axisType: axisType,
            put("axisLabel", axisLabel)
            // Compatible with 2 and use text
            put("name", indicatorOpt["text"])          // name: indicatorOpt.text
            put("showName", showName)
            source["nameLocation"] = "end"
            put("nameGap", nameGap)
            // min: 0,
            put("nameTextStyle", iNameTextStyle)
            put("triggerEvent", triggerEvent)
            var innerIndicatorOpt = util.merge(&mergeTarget, source, false)

            // if (zrUtil.isString(nameFormatter)) { ... }
            if util.isString(nameFormatter) {
                let fmt = nameFormatter as! String
                // const indName = innerIndicatorOpt.name;
                let indName = innerIndicatorOpt["name"] as? String
                // innerIndicatorOpt.name = nameFormatter.replace('{value}', indName != null ? indName : '');
                let replacement = indName != nil ? indName! : ""
                // JS String.prototype.replace(searchString, replaceString) replaces only the FIRST occurrence.
                if let r = fmt.range(of: "{value}") {
                    var s = fmt
                    s.replaceSubrange(r, with: replacement)
                    innerIndicatorOpt["name"] = s
                }
                else {
                    innerIndicatorOpt["name"] = fmt
                }
            }
            // else if (zrUtil.isFunction(nameFormatter)) { ... }
            else if util.isFunction(nameFormatter) {
                // innerIndicatorOpt.name = nameFormatter(innerIndicatorOpt.name, innerIndicatorOpt);
                // PORT-TODO: the formatter closure's dynamic type is erased in the option bag; cast to the
                //   conventional `RadarAxisNameFormatter` signature. If the stored closure was created with a
                //   different signature this cast fails and the name is left unchanged.
                if let fn = nameFormatter as? RadarAxisNameFormatter {
                    innerIndicatorOpt["name"] = fn(innerIndicatorOpt["name"] as? String, innerIndicatorOpt)
                }
            }

            // const model = new Model(innerIndicatorOpt, null, this.ecModel) as AxisBaseModel<...>;
            // zrUtil.mixin(model, AxisModelCommonMixin.prototype);
            //   FIXME: construct an AxisBaseModel directly, rather than mixin.
            //   PORT-TODO: embracing that upstream FIXME — the Swift port has a real `AxisBaseModel`
            //   (an `open class : ComponentModel, AxisModelCommonMixin`), so it is constructed directly.
            //   Its `ComponentModel.init` stores `option = innerIndicatorOpt` WITHOUT default-merge (mirrors
            //   `new Model(...)`), and the `AxisModelCommonMixin` methods (needIncludeZero / getCoordSysModel)
            //   come from the conformance (replacing `zrUtil.mixin(model, AxisModelCommonMixin.prototype)`).
            let model = AxisBaseModel(innerIndicatorOpt, nil, self.ecModel)
            // For triggerEvent.
            // model.mainType = 'radar';
            model.mainType = "radar"
            // model.componentIndex = this.componentIndex;
            model.componentIndex = self.componentIndex
            // model.uid = getUID('ec_radar');
            //   PORT-TODO: `ComponentModel.uid` is a `let` assigned in its init (prefix "ec_cpt_model");
            //   it can not be re-assigned to `getUID('ec_radar')` here. The uid still uniquely identifies
            //   the model (different prefix only). Reconcile if the "ec_radar" prefix is load-bearing.
            _ = COMPONENT_TYPE_RADAR   // (silences unused-import style lints; keeps constant referenced)

            return model
        }

        // Persist the in-place mutations of the indicator option objects back onto the option tree
        //   (upstream mutates them by reference — see NOTE above the map).
        if var opt = self.option as? [String: Any] {
            opt["indicator"] = indicator
            self.option = opt
        }

        self._indicatorModels = indicatorModels
    }

    // getIndicatorModels() { return this._indicatorModels; }
    public func getIndicatorModels() -> [AxisBaseModel] {
        return self._indicatorModels
    }

    // static defaultOption: RadarOption = { ... }
    public override class var defaultOption: ModelOption? {
        // upstream: axisLine: zrUtil.merge({ lineStyle: { color: tokens.color.neutral20 } }, valueAxisDefault.axisLine)
        var axisLineTarget: [String: Any] = [
            "lineStyle": [
                "color": "#cfd2d7"   // tokens.color.neutral20
            ] as [String: Any]
        ]
        let axisLine = util.merge(&axisLineTarget, (valueAxisDefault["axisLine"] as? [String: Any]) ?? [:])

        return [

            // zlevel: 0,

            "z": 0,

            "center": ["50%", "50%"],

            "radius": "50%",

            "startAngle": 90,

            "clockwise": false,

            "axisName": [
                "show": true,
                "color": "#54555a"   // tokens.color.axisLabel
                // formatter: null
                // textStyle: {}
            ] as [String: Any],

            "boundaryGap": [0, 0],

            "splitNumber": RADAR_DEFAULT_SPLIT_NUMBER,

            "axisNameGap": 15,

            "scale": false,

            // Polygon or circle
            "shape": "polygon",

            "axisLine": axisLine,
            "axisLabel": defaultsShow((valueAxisDefault["axisLabel"] as? [String: Any]) ?? [:], false),
            "axisTick": defaultsShow((valueAxisDefault["axisTick"] as? [String: Any]) ?? [:], false),
            // axisType: 'value',
            "splitLine": defaultsShow((valueAxisDefault["splitLine"] as? [String: Any]) ?? [:], true),
            "splitArea": defaultsShow((valueAxisDefault["splitArea"] as? [String: Any]) ?? [:], true),

            // {text, min, max}
            "indicator": []
        ] as [String: Any]
    }
}

// JS truthiness for a dynamic option value (used where upstream relies on `!x` / `if (x)`).
// PORT-TODO: falsy = nil / NSNull / false / 0 / "" / NaN (CONVENTIONS §6). Mirrors Grid.swift's helper.
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

// Coerce a dynamic option number tolerating Int boxing (e.g. `max: 100` as an Int literal); a bare
// `as? Double` returns nil on an Int and silently drops the value.
private func radarNumOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// export default RadarModel;  -> `public final class RadarModel` above.
