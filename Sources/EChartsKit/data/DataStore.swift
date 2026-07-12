// Ported from echarts/src/data/DataStore.ts — keep in sync with upstream
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

// import { assert, clone, createHashMap, isFunction, keys, map, reduce } from 'zrender/src/core/util';
//   -> `assert`/`clone`/`isFunction`/`keys`/`map`/`reduce` are ZRenderKit.util.* ;
//      `createHashMap`/`HashMap` are the EChartsKit local shim (same module — util/model.swift).
// import { DimensionIndex, DimensionName, NullUndefined, OptionDataItem, ParsedValue,
//          ParsedValueNumeric, UNDEFINED_STR } from '../util/types';   -> same module (util/types.swift)
// import { DataProvider } from './helper/dataProvider';                -> same module (data/helper/dataProvider.swift)
// import { DataSanitizationFilter, parseDataValue, parseSanitizationFilter,
//          passesSanitizationFilter } from './helper/dataValueHelper'; -> same module (`dataValueHelper.*`)
// import OrdinalMeta from './OrdinalMeta';                             -> same module (data/OrdinalMeta.swift)
// import { shouldRetrieveDataByName, Source } from './Source';         -> same module (data/Source.swift)
// import { initExtentForUnion } from '../util/model';                  -> EChartsKit `model.initExtentForUnion`
// import { asc } from '../util/number';                                -> EChartsKit `number.asc`
import Foundation
import ZRenderKit

/* global Float64Array, Int32Array, Uint32Array, Uint16Array */

// Caution: MUST not use `new CtorUint32Array(arr, 0, len)`, because the Ctor of array is
// different from the Ctor of typed array.
// PORT-NOTE: upstream `CtorUint32Array/CtorUint16Array/CtorInt32Array/CtorFloat64Array` are
//   typed-array constructors selected via `typeof X === UNDEFINED_STR ? Array : X` runtime
//   feature detection. Swift always has the typed storage, so the feature-detection branch
//   is dropped; columns are modeled as `[ParsedValue]` (= `ArrayLike<ParsedValue>`, the
//   convention `DataProvider.fillStorage` consumes) and index arrays as `ContiguousArray<Int>`.

/**
 * Multi dimensional data store
 */
// const dataCtors = { 'float': CtorFloat64Array, 'int': CtorInt32Array, 'ordinal': Array,
//                     'number': Array, 'time': CtorFloat64Array } as const;
//   -> modeled by `makeChunk(_:_:)` below (per-type fill semantics).

// export type DataStoreDimensionType = keyof typeof dataCtors;
//   -> already declared in util/types.swift (`enum DataStoreDimensionType`); referenced here.

// type DataTypedArray / DataTypedArrayConstructor / DataArrayLikeConstructor
//   -> not modeled as distinct Swift types; see PORT-NOTE above.

// type DataValueChunk = ArrayLike<ParsedValue>;
//   -> `[ParsedValue]`. Columns are heterogeneous and may transiently hold ordinal raw
//      values (string) before `collectOrdinalMeta`. PORT-NOTE: storage-model divergence — `int`
//      columns are not truncated to int32 (all columns are `[ParsedValue]`/Double-backed);
//      ordinal/number columns are pre-filled with `NaN` rather than `undefined` holes.

// If Ctx not specified, use List as Ctx
// type EachCb0 = (idx) => void; EachCb1 = (x, idx) => void; EachCb2 = (x, y, idx) => void;
// PORT-NOTE: the arity-specialized callback types (EachCb0/1/2, FilterCb0/1) are collapsed
//   to a single array-arg form. The last array element is the data index (as `Double`).
public typealias EachCb = (_ args: [ParsedValue]) -> Void
public typealias FilterCb = (_ args: [ParsedValue]) -> Bool
// type MapArrayCb = (...args) => any;
// upstream: MapCb returns `ParsedValue | ParsedValue[]` (or null). `nil` => no write.
public typealias MapCb = (_ args: [ParsedValue]) -> ParsedValue?

// upstream: bound `this: DataStore`; here the store is passed as the first argument.
public typealias DimValueGetter = (
    _ store: DataStore,
    _ dataItem: Any?,
    _ property: String?,
    _ dataIndex: Int,
    _ dimIndex: DimensionIndex
) -> ParsedValue

public struct DataStoreDimensionDefine {
    /**
     * Default to be float.
     */
    public var type: DataStoreDimensionType?

    /**
     * Only used in SOURCE_FORMAT_OBJECT_ROWS and SOURCE_FORMAT_KEYED_COLUMNS to retrieve value
     * by "object property".
     * For example, in `[{bb: 124, aa: 543}, ...]`, "aa" and "bb" is "object property".
     *
     * Deliberately name it as "property" rather than "name" to prevent it from been used in
     * SOURCE_FORMAT_ARRAY_ROWS, because if it comes from series, it probably
     * can not be shared by different series.
     */
    public var property: String?

    /**
     * When using category axis.
     * Category strings will be collected and stored in ordinalMeta.categories.
     * And store will store the index of categories.
     */
    public var ordinalMeta: OrdinalMeta?

    /**
     * Offset for ordinal parsing and collect
     */
    public var ordinalOffset: Double?

    public init(
        type: DataStoreDimensionType? = nil,
        property: String? = nil,
        ordinalMeta: OrdinalMeta? = nil,
        ordinalOffset: Double? = nil
    ) {
        self.type = type
        self.property = property
        self.ordinalMeta = ordinalMeta
        self.ordinalOffset = ordinalOffset
    }
}

// let defaultDimValueGetters: {[sourceFormat: string]: DimValueGetter};
//   -> assigned at file scope (see `DataStore.internalField`); upstream assigns it inside the
//      `internalField` IIFE.
fileprivate var defaultDimValueGetters: [String: DimValueGetter] = DataStore.internalField

fileprivate func getIndicesCtor(_ rawCount: Int) -> (Int) -> ContiguousArray<Int> {
    // The possible max value in this._indicies is always this._rawCount despite of filtering.
    // PORT-NOTE: Uint32Array vs Uint16Array distinction collapsed to ContiguousArray<Int>.
    return rawCount > 65535
        ? { ContiguousArray<Int>(repeating: 0, count: $0) }   // CtorUint32Array
        : { ContiguousArray<Int>(repeating: 0, count: $0) }   // CtorUint16Array
}

// new DataCtor(end) — per-type column allocation (see dropped `dataCtors` map above).
fileprivate func makeChunk(_ type: DataStoreDimensionType, _ count: Int) -> [ParsedValue] {
    switch type {
    case .ordinal, .number:
        // `new Array(count)`: holes (undefined).
        return [ParsedValue](repeating: Double.nan, count: count)
    case .float, .time, .int:
        // `new Float64Array(count)` / `new Int32Array(count)`: zero-filled.
        return [ParsedValue](repeating: Double(0), count: count)
    }
}

fileprivate func cloneChunk(_ originalChunk: [ParsedValue]) -> [ParsedValue] {
    // Only shallow clone is enough when Array (and value-copy for the typed-array case).
    return originalChunk
}

fileprivate func prepareStore(
    _ store: inout [[ParsedValue]],
    _ dimIdx: Int,
    _ dimType: DataStoreDimensionType?,
    _ end: Int,
    _ append: Bool = false
) {
    let dataCtorType = dimType ?? .float   // dataCtors[dimType || 'float']

    // Grow the column list to hold `dimIdx` (JS arrays auto-extend with holes).
    while store.count <= dimIdx { store.append([]) }

    if append {
        let oldStore = store[dimIdx]
        let oldLen = oldStore.count
        if !(oldLen == end) {
            var newStore = makeChunk(dataCtorType, end)
            // The cost of the copy is probably inconsiderable
            // within the initial chunkSize.
            for j in 0..<oldLen {
                newStore[j] = oldStore[j]
            }
            store[dimIdx] = newStore
        }
    }
    else {
        store[dimIdx] = makeChunk(dataCtorType, end)
    }
}

/**
 * Basically, DataStore API keep immutable.
 */
public final class DataStore {
    private var _chunks: [[ParsedValue]] = []

    private var _provider: DataProvider!

    // It will not be calculated until needed.
    // PORT-NOTE: an "unset" entry is the empty array `[]` (upstream `undefined`).
    private var _rawExtent: [[Double]] = []

    // structure:
    //  `const extentOnFilterOnDimension = this._extent[dim][extentFilterKey]`
    private var _extent: [[String: [Double]]] = []

    // Indices stores the indices of data subset after filtered.
    // This data subset will be used in chart.
    private var _indices: ContiguousArray<Int>?

    // Count after filtered.
    private var _count: Int = 0
    private var _rawCount: Int = 0

    private var _dimensions: [DataStoreDimensionDefine] = []
    private var _dimValueGetter: DimValueGetter!

    private var _calcDimNameToIdx: HashMap<DimensionIndex> = createHashMap()

    public var defaultDimValueGetter: DimValueGetter!

    public init() {}

    /**
     * Initialize from data
     */
    public func initData(
        _ provider: DataProvider,
        _ inputDimensions: [DataStoreDimensionDefine],
        _ dimValueGetter: DimValueGetter? = nil
    ) {
        if __DEV__ {
            util.assert(
                util.isFunction(provider.getItem) && util.isFunction(provider.count),
                "Invalid data provider."
            )
        }

        self._provider = provider

        // Clear
        self._chunks = []
        self._indices = nil
        self.getRawIndex = { [unowned self] idx in self._getRawIdxIdentity(idx) }

        let source = provider.getSource()
        let defaultGetter = defaultDimValueGetters[source.sourceFormat]
        self.defaultDimValueGetter = defaultGetter
        // Default dim value getter
        self._dimValueGetter = dimValueGetter ?? defaultGetter

        // Reset raw extent.
        self._rawExtent = []
        let willRetrieveDataByName = shouldRetrieveDataByName(source)
        self._dimensions = util.map(inputDimensions) { dim, _ in
            if __DEV__ {
                if willRetrieveDataByName {
                    util.assert(dim.property != nil)
                }
            }
            // Only pick these two props. Not leak other properties like orderMeta.
            return DataStoreDimensionDefine(type: dim.type, property: dim.property)
        }

        self._initDataFromProvider(0, Int(provider.count()))
    }

    public func getProvider() -> DataProvider {
        return self._provider
    }

    /**
     * Caution: even when a `source` instance owned by a series, the created data store
     * may still be shared by different sereis (the source hash does not use all `source`
     * props, see `sourceManager`). In this case, the `source` props that are not used in
     * hash (like `source.dimensionDefine`) probably only belongs to a certain series and
     * thus should not be fetch here.
     */
    public func getSource() -> Source {
        return self._provider.getSource()
    }

    /**
     * @caution Only used in dataStack.
     */
    public func ensureCalculationDimension(_ dimName: DimensionName, _ type: DataStoreDimensionType) -> DimensionIndex {
        let calcDimNameToIdx = self._calcDimNameToIdx
        let dimensions = self._dimensions

        var calcDimIdx = calcDimNameToIdx.get(dimName)
        if calcDimIdx != nil {
            if dimensions[Int(calcDimIdx!)].type == type {
                return calcDimIdx!
            }
        }
        else {
            calcDimIdx = DimensionIndex(dimensions.count)
        }

        let idx = Int(calcDimIdx!)
        while self._dimensions.count <= idx { self._dimensions.append(DataStoreDimensionDefine()) }
        self._dimensions[idx] = DataStoreDimensionDefine(type: type)
        _ = calcDimNameToIdx.set(dimName, calcDimIdx!)

        while self._chunks.count <= idx { self._chunks.append([]) }
        self._chunks[idx] = makeChunk(type, self._rawCount)   // new dataCtors[type || 'float'](this._rawCount)
        while self._rawExtent.count <= idx { self._rawExtent.append([]) }
        self._rawExtent[idx] = model.initExtentForUnion()

        return calcDimIdx!
    }

    public func collectOrdinalMeta(_ dimIdx: Int, _ ordinalMeta: OrdinalMeta) {
        // const chunk = this._chunks[dimIdx]; (value-type; mutate stored directly, §3)
        var dim = self._dimensions[dimIdx]
        // const rawExtents = this._rawExtent;

        let offset = Int(dim.ordinalOffset ?? 0)
        let len = self._chunks[dimIdx].count

        if offset == 0 {
            // We need to reset the rawExtent if collect is from start.
            // Because this dimension may be guessed as number and calcuating a wrong extent.
            while self._rawExtent.count <= dimIdx { self._rawExtent.append([]) }
            self._rawExtent[dimIdx] = model.initExtentForUnion()
        }

        // const dimRawExtent = rawExtents[dimIdx]; (value-type; mutate stored directly, §3)

        // Parse from previous data offset. len may be changed after appendData
        for i in offset..<len {
            // See also CATEGORY_AXIS_MODEL_DATA_IS_EMPTY_ARRAY.
            let val = ordinalMeta.parseAndCollect(self._chunks[dimIdx][i])
            self._chunks[dimIdx][i] = val
            if !val.isNaN {
                self._rawExtent[dimIdx][0] = Swift.min(val, self._rawExtent[dimIdx][0])
                self._rawExtent[dimIdx][1] = Swift.max(val, self._rawExtent[dimIdx][1])
            }
        }

        dim.ordinalMeta = ordinalMeta
        dim.ordinalOffset = Double(len)
        dim.type = .ordinal   // Force to be ordinal
        self._dimensions[dimIdx] = dim
    }

    public func getOrdinalMeta(_ dimIdx: Int) -> OrdinalMeta? {
        let dimInfo = self._dimensions[dimIdx]
        let ordinalMeta = dimInfo.ordinalMeta
        return ordinalMeta
    }

    public func getDimensionProperty(_ dimIndex: DimensionIndex) -> String? {
        let i = Int(dimIndex)
        let item = i >= 0 && i < self._dimensions.count ? self._dimensions[i] : nil
        return item?.property
    }

    /**
     * Caution: Can be only called on raw data (before `this._indices` created).
     */
    public func appendData(_ data: OptionSourceData) -> [Int] {
        if __DEV__ {
            util.assert(self._indices == nil, "appendData can only be called on raw data.")
        }

        let provider = self._provider!
        let start = self.count()
        provider.appendData(data)
        var end = Int(provider.count())
        if !provider.persistent {
            end += start
        }

        if start < end {
            self._initDataFromProvider(start, end, true)
        }

        // upstream returns `number[]`.
        return [start, end]
    }

    public func appendValues(_ values: [[Any?]], _ minFillLen: Int? = nil) -> (start: Int, end: Int) {
        let dimensions = self._dimensions
        let dimLen = dimensions.count

        let start = self.count()
        let end = start + Swift.max(values.count, minFillLen ?? 0)

        for i in 0..<dimLen {
            let dim = dimensions[i]
            prepareStore(&self._chunks, i, dim.type, end, true)
        }

        let emptyDataItem: [Any?] = []
        for idx in start..<end {
            let sourceIdx = idx - start
            // Store the data by dimensions
            for dimIdx in 0..<dimLen {
                let dim = dimensions[dimIdx]
                let val = defaultDimValueGetters["arrayRows"]!(
                    self, sourceIdx < values.count ? values[sourceIdx] : emptyDataItem,
                    dim.property, sourceIdx, DimensionIndex(dimIdx)
                )
                self._chunks[dimIdx][idx] = val

                // const dimRawExtent = rawExtent[dimIdx]; (value-type; mutate stored, §3)
                let numVal = DataStore.numericValue(val)
                if numVal < self._rawExtent[dimIdx][0] { self._rawExtent[dimIdx][0] = numVal }
                if numVal > self._rawExtent[dimIdx][1] { self._rawExtent[dimIdx][1] = numVal }
            }
        }

        self._rawCount = end
        self._count = end

        return (start, end)
    }

    private func _initDataFromProvider(
        _ start: Int,
        _ end: Int,
        _ append: Bool = false
    ) {
        let provider = self._provider!
        let dimensions = self._dimensions
        let dimLen = dimensions.count
        let dimNames = util.map(dimensions) { dim, _ in dim.property }

        for i in 0..<dimLen {
            let dim = dimensions[i]
            while self._rawExtent.count <= i { self._rawExtent.append([]) }
            if self._rawExtent[i].isEmpty {   // if (!rawExtent[i])
                self._rawExtent[i] = model.initExtentForUnion()
            }
            prepareStore(&self._chunks, i, dim.type, end, append)
        }

        // PORT-NOTE: upstream branches on `if (provider.fillStorage)` (method presence). The
        //   ported `DataProvider` models `fillStorage` as a required method with a no-op
        //   default, so method presence cannot be queried; gate on the typed-array source
        //   format instead — the only provider that mounts `fillStorage` upstream
        //   (see dataProvider.ts).
        if provider.getSource().sourceFormat == SOURCE_FORMAT_TYPED_ARRAY {
            provider.fillStorage(Double(start), Double(end), &self._chunks, &self._rawExtent)
        }
        else {
            var dataItem: OptionDataItem = [OptionDataValue]()
            for idx in start..<end {
                // NOTICE: Try not to write things into dataItem
                dataItem = provider.getItem(Double(idx), dataItem as? [OptionDataValue])
                // Each data item is value
                // [1, 2]
                // 2
                // Bar chart, line chart which uses category axis
                // only gives the 'y' value. 'x' value is the indices of category
                // Use a tempValue to normalize the value to be a (x, y) value

                // Store the data by dimensions
                for dimIdx in 0..<dimLen {
                    // PENDING NULL is empty or zero
                    let val = self._dimValueGetter(
                        self, dataItem, dimNames[dimIdx], idx, DimensionIndex(dimIdx)
                    )
                    self._chunks[dimIdx][idx] = val

                    // const dimRawExtent = rawExtent[dimIdx]; (value-type; mutate stored, §3)
                    let numVal = DataStore.numericValue(val)
                    if numVal < self._rawExtent[dimIdx][0] { self._rawExtent[dimIdx][0] = numVal }
                    if numVal > self._rawExtent[dimIdx][1] { self._rawExtent[dimIdx][1] = numVal }
                }
            }
        }

        if !provider.persistent {
            // Clean unused data if data source is typed array.
            provider.clean()
        }

        self._rawCount = end
        self._count = end
        // Reset data extent
        self._extent = []
    }

    public func count() -> Int {
        return self._count
    }

    /**
     * Get value. Return NaN if idx is out of range.
     */
    public func get(_ dim: DimensionIndex, _ idx: Int) -> ParsedValue {
        if !(idx >= 0 && idx < self._count) {
            return Double.nan
        }
        let dimStore = self.chunk(Int(dim))
        return dimStore != nil ? dimStore![self.getRawIndex(idx)] : Double.nan
    }

    // upstream overload: `getValues(idx)` — all dimensions.
    public func getValues(_ idx: Int) -> [ParsedValue] {
        var values: [ParsedValue] = []
        var dimArr: [DimensionIndex] = []
        // TODO get all from store?
        // All dimensions
        for i in 0..<self._dimensions.count {
            dimArr.append(DimensionIndex(i))
        }

        for i in 0..<dimArr.count {
            values.append(self.get(dimArr[i], idx))
        }

        return values
    }

    // upstream overload: `getValues(dimensions, idx)`.
    public func getValues(_ dimensions: [DimensionIndex], _ idx: Int) -> [ParsedValue] {
        var values: [ParsedValue] = []
        let dimArr: [DimensionIndex] = dimensions

        for i in 0..<dimArr.count {
            values.append(self.get(dimArr[i], idx))
        }

        return values
    }

    /**
     * @param dim concrete dim
     */
    public func getByRawIndex(_ dim: DimensionIndex, _ rawIdx: Int) -> ParsedValue {
        if !(rawIdx >= 0 && rawIdx < self._rawCount) {
            return Double.nan
        }
        let dimStore = self.chunk(Int(dim))
        return dimStore != nil ? dimStore![rawIdx] : Double.nan
    }

    /**
     * Get sum of data in one dimension
     */
    public func getSum(_ dim: DimensionIndex) -> Double {
        let dimData = self.chunk(Int(dim))
        var sum: Double = 0
        if dimData != nil {
            var i = 0
            let len = self.count()
            while i < len {
                let value = DataStore.numericValue(self.get(dim, i))
                if !value.isNaN {
                    sum += value
                }
                i += 1
            }
        }
        return sum
    }

    /**
     * Get median of data in one dimension
     */
    public func getMedian(_ dim: DimensionIndex) -> Double {
        var dimDataArray: [Double] = []
        // map all data of one dimension
        self.each([dim]) { args in
            let val = DataStore.numericValue(args[0])
            if !val.isNaN {
                dimDataArray.append(val)
            }
        }

        // TODO
        // Use quick select?
        dimDataArray = number.asc(dimDataArray)
        let len = self.count()
        // calculate median
        return len == 0
            ? 0
            : len % 2 == 1
            ? dimDataArray[(len - 1) / 2]
            : (dimDataArray[len / 2] + dimDataArray[len / 2 - 1]) / 2
    }

    /**
     * Retrieve the index with given raw data index.
     */
    public func indexOfRawIndex(_ rawIndex: Int) -> Int {
        if rawIndex >= self._rawCount || rawIndex < 0 {
            return -1
        }

        guard let indices = self._indices else {
            return rawIndex
        }

        // Indices are ascending

        // If rawIndex === dataIndex
        let rawDataIndex: Int? = rawIndex < indices.count ? indices[rawIndex] : nil
        if rawDataIndex != nil && rawDataIndex! < self._count && rawDataIndex! == rawIndex {
            return rawIndex
        }

        var left = 0
        var right = self._count - 1
        while left <= right {
            let mid = (left + right) / 2
            if indices[mid] < rawIndex {
                left = mid + 1
            }
            else if indices[mid] > rawIndex {
                right = mid - 1
            }
            else {
                return mid
            }
        }
        return -1
    }

    public func getIndices() -> ContiguousArray<Int> {
        var newIndices: ContiguousArray<Int>

        if let indices = self._indices {
            let thisCount = self._count
            // `new Array(a, b, c)` is different from `new Uint32Array(a, b, c)`.
            // PORT-NOTE: `Ctor === Array` vs typed-buffer-share distinction collapsed to copy.
            newIndices = ContiguousArray<Int>(repeating: 0, count: thisCount)
            for i in 0..<thisCount {
                newIndices[i] = indices[i]
            }
        }
        else {
            let Ctor = getIndicesCtor(self._rawCount)
            newIndices = Ctor(self.count())
            for i in 0..<newIndices.count {
                newIndices[i] = i
            }
        }

        return newIndices
    }

    /**
     * [NOTICE]: Performance-sensitive for large data.
     */
    public func filter(
        _ dims: [DimensionIndex],
        _ cb: FilterCb
    ) -> DataStore {
        if self._count == 0 {
            return self
        }

        let newStore = self.clone()

        let count = newStore.count()
        let Ctor = getIndicesCtor(newStore._rawCount)
        var newIndices = Ctor(count)
        var value: [ParsedValue] = []
        let dimSize = dims.count

        var offset = 0
        let dim0 = dims.isEmpty ? 0 : dims[0]
        let chunks = newStore._chunks

        for i in 0..<count {
            var keep: Bool
            let rawIdx = newStore.getRawIndex(i)
            // Simple optimization
            if dimSize == 0 {
                keep = cb([Double(i)])
            }
            else if dimSize == 1 {
                let val = chunks[Int(dim0)][rawIdx]
                keep = cb([val, Double(i)])
            }
            else {
                var k = 0
                while k < dimSize {
                    if value.count <= k { value.append(Double.nan) }
                    value[k] = chunks[Int(dims[k])][rawIdx]
                    k += 1
                }
                if value.count <= k { value.append(Double.nan) }
                value[k] = Double(i)
                keep = cb(value)
            }
            if keep {
                newIndices[offset] = rawIdx
                offset += 1
            }
        }

        // Set indices after filtered.
        if offset < count {
            newStore._indices = newIndices
        }
        newStore._count = offset
        // Reset data extent
        newStore._extent = []

        newStore._updateGetRawIdx()

        return newStore
    }

    /**
     * Select data in range. (For optimization of filter)
     * (Manually inline code, support 5 million data filtering in data zoom.)
     */
    public func selectRange(_ range: [DimensionIndex: [Double]]) -> DataStore {
        let newStore = self.clone()

        let len = newStore._count

        if len == 0 {
            return self
        }

        // PORT-NOTE: upstream `keys(range)` iterates object keys in ascending numeric order;
        //   Swift `Dictionary.keys` is unordered. Only the dim0/dim1 quick-path selection is
        //   affected (the result is order-independent).
        let dims = Array(range.keys)
        let dimSize = dims.count
        if dimSize == 0 {
            return self
        }

        let originalCount = newStore.count()
        let Ctor = getIndicesCtor(newStore._rawCount)
        var newIndices = Ctor(originalCount)

        var offset = 0
        let dim0 = dims[0]

        let min = range[dim0]![0]
        let max = range[dim0]![1]
        let storeArr = newStore._chunks

        var quickFinished = false
        if newStore._indices == nil {
            // Extreme optimization for common case. About 2x faster in chrome.
            var idx = 0
            if dimSize == 1 {
                let dimStorage = storeArr[Int(dims[0])]
                for i in 0..<len {
                    let val = DataStore.numericValue(dimStorage[i])
                    // NaN will not be filtered. Consider the case, in line chart, empty
                    // value indicates the line should be broken. But for the case like
                    // scatter plot, a data item with empty value will not be rendered,
                    // but the axis extent may be effected if some other dim of the data
                    // item has value. Fortunately it is not a significant negative effect.
                    if (val >= min && val <= max) || val.isNaN {
                        newIndices[offset] = idx
                        offset += 1
                    }
                    idx += 1
                }
                quickFinished = true
            }
            else if dimSize == 2 {
                let dimStorage = storeArr[Int(dims[0])]
                let dimStorage2 = storeArr[Int(dims[1])]
                let min2 = range[dims[1]]![0]
                let max2 = range[dims[1]]![1]
                for i in 0..<len {
                    let val = DataStore.numericValue(dimStorage[i])
                    let val2 = DataStore.numericValue(dimStorage2[i])
                    // Do not filter NaN, see comment above.
                    if ((val >= min && val <= max) || val.isNaN)
                        && ((val2 >= min2 && val2 <= max2) || val2.isNaN) {
                        newIndices[offset] = idx
                        offset += 1
                    }
                    idx += 1
                }
                quickFinished = true
            }
        }
        if !quickFinished {
            if dimSize == 1 {
                for i in 0..<originalCount {
                    let rawIndex = newStore.getRawIndex(i)
                    let val = DataStore.numericValue(storeArr[Int(dims[0])][rawIndex])
                    // Do not filter NaN, see comment above.
                    if (val >= min && val <= max) || val.isNaN {
                        newIndices[offset] = rawIndex
                        offset += 1
                    }
                }
            }
            else {
                for i in 0..<originalCount {
                    var keep = true
                    let rawIndex = newStore.getRawIndex(i)
                    for k in 0..<dimSize {
                        let dimk = dims[k]
                        let val = DataStore.numericValue(storeArr[Int(dimk)][rawIndex])
                        // Do not filter NaN, see comment above.
                        if val < range[dimk]![0] || val > range[dimk]![1] {
                            keep = false
                        }
                    }
                    if keep {
                        newIndices[offset] = newStore.getRawIndex(i)
                        offset += 1
                    }
                }
            }
        }

        // Set indices after filtered.
        if offset < originalCount {
            newStore._indices = newIndices
        }
        newStore._count = offset
        // Reset data extent
        newStore._extent = []

        newStore._updateGetRawIdx()

        return newStore
    }

    // /**
    //  * Data mapping to a plain array
    //  */
    // mapArray(dims: DimensionIndex[], cb: MapArrayCb): any[] {
    //     const result: any[] = [];
    //     this.each(dims, function () {
    //         result.push(cb && (cb as MapArrayCb).apply(null, arguments));
    //     });
    //     return result;
    // }

    /**
     * Data mapping to a new List with given dimensions
     */
    public func map(_ dims: [DimensionIndex], _ cb: MapCb) -> DataStore {
        // TODO only clone picked chunks.
        let target = self.clone(dims)
        self._updateDims(target, dims, cb)
        return target
    }

    /**
     * @caution Danger!! Only used in dataStack.
     */
    public func modify(_ dims: [DimensionIndex], _ cb: MapCb) {
        self._updateDims(self, dims, cb)
    }

    private func _updateDims(
        _ target: DataStore,
        _ dims: [DimensionIndex],
        _ cb: MapCb
    ) {
        // const targetChunks = target._chunks; (writes go to `target._chunks` directly, §3)

        let dimSize = dims.count
        let dataCount = target.count()
        var values: [ParsedValue] = []

        for i in 0..<dims.count {
            let d = Int(dims[i])
            while target._rawExtent.count <= d { target._rawExtent.append([]) }
            target._rawExtent[d] = model.initExtentForUnion()
        }

        for dataIndex in 0..<dataCount {
            let rawIndex = target.getRawIndex(dataIndex)

            for k in 0..<dimSize {
                if values.count <= k { values.append(Double.nan) }
                values[k] = target._chunks[Int(dims[k])][rawIndex]
            }
            if values.count <= dimSize { values.append(Double.nan) }
            values[dimSize] = Double(dataIndex)

            var retValue = cb(values)
            if retValue != nil {
                // a number or string (in ordinal dimension)?
                var retArray: [ParsedValue]
                if let arr = retValue as? [ParsedValue] {
                    retArray = arr
                }
                else {
                    retArray = [retValue!]
                }
                retValue = retArray

                for i in 0..<retArray.count {
                    let dim = Int(dims[i])
                    let val = retArray[i]

                    if dim < target._chunks.count {
                        target._chunks[dim][rawIndex] = val
                    }

                    let numVal = DataStore.numericValue(val)
                    if numVal < target._rawExtent[dim][0] {
                        target._rawExtent[dim][0] = numVal
                    }
                    if numVal > target._rawExtent[dim][1] {
                        target._rawExtent[dim][1] = numVal
                    }
                }
            }
        }
    }

    /**
     * Large data down sampling using largest-triangle-three-buckets
     * @param {string} valueDimension
     * @param {number} targetCount
     */
    public func lttbDownSample(
        _ valueDimension: DimensionIndex,
        _ rate: Double
    ) -> DataStore {
        let target = self.clone([valueDimension], true)
        let targetStorage = target._chunks
        let dimStore = targetStorage[Int(valueDimension)]
        let len = self.count()

        var sampledIndex = 0

        let frameSize = Int(floor(1 / rate))

        var currentRawIndex = self.getRawIndex(0)
        var maxArea: Double
        var area: Double
        var nextRawIndex: Int

        var newIndices = getIndicesCtor(self._rawCount)(Swift.min((Int(ceil(Double(len) / Double(frameSize))) + 2) * 2, len))

        // First frame use the first data.
        newIndices[sampledIndex] = currentRawIndex
        sampledIndex += 1
        var i = 1
        while i < len - 1 {
            let nextFrameStart = Swift.min(i + frameSize, len - 1)
            let nextFrameEnd = Swift.min(i + frameSize * 2, len)

            let avgX = Double(nextFrameEnd + nextFrameStart) / 2
            var avgY: Double = 0

            for idx in nextFrameStart..<nextFrameEnd {
                let rawIndex = self.getRawIndex(idx)
                let y = DataStore.numericValue(dimStore[rawIndex])
                if y.isNaN {
                    continue
                }
                avgY += y
            }
            avgY /= Double(nextFrameEnd - nextFrameStart)

            let frameStart = i
            let frameEnd = Swift.min(i + frameSize, len)

            let pointAX = Double(i - 1)
            let pointAY = DataStore.numericValue(dimStore[currentRawIndex])

            maxArea = -1

            nextRawIndex = frameStart

            var firstNaNIndex = -1
            var countNaN = 0
            // Find a point from current frame that construct a triangle with largest area with previous selected point
            // And the average of next frame.
            for idx in frameStart..<frameEnd {
                let rawIndex = self.getRawIndex(idx)
                let y = DataStore.numericValue(dimStore[rawIndex])
                if y.isNaN {
                    countNaN += 1
                    if firstNaNIndex < 0 {
                        firstNaNIndex = rawIndex
                    }
                    continue
                }
                // Calculate triangle area over three buckets
                area = Swift.abs((pointAX - avgX) * (y - pointAY)
                    - (pointAX - Double(idx)) * (avgY - pointAY)
                )
                if area > maxArea {
                    maxArea = area
                    nextRawIndex = rawIndex // Next a is this b
                }
            }

            if countNaN > 0 && countNaN < frameEnd - frameStart {
                // Append first NaN point in every bucket.
                // It is necessary to ensure the correct order of indices.
                newIndices[sampledIndex] = Swift.min(firstNaNIndex, nextRawIndex)
                sampledIndex += 1
                nextRawIndex = Swift.max(firstNaNIndex, nextRawIndex)
            }

            newIndices[sampledIndex] = nextRawIndex
            sampledIndex += 1

            currentRawIndex = nextRawIndex // This a is the next a (chosen b)

            i += frameSize
        }

        // First frame use the last data.
        newIndices[sampledIndex] = self.getRawIndex(len - 1)
        sampledIndex += 1
        target._count = sampledIndex
        target._indices = newIndices

        target.getRawIndex = { [unowned target] idx in target._getRawIdx(idx) }
        return target
    }

    /**
     * Large data down sampling using min-max
     * @param {string} valueDimension
     * @param {number} rate
     */
    public func minmaxDownSample(
        _ valueDimension: DimensionIndex,
        _ rate: Double
    ) -> DataStore {
        let target = self.clone([valueDimension], true)
        let targetStorage = target._chunks

        let frameSize = Int(floor(1 / rate))

        let dimStore = targetStorage[Int(valueDimension)]
        let len = self.count()

        // Each frame results in 2 data points, one for min and one for max
        var newIndices = getIndicesCtor(self._rawCount)(Int(ceil(Double(len) / Double(frameSize))) * 2)

        var offset = 0
        var i = 0
        while i < len {
            var minIndex = i
            var minValue = DataStore.numericValue(dimStore[self.getRawIndex(minIndex)])
            var maxIndex = i
            var maxValue = DataStore.numericValue(dimStore[self.getRawIndex(maxIndex)])

            var thisFrameSize = frameSize
            // Handle final smaller frame
            if i + frameSize > len {
                thisFrameSize = len - i
            }
            // Determine min and max within the current frame
            for k in 0..<thisFrameSize {
                let rawIndex = self.getRawIndex(i + k)
                let value = DataStore.numericValue(dimStore[rawIndex])

                if value < minValue {
                    minValue = value
                    minIndex = i + k
                }
                if value > maxValue {
                    maxValue = value
                    maxIndex = i + k
                }
            }

            let rawMinIndex = self.getRawIndex(minIndex)
            let rawMaxIndex = self.getRawIndex(maxIndex)

            // Set the order of the min and max values, based on their ordering in the frame
            if minIndex < maxIndex {
                newIndices[offset] = rawMinIndex
                offset += 1
                newIndices[offset] = rawMaxIndex
                offset += 1
            }
            else {
                newIndices[offset] = rawMaxIndex
                offset += 1
                newIndices[offset] = rawMinIndex
                offset += 1
            }

            i += frameSize
        }

        target._count = offset
        target._indices = newIndices

        target._updateGetRawIdx()

        return target
    }


    /**
     * Large data down sampling on given dimension
     * @param sampleIndex Sample index for name and id
     */
    public func downSample(
        _ dimension: DimensionIndex,
        _ rate: Double,
        _ sampleValue: (_ frameValues: [ParsedValue]) -> ParsedValueNumeric,
        _ sampleIndex: (_ frameValues: [ParsedValue], _ value: ParsedValueNumeric) -> Int
    ) -> DataStore {
        let target = self.clone([dimension], true)
        // const targetStorage = target._chunks; (writes go to `target._chunks` directly, §3)

        var frameValues: [ParsedValue] = []
        var frameSize = Int(floor(1 / rate))

        let dimStore = target._chunks[Int(dimension)]
        let len = self.count()
        while target._rawExtent.count <= Int(dimension) { target._rawExtent.append([]) }
        target._rawExtent[Int(dimension)] = model.initExtentForUnion()
        // const rawExtentOnDim = target._rawExtent[dimension]; (value-type; mutate stored, §3)

        var newIndices = getIndicesCtor(self._rawCount)(Int(ceil(Double(len) / Double(frameSize))))

        var offset = 0
        var i = 0
        while i < len {
            // Last frame
            if frameSize > len - i {
                frameSize = len - i
                if frameValues.count > frameSize {
                    frameValues.removeLast(frameValues.count - frameSize)
                }
            }
            for k in 0..<frameSize {
                let dataIdx = self.getRawIndex(i + k)
                if frameValues.count <= k { frameValues.append(Double.nan) }
                frameValues[k] = dimStore[dataIdx]
            }
            let value = sampleValue(frameValues)
            let sampleFrameIdx = self.getRawIndex(
                Swift.min(i + sampleIndex(frameValues, value), len - 1)
            )
            // Only write value on the filtered data
            target._chunks[Int(dimension)][sampleFrameIdx] = value

            if value < target._rawExtent[Int(dimension)][0] {
                target._rawExtent[Int(dimension)][0] = value
            }
            if value > target._rawExtent[Int(dimension)][1] {
                target._rawExtent[Int(dimension)][1] = value
            }

            newIndices[offset] = sampleFrameIdx
            offset += 1

            i += frameSize
        }

        target._count = offset
        target._indices = newIndices

        target._updateGetRawIdx()

        return target
    }

    /**
     * Data iteration
     * @param ctx default this
     * @example
     *  list.each(0, function (x, idx) {});
     *  list.each([0, 1], function (x, y, idx) {});
     *  list.each(function (idx) {})
     */
    public func each(_ dims: [DimensionIndex], _ cb: EachCb) {
        if self._count == 0 {
            return
        }
        let dimSize = dims.count
        let chunks = self._chunks

        var i = 0
        let len = self.count()
        while i < len {
            let rawIdx = self.getRawIndex(i)
            // Simple optimization
            switch dimSize {
            case 0:
                cb([Double(i)])
            case 1:
                cb([chunks[Int(dims[0])][rawIdx], Double(i)])
            case 2:
                cb([chunks[Int(dims[0])][rawIdx], chunks[Int(dims[1])][rawIdx], Double(i)])
            default:
                var k = 0
                var value: [ParsedValue] = []
                while k < dimSize {
                    value.append(chunks[Int(dims[k])][rawIdx])
                    k += 1
                }
                // Index
                value.append(Double(i))
                cb(value)
            }
            i += 1
        }
    }

    public func getDataExtent(
        _ dim: DimensionIndex,
        _ filter: DataSanitizationFilter?
    ) -> [Double] {
        // Make sure use concrete dim as cache name.
        let dimData = self.chunk(Int(dim))
        let initialExtent = model.initExtentForUnion()

        guard let dimData = dimData else {
            return initialExtent
        }

        // Make more strict checkings to ensure hitting cache.
        let currEnd = self.count()

        // Consider the most cases when using data zoom, `getDataExtent`
        // happened before filtering. We cache raw extent, which is not
        // necessary to be cleared and recalculated when restore data.
        let useRaw = self._indices == nil && filter == nil
        if useRaw {
            return self._rawExtent[Int(dim)]   // .slice() -> value copy
        }

        // NOTE:
        //  - In logarithm axis, zero should be excluded, therefore the `extent[0]` should be less or equal
        //    than the min positive data item, which requires the special handling here.
        //  - "Filter non-positive values for logarithm axis" can also be implemented in a data processor
        //    but that requires more complicated code to not break all streams under the current architecture,
        //    therefore we simply implement it here.
        //  - Performance is sensitive for large data, therefore inline filters rather than cb is used here.

        // const dimExtentRecord = thisExtent[dim] || (thisExtent[dim] = {}); (value-type; mutate stored, §3)
        while self._extent.count <= Int(dim) { self._extent.append([:]) }

        let filterParsed = dataValueHelper.parseSanitizationFilter(filter)
        let filterKey = filterParsed.key

        let dimExtent = self._extent[Int(dim)][filterKey]
        if let dimExtent = dimExtent {
            return dimExtent   // .slice() -> value copy
        }

        var min = initialExtent[0]
        var max = initialExtent[1]

        for i in 0..<currEnd {
            // NOTICE: Manually inline some code for performance of large data.
            let rawIdx = self.getRawIndex(i)
            let value = DataStore.numericValue(dimData[rawIdx])
            // NOTE: in most cases, filter does not exist.
            if filter == nil || dataValueHelper.passesSanitizationFilter(filterParsed, value) {
                if value < min {
                    min = value
                }
                if value > max {
                    max = value
                }
            }
        }

        self._extent[Int(dim)][filterKey] = [min, max]
        return [min, max]
    }

    /**
     * Get raw data index.
     * Do not initialize.
     * Default `getRawIndex`. And it can be changed.
     */
    // Default identity getter (upstream assigns `this._getRawIdxIdentity` in `initData`); a
    // non-`self`-capturing default is required so `init` can run before reassignment.
    public var getRawIndex: (_ idx: Int) -> Int = { idx in idx }

    /**
     * Get raw data item
     */
    public func getRawDataItem(_ idx: Int) -> OptionDataItem {
        let rawIdx = self.getRawIndex(idx)
        if !self._provider.persistent {
            var val: [ParsedValue] = []
            let chunks = self._chunks
            for i in 0..<chunks.count {
                val.append(chunks[i][rawIdx])
            }
            return val
        }
        else {
            return self._provider.getItem(Double(rawIdx), nil)
        }
    }

    /**
     * Clone shallow.
     *
     * @param clonedDims Determine which dims to clone. Will share the data if not specified.
     */
    public func clone(_ clonedDims: [DimensionIndex]? = nil, _ ignoreIndices: Bool = false) -> DataStore {
        let target = DataStore()
        let chunks = self._chunks
        let clonedDimsMap: [Int: Bool]? = clonedDims.map { dims in
            util.reduce(dims, { (obj: [Int: Bool], dimIdx: DimensionIndex, _: Int) -> [Int: Bool] in
                var obj = obj
                obj[Int(dimIdx)] = true
                return obj
            }, [Int: Bool]())
        }

        if let clonedDimsMap = clonedDimsMap {
            for i in 0..<chunks.count {
                // Not clone if dim is not picked.
                // target._chunks[i] = !clonedDimsMap[i] ? chunks[i] : cloneChunk(chunks[i]);
                target._chunks.append(!(clonedDimsMap[i] ?? false) ? chunks[i] : cloneChunk(chunks[i]))
            }
        }
        else {
            target._chunks = chunks
        }
        self._copyCommonProps(target)

        if !ignoreIndices {
            target._indices = self._cloneIndices()
        }
        target._updateGetRawIdx()
        return target
    }

    private func _copyCommonProps(_ target: DataStore) {
        target._count = self._count
        target._rawCount = self._rawCount
        target._provider = self._provider
        target._dimensions = self._dimensions

        target._extent = util.clone(self._extent)
        target._rawExtent = util.clone(self._rawExtent)
    }

    private func _cloneIndices() -> ContiguousArray<Int>? {
        if let indices = self._indices {
            // PORT-NOTE: `Ctor === Array` vs typed distinction collapsed to copy.
            let thisCount = indices.count
            var newIndices = ContiguousArray<Int>(repeating: 0, count: thisCount)
            for i in 0..<thisCount {
                newIndices[i] = indices[i]
            }
            return newIndices
        }
        return nil
    }

    private func _getRawIdxIdentity(_ idx: Int) -> Int {
        return idx
    }
    private func _getRawIdx(_ idx: Int) -> Int {
        if idx < self._count && idx >= 0 {
            return self._indices![idx]
        }
        return -1
    }

    private func _updateGetRawIdx() {
        // PORT-NOTE: verify capture — `getRawIndex` is stored on `self` and captures `self`
        //   unowned to avoid a retain cycle.
        self.getRawIndex = self._indices != nil
            ? { [unowned self] idx in self._getRawIdx(idx) }
            : { [unowned self] idx in self._getRawIdxIdentity(idx) }
    }

    // private static internalField = (function () { ... })();
    //   -> upstream IIFE assigns the module-level `defaultDimValueGetters`. Here it is a
    //      static value used to initialize the file-scope `defaultDimValueGetters`.
    fileprivate static let internalField: [String: DimValueGetter] = {

        func getDimValueSimply(
            _ store: DataStore, _ dataItem: Any?, _ property: String?, _ dataIndex: Int, _ dimIndex: DimensionIndex
        ) -> ParsedValue {
            return dataValueHelper.parseDataValue(
                itemAt(dataItem, Int(dimIndex)),
                ParseDataValueOpt(type: store._dimensions[Int(dimIndex)].type)
            )
        }

        var getters: [String: DimValueGetter] = [:]

        getters["arrayRows"] = getDimValueSimply

        getters["objectRows"] = { store, dataItem, property, dataIndex, dimIndex in
            return dataValueHelper.parseDataValue(
                propertyOf(dataItem, property),
                ParseDataValueOpt(type: store._dimensions[Int(dimIndex)].type)
            )
        }

        getters["keyedColumns"] = getDimValueSimply

        getters["original"] = { store, dataItem, property, dataIndex, dimIndex in
            // Performance sensitive, do not use modelUtil.getDataItemValue.
            // If dataItem is an plain object with no value field, the let `value`
            // will be assigned with the object, but it will be tread correctly
            // in the `convertValue`.
            // const value = dataItem && (dataItem.value == null ? dataItem : dataItem.value);
            var value: Any? = nil
            if dataItem != nil {
                let v = propertyOf(dataItem, "value")
                value = (v == nil) ? dataItem : v
            }

            return dataValueHelper.parseDataValue(
                (value is [Any?])
                    ? itemAt(value, Int(dimIndex))
                    // If value is a single number or something else not array.
                    : value,
                ParseDataValueOpt(type: store._dimensions[Int(dimIndex)].type)
            )
        }

        getters["typedArray"] = { store, dataItem, property, dataIndex, dimIndex in
            return itemAt(dataItem, Int(dimIndex)) as Any
        }

        return getters
    }()

    private func chunk(_ dim: Int) -> [ParsedValue]? {
        return dim >= 0 && dim < self._chunks.count ? self._chunks[dim] : nil
    }

    // Helper: coerce a stored ParsedValue to a numeric `Double` for comparison/arithmetic.
    // PORT-NOTE: upstream relies on JS implicit coercion / typed-array numeric storage; here
    //   non-`Double` values (e.g. ordinal raw strings before `collectOrdinalMeta`) become NaN,
    //   matching JS's `Number('x') === NaN` for a non-numeric value.
    fileprivate static func numericValue(_ v: ParsedValue) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return Double.nan
    }
}

// upstream: `dataItem[dimIndex]` — index `Any` (an array-like data item) by position.
fileprivate func itemAt(_ dataItem: Any?, _ i: Int) -> Any? {
    if let arr = dataItem as? [Any?] {
        return i >= 0 && i < arr.count ? arr[i] : nil
    }
    return nil
}

// upstream: `dataItem[property]` / `dataItem.value` — index `Any` (a plain object) by key.
fileprivate func propertyOf(_ dataItem: Any?, _ property: String?) -> Any? {
    guard let property = property, let dict = dataItem as? [String: Any] else {
        return nil
    }
    return dict[property]
}

// export default DataStore;
