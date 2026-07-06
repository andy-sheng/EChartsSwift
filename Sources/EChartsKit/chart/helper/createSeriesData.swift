// Ported from echarts/src/chart/helper/createSeriesData.ts — keep in sync with upstream
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

// upstream imports (translated against the conventional public API of sibling files):
//   import * as zrUtil from 'zrender/src/core/util';
//       -> ZRenderKit `util.{map, each, isFunction, isArray, curry}` (curry inlined; see below).
//   import SeriesData from '../../data/SeriesData';                              -> data/SeriesData.swift
//   import prepareSeriesDataSchema from '../../data/helper/createDimensions';    -> createDimensions.prepareSeriesDataSchema
//   import {getDimensionTypeByAxis} from '../../data/helper/dimensionHelper';    -> dimensionHelper.getDimensionTypeByAxis (free func)
//   import {getDataItemValue} from '../../util/model';                           -> model.getDataItemValue (util/modelUtil.swift)
//   import CoordinateSystem from '../../core/CoordinateSystem';
//       -> PORT: the default export is `CoordinateSystemManager` (core/CoordinateSystemManager.swift);
//          `CoordinateSystem.get(type)` -> `CoordinateSystemManager.get(type)` (returns `CoordinateSystemCreator?`).
//   import {getCoordSysInfoBySeries, SeriesModelCoordSysInfo} from '../../model/referHelper';  -> model/referHelper.swift
//   import { createSourceFromSeriesDataOption, Source } from '../../data/Source';               -> data/Source.swift
//   import {enableDataStack} from '../../data/helper/dataStackHelper';                          -> data/helper/dataStackHelper.swift
//   import {makeSeriesEncodeForAxisCoordSys} from '../../data/helper/sourceHelper';             -> sourceHelper.makeSeriesEncodeForAxisCoordSys
//   import { SOURCE_FORMAT_ORIGINAL, DimensionDefinitionLoose, DimensionDefinition,
//            OptionSourceData, EncodeDefaulter } from '../../util/types';                       -> util/types.swift
//   import SeriesModel from '../../model/Series';                                -> SeriesModel (model/Series.swift)
//   import DataStore from '../../data/DataStore';                                -> data/DataStore.swift
//   import SeriesDimensionDefine from '../../data/SeriesDimensionDefine';        -> data/SeriesDimensionDefine.swift

// upstream inline `opt` type of `createSeriesData` (the anonymous object becomes a value struct,
// CONVENTIONS §4):
//   opt?: {
//       generateCoord?: string
//       useEncodeDefaulter?: boolean | EncodeDefaulter
//       createInvertedIndices?: boolean   // if true, create inverted indices for all ordinal dimension on coordSys.
//   }
public struct CreateSeriesDataOpt {
    public var generateCoord: String?
    // PORT-TODO: union `boolean | EncodeDefaulter` -> `Any?` (Bool or the `EncodeDefaulter` closure).
    public var useEncodeDefaulter: Any?
    // By default: auto. If `true`, create inverted indices for all ordinal dimension on coordSys.
    public var createInvertedIndices: Bool?

    public init(
        generateCoord: String? = nil,
        useEncodeDefaulter: Any? = nil,
        createInvertedIndices: Bool? = nil
    ) {
        self.generateCoord = generateCoord
        self.useEncodeDefaulter = useEncodeDefaulter
        self.createInvertedIndices = createInvertedIndices
    }
}

private func getCoordSysDimDefs(
    _ seriesModel: SeriesModel,
    _ coordSysInfo: SeriesModelCoordSysInfo?
) -> [CoordDimensionDefinitionLoose] {
    let coordSysName = (seriesModel.get("coordinateSystem") as? String) ?? ""
    // upstream: CoordinateSystem.get(coordSysName)  (CoordinateSystem == CoordinateSystemManager here)
    let registeredCoordSys = CoordinateSystemManager.get(coordSysName)

    // upstream typing: `DimensionDefinitionLoose[]`; modeled as `[CoordDimensionDefinitionLoose]`
    // (== `[Any]`) so the elements flow directly into `PrepareSeriesDataSchemaParams.coordDimensions`.
    var coordSysDimDefs: [CoordDimensionDefinitionLoose]?

    // upstream: `if (coordSysInfo && coordSysInfo.coordSysDims)`. `coordSysDims` is a (possibly
    // empty) array — always truthy in JS — so the guard reduces to `coordSysInfo != nil`.
    if let coordSysInfo = coordSysInfo {
        coordSysDimDefs = util.map(coordSysInfo.coordSysDims) { dim, _ -> CoordDimensionDefinitionLoose in
            // upstream builds `{ name: dim } as DimensionDefinition` then sets `.type`.
            // PORT-TODO: `createDimensions` downcasts each non-string coord dimension to
            //   `CoordDimensionDefinition` (a distinct Swift value struct from `DimensionDefinition`),
            //   so build that concrete type here (upstream relies on TS structural subtyping —
            //   `CoordDimensionDefinition extends DimensionDefinition`).
            var dimInfo = CoordDimensionDefinition()
            dimInfo.name = dim
            let axisModel = coordSysInfo.axisMap.get(dim)
            if let axisModel = axisModel {
                let axisType = (axisModel.get("type") as? String) ?? ""
                dimInfo.type = getDimensionTypeByAxis(axisType)
                // BUGFIX (dataset category axis): a CATEGORY axis' series dimension must SHARE the axis'
                //   `OrdinalMeta` so that building the series data (`parseAndCollect`) populates the axis'
                //   category registry. Without this, a dataset-sourced category axis with no explicit
                //   `xAxis.data` collected NO categories → empty scale extent → no bars/points rendered.
                //   `createScaleByModel` reads the SAME `getOrdinalMeta()` for the axis scale, so assigning
                //   it here shares one object between the axis and the series dimension (upstream does the
                //   equivalent via the axis-model ordinalMeta the dimension picks up).
                if axisType == "category" {
                    dimInfo.ordinalMeta = (axisModel as? AxisModelExtendedInCreator)?.getOrdinalMeta()
                }
            }
            return dimInfo
        }
    }

    if coordSysDimDefs == nil {
        // Get dimensions from registered coordinate system.
        // upstream: (registeredCoordSys && (registeredCoordSys.getDimensionsInfo
        //     ? registeredCoordSys.getDimensionsInfo() : registeredCoordSys.dimensions.slice())) || ['x', 'y']
        // PORT-TODO: upstream branches on whether the *method* `getDimensionsInfo` is defined; the
        //   ported `CoordinateSystemCreator.getDimensionsInfo()` returns nil by default (method not
        //   provided), so a non-nil return is treated as "method present", otherwise fall to
        //   `dimensions`.
        if let registeredCoordSys = registeredCoordSys {
            if let dimsInfo = registeredCoordSys.getDimensionsInfo() {
                coordSysDimDefs = dimsInfo.map { $0 as CoordDimensionDefinitionLoose }
            }
            else if let dims = registeredCoordSys.dimensions {
                coordSysDimDefs = dims.map { $0 as CoordDimensionDefinitionLoose }   // .slice()
            }
        }
        if coordSysDimDefs == nil {
            coordSysDimDefs = ["x", "y"]
        }
    }

    return coordSysDimDefs!
}

private func injectOrdinalMeta(
    _ dimInfoList: [SeriesDimensionDefine],
    _ createInvertedIndices: Bool?,
    _ coordSysInfo: SeriesModelCoordSysInfo?
) -> Double? {
    var firstCategoryDimIndex: Double?
    var hasNameEncode = false
    if let coordSysInfo = coordSysInfo {
        util.each(dimInfoList) { (dimInfo: SeriesDimensionDefine, dimIndex: Int) in
            let coordDim = dimInfo.coordDim
            let categoryAxisModel = coordDim != nil ? coordSysInfo.categoryAxisMap.get(coordDim!) : nil
            if let categoryAxisModel = categoryAxisModel {
                if firstCategoryDimIndex == nil {
                    firstCategoryDimIndex = Double(dimIndex)
                }
                // upstream: `dimInfo.ordinalMeta = categoryAxisModel.getOrdinalMeta();`
                // PORT-TODO: `categoryAxisMap` holds `AxisBaseModel` (referHelper collapses the
                //   upstream `FetcherAxisModel` = `Model & Pick<AxisModelExtendedInCreator,'getOrdinalMeta'>`
                //   down to `AxisBaseModel`). `getOrdinalMeta()` lives on `AxisModelExtendedInCreator`
                //   (implemented by the generated axis model), so cast to reach it. Category axis
                //   instances conform.
                if let ext = categoryAxisModel as? AxisModelExtendedInCreator {
                    dimInfo.ordinalMeta = ext.getOrdinalMeta()
                }
                if createInvertedIndices == true {
                    dimInfo.createInvertedIndices = true
                }
            }
            if dimInfo.otherDims?.itemName != nil {
                hasNameEncode = true
            }
        }
    }
    if !hasNameEncode, let firstCategoryDimIndex = firstCategoryDimIndex {
        dimInfoList[Int(firstCategoryDimIndex)].otherDims?.itemName = 0
    }
    return firstCategoryDimIndex
}

/**
 * Caution: there are side effects to `sourceManager` in this method.
 * Should better only be called in `Series['getInitialData']`.
 */
// upstream default export `createSeriesData` -> free function (CONVENTIONS §2).
public func createSeriesData(
    _ sourceRaw: OptionSourceData?,   // OptionSourceData | null | undefined  (OptionSourceData == Any)
    _ seriesModel: SeriesModel,
    _ optInput: CreateSeriesDataOpt? = nil
) -> SeriesData {
    let opt = optInput ?? CreateSeriesDataOpt()

    let sourceManager = seriesModel.getSourceManager()
    var source: Source
    var isOriginalSource = false
    if let sourceRaw = sourceRaw {
        isOriginalSource = true
        source = createSourceFromSeriesDataOption(sourceRaw)
    }
    else {
        // upstream `getSource()` returns `Source` (non-optional); the ported
        // `SourceManager.getSource()` returns `Source?` (faithful to `Source | undefined`).
        // On the reachable series inline-data path a source is always created.
        source = sourceManager.getSource()!
        // Is series.data. not dataset.
        isOriginalSource = source.sourceFormat == SOURCE_FORMAT_ORIGINAL
    }
    let coordSysInfo = getCoordSysInfoBySeries(seriesModel)
    let coordSysDimDefs = getCoordSysDimDefs(seriesModel, coordSysInfo)
    let useEncodeDefaulter = opt.useEncodeDefaulter

    // upstream:
    //   const encodeDefaulter = zrUtil.isFunction(useEncodeDefaulter)
    //       ? useEncodeDefaulter
    //       : useEncodeDefaulter
    //       ? zrUtil.curry(makeSeriesEncodeForAxisCoordSys, coordSysDimDefs, seriesModel)
    //       : null;
    let encodeDefaulter: EncodeDefaulter?
    if let fn = useEncodeDefaulter as? EncodeDefaulter {
        encodeDefaulter = fn
    }
    else if jsTruthy(useEncodeDefaulter) {
        // curry(makeSeriesEncodeForAxisCoordSys, coordSysDimDefs, seriesModel): the curried defaulter
        // is `(source, dimCount) -> OptionEncode`; the trailing `dimCount` arg is ignored by
        // `makeSeriesEncodeForAxisCoordSys`. `SeriesEncodeInternal` ([String:[DimensionIndex]]) is
        // widened to `OptionEncode` (== [String: Any]).
        encodeDefaulter = { (src: Source, _: Double) -> OptionEncode in
            let internalEncode = sourceHelper.makeSeriesEncodeForAxisCoordSys(coordSysDimDefs, seriesModel, src)
            return internalEncode.mapValues { $0 as Any } as OptionEncode
        }
    }
    else {
        encodeDefaulter = nil
    }

    let createDimensionOptions = PrepareSeriesDataSchemaParams(
        coordDimensions: coordSysDimDefs,
        encodeDefine: seriesModel.getEncode(),
        encodeDefaulter: encodeDefaulter,
        generateCoord: opt.generateCoord,
        canOmitUnusedDimensions: !isOriginalSource
    )
    let schema = createDimensions.prepareSeriesDataSchema(source, createDimensionOptions)
    let firstCategoryDimIndex = injectOrdinalMeta(
        schema.dimensions, opt.createInvertedIndices, coordSysInfo
    )

    // upstream: `const store = !isOriginalSource ? sourceManager.getSharedDataStore(schema) : null;`
    let store: DataStore? = !isOriginalSource ? sourceManager.getSharedDataStore(schema) : nil

    // upstream: `enableDataStack(seriesModel, { schema, store })`.
    // `enableDataStack` takes `inout EnableDataStackDimensions`; wrap the `{ schema, store }` bag.
    var dimensionsInput = EnableDataStackDimensions.input(
        EnableDataStackDimensionsInput(schema: schema, store: store)
    )
    let stackCalculationInfo = enableDataStack(seriesModel, &dimensionsInput)

    let data = SeriesData(schema, seriesModel)
    // upstream: `data.setCalculationInfo(stackCalculationInfo)` — the `EnableDataStackResult` bag is
    // spread into `_calculationInfo`. Its fields are optionals (short-circuit `undefined`); only
    // present (non-nil) keys are written (an `undefined` value in a JS `extend` reads back as absent).
    var calcInfo: [String: Any] = [:]
    if let v = stackCalculationInfo.stackedDimension { calcInfo["stackedDimension"] = v }
    if let v = stackCalculationInfo.stackedByDimension { calcInfo["stackedByDimension"] = v }
    if let v = stackCalculationInfo.isStackedByIndex { calcInfo["isStackedByIndex"] = v }
    if let v = stackCalculationInfo.stackedOverDimension { calcInfo["stackedOverDimension"] = v }
    if let v = stackCalculationInfo.stackResultDimension { calcInfo["stackResultDimension"] = v }
    data.setCalculationInfo(calcInfo)

    let dimValueGetter: DimValueGetter?
    if firstCategoryDimIndex != nil && (isNeedCompleteOrdinalData(source) == true) {
        /**
         * This serves this case:
         *  var echarts_option = {
         *      xAxis: { data: ['a', 'b', 'c'] },
         *      yAxis: {}
         *      series: { data: [555, 666, 777] }
         *  };
         * The `series.data` is completed to:
         *  [[0, 555], [1, 666], [2, 777]]
         */
        let firstCategoryDim = firstCategoryDimIndex!
        // upstream `this: DataStore` binding -> the store is the closure's first param.
        dimValueGetter = { (store: DataStore, itemOpt: Any?, dimName: String?, dataIndex: Int, dimIndex: DimensionIndex) -> ParsedValue in
            // Use dataIndex as ordinal value in categoryAxis
            return dimIndex == firstCategoryDim
                ? Double(dataIndex)
                : store.defaultDimValueGetter(store, itemOpt, dimName, dataIndex, dimIndex)
        }
    }
    else {
        dimValueGetter = nil
    }

    data.hasItemOption = false
    data.initData(
        // Try to reuse the data store in sourceManager if using dataset.
        isOriginalSource ? (source as Any) : (store! as Any),
        nil,
        dimValueGetter
    )

    return data
}

private func isNeedCompleteOrdinalData(_ source: Source) -> Bool? {
    if source.sourceFormat == SOURCE_FORMAT_ORIGINAL {
        // firstDataNotNull(source.data as ArrayLike<any> || [])
        let arr = (source.data as? [Any]) ?? []
        let sampleItem = firstDataNotNull(arr)
        return !util.isArray(model.getDataItemValue(sampleItem as Any))
    }
    // upstream returns `undefined` when not original.
    return nil
}

private func firstDataNotNull(_ arr: [Any]) -> Any? {
    var i = 0
    // `arr[i] == null` matches both null and undefined (here: NSNull sentinel).
    while i < arr.count && (arr[i] is NSNull) {
        i += 1
    }
    return i < arr.count ? arr[i] : nil
}

// export default createSeriesData;  -> `public func createSeriesData(...)` above.

// JS truthiness shim for the dynamic `useEncodeDefaulter` bag (nil/false/0/NaN/"" are falsy). Not an
// upstream symbol — replaces the inline `useEncodeDefaulter ? ... : ...` truthiness on `Any?`.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
