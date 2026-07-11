// Ported from echarts/src/chart/helper/createGraphFromNodeEdge.ts — keep in sync with upstream
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

// upstream imports (translated against the conventional public API of sibling files):
//   import * as zrUtil from 'zrender/src/core/util';                    -> ZRenderKit.util (retrieve, indexOf)
//   import SeriesData from '../../data/SeriesData';                      -> data/SeriesData.swift
//   import Graph from '../../data/Graph';                                -> data/Graph.swift (sibling port)
//   import linkSeriesData from '../../data/helper/linkSeriesData';       -> linkSeriesData.linkSeriesData
//   import prepareSeriesDataSchema from '../../data/helper/createDimensions';  -> createDimensions.prepareSeriesDataSchema
//   import CoordinateSystem from '../../core/CoordinateSystem';
//       -> PORT: default export is `CoordinateSystemManager` (core/CoordinateSystemManager.swift);
//          `CoordinateSystem.get(type)` -> `CoordinateSystemManager.get(type)` (returns `CoordinateSystemCreator?`).
//   import createSeriesData from './createSeriesData';                   -> createSeriesData (free func)
//   import { OptionSourceDataOriginal, GraphEdgeItemObject, OptionDataValue,
//            OptionDataItemObject } from '../../util/types';             -> util/types.swift
//   import SeriesModel from '../../model/Series';                        -> model/Series.swift
//   import { convertOptionIdName } from '../../util/model';              -> model.convertOptionIdName

// export default function createGraphFromNodeEdge(...): Graph  -> free function (CONVENTIONS §2).
//
// PORT-NOTE: upstream `nodes: OptionSourceDataOriginal<OptionDataValue, OptionDataItemObject<OptionDataValue>>`
//   and `edges: OptionSourceDataOriginal<OptionDataValue, GraphEdgeItemObject<OptionDataValue>>`. Both
//   `OptionSourceDataOriginal` collapse to `[Any]` here (== `[OptionDataItemOriginal]`); each element is
//   read as a `[String: Any]` option bag (`.id` / `.name` for nodes, `.source` / `.target` / `.id` for edges).
public func createGraphFromNodeEdge(
    _ nodes: OptionSourceDataOriginal,
    _ edges: OptionSourceDataOriginal,
    _ seriesModel: SeriesModel,
    _ directed: Bool,
    _ beforeLink: ((SeriesData, SeriesData) -> Void)? = nil
) -> Graph {
    // ??? TODO
    // support dataset?
    let graph = Graph(directed)
    for i in 0..<nodes.count {
        let nodeItem = nodes[i] as? [String: Any]
        // graph.addNode(zrUtil.retrieve(nodes[i].id, nodes[i].name, i), i);
        // Id, name, dataIndex
        graph.addNode(
            util.retrieve(nodeItem?["id"], nodeItem?["name"], Double(i) as Any?),
            i
        )
    }

    var linkNameList: [String?] = []
    var validEdges: [Any] = []
    var linkCount = 0
    for i in 0..<edges.count {
        let link = edges[i] as? [String: Any]
        let source = link?["source"]
        let target = link?["target"]
        // addEdge may fail when source or target not exists
        if graph.addEdge(source, target, linkCount) != nil {
            validEdges.append(edges[i])
            // zrUtil.retrieve(convertOptionIdName(link.id, null), source + ' > ' + target)
            linkNameList.append(
                util.retrieve(
                    model.convertOptionIdName(link?["id"], nil),
                    optionDataValueToString(source) + " > " + optionDataValueToString(target)
                )
            )
            linkCount += 1
        }
    }

    let coordSys = seriesModel.get("coordinateSystem", false) as? String
    let nodeData: SeriesData
    if coordSys == "cartesian2d" || coordSys == "polar" || coordSys == "matrix" {
        nodeData = createSeriesData(nodes, seriesModel)
    }
    else {
        // upstream: CoordinateSystem.get(coordSys)  (CoordinateSystem == CoordinateSystemManager here)
        let coordSysCtor = CoordinateSystemManager.get(coordSys ?? "")
        // const coordDimensions = coordSysCtor ? (coordSysCtor.dimensions || []) : [];
        let coordDimensions: [DimensionName] = (coordSysCtor?.dimensions) ?? []
        // FIXME: Some geo do not need `value` dimenson, whereas `calendar` needs
        // `value` dimension, but graph need `value` dimension. It's better to
        // uniform this behavior.
        if util.indexOf(coordDimensions, "value") < 0 {
            // PORT NOTE: faithful to the upstream bug — `Array.prototype.concat` returns a NEW array
            //   but the result is never assigned back, so this branch is a no-op. Replicated as a
            //   discarded expression to keep the diff surface identical.
            _ = coordDimensions + ["value"]  // coordDimensions.concat(['value']);
        }

        let schema = createDimensions.prepareSeriesDataSchema(
            nodes,
            PrepareSeriesDataSchemaParams(
                coordDimensions: coordDimensions.map { $0 as CoordDimensionDefinitionLoose },
                encodeDefine: seriesModel.getEncode()
            )
        )
        let dimensions = schema.dimensions
        nodeData = SeriesData(dimensions, seriesModel)
        nodeData.initData(nodes)
    }

    let edgeData = SeriesData(["value"], seriesModel)
    edgeData.initData(validEdges, linkNameList)

    // beforeLink && beforeLink(nodeData, edgeData);
    beforeLink?(nodeData, edgeData)

    linkSeriesData.linkSeriesData(LinkSeriesDataOpt(
        mainData: nodeData,
        // `LinkSeriesDataOpt.struct` is the shared `LinkableStruct` protocol (Tree | Graph); `linkSingle`
        //   wires `structAttr == "graph"` and the `datasAttr` values "data"/"edgeData".
        struct: graph,
        structAttr: "graph",
        datas: [.node: nodeData, .edge: edgeData],
        datasAttr: [.node: "data", .edge: "edgeData"]
    ))

    // Update dataIndex of nodes and edges because invalid edge may be removed
    graph.update()

    return graph
}

// Mirrors JS string coercion of an `OptionDataValue` (string | number | null) for the
// `source + ' > ' + target` link-name concatenation. Not an upstream symbol.
private func optionDataValueToString(_ v: Any?) -> String {
    guard let v = v else { return "undefined" }
    if v is NSNull { return "null" }
    if let s = v as? String { return s }
    if let d = v as? Double {
        // JS number-to-string: integral doubles print without a fractional part.
        if d == d.rounded() && d.isFinite {
            return String(Int(d))
        }
        return String(d)
    }
    if let i = v as? Int { return String(i) }
    if let b = v as? Bool { return b ? "true" : "false" }
    return String(describing: v)
}
