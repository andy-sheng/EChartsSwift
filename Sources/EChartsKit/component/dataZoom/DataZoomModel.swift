// Ported from echarts/src/component/dataZoom/DataZoomModel.ts — keep in sync with upstream
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

// import { each, createHashMap, merge, HashMap, assert } from 'zrender/src/core/util';
//   -> ZRenderKit `util` (util.each / util.merge) + EChartsKit modelUtil.swift `createHashMap` / `HashMap`.
// import AxisProxy from './AxisProxy';
//   -> AxisProxy (component/dataZoom/AxisProxy.swift — TASK 2; referenced here, not defined).
// import ComponentModel from '../../model/Component';        -> ComponentModel (model/Component.swift)
// import { LayoutOrient, ComponentOption, LabelOption } from '../../util/types';
//   -> the dynamic option tree is the `[String: Any]` bag (CONVENTIONS §2); `DataZoomOption` /
//      `RangeOption` interfaces are preserved as comments only. `LayoutOrient` ('horizontal'|'vertical')
//      is modeled as `String`.
// import Model from '../../model/Model';                     -> Model (model/Model.swift)
// import GlobalModel from '../../model/Global';              -> GlobalModel (model/Global.swift)
// import { AxisBaseModel } from '../../coord/AxisBaseModel'; -> AxisBaseModel (coord/AxisBaseModel.swift)
// import {
//     getAxisMainType, DATA_ZOOM_AXIS_DIMENSIONS, DataZoomAxisDimension, getAxisProxyFromModel
// } from './helper';
//   -> helper (component/dataZoom/helper.swift). PORT DEPENDENCY: `getAxisMainType`,
//      `DATA_ZOOM_AXIS_DIMENSIONS`, `getAxisProxyFromModel` and the `DataZoomAxisDimension` (= String)
//      alias are owned by the dataZoom `helper` port (shared with AxisProxy.ts). `getAxisMainType` is
//      inlined here as the trivial `axisDim + "Axis"` to avoid a hard link; `DATA_ZOOM_AXIS_DIMENSIONS`
//      and `getAxisProxyFromModel` are referenced as external helper symbols.
// import SingleAxisModel from '../../coord/single/AxisModel'; -> SingleAxisModel (coord/single/SingleAxisModel.swift) — type-only.
// import { MULTIPLE_REFERRING, SINGLE_REFERRING, ModelFinderIndexQuery, ModelFinderIdQuery }
//     from '../../util/model';                               -> model.MULTIPLE_REFERRING / model.SINGLE_REFERRING (util/modelUtil.swift)

// PORT DEPENDENCY (helper.swift, shared with AxisProxy): the axis-dimension list. Inlined constant
// mirrors `DATA_ZOOM_AXIS_DIMENSIONS` for use here; the canonical definition lives in helper.
// (Declared `fileprivate` so it never collides with helper's export.)
fileprivate let DATA_ZOOM_AXIS_DIMENSIONS_LOCAL: [String] = ["x", "y", "radius", "angle", "single"]

// getAxisMainType(axisDim) === axisDim + 'Axis'.
fileprivate func dzGetAxisMainType(_ axisDim: String) -> String {
    return axisDim + "Axis"
}

// class DataZoomAxisInfo { indexList: number[]; indexMap: boolean[]; add(axisCmptIdx); }
final class DataZoomAxisInfo {
    // componentIndex is `Double` on ComponentModel; keep the list as `Double` (feeds getComponent).
    var indexList: [Double] = []
    // upstream: sparse `boolean[]` indexed by componentIndex. Modeled as an Int-keyed set/map.
    var indexMap: [Int: Bool] = [:]

    func add(_ axisCmptIdx: Double) {
        // Remove duplication.
        let key = Int(axisCmptIdx)
        if self.indexMap[key] != true {
            self.indexList.append(axisCmptIdx)
            self.indexMap[key] = true
        }
    }
}

// export type DataZoomTargetAxisInfoMap = HashMap<DataZoomAxisInfo, DataZoomAxisDimension>;
typealias DataZoomTargetAxisInfoMap = HashMap<DataZoomAxisInfo>

// class DataZoomModel<Opts extends DataZoomOption = DataZoomOption> extends ComponentModel<Opts>
//   -> generic `Opts` dropped per CONVENTIONS §2 (dynamic option bag).
open class DataZoomModel: ComponentModel {

    // static type = 'dataZoom'; type = DataZoomModel.type;
    public override class var type: ComponentFullType { return "dataZoom" }

    // static dependencies = ['xAxis', 'yAxis', 'radiusAxis', 'angleAxis', 'singleAxis', 'series', 'toolbox'];
    public override class var dependencies: [String] {
        return ["xAxis", "yAxis", "radiusAxis", "angleAxis", "singleAxis", "series", "toolbox"]
    }

    // static defaultOption: DataZoomOption = { z: 4, filterMode: 'filter', start: 0, end: 100 };
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 4.0,               // Higher than normal component (z: 2).
            "filterMode": "filter",
            "start": 0.0,
            "end": 100.0
        ] as [String: Any]
    }

    // private _autoThrottle = true;
    private var _autoThrottle: Bool = true

    // private _orient: LayoutOrient;
    private var _orient: String = ""

    // private _targetAxisInfoMap: DataZoomTargetAxisInfoMap;
    private var _targetAxisInfoMap: DataZoomTargetAxisInfoMap = createHashMap()

    // private _noTarget: boolean = true;
    private var _noTarget: Bool = true

    // private _rangePropMode: ['percent'|'value', 'percent'|'value'] = ['percent', 'percent'];
    private var _rangePropMode: [String] = ["percent", "percent"]

    // @readonly settledOption: Opts;
    public var settledOption: ModelOption?

    // init(option, parentModel, ecModel)
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {

        // const inputRawOption = retrieveRawOption(option);
        let inputRawOption = retrieveRawOption(option)

        // this.settledOption = inputRawOption;
        self.settledOption = inputRawOption

        // this.mergeDefaultAndTheme(option, ecModel);
        self.mergeDefaultAndTheme(option, ecModel)

        // this._doInit(inputRawOption);
        self._doInit(inputRawOption)
    }

    // mergeOption(newOption: Opts)
    //   upstream takes a single arg; the Swift override matches ComponentModel's `(option, ecModel)`
    //   signature and treats `option` as `newOption` (ecModel unused). Does NOT call super.
    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        _ = ecModel
        // const inputRawOption = retrieveRawOption(newOption);
        let inputRawOption = retrieveRawOption(option)

        // FIX #2591
        // merge(this.option, newOption, true);
        if var target = self.option as? [String: Any], let source = option as? [String: Any] {
            util.merge(&target, source, true)
            self.option = target
        }
        // merge(this.settledOption, inputRawOption, true);
        if var settled = self.settledOption as? [String: Any] {
            util.merge(&settled, inputRawOption, true)
            self.settledOption = settled
        }

        // this._doInit(inputRawOption);
        self._doInit(inputRawOption)
    }

    // private _doInit(inputRawOption: Opts)
    private func _doInit(_ inputRawOption: [String: Any]) {
        // const thisOption = this.option;
        // (Swift option bag is a value type; read/mutate `self.option` as a dict and write back.)

        // this._setDefaultThrottle(inputRawOption);
        self._setDefaultThrottle(inputRawOption)

        // this._updateRangeUse(inputRawOption);
        self._updateRangeUse(inputRawOption)

        // const settledOption = this.settledOption;
        // each([['start','startValue'],['end','endValue']], function (names, index) {
        //   if (this._rangePropMode[index] === 'value') {
        //     thisOption[names[0]] = settledOption[names[0]] = null;
        //   }
        // });
        var thisOption = (self.option as? [String: Any]) ?? [:]
        var settledOption = (self.settledOption as? [String: Any]) ?? [:]
        let pairs = [["start", "startValue"], ["end", "endValue"]]
        for (index, names) in pairs.enumerated() {
            if self._rangePropMode[index] == "value" {
                thisOption[names[0]] = NSNull()   // JS null
                settledOption[names[0]] = NSNull()
            }
            // Otherwise do nothing and use the merge result.
        }
        self.option = thisOption
        self.settledOption = settledOption

        // this._resetTarget();
        self._resetTarget()
    }

    // private _resetTarget()
    private func _resetTarget() {
        // const optionOrient = this.get('orient', true);
        let optionOrient = self.get("orient", true) as? String
        // const targetAxisIndexMap = this._targetAxisInfoMap = createHashMap();
        let targetAxisIndexMap: DataZoomTargetAxisInfoMap = createHashMap()
        self._targetAxisInfoMap = targetAxisIndexMap

        // const hasAxisSpecified = this._fillSpecifiedTargetAxis(targetAxisIndexMap);
        let hasAxisSpecified = self._fillSpecifiedTargetAxis(targetAxisIndexMap)

        if hasAxisSpecified {
            // this._orient = optionOrient || this._makeAutoOrientByTargetAxis();
            self._orient = jsTruthyString(optionOrient) ? optionOrient! : self._makeAutoOrientByTargetAxis()
        }
        else {
            // this._orient = optionOrient || 'horizontal';
            self._orient = jsTruthyString(optionOrient) ? optionOrient! : "horizontal"
            // this._fillAutoTargetAxisByOrient(targetAxisIndexMap, this._orient);
            self._fillAutoTargetAxisByOrient(targetAxisIndexMap, self._orient)
        }

        // this._noTarget = true;
        self._noTarget = true
        // targetAxisIndexMap.each(function (axisInfo) { if (axisInfo.indexList.length) this._noTarget = false; });
        targetAxisIndexMap.each { axisInfo, _ in
            if !axisInfo.indexList.isEmpty {
                self._noTarget = false
            }
        }
    }

    // private _fillSpecifiedTargetAxis(targetAxisIndexMap): boolean
    private func _fillSpecifiedTargetAxis(_ targetAxisIndexMap: DataZoomTargetAxisInfoMap) -> Bool {
        var hasAxisSpecified = false

        // each(DATA_ZOOM_AXIS_DIMENSIONS, function (axisDim) { ... });
        util.each(DATA_ZOOM_AXIS_DIMENSIONS_LOCAL) { axisDim, _ in
            // const refering = this.getReferringComponents(getAxisMainType(axisDim), MULTIPLE_REFERRING);
            let refering = self.getReferringComponents(dzGetAxisMainType(axisDim), model.MULTIPLE_REFERRING)
            // When user set axisIndex as a empty array, we think that user specify axisIndex
            // but do not want use auto mode. Because empty array may be encountered when
            // some error occurred.
            // if (!refering.specified) return;
            if !refering.specified {
                return
            }
            hasAxisSpecified = true
            let axisInfo = DataZoomAxisInfo()
            // each(refering.models, function (axisModel) { axisInfo.add(axisModel.componentIndex); });
            util.each(refering.models) { axisModel, _ in
                axisInfo.add(axisModel.componentIndex)
            }
            targetAxisIndexMap.set(axisDim, axisInfo)
        }

        return hasAxisSpecified
    }

    // private _fillAutoTargetAxisByOrient(targetAxisIndexMap, orient: LayoutOrient)
    private func _fillAutoTargetAxisByOrient(_ targetAxisIndexMap: DataZoomTargetAxisInfoMap, _ orient: String) {
        // const ecModel = this.ecModel;
        guard let ecModel = self.ecModel else { return }
        // let needAuto = true;
        var needAuto = true

        // function setParallelAxis(axisModels, axisDim) { ... } (captures needAuto)
        func setParallelAxis(_ axisModels: [ComponentModel], _ axisDim: String) {
            // At least use the first parallel axis as the target axis.
            // const axisModel = axisModels[0]; if (!axisModel) return;
            guard let axisModel = axisModels.first else {
                return
            }
            let axisInfo = DataZoomAxisInfo()
            axisInfo.add(axisModel.componentIndex)
            targetAxisIndexMap.set(axisDim, axisInfo)
            needAuto = false

            // Find parallel axes in the same grid.
            if axisDim == "x" || axisDim == "y" {
                // const gridModel = axisModel.getReferringComponents('grid', SINGLE_REFERRING).models[0];
                let gridModel = axisModel.getReferringComponents("grid", model.SINGLE_REFERRING).models.first
                // gridModel && each(axisModels, function (axModel) { ... });
                if let gridModel = gridModel {
                    util.each(axisModels) { axModel, _ in
                        if axisModel.componentIndex != axModel.componentIndex
                            && gridModel === axModel.getReferringComponents("grid", model.SINGLE_REFERRING).models.first {
                            axisInfo.add(axModel.componentIndex)
                        }
                    }
                }
            }
        }

        // Find axis that parallel to dataZoom as default.
        if needAuto {
            let axisDim = orient == "vertical" ? "y" : "x"
            // const axisModels = ecModel.findComponents({ mainType: axisDim + 'Axis' });
            let axisModels = ecModel.findComponents(QueryConditionKindA(mainType: axisDim + "Axis"))
            setParallelAxis(axisModels, axisDim)
        }
        // Find axis that parallel to dataZoom as default.
        if needAuto {
            // const axisModels = ecModel.findComponents({ mainType: 'singleAxis',
            //     filter: (axisModel) => axisModel.get('orient', true) === orient });
            let axisModels = ecModel.findComponents(QueryConditionKindA(
                mainType: "singleAxis",
                filter: { axisModel in (axisModel.get("orient", true) as? String) == orient }
            ))
            setParallelAxis(axisModels, "single")
        }

        if needAuto {
            // If no parallel axis, find the first category axis as default. (Also consider polar).
            util.each(DATA_ZOOM_AXIS_DIMENSIONS_LOCAL) { axisDim, _ in
                if !needAuto {
                    return
                }
                // const axisModels = ecModel.findComponents({ mainType: getAxisMainType(axisDim),
                //     filter: (axisModel) => axisModel.get('type', true) === 'category' });
                let axisModels = ecModel.findComponents(QueryConditionKindA(
                    mainType: dzGetAxisMainType(axisDim),
                    filter: { axisModel in (axisModel.get("type", true) as? String) == "category" }
                ))
                if let first = axisModels.first {
                    let axisInfo = DataZoomAxisInfo()
                    axisInfo.add(first.componentIndex)
                    targetAxisIndexMap.set(axisDim, axisInfo)
                    needAuto = false
                }
            }
        }
    }

    // private _makeAutoOrientByTargetAxis(): LayoutOrient
    private func _makeAutoOrientByTargetAxis() -> String {
        // let dim: string;
        var dim: String?

        // Find the first axis
        self.eachTargetAxis { axisDim, _ in
            // !dim && (dim = axisDim);
            if !jsTruthyString(dim) {
                dim = axisDim
            }
        }

        // return dim === 'y' ? 'vertical' : 'horizontal';
        return dim == "y" ? "vertical" : "horizontal"
    }

    // private _setDefaultThrottle(inputRawOption: DataZoomOption)
    private func _setDefaultThrottle(_ inputRawOption: [String: Any]) {
        // When first time user set throttle, auto throttle ends.
        // if (inputRawOption.hasOwnProperty('throttle')) { this._autoThrottle = false; }
        if inputRawOption.keys.contains("throttle") {
            self._autoThrottle = false
        }
        if self._autoThrottle {
            // const globalOption = this.ecModel.option;
            let globalOption = (self.ecModel?.option as? [String: Any]) ?? [:]
            // this.option.throttle = (globalOption.animation && globalOption.animationDurationUpdate > 0) ? 100 : 20;
            let animation = jsTruthy(globalOption["animation"])
            let durUpdate = dzAsNum(globalOption["animationDurationUpdate"]) ?? 0
            if var opt = self.option as? [String: Any] {
                opt["throttle"] = (animation && durUpdate > 0) ? 100.0 : 20.0
                self.option = opt
            }
        }
    }

    // private _updateRangeUse(inputRawOption: RangeOption)
    private func _updateRangeUse(_ inputRawOption: [String: Any]) {
        // const rangePropMode = this._rangePropMode;
        // const rangeModeInOption = this.get('rangeMode');
        let rangeModeInOption = self.get("rangeMode") as? [Any]

        let pairs = [["start", "startValue"], ["end", "endValue"]]
        for (index, names) in pairs.enumerated() {
            // const percentSpecified = inputRawOption[names[0]] != null;
            // const valueSpecified = inputRawOption[names[1]] != null;
            let percentSpecified = jsNotNull(inputRawOption[names[0]])
            let valueSpecified = jsNotNull(inputRawOption[names[1]])
            if percentSpecified && !valueSpecified {
                self._rangePropMode[index] = "percent"
            }
            else if !percentSpecified && valueSpecified {
                self._rangePropMode[index] = "value"
            }
            else if let rangeModeInOption = rangeModeInOption {   // else if (rangeModeInOption)
                self._rangePropMode[index] = (rangeModeInOption[index] as? String) ?? self._rangePropMode[index]
            }
            else if percentSpecified {   // percentSpecified && valueSpecified
                self._rangePropMode[index] = "percent"
            }
            // else remain its original setting.
        }
    }

    // noTarget(): boolean
    open func noTarget() -> Bool {
        return self._noTarget
    }

    // getFirstTargetAxisModel(): AxisBaseModel
    open func getFirstTargetAxisModel() -> AxisBaseModel? {
        // let firstAxisModel: AxisBaseModel;
        var firstAxisModel: AxisBaseModel?
        self.eachTargetAxis { axisDim, axisIndex in
            // if (firstAxisModel == null) {
            //   firstAxisModel = this.ecModel.getComponent(getAxisMainType(axisDim), axisIndex);
            // }
            if firstAxisModel == nil {
                firstAxisModel = self.ecModel?.getComponent(dzGetAxisMainType(axisDim), axisIndex) as? AxisBaseModel
            }
        }
        return firstAxisModel
    }

    // eachTargetAxis(callback: (axisDim, axisIndex) => void, context?)
    open func eachTargetAxis(_ callback: (_ axisDim: String, _ axisIndex: Double) -> Void) {
        self._targetAxisInfoMap.each { axisInfo, axisDim in
            util.each(axisInfo.indexList) { axisIndex, _ in
                callback(axisDim, axisIndex)
            }
        }
    }

    // getAxisProxy(axisDim, axisIndex): AxisProxy   (null/undefined if not found)
    open func getAxisProxy(_ axisDim: String, _ axisIndex: Double) -> AxisProxy? {
        return getAxisProxyFromModel(self.getAxisModel(axisDim, axisIndex))
    }

    // getAxisModel(axisDim, axisIndex): AxisBaseModel   (null/undefined if not found)
    open func getAxisModel(_ axisDim: String, _ axisIndex: Double) -> AxisBaseModel? {
        // if (__DEV__) assert(axisDim && axisIndex != null);
        // const axisInfo = this._targetAxisInfoMap.get(axisDim);
        let axisInfo = self._targetAxisInfoMap.get(axisDim)
        // if (axisInfo && axisInfo.indexMap[axisIndex]) {
        if let axisInfo = axisInfo, axisInfo.indexMap[Int(axisIndex)] == true {
            return self.ecModel?.getComponent(dzGetAxisMainType(axisDim), axisIndex) as? AxisBaseModel
        }
        return nil
    }

    // setRawRange(opt: RangeOption)   (If not specified, set to undefined.)
    open func setRawRange(_ opt: [String: Any]) {
        // const thisOption = this.option; const settledOption = this.settledOption;
        var thisOption = (self.option as? [String: Any]) ?? [:]
        var settledOption = (self.settledOption as? [String: Any]) ?? [:]
        let pairs = [["start", "startValue"], ["end", "endValue"]]
        util.each(pairs) { names, _ in
            // if (opt[names[0]] != null || opt[names[1]] != null) {
            //   thisOption[names[0]] = settledOption[names[0]] = opt[names[0]];
            //   thisOption[names[1]] = settledOption[names[1]] = opt[names[1]];
            // }
            if jsNotNull(opt[names[0]]) || jsNotNull(opt[names[1]]) {
                // Assign the possibly-undefined value (undefined -> remove key; mirrors JS `= undefined`).
                dzAssign(&thisOption, names[0], opt[names[0]])
                dzAssign(&settledOption, names[0], opt[names[0]])
                dzAssign(&thisOption, names[1], opt[names[1]])
                dzAssign(&settledOption, names[1], opt[names[1]])
            }
        }
        self.option = thisOption
        self.settledOption = settledOption

        // this._updateRangeUse(opt);
        self._updateRangeUse(opt)
    }

    // setCalculatedRange(opt: RangeOption)
    open func setCalculatedRange(_ opt: [String: Any]) {
        // const option = this.option;
        var option = (self.option as? [String: Any]) ?? [:]
        // each(['start','startValue','end','endValue'], function (name) { option[name] = opt[name]; });
        util.each(["start", "startValue", "end", "endValue"]) { name, _ in
            dzAssign(&option, name, opt[name])
        }
        self.option = option
    }

    // getPercentRange(): number[]
    open func getPercentRange() -> [Double]? {
        // const axisProxy = this.findRepresentativeAxisProxy();
        if let axisProxy = self.findRepresentativeAxisProxy() {
            return axisProxy.getWindow().percent
        }
        return nil
    }

    // getValueRange(axisDim, axisIndex): number[]
    open func getValueRange(_ axisDim: String? = nil, _ axisIndex: Double? = nil) -> [Double]? {
        // if (axisDim == null && axisIndex == null) {
        if axisDim == nil && axisIndex == nil {
            if let axisProxy = self.findRepresentativeAxisProxy() {
                return axisProxy.getWindow().value
            }
            return nil
        }
        else {
            // return this.getAxisProxy(axisDim, axisIndex).getWindow().value;
            return self.getAxisProxy(axisDim!, axisIndex!)?.getWindow().value
        }
    }

    // findRepresentativeAxisProxy(axisModel?): AxisProxy
    open func findRepresentativeAxisProxy(_ axisModel: AxisBaseModel? = nil) -> AxisProxy? {
        // if (axisModel) return getAxisProxyFromModel(axisModel);
        if let axisModel = axisModel {
            return getAxisProxyFromModel(axisModel)
        }

        // Find the first hosted axisProxy
        var firstProxy: AxisProxy?
        let axisDimList = self._targetAxisInfoMap.keys()
        for i in 0..<axisDimList.count {
            let axisDim = axisDimList[i]
            guard let axisInfo = self._targetAxisInfoMap.get(axisDim) else { continue }
            for j in 0..<axisInfo.indexList.count {
                let proxy = self.getAxisProxy(axisDim, axisInfo.indexList[j])
                if let proxy = proxy, proxy.hostedBy(self) {
                    return proxy
                }
                if firstProxy == nil {   // if (!firstProxy)
                    firstProxy = proxy
                }
            }
        }

        // If no hosted proxy found, still need to return a proxy.
        // This case always happens in toolbox dataZoom, where axes are all hosted by
        // other dataZooms.
        return firstProxy
    }

    // getRangePropMode(): ['percent'|'value', 'percent'|'value']
    open func getRangePropMode() -> [String] {
        // return this._rangePropMode.slice();
        return Array(self._rangePropMode)
    }

    // getOrient(): LayoutOrient
    open func getOrient() -> String {
        // if (__DEV__) assert(this._orient);  // Should not be called before initialized.
        return self._orient
    }
}

// function retrieveRawOption<T extends DataZoomOption>(option: T)
//   Retrieve those raw params from option, which will be cached separately, because they will be
//   overwritten by normalized/calculated values in the main process.
private func retrieveRawOption(_ option: ModelOption?) -> [String: Any] {
    var ret: [String: Any] = [:]
    let opt = (option as? [String: Any]) ?? [:]
    util.each(["start", "end", "startValue", "endValue", "throttle"]) { name, _ in
        // option.hasOwnProperty(name) && (ret[name] = option[name]);
        if opt.keys.contains(name) {
            ret[name] = opt[name]
        }
    }
    return ret
}

// export default DataZoomModel; -> `open class DataZoomModel` above.

// ---- port-local helpers (not in upstream) ----

// JS `x != null` — false only for `nil`/undefined and `NSNull` (JS null).
fileprivate func jsNotNull(_ value: Any?) -> Bool {
    if value == nil { return false }
    if value is NSNull { return false }
    return true
}

// JS truthiness of a `Any?` bag value (for `globalOption.animation` etc.).
fileprivate func jsTruthy(_ value: Any?) -> Bool {
    guard let value = value, !(value is NSNull) else { return false }
    if let b = value as? Bool { return b }
    if let n = value as? Double { return n != 0 && !n.isNaN }
    if let i = value as? Int { return i != 0 }
    if let s = value as? String { return !s.isEmpty }
    return true
}

// JS truthiness of an optional string (`optionOrient || ...`, `!dim`).
fileprivate func jsTruthyString(_ value: String?) -> Bool {
    guard let value = value else { return false }
    return !value.isEmpty
}

// Int-vs-Double coercion for numeric option reads (defaultOptions box numbers as Int).
fileprivate func dzAsNum(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let f = value as? Float { return Double(f) }
    return nil
}

// JS `dict[key] = value` where `value` may be `undefined` (nil). Assigning `undefined` in JS removes
// nothing on read via `!= null`, but keeps the object shape; here we set the key to the value, or
// remove it when the source is truly absent (nil), while preserving explicit NSNull (JS null).
fileprivate func dzAssign(_ dict: inout [String: Any], _ key: String, _ value: Any?) {
    if let value = value {
        dict[key] = value
    }
    else {
        // JS `= undefined`: on our value-bag, model an explicit `undefined` as key removal so that
        // subsequent `!= null` reads see it as absent.
        dict.removeValue(forKey: key)
    }
}
