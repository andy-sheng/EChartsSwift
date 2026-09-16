// Ported from echarts/src/data/helper/dataStackHelper.ts — keep in sync with upstream
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

// import {each, isString} from 'zrender/src/core/util';   -> ZRenderKit util.each / util.isString
// import SeriesDimensionDefine from '../SeriesDimensionDefine';                 -> data/SeriesDimensionDefine.swift
// import SeriesModel from '../../model/Series';                                 -> SeriesModel placeholder (util/types.swift); model layer is Phase 5c
// import SeriesData, { DataCalculationInfo } from '../SeriesData';              -> SeriesData placeholder (util/types.swift); SeriesData is not yet ported
// import type { SeriesOption, SeriesStackOptionMixin, DimensionName } from '../../util/types';  -> util/types.swift (DimensionName)
// import { isSeriesDataSchema, SeriesDataSchema } from './SeriesDataSchema';    -> data/helper/SeriesDataSchema.swift
// import DataStore from '../DataStore';                                         -> sibling data/DataStore (this phase)
import Foundation
import ZRenderKit

// model/Series (model/Series.swift) is ported. This file needs only `seriesModel.get('stack')`
// and `seriesModel.id`, so it declares the minimal `DataStackSeriesModel` surface here and the real
// SeriesModel conforms to it (avoids a hard dependency on the full model layer).
public protocol DataStackSeriesModel: AnyObject {
    func get(_ key: String) -> Any?
    var id: String { get }
}

// `SeriesData` (data/SeriesData.swift) is ported. This file needs only `data.getCalculationInfo(key)`
// (which returns `DataCalculationInfo[key]`), so it declares the minimal `DataStackSeriesData` surface here
// and the real SeriesData conforms to it.
public protocol DataStackSeriesData: AnyObject {
    func getCalculationInfo(_ key: String) -> Any?
}

// type EnableDataStackDimensionsInput = { schema: SeriesDataSchema; store?: DataStore; };
public struct EnableDataStackDimensionsInput {
    public var schema: SeriesDataSchema
    // If given, stack dimension will be ensured on this store.
    // Otherwise, stack dimension will be appended at the tail, and should not
    // be used on a shared store, but should create a brand new storage later.
    public var store: DataStore?
    public init(schema: SeriesDataSchema, store: DataStore? = nil) {
        self.schema = schema
        self.store = store
    }
}
// type EnableDataStackDimensionsInputLegacy = (SeriesDimensionDefine | string)[];
// TS union element `SeriesDimensionDefine | string` -> `[Any]` whose elements are
// either `String` or `SeriesDimensionDefine` (CONVENTIONS dynamic-bag mapping).
public typealias EnableDataStackDimensionsInputLegacy = [Any]

// upstream union param: `EnableDataStackDimensionsInput | EnableDataStackDimensionsInputLegacy`.
public enum EnableDataStackDimensions {
    case input(EnableDataStackDimensionsInput)
    case legacy(EnableDataStackDimensionsInputLegacy)
}

// upstream optional `opt` arg of `enableDataStack`.
public struct EnableDataStackOpt {
    // Backward compat
    public var stackedCoordDimension: String?
    public var byIndex: Bool?
    public init(stackedCoordDimension: String? = nil, byIndex: Bool? = nil) {
        self.stackedCoordDimension = stackedCoordDimension
        self.byIndex = byIndex
    }
}

// upstream return type is
//   Pick<DataCalculationInfo<unknown>, 'stackedDimension' | 'stackedByDimension'
//        | 'isStackedByIndex' | 'stackedOverDimension' | 'stackResultDimension'>.
// The values are produced by short-circuit expressions (`stackedDimInfo && stackedDimInfo.name`)
// so they can be `undefined`; modeled here as optionals.
public struct EnableDataStackResult {
    public var stackedDimension: DimensionName?
    public var stackedByDimension: DimensionName?
    public var isStackedByIndex: Bool?
    public var stackedOverDimension: DimensionName?
    public var stackResultDimension: DimensionName?
}

/**
 * Note that it is too complicated to support 3d stack by value
 * (have to create two-dimension inverted index), so in 3d case
 * we just support that stacked by index.
 *
 * Stack is calculated in `src/processor/dataStack.ts`.
 *
 * @param seriesModel
 * @param dimensionsInput The same as the input of <module:echarts/data/SeriesData>.
 *        The input will be modified.
 * @param opt
 * @param opt.stackedCoordDimension Specify a coord dimension if needed.
 * @param opt.byIndex=false
 * @return calculationInfo
 * {
 *     stackedDimension: string
 *     stackedByDimension: string
 *     isStackedByIndex: boolean
 *     stackedOverDimension: string
 *     stackResultDimension: string
 * }
 */
// `dimensionsInput` is `inout` because upstream mutates the (legacy) input array
// in place ("The input will be modified."): string entries are replaced by `SeriesDimensionDefine`
// and the two calculation dimensions are pushed onto it. The schema branch mutates the
// `SeriesDataSchema` reference instead, so it needs no write-back.
public func enableDataStack(
    _ seriesModel: SeriesModel,
    _ dimensionsInput: inout EnableDataStackDimensions,
    _ opt: EnableDataStackOpt? = nil
) -> EnableDataStackResult {
    let opt = opt ?? EnableDataStackOpt()
    var byIndex = opt.byIndex
    let stackedCoordDimension = opt.stackedCoordDimension

    var dimensionDefineList: EnableDataStackDimensionsInputLegacy
    var schema: SeriesDataSchema?
    var store: DataStore?

    let isLegacy = isLegacyDimensionsInput(dimensionsInput)
    switch dimensionsInput {
    case .legacy(let list):
        dimensionDefineList = list
    case .input(let input):
        schema = input.schema
        dimensionDefineList = input.schema.dimensions   // schema.dimensions
        store = input.store
    }

    // compatible: when `stack` is set as '', do not stack.
    // `seriesModel.get('stack')` via the DataStackSeriesModel surface. JS `!!` truthiness on
    // the returned option (a string); '' counts as false.
    let mayStack = jsTruthy((seriesModel as DataStackSeriesModel).get("stack"))
    var stackedByDimInfo: SeriesDimensionDefine?
    var stackedDimInfo: SeriesDimensionDefine?
    var stackResultDimension: String?
    var stackedOverDimension: String?
    var allDimTypesAreNotOrdinalAndTime = true

    func dimTypeIsNotOrdinalAndTime(_ dimensionInfo: SeriesDimensionDefine) -> Bool {
        return dimensionInfo.type != .ordinal && dimensionInfo.type != .time
    }

    util.each(dimensionDefineList) { (dimensionInfoAny: Any, index: Int) in
        var dimensionInfo = dimensionInfoAny
        if util.isString(dimensionInfo) {
            let def = SeriesDimensionDefine()
            def.name = dimensionInfo as! String
            dimensionDefineList[index] = def
            dimensionInfo = def
        }
        if let dimensionInfo = dimensionInfo as? SeriesDimensionDefine {
            if !dimTypeIsNotOrdinalAndTime(dimensionInfo) {
                allDimTypesAreNotOrdinalAndTime = false
            }
        }
    }

    util.each(dimensionDefineList) { (dimensionInfoAny: Any, index: Int) in
        guard let dimensionInfo = dimensionInfoAny as? SeriesDimensionDefine else { return }
        if mayStack && !((dimensionInfo.isExtraCoord) ?? false) {
            // Find the first ordinal dimension as the stackedByDimInfo.
            if !(byIndex ?? false) && stackedByDimInfo == nil && dimensionInfo.ordinalMeta != nil {
                stackedByDimInfo = dimensionInfo
            }
            // Find the first stackable dimension as the stackedDimInfo.
            if stackedDimInfo == nil
                && dimTypeIsNotOrdinalAndTime(dimensionInfo)
                // FIXME:
                //  This rule MUST be consistent with `Cartesian2D['getBaseAxis']` and `Polar['getBaseAxis']`
                //  Need refactor - merge them!
                //  See comments in `Cartesian2D['getBaseAxis']` for details.
                && (!allDimTypesAreNotOrdinalAndTime
                    || (
                        dimensionInfo.coordDim != "x"
                        && dimensionInfo.coordDim != "angle"
                    )
                )
                && (stackedCoordDimension == nil
                    || stackedCoordDimension == ""
                    || stackedCoordDimension == dimensionInfo.coordDim)
            {
                stackedDimInfo = dimensionInfo
            }
        }
    }

    if stackedDimInfo != nil && !(byIndex ?? false) && stackedByDimInfo == nil {
        // "Stack by data index" makes sense only if users provide carefully constructed data - any
        // mismatch or absence of data items can cause incorrect results. By "Stack by data index"
        // is more performant - no hashmap is required.
        // PENDING:
        //  Compatible with previous design, non-category axis ("value"/"log"/"time" axis) can only
        //  stack by index. "Stack by value" will not be supported until concrete requirements arise.
        byIndex = true
    }

    if let stackedDimInfo = stackedDimInfo {
        // Use a weird name that not duplicated with other names.
        // Also need to use seriesModel.id as postfix because different
        // series may share same data store. The stack dimension needs to be distinguished.
        // `seriesModel.id` via the DataStackSeriesModel surface.
        let seriesId = (seriesModel as DataStackSeriesModel).id
        stackResultDimension = "__\u{0}ecstackresult_" + seriesId
        stackedOverDimension = "__\u{0}ecstackedover_" + seriesId

        // Create inverted index to fast query index by value.
        if let stackedByDimInfo = stackedByDimInfo {
            stackedByDimInfo.createInvertedIndices = true
        }

        let stackedDimCoordDim = stackedDimInfo.coordDim
        let stackedDimType = stackedDimInfo.type
        var stackedDimCoordIndex = 0.0

        util.each(dimensionDefineList) { (dimensionInfoAny: Any, _: Int) in
            guard let dimensionInfo = dimensionInfoAny as? SeriesDimensionDefine else { return }
            if dimensionInfo.coordDim == stackedDimCoordDim {
                stackedDimCoordIndex += 1
            }
        }

        let stackedOverDimensionDefine = SeriesDimensionDefine()
        stackedOverDimensionDefine.name = stackResultDimension!   // set non-nil above
        stackedOverDimensionDefine.coordDim = stackedDimCoordDim
        stackedOverDimensionDefine.coordDimIndex = stackedDimCoordIndex
        stackedOverDimensionDefine.type = stackedDimType
        stackedOverDimensionDefine.isExtraCoord = true
        stackedOverDimensionDefine.isCalculationCoord = true
        stackedOverDimensionDefine.storeDimIndex = Double(dimensionDefineList.count)

        let stackResultDimensionDefine = SeriesDimensionDefine()
        stackResultDimensionDefine.name = stackedOverDimension!   // set non-nil above
        // This dimension contains stack base (generally, 0), so do not set it as
        // `stackedDimCoordDim` to avoid extent calculation, consider log scale.
        stackResultDimensionDefine.coordDim = stackedOverDimension
        stackResultDimensionDefine.coordDimIndex = stackedDimCoordIndex + 1
        stackResultDimensionDefine.type = stackedDimType
        stackResultDimensionDefine.isExtraCoord = true
        stackResultDimensionDefine.isCalculationCoord = true
        stackResultDimensionDefine.storeDimIndex = Double(dimensionDefineList.count) + 1

        if let schema = schema {
            if let store = store {
                // the ported `DataStore.ensureCalculationDimension(dimName, type)`
                // takes a non-optional `DataStoreDimensionType`, while `stackedDimType` (the dim
                // define's `type?`) may be `nil`. Upstream tolerates `undefined` (uses `type || 'float'`
                // internally), so default to `.float` here to match that fallback.
                stackedOverDimensionDefine.storeDimIndex =
                    store.ensureCalculationDimension(stackedOverDimension!, stackedDimType ?? .float)
                stackResultDimensionDefine.storeDimIndex =
                    store.ensureCalculationDimension(stackResultDimension!, stackedDimType ?? .float)
            }

            schema.appendCalculationDimension(stackedOverDimensionDefine)
            schema.appendCalculationDimension(stackResultDimensionDefine)
        }
        else {
            dimensionDefineList.append(stackedOverDimensionDefine)
            dimensionDefineList.append(stackResultDimensionDefine)
        }
    }

    // Write back the (possibly mutated) legacy array. The schema branch mutates the
    // `SeriesDataSchema` reference directly, so no write-back is needed there.
    if isLegacy {
        dimensionsInput = .legacy(dimensionDefineList)
    }

    return EnableDataStackResult(
        stackedDimension: stackedDimInfo.map { $0.name },
        stackedByDimension: stackedByDimInfo.map { $0.name },
        isStackedByIndex: byIndex,
        stackedOverDimension: stackedOverDimension,
        stackResultDimension: stackResultDimension
    )
}

private func isLegacyDimensionsInput(
    _ dimensionsInput: EnableDataStackDimensions
) -> Bool {
    switch dimensionsInput {
    case .input(let input):
        return !isSeriesDataSchema(input.schema)
    case .legacy:
        // `(dimensionsInput as EnableDataStackDimensionsInput).schema` is undefined here,
        // so `isSeriesDataSchema` is false and the input is legacy.
        return true
    }
}

public func isDimensionStacked(_ data: SeriesData, _ stackedDim: String) -> Bool {
    // Each single series only maps to one pair of axis. So we do not need to
    // check stackByDim, whatever stacked by a dimension or stacked by index.
    // `data.getCalculationInfo('stackedDimension')` — provided by SeriesData (data/SeriesData.swift).
    return !stackedDim.isEmpty
        && (data.getCalculationInfo("stackedDimension") as? String) == stackedDim   // SeriesData conforms to DataStackSeriesData
}

public func getStackedDimension(_ data: SeriesData, _ targetDim: String) -> DimensionName {
    // `data.getCalculationInfo('stackResultDimension')` — provided by SeriesData (data/SeriesData.swift).
    return isDimensionStacked(data, targetDim)
        ? ((data.getCalculationInfo("stackResultDimension") as? DimensionName) ?? targetDim)   // SeriesData conforms
        : targetDim
}

// JS truthiness shim for `seriesModel.get('stack')` (CONVENTIONS §5/§6). nil/false/0/NaN/""
// are falsy; everything else is truthy.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
