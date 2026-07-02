// Ported from echarts/src/coord/axisStatisticsMetricsImpl.ts — keep in sync with upstream
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

// import { createHashMap } from 'zrender/src/core/util';  → HashMap/createHashMap (util/modelUtil shim)
// import type GlobalModel from '../model/Global';
// import type SeriesModel from '../model/Series';
// import { DimensionIndex } from '../util/types';
// import { asc, isNullableNumberFinite } from '../util/number';  → number.asc / number.isNullableNumberFinite
// import { parseSanitizationFilter, passesSanitizationFilter } from '../data/helper/dataValueHelper';
// import type DataStore from '../data/DataStore';
// import { tryEnsureTypedArray, Float64ArrayCtor } from '../util/vendor';  → vendor.*
// import {
//     AxisStatECPrepareCachePerKeyPerAxis, AxisStatPerKeyPerAxis, eachSeriesDealForAxisStat,
//     LINEAR_POSITIVE_MIN_GAP_NO_VALID_VALUE, LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE,
//     registerMetricImpl
// } from './axisStatistics';
// NOTE: `./axisStatistics` and `../util/vendor` land together with this file (same phase, other agents).
// This file references their conventional public API. `Axis`/`Scale` members (axis.scale, axis.dim,
// scale.needTransform/getFilter/transformIn) are Phase 6b — see PORT-TODOs below.


public func registerMetricImplLiPosMinGap() {
    // PORT-TODO: upstream first arg is `keyof AxisStatMetrics`; passed as String key here.
    registerMetricImpl("liPosMinGap", metricLiPosMinGapImpl)
}

private func metricLiPosMinGapImpl(
    _ ecModel: GlobalModel,
    _ perKeyPerAxis: AxisStatPerKeyPerAxis,
    _ ecPreparePerKeyPerAxis: AxisStatECPrepareCachePerKeyPerAxis
) {
    let newSerUids: HashMap<Double> = createHashMap()
    let ecPrepareSerUids = ecPreparePerKeyPerAxis.serUids
    let ecPrepareLiPosMinGap = ecPreparePerKeyPerAxis.liPosMinGap
    var ecPrepareCacheMiss = false   // upstream: `let ecPrepareCacheMiss: boolean;` (undefined ≡ falsy)

    let axis = perKeyPerAxis.axis
    let scale = axis.scale
    // const linearValueExtent = initExtentForUnion();
    let needTransform = scale.needTransform()
    // PORT-TODO: upstream `scale.getFilter ? scale.getFilter() : null` — Scale.getFilter is Phase 6b.
    let filter: DataSanitizationFilter? = scale.getFilter?()
    let filterParsed = dataValueHelper.parseSanitizationFilter(filter)

    // const timeRetrieve: number[] = []; // _EC_PERF_
    // const timeSort: number[] = []; // _EC_PERF_
    // const timeAll: number[] = []; // _EC_PERF_
    // timeAll[0] = Date.now(); // _EC_PERF_

    func eachSeries(
        _ cb: (_ dimStoreIdx: DimensionIndex, _ seriesModel: SeriesModel, _ rawDataStore: DataStore) -> Void
    ) {
        eachSeriesDealForAxisStat(ecModel, perKeyPerAxis.sers) { seriesModel in
            let rawData = seriesModel.getRawData()
            // NOTE: Currently there is no series that a "base axis" can map to multiple dimensions.
            let dimStoreIdx = rawData.getDimensionIndex(rawData.mapDimension(axis.dim) as Any)
            if dimStoreIdx >= 0 {
                cb(dimStoreIdx, seriesModel, rawData.getStore())
            }
        }
    }

    var bufferCapacity: Double = 0
    eachSeries { dimStoreIdx, seriesModel, rawDataStore in
        newSerUids.set(seriesModel.uid, 1)
        if ecPrepareSerUids == nil || !ecPrepareSerUids!.hasKey(seriesModel.uid) {
            ecPrepareCacheMiss = true
        }
        bufferCapacity += Double(rawDataStore.count())
    }

    if ecPrepareSerUids == nil || ecPrepareSerUids!.keys().count != newSerUids.keys().count {
        ecPrepareCacheMiss = true
    }
    if !ecPrepareCacheMiss && ecPrepareLiPosMinGap != nil {
        // Consider the fact in practice:
        //  - Series data can only be changed in EC_PREPARE.
        //  - The relationship between series and axes can only be changed in EC_PREPARE and
        //    SERIES_FILTER.
        //  (See EC_CYCLE for more info)
        // Therefore, some statistics results can be cached in `GlobalModelCachePerECPrepare` to avoid
        // repeated time-consuming calculation for large data (e.g., over 1e5 data items).
        perKeyPerAxis.liPosMinGap = ecPrepareLiPosMinGap
        return
    }

    _ = vendor.tryEnsureTypedArray(tmpValueBuffer, bufferCapacity)

    // timeRetrieve[0] = Date.now(); // _EC_PERF_
    var writeIdx = 0
    eachSeries { dimStoreIdx, seriesModel, store in
        // NOTE: It appears to be optimized by traveling only in a specific window (e.g., the current window)
        // instead of the entire data, but that would likely generate inconsistent result and bring
        // jitter when dataZoom roaming.
        var i = 0
        let cnt = store.count()
        while i < cnt {
            // Manually inline some code for performance, since no other optimization
            // (such as, progressive) can be applied here.
            // PORT-TODO: ParsedValue is `Any`; upstream casts `store.get(...) as number`.
            var val = store.get(dimStoreIdx, i) as? Double ?? Double.nan
            // NOTE: in most cases, filter does not exist.
            if val.isFinite
                && (filter == nil || dataValueHelper.passesSanitizationFilter(filterParsed, val))
            {
                if needTransform {
                    // PENDING: time-consuming if axis break is applied.
                    val = scale.transformIn(val, nil)
                }
                tmpValueBuffer.arr[writeIdx] = val
                writeIdx += 1
                // val < linearValueExtent[0] && (linearValueExtent[0] = val);
                // val > linearValueExtent[1] && (linearValueExtent[1] = val);
            }
            i += 1
        }
    }
    // Indicatively, retrieving values above costs 40ms for 1e6 values in a certain platform.
    // timeRetrieve[1] = Date.now(); // _EC_PERF_

    // PORT-TODO: upstream slices a shared subarray view `(arr as Float64Array).subarray(0, writeIdx)`
    // (typed branch) / truncates `arr.length = writeIdx` (number[] branch). Swift value semantics: we
    // copy the `[0, writeIdx)` window into `tmpValueBufferView`; the sort below then reads from it.
    var tmpValueBufferView: ContiguousArray<Double> = tmpValueBuffer.typed
        ? ContiguousArray(tmpValueBuffer.arr[0..<writeIdx])
        : ContiguousArray(tmpValueBuffer.arr[0..<writeIdx])

    // timeSort[0] = Date.now(); // _EC_PERF_
    // Sort axis values into ascending order to calculate gaps.
    if tmpValueBuffer.typed {
        // Indicatively, 5ms for 1e6 values in a certain platform.
        tmpValueBufferView.sort()
    }
    else {
        tmpValueBufferView = ContiguousArray(number.asc(Array(tmpValueBufferView)))
    }
    // timeAll[1] = timeSort[1] = Date.now(); // _EC_PERF_

    // console.log('axisStatistics_minGap_retrieve', timeRetrieve[1] - timeRetrieve[0]); // _EC_PERF_
    // console.log('axisStatistics_minGap_sort', timeSort[1] - timeSort[0]); // _EC_PERF_
    // console.log('axisStatistics_minGap_all', timeAll[1] - timeAll[0]); // _EC_PERF_

    var min = Double.infinity
    var j = 1
    while j < writeIdx {
        let delta = tmpValueBufferView[j] - tmpValueBufferView[j - 1]
        if  // - Different series normally have the same values (e.g., barA, barB, barC),
            //   which should be ignored.
            // - A single series with multiple same values is often not meaningful to
            //   create `bandWidth`, so it is also ignored.
            delta > 0
            && delta < min
        {
            min = delta
        }
        j += 1
    }

    let liPosMinGap: Double = number.isNullableNumberFinite(min) ? min
        : writeIdx > 0 ? LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE
        : LINEAR_POSITIVE_MIN_GAP_NO_VALID_VALUE
    perKeyPerAxis.liPosMinGap = liPosMinGap
    ecPreparePerKeyPerAxis.liPosMinGap = liPosMinGap
    ecPreparePerKeyPerAxis.serUids = newSerUids
}

// For performance optimization.
private let tmpValueBuffer = vendor.tryEnsureTypedArray(
    CompatibleTypedArray(ctor: vendor.Float64ArrayCtor),
    50 // An arbitrary initial capability.
)
