// Ported from echarts/src/data/helper/dataProvider.ts — keep in sync with upstream
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

// TODO
// ??? refactor? check the outer usage of data provider.
// merge with defaultDimValueGetter?

import Foundation
import ZRenderKit
// import {isTypedArray, extend, assert, each, isObject, bind, isArray} from 'zrender/src/core/util';
// import {getDataItemValue} from '../../util/model';      -> model.getDataItemValue (EChartsKit)
// import { createSourceFromSeriesDataOption, Source, isSourceInstance } from '../Source';
//   PORT-TODO: `Source`, `createSourceFromSeriesDataOption`, `isSourceInstance` live in
//   data/Source.swift (ported by a sibling agent this phase); referenced by conventional API.
// import {ArrayLike, Dictionary} from 'zrender/src/core/types';   -> ZRenderKit
// import SeriesData from '../SeriesData';
//   PORT-TODO: `SeriesData` (+ its `DataStore`) ported by a sibling agent this phase.
// import { error } from '../../util/log';                          -> log.error (EChartsKit)

public protocol DataProvider: AnyObject {
    /**
     * true: all of the value are in primitive type (in type `OptionDataValue`).
     * false: Not sure whether any of them is non primitive type (in type `OptionDataItemObject`).
     *     Like `data: [ { value: xx, itemStyle: {...} }, ...]`
     *     At present it only happen in `SOURCE_FORMAT_ORIGINAL`.
     */
    var pure: Bool { get }   // upstream: pure?: boolean
    /**
     * If data is persistent and will not be released after use.
     */
    var persistent: Bool { get }   // upstream: persistent?: boolean

    func getSource() -> Source
    func count() -> Double
    func getItem(_ idx: Double, _ out: ArrayLike<OptionDataValue>?) -> OptionDataItem
    // upstream optional methods (`fillStorage?`, `appendData?`, `clean?`):
    func fillStorage(
        _ start: Double,
        _ end: Double,
        _ out: inout [ArrayLike<ParsedValue>],
        _ extent: inout [[Double]]
    )
    func appendData(_ newData: OptionSourceData)
    func clean()
}

// PORT-TODO: model the upstream optional interface members with default no-op impls so
// conformers need not implement them (TS `fillStorage?`/`appendData?`/`clean?`).
extension DataProvider {
    public func fillStorage(
        _ start: Double, _ end: Double,
        _ out: inout [ArrayLike<ParsedValue>], _ extent: inout [[Double]]
    ) {}
    public func appendData(_ newData: OptionSourceData) {}
    public func clean() {}
}

/**
 * If normal array used, mutable chunk size is supported.
 * If typed array used, chunk size must be fixed.
 */
public final class DefaultDataProvider: DataProvider {

    private var _source: Source

    fileprivate var _data: OptionSourceData?

    fileprivate var _offset: Double = 0

    fileprivate var _dimSize: Double = 0

    public var pure: Bool = false       // static protoInitialize: proto.pure = false

    public var persistent: Bool = true  // static protoInitialize: proto.persistent = true

    // PORT-TODO: upstream replaces `getItem`/`count`/`fillStorage`/`appendData`/`clean`
    // on the instance at runtime (via `extend(provider, methods)` + `bind(...)`). Swift cannot
    // re-bind methods, so the mounted implementations are stored as closures here and the
    // instance methods below forward to them.
    fileprivate var _getItem: ((Double, ArrayLike<OptionDataValue>?) -> OptionDataItem)!
    fileprivate var _count: (() -> Double)!
    fileprivate var _appendData: ((OptionSourceData) -> Void)?
    fileprivate var _fillStorage: ((Double, Double, inout [ArrayLike<ParsedValue>], inout [[Double]]) -> Void)?
    fileprivate var _clean: (() -> Void)?

    public init(_ sourceParam: Any, _ dimSize: Double? = nil) {
        // let source: Source;
        let source: Source = !isSourceInstance(sourceParam)
            ? createSourceFromSeriesDataOption(sourceParam as OptionSourceData)
            : (sourceParam as! Source)

        // declare source is Source;
        self._source = source
        let data = source.data
        self._data = data
        let sourceFormat = source.sourceFormat
        let seriesLayoutBy = source.seriesLayoutBy

        // Typed array. TODO IE10+?
        if sourceFormat == SOURCE_FORMAT_TYPED_ARRAY {
            if __DEV__ {
                if dimSize == nil {
                    // throw new Error('Typed array data must specify dimension size');
                    fatalError("Typed array data must specify dimension size")
                }
            }
            self._offset = 0
            self._dimSize = dimSize ?? 0
            self._data = data
        }

        if __DEV__ {
            let validator = rawSourceDataValidatorMap[getMethodMapKey(sourceFormat, seriesLayoutBy)]
            validator?(data, source.dimensionsDefine ?? [])
        }

        mountMethods(self, data, source)
    }

    public func getSource() -> Source {
        return self._source
    }

    public func count() -> Double {
        return self._count()
    }

    public func getItem(_ idx: Double, _ out: ArrayLike<OptionDataValue>? = nil) -> OptionDataItem {
        return self._getItem(idx, out)
    }

    // PORT bridge (not upstream): upstream mutates a raw option data item BY REFERENCE — e.g.
    //   `SankeySeriesModel.setNodePosition` sets `option.data[i].localX/localY` — and because this
    //   provider's `_data` IS that same array reference, the mutation is immediately visible through
    //   `getItem`. Swift arrays/dicts are VALUE types, so a write to the series option never reaches this
    //   provider's `_data` copy. This setter writes the field back into `_data` so `getItem(idx)[key]`
    //   reflects it — reproducing the shared-reference semantics (same spirit as the `appendData` note
    //   above, which reassigns `_data` because Swift arrays are value types). Object/original source only
    //   (each raw item is a `[String: Any]` dict); a no-op otherwise.
    public func setRawItemField(_ idx: Int, _ key: String, _ value: Any?) {
        if var arr = self._data as? [Any?], idx >= 0, idx < arr.count {
            if var dict = arr[idx] as? [String: Any] {
                dict[key] = value
                arr[idx] = dict
                self._data = arr
            }
        }
        else if var arr = self._data as? [Any], idx >= 0, idx < arr.count {
            if var dict = arr[idx] as? [String: Any] {
                dict[key] = value
                arr[idx] = dict
                self._data = arr
            }
        }
    }

    public func fillStorage(
        _ start: Double, _ end: Double,
        _ out: inout [ArrayLike<ParsedValue>], _ extent: inout [[Double]]
    ) {
        self._fillStorage?(start, end, &out, &extent)
    }

    public func appendData(_ newData: OptionSourceData) {
        self._appendData?(newData)
    }

    public func clean() {
        self._clean?()
    }
}


// ---------------------------------------------------------------------------
// upstream: `DefaultDataProvider.internalField` IIFE — `mountMethods` + the per-format
// method tables. Kept as file-scope helpers; structure preserved.
// ---------------------------------------------------------------------------

private func mountMethods(_ provider: DefaultDataProvider, _ data: OptionSourceData, _ source: Source) {
    let sourceFormat = source.sourceFormat
    let seriesLayoutBy = source.seriesLayoutBy
    let startIndex = source.startIndex
    let dimsDef = source.dimensionsDefine ?? []

    let methods = providerMethods[getMethodMapKey(sourceFormat, seriesLayoutBy)]
    if __DEV__ {
        util.assert(methods != nil, "Invalide sourceFormat: " + sourceFormat)
    }

    // extend(provider, methods) — copy the per-format fields onto the provider.
    if let methods = methods {
        if let pure = methods.pure { provider.pure = pure }
        if let persistent = methods.persistent { provider.persistent = persistent }
        if let appendData = methods.appendData {
            provider._appendData = { [unowned provider] newData in appendData(provider, newData) }
        }
        if let clean = methods.clean {
            provider._clean = { [unowned provider] in clean(provider) }
        }
    }

    if sourceFormat == SOURCE_FORMAT_TYPED_ARRAY {
        provider._getItem = { [unowned provider] idx, out in getItemForTypedArray(provider, idx, out) }
        provider._count = { [unowned provider] in countForTypedArray(provider) }
        provider._fillStorage = { [unowned provider] start, end, storage, extent in
            fillStorageForTypedArray(provider, start, end, &storage, &extent)
        }
    }
    else {
        let rawItemGetter = getRawSourceItemGetter(sourceFormat, seriesLayoutBy)
        // PORT PERF (no upstream analogue — JS is untyped): the row-indexed getters below read
        //   `rawData[idx]` after `rawData as? [Any?]` (getItemSimply / countSimply). When `_data`
        //   holds a concrete element type (e.g. an inline series `[[Double]]`), `array as? [Any?]`
        //   bridges EVERY element into a fresh `[Any?]` — O(n) per call. Since `getItem` runs once
        //   per datum during initData, that is O(n²) (measured: ~9 s for a 10k-point line-lttb).
        //   Pre-bridge the outer array to `[Any?]` ONCE here so every subsequent per-call cast is a
        //   same-type O(1) check. Only for the formats whose getters index a `[Any?]` outer array
        //   (ORIGINAL — inline series data — and OBJECT_ROWS); ARRAY_ROWS/KEYED_COLUMNS getters cast
        //   to other element types and must keep their raw storage. `appendData` for these formats
        //   already reassigns `_data` as `[Any?]`, so this is consistent with the append path.
        if (sourceFormat == SOURCE_FORMAT_ORIGINAL || sourceFormat == SOURCE_FORMAT_OBJECT_ROWS),
           let bridged = provider._data as? [Any?] {
            provider._data = bridged
        }
        // PORT-TODO: upstream binds the `data` reference; we read `provider._data` live so that
        // `appendData` (which reassigns `_data`, since Swift arrays are value types) is visible.
        provider._getItem = { [unowned provider] idx, out in
            rawItemGetter(provider._data ?? [], startIndex, dimsDef, idx, out)
        }
        let rawCounter = getRawSourceDataCounter(sourceFormat, seriesLayoutBy)
        provider._count = { [unowned provider] in
            rawCounter(provider._data ?? [], startIndex, dimsDef)
        }
    }
}

private let getItemForTypedArray: (DefaultDataProvider, Double, ArrayLike<OptionDataValue>?) -> OptionDataItem = {
    provider, idxIn, outIn in
    let idx = idxIn - provider._offset
    var out: ArrayLike<OptionDataValue> = outIn ?? []
    let data = (provider._data as? [Double]) ?? []
    let dimSize = provider._dimSize
    let offset = dimSize * idx
    var i = 0.0
    while i < dimSize {
        let dst = Int(offset + i)
        ensureSize(&out, dst + 1)
        out[dst] = (dst >= 0 && dst < data.count) ? data[dst] : nil
        i += 1
    }
    return out
}

private let fillStorageForTypedArray: (DefaultDataProvider, Double, Double, inout [ArrayLike<ParsedValue>], inout [[Double]]) -> Void = {
    provider, start, end, storage, extent in
    let data = (provider._data as? [Double]) ?? []
    let dimSize = provider._dimSize

    var dim = 0.0
    while dim < dimSize {
        var dimExtent = extent[Int(dim)]
        var min = (dimExtent.count > 0 && !dimExtent[0].isNaN) ? dimExtent[0] : Double.infinity
        var max = (dimExtent.count > 1 && !dimExtent[1].isNaN) ? dimExtent[1] : -Double.infinity
        let count = end - start
        var arr = storage[Int(dim)]
        var i = 0.0
        while i < count {
            // appendData with TypedArray will always do replace in provider.
            let srcIdx = Int(i * dimSize + dim)
            let val = (srcIdx >= 0 && srcIdx < data.count) ? data[srcIdx] : Double.nan
            let dstIdx = Int(start + i)
            ensureSizeParsed(&arr, dstIdx + 1)
            arr[dstIdx] = val
            if val < min { min = val }
            if val > max { max = val }
            i += 1
        }
        storage[Int(dim)] = arr
        dimExtent[0] = min
        dimExtent[1] = max
        extent[Int(dim)] = dimExtent
        dim += 1
    }
}

private let countForTypedArray: (DefaultDataProvider) -> Double = { provider in
    if let data = provider._data as? [Double] {
        return Double(data.count) / provider._dimSize
    }
    return 0
}

// Per-format method tables (upstream `providerMethods`).
private struct ProviderMethods {
    var pure: Bool? = nil
    var persistent: Bool? = nil
    var appendData: ((DefaultDataProvider, OptionSourceData) -> Void)? = nil
    var clean: ((DefaultDataProvider) -> Void)? = nil
}

private let providerMethods: [String: ProviderMethods] = [

    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_COLUMN: ProviderMethods(
        pure: true,
        appendData: appendDataSimply
    ),

    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_ROW: ProviderMethods(
        pure: true,
        appendData: { _, _ in
            // throw new Error('Do not support appendData when set seriesLayoutBy: "row".');
            fatalError("Do not support appendData when set seriesLayoutBy: \"row\".")
        }
    ),

    SOURCE_FORMAT_OBJECT_ROWS: ProviderMethods(
        pure: true,
        appendData: appendDataSimply
    ),

    SOURCE_FORMAT_KEYED_COLUMNS: ProviderMethods(
        pure: true,
        appendData: { provider, newDataAny in
            var data = (provider._data as? [String: [OptionDataValue]]) ?? [:]
            let newData = (newDataAny as? [String: [OptionDataValue]]) ?? [:]
            // each(newData, function (newCol, key) { ... })
            for (key, newCol) in newData {
                var oldCol = data[key] ?? []
                let nc = newCol  // (newCol || [])
                for i in 0..<nc.count {
                    oldCol.append(nc[i])
                }
                data[key] = oldCol
            }
            provider._data = data
        }
    ),

    SOURCE_FORMAT_ORIGINAL: ProviderMethods(
        appendData: appendDataSimply
    ),

    SOURCE_FORMAT_TYPED_ARRAY: ProviderMethods(
        pure: true,
        persistent: false,
        appendData: { provider, newData in
            if __DEV__ {
                // PORT-TODO: upstream asserts `isTypedArray(newData)`; Swift typed arrays are
                // `[Double]`/`ContiguousArray<Double>`, which `util.isTypedArray` does not detect.
                // assert(isTypedArray(newData),
                //     'Added data must be TypedArray if data in initialization is TypedArray');
            }
            provider._data = newData
        },

        // Clean self if data is already used.
        clean: { provider in
            // PENDING
            provider._offset += provider.count()
            provider._data = nil
        }
    )
]

private func appendDataSimply(_ provider: DefaultDataProvider, _ newDataAny: OptionSourceData) {
    var data = (provider._data as? [Any?]) ?? []
    let newData = (newDataAny as? [Any?]) ?? []
    for i in 0..<newData.count {
        data.append(newData[i])
    }
    provider._data = data
}


// upstream module-level types/maps below ----------------------------------

// type RawSourceDataValidator
// PORT-TODO: dimsDef typed `{ name?: DimensionName }[]` -> `[DimensionDefinition]`.
private typealias RawSourceDataValidator = (_ rawData: OptionSourceData, _ dimsDef: [DimensionDefinition]) -> Void

private let validateSimply: RawSourceDataValidator = { rawData, _ in
    if !util.isArray(rawData) {
        log.error("series.data or dataset.source must be an array.")
    }
}

/**
 * Only run in dev mode - hint users for debug.
 */
private let rawSourceDataValidatorMap: [String: RawSourceDataValidator] = [
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_COLUMN: validateSimply,
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_ROW: validateSimply,
    SOURCE_FORMAT_OBJECT_ROWS: validateSimply,
    SOURCE_FORMAT_KEYED_COLUMNS: { rawData, dimsDef in
        for i in 0..<dimsDef.count {
            let dimName = dimsDef[i].name
            if dimName == nil {
                log.error("dimension name must not be null/undefined.")
            }
        }
    },
    SOURCE_FORMAT_ORIGINAL: validateSimply
]


// type RawSourceItemGetter — last param `out` only used by ARRAY_ROWS+ROW and KEYED_COLUMNS.
public typealias RawSourceItemGetter = (
    _ rawData: OptionSourceData,
    _ startIndex: Double,
    _ dimsDef: [DimensionDefinition],
    _ idx: Double,
    _ out: ArrayLike<OptionDataValue>?
) -> OptionDataItem

// PORT-TODO: `out` parameter added to unify the closure arity (upstream `getItemSimply`
// omits it). Callers that pass `out` must read the returned value — Swift arrays are value
// types, so in-place buffer reuse is not preserved.
private let getItemSimply: RawSourceItemGetter = { rawData, _, _, idx, _ in
    return (rawData as? [Any?])?[Int(idx)] as Any
}

private let rawSourceItemGetterMap: [String: RawSourceItemGetter] = [
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_COLUMN: { rawData, startIndex, _, idx, _ in
        let data = (rawData as? [[OptionDataValue]]) ?? []
        return data[Int(idx + startIndex)]
    },
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_ROW: { rawData, startIndex, _, idxIn, out in
        let idx = idxIn + startIndex
        var item: ArrayLike<OptionDataValue> = out ?? []
        let data = (rawData as? [[OptionDataValue]]) ?? []
        for i in 0..<data.count {
            let row = data[i]   // row may be empty in upstream (`row ? row[idx] : null`)
            ensureSize(&item, i + 1)
            let j = Int(idx)
            item[i] = (j >= 0 && j < row.count) ? row[j] : nil
        }
        return item
    },
    SOURCE_FORMAT_OBJECT_ROWS: getItemSimply,
    SOURCE_FORMAT_KEYED_COLUMNS: { rawData, _, dimsDef, idx, out in
        var item: ArrayLike<OptionDataValue> = out ?? []
        let dict = (rawData as? [String: [OptionDataValue]]) ?? [:]
        for i in 0..<dimsDef.count {
            let dimName = dimsDef[i].name
            let col = dimName != nil ? dict[dimName!] : nil
            ensureSize(&item, i + 1)
            let j = Int(idx)
            item[i] = (col != nil && j >= 0 && j < col!.count) ? col![j] : nil
        }
        return item
    },
    SOURCE_FORMAT_ORIGINAL: getItemSimply
]

public func getRawSourceItemGetter(
    _ sourceFormat: SourceFormat, _ seriesLayoutBy: SeriesLayoutBy
) -> RawSourceItemGetter {
    let method = rawSourceItemGetterMap[getMethodMapKey(sourceFormat, seriesLayoutBy)]
    if __DEV__ {
        util.assert(method != nil, "Do not support get item on \"" + sourceFormat + "\", \"" + seriesLayoutBy + "\".")
    }
    return method!
}


// type RawSourceDataCounter
public typealias RawSourceDataCounter = (
    _ rawData: OptionSourceData,
    _ startIndex: Double,
    _ dimsDef: [DimensionDefinition]
) -> Double

private let countSimply: RawSourceDataCounter = { rawData, _, _ in
    return Double((rawData as? [Any?])?.count ?? 0)
}

private let rawSourceDataCounterMap: [String: RawSourceDataCounter] = [
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_COLUMN: { rawData, startIndex, _ in
        let len = Double((rawData as? [Any?])?.count ?? 0)
        return Swift.max(0, len - startIndex)
    },
    SOURCE_FORMAT_ARRAY_ROWS + "_" + SERIES_LAYOUT_BY_ROW: { rawData, startIndex, _ in
        let row = (rawData as? [[OptionDataValue]])?.first
        if let row = row {
            return Swift.max(0, Double(row.count) - startIndex)
        }
        return 0
    },
    SOURCE_FORMAT_OBJECT_ROWS: countSimply,
    SOURCE_FORMAT_KEYED_COLUMNS: { rawData, _, dimsDef in
        let dimName = dimsDef.first?.name
        let col = dimName != nil ? (rawData as? [String: [OptionDataValue]])?[dimName!] : nil
        return col != nil ? Double(col!.count) : 0
    },
    SOURCE_FORMAT_ORIGINAL: countSimply
]

public func getRawSourceDataCounter(
    _ sourceFormat: SourceFormat, _ seriesLayoutBy: SeriesLayoutBy
) -> RawSourceDataCounter {
    let method = rawSourceDataCounterMap[getMethodMapKey(sourceFormat, seriesLayoutBy)]
    if __DEV__ {
        util.assert(method != nil, "Do not support count on \"" + sourceFormat + "\", \"" + seriesLayoutBy + "\".")
    }
    return method!
}


// type RawSourceValueGetter
public typealias RawSourceValueGetter = (
    _ dataItem: OptionDataItem,
    _ dimIndex: DimensionIndex,
    _ property: DimensionName
) -> OptionDataValue

private let getRawValueSimply: RawSourceValueGetter = { dataItem, dimIndex, _ in
    let arr = (dataItem as? [OptionDataValue]) ?? []
    let i = Int(dimIndex)
    return (i >= 0 && i < arr.count) ? arr[i] : nil
}

private let rawSourceValueGetterMap: [SourceFormat: RawSourceValueGetter] = [

    SOURCE_FORMAT_ARRAY_ROWS: getRawValueSimply,

    SOURCE_FORMAT_OBJECT_ROWS: { dataItem, _, property in
        return (dataItem as? [String: OptionDataValue])?[property] ?? nil
    },

    SOURCE_FORMAT_KEYED_COLUMNS: getRawValueSimply,

    SOURCE_FORMAT_ORIGINAL: { dataItem, dimIndex, _ in
        // FIXME: In some case (markpoint in geo (geo-map.html)),
        // dataItem is {coord: [...]}
        let value = model.getDataItemValue(dataItem)
        // !(value instanceof Array) ? value : value[dimIndex]
        if let arr = value as? [Any] {
            let i = Int(dimIndex)
            return (i >= 0 && i < arr.count) ? arr[i] : nil
        }
        return value
    },

    SOURCE_FORMAT_TYPED_ARRAY: getRawValueSimply
]

public func getRawSourceValueGetter(_ sourceFormat: SourceFormat) -> RawSourceValueGetter {
    let method = rawSourceValueGetterMap[sourceFormat]
    if __DEV__ {
        util.assert(method != nil, "Do not support get value on \"" + sourceFormat + "\".")
    }
    return method!
}


private func getMethodMapKey(_ sourceFormat: SourceFormat, _ seriesLayoutBy: SeriesLayoutBy) -> String {
    return sourceFormat == SOURCE_FORMAT_ARRAY_ROWS
        ? sourceFormat + "_" + seriesLayoutBy
        : sourceFormat
}


// ??? FIXME can these logic be more neat: getRawValue, getRawDataItem,
// Consider persistent.
// Caution: why use raw value to display on label or tooltip?
// A reason is to avoid format. For example time value we do not know
// how to format is expected. More over, if stack is used, calculated
// value may be 0.91000000001, which have brings trouble to display.
// TODO: consider how to treat null/undefined/NaN when display?
public func retrieveRawValue(
    _ data: SeriesData?, _ dataIndex: Double,
    // If dimIndex is null/undefined, return OptionDataItem.
    // Otherwise, return OptionDataValue.
    _ dim: DimensionLoose? = nil
) -> Any? {   // upstream: OptionDataValue | OptionDataItem
    guard let data = data else {
        return nil
    }

    // (Phase 31: un-stubbed. `SeriesData.getRawDataItem/getStore/getDimensionIndex` and
    //  `DataStore.getSource/getDimensionProperty` + `model.getDataItemValue` + the
    //  `getRawSourceValueGetter` map have all landed, so the faithful body is enabled — the tooltip
    //  content model reads the raw value through this.)
    // Consider data may be not persistent.
    let dataItem = data.getRawDataItem(Int(dataIndex))

    // upstream: `if (dataItem == null) { return; }` — `getRawDataItem` returns `OptionDataItem`
    //   (= Any); an out-of-range/absent item comes back nullish (nil or NSNull).
    if retrieveRawValueIsNullish(dataItem) {
        return nil
    }

    let store = data.getStore()
    let sourceFormat = store.getSource().sourceFormat

    if dim != nil {
        let dimIndex = data.getDimensionIndex(dim!)
        // upstream `getDimensionProperty` returns a `string`; the Swift port returns `String?`
        //   (only the object-rows getter reads it, keyed by property name). Coerce nil to "".
        let property = store.getDimensionProperty(dimIndex) ?? ""

        return getRawSourceValueGetter(sourceFormat)(dataItem, dimIndex, property)
    }
    else {
        var result: Any? = dataItem
        if sourceFormat == SOURCE_FORMAT_ORIGINAL {
            result = model.getDataItemValue(dataItem)
        }
        return result
    }
}

// upstream JS `dataItem == null` on a value typed `OptionDataItem` (= Any here).
private func retrieveRawValueIsNullish(_ v: Any?) -> Bool {
    guard let v = v else { return true }
    return v is NSNull
}


/**
 * Compatible with some cases (in pie, map) like:
 * data: [{name: 'xx', value: 5, selected: true}, ...]
 * where only sourceFormat is 'original' and 'objectRows' supported.
 *
 * // TODO
 * Supported detail options in data item when using 'arrayRows'.
 *
 * @param data
 * @param dataIndex
 * @param attr like 'selected'
 */
public func retrieveRawAttr(_ data: SeriesData?, _ dataIndex: Double, _ attr: String) -> Any? {
    guard let data = data else {
        return nil
    }

    // PORT-TODO: `SeriesData` is an empty protocol stub and `DataStore` is not yet ported.
    // Body preserved verbatim below; re-enable once `SeriesData.getStore/getRawDataItem`
    // and `DataStore.getSource` land.
    _ = data
    return nil
    /*
    let sourceFormat = data.getStore().getSource().sourceFormat

    if sourceFormat != SOURCE_FORMAT_ORIGINAL
        && sourceFormat != SOURCE_FORMAT_OBJECT_ROWS {
        return nil
    }

    var dataItem = data.getRawDataItem(dataIndex)
    if sourceFormat == SOURCE_FORMAT_ORIGINAL && !util.isObject(dataItem) {
        dataItem = nil
    }
    if let dataItem = dataItem {
        return (dataItem as? [String: OptionDataValue])?[attr] ?? nil
    }
    return nil
    */
}


// PORT-TODO: helpers — JS arrays auto-extend on out-of-range assignment; Swift arrays do not.
// `ensureSize`/`ensureSizeParsed` grow a buffer (with `nil`/`NaN`) to match JS `undefined` holes.
private func ensureSize(_ arr: inout ArrayLike<OptionDataValue>, _ size: Int) {
    while arr.count < size {
        arr.append(nil)
    }
}
private func ensureSizeParsed(_ arr: inout ArrayLike<ParsedValue>, _ size: Int) {
    while arr.count < size {
        arr.append(Double.nan)
    }
}
