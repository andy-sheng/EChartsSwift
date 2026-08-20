// Ported from echarts/src/data/Graph.ts — keep in sync with upstream
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

// upstream imports (reused from sibling/ZRenderKit ports where available):
//   import * as zrUtil from 'zrender/src/core/util';            -> ZRenderKit.util
//   import { Dictionary } from 'zrender/src/core/types';        -> [String: T] / HashMap
//   import SeriesData from './SeriesData';                      -> data/SeriesData.swift
//   import Model from '../model/Model';                         -> model/Model.swift
//   import Element from 'zrender/src/Element';                  -> ZRenderKit.Element
//   import { DimensionLoose, ParsedValue } from '../util/types';-> util/types.swift

// id may be function name of Object, add a prefix to avoid this problem.
// function generateNodeKey(id: string): string { return '_EC_' + id; }
private func generateNodeKey(_ id: String) -> String {
    return "_EC_" + id
}

// Shape returned by getAdjacentDataIndices / getTrajectoryDataIndices:
//   `{ node: number[], edge: number[] }`.
public struct GraphDataIndices {
    public var node: [Int]
    public var edge: [Int]
    public init(node: [Int] = [], edge: [Int] = []) {
        self.node = node
        self.edge = edge
    }
}

public final class Graph: LinkableStruct {

    // type: 'graph' = 'graph';
    public let type: String = "graph"

    // readonly nodes: GraphNode[] = [];
    public private(set) var nodes: [GraphNode] = []

    // readonly edges: GraphEdge[] = [];
    public private(set) var edges: [GraphEdge] = []

    // PORT-NOTE: upstream `data: SeriesData` is assigned by linkSeriesData; implicitly-unwrapped.
    // The linked SeriesData objects own this Graph. These inverse links must not close ARC cycles.
    public weak var data: SeriesData!

    // PORT-NOTE: upstream `edgeData: SeriesData` is assigned by linkSeriesData; implicitly-unwrapped.
    public weak var edgeData: SeriesData!

    /**
     * Whether directed graph.
     */
    private var _directed: Bool

    private var _nodesMap: [String: GraphNode] = [:]
    /**
     * @private
     */
    private var _edgesMap: [String: GraphEdge] = [:]

    // constructor(directed?: boolean) { this._directed = directed || false; }
    public init(_ directed: Bool? = nil) {
        self._directed = directed ?? false
    }

    /**
     * If is directed graph
     */
    public func isDirected() -> Bool {
        return self._directed
    }

    /**
     * Add a new node
     */
    // addNode(id: string | number, dataIndex?: number): GraphNode
    // Returns nil on the duplicate-name early `return;` (upstream types GraphNode but returns undefined).
    @discardableResult
    public func addNode(_ id: Any?, _ dataIndex: Int? = nil) -> GraphNode? {
        // id = id == null ? ('' + dataIndex) : ('' + id);
        let isNull = (id == nil) || (id is NSNull)
        let idStr: String = isNull ? jsPlus(dataIndex) : jsPlus(id)

        // const nodesMap = this._nodesMap;  (Swift dictionaries are value types; mutate via self._nodesMap.)
        if self._nodesMap[generateNodeKey(idStr)] != nil {
            // if (__DEV__) { console.error('Graph nodes have duplicate name or id'); }
            return nil
        }

        let node = GraphNode(idStr, dataIndex)
        node.hostGraph = self

        self.nodes.append(node)

        self._nodesMap[generateNodeKey(idStr)] = node
        return node
    }

    /**
     * Get node by data index
     */
    public func getNodeByIndex(_ dataIndex: Int) -> GraphNode? {
        let rawIdx = self.data.getRawIndex(dataIndex)
        return (rawIdx >= 0 && rawIdx < self.nodes.count) ? self.nodes[rawIdx] : nil
    }
    /**
     * Get node by id
     */
    public func getNodeById(_ id: String) -> GraphNode? {
        return self._nodesMap[generateNodeKey(id)]
    }

    /**
     * Add a new edge
     */
    // addEdge(n1: GraphNode | number | string, n2: GraphNode | number | string, dataIndex?: number)
    @discardableResult
    public func addEdge(_ n1: Any?, _ n2: Any?, _ dataIndex: Int? = nil) -> GraphEdge? {
        // const nodesMap = this._nodesMap; const edgesMap = this._edgesMap;

        // PENDING
        // if (zrUtil.isNumber(n1)) { n1 = this.nodes[n1]; }
        // if (!(n1 instanceof GraphNode)) { n1 = nodesMap[generateNodeKey(n1)]; }
        let node1 = self.resolveNode(n1)
        let node2 = self.resolveNode(n2)

        // if (!n1 || !n2) { return; }
        guard let n1n = node1, let n2n = node2 else {
            return nil
        }

        let key = n1n.id + "-" + n2n.id

        let edge = GraphEdge(n1n, n2n, dataIndex)
        edge.hostGraph = self

        if self._directed {
            n1n.outEdges.append(edge)
            n2n.inEdges.append(edge)
        }
        n1n.edges.append(edge)
        if n1n !== n2n {
            n2n.edges.append(edge)
        }

        self.edges.append(edge)
        self._edgesMap[key] = edge

        return edge
    }

    // Resolves the `GraphNode | number | string` argument of addEdge, mirroring upstream's
    // isNumber -> nodes[n] then `!(n instanceof GraphNode)` -> nodesMap[generateNodeKey(n)] chain.
    private func resolveNode(_ n: Any?) -> GraphNode? {
        // upstream: `if (isNumber(n)) { n = this.nodes[n]; }` runs UNCONDITIONALLY, so an
        //   out-of-range numeric index becomes `undefined` and the follow-up map lookup keys on
        //   `generateNodeKey(undefined)` (== "_EC_undefined") — NOT on the original number. Track the
        //   resolved value the same way (nil == undefined) so jsPlus(nil) yields "undefined".
        var resolved: Any? = n
        // upstream `zrUtil.isNumber(n)`; accept Int too since node indices may arrive as either.
        if util.isNumber(n) || (n is Int) {
            let idx = asInt(n)
            resolved = (idx >= 0 && idx < self.nodes.count) ? self.nodes[idx] : nil
        }
        // upstream: `if (!(n instanceof GraphNode)) { n = nodesMap[generateNodeKey(n)]; }`
        if let gn = resolved as? GraphNode {
            return gn
        }
        return self._nodesMap[generateNodeKey(jsPlus(resolved))]
    }

    /**
     * Get edge by data index
     */
    public func getEdgeByIndex(_ dataIndex: Int) -> GraphEdge? {
        let rawIdx = self.edgeData.getRawIndex(dataIndex)
        return (rawIdx >= 0 && rawIdx < self.edges.count) ? self.edges[rawIdx] : nil
    }
    /**
     * Get edge by two linked nodes
     */
    // getEdge(n1: string | GraphNode, n2: string | GraphNode): GraphEdge
    public func getEdge(_ n1: Any?, _ n2: Any?) -> GraphEdge? {
        // if (n1 instanceof GraphNode) { n1 = n1.id; }
        let id1: String = (n1 as? GraphNode)?.id ?? jsPlus(n1)
        let id2: String = (n2 as? GraphNode)?.id ?? jsPlus(n2)

        if self._directed {
            return self._edgesMap[id1 + "-" + id2]
        }
        else {
            // edgesMap[n1 + '-' + n2] || edgesMap[n2 + '-' + n1]
            return self._edgesMap[id1 + "-" + id2]
                ?? self._edgesMap[id2 + "-" + id1]
        }
    }

    /**
     * Iterate all nodes
     */
    // eachNode<Ctx>(cb, context?)
    public func eachNode(_ cb: (GraphNode, Int) -> Void, _ context: Any? = nil) {
        let nodes = self.nodes
        let len = nodes.count
        for i in 0..<len {
            if nodes[i].dataIndex >= 0 {
                cb(nodes[i], i)
            }
        }
    }

    /**
     * Iterate all edges
     */
    // eachEdge<Ctx>(cb, context?)
    public func eachEdge(_ cb: (GraphEdge, Int) -> Void, _ context: Any? = nil) {
        let edges = self.edges
        let len = edges.count
        for i in 0..<len {
            if edges[i].dataIndex >= 0
                && edges[i].node1.dataIndex >= 0
                && edges[i].node2.dataIndex >= 0 {
                cb(edges[i], i)
            }
        }
    }

    /**
     * Breadth first traverse
     * Return true to stop traversing
     */
    // breadthFirstTraverse<Ctx>(cb, startNode, direction, context?)
    // PORT-NOTE: cb returns `boolean | void`; modeled as `Any?` (truthy -> stop). `this: Ctx`
    //   binding dropped (Swift closures capture context directly); `context` kept for fidelity.
    public func breadthFirstTraverse(
        _ cb: (GraphNode, GraphNode?) -> Any?,
        _ startNode: Any?,
        _ direction: String,
        _ context: Any? = nil
    ) {
        // if (!(startNode instanceof GraphNode)) { startNode = this._nodesMap[generateNodeKey(startNode)]; }
        var start: GraphNode?
        if let sn = startNode as? GraphNode {
            start = sn
        }
        else {
            start = self._nodesMap[generateNodeKey(jsPlus(startNode))]
        }
        guard let startNodeResolved = start else {
            return
        }

        // const edgeType = direction === 'out' ? 'outEdges' : (direction === 'in' ? 'inEdges' : 'edges');
        let edgeType: String = direction == "out"
            ? "outEdges" : (direction == "in" ? "inEdges" : "edges")

        for i in 0..<self.nodes.count {
            self.nodes[i].__visited = false
        }

        // if (cb.call(context, startNode, null)) { return; }
        if jsBool(cb(startNodeResolved, nil)) {
            return
        }

        var queue: [GraphNode] = [startNodeResolved]
        while !queue.isEmpty {
            let currentNode = queue.removeFirst()
            let edges = currentNode.edgesForType(edgeType)

            for i in 0..<edges.count {
                let e = edges[i]
                let otherNode = e.node1 === currentNode ? e.node2 : e.node1
                if !otherNode.__visited {
                    if jsBool(cb(otherNode, currentNode)) {
                        // Stop traversing
                        return
                    }
                    queue.append(otherNode)
                    otherNode.__visited = true
                }
            }
        }
    }

    // TODO
    // depthFirstTraverse(cb, startNode, direction, context) {};

    // Filter update
    public func update() {
        let data = self.data!
        let edgeData = self.edgeData!
        let nodes = self.nodes
        let edges = self.edges

        var i = 0
        var len = nodes.count
        while i < len {
            nodes[i].dataIndex = -1
            i += 1
        }
        i = 0
        len = data.count()
        while i < len {
            nodes[data.getRawIndex(i)].dataIndex = i
            i += 1
        }

        edgeData.filterSelf { args in
            let idx = asInt(args.first)
            let edge = edges[edgeData.getRawIndex(idx)]
            return edge.node1.dataIndex >= 0 && edge.node2.dataIndex >= 0
        }

        // Update edge
        i = 0
        len = edges.count
        while i < len {
            edges[i].dataIndex = -1
            i += 1
        }
        i = 0
        len = edgeData.count()
        while i < len {
            edges[edgeData.getRawIndex(i)].dataIndex = i
            i += 1
        }
    }

    /**
     * @return {module:echarts/data/Graph}
     */
    public func clone() -> Graph {
        let graph = Graph(self._directed)
        let nodes = self.nodes
        let edges = self.edges
        for i in 0..<nodes.count {
            graph.addNode(nodes[i].id, nodes[i].dataIndex)
        }
        for i in 0..<edges.count {
            let e = edges[i]
            graph.addEdge(e.node1.id, e.node2.id, e.dataIndex)
        }
        return graph
    }
}


public final class GraphNode {

    public var id: String

    public var inEdges: [GraphEdge] = []

    public var outEdges: [GraphEdge] = []

    public var edges: [GraphEdge] = []

    // PORT-NOTE: upstream `hostGraph: Graph` is set right after construction (addNode/clone);
    //   implicitly-unwrapped so the proxy accessors can reach `hostGraph.data`.
    public unowned var hostGraph: Graph!

    public var dataIndex: Int = -1

    // Used in traverse of Graph
    // upstream `__visited: boolean;` (uninitialized) — defaulted to false.
    public var __visited: Bool = false

    // constructor(id?: string, dataIndex?: number)
    public init(_ id: String? = nil, _ dataIndex: Int? = nil) {
        // this.id = id == null ? '' : id;
        self.id = id ?? ""
        // this.dataIndex = dataIndex == null ? -1 : dataIndex;
        self.dataIndex = dataIndex ?? -1
    }

    public func degree() -> Int {
        return self.edges.count
    }

    public func inDegree() -> Int {
        return self.inEdges.count
    }

    public func outDegree() -> Int {
        return self.outEdges.count
    }

    // getModel<T>(path?: string): Model
    public func getModel(_ path: String? = nil) -> Model? {
        if self.dataIndex < 0 {
            return nil
        }
        let graph = self.hostGraph!
        let itemModel = graph.data.getItemModel(self.dataIndex)
        if let path = path {
            return itemModel.getModel(path)
        }
        return itemModel.getModel()
    }

    public func getAdjacentDataIndices() -> GraphDataIndices {
        var dataIndices = GraphDataIndices(node: [], edge: [])
        for i in 0..<self.edges.count {
            let adjacentEdge = self.edges[i]
            if adjacentEdge.dataIndex < 0 {
                continue
            }
            dataIndices.edge.append(adjacentEdge.dataIndex)
            dataIndices.node.append(adjacentEdge.node1.dataIndex)
            dataIndices.node.append(adjacentEdge.node2.dataIndex)
        }
        return dataIndices
    }

    public func getTrajectoryDataIndices() -> GraphDataIndices {
        let connectedEdgesMap: HashMap<Bool> = createHashMap()
        let connectedNodesMap: HashMap<Bool> = createHashMap()

        for i in 0..<self.edges.count {
            let adjacentEdge = self.edges[i]
            if adjacentEdge.dataIndex < 0 {
                continue
            }

            connectedEdgesMap.set(adjacentEdge.dataIndex, true)

            var sourceNodesQueue: [GraphNode] = [adjacentEdge.node1]
            var targetNodesQueue: [GraphNode] = [adjacentEdge.node2]

            var nodeIteratorIndex = 0
            while nodeIteratorIndex < sourceNodesQueue.count {
                let sourceNode = sourceNodesQueue[nodeIteratorIndex]
                nodeIteratorIndex += 1
                connectedNodesMap.set(sourceNode.dataIndex, true)

                let sourceNodeInEdges = sourceNode.inEdges
                for j in 0..<sourceNodeInEdges.count {
                    let inEdge = sourceNodeInEdges[j]
                    let inEdgeDataIndex = inEdge.dataIndex
                    if inEdgeDataIndex >= 0 && !connectedEdgesMap.hasKey(inEdgeDataIndex) {
                        connectedEdgesMap.set(inEdgeDataIndex, true)
                        sourceNodesQueue.append(inEdge.node1)
                    }
                }
            }

            nodeIteratorIndex = 0
            while nodeIteratorIndex < targetNodesQueue.count {
                let targetNode = targetNodesQueue[nodeIteratorIndex]
                nodeIteratorIndex += 1
                connectedNodesMap.set(targetNode.dataIndex, true)

                let targetNodeOutEdges = targetNode.outEdges
                for j in 0..<targetNodeOutEdges.count {
                    let outEdge = targetNodeOutEdges[j]
                    let outEdgeDataIndex = outEdge.dataIndex
                    if outEdgeDataIndex >= 0 && !connectedEdgesMap.hasKey(outEdgeDataIndex) {
                        connectedEdgesMap.set(outEdgeDataIndex, true)
                        targetNodesQueue.append(outEdge.node2)
                    }
                }
            }
        }

        return GraphDataIndices(
            // upstream reads these from a JS object via `keys()`, which enumerates integer keys in
            //   ascending numeric order; the HashMap shim preserves insertion order, so sort to match.
            node: connectedNodesMap.keys().compactMap { Int($0) }.sorted(),
            edge: connectedEdgesMap.keys().compactMap { Int($0) }.sorted()
        )
    }

    // Returns the adjacency list matching a breadthFirstTraverse `edgeType` string.
    fileprivate func edgesForType(_ edgeType: String) -> [GraphEdge] {
        switch edgeType {
        case "inEdges": return self.inEdges
        case "outEdges": return self.outEdges
        default: return self.edges
        }
    }

    // ---- createGraphDataProxyMixin('hostGraph', 'data') ----
    // PORT NOTE: upstream mixes these accessors onto GraphNode (dataName='data'); Swift has no
    //   prototype mixin, so they are implemented directly against `hostGraph.data`.

    // getValue(dimension?: DimensionLoose): ParsedValue
    public func getValue(_ dimension: DimensionLoose? = nil) -> ParsedValue {
        let data: SeriesData = self.hostGraph.data
        // data.getStore().get(data.getDimensionIndex(dimension || 'value'), this.dataIndex)
        let dim: DimensionLoose = jsTruthy(dimension) ? dimension! : "value"
        return data.getStore().get(data.getDimensionIndex(dim), self.dataIndex)
    }

    // setVisual(key: string | Dictionary<any>, value?: any)
    public func setVisual(_ key: String, _ value: Any?) {
        if self.dataIndex >= 0 {
            self.hostGraph.data.setItemVisual(self.dataIndex, key, value)
        }
    }
    public func setVisual(_ obj: [String: Any]) {
        if self.dataIndex >= 0 {
            self.hostGraph.data.setItemVisual(self.dataIndex, obj)
        }
    }

    public func getVisual(_ key: String) -> Any? {
        return self.hostGraph.data.getItemVisual(self.dataIndex, key)
    }

    public func setLayout(_ layout: Any?, _ merge: Bool? = nil) {
        if self.dataIndex >= 0 {
            self.hostGraph.data.setItemLayout(self.dataIndex, layout, merge ?? false)
        }
    }

    public func getLayout() -> Any? {
        return self.hostGraph.data.getItemLayout(self.dataIndex)
    }

    public func getGraphicEl() -> Element? {
        return self.hostGraph.data.getItemGraphicEl(self.dataIndex)
    }

    public func getRawIndex() -> Int {
        return self.hostGraph.data.getRawIndex(self.dataIndex)
    }
}


public final class GraphEdge {
    /**
     * The first node. If directed graph, it represents the source node.
     */
    public unowned var node1: GraphNode
    /**
     * The second node. If directed graph, it represents the target node.
     */
    public unowned var node2: GraphNode

    public var dataIndex: Int = -1

    // PORT-NOTE: upstream `hostGraph: Graph` is set right after construction; implicitly-unwrapped.
    public unowned var hostGraph: Graph!

    // constructor(n1: GraphNode, n2: GraphNode, dataIndex?: number)
    public init(_ n1: GraphNode, _ n2: GraphNode, _ dataIndex: Int? = nil) {
        self.node1 = n1
        self.node2 = n2
        self.dataIndex = dataIndex ?? -1
    }

    // getModel<T>(path?: string): Model
    public func getModel(_ path: String? = nil) -> Model? {
        if self.dataIndex < 0 {
            return nil
        }
        let graph = self.hostGraph!
        let itemModel = graph.edgeData.getItemModel(self.dataIndex)
        if let path = path {
            return itemModel.getModel(path)
        }
        return itemModel.getModel()
    }

    public func getAdjacentDataIndices() -> GraphDataIndices {
        return GraphDataIndices(
            node: [self.node1.dataIndex, self.node2.dataIndex],
            edge: [self.dataIndex]
        )
    }

    public func getTrajectoryDataIndices() -> GraphDataIndices {
        let connectedEdgesMap: HashMap<Bool> = createHashMap()
        let connectedNodesMap: HashMap<Bool> = createHashMap()

        connectedEdgesMap.set(self.dataIndex, true)

        var sourceNodes: [GraphNode] = [self.node1]
        var targetNodes: [GraphNode] = [self.node2]

        var nodeIteratorIndex = 0
        while nodeIteratorIndex < sourceNodes.count {
            let sourceNode = sourceNodes[nodeIteratorIndex]
            nodeIteratorIndex += 1

            connectedNodesMap.set(sourceNode.dataIndex, true)

            let sourceNodeInEdges = sourceNode.inEdges
            for j in 0..<sourceNodeInEdges.count {
                let inEdge = sourceNode.inEdges[j]
                let inEdgeDataIndex = inEdge.dataIndex
                if inEdgeDataIndex >= 0 && !connectedEdgesMap.hasKey(inEdgeDataIndex) {
                    connectedEdgesMap.set(inEdgeDataIndex, true)
                    sourceNodes.append(inEdge.node1)
                }
            }
        }

        nodeIteratorIndex = 0
        while nodeIteratorIndex < targetNodes.count {
            let targetNode = targetNodes[nodeIteratorIndex]
            nodeIteratorIndex += 1

            connectedNodesMap.set(targetNode.dataIndex, true)

            let targetNodeOutEdges = targetNode.outEdges
            for j in 0..<targetNodeOutEdges.count {
                let outEdge = targetNode.outEdges[j]
                let outEdgeDataIndex = outEdge.dataIndex
                if outEdgeDataIndex >= 0 && !connectedEdgesMap.hasKey(outEdgeDataIndex) {
                    connectedEdgesMap.set(outEdgeDataIndex, true)
                    targetNodes.append(outEdge.node2)
                }
            }
        }

        return GraphDataIndices(
            // upstream reads these from a JS object via `keys()`, which enumerates integer keys in
            //   ascending numeric order; the HashMap shim preserves insertion order, so sort to match.
            node: connectedNodesMap.keys().compactMap { Int($0) }.sorted(),
            edge: connectedEdgesMap.keys().compactMap { Int($0) }.sorted()
        )
    }

    // ---- createGraphDataProxyMixin('hostGraph', 'edgeData') ----
    // PORT NOTE: upstream mixes these accessors onto GraphEdge (dataName='edgeData'); implemented
    //   directly against `hostGraph.edgeData`.

    public func getValue(_ dimension: DimensionLoose? = nil) -> ParsedValue {
        let data: SeriesData = self.hostGraph.edgeData
        let dim: DimensionLoose = jsTruthy(dimension) ? dimension! : "value"
        return data.getStore().get(data.getDimensionIndex(dim), self.dataIndex)
    }

    public func setVisual(_ key: String, _ value: Any?) {
        if self.dataIndex >= 0 {
            self.hostGraph.edgeData.setItemVisual(self.dataIndex, key, value)
        }
    }
    public func setVisual(_ obj: [String: Any]) {
        if self.dataIndex >= 0 {
            self.hostGraph.edgeData.setItemVisual(self.dataIndex, obj)
        }
    }

    public func getVisual(_ key: String) -> Any? {
        return self.hostGraph.edgeData.getItemVisual(self.dataIndex, key)
    }

    public func setLayout(_ layout: Any?, _ merge: Bool? = nil) {
        if self.dataIndex >= 0 {
            self.hostGraph.edgeData.setItemLayout(self.dataIndex, layout, merge ?? false)
        }
    }

    public func getLayout() -> Any? {
        return self.hostGraph.edgeData.getItemLayout(self.dataIndex)
    }

    public func getGraphicEl() -> Element? {
        return self.hostGraph.edgeData.getItemGraphicEl(self.dataIndex)
    }

    public func getRawIndex() -> Int {
        return self.hostGraph.edgeData.getRawIndex(self.dataIndex)
    }
}

// ---- port-local helpers (not part of upstream Graph.ts) ----

// JS `'' + x` string coercion for the `string | number` id / node arguments.
private func jsPlus(_ v: Any?) -> String {
    switch v {
    case nil: return "undefined"
    case is NSNull: return "null"
    case let s as String: return s
    case let i as Int: return String(i)
    case let d as Double:
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: v!)
    }
}

// Extract an Int index from a JS `number` argument (Int or Double).
private func asInt(_ v: Any?) -> Int {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    return -1
}

// Mirrors JavaScript truthiness for a `boolean | void` callback result (nil / NSNull / false /
// 0 / NaN / "" are falsy).
private func jsBool(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// Mirrors JS `dimension || 'value'` falsy fall-through (see TreeNode.getValue).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
