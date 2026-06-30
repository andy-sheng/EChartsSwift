// Ported from echarts/src/data/helper/createDimensions.ts — keep in sync with upstream

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

// import {
//     DimensionDefinitionLoose, OptionEncode, OptionEncodeValue,
//     EncodeDefaulter,
//     OptionSourceData,
//     DimensionName,
//     DimensionDefinition,
//     DataVisualDimensions,
//     DimensionIndex,
//     VISUAL_DIMENSIONS
// } from '../../util/types';
// import SeriesDimensionDefine from '../SeriesDimensionDefine';
// import {
//     createHashMap, defaults, each, extend, HashMap, isObject, isString
// } from 'zrender/src/core/util';
// import OrdinalMeta from '../OrdinalMeta';
// import { createSourceFromSeriesDataOption, isSourceInstance, Source } from '../Source';
// import { CtorInt32Array } from '../DataStore';
// import { normalizeToArray, removeDuplicates } from '../../util/model';
// import { BE_ORDINAL, guessOrdinal } from './sourceHelper';
// import {
//     createDimNameMap, ensureSourceDimNameMap, SeriesDataSchema, shouldOmitUnusedDimensions
// } from './SeriesDataSchema';
//
// PORT-TODO: this file references several sibling data-engine symbols that are ported by
//   other agents this phase. It expects their conventional public API:
//     - data/Source:                 `Source` (class) with `dimensionsDefine: [DimensionDefinition]?`
//                                     and `dimensionsDetectedCount: Double`;
//                                     free funcs `isSourceInstance`, `createSourceFromSeriesDataOption`.
//     - data/DataStore:              `CtorInt32Array` (here modeled directly as ContiguousArray<Int32>).
//     - data/helper/sourceHelper:    `BE_ORDINAL` (.Must/.Might/.Not) + `guessOrdinal(source, dimIndex)`.
//     - data/helper/SeriesDataSchema:`SeriesDataSchema` (class) + `createDimNameMap`,
//                                     `ensureSourceDimNameMap`, `shouldOmitUnusedDimensions`.
//   `Source` currently exists only as an empty forward-ref protocol in util/types.swift; the
//   real Source class (this phase) must expose the members accessed below.

// upstream: CoordDimensionDefinition extends DimensionDefinition
public struct CoordDimensionDefinition {
    // ---- inherited from DimensionDefinition ----
    public var type: DataStoreDimensionType?
    public var name: DimensionName?
    public var displayName: String?
    // ---- own ----
    // PORT-TODO: dimsDef is `(DimensionName | { name: DimensionName, defaultTooltip?: boolean })[]`;
    //   modeled as `[Any]` whose elements are `String` or `CoordDimensionDimsDefItem`.
    public var dimsDef: [Any]?
    public var otherDims: DataVisualDimensions?
    public var ordinalMeta: OrdinalMeta?
    public var coordDim: DimensionName?
    public var coordDimIndex: DimensionIndex?
    public init() {}
}

// PORT-TODO: the inline `{ name: DimensionName, defaultTooltip?: boolean }` object inside `dimsDef`.
public struct CoordDimensionDimsDefItem {
    public var name: DimensionName
    public var defaultTooltip: Bool?
    public init(name: DimensionName, defaultTooltip: Bool? = nil) {
        self.name = name
        self.defaultTooltip = defaultTooltip
    }
}

// upstream: CoordDimensionDefinition['name'] | CoordDimensionDefinition
// PORT-TODO: union `string | CoordDimensionDefinition` -> Any.
public typealias CoordDimensionDefinitionLoose = Any

public struct PrepareSeriesDataSchemaParams {
    public var coordDimensions: [CoordDimensionDefinitionLoose]?
    /**
     * Will use `source.dimensionsDefine` if not given.
     */
    public var dimensionsDefine: [DimensionDefinitionLoose]?
    /**
     * Will use `source.encodeDefine` if not given.
     */
    // PORT-TODO: union `HashMap<OptionEncodeValue, DimensionName> | OptionEncode` -> Any.
    public var encodeDefine: Any?
    public var dimensionsCount: Double?
    /**
     * Make default encode if user not specified.
     */
    public var encodeDefaulter: EncodeDefaulter?
    public var generateCoord: String?
    public var generateCoordCount: Double?

    /**
     * If be able to omit unused dimension
     * Used to improve the performance on high dimension data.
     */
    public var canOmitUnusedDimensions: Bool?

    public init(
        coordDimensions: [CoordDimensionDefinitionLoose]? = nil,
        dimensionsDefine: [DimensionDefinitionLoose]? = nil,
        encodeDefine: Any? = nil,
        dimensionsCount: Double? = nil,
        encodeDefaulter: EncodeDefaulter? = nil,
        generateCoord: String? = nil,
        generateCoordCount: Double? = nil,
        canOmitUnusedDimensions: Bool? = nil
    ) {
        self.coordDimensions = coordDimensions
        self.dimensionsDefine = dimensionsDefine
        self.encodeDefine = encodeDefine
        self.dimensionsCount = dimensionsCount
        self.encodeDefaulter = encodeDefaulter
        self.generateCoord = generateCoord
        self.generateCoordCount = generateCoordCount
        self.canOmitUnusedDimensions = canOmitUnusedDimensions
    }
}

// Free-function module `createDimensions.ts` -> caseless enum namespace `createDimensions`
// (CONVENTIONS §2). The default export is `prepareSeriesDataSchema`; the named export is
// `createDimensions`. Call sites: upstream `prepareSeriesDataSchema(...)` ->
// `createDimensions.prepareSeriesDataSchema(...)`, `createDimensions(...)` ->
// `createDimensions.createDimensions(...)`.
public enum createDimensions {

    /**
     * For outside usage compat (like echarts-gl are using it).
     */
    public static func createDimensions(
        _ source: Any,   // PORT-TODO: upstream `Source | OptionSourceData`; OptionSourceData = Any
        _ opt: PrepareSeriesDataSchemaParams? = nil
    ) -> [SeriesDimensionDefine] {
        return prepareSeriesDataSchema(source, opt).dimensions
    }

    /**
     * This method builds the relationship between:
     * + "what the coord sys or series requires (see `coordDimensions`)",
     * + "what the user defines (in `encode` and `dimensions`, see `opt.dimensionsDefine` and `opt.encodeDefine`)"
     * + "what the data source provids (see `source`)".
     *
     * Some guess strategy will be adapted if user does not define something.
     * If no 'value' dimension specified, the first no-named dimension will be
     * named as 'value'.
     *
     * @return The results are always sorted by `storeDimIndex` asc.
     */
    // (default export in upstream)
    public static func prepareSeriesDataSchema(
        // TODO: TYPE completeDimensions type
        _ source: Any,   // PORT-TODO: upstream `Source | OptionSourceData`
        _ opt: PrepareSeriesDataSchemaParams? = nil
    ) -> SeriesDataSchema {
        var source = source
        if !isSourceInstance(source) {
            source = createSourceFromSeriesDataOption(source /* as OptionSourceData */)
        }
        // After the guard above, `source` is a `Source` instance.
        let srcInst = source as! Source

        let opt = opt ?? PrepareSeriesDataSchemaParams()

        let sysDims: [CoordDimensionDefinitionLoose] = opt.coordDimensions ?? []
        // upstream: dimsDef = opt.dimensionsDefine || source.dimensionsDefine || [];
        // upstream: isUsingSourceDimensionsDef = dimsDef === source.dimensionsDefine;
        // `===` is reference identity over the array; with Swift value semantics we instead
        // track which branch supplied `dimsDef`.
        let dimsDef: [DimensionDefinitionLoose]
        let isUsingSourceDimensionsDef: Bool
        if let optDimsDef = opt.dimensionsDefine {
            dimsDef = optDimsDef
            isUsingSourceDimensionsDef = false
        }
        else if let srcDimsDef = srcInst.dimensionsDefine {
            dimsDef = srcDimsDef.map { $0 as DimensionDefinitionLoose }
            isUsingSourceDimensionsDef = true
        }
        else {
            dimsDef = []
            isUsingSourceDimensionsDef = false
        }
        let coordDimNameMap: HashMap<Bool> = createHashMap()  // createHashMap<true, DimensionName>()
        var resultList: [SeriesDimensionDefine] = []
        let dimCount = getDimCount(srcInst, sysDims, dimsDef, opt.dimensionsCount)

        // Try to ignore unused dimensions if sharing a high dimension datastore
        // 30 is an experience value.
        let omitUnusedDimensions = (opt.canOmitUnusedDimensions ?? false) && shouldOmitUnusedDimensions(dimCount)

        let dataDimNameMap: HashMap<DimensionIndex> = isUsingSourceDimensionsDef
            ? ensureSourceDimNameMap(srcInst) : createDimNameMap(dimsDef)

        var encodeDef = opt.encodeDefine
        if encodeDef == nil, let encodeDefaulter = opt.encodeDefaulter {
            encodeDef = encodeDefaulter(srcInst, dimCount)
        }
        // createHashMap<DimensionIndex[] | false, DimensionName>(encodeDef as any)
        // PORT-TODO: the EChartsKit `createHashMap` shim has no init-from-object overload, so we
        //   populate it manually. Values are either `[DimensionIndex?]` or `false` (or raw
        //   OptionEncodeValue before normalization below). `[String: Any]` iteration loses JS
        //   insertion order.
        let encodeDefMap = HashMap<Any>()
        if let encodeDef = encodeDef {
            if let h = encodeDef as? HashMap<Any> {
                h.each { v, k in encodeDefMap.set(k, v) }
            }
            else if let d = encodeDef as? [String: Any] {
                for (k, v) in d {
                    encodeDefMap.set(k, v)
                }
            }
            // PORT-TODO: unknown encode shape -> ignored.
        }

        // new CtorInt32Array(dimCount)  (PORT-TODO: CtorInt32Array is a data/DataStore export)
        var indicesMap = ContiguousArray<Int32>(repeating: 0, count: Int(dimCount))
        for i in 0..<indicesMap.count {
            indicesMap[i] = -1
        }

        // Nested helpers below are hoisted above their first use (Swift has no function
        // hoisting; in upstream `getResultItem`/`applyDim` are function declarations).
        func getResultItem(_ dimIdx: Double) -> SeriesDimensionDefine {
            let idx = indicesMap[Int(dimIdx)]
            if idx < 0 {
                let dimDefItemRaw: Any? = (Int(dimIdx) < dimsDef.count) ? dimsDef[Int(dimIdx)] : nil
                let dimDefItem: DimensionDefinition
                if let obj = dimDefItemRaw as? DimensionDefinition {
                    dimDefItem = obj
                }
                else {
                    var d = DimensionDefinition()
                    d.name = dimDefItemRaw as? DimensionName
                    dimDefItem = d
                }
                let resultItem = SeriesDimensionDefine()
                let userDimName = dimDefItem.name
                if let userDimName = userDimName, dataDimNameMap.get(userDimName) != nil {
                    // Only if `series.dimensions` is defined in option
                    // displayName, will be set, and dimension will be displayed vertically in
                    // tooltip by default.
                    resultItem.name = userDimName
                    resultItem.displayName = userDimName
                }
                if dimDefItem.type != nil { resultItem.type = dimDefItem.type }
                if dimDefItem.displayName != nil { resultItem.displayName = dimDefItem.displayName }
                let newIdx = resultList.count
                indicesMap[Int(dimIdx)] = Int32(newIdx)
                resultItem.storeDimIndex = dimIdx
                resultList.append(resultItem)
                return resultItem
            }
            return resultList[Int(idx)]
        }

        func applyDim(
            _ resultItem: SeriesDimensionDefine,
            _ coordDim: String?,
            _ coordDimIndex: Double
        ) {
            // VISUAL_DIMENSIONS.get(coordDim) != null
            if let coordDim = coordDim, VISUAL_DIMENSIONS.contains(coordDim) {
                var otherDims = resultItem.otherDims ?? DataVisualDimensions()
                setOtherDim(&otherDims, coordDim, coordDimIndex)
                resultItem.otherDims = otherDims
            }
            else {
                resultItem.coordDim = coordDim
                resultItem.coordDimIndex = coordDimIndex
                coordDimNameMap.set(coordDim, true)
            }
        }

        func ifNoNameFillWithCoordName(_ resultItem: SeriesDimensionDefine) {
            // resultItem.name == null
            // PORT-TODO: ported SeriesDimensionDefine.name is non-optional (defaults to ""),
            //   so empty string is treated as the upstream `null`/unset state.
            if resultItem.name.isEmpty {
                // Duplication will be removed in the next step.
                resultItem.name = resultItem.coordDim ?? ""
            }
        }

        if !omitUnusedDimensions {
            for i in 0..<Int(dimCount) {
                _ = getResultItem(Double(i))
            }
        }

        // Set `coordDim` and `coordDimIndex` by `encodeDefMap` and normalize `encodeDefMap`.
        encodeDefMap.each { dataDimsRaw, coordDim in
            let dataDims: [Any] = model.normalizeToArray(dataDimsRaw)   // .slice() -> implicit value copy

            // Note: It is allowed that `dataDims.length` is `0`, e.g., options is
            // `{encode: {x: -1, y: 1}}`. Should not filter anything in
            // this case.
            if dataDims.count == 1, !util.isString(dataDims[0]), let d0 = dataDims[0] as? Double, d0 < 0 {
                encodeDefMap.set(coordDim, false)
                return
            }

            var validDataDims: [DimensionIndex?] = []   // encodeDefMap.set(coordDim, []) as DimensionIndex[]
            encodeDefMap.set(coordDim, validDataDims)
            util.each(dataDims) { resultDimIdxOrName, idx in
                // The input resultDimIdx can be dim name or index.
                let resultDimIdx: DimensionIndex? = util.isString(resultDimIdxOrName)
                    ? dataDimNameMap.get(resultDimIdxOrName as! String)
                    : (resultDimIdxOrName as? DimensionIndex)
                if let resultDimIdx = resultDimIdx, resultDimIdx < dimCount {
                    while validDataDims.count <= idx { validDataDims.append(nil) }
                    validDataDims[idx] = resultDimIdx
                    applyDim(getResultItem(resultDimIdx), coordDim, Double(idx))
                }
            }
            // PORT-TODO: re-set after mutation — Swift arrays are value types, so the push above
            //   does not write through to the map (upstream relies on the array reference).
            encodeDefMap.set(coordDim, validDataDims)
        }

        // Apply templates and default order from `sysDims`.
        var availDimIdx: Double = 0
        util.each(sysDims) { sysDimItemRaw, _ in
            var coordDim: DimensionName?
            var sysDimItemDimsDef: [Any]?
            var sysDimItemOtherDims: DataVisualDimensions?
            var sysDimItem: CoordDimensionDefinition
            if util.isString(sysDimItemRaw) {
                coordDim = (sysDimItemRaw as! String)
                sysDimItem = CoordDimensionDefinition()
            }
            else {
                // extend({}, sysDimItem): with value semantics the assignment below already makes
                // an independent copy; the upstream ordinalMeta null/restore dance (to keep
                // `extend` shallow) is preserved structurally but no longer mutates the input.
                sysDimItem = sysDimItemRaw as! CoordDimensionDefinition
                coordDim = sysDimItem.name
                let ordinalMeta = sysDimItem.ordinalMeta
                sysDimItem.ordinalMeta = nil
                // sysDimItem = extend({}, sysDimItem)  -> value-type copy already done above
                sysDimItem.ordinalMeta = ordinalMeta
                // `coordDimIndex` should not be set directly.
                sysDimItemDimsDef = sysDimItem.dimsDef
                sysDimItemOtherDims = sysDimItem.otherDims
                sysDimItem.name = nil
                sysDimItem.coordDim = nil
                sysDimItem.coordDimIndex = nil
                sysDimItem.dimsDef = nil
                sysDimItem.otherDims = nil
            }

            let dataDimsRaw = encodeDefMap.get(coordDim)

            // negative resultDimIdx means no need to mapping.
            if let b = dataDimsRaw as? Bool, b == false {   // dataDims === false
                return
            }

            var dataDims: [DimensionIndex?] = model.normalizeToArray(dataDimsRaw)

            // dimensions provides default dim sequences.
            if dataDims.isEmpty {
                // (sysDimItemDimsDef && sysDimItemDimsDef.length || 1)
                var fillCount = sysDimItemDimsDef?.count ?? 0
                if fillCount == 0 { fillCount = 1 }
                for _ in 0..<fillCount {
                    while availDimIdx < dimCount && getResultItem(availDimIdx).coordDim != nil {
                        availDimIdx += 1
                    }
                    if availDimIdx < dimCount {
                        dataDims.append(availDimIdx)
                        availDimIdx += 1
                    }
                }
            }

            // Apply templates.
            util.each(dataDims) { resultDimIdxOpt, coordDimIndex in
                // PORT-TODO: holes (skipped invalid indices in `validDataDims`) surface as nil;
                //   upstream would visit them as `undefined`. They do not occur for valid encode.
                guard let resultDimIdx = resultDimIdxOpt else { return }
                let resultItem = getResultItem(resultDimIdx)
                // Coordinate system has a higher priority on dim type than source.
                if isUsingSourceDimensionsDef && sysDimItem.type != nil {
                    resultItem.type = sysDimItem.type
                }
                defaultsSeriesDim(resultItem, sysDimItem)   // defaults(resultItem, sysDimItem)
                applyDim(resultItem, coordDim, Double(coordDimIndex))
                if resultItem.name.isEmpty, let sysDimItemDimsDef = sysDimItemDimsDef {
                    // resultItem.name == null && sysDimItemDimsDef
                    var sysDimItemDimsDefItem: Any? = (coordDimIndex < sysDimItemDimsDef.count)
                        ? sysDimItemDimsDef[coordDimIndex] : nil
                    if !(sysDimItemDimsDefItem is CoordDimensionDimsDefItem) {   // !isObject(...)
                        sysDimItemDimsDefItem = CoordDimensionDimsDefItem(
                            name: (sysDimItemDimsDefItem as? DimensionName) ?? ""
                        )
                    }
                    let item = sysDimItemDimsDefItem as! CoordDimensionDimsDefItem
                    resultItem.name = item.name
                    resultItem.displayName = item.name
                    resultItem.defaultTooltip = item.defaultTooltip
                }
                // FIXME refactor, currently only used in case: {otherDims: {tooltip: false}}
                if let sysDimItemOtherDims = sysDimItemOtherDims {
                    var otherDims = resultItem.otherDims ?? DataVisualDimensions()
                    defaultsOtherDims(&otherDims, sysDimItemOtherDims)
                    resultItem.otherDims = otherDims
                }
            }
        }

        // Make sure the first extra dim is 'value'.
        let generateCoord = opt.generateCoord
        let fromZero = opt.generateCoordCount != nil
        // generateCoordCount = generateCoord ? (generateCoordCount || 1) : 0;
        // PORT-TODO: `generateCoord` truthiness modeled as non-nil (empty string edge case ignored).
        var generateCoordCount: Double = (generateCoord != nil)
            ? ((opt.generateCoordCount != nil && opt.generateCoordCount != 0) ? opt.generateCoordCount! : 1)
            : 0
        let extra = generateCoord ?? "value"

        // Set dim `name` and other `coordDim` and other props.
        if !omitUnusedDimensions {
            for resultDimIdx in 0..<Int(dimCount) {
                let resultItem = getResultItem(Double(resultDimIdx))
                let coordDim = resultItem.coordDim

                if coordDim == nil {
                    // TODO no need to generate coordDim for isExtraCoord?
                    resultItem.coordDim = genCoordDimName(
                        extra, coordDimNameMap, fromZero
                    )

                    resultItem.coordDimIndex = 0
                    // Series specified generateCoord is using out.
                    if generateCoord == nil || generateCoordCount <= 0 {
                        resultItem.isExtraCoord = true
                    }
                    generateCoordCount -= 1
                }

                ifNoNameFillWithCoordName(resultItem)

                if resultItem.type == nil
                    && (
                        sourceHelper.guessOrdinal(srcInst, Double(resultDimIdx)) == sourceHelper.BE_ORDINAL.Must
                        // Consider the case:
                        // {
                        //    dataset: {source: [
                        //        ['2001', 123],
                        //        ['2002', 456],
                        //        ...
                        //        ['The others', 987],
                        //    ]},
                        //    series: {type: 'pie'}
                        // }
                        // The first column should better be treated as a "ordinal" although it
                        // might not be detected as an "ordinal" by `guessOrdinal`.
                        || (resultItem.isExtraCoord == true
                            && (resultItem.otherDims?.itemName != nil
                                || resultItem.otherDims?.seriesName != nil
                            )
                        )
                    )
                {
                    resultItem.type = .ordinal
                }
            }
        }
        else {
            util.each(resultList) { resultItem, _ in
                // PENDING: guessOrdinal or let user specify type: 'ordinal' manually?
                ifNoNameFillWithCoordName(resultItem)
            }
            // Sort dimensions: there are some rule that use the last dim as label,
            // and for some latter travel process easier.
            resultList.sort { item0, item1 in
                (item0.storeDimIndex ?? 0) < (item1.storeDimIndex ?? 0)
            }
        }

        // PORT-TODO: model.removeDuplicates takes `inout [TItem?]`; SeriesDimensionDefine is a
        //   class, so resolving (which mutates `item.name` through the reference) is reflected in
        //   `resultList` directly. With `resolve != nil`, the array length is not modified.
        var resultListBox: [SeriesDimensionDefine?] = resultList.map { $0 }
        model.removeDuplicates(
            &resultListBox,
            { item in
                return item?.name ?? ""
            },
            { item, existingCount in
                if existingCount > 0 {
                    // Starts from 0.
                    item.name = item.name + String(Int(existingCount - 1))
                }
            }
        )

        return SeriesDataSchema(opt: (
            source: srcInst,
            dimensions: resultList,
            fullDimensionCount: dimCount,
            dimensionOmitted: omitUnusedDimensions
        ))
    }

    // ??? TODO
    // Originally detect dimCount by data[0]. Should we
    // optimize it to only by sysDims and dimensions and encode.
    // So only necessary dims will be initialized.
    // But
    // (1) custom series should be considered. where other dims
    // may be visited.
    // (2) sometimes user need to calculate bubble size or use visualMap
    // on other dimensions besides coordSys needed.
    // So, dims that is not used by system, should be shared in data store?
    private static func getDimCount(
        _ source: Source,
        _ sysDims: [CoordDimensionDefinitionLoose],
        _ dimsDef: [DimensionDefinitionLoose],
        _ optDimCount: Double?
    ) -> Double {
        // Note that the result dimCount should not small than columns count
        // of data, otherwise `dataDimNameMap` checking will be incorrect.
        // source.dimensionsDetectedCount || 1  — nil/0 fall back to 1 (JS `||`); the ported
        // Source exposes `dimensionsDetectedCount` as `Double?`.
        let detected = source.dimensionsDetectedCount
        let detectedCount: Double = (detected != nil && detected != 0) ? detected! : 1
        var dimCount = Swift.max(
            detectedCount,
            Double(sysDims.count),
            Double(dimsDef.count),
            optDimCount ?? 0
        )
        util.each(sysDims) { sysDimItem, _ in
            if let sysDimItem = sysDimItem as? CoordDimensionDefinition,
               let sysDimItemDimsDef = sysDimItem.dimsDef {
                dimCount = Swift.max(dimCount, Double(sysDimItemDimsDef.count))
            }
        }
        return dimCount
    }

    private static func genCoordDimName(
        _ name: DimensionName,
        _ map: HashMap<Bool>,   // upstream: HashMap<unknown, DimensionName>
        _ fromZero: Bool
    ) -> DimensionName {
        var name = name
        // map.hasKey(name) -> map.get(name) != nil (shim has no hasKey)
        if fromZero || map.get(name) != nil {
            var i = 0
            while map.get(name + String(i)) != nil {
                i += 1
            }
            name += String(i)
        }
        map.set(name, true)
        return name
    }
}

// ----------------------------------------------------------------------------
// Typed merge helpers — replace `zrUtil.defaults`/object field writes that operate over
// the typed `SeriesDimensionDefine` / `DataVisualDimensions` shapes (the dictionary-form
// `util.defaults` is not applicable here). Not part of upstream as standalone functions.
// ----------------------------------------------------------------------------

// defaults(resultItem, sysDimItem): fill missing fields of `target` from `source`.
// After the sysDims null-out dance, only `type`/`displayName`/`ordinalMeta` can be present on
// `source`; the rest (name/coordDim/coordDimIndex/dimsDef/otherDims) are nil and never apply.
private func defaultsSeriesDim(_ target: SeriesDimensionDefine, _ source: CoordDimensionDefinition) {
    if target.type == nil { target.type = source.type }
    if target.displayName == nil { target.displayName = source.displayName }
    if target.ordinalMeta == nil { target.ordinalMeta = source.ordinalMeta }
    // PORT-TODO: name is non-optional ("") on SeriesDimensionDefine and nil on `source` here,
    //   so it never contributes — faithful to the upstream `defaults` result.
}

// defaults(resultItem.otherDims, sysDimItemOtherDims)
private func defaultsOtherDims(_ target: inout DataVisualDimensions, _ source: DataVisualDimensions) {
    if target.tooltip == nil { target.tooltip = source.tooltip }
    if target.label == nil { target.label = source.label }
    if target.itemName == nil { target.itemName = source.itemName }
    if target.itemId == nil { target.itemId = source.itemId }
    if target.itemGroupId == nil { target.itemGroupId = source.itemGroupId }
    if target.itemChildGroupId == nil { target.itemChildGroupId = source.itemChildGroupId }
    if target.seriesName == nil { target.seriesName = source.seriesName }
}

// resultItem.otherDims[coordDim] = coordDimIndex  (coordDim is a VISUAL_DIMENSIONS key)
private func setOtherDim(_ otherDims: inout DataVisualDimensions, _ key: String, _ value: Double) {
    switch key {
    case "tooltip": otherDims.tooltip = value
    case "label": otherDims.label = value
    case "itemName": otherDims.itemName = value
    case "itemId": otherDims.itemId = value
    case "itemGroupId": otherDims.itemGroupId = value
    case "itemChildGroupId": otherDims.itemChildGroupId = value
    case "seriesName": otherDims.seriesName = value
    default: break   // PORT-TODO: non-VISUAL_DIMENSIONS key (should not happen here)
    }
}
