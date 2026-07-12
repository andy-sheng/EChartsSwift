// Ported from echarts/src/chart/radar/radarLayout.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                     -> `util.*` (ZRenderKit).
//   import GlobalModel from '../../model/Global';                        -> GlobalModel (model/Global.swift).
//   import RadarSeriesModel, { SERIES_TYPE_RADAR } from './RadarSeries'; -> RadarSeriesModel / `SERIES_TYPE_RADAR`
//       (sibling chart/radar/RadarSeries.swift).
//   import Radar from '../../coord/radar/Radar';                         -> Radar (coord/radar/Radar.swift — the
//       radar coordinate system; see integration notes).
//   import { createSimpleOverallStageHandler } from '../../util/model';  -> `model.createSimpleOverallStageHandler`
//       (util/modelUtil.swift).

// type Point = number[];
typealias RadarLayoutPoint = [Double]

// upstream:
//   export const radarLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_RADAR, radarLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `radarLayout` is `(ecModel)` (1-arg). Adapt with a thin wrapper that
// drops the (unused) api + payload, keeping `radarLayout` byte-faithful (1-arg) below (mirrors pieLayout).
public let radarLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_RADAR,
    { ecModel, _, _ in radarLayout(ecModel) }
)

// upstream: function radarLayout(ecModel: GlobalModel)
//   Exposed for the driver to invoke directly (mirrors pieLayout), matching upstream's
//   module-private `function radarLayout(ecModel)`.
public func radarLayout(_ ecModel: GlobalModel) {
    ecModel.eachSeriesByType(SERIES_TYPE_RADAR) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: RadarSeriesModel`.
        let seriesModel = seriesModelBase as! RadarSeriesModel
        let data = seriesModel.getData()
        // const points: Point[][] = [];
        var points: [[RadarLayoutPoint]] = []
        // const coordSys = seriesModel.coordinateSystem;
        // if (!coordSys) { return; }
        guard let coordSys = seriesModel.radarCoordinateSystem else {
            return
        }

        // const axes = coordSys.getIndicatorAxes();
        let axes = coordSys.getIndicatorAxes()

        // zrUtil.each(axes, function (axis, axisIndex) { ... });
        util.each(axes) { axis, axisIndex in
            _ = axis
            // data.each(data.mapDimension(axes[axisIndex].dim), function (val, dataIndex) { ... });
            // PORT-NOTE: `mapDimension` is force-unwrapped — faithful to upstream's non-optional
            //   DimensionName return; the indicator dim is always present for a radar axis.
            data.each(data.mapDimension(axes[axisIndex].dim)!) { args in
                let val = args[0]
                let dataIndex = Int(args[1] as! Double)
                // points[dataIndex] = points[dataIndex] || [];
                while points.count <= dataIndex { points.append([]) }
                // const point = coordSys.dataToPoint(val, axisIndex);
                let point = coordSys.dataToPoint(val, Double(axisIndex))
                // points[dataIndex][axisIndex] = isValidPoint(point) ? point : getValueMissingPoint(coordSys);
                while points[dataIndex].count <= axisIndex { points[dataIndex].append([]) }
                points[dataIndex][axisIndex] = isValidPoint(point)
                    ? point : getValueMissingPoint(coordSys)
            }
        }

        // Close polygon
        // data.each(function (idx) { ... });
        data.each { args in
            let idx = Int(args[0] as! Double)
            // TODO
            // Is it appropriate to connect to the next data when some data is missing?
            // Or, should trade it like `connectNull` in line chart?
            // const firstPoint = zrUtil.find(points[idx], function (point) {
            //     return isValidPoint(point);
            // }) || getValueMissingPoint(coordSys);
            let firstPoint = util.find(points[idx]) { point, _ in
                return isValidPoint(point)
            } ?? getValueMissingPoint(coordSys)

            // Copy the first actual point to the end of the array
            // points[idx].push(firstPoint.slice());
            points[idx].append(firstPoint)   // firstPoint.slice() — value-type copy of the array
            // data.setItemLayout(idx, points[idx]);
            data.setItemLayout(idx, points[idx])
        }
    }
}

// upstream: function isValidPoint(point: Point) { return !isNaN(point[0]) && !isNaN(point[1]); }
private func isValidPoint(_ point: RadarLayoutPoint) -> Bool {
    return !point[0].isNaN && !point[1].isNaN
}

// upstream: function getValueMissingPoint(coordSys: Radar): Point { return [coordSys.cx, coordSys.cy]; }
private func getValueMissingPoint(_ coordSys: Radar) -> RadarLayoutPoint {
    // It is error-prone to input [NaN, NaN] into polygon, polygon.
    // (probably cause problem when refreshing or animating)
    return [coordSys.cx, coordSys.cy]
}
