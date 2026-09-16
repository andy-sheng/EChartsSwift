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
//       -> note: visual/VisualMapping.swift is ported. This file still uses a local stand-in,
//          `sankeyMapValueToColor`, for the per-node linear color mapping
//          (`new VisualMapping({ type:'color', mappingMethod:'linear', dataExtent:[min,max], visual:… })`
//          + `mapping.mapValueToVisual(value)`); the stand-in does the linear palette interpolation
//          directly, so a node's fill is computed here. It could be re-wired to the real VisualMapping.
//          The min/max value walk below is kept faithful so the `dataExtent` is ready for the mapping.
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
                // uses the local `sankeyMapValueToColor` stand-in (see the top-of-file import
                //   note); `dataExtent` [minValue, maxValue] and the series `color` palette are passed
                //   through. Could be re-wired to the real (ported) VisualMapping.
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

// local stand-in for `new VisualMapping({type:'color', mappingMethod:'linear', dataExtent, visual})
//   .mapValueToVisual(value)`. visual/VisualMapping.swift is ported; this local implementation does the
//   linear palette interpolation itself and could be re-wired to the real VisualMapping.
//   The signature carries the exact upstream inputs.
// Faithful stand-in for `new VisualMapping({type:'color', mappingMethod:'linear', dataExtent, visual})`
//   `.mapValueToVisual(value)`: normalize `value` into [0,1] over `dataExtent`, then linear-interpolate
//   across the palette color list (zrColor.lerp). The full VisualMapping subsystem is deferred; this is
//   the one mapping sankey needs (without it every node fell to the default black fill).
private func sankeyMapValueToColor(_ dataExtent: [Double], _ visual: Any?, _ value: Double) -> Any? {
    let colors = sankeyNormalizePalette(visual)
    guard !colors.isEmpty else { return nil }
    if colors.count == 1 { return colors[0] }
    // Faithful to `linearMap(value, dataExtent, [0, 1], /* clamp */ true)` (util/number.ts):
    //   the mapping is `new VisualMapping({ mappingMethod: 'linear', dataExtent, … })._normalizeData`.
    //   subDomain = hi - lo; subRange = 1 - 0 = 1. When subDomain === 0 (all-equal / single node)
    //   linearMap returns (r0 + r1) / 2 = 0.5 (NOT 0), which lands on the mid-palette color.
    let lo = dataExtent[0], hi = dataExtent[1]
    let subDomain = hi - lo
    var t: Double
    if subDomain == 0 {
        t = 0.5
    }
    else if subDomain > 0 {
        if value <= lo { t = 0 }
        else if value >= hi { t = 1 }
        else { t = (value - lo) / subDomain }
    }
    else { // subDomain < 0
        if value >= lo { t = 0 }
        else if value <= hi { t = 1 }
        else { t = (value - lo) / subDomain }
    }
    if !t.isFinite { t = 0 }
    t = Swift.min(Swift.max(t, 0), 1)
    if case let .color(c)? = ZRenderKit.color.lerp(t, colors) { return c }
    return colors[0]
}

// Coerce a dynamic `color` palette option (String / [String] / [ZRColor] / mixed) into `[String]`.
private func sankeyNormalizePalette(_ visual: Any?) -> [String] {
    func one(_ v: Any?) -> String? {
        if let s = v as? String { return s }
        if let z = v as? EChartsKit.ZRColor, case let .color(s) = z { return s }
        if let z = v as? ZRenderKit.ZRColor, case let .string(s) = z { return s }
        return nil
    }
    if let arr = visual as? [Any] { return arr.compactMap(one) }
    if let s = one(visual) { return [s] }
    return []
}
