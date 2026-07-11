// Ported from echarts/src/data/helper/SeriesDataSchema.ts — keep in sync with upstream
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

// import { createHashMap, HashMap, isObject, retrieve2 } from 'zrender/src/core/util';
//   -> `isObject`/`retrieve2` are ZRenderKit.util.* ; `createHashMap`/`HashMap` are the
//      EChartsKit local shim (util/model.swift) until ZRenderKit ports them.
// import { makeInner } from '../../util/model';                  -> `model.makeInner`
// import { DimensionDefinition, DimensionDefinitionLoose, DimensionIndex, DimensionName,
//          DimensionType } from '../../util/types';              -> same module (util/types.swift)
// import { DataStoreDimensionDefine } from '../DataStore';       -> sibling data/DataStore (this phase)
// import OrdinalMeta from '../OrdinalMeta';                      -> data/OrdinalMeta.swift
// import SeriesDimensionDefine from '../SeriesDimensionDefine';  -> sibling data/SeriesDimensionDefine (this phase)
// import { shouldRetrieveDataByName, Source } from '../Source';  -> sibling data/Source (this phase)
import Foundation
import ZRenderKit

// PORT-NOTE: `inner` is a per-`Source` property store. Upstream:
//   const inner = makeInner<{ dimNameMap: HashMap<DimensionIndex, DimensionName>; }, Source>();
// Our `model.makeInner` takes a factory closure and is keyed by host object identity
// (Source must be a `final class`, per the sibling data/Source port). The anonymous bag
// `{ dimNameMap }` is modeled as the `final class SeriesDataSchemaInner` below.
private final class SeriesDataSchemaInner {
    // HashMap<DimensionIndex, DimensionName>: our shim drops the key generic (keys are
    // string-coerced), so value type DimensionIndex (= Double).
    var dimNameMap: HashMap<DimensionIndex>?
}
private let inner: (Source) -> SeriesDataSchemaInner = model.makeInner { SeriesDataSchemaInner() }

// dimTypeShort = { float: 'f', int: 'i', ordinal: 'o', number: 'n', time: 't' } as const;
private let dimTypeShort: [DimensionType: String] = [
    .float: "f", .int: "i", .ordinal: "o", .number: "n", .time: "t"
]

/**
 * Represents the dimension requirement of a series.
 *
 * NOTICE:
 * When there are too many dimensions in dataset and many series, only the used dimensions
 * (i.e., used by coord sys and declared in `series.encode`) are add to `dimensionDefineList`.
 * But users may query data by other unused dimension names.
 * In this case, users can only query data if and only if they have defined dimension names
 * via ec option, so we provide `getDimensionIndexFromSource`, which only query them from
 * `source` dimensions.
 */
public final class SeriesDataSchema {

    /**
     * When there are too many dimensions, `dimensionDefineList` might only contain
     * used dimensions.
     *
     * CAUTION:
     * Should have been sorted by `storeDimIndex` asc.
     *
     * PENDING:
     * The item can still be modified outsite.
     * But MUST NOT add/remove item of this array.
     */
    // PORT-NOTE: upstream `readonly` (binding fixed, but `appendCalculationDimension` pushes
    // into it). Modeled as `private(set) var` so the class can mutate the array.
    public private(set) var dimensions: [SeriesDimensionDefine]

    public let source: Source

    private var _fullDimCount: Double
    // ReturnType<typeof inner>['dimNameMap']: lazily assigned (only when dimensionOmitted).
    private var _dimNameMap: HashMap<DimensionIndex>!
    private var _dimOmitted: Bool

    public init(opt: (
        source: Source,
        dimensions: [SeriesDimensionDefine],
        fullDimensionCount: Double,
        dimensionOmitted: Bool
    )) {
        self.dimensions = opt.dimensions
        self._dimOmitted = opt.dimensionOmitted
        self.source = opt.source
        self._fullDimCount = opt.fullDimensionCount

        self._updateDimOmitted(opt.dimensionOmitted)
    }

    public func isDimensionOmitted() -> Bool {
        return self._dimOmitted
    }

    private func _updateDimOmitted(_ dimensionOmitted: Bool) {
        self._dimOmitted = dimensionOmitted
        if !dimensionOmitted {
            return
        }
        if self._dimNameMap == nil {
            self._dimNameMap = ensureSourceDimNameMap(self.source)
        }
    }

    /**
     * @caution Can only be used when `dimensionOmitted: true`.
     *
     * Get index by user defined dimension name (i.e., not internal generate name).
     * That is, get index from `dimensionsDefine`.
     * If no `dimensionsDefine`, or no name get, return -1.
     */
    public func getSourceDimensionIndex(_ dimName: DimensionName) -> DimensionIndex {
        return util.retrieve2(self._dimNameMap.get(dimName), -1) ?? -1
    }

    /**
     * @caution Can only be used when `dimensionOmitted: true`.
     *
     * Notice: may return `null`/`undefined` if user not specify dimension names.
     */
    public func getSourceDimension(_ dimIndex: DimensionIndex) -> DimensionDefinition? {
        let dimensionsDefine = self.source.dimensionsDefine
        if let dimensionsDefine = dimensionsDefine {
            // PORT-NOTE: JS returns `undefined` on out-of-range index; guard to avoid a trap.
            let i = Int(dimIndex)
            if i >= 0 && i < dimensionsDefine.count {
                return dimensionsDefine[i]
            }
            return nil
        }
        return nil
    }

    public func makeStoreSchema() -> (
        dimensions: [DataStoreDimensionDefine],
        hash: String
    ) {
        let dimCount = self._fullDimCount
        let willRetrieveDataByName = shouldRetrieveDataByName(self.source)
        let makeHashStrict = !shouldOmitUnusedDimensions(dimCount)

        // If source don't have dimensions or series don't omit unsed dimensions.
        // Generate from seriesDimList directly
        var dimHash = ""
        var dims: [DataStoreDimensionDefine] = []

        var fullDimIdx = 0
        var seriesDimIdx = 0
        while Double(fullDimIdx) < dimCount {
            var property: String?
            var type: DimensionType?
            var ordinalMeta: OrdinalMeta?

            // PORT-NOTE: JS `this.dimensions[seriesDimIdx]` yields `undefined` past the end;
            // guard the index so `seriesDimDef` is `nil` there.
            let seriesDimDef: SeriesDimensionDefine? =
                seriesDimIdx < self.dimensions.count ? self.dimensions[seriesDimIdx] : nil
            // The list has been sorted by `storeDimIndex` asc.
            if seriesDimDef != nil && seriesDimDef!.storeDimIndex == Double(fullDimIdx) {
                property = willRetrieveDataByName ? seriesDimDef!.name : nil
                type = seriesDimDef!.type
                ordinalMeta = seriesDimDef!.ordinalMeta

                seriesDimIdx += 1
            }
            else {
                let sourceDimDef = self.getSourceDimension(Double(fullDimIdx))
                if let sourceDimDef = sourceDimDef {
                    property = willRetrieveDataByName ? sourceDimDef.name : nil
                    type = sourceDimDef.type
                }
            }

            // PORT-NOTE: relies on the sibling data/DataStore port exposing
            // `DataStoreDimensionDefine` (struct) with a default init + mutable
            // `property`/`type`/`ordinalMeta` fields. Mirrors `dims.push({ property, type, ordinalMeta })`.
            var dim = DataStoreDimensionDefine()
            dim.property = property
            dim.type = type
            dim.ordinalMeta = ordinalMeta
            dims.append(dim)

            // If retrieving data by index,
            //   use <index, type, ordinalMeta> to determine whether data can be shared.
            //   (Because in this case there might be no dimension name defined in dataset, but indices always exists).
            //   (Indices are always 0, 1, 2, ..., so we can ignore them to shorten the hash).
            // Otherwise if retrieving data by property name (like `data: [{aa: 123, bb: 765}, ...]`),
            //   use <property, type, ordinalMeta> in hash.
            if willRetrieveDataByName
                && property != nil
                // For data stack, we have make sure each series has its own dim on this store.
                // So we do not add property to hash to make sure they can share this store.
                && (seriesDimDef == nil || !((seriesDimDef!.isCalculationCoord) ?? false))
            {
                dimHash += (makeHashStrict
                    // Use escape character '`' in case that property name contains '$'.
                    ? property!.replacingOccurrences(of: "`", with: "`1")
                                .replacingOccurrences(of: "$", with: "`2")
                    // For better performance, when there are large dimensions, tolerant this defects that hardly meet.
                    : property!
                )
            }
            dimHash += "$"
            dimHash += (type.flatMap { dimTypeShort[$0] }) ?? "f"

            if let ordinalMeta = ordinalMeta {
                dimHash += jsNumberToString(ordinalMeta.uid)
            }

            dimHash += "$"

            fullDimIdx += 1
        }

        // Source from endpoint(usually series) will be read differently
        // when seriesLayoutBy or startIndex(which is affected by sourceHeader) are different.
        // So we use this three props as key.
        let source = self.source
        let hash = [
            source.seriesLayoutBy,
            jsNumberToString(source.startIndex),
            dimHash
        ].joined(separator: "$$")

        return (
            dimensions: dims,
            hash: hash
        )
    }

    public func makeOutputDimensionNames() -> [DimensionName?] {
        // PORT-NOTE: upstream return type is `DimensionName[]`, but `name` is left `undefined`
        // when there is no matching series/source dimension, so elements may be `nil`.
        var result: [DimensionName?] = []

        var fullDimIdx = 0
        var seriesDimIdx = 0
        while Double(fullDimIdx) < self._fullDimCount {
            var name: DimensionName?
            let seriesDimDef: SeriesDimensionDefine? =
                seriesDimIdx < self.dimensions.count ? self.dimensions[seriesDimIdx] : nil
            // The list has been sorted by `storeDimIndex` asc.
            if seriesDimDef != nil && seriesDimDef!.storeDimIndex == Double(fullDimIdx) {
                if !((seriesDimDef!.isCalculationCoord) ?? false) {
                    name = seriesDimDef!.name
                }
                seriesDimIdx += 1
            }
            else {
                let sourceDimDef = self.getSourceDimension(Double(fullDimIdx))
                if let sourceDimDef = sourceDimDef {
                    name = sourceDimDef.name
                }
            }
            result.append(name)

            fullDimIdx += 1
        }

        return result
    }

    public func appendCalculationDimension(_ dimDef: SeriesDimensionDefine) {
        self.dimensions.append(dimDef)
        dimDef.isCalculationCoord = true
        self._fullDimCount += 1
        // If append dimension on a data store, consider the store
        // might be shared by different series, series dimensions not
        // really map to store dimensions.
        self._updateDimOmitted(true)
    }
}

public func isSeriesDataSchema(
    _ schema: Any?
) -> Bool {
    return schema is SeriesDataSchema
}


public func createDimNameMap(_ dimsDef: [DimensionDefinitionLoose]?) -> HashMap<DimensionIndex> {
    let dataDimNameMap: HashMap<DimensionIndex> = createHashMap()
    let dimsDef = dimsDef ?? []   // (dimsDef || [])
    for i in 0..<dimsDef.count {
        let dimDefItemRaw = dimsDef[i]
        // isObject(dimDefItemRaw) ? dimDefItemRaw.name : dimDefItemRaw
        //   The ported `DimensionDefinition` is a Swift STRUCT (value type); `util.isObject` only reports
        //   true for arrays/dicts/functions/class instances, so it returns false for the struct and the
        //   `.name` would be missed. Match the struct explicitly (mirroring getResultItem in
        //   createDimensions.swift, which downcasts `as? DimensionDefinition` directly) so a
        //   dimensionsDefine of `[DimensionDefinition]` registers its names (e.g. themeRiver's 'name' dim).
        let userDimName: DimensionName?
        if let dimDef = dimDefItemRaw as? DimensionDefinition {
            userDimName = dimDef.name
        }
        else if util.isObject(dimDefItemRaw) {
            userDimName = nil   // some other object shape without a mappable name
        }
        else {
            userDimName = dimDefItemRaw as? DimensionName
        }
        if userDimName != nil && dataDimNameMap.get(userDimName) == nil {
            dataDimNameMap.set(userDimName, DimensionIndex(i))
        }
    }
    return dataDimNameMap
}

public func ensureSourceDimNameMap(_ source: Source) -> HashMap<DimensionIndex> {
    let innerSource = inner(source)
    if let dimNameMap = innerSource.dimNameMap {
        return dimNameMap
    }
    // DimensionDefinitionLoose = Any; box the [DimensionDefinition] elements.
    let dimNameMap = createDimNameMap(source.dimensionsDefine?.map { $0 as DimensionDefinitionLoose })
    innerSource.dimNameMap = dimNameMap
    return dimNameMap
}

public func shouldOmitUnusedDimensions(_ dimCount: Double) -> Bool {
    return dimCount > 30
}

// JS Number-to-string coercion used by `+=`/`join` on numbers (e.g. `ordinalMeta.uid`,
// `source.startIndex`). Not a standalone upstream symbol; integer-valued numbers print
// without a fractional part, matching JS.
private func jsNumberToString(_ n: Double) -> String {
    if n.isFinite && n == n.rounded() && Swift.abs(n) < 1e21 {
        return String(Int64(n))
    }
    return String(n)
}
