// Ported from echarts/src/data/Tree.ts — keep in sync with upstream
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

/**
 * Tree data structure
 */

import Foundation
import ZRenderKit

// upstream imports (reused from sibling/ZRenderKit ports where available):
//   import * as zrUtil from 'zrender/src/core/util';               -> ZRenderKit.util
//   import Model from '../model/Model';                            -> model/Model.swift
//   import linkSeriesData from './helper/linkSeriesData';          -> sibling data/helper/linkSeriesData.swift
//   import SeriesData from './SeriesData';                         -> sibling data/SeriesData.swift
//   import prepareSeriesDataSchema from './helper/createDimensions';  -> createDimensions.prepareSeriesDataSchema
//   import { DimensionLoose, ParsedValue, OptionDataValue, OptionDataItemObject } from '../util/types';  -> util/types.swift
//   import { Dictionary } from 'zrender/src/core/types';           -> [String: Any]
//   import { convertOptionIdName } from '../util/model';           -> model.convertOptionIdName

// type TreeTraverseOrder = 'preorder' | 'postorder';
public typealias TreeTraverseOrder = String
// type TreeTraverseCallback<Ctx> = (this: Ctx, node: TreeNode) => boolean | void;
// PORT-NOTE: upstream returns `boolean | void`; modeled as `Any?` (a `Bool` -> suppress subtree,
//   `nil`/void -> continue). The `this: Ctx` binding is dropped: Swift closures capture context
//   directly, so the trailing `context` parameter (kept for fidelity) is unused by the closure.
public typealias TreeTraverseCallback = (TreeNode) -> Any?
// type TreeTraverseOption = { order?: TreeTraverseOrder; attr?: 'children' | 'viewChildren' };
//   -> a dynamic option bag `[String: Any]` (CONVENTIONS §2).

// interface TreeNodeOption extends Pick<OptionDataItemObject<OptionDataValue>, 'name' | 'value'> {
//     children?: TreeNodeOption[];
// }
// PORT-NOTE: the `{name, value, children}` node option is modeled as a dynamic bag `[String: Any]`.
public typealias TreeNodeOption = [String: Any]

public final class TreeNode {
    public var name: String

    public var depth: Double = 0

    public var height: Double = 0

    // PORT-NOTE: upstream declares `parentNode: TreeNode` (non-optional) but leaves it undefined
    //   for the root and relies on `while (node)`; modeled as Optional.
    public var parentNode: TreeNode?
    /**
     * Reference to list item.
     * Do not persistent dataIndex outside,
     * besause it may be changed by list.
     * If dataIndex -1,
     * this node is logical deleted (filtered) in list.
     */
    // PORT-NOTE: upstream types `dataIndex: number`; kept `Int` here because every consumer
    //   (SeriesData.getRawIndex/getId/getItemModel/getItemLayout/setItemLayout/…) is Int-indexed.
    public var dataIndex: Int = -1

    public var children: [TreeNode] = []

    public var viewChildren: [TreeNode] = []

    public var isExpand: Bool = false

    public let hostTree: Tree

    public init(_ name: String, _ hostTree: Tree) {
        // this.name = name || '';
        self.name = name.isEmpty ? "" : name

        self.hostTree = hostTree
    }
    /**
     * The node is removed.
     */
    public func isRemoved() -> Bool {
        return self.dataIndex < 0
    }

    /**
     * Travel this subtree (include this node).
     * Usage:
     *    node.eachNode(function () { ... }); // preorder
     *    node.eachNode('preorder', function () { ... }); // preorder
     *    node.eachNode('postorder', function () { ... }); // postorder
     *    node.eachNode(
     *        {order: 'postorder', attr: 'viewChildren'},
     *        function () { ... }
     *    ); // postorder
     *
     * @param options If string, means order.
     * @param options.order 'preorder' or 'postorder'
     * @param options.attr 'children' or 'viewChildren'
     * @param cb If in preorder and return false,
     *                      its subtree will not be visited.
     */
    // upstream overloads collapse into one implementation dispatching on the runtime type of
    // `options` (order string | option bag | callback).
    public func eachNode(_ options: Any?, _ cb: Any? = nil, _ context: Any? = nil) {
        var options = options
        var cb = cb
        var context = context

        if util.isFunction(options) {
            context = cb
            cb = options
            options = nil
        }

        // options = options || {};
        var opts: [String: Any] = [:]
        if let o = options {
            // if (zrUtil.isString(options)) { options = {order: options}; }
            if util.isString(o) {
                opts = ["order": o]
            }
            else if let d = o as? [String: Any] {
                opts = d
            }
        }

        let order = (opts["order"] as? String) ?? "preorder"
        // const children = this[(options as TreeTraverseOption).attr || 'children'];
        let attr = (opts["attr"] as? String) ?? "children"
        let children: [TreeNode] = (attr == "viewChildren") ? self.viewChildren : self.children

        let callback = cb as! TreeTraverseCallback

        var suppressVisitSub: Any?
        // order === 'preorder' && (suppressVisitSub = cb.call(context, this));
        if order == "preorder" {
            suppressVisitSub = callback(self)
        }
        let suppress = (suppressVisitSub as? Bool) == true

        var i = 0
        while !suppress && i < children.count {
            children[i].eachNode(opts, cb, context)
            i += 1
        }

        // order === 'postorder' && cb.call(context, this);
        if order == "postorder" {
            _ = callback(self)
        }
    }

    /**
     * Update depth and height of this subtree.
     */
    public func updateDepthAndHeight(_ depth: Double) {
        var height: Double = 0
        self.depth = depth
        for i in 0..<self.children.count {
            let child = self.children[i]
            child.updateDepthAndHeight(depth + 1)
            if child.height > height {
                height = child.height
            }
        }
        self.height = height + 1
    }

    public func getNodeById(_ id: String) -> TreeNode? {
        if self.getId() == id {
            return self
        }
        let children = self.children
        let len = children.count
        for i in 0..<len {
            let res = children[i].getNodeById(id)
            if res != nil {
                return res
            }
        }
        return nil
    }

    public func contains(_ node: TreeNode) -> Bool {
        if node === self {
            return true
        }
        let children = self.children
        let len = children.count
        for i in 0..<len {
            let res = children[i].contains(node)
            if res {
                return res
            }
        }
        return false
    }

    /**
     * @param includeSelf Default false.
     * @return order: [root, child, grandchild, ...]
     */
    public func getAncestors(_ includeSelf: Bool? = nil) -> [TreeNode] {
        var ancestors: [TreeNode] = []
        var node: TreeNode? = (includeSelf ?? false) ? self : self.parentNode
        while let n = node {
            ancestors.append(n)
            node = n.parentNode
        }
        ancestors.reverse()
        return ancestors
    }

    public func getAncestorsIndices() -> [Int] {
        var indices: [Int] = []
        var currNode: TreeNode? = self
        while let n = currNode {
            indices.append(n.dataIndex)
            currNode = n.parentNode
        }
        indices.reverse()
        return indices
    }

    public func getDescendantIndices() -> [Int] {
        var indices: [Int] = []
        self.eachNode({ (childNode: TreeNode) -> Any? in
            indices.append(childNode.dataIndex)
            return nil
        })
        return indices
    }

    public func getValue(_ dimension: DimensionLoose? = nil) -> ParsedValue {
        let data: SeriesData = self.hostTree.data   // annotate: IUO bound to a `let` would infer Optional
        // data.getStore().get(data.getDimensionIndex(dimension || 'value'), this.dataIndex)
        //   JS `||` treats a falsy `dimension` (nil / 0 / "") as absent → default to "value";
        //   Swift `??` only substitutes nil, so use jsTruthy to match the falsy fall-through.
        let dim: DimensionLoose = jsTruthy(dimension) ? dimension! : "value"
        return data.getStore().get(data.getDimensionIndex(dim), self.dataIndex)
    }

    public func setLayout(_ layout: Any?, _ merge: Bool? = nil) {
        // this.dataIndex >= 0 && this.hostTree.data.setItemLayout(this.dataIndex, layout, merge);
        if self.dataIndex >= 0 {
            self.hostTree.data.setItemLayout(self.dataIndex, layout, merge ?? false)
        }
    }

    /**
     * @return {Object} layout
     */
    public func getLayout() -> Any? {
        return self.hostTree.data.getItemLayout(self.dataIndex)
    }

    // getModel<T = unknown>(): Model<T>;
    // getModel<T = unknown>(path?: string): Model {...}
    public func getModel(_ path: String? = nil) -> Model? {
        if self.dataIndex < 0 {
            return nil
        }
        let hostTree = self.hostTree
        let itemModel = hostTree.data.getItemModel(self.dataIndex)
        // Faithful port of the TreemapSeries `beforeLink` `wrapMethod('getItemModel')` injection
        // (upstream reassigns `model.parentModel = levelModels[node.depth] || designatedVisualModel`).
        // The port's `SeriesData.getItemModel` does not invoke wrapMethod injections, so the per-depth
        // level-model parenting is applied here instead: the freshly-created item model is reparented
        // onto its depth's level model so `levels[n]` config (color / colorMappingBy / itemStyle
        // borderWidth·gapWidth·borderColor(Saturation) / upperLabel) is inherited through the chain.
        // Only TreemapSeriesModel populates `hostTree.levelModels`; tree/sunburst leave it nil (they use
        // their own `_levelModels`), so their node models are untouched by this branch.
        if let levelModels = hostTree.levelModels {
            let idx = Int(self.depth)
            if idx >= 0 && idx < levelModels.count {
                itemModel.parentModel = levelModels[idx]
            }
            else if let designated = hostTree.designatedVisualModel {
                // Depth beyond the configured levels: fall back to the designated-visual model
                // (whose own parent is the series), mirroring `levelModels[depth] || designatedVisualModel`.
                itemModel.parentModel = designated
            }
        }
        if let path = path {
            return itemModel.getModel(path)
        }
        return itemModel.getModel()
    }

    // TODO: TYPE More specific model
    public func getLevelModel() -> Model? {
        // (this.hostTree.levelModels || [])[this.depth]
        let levelModels = self.hostTree.levelModels ?? []
        let idx = Int(self.depth)
        return (idx >= 0 && idx < levelModels.count) ? levelModels[idx] : nil
    }

    /**
     * @example
     *  setItemVisual('color', color);
     *  setItemVisual({
     *      'color': color
     *  });
     */
    // TODO: TYPE
    // setVisual(key: string, value: any): void;
    public func setVisual(_ key: String, _ value: Any?) {
        // this.dataIndex >= 0 && this.hostTree.data.setItemVisual(this.dataIndex, key, value);
        if self.dataIndex >= 0 {
            self.hostTree.data.setItemVisual(self.dataIndex, key, value)
        }
    }
    // setVisual(obj: Dictionary<any>): void;
    public func setVisual(_ obj: [String: Any]) {
        if self.dataIndex >= 0 {
            self.hostTree.data.setItemVisual(self.dataIndex, obj)
        }
    }

    /**
     * Get item visual
     * FIXME: make return type better
     */
    public func getVisual(_ key: String) -> Any? {
        return self.hostTree.data.getItemVisual(self.dataIndex, key)
    }

    public func getRawIndex() -> Int {
        return self.hostTree.data.getRawIndex(self.dataIndex)
    }

    public func getId() -> String {
        return self.hostTree.data.getId(self.dataIndex)
    }

    /**
     * index in parent's children
     */
    public func getChildIndex() -> Int {
        if let parentNode = self.parentNode {
            let children = parentNode.children
            for i in 0..<children.count {
                if children[i] === self {
                    return i
                }
            }
            return -1
        }
        return -1
    }

    /**
     * if this is an ancestor of another node
     *
     * @param node another node
     * @return if is ancestor
     */
    public func isAncestorOf(_ node: TreeNode) -> Bool {
        var parent = node.parentNode
        while let p = parent {
            if p === self {
                return true
            }
            parent = p.parentNode
        }
        return false
    }

    /**
     * if this is an descendant of another node
     *
     * @param node another node
     * @return if is descendant
     */
    public func isDescendantOf(_ node: TreeNode) -> Bool {
        return node !== self && node.isAncestorOf(self)
    }
}

// PORT-NOTE: upstream `Tree<HostModel extends Model = Model, LevelOption = any>` is generic; the
//   Swift port fixes `HostModel = Model` / `LevelOption = Any` since the generic parameters are
//   only surfaced through `hostModel`/`levelModels` typing.
public final class Tree: LinkableStruct {

    public let type: String = "tree"

    // PORT-NOTE: upstream `root: TreeNode` is set during createTree; modeled as implicitly-unwrapped.
    public var root: TreeNode!

    // PORT-NOTE: upstream `data: SeriesData` is assigned by linkSeriesData; implicitly-unwrapped.
    public var data: SeriesData!

    public var hostModel: Model

    public var levelModels: [Model]?

    // PORT-NOTE: the fallback parent for nodes deeper than the configured `levelModels` (upstream
    //   `levelModels[depth] || designatedVisualModel`). Only TreemapSeriesModel sets it; nil otherwise.
    public var designatedVisualModel: Model?

    private var _nodes: [TreeNode] = []

    public init(_ hostModel: Model) {
        self.hostModel = hostModel
    }
    /**
     * Travel this subtree (include this node).
     * Usage:
     *    node.eachNode(function () { ... }); // preorder
     *    node.eachNode('preorder', function () { ... }); // preorder
     *    node.eachNode('postorder', function () { ... }); // postorder
     *    node.eachNode(
     *        {order: 'postorder', attr: 'viewChildren'},
     *        function () { ... }
     *    ); // postorder
     *
     * @param options If string, means order.
     * @param options.order 'preorder' or 'postorder'
     * @param options.attr 'children' or 'viewChildren'
     * @param cb
     * @param context
     */
    public func eachNode(_ options: Any?, _ cb: Any? = nil, _ context: Any? = nil) {
        self.root.eachNode(options, cb, context)
    }

    public func getNodeByDataIndex(_ dataIndex: Int) -> TreeNode? {
        let rawIndex = self.data.getRawIndex(dataIndex)
        return (rawIndex >= 0 && rawIndex < self._nodes.count) ? self._nodes[rawIndex] : nil
    }

    public func getNodeById(_ name: String) -> TreeNode? {
        return self.root.getNodeById(name)
    }

    /**
     * Update item available by list,
     * when list has been performed options like 'filterSelf' or 'map'.
     */
    public func update() {
        let data = self.data!
        let nodes = self._nodes

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
    }

    /**
     * Clear all layouts
     */
    public func clearLayouts() {
        self.data.clearItemLayouts()
    }


    /**
     * data node format:
     * {
     *     name: ...
     *     value: ...
     *     children: [
     *         {
     *             name: ...
     *             value: ...
     *             children: ...
     *         },
     *         ...
     *     ]
     * }
     */
    public static func createTree(
        _ dataRoot: TreeNodeOption,
        _ hostModel: Model,
        _ beforeLink: ((SeriesData) -> Void)? = nil
    ) -> Tree {

        let tree = Tree(hostModel)
        var listData: [TreeNodeOption] = []
        var dimMax: Double = 1

        // buildHierarchy is a nested recursive function; captured `tree`/`listData`/`dimMax`.
        func buildHierarchy(_ dataNode: TreeNodeOption, _ parentNode: TreeNode?) {
            let value = dataNode["value"]
            dimMax = Swift.max(dimMax, util.isArray(value) ? Double((value as! [Any]).count) : 1)

            listData.append(dataNode)

            let node = TreeNode(model.convertOptionIdName(dataNode["name"], "") ?? "", tree)
            if let parentNode = parentNode {
                addChild(node, parentNode)
            }
            else {
                tree.root = node
            }

            tree._nodes.append(node)

            let children = dataNode["children"]
            if let children = children as? [Any] {
                for i in 0..<children.count {
                    // PORT-NOTE: upstream `dataNode.children` is typed `TreeNodeOption[]`; in Swift the
                    //   children arrive in the dynamic option bag as `[Any]`, so cast each element back
                    //   to `TreeNodeOption` (semantically equivalent to upstream's static typing).
                    buildHierarchy(children[i] as! TreeNodeOption, node)
                }
            }
        }

        buildHierarchy(dataRoot, nil)

        tree.root.updateDepthAndHeight(0)

        let schema = createDimensions.prepareSeriesDataSchema(
            listData,
            PrepareSeriesDataSchemaParams(
                coordDimensions: ["value"],
                dimensionsCount: dimMax
            )
        )
        let dimensions = schema.dimensions

        let list = SeriesData(dimensions, hostModel)
        list.initData(listData)

        beforeLink?(list)

        linkSeriesData.linkSeriesData(LinkSeriesDataOpt(
            mainData: list,
            struct: tree,
            structAttr: "tree"
        ))

        tree.update()

        return tree
    }

}

/**
 * It is needed to consider the mess of 'list', 'hostModel' when creating a TreeNote,
 * so this function is not ready and not necessary to be public.
 */
private func addChild(_ child: TreeNode, _ node: TreeNode) {
    // const children = node.children; (Swift arrays are value types, so append to node.children
    // directly rather than through an aliasing local.)
    if child.parentNode === node {
        return
    }

    node.children.append(child)   // children.push(child)
    child.parentNode = node
}

// Mirrors JavaScript `||`/`&&` truthiness for a dynamic `Any?` value (nil / NSNull / false /
// 0 / NaN / "" are falsy). Used by `TreeNode.getValue` to reproduce `dimension || 'value'`.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
