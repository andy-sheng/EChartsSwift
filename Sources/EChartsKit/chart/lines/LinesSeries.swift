// Ported from echarts/src/chart/lines/LinesSeries.ts — keep in sync with upstream
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

/* global Uint32Array, Float64Array, Float32Array */

import Foundation
import ZRenderKit

// upstream imports:
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import { concatArray, mergeAll, map, isNumber } from 'zrender/src/core/util';
//       -> ZRenderKit `util` (`util.mergeAll`, `util.map`, `util.isNumber`). `concatArray` is a
//          PORT-NOTE in ZRenderKit.util (typed-array concat) — Swift `a + b` is used inline for the
//          `ContiguousArray` flat-coord buffers in `appendData`.
//   import CoordinateSystem from '../../core/CoordinateSystem';
//       -> core/CoordinateSystemManager (CoordinateSystemManager.get); the __DEV__ "Unknown coordinate
//          system" guard in getInitialData is ported below.
//   import { ... option mixins ... } from '../../util/types';        -> util/types.swift (type-only; the
//       dynamic option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> component/tooltip/tooltipMarkup.swift (createTooltipMarkup); used in formatTooltip below.
//   import { LineDrawModelOption } from '../helper/baseDraw';        -> type-only (the `effect` sub-option
//       shape); DEFERRED (effect is animated, CONVENTIONS §5).
//
// Feature detection:
//   const Uint32Arr = typeof Uint32Array === 'undefined' ? Array : Uint32Array;
//   const Float64Arr = typeof Float64Array === 'undefined' ? Array : Float64Array;
//   -> The Swift-true branch is the typed array (CONVENTIONS §1: Uint32Array -> ContiguousArray<UInt32>,
//      Float64Array -> ContiguousArray<Double>); the `Array` polyfill branch is dropped.

// function compatEc2(seriesOpt: LinesSeriesOption)
//   @deprecated ec2 data format: `data: [[{coord, name}, {coord, name}], ...]`. Rewrites each legacy
//   two-endpoint item into `{ coords: [coord0, coord1], fromName, toName }` merged with both endpoints.
//   Upstream mutates `seriesOpt.data` in place; the Swift option bag is a value type, so this operates on
//   an `inout [String: Any]` and the caller writes it back to `self.option`.
private func compatEc2(_ seriesOpt: inout [String: Any]) {
    // const data = seriesOpt.data;
    let data = seriesOpt["data"]
    // if (data && data[0] && data[0][0] && data[0][0].coord) {
    guard let dataArr = data as? [Any], dataArr.count > 0,
          let first = dataArr[0] as? [Any], first.count > 0,
          let firstEndpoint = first[0] as? [String: Any],
          firstEndpoint["coord"] != nil else {
        return
    }

    // if (__DEV__) { console.warn('Lines data configuration has been changed to { coords:[[1,2],[2,3]] }'); }
    if __DEV__ {
        log.warn("Lines data configuration has been changed to { coords:[[1,2],[2,3]] }")
    }

    // seriesOpt.data = map(data, function (itemOpt) {
    //     const coords = [itemOpt[0].coord, itemOpt[1].coord];
    //     const target = { coords: coords };
    //     if (itemOpt[0].name) { target.fromName = itemOpt[0].name; }
    //     if (itemOpt[1].name) { target.toName = itemOpt[1].name; }
    //     return mergeAll([target, itemOpt[0], itemOpt[1]]);
    // });
    seriesOpt["data"] = util.map(dataArr) { itemOptAny, _ -> Any in
        let itemOpt = (itemOptAny as? [Any]) ?? []
        let ep0 = (itemOpt.count > 0 ? itemOpt[0] : nil) as? [String: Any] ?? [:]
        let ep1 = (itemOpt.count > 1 ? itemOpt[1] : nil) as? [String: Any] ?? [:]
        let coords: [Any] = [ep0["coord"] as Any, ep1["coord"] as Any]
        var target: [String: Any] = ["coords": coords]
        if jsTruthy(ep0["name"]) { target["fromName"] = ep0["name"] }
        if jsTruthy(ep1["name"]) { target["toName"] = ep1["name"] }
        // mergeAll([target, itemOpt[0], itemOpt[1]])
        return util.mergeAll([target, ep0, ep1])
    }
}

// ============================================================================
// The following upstream `interface`/`type` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; kept as documentation only.
// ============================================================================
//
// type LinesCoords = number[][];
// type LinesValue = OptionDataValue | OptionDataValue[];
// interface LinesLineStyleOption<TClr> extends LineStyleOption<TClr> { curveness?: number }
// interface LegacyDataItemOption { coord: number[]; name: string }   // @deprecated
// interface LinesStatesMixin { emphasis?: DefaultStatesMixinEmphasis }
// export interface LinesStateOption<TCbParams = never> {
//     lineStyle?: LinesLineStyleOption<...>
//     label?: SeriesLineLabelOption
// }
// export interface LinesDataItemOption extends LinesStateOption, StatesOptionMixin<...> {
//     name?: string; fromName?: string; toName?: string
//     symbol?: string[] | string; symbolSize?: number[] | number
//     coords?: LinesCoords; value?: LinesValue
//     effect?: LineDrawModelOption['effect']
// }
// export interface LinesSeriesOption extends SeriesOption<...>, LinesStateOption<CallbackDataParams>,
//     SeriesOnCartesianOptionMixin, SeriesOnGeoOptionMixin, SeriesOnPolarOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin, SeriesLargeOptionMixin {
//     type?: 'lines'
//     coordinateSystem?: string
//     symbol?: string[] | string; symbolSize?: number[] | number
//     effect?: LineDrawModelOption['effect']
//     polyline?: boolean     // If lines are polyline (polyline not support curveness, label, animation)
//     clip?: boolean         // Clip overflow (cartesian/polar only)
//     data?: LinesDataItemOption[] | ArrayLike<number>
//         // Flat-array format: Points Count(2) | x | y | x | y | Points Count(3) | x | y | x | y | x | y |
//     dimensions?: DimensionDefinitionLoose | DimensionDefinitionLoose[]
// }

// upstream: class LinesSeriesModel extends SeriesModel<LinesSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2. `open class` to match the port's model style.
open class LinesSeriesModel: SeriesModel {

    // static readonly type = 'series.lines';  /  readonly type = LinesSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.lines" }

    // static readonly dependencies = ['grid', 'polar', 'geo', 'calendar'];
    //   PORT-NOTE (deferred): only grid/cartesian2d is renderable now (polar/geo/calendar coord systems
    //   for lines not ported); the dependency list is kept verbatim so registration/topo order matches.
    open override class var dependencies: [String] {
        return ["grid", "polar", "geo", "calendar"]
    }

    // visualStyleAccessPath = 'lineStyle';   visualDrawType = 'stroke' as const;
    //   Upstream proto fields; the base `SeriesModel` declares these as stored `open var`s
    //   ('itemStyle' / 'fill'), so they are flipped in the `init` override below (same pattern as
    //   ScatterSeries.hasSymbolVisual). LOAD-BEARING: visual/style.ts reads both.

    // private _flatCoords: ArrayLike<number>;         (Float64Array)   -> ContiguousArray<Double>?
    private var _flatCoords: ContiguousArray<Double>?
    // private _flatCoordsOffset: ArrayLike<number>;   (Uint32Array)    -> ContiguousArray<UInt32>?
    private var _flatCoordsOffset: ContiguousArray<UInt32>?

    // init(option: LinesSeriesOption) { ... super.init.apply(this, arguments); }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // proto fields (see note above)
        self.visualStyleAccessPath = "lineStyle"
        self.visualDrawType = "stroke"

        // The real Swift initializer (Model.init) already stored `option` into `self.option` before this
        // lifecycle `init` runs, and upstream mutates `option` === `this.option` in place; so operate on
        // `self.option` and write the mutated bag back before delegating to super.
        var opt = (self.option as? [String: Any]) ?? [:]

        // The input data may be null/undefined.
        // option.data = option.data || [];   (JS: [] is truthy, only nullish falls through)
        if opt["data"] == nil || opt["data"] is NSNull {
            opt["data"] = [Any]()
        }

        // Not using preprocessor because mergeOption may not have series.type
        // compatEc2(option);
        compatEc2(&opt)

        // const result = this._processFlatCoordsArray(option.data);
        let result = self._processFlatCoordsArray(opt["data"])
        // this._flatCoords = result.flatCoords;  this._flatCoordsOffset = result.flatCoordsOffset;
        self._flatCoords = result.flatCoords
        self._flatCoordsOffset = result.flatCoordsOffset
        // if (result.flatCoords) { option.data = new Float32Array(result.count); }
        if result.flatCoords != nil {
            // PORT-NOTE: upstream `new Float32Array(count)` (a zero-filled placeholder, one slot per line —
            //   the real coords live in `_flatCoords`). Modeled as a `[Double]` of zeros so the ported
            //   Source/DataStore pipeline (which expects an array-like) can build `count` line data items.
            opt["data"] = [Double](repeating: 0, count: Int(result.count))
        }

        self.option = opt

        // super.init.apply(this, arguments);
        super.`init`(self.option, parentModel, ecModel)
    }

    // mergeOption(option: LinesSeriesOption) { ... super.mergeOption.apply(this, arguments); }
    open override func mergeOption(_ newSeriesOption: ModelOption?, _ ecModel: GlobalModel?) {
        var opt = (newSeriesOption as? [String: Any]) ?? [:]

        // compatEc2(option);
        compatEc2(&opt)

        // if (option.data) { ... }   (JS truthy — an empty array is truthy, only nullish is skipped)
        if let d = opt["data"], !(d is NSNull) {
            // Only update when have option data to merge.
            // const result = this._processFlatCoordsArray(option.data);
            let result = self._processFlatCoordsArray(opt["data"])
            self._flatCoords = result.flatCoords
            self._flatCoordsOffset = result.flatCoordsOffset
            // if (result.flatCoords) { option.data = new Float32Array(result.count); }
            if result.flatCoords != nil {
                opt["data"] = [Double](repeating: 0, count: Int(result.count))
            }
        }

        // super.mergeOption.apply(this, arguments);
        super.mergeOption(opt, ecModel)
    }

    // appendData(params: Pick<LinesSeriesOption, 'data'>)
    open override func appendData(_ params: SeriesAppendDataParams) {
        var params = params   // mutable copy (upstream reassigns params.data)
        // const result = this._processFlatCoordsArray(params.data);
        let result = self._processFlatCoordsArray(params.data)
        // if (result.flatCoords) {
        if let resultFlatCoords = result.flatCoords {
            // if (!this._flatCoords) {
            if self._flatCoords == nil {
                self._flatCoords = resultFlatCoords
                self._flatCoordsOffset = result.flatCoordsOffset
            }
            else {
                // this._flatCoords = concatArray(this._flatCoords, result.flatCoords);
                //   concatArray -> ContiguousArray `+` (CONVENTIONS §8; util.concatArray is a PORT-NOTE).
                self._flatCoords = self._flatCoords! + resultFlatCoords
                self._flatCoordsOffset = (self._flatCoordsOffset ?? []) + (result.flatCoordsOffset ?? [])
            }
            // params.data = new Float32Array(result.count);
            //   (SeriesAppendDataParams.data is `[Any]`; box the zero-fill placeholder as `[Any]`.)
            params.data = [Any](repeating: 0.0, count: Int(result.count))
        }

        // this.getRawData().appendData(params.data);
        self.getRawData().appendData(params.data)
    }

    // _getCoordsFromItemModel(idx: number)
    open func _getCoordsFromItemModel(_ idx: Int) -> [[Double]] {
        // const itemModel = this.getData().getItemModel<LinesDataItemOption>(idx);
        let itemModel = self.getData().getItemModel(idx)
        // const coords = (itemModel.option instanceof Array) ? itemModel.option : itemModel.getShallow('coords');
        let coords: Any?
        if itemModel.option is [Any] {
            coords = itemModel.option
        }
        else {
            coords = itemModel.getShallow("coords")
        }

        // if (__DEV__) { if (!(coords instanceof Array && coords.length > 0 && coords[0] instanceof Array)) {
        //     throw new Error('Invalid coords ... Lines must have 2d coords array in data item.'); } }
        if __DEV__ {
            let ok = (coords as? [Any]).map { $0.count > 0 && $0[0] is [Any] } ?? false
            if !ok {
                log.error("Invalid coords. Lines must have 2d coords array in data item.")
            }
        }
        return linesCoords2D(coords)
    }

    // getLineCoordsCount(idx: number)
    open func getLineCoordsCount(_ idx: Int) -> Int {
        // if (this._flatCoordsOffset) { return this._flatCoordsOffset[idx * 2 + 1]; }
        if let offsets = self._flatCoordsOffset {
            return Int(offsets[idx * 2 + 1])
        }
        // else { return this._getCoordsFromItemModel(idx).length; }
        else {
            return self._getCoordsFromItemModel(idx).count
        }
    }

    // getLineCoords(idx: number, out: number[][])
    //   Upstream fills the caller-owned `out` scratch (reused across the layout loop) and returns the
    //   point count. Kept as an `inout` fill (a data method, not a math out-param — CONVENTIONS §3 targets
    //   vector/matrix modules); `out[i] = out[i] || []` becomes an append-if-missing.
    open func getLineCoords(_ idx: Int, _ out: inout [[Double]]) -> Int {
        // if (this._flatCoordsOffset) {
        if let offsets = self._flatCoordsOffset, let flat = self._flatCoords {
            // const offset = this._flatCoordsOffset[idx * 2];
            let offset = Int(offsets[idx * 2])
            // const len = this._flatCoordsOffset[idx * 2 + 1];
            let len = Int(offsets[idx * 2 + 1])
            // for (let i = 0; i < len; i++) {
            for i in 0..<len {
                // out[i] = out[i] || [];
                if i >= out.count { out.append([0, 0]) }
                else if out[i].count < 2 { out[i] = [0, 0] }
                // out[i][0] = this._flatCoords[offset + i * 2];
                out[i][0] = flat[offset + i * 2]
                // out[i][1] = this._flatCoords[offset + i * 2 + 1];
                out[i][1] = flat[offset + i * 2 + 1]
            }
            return len
        }
        // else {
        else {
            // const coords = this._getCoordsFromItemModel(idx);
            let coords = self._getCoordsFromItemModel(idx)
            // for (let i = 0; i < coords.length; i++) {
            for i in 0..<coords.count {
                // out[i] = out[i] || [];
                if i >= out.count { out.append([0, 0]) }
                else if out[i].count < 2 { out[i] = [0, 0] }
                // out[i][0] = coords[i][0];  out[i][1] = coords[i][1];
                out[i][0] = coords[i][0]
                out[i][1] = coords[i][1]
            }
            return coords.count
        }
    }

    // _processFlatCoordsArray(data: LinesSeriesOption['data'])
    //   Returns { flatCoordsOffset, flatCoords, count }. The typed-array branch parses the compact numeric
    //   input format: Points Count | x | y | ... per segment.
    open func _processFlatCoordsArray(_ data: Any?)
        -> (flatCoordsOffset: ContiguousArray<UInt32>?, flatCoords: ContiguousArray<Double>?, count: Double) {
        // let startOffset = 0;
        var startOffset = 0
        // if (this._flatCoords) { startOffset = this._flatCoords.length; }
        if let fc = self._flatCoords {
            startOffset = fc.count
        }

        let dataArr = (data as? [Any]) ?? []

        // Stored as a typed array. In format
        // Points Count(2) | x | y | x | y | Points Count(3) | x |  y | x | y | x | y |
        // if (isNumber(data[0])) {
        if dataArr.count > 0 && util.isNumber(dataArr[0]) {
            // const len = data.length;
            let len = dataArr.count
            // Store offset and len of each segment
            // const coordsOffsetAndLenStorage = new Uint32Arr(len);
            var coordsOffsetAndLenStorage = ContiguousArray<UInt32>(repeating: 0, count: len)
            // const coordsStorage = new Float64Arr(len);
            var coordsStorage = ContiguousArray<Double>(repeating: 0, count: len)
            // let coordsCursor = 0;  let offsetCursor = 0;  let dataCount = 0;
            var coordsCursor = 0
            var offsetCursor = 0
            var dataCount = 0
            // for (let i = 0; i < len;) {
            var i = 0
            while i < len {
                // dataCount++;
                dataCount += 1
                // const count = data[i++];
                let count = Int(linesNum(dataArr[i])); i += 1
                // Offset
                // coordsOffsetAndLenStorage[offsetCursor++] = coordsCursor + startOffset;
                coordsOffsetAndLenStorage[offsetCursor] = UInt32(coordsCursor + startOffset); offsetCursor += 1
                // Len
                // coordsOffsetAndLenStorage[offsetCursor++] = count;
                coordsOffsetAndLenStorage[offsetCursor] = UInt32(count); offsetCursor += 1
                // for (let k = 0; k < count; k++) {
                for _ in 0..<count {
                    // const x = data[i++];  const y = data[i++];
                    let x = linesNum(dataArr[i]); i += 1
                    let y = linesNum(dataArr[i]); i += 1
                    // coordsStorage[coordsCursor++] = x;  coordsStorage[coordsCursor++] = y;
                    coordsStorage[coordsCursor] = x; coordsCursor += 1
                    coordsStorage[coordsCursor] = y; coordsCursor += 1

                    // if (i > len) { if (__DEV__) { throw new Error('Invalid data format.'); } }
                    if i > len {
                        if __DEV__ {
                            log.error("Invalid data format.")
                        }
                    }
                }
            }

            // return {
            //     flatCoordsOffset: new Uint32Array(coordsOffsetAndLenStorage.buffer, 0, offsetCursor),
            //     flatCoords: coordsStorage,
            //     count: dataCount
            // };
            //   The `new Uint32Array(buffer, 0, offsetCursor)` is a length-`offsetCursor` view over the
            //   over-allocated storage; modeled as a prefix copy.
            let flatCoordsOffset = ContiguousArray(coordsOffsetAndLenStorage.prefix(offsetCursor))
            return (flatCoordsOffset: flatCoordsOffset, flatCoords: coordsStorage, count: Double(dataCount))
        }

        // return { flatCoordsOffset: null, flatCoords: null, count: data.length };
        return (flatCoordsOffset: nil, flatCoords: nil, count: Double(dataArr.count))
    }

    // getInitialData(option: LinesSeriesOption, ecModel: GlobalModel): SeriesData
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // if (__DEV__) {
        //     const CoordSys = CoordinateSystem.get(option.coordinateSystem);
        //     if (!CoordSys) { throw new Error('Unknown coordinate system ' + option.coordinateSystem); }
        // }
        let opt = option as? [String: Any]
        if __DEV__ {
            let coordSysName = (opt?["coordinateSystem"] as? String) ?? ""
            if CoordinateSystemManager.get(coordSysName) == nil {
                log.error("Unknown coordinate system " + coordSysName)
            }
        }

        // const lineData = new SeriesData(['value'], this);
        let lineData = SeriesData(["value"], self)
        // lineData.hasItemOption = false;
        lineData.hasItemOption = false

        // lineData.initData(option.data, [], function (dataItem, dimName, dataIndex, dimIndex) { ... });
        lineData.initData(opt?["data"] ?? [Any](), [String?](), { [weak lineData] _, dataItem, _, _, dimIndex in
            // dataItem is simply coords
            // if (dataItem instanceof Array) { return NaN; }
            if dataItem is [Any] {
                return Double.nan
            }
            // else {
            else {
                // lineData.hasItemOption = true;
                lineData?.hasItemOption = true
                // const value = dataItem.value;
                let value = (dataItem as? [String: Any])?["value"]
                // if (value != null) { return value instanceof Array ? value[dimIndex] : value; }
                if let value = value, !(value is NSNull) {
                    if let valueArr = value as? [Any] {
                        // dimIndex is a `DimensionIndex` (== Double); index at the Int boundary.
                        return valueArr[Int(dimIndex)]
                    }
                    return value
                }
                // (implicit `return undefined` fallthrough)
                // PORT-NOTE: upstream returns `undefined` here; modeled as NaN (ParsedValue is non-optional
                //   in this port), matching the "no numeric value" intent for a coords-only data item.
                return Double.nan
            }
        })

        // return lineData;
        return lineData
    }

    // formatTooltip(dataIndex: number, multipleSeries: boolean, dataType: string)
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        // const data = this.getData();
        let data = self.getData()
        // const value = this.getRawValue(dataIndex);
        let value = self.getRawValue(dataIndex)

        // const itemModel = data.getItemModel<LinesDataItemOption>(dataIndex);
        let itemModel = data.getItemModel(Int(dataIndex))
        // let itemName = itemModel.get('name');
        var itemName = itemModel.get("name") as? String
        // if (!itemName) {
        if !jsTruthy(itemName) {
            // const fromName = itemModel.get('fromName');
            let fromName = itemModel.get("fromName")
            // const toName = itemModel.get('toName');
            let toName = itemModel.get("toName")
            // const nameArr = [];
            var nameArr: [String] = []
            // fromName != null && nameArr.push(fromName);
            if let fromName = fromName, !(fromName is NSNull) { nameArr.append(linesToStr(fromName)) }
            // toName != null && nameArr.push(toName);
            if let toName = toName, !(toName is NSNull) { nameArr.append(linesToStr(toName)) }
            // itemName = nameArr.join(' > ');
            itemName = nameArr.joined(separator: " > ")
        }
        _ = (multipleSeries, dataType)

        // NOTE: `value` may be `coords` (a 2D-array) — do not display in that case.
        let noValue = value == nil || value is NSNull || (value as? Double).map { $0.isNaN } == true
        return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
            name: itemName, value: value, noValue: noValue))
    }

    // preventIncremental() { return !!this.get(['effect', 'show']); }
    open override func preventIncremental() -> Bool {
        // PORT-NOTE (deferred): `effect` render is ANIMATED and DEFERRED (CONVENTIONS §5). The option flag
        //   is still read faithfully so the (deferred) incremental/effect pipeline sees the right value.
        return jsTruthy(self.get(["effect", "show"]))
    }

    // getProgressive()
    open override func getProgressive() -> Any? {
        // const progressive = this.option.progressive;
        let progressive = (self.option as? [String: Any])?["progressive"]
        // if (progressive == null) { return this.option.large ? 1e4 : this.get('progressive'); }
        if progressive == nil || progressive is NSNull {
            return jsTruthy((self.option as? [String: Any])?["large"]) ? (1e4 as Any) : self.get("progressive")
        }
        // return progressive;
        return progressive
    }

    // getProgressiveThreshold()
    open override func getProgressiveThreshold() -> Double {
        // const progressiveThreshold = this.option.progressiveThreshold;
        let progressiveThreshold = (self.option as? [String: Any])?["progressiveThreshold"]
        // if (progressiveThreshold == null) { return this.option.large ? 2e4 : this.get('progressiveThreshold'); }
        if progressiveThreshold == nil || progressiveThreshold is NSNull {
            return jsTruthy((self.option as? [String: Any])?["large"])
                ? 2e4 : linesNum(self.get("progressiveThreshold"))
        }
        // return progressiveThreshold;
        return linesNum(progressiveThreshold)
    }

    // getZLevelKey()
    open override func getZLevelKey() -> String {
        // const effectModel = this.getModel('effect');
        let effectModel = self.getModel("effect")
        // const trailLength = effectModel.get('trailLength');
        let trailLength = linesNum(effectModel.get("trailLength"))
        // return this.getData().count() > this.getProgressiveThreshold()
        //     ? this.id
        //     : (effectModel.get('show') && trailLength > 0 ? trailLength + '' : '');
        if Double(self.getData().count()) > self.getProgressiveThreshold() {
            return self.id   // PENDING: See `GET_ZLEVEL_KEY_FOR_PROGRESSIVE`
        }
        else {
            return (jsTruthy(effectModel.get("show")) && trailLength > 0) ? linesTrailStr(trailLength) : ""
        }
    }

    // static defaultOption: LinesSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // coordinateSystem defaults to 'geo' upstream, but ONLY cartesian2d is rendered by the ported
            //   static view (polar/geo/calendar are deferred in linesLayout). The default is kept faithful.
            "coordinateSystem": "geo",
            // zlevel: 0,
            "z": 2.0,
            "legendHoverLink": true,

            // Cartesian coordinate system
            //   INT-vs-DOUBLE trap: index defaults MUST be `0.0` (Double), not `0` (Int) — CONVENTIONS.
            "xAxisIndex": 0.0,
            "yAxisIndex": 0.0,

            "symbol": ["none", "none"],
            "symbolSize": [10.0, 10.0],
            // Geo coordinate system
            "geoIndex": 0.0,

            // PORT-NOTE (deferred): `effect` (moving-dot / trail) render is ANIMATED and DEFERRED
            //   (CONVENTIONS §5). The option sub-tree is preserved verbatim for the diffable surface +
            //   the (deferred) effect pipeline.
            "effect": [
                "show": false,
                "period": 4.0,
                "constantSpeed": 0.0,
                "symbol": "circle",
                "symbolSize": 3.0,
                "loop": true,
                "trailLength": 0.2
            ] as [String: Any],

            // `large` IS wired end-to-end: `large` + `largeThreshold` reach `pipelineContext.large` via
            //   Scheduler.updateStreamModes → modelUtil.preparePipelineContext; the linesLayout STAGE
            //   branches on it to pack the `linesPoints` buffer, and LinesView reads the SAME flag to draw
            //   that buffer through chart/helper/LargeLineDraw. Only the PROGRESSIVE half is still deferred.
            "large": false,
            // Available when large is true
            "largeThreshold": 2000.0,

            "polyline": false,

            "clip": true,

            "label": [
                "show": false,
                "position": "end"
                // distance: 5,
                // formatter: label formatter (same as Tooltip.formatter; async callback unsupported)
            ] as [String: Any],

            "lineStyle": [
                "opacity": 0.5
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default LinesSeriesModel;  -> `open class LinesSeriesModel` above.

// ─── JS coercion shims (not upstream symbols) ─────────────────────────────────────────────────────

// Coerce a dynamic option/data value to Double. A bare `as? Double` drops an Int (INT-vs-DOUBLE trap);
//   nil / non-numeric collapse to NaN (mirrors JS `+x`).
private func linesNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// Coerce a dynamic `[[x, y], ...]` coords value (stored as `[[Double]]`, `[[Any]]`, `[Any]` of arrays) to
//   `[[Double]]`. Non-array / short rows are skipped defensively.
private func linesCoords2D(_ v: Any?) -> [[Double]] {
    guard let outer = v as? [Any] else { return [] }
    return outer.map { row -> [Double] in
        if let d = row as? [Double] { return d }
        if let arr = row as? [Any] { return arr.map { linesNum($0) } }
        return []
    }
}

// `nameArr.push(fromName)` — coerce a dynamic name value to its string form.
private func linesToStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let d = v as? Double { return "\(d)" }
    if let i = v as? Int { return "\(i)" }
    if let n = v as? NSNumber { return "\(n)" }
    return ""
}

// `trailLength + ''` — JS number→string. 0.2 -> "0.2"; integral values drop the trailing ".0".
private func linesTrailStr(_ v: Double) -> String {
    if v == v.rounded() && v.isFinite {
        return String(Int(v))
    }
    return "\(v)"
}

// Mirrors JavaScript truthiness for a dynamic `Any?` value (nil / NSNull / false / 0 / NaN / "" are falsy).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
