// Ported from echarts/src/chart/graph/simpleLayout.ts — keep in sync with upstream
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
//   import {each} from 'zrender/src/core/util';                      -> `util.each` (ZRenderKit).
//   import {simpleLayout, simpleLayoutEdge} from './simpleLayoutHelper';  -> siblings (simpleLayoutHelper.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import GraphSeriesModel, { SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> GraphSeriesModel / SERIES_TYPE_GRAPH (chart/graph/GraphSeries.swift).
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// upstream:
//   export const graphSimpleLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, graphSimpleLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; upstream `graphSimpleLayout` is `(ecModel, api)` (2-arg). Adapt with a thin wrapper
// that drops the (unused) payload, keeping `graphSimpleLayout` byte-faithful (2-arg) below.
public let graphSimpleLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, api, _ in graphSimpleLayout(ecModel, api) }
)

// Exposed for the driver to call directly (mirrors pie/funnel/sunburst layout handlers), matching
// upstream's module-private `function graphSimpleLayout(ecModel, api)`.
func graphSimpleLayout(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
    ecModel.eachSeriesByType(SERIES_TYPE_GRAPH) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: GraphSeriesModel`.
        let seriesModel = seriesModelBase as! GraphSeriesModel

        let layout = seriesModel.get("layout")
        let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
        if let coordSys = coordSys, coordSys.type != "view" {
            let data = seriesModel.getData()

            var dimensions: [String] = []
            util.each(coordSys.dimensions) { coordDim, _ in
                dimensions = dimensions + data.mapDimensionsAll(coordDim)
            }

            var dataIndex = 0
            while dataIndex < data.count() {
                var value: [Double] = []
                var hasValue = false
                for i in 0..<dimensions.count {
                    let val = asNumber(data.get(dimensions[i], dataIndex))
                    if !val.isNaN {
                        hasValue = true
                    }
                    value.append(val)
                }
                if hasValue {
                    data.setItemLayout(dataIndex, coordSys.dataToPoint(value, nil))
                }
                else {
                    // Also {Array.<number>}, not undefined to avoid if...else... statement
                    data.setItemLayout(dataIndex, [Double.nan, Double.nan])
                }
                dataIndex += 1
            }

            // upstream: simpleLayoutEdge(data.graph, seriesModel);
            // `SeriesData.graph` is `AnyObject?` (Graph not ported yet); narrow to Graph.
            simpleLayoutEdge(data.graph!, seriesModel)
        }
        // else if (!layout || layout === 'none') { simpleLayout(seriesModel); }
        // `!layout`: JS-falsy — undefined/null/'' all fall through to simpleLayout.
        else {
            let layoutStr = layout as? String
            if layoutStr == nil || layoutStr!.isEmpty || layoutStr == "none" {
                simpleLayout(seriesModel)
            }
        }
    }
}

// `data.get(...)` returns a dynamic ParsedValue?; coerce to Double (NaN when non-numeric),
// mirroring the upstream `as number` cast + `isNaN(val)` test.
private func asNumber(_ v: Any?) -> Double {
    guard let v else { return Double.nan }
    let mirror = Mirror(reflecting: v)
    if mirror.displayStyle == .optional {
        return asNumber(mirror.children.first?.value)
    }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String {
        // A time dimension is normally stored as its parsed millisecond value upstream. Some original
        // graph-node arrays still expose the raw date string through SeriesData in the Swift port;
        // normalize it here before handing the homogeneous coordinate vector to Calendar.dataToPoint.
        let timestamp = number.parseDate(s).timeIntervalSince1970 * 1000
        return timestamp.isNaN ? (Double(s) ?? Double.nan) : timestamp
    }
    return Double.nan
}
