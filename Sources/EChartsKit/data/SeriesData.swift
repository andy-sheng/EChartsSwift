// Ported from echarts/src/data/SeriesData.ts — keep in sync with upstream
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

/* global Int32Array */

import Foundation
import ZRenderKit

// upstream imports (reused from sibling/ZRenderKit ports where available):
//   import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit.util
//   import {PathStyleProps} from 'zrender/src/graphic/Path';         -> ZRenderKit.PathStyleProps
//   import Model from '../model/Model';                              -> Model placeholder (util/types.swift); Phase 5c
//   import DataDiffer from './DataDiffer';                           -> sibling data/DataDiffer.swift
//   import {DataProvider, DefaultDataProvider} from './helper/dataProvider';  -> sibling data/helper/dataProvider.swift
//   import {summarizeDimensions, DimensionSummary} from './helper/dimensionHelper';  -> sibling data/helper/dimensionHelper.swift
//   import SeriesDimensionDefine from './SeriesDimensionDefine';     -> sibling data/SeriesDimensionDefine.swift
//   import {ArrayLike, Dictionary, FunctionPropertyNames, NullUndefined} from 'zrender/src/core/types';  -> ZRenderKit
//   import Element from 'zrender/src/Element';                       -> ZRenderKit.Element
//   import { ... } from '../util/types';                             -> sibling util/types.swift
//   import {convertOptionIdName, isDataItemOption} from '../util/model';  -> model.convertOptionIdName / model.isDataItemOption
//   import { setCommonECData } from '../util/innerStore';            -> innerStore.setCommonECData
//   import type Graph from './Graph';                                -> sibling data/Graph.swift
//   import type Tree from './Tree';                                  -> sibling data/Tree.swift
//   import type { VisualMeta } from '../component/visualMap/VisualMapModel';  -> component/visualMap/VisualMapModel.swift (struct VisualMeta)
//   import {isSourceInstance, Source} from './Source';               -> sibling data/Source.swift
//   import { LineStyleProps } from '../model/mixin/lineStyle';       -> model/mixin/lineStyle.swift
//   import DataStore, { DataStoreDimensionDefine, DimValueGetter } from './DataStore';  -> sibling data/DataStore.swift
//   import { isSeriesDataSchema, SeriesDataSchema } from './helper/SeriesDataSchema';   -> sibling data/helper/SeriesDataSchema.swift
//   import { DataSanitizationFilter } from './helper/dataValueHelper';  -> sibling data/helper/dataValueHelper.swift

// const isObject = zrUtil.isObject;
// const map = zrUtil.map;
//   -> referenced as `util.isObject` / `util.map` at call sites.

// const CtorInt32Array = typeof Int32Array === 'undefined' ? Array : Int32Array;
//   -> PORT-NOTE: Swift always has typed storage; the feature-detection branch is dropped.
//      Inverted-index buffers are modeled as `ContiguousArray<Int>` (CONVENTIONS §1).

// Use prefix to avoid index to be the same as otherIdList[idx],
// which will cause weird update animation.
private let ID_PREFIX = "e\0\0"

private let INDEX_NOT_FOUND = -1

// type NameRepeatCount = {[name: string]: number};
private typealias NameRepeatCount = [String: Double]
// type ItrParamDims = DimensionLoose | Array<DimensionLoose>;
//   -> `Any` (CONVENTIONS dynamic union). `normalizeDimensions` collapses it to `[DimensionLoose]`.
public typealias ItrParamDims = Any
// If Ctx not specified, use List as Ctx
// type CtxOrList / EachCb0..2 / FilterCb0..2 / MapArrayCb0..2 / MapCb1..2
//   -> the arity-specialized + `this`-bound callbacks are collapsed to the array-arg forms
//      already declared on `DataStore` (EachCb / FilterCb / MapCb). The last array element is
//      the data index (as Double). The `ctx`/`this`-binding argument is dropped (PORT-NOTE).
public typealias MapArrayCb = (_ args: [ParsedValue]) -> Any?

// type SeriesDimensionDefineLoose = string | object | SeriesDimensionDefine;
public typealias SeriesDimensionDefineLoose = Any

// `SeriesDimensionLoose` and `SeriesDimensionName` is the dimension that is used by coordinate
// system or declared in `series.encode`, which will be saved in `SeriesData`. Other dimension
// might not be saved in `SeriesData` for performance consideration. See `createDimension` for
// more details.
public typealias SeriesDimensionLoose = DimensionLoose
public typealias SeriesDimensionName = DimensionName
// type SeriesDimensionIndex = DimensionIndex;

private let TRANSFERABLE_PROPERTIES = [
    "hasItemOption", "_nameList", "_idList", "_invertedIndicesMap",
    "_dimSummary", "userOutput",
    "_rawData", "_dimValueGetter",
    "_nameDimIdx", "_idDimIdx", "_nameRepeatCount"
]

private let CLONE_PROPERTIES = [
    "_approximateExtent"
]

public struct DefaultDataVisual {
    public var style: PathStyleProps?
    // Draw type determined which prop should be set with encoded color.
    // It's only available on the global visual. Use getVisual('drawType') to access it.
    // It will be set in visual/style.ts module in the first priority.
    public var drawType: String   // 'fill' | 'stroke'

    public var symbol: String?
    public var symbolSize: Any?   // number | number[]
    public var symbolRotate: Double?
    public var symbolKeepAspect: Bool?
    public var symbolOffset: Any?  // string | number | (string | number)[]
    public var z2: Double
    public var liftZ: Double?
    // For legend.
    public var legendIcon: String?
    public var legendLineStyle: Any?   // PORT-NOTE: concrete type is LineStyleProps (model/mixin/lineStyle); typed loosely as Any here

    // visualMap will inject visualMeta data
    public var visualMeta: [Any]?      // PORT-NOTE: element type is VisualMeta (component/visualMap/VisualMapModel.swift); typed loosely as [Any] here

    // If color is encoded from palette
    public var colorFromPalette: Bool?

    public var decal: DecalObject?
}

public struct DataCalculationInfo {   // PORT-NOTE: upstream generic <SERIES_MODEL>
    public var stackedDimension: DimensionName
    public var stackedByDimension: DimensionName
    public var isStackedByIndex: Bool
    public var stackedOverDimension: DimensionName
    public var stackResultDimension: DimensionName
    public var stackedOnSeries: Model?   // PORT-NOTE: SERIES_MODEL (model layer, Phase 5c)
}

// -----------------------------
// Internal method declarations:
// -----------------------------
//   upstream declares module-level `let prepareInvertedIndex / getId / getIdNameFromStore /
//   normalizeDimensions / transferProperties / cloneListForMapAndSample / makeIdFromName` that
//   are assigned inside the `SeriesData.internalField` IIFE (so they may visit private members).
//   Here they are ported as `private static func`s on `SeriesData` (static methods may access
//   private instance members of the same type) — see the `internalField` section at the end.

public final class SeriesData: DataStackSeriesData {

    public let type = "list"

    /**
     * Name of dimensions list of SeriesData.
     *
     * @caution Carefully use the index of this array.
     * Because when DataStore is an extra high dimension(>30) dataset. We will only pick
     * the used dimensions from DataStore to avoid performance issue.
     */
    public let dimensions: [SeriesDimensionName]

    // Information of each data dimension, like data type.
    private var _dimInfos: [SeriesDimensionName: SeriesDimensionDefine] = [:]

    private var _dimOmitted = false
    private var _schema: SeriesDataSchema?
    /**
     * @pending
     * Actually we do not really need to convert dimensionIndex to dimensionName
     * and do not need `_dimIdxToName` if we do everything internally based on dimension
     * index rather than dimension name.
     */
    private var _dimIdxToName: HashMap<DimensionName>?

    public let hostModel: Model?   // upstream: readonly hostModel: HostModel (HostModel extends Model)

    /**
     * @readonly
     */
    public var dataType: SeriesDataType?

    /**
     * @readonly
     * Host graph if List is used to store graph nodes / edges.
     */
    public var graph: Graph?       // upstream: `graph?: Graph` — wired by the sibling data/Graph.swift port

    /**
     * @readonly
     * Host tree if List is used to store tree nodes.
     */
    public var tree: Tree?         // upstream: `tree?: Tree` — wired by the sibling data/Tree.swift port

    private var _store: DataStore!

    private var _nameList: [String?] = []
    private var _idList: [String?] = []

    // Models of data option is stored sparse for optimizing memory cost
    // private _optionModels: Model[] = [];

    // Global visual properties after visual coding
    private var _visual: [String: Any] = [:]

    // Global layout properties.
    private var _layout: [String: Any] = [:]

    // Item visual properties after visual coding
    private var _itemVisuals: [[String: Any]?] = []

    // Item layout properties after layout
    private var _itemLayouts: [Any?] = []

    // Graphic elements
    private var _graphicEls: [Element?] = []

    // key: dim, value: extent
    private var _approximateExtent: [SeriesDimensionName: [Double]] = [:]

    private var _dimSummary: DimensionSummary!

    // key: dim, value: extent
    // PORT-NOTE: upstream `Record<SeriesDimensionName, ArrayLike<number>>` (the value is a
    //   `CtorInt32Array`). Modeled as `ContiguousArray<Int>` (CONVENTIONS §1).
    private var _invertedIndicesMap: [SeriesDimensionName: ContiguousArray<Int>] = [:]

    // PORT-NOTE: upstream `DataCalculationInfo<HostModel>`; stored as a dynamic bag so
    //   `getCalculationInfo(key)`/`setCalculationInfo(kvObject)` (and `dataStackHelper`) can
    //   read/write by string key. See `DataCalculationInfo` struct above for the documented shape.
    private var _calculationInfo: [String: Any] = [:]

    // User output info of this data.
    // DO NOT use it in other places!
    public var userOutput: DimensionUserOuput!

    // Having detected that there is data item is non primitive type
    // (in type `OptionDataItemObject`).
    // Like `data: [ { value: xx, itemStyle: {...} }, ...]`
    // At present it only happen in `SOURCE_FORMAT_ORIGINAL`.
    public var hasItemOption: Bool = false

    // id or name is used on dynamic data, mapping old and new items.
    // When generating id from name, avoid repeat.
    private var _nameRepeatCount: NameRepeatCount = [:]
    private var _nameDimIdx: DimensionIndex?
    private var _idDimIdx: DimensionIndex?

    private var __wrappedMethods: [String]?

    // PORT NOTE: upstream `wrapMethod` rebinds `this[methodName]` so registered injections fire when the
    //   method runs. Swift can not replace a method by string name, so instead `wrapMethod` stores the
    //   injection closures here, keyed by method name, and the ported methods that support wrapping invoke
    //   them explicitly (`cloneShallow`, the TRANSFERABLE_METHODS `map`/`downSample`/`minmaxDownSample`/
    //   `lttbDownSample`, and the CHANGABLE_METHODS `filterSelf`/`selectRange` — all fire via
    //   `fireWrappedMethodInjections`; see linkSeriesData `transferInjection`/`changeInjection`/
    //   `cloneShallowInjection` and Series.wrapData `onDataChange`). Registration order is preserved so the
    //   injections fire in the same order upstream's wrap chain does (original → transfer → cloneShallow).
    private var _wrappedMethodInjections: [String: [(SeriesData) -> Void]] = [:]

    // upstream `wrapMethod('getItemModel', injectFn)` (used by Tree.createTree's `beforeLink` to hang the
    //   per-depth level model off each node's item model as its `parentModel`). Unlike the `cloneShallow`
    //   injections above, this method RETURNS a value (the `Model`) that the injection may replace, and it
    //   takes the datum index as a second argument — so it needs a differently-typed store. Upstream's
    //   wrap chains `res = originalMethod(...); return injectFn(res, ...args)`; the port reproduces that in
    //   `getItemModel` by threading the model through each injection. Transferred on `cloneShallow` (via
    //   `transferProperties`) so a tree/sunburst series whose data is cloned in the pipeline keeps the
    //   level-model parenting — otherwise `levels[].itemStyle` silently stops reaching the sectors.
    private var _getItemModelInjections: [(_ res: Model, _ idx: Int) -> Model] = []

    // Methods that create a new list based on this list should be listed here.
    // Notice that those method should `RETURN` the new list.
    public let TRANSFERABLE_METHODS = ["cloneShallow", "downSample", "minmaxDownSample", "lttbDownSample", "map"]
    // Methods that change indices of this list should be listed here.
    public let CHANGABLE_METHODS = ["filterSelf", "selectRange"]
    public let DOWNSAMPLE_METHODS = ["downSample", "minmaxDownSample", "lttbDownSample"]

    /**
     * @param dimensionsInput.dimensions
     *        For example, ['someDimName', {name: 'someDimName', type: 'someDimType'}, ...].
     *        Dimensions should be concrete names like x, y, z, lng, lat, angle, radius
     */
    // PORT-NOTE: upstream is generic `SeriesData<HostModel extends Model, Visual extends
    //   DefaultDataVisual>`. The generics are dropped (the type is referenced as a plain
    //   `SeriesData` throughout the codebase): `HostModel` -> the `Model` placeholder, and
    //   `Visual` -> dynamic `[String: Any]` visual storage (`getVisual`/`setVisual` take String).
    public init(
        _ dimensionsInput: Any,   // SeriesDataSchema | SeriesDimensionDefineLoose[]
        _ hostModel: Model?
    ) {
        var dimensions: [SeriesDimensionDefineLoose]
        var assignStoreDimIdx = false
        if isSeriesDataSchema(dimensionsInput) {
            let schema = dimensionsInput as! SeriesDataSchema
            dimensions = schema.dimensions.map { $0 as SeriesDimensionDefineLoose }
            self._dimOmitted = schema.isDimensionOmitted()
            self._schema = schema
        }
        else {
            assignStoreDimIdx = true
            dimensions = (dimensionsInput as? [Any]) ?? []
        }

        // dimensions = dimensions || ['x', 'y'];
        if dimensions.isEmpty {
            dimensions = ["x", "y"]
        }

        var dimensionInfos: [SeriesDimensionName: SeriesDimensionDefine] = [:]
        var dimensionNames: [SeriesDimensionName] = []
        var invertedIndicesMap: [SeriesDimensionName: ContiguousArray<Int>] = [:]
        let needsHasOwn = false
        // const emptyObj = {};
        //   PORT-NOTE: upstream uses `(emptyObj as any)[dimensionName] != null` to detect a
        //   dimension name that collides with `Object.prototype` (e.g. 'constructor') and then
        //   switches `_getDimInfo` to a `hasOwnProperty` form. Swift `Dictionary` has no
        //   prototype, so this collision never happens; `needsHasOwn` stays `false`.

        var nameDimIdx: DimensionIndex?
        var idDimIdx: DimensionIndex?

        for i in 0..<dimensions.count {
            // Use the original dimensions[i], where other flag props may exists.
            let dimInfoInput = dimensions[i]

            let dimensionInfo: SeriesDimensionDefine
            if util.isString(dimInfoInput) {
                // new SeriesDimensionDefine({name: dimInfoInput})
                let d = SeriesDimensionDefine()
                d.name = dimInfoInput as! String
                dimensionInfo = d
            }
            else if !(dimInfoInput is SeriesDimensionDefine) {
                // new SeriesDimensionDefine(dimInfoInput)  — object-literal form
                // PORT-NOTE (deferred): `SeriesDimensionDefine.init` accepts only another
                //   `SeriesDimensionDefine`; the object-literal dimension case is reduced to copying the
                //   recognized `name` field — richer fields (type/coordDim) on a dict would be dropped, but
                //   the model layer (Phase 5c) produces SeriesDimensionDefine objects, so this path is not
                //   hit in practice. Widen the init when a dict dimension source lands.
                let d = SeriesDimensionDefine()
                if let dict = dimInfoInput as? [String: Any], let nm = dict["name"] as? String {
                    d.name = nm
                }
                dimensionInfo = d
            }
            else {
                dimensionInfo = dimInfoInput as! SeriesDimensionDefine
            }

            let dimensionName = dimensionInfo.name
            dimensionInfo.type = dimensionInfo.type ?? .float   // || 'float'
            if dimensionInfo.coordDim == nil {   // !dimensionInfo.coordDim
                dimensionInfo.coordDim = dimensionName
                dimensionInfo.coordDimIndex = 0
            }

            let otherDims = dimensionInfo.otherDims ?? DataVisualDimensions()
            dimensionInfo.otherDims = otherDims
            dimensionNames.append(dimensionName)
            dimensionInfos[dimensionName] = dimensionInfo

            if dimensionInfo.createInvertedIndices ?? false {
                invertedIndicesMap[dimensionName] = []
            }

            if __DEV__ {
                util.assert(assignStoreDimIdx || (dimensionInfo.storeDimIndex ?? -1) >= 0)
            }
            if assignStoreDimIdx {
                dimensionInfo.storeDimIndex = Double(i)
            }

            if otherDims.itemName == 0 {
                nameDimIdx = dimensionInfo.storeDimIndex
            }
            if otherDims.itemId == 0 {
                idDimIdx = dimensionInfo.storeDimIndex
            }
        }

        self.dimensions = dimensionNames
        self._dimInfos = dimensionInfos

        // (reordered vs upstream: Swift requires all stored properties to be initialized before
        //  an instance method like `_initGetDimensionInfo` can be called.)
        self.hostModel = hostModel
        self._invertedIndicesMap = invertedIndicesMap
        self._nameDimIdx = nameDimIdx
        self._idDimIdx = idDimIdx

        self._initGetDimensionInfo(needsHasOwn)

        if self._dimOmitted {
            let dimIdxToName: HashMap<DimensionName> = createHashMap()
            self._dimIdxToName = dimIdxToName
            util.each(dimensionNames) { dimName, _ in
                dimIdxToName.set(dimensionInfos[dimName]!.storeDimIndex, dimName)
            }
        }
    }

    /**
     *
     * Get concrete dimension name by dimension name or dimension index.
     * If input a dimension name, do not validate whether the dimension name exits.
     *
     * @caution
     * @param dim Must make sure the dimension is `SeriesDimensionLoose`.
     *
     * @notice Because of this reason, should better use `getDimensionIndex` instead.
     *
     * @return Concrete dim name.
     */
    public func getDimension(_ dim: SeriesDimensionLoose) -> DimensionName {
        let dimIdx = self._recognizeDimIndex(dim)
        if dimIdx == nil {
            return dim as? DimensionName ?? ""   // return dim as DimensionName
        }
        // dimIdx = dim as DimensionIndex;  (TS type assertion; dimIdx already the recognized numeric index)

        if !self._dimOmitted {
            return self.dimensions[Int(dimIdx!)]
        }

        // Retrieve from series dimension definition because it probably contains
        // generated dimension name (like 'x', 'y').
        let dimName = self._dimIdxToName?.get(dimIdx!)
        if let dimName = dimName {
            return dimName
        }

        let sourceDimDef = self._schema?.getSourceDimension(dimIdx!)
        if let sourceDimDef = sourceDimDef, let name = sourceDimDef.name {
            return name
        }
        return ""   // PORT-NOTE: getDimension returns a non-optional String; upstream may return undefined — the "" fallback stands in.
    }

    /**
     * Get dimension index in data store. Return -1 if not found.
     * Can be used to index value from getRawValue.
     */
    public func getDimensionIndex(_ dim: DimensionLoose) -> DimensionIndex {
        let dimIdx = self._recognizeDimIndex(dim)
        if let dimIdx = dimIdx {
            return dimIdx
        }

        if dim is NSNull {   // dim == null
            return -1
        }
        // `Any` is non-nil here; the `dim == null` upstream case maps to NSNull / absence at call sites.

        let dimInfo = self._getDimInfo(dimAsName(dim))
        return dimInfo != nil
            ? dimInfo!.storeDimIndex ?? -1   // PORT-NOTE: storeDimIndex is Optional in the port; upstream assumes it set — the -1 fallback matches the "not found" return.
            : self._dimOmitted
            ? self._schema!.getSourceDimensionIndex(dimAsName(dim))
            : -1
    }

    /**
     * The meanings of the input parameter `dim`:
     *
     * + If dim is a number (e.g., `1`), it means the index of the dimension.
     * + If dim is a number-like string (e.g., `"1"`):
     *     + If there is the same concrete dim name defined, it means that concrete name.
     *     + If not, it will be converted to a number (backward compatibility).
     * + If dim is a not-number-like string, it means the concrete dim name.
     *
     * @return recognized `DimensionIndex`. Otherwise return null/undefined (means `DimensionName`).
     */
    private func _recognizeDimIndex(_ dim: DimensionLoose) -> DimensionIndex? {
        if util.isNumber(dim) {
            return (dim as! Double)
        }
        // If being a number-like string but not being defined as a dimension name.
        if !(dim is NSNull)
            && !jsIsNaN(dim)
            && self._getDimInfo(dimAsName(dim)) == nil
            && (!self._dimOmitted || self._schema!.getSourceDimensionIndex(dimAsName(dim)) < 0)
        {
            return jsToNumber(dim)   // +dim
        }
        return nil
    }

    private func _getStoreDimIndex(_ dim: DimensionLoose) -> DimensionIndex {
        let dimIdx = self.getDimensionIndex(dim)
        // if __DEV__ { if (dimIdx == null) throw new Error('Unknown dimension ' + dim); }
        //   PORT-NOTE: `getDimensionIndex` returns a non-optional `DimensionIndex` (-1 if not
        //   found) so the null check can never fire here.
        return dimIdx
    }

    /**
     * Get type and calculation info of particular dimension
     */
    public func getDimensionInfo(_ dim: SeriesDimensionLoose) -> SeriesDimensionDefine {
        // Do not clone, because there may be categories in dimInfo.
        // POTENTIAL-BUG: upstream returns the value directly (may be undefined); force-unwrapped here
        //   because callers pass concrete dims that exist in `_dimInfos`. A caller passing an unknown dim
        //   would SIGTRAP rather than get undefined — the return type is non-optional, so widening it would
        //   ripple to all callers; left as a guarded risk.
        return self._getDimInfo(self.getDimension(dim))!
    }

    /**
     * If `dimName` if from outside of `SeriesData`,
     * use this method other than visit `this._dimInfos` directly.
     */
    private var _getDimInfo: (SeriesDimensionName) -> SeriesDimensionDefine? = { _ in nil }

    private func _initGetDimensionInfo(_ needsHasOwn: Bool) {
        let dimensionInfos = self._dimInfos
        // Swift `Dictionary` subscript already behaves like `hasOwnProperty` (returns nil if
        // absent), so both upstream branches collapse to the same lookup.
        self._getDimInfo = needsHasOwn
            ? { dimName in dimensionInfos[dimName] }
            : { dimName in dimensionInfos[dimName] }
    }

    /**
     * concrete dimension name list on coord.
     */
    public func getDimensionsOnCoord() -> [SeriesDimensionName] {
        return self._dimSummary.dataDimsOnCoord   // .slice() — value-type copy
    }

    /**
     * @param coordDim
     * @return concrete data dim. If not found, return null/undefined
     */
    public func mapDimension(_ coordDim: SeriesDimensionName) -> SeriesDimensionName? {
        let dimensionsSummary = self._dimSummary!
        return dimensionsSummary.encodeFirstDimNotExtra[coordDim]
    }
    public func mapDimension(_ coordDim: SeriesDimensionName, _ idx: Double) -> SeriesDimensionName? {
        let dimensionsSummary = self._dimSummary!
        let dims = dimensionsSummary.encode[coordDim]
        return dims != nil ? dims![Int(idx)] : nil
    }

    public func mapDimensionsAll(_ coordDim: SeriesDimensionName) -> [SeriesDimensionName] {
        let dimensionsSummary = self._dimSummary!
        let dims = dimensionsSummary.encode[coordDim]
        return (dims ?? [])   // .slice()
    }

    public func getStore() -> DataStore {
        return self._store
    }

    /**
     * Initialize from data
     * @param data source or data or data store.
     * @param nameList The name of a datum is used on data diff and default label/tooltip.
     */
    public func initData(
        _ data: Any,   // Source | OptionSourceData | DataStore | DataProvider
        _ nameList: [String?]? = nil,
        _ dimValueGetter: DimValueGetter? = nil
    ) {
        var store: DataStore?
        if let s = data as? DataStore {
            store = s
        }

        if store == nil {
            let dimensions = self.dimensions
            let provider: DataProvider = (isSourceInstance(data) || util.isArrayLike(data))
                ? DefaultDataProvider(data, Double(dimensions.count))
                : (data as! DataProvider)
            store = DataStore()
            let dimensionInfos: [DataStoreDimensionDefine] = util.map(dimensions) { dimName, _ in
                DataStoreDimensionDefine(
                    type: self._dimInfos[dimName]!.type,
                    property: dimName
                )
            }
            store!.initData(provider, dimensionInfos, dimValueGetter)
        }

        self._store = store

        // Reset
        self._nameList = nameList ?? []   // (nameList || []).slice()
        self._idList = []
        self._nameRepeatCount = [:]

        self._doInit(0, store!.count())

        // Cache summary info for fast visit. See "dimensionHelper".
        // Needs to be initialized after store is prepared.
        self._dimSummary = summarizeDimensions(self, self._schema)
        self.userOutput = self._dimSummary.userOutput
    }

    /**
     * Caution: Can be only called on raw data (before `this._indices` created).
     */
    public func appendData(_ data: ArrayLike<Any>) {
        let range = self._store.appendData(data)
        self._doInit(range[0], range[1])
    }
    /**
     * Caution: Can be only called on raw data (before `this._indices` created).
     * This method does not modify `rawData` (`dataProvider`), but only add values to store.
     *
     * The final count will be increased by `Math.max(values.length, names.length)`.
     */
    public func appendValues(_ values: [[Any?]], _ names: [String?]? = nil) {
        let r = self._store.appendValues(values, names != nil ? names!.count : nil)
        let start = r.start
        let end = r.end
        let shouldMakeIdFromName = self._shouldMakeIdFromName()

        self._updateOrdinalMeta()

        if let names = names {
            for idx in start..<end {
                let sourceIdx = idx - start
                sparseSet(&self._nameList, idx, sourceIdx < names.count ? names[sourceIdx] : nil)
                if shouldMakeIdFromName {
                    SeriesData.makeIdFromName(self, idx)
                }
            }
        }
    }

    private func _updateOrdinalMeta() {
        let store = self._store!
        let dimensions = self.dimensions
        for i in 0..<dimensions.count {
            let dimInfo = self._dimInfos[dimensions[i]]!
            if let ordinalMeta = dimInfo.ordinalMeta {
                store.collectOrdinalMeta(Int(dimInfo.storeDimIndex!), ordinalMeta)
            }
        }
    }

    private func _shouldMakeIdFromName() -> Bool {
        let provider = self._store.getProvider()
        // PORT-NOTE: upstream final term is `!provider.fillStorage` (method presence). In the
        //   ported `DataProvider`, `fillStorage` is a no-op default and is only meaningfully
        //   mounted for the typed-array source format — which is already excluded by the
        //   `sourceFormat !== TYPED_ARRAY` term — so the `!provider.fillStorage` term is dropped.
        return self._idDimIdx == nil
            && provider.getSource().sourceFormat != SOURCE_FORMAT_TYPED_ARRAY
    }

    private func _doInit(_ start: Int, _ end: Int) {
        if start >= end {
            return
        }

        let store = self._store!
        let provider = store.getProvider()

        self._updateOrdinalMeta()

        let sourceFormat = provider.getSource().sourceFormat
        let isFormatOriginal = sourceFormat == SOURCE_FORMAT_ORIGINAL

        // Each data item is value
        // [1, 2] / 2 ; if dataItem is {name: ...} or {id: ...}, it has highest priority.
        // This kind of ids and names are always stored `_nameList` and `_idList`.
        if isFormatOriginal && !provider.pure {
            var sharedDataItem: OptionDataItem = [OptionDataValue]()
            for idx in start..<end {
                // NOTICE: Try not to write things into dataItem
                let dataItem = provider.getItem(Double(idx), sharedDataItem as? [OptionDataValue])
                sharedDataItem = dataItem
                if !self.hasItemOption && model.isDataItemOption(dataItem) {
                    self.hasItemOption = true
                }
                // if (dataItem)
                let dict = dataItem as? [String: Any]
                let itemName = dict?["name"]
                if (idx >= self._nameList.count || self._nameList[idx] == nil)
                    && itemName != nil && !(itemName is NSNull) {
                    sparseSet(&self._nameList, idx, model.convertOptionIdName(itemName, nil))
                }
                let itemId = dict?["id"]
                if (idx >= self._idList.count || self._idList[idx] == nil)
                    && itemId != nil && !(itemId is NSNull) {
                    sparseSet(&self._idList, idx, model.convertOptionIdName(itemId, nil))
                }
            }
        }

        if self._shouldMakeIdFromName() {
            for idx in start..<end {
                SeriesData.makeIdFromName(self, idx)
            }
        }

        SeriesData.prepareInvertedIndex(self)
    }

    /**
     * Optimize for the scenario that data is filtered by a given extent.
     */
    public func getApproximateExtent(
        _ dim: SeriesDimensionLoose,
        _ filter: DataSanitizationFilter?
    ) -> [Double] {
        return self._approximateExtent[dimAsName(dim)]
            ?? self._store.getDataExtent(self._getStoreDimIndex(dim), filter)
    }

    /**
     * NOTICE: `_approximateExtent` does not support filter.
     */
    public func setApproximateExtent(_ extent: [Double], _ dim: SeriesDimensionLoose) {
        let dimName = self.getDimension(dim)
        self._approximateExtent[dimName] = extent   // .slice()
    }

    public func getCalculationInfo(_ key: String) -> Any? {
        return self._calculationInfo[key]
    }

    /**
     * @param key or k-v object
     */
    public func setCalculationInfo(_ key: [String: Any]) {
        // isObject(key) ? extend(this._calculationInfo, key) : ...
        for (k, v) in key {
            self._calculationInfo[k] = v
        }
    }
    public func setCalculationInfo(_ key: String, _ value: Any?) {
        self._calculationInfo[key] = value
    }

    /**
     * @return Never be null/undefined. `number` will be converted to string.
     */
    public func getName(_ idx: Int) -> String {
        let rawIndex = self.getRawIndex(idx)
        var name = (rawIndex >= 0 && rawIndex < self._nameList.count) ? self._nameList[rawIndex] : nil
        if name == nil && self._nameDimIdx != nil {
            name = SeriesData.getIdNameFromStore(self, Int(self._nameDimIdx!), rawIndex)
        }
        if name == nil {
            name = ""
        }
        return name!
    }

    private func _getCategory(_ dimIdx: Int, _ idx: Int) -> OrdinalRawValue {
        let ordinal = self._store.get(DimensionIndex(dimIdx), idx)
        let ordinalMeta = self._store.getOrdinalMeta(dimIdx)
        if let ordinalMeta = ordinalMeta {
            // ordinalMeta.categories[ordinal as OrdinalNumber]
            let oi = (ordinal as? Double) ?? Double.nan   // PORT-NOTE: numeric coercion (CONVENTIONS §1)
            if oi.isFinite {
                let i = Int(oi)
                if i >= 0 && i < ordinalMeta.categories.count {
                    return ordinalMeta.categories[i]
                }
            }
            return Double.nan   // out-of-range -> undefined in JS
        }
        return ordinal
    }

    /**
     * @return Never null/undefined. `number` will be converted to string.
     */
    public func getId(_ idx: Int) -> String {
        return SeriesData.getId(self, self.getRawIndex(idx))
    }

    public func count() -> Int {
        return self._store.count()
    }

    /**
     * Get value. Return NaN if idx is out of range.
     *
     * @notice Should better to use `data.getStore().get(dimIndex, dataIdx)` instead.
     */
    public func get(_ dim: SeriesDimensionName, _ idx: Int) -> ParsedValue? {
        let store = self._store!
        let dimInfo = self._dimInfos[dim]
        if let dimInfo = dimInfo {
            return store.get(dimInfo.storeDimIndex!, idx)
        }
        return nil
    }

    /**
     * @notice Should better to use `data.getStore().getByRawIndex(dimIndex, dataIdx)` instead.
     */
    public func getByRawIndex(_ dim: SeriesDimensionName, _ rawIdx: Int) -> ParsedValue? {
        let store = self._store!
        let dimInfo = self._dimInfos[dim]
        if let dimInfo = dimInfo {
            return store.getByRawIndex(dimInfo.storeDimIndex!, rawIdx)
        }
        return nil
    }

    public func getIndices() -> ContiguousArray<Int> {
        return self._store.getIndices()
    }

    public func getDataExtent(_ dim: DimensionLoose) -> [Double] {
        return self._store.getDataExtent(self._getStoreDimIndex(dim), nil)
    }

    public func getSum(_ dim: DimensionLoose) -> Double {
        return self._store.getSum(self._getStoreDimIndex(dim))
    }

    public func getMedian(_ dim: DimensionLoose) -> Double {
        return self._store.getMedian(self._getStoreDimIndex(dim))
    }

    /**
     * Get value for multi dimensions.
     */
    public func getValues(_ idx: Int) -> [ParsedValue] {
        return self._store.getValues(idx)
    }
    public func getValues(_ dimensions: [DimensionName], _ idx: Int) -> [ParsedValue] {
        let store = self._store!
        return store.getValues(util.map(dimensions) { dim, _ in self._getStoreDimIndex(dim) }, idx)
    }

    /**
     * If value is NaN. Including '-'
     * Only check the coord dimensions.
     */
    public func hasValue(_ idx: Int) -> Bool {
        let dataDimIndicesOnCoord = self._dimSummary.dataDimIndicesOnCoord
        var i = 0
        let len = dataDimIndicesOnCoord.count
        while i < len {
            // Ordinal type used on coord can not be string but only number, so we can use isNaN.
            if jsIsNaN(self._store.get(dataDimIndicesOnCoord[i], idx)) {
                return false
            }
            i += 1
        }
        return true
    }

    /**
     * Retrieve the index with given name
     */
    public func indexOfName(_ name: String) -> Int {
        var i = 0
        let len = self._store.count()
        while i < len {
            if self.getName(i) == name {
                return i
            }
            i += 1
        }
        return -1
    }

    public func getRawIndex(_ idx: Int) -> Int {
        return self._store.getRawIndex(idx)
    }

    public func indexOfRawIndex(_ rawIndex: Int) -> Int {
        return self._store.indexOfRawIndex(rawIndex)
    }

    /**
     * Only support the dimension which inverted index created.
     * @param dim concrete dim
     * @param value ordinal index
     * @return rawIndex
     */
    public func rawIndexOf(_ dim: SeriesDimensionName, _ value: OrdinalNumber) -> Int {
        let invertedIndices = !dim.isEmpty ? self._invertedIndicesMap[dim] : nil
        if __DEV__ {
            if invertedIndices == nil {
                fatalError("Do not supported yet")
            }
        }
        // const rawIndex = invertedIndices && invertedIndices[value];
        let v = value.isFinite ? Int(value) : -1
        let rawIndex: Int? = (invertedIndices != nil && v >= 0 && v < invertedIndices!.count)
            ? invertedIndices![v] : nil
        if rawIndex == nil {   // rawIndex == null || isNaN(rawIndex)
            return INDEX_NOT_FOUND
        }
        return rawIndex!
    }

    /**
     * Data iteration
     * @example
     *  list.each('x', function (x, idx) {});
     *  list.each(['x', 'y'], function (x, y, idx) {});
     *  list.each(function (idx) {})
     */
    public func each(_ cb: @escaping EachCb) {
        // ctxCompat / ctx dropped (PORT-NOTE: Swift closures have no `this` binding).
        self._store.each([], cb)
    }
    public func each(_ dims: ItrParamDims, _ cb: @escaping EachCb) {
        let dimIndices = util.map(SeriesData.normalizeDimensions(dims)) { dim, _ in self._getStoreDimIndex(dim) }
        self._store.each(dimIndices, cb)
    }

    /**
     * Data filter
     */
    @discardableResult
    public func filterSelf(_ cb: @escaping FilterCb) -> SeriesData {
        self._store = self._store.filter([], cb)
        self.fireWrappedMethodInjections("filterSelf", self)
        return self
    }
    @discardableResult
    public func filterSelf(_ dims: ItrParamDims, _ cb: @escaping FilterCb) -> SeriesData {
        let dimIndices = util.map(SeriesData.normalizeDimensions(dims)) { dim, _ in self._getStoreDimIndex(dim) }
        self._store = self._store.filter(dimIndices, cb)
        self.fireWrappedMethodInjections("filterSelf", self)
        return self
    }

    /**
     * Select data in range. (For optimization of filter)
     */
    @discardableResult
    public func selectRange(_ range: [String: [Double]]) -> SeriesData {
        var innerRange: [DimensionIndex: [Double]] = [:]
        let dims = util.keys(range)
        var dimIndices: [DimensionIndex] = []
        util.each(dims) { dim, _ in
            let dimIdx = self._getStoreDimIndex(dim)
            innerRange[dimIdx] = range[dim]
            dimIndices.append(dimIdx)
        }

        self._store = self._store.selectRange(innerRange)
        self.fireWrappedMethodInjections("selectRange", self)
        return self
    }

    /**
     * Data mapping to a plain array
     */
    public func mapArray(_ cb: @escaping MapArrayCb) -> [Any?] {
        return self.mapArray([], cb)
    }
    public func mapArray(_ dims: ItrParamDims, _ cb: @escaping MapArrayCb) -> [Any?] {
        var result: [Any?] = []
        self.each(dims) { args in
            result.append(cb(args))
        }
        return result
    }

    /**
     * Data mapping to a new List with given dimensions
     */
    public func map(_ dims: ItrParamDims, _ cb: @escaping MapCb) -> SeriesData {
        let dimIndices = util.map(SeriesData.normalizeDimensions(dims)) { dim, _ in self._getStoreDimIndex(dim) }

        let list = SeriesData.cloneListForMapAndSample(self)
        list._store = self._store.map(dimIndices, cb)
        self.fireWrappedMethodInjections("map", list)
        return list
    }

    /**
     * !!Danger: used on stack dimension only.
     */
    public func modify(_ dims: ItrParamDims, _ cb: @escaping MapCb) {
        if __DEV__ {
            util.each(SeriesData.normalizeDimensions(dims)) { dim, _ in
                let dimInfo = self.getDimensionInfo(dim)
                if !(dimInfo.isCalculationCoord ?? false) {
                    log.error("Danger: only stack dimension can be modified")
                }
            }
        }

        let dimIndices = util.map(SeriesData.normalizeDimensions(dims)) { dim, _ in self._getStoreDimIndex(dim) }

        // If do shallow clone here, if there are too many stacked series, it still cost lots of
        // memory, because `_store.dimensions` are not shared.
        self._store.modify(dimIndices, cb)
    }

    /**
     * Large data down sampling on given dimension
     * @param sampleIndex Sample index for name and id
     */
    public func downSample(
        _ dimension: DimensionLoose,
        _ rate: Double,
        _ sampleValue: @escaping (_ frameValues: [ParsedValue]) -> ParsedValueNumeric,
        _ sampleIndex: @escaping (_ frameValues: [ParsedValue], _ value: ParsedValueNumeric) -> Int
    ) -> SeriesData {
        let list = SeriesData.cloneListForMapAndSample(self)
        list._store = self._store.downSample(
            self._getStoreDimIndex(dimension),
            rate,
            sampleValue,
            sampleIndex
        )
        self.fireWrappedMethodInjections("downSample", list)
        return list
    }

    /**
     * Large data down sampling using min-max
     */
    public func minmaxDownSample(
        _ valueDimension: DimensionLoose,
        _ rate: Double
    ) -> SeriesData {
        let list = SeriesData.cloneListForMapAndSample(self)
        list._store = self._store.minmaxDownSample(
            self._getStoreDimIndex(valueDimension),
            rate
        )
        self.fireWrappedMethodInjections("minmaxDownSample", list)
        return list
    }

    /**
     * Large data down sampling using largest-triangle-three-buckets
     */
    public func lttbDownSample(
        _ valueDimension: DimensionLoose,
        _ rate: Double
    ) -> SeriesData {
        let list = SeriesData.cloneListForMapAndSample(self)
        list._store = self._store.lttbDownSample(
            self._getStoreDimIndex(valueDimension),
            rate
        )
        self.fireWrappedMethodInjections("lttbDownSample", list)
        return list
    }

    public func getRawDataItem(_ idx: Int) -> OptionDataItem {
        return self._store.getRawDataItem(idx)
    }

    // PORT bridge (not upstream): write a field onto the RAW option data item `rawIdx` in the underlying
    //   provider, so a subsequent `getItemModel(idx).get(key)` reflects it WITHOUT rebuilding the data.
    //   Reproduces upstream's shared-reference option mutation (see DefaultDataProvider.setRawItemField).
    //   `rawIdx` is a RAW source index (== option data index); consumed by SankeySeriesModel.setNodePosition.
    public func setRawDataItemField(_ rawIdx: Int, _ key: String, _ value: Any?) {
        (self._store.getProvider() as? DefaultDataProvider)?.setRawItemField(rawIdx, key, value)
    }

    /**
     * Get model of one data item.
     */
    // TODO: Type of data item
    public func getItemModel(_ idx: Int) -> Model {
        // const hostModel = this.hostModel;
        // const dataItem = this.getRawDataItem(idx) as ModelOption;
        // return new Model(dataItem, hostModel, hostModel && hostModel.ecModel);
        // (model/Model has landed — Phase 5c — so this is now the faithful implementation.)
        let hostModel = self.hostModel
        // upstream: `getRawDataItem(idx) as ModelOption`. `OptionDataItem` and `ModelOption` are both the
        //   `Any` PORT-NOTE alias, so the TS assertion cast is a no-op here — pass through directly
        //   (a conditional `as?` between two `Any` aliases always succeeds → warning).
        let dataItem: ModelOption = self.getRawDataItem(idx)
        var model = Model(dataItem, hostModel, hostModel?.ecModel)
        // upstream `wrapMethod('getItemModel', injectFn)` chain: run each registered injection, threading
        //   the (possibly replaced) model. Tree.createTree's `beforeLink` uses this to set the per-depth
        //   level model as the item model's parentModel, so `node.getModel('itemStyle')` inherits
        //   `levels[].itemStyle` (e.g. sunburst per-ring colors).
        for inject in self._getItemModelInjections {
            model = inject(model, idx)
        }
        return model
    }

    /**
     * Create a data differ
     */
    public func diff(_ otherList: SeriesData?) -> DataDiffer<SeriesData> {
        let thisList = self

        return DataDiffer<SeriesData>(
            otherList != nil ? otherList!.getStore().getIndices().map { $0 as Any } : [],
            self.getStore().getIndices().map { $0 as Any },
            // The DiffKeyGetter's FIRST arg is the value from getIndices() (the rawIndex), NOT the
            // loop position — upstream `function (idx) { return getId(list, idx); }` binds `idx` to
            // that value (DataDiffer calls keyGetter(arr[i], i)). Using the loop index instead would
            // produce wrong diff keys on FILTERED data (e.g. dataZoom). See PORT_STATUS §24 #0.
            { value, _ in
                otherList != nil ? SeriesData.getId(otherList!, value as! Int) : ""
            },
            { value, _ in
                SeriesData.getId(thisList, value as! Int)
            }
        )
    }

    /**
     * Get visual property.
     */
    public func getVisual(_ key: String) -> Any? {
        let visual = self._visual
        return visual[key]
    }

    /**
     * Set visual property
     *
     * @example
     *  setVisual('color', color);
     *  setVisual({ 'color': color });
     */
    public func setVisual(_ key: String, _ val: Any?) {
        self._visual[key] = val
    }
    public func setVisual(_ kvObj: [String: Any]) {
        _ = util.extend(&self._visual, kvObj)
    }

    /**
     * Get visual property of single data item
     */
    public func getItemVisual(_ idx: Int, _ key: String) -> Any? {
        let itemVisual = (idx >= 0 && idx < self._itemVisuals.count) ? self._itemVisuals[idx] : nil
        let val = itemVisual?[key]
        if val == nil {
            // Use global visual property
            return self.getVisual(key)
        }
        return val
    }

    /**
     * If exists visual property of single data item
     */
    public func hasItemVisual() -> Bool {
        return self._itemVisuals.count > 0
    }

    /**
     * Make sure itemVisual property is unique
     */
    // TODO: use key to save visual to reduce memory.
    @discardableResult
    public func ensureUniqueItemVisual(_ idx: Int, _ key: String) -> Any? {
        var itemVisual = (idx >= 0 && idx < self._itemVisuals.count) ? self._itemVisuals[idx] : nil
        if itemVisual == nil {
            itemVisual = [:]
            sparseSet(&self._itemVisuals, idx, itemVisual)
        }
        var val = itemVisual![key]
        if val == nil {
            val = self.getVisual(key)

            // TODO Performance?
            if util.isArray(val) {
                val = (val as? [Any])   // .slice() — Swift arrays are value types
            }
            else if util.isObject(val) {
                if let d = val as? [String: Any] {   // extend({}, val)
                    var c: [String: Any] = [:]
                    for (k, v) in d { c[k] = v }
                    val = c
                }
            }

            itemVisual![key] = val
            sparseSet(&self._itemVisuals, idx, itemVisual)
        }
        return val
    }
    /**
     * Set visual property of single data item
     *
     * @example
     *  setItemVisual(0, 'color', color);
     *  setItemVisual(0, { 'color': color });
     */
    public func setItemVisual(_ idx: Int, _ key: String, _ value: Any?) {
        var itemVisual = ((idx >= 0 && idx < self._itemVisuals.count) ? self._itemVisuals[idx] : nil) ?? [:]
        itemVisual[key] = value
        sparseSet(&self._itemVisuals, idx, itemVisual)
    }
    public func setItemVisual(_ idx: Int, _ kvObject: [String: Any]) {
        var itemVisual = ((idx >= 0 && idx < self._itemVisuals.count) ? self._itemVisuals[idx] : nil) ?? [:]
        for (k, v) in kvObject { itemVisual[k] = v }   // extend(itemVisual, key)
        sparseSet(&self._itemVisuals, idx, itemVisual)
    }

    /**
     * Clear itemVisuals and list visual.
     */
    public func clearAllVisual() {
        self._visual = [:]
        self._itemVisuals = []
    }

    /**
     * Set layout property.
     */
    public func setLayout(_ key: String, _ val: Any?) {
        self._layout[key] = val
    }
    public func setLayout(_ kvObj: [String: Any]) {
        _ = util.extend(&self._layout, kvObj)
    }

    /**
     * Get layout property.
     */
    public func getLayout(_ key: String) -> Any? {
        return self._layout[key]
    }

    /**
     * Get layout of single data item
     */
    public func getItemLayout(_ idx: Int) -> Any? {
        return (idx >= 0 && idx < self._itemLayouts.count) ? self._itemLayouts[idx] : nil
    }

    /**
     * Set layout of single data item
     */
    public func setItemLayout(_ idx: Int, _ layout: Any?, _ merge: Bool = false) {
        if merge {
            var base = ((idx >= 0 && idx < self._itemLayouts.count) ? (self._itemLayouts[idx] as? [String: Any]) : nil) ?? [:]
            if let l = layout as? [String: Any] {
                for (k, v) in l { base[k] = v }   // extend(this._itemLayouts[idx] || {}, layout)
            }
            sparseSet(&self._itemLayouts, idx, base)
        }
        else {
            sparseSet(&self._itemLayouts, idx, layout)
        }
    }

    /**
     * Clear all layout of single data item
     */
    public func clearItemLayouts() {
        self._itemLayouts = []   // this._itemLayouts.length = 0;
    }

    /**
     * Set graphic element relative to data. It can be set as null
     */
    public func setItemGraphicEl(_ idx: Int, _ el: Element?) {
        // const seriesIndex = this.hostModel && (this.hostModel as any).seriesIndex;
        //   (was a PORT-NOTE defaulting to 0 — with a live SeriesModel host the real index is stamped,
        //   so the focus/blur fan-out targets the right series in MULTI-series charts; a hardcoded 0
        //   made hovering series 1 blur against series 0's identity.)
        let seriesIndex: Double = (self.hostModel as? SeriesModel)?.seriesIndex ?? 0

        // PORT-NOTE: `innerStore.setCommonECData` requires a non-optional `SeriesDataType` (sibling port);
        //   upstream `this.dataType` may be undefined for main series data, reconciled here to `.main`.
        innerStore.setCommonECData(seriesIndex, self.dataType ?? .main, Double(idx), el)

        sparseSet(&self._graphicEls, idx, el)
    }

    public func getItemGraphicEl(_ idx: Int) -> Element? {
        return (idx >= 0 && idx < self._graphicEls.count) ? self._graphicEls[idx] : nil
    }

    public func eachItemGraphicEl(
        _ cb: (_ el: Element, _ idx: Int) -> Void,
        _ context: Any? = nil   // PORT-NOTE: `this`-binding dropped (Swift closures capture)
    ) {
        util.each(self._graphicEls) { el, idx in
            if let el = el {
                cb(el, idx)
            }
        }
    }

    /**
     * Shallow clone a new list except visual and layout properties, and graph elements.
     * New list only change the indices.
     */
    @discardableResult
    // PORT helper: fire the side-effect injections `wrapMethod` stored for `methodName`, in registration
    //   order, feeding each the method's result (`res`). Upstream rebinds `this[methodName]` so the injection
    //   runs after the original method; here the ported wrappable methods call this explicitly. Mirrors the
    //   `res` = original-method-return that upstream passes as `injectFunction.apply(this, [res].concat(...))`;
    //   the side-effecting injections (transferInjection re-linking references, changeInjection's
    //   `struct.update()`, onDataChange's task output-end) all return `res` unchanged, so returning the
    //   original `res` after firing is faithful.
    private func fireWrappedMethodInjections(_ methodName: String, _ res: SeriesData) {
        for injection in self._wrappedMethodInjections[methodName] ?? [] {
            injection(res)
        }
    }

    public func cloneShallow(_ list: SeriesData? = nil) -> SeriesData {
        var list = list
        if list == nil {
            list = SeriesData(
                self._schema != nil
                    ? (self._schema! as Any)
                    : (util.map(self.dimensions) { dimName, _ in self._getDimInfo(dimName)! } as Any),
                self.hostModel
            )
        }

        SeriesData.transferProperties(list!, self)
        list!._store = self._store

        // PORT NOTE: fire the injections `linkSeriesData` registered on `cloneShallow` (transferInjection +
        //   cloneShallowInjection). Upstream does this via the `wrapMethod` rebind; here the ported methods
        //   invoke stored injections explicitly. This is what re-links the shared tree/graph struct onto the
        //   fresh clone (`clone.tree = struct`, `struct.data = clone`), so a tree/treemap/sunburst series'
        //   `getData().tree` survives the `dataTaskReset` cloneShallow.
        self.fireWrappedMethodInjections("cloneShallow", list!)

        return list!
    }

    /**
     * Wrap some method to add more feature
     */
    public func wrapMethod(
        _ methodName: String,   // FunctionPropertyNames<SeriesData>
        _ injectFunction: @escaping (_ args: Any...) -> Any?
    ) {
        // PORT NOTE: upstream dynamically rebinds `this[methodName]` to run the original method then the
        //   injection. Swift cannot replace a method by string name, so the injection is STORED here (keyed
        //   by method name) and the ported wrappable methods invoke it explicitly. The injection is fed the
        //   original method's result (a new `SeriesData`), matching upstream's `[res].concat(arguments)`.
        //   `__wrappedMethods` bookkeeping is still recorded for `transferProperties` fidelity.
        self.__wrappedMethods = self.__wrappedMethods ?? []
        self.__wrappedMethods!.append(methodName)
        // `getItemModel` is a VALUE-returning wrapped method (takes `idx`, returns a `Model` the injection
        //   may replace); it goes into the dedicated `_getItemModelInjections` store so `getItemModel`
        //   can thread the result. All other wrapped methods (`cloneShallow`, the TRANSFERABLE_METHODS
        //   `map`/`downSample`/`minmaxDownSample`/`lttbDownSample`, and the CHANGABLE_METHODS
        //   `filterSelf`/`selectRange`) run for side effects on the result SeriesData; they are stored here
        //   and fired by those methods via `fireWrappedMethodInjections`.
        if methodName == "getItemModel" {
            self._getItemModelInjections.append { res, idx in
                // Upstream feeds `[res].concat(arguments)` → (model, idx). The ported `beforeLink`
                //   closure reads `args[0] as Model` and `args[1] as Double`, returning the (mutated) model.
                (injectFunction(res, Double(idx)) as? Model) ?? res
            }
        }
        else {
            self._wrappedMethodInjections[methodName, default: []].append { res in
                _ = injectFunction(res)
            }
        }
    }

    // ----------------------------------------------------------
    // A work around for internal method visiting private member.
    // (upstream `private static internalField = (function () { ... })()` IIFE; ported as
    //  `private static func`s — static methods may visit private instance members of the type.)
    // ----------------------------------------------------------

    private static func prepareInvertedIndex(_ data: SeriesData) {
        let invertedIndicesMap = data._invertedIndicesMap
        // zrUtil.each(invertedIndicesMap, function (invertedIndices, dim) { ... })
        for (dim, _) in invertedIndicesMap {
            let dimInfo = data._dimInfos[dim]!
            // Currently, only dimensions that has ordinalMeta can create inverted indices.
            let ordinalMeta = dimInfo.ordinalMeta
            let store = data._store!
            if let ordinalMeta = ordinalMeta {
                var invertedIndices = ContiguousArray<Int>(   // new CtorInt32Array(len)
                    repeating: 0, count: ordinalMeta.categories.count
                )
                // The default value of TypedArray is 0. To avoid miss mapping to 0, we should
                // set it as INDEX_NOT_FOUND.
                for i in 0..<invertedIndices.count {
                    invertedIndices[i] = INDEX_NOT_FOUND
                }
                for i in 0..<store.count() {
                    // Only support the case that all values are distinct.
                    // invertedIndices[store.get(dimInfo.storeDimIndex, i)] = i;
                    let ord = (store.get(dimInfo.storeDimIndex!, i) as? Double) ?? Double.nan
                    if ord.isFinite {
                        let oi = Int(ord)
                        if oi >= 0 && oi < invertedIndices.count {
                            invertedIndices[oi] = i
                        }
                    }
                }
                data._invertedIndicesMap[dim] = invertedIndices
            }
        }
    }

    private static func getIdNameFromStore(
        _ data: SeriesData, _ dimIdx: Int, _ idx: Int
    ) -> String? {
        return model.convertOptionIdName(data._getCategory(dimIdx, idx), nil)
    }

    /**
     * @see the comment of `List['getId']`.
     */
    private static func getId(_ data: SeriesData, _ rawIndex: Int) -> String {
        var id = (rawIndex >= 0 && rawIndex < data._idList.count) ? data._idList[rawIndex] : nil
        if id == nil && data._idDimIdx != nil {
            id = getIdNameFromStore(data, Int(data._idDimIdx!), rawIndex)
        }
        if id == nil {
            id = ID_PREFIX + String(rawIndex)
        }
        return id!
    }

    private static func normalizeDimensions(
        _ dimensions: ItrParamDims
    ) -> [DimensionLoose] {
        if let arr = dimensions as? [Any] {
            return arr
        }
        if !(dimensions is NSNull) {
            return [dimensions]   // dimensions != null ? [dimensions] : []
        }
        return []
    }

    /**
     * Data in excludeDimensions is copied, otherwise transferred.
     */
    private static func cloneListForMapAndSample(_ original: SeriesData) -> SeriesData {
        let list = SeriesData(
            original._schema != nil
                ? (original._schema! as Any)
                : (util.map(original.dimensions) { dimName, _ in original._getDimInfo(dimName)! } as Any),
            original.hostModel
        )
        // FIXME If needs stackedOn, value may already been stacked
        transferProperties(list, original)
        return list
    }

    private static func transferProperties(_ target: SeriesData, _ source: SeriesData) {
        // PORT-NOTE: upstream copies `TRANSFERABLE_PROPERTIES.concat(source.__wrappedMethods||[])`
        //   by string name with a `hasOwnProperty` guard. Swift has typed stored properties, so
        //   the existing ones are copied explicitly (`_rawData`/`_dimValueGetter` are legacy list
        //   entries that no longer exist on this class and are skipped).
        target.hasItemOption = source.hasItemOption
        target._nameList = source._nameList
        target._idList = source._idList
        target._invertedIndicesMap = source._invertedIndicesMap
        target._dimSummary = source._dimSummary
        target.userOutput = source.userOutput
        target._nameDimIdx = source._nameDimIdx
        target._idDimIdx = source._idDimIdx
        target._nameRepeatCount = source._nameRepeatCount

        target.__wrappedMethods = source.__wrappedMethods
        // Upstream copies each wrapped method FUNCTION by name (methods are instance props in JS). The port
        //   keeps the injections in side stores; carry the value-returning `getItemModel` injections onto
        //   the clone so a cloned tree/sunburst data keeps its per-node level-model parenting. (The
        //   `cloneShallow` injections in `_wrappedMethodInjections` are re-established by linkSeriesData's
        //   own cloneShallow injection, so they are not copied here — matching the prior behavior.)
        target._getItemModelInjections = source._getItemModelInjections

        // CLONE_PROPERTIES
        target._approximateExtent = util.clone(source._approximateExtent)

        target._calculationInfo = source._calculationInfo   // extend({}, source._calculationInfo)
    }

    private static func makeIdFromName(_ data: SeriesData, _ idx: Int) {
        let nameDimIdx = data._nameDimIdx
        let idDimIdx = data._idDimIdx

        var name = (idx >= 0 && idx < data._nameList.count) ? data._nameList[idx] : nil
        var id = (idx >= 0 && idx < data._idList.count) ? data._idList[idx] : nil

        if name == nil && nameDimIdx != nil {
            name = getIdNameFromStore(data, Int(nameDimIdx!), idx)
            sparseSet(&data._nameList, idx, name)
        }
        if id == nil && idDimIdx != nil {
            id = getIdNameFromStore(data, Int(idDimIdx!), idx)
            sparseSet(&data._idList, idx, id)
        }
        if id == nil && name != nil {
            let nm = name!
            let nmCnt = (data._nameRepeatCount[nm] ?? 0) + 1
            data._nameRepeatCount[nm] = nmCnt
            id = nm
            if nmCnt > 1 {
                id! += "__ec__" + String(Int(nmCnt))
            }
            sparseSet(&data._idList, idx, id)
        }
    }

    // ----------------------------------------------------------------------------------
    // upstream: `interface SeriesData { getLinkedData(...); getLinkedDataAll(); }` (TS
    // declaration-merging), implemented by Graph.ts / Tree.ts.
    // PORT-NOTE: upstream runtime-attaches these to the instance (linkSeriesData.ts:182-183). Swift can't
    //   attach methods at runtime, so the real logic lives as `LinkSeriesData.getLinkedData(thisData:)` /
    //   `.getLinkedDataAll(thisData:)` static funcs (data/helper/linkSeriesData.swift), and Series.swift
    //   routes through those. These instance stubs mirror the declaration-merged signature and are unused
    //   (they fatalError if ever called directly).
    // ----------------------------------------------------------------------------------
    public func getLinkedData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        _ = dataType
        fatalError("getLinkedData: use LinkSeriesData.getLinkedData(thisData:) — instance stub not attached")
    }
    public func getLinkedDataAll() -> [(data: SeriesData, type: SeriesDataType?)] {
        fatalError("getLinkedDataAll: use LinkSeriesData.getLinkedDataAll(thisData:) — instance stub not attached")
    }
}

// ============================================================================
// File-scope helpers (not upstream symbols).
// ============================================================================

// JS sparse-array assignment (`arr[idx] = value`): JS arrays auto-extend with holes; Swift
// arrays do not. Grow the buffer (with `nil`) up to `idx` then write.
private func sparseSet<T>(_ arr: inout [T?], _ idx: Int, _ value: T?) {
    while arr.count <= idx { arr.append(nil) }
    arr[idx] = value
}

// `dim` used as an object key (`this._approximateExtent[dim]`) / dimension name lookup. JS
// coerces a number key to its string form; a string passes through.
private func dimAsName(_ dim: Any?) -> DimensionName {
    if let s = dim as? String { return s }
    return jsNumberOrStr(dim)
}

// JS `Number(value)` coercion used by `+dim` and `isNaN(dim)`. Number('')===0,
// Number('  12 ')===12, Number('x')===NaN, Number(true)===1.
private func jsToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }   // Number('') === 0
        return Double(t) ?? Double.nan
    }
    if let b = v as? Bool { return b ? 1 : 0 }
    return Double.nan   // Number(undefined) === NaN
}
private func jsIsNaN(_ v: Any?) -> Bool {
    return jsToNumber(v).isNaN
}

// JS `value + ''` for a non-string key.
private func jsNumberOrStr(_ v: Any?) -> String {
    switch v {
    case nil: return "undefined"
    case let s as String: return s
    case let d as Double:
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    case let i as Int: return String(i)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: v!)
    }
}

// export default SeriesData;
