// Ported from echarts/src/chart/graph/forceLayout.ts — keep in sync with upstream
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
//   import {forceLayout} from './forceHelper';                       -> sibling (forceHelper.swift).
//   import {simpleLayout} from './simpleLayoutHelper';               -> sibling (simpleLayoutHelper.swift).
//   import {circularLayout} from './circularLayoutHelper';           -> sibling (circularLayoutHelper.swift).
//   import {linearMap} from '../../util/number';                     -> `number.linearMap` (util/number.swift).
//   import * as vec2 from 'zrender/src/core/vector';                 -> `vector.*` (ZRenderKit).
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import GraphSeriesModel, { ..., SERIES_TYPE_GRAPH } from './GraphSeries';  -> GraphSeriesModel / SERIES_TYPE_GRAPH.
//   import {getCurvenessForEdge} from '../helper/multipleGraphEdgeHelper';
//       -> `multipleGraphEdgeHelper.getCurvenessForEdge`.
//   import { createSimpleOverallStageHandler } from '../../util/model'; -> `model.createSimpleOverallStageHandler`.

// export interface ForceLayoutInstance { step, warmUp, setFixed, setUnfixed }
//   -> the concrete `ForceLayoutInstance` class returned by `forceLayout` (forceHelper.swift) exposes
//      exactly these (plus the beforeStep/afterStep hooks the object literal carries). Modeled as a class
//      instead of a type-only interface; `GraphSeriesModel.forceLayout` holds it in its `Any?` slot.

// upstream:
//   export const graphForceLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_GRAPH, graphForceLayout);
// `createSimpleOverallStageHandler` expects `(GlobalModel, ExtensionAPI, Payload?) -> Void`; upstream
// `graphForceLayout` is `(ecModel)` (1-arg). Adapt with a thin wrapper that drops the (unused) api +
// payload, keeping `graphForceLayout` byte-faithful (1-arg) below.
public let graphForceLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_GRAPH,
    { ecModel, _, _ in graphForceLayout(ecModel) }
)

// Exposed for the driver to call directly (mirrors the sibling graph layout handlers), matching
// upstream's module-private `function graphForceLayout(ecModel)`.
func graphForceLayout(_ ecModel: GlobalModel) {
    ecModel.eachSeriesByType(SERIES_TYPE_GRAPH) { seriesModelBase, _ in
        // upstream typed callback param `graphSeries: GraphSeriesModel`.
        let graphSeries = seriesModelBase as! GraphSeriesModel

        let coordSys = graphSeries.coordinateSystem as? CoordinateSystem
        // if (coordSys && coordSys.type !== 'view') { return; }
        if let coordSys = coordSys, coordSys.type != "view" {
            return
        }
        if (graphSeries.get("layout") as? String) == "force" {
            // const preservedPoints = graphSeries.preservedPoints || {};
            var preservedPoints = graphSeries.preservedPoints ?? [:]
            let graph = graphSeries.getGraph()
            let nodeData = graph.data!
            let edgeData = graph.edgeData!
            let forceModel = graphSeries.getModel("force")
            let initLayout = forceModel.get("initLayout")
            if graphSeries.preservedPoints != nil {
                nodeData.each { args in
                    let idx = Int(asNumber(args.last))
                    // const id = nodeData.getId(idx);
                    let id = nodeData.getId(idx)
                    // nodeData.setItemLayout(idx, preservedPoints[id] || [NaN, NaN]);
                    nodeData.setItemLayout(idx, preservedPoints[id] ?? [Double.nan, Double.nan])
                }
            }
            // else if (!initLayout || initLayout === 'none') { simpleLayout(graphSeries); }
            //   `!initLayout`: JS-falsy — nil/NSNull/'' fall through to simpleLayout.
            else if !jsTruthy(initLayout) || (initLayout as? String) == "none" {
                simpleLayout(graphSeries)
            }
            // else if (initLayout === 'circular') { circularLayout(graphSeries, 'value'); }
            else if (initLayout as? String) == "circular" {
                circularLayout(graphSeries, "value")
            }

            // const nodeDataExtent = nodeData.getDataExtent('value');
            let nodeDataExtent = nodeData.getDataExtent("value")
            // const edgeDataExtent = edgeData.getDataExtent('value');
            let edgeDataExtent = edgeData.getDataExtent("value")
            // const repulsion = forceModel.get('repulsion');
            let repulsion = forceModel.get("repulsion")
            // const edgeLength = forceModel.get('edgeLength');
            let edgeLength = forceModel.get("edgeLength")
            // const repulsionArr = zrUtil.isArray(repulsion) ? repulsion : [repulsion, repulsion];
            let repulsionArr: [Double] = util.isArray(repulsion)
                ? asDoubleArr(repulsion)
                : [asDouble(repulsion), asDouble(repulsion)]
            // let edgeLengthArr = zrUtil.isArray(edgeLength) ? edgeLength : [edgeLength, edgeLength];
            var edgeLengthArr: [Double] = util.isArray(edgeLength)
                ? asDoubleArr(edgeLength)
                : [asDouble(edgeLength), asDouble(edgeLength)]

            // Larger value has smaller length
            // edgeLengthArr = [edgeLengthArr[1], edgeLengthArr[0]];
            edgeLengthArr = [edgeLengthArr[1], edgeLengthArr[0]]

            // const nodes = nodeData.mapArray('value', function (value, idx) { ... });
            let nodes: [ForceNode] = nodeData.mapArray("value") { args in
                let value = asNumber(args.first ?? nil)
                let idx = Int(asNumber(args.last))
                // const point = nodeData.getItemLayout(idx) as number[];
                let point = asPoint(nodeData.getItemLayout(idx))
                // let rep = linearMap(value, nodeDataExtent, repulsionArr);
                var rep = number.linearMap(value, nodeDataExtent, repulsionArr)
                if rep.isNaN {
                    rep = (repulsionArr[0] + repulsionArr[1]) / 2
                }
                // fixed: nodeData.getItemModel(idx).get('fixed'),
                let fixed = jsTruthy(nodeData.getItemModel(idx).get("fixed"))
                // p: (!point || isNaN(point[0]) || isNaN(point[1])) ? null : point
                let p: VectorArray? = (point.count < 2 || point[0].isNaN || point[1].isNaN)
                    ? nil : VectorArray(point[0], point[1])
                return ForceNode(w: rep, rep: rep, fixed: fixed, p: p)
            }.map { $0 as! ForceNode }

            // const edges = edgeData.mapArray('value', function (value, idx) { ... });
            let edges: [ForceEdge] = edgeData.mapArray("value") { args in
                let value = asNumber(args.first ?? nil)
                let idx = Int(asNumber(args.last))
                // const edge = graph.getEdgeByIndex(idx);
                let edge = graph.getEdgeByIndex(idx)!
                // let d = linearMap(value, edgeDataExtent, edgeLengthArr);
                var d = number.linearMap(value, edgeDataExtent, edgeLengthArr)
                if d.isNaN {
                    d = (edgeLengthArr[0] + edgeLengthArr[1]) / 2
                }
                let edgeModel = edge.getModel()
                // const curveness = zrUtil.retrieve3(
                //     edge.getModel().get(['lineStyle', 'curveness']),
                //     -getCurvenessForEdge(edge, graphSeries, idx, true),
                //     0
                // );
                let curveness: Double = util.retrieve3(
                    asNumberOpt(edgeModel?.get(["lineStyle", "curveness"])),
                    -multipleGraphEdgeHelper.getCurvenessForEdge(edge, graphSeries, Double(idx), true),
                    0
                ) ?? 0
                // ignoreForceLayout: edgeModel.get('ignoreForceLayout')
                let ignore = jsTruthy(edgeModel?.get("ignoreForceLayout"))
                return ForceEdge(
                    n1: nodes[edge.node1.dataIndex],
                    n2: nodes[edge.node2.dataIndex],
                    d: d,
                    curveness: curveness,
                    ignoreForceLayout: ignore
                )
            }.map { $0 as! ForceEdge }

            // const rect = coordSys.getBoundingRect();
            //   A graph series always carries a view coord sys once created; force-unwrap to mirror the
            //   unconditional upstream deref.
            let rect = coordSys!.getBoundingRect()!
            // const forceInstance = forceLayout(nodes, edges, { rect, gravity, friction });
            let forceInstance = forceLayout(nodes, edges, ForceLayoutCfg(
                rect: rect,
                gravity: asDoubleOpt(forceModel.get("gravity")),
                friction: asDoubleOpt(forceModel.get("friction"))
            ))
            // forceInstance.beforeStep(function (nodes, edges) { ... });
            forceInstance.beforeStep { nodes, _ in
                for i in 0..<nodes.count {
                    if nodes[i].fixed {
                        // Write back to layout instance
                        // vec2.copy(nodes[i].p, graph.getNodeByIndex(i).getLayout());
                        let lay = asPoint(graph.getNodeByIndex(i)?.getLayout())
                        if lay.count >= 2 {
                            nodes[i].p = VectorArray(lay[0], lay[1])
                        }
                    }
                }
            }
            // forceInstance.afterStep(function (nodes, edges, stopped) { ... });
            forceInstance.afterStep { [weak graphSeries] nodes, edges, _ in
                for i in 0..<nodes.count {
                    // PORT-NOTE: upstream derefs `nodes[i].p` unconditionally, but `p` is genuinely
                    //   Optional here (set to nil above when the initial point is missing/NaN), so the
                    //   node is skipped instead of trapping.
                    guard let p = nodes[i].p else { continue }
                    if !nodes[i].fixed {
                        graph.getNodeByIndex(i)?.setLayout([p[0], p[1]])
                    }
                    // preservedPoints[nodeData.getId(i)] = nodes[i].p;
                    preservedPoints[nodeData.getId(i)] = [p[0], p[1]]
                }
                // Upstream mutates the SHARED `preservedPoints` object, which `graphSeries.preservedPoints`
                //   already points at. A Swift dictionary is a value, so publish the updated copy back
                //   onto the series every step (weakly captured: the series owns the forceInstance that
                //   owns this closure).
                graphSeries?.preservedPoints = preservedPoints
                for i in 0..<edges.count {
                    let e = edges[i]
                    // PORT-NOTE: upstream derefs the edge and both endpoint points unconditionally;
                    //   both are Optional here, so a missing one skips the edge instead of trapping.
                    guard let edge = graph.getEdgeByIndex(i),
                          let p1 = e.n1.p,
                          let p2 = e.n2.p
                    else { continue }
                    // let points = edge.getLayout(); points = points ? points.slice() : [];
                    // points[0] = points[0] || []; points[1] = points[1] || [];
                    var points = asPointList(edge.getLayout())
                    while points.count < 2 {
                        points.append([])
                    }
                    // vec2.copy(points[0], p1); vec2.copy(points[1], p2);
                    points[0] = [p1[0], p1[1]]
                    points[1] = [p2[0], p2[1]]
                    // if (+e.curveness) { points[2] = [...]; }
                    if e.curveness != 0 {
                        let cp: [Double] = [
                            (p1[0] + p2[0]) / 2 - (p1[1] - p2[1]) * e.curveness,
                            (p1[1] + p2[1]) / 2 - (p2[0] - p1[0]) * e.curveness
                        ]
                        if points.count < 3 {
                            points.append(cp)
                        }
                        else {
                            points[2] = cp
                        }
                    }
                    edge.setLayout(points)
                }
            }
            // graphSeries.forceLayout = forceInstance;
            graphSeries.forceLayout = forceInstance
            // graphSeries.preservedPoints = preservedPoints;
            //   Upstream assigns BEFORE the step: `preservedPoints` is a JS object shared BY REFERENCE, so
            //   every later afterStep mutation is visible through `graphSeries.preservedPoints`. A Swift
            //   dictionary is a VALUE, so the afterStep closure additionally writes its updated copy back
            //   onto the series (see the `graphSeries?.preservedPoints = preservedPoints` above) — that
            //   matters now that most steps run LATER, from GraphView's iteration.
            graphSeries.preservedPoints = preservedPoints

            // Step to get the layout
            // upstream: `forceInstance.step();` — a SINGLE step. The remaining steps are driven by
            //   GraphView._startForceLayoutIteration until the force reports `finished` (friction < 0.01).
            //   (The 1500-iteration synchronous settle that used to stand in here is GONE: the iteration
            //   is now wired in GraphView, which also owns the still-frame fallback — see its
            //   `_startForceLayoutIteration` PORT SEAM note.)
            forceInstance.step()
        }
        else {
            // Remove prev injected forceLayout instance
            // graphSeries.forceLayout = null;
            graphSeries.forceLayout = nil
        }
    }
}

// MARK: - Port helpers (not upstream symbols)

// `data.get(...)`/mapArray-arg dynamic value -> Double (NaN when non-numeric), mirroring `as number`.
private func asNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return Double.nan
}

// numeric-or-nil (for retrieve3 / option reads that may be absent). Handles the Int-vs-Double
//   option-boxing trap (option numbers box Int OR Double).
private func asNumberOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return Double.nan
}

private func asDoubleOpt(_ v: Any?) -> Double? {
    return asNumberOpt(v)
}

// Coerce a dynamic option value that is an array of numbers (Int or Double boxed) to [Double].
private func asDoubleArr(_ v: Any?) -> [Double] {
    if let a = v as? [Double] { return a }
    if let a = v as? [Any] {
        return a.map { asDouble($0) }
    }
    return []
}

// A node/edge layout point is a JS `number[]` of length 2; read it back as [Double].
private func asPoint(_ layout: Any?) -> [Double] {
    if let a = layout as? [Double] { return a }
    if let a = layout as? [Any] {
        return a.map { asDouble($0) }
    }
    return [Double.nan, Double.nan]
}

// An edge layout is a JS `number[][]` (list of points); read it back as [[Double]].
private func asPointList(_ layout: Any?) -> [[Double]] {
    if let a = layout as? [[Double]] { return a }
    if let a = layout as? [Any] {
        return a.map { asPoint($0) }
    }
    return []
}

// Mirrors JavaScript `||`/`&&`/`!` truthiness for a dynamic `Any?` (nil / NSNull / false / 0 / NaN / ""
//   are falsy). Used for `!initLayout`, `n.fixed`, `ignoreForceLayout`.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
