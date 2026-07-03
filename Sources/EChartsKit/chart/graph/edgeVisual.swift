// Ported from echarts/src/chart/graph/edgeVisual.ts — keep in sync with upstream
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
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.
//   import GraphSeriesModel, { GraphEdgeItemOption, SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> PORT-TODO: sibling GraphSeries.swift NOT ported yet; `GraphSeriesModel` / `SERIES_TYPE_GRAPH`
//          referenced as siblings. `GraphEdgeItemOption` is a type-only generic — dropped.
//   import { extend } from 'zrender/src/core/util';                  -> `util.extend`.

// function normalize(a): a is `string | number | (string | number)[]`.
//   The two TS overloads are erased at runtime to the single body below.
//   if (!(a instanceof Array)) { a = [a, a]; } return a;
private func normalize(_ a: Any?) -> [Any?] {
    if let arr = a as? [Any?] {
        return arr
    }
    return [a, a]
}

// upstream:
//   export const graphEdgeVisualStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, graphEdgeVisual);
// `graphEdgeVisual` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
public let graphEdgeVisualStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, _, _ in graphEdgeVisual(ecModel) }
)

func graphEdgeVisual(_ ecModel: GlobalModel) {
    ecModel.eachSeriesByType(SERIES_TYPE_GRAPH) { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! GraphSeriesModel
        let graph = seriesModel.getGraph()
        let edgeData = seriesModel.getEdgeData()
        let symbolType = normalize(seriesModel.get("edgeSymbol"))
        let symbolSize = normalize(seriesModel.get("edgeSymbolSize"))

        // const colorQuery = ['lineStyle', 'color'] as const;
        // const opacityQuery = ['lineStyle', 'opacity'] as const;

        // `symbolType && symbolType[0]`: `normalize` always returns a 2-element array (truthy), so the
        //   `&&` short-circuit reduces to `symbolType[0]` (likewise below).
        edgeData.setVisual("fromSymbol", symbolType[0])
        edgeData.setVisual("toSymbol", symbolType[1])
        edgeData.setVisual("fromSymbolSize", symbolSize[0])
        edgeData.setVisual("toSymbolSize", symbolSize[1])

        edgeData.setVisual("style", seriesModel.getModel("lineStyle").getLineStyle())

        edgeData.each { args in
            let idx = Int(args[0] as! Double)
            let itemModel = edgeData.getItemModel(idx)
            // `getEdgeByIndex` is `GraphEdge?` in the port; upstream types it non-null and the index
            // comes straight from `edgeData.each`, so it is always present — force-unwrap.
            let edge = graph.getEdgeByIndex(idx)!
            let symbolType = normalize(itemModel.getShallow("symbol", true))
            let symbolSize = normalize(itemModel.getShallow("symbolSize", true))
            // Edge visual must after node visual
            let style = itemModel.getModel("lineStyle").getLineStyle()

            // const existsStyle = edgeData.ensureUniqueItemVisual(idx, 'style'); extend(existsStyle, style);
            //   Upstream mutates the stored visual `style` object in place; the ported store returns a
            //   value dict, so read → extend → (mutate) → write back (CONVENTIONS §3).
            var existsStyle = (edgeData.ensureUniqueItemVisual(idx, "style") as? [String: Any]) ?? [:]
            _ = util.extend(&existsStyle, style)

            switch existsStyle["stroke"] as? String {
            case "source":
                let nodeStyle = edge.node1.getVisual("style") as? [String: Any]
                // existsStyle.stroke = nodeStyle && nodeStyle.fill;
                existsStyle["stroke"] = nodeStyle != nil ? nodeStyle!["fill"] : nil
            case "target":
                let nodeStyle = edge.node2.getVisual("style") as? [String: Any]
                existsStyle["stroke"] = nodeStyle != nil ? nodeStyle!["fill"] : nil
            default:
                break
            }

            edgeData.setItemVisual(idx, "style", existsStyle)

            // symbolType[0] && edge.setVisual('fromSymbol', symbolType[0]); (per-item, guarded)
            if isTruthy(symbolType[0]) { edge.setVisual("fromSymbol", symbolType[0]) }
            if isTruthy(symbolType[1]) { edge.setVisual("toSymbol", symbolType[1]) }
            if isTruthy(symbolSize[0]) { edge.setVisual("fromSymbolSize", symbolSize[0]) }
            if isTruthy(symbolSize[1]) { edge.setVisual("toSymbolSize", symbolSize[1]) }
        }
    }
}

// JS falsy semantics (nil/0/""/false/NaN) for the guarded per-item `x && ...` short-circuits.
private func isTruthy(_ value: Any?) -> Bool {
    switch value {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
