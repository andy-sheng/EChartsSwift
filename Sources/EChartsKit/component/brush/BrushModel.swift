// Ported from echarts/src/component/brush/BrushModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';           -> ZRenderKit `util` (util.map / util.merge).
// import * as visualSolution from '../../visual/visualSolution'; -> `visualSolution` (visual/visualSolution.swift)
// import Model from '../../model/Model';                     -> Model (model/Model.swift)
// import ComponentModel from '../../model/Component';        -> ComponentModel (model/Component.swift)
// import BrushTargetManager from '../helper/BrushTargetManager';
//   -> BrushTargetManager (component/helper/BrushTargetManager.swift) — the grid + geo coord-system
//      targets, the coordRange<->pixel converts, and `controlSeries`. Injected below.
// import {
//     BrushCoverCreatorConfig, BrushMode, BrushCoverConfig, BrushDimensionMinMax,
//     BrushAreaRange, BrushTypeUncertain, BrushType
// } from '../helper/BrushController';
//   -> BrushController (component/helper/BrushController.swift) declares all of these:
//      `BrushType`/`BrushMode`/`BrushTypeUncertain` collapse to `String`(?) per CONVENTIONS §2;
//      `BrushDimensionMinMax` = [Double]; `BrushAreaRange` = Any (the TS union); `BrushCoverConfig` /
//      `BrushCoverCreatorConfig` are classes there. This model still carries its own option/area state
//      as the `[String: Any]` bag (that IS the upstream shape — `areas` are plain option objects).
// import { ModelFinderObject } from '../../util/model';      -> ModelFinderObject (util/modelUtil.swift, = [String: Any])
// import tokens from '../../visual/tokens';                  -> `tokens` (visual/tokens.swift)

// The TS interfaces below are documented as comments; the dynamic option/area shapes are the
// `[String: Any]` bag (CONVENTIONS §2).
//
// interface BrushAreaParam extends ModelFinderObject {
//     brushType; id?; range?; panelId?; coordRange?; coordRanges?; __rangeOffset?;
// }
//   -> the input area bag created by dispatchAction or BrushController. `brushType` is required.
public typealias BrushAreaParam = [String: Any]
//
// interface BrushAreaParamInternal extends BrushAreaParam {
//     brushMode; brushStyle; transformable; removeOnClick; z; __rangeOffset?;
// }
//   -> the internal area bag produced by `generateBrushOption` (area merged with the brush option).
public typealias BrushAreaParamInternal = [String: Any]
//
// export type BrushToolboxIconType = BrushType | 'keep' | 'clear';  -> String (toolbox DEFERRED)
//
// interface BrushOption extends ComponentOption, ModelFinderObject { ... }
//   -> the dynamic brush option bag.
public typealias BrushOption = [String: Any]

// class BrushModel extends ComponentModel<BrushOption>
open class BrushModel: ComponentModel {

    // static type = 'brush' as const; type = BrushModel.type;
    public override class var type: ComponentFullType { return "brush" }

    // static dependencies = ['geo', 'grid', 'xAxis', 'yAxis', 'parallel', 'series'];
    public override class var dependencies: [String] {
        return ["geo", "grid", "xAxis", "yAxis", "parallel", "series"]
    }

    // static defaultOption: BrushOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            "seriesIndex": "all",
            "brushType": "rect",
            "brushMode": "single",
            "transformable": true,
            "brushStyle": [
                "borderWidth": 1.0,
                "color": tokens.color.backgroundTint,
                "borderColor": tokens.color.borderTint
            ] as [String: Any],
            "throttleType": "fixRate",
            "throttleDelay": 0.0,
            "removeOnClick": true,
            "z": 10000.0,
            "defaultOutOfBrushColor": tokens.color.disabled
        ] as [String: Any]
    }

    // @readOnly areas: BrushAreaParamInternal[] = [];
    public var areas: [BrushAreaParamInternal] = []

    // @readOnly brushType: BrushTypeUncertain;  (null => brush inactive)
    public var brushType: String?

    // @readOnly brushOption: BrushCoverCreatorConfig = {};
    public var brushOption: [String: Any] = [:]

    // Inject brushTargetManager: BrushTargetManager;
    //   Assigned by `layoutCovers` (brushVisual.swift) on every visual pass; read by `stepAOthers`
    //   (controlSeries) and by BrushView (`makePanelOpts` / `setOutputRanges`).
    public var brushTargetManager: BrushTargetManager?

    // optionUpdated(newOption: BrushOption, isInit: boolean): void
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // const thisOption = this.option;
        var thisOption = (self.option as? [String: Any]) ?? [:]
        let newOption = (newCptOption as? [String: Any]) ?? [:]

        // !isInit && visualSolution.replaceVisualOption(thisOption, newOption, ['inBrush', 'outOfBrush']);
        if !isInit {
            visualSolution.replaceVisualOption(&thisOption, newOption, ["inBrush", "outOfBrush"])
        }

        // const inBrush = thisOption.inBrush = thisOption.inBrush || {};
        var inBrush = brushJsTruthy(thisOption["inBrush"])
            ? ((thisOption["inBrush"] as? [String: Any]) ?? [:])
            : [:]

        // Always give default visual, consider setOption at the second time.
        // thisOption.outOfBrush = thisOption.outOfBrush || {color: this.option.defaultOutOfBrushColor};
        if !brushJsTruthy(thisOption["outOfBrush"]) {
            thisOption["outOfBrush"] = ["color": thisOption["defaultOutOfBrushColor"] ?? NSNull()] as [String: Any]
        }

        // if (!inBrush.hasOwnProperty('liftZ')) {
        //   // Bigger than the highlight z lift, otherwise it will be effected by the highlight z when brush.
        //   inBrush.liftZ = 5;
        // }
        if inBrush.index(forKey: "liftZ") == nil {
            inBrush["liftZ"] = 5.0
        }

        thisOption["inBrush"] = inBrush
        self.option = thisOption

        // Static/native hosts can provide the same deterministic brush area that an upstream demo
        // dispatches immediately after setOption. Upstream normally populates `areas` only through
        // `dispatchAction`, but accepting it in the option is intentionally additive and lets a
        // headless first-frame render run the regular layout/selector/visual pipeline as well.
        if let areas = newOption["areas"] as? [[String: Any]] {
            setAreas(areas)
        } else if let rawAreas = newOption["areas"] as? [Any] {
            setAreas(rawAreas.compactMap { $0 as? [String: Any] })
        }
    }

    // setAreas(areas?: BrushAreaParam[]): void
    //   If `areas` is null/undefined, range state remain.
    open func setAreas(_ areas: [BrushAreaParam]?) {
        // if (__DEV__) { assert(isArray(areas)); each(areas, (area) => assert(area.brushType, 'Illegal areas')); }
        // (dev asserts dropped)

        // If areas is null/undefined, range state remain. This helps user to
        // dispatchAction({type: 'brush'}) with no areas set but just want to get the current
        // brush select info from a `brush` event.
        guard let areas = areas else {
            return
        }

        // this.areas = map(areas, (area) => generateBrushOption(this.option, area), this);
        let option = (self.option as? [String: Any]) ?? [:]
        self.areas = util.map(areas) { area, _ in
            return generateBrushOption(option, area)
        }
    }

    // setBrushOption(brushOption: BrushCoverCreatorConfig): void
    //   Set the current painting brush option.
    open func setBrushOption(_ brushOption: [String: Any]) {
        // this.brushOption = generateBrushOption(this.option, brushOption);
        let option = (self.option as? [String: Any]) ?? [:]
        self.brushOption = generateBrushOption(option, brushOption)
        // this.brushType = this.brushOption.brushType;
        self.brushType = self.brushOption["brushType"] as? String
    }

}

// function generateBrushOption(option: BrushOption, brushOption): BrushAreaParamInternal | BrushCoverCreatorConfig
//   return merge({ brushType, brushMode, transformable, brushStyle, removeOnClick, z }, brushOption, true);
private func generateBrushOption(_ option: [String: Any], _ brushOption: [String: Any]) -> [String: Any] {
    // Build the base literal. Missing keys stay absent (mirrors `undefined` fields; defaultOption
    // guarantees they are present here).
    var base: [String: Any] = [:]
    if let v = option["brushType"] { base["brushType"] = v }
    if let v = option["brushMode"] { base["brushMode"] = v }
    if let v = option["transformable"] { base["transformable"] = v }
    // brushStyle: new Model(option.brushStyle).getItemStyle()
    base["brushStyle"] = Model(option["brushStyle"]).getItemStyle()
    if let v = option["removeOnClick"] { base["removeOnClick"] = v }
    if let v = option["z"] { base["z"] = v }

    // merge(base, brushOption, true)
    util.merge(&base, brushOption, true)
    return base
}

// export default BrushModel; -> `open class BrushModel` above.

// ---- port-local helpers (not in upstream) ----

// JS truthiness of an `Any?` bag value (for `thisOption.inBrush || {}`, `... || {...}`).
fileprivate func brushJsTruthy(_ value: Any?) -> Bool {
    guard let value = value, !(value is NSNull) else { return false }
    if let b = value as? Bool { return b }
    if let n = value as? Double { return n != 0 && !n.isNaN }
    if let i = value as? Int { return i != 0 }
    if let s = value as? String { return !s.isEmpty }
    return true
}
