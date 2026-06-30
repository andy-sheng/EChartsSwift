// Ported from echarts/src/data/helper/dimensionHelper.ts — keep in sync with upstream
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

// import {each, createHashMap, assert, map} from 'zrender/src/core/util';   -> ZRenderKit.util.{each, assert, map}
//   (createHashMap/HashMap are NOT yet ported in ZRenderKit — see ZRenderKit/Core/util.swift PORT-TODO.)
// import SeriesData from '../SeriesData';                                    -> sibling data/SeriesData (this phase)
// import { DimensionName, VISUAL_DIMENSIONS, DimensionType, DimensionIndex } from '../../util/types';
// import { DataStoreDimensionType } from '../DataStore';                     -> util/types.DataStoreDimensionType
// import { SeriesDataSchema } from './SeriesDataSchema';                     -> sibling data/helper/SeriesDataSchema (this phase)

// upstream:
//   export type DimensionSummaryEncode = {
//       defaultedLabel: DimensionName[],
//       defaultedTooltip: DimensionName[],
//       [coordOrVisualDimName: string]:  // index: coordDimIndex, value: dataDimName
//           DimensionName[]
//   };
// All values are `DimensionName[]` (incl. the two named keys), so model as a string-keyed map.
// PORT-TODO: JS sparse-array holes (`arr[i]` assigned past `length` -> `undefined`) are
// represented as empty-string placeholders; in practice `coordDimIndex` is sequential so
// no holes are ever produced (see `encodeArrSet`).
public typealias DimensionSummaryEncode = Dictionary<[DimensionName]>

public final class DimensionSummary {
    public var encode: DimensionSummaryEncode = [:]
    // Those details that can be expose to users are put int `userOutput`.
    // PORT-TODO: implicitly-unwrapped; upstream builds the object incrementally
    // (`{} as DimensionSummary`) and always assigns `userOutput` before returning.
    public var userOutput: DimensionUserOuput!
    // All of the data dim names that mapped by coordDim.
    public var dataDimsOnCoord: [DimensionName] = []
    public var dataDimIndicesOnCoord: [DimensionIndex] = []
    public var encodeFirstDimNotExtra: Dictionary<DimensionName> = [:]
    public init() {}
}

// upstream:
//   export type DimensionUserOuputEncode = {
//       [coordOrVisualDimName: string]: DimensionIndex[]   // index: coordDimIndex, value: dataDimIndex
//   };
// Already declared in util/types.swift as `Dictionary<[Double]>` — reused here.

public final class DimensionUserOuput {
    private var _encode: DimensionUserOuputEncode
    // PORT-TODO: upstream `_cachedDimNames: DimensionName[]`; sibling
    // `SeriesDataSchema.makeOutputDimensionNames()` returns `[DimensionName?]`
    // (name may be `undefined`), so element type is optional here.
    private var _cachedDimNames: [DimensionName?]?
    private var _schema: SeriesDataSchema?

    public init(
        _ encode: DimensionUserOuputEncode,
        _ dimRequest: SeriesDataSchema? = nil
    ) {
        self._encode = encode
        self._schema = dimRequest
    }

    public func get() -> (
        fullDimensions: [DimensionName?],
        encode: DimensionUserOuputEncode
    ) {
        return (
            // Do not generate full dimension name until fist used.
            fullDimensions: self._getFullDimensionNames(),
            encode: self._encode
        )
    }

    /**
     * Get all data store dimension names.
     * Theoretically a series data store is defined both by series and used dataset (if any).
     * If some dimensions are omitted for performance reason in `this.dimensions`,
     * the dimension name may not be auto-generated if user does not specify a dimension name.
     * In this case, the dimension name is `null`/`undefined`.
     */
    private func _getFullDimensionNames() -> [DimensionName?] {
        if self._cachedDimNames == nil {
            self._cachedDimNames = self._schema != nil
                ? self._schema!.makeOutputDimensionNames()
                : []
        }
        return self._cachedDimNames!
    }
}


// The real `SeriesData` (`final class`, ported in data/SeriesData.swift) provides
// `dimensions` / `getDimensionInfo` / `getDimensionIndex`; the temporary placeholder
// extension that stubbed those accessors was removed now that SeriesData is ported.

public func summarizeDimensions(
    _ data: SeriesData,
    _ schema: SeriesDataSchema? = nil
) -> DimensionSummary {
    let summary = DimensionSummary()
    var encode = DimensionSummaryEncode()
    summary.encode = encode
    // PORT-TODO: createHashMap<1, DimensionName> — modeled as an insertion-ordered key set
    // (the values are all `1`). Swift `Dictionary` is unordered, so use an array + `contains`
    // to preserve upstream iteration/concat order.
    var notExtraCoordDimMap: [DimensionName] = []
    var defaultedLabel: [DimensionName] = []
    var defaultedTooltip: [DimensionName] = []

    var userOutputEncode = DimensionUserOuputEncode()

    util.each(data.dimensions) { dimName, _ in
        let dimItem = data.getDimensionInfo(dimName)

        let coordDim = dimItem.coordDim
        // `if (coordDim)` — JS truthiness: skip nil and empty-string coordDim.
        if let coordDim = coordDim, !coordDim.isEmpty {
            if __DEV__ {
                util.assert(!VISUAL_DIMENSIONS.contains(coordDim))
            }

            let coordDimIndex = Int(dimItem.coordDimIndex ?? 0)
            // upstream: getOrCreateEncodeArr(encode, coordDim)[coordDimIndex] = dimName;
            encodeArrSet(&encode, coordDim, coordDimIndex, dimName)

            if !(dimItem.isExtraCoord ?? false) {
                if !notExtraCoordDimMap.contains(coordDim) {
                    notExtraCoordDimMap.append(coordDim)
                }

                // Use the last coord dim (and label friendly) as default label,
                // because when dataset is used, it is hard to guess which dimension
                // can be value dimension. If both show x, y on label is not look good,
                // and conventionally y axis is focused more.
                if mayLabelDimType(dimItem.type) {
                    // defaultedLabel[0] = dimName;
                    if defaultedLabel.isEmpty {
                        defaultedLabel.append(dimName)
                    }
                    else {
                        defaultedLabel[0] = dimName
                    }
                }

                // User output encode do not contain generated coords.
                // And it only has index. User can use index to retrieve value from the raw item array.
                // upstream: getOrCreateEncodeArr(userOutputEncode, coordDim)[coordDimIndex] =
                //               data.getDimensionIndex(dimItem.name);
                encodeArrSet(&userOutputEncode, coordDim, coordDimIndex,
                    data.getDimensionIndex(dimItem.name))
            }
            if dimItem.defaultTooltip ?? false {
                defaultedTooltip.append(dimName)
            }
        }

        util.each(VISUAL_DIMENSIONS) { otherDim, _ in
            getOrCreateEncodeArr(&encode, otherDim)

            let dimIndex = otherDimsValue(dimItem.otherDims, otherDim)
            // `dimIndex != null && dimIndex !== false`
            if let dimIndex = dimIndex, !isFalse(dimIndex), let di = dimIndex as? Double {
                encodeArrSet(&encode, otherDim, Int(di), dimItem.name)
            }
        }
    }

    var dataDimsOnCoord: [DimensionName] = []
    var encodeFirstDimNotExtra = Dictionary<DimensionName>()

    // notExtraCoordDimMap.each(function (v, coordDim) { ... })
    util.each(notExtraCoordDimMap) { coordDim, _ in
        let dimArr = encode[coordDim]!
        encodeFirstDimNotExtra[coordDim] = dimArr[0]
        // Not necessary to remove duplicate, because a data
        // dim canot on more than one coordDim.
        dataDimsOnCoord = dataDimsOnCoord + dimArr
    }

    summary.dataDimsOnCoord = dataDimsOnCoord
    summary.dataDimIndicesOnCoord = util.map(
        dataDimsOnCoord
    ) { dimName, _ in
        // PORT-TODO: storeDimIndex is optional in SeriesDimensionDefine; upstream assumes it is set here.
        data.getDimensionInfo(dimName).storeDimIndex ?? 0
    }
    summary.encodeFirstDimNotExtra = encodeFirstDimNotExtra

    let encodeLabel = encode["label"]
    // FIXME `encode.label` is not recommended, because formatter cannot be set
    // in this way. Use label.formatter instead. Maybe remove this approach someday.
    if let encodeLabel = encodeLabel, !encodeLabel.isEmpty {
        defaultedLabel = encodeLabel   // .slice() — value-type copy
    }

    let encodeTooltip = encode["tooltip"]
    if let encodeTooltip = encodeTooltip, !encodeTooltip.isEmpty {
        defaultedTooltip = encodeTooltip   // .slice()
    }
    else if defaultedTooltip.isEmpty {
        defaultedTooltip = defaultedLabel   // .slice()
    }

    encode["defaultedLabel"] = defaultedLabel
    encode["defaultedTooltip"] = defaultedTooltip
    // `encode` is by-reference upstream (`const encode = summary.encode = {}`); replicate the
    // shared mutation by writing the (value-type) dictionary back into the summary.
    summary.encode = encode

    summary.userOutput = DimensionUserOuput(userOutputEncode, schema)

    return summary
}

// upstream: getOrCreateEncodeArr(encode, dim): (DimensionIndex | DimensionName)[]
//   returns the (by-reference) array so the caller can index-assign into it.
// Swift arrays are value types, so the get-then-index-assign idiom is split into a
// key-ensuring `getOrCreateEncodeArr` plus the `encodeArrSet` indexed setter below.
// Overloaded for the two concrete element types (DimensionName / DimensionIndex).
private func getOrCreateEncodeArr(_ encode: inout DimensionSummaryEncode, _ dim: DimensionName) {
    if encode[dim] == nil {
        encode[dim] = []
    }
}
private func getOrCreateEncodeArr(_ encode: inout DimensionUserOuputEncode, _ dim: DimensionName) {
    if encode[dim] == nil {
        encode[dim] = []
    }
}

// PORT-TODO: replicates `getOrCreateEncodeArr(encode, dim)[index] = value` (JS array-by-reference
// index-assignment) for Swift value-type arrays. The `while` pad mirrors JS sparse-array growth
// (holes -> placeholder); `index` is sequential in practice so it never actually pads.
private func encodeArrSet(_ encode: inout DimensionSummaryEncode, _ dim: DimensionName, _ index: Int, _ value: DimensionName) {
    getOrCreateEncodeArr(&encode, dim)
    var arr = encode[dim]!
    while arr.count <= index { arr.append("") }
    arr[index] = value
    encode[dim] = arr
}
private func encodeArrSet(_ encode: inout DimensionUserOuputEncode, _ dim: DimensionName, _ index: Int, _ value: DimensionIndex) {
    getOrCreateEncodeArr(&encode, dim)
    var arr = encode[dim]!
    while arr.count <= index { arr.append(0) }
    arr[index] = value
    encode[dim] = arr
}

// PORT-TODO: upstream indexes the dynamic `otherDims` bag by string key
// (`dimItem.otherDims[otherDim]`). `DataVisualDimensions` is a typed struct here, so map the
// known VISUAL_DIMENSIONS keys explicitly. Returns `Any?` because `tooltip` may be `false`.
private func otherDimsValue(_ otherDims: DataVisualDimensions?, _ otherDim: String) -> Any? {
    guard let otherDims = otherDims else { return nil }
    switch otherDim {
    case "tooltip": return otherDims.tooltip
    case "label": return otherDims.label
    case "itemName": return otherDims.itemName
    case "itemId": return otherDims.itemId
    case "itemGroupId": return otherDims.itemGroupId
    case "itemChildGroupId": return otherDims.itemChildGroupId
    case "seriesName": return otherDims.seriesName
    default: return nil
    }
}

// `value !== false` for the `Any?` `otherDims` lookup (only `tooltip` can be the boolean `false`).
private func isFalse(_ value: Any) -> Bool {
    if let b = value as? Bool {
        return b == false
    }
    return false
}

// FIXME:TS should be type `AxisType`
public func getDimensionTypeByAxis(_ axisType: String) -> DataStoreDimensionType {
    return axisType == "category"
        ? .ordinal
        : axisType == "time"
        ? .time
        : .float
}

// PORT-TODO: upstream signature is `mayLabelDimType(dimType: DimensionType)`; `SeriesDimensionDefine.type`
// is optional, so accept an optional here (an absent type is neither 'ordinal' nor 'time' -> labelable).
private func mayLabelDimType(_ dimType: DimensionType?) -> Bool {
    // In most cases, ordinal and time do not suitable for label.
    // Ordinal info can be displayed on axis. Time is too long.
    return !(dimType == .ordinal || dimType == .time)
}

// function findTheLastDimMayLabel(data) {
//     // Get last value dim
//     let dimensions = data.dimensions.slice();
//     let valueType;
//     let valueDim;
//     while (dimensions.length && (
//         valueDim = dimensions.pop(),
//         valueType = data.getDimensionInfo(valueDim).type,
//         valueType === 'ordinal' || valueType === 'time'
//     )) {} // jshint ignore:line
//     return valueDim;
// }
