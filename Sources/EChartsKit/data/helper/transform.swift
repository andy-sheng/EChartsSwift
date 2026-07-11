// Ported from echarts/src/data/helper/transform.ts — keep in sync with upstream
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

// upstream imports:
//   import { Dictionary, DimensionDefinitionLoose, SourceFormat, DimensionDefinition,
//       DimensionIndex, OptionDataValue, DimensionLoose, DimensionName, ParsedValue,
//       SERIES_LAYOUT_BY_COLUMN, SOURCE_FORMAT_OBJECT_ROWS, SOURCE_FORMAT_ARRAY_ROWS,
//       OptionSourceDataObjectRows, OptionSourceDataArrayRows } from '../../util/types';
//       -> util/types.swift (same module).
//   import { normalizeToArray } from '../../util/model';   -> `model.normalizeToArray` (util/modelUtil.swift).
//   import { createHashMap, bind, each, hasOwn, map, clone, isObject, extend, isNumber }
//       from 'zrender/src/core/util';
//       -> `each`/`map`/`clone`/`isObject`/`isNumber`/`extend` are `ZRenderKit.util.*`; `createHashMap`
//          is the EChartsKit local shim (util/modelUtil.swift). `bind` is inlined as a Swift closure.
//          `hasOwn` is replicated inline (own-key check via HashMap.hasKey / dictionary lookup).
//   import { getRawSourceItemGetter, getRawSourceDataCounter, getRawSourceValueGetter }
//       from './dataProvider';                              -> data/helper/dataProvider.swift (same module).
//   import { parseDataValue } from './dataValueHelper';     -> `dataValueHelper.parseDataValue`.
//   import { log, makePrintable, throwError } from '../../util/log';
//       -> `log.log` / `log.makePrintable` / `log.throwError` (util/log.swift).
//   import { createSource, Source, SourceMetaRawOption, detectSourceFormat } from '../Source';
//       -> data/Source.swift (same module).
import Foundation
import ZRenderKit


// upstream: export type PipedDataTransformOption = DataTransformOption[];
public typealias PipedDataTransformOption = [DataTransformOption]
// upstream: export type DataTransformType = string;
public typealias DataTransformType = String
// upstream: export type DataTransformConfig = unknown;
public typealias DataTransformConfig = Any?

// upstream: export interface DataTransformOption { type; config?; print?; }
public struct DataTransformOption {
    public var type: DataTransformType
    public var config: DataTransformConfig
    // Print the result via `console.log` when transform performed. Only work in dev mode for debug.
    public var print: Bool?

    public init(type: DataTransformType, config: DataTransformConfig = nil, print: Bool? = nil) {
        self.type = type
        self.config = config
        self.print = print
    }
}

// upstream: export interface ExternalDataTransform<TO extends DataTransformOption = DataTransformOption>
// The generic parameter `TO` only narrows `config` (erased to `Any?` here), so it is dropped.
public struct ExternalDataTransform {
    // Must include namespace like: 'ecStat:regression'
    public var type: String
    public var __isBuiltIn: Bool?
    public var transform: (_ param: ExternalDataTransformParam) -> ExternalDataTransformResult

    public init(
        type: String,
        __isBuiltIn: Bool? = nil,
        transform: @escaping (_ param: ExternalDataTransformParam) -> ExternalDataTransformResult
    ) {
        self.type = type
        self.__isBuiltIn = __isBuiltIn
        self.transform = transform
    }
}

// upstream: the transform return is `ExternalDataTransformResultItem | ExternalDataTransformResultItem[]`.
// The union is erased to `Any` (a single item or an array), then `normalizeToArray`-d below.
public typealias ExternalDataTransformResult = Any

// upstream: interface ExternalDataTransformParam<TO> { upstream; upstreamList; config; }
public struct ExternalDataTransformParam {
    // This is the first source in upstreamList. In most cases,
    // there is only one upstream source.
    public var upstream: ExternalSource
    public var upstreamList: [ExternalSource]
    public var config: DataTransformConfig

    public init(upstream: ExternalSource, upstreamList: [ExternalSource], config: DataTransformConfig) {
        self.upstream = upstream
        self.upstreamList = upstreamList
        self.config = config
    }
}

// upstream: export interface ExternalDataTransformResultItem { data; dimensions?; }
public struct ExternalDataTransformResultItem {
    /**
     * If `data` is null/undefined, inherit upstream data.
     */
    // upstream: OptionSourceDataArrayRows | OptionSourceDataObjectRows (erased to OptionSourceData = Any).
    public var data: OptionSourceData
    /**
     * A `transform` can optionally return a dimensions definition.
     * The rule:
     * If this `transform result` have different dimensions from the upstream, it should return
     * a new dimension definition. For example, this transform inherit the upstream data totally
     * but add a extra dimension.
     * Otherwise, do not need to return that dimension definition. echarts will inherit dimension
     * definition from the upstream.
     */
    public var dimensions: [DimensionDefinitionLoose]?

    public init(data: OptionSourceData, dimensions: [DimensionDefinitionLoose]? = nil) {
        self.data = data
        self.dimensions = dimensions
    }
}

// upstream: export type DataTransformDataItem = ExternalDataTransformResultItem['data'][number];
// i.e. a single row: `OptionSourceDataArrayRows[number] | OptionSourceDataObjectRows[number]`.
public typealias DataTransformDataItem = Any?

// upstream: export interface ExternalDimensionDefinition extends Partial<DimensionDefinition> { index }
public struct ExternalDimensionDefinition {
    // Mandatory
    public var index: DimensionIndex
    // Partial<DimensionDefinition>
    public var type: DataStoreDimensionType?
    public var name: DimensionName?
    public var displayName: String?

    public init(
        index: DimensionIndex,
        type: DataStoreDimensionType? = nil,
        name: DimensionName? = nil,
        displayName: String? = nil
    ) {
        self.index = index
        self.type = type
        self.name = name
        self.displayName = displayName
    }
}

// upstream: `type DataTransformConfig = unknown;` — see typealias above.

/**
 * TODO: disable writable.
 * This structure will be exposed to users.
 */
// upstream: `export class ExternalSource`. The public methods are overridden per-instance in
// `createExternalSource` (JS assigns function properties on the instance). Modeled here as a
// `final class` whose methods are stored closures, initialized to the upstream default bodies
// and re-assigned in `createExternalSource`.
public final class ExternalSource {
    /**
     * [Caveat]
     * This instance is to be exposed to users.
     * (1) DO NOT mount private members on this instance directly.
     * If we have to use private members, we can make them in closure or use `makeInner`.
     * (2) "source header count" is not provided to transform, because it's complicated to manage
     * header and dimensions definition in each transform. Source headers are all normalized to
     * dimensions definitions in transforms and their downstreams.
     */

    public var sourceFormat: SourceFormat = SOURCE_FORMAT_UNKNOWN

    // upstream default: `throw new Error('not supported')` (only built-in transform available).
    // Overridden in `createExternalSource` iff `externalTransform.__isBuiltIn`.
    public var getRawData: () throws -> OptionSourceData = {
        // Only built-in transform available.
        throw EChartsError(message: "not supported")
    }

    // upstream default: `throw new Error('not supported')`.
    public var getRawDataItem: (_ dataIndex: Double) throws -> DataTransformDataItem = { _ in
        // Only built-in transform available.
        throw EChartsError(message: "not supported")
    }

    // upstream default: `return;` (undefined).
    public var cloneRawData: () throws -> OptionSourceData? = { return nil }

    /**
     * @return If dimension not found, return null/undefined.
     */
    // upstream default: `return;` (undefined).
    public var getDimensionInfo: (_ dim: DimensionLoose?) -> ExternalDimensionDefinition? = { _ in return nil }

    /**
     * dimensions defined if and only if either:
     * (a) dataset.dimensions are declared.
     * (b) dataset data include dimensions definitions in data (detected or via specified `sourceHeader`).
     * If dimensions are defined, `dimensionInfoAll` is corresponding to
     * the defined dimensions.
     * Otherwise, `dimensionInfoAll` is determined by data columns.
     * @return Always return an array (even empty array).
     */
    // upstream default: `return;` (undefined).
    public var cloneAllDimensionInfo: () -> [ExternalDimensionDefinition] = { return [] }

    // upstream default: `return;` (undefined).
    public var count: () -> Double = { return 0 }

    /**
     * Only support by dimension index.
     * No need to support by dimension name in transform function,
     * because transform function is not case-specific, no need to use name literally.
     */
    // upstream default: `return;` (undefined).
    public var retrieveValue: (_ dataIndex: Double, _ dimIndex: DimensionIndex) -> OptionDataValue = { _, _ in return nil }

    // upstream default: `return;` (undefined).
    public var retrieveValueFromItem: (_ dataItem: DataTransformDataItem, _ dimIndex: DimensionIndex) -> OptionDataValue = { _, _ in return nil }

    public func convertValue(_ rawVal: Any?, _ dimInfo: ExternalDimensionDefinition) -> ParsedValue {
        // upstream: return parseDataValue(rawVal, dimInfo);
        //   `parseDataValue` only reads `dimInfo.type`; build the option bag from it.
        return dataValueHelper.parseDataValue(rawVal, ParseDataValueOpt(type: dimInfo.type))
    }

    public init() {}
}


// upstream: function createExternalSource(internalSource: Source, externalTransform): ExternalSource
private func createExternalSource(_ internalSource: Source, _ externalTransform: ExternalDataTransform) throws -> ExternalSource {
    let extSource = ExternalSource()

    let data = internalSource.data
    extSource.sourceFormat = internalSource.sourceFormat
    let sourceFormat = extSource.sourceFormat
    let sourceHeaderCount = internalSource.startIndex

    var errMsg = ""
    if internalSource.seriesLayoutBy != SERIES_LAYOUT_BY_COLUMN {
        // For the logic simplicity in transformer, only 'culumn' is
        // supported in data transform. Otherwise, the `dimensionsDefine`
        // might be detected by 'row', which probably confuses users.
        if __DEV__ {
            errMsg = "`seriesLayoutBy` of upstream dataset can only be \"column\" in data transform."
        }
        try log.throwError(errMsg)
    }

    // [MEMO]
    // Create a new dimensions structure for exposing.
    // Do not expose all dimension info to users directly.
    // Because the dimension is probably auto detected from data and not might reliable.
    // Should not lead the transformers to think that is reliable and return it.
    // See [DIMENSION_INHERIT_RULE] in `sourceManager.ts`.
    var dimensions: [ExternalDimensionDefinition] = []
    let dimsByName: HashMap<ExternalDimensionDefinition> = createHashMap()

    let dimsDef = internalSource.dimensionsDefine
    if let dimsDef = dimsDef {
        // upstream: each(dimsDef, function (dimDef, idx) { ... })
        //   (a manual loop is used because the body may `throwError` on duplicate names).
        for idx in 0..<dimsDef.count {
            let dimDef = dimsDef[idx]
            let name = dimDef.name
            let dimDefExt = ExternalDimensionDefinition(
                index: Double(idx),
                name: name,
                displayName: dimDef.displayName
            )
            dimensions.append(dimDefExt)
            // Users probably do not specify dimension name. For simplicity, data transform
            // does not generate dimension name.
            if let name = name {
                // Dimension name should not be duplicated.
                // For simplicity, data transform forbids name duplication, do not generate
                // new name like module `completeDimensions.ts` did, but just tell users.
                var errMsg = ""
                if dimsByName.hasKey(name) {   // upstream: hasOwn(dimsByName, name)
                    if __DEV__ {
                        errMsg = "dimension name \"" + name + "\" duplicated."
                    }
                    try log.throwError(errMsg)
                }
                dimsByName.set(name, dimDefExt)
            }
        }
    }
    // If dimension definitions are not defined and can not be detected.
    // e.g., pure data `[[11, 22], ...]`.
    else {
        // upstream: for (let i = 0; i < internalSource.dimensionsDetectedCount || 0; i++)
        //   `|| 0` sheds nil/NaN; `orZero` reproduces it (nil/NaN -> 0).
        let detectedCount = orZero(internalSource.dimensionsDetectedCount)
        var i = 0
        while Double(i) < detectedCount {
            // Do not generete name or anything others. The consequence process in
            // `transform` or `series` probably have there own name generation strategry.
            dimensions.append(ExternalDimensionDefinition(index: Double(i)))
            i += 1
        }
    }

    // `dimsDef` shape needed by the `dataProvider` getters (they only read `.name`/`.type`).
    let dimsDefForGetter: [DimensionDefinition] = dimensions.map { ext in
        var d = DimensionDefinition()
        d.name = ext.name
        d.displayName = ext.displayName
        d.type = ext.type
        return d
    }

    // Implement public methods:
    let rawItemGetter = getRawSourceItemGetter(sourceFormat, SERIES_LAYOUT_BY_COLUMN)
    if externalTransform.__isBuiltIn == true {
        extSource.getRawDataItem = { dataIndex in
            return rawItemGetter(data, sourceHeaderCount, dimsDefForGetter, dataIndex, nil) as DataTransformDataItem
        }
        // upstream: bind(getRawData, null, internalSource)
        extSource.getRawData = { try getRawData(internalSource) }
    }

    // upstream: bind(cloneRawData, null, internalSource)
    extSource.cloneRawData = { try cloneRawData(internalSource) }

    let rawCounter = getRawSourceDataCounter(sourceFormat, SERIES_LAYOUT_BY_COLUMN)
    // upstream: bind(rawCounter, null, data, sourceHeaderCount, dimensions)
    extSource.count = { rawCounter(data, sourceHeaderCount, dimsDefForGetter) }

    let rawValueGetter = getRawSourceValueGetter(sourceFormat)

    // upstream: `retrieveValueFromItem` is assigned first, then closed over by `retrieveValue`.
    let retrieveValueFromItem: (_ dataItem: DataTransformDataItem, _ dimIndex: DimensionIndex) -> OptionDataValue = { dataItem, dimIndex in
        // upstream: if (dataItem == null) { return; }
        if isNullish(dataItem) {
            return nil
        }
        let di = Int(dimIndex)
        let dimDef: ExternalDimensionDefinition? = (di >= 0 && di < dimensions.count) ? dimensions[di] : nil
        // When `dimIndex` is `null`, `rawValueGetter` return the whole item.
        if let dimDef = dimDef {
            // upstream: rawValueGetter(dataItem, dimIndex, dimDef.name)
            //   `property` is only used by the object-rows getter; a nil `name` becomes "" here
            //   (object-rows dims always carry a name, so this does not arise in practice).
            return rawValueGetter(dataItem as Any, dimIndex, dimDef.name ?? "")
        }
        return nil
    }
    extSource.retrieveValueFromItem = retrieveValueFromItem

    extSource.retrieveValue = { dataIndex, dimIndex in
        let rawItem = rawItemGetter(data, sourceHeaderCount, dimsDefForGetter, dataIndex, nil) as DataTransformDataItem
        return retrieveValueFromItem(rawItem, dimIndex)
    }

    // upstream: bind(getDimensionInfo, null, dimensions, dimsByName)
    extSource.getDimensionInfo = { dim in getDimensionInfo(dimensions, dimsByName, dim) }
    // upstream: bind(cloneAllDimensionInfo, null, dimensions)
    extSource.cloneAllDimensionInfo = { cloneAllDimensionInfo(dimensions) }

    return extSource
}

// upstream: function getRawData(upstream: Source): Source['data']
private func getRawData(_ upstream: Source) throws -> OptionSourceData {
    let sourceFormat = upstream.sourceFormat

    if !isSupportedSourceFormat(sourceFormat) {
        var errMsg = ""
        if __DEV__ {
            errMsg = "`getRawData` is not supported in source format " + sourceFormat
        }
        try log.throwError(errMsg)
    }

    return upstream.data
}

// upstream: function cloneRawData(upstream: Source): Source['data']
private func cloneRawData(_ upstream: Source) throws -> OptionSourceData? {
    let sourceFormat = upstream.sourceFormat
    let data = upstream.data

    if !isSupportedSourceFormat(sourceFormat) {
        var errMsg = ""
        if __DEV__ {
            errMsg = "`cloneRawData` is not supported in source format " + sourceFormat
        }
        try log.throwError(errMsg)
    }

    if sourceFormat == SOURCE_FORMAT_ARRAY_ROWS {
        var result: [Any] = []
        let arr = (data as? OptionSourceDataArrayRows) ?? []
        for i in 0..<arr.count {
            // Not strictly clone for performance
            // upstream: result.push(data[i].slice());
            result.append(arr[i])   // Swift arrays are value types; the element is a copy.
        }
        return result
    }
    else if sourceFormat == SOURCE_FORMAT_OBJECT_ROWS {
        var result: [Any] = []
        let arr = (data as? OptionSourceDataObjectRows) ?? []
        for i in 0..<arr.count {
            // Not strictly clone for performance
            // upstream: result.push(extend({}, data[i]));
            var target: [String: OptionDataValue] = [:]
            _ = util.extend(&target, arr[i])
            result.append(target)
        }
        return result
    }
    // upstream: falls through to `return undefined`.
    return nil
}

// upstream: function getDimensionInfo(dimensions, dimsByName, dim): ExternalDimensionDefinition
private func getDimensionInfo(
    _ dimensions: [ExternalDimensionDefinition],
    _ dimsByName: HashMap<ExternalDimensionDefinition>,
    _ dim: DimensionLoose?
) -> ExternalDimensionDefinition? {
    // upstream: if (dim == null) { return; }
    guard let dim = dim, !(dim is NSNull) else {
        return nil
    }
    // Keep the same logic as `List::getDimension` did.
    // upstream: isNumber(dim) || (!isNaN(dim) && !hasOwn(dimsByName, dim))
    if util.isNumber(dim)
        // If being a number-like string but not being defined a dimension name.
        || (!jsIsNaN(dim) && !dimsByName.hasKey(dim))
    {
        // upstream: return dimensions[dim as DimensionIndex];
        if let idx = toDimIndex(dim), idx >= 0, idx < dimensions.count {
            return dimensions[idx]
        }
        return nil
    }
    else if dimsByName.hasKey(dim) {   // upstream: hasOwn(dimsByName, dim)
        // upstream: return dimsByName[dim as DimensionName];
        return dimsByName.get(dim)
    }
    return nil
}

// upstream: function cloneAllDimensionInfo(dimensions): ExternalDimensionDefinition[]
private func cloneAllDimensionInfo(_ dimensions: [ExternalDimensionDefinition]) -> [ExternalDimensionDefinition] {
    // upstream: return clone(dimensions);
    //   `ExternalDimensionDefinition` is a value struct; array copy is a deep clone here.
    return dimensions
}


// upstream: const externalTransformMap = createHashMap<ExternalDataTransform, string>();
//   (the shim `HashMap<V>` drops the key generic; keyed by transform type string.)
private let externalTransformMap: HashMap<ExternalDataTransform> = createHashMap()

// upstream: export function registerExternalTransform(externalTransform): void
public func registerExternalTransform(_ externalTransformIn: ExternalDataTransform) throws {
    // upstream: externalTransform = clone(externalTransform);
    //   `ExternalDataTransform` is a value struct (the `transform` closure is a reference,
    //   which zrender `clone` also copies by reference), so a plain copy is faithful.
    var externalTransform = externalTransformIn
    var type = externalTransform.type
    var errMsg = ""
    if type.isEmpty {   // upstream: if (!type)
        if __DEV__ {
            errMsg = "Must have a `type` when `registerTransform`."
        }
        try log.throwError(errMsg)
    }
    let typeParsed = type.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
    if typeParsed.count != 2 {
        if __DEV__ {
            errMsg = "Name must include namespace like \"ns:regression\"."
        }
        try log.throwError(errMsg)
    }
    // Namespace 'echarts:xxx' is official namespace, where the transforms should
    // be called directly via 'xxx' rather than 'echarts:xxx'.
    var isBuiltIn = false
    if typeParsed[0] == "echarts" {
        type = typeParsed[1]
        isBuiltIn = true
    }
    externalTransform.__isBuiltIn = isBuiltIn
    externalTransformMap.set(type, externalTransform)
}

// upstream: { datasetIndex: number }
public struct DataTransformInfoForPrint {
    public var datasetIndex: Double
    public init(datasetIndex: Double) {
        self.datasetIndex = datasetIndex
    }
}

// upstream: export function applyDataTransform(rawTransOption, sourceList, infoForPrint): Source[]
public func applyDataTransform(
    // upstream: DataTransformOption | PipedDataTransformOption
    _ rawTransOption: Any,
    _ sourceListIn: [Source],
    _ infoForPrint: DataTransformInfoForPrint
) throws -> [Source] {
    var sourceList = sourceListIn
    // upstream: `const pipedTransOption = normalizeToArray(rawTransOption);`
    //   Upstream `DataTransformOption` is a plain JS object; in this port the raw option flows from
    //   the dynamic `[String: Any]` option bag (CONVENTIONS §2), NOT as a `DataTransformOption`
    //   struct. So `normalizeToArray<DataTransformOption>` cannot cast the dict — normalize the raw
    //   option (single dict / struct, or an array of them) into `DataTransformOption` structs here.
    let pipedTransOption: PipedDataTransformOption = normalizeTransformOptions(rawTransOption)
    let pipeLen = pipedTransOption.count

    var errMsg = ""
    if pipeLen == 0 {
        if __DEV__ {
            errMsg = "If `transform` declared, it should at least contain one transform."
        }
        try log.throwError(errMsg)
    }

    let len = pipeLen
    for i in 0..<len {
        let transOption = pipedTransOption[i]
        sourceList = try applySingleDataTransform(
            transOption, sourceList, infoForPrint, pipeLen == 1 ? nil : Double(i)
        )
        // piped transform only support single input, except the fist one.
        // piped transform only support single output, except the last one.
        if i != len - 1 {
            // upstream: sourceList.length = Math.max(sourceList.length, 1);
            //   Only grows an empty list by one (undefined) slot; a Swift `[Source]` cannot hold
            //   nil, and a transform always yields at least one result, so this is a no-op here.
            // PORT-NOTE (transform.ts:385): an empty `sourceList` would need a placeholder Source.
            if sourceList.isEmpty {
                // intentionally left as no-op (see note above)
            }
        }
    }

    return sourceList
}

// upstream: function applySingleDataTransform(transOption, upSourceList, infoForPrint, pipeIndex): Source[]
private func applySingleDataTransform(
    _ transOption: DataTransformOption,
    _ upSourceList: [Source],
    _ infoForPrint: DataTransformInfoForPrint,
    // If `pipeIndex` is null/undefined, no piped transform.
    _ pipeIndex: Double?
) throws -> [Source] {
    var errMsg = ""
    if upSourceList.isEmpty {
        if __DEV__ {
            errMsg = "Must have at least one upstream dataset."
        }
        try log.throwError(errMsg)
    }
    // upstream: if (!isObject(transOption)) { ... }
    //   `transOption` is a `DataTransformOption` struct here (always an object), so the guard
    //   cannot fail; kept as a faithful comment.

    let transType = transOption.type
    let externalTransform = externalTransformMap.get(transType)

    guard let externalTransform = externalTransform else {
        if __DEV__ {
            errMsg = "Can not find transform on type \"" + transType + "\"."
        }
        try log.throwError(errMsg)
        return []   // unreachable: throwError always throws.
    }

    // Prepare source
    // upstream: map(upSourceList, upSource => createExternalSource(upSource, externalTransform))
    //   (a manual loop is used because `createExternalSource` may `throwError`).
    var extUpSourceList: [ExternalSource] = []
    for upSource in upSourceList {
        extUpSourceList.append(try createExternalSource(upSource, externalTransform))
    }

    let resultList: [ExternalDataTransformResultItem] = model.normalizeToArray(
        externalTransform.transform(ExternalDataTransformParam(
            upstream: extUpSourceList[0],
            upstreamList: extUpSourceList,
            config: util.clone(transOption.config)
        ))
    )

    if __DEV__ {
        if transOption.print == true {
            // upstream: map(resultList, extSource => [...].join('\n')).join('\n')
            //   (the closure var `extSource` is actually a result item — it has `.data`/`.dimensions`.)
            let printStrArr = resultList.map { result -> String in
                let pipeIndexStr = pipeIndex != nil ? " === pipe index: " + jsNumberString(pipeIndex!) : ""
                return [
                    "=== dataset index: " + jsNumberString(infoForPrint.datasetIndex) + pipeIndexStr + " ===",
                    "- transform result data:",
                    log.makePrintable(result.data),
                    "- transform result dimensions:",
                    log.makePrintable(result.dimensions as Any)
                ].joined(separator: "\n")
            }.joined(separator: "\n")
            log.log(printStrArr)
        }
    }

    // upstream: return map(resultList, function (result, resultIndex) { ... })
    //   (a manual loop is used because the body may `throwError`.)
    var out: [Source] = []
    for resultIndex in 0..<resultList.count {
        var result = resultList[resultIndex]
        var errMsg = ""

        // upstream: if (!isObject(result)) { ... }
        //   `result` is an `ExternalDataTransformResultItem` struct (always an object); guard kept
        //   as a comment.

        // upstream: if (!result.data) { ... }
        if isNullish(result.data) {
            if __DEV__ {
                errMsg = "Transform result data should be not be null or undefined"
            }
            try log.throwError(errMsg)
        }

        let sourceFormat = detectSourceFormat(result.data)
        if !isSupportedSourceFormat(sourceFormat) {
            if __DEV__ {
                errMsg = "Transform result data should be array rows or object rows."
            }
            try log.throwError(errMsg)
        }

        let resultMetaRawOption: SourceMetaRawOption
        let firstUpSource: Source? = upSourceList.first

        /**
         * Intuitively, the end users known the content of the original `dataset.source`,
         * calucating the transform result in mind.
         * Suppose the original `dataset.source` is:
         * ```js
         * [
         *     ['product', '2012', '2013', '2014', '2015'],
         *     ['AAA', 41.1, 30.4, 65.1, 53.3],
         *     ['BBB', 86.5, 92.1, 85.7, 83.1],
         *     ['CCC', 24.1, 67.2, 79.5, 86.4]
         * ]
         * ```
         * The dimension info have to be detected from the source data.
         * Some of the transformers (like filter, sort) will follow the dimension info
         * of upstream, while others use new dimensions (like aggregate).
         * Transformer can output a field `dimensions` to define the its own output dimensions.
         * We also allow transformers to ignore the output `dimensions` field, and
         * inherit the upstream dimensions definition. It can reduce the burden of handling
         * dimensions in transformers.
         *
         * See also [DIMENSION_INHERIT_RULE] in `sourceManager.ts`.
         */
        if let firstUpSource = firstUpSource,
            resultIndex == 0,
            // If transformer returns `dimensions`, it means that the transformer has different
            // dimensions definitions. We do not inherit anything from upstream.
            result.dimensions == nil
        {
            let startIndex = firstUpSource.startIndex
            // We copy the header of upstream to the result, because:
            // (1) The returned data always does not contain header line and can not be used
            // as dimension-detection. In this case we can not use "detected dimensions" of
            // upstream directly, because it might be detected based on different `seriesLayoutBy`.
            // (2) We should support that the series read the upstream source in `seriesLayoutBy: 'row'`.
            // So the original detected header should be add to the result, otherwise they can not be read.
            if startIndex != 0 {   // upstream: if (startIndex)
                // upstream: result.data = firstUpSource.data.slice(0, startIndex).concat(result.data);
                let upData = (firstUpSource.data as? [Any]) ?? []
                let header = Array(upData.prefix(Int(startIndex)))
                let resultRows = (result.data as? [Any]) ?? []
                result.data = header + resultRows
            }

            resultMetaRawOption = SourceMetaRawOption(
                seriesLayoutBy: SERIES_LAYOUT_BY_COLUMN,
                sourceHeader: startIndex,
                dimensions: firstUpSource.metaRawOption?.dimensions
            )
        }
        else {
            resultMetaRawOption = SourceMetaRawOption(
                seriesLayoutBy: SERIES_LAYOUT_BY_COLUMN,
                sourceHeader: Double(0),   // Double (not Int) so downstream `isNumber` recognizes it — Int-vs-Double trap.
                dimensions: result.dimensions
            )
        }

        out.append(createSource(
            result.data,
            resultMetaRawOption,
            nil
        ))
    }
    return out
}

// Normalize the raw `transform` option into `DataTransformOption` structs.
//   Upstream `DataTransformOption` is a plain object read via `.type`/`.config`/`.print`; in this
//   port the runtime value is a `[String: Any]` (single) or `[[String: Any]]` (piped) from the
//   option bag (or an already-built struct/array in the programmatic `registerExternalTransform`
//   test path). Faithful to `normalizeToArray` + upstream's property reads.
private func normalizeTransformOptions(_ raw: Any) -> [DataTransformOption] {
    // Already a struct array (programmatic path).
    if let arr = raw as? [DataTransformOption] { return arr }
    // Single struct.
    if let one = raw as? DataTransformOption { return [one] }
    // Array of raw items (piped) — each a dict or a struct.
    if let arr = raw as? [Any] { return arr.compactMap { toDataTransformOption($0) } }
    // Single raw dict.
    if let single = toDataTransformOption(raw) { return [single] }
    return []
}

private func toDataTransformOption(_ item: Any) -> DataTransformOption? {
    if let s = item as? DataTransformOption { return s }
    if let dict = item as? [String: Any] {
        // `transOption.type` — required; a missing type yields "" so the "can not find transform"
        // guard in `applySingleDataTransform` fires (matching upstream's undefined-type lookup miss).
        let type = (dict["type"] as? String) ?? ""
        let config = dict["config"]                 // `transOption.config` (unknown -> Any?)
        let print = dict["print"] as? Bool          // `transOption.print`
        return DataTransformOption(type: type, config: config, print: print)
    }
    return nil
}

// upstream: function isSupportedSourceFormat(sourceFormat): boolean
private func isSupportedSourceFormat(_ sourceFormat: SourceFormat) -> Bool {
    return sourceFormat == SOURCE_FORMAT_ARRAY_ROWS || sourceFormat == SOURCE_FORMAT_OBJECT_ROWS
}


// ============================================================================
// Local helpers (not part of upstream): JS value coercions used by the routines above.
// ============================================================================

// JS `x || 0` for an optional/NaN Double (sheds nil AND NaN). Mirrors the port's `orZero` trap.
private func orZero(_ v: Double?) -> Double {
    guard let v = v, !v.isNaN else { return 0 }
    return v
}

// JS `x == null` (null or undefined). NSNull models an explicit JS `null`.
private func isNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// JS `isNaN(dim)` — coerces `dim` via `Number(dim)` and reports whether the result is NaN.
// Used by `getDimensionInfo` to detect number-like dimension references.
private func jsIsNaN(_ v: Any?) -> Bool {
    switch v {
    case nil: return true                        // Number(null|undefined) handled by caller; treated as NaN-safe here
    case let d as Double: return d.isNaN
    case let i as Int: _ = i; return false
    case let b as Bool: _ = b; return false      // Number(true)=1, Number(false)=0 -> not NaN
    case let s as String:
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return false }            // Number('') === 0 -> not NaN
        return Double(t) == nil
    default: return true
    }
}

// Coerce a number/number-like-string dimension reference to an `Int` index (JS `dimensions[dim]`).
private func toDimIndex(_ v: Any?) -> Int? {
    switch v {
    case let d as Double: return d.isFinite ? Int(d) : nil
    case let i as Int: return i
    case let s as String:
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(t), d.isFinite { return Int(d) }
        return nil
    default: return nil
    }
}

// JS `'' + number` for a Double (integral values print without a fraction). Used for print output.
private func jsNumberString(_ x: Double) -> String {
    if x == x.rounded() && Swift.abs(x) < 1e15 {
        return String(Int(x))
    }
    return String(x)
}
