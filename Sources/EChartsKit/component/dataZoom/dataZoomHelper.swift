// Ported from echarts/src/component/dataZoom/helper.ts — keep in sync with upstream
// (basename `dataZoomHelper.swift` to avoid a SwiftPM duplicate-basename collision with other `helper.swift`s.)
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

// upstream imports:
//   import { NullUndefined, Payload } from '../../util/types';        -> Optional / `Payload` (util/types.swift)
//   import GlobalModel from '../../model/Global';                     -> `GlobalModel` (model/Global.swift)
//   import DataZoomModel from './DataZoomModel';                      -> `DataZoomModel` (TASK 1, sibling; integrator reconciles)
//   import { indexOf, createHashMap, assert, HashMap } from 'zrender/src/core/util';
//       -> `util.*` (ZRenderKit); `HashMap`/`createHashMap` (util/modelUtil.swift shim)
//   import SeriesModel from '../../model/Series';                     -> `SeriesModel` (model/Series.swift)
//   import { CoordinateSystemHostModel } from '../../coord/CoordinateSystem';
//       -> PORT-NOTE: `CoordinateSystemHostModel` is ported (coord/CoordinateSystem.swift); modeled here as its `ComponentModel` supertype.
//   import { AxisBaseModel } from '../../coord/AxisBaseModel';        -> `AxisBaseModel` (coord/AxisBaseModel.swift)
//   import type AxisProxy from './AxisProxy';                         -> `AxisProxy` (sibling AxisProxy.swift)
//   import { makeInner } from '../../util/model';                     -> `model.makeInner` (util/modelUtil.swift)
//   import type ComponentModel from '../../model/Component';          -> `ComponentModel` (model/Component.swift)
//   import { getCachePerECPrepare, GlobalModelCachePerECPrepare } from '../../util/cycleCache';
//       -> `getCachePerECPrepare` / `GlobalModelCachePerECPrepare` (coord/axisStatistics.swift stubs)


// upstream: interface DataZoomPayloadBatchItem
public struct DataZoomPayloadBatchItem {
    public var dataZoomId: String
    public var start: Double?
    public var end: Double?
    public var startValue: Double?
    public var endValue: Double?
    public init(
        dataZoomId: String,
        start: Double? = nil,
        end: Double? = nil,
        startValue: Double? = nil,
        endValue: Double? = nil
    ) {
        self.dataZoomId = dataZoomId
        self.start = start
        self.end = end
        self.startValue = startValue
        self.endValue = endValue
    }
}

// upstream: interface DataZoomReferCoordSysInfo { model; axisModels }
//   Upstream pushes ONE object simultaneously into `infoList` and `infoMap` and then mutates
//   `.axisModels` on it — the list entry and the map entry are the SAME reference. A Swift value
//   struct would break that aliasing (value-type write-back trap), so this is a `final class`.
public final class DataZoomReferCoordSysInfo {
    // upstream: model: CoordinateSystemHostModel  -> PORT-NOTE: modeled as its `ComponentModel` supertype.
    public var model: ComponentModel
    // Notice: if two dataZooms refer the same coordinate system model,
    // (1) The axis they referred may different
    // (2) The sequence the axisModels matters, may different in different dataZooms.
    public var axisModels: [AxisBaseModel]
    public init(model: ComponentModel, axisModels: [AxisBaseModel]) {
        self.model = model
        self.axisModels = axisModels
    }
}

// upstream: export const DATA_ZOOM_AXIS_DIMENSIONS = ['x', 'y', 'radius', 'angle', 'single'] as const;
public let DATA_ZOOM_AXIS_DIMENSIONS: [String] = ["x", "y", "radius", "angle", "single"]

// upstream: type DataZoomAxisDimension = 'x' | 'y' | 'radius' | 'angle' | 'single'
public typealias DataZoomAxisDimension = String
// upstream: type DataZoomAxisMainType = 'xAxis' | ... | 'singleAxis'
public typealias DataZoomAxisMainType = String
// upstream: type DataZoomAxisIndexPropName = 'xAxisIndex' | ...
public typealias DataZoomAxisIndexPropName = String
// upstream: type DataZoomAxisIdPropName = 'xAxisId' | ...
public typealias DataZoomAxisIdPropName = String
// upstream: export type DataZoomCoordSysMainType = 'polar' | 'grid' | 'singleAxis'
public typealias DataZoomCoordSysMainType = String

// upstream: type AxisProxyMap = HashMap<AxisProxy, ComponentModel['uid']>;  (keyed by axisModel.uid : String)
private typealias AxisProxyMap = HashMap<AxisProxy>

// upstream: const ecModelCacheInner = makeInner<{ axisProxyMap: AxisProxyMap; }, GlobalModelCachePerECPrepare>();
//   `makeInner` requires the record `T` to be a class (object-identity keyed WeakMap).
final class DataZoomAxisProxyCacheStore {
    fileprivate var axisProxyMap: AxisProxyMap?
    init() {}
}
private let ecModelCacheInner: (GlobalModelCachePerECPrepare) -> DataZoomAxisProxyCacheStore
    = model.makeInner { DataZoomAxisProxyCacheStore() }

// Supported coords.
// FIXME: polar has been broken (but rarely used).
// upstream: const SERIES_COORDS = ['cartesian2d', 'polar', 'singleAxis'] as const;
private let SERIES_COORDS: [String] = ["cartesian2d", "polar", "singleAxis"]

public func isCoordSupported(_ seriesModel: SeriesModel) -> Bool {
    let coordType = seriesModel.get("coordinateSystem", false)
    // indexOf(SERIES_COORDS, coordType) >= 0
    if let coordType = coordType as? String {
        return util.indexOf(SERIES_COORDS, coordType) >= 0
    }
    return false
}

public func getAxisMainType(_ axisDim: DataZoomAxisDimension) -> DataZoomAxisMainType {
    if __DEV__ {
        util.assert(!axisDim.isEmpty)
    }
    return axisDim + "Axis"
}

public func getAxisIndexPropName(_ axisDim: DataZoomAxisDimension) -> DataZoomAxisIndexPropName {
    if __DEV__ {
        util.assert(!axisDim.isEmpty)
    }
    return axisDim + "AxisIndex"
}

public func getAxisIdPropName(_ axisDim: DataZoomAxisDimension) -> DataZoomAxisIdPropName {
    if __DEV__ {
        util.assert(!axisDim.isEmpty)
    }
    return axisDim + "AxisId"
}

/**
 * If two dataZoomModels has the same axis controlled, we say that they are 'linked'.
 * This function finds all linked dataZoomModels start from the given payload.
 */
public func findEffectedDataZooms(_ ecModel: GlobalModel, _ payload: Payload) -> [DataZoomModel] {

    // Key: `DataZoomAxisDimension`
    let axisRecords: HashMap<[Bool]> = createHashMap()
    var effectedModels: [DataZoomModel] = []
    // Key: uid of dataZoomModel
    let effectedModelMap: HashMap<Bool> = createHashMap()

    func markAxisControlled(_ dataZoomModel: DataZoomModel) {
        dataZoomModel.eachTargetAxis { axisDim, axisIndex in
            // (axisRecords.get(axisDim) || axisRecords.set(axisDim, []))[axisIndex] = true;
            // Value-type write-back: read, grow, mutate, set.
            let idx = Int(axisIndex)
            var arr = axisRecords.get(axisDim) ?? []
            while arr.count <= idx { arr.append(false) }
            arr[idx] = true
            axisRecords.set(axisDim, arr)
        }
    }

    func addToEffected(_ dataZoom: DataZoomModel) {
        effectedModelMap.set(dataZoom.uid, true)
        effectedModels.append(dataZoom)
        markAxisControlled(dataZoom)
    }

    func isLinked(_ dataZoomModel: DataZoomModel) -> Bool {
        var isLink = false
        dataZoomModel.eachTargetAxis { axisDim, axisIndex in
            let idx = Int(axisIndex)
            let axisIdxArr = axisRecords.get(axisDim)
            if let axisIdxArr = axisIdxArr, idx < axisIdxArr.count, axisIdxArr[idx] {
                isLink = true
            }
        }
        return isLink
    }

    // Find the dataZooms specified by payload.
    ecModel.eachComponent(
        QueryConditionKindA(mainType: "dataZoom", query: payload.other)
    ) { modelItem, _ in
        let dataZoomModel = modelItem as! DataZoomModel
        if effectedModelMap.get(dataZoomModel.uid) != true {
            addToEffected(dataZoomModel)
        }
    }

    // Start from the given dataZoomModels, travel the graph to find
    // all of the linked dataZoom models.
    var foundNewLink = false
    func processSingle(_ dataZoomModel: DataZoomModel) {
        if effectedModelMap.get(dataZoomModel.uid) != true && isLinked(dataZoomModel) {
            addToEffected(dataZoomModel)
            foundNewLink = true
        }
    }

    repeat {
        foundNewLink = false
        ecModel.eachComponent("dataZoom") { modelItem, _ in
            processSingle(modelItem as! DataZoomModel)
        }
    } while foundNewLink

    return effectedModels
}

// upstream: collectReferCoordSysModelInfo returns { infoList; infoMap }
public struct DataZoomReferCoordSysInfoWrap {
    public var infoList: [DataZoomReferCoordSysInfo]
    // Key: coordSysModel.uid
    public var infoMap: HashMap<DataZoomReferCoordSysInfo>
    public init(infoList: [DataZoomReferCoordSysInfo], infoMap: HashMap<DataZoomReferCoordSysInfo>) {
        self.infoList = infoList
        self.infoMap = infoMap
    }
}

/**
 * Find the first target coordinate system.
 * Available after model built.
 * (See upstream doc block for the returned shape.)
 */
public func collectReferCoordSysModelInfo(_ dataZoomModel: DataZoomModel) -> DataZoomReferCoordSysInfoWrap {
    let ecModel = dataZoomModel.ecModel!
    var coordSysInfoWrap = DataZoomReferCoordSysInfoWrap(
        infoList: [],
        infoMap: createHashMap()
    )

    dataZoomModel.eachTargetAxis { axisDim, axisIndex in
        let axisModel = ecModel.getComponent(getAxisMainType(axisDim), Double(axisIndex)) as? AxisBaseModel
        guard let axisModel = axisModel else {
            return
        }
        // getCoordSysModel() -> Any? (upstream CoordinateSystemHostModel, ported); narrow to ComponentModel.
        guard let coordSysModel = axisModel.getCoordSysModel() as? ComponentModel else {
            return
        }

        let coordSysUid = coordSysModel.uid
        var coordSysInfo = coordSysInfoWrap.infoMap.get(coordSysUid)
        if coordSysInfo == nil {
            let created = DataZoomReferCoordSysInfo(model: coordSysModel, axisModels: [])
            coordSysInfoWrap.infoList.append(created)
            coordSysInfoWrap.infoMap.set(coordSysUid, created)
            coordSysInfo = created
        }
        // `coordSysInfo` is a reference (class) shared with the list entry — mutation is visible in both.
        coordSysInfo!.axisModels.append(axisModel)
    }

    return coordSysInfoWrap
}

// upstream: ensureAxisProxyMap(ecModel): AxisProxyMap
private func ensureAxisProxyMap(_ ecModel: GlobalModel) -> AxisProxyMap {
    // Consider some axes may be deleted, and dataZoom options may be changed at and only at each run of
    // "ec prepare", we save axis proxies to a cache that is auto-cleared for each run of "ec prepare".
    let store = ecModelCacheInner(getCachePerECPrepare(ecModel))
    if store.axisProxyMap == nil {
        store.axisProxyMap = createHashMap()
    }
    return store.axisProxyMap!
}

public func getAxisProxyFromModel(_ axisModel: AxisBaseModel?) -> AxisProxy? {
    guard let axisModel = axisModel else {
        return nil
    }
    if __DEV__ {
        util.assert(axisModel.ecModel != nil)
    }
    return ensureAxisProxyMap(axisModel.ecModel!).get(axisModel.uid)
}

public func setAxisProxyToModel(_ axisModel: AxisBaseModel, _ axisProxy: AxisProxy) {
    if __DEV__ {
        util.assert(axisModel.ecModel != nil)
    }
    ensureAxisProxyMap(axisModel.ecModel!).set(axisModel.uid, axisProxy)
}

/**
 * NOTICE: If `axis_a` aligns to `axis_b`, but they are not controlled by
 * the same `dataZoom`, do not consider `axis_b` as `alignTo` and
 * then do not input it into `AxisProxy#reset`.
 */
public func getAlignTo(_ dataZoomModel: DataZoomModel, _ axisProxy: AxisProxy) -> AxisProxy? {
    // upstream: const alignToAxis = axisProxy.getAxisModel().axis.__alignTo;
    let axis = axisProxy.getAxisModel().axis as! Axis
    guard let alignToAxis = axis.__alignTo else {
        return nil
    }
    // (alignToAxis && dataZoomModel.getAxisProxy(alignToAxis.dim, alignToAxis.model.componentIndex))
    //     ? getAxisProxyFromModel(alignToAxis.model) : null
    let referredProxy = dataZoomModel.getAxisProxy(
        alignToAxis.dim as DataZoomAxisDimension,
        alignToAxis.model.componentIndex
    )
    if referredProxy != nil {
        return getAxisProxyFromModel(alignToAxis.model)
    }
    return nil
}
