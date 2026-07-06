// Ported from echarts/src/component/visualMap/VisualMapModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';
//   -> ZRenderKit `util` (util.each / util.map / util.find / util.clone / util.merge / util.isArray
//      / util.isString / util.isFunction / util.bind)
// import visualDefault from '../../visual/visualDefault';
//   -> PORT-TODO: visual/visualDefault.ts NOT ported. `visualDefault.get(visualType, 'inactive',
//      isCategory)` supplies the default "inactive" visual for `completeInactive`. The inactive-state
//      completion is DEFERRED (see completeInactive below) until visualDefault lands.
// import VisualMapping, { VisualMappingOption } from '../../visual/VisualMapping';
//   -> PORT-TODO: visual/VisualMapping.ts NOT ported (same deferral as treemapVisual.swift /
//      sankeyVisual.swift). `VisualMapping.mapVisual` / `.eachVisual` / `.isValidType` and the
//      `VisualMapping` instances built by visualSolution are unavailable. `VisualMappingOption` is
//      modeled as the `[String: Any]` bag.
// import * as visualSolution from '../../visual/visualSolution';
//   -> PORT-TODO: visual/visualSolution.ts NOT ported. `visualSolution.createVisualMappings`,
//      `visualSolution.replaceVisualOption` back `resetVisual` / `optionUpdated`; DEFERRED.
// import * as modelUtil from '../../util/model';        -> EChartsKit `model` namespace (util/modelUtil.swift)
// import * as numberUtil from '../../util/number';      -> EChartsKit `number` namespace (util/number.swift)
// import { ...many option interfaces... } from '../../util/types';
//   -> The dynamic option tree is modeled as the `[String: Any]` bag (CONVENTIONS §2); the TS
//      `VisualMapOption` interface is not emitted as a Swift struct (kept as comments only).
// import ComponentModel from '../../model/Component';   -> ComponentModel (model/Component.swift)
// import Model from '../../model/Model';                -> Model (model/Model.swift)
// import GlobalModel from '../../model/Global';         -> GlobalModel (model/Global.swift)
// import SeriesModel from '../../model/Series';         -> SeriesModel (model/Series.swift)
// import SeriesData from '../../data/SeriesData';       -> SeriesData (data/SeriesData.swift)
// import tokens from '../../visual/tokens';
//   -> PORT-TODO: visual/tokens.ts not ported yet. The `tokens.*` values consumed in `defaultOption`
//      are inlined verbatim as their resolved constants; re-wire once visual/tokens.swift lands.
//        tokens.color.transparent = 'rgba(0,0,0,0)'
//        tokens.color.borderTint  = color.neutral20 = '#cfd2d7'
//        tokens.color.theme[0]    = '#5070dd'
//        tokens.color.disabled    = color.neutral20 = '#cfd2d7'
//        tokens.color.secondary   = color.neutral70 = '#54555a'
//        tokens.size.m            = 15

// const mapVisual = VisualMapping.mapVisual;
// const eachVisual = VisualMapping.eachVisual;
// PORT-TODO: VisualMapping DEFERRED — `mapVisual` / `eachVisual` are unavailable; the call sites in
//   `completeVisualOption` that use them are elided behind PORT-TODO.
// const isArray = zrUtil.isArray;    -> util.isArray
// const each = zrUtil.each;          -> util.each
// const asc = numberUtil.asc;        -> number.asc
// const linearMap = numberUtil.linearMap;   -> number.linearMap

// type VisualOptionBase = {[key in BuiltinVisualProperty]?: any};   -> [String: Any]
// type LabelFormatter = (min: OptionDataValue, max?: OptionDataValue) => string;
// type VisualState = VisualMapModel['stateList'][number];   -> 'inRange' | 'outOfRange'
public typealias VisualState = String

// export interface VisualMapOption<...> extends ComponentOption, ... { ... }
//   -> Modeled as the `[String: Any]` option bag (CONVENTIONS §2). The interface's fields
//      (show / align / realtime / seriesIndex / min / max / dimension / inRange / outOfRange /
//      controller / target / itemWidth / itemHeight / inverse / orient / backgroundColor /
//      contentColor / inactiveColor / padding / textGap / precision / color / formatter / text /
//      textStyle / categories …) are accessed dynamically off `self.option`.

// export interface VisualMeta { stops: {value,color}[]; outerColors: ColorString[]; dimension? }
public struct VisualMeta {
    // outerColor means [colorBeyondMinValue, colorBeyondMaxValue]
    public struct Stop {
        public var value: Double
        public var color: ColorString
        public init(value: Double, color: ColorString) {
            self.value = value
            self.color = color
        }
    }
    public var stops: [Stop]
    public var outerColors: [ColorString]
    public var dimension: DimensionIndex?
    public init(stops: [Stop], outerColors: [ColorString], dimension: DimensionIndex? = nil) {
        self.stops = stops
        self.outerColors = outerColors
        self.dimension = dimension
    }
}

// class VisualMapModel<Opts extends VisualMapOption = VisualMapOption> extends ComponentModel<Opts>
//   -> generic `Opts` dropped per CONVENTIONS §2 (dynamic option bag). `open` so the concrete
//      Continuous/Piecewise models subclass it.
open class VisualMapModel: ComponentModel {

    // static type = 'visualMap';
    // type = VisualMapModel.type;   (instance `type` already mirrors the static in ComponentModel)
    public override class var type: ComponentFullType { return "visualMap" }

    // static readonly dependencies = ['series'];
    public override class var dependencies: [String] { return ["series"] }

    // readonly stateList = ['inRange', 'outOfRange'] as const;
    public let stateList: [VisualState] = ["inRange", "outOfRange"]

    // readonly replacableOptionKeys = ['inRange', 'outOfRange', 'target', 'controller', 'color'] as const;
    // (upstream spelling "replacable" preserved.)
    public let replacableOptionKeys: [String] = [
        "inRange", "outOfRange", "target", "controller", "color"
    ]

    // readonly layoutMode = { type: 'box', ignoreSize: true } as const;
    // PORT-TODO: upstream declares `layoutMode` as an INSTANCE readonly member; the Swift
    //   ComponentModel exposes it as `open class var`. Modeled as a class-var override.
    public override class var layoutMode: Any? {
        return ["type": "box", "ignoreSize": true] as [String: Any]
    }

    /**
     * [lowerBound, upperBound]
     */
    // dataBound = [-Infinity, Infinity];
    public var dataBound: [Double] = [-Double.infinity, Double.infinity]

    // protected _dataExtent: [number, number];
    // PORT-TODO: upstream leaves this uninitialized (assigned by `resetExtent`); Swift requires a
    //   stored value, so it defaults to empty.
    internal var _dataExtent: [Double] = []   // upstream: protected

    // targetVisuals = {} as ReturnType<typeof visualSolution.createVisualMappings>;
    // PORT-TODO: visualSolution NOT ported — `createVisualMappings` returns a per-state map of
    //   `VisualMapping` instances (`{ inRange: {...}, outOfRange: {...} }`). Held as the `[String: Any]`
    //   bag; populated once visualSolution + VisualMapping land.
    public var targetVisuals: [String: Any] = [:]

    // controllerVisuals = {} as ReturnType<typeof visualSolution.createVisualMappings>;
    public var controllerVisuals: [String: Any] = [:]

    // textStyleModel: Model<LabelOption>;
    // PORT-TODO: upstream leaves this uninitialized (assigned by `optionUpdated`); Swift requires a
    //   stored value, so it defaults to a fresh empty Model until `optionUpdated` runs.
    public var textStyleModel: Model = Model()

    // itemSize: number[];
    // PORT-TODO: assigned by `resetItemSize`; defaults to empty until then.
    public var itemSize: [Double] = []

    // init(option, parentModel, ecModel) { this.mergeDefaultAndTheme(option, ecModel); }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        self.mergeDefaultAndTheme(option, ecModel)
    }

    /**
     * @protected
     */
    // optionUpdated(newOption, isInit?)
    open override func optionUpdated(_ newOption: ModelOption?, _ isInit: Bool) {
        let thisOption = self.option

        // !isInit && visualSolution.replaceVisualOption(thisOption, newOption, this.replacableOptionKeys);
        // PORT-TODO: visualSolution.replaceVisualOption NOT ported (visualSolution deferred). It moves
        //   the replacable option keys from `newOption` onto `thisOption` (replace-not-merge). Deferred.
        _ = thisOption
        _ = newOption
        if !isInit {
            // visualSolution.replaceVisualOption(thisOption, newOption, this.replacableOptionKeys)
        }

        // this.textStyleModel = this.getModel('textStyle');
        self.textStyleModel = self.getModel("textStyle")

        // this.resetItemSize();
        self.resetItemSize()

        // this.completeVisualOption();
        self.completeVisualOption()
    }

    /**
     * @protected
     */
    // resetVisual(supplementVisualOption: (this, mappingOption, state) => void)
    open func resetVisual(_ supplementVisualOption: @escaping (VisualMapModel, inout [String: Any], String) -> Void) {
        // const stateList = this.stateList;
        let stateList = self.stateList
        // supplementVisualOption = zrUtil.bind(supplementVisualOption, this);
        //   Bridge the model-first callback to the (mappingOption, state) shape createVisualMappings wants.
        let bound: (inout [String: Any], String) -> Void = { [weak self] mappingOption, state in
            guard let self = self else { return }
            supplementVisualOption(self, &mappingOption, state)
        }

        let thisOption = (self.option as? [String: Any]) ?? [:]
        let controllerOption = thisOption["controller"] as? [String: Any]
        let targetOption = thisOption["target"] as? [String: Any]

        // this.controllerVisuals = visualSolution.createVisualMappings(this.option.controller, stateList, supplement);
        let controllerColl = visualSolution.createVisualMappings(controllerOption, stateList, bound)
        self.controllerVisuals = controllerColl.mapValues { $0 as Any }
        // this.targetVisuals = visualSolution.createVisualMappings(this.option.target, stateList, supplement);
        let targetColl = visualSolution.createVisualMappings(targetOption, stateList, bound)
        self.targetVisuals = targetColl.mapValues { $0 as Any }
    }

    /**
     * @public
     */
    // getItemSymbol(): string { return null; }
    open func getItemSymbol() -> String? {
        return nil
    }

    /**
     * @return An array of series indices.
     */
    // protected getTargetSeriesIndices(): number[]
    internal func getTargetSeriesIndices() -> [Double] {   // upstream: protected
        let thisOption = self.option as? [String: Any] ?? [:]
        let seriesTargets = thisOption["seriesTargets"] as? [[String: Any]]
        if let seriesTargets = seriesTargets {
            // When seriesTargets is provided, collect all target series indices
            var indices: [Double] = []
            util.each(seriesTargets) { target, _ in
                if let seriesIndex = target["seriesIndex"], !(seriesIndex is NSNull) {
                    indices.append(vmToDouble(seriesIndex))
                }
                else if let seriesId = target["seriesId"], !(seriesId is NSNull) {
                    // Find series by ID
                    var seriesModel: SeriesModel?
                    self.ecModel?.eachSeries { series, _ in
                        if vmEqualId(series.id, seriesId) {
                            seriesModel = series
                        }
                    }
                    if let seriesModel = seriesModel {
                        indices.append(seriesModel.componentIndex)
                    }
                }
            }
            return indices
        }

        let optionSeriesId = thisOption["seriesId"]
        var optionSeriesIndex = thisOption["seriesIndex"]
        if (optionSeriesIndex == nil || optionSeriesIndex is NSNull)
            && (optionSeriesId == nil || optionSeriesId is NSNull) {
            optionSeriesIndex = "all"
        }

        var userOption = QueryReferringUserOption()
        userOption.index = optionSeriesIndex
        userOption.id = optionSeriesId

        let seriesModels = model.queryReferringComponents(
            self.ecModel!,
            "series",
            userOption,
            QueryReferringOpt(useDefault: false, enableAll: true, enableNone: false)
        ).models

        return util.map(seriesModels) { seriesModel, _ in seriesModel.componentIndex }
    }

    /**
     * @public
     */
    // eachTargetSeries<Ctx>(callback, context?)
    open func eachTargetSeries(_ callback: (SeriesModel) -> Void) {
        util.each(self.getTargetSeriesIndices()) { seriesIndex, _ in
            let seriesModel = self.ecModel?.getSeriesByIndex(seriesIndex)
            if let seriesModel = seriesModel {
                callback(seriesModel)
            }
        }
    }

    /**
     * @pubilc
     */
    // isTargetSeries(seriesModel)
    open func isTargetSeries(_ seriesModel: SeriesModel) -> Bool {
        var isTarget = false
        self.eachTargetSeries { modelIn in
            if modelIn === seriesModel { isTarget = true }
        }
        return isTarget
    }

    /**
     * [CAVEAT]
     *  For `visualMap.type: 'continuous'`, the input `value` can only be an `number[]`.
     *  For `visualMap.type: 'piecewise'`, the input `value` can only be an `number | string`.
     *  Otherwise a breaking change will be introduced to `visualMap.formatter: function() {}`.
     *
     * @example
     * this.formatValueText(someVal); // format single numeric value to text.
     * this.formatValueText(someVal, true); // format single category value to text.
     * this.formatValueText([min, max]); // format numeric min-max to text.
     * this.formatValueText([this.dataBound[0], max]); // using data lower bound.
     * this.formatValueText([min, this.dataBound[1]]); // using data upper bound.
     *
     * @param value Real value, or this.dataBound[0 or 1].
     * @param isCategory Only available when value is number.
     * @param edgeSymbols Open-close symbol when value is interval.
     * @protected
     */
    // formatValueText(value, isCategory?, edgeSymbols?): string
    internal func formatValueText(   // upstream: protected
        _ valueIn: Any,
        _ isCategory: Bool? = nil,
        _ edgeSymbolsIn: [String]? = nil
    ) -> String {
        let option = self.option as? [String: Any] ?? [:]
        let precision = vmToDouble(option["precision"])
        let dataBound = self.dataBound
        let formatter = option["formatter"]
        var isMinMax = false
        // edgeSymbols = edgeSymbols || ['<', '>'];
        let edgeSymbols = edgeSymbolsIn ?? ["<", ">"]

        var value = valueIn
        if util.isArray(value) {
            // value = value.slice();
            value = (value as? [Any]) ?? []
            isMinMax = true
        }

        // function toFixed(val)
        func toFixed(_ val: Double) -> String {
            if val == dataBound[0] { return "min" }
            if val == dataBound[1] { return "max" }
            // (+val).toFixed(Math.min(precision, 20))
            let digits = Int(Swift.min(precision, 20))
            return String(format: "%.\(digits)f", val)
        }

        // const textValue = isCategory ? value : (isMinMax ? [toFixed(v[0]), toFixed(v[1])] : toFixed(v))
        let textValue: Any
        if isCategory == true {
            textValue = value   // Value is string when isCategory
        }
        else if isMinMax {
            let arr = value as? [Any] ?? []
            textValue = [toFixed(vmToDouble(arr[0])), toFixed(vmToDouble(arr[1]))]
        }
        else {
            textValue = toFixed(vmToDouble(value))
        }

        if util.isString(formatter) {
            let fmt = formatter as? String ?? ""
            // .replace('{value}', ...) / .replace('{value2}', ...)
            // Note: JS String.replace replaces the FIRST occurrence only; Swift
            // replacingOccurrences replaces all. In practice `{value}`/`{value2}` appear once.
            let tv0 = isMinMax ? (textValue as? [String] ?? [])[0] : (textValue as? String ?? "")
            let tv1 = isMinMax ? (textValue as? [String] ?? [])[1] : (textValue as? String ?? "")
            return fmt
                .replacingOccurrences(of: "{value}", with: tv0)
                .replacingOccurrences(of: "{value2}", with: tv1)
        }
        else if util.isFunction(formatter) {
            // return isMinMax ? formatter(v[0], v[1]) : formatter(v);
            // PORT-TODO: function formatter (LabelFormatter closure carried in the option bag) is
            //   deferred — the closure is not typed off the `[String: Any]` bag. Falls through to the
            //   default text below.
        }

        if isMinMax {
            let arr = value as? [Any] ?? []
            let tv = textValue as? [String] ?? []
            if vmToDouble(arr[0]) == dataBound[0] {
                return edgeSymbols[0] + " " + tv[1]
            }
            else if vmToDouble(arr[1]) == dataBound[1] {
                return edgeSymbols[1] + " " + tv[0]
            }
            else {
                return tv[0] + " - " + tv[1]
            }
        }
        else { // Format single value (includes category case).
            return textValue as? String ?? ""
        }
    }

    /**
     * @protected
     */
    // resetExtent()
    open func resetExtent() {
        let thisOption = self.option as? [String: Any] ?? [:]

        // Can not calculate data extent by data here.
        // Because series and data may be modified in processing stage.
        // So we do not support the feature "auto min/max".

        // const extent = asc([thisOption.min, thisOption.max] as [number, number]);
        let extent = number.asc([vmToDouble(thisOption["min"]), vmToDouble(thisOption["max"])])

        self._dataExtent = extent
    }

    /**
     * PENDING:
     * delete this method if no outer usage.
     *
     * Return  Concrete dimension. If null/undefined is returned, no dimension is used.
     */
    // getDataDimension(data: SeriesData) { ... }   -> commented out upstream; omitted here.

    // getDimension(seriesIndex: number): number
    open func getDimension(_ seriesIndex: Double) -> Double? {
        let thisOption = self.option as? [String: Any] ?? [:]
        let seriesTargets = thisOption["seriesTargets"] as? [[String: Any]]
        if let seriesTargets = seriesTargets {
            let target = util.find(seriesTargets) { target, _ -> Bool in
                let hasIndex = (target["seriesIndex"] != nil && !(target["seriesIndex"] is NSNull))
                    && vmToDouble(target["seriesIndex"]) == seriesIndex
                var hasId = false
                if let tid = target["seriesId"], !(tid is NSNull),
                   let series = self.ecModel?.getSeriesByIndex(seriesIndex) {
                    hasId = vmEqualId(series.id, tid)
                }
                return hasIndex || hasId
            }
            if let target = target {
                return vmToDoubleOpt(target["dimension"])
            }
        }
        return vmToDoubleOpt(thisOption["dimension"])
    }

    // getDataDimensionIndex(data: SeriesData): DimensionIndex
    open func getDataDimensionIndex(_ data: SeriesData) -> DimensionIndex? {
        // const seriesIndex = (data.hostModel as any).seriesIndex;
        let seriesIndex = (data.hostModel as? SeriesModel)?.seriesIndex ?? 0
        let optDim = self.getDimension(seriesIndex)

        if let optDim = optDim {
            return data.getDimensionIndex(optDim)
        }

        let dimNames = data.dimensions
        var i = dimNames.count - 1
        while i >= 0 {
            let dimName = dimNames[i]
            let dimInfo = data.getDimensionInfo(dimName)
            if !(dimInfo.isCalculationCoord ?? false) {
                return dimInfo.storeDimIndex
            }
            i -= 1
        }
        return nil
    }

    // getExtent()
    open func getExtent() -> [Double] {
        // return this._dataExtent.slice() as [number, number];
        return Array(self._dataExtent)
    }

    // completeVisualOption()
    open func completeVisualOption() {

        let ecModel = self.ecModel
        var thisOption = self.option as? [String: Any] ?? [:]
        // const base = { inRange: thisOption.inRange, outOfRange: thisOption.outOfRange };
        var base: [String: Any] = [:]
        if let inRange = thisOption["inRange"] { base["inRange"] = inRange }
        if let outOfRange = thisOption["outOfRange"] { base["outOfRange"] = outOfRange }

        // const target = thisOption.target || (thisOption.target = {});
        var target = thisOption["target"] as? [String: Any] ?? [:]
        // const controller = thisOption.controller || (thisOption.controller = {});
        var controller = thisOption["controller"] as? [String: Any] ?? [:]

        // zrUtil.merge(target, base);       // Do not override
        _ = util.merge(&target, base, false)
        // zrUtil.merge(controller, base);   // Do not override
        _ = util.merge(&controller, base, false)

        let isCategory = self.isCategory()

        // completeSingle.call(this, target);
        completeSingle(&target, thisOption, ecModel, isCategory)
        // completeSingle.call(this, controller);
        completeSingle(&controller, thisOption, ecModel, isCategory)
        // completeInactive.call(this, target, 'inRange', 'outOfRange');
        completeInactive(&target, "inRange", "outOfRange", isCategory)
        // completeInactive.call(this, target, 'outOfRange', 'inRange');   // (commented out upstream)
        // completeController.call(this, controller);
        completeController(&controller, isCategory)

        // Write the (mutated) target/controller back into the option bag (value-type writeback,
        // CONVENTIONS §3 — upstream mutates the shared objects in place).
        thisOption["target"] = target
        thisOption["controller"] = controller
        self.option = thisOption
    }

    // function completeSingle(base: VisualMapOption['target'])
    private func completeSingle(
        _ base: inout [String: Any],
        _ thisOption: [String: Any],
        _ ecModel: GlobalModel?,
        _ isCategory: Bool
    ) {
        // Compatible with ec2 dataRange.color.
        // The mapping order of dataRange.color is: [high value, ..., low value]
        // whereas inRange.color and outOfRange.color is [low value, ..., high value]
        // Notice: ec2 has no inverse.
        if util.isArray(thisOption["color"])
            // If there has been inRange: {symbol: ...}, adding color is a mistake.
            // So adding color only when no inRange defined.
            && base["inRange"] == nil
        {
            // base.inRange = {color: thisOption.color.slice().reverse()};
            let color = (thisOption["color"] as? [Any]) ?? []
            base["inRange"] = ["color": Array(color.reversed())] as [String: Any]
        }

        // Compatible with previous logic, always give a default color, otherwise
        // simple config with no inRange and outOfRange will not work.
        // Originally we use visualMap.color as the default color, but setOption at
        // the second time the default color will be erased. So we change to use
        // constant DEFAULT_COLOR.
        // If user do not want the default color, set inRange: {color: null}.
        // base.inRange = base.inRange || {color: ecModel.get('gradientColor')};
        //   BUGFIX (visual-parity): when a visualMap omits `inRange.color`, upstream falls back to the
        //   global `gradientColor` default so the map still colors (a blue→light gradient). In the slim
        //   driver `self.ecModel` may not be injected when `completeVisualOption` runs during
        //   `optionUpdated`, so `ecModel?.get(...)` returned nil → `inRange.color = nil` → the heatmap
        //   cells + the visualMap bar rendered SOLID BLACK. Fall back to `globalDefault.option.gradientColor`
        //   directly (the same 2-color default) so the default path is robust regardless of ecModel timing.
        if base["inRange"] == nil {
            let gradientColor = ecModel?.get("gradientColor", false)
                ?? globalDefault.option["gradientColor"]
            base["inRange"] = ["color": gradientColor as Any] as [String: Any]
        }
    }

    // function completeInactive(base, stateExist, stateAbsent)
    private func completeInactive(
        _ base: inout [String: Any],
        _ stateExist: VisualState,
        _ stateAbsent: VisualState,
        _ isCategory: Bool
    ) {
        let optExist = base[stateExist] as? [String: Any]
        let optAbsent = base[stateAbsent]

        if let optExist = optExist, optAbsent == nil {
            // optAbsent = base[stateAbsent] = {};
            let newAbsent: [String: Any] = [:]
            // PORT-TODO: visualDefault.get / VisualMapping.isValidType NOT ported (visualDefault +
            //   VisualMapping deferred). The upstream body walks `optExist`, and for each valid visual
            //   type looks up `visualDefault.get(visualType, 'inactive', isCategory)`, assigning it to
            //   `optAbsent[visualType]` (plus the ec2-compat `opacity = [0, 0]` when the type is
            //   'color' and neither `opacity` nor `colorAlpha` is present). DEFERRED — the absent state
            //   is created empty until visualDefault + VisualMapping land.
            _ = optExist
            _ = isCategory
            // each(optExist, function (visualData, visualType) {
            //     if (!VisualMapping.isValidType(visualType)) { return; }
            //     const defa = visualDefault.get(visualType, 'inactive', isCategory);
            //     if (defa != null) {
            //         optAbsent[visualType] = defa;
            //         if (visualType === 'color'
            //             && !optAbsent.hasOwnProperty('opacity')
            //             && !optAbsent.hasOwnProperty('colorAlpha')) {
            //             optAbsent.opacity = [0, 0];
            //         }
            //     }
            // });
            base[stateAbsent] = newAbsent
            _ = newAbsent
        }
    }

    // function completeController(controller?: VisualMapOption['controller'])
    private func completeController(
        _ controller: inout [String: Any],
        _ isCategory: Bool
    ) {
        // const symbolExists = (controller.inRange || {}).symbol || (controller.outOfRange || {}).symbol;
        let inRange = controller["inRange"] as? [String: Any] ?? [:]
        let outOfRange = controller["outOfRange"] as? [String: Any] ?? [:]
        let symbolExists = jsTruthyOr(inRange["symbol"], outOfRange["symbol"])
        // const symbolSizeExists = (controller.inRange || {}).symbolSize || (controller.outOfRange || {}).symbolSize;
        let symbolSizeExists = jsTruthyOr(inRange["symbolSize"], outOfRange["symbolSize"])
        // const inactiveColor = this.get('inactiveColor');
        let inactiveColor = self.get("inactiveColor")
        // const itemSymbol = this.getItemSymbol();
        let itemSymbol = self.getItemSymbol()
        // const defaultSymbol = itemSymbol || 'roundRect';
        let defaultSymbol: String = (itemSymbol != nil && !itemSymbol!.isEmpty) ? itemSymbol! : "roundRect"

        // each(this.stateList, function (state) { ... }, this);
        util.each(self.stateList) { state, _ in
            let itemSize = self.itemSize
            var visuals = controller[state] as? [String: Any]

            // Set inactive color for controller if no other color attr (like colorAlpha) specified.
            if visuals == nil {
                // visuals = controller[state] = { color: isCategory ? inactiveColor : [inactiveColor] };
                visuals = ["color": isCategory ? (inactiveColor as Any) : ([inactiveColor as Any] as [Any])]
            }
            var visualsBag = visuals ?? [:]

            // Consistent symbol and symbolSize if not specified.
            if visualsBag["symbol"] == nil || visualsBag["symbol"] is NSNull {
                // visuals.symbol = symbolExists && zrUtil.clone(symbolExists)
                //     || (isCategory ? defaultSymbol : [defaultSymbol]);
                if let symbolExists = symbolExists {
                    visualsBag["symbol"] = util.clone(symbolExists) as Any
                }
                else {
                    visualsBag["symbol"] = isCategory ? (defaultSymbol as Any) : ([defaultSymbol] as [Any])
                }
            }
            if visualsBag["symbolSize"] == nil || visualsBag["symbolSize"] is NSNull {
                // visuals.symbolSize = symbolSizeExists && zrUtil.clone(symbolSizeExists)
                //     || (isCategory ? itemSize[0] : [itemSize[0], itemSize[0]]);
                if let symbolSizeExists = symbolSizeExists {
                    visualsBag["symbolSize"] = util.clone(symbolSizeExists) as Any
                }
                else {
                    visualsBag["symbolSize"] = isCategory
                        ? (itemSize[0] as Any)
                        : ([itemSize[0], itemSize[0]] as [Any])
                }
            }

            // PORT-TODO: VisualMapping.mapVisual / eachVisual NOT ported (VisualMapping deferred). The
            //   upstream "Filter none" symbol remap and the symbolSize normalization (linearMap into
            //   [0, itemSize[0]]) require `mapVisual` / `eachVisual`, which walk either a plain value or
            //   a per-category object. DEFERRED until VisualMapping lands:
            //
            //   // Filter none
            //   visuals.symbol = mapVisual(visuals.symbol, symbol => symbol === 'none' ? defaultSymbol : symbol);
            //
            //   // Normalize symbolSize
            //   const symbolSize = visuals.symbolSize;
            //   if (symbolSize != null) {
            //       let max = -Infinity;
            //       eachVisual(symbolSize, value => { value > max && (max = value); });
            //       visuals.symbolSize = mapVisual(symbolSize, value =>
            //           linearMap(value, [0, max], [0, itemSize[0]], true));
            //   }
            _ = defaultSymbol

            controller[state] = visualsBag
        }
    }

    // resetItemSize()
    open func resetItemSize() {
        // this.itemSize = [ parseFloat(this.get('itemWidth')), parseFloat(this.get('itemHeight')) ];
        self.itemSize = [
            vmParseFloat(self.get("itemWidth")),
            vmParseFloat(self.get("itemHeight"))
        ]
    }

    // isCategory()
    open func isCategory() -> Bool {
        // return !!this.option.categories;
        let thisOption = self.option as? [String: Any] ?? [:]
        return jsTruthyVM(thisOption["categories"])
    }

    /**
     * @public
     * @abstract
     */
    // setSelected(selected?: any) {}
    open func setSelected(_ selected: Any? = nil) {}

    // getSelected(): any { return null; }
    open func getSelected() -> Any? {
        return nil
    }

    /**
     * @public
     * @abstract
     */
    // getValueState(value: any): VisualMapModel['stateList'][number] { return null; }
    open func getValueState(_ value: Any?) -> VisualState? {
        return nil
    }

    /**
     * FIXME
     * Do not publish to thirt-part-dev temporarily
     * util the interface is stable. (Should it return
     * a function but not visual meta?)
     *
     * @pubilc
     * @abstract
     * @param getColorVisual
     *        params: value, valueState
     *        return: color
     * @return {Object} visualMeta
     *        should includes {stops, outerColors}
     *        outerColor means [colorBeyondMinValue, colorBeyondMaxValue]
     */
    // getVisualMeta(getColorVisual: (value, valueState) => string): VisualMeta { return null; }
    open func getVisualMeta(_ getColorVisual: (Double, VisualState) -> String) -> VisualMeta? {
        return nil
    }

    // static defaultOption: VisualMapOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            "show": true,

            // zlevel: 0,
            "z": 4.0,

            // seriesIndex: 'all',

            "min": 0.0,
            "max": 200.0,

            "left": 0.0,
            "right": NSNull(),
            "top": NSNull(),
            "bottom": 0.0,

            "itemWidth": NSNull(),
            "itemHeight": NSNull(),
            "inverse": false,
            "orient": "vertical",        // 'horizontal' ¦ 'vertical'

            "backgroundColor": "rgba(0,0,0,0)",     // tokens.color.transparent
            "borderColor": "#cfd2d7",               // tokens.color.borderTint  值域边框颜色
            "contentColor": "#5070dd",              // tokens.color.theme[0]
            "inactiveColor": "#cfd2d7",             // tokens.color.disabled
            "borderWidth": 0.0,
            "padding": 15.0,                        // tokens.size.m
                                        // 接受数组分别设定上右下左边距，同css
            "textGap": 10.0,           //
            "precision": 0.0,          // 小数精度，默认为0，无小数点

            "textStyle": [
                "color": "#54555a"      // tokens.color.secondary  值域文字颜色
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default VisualMapModel;  -> `open class VisualMapModel` above.

// -----------------------------------------------------------------------------
// Local helpers (not upstream symbols)
// -----------------------------------------------------------------------------

// Int|Double|NSNumber|String -> Double coercion (CONVENTIONS trap #1: never read a numeric option
// with a bare `as? Double`, which drops bare Int literals stored in the `[String: Any]` bag).
private func vmToDouble(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// Same coercion but preserving JS `null`/`undefined` -> nil (used where upstream keeps the value
// optional, e.g. option.dimension / target.dimension).
private func vmToDoubleOpt(_ v: Any?) -> Double? {
    guard let v = v, !(v is NSNull) else { return nil }
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

// parseFloat(value) — JS `parseFloat(null)` / `parseFloat(undefined)` === NaN.
private func vmParseFloat(_ v: Any?) -> Double {
    guard let v = v, !(v is NSNull) else { return Double.nan }
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// JS truthiness shim for the dynamic option bag (`false`/`0`/`''`/null/undefined are falsy).
private func jsTruthyVM(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}

// JS `a || b` returning a value (used for `symbolExists = a.symbol || b.symbol`): returns the first
// truthy operand, else the second.
private func jsTruthyOr(_ a: Any?, _ b: Any?) -> Any? {
    return jsTruthyVM(a) ? a : b
}

// JS `series.id === target.seriesId` where id is a String and seriesId is OptionId (string | number).
private func vmEqualId(_ id: String, _ query: Any?) -> Bool {
    switch query {
    case let s as String: return id == s
    case let d as Double: return id == String(d) || (Double(id) == d)
    case let i as Int: return id == String(i) || (Double(id) == Double(i))
    case let n as NSNumber: return id == "\(n)" || (Double(id) == n.doubleValue)
    default: return false
    }
}
