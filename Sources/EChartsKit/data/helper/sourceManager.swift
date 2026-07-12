// Ported from echarts/src/data/helper/sourceManager.ts — keep in sync with upstream
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

// import { DatasetModel } from '../../component/dataset/install';
//   -> component/dataset/datasetInstall.swift (Phase 27). `DatasetModel` is a protocol (data-layer
//      forward reference in sourceHelper.swift); `DatasetModelImpl` is the concrete ComponentModel.
//      The dataset host path here is now fully wired (see `_getUpstreamSourceManagers`).
// import SeriesModel from '../../model/Series';                       -> SeriesModel (model/Series.swift)
// import { setAsPrimitive, map, isTypedArray, assert, each, retrieve2 } from 'zrender/src/core/util';
//   -> ZRenderKit `util.*` (map/isTypedArray/assert/each/retrieve2). `setAsPrimitive` is NOT
//      ported; used only by `disableTransformOptionMerge` (dataset) -> PORT-NOTE.
// import { SourceMetaRawOption, Source, createSource, cloneSourceShallow } from '../Source';
//   -> data/Source.swift (same module).
// import { SeriesEncodableModel, OptionSourceData, SOURCE_FORMAT_TYPED_ARRAY, SOURCE_FORMAT_ORIGINAL,
//          SourceFormat, SeriesLayoutBy, OptionSourceHeader, DimensionDefinitionLoose, Dictionary }
//   from '../../util/types';                                          -> util/types.swift.
// import { querySeriesUpstreamDatasetModel, queryDatasetUpstreamDatasetModels } from './sourceHelper';
//   -> sourceHelper.swift (namespace enum `sourceHelper`).
// import { applyDataTransform } from './transform';
//   -> data/helper/transform.swift (Phase 27). Used by `_applyTransform` (dataset transform).
// import DataStore, { DataStoreDimensionDefine } from '../DataStore';  -> data/DataStore.swift.
// import { DefaultDataProvider } from './dataProvider';               -> data/helper/dataProvider.swift.
// import { SeriesDataSchema } from './SeriesDataSchema';              -> data/helper/SeriesDataSchema.swift.
import Foundation
import ZRenderKit

// upstream: type DataStoreMap = Dictionary<DataStore>;
// (ZRenderKit provides `typealias Dictionary<T> = [String: T]`; the named alias is kept for parity.)
public typealias DataStoreMap = [String: DataStore]

// Host of a SourceManager. Upstream typing is `DatasetModel | SeriesModel`; modeled here as a
// marker protocol both host kinds conform to (SeriesModel via the extension below;
// DatasetModelImpl conforms directly — see component/dataset/datasetInstall.swift, Phase 27).
// Only `uid` is required by SourceManager itself.
public protocol SourceManagerHost: AnyObject {
    var uid: String { get }
}

// Retroactive conformance so a `SeriesModel` can be held as `_sourceHost` without editing
// Series.swift. `uid` is inherited from ComponentModel. (Integration NOTE: do NOT also add
// `: SourceManagerHost` to the SeriesModel class decl — that would be a duplicate conformance.)
extension SeriesModel: SourceManagerHost {}

/**
 * [REQUIREMENT_MEMO]:
 * (0) `metaRawOption` means `dimensions`/`sourceHeader`/`seriesLayoutBy` in raw option.
 * (1) Keep support the feature: `metaRawOption` can be specified both on `series` and
 * `root-dataset`. Them on `series` has higher priority.
 * (2) Do not support to set `metaRawOption` on a `non-root-dataset`, because it might
 * confuse users: whether those props indicate how to visit the upstream source or visit
 * the transform result source, and some transforms has nothing to do with these props,
 * and some transforms might have multiple upstream.
 * (3) Transforms should specify `metaRawOption` in each output, just like they can be
 * declared in `root-dataset`.
 * (4) At present only support visit source in `SERIES_LAYOUT_BY_COLUMN` in transforms.
 * That is for reducing complexity in transforms.
 * PENDING: Whether to provide transposition transform?
 *
 * [IMPLEMENTAION_MEMO]:
 * "sourceVisitConfig" are calculated from `metaRawOption` and `data`.
 * They will not be calculated until `source` is about to be visited (to prevent from
 * duplicate calcuation). `source` is visited only in series and input to transforms.
 *
 * [DIMENSION_INHERIT_RULE]:
 * By default the dimensions are inherited from ancestors, unless a transform return
 * a new dimensions definition.
 * (See upstream for the full option-shape examples.)
 */
public final class SourceManager {

    // Currently only datasetModel can host `transform`
    // (upstream holds a strong ref to the host; NOT weak.)
    private let _sourceHost: SourceManagerHost

    // Cached source. Do not repeat calculating if not dirty.
    private var _sourceList: [Source] = []

    private var _storeList: [DataStoreMap] = []

    // version sign of each upstream source manager.
    private var _upstreamSignList: [String] = []

    private var _versionSignBase: Double = 0

    private var _dirty = true

    public init(_ sourceHost: SourceManagerHost) {
        self._sourceHost = sourceHost
    }

    /**
     * Mark dirty.
     */
    public func dirty() {
        self._setLocalSource([], [])
        self._storeList = []
        self._dirty = true
    }

    private func _setLocalSource(
        _ sourceList: [Source],
        _ upstreamSignList: [String]
    ) {
        self._sourceList = sourceList
        self._upstreamSignList = upstreamSignList
        self._versionSignBase += 1
        if self._versionSignBase > 9e10 {
            self._versionSignBase = 0
        }
    }

    /**
     * For detecting whether the upstream source is dirty, so that
     * the local cached source (in `_sourceList`) should be discarded.
     */
    private func _getVersionSign() -> String {
        // upstream: this._sourceHost.uid + '_' + this._versionSignBase (JS number coercion;
        // `_versionSignBase` is integer-valued so it prints without a fraction).
        return self._sourceHost.uid + "_" + jsNumberStr(self._versionSignBase)
    }

    /**
     * Always return a source instance. Otherwise throw error.
     */
    public func prepareSource() {
        // For the case that call `setOption` multiple time but no data changed,
        // cache the result source to prevent from repeating transform.
        if self._isDirty() {
            self._createSource()
            self._dirty = false
        }
    }

    private func _createSource() {
        self._setLocalSource([], [])

        let sourceHost = self._sourceHost

        let upSourceMgrList = self._getUpstreamSourceManagers()
        let hasUpstream = !upSourceMgrList.isEmpty
        // upstream: `let resultSourceList: Source[]; let upstreamSignList: string[];`
        // (assigned in each branch, then asserted non-null before use.)
        var resultSourceList: [Source]!
        var upstreamSignList: [String]!

        if isSeries(sourceHost) {
            let seriesModel = sourceHost as! SeriesModel
            var data: OptionSourceData?
            var sourceFormat: SourceFormat
            var upSource: Source?

            // Has upstream dataset
            if hasUpstream {
                let upSourceMgr = upSourceMgrList[0]
                upSourceMgr.prepareSource()
                upSource = upSourceMgr.getSource()
                data = upSource!.data
                sourceFormat = upSource!.sourceFormat
                upstreamSignList = [upSourceMgr._getVersionSign()]
            }
            // Series data is from own.
            else {
                data = seriesModel.get("data", true)  // as OptionSourceData
                sourceFormat = util.isTypedArray(data)
                    ? SOURCE_FORMAT_TYPED_ARRAY : SOURCE_FORMAT_ORIGINAL
                upstreamSignList = []
            }

            // See [REQUIREMENT_MEMO], merge settings on series and parent dataset if it is root.
            // upstream: `this._getSourceMetaRawOption() || {}` — the Swift helper always returns a
            // struct (never nil), so `|| {}` never triggers.
            let newMetaRawOption = self._getSourceMetaRawOption()
            // upstream: `upSource && upSource.metaRawOption || {}`. Modeled as an Optional: nil
            // represents the JS empty `{}` (all fields `undefined`) used when there is no upSource.
            let upMetaRawOption: SourceMetaRawOption? = upSource?.metaRawOption
            // upstream: `retrieve2(...) || null`. retrieve2 already yields nil when both are
            // absent; the only meaningful values are 'row'/'column' (truthy), so `|| null` is a
            // no-op here. nil therefore represents JS `null` (distinct from the RHS `undefined`
            // modeled by `upMetaRawOption == nil` in `needsCreateSource`).
            let seriesLayoutBy = util.retrieve2(newMetaRawOption.seriesLayoutBy, upMetaRawOption?.seriesLayoutBy)
            let sourceHeader = util.retrieve2(newMetaRawOption.sourceHeader, upMetaRawOption?.sourceHeader)
            // Note here we should not use `upSource.dimensionsDefine`. Consider the case:
            // `upSource.dimensionsDefine` is detected by `seriesLayoutBy: 'column'`,
            // but series need `seriesLayoutBy: 'row'`.
            let dimensions = util.retrieve2(newMetaRawOption.dimensions, upMetaRawOption?.dimensions)

            // We share source with dataset as much as possible
            // to avoid extra memory cost of high dimensional data.
            // upstream:
            //   const needsCreateSource = seriesLayoutBy !== upMetaRawOption.seriesLayoutBy
            //       || !!sourceHeader !== !!upMetaRawOption.sourceHeader
            //       || dimensions;
            // When there is no upstream metaRawOption (upMetaRawOption == nil), the RHS of each
            // `!==` is JS `undefined`; the LHS `seriesLayoutBy` is `value|null` (never undefined),
            // so the first term is always true -> a source IS created for the inline-data series.
            // POTENTIAL-BUG (sourceManager.ts:240): when `upMetaRawOption != nil` (dataset upstream)
            //   the null-vs-undefined `!==` distinction for `seriesLayoutBy` is collapsed by Swift
            //   Optionals — a JS `null` and `undefined` both map to `nil`, so `needsCreateSource` may
            //   diverge from upstream in the dataset-upstream path. Revisit with a dataset SourceManager.
            let needsCreateSource = (upMetaRawOption == nil || seriesLayoutBy != upMetaRawOption!.seriesLayoutBy)
                || (jsTruthy(sourceHeader) != jsTruthy(upMetaRawOption?.sourceHeader ?? nil))
                || (dimensions != nil)
            resultSourceList = needsCreateSource ? [createSource(
                data,
                SourceMetaRawOption(seriesLayoutBy: seriesLayoutBy, sourceHeader: sourceHeader, dimensions: dimensions),
                sourceFormat
            )] : []
        }
        else {
            let datasetModel = sourceHost as! DatasetModel

            // Has upstream dataset.
            if hasUpstream {
                // const result = this._applyTransform(upSourceMgrList);
                let result = self._applyTransform(upSourceMgrList)
                resultSourceList = result.sourceList
                upstreamSignList = result.upstreamSignList
            }
            // Is root dataset.
            else {
                // const sourceData = datasetModel.get('source', true);
                let sourceData = datasetModel.get("source", true)
                // resultSourceList = [createSource(sourceData, this._getSourceMetaRawOption(), null)];
                resultSourceList = [createSource(
                    sourceData,
                    self._getSourceMetaRawOption(),
                    nil
                )]
                upstreamSignList = []
            }
        }

        if __DEV__ {
            util.assert(resultSourceList != nil && upstreamSignList != nil)
        }

        self._setLocalSource(resultSourceList, upstreamSignList)
    }

    private func _applyTransform(
        _ upMgrList: [SourceManager]
    ) -> (sourceList: [Source], upstreamSignList: [String]) {
        // const datasetModel = this._sourceHost as DatasetModel;
        let datasetModel = self._sourceHost as! DatasetModel
        // const transformOption = datasetModel.get('transform', true);
        let transformOption = datasetModel.get("transform", true)
        // const fromTransformResult = datasetModel.get('fromTransformResult', true);
        let fromTransformResult = datasetModel.get("fromTransformResult", true)

        if __DEV__ {
            // assert(fromTransformResult != null || transformOption != null);
            util.assert(!isNullish(fromTransformResult) || !isNullish(transformOption))
        }

        if !isNullish(fromTransformResult) {
            var errMsg = ""
            if upMgrList.count != 1 {
                if __DEV__ {
                    errMsg = "When using `fromTransformResult`, there should be only one upstream dataset"
                }
                doThrow(errMsg)
            }
        }

        // let sourceList: Source[];
        var sourceList: [Source]!
        var upSourceList: [Source] = []
        var upstreamSignList: [String] = []
        util.each(upMgrList) { upMgr, _ in
            upMgr.prepareSource()
            // const upSource = upMgr.getSource(fromTransformResult || 0);
            let upSource = upMgr.getSource(optNumberOrZero(fromTransformResult))
            var errMsg = ""
            // if (fromTransformResult != null && !upSource) { ... doThrow ... }
            if !isNullish(fromTransformResult) && upSource == nil {
                if __DEV__ {
                    errMsg = "Can not retrieve result by `fromTransformResult`: " + jsAnyString(fromTransformResult)
                }
                doThrow(errMsg)
            }
            // upstream pushes the (possibly undefined) upSource; here upSource is non-nil on the
            // reachable path (fromTransformResult nil -> getSource(0) always yields the main source).
            upSourceList.append(upSource!)
            upstreamSignList.append(upMgr._getVersionSign())
        }

        if jsTruthy(transformOption) {
            // sourceList = applyDataTransform(transformOption, upSourceList, { datasetIndex: datasetModel.componentIndex });
            //   `applyDataTransform` is `throws` in the port (upstream `throwError` throws a JS Error
            //   that bubbles through `prepareSource`); route a bad-transform error to `doThrow`
            //   (fatalError) to keep the `prepareSource` chain non-throwing, matching the existing
            //   `doThrow` convention in this file for option-level transform errors.
            do {
                sourceList = try applyDataTransform(
                    transformOption!,
                    upSourceList,
                    DataTransformInfoForPrint(datasetIndex: datasetModel.componentIndex)
                )
            }
            catch let err as EChartsError {
                doThrow(err.message ?? "")
            }
            catch {
                doThrow("\(error)")
            }
        }
        else if !isNullish(fromTransformResult) {
            // sourceList = [cloneSourceShallow(upSourceList[0])];
            sourceList = [cloneSourceShallow(upSourceList[0])]
        }

        // return { sourceList, upstreamSignList };
        return (sourceList, upstreamSignList)
    }

    private func _isDirty() -> Bool {
        if self._dirty {
            return true
        }

        // All sourceList is from the some upstream.
        let upSourceMgrList = self._getUpstreamSourceManagers()
        for i in 0..<upSourceMgrList.count {
            let upSrcMgr = upSourceMgrList[i]
            if
                // Consider the case that there is ancestor diry, call it recursively.
                // The performance is probably not an issue because usually the chain is not long.
                upSrcMgr._isDirty()
                || self._upstreamSignList[i] != upSrcMgr._getVersionSign()
            {
                return true
            }
        }
        // upstream: implicit `return undefined` when the loop completes.
        return false
    }

    /**
     * @param sourceIndex By default 0, means "main source".
     *                    In most cases there is only one source.
     */
    public func getSource(_ sourceIndex: Double? = nil) -> Source? {
        // upstream: `sourceIndex = sourceIndex || 0`
        let sourceIndex = Int(sourceIndex ?? 0)
        let source = sourceIndex >= 0 && sourceIndex < self._sourceList.count
            ? self._sourceList[sourceIndex] : nil
        if source == nil {
            // Series may share source instance with dataset.
            let upSourceMgrList = self._getUpstreamSourceManagers()
            return upSourceMgrList.first?.getSource(Double(sourceIndex))
        }
        return source
    }

    /**
     *
     * Get a data store which can be shared across series.
     * Only available for series.
     *
     * @param seriesDimRequest Dimensions that are generated in series.
     *        Should have been sorted by `storeDimIndex` asc.
     */
    public func getSharedDataStore(_ seriesDimRequest: SeriesDataSchema) -> DataStore {
        if __DEV__ {
            util.assert(isSeries(self._sourceHost), "Can only call getDataStore on series source manager.")
        }
        let schema = seriesDimRequest.makeStoreSchema()
        return self._innerGetDataStore(
            schema.dimensions, seriesDimRequest.source, schema.hash
        )!
    }

    private func _innerGetDataStore(
        _ storeDims: [DataStoreDimensionDefine],
        _ seriesSource: Source,
        _ sourceReadKey: String
    ) -> DataStore? {
        // TODO Can use other sourceIndex?
        let sourceIndex = 0

        // upstream: `const storeList = this._storeList; let cachedStoreMap = storeList[sourceIndex];
        //            if (!cachedStoreMap) { cachedStoreMap = storeList[sourceIndex] = {}; }`
        // JS auto-vivifies the array hole at `sourceIndex`; grow the Swift array (sourceIndex == 0).
        if self._storeList.count <= sourceIndex {
            self._storeList.append([:])
        }
        // Value-type copy; written back after mutation (JS mutates the shared map in place).
        var cachedStoreMap = self._storeList[sourceIndex]

        var cachedStore = cachedStoreMap[sourceReadKey]
        if cachedStore == nil {
            let upSourceMgr = self._getUpstreamSourceManagers().first

            if isSeries(self._sourceHost), let upSourceMgr = upSourceMgr {
                cachedStore = upSourceMgr._innerGetDataStore(
                    storeDims, seriesSource, sourceReadKey
                )
            }
            else {
                let store = DataStore()
                // Always create store from source of series.
                store.initData(
                    DefaultDataProvider(seriesSource, Double(storeDims.count)),
                    storeDims
                )
                cachedStore = store
            }
            cachedStoreMap[sourceReadKey] = cachedStore
            self._storeList[sourceIndex] = cachedStoreMap
        }

        return cachedStore
    }

    /**
     * PENDING: Is it fast enough?
     * If no upstream, return empty array.
     */
    private func _getUpstreamSourceManagers() -> [SourceManager] {
        // Always get the relationship from the raw option.
        // Do not cache the link of the dependency graph, so that
        // there is no need to update them when change happens.
        let sourceHost = self._sourceHost

        if isSeries(sourceHost) {
            // const datasetModel = querySeriesUpstreamDatasetModel(sourceHost);
            // return !datasetModel ? [] : [datasetModel.getSourceManager()];
            let datasetModel = sourceHelper.querySeriesUpstreamDatasetModel(sourceHost as! SeriesModel)
            guard let datasetModel = datasetModel else {
                return []
            }
            return [datasetModel.getSourceManager()]
        }
        else {
            // return map(queryDatasetUpstreamDatasetModels(sourceHost as DatasetModel),
            //     datasetModel => datasetModel.getSourceManager());
            return util.map(
                sourceHelper.queryDatasetUpstreamDatasetModels(sourceHost as! DatasetModel)
            ) { datasetModel, _ in datasetModel.getSourceManager() }
        }
    }

    private func _getSourceMetaRawOption() -> SourceMetaRawOption {
        let sourceHost = self._sourceHost
        var seriesLayoutBy: SeriesLayoutBy?
        var sourceHeader: OptionSourceHeader?
        var dimensions: [DimensionDefinitionLoose]?
        if isSeries(sourceHost) {
            let seriesModel = sourceHost as! SeriesModel
            seriesLayoutBy = seriesModel.get("seriesLayoutBy", true) as? SeriesLayoutBy
            sourceHeader = seriesModel.get("sourceHeader", true)
            dimensions = seriesModel.get("dimensions", true) as? [DimensionDefinitionLoose]
        }
        // See [REQUIREMENT_MEMO], `non-root-dataset` do not support them.
        else if self._getUpstreamSourceManagers().isEmpty {
            // const model = sourceHost as DatasetModel;
            // seriesLayoutBy = model.get('seriesLayoutBy', true);
            // sourceHeader = model.get('sourceHeader', true);
            // dimensions = model.get('dimensions', true);
            let datasetModel = sourceHost as! DatasetModel
            seriesLayoutBy = datasetModel.get("seriesLayoutBy", true) as? SeriesLayoutBy
            sourceHeader = datasetModel.get("sourceHeader", true)
            dimensions = datasetModel.get("dimensions", true) as? [DimensionDefinitionLoose]
        }
        return SourceMetaRawOption(seriesLayoutBy: seriesLayoutBy, sourceHeader: sourceHeader, dimensions: dimensions)
    }

}

// Call this method after `super.init` and `super.mergeOption` to
// disable the transform merge, but do not disable transform clone from rawOption.
// upstream:
//   const transformOption = datasetModel.option.transform;
//   transformOption && setAsPrimitive(datasetModel.option.transform);
public func disableTransformOptionMerge(_ datasetModel: DatasetModel) {
    // const transformOption = datasetModel.option.transform;
    let transformOption = (datasetModel.option as? [String: Any])?["transform"]
    if jsTruthy(transformOption) {
        // transformOption && setAsPrimitive(datasetModel.option.transform);
        // PORT-NOTE (deferred): requires `util.setAsPrimitive` (not ported — util.swift:474): `setAsPrimitive`
        //   tags the transform option object with a hidden key so the option-merge pass replaces
        //   it wholesale instead of deep-merging it. Only affects a *second* `setOption` re-merge;
        //   the static single-setOption transform data path is unaffected. Wire once
        //   `setAsPrimitive` lands.
        _ = transformOption
    }
}

// upstream: `sourceHost is SeriesEncodableModel` type guard, checking `mainType === 'series'`.
// For the two possible host kinds (SeriesModel | DatasetModel) an `is SeriesModel` test is
// equivalent (a SeriesModel's mainType is 'series'; a DatasetModel is not a SeriesModel), and it
// avoids depending on `mainType` being assigned before this runs.
func isSeries(_ sourceHost: SourceManagerHost) -> Bool {
    // Avoid circular dependency with Series.ts
    return sourceHost is SeriesModel
}

// upstream: `function doThrow(errMsg) { throw new Error(errMsg); }`.
// Fires on invalid dataset transform config (a dev/authoring error); maps a JS throw to the
// port's established fatalError-on-dev-error pattern, consistent with the __DEV__ asserts above.
func doThrow(_ errMsg: String) -> Never {
    fatalError(errMsg)
}

// JS `x == null` (null or undefined). NSNull models an explicit JS `null`.
private func isNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// JS `x || 0` for an option value that should be a number index (used for `getSource(fromTransformResult || 0)`).
// Coerces Int/Double/NSNumber/number-like-String to Double; nil / non-truthy (0/NaN) -> 0.
private func optNumberOrZero(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return (d != 0 && !d.isNaN) ? d : 0
    case let i as Int: return i != 0 ? Double(i) : 0
    case let n as NSNumber: let d = n.doubleValue; return (d != 0 && !d.isNaN) ? d : 0
    case let s as String:
        if let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)), d != 0, !d.isNaN { return d }
        return 0
    default: return 0
    }
}

// JS `'' + value` for an arbitrary option value (used only in a dev error message).
private func jsAnyString(_ v: Any?) -> String {
    guard let v = v, !(v is NSNull) else { return "" }
    if let d = v as? Double { return jsNumberStr(d) }
    if let i = v as? Int { return String(i) }
    if let s = v as? String { return s }
    return "\(v)"
}

// JS `Number.prototype.toString` for a Double (integral values print without a fraction).
// (Local shim; mirrors the one in data/Source.swift. Used by `_getVersionSign`.)
private func jsNumberStr(_ x: Double) -> String {   // PORT-NOTE: JS number-to-string shim
    if x == x.rounded() && Swift.abs(x) < 1e15 {
        return String(Int(x))
    }
    return String(x)
}

// JS truthiness for an arbitrary value (used for `!!sourceHeader !== !!upMetaRawOption.sourceHeader`).
// (Local shim; mirrors the one in data/Source.swift.)
private func jsTruthy(_ v: Any?) -> Bool {   // PORT-NOTE: JS truthiness shim
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
