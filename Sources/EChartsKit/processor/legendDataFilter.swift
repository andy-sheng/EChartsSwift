// Ported from echarts/src/processor/dataFilter.ts — keep in sync with upstream.
//
// (File basename is `legendDataFilter` — distinct from the marker-helper `dataFilter`, the series-level
//  `legendFilter`, and `negativeDataFilter` — to keep SwiftPM object basenames unique per module.)
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

// import { StageHandler } from '../util/types';
//
// The DATA-ITEM legend filter processor. Unlike component/legend/legendFilter.ts (which drops whole
// SERIES whose name is unselected), this per-series processor filters INDIVIDUAL DATA ITEMS whose NAME
// is unselected in any legend — the mechanism behind legend show/hide for pie/funnel/radar/themeRiver/
// chord, whose legend entries are the data-item names (slice/polygon names), not the series name.
// Registered upstream via `registerProcessor(dataFilter(SERIES_TYPE))` in each of those charts' install.ts.

// export default function dataFilter(seriesType: string): StageHandler {
public func legendDataFilter(_ seriesType: String) -> StageHandler {
    var handler = StageHandler()
    handler.seriesType = seriesType
    handler.reset = { seriesModel, ecModel, _, _ in
        // const legendModels = ecModel.findComponents({ mainType: 'legend' });
        let legendModels = ecModel.findComponents(QueryConditionKindA(mainType: "legend"))
        // if (!legendModels || !legendModels.length) { return; }
        if legendModels.isEmpty {
            return nil
        }
        // const data = seriesModel.getData();
        let data = seriesModel.getData()
        // data.filterSelf(function (idx) { const name = data.getName(idx); ... });
        //   The port's `FilterCb` receives an args array; with no dims the trailing (only) element is the
        //   dataIndex `i` (DataStore.filter: `cb([Double(i)])`).
        _ = data.filterSelf { args in
            let idx = Int(legendDataFilterIndexOf(args.last) ?? 0)
            let name = data.getName(idx)
            // If in any legend component the status is not selected.
            for lm in legendModels {
                if let legend = lm as? LegendModel, !legend.isSelected(name) {
                    return false
                }
            }
            return true
        }
        return nil
    }
    return handler
}

private func legendDataFilterIndexOf(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
