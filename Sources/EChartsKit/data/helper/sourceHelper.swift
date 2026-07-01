// Ported from echarts/src/data/helper/sourceHelper.ts — keep in sync with upstream
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
//   import {makeInner, getDataItemValue, queryReferringComponents, SINGLE_REFERRING} from '../../util/model';
//       -> `model.makeInner` / `model.getDataItemValue` / `model.queryReferringComponents`
//          / `model.SINGLE_REFERRING` (util/model.swift, same module).
//   import { createHashMap, each, isArray, isString, isObject, isTypedArray, HashMap }
//       from 'zrender/src/core/util';
//       -> `each`/`isArray`/`isString`/`isObject`/`isTypedArray` are `ZRenderKit.util.*`;
//          `createHashMap`/`HashMap` are the EChartsKit local shim (util/model.swift) until
//          ZRenderKit ports them.
//   import { Source } from '../Source';                 -> data/Source.swift (same module)
//   import { ... } from '../../util/types';             -> util/types.swift (same module)
//   import { DatasetModel } from '../../component/dataset/install';
//       -> NOT ported yet (component layer). Forward-reference placeholder protocol below.
//   import SeriesModel from '../../model/Series';       -> SeriesModel placeholder (util/types.swift)
//   import GlobalModel from '../../model/Global';       -> GlobalModel placeholder (util/types.swift)
//   import { CoordDimensionDefinition } from './createDimensions';  -> data/helper/createDimensions.swift
import Foundation
import ZRenderKit

// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDER
// `DatasetModel` is imported by upstream from `../../component/dataset/install`,
// which is NOT ported in this phase (component layer). It is declared here as a
// minimal placeholder so this file compiles. The agent that ports
// `component/dataset/install` MUST remove this placeholder and replace it with
// the real, fully-ported type. Only `uid` is exercised by live code here; the
// rest of the DatasetModel surface (`get`, `ecModel`, `transform`,
// `fromTransformResult`, …) is referenced only inside the faithful bodies that
// are stubbed/commented until the model layer lands (Phase 5c).
// ============================================================================
public protocol DatasetModel: AnyObject {                                  // PORT-TODO: belongs to component/dataset/install
    var uid: String { get }
}

// upstream: type BeOrdinalValue = (typeof BE_ORDINAL)[keyof typeof BE_ORDINAL]
// (declared after BE_ORDINAL upstream; hoisted here so `BE_ORDINAL` and `detectValue`
//  can refer to it.)
public typealias BeOrdinalValue = Double

// upstream: interface DatasetRecord { categoryWayDim: number; valueWayDim: number; }
// Modeled as a `final class` (reference) because upstream caches it in `datasetMap`
// and then mutates `valueWayDim`/`categoryWayDim` through the aliased record
// (`datasetRecord.valueWayDim += count`), relying on JS object identity (CONVENTIONS §4).
final class DatasetRecord {
    var categoryWayDim: Double
    var valueWayDim: Double
    init(categoryWayDim: Double, valueWayDim: Double) {
        self.categoryWayDim = categoryWayDim
        self.valueWayDim = valueWayDim
    }
}

// upstream: type SeriesEncodeInternal = { [key in keyof OptionEncode]: DimensionIndex[] };
public typealias SeriesEncodeInternal = [DimensionName: [DimensionIndex]]

// The anonymous bag `{ datasetMap: HashMap<DatasetRecord, string> }` stored per GlobalModel.
// Modeled as a `final class` (per `model.makeInner`, which keys by host object identity).
// `datasetMap` is set by `resetSourceDefaulter` before any encode is made, hence `!`.
final class SourceHelperGlobalInner {
    var datasetMap: HashMap<DatasetRecord>!   // upstream: HashMap<DatasetRecord, string> (shim drops key generic)
}

// upstream: const innerGlobalModel = makeInner<{ datasetMap: ... }, GlobalModel>();
// PORT-TODO: `model.makeInner` requires a concrete class host (it builds a `WeakMap<Host, T>`),
//   but `GlobalModel` is currently a protocol-existential placeholder (the real GlobalModel class
//   is ported in Phase 5c). Implemented here as an object-identity keyed store with the same
//   `innerGlobalModel(ecModel)` call shape; switch to `model.makeInner` once GlobalModel is a class.
private final class SourceHelperGlobalInnerStore {
    private var map: [ObjectIdentifier: SourceHelperGlobalInner] = [:]   // PORT-TODO: strong (vs WeakMap)
    func callAsFunction(_ host: GlobalModel) -> SourceHelperGlobalInner {
        let id = ObjectIdentifier(host as AnyObject)
        if let existing = map[id] {
            return existing
        }
        let created = SourceHelperGlobalInner()
        map[id] = created
        return created
    }
}
private let innerGlobalModel = SourceHelperGlobalInnerStore()

// `sourceHelper.ts` is a free-function module -> caseless `enum` namespace `sourceHelper`
// (CONVENTIONS §2). Call sites stay identical to upstream named imports, e.g.
// `sourceHelper.guessOrdinal(...)`, `sourceHelper.BE_ORDINAL.Must` (see data/Source.swift).
public enum sourceHelper {

    // The result of `guessOrdinal`.
    // upstream: const BE_ORDINAL = { Must: 1, Might: 2, Not: 3 } (const object used as enum
    //   -> caseless enum of static lets, CONVENTIONS §2).
    public enum BE_ORDINAL {
        public static let Must: BeOrdinalValue = 1 // Encounter string but not '-' and not number-like.
        public static let Might: BeOrdinalValue = 2 // Encounter string but number-like.
        public static let Not: BeOrdinalValue = 3 // Other cases
    }

    /**
     * MUST be called before mergeOption of all series.
     */
    public static func resetSourceDefaulter(_ ecModel: GlobalModel) {
        // `datasetMap` is used to make default encode.
        innerGlobalModel(ecModel).datasetMap = createHashMap()
    }

    /**
     * [The strategy of the arrengment of data dimensions for dataset]:
     * "value way": all axes are non-category axes. So series one by one take
     *     several (the number is coordSysDims.length) dimensions from dataset.
     *     The result of data arrengment of data dimensions like:
     *     | ser0_x | ser0_y | ser1_x | ser1_y | ser2_x | ser2_y |
     * "category way": at least one axis is category axis. So the the first data
     *     dimension is always mapped to the first category axis and shared by
     *     all of the series. The other data dimensions are taken by series like
     *     "value way" does.
     *     The result of data arrengment of data dimensions like:
     *     | ser_shared_x | ser0_y | ser1_y | ser2_y |
     *
     * @return encode Never be `null/undefined`.
     */
    public static func makeSeriesEncodeForAxisCoordSys(
        _ coordDimensionsInput: [CoordDimensionDefinitionLoose],
        _ seriesModel: SeriesModel,
        _ source: Source
    ) -> SeriesEncodeInternal {
        var encode: SeriesEncodeInternal = [:]

        let datasetModel = querySeriesUpstreamDatasetModel(seriesModel)
        // Currently only make default when using dataset, util more reqirements occur.
        // (`!coordDimensions` is always false here: a non-optional array is passed.)
        guard let datasetModel = datasetModel else {
            return encode
        }

        var encodeItemName: [DimensionIndex] = []
        var encodeSeriesName: [DimensionIndex] = []

        // upstream `ComponentModel.ecModel` is non-null; `Model.ecModel` is `GlobalModel?` in the port
        // (see the reconciliation PORT-TODO in util/types.swift, resolved now that model/Global landed).
        let ecModel = seriesModel.ecModel!
        let datasetMap = innerGlobalModel(ecModel).datasetMap!
        let key = datasetModel.uid + "_" + source.seriesLayoutBy

        var baseCategoryDimIndex: Double?
        var categoryWayValueDimStart: Double?
        var coordDimensions = coordDimensionsInput   // coordDimensions.slice()
        util.each(coordDimensions) { coordDimInfoLoose, coordDimIdx in
            // isObject(coordDimInfoLoose) ? coordDimInfoLoose : (coordDimensions[i] = { name: ... })
            // PORT-TODO: upstream uses `isObject(...)`; modeled as a type-cast because
            //   `CoordDimensionDefinition` is a Swift value struct (util.isObject only
            //   recognizes class instances / dictionaries).
            let coordDimInfo: CoordDimensionDefinition
            if let c = coordDimInfoLoose as? CoordDimensionDefinition {
                coordDimInfo = c
            }
            else {
                var created = CoordDimensionDefinition()
                created.name = coordDimInfoLoose as? DimensionName
                coordDimensions[coordDimIdx] = created
                coordDimInfo = created
            }
            if coordDimInfo.type == .ordinal && baseCategoryDimIndex == nil {
                baseCategoryDimIndex = Double(coordDimIdx)
                categoryWayValueDimStart = getDataDimCountOnCoordDim(coordDimInfo)
            }
            encode[coordDimInfo.name!] = []   // PORT-TODO: `name` is non-null DimensionName by construction
        }

        // datasetMap.get(key) || datasetMap.set(key, {categoryWayDim: categoryWayValueDimStart, valueWayDim: 0})
        // PORT-TODO: `categoryWayValueDimStart` can be undefined upstream when there is no ordinal
        //   coord dim; in that case `categoryWayDim` is never read (value-way path), so `?? 0` is benign.
        let datasetRecord = datasetMap.get(key)
            ?? datasetMap.set(key, DatasetRecord(categoryWayDim: categoryWayValueDimStart ?? 0, valueWayDim: 0))

        // TODO
        // Auto detect first time axis and do arrangement.
        util.each(coordDimensions) { coordDimInfoAny, coordDimIdx in
            let coordDimInfo = coordDimInfoAny as! CoordDimensionDefinition   // normalized to object in the loop above
            let coordDimName = coordDimInfo.name
            let count = getDataDimCountOnCoordDim(coordDimInfo)

            // In value way.
            if baseCategoryDimIndex == nil {
                let start = datasetRecord.valueWayDim
                pushDim(&encode[coordDimName!, default: []], start, count)
                pushDim(&encodeSeriesName, start, count)
                datasetRecord.valueWayDim += count

                // ??? TODO give a better default series name rule?
                // especially when encode x y specified.
                // consider: when multiple series share one dimension
                // category axis, series name should better use
                // the other dimension name. On the other hand, use
                // both dimensions name.
            }
            // In category way, the first category axis.
            else if baseCategoryDimIndex == Double(coordDimIdx) {
                pushDim(&encode[coordDimName!, default: []], 0, count)
                pushDim(&encodeItemName, 0, count)
            }
            // In category way, the other axis.
            else {
                let start = datasetRecord.categoryWayDim
                pushDim(&encode[coordDimName!, default: []], start, count)
                pushDim(&encodeSeriesName, start, count)
                datasetRecord.categoryWayDim += count
            }
        }

        func pushDim(_ dimIdxArr: inout [DimensionIndex], _ idxFrom: Double, _ idxCount: Double) {
            var i = 0
            while Double(i) < idxCount {
                dimIdxArr.append(idxFrom + Double(i))
                i += 1
            }
        }

        func getDataDimCountOnCoordDim(_ coordDimInfo: CoordDimensionDefinition) -> Double {
            let dimsDef = coordDimInfo.dimsDef
            return dimsDef != nil ? Double(dimsDef!.count) : 1
        }

        if !encodeItemName.isEmpty { encode["itemName"] = encodeItemName }
        if !encodeSeriesName.isEmpty { encode["seriesName"] = encodeSeriesName }

        return encode
    }

    /**
     * Work for data like [{name: ..., value: ...}, ...].
     *
     * @return encode Never be `null/undefined`.
     */
    public static func makeSeriesEncodeForNameBased(
        _ seriesModel: SeriesModel,
        _ source: Source,
        _ dimCount: Double
    ) -> SeriesEncodeInternal {
        var encode: SeriesEncodeInternal = [:]

        let datasetModel = querySeriesUpstreamDatasetModel(seriesModel)
        // Currently only make default when using dataset, util more reqirements occur.
        if datasetModel == nil {
            return encode
        }

        let sourceFormat = source.sourceFormat
        let dimensionsDefine = source.dimensionsDefine

        var potentialNameDimIndex: Double?
        if sourceFormat == SOURCE_FORMAT_OBJECT_ROWS || sourceFormat == SOURCE_FORMAT_KEYED_COLUMNS {
            util.each(dimensionsDefine) { dim, idx in
                // (isObject(dim) ? dim.name : dim) === 'name'
                // PORT-TODO: `dimensionsDefine` is `DimensionDefinition[]` (always objects);
                //   the `isString(dim)` arm of upstream is unreachable here.
                if dim.name == "name" {
                    potentialNameDimIndex = Double(idx)
                }
            }
        }

        struct IdxResult { var v: Double?; var n: Double? }

        // upstream IIFE assigned to `idxResult`.
        let idxResult: IdxResult? = {
            var idxRes0 = IdxResult(v: nil, n: nil)
            var idxRes1 = IdxResult(v: nil, n: nil)
            var guessRecords: [BeOrdinalValue] = []

            func fulfilled(_ idxResult: IdxResult) -> Bool {
                return idxResult.v != nil && idxResult.n != nil
            }

            // 5 is an experience value.
            let len = Int(Swift.min(5, dimCount))
            var i = 0
            while i < len {
                let guessResult = doGuessOrdinal(
                    source.data, sourceFormat, source.seriesLayoutBy,
                    dimensionsDefine, source.startIndex, Double(i)
                )
                guessRecords.append(guessResult)
                let isPureNumber = guessResult == BE_ORDINAL.Not

                // [Strategy of idxRes0]: find the first BE_ORDINAL.Not as the value dim,
                // and then find a name dim with the priority:
                // "BE_ORDINAL.Might|BE_ORDINAL.Must" > "other dim" > "the value dim itself".
                if isPureNumber && idxRes0.v == nil && Double(i) != potentialNameDimIndex {
                    idxRes0.v = Double(i)
                }
                if idxRes0.n == nil
                    || (idxRes0.n == idxRes0.v)
                    || (!isPureNumber && guessRecords[Int(idxRes0.n!)] == BE_ORDINAL.Not) {
                    idxRes0.n = Double(i)
                }
                if fulfilled(idxRes0) && guessRecords[Int(idxRes0.n!)] != BE_ORDINAL.Not {
                    return idxRes0
                }

                // [Strategy of idxRes1]: if idxRes0 not satisfied (that is, no BE_ORDINAL.Not),
                // find the first BE_ORDINAL.Might as the value dim,
                // and then find a name dim with the priority:
                // "other dim" > "the value dim itself".
                // That is for backward compat: number-like (e.g., `'3'`, `'55'`) can be
                // treated as number.
                if !isPureNumber {
                    if guessResult == BE_ORDINAL.Might && idxRes1.v == nil && Double(i) != potentialNameDimIndex {
                        idxRes1.v = Double(i)
                    }
                    if idxRes1.n == nil || (idxRes1.n == idxRes1.v) {
                        idxRes1.n = Double(i)
                    }
                }
                i += 1
            }

            return fulfilled(idxRes0) ? idxRes0 : (fulfilled(idxRes1) ? idxRes1 : nil)
        }()

        if let idxResult = idxResult {
            encode["value"] = [idxResult.v!]
            // `potentialNameDimIndex` has highest priority.
            let nameDimIndex = potentialNameDimIndex != nil ? potentialNameDimIndex! : idxResult.n!
            // By default, label uses itemName in charts.
            // So we don't set encodeLabel here.
            encode["itemName"] = [nameDimIndex]
            encode["seriesName"] = [nameDimIndex]
        }

        return encode
    }

    /**
     * @return If return null/undefined, indicate that should not use datasetModel.
     */
    public static func querySeriesUpstreamDatasetModel(
        _ seriesModel: SeriesEncodableModel
    ) -> DatasetModel? {
        // Caution: consider the scenario:
        // A dataset is declared and a series is not expected to use the dataset,
        // and at the beginning `setOption({series: { noData })` (just prepare other
        // option but no data), then `setOption({series: {data: [...]}); In this case,
        // the user should set an empty array to avoid that dataset is used by default.
        //
        // PORT-TODO (Phase 5c): requires `SeriesModel.get(...)` and
        //   `model.queryReferringComponents` wiring against a real `GlobalModel`
        //   (the model layer is not yet ported). Returns nil meanwhile, so the encode
        //   defaulters fall back to the "no dataset" path. Faithful body preserved below:
        //
        // const thisData = seriesModel.get('data', true);
        // if (!thisData) {
        //     return queryReferringComponents(
        //         seriesModel.ecModel,
        //         'dataset',
        //         {
        //             index: seriesModel.get('datasetIndex', true),
        //             id: seriesModel.get('datasetId', true)
        //         },
        //         SINGLE_REFERRING
        //     ).models[0] as DatasetModel;
        // }
        _ = seriesModel
        return nil
    }

    /**
     * @return Always return an array event empty.
     */
    public static func queryDatasetUpstreamDatasetModels(
        _ datasetModel: DatasetModel
    ) -> [DatasetModel] {
        // Only these attributes declared, we by default reference to `datasetIndex: 0`.
        // Otherwise, no reference.
        //
        // PORT-TODO (Phase 5c): requires `DatasetModel.get(...)` and
        //   `model.queryReferringComponents` against a real `GlobalModel`. Returns []
        //   meanwhile. Faithful body preserved below:
        //
        // if (!datasetModel.get('transform', true)
        //     && !datasetModel.get('fromTransformResult', true)
        // ) {
        //     return [];
        // }
        // return queryReferringComponents(
        //     datasetModel.ecModel,
        //     'dataset',
        //     {
        //         index: datasetModel.get('fromDatasetIndex', true),
        //         id: datasetModel.get('fromDatasetId', true)
        //     },
        //     SINGLE_REFERRING
        // ).models as DatasetModel[];
        _ = datasetModel
        return []
    }

    /**
     * The rule should not be complex, otherwise user might not
     * be able to known where the data is wrong.
     * The code is ugly, but how to make it neat?
     */
    public static func guessOrdinal(_ source: Source, _ dimIndex: DimensionIndex) -> BeOrdinalValue {
        return doGuessOrdinal(
            source.data,
            source.sourceFormat,
            source.seriesLayoutBy,
            source.dimensionsDefine,
            source.startIndex,
            dimIndex
        )
    }

    // dimIndex may be overflow source data.
    // return {BE_ORDINAL}
    private static func doGuessOrdinal(
        _ data: OptionSourceData,
        _ sourceFormat: SourceFormat,
        _ seriesLayoutBy: SeriesLayoutBy,
        _ dimensionsDefine: [DimensionDefinition]?,
        _ startIndex: Double,
        _ dimIndex: DimensionIndex
    ) -> BeOrdinalValue {
        // Experience value.
        let maxLoop = 5

        if util.isTypedArray(data) {
            return BE_ORDINAL.Not
        }

        // When sourceType is 'objectRows' or 'keyedColumns', dimensionsDefine
        // always exists in source.
        var dimName: DimensionName?
        var dimType: DataStoreDimensionType?
        if let dimensionsDefine = dimensionsDefine {
            let di = Int(dimIndex)
            let dimDefItem: DimensionDefinition? = (di >= 0 && di < dimensionsDefine.count) ? dimensionsDefine[di] : nil
            // PORT-TODO: `dimensionsDefine` is `DimensionDefinition[]` (always object items); the
            //   upstream `isObject(dimDefItem)` arm always holds and the `isString(dimDefItem)` arm
            //   is unreachable here.
            if let dimDefItem = dimDefItem {
                dimName = dimDefItem.name
                dimType = dimDefItem.type
            }
        }

        if dimType != nil {
            return dimType == .ordinal ? BE_ORDINAL.Must : BE_ORDINAL.Not
        }

        if sourceFormat == SOURCE_FORMAT_ARRAY_ROWS {
            let dataArrayRows = (data as? [Any]) ?? []   // OptionSourceDataArrayRows
            if seriesLayoutBy == SERIES_LAYOUT_BY_ROW {
                let di = Int(dimIndex)
                let sample = (di >= 0 && di < dataArrayRows.count) ? (dataArrayRows[di] as? [Any]) : nil
                let sampleArr = sample ?? []   // (sample || [])
                var i = 0
                while i < sampleArr.count && i < maxLoop {
                    // result = detectValue(sample[startIndex + i])
                    if let result = detectValue(arrAt(sampleArr, Int(startIndex) + i)) {
                        return result
                    }
                    i += 1
                }
            }
            else {
                var i = 0
                while i < dataArrayRows.count && i < maxLoop {
                    let row = arrAt(dataArrayRows, Int(startIndex) + i) as? [Any]
                    // if (row && (result = detectValue(row[dimIndex])) != null)
                    if let row = row, let result = detectValue(arrAt(row, Int(dimIndex))) {
                        return result
                    }
                    i += 1
                }
            }
        }
        else if sourceFormat == SOURCE_FORMAT_OBJECT_ROWS {
            let dataObjectRows = (data as? [Any]) ?? []   // OptionSourceDataObjectRows
            if dimName == nil {
                return BE_ORDINAL.Not
            }
            var i = 0
            while i < dataObjectRows.count && i < maxLoop {
                let item = dataObjectRows[i] as? [String: Any]
                if let item = item, let result = detectValue(item[dimName!]) {
                    return result
                }
                i += 1
            }
        }
        else if sourceFormat == SOURCE_FORMAT_KEYED_COLUMNS {
            let dataKeyedColumns = (data as? [String: Any]) ?? [:]   // OptionSourceDataKeyedColumns
            if dimName == nil {
                return BE_ORDINAL.Not
            }
            let sampleAny = dataKeyedColumns[dimName!]
            if sampleAny == nil || sampleAny is NSNull || util.isTypedArray(sampleAny) {
                return BE_ORDINAL.Not
            }
            let sample = (sampleAny as? [Any]) ?? []
            var i = 0
            while i < sample.count && i < maxLoop {
                if let result = detectValue(sample[i]) {
                    return result
                }
                i += 1
            }
        }
        else if sourceFormat == SOURCE_FORMAT_ORIGINAL {
            let dataOriginal = (data as? [Any]) ?? []   // OptionSourceDataOriginal
            var i = 0
            while i < dataOriginal.count && i < maxLoop {
                let item = dataOriginal[i]
                let val = model.getDataItemValue(item)
                if !util.isArray(val) {
                    return BE_ORDINAL.Not
                }
                if let result = detectValue(arrAt((val as? [Any]) ?? [], Int(dimIndex))) {
                    return result
                }
                i += 1
            }
        }

        func detectValue(_ val: OptionDataValue) -> BeOrdinalValue? {
            let beStr = util.isString(val)
            // Consider usage convenience, '1', '2' will be treated as "number".
            // `Number('')` (or any whitespace) is `0`.
            // `Number(val)` prevents error for BigInt.
            if val != nil && !(val is NSNull) && jsNumber(val).isFinite && !(isEmptyJSString(val)) {
                return beStr ? BE_ORDINAL.Might : BE_ORDINAL.Not
            }
            else if beStr && (val as? String) != "-" {
                return BE_ORDINAL.Must
            }
            return nil
        }

        return BE_ORDINAL.Not
    }

    // JS out-of-bounds index access yields `undefined`; this mirrors `arr[i]` returning nil.
    // Not a standalone upstream symbol.
    private static func arrAt(_ arr: [Any], _ i: Int) -> Any? {
        return (i >= 0 && i < arr.count) ? arr[i] : nil
    }

    // JS `val !== ''`. Not a standalone upstream symbol.
    private static func isEmptyJSString(_ val: Any?) -> Bool {
        return (val as? String) == ""
    }

    // JS `Number(val)` coercion (used by `detectValue`). Not a standalone upstream symbol.
    // PORT-TODO: hex strings ('0x10'), 'Infinity', BigInt, and Date coercions are not handled;
    //   these do not arise for the value-classification heuristic here.
    private static func jsNumber(_ val: Any?) -> Double {
        switch val {
        case nil: return 0                       // Number(null) === 0 (guarded before this call)
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let b as Bool: return b ? 1 : 0
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return 0 }            // Number('') === 0
            return Double(t) ?? Double.nan       // Number('abc') === NaN
        default: return Double.nan
        }
    }
}
