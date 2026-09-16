// Ported from echarts/src/chart/themeRiver/ThemeRiverSeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import prepareSeriesDataSchema from '../../data/helper/createDimensions';
//       -> `createDimensions.prepareSeriesDataSchema` (data/helper/createDimensions.swift).
//   import {getDimensionTypeByAxis} from '../../data/helper/dimensionHelper';
//       -> `getDimensionTypeByAxis` (data/helper/dimensionHelper.swift).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit.util (+ `createHashMap`/`HashMap` shim, util/modelUtil.swift).
//   import {groupData, SINGLE_REFERRING} from '../../util/model';    -> `model.groupData` / `model.SINGLE_REFERRING` (util/modelUtil.swift).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> visual/LegendVisualProvider.swift (ported). Wired in `init` (self.legendVisualProvider = LegendVisualProvider(...)).
//   import { ... } from '../../util/types';                          -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2. The interface/type declarations
//       (ThemeRiverSeriesLabelOption, ThemerRiverDataItem, ThemeRiverStatesMixin, ThemeRiverStateOption,
//       ThemeRiverSeriesOption, …) describe the option tree — kept as documentation only, no Swift types emitted.
//   import SingleAxis from '../../coord/single/SingleAxis';
//       -> coord/single/SingleAxis.swift (ported); `getAxisTooltipData` still types `baseAxis` loosely as `Any?`.
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import Single from '../../coord/single/Single';
//       -> coord/single/Single.swift (the coord-sys master, ported);
//          `coordinateSystem` uses the inherited `Any?` slot (model/Series.swift) — cast to `Single` at layout time.
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> component/tooltip/tooltipMarkup.swift (ported); `createTooltipMarkup` used below.

// const DATA_NAME_INDEX = 2;
private let DATA_NAME_INDEX = 2

// export const SERIES_TYPE_THEME_RIVER = 'themeRiver';
public let SERIES_TYPE_THEME_RIVER = "themeRiver"

// upstream: class ThemeRiverSeriesModel extends SeriesModel<ThemeRiverSeriesOption>
open class ThemeRiverSeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_THEME_RIVER;
    // readonly type = ThemeRiverSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_THEME_RIVER }

    // static readonly dependencies = ['singleAxis'];
    open override class var dependencies: [String] { return ["singleAxis"] }

    // nameMap: zrUtil.HashMap<number, string>;
    //   zrender `HashMap<VALUE, KEY>` -> value = number (Double), key = string; modeled with the
    //   `HashMap<V>` shim (util/modelUtil.swift, string-keyed). Reassigned in `getInitialData`.
    public var nameMap: HashMap<Double> = createHashMap()

    // coordinateSystem: Single;
    //   upstream types `coordinateSystem: Single`; coord/single/Single.swift is ported, but the
    //   inherited `open var coordinateSystem: Any?` slot (model/Series.swift) is used unchanged here and cast
    //   to `Single` in themeRiverLayout.

    /**
     * @override
     */
    // init(option: ThemeRiverSeriesOption) { super.init.apply(this, arguments); ... }
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // eslint-disable-next-line
        // super.init.apply(this, arguments as any);
        super.`init`(option, parentModel, ecModel)

        // Enable legend selection for each DATA ITEM (themeRiver legend entries are layer names). Use
        //   functions (not direct data refs) because the data reference may change.
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getData() },
            { [unowned self] in self.getRawData() }
        )
    }

    /**
     * If there is no value of a certain point in the time for some event,set it value to 0.
     *
     * @param {Array} data  initial data in the option
     * @return {Array}
     */
    // fixData(data: ThemeRiverSeriesOption['data'])
    //   `data` is `ThemerRiverDataItem[]` = `[[date, value, name], …]` — each item is `[Any]`.
    //   Upstream mutates `data` in place (pushes filler items) and returns it; here the value-type
    //   `[[Any]]` is a mutable local, mutated then returned (CONVENTIONS §3).
    open func fixData(_ dataIn: [[Any]]) -> [[Any]] {
        var data = dataIn
        // let rawDataLength = data.length;
        var rawDataLength = data.count
        /**
         * Make sure every layer data get the same keys.
         * The value index tells which layer has visited.
         * {
         *  2014/01/01: -1
         * }
         */
        // const timeValueKeys: Dictionary<number> = {};
        //   Insertion order matters (`for (const timeValue in timeValueKeys)` below walks keys in
        //   insertion order), so a plain `[String: Double]` is paired with an ordered key list.
        var timeValueKeys: [String: Double] = [:]
        var timeValueKeyOrder: [String] = []

        // grouped data by name
        // const groupResult = groupData(data, function (item) {
        //     if (!timeValueKeys.hasOwnProperty(item[0] + '')) { timeValueKeys[item[0] + ''] = -1; }
        //     return item[2];
        // });
        let groupResult = model.groupData(data) { (item: [Any]) -> String in
            let timeKey = trToString(item[0])
            if timeValueKeys[timeKey] == nil {
                timeValueKeys[timeKey] = -1
                timeValueKeyOrder.append(timeKey)
            }
            return trToString(item[2])
        }
        // const layerData: {name: string, dataList: ThemerRiverDataItem[]}[] = [];
        var layerData: [(name: String, dataList: [[Any]])] = []
        // groupResult.buckets.each(function (items, key) { layerData.push({ name: key, dataList: items }); });
        groupResult.buckets.each { items, key in
            layerData.append((name: key, dataList: items))
        }
        // const layerNum = layerData.length;
        let layerNum = layerData.count

        // for (let k = 0; k < layerNum; ++k) {
        for k in 0..<layerNum {
            // const name = layerData[k].name;
            let name = layerData[k].name
            // for (let j = 0; j < layerData[k].dataList.length; ++j) {
            for j in 0..<layerData[k].dataList.count {
                // const timeValue = layerData[k].dataList[j][0] + '';
                let timeValue = trToString(layerData[k].dataList[j][0])
                // timeValueKeys[timeValue] = k;
                timeValueKeys[timeValue] = Double(k)
            }

            // for (const timeValue in timeValueKeys) {
            for timeValue in timeValueKeyOrder {
                // if (timeValueKeys.hasOwnProperty(timeValue) && timeValueKeys[timeValue] !== k) {
                if let tvk = timeValueKeys[timeValue], tvk != Double(k) {
                    // timeValueKeys[timeValue] = k;
                    timeValueKeys[timeValue] = Double(k)
                    // data[rawDataLength] = [timeValue, 0, name];
                    if rawDataLength < data.count {
                        data[rawDataLength] = [timeValue, 0.0, name]
                    }
                    else {
                        data.append([timeValue, 0.0, name])
                    }
                    // rawDataLength++;
                    rawDataLength += 1
                }
            }

        }
        // return data;
        return data
    }

    /**
     * @override
     * @param  option  the initial option that user gave
     * @param  ecModel  the model object for themeRiver option
     */
    // getInitialData(option: ThemeRiverSeriesOption, ecModel: GlobalModel): SeriesData
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // const singleAxisModel = this.getReferringComponents('singleAxis', SINGLE_REFERRING).models[0];
        let singleAxisModel = self.getReferringComponents("singleAxis", model.SINGLE_REFERRING).models.first

        // const axisType = singleAxisModel.get('type');
        let axisType = singleAxisModel?.get("type") as? String

        // filter the data item with the value of label is undefined
        // const filterData = zrUtil.filter(option.data, function (dataItem) { return dataItem[2] !== undefined; });
        let optionData: [[Any]] = (opt?["data"] as? [Any])?.compactMap { $0 as? [Any] } ?? []
        let filterData: [[Any]] = optionData.filter { dataItem in
            // dataItem[2] !== undefined
            return dataItem.count > DATA_NAME_INDEX && !(dataItem[DATA_NAME_INDEX] is NSNull)
        }

        // ??? TODO design a stage to transfer data for themeRiver and lines?
        // const data = this.fixData(filterData || []);
        let data = self.fixData(filterData)
        // const nameList = [];
        var nameList: [Any] = []
        // const nameMap = this.nameMap = zrUtil.createHashMap();
        let nameMap: HashMap<Double> = createHashMap()
        self.nameMap = nameMap
        // let count = 0;
        var count: Double = 0

        // for (let i = 0; i < data.length; ++i) {
        for i in 0..<data.count {
            // nameList.push(data[i][DATA_NAME_INDEX]);
            nameList.append(data[i][DATA_NAME_INDEX])
            // if (!nameMap.get(data[i][DATA_NAME_INDEX] as string)) {
            let nameKey = data[i][DATA_NAME_INDEX]
            // JS `!nameMap.get(...)`: absent (nil) OR the falsy `0` both re-enter. The first inserted
            //   name maps to `0` (falsy), so upstream re-sets it once; harmless (same value). Model the
            //   nil-or-zero re-entry faithfully.
            let existing = nameMap.get(nameKey)
            if existing == nil || existing == 0 {
                // nameMap.set(data[i][DATA_NAME_INDEX] as string, count);
                nameMap.set(nameKey, count)
                // count++;
                count += 1
            }
        }

        // const { dimensions } = prepareSeriesDataSchema(data, { coordDimensions, dimensionsDefine, encodeDefine });
        var timeDimDef = DimensionDefinition()
        timeDimDef.name = "time"
        timeDimDef.type = getDimensionTypeByAxis(axisType ?? "")
        var valueDimDef = DimensionDefinition()
        valueDimDef.name = "value"
        valueDimDef.type = .float
        var nameDimDef = DimensionDefinition()
        nameDimDef.name = "name"
        nameDimDef.type = .ordinal

        var schemaOpt = PrepareSeriesDataSchemaParams(
            coordDimensions: ["single"] as [CoordDimensionDefinitionLoose],
            dimensionsDefine: [timeDimDef, valueDimDef, nameDimDef] as [DimensionDefinitionLoose]
        )
        // encodeDefine: { single: 0, value: 1, itemName: 2 }
        //   INT-vs-DOUBLE trap: createDimensions reads each index via `as? DimensionIndex` (== Double),
        //   which returns nil on a bare Int literal and silently drops the encode. Store as Double.
        schemaOpt.encodeDefine = [
            "single": 0.0,
            "value": 1.0,
            "itemName": 2.0
        ] as [String: Any]
        // upstream feeds the ThemerRiverDataItem[] straight in; the [[Any]] rows are the OptionSourceData.
        let dimensions = createDimensions.prepareSeriesDataSchema(data.map { $0 as Any }, schemaOpt).dimensions

        // const list = new SeriesData(dimensions, this);
        let list = SeriesData(dimensions, self)
        // list.initData(data);
        list.initData(data.map { $0 as Any })

        // return list;
        return list
    }

    /**
     * The raw data is divided into multiple layers and each layer
     *     has same name.
     */
    // getLayerSeries()
    //   upstream returns `{ name: string, indices: number[] }[]`. Modeled as `[[String: Any]]`
    //   (one dict per layer, keys "name": String / "indices": [Int]) — the shape ThemeRiverView and
    //   themeRiverLayout consume (the view assigns the result straight into `_layersSeries: [[String: Any]]?`).
    open func getLayerSeries() -> [[String: Any]] {
        // const data = this.getData();
        let data = self.getData()
        // const lenCount = data.count();
        let lenCount = data.count()
        // const indexArr = [];
        var indexArr: [Int] = []

        // for (let i = 0; i < lenCount; ++i) { indexArr[i] = i; }
        for i in 0..<lenCount {
            indexArr.append(i)
        }

        // const timeDim = data.mapDimension('single');
        let timeDim = data.mapDimension("single")!

        // data group by name
        // const groupResult = groupData(indexArr, function (index) { return data.get('name', index) as string; });
        let groupResult = model.groupData(indexArr) { (index: Int) -> String in
            return trToString(data.get("name", index))
        }
        // const layerSeries: {name, indices}[] = [];
        var layerSeries: [[String: Any]] = []
        // groupResult.buckets.each(function (items, key) {
        //     items.sort(function (index1, index2) { return data.get(timeDim, index1) - data.get(timeDim, index2); });
        //     layerSeries.push({ name: key, indices: items });
        // });
        groupResult.buckets.each { itemsIn, key in
            var items = itemsIn
            items.sort { index1, index2 in
                return trNum(data.get(timeDim, index1)) - trNum(data.get(timeDim, index2)) < 0
            }
            layerSeries.append(["name": key, "indices": items])
        }

        // return layerSeries;
        return layerSeries
    }

    /**
     * Get data indices for show tooltip content
     */
    // getAxisTooltipData(dim: string | string[], value: number, baseAxis: SingleAxis)
    //   `baseAxis: SingleAxis` (coord/single/SingleAxis.swift, ported) typed loosely as `Any?` here.
    open func getAxisTooltipData(_ dimIn: Any?, _ value: Double, _ baseAxis: Any?) -> (dataIndices: [Int], nestestValue: Double?) {
        // if (!zrUtil.isArray(dim)) { dim = dim ? [dim] : []; }
        var dim: [String]
        if !util.isArray(dimIn) {
            if let d = dimIn as? String, !d.isEmpty {
                dim = [d]
            }
            else {
                dim = []
            }
        }
        else {
            dim = (dimIn as? [String]) ?? []
        }

        // const data = this.getData();
        let data = self.getData()
        // const layerSeries = this.getLayerSeries();
        let layerSeries = self.getLayerSeries()
        // const indices = [];
        var indices: [Int] = []
        // const layerNum = layerSeries.length;
        let layerNum = layerSeries.count
        // let nestestValue;
        var nestestValue: Double? = nil

        // for (let i = 0; i < layerNum; ++i) {
        for i in 0..<layerNum {
            // let minDist = Number.MAX_VALUE;
            var minDist = Double.greatestFiniteMagnitude
            // let nearestIdx = -1;
            var nearestIdx = -1
            // const pointNum = layerSeries[i].indices.length;
            let layerIndices = (layerSeries[i]["indices"] as? [Int]) ?? []
            let pointNum = layerIndices.count
            // for (let j = 0; j < pointNum; ++j) {
            for j in 0..<pointNum {
                // const theValue = data.get(dim[0], layerSeries[i].indices[j]) as number;
                let theValue = trNum(data.get(dim[0], layerIndices[j]))
                // const dist = Math.abs(theValue - value);
                let dist = Swift.abs(theValue - value)
                // if (dist <= minDist) {
                if dist <= minDist {
                    nestestValue = theValue
                    minDist = dist
                    nearestIdx = layerIndices[j]
                }
            }
            // indices.push(nearestIdx);
            indices.append(nearestIdx)
        }

        // return {dataIndices: indices, nestestValue: nestestValue};
        return (dataIndices: indices, nestestValue: nestestValue)
    }

    // formatTooltip(dataIndex, multipleSeries, dataType)
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        _ = (multipleSeries, dataType)
        let data = self.getData()
        let name = data.getName(Int(dataIndex))
        let value = data.mapDimension("value").flatMap { data.get($0, Int(dataIndex)) }
        return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(name: name, value: value))
    }

    // static defaultOption: ThemeRiverSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            "colorBy": "data",
            "coordinateSystem": "singleAxis",

            // gap in axis's orthogonal orientation
            "boundaryGap": ["10%", "10%"],

            // legendHoverLink: true,

            "singleAxisIndex": 0.0,

            "animationEasing": "linear",

            "label": [
                "margin": 4.0,
                "show": true,
                "position": "left",
                "fontSize": 11.0
            ] as [String: Any],

            "emphasis": [
                "label": [
                    "show": true
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default ThemeRiverSeriesModel;  -> `open class ThemeRiverSeriesModel` above.

// ─── JS coercion shims (not upstream symbols) ─────────────────────────────────────────────────────

// JS `x + ''` for a ParsedValue / option value of unknown type (used for `item[0] + ''` time keys and
//   `data.get('name', idx) as string`). Mirrors util/modelUtil.swift's private `jsToString`.
private func trToString(_ val: Any?) -> String {
    switch val {
    case nil: return "undefined"
    case is NSNull: return "undefined"
    case let s as String: return s
    case let d as Double:
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    case let i as Int: return String(i)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: val!)
    }
}

// Coerce a ParsedValue (`Any?`) that upstream reads `as number` into a Double. The `[String: Any]`
//   value store may hold Int / Double / NSNumber; a bare `as? Double` drops an Int (INT-vs-DOUBLE trap).
private func trNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}
