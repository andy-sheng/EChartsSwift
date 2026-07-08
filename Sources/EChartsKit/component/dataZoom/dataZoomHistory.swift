// Ported from echarts/src/component/dataZoom/history.ts — keep in sync with upstream
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

// upstream imports (mapped to this port):
//   import * as zrUtil from 'zrender/src/core/util';       -> not needed (plain Swift loops)
//   import GlobalModel from '../../model/Global';           -> `GlobalModel`
//   import { Dictionary } from '../../util/types';          -> `[String: ...]`
//   import DataZoomModel from './DataZoomModel';            -> `DataZoomModel`
//   import { makeInner } from '../../util/model';           -> `model.makeInner`
//   import { DataZoomPayloadBatchItem } from './helper';    -> the dynamic batch-item bag below

// export type DataZoomStoreSnapshot = Dictionary<DataZoomPayloadBatchItem>;
//   `DataZoomPayloadBatchItem` = { dataZoomId; start?; end?; startValue?; endValue? } — the port keeps
//   it a dynamic `[String: Any]` bag (the `dataZoom` action reads start/end/startValue/endValue off it).
public typealias DataZoomStoreSnapshot = [String: [String: Any]]

// type Store = { snapshots: DataZoomStoreSnapshot[] };
final class DataZoomHistoryStore {
    var snapshots: [DataZoomStoreSnapshot]? = nil
}

// const inner = makeInner<Store, GlobalModel>();
let dataZoomHistoryInner: (GlobalModel) -> DataZoomHistoryStore = model.makeInner { DataZoomHistoryStore() }

/// push(ecModel, newSnapshot) — key is dataZoomId.
public func dataZoomHistoryPush(_ ecModel: GlobalModel, _ newSnapshot: DataZoomStoreSnapshot) {
    let store = dataZoomHistoryInner(ecModel)
    var storedSnapshots = dataZoomGetStoreSnapshots(store)

    // If a previous dataZoom range can not be found, complete snapshots[0] (the "origin") from the
    //   current range so `back` can restore to it.
    for (dataZoomId, _) in newSnapshot {
        var i = storedSnapshots.count - 1
        while i >= 0 {
            if storedSnapshots[i][dataZoomId] != nil { break }
            i -= 1
        }
        if i < 0 {
            // upstream: `ecModel.queryComponents({mainType:'dataZoom', subType:'select', id})[0]`.
            // DEVIATION: the port has no toolbox-internal 'select' dataZoom creator (the box-select
            //   drives whatever cartesian dataZoom the user configured), so match ANY dataZoom by id.
            var dataZoomModel: DataZoomModel?
            ecModel.eachComponent("dataZoom") { modelItem, _ in
                if dataZoomModel == nil, let dz = modelItem as? DataZoomModel, dz.id == dataZoomId {
                    dataZoomModel = dz
                }
            }
            if let dz = dataZoomModel, let percentRange = dz.getPercentRange(), percentRange.count == 2 {
                storedSnapshots[0][dataZoomId] = [
                    "dataZoomId": dataZoomId,
                    "start": percentRange[0],
                    "end": percentRange[1]
                ]
            }
        }
    }

    storedSnapshots.append(newSnapshot)
    store.snapshots = storedSnapshots
}

/// pop(ecModel) — pop the top snapshot and return, for each dataZoom in the popped head, the next
///   remaining top entry (i.e. the range to restore to).
public func dataZoomHistoryPop(_ ecModel: GlobalModel) -> DataZoomStoreSnapshot {
    let store = dataZoomHistoryInner(ecModel)
    var storedSnapshots = dataZoomGetStoreSnapshots(store)
    let head = storedSnapshots[storedSnapshots.count - 1]
    if storedSnapshots.count > 1 { storedSnapshots.removeLast() }

    // Find top for all dataZoom.
    var snapshot: DataZoomStoreSnapshot = [:]
    for (dataZoomId, _) in head {
        var i = storedSnapshots.count - 1
        while i >= 0 {
            if let batchItem = storedSnapshots[i][dataZoomId] {
                snapshot[dataZoomId] = batchItem
                break
            }
            i -= 1
        }
    }

    store.snapshots = storedSnapshots
    return snapshot
}

/// clear(ecModel) — inner(ecModel).snapshots = null.
public func dataZoomHistoryClear(_ ecModel: GlobalModel) {
    dataZoomHistoryInner(ecModel).snapshots = nil
}

/// count(ecModel) — getStoreSnapshots(ecModel).length.
public func dataZoomHistoryCount(_ ecModel: GlobalModel) -> Int {
    let store = dataZoomHistoryInner(ecModel)
    let snapshots = dataZoomGetStoreSnapshots(store)
    store.snapshots = snapshots
    return snapshots.count
}

/// getStoreSnapshots — this._history[0] is used to store the origin range.
private func dataZoomGetStoreSnapshots(_ store: DataZoomHistoryStore) -> [DataZoomStoreSnapshot] {
    if store.snapshots == nil {
        store.snapshots = [[:]]
    }
    return store.snapshots!
}
