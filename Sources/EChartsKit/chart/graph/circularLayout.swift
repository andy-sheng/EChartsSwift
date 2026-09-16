// Ported from echarts/src/chart/graph/circularLayout.ts — keep in sync with upstream
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
//   import {circularLayout} from './circularLayoutHelper';           -> sibling (circularLayoutHelper.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import GraphSeriesModel, { SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> GraphSeriesModel / SERIES_TYPE_GRAPH (chart/graph/GraphSeries.swift).
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// upstream:
//   export const graphCircularLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, graphCircularLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; upstream `graphCircularLayout` is `(ecModel)` (1-arg). Adapt with a thin wrapper
// that drops the (unused) api + payload, keeping `graphCircularLayout` byte-faithful (1-arg) below.
public let graphCircularLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, _, _ in graphCircularLayout(ecModel) }
)

// The third graph layout — iterative physics (`layout: 'force'`) — is ported in the siblings
// `forceLayout.swift` (+ `forceHelper.swift`): `graphForceLayoutStageHandler`. It settles the
// simulation synchronously for the static render (the live per-frame tick is a note there).

// Exposed for the driver to call directly, matching upstream's module-private
// `function graphCircularLayout(ecModel)`.
func graphCircularLayout(_ ecModel: GlobalModel) {
    ecModel.eachSeriesByType("graph") { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: GraphSeriesModel`.
        let seriesModel = seriesModelBase as! GraphSeriesModel
        if (seriesModel.get("layout") as? String) == "circular" {
            circularLayout(seriesModel, "symbolSize")
        }
    }
}
