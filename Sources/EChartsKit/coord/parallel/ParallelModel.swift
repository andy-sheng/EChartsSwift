// Ported from echarts/src/coord/parallel/ParallelModel.ts — keep in sync with upstream
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

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                    -> `util.*` (ZRenderKit).
//   import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift).
//   import type Parallel from './Parallel';                             -> Parallel (coord/parallel/Parallel.swift; coord-sys master).
//       `Parallel` (the 5th coordinate-system master) is ported (coord/parallel/Parallel.swift).
//       `coordinateSystem` is typed via `CoordinateSystemMaster?` below (mirroring PolarModel);
//       narrow via `as? Parallel` at use.
//   import {
//       DimensionName, ComponentOption, BoxLayoutOptionMixin, ComponentOnCalendarOptionMixin,
//       ComponentOnMatrixOptionMixin
//   } from '../../util/types';                                          -> DimensionName (util/types.swift); the option
//       mixin interfaces are dropped (dynamic option bag, CONVENTIONS §2).
//   import ParallelAxisModel, { ParallelAxisOption } from './AxisModel';
//       -> ParallelAxisModel (coord/parallel/ParallelAxisModel.swift; a forthcoming sibling). Not referenced
//          by name here — the axis models are read back through the generic `ComponentModel` base.
//   import GlobalModel from '../../model/Global';                       -> GlobalModel (model/Global.swift).
//   import ParallelSeriesModel from '../../chart/parallel/ParallelSeries';
//       -> ParallelSeriesModel (chart/parallel/ParallelSeries.swift; a forthcoming sibling). Erased to the
//          `ComponentModel` base in `contains` (the `.get('parallelIndex')` read lives on the base).
//   import SeriesModel from '../../model/Series';                       -> SeriesModel (model/Series.swift).

// upstream: export const COORD_SYS_TYPE_PARALLEL = 'parallel';
public let COORD_SYS_TYPE_PARALLEL = "parallel"
// upstream: export const COMPONENT_TYPE_PARALLEL = COORD_SYS_TYPE_PARALLEL;
public let COMPONENT_TYPE_PARALLEL = COORD_SYS_TYPE_PARALLEL

// upstream: export type ParallelLayoutDirection = 'horizontal' | 'vertical';
//   no string unions in Swift → a `String` alias (option is read from the dynamic bag).
public typealias ParallelLayoutDirection = String

// upstream:
// export interface ParallelCoordinateSystemOption extends
//     ComponentOption, ComponentOnCalendarOptionMixin,
//     ComponentOnMatrixOptionMixin, BoxLayoutOptionMixin { ... }
//   `ParallelCoordinateSystemOption` describes the dynamic option shape (mainType/layout/
//   axisExpand*/left/top/right/bottom/parallelAxisDefault plus the box/calendar/matrix mixins); modeled as
//   the dynamic option bag ([String: Any]) per CONVENTIONS §2 — no standalone Swift struct emitted.

// upstream:
// class ParallelModel extends ComponentModel<ParallelCoordinateSystemOption> { ... }
//   TS class → `final class : ComponentModel` (CONVENTIONS §2). Conforms to `CoordinateSystemHostModel`
//   so `coordinateSystem` satisfies the required contract (mirrors PolarModel; upstream's
//   `coordinateSystem: Parallel` matches that interface since Parallel is a CoordinateSystemMaster).
public final class ParallelModel: ComponentModel, CoordinateSystemHostModel {

    // static type = COMPONENT_TYPE_PARALLEL;
    // readonly type = ParallelModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return COMPONENT_TYPE_PARALLEL }

    // static dependencies = ['parallelAxis'];
    public override class var dependencies: [String] { return ["parallelAxis"] }

    // coordinateSystem: Parallel;
    //   upstream types this the concrete `Parallel` (a `CoordinateSystemMaster`), injected by
    //   parallelCreator once the coordinate system is built. `Parallel` (coord/parallel/Parallel.swift) is
    //   ported; typed here as the `CoordinateSystemMaster?` required by
    //   `CoordinateSystemHostModel` (narrow via `as? Parallel` at use).
    public var coordinateSystem: CoordinateSystemMaster?

    /**
     * Each item like: 'dim0', 'dim1', 'dim2', ...
     */
    // dimensions: DimensionName[];
    public var dimensions: [DimensionName] = []

    /**
     * Corresponding to dimensions.
     */
    // parallelAxisIndex: number[];
    public var parallelAxisIndex: [Double] = []

    // static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    // static defaultOption: ParallelCoordinateSystemOption = { ... }
    //   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
    //   (the INT-vs-DOUBLE option-read trap).
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 0.0,
            "left": 80.0,
            "top": 60.0,
            "right": 80.0,
            "bottom": 60.0,
            // width: {totalWidth} - left - right,
            // height: {totalHeight} - top - bottom,

            "layout": "horizontal",      // 'horizontal' or 'vertical'

            // FIXME
            // naming?
            "axisExpandable": false,
            // axisExpandCenter: null,
            //   upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
            "axisExpandCenter": NSNull(),
            "axisExpandCount": 0.0,
            "axisExpandWidth": 50.0,      // FIXME '10%' ?
            "axisExpandRate": 17.0,
            "axisExpandDebounce": 50.0,
            // [out, in, jumpTarget]. In percentage. If use [null, 0.05], null means full.
            // Do not doc to user until necessary.
            "axisExpandSlideTriggerArea": [-0.15, 0.05, 0.4],
            "axisExpandTriggerOn": "click", // 'mousemove' or 'click'

            // parallelAxisDefault: null
            //   upstream value is `null`; NSNull() retains the key.
            "parallelAxisDefault": NSNull()
        ] as [String: Any]
    }

    // init() { super.init.apply(this, arguments as any); this.mergeOption({}); }
    //   Overrides the ec lifecycle `init` (not the constructor). `super.init.apply(this, arguments)` forwards
    //   the constructor args; the variadic `rest` tail is unused by the base, so the fixed three are forwarded.
    public override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // super.init.apply(this, arguments as any);
        super.`init`(option, parentModel, ecModel)
        // this.mergeOption({});
        self.mergeOption([String: Any](), ecModel)
    }

    // mergeOption(newOption: ParallelCoordinateSystemOption) { ... }
    //   NOTE: upstream does NOT call `super.mergeOption`; it merges directly then re-inits dimensions.
    //   The base signature carries `ecModel` (unused by this override).
    public override func mergeOption(_ newOption: ModelOption?, _ ecModel: GlobalModel?) {
        // const thisOption = this.option;
        // newOption && zrUtil.merge(thisOption, newOption, true);
        //   upstream mutates `this.option` in place; Swift option bags are value types, so
        //   read-modify-write `self.option`. `{}` is truthy in JS, so only nil skips the merge.
        if let source = newOption as? [String: Any],
           var thisOption = self.option as? [String: Any] {
            util.merge(&thisOption, source, true)
            self.option = thisOption
        }

        // this._initDimensions();
        self._initDimensions()

        _ = ecModel
    }

    /**
     * Whether series or axis is in this coordinate system.
     */
    // contains(model: SeriesModel | ParallelAxisModel, ecModel: GlobalModel): boolean
    //   union param erased to the shared `ComponentModel` base (the `.get('parallelIndex')` read lives there).
    public func contains(_ model: ComponentModel, _ ecModel: GlobalModel) -> Bool {
        // const parallelIndex = (model as ParallelSeriesModel).get('parallelIndex');
        let parallelIndex = model.get("parallelIndex")
        // return parallelIndex != null && ecModel.getComponent('parallel', parallelIndex) === this;
        if parallelIndex != nil && !(parallelIndex is NSNull) {
            if let comp = ecModel.getComponent("parallel", numOpt(parallelIndex)), comp === self {
                return true
            }
        }
        return false
    }

    // setAxisExpand(opt: { axisExpandable?, axisExpandCenter?, axisExpandCount?, axisExpandWidth?, axisExpandWindow? }): void
    //   TS object-param modeled as the dynamic `[String: Any]` bag.
    public func setAxisExpand(_ opt: [String: Any]) {
        // zrUtil.each(['axisExpandable', 'axisExpandCenter', 'axisExpandCount', 'axisExpandWidth', 'axisExpandWindow'],
        //     function (name) { if (opt.hasOwnProperty(name)) { this.option[name] = opt[name]; } }, this);
        util.each([
            "axisExpandable",
            "axisExpandCenter",
            "axisExpandCount",
            "axisExpandWidth",
            "axisExpandWindow"
        ]) { name, _ in
            // if (opt.hasOwnProperty(name)) { this.option[name] = opt[name]; }
            //   hasOwnProperty is true whenever the key is present -> `opt.keys.contains(name)`.
            if opt.keys.contains(name) {
                if var o = self.option as? [String: Any] {
                    o[name] = opt[name]
                    self.option = o
                }
            }
        }
    }

    // private _initDimensions(): void
    private func _initDimensions() {
        // const dimensions = this.dimensions = [] as DimensionName[];
        self.dimensions = []
        // const parallelAxisIndex = this.parallelAxisIndex = [] as number[];
        self.parallelAxisIndex = []

        // const axisModels = zrUtil.filter(
        //     this.ecModel.queryComponents({ mainType: 'parallelAxis' }),
        //     function (axisModel) {
        //         // Can not use this.contains here, because
        //         // initialization has not been completed yet.
        //         return (axisModel.get('parallelIndex') || 0) === this.componentIndex;
        //     }, this);
        let queried = self.ecModel?.queryComponents(QueryConditionKindB(mainType: "parallelAxis")) ?? []
        let axisModels = util.filter(queried) { axisModel, _ in
            // (axisModel.get('parallelIndex') || 0) === this.componentIndex
            //   `|| 0` (JS falsy): a missing/0 parallelIndex resolves to 0 -> `numOpt(...) ?? 0`.
            return (numOpt(axisModel.get("parallelIndex")) ?? 0) == self.componentIndex
        }

        // zrUtil.each(axisModels, function (axisModel) {
        //     dimensions.push('dim' + axisModel.get('dim'));
        //     parallelAxisIndex.push(axisModel.componentIndex);
        // });
        util.each(axisModels) { axisModel, _ in
            self.dimensions.append("dim" + jsNumStr(axisModel.get("dim")))
            self.parallelAxisIndex.append(axisModel.componentIndex)
        }
    }
}

// export default ParallelModel;  -> `public final class ParallelModel` above.

// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
// defaultOption literals use (e.g. `"axisExpandWidth": 50`). A bare `as? Double` returns nil on an
// Int, which silently drops the value — the recurring Int-vs-Double option-read trap.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// JS `'dim' + value` string concat. Integer numbers print without a trailing `.0`
// (JS `'dim' + 0` === 'dim0', not 'dim0.0'); strings pass through unchanged.
private func jsNumStr(_ v: Any?) -> String {
    if let d = numOpt(v) {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }
    if let s = v as? String { return s }
    // JS would stringify other values (e.g. `undefined` -> "undefined"); `dim` is always a
    //   number/string in practice, so non-number/non-string falls back to "".
    return ""
}
