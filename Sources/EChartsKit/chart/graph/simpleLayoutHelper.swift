// Ported from echarts/src/chart/graph/simpleLayoutHelper.ts — keep in sync with upstream
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
//   import * as vec2 from 'zrender/src/core/vector';                 -> `vector.*` (ZRenderKit).
//   import GraphSeriesModel, { GraphNodeItemOption, GraphEdgeItemOption } from './GraphSeries';
//       -> GraphSeriesModel (PORT-NOTE: chart/graph/GraphSeries.swift ported).
//   import Graph from '../../data/Graph';                            -> Graph (data/Graph.swift).
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import {getCurvenessForEdge} from '../helper/multipleGraphEdgeHelper';
//       -> `multipleGraphEdgeHelper.getCurvenessForEdge` (chart/helper/multipleGraphEdgeHelper.swift).

public func simpleLayout(_ seriesModel: GraphSeriesModel) {
    let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
    // if (coordSys && coordSys.type !== 'view') { return; }
    if coordSys != nil && coordSys!.type != "view" {
        return
    }
    let graph = seriesModel.getGraph()

    graph.eachNode { node, _ in
        // const model = node.getModel<GraphNodeItemOption>();
        let model = node.getModel()   // GraphNode.getModel() -> Model?
        // node.setLayout([+model.get('x'), +model.get('y')]);
        // `+` is JS unary-plus (string/undefined -> number coercion); see `plus` below.
        node.setLayout([plus(model?.get("x")), plus(model?.get("y"))])
    }

    simpleLayoutEdge(graph, seriesModel)
}

public func simpleLayoutEdge(_ graph: Graph, _ seriesModel: GraphSeriesModel) {
    graph.eachEdge { edge, index in
        // const curveness = zrUtil.retrieve3(
        //     edge.getModel<GraphEdgeItemOption>().get(['lineStyle', 'curveness']),
        //     -getCurvenessForEdge(edge, seriesModel, index, true),
        //     0
        // );
        let curveness: Double = util.retrieve3(
            asNumberOpt(edge.getModel()?.get(["lineStyle", "curveness"])),
            -multipleGraphEdgeHelper.getCurvenessForEdge(edge, seriesModel, Double(index), true),
            0
        ) ?? 0
        // const p1 = vec2.clone(edge.node1.getLayout());
        // const p2 = vec2.clone(edge.node2.getLayout());
        // vec2.clone of a number[] is a value copy; [Double] is already a value type (CONVENTIONS §3/§4).
        let p1 = asPoint(edge.node1.getLayout())
        let p2 = asPoint(edge.node2.getLayout())
        // const points = [p1, p2];
        var points: [[Double]] = [p1, p2]
        // if (+curveness) { points.push([...]); }
        if curveness != 0 {
            points.append([
                (p1[0] + p2[0]) / 2 - (p1[1] - p2[1]) * curveness,
                (p1[1] + p2[1]) / 2 - (p2[0] - p1[0]) * curveness
            ])
        }
        edge.setLayout(points)
    }
}

// MARK: - Port helpers (not upstream symbols)

// JS unary-plus coercion of a dynamic option value (`+model.get(...)`):
//   undefined -> NaN, null -> 0, "" -> 0, numeric string -> its value, else NaN.
private func plus(_ v: Any?) -> Double {
    guard let v = v else { return Double.nan }   // +undefined
    if v is NSNull { return 0 }                  // +null
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let b = v as? Bool { return b ? 1 : 0 }
    if let s = v as? String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return 0 }                 // +"" === 0
        return Double(t) ?? Double.nan
    }
    return Double.nan
}

// `edge.getModel().get([...])` returns a dynamic value; coerce numeric-or-nil for retrieve3.
private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

// A node/edge layout point is a JS `number[]` of length 2; read it back as [Double].
private func asPoint(_ layout: Any?) -> [Double] {
    if let a = layout as? [Double] { return a }
    if let a = layout as? [Any] {
        return a.map { (($0 as? Double) ?? Double(($0 as? Int) ?? 0)) }
    }
    return [Double.nan, Double.nan]
}
