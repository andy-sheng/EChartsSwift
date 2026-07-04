// Ported from echarts/src/component/visualMap/PiecewiseModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                       -> ZRenderKit `util` (each / map / clone / isObject).
// import VisualMapModel, { VisualMapOption, VisualMeta } from './VisualMapModel';
//   -> VisualMapModel (sibling port, component/visualMap/VisualMapModel.swift). `VisualMapOption` is
//      the dynamic `[String: Any]` option bag (CONVENTIONS §2); `VisualMeta` is the sibling
//      `struct VisualMeta { stops: [Stop]; outerColors: [ColorString]; dimension? }`.
// import VisualMapping, { VisualMappingOption } from '../../visual/VisualMapping';
//   -> VisualMapping (sibling port, visual/VisualMapping.swift): static `findPieceIndex(_:_:_:)`
//      (takes `[VisualMappingPiece]` — see `toMappingPieces`), `listVisualTypes()`, `retrieveVisuals(_:)`.
// import visualDefault from '../../visual/visualDefault';
//   -> PORT-TODO: visual/visualDefault.ts is NOT ported yet (deferred, matching the VisualMapModel
//      base). The `visualDefault.get(...)` completion in `completeVisualOption` is left deferred.
// import {reformIntervals} from '../../util/number';
//   -> `number.reformIntervals` handles `[number.IntervalItem]`. Upstream reforms the REAL piece
//      objects (`Required<InnerVisualPiece>[]`), which carry extra fields (visual/value/text/index)
//      that `number.IntervalItem` can not hold. So the reform is re-implemented locally over the
//      `InnerVisualPiece` dicts (see `reformIntervals(_:)`), mirroring `number.reformIntervals`
//      line-for-line. PORT-TODO: keep in sync with util/number.swift#reformIntervals.
// import { VisualOptionPiecewise, BuiltinVisualProperty } from '../../util/types';  -> (type-only).
// import { Dictionary } from 'zrender/src/core/types';                    -> Dictionary<T> = [String: T].
// import { inheritDefaultOption } from '../../util/component';            -> `component.inheritDefaultOption`.
//
// PORT-TODO (sibling-base coupling): this model `extends VisualMapModel`. Members provided by the
//   sibling base and referenced here exactly as upstream:
//     - `resetExtent()`, `getExtent() -> [Double]`
//     - `resetVisual(_ supplementVisualOption: @escaping (VisualMapModel, [String: Any], String) -> Void)`
//        (callback receives (model, mappingOption-by-value, state); writes are no-ops until the base's
//         deferred visualSolution.createVisualMappings lands)
//     - `formatValueText(_ value: Any, _ isCategory: Bool?, _ edgeSymbols: [String]?) -> String`
//     - `eachTargetSeries(_ callback: (SeriesModel) -> Void)`
//     - `getDataDimensionIndex(_ data: SeriesData) -> DimensionIndex?`
//     - `isCategory() -> Bool`, `stateList: [VisualState]` (= ["inRange","outOfRange"])
//     - `getItemSymbol() -> String?` (overridden below)
//   Abstract base signatures overridden below (real sibling VisualMapModel.swift):
//     - `setSelected(_ selected: Any?)`
//     - `getValueState(_ value: Any?) -> VisualState?`   (VisualState = String; override narrows to non-optional)
//     - `getVisualMeta(_ getColorVisual: (Double, VisualState) -> String) -> VisualMeta?`
//   `findTargetDataIndices` is subclass-only (different per subclass) -> `open func` (not `override`).

// TODO: use `relationExpression.ts` instead
// interface VisualPiece extends VisualOptionPiecewise { min?/max?/lt?/gt?/lte?/gte?/value?/label? }
//   -> the user `pieces[i]` bag stays `[String: Any]`.

// type VisualState = VisualMapModel['stateList'][number];              -> String.
// type InnerVisualPiece = VisualMappingOption['pieceList'][number];   -> [String: Any]
//   ({ text?, index?, value?, interval?: [Double,Double], close?: [Double,Double], visual? }).

/**
 * Order Rule:
 *
 * option.categories / option.pieces / option.text / option.selected:
 *     If !option.inverse,
 *     Order when vertical: ['top', ..., 'bottom'].
 *     Order when horizontal: ['left', ..., 'right'].
 *     If option.inverse, the meaning of
 *     the order should be reversed.
 *
 * this._pieceList:
 *     The order is always [low, ..., high].
 *
 * Mapping from location to low-high:
 *     If !option.inverse
 *     When vertical, top is high.
 *     When horizontal, right is high.
 *     If option.inverse, reverse.
 */

// class PiecewiseModel extends VisualMapModel<PiecewiseVisualMapOption>
//   -> generic `Ops` dropped per CONVENTIONS §2 (dynamic option bag).
open class PiecewiseModel: VisualMapModel {

    // static type = 'visualMap.piecewise' as const;
    // type = PiecewiseModel.type;
    public override class var type: ComponentFullType { return "visualMap.piecewise" }

    /**
     * The order is always [low, ..., high].
     * [{text: string, interval: Array.<number>}, ...]
     */
    // private _pieceList: InnerVisualPiece[] = [];
    private var _pieceList: [[String: Any]] = []

    // private _mode: 'pieces' | 'categories' | 'splitNumber';
    private var _mode: String = ""

    // optionUpdated(newOption: PiecewiseVisualMapOption, isInit?: boolean)
    open override func optionUpdated(_ newOption: ModelOption?, _ isInit: Bool) {
        // super.optionUpdated.apply(this, arguments as any);
        super.optionUpdated(newOption, isInit)

        // this.resetExtent();
        self.resetExtent()

        // const mode = this._mode = this._determineMode();
        let mode = self._determineMode()
        self._mode = mode

        // this._pieceList = [];
        // resetMethods[this._mode].call(this, this._pieceList);
        var outPieceList: [[String: Any]] = []
        switch self._mode {
        case "splitNumber": self.resetMethodSplitNumber(&outPieceList)
        case "categories": self.resetMethodCategories(&outPieceList)
        case "pieces": self.resetMethodPieces(&outPieceList)
        default: break
        }
        self._pieceList = outPieceList

        // this._resetSelected(newOption, isInit);
        self._resetSelected(newOption, isInit)

        // const categories = this.option.categories;
        let categories = (self.option as? [String: Any])?["categories"]

        // this.resetVisual(function (mappingOption, state) {
        // (base callback shape is `(this, mappingOption, state) -> Void`; first param is the model.)
        self.resetVisual { _, mappingOption, state in
            // if (mode === 'categories') {
            if mode == "categories" {
                // mappingOption.mappingMethod = 'category';
                mappingOption["mappingMethod"] = "category"
                // mappingOption.categories = zrUtil.clone(categories);
                if let categories = categories {
                    mappingOption["categories"] = util.clone(categories) as Any
                }
            }
            else {
                // mappingOption.dataExtent = this.getExtent();
                mappingOption["dataExtent"] = self.getExtent()
                // mappingOption.mappingMethod = 'piecewise';
                mappingOption["mappingMethod"] = "piecewise"
                // mappingOption.pieceList = zrUtil.map(this._pieceList, function (piece) {
                mappingOption["pieceList"] = util.map(self._pieceList) { pieceIn, _ in
                    // piece = zrUtil.clone(piece);
                    var piece = util.clone(pieceIn)
                    // if (state !== 'inRange') { piece.visual = null; }
                    if state != "inRange" {
                        // FIXME
                        // outOfRange do not support special visual in pieces.
                        piece["visual"] = NSNull()
                    }
                    return piece
                }
            }
        }
    }

    /**
     * @protected
     * @override
     */
    // completeVisualOption()
    open override func completeVisualOption() {
        // Consider this case:
        // visualMap: {
        //      pieces: [{symbol: 'circle', lt: 0}, {symbol: 'rect', gte: 0}]
        // }
        // where no inRange/outOfRange set but only pieces. So we should make
        // default inRange/outOfRange for this case, otherwise visuals that only
        // appear in `pieces` will not be taken into account in visual encoding.

        // const option = this.option;
        let option = (self.option as? [String: Any]) ?? [:]
        // const visualTypesInPieces: {...} = {};
        var visualTypesInPieces: [String: Double] = [:]
        // const visualTypes = VisualMapping.listVisualTypes();
        let visualTypes = VisualMapping.listVisualTypes()
        // const isCategory = this.isCategory();
        let isCategory = self.isCategory()

        // zrUtil.each(option.pieces, function (piece) {
        util.each(option["pieces"] as? [Any]) { pieceAny, _ in
            guard let piece = pieceAny as? [String: Any] else { return }
            // zrUtil.each(visualTypes, function (visualType) {
            util.each(visualTypes) { visualType, _ in
                // if (piece.hasOwnProperty(visualType)) { visualTypesInPieces[visualType] = 1; }
                if piece.index(forKey: visualType) != nil {
                    visualTypesInPieces[visualType] = 1
                }
            }
        }

        // function has(obj, state, visualType) {
        //     return obj && obj[state] && obj[state].hasOwnProperty(visualType);
        // }
        func has(_ obj: [String: Any]?, _ state: String, _ visualType: String) -> Bool {
            guard let obj = obj, let s = obj[state] as? [String: Any] else { return false }
            return s.index(forKey: visualType) != nil
        }

        // zrUtil.each(visualTypesInPieces, function (v, visualType) {
        // PORT-TODO: JS iterates `visualTypesInPieces` in insertion order; Swift dict order is
        //   unspecified. The result set of applied default visuals is order-independent, so this is
        //   safe, but the write order into `option[state]` may differ.
        for (visualType, _) in visualTypesInPieces {
            // let exists = false;
            var exists = false
            // zrUtil.each(this.stateList, function (state) {
            util.each(self.stateList) { state, _ in
                // exists = exists || has(option, state, visualType) || has(option.target, state, visualType);
                exists = exists || has(option, state, visualType)
                    || has(option["target"] as? [String: Any], state, visualType)
            }

            // !exists && zrUtil.each(this.stateList, function (state) {
            if !exists {
                util.each(self.stateList) { state, _ in
                    // (option[state] || (option[state] = {}))[visualType] = visualDefault.get(
                    //     visualType, state === 'inRange' ? 'active' : 'inactive', isCategory);
                    // PORT-TODO: visual/visualDefault.ts is NOT ported (deferred — matching the
                    //   VisualMapModel base). The default inRange/outOfRange visual for pieces-only
                    //   visuals is therefore not filled here yet. When `visualDefault.get(...)` lands:
                    //     var stateOpt = (option[state] as? [String: Any]) ?? [:]
                    //     stateOpt[visualType] = visualDefault.get(
                    //         visualType, state == "inRange" ? "active" : "inactive", isCategory)
                    //     option[state] = stateOpt
                    _ = state
                    _ = isCategory
                }
            }
        }

        self.option = option

        // super.completeVisualOption.apply(this, arguments as any);
        super.completeVisualOption()
    }

    // private _resetSelected(newOption, isInit?)
    private func _resetSelected(_ newOption: ModelOption?, _ isInit: Bool) {
        // const thisOption = this.option;
        var thisOption = (self.option as? [String: Any]) ?? [:]
        // const pieceList = this._pieceList;
        let pieceList = self._pieceList

        // Selected do not merge but all override.
        // const selected = (isInit ? thisOption : newOption).selected || {};
        let selectedSource = (isInit ? (self.option as? [String: Any]) : (newOption as? [String: Any]))
        var selected = (selectedSource?["selected"] as? [String: Any]) ?? [:]
        // thisOption.selected = selected;
        // (deferred write-back until after the loops mutate `selected`.)

        // Consider 'not specified' means true.
        // zrUtil.each(pieceList, function (piece, index) {
        util.each(pieceList) { piece, _ in
            // const key = this.getSelectedMapKey(piece);
            let key = self.getSelectedMapKey(piece)
            // if (!selected.hasOwnProperty(key)) { selected[key] = true; }
            if selected.index(forKey: key) == nil {
                selected[key] = true
            }
        }

        // if (thisOption.selectedMode === 'single') {
        if (thisOption["selectedMode"] as? String) == "single" {
            // Ensure there is only one selected.
            var hasSel = false

            // zrUtil.each(pieceList, function (piece, index) {
            util.each(pieceList) { piece, _ in
                // const key = this.getSelectedMapKey(piece);
                let key = self.getSelectedMapKey(piece)
                // if (selected[key]) {
                if jsTruthyBool(selected[key]) {
                    // hasSel ? (selected[key] = false) : (hasSel = true);
                    if hasSel {
                        selected[key] = false
                    }
                    else {
                        hasSel = true
                    }
                }
            }
        }
        // thisOption.selectedMode === 'multiple', default: all selected.

        thisOption["selected"] = selected
        self.option = thisOption
    }

    /**
     * @public
     */
    // getItemSymbol(): string
    open override func getItemSymbol() -> String? {
        // return this.get('itemSymbol');
        return self.get("itemSymbol") as? String
    }

    /**
     * @public
     */
    // getSelectedMapKey(piece: InnerVisualPiece)
    open func getSelectedMapKey(_ piece: [String: Any]) -> String {
        // return this._mode === 'categories' ? piece.value + '' : piece.index + '';
        return self._mode == "categories"
            ? jsPlusEmpty(piece["value"])
            : jsPlusEmpty(piece["index"])
    }

    /**
     * @public
     */
    // getPieceList(): InnerVisualPiece[]
    open func getPieceList() -> [[String: Any]] {
        // return this._pieceList;
        return self._pieceList
    }

    /**
     * @return {string}
     */
    // private _determineMode()
    private func _determineMode() -> String {
        // const option = this.option;
        let option = (self.option as? [String: Any]) ?? [:]

        // return option.pieces && option.pieces.length > 0
        //     ? 'pieces'
        //     : this.option.categories ? 'categories' : 'splitNumber';
        if let pieces = option["pieces"] as? [Any], pieces.count > 0 {
            return "pieces"
        }
        else if jsTruthyBool(option["categories"]) {
            return "categories"
        }
        return "splitNumber"
    }

    /**
     * @override
     */
    // setSelected(selected: this['option']['selected'])
    open override func setSelected(_ selected: Any?) {
        // this.option.selected = zrUtil.clone(selected);
        guard var opt = self.option as? [String: Any] else { return }
        if let selected = selected {
            opt["selected"] = util.clone(selected) as Any
        }
        else {
            opt["selected"] = NSNull()
        }
        self.option = opt
    }

    /**
     * @override
     */
    // getValueState(value: number): VisualState
    open override func getValueState(_ valueAny: Any?) -> String {
        // (base signature is `value: any`; upstream PiecewiseModel treats it as `number`.)
        let value = asDouble(valueAny)
        // const index = VisualMapping.findPieceIndex(value, this._pieceList);
        // (findPieceIndex takes `[VisualMappingPiece]`; the model holds the dict form — convert.)
        let index = VisualMapping.findPieceIndex(value, self.toMappingPieces(self._pieceList))

        // return index != null
        //     ? (this.option.selected[this.getSelectedMapKey(this._pieceList[index])] ? 'inRange' : 'outOfRange')
        //     : 'outOfRange';
        if let index = index {
            let selected = (self.option as? [String: Any])?["selected"] as? [String: Any] ?? [:]
            let key = self.getSelectedMapKey(self._pieceList[Int(index)])
            return jsTruthyBool(selected[key]) ? "inRange" : "outOfRange"
        }
        return "outOfRange"
    }

    /**
     * @public
     * @param pieceIndex piece index in visualMapModel.getPieceList()
     */
    // findTargetDataIndices(pieceIndex: number)
    // (subclass-only method — not declared on the base, so not an `override`.)
    open func findTargetDataIndices(_ pieceIndex: Double) -> [[String: Any]] {
        // type DataIndices = { seriesId: string; dataIndex: number[] };
        // const result: DataIndices[] = [];
        var result: [[String: Any]] = []
        // const pieceList = this._pieceList;
        // (findPieceIndex takes `[VisualMappingPiece]`; convert once — the model holds the dict form.)
        let pieceList = self.toMappingPieces(self._pieceList)

        // this.eachTargetSeries(function (seriesModel) {
        self.eachTargetSeries { seriesModel in
            // const dataIndices: number[] = [];
            var dataIndices: [Double] = []
            // const data = seriesModel.getData();
            let data = seriesModel.getData()

            // data.each(this.getDataDimensionIndex(data), function (value, dataIndex) {
            // PORT-TODO: base `getDataDimensionIndex` returns `DimensionIndex?`; upstream treats it as
            //   always-present, so force-unwrap here.
            data.each(self.getDataDimensionIndex(data)!) { args in
                let value = asDouble(args[0])
                let dataIndex = asDouble(args[1])
                // Should always base on model pieceList, because it is order sensitive.
                // const pIdx = VisualMapping.findPieceIndex(value, pieceList);
                let pIdx = VisualMapping.findPieceIndex(value, pieceList)
                // pIdx === pieceIndex && dataIndices.push(dataIndex);
                if pIdx != nil && pIdx! == pieceIndex {
                    dataIndices.append(dataIndex)
                }
            }

            // result.push({seriesId: seriesModel.id, dataIndex: dataIndices});
            result.append(["seriesId": seriesModel.id, "dataIndex": dataIndices])
        }

        return result
    }

    /**
     * @private
     * @param piece piece.value or piece.interval is required.
     * @return  Can be Infinity or -Infinity
     */
    // getRepresentValue(piece: InnerVisualPiece)
    open func getRepresentValue(_ piece: [String: Any]) -> Any? {
        // let representValue;
        var representValue: Any?
        // if (this.isCategory()) {
        if self.isCategory() {
            // representValue = piece.value;
            representValue = piece["value"]
        }
        else {
            // if (piece.value != null) {
            if piece["value"] != nil && !(piece["value"] is NSNull) {
                // representValue = piece.value;
                representValue = piece["value"]
            }
            else {
                // const pieceInterval = piece.interval || [];
                let pieceInterval = asDoubleArrayOpt(piece["interval"]) ?? []
                // representValue = (pieceInterval[0] === -Infinity && pieceInterval[1] === Infinity)
                //     ? 0 : (pieceInterval[0] + pieceInterval[1]) / 2;
                if pieceInterval.count >= 2 && pieceInterval[0] == -Double.infinity && pieceInterval[1] == Double.infinity {
                    representValue = 0.0
                }
                else if pieceInterval.count >= 2 {
                    representValue = (pieceInterval[0] + pieceInterval[1]) / 2
                }
                else {
                    // PORT-TODO: JS would produce NaN from `undefined + undefined`; empty interval only
                    //   occurs for a malformed piece.
                    representValue = Double.nan
                }
            }
        }

        return representValue
    }

    // getVisualMeta(getColorVisual): VisualMeta
    open override func getVisualMeta(_ getColorVisual: (Double, VisualState) -> String) -> VisualMeta? {
        // Do not support category. (category axis is ordinal, numerical)
        // if (this.isCategory()) { return; }
        if self.isCategory() {
            return nil
        }

        // const stops: VisualMeta['stops'] = [];
        var stops: [VisualMeta.Stop] = []
        // const outerColors: VisualMeta['outerColors'] = ['', ''];
        var outerColors: [ColorString] = ["", ""]

        // function setStop(interval: [number, number], valueState?) {
        func setStop(_ interval: [Double], _ valueStateIn: VisualState?) {
            // const representValue = visualMapModel.getRepresentValue({ interval }) as number;// Not category
            let representValue = asDouble(self.getRepresentValue(["interval": interval]))
            // if (!valueState) { valueState = visualMapModel.getValueState(representValue); }
            let valueState = valueStateIn ?? self.getValueState(representValue)
            // const color = getColorVisual(representValue, valueState);
            let color = getColorVisual(representValue, valueState)
            // if (interval[0] === -Infinity) { outerColors[0] = color; }
            if interval[0] == -Double.infinity {
                outerColors[0] = color
            }
            // else if (interval[1] === Infinity) { outerColors[1] = color; }
            else if interval[1] == Double.infinity {
                outerColors[1] = color
            }
            else {
                // stops.push({value: interval[0], color}, {value: interval[1], color});
                stops.append(VisualMeta.Stop(value: interval[0], color: color))
                stops.append(VisualMeta.Stop(value: interval[1], color: color))
            }
        }

        // Suplement
        // const pieceList = this._pieceList.slice();
        var pieceList = self._pieceList
        // if (!pieceList.length) {
        if pieceList.isEmpty {
            // pieceList.push({interval: [-Infinity, Infinity]});
            pieceList.append(["interval": [-Double.infinity, Double.infinity]])
        }
        else {
            // let edge = pieceList[0].interval[0];
            var edge = (asDoubleArrayOpt(pieceList[0]["interval"]) ?? [])[0]
            // edge !== -Infinity && pieceList.unshift({interval: [-Infinity, edge]});
            if edge != -Double.infinity {
                pieceList.insert(["interval": [-Double.infinity, edge]], at: 0)
            }
            // edge = pieceList[pieceList.length - 1].interval[1];
            edge = (asDoubleArrayOpt(pieceList[pieceList.count - 1]["interval"]) ?? [])[1]
            // edge !== Infinity && pieceList.push({interval: [edge, Infinity]});
            if edge != Double.infinity {
                pieceList.append(["interval": [edge, Double.infinity]])
            }
        }

        // let curr = -Infinity;
        var curr = -Double.infinity
        // zrUtil.each(pieceList, function (piece) {
        util.each(pieceList) { piece, _ in
            // const interval = piece.interval;
            // if (interval) {
            guard let interval = asDoubleArrayOpt(piece["interval"]) else { return }
            // Fulfill gap.
            // interval[0] > curr && setStop([curr, interval[0]], 'outOfRange');
            if interval[0] > curr {
                setStop([curr, interval[0]], "outOfRange")
            }
            // setStop(interval.slice() as [number, number]);
            setStop(Array(interval), nil)
            // curr = interval[1];
            curr = interval[1]
        }

        // return {stops: stops, outerColors: outerColors};
        return VisualMeta(stops: stops, outerColors: outerColors)
    }

    // static defaultOption = inheritDefaultOption(VisualMapModel.defaultOption, {...})
    public override class var defaultOption: ModelOption? {
        return component.inheritDefaultOption(
            (VisualMapModel.defaultOption as? [String: Any]) ?? [:],
            [
                // PORT-TODO: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
                "selected": NSNull(),
                "minOpen": false,           // Whether include values that smaller than `min`.
                "maxOpen": false,           // Whether include values that bigger than `max`.

                "align": "auto",            // 'auto', 'left', 'right'
                "itemWidth": 20.0,

                "itemHeight": 14.0,

                "itemSymbol": "roundRect",
                "pieces": NSNull(),
                "categories": NSNull(),
                "splitNumber": 5.0,
                "selectedMode": "multiple", // Can be 'multiple' or 'single'.
                "itemGap": 10.0,            // The gap between two items, in px.
                "hoverLink": true           // Enable hover highlight.
            ]
        )
    }

    // =============================================================================================
    // const resetMethods: Dictionary<ResetMethod> & ThisType<PiecewiseModel> = { ... }
    //
    // The `resetMethods` object (keyed by `this._mode`) is ported as three private methods dispatched
    // in `optionUpdated`. Each mutates the `outPieceList` in place (upstream `push`es onto it), so it
    // takes `inout [[String: Any]]`. `this` -> `self`.
    // =============================================================================================

    // splitNumber(outPieceList)
    private func resetMethodSplitNumber(_ outPieceList: inout [[String: Any]]) {
        // const thisOption = this.option;
        var thisOption = (self.option as? [String: Any]) ?? [:]
        // let precision = Math.min(thisOption.precision, 20);
        var precision = Swift.min(asDouble(thisOption["precision"]), 20)
        // const dataExtent = this.getExtent();
        let dataExtent = self.getExtent()
        // let splitNumber = thisOption.splitNumber;
        // splitNumber = Math.max(parseInt(splitNumber as unknown as string, 10), 1);
        let splitNumber = Swift.max(jsParseInt(thisOption["splitNumber"]), 1)
        // thisOption.splitNumber = splitNumber;
        thisOption["splitNumber"] = splitNumber

        // let splitStep = (dataExtent[1] - dataExtent[0]) / splitNumber;
        var splitStep = (dataExtent[1] - dataExtent[0]) / splitNumber
        // Precision auto-adaption
        // while (+splitStep.toFixed(precision) !== splitStep && precision < 5) { precision++; }
        while jsToFixedNumber(splitStep, precision) != splitStep && precision < 5 {
            precision += 1
        }
        // thisOption.precision = precision;
        thisOption["precision"] = precision
        // splitStep = +splitStep.toFixed(precision);
        splitStep = jsToFixedNumber(splitStep, precision)

        self.option = thisOption

        // if (thisOption.minOpen) {
        if jsTruthyBool(thisOption["minOpen"]) {
            // outPieceList.push({ interval: [-Infinity, dataExtent[0]], close: [0, 0] });
            outPieceList.append([
                "interval": [-Double.infinity, dataExtent[0]],
                "close": [0.0, 0.0]
            ])
        }

        // for (let index = 0, curr = dataExtent[0]; index < splitNumber; curr += splitStep, index++) {
        var index = 0
        var curr = dataExtent[0]
        let splitNumberInt = Int(splitNumber)
        while index < splitNumberInt {
            // const max = index === splitNumber - 1 ? dataExtent[1] : (curr + splitStep);
            let maxV = index == splitNumberInt - 1 ? dataExtent[1] : (curr + splitStep)

            // outPieceList.push({ interval: [curr, max], close: [1, 1] });
            outPieceList.append([
                "interval": [curr, maxV],
                "close": [1.0, 1.0]
            ])

            curr += splitStep
            index += 1
        }

        // if (thisOption.maxOpen) {
        if jsTruthyBool(thisOption["maxOpen"]) {
            // outPieceList.push({ interval: [dataExtent[1], Infinity], close: [0, 0] });
            outPieceList.append([
                "interval": [dataExtent[1], Double.infinity],
                "close": [0.0, 0.0]
            ])
        }

        // reformIntervals(outPieceList as Required<InnerVisualPiece>[]);
        outPieceList = self.reformIntervals(outPieceList)

        // zrUtil.each(outPieceList, function (piece, index) {
        for i in 0..<outPieceList.count {
            // piece.index = index;
            outPieceList[i]["index"] = Double(i)
            // piece.text = this.formatValueText(piece.interval);
            outPieceList[i]["text"] = self.formatValueText(outPieceList[i]["interval"] ?? NSNull(), nil, nil)
        }
    }

    // categories(outPieceList)
    private func resetMethodCategories(_ outPieceList: inout [[String: Any]]) {
        // const thisOption = this.option;
        let thisOption = (self.option as? [String: Any]) ?? [:]
        // zrUtil.each(thisOption.categories, function (cate) {
        util.each(thisOption["categories"] as? [Any]) { cate, _ in
            // FIXME category模式也使用pieceList，但在visualMapping中不是使用pieceList。
            // 是否改一致。
            // outPieceList.push({ text: this.formatValueText(cate, true), value: cate });
            outPieceList.append([
                "text": self.formatValueText(cate, true, nil),
                "value": cate
            ])
        }

        // See "Order Rule".
        // normalizeReverse(thisOption, outPieceList);
        outPieceList = self.normalizeReverse(outPieceList)
    }

    // pieces(outPieceList)
    private func resetMethodPieces(_ outPieceList: inout [[String: Any]]) {
        // const thisOption = this.option;
        let thisOption = (self.option as? [String: Any]) ?? [:]

        // zrUtil.each(thisOption.pieces, function (pieceListItem, index) {
        util.each(thisOption["pieces"] as? [Any]) { pieceListItemIn, index in
            // if (!zrUtil.isObject(pieceListItem)) { pieceListItem = {value: pieceListItem}; }
            var pieceListItem: [String: Any]
            if util.isObject(pieceListItemIn) {
                pieceListItem = (pieceListItemIn as? [String: Any]) ?? [:]
            }
            else {
                pieceListItem = ["value": pieceListItemIn]
            }

            // const item: InnerVisualPiece = {text: '', index: index};
            var item: [String: Any] = ["text": "", "index": Double(index)]

            // if (pieceListItem.label != null) { item.text = pieceListItem.label; }
            if let label = pieceListItem["label"], !(label is NSNull) {
                item["text"] = label
            }

            // if (pieceListItem.hasOwnProperty('value')) {
            if pieceListItem.index(forKey: "value") != nil {
                // const value = item.value = pieceListItem.value;
                let value = pieceListItem["value"] ?? NSNull()
                item["value"] = value
                // item.interval = [value, value];
                let v = asDouble(value)
                item["interval"] = [v, v]
                // item.close = [1, 1];
                item["close"] = [1.0, 1.0]
            }
            else {
                // `min` `max` is legacy option.
                // `lt` `gt` `lte` `gte` is recommended.
                // const interval = item.interval = [];
                var interval: [Double?] = [nil, nil]
                // const close = item.close = [0, 0];
                var close: [Double] = [0, 0]

                // const closeList = [1, 0, 1] as const;
                let closeList: [Double] = [1, 0, 1]
                // const infinityList = [-Infinity, Infinity];
                let infinityList: [Double] = [-Double.infinity, Double.infinity]

                // const useMinMax = [];
                var useMinMax: [Bool] = [false, false]
                // for (let lg = 0; lg < 2; lg++) {
                for lg in 0..<2 {
                    // const names = [['gte', 'gt', 'min'], ['lte', 'lt', 'max']][lg];
                    let names = [["gte", "gt", "min"], ["lte", "lt", "max"]][lg]
                    // for (let i = 0; i < 3 && interval[lg] == null; i++) {
                    var i = 0
                    while i < 3 && interval[lg] == nil {
                        // interval[lg] = pieceListItem[names[i]];
                        interval[lg] = asDoubleOpt(pieceListItem[names[i]])
                        // close[lg] = closeList[i];
                        close[lg] = closeList[i]
                        // useMinMax[lg] = i === 2;
                        useMinMax[lg] = (i == 2)
                        i += 1
                    }
                    // interval[lg] == null && (interval[lg] = infinityList[lg]);
                    if interval[lg] == nil {
                        interval[lg] = infinityList[lg]
                    }
                }
                // useMinMax[0] && interval[1] === Infinity && (close[0] = 0);
                if useMinMax[0] && interval[1] == Double.infinity {
                    close[0] = 0
                }
                // useMinMax[1] && interval[0] === -Infinity && (close[1] = 0);
                if useMinMax[1] && interval[0] == -Double.infinity {
                    close[1] = 0
                }

                // if (__DEV__) { if (interval[0] > interval[1]) console.warn(...); }
                // PORT-TODO: __DEV__ warn (illegal piece: lower bound > upper bound) dropped.

                // if (interval[0] === interval[1] && close[0] && close[1]) {
                if interval[0] == interval[1] && close[0] != 0 && close[1] != 0 {
                    // Consider: [{min: 5, max: 5, visual: {...}}, {min: 0, max: 5}],
                    // we use value to lift the priority when min === max
                    // item.value = interval[0];
                    item["value"] = interval[0]!
                }

                item["interval"] = [interval[0]!, interval[1]!]
                item["close"] = close
            }

            // item.visual = VisualMapping.retrieveVisuals(pieceListItem);
            item["visual"] = VisualMapping.retrieveVisuals(pieceListItem)

            // outPieceList.push(item);
            outPieceList.append(item)
        }

        // See "Order Rule".
        // normalizeReverse(thisOption, outPieceList);
        outPieceList = self.normalizeReverse(outPieceList)
        // Only pieces
        // reformIntervals(outPieceList as Required<InnerVisualPiece>[]);
        outPieceList = self.reformIntervals(outPieceList)

        // zrUtil.each(outPieceList, function (piece) {
        for i in 0..<outPieceList.count {
            // const close = piece.close;
            let close = asDoubleArrayOpt(outPieceList[i]["close"]) ?? [0, 0]
            // const edgeSymbols = [['<', '≤'][close[1]], ['>', '≥'][close[0]]];
            let edgeSymbols = [
                ["<", "≤"][Int(close[1])],
                [">", "≥"][Int(close[0])]
            ]
            // piece.text = piece.text || this.formatValueText(
            //     piece.value != null ? piece.value : piece.interval, false, edgeSymbols);
            let curText = outPieceList[i]["text"] as? String ?? ""
            if curText.isEmpty {
                let pieceValue = outPieceList[i]["value"]
                let formatArg: Any = (pieceValue != nil && !(pieceValue is NSNull))
                    ? pieceValue!
                    : (outPieceList[i]["interval"] ?? NSNull())
                outPieceList[i]["text"] = self.formatValueText(formatArg, false, edgeSymbols)
            }
        }
    }

    // function normalizeReverse(thisOption, pieceList)
    //   -> private method (reads self.option; upstream reads the passed `thisOption`, === this.option).
    private func normalizeReverse(_ pieceList: [[String: Any]]) -> [[String: Any]] {
        let thisOption = (self.option as? [String: Any]) ?? [:]
        // const inverse = thisOption.inverse;
        let inverse = jsTruthyBool(thisOption["inverse"])
        var pieceList = pieceList
        // if (thisOption.orient === 'vertical' ? !inverse : inverse) { pieceList.reverse(); }
        if ((thisOption["orient"] as? String) == "vertical") ? !inverse : inverse {
            pieceList.reverse()
        }
        return pieceList
    }

    // Local re-implementation of `number.reformIntervals` over `InnerVisualPiece` dicts (so the extra
    // piece fields travel with their interval). Mirrors util/number.swift#reformIntervals line-for-line.
    // PORT-TODO: keep in sync with util/number.swift#reformIntervals.
    private func reformIntervals(_ listIn: [[String: Any]]) -> [[String: Any]] {
        func iv(_ p: [String: Any]) -> [Double] { return asDoubleArrayOpt(p["interval"]) ?? [0, 0] }
        func cl(_ p: [String: Any]) -> [Double] { return asDoubleArrayOpt(p["close"]) ?? [0, 0] }

        // function littleThan(a, b, lg) { ... }
        func littleThan(_ a: [String: Any], _ b: [String: Any], _ lg: Int) -> Bool {
            let ai = iv(a); let bi = iv(b)
            let ac = cl(a); let bc = cl(b)
            return ai[lg] < bi[lg]
                || (
                    ai[lg] == bi[lg]
                    && (
                        (ac[lg] - bc[lg] == (lg == 0 ? 1 : -1))
                        || (lg == 0 && littleThan(a, b, 1))
                    )
                )
        }

        var list = listIn
        // list.sort(function (a, b) { return littleThan(a, b, 0) ? -1 : 1; });
        list.sort { a, b in littleThan(a, b, 0) }

        // let curr = -Infinity; let currClose = 1;
        var curr = -Double.infinity
        var currClose: Double = 1
        var i = 0
        while i < list.count {
            var interval = iv(list[i])
            var close = cl(list[i])
            for lg in 0..<2 {
                // if (list[i].interval[lg] <= curr) {
                if interval[lg] <= curr {
                    // list[i].interval[lg] = curr;
                    interval[lg] = curr
                    // list[i].close[lg] = lg ? 1 : 1 - currClose;
                    close[lg] = (lg == 0 ? 1 - currClose : 1)
                }
                // curr = list[i].interval[lg]; currClose = list[i].close[lg];
                curr = interval[lg]
                currClose = close[lg]
            }
            list[i]["interval"] = interval
            list[i]["close"] = close

            // number.swift: remove the degenerate zero-width interval when it is NOT both-closed
            //   (`close[0] * close[1] != 1`).
            if interval[0] == interval[1] && close[0] * close[1] != 1 {
                list.remove(at: i)
            }
            else {
                i += 1
            }
        }

        return list
    }

    // Convert the model's dict-form pieces (`InnerVisualPiece` = [String: Any]) to the typed
    // `[VisualMappingPiece]` that `VisualMapping.findPieceIndex` consumes. Mirrors the dict->piece
    // mapping in `VisualMappingOption.init(_ bag:)` (visual/VisualMapping.swift). Not upstream: the
    // TS `InnerVisualPiece` and `VisualMappingPiece` are the same shape, so no conversion is needed there.
    private func toMappingPieces(_ list: [[String: Any]]) -> [VisualMappingPiece] {
        return list.map { d -> VisualMappingPiece in
            var p = VisualMappingPiece()
            p.value = d["value"]
            p.interval = asDoubleArrayOpt(d["interval"])
            p.close = asDoubleArrayOpt(d["close"])
            p.text = d["text"] as? String
            p.visual = d["visual"] as? [String: Any]
            if let idx = d["index"] { p.index = asDouble(idx) }
            return p
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Local coercion / JS-op helpers (not upstream). Reproduce numeric reads from the Int-boxed
// `[String: Any]` option bag (CONVENTIONS numeric-read trap) and JS operators (`x + ''`, truthiness,
// `parseInt`, `Number.prototype.toFixed`). Same shape as sibling chart files.
// ---------------------------------------------------------------------------------------------
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

// Optional number: nil when absent/null/non-numeric (models `x == null`).
private func asDoubleOpt(_ v: Any?) -> Double? {
    if v == nil || v is NSNull { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return nil
}

// Coerce a `number[]`-shaped option slot; nil when absent/null/non-array (models `x == null`).
private func asDoubleArrayOpt(_ v: Any?) -> [Double]? {
    if v == nil || v is NSNull { return nil }
    if let arr = v as? [Double] { return arr }
    if let arr = v as? [Any] { return arr.map { asDouble($0) } }
    return nil
}

// JS `x + ''` (String coercion) for the map-key. Numbers stringify without a trailing `.0`.
private func jsPlusEmpty(_ v: Any?) -> String {
    guard let v = v, !(v is NSNull) else { return v == nil ? "undefined" : "null" }
    if let d = v as? Double {
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    }
    if let i = v as? Int { return String(i) }
    if let b = v as? Bool { return b ? "true" : "false" }
    if let s = v as? String { return s }
    return String(describing: v)
}

// JS truthiness of a bag value (used for `if (selected[key])`, `option.minOpen`, `thisOption.inverse`).
private func jsTruthyBool(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { _ = a; return true }   // arrays/objects are truthy
    return true
}

// JS `Math.max(parseInt(x, 10), 1)`-style parseInt: truncate toward zero (NaN -> NaN).
private func jsParseInt(_ v: Any?) -> Double {
    let d = asDouble(v)
    if d.isNaN { return Double.nan }
    return d.rounded(.towardZero)
}

// JS `+x.toFixed(p)`: round to `p` decimals (as fixed-point) and parse back to a number.
// PORT-TODO: `Number.prototype.toFixed` rounding (round-half-to-even-ish, implementation-defined)
//   is approximated by `%.*f` (round-half-away). Used only for the precision auto-adaption loop.
private func jsToFixedNumber(_ x: Double, _ p: Double) -> Double {
    let digits = Swift.max(0, Int(p))
    let s = String(format: "%.\(digits)f", x)
    return Double(s) ?? Double.nan
}

// export default PiecewiseModel;  -> `open class PiecewiseModel` above.
