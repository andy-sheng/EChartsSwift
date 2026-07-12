// Ported from echarts/src/component/visualMap/ContinuousModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit `util` (util.each / util.isArray / util.retrieve2).
// import VisualMapModel, { VisualMapOption, VisualMeta } from './VisualMapModel';
//   -> VisualMapModel (sibling port, component/visualMap/VisualMapModel.swift). `VisualMapOption`
//      is modeled by the dynamic `[String: Any]` option bag (CONVENTIONS §2); `VisualMeta` is the
//      sibling `struct VisualMeta { stops: [Stop]; outerColors: [ColorString]; dimension? }`.
// import * as numberUtil from '../../util/number';                 -> EChartsKit `number` (number.asc).
// import { VisualMappingOption } from '../../visual/VisualMapping'; -> the `[String: Any]` mapping-option bag.
// import { inheritDefaultOption } from '../../util/component';      -> `component.inheritDefaultOption`.
// import { ItemStyleOption } from '../../util/types';               -> (type-only; the ItemStyle bag stays `[String: Any]`).
// import tokens from '../../visual/tokens';
//   -> PORT-NOTE: visual/tokens.ts is ported (visual/tokens.swift). The `tokens.*` values consumed in
//      `defaultOption` are still inlined verbatim as their resolved constants; could be re-wired.
//        tokens.color.neutral00 = '#fff'
//        tokens.color.shadow    = 'rgba(0,0,0,0.2)'
//
// PORT-NOTE (sibling-base coupling): this model `extends VisualMapModel`. The following members are
//   declared/provided by the sibling `VisualMapModel` base (component/visualMap/VisualMapModel.swift)
//   and are referenced here exactly as upstream:
//     - stored `itemSize: [Double]`
//     - `stateList: [String]` (= ["inRange", "outOfRange"])
//     - `resetExtent()`, `getExtent() -> [Double]`
//     - `resetItemSize()`, `completeVisualOption()`
//     - `resetVisual(_ supplementVisualOption: @escaping (VisualMapModel, [String: Any], String) -> Void)`
//        (callback receives (model, mappingOption-by-value, state); its writes are no-ops until the
//         base's deferred visualSolution.createVisualMappings lands — see the callbacks below)
//     - `eachTargetSeries(_ callback: (SeriesModel) -> Void)`
//     - `getDataDimensionIndex(_ data: SeriesData) -> DimensionIndex?`
//   The abstract base signatures overridden below are (real sibling VisualMapModel.swift):
//     - `setSelected(_ selected: Any?)`
//     - `getSelected() -> Any?`
//     - `getValueState(_ value: Any?) -> VisualState?`   (VisualState = String; override narrows to non-optional)
//     - `getVisualMeta(_ getColorVisual: (Double, VisualState) -> String) -> VisualMeta?`
//   `findTargetDataIndices` is NOT declared on the base — it is a subclass-only method (each subclass
//   has a different signature), so it is `open func` (not `override`) here.

// Constant
// const DEFAULT_BAR_BOUND = [20, 140];
private let DEFAULT_BAR_BOUND: [Double] = [20.0, 140.0]

// type RangeWithAuto = { auto?: 0 | 1 };
//   -> In JS the `auto` flag is attached as a property ON the `range` array object. A Swift `[Double]`
//      can not carry an extra property, so the flag is mirrored by the private `_rangeIsAuto` stored
//      member below (see `_resetRange`). PORT-NOTE: this deviates from upstream's array-property hack.

// type VisualState = VisualMapModel['stateList'][number];   -> String (= "inRange" | "outOfRange").

// class ContinuousModel extends VisualMapModel<ContinuousVisualMapOption>
//   -> generic `Ops` dropped per CONVENTIONS §2 (dynamic option bag).
open class ContinuousModel: VisualMapModel {

    // static type = 'visualMap.continuous' as const;
    // type = ContinuousModel.type;
    public override class var type: ComponentFullType { return "visualMap.continuous" }

    // Mirror of the JS `(range as RangeWithAuto).auto` flag (see `RangeWithAuto` note above).
    private var _rangeIsAuto: Bool = false

    /**
     * @override
     */
    // optionUpdated(newOption: ContinuousVisualMapOption, isInit: boolean)
    open override func optionUpdated(_ newOption: ModelOption?, _ isInit: Bool) {
        // super.optionUpdated.apply(this, arguments as any);
        super.optionUpdated(newOption, isInit)

        // this.resetExtent();
        self.resetExtent()

        // this.resetVisual(function (mappingOption?) {
        //     mappingOption.mappingMethod = 'linear';
        //     mappingOption.dataExtent = this.getExtent();
        // });
        // (base callback shape is `(this, mappingOption, state) -> Void`; first param is the model.)
        self.resetVisual { _, mappingOption, _ in
            mappingOption["mappingMethod"] = "linear"
            mappingOption["dataExtent"] = self.getExtent()
        }

        // this._resetRange();
        self._resetRange()
    }

    /**
     * @protected
     * @override
     */
    // resetItemSize()
    open override func resetItemSize() {
        // super.resetItemSize.apply(this, arguments as any);
        super.resetItemSize()

        // const itemSize = this.itemSize;
        var itemSize = self.itemSize
        // PORT-NOTE: upstream treats `itemSize[i] == null` (missing) the same as `isNaN`. The ported
        //   base `itemSize` is a `[Double]`; a missing element is reproduced by padding with NaN so the
        //   `isNaN` branch applies uniformly.
        while itemSize.count < 2 { itemSize.append(Double.nan) }

        // (itemSize[0] == null || isNaN(itemSize[0])) && (itemSize[0] = DEFAULT_BAR_BOUND[0]);
        if itemSize[0].isNaN { itemSize[0] = DEFAULT_BAR_BOUND[0] }
        // (itemSize[1] == null || isNaN(itemSize[1])) && (itemSize[1] = DEFAULT_BAR_BOUND[1]);
        if itemSize[1].isNaN { itemSize[1] = DEFAULT_BAR_BOUND[1] }

        self.itemSize = itemSize
    }

    /**
     * @private
     */
    // _resetRange()
    func _resetRange() {
        // const dataExtent = this.getExtent();
        let dataExtent = self.getExtent()
        // const range = this.option.range;
        let range = self._optRange()

        // if (!range || (range as RangeWithAuto).auto) {
        if range == nil || self._rangeIsAuto {
            // `range` should always be array (so we don't use other
            // value like 'auto') for user-friend. (consider getOption).
            // (dataExtent as RangeWithAuto).auto = 1;
            self._rangeIsAuto = true
            // this.option.range = dataExtent;
            self._setOptRange(dataExtent)
        }
        // else if (zrUtil.isArray(range)) {
        else if var r = range {
            // if (range[0] > range[1]) { range.reverse(); }
            if r[0] > r[1] {
                r.reverse()
            }
            // range[0] = Math.max(range[0], dataExtent[0]);
            r[0] = Swift.max(r[0], dataExtent[0])
            // range[1] = Math.min(range[1], dataExtent[1]);
            r[1] = Swift.min(r[1], dataExtent[1])
            self._setOptRange(r)
        }
    }

    /**
     * @protected
     * @override
     */
    // completeVisualOption()
    open override func completeVisualOption() {
        // super.completeVisualOption.apply(this, arguments as any);
        super.completeVisualOption()

        // zrUtil.each(this.stateList, function (state) {
        util.each(self.stateList) { state, _ in
            // const symbolSize = this.option.controller[state].symbolSize;
            guard var opt = self.option as? [String: Any],
                  var controller = opt["controller"] as? [String: Any],
                  var stateOpt = controller[state] as? [String: Any] else { return }
            guard var symbolSize = asDoubleArrayOpt(stateOpt["symbolSize"]) else { return }
            // if (symbolSize && symbolSize[0] !== symbolSize[1]) {
            if symbolSize.count >= 2 && symbolSize[0] != symbolSize[1] {
                // symbolSize[0] = symbolSize[1] / 3; // For good looking.
                symbolSize[0] = symbolSize[1] / 3
                stateOpt["symbolSize"] = symbolSize
                controller[state] = stateOpt
                opt["controller"] = controller
                self.option = opt
            }
        }
    }

    /**
     * @override
     */
    // setSelected(selected: number[])
    open override func setSelected(_ selected: Any?) {
        // this.option.range = selected.slice();
        // (base signature is `selected?: any`; upstream ContinuousModel narrows to `number[]`.)
        let selected = asDoubleArrayOpt(selected) ?? []
        self._rangeIsAuto = false
        self._setOptRange(Array(selected))
        // this._resetRange();
        self._resetRange()
    }

    /**
     * @public
     */
    // getSelected(): [number, number]
    // (base returns `any`; return type is `Any?` for override covariance — value is the `[Double]`.)
    open override func getSelected() -> Any? {
        // const dataExtent = this.getExtent();
        let dataExtent = self.getExtent()

        // const dataInterval = numberUtil.asc((this.get('range') || []).slice()) as [number, number];
        var dataInterval = number.asc(asDoubleArrayOpt(self.get("range")) ?? [])

        // Clamp
        // dataInterval[0] > dataExtent[1] && (dataInterval[0] = dataExtent[1]);
        if dataInterval.count > 0 && dataInterval[0] > dataExtent[1] { dataInterval[0] = dataExtent[1] }
        // dataInterval[1] > dataExtent[1] && (dataInterval[1] = dataExtent[1]);
        if dataInterval.count > 1 && dataInterval[1] > dataExtent[1] { dataInterval[1] = dataExtent[1] }
        // dataInterval[0] < dataExtent[0] && (dataInterval[0] = dataExtent[0]);
        if dataInterval.count > 0 && dataInterval[0] < dataExtent[0] { dataInterval[0] = dataExtent[0] }
        // dataInterval[1] < dataExtent[0] && (dataInterval[1] = dataExtent[0]);
        if dataInterval.count > 1 && dataInterval[1] < dataExtent[0] { dataInterval[1] = dataExtent[0] }

        return dataInterval
    }

    /**
     * @override
     */
    // getValueState(value: number): VisualState
    open override func getValueState(_ valueAny: Any?) -> String {
        // (base signature is `value: any`; upstream ContinuousModel treats it as `number`.)
        let value = asDouble(valueAny)
        // const range = this.option.range;
        let range = self._optRange() ?? []
        // const dataExtent = this.getExtent();
        let dataExtent = self.getExtent()
        // const unboundedRange = zrUtil.retrieve2(this.option.unboundedRange, true);
        let unboundedRange = util.retrieve2(self._optBool("unboundedRange"), true) ?? true

        // return (
        //     ((unboundedRange && range[0] <= dataExtent[0]) || range[0] <= value)
        //     && ((unboundedRange && range[1] >= dataExtent[1]) || value <= range[1])
        // ) ? 'inRange' : 'outOfRange';
        return (
            ((unboundedRange && range[0] <= dataExtent[0]) || range[0] <= value)
            && ((unboundedRange && range[1] >= dataExtent[1]) || value <= range[1])
        ) ? "inRange" : "outOfRange"
    }

    // findTargetDataIndices(range: number[])
    // (subclass-only method — not declared on the base, so not an `override`.)
    open func findTargetDataIndices(_ range: [Double]) -> [[String: Any]] {
        // type DataIndices = { seriesId: string; dataIndex: number[] };
        // const result: DataIndices[] = [];
        var result: [[String: Any]] = []

        // this.eachTargetSeries(function (seriesModel) {
        self.eachTargetSeries { seriesModel in
            // const dataIndices: number[] = [];
            var dataIndices: [Double] = []
            // const data = seriesModel.getData();
            let data = seriesModel.getData()

            // data.each(this.getDataDimensionIndex(data), function (value, dataIndex) {
            // POTENTIAL-BUG: base `getDataDimensionIndex` returns `DimensionIndex?`; upstream treats it as
            //   always-present, so force-unwrap here — a nil dim index (e.g. no visualMap dimension
            //   resolvable on the data) would SIGTRAP instead of degrading like JS `undefined`.
            data.each(self.getDataDimensionIndex(data)!) { args in
                let value = asDouble(args[0])
                let dataIndex = asDouble(args[1])
                // range[0] <= value && value <= range[1] && dataIndices.push(dataIndex);
                if range[0] <= value && value <= range[1] {
                    dataIndices.append(dataIndex)
                }
            }

            // result.push({ seriesId: seriesModel.id, dataIndex: dataIndices });
            result.append([
                "seriesId": seriesModel.id,
                "dataIndex": dataIndices
            ])
        }

        return result
    }

    /**
     * @implement
     */
    // getVisualMeta(getColorVisual: (value, valueState) => string)
    open override func getVisualMeta(_ getColorVisual: (Double, VisualState) -> String) -> VisualMeta? {
        // type ColorStop = VisualMeta['stops'][number];
        // const oVals = getColorStopValues(this, 'outOfRange', this.getExtent());
        let oVals = getColorStopValues(self, "outOfRange", self.getExtent())
        // const iVals = getColorStopValues(this, 'inRange', this.option.range.slice());
        let iVals = getColorStopValues(self, "inRange", self._optRange() ?? [])
        // const stops: ColorStop[] = [];
        var stops: [VisualMeta.Stop] = []

        // function setStop(value, valueState) { stops.push({ value, color: getColorVisual(value, valueState) }); }
        func setStop(_ value: Double, _ valueState: VisualState) {
            stops.append(VisualMeta.Stop(
                value: value,
                color: getColorVisual(value, valueState)
            ))
        }

        // Format to: outOfRange -- inRange -- outOfRange.
        var iIdx = 0
        var oIdx = 0
        let iLen = iVals.count
        let oLen = oVals.count

        // for (; oIdx < oLen && (!iVals.length || oVals[oIdx] <= iVals[0]); oIdx++) {
        while oIdx < oLen && (iVals.isEmpty || oVals[oIdx] <= iVals[0]) {
            // If oVal[oIdx] === iVals[iIdx], oVal[oIdx] should be ignored.
            // if (oVals[oIdx] < iVals[iIdx]) { setStop(oVals[oIdx], 'outOfRange'); }
            if iIdx < iLen && oVals[oIdx] < iVals[iIdx] {
                setStop(oVals[oIdx], "outOfRange")
            }
            oIdx += 1
        }
        // for (let first = 1; iIdx < iLen; iIdx++, first = 0) {
        var first = 1
        while iIdx < iLen {
            // If range is full, value beyond min, max will be clamped.
            // make a singularity
            // first && stops.length && setStop(iVals[iIdx], 'outOfRange');
            if first != 0 && !stops.isEmpty {
                setStop(iVals[iIdx], "outOfRange")
            }
            // setStop(iVals[iIdx], 'inRange');
            setStop(iVals[iIdx], "inRange")
            iIdx += 1
            first = 0
        }
        // for (let first = 1; oIdx < oLen; oIdx++) {
        first = 1
        while oIdx < oLen {
            // if (!iVals.length || iVals[iVals.length - 1] < oVals[oIdx]) {
            if iVals.isEmpty || iVals[iVals.count - 1] < oVals[oIdx] {
                // make a singularity
                if first != 0 {
                    // stops.length && setStop(stops[stops.length - 1].value, 'outOfRange');
                    if !stops.isEmpty {
                        setStop(stops[stops.count - 1].value, "outOfRange")
                    }
                    first = 0
                }
                // setStop(oVals[oIdx], 'outOfRange');
                setStop(oVals[oIdx], "outOfRange")
            }
            oIdx += 1
        }

        // const stopsLen = stops.length;
        let stopsLen = stops.count

        // return { stops, outerColors: [...] };
        return VisualMeta(
            stops: stops,
            outerColors: [
                stopsLen != 0 ? stops[0].color : "transparent",
                stopsLen != 0 ? stops[stopsLen - 1].color : "transparent"
            ]
        )
    }

    // static defaultOption = inheritDefaultOption(VisualMapModel.defaultOption, {...})
    public override class var defaultOption: ModelOption? {
        return component.inheritDefaultOption(
            (VisualMapModel.defaultOption as? [String: Any]) ?? [:],
            [
                "align": "auto",           // 'auto', 'left', 'right', 'top', 'bottom'
                "calculable": false,
                "hoverLink": true,
                "realtime": true,

                "handleIcon": "path://M-11.39,9.77h0a3.5,3.5,0,0,1-3.5,3.5h-22a3.5,3.5,0,0,1-3.5-3.5h0a3.5,3.5,0,0,1,3.5-3.5h22A3.5,3.5,0,0,1-11.39,9.77Z",
                "handleSize": "120%",

                "handleStyle": [
                    "borderColor": "#fff",                // tokens.color.neutral00
                    "borderWidth": 1.0
                ] as [String: Any],

                "indicatorIcon": "circle",
                "indicatorSize": "50%",
                "indicatorStyle": [
                    "borderColor": "#fff",                // tokens.color.neutral00
                    "borderWidth": 2.0,
                    "shadowBlur": 2.0,
                    "shadowOffsetX": 1.0,
                    "shadowOffsetY": 1.0,
                    "shadowColor": "rgba(0,0,0,0.2)"      // tokens.color.shadow
                ] as [String: Any]
                // emphasis: {
                //     handleStyle: {
                //         shadowBlur: 3,
                //         shadowOffsetX: 1,
                //         shadowOffsetY: 1,
                //         shadowColor: tokens.color.shadow
                //     }
                // }
            ]
        )
    }

    // ---------------------------------------------------------------------------------------------
    // Private option-bag accessors (not upstream). They coerce the Int-boxed `[String: Any]` option
    // slots to `Double`/`[Double]` per CONVENTIONS numeric-read trap, and mirror JS `this.option.range`
    // read/write. `_rangeIsAuto` above stands in for the JS `.auto` array property.
    // ---------------------------------------------------------------------------------------------

    // this.option.range  (read)
    private func _optRange() -> [Double]? {
        return asDoubleArrayOpt((self.option as? [String: Any])?["range"])
    }

    // this.option.range = value  (write)
    private func _setOptRange(_ value: [Double]) {
        guard var opt = self.option as? [String: Any] else { return }
        opt["range"] = value
        self.option = opt
    }

    // this.option.unboundedRange  (read, as boolean-or-nil for retrieve2)
    private func _optBool(_ key: String) -> Bool? {
        return (self.option as? [String: Any])?[key] as? Bool
    }
}

// function getColorStopValues(visualMapModel, valueState, dataExtent)
private func getColorStopValues(
    _ visualMapModel: ContinuousModel,
    _ valueState: String,
    _ dataExtent: [Double]
) -> [Double] {
    // if (dataExtent[0] === dataExtent[1]) { return dataExtent.slice(); }
    if dataExtent[0] == dataExtent[1] {
        return Array(dataExtent)
    }

    // When using colorHue mapping, it is not linear color any more.
    // Moreover, canvas gradient seems not to be accurate linear.
    // FIXME
    // Should be arbitrary value 100? or based on pixel size?
    // const count = 200;
    let count = 200
    // const step = (dataExtent[1] - dataExtent[0]) / count;
    let step = (dataExtent[1] - dataExtent[0]) / Double(count)

    // let value = dataExtent[0];
    var value = dataExtent[0]
    // const stopValues = [];
    var stopValues: [Double] = []
    // for (let i = 0; i <= count && value < dataExtent[1]; i++) {
    var i = 0
    while i <= count && value < dataExtent[1] {
        stopValues.append(value)
        value += step
        i += 1
    }
    stopValues.append(dataExtent[1])

    return stopValues
}

// ---------------------------------------------------------------------------------------------
// Local numeric coercion helpers (not upstream): reproduce JS numeric reads from the Int-boxed
// `[String: Any]` option bag (CONVENTIONS numeric-read trap). Same shape as the sibling chart files.
// ---------------------------------------------------------------------------------------------
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

// Coerce a `number[]`-shaped option slot; nil when absent/null/non-array (models `x == null`).
private func asDoubleArrayOpt(_ v: Any?) -> [Double]? {
    if v == nil || v is NSNull { return nil }
    if let arr = v as? [Double] { return arr }
    if let arr = v as? [Any] { return arr.map { asDouble($0) } }
    return nil
}

// export default ContinuousModel;  -> `open class ContinuousModel` above.
