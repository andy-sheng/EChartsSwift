// Ported from echarts/src/data/Source.ts — keep in sync with upstream
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

// import {
//     isTypedArray, HashMap, clone, createHashMap, isArray, isObject, isArrayLike,
//     hasOwn, assert, each, map, isNumber, isString, keys
// } from 'zrender/src/core/util';
//   -> `isTypedArray`/`clone`/`isArray`/`isObject`/`isArrayLike`/`assert`/`each`/`map`/
//      `isNumber`/`isString`/`keys` are ZRenderKit.util.* ; `HashMap`/`createHashMap` are
//      the EChartsKit local shim (same module — see util/model.swift; ZRenderKit has not
//      yet ported them, see ZRenderKit/Core/util.swift note).
//      `hasOwn` is not ported; replicated inline (own-key check is trivial on a Swift dict).
// import { ... SourceFormat, SeriesLayoutBy, DimensionDefinition, ... } from '../util/types';
//   -> same module (util/types.swift).
// import { DatasetOption } from '../component/dataset/install';
//   -> note: dataset/install is ported (component/dataset/datasetInstall.swift); there is no
//      typed `DatasetOption` here, so `DatasetOption['source']` is read as `Any?`.
// import { getDataItemValue } from '../util/model';        -> model.getDataItemValue (same module).
// import { BE_ORDINAL, guessOrdinal } from './helper/sourceHelper';
//   -> sourceHelper ported separately this phase (sibling data file); referenced via its
//      conventional namespace `sourceHelper.BE_ORDINAL` / `sourceHelper.guessOrdinal`.
import Foundation
import ZRenderKit

/**
 * [sourceFormat]
 *
 * + "original":
 * This format is only used in series.data, where
 * itemStyle can be specified in data item.
 *
 * + "arrayRows":
 * [
 *     ['product', 'score', 'amount'],
 *     ['Matcha Latte', 89.3, 95.8],
 *     ['Milk Tea', 92.1, 89.4],
 *     ['Cheese Cocoa', 94.4, 91.2],
 *     ['Walnut Brownie', 85.4, 76.9]
 * ]
 *
 * + "objectRows":
 * [
 *     {product: 'Matcha Latte', score: 89.3, amount: 95.8},
 *     {product: 'Milk Tea', score: 92.1, amount: 89.4},
 *     {product: 'Cheese Cocoa', score: 94.4, amount: 91.2},
 *     {product: 'Walnut Brownie', score: 85.4, amount: 76.9}
 * ]
 *
 * + "keyedColumns":
 * {
 *     'product': ['Matcha Latte', 'Milk Tea', 'Cheese Cocoa', 'Walnut Brownie'],
 *     'count': [823, 235, 1042, 988],
 *     'score': [95.8, 81.4, 91.2, 76.9]
 * }
 *
 * + "typedArray"
 *
 * + "unknown"
 */

public struct SourceMetaRawOption {
    // PORT note: upstream `seriesLayoutBy?: SeriesLayoutBy` (optional). Kept Optional so the
    // SourceManager pipeline can carry the JS `retrieve2(...) || null` (i.e. absent) value
    // faithfully — see sourceManager.swift `_createSource`/`_getSourceMetaRawOption`.
    // `SourceImpl.seriesLayoutBy` stays non-optional (defaults to 'column' when nil).
    public var seriesLayoutBy: SeriesLayoutBy?
    public var sourceHeader: OptionSourceHeader?      // OptionSourceHeader = Any
    public var dimensions: [DimensionDefinitionLoose]?

    public init(
        seriesLayoutBy: SeriesLayoutBy? = nil,
        sourceHeader: OptionSourceHeader? = nil,
        dimensions: [DimensionDefinitionLoose]? = nil
    ) {
        self.seriesLayoutBy = seriesLayoutBy
        self.sourceHeader = sourceHeader
        self.dimensions = dimensions
    }
}

// Prevent from `new Source()` external and circular reference.
// upstream: `interface Source extends SourceImpl {}` — modeled here as a typealias.
public typealias Source = SourceImpl

// @inner
public final class SourceImpl {

    /**
     * Not null/undefined.
     */
    public let data: OptionSourceData

    /**
     * See also "detectSourceFormat".
     * Not null/undefined.
     */
    public let sourceFormat: SourceFormat

    /**
     * 'row' or 'column'
     * Not null/undefined.
     */
    public let seriesLayoutBy: SeriesLayoutBy

    /**
     * dimensions definition from:
     * (1) standalone defined in option prop `dimensions: [...]`
     * (2) detected from option data. See `determineSourceDimensions`.
     * If can not be detected (e.g., there is only pure data `[[11, 33], ...]`
     * `dimensionsDefine` will be null/undefined.
     */
    // upstream: readonly DimensionDefinition[] — kept `var` because the constructor mutates
    // `dim.type` in place (struct elements need a mutable storage).
    public var dimensionsDefine: [DimensionDefinition]?

    /**
     * Only make sense in `SOURCE_FORMAT_ARRAY_ROWS`.
     * That is the same as `sourceHeader: number`,
     * which means from which line the real data start.
     * Not null/undefined, uint.
     */
    public let startIndex: Double

    /**
     * Dimension count detected from data. Only works when `dimensionDefine`
     * does not exists.
     * Can be null/undefined (when unknown), uint.
     */
    public let dimensionsDetectedCount: Double?

    /**
     * Raw props from user option.
     */
    public let metaRawOption: SourceMetaRawOption?


    public init(
        data: OptionSourceData?,
        sourceFormat: SourceFormat?,   // default: SOURCE_FORMAT_UNKNOWN

        // Visit config are optional:
        seriesLayoutBy: SeriesLayoutBy? = nil,   // default: 'column'
        dimensionsDefine: [DimensionDefinition]? = nil,
        startIndex: Double? = nil,   // default: 0
        dimensionsDetectedCount: Double? = nil,

        metaRawOption: SourceMetaRawOption? = nil,

        // [Caveat]
        // This is the raw user defined `encode` in `series`.
        // If user not defined, DO NOT make a empty object or hashMap here.
        // An empty object or hashMap will prevent from auto generating encode.
        // `encodeDefine` is declared in the upstream `fields` type but never used
        //   in the constructor body; kept for faithfulness.
        encodeDefine: HashMap<OptionEncodeValue>? = nil
    ) {

        self.data = data ?? (
            sourceFormat == SOURCE_FORMAT_KEYED_COLUMNS ? [String: Any]() : [Any]()
        )
        self.sourceFormat = sourceFormat ?? SOURCE_FORMAT_UNKNOWN

        // Visit config
        self.seriesLayoutBy = seriesLayoutBy ?? SERIES_LAYOUT_BY_COLUMN
        self.startIndex = startIndex ?? 0
        self.dimensionsDetectedCount = dimensionsDetectedCount
        self.metaRawOption = metaRawOption

        self.dimensionsDefine = dimensionsDefine

        if self.dimensionsDefine != nil {
            for i in 0..<self.dimensionsDefine!.count {
                let dim = self.dimensionsDefine![i]
                if dim.type == nil {
                    if sourceHelper.guessOrdinal(self, Double(i)) == sourceHelper.BE_ORDINAL.Must {
                        self.dimensionsDefine![i].type = .ordinal
                    }
                }
            }
        }
    }

}

public func isSourceInstance(_ val: Any?) -> Bool {
    return val is SourceImpl
}

/**
 * Create a source from option.
 * NOTE: Created source is immutable. Don't change any properties in it.
 */
public func createSource(
    // PORT note: upstream `sourceData: OptionSourceData` may be `undefined` (e.g. a series
    // with no `data`). Widened to Optional so callers (SourceManager) can pass through an
    // absent value faithfully; `determineSourceDimensions`/`SourceImpl` already handle nil.
    _ sourceData: OptionSourceData?,
    _ thisMetaRawOption: SourceMetaRawOption,
    // can be null. If not provided, auto detect it from `sourceData`.
    _ sourceFormat: SourceFormat?
) -> Source {
    let sourceFormat = sourceFormat ?? detectSourceFormat(sourceData)
    let seriesLayoutBy = thisMetaRawOption.seriesLayoutBy
    let determined = determineSourceDimensions(
        sourceData,
        sourceFormat,
        seriesLayoutBy,
        thisMetaRawOption.sourceHeader,
        thisMetaRawOption.dimensions
    )
    let source = SourceImpl(
        data: sourceData,
        sourceFormat: sourceFormat,

        seriesLayoutBy: seriesLayoutBy,
        dimensionsDefine: determined.dimensionsDefine,
        startIndex: determined.startIndex,
        dimensionsDetectedCount: determined.dimensionsDetectedCount,
        metaRawOption: util.clone(thisMetaRawOption)
    )

    return source
}

/**
 * Wrap original series data for some compatibility cases.
 */
public func createSourceFromSeriesDataOption(_ data: OptionSourceData) -> Source {
    return SourceImpl(
        data: data,
        sourceFormat: util.isTypedArray(data)
            ? SOURCE_FORMAT_TYPED_ARRAY
            : SOURCE_FORMAT_ORIGINAL
    )
}

/**
 * Clone source but excludes source data.
 */
public func cloneSourceShallow(_ source: Source) -> Source {
    return SourceImpl(
        data: source.data,
        sourceFormat: source.sourceFormat,

        seriesLayoutBy: source.seriesLayoutBy,
        dimensionsDefine: util.clone(source.dimensionsDefine),
        startIndex: source.startIndex,
        dimensionsDetectedCount: source.dimensionsDetectedCount
    )
}

/**
 * Note: An empty array will be detected as `SOURCE_FORMAT_ARRAY_ROWS`.
 */
// upstream: detectSourceFormat(data: DatasetOption['source']) — `DatasetOption['source']` is `Any?`.
public func detectSourceFormat(_ data: Any?) -> SourceFormat {
    var sourceFormat: SourceFormat = SOURCE_FORMAT_UNKNOWN

    if util.isTypedArray(data) {
        sourceFormat = SOURCE_FORMAT_TYPED_ARRAY
    }
    else if util.isArray(data) {
        // FIXME Whether tolerate null in top level array?
        let dataArr = (data as? [Any?]) ?? []
        if dataArr.count == 0 {
            sourceFormat = SOURCE_FORMAT_ARRAY_ROWS
        }

        var i = 0
        let len = dataArr.count
        while i < len {
            let item = dataArr[i]

            if item == nil {
                i += 1
                continue
            }
            else if util.isArray(item) || util.isTypedArray(item) {
                sourceFormat = SOURCE_FORMAT_ARRAY_ROWS
                break
            }
            else if util.isObject(item) {
                sourceFormat = SOURCE_FORMAT_OBJECT_ROWS
                break
            }
            i += 1
        }
    }
    else if util.isObject(data) {
        let dataDict = (data as? [String: Any?]) ?? [:]
        for key in dataDict.keys {
            // upstream: hasOwn(data, key) — all Swift-dict keys are own keys.
            if util.isArrayLike(dataDict[key] ?? nil) {
                sourceFormat = SOURCE_FORMAT_KEYED_COLUMNS
                break
            }
        }
    }

    return sourceFormat
}

/**
 * Determine the source definitions from data standalone dimensions definitions
 * are not specified.
 */
private func determineSourceDimensions(
    _ data: OptionSourceData?,
    _ sourceFormat: SourceFormat,
    // PORT note: Optional to carry the SourceManager `|| null` value; compared only via
    // `== SERIES_LAYOUT_BY_ROW`, so nil (null/undefined) behaves as "not row" like upstream.
    _ seriesLayoutBy: SeriesLayoutBy?,
    _ sourceHeader: OptionSourceHeader?,
    // standalone raw dimensions definition, like:
    // {
    //     dimensions: ['aa', 'bb', { name: 'cc', type: 'time' }]
    // }
    // in `dataset` or `series`
    _ dimensionsDefineIn: [DimensionDefinitionLoose]?
) -> (
    // If the input `dimensionsDefine` is specified, return it.
    // Else determine dimensions from the input `data`.
    // If not determined, `dimensionsDefine` will be null/undefined.
    dimensionsDefine: [DimensionDefinition]?,
    startIndex: Double?,
    dimensionsDetectedCount: Double?
) {
    var dimensionsDefine = dimensionsDefineIn
    var dimensionsDetectedCount: Double? = nil
    var startIndex: Double? = nil

    // PENDING: Could data be null/undefined here?
    // currently, if `dataset.source` not specified, error thrown.
    // if `series.data` not specified, nothing rendered without error thrown.
    // Should test these cases.
    if data == nil {
        return (
            normalizeDimensionsOption(dimensionsDefine),
            startIndex,
            dimensionsDetectedCount
        )
    }

    if sourceFormat == SOURCE_FORMAT_ARRAY_ROWS {
        // dynamic cast of `OptionSourceData` (Any) to the typed array shape mirrors
        //   upstream's structural typing; the `?? []` fallback preserves the null-data path above.
        let dataArrayRows = (data as? OptionSourceDataArrayRows) ?? []
        // Rule: Most of the first line are string: it is header.
        // Caution: consider a line with 5 string and 1 number,
        // it still can not be sure it is a head, because the
        // 5 string may be 5 values of category columns.
        if (sourceHeader as? String) == "auto" || sourceHeader == nil {
            arrayRowsTravelFirst({ val, _ in
                // '-' is regarded as null/undefined.
                if val != nil && (val as? String) != "-" {
                    if util.isString(val) {
                        if startIndex == nil { startIndex = 1 }
                    }
                    else {
                        startIndex = 0
                    }
                }
            // 10 is an experience number, avoid long loop.
            }, seriesLayoutBy, dataArrayRows, 10)
        }
        else {
            if util.isNumber(sourceHeader), let n = sourceHeader as? Double {
                startIndex = n
            }
            else {
                startIndex = jsTruthy(sourceHeader) ? 1 : 0
            }
        }

        if dimensionsDefine == nil && startIndex == 1 {
            dimensionsDefine = []
            arrayRowsTravelFirst({ val, index in
                // upstream: dimensionsDefine[index] = (val != null ? val + '' : '');
                //   `index` is contiguous here, so growing/appending reproduces the assignment.
                let name: DimensionDefinitionLoose = (val != nil ? plusEmptyString(val) : "")
                if index < dimensionsDefine!.count {
                    dimensionsDefine![index] = name
                }
                else {
                    dimensionsDefine!.append(name)
                }
            }, seriesLayoutBy, dataArrayRows, Double.infinity)
        }

        if dimensionsDefine != nil {
            dimensionsDetectedCount = Double(dimensionsDefine!.count)
        }
        else if seriesLayoutBy == SERIES_LAYOUT_BY_ROW {
            dimensionsDetectedCount = Double(dataArrayRows.count)
        }
        else {
            dimensionsDetectedCount = dataArrayRows.count > 0
                ? Double(dataArrayRows[0].count)
                : nil
        }
    }
    else if sourceFormat == SOURCE_FORMAT_OBJECT_ROWS {
        if dimensionsDefine == nil {
            dimensionsDefine = objectRowsCollectDimensions((data as? OptionSourceDataObjectRows) ?? [])
        }
    }
    else if sourceFormat == SOURCE_FORMAT_KEYED_COLUMNS {
        if dimensionsDefine == nil {
            dimensionsDefine = []
            // upstream: each(data, function (colArr, key) { dimensionsDefine.push(key); });
            //   Upstream iterates the object in JS enumeration order; a Swift `Dictionary` is
            //   per-process-seeded, so the raw key order was run-to-run NONDETERMINISTIC here.
            //   `jsPropertyKeyOrder` (see objectRowsCollectDimensions) restores the derivable part.
            if let dataDict = data as? [String: Any] {
                for key in jsPropertyKeyOrder(Array(dataDict.keys)) {
                    dimensionsDefine!.append(key)
                }
            }
        }
    }
    else if sourceFormat == SOURCE_FORMAT_ORIGINAL {
        let dataOriginal = (data as? OptionSourceDataOriginal) ?? []
        let value0: Any? = dataOriginal.count > 0 ? model.getDataItemValue(dataOriginal[0]) : nil
        // dimensionsDetectedCount = isArray(value0) && value0.length || 1;
        if util.isArray(value0), let arr = value0 as? [Any], arr.count > 0 {
            dimensionsDetectedCount = Double(arr.count)
        }
        else {
            dimensionsDetectedCount = 1
        }
    }
    else if sourceFormat == SOURCE_FORMAT_TYPED_ARRAY {
        // __DEV__
        util.assert(dimensionsDefine != nil, "dimensions must be given if data is TypedArray.")
    }

    return (
        normalizeDimensionsOption(dimensionsDefine),
        startIndex,
        dimensionsDetectedCount
    )
}

private func objectRowsCollectDimensions(_ data: OptionSourceDataObjectRows) -> [DimensionDefinitionLoose]? {
    var firstIndex = 0
    var obj: [String: OptionDataValue]? = nil
    // upstream: while (firstIndex < data.length && !(obj = data[firstIndex++])) {} // jshint ignore: line
    // an empty object `{}` is truthy in JS; the typed element here cannot be
    //   null/undefined, so the first element always satisfies the loop guard.
    while firstIndex < data.count {
        obj = data[firstIndex]
        firstIndex += 1
        if obj != nil { break }
    }
    if let obj = obj {
        return jsPropertyKeyOrder(Array(obj.keys)) as [DimensionDefinitionLoose]
    }
    return nil
}

/// Emulate JS own-property enumeration order for keys recovered from a Swift `Dictionary`.
///
/// Upstream collects dataset dimensions with `Object.keys`, whose order the spec fixes as: canonical
/// array-index keys in ASCENDING NUMERIC order first, then string keys in insertion order — verified
/// against real echarts in the WKWebView oracle: `Object.keys({product:'A', 2016:85, 2015:43})` is
/// `["2015","2016","product"]`, with `product` LAST despite being written first.
///
/// A Swift `Dictionary` uses per-process seeded hashing, so `Array(dict.keys)` is not merely
/// "possibly different from upstream" — it is different run to run, which made the default `encode`
/// bind columns nondeterministically (the chart could literally change between launches). This helper
/// restores what is derivable:
///   - the numeric portion is EXACTLY upstream's order (it never depended on insertion order);
///   - the string portion's insertion order is unrecoverable from a `Dictionary` — those keys fall
///     back to lexicographic order, which is deterministic but CAN diverge from upstream when a row
///     has 2+ non-numeric keys. The escape hatch is the one upstream also offers: declare
///     `dataset.dimensions` explicitly and this derivation never runs.
func jsPropertyKeyOrder(_ keys: [String]) -> [String] {
    // A canonical array index per the spec: "0", or a non-empty digit string without a leading zero,
    // within 2^32-1. (Negative / fractional / exponent forms are ordinary string keys.)
    func arrayIndex(_ k: String) -> UInt32? {
        if k == "0" { return 0 }
        guard !k.isEmpty, k.first != "0", k.allSatisfy({ $0.isASCII && $0.isNumber }),
              let n = UInt32(k), n < UInt32.max else { return nil }
        return n
    }
    var numeric: [(UInt32, String)] = []
    var rest: [String] = []
    for k in keys {
        if let n = arrayIndex(k) { numeric.append((n, k)) } else { rest.append(k) }
    }
    numeric.sort { $0.0 < $1.0 }
    return numeric.map { $0.1 } + rest.sorted()
}

// Consider dimensions defined like ['A', 'price', 'B', 'price', 'C', 'price'],
// which is reasonable. But dimension name is duplicated.
// Returns undefined or an array contains only object without null/undefined or string.
private func normalizeDimensionsOption(_ dimensionsDefine: [DimensionDefinitionLoose]?) -> [DimensionDefinition]? {
    guard let dimensionsDefine = dimensionsDefine else {
        // The meaning of null/undefined is different from empty array.
        return nil
    }
    let nameMap: HashMap<CountBox> = createHashMap()   // upstream: createHashMap<{ count: number }, string>()
    return util.map(dimensionsDefine, { rawItemAny, index in
        // rawItem = isObject(rawItem) ? rawItem : { name: rawItem };
        var rawItem = DimensionDefinition()
        if util.isObject(rawItemAny), let d = rawItemAny as? DimensionDefinition {
            rawItem = d
        }
        else {
            // { name: rawItem } — rawItem may be string|number; the `+ ''` coercion below
            // (and here) normalizes a number-form name like 2012. (rawItemAny is a non-optional
            // loose dim value here — upstream's `null` case can't occur in this Swift typing.)
            rawItem.name = plusEmptyString(rawItemAny)
        }
        // Other fields will be discarded.
        var item = DimensionDefinition()
        item.name = rawItem.name
        item.displayName = rawItem.displayName
        item.type = rawItem.type

        // User can set null in dimensions.
        // We don't auto specify name, otherwise a given name may
        // cause it to be referred unexpectedly.
        if item.name == nil {
            return item
        }

        // Also consider number form like 2012.
        item.name = item.name! + ""
        // User may also specify displayName.
        // displayName will always exists except user not
        // specified or dim name is not specified or detected.
        // (A auto generated dim name will not be used as
        // displayName).
        if item.displayName == nil {
            item.displayName = item.name
        }

        let exist = nameMap.get(item.name)
        if exist == nil {
            let box = CountBox()
            box.count = 1
            nameMap.set(item.name, box)
        }
        else {
            // item.name += '-' + exist.count++;
            let old = exist!.count
            exist!.count += 1
            item.name = item.name! + "-" + jsNumberStr(old)
        }

        return item
    })
}

private func arrayRowsTravelFirst(
    _ cb: (OptionDataValue, Int) -> Void,
    _ seriesLayoutBy: SeriesLayoutBy?,
    _ data: OptionSourceDataArrayRows,
    _ maxLoop: Double
) {
    if seriesLayoutBy == SERIES_LAYOUT_BY_ROW {
        var i = 0
        while i < data.count && Double(i) < maxLoop {
            // upstream: data[i] ? data[i][0] : null
            let row = data[i]
            cb(row.count > 0 ? row[0] : nil, i)
            i += 1
        }
    }
    else {
        let value0 = data.count > 0 ? data[0] : []
        var i = 0
        while i < value0.count && Double(i) < maxLoop {
            cb(value0[i], i)
            i += 1
        }
    }
}

public func shouldRetrieveDataByName(_ source: Source) -> Bool {
    let sourceFormat = source.sourceFormat
    return sourceFormat == SOURCE_FORMAT_OBJECT_ROWS || sourceFormat == SOURCE_FORMAT_KEYED_COLUMNS
}

// ============================================================================
// Local helpers (not part of upstream): mutable counter box for `normalizeDimensionsOption`
// (upstream uses a `{ count: number }` object aliased through a HashMap), plus JS value
// coercions (`'' + x`, JS truthiness) used by the routines above.
// ============================================================================

private final class CountBox {   // upstream: { count: number }
    var count: Double = 0
    init() {}
}

// JS `'' + x` string coercion. Only called when the value is non-null.
private func plusEmptyString(_ v: Any?) -> String {   // JS string coercion shim
    guard let v = v else { return "undefined" }
    if let s = v as? String { return s }
    if let d = v as? Double { return jsNumberStr(d) }
    if let i = v as? Int { return String(i) }
    if let b = v as? Bool { return b ? "true" : "false" }
    return String(describing: v)
}

// JS `Number.prototype.toString` for a Double (integral values print without a fraction).
private func jsNumberStr(_ x: Double) -> String {   // JS number-to-string shim
    if x == x.rounded() && Swift.abs(x) < 1e15 {
        return String(Int(x))
    }
    return String(x)
}

// JS truthiness for an arbitrary value (used for `sourceHeader ? 1 : 0`).
private func jsTruthy(_ v: Any?) -> Bool {   // JS truthiness shim
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
