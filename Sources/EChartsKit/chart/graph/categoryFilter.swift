// Ported from echarts/src/chart/graph/categoryFilter.ts — keep in sync with upstream
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
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import GraphSeriesModel, { GraphNodeItemOption, SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> sibling GraphSeries.swift (ported): `GraphSeriesModel` / `SERIES_TYPE_GRAPH`.
//          `GraphNodeItemOption` is a type-only generic — dropped.
//   import type LegendModel from '../../component/legend/LegendModel'; -> LegendModel (component/legend/LegendModel.swift).
//   import { isNumber } from 'zrender/src/core/util';                -> `util.isNumber`.
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// upstream:
//   export const graphCategoryFilterStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, categoryFilter);
// `categoryFilter` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
public let graphCategoryFilterStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, _, _ in categoryFilter(ecModel) }
)

func categoryFilter(_ ecModel: GlobalModel) {
    let legendModels = ecModel.findComponents(QueryConditionKindA(
        mainType: "legend"
    )) as? [LegendModel] ?? []
    // if (!legendModels || !legendModels.length) { return; }
    if legendModels.isEmpty {
        return
    }
    ecModel.eachSeriesByType(SERIES_TYPE_GRAPH) { seriesModelBase, _ in
        let graphSeries = seriesModelBase as! GraphSeriesModel
        let categoriesData = graphSeries.getCategoriesData()
        let graph = graphSeries.getGraph()
        // `graph.data` is `SeriesData!` (IUO); annotate the type so `let` does not infer `SeriesData?`.
        let data: SeriesData = graph.data

        // const categoryNames = categoriesData.mapArray(categoriesData.getName);
        //   `mapArray` passes `[ParsedValue]` (last element = data index); wrap to call `getName(idx)`.
        let categoryNames = categoriesData.mapArray { args in
            categoriesData.getName(Int(args[0] as! Double))
        }

        data.filterSelf { args in
            let idx = Int(args[0] as! Double)
            let itemModel = data.getItemModel(idx)
            let categoryRaw = itemModel.getShallow("category")
            if let categoryRaw = categoryRaw {
                // let category: string. If a number, resolve to the category name.
                let category: String
                if util.isNumber(categoryRaw) {
                    category = (categoryNames[Int(toNumber(categoryRaw))] as? String) ?? ""
                }
                else {
                    category = categoryRaw as? String ?? ""
                }
                // If in any legend component the status is not selected.
                for i in 0..<legendModels.count {
                    if !legendModels[i].isSelected(category) {
                        return false
                    }
                }
            }
            return true
        }
    }
}

// upstream numeric coercion for the `category` index into `categoryNames`.
private func toNumber(_ value: Any?) -> Double {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}
