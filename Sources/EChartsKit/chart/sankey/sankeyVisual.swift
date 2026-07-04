// Ported from echarts/src/chart/sankey/sankeyVisual.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                        -> `util.each` (ZRenderKit).
//   import VisualMapping from '../../visual/VisualMapping';
//       -> PORT-TODO: visual/VisualMapping.ts NOT ported. The per-node linear color mapping
//          (`new VisualMapping({ type:'color', mappingMethod:'linear', dataExtent:[min,max], visual:… })`
//          + `mapping.mapValueToVisual(value)`) is DEFERRED — `sankeyMapValueToColor` returns nil, so a
//          node with no explicit itemStyle.color receives no palette color yet. Wire once VisualMapping
//          lands (same deferral as treemapVisual.swift). The min/max value walk below is kept faithful so
//          the `dataExtent` is ready for the mapping.
//   import GlobalModel from '../../model/Global';                           -> GlobalModel (model/Global.swift).
//   import SankeySeriesModel, { SankeyEdgeItemOption, SankeyNodeItemOption, SERIES_TYPE_SANKEY } from './SankeySeries';
//       -> sibling SankeySeries.swift (SankeySeriesModel / SERIES_TYPE_SANKEY). The two *ItemOption
//          generics only parameterize `getModel<T>()` — dropped (getModel() is untyped).
//   import { createSimpleOverallStageHandler } from '../../util/model';     -> `model.createSimpleOverallStageHandler`.

// export const sankeyVisualStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_SANKEY, sankeyVisual);
// `sankeyVisual` is `(ecModel)` (1-arg); the handler expects `(GlobalModel, ExtensionAPI, Payload?)`.
// Adapt with a thin wrapper that drops the extra args, keeping `sankeyVisual` byte-faithful (1-arg)
// (same deviation as treeVisualStageHandler / graphEdgeVisualStageHandler).
public let sankeyVisualStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_SANKEY,
    { ecModel, _, _ in sankeyVisual(ecModel) }
)

func sankeyVisual(_ ecModel: GlobalModel) {
    ecModel.eachSeriesByType(SERIES_TYPE_SANKEY) { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! SankeySeriesModel
        let graph = seriesModel.getGraph()
        let nodes = graph.nodes
        let edges = graph.edges
        // if (nodes.length) {
        if nodes.count != 0 {
            // let minValue = Infinity;
            var minValue = Double.infinity
            // let maxValue = -Infinity;
            var maxValue = -Double.infinity
            // zrUtil.each(nodes, function (node) {
            util.each(nodes) { (node: GraphNode, _) in
                // const nodeValue = node.getLayout().value;
                let nodeValue = sankeyLayoutValue(node.getLayout())
                // if (nodeValue < minValue) { minValue = nodeValue; }
                if nodeValue < minValue { minValue = nodeValue }
                // if (nodeValue > maxValue) { maxValue = nodeValue; }
                if nodeValue > maxValue { maxValue = nodeValue }
            }

            // zrUtil.each(nodes, function (node) {
            util.each(nodes) { (node: GraphNode, _) in
                // const mapping = new VisualMapping({
                //     type: 'color', mappingMethod: 'linear',
                //     dataExtent: [minValue, maxValue], visual: seriesModel.get('color')
                // });
                // const mapValueToColor = mapping.mapValueToVisual(node.getLayout().value);
                // PORT-TODO: VisualMapping DEFERRED — see the top-of-file import PORT-TODO. The mapped color
                //   resolves to nil; `dataExtent` [minValue, maxValue] and the series `color` palette are
                //   passed through for when the mapping lands.
                let mapValueToColor = sankeyMapValueToColor(
                    [minValue, maxValue],
                    seriesModel.get("color"),
                    sankeyLayoutValue(node.getLayout())
                )

                // const customColor = node.getModel<SankeyNodeItemOption>().get(['itemStyle', 'color']);
                let customColor = node.getModel()?.get(["itemStyle", "color"])
                // if (customColor != null) {
                if customColor != nil && !(customColor is NSNull) {
                    // node.setVisual('color', customColor);
                    node.setVisual("color", customColor)
                    // node.setVisual('style', {fill: customColor});
                    node.setVisual("style", ["fill": customColor as Any] as [String: Any])
                }
                else {
                    // node.setVisual('color', mapValueToColor);
                    node.setVisual("color", mapValueToColor)
                    // node.setVisual('style', {fill: mapValueToColor});
                    node.setVisual("style", ["fill": mapValueToColor as Any] as [String: Any])
                }
            }
        }
        // if (edges.length) {
        if edges.count != 0 {
            // zrUtil.each(edges, function (edge) {
            util.each(edges) { (edge: GraphEdge, _) in
                // const edgeStyle = edge.getModel<SankeyEdgeItemOption>().get('lineStyle');
                let edgeStyle = edge.getModel()?.get("lineStyle")
                // edge.setVisual('style', edgeStyle);
                edge.setVisual("style", edgeStyle)
            }
        }
    }
}

// Reads `node.getLayout().value` off the dynamic `Any?` layout bag (a `[String: Any]` sankeyLayout
//   writes). Returns the node's flow value as a `Double`; missing → NaN (so it participates in neither
//   min nor max, matching an undefined value's JS comparison behavior). Not an upstream symbol.
private func sankeyLayoutValue(_ layout: Any?) -> Double {
    guard let d = layout as? [String: Any] else { return Double.nan }
    switch d["value"] {
    case let v as Double: return v
    case let v as Int: return Double(v)
    case let v as NSNumber: return v.doubleValue
    default: return Double.nan
    }
}

// PORT-TODO: stand-in for `new VisualMapping({type:'color', mappingMethod:'linear', dataExtent, visual})
//   .mapValueToVisual(value)`. visual/VisualMapping.ts NOT ported, so the linear palette interpolation is
//   DEFERRED and this returns nil (a node with no explicit itemStyle.color gets no computed fill yet).
//   The signature carries the exact upstream inputs so the body can be filled in once VisualMapping lands.
private func sankeyMapValueToColor(_ dataExtent: [Double], _ visual: Any?, _ value: Double) -> Any? {
    _ = (dataExtent, visual, value)
    return nil
}
