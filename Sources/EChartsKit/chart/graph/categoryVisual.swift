// Ported from echarts/src/chart/graph/categoryVisual.ts — keep in sync with upstream
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
//       -> PORT-TODO: sibling GraphSeries.swift NOT ported yet. `GraphSeriesModel` /
//          `SERIES_TYPE_GRAPH` are referenced as siblings (to be provided by the GraphSeries port,
//          exactly as sunburstVisual references SunburstSeries). `GraphNodeItemOption` is a
//          type-only generic for `getItemModel<T>()` / `getShallow<T>()` — dropped (untyped here).
//   import { Dictionary, ColorString } from '../../util/types';      -> util/types.swift (type-only).
//   import { extend, isString } from 'zrender/src/core/util';        -> `util.extend` / `util.isString`.
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// upstream:
//   export const graphCategoryVisualStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, categoryVisual);
// `categoryVisual` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
// Adapt with a thin wrapper that drops the extra args, keeping `categoryVisual` byte-faithful (1-arg)
// (same deviation as sunburstVisualStageHandler / treeVisualStageHandler).
public let graphCategoryVisualStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, _, _ in categoryVisual(ecModel) }
)

// PORT-TODO: upstream `paletteScope` is the object literal `{}` (`Dictionary<ColorString>`), used only
//   as a WeakMap identity key by getColorFromPalette (see model/mixin/palette.swift). Modeled as an
//   empty reference type so it can key the per-scope palette store (mirrors SunburstPaletteScope).
private final class GraphCategoryPaletteScope {}

func categoryVisual(_ ecModel: GlobalModel) {

    // const paletteScope: Dictionary<ColorString> = {};
    let paletteScope = GraphCategoryPaletteScope()

    ecModel.eachSeriesByType(SERIES_TYPE_GRAPH) { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! GraphSeriesModel
        let categoriesData = seriesModel.getCategoriesData()
        let data = seriesModel.getData()

        // const categoryNameIdxMap: Dictionary<number> = {};
        var categoryNameIdxMap: [String: Int] = [:]

        categoriesData.each { args in
            let idx = Int(args[0] as! Double)
            let name = categoriesData.getName(idx)
            // Add prefix to avoid conflict with Object.prototype.
            categoryNameIdxMap["ec-" + name] = idx
            let itemModel = categoriesData.getItemModel(idx)

            var style = itemModel.getModel("itemStyle").getItemStyle()
            if style["fill"] == nil {
                // Get color from palette.
                style["fill"] = seriesModel.getColorFromPalette(name, paletteScope)
            }
            categoriesData.setItemVisual(idx, "style", style)

            let symbolVisualList = ["symbol", "symbolSize", "symbolKeepAspect"]

            for i in 0..<symbolVisualList.count {
                let symbolVisual = itemModel.getShallow(symbolVisualList[i], true)
                if symbolVisual != nil {
                    categoriesData.setItemVisual(idx, symbolVisualList[i], symbolVisual)
                }
            }
        }

        // Assign category color to visual
        if categoriesData.count() != 0 {
            data.each { args in
                let idx = Int(args[0] as! Double)
                let itemModel = data.getItemModel(idx)
                // let categoryIdx = model.getShallow('category'); (may be a name string or a number)
                if let categoryIdxRaw = itemModel.getShallow("category") {
                    // Upstream reassigns `categoryIdx` in place (string name -> numeric index); split into
                    // raw + resolved here.
                    let categoryIdx: Int
                    if util.isString(categoryIdxRaw) {
                        categoryIdx = categoryNameIdxMap["ec-" + (categoryIdxRaw as! String)] ?? -1
                    }
                    else {
                        categoryIdx = Int(toNumber(categoryIdxRaw))
                    }

                    let categoryStyle = (categoriesData.getItemVisual(categoryIdx, "style") as? [String: Any]) ?? [:]
                    // const style = data.ensureUniqueItemVisual(idx, 'style'); extend(style, categoryStyle);
                    //   Upstream mutates the stored visual `style` object in place; the ported store returns
                    //   a value dict, so read → extend → write back (CONVENTIONS §3, mirrors sunburstVisual).
                    var style = (data.ensureUniqueItemVisual(idx, "style") as? [String: Any]) ?? [:]
                    _ = util.extend(&style, categoryStyle)
                    data.setItemVisual(idx, "style", style)

                    let visualList = ["symbol", "symbolSize", "symbolKeepAspect"]

                    for i in 0..<visualList.count {
                        data.setItemVisual(
                            idx, visualList[i],
                            categoriesData.getItemVisual(categoryIdx, visualList[i])
                        )
                    }
                }
            }
        }
    }
}

// upstream `+categoryIdx`-style numeric coercion for the non-string `category` value (number path).
private func toNumber(_ value: Any?) -> Double {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}
