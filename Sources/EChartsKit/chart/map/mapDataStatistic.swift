// Ported from echarts/src/chart/map/mapDataStatistic.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` (ZRenderKit).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData (data/SeriesData.swift).
//   import { buildAllMapSeriesGroups, getMainMapSeries, MapValueCalculationType, SERIES_TYPE_MAP }
//       from './MapSeries';                                        -> sibling MapSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import { createSimpleOverallStageHandler } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` (util/modelUtil.swift).

// FIXME 公用？
// upstream: function dataStatistics(datas: SeriesData[], statisticType: MapValueCalculationType): SeriesData
func dataStatistics(_ datas: [SeriesData], _ statisticType: MapValueCalculationType?) -> SeriesData {
    // const dataNameMap = {} as {[mapKey: string]: number[]};
    var dataNameMap: [String: [Double]] = [:]

    // zrUtil.each(datas, function (data) {
    //     data.each(data.mapDimension('value'), function (value: number, idx) { ... });
    // });
    util.each(datas) { data, _ in
        data.each(data.mapDimension("value") ?? "value") { args in
            // (value, idx): store.each yields [value, idx] for a single dim.
            let value = args.count > 0 ? args[0] : nil
            let idx = Int((args.count > 1 ? args[1] as? Double : nil) ?? 0)
            // Add prefix to avoid conflict with Object.prototype.
            // const mapKey = 'ec-' + data.getName(idx);
            let mapKey = "ec-" + data.getName(idx)
            // dataNameMap[mapKey] = dataNameMap[mapKey] || [];
            if dataNameMap[mapKey] == nil {
                dataNameMap[mapKey] = []
            }
            // if (!isNaN(value)) { dataNameMap[mapKey].push(value); }
            if let v = value as? Double, !v.isNaN {
                dataNameMap[mapKey]!.append(v)
            }
        }
    }

    // return datas[0].map(datas[0].mapDimension('value'), function (value, idx) { ... });
    return datas[0].map(datas[0].mapDimension("value") ?? "value") { args in
        // (value, idx)
        let idx = Int((args.count > 1 ? args[1] as? Double : nil) ?? 0)
        // const mapKey = 'ec-' + datas[0].getName(idx);
        let mapKey = "ec-" + datas[0].getName(idx)
        // let sum = 0; let min = Infinity; let max = -Infinity;
        var sum: Double = 0
        var minV: Double = .infinity
        var maxV: Double = -.infinity
        // const len = dataNameMap[mapKey].length;
        let arr = dataNameMap[mapKey] ?? []
        let len = arr.count
        // for (let i = 0; i < len; i++) { min = Math.min(...); max = Math.max(...); sum += ...; }
        for i in 0..<len {
            minV = Swift.min(minV, arr[i])
            maxV = Swift.max(maxV, arr[i])
            sum += arr[i]
        }
        // let result;
        let result: Double
        // if (statisticType === 'min') { result = min; }
        if statisticType == "min" {
            result = minV
        }
        // else if (statisticType === 'max') { result = max; }
        else if statisticType == "max" {
            result = maxV
        }
        // else if (statisticType === 'average') { result = sum / len; }
        else if statisticType == "average" {
            result = sum / Double(len)
        }
        // else { result = sum; }
        else {
            result = sum
        }
        // return len === 0 ? NaN : result;
        return (len == 0 ? Double.nan : result) as ParsedValue
    }
}

// export const mapDataStatisticStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_MAP, mapDataStatistic);
//   The overall-reset handler shape is `(GlobalModel, ExtensionAPI, Payload?) -> Void`; the upstream
//   `mapDataStatistic(ecModel)` reads only `ecModel`, so `api`/`payload` are ignored in the wrapper.
public let mapDataStatisticStageHandler: StageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_MAP,
    { (ecModel: GlobalModel, _: ExtensionAPI, _: Payload?) in
        mapDataStatistic(ecModel)
    }
)

// upstream: function mapDataStatistic(ecModel: GlobalModel): void
func mapDataStatistic(_ ecModel: GlobalModel) {
    // zrUtil.each(buildAllMapSeriesGroups(ecModel), function (seriesGroup) { ... });
    //   `util.each` (ZRenderKit) only iterates arrays; the object map is iterated with a Swift `for-in`
    //   (NOTE: Dictionary order is unspecified, but each group's work is independent, so it is irrelevant).
    for (_, seriesGroup) in buildAllMapSeriesGroups(ecModel) {
        // const mainSeries = getMainMapSeries(seriesGroup);
        let mainSeries = getMainMapSeries(seriesGroup)
        // if (!mainSeries) { return; }
        guard let mainSeries = mainSeries else {
            continue
        }
        // const data = dataStatistics(
        //     zrUtil.map(seriesGroup.f, function (seriesModel) { return seriesModel.getData(); }),
        //     mainSeries.get('mapValueCalculation')
        // );
        let data = dataStatistics(
            util.map(seriesGroup.f) { seriesModel, _ in seriesModel.getData() },
            // PENDING: long history of using `seriesGroup[0]` here (see upstream comment).
            mainSeries.get("mapValueCalculation") as? MapValueCalculationType
        )

        // zrUtil.each(seriesGroup.f, function (series) {
        //     series.seriesGroup = seriesGroup;
        //     series.originalData = series.getData();
        //     series.setData(data.cloneShallow());
        // });
        util.each(seriesGroup.f) { series, _ in
            series.seriesGroup = seriesGroup
            series.originalData = series.getData()
            series.setData(data.cloneShallow())
        }
    }
}
