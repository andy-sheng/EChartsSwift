// Ported from echarts/src/chart/tree/TreeSeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import Tree from '../../data/Tree';                              -> Tree / TreeNode (data/Tree.swift — the
//       sibling tree-data track). This file references `Tree.createTree`, `tree.data`,
//       `tree.getNodeByDataIndex`, `tree.root`, `tree.eachNode`, `node.depth`, `node.isExpand`,
//       `node.getValue`, `node.parentNode`.
//   import { ... } from '../../util/types';                         -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2.
//   import SeriesData from '../../data/SeriesData';                 -> SeriesData (data/SeriesData.swift).
//   import View from '../../coord/View';
//       -> View (coord/View.swift, ported); the tree's box coordinate system is still not wired here, so
//          the `coordinateSystem` slot is inherited from SeriesModel typed `Any?`.
//   import { LayoutRect } from '../../util/layout';                 -> `LayoutRect` (== BoundingRect).
//   import Model from '../../model/Model';                          -> Model (model/Model.swift).
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> createTooltipMarkup (component/tooltip/tooltipMarkup.swift, ported); tree's use is deferred with getDataParams.
//   import { wrapTreePathInfo } from '../helper/treeHelper';
//       -> treeHelper.wrapTreePathInfo (chart/helper/treeHelper.swift, fully ported); consumed by the
//          `getDataParams` override below, still blocked on util/types.CallbackDataParams.treeFields.
//   import tokens from '../../visual/tokens';
//       -> visual/tokens.ts IS ported (visual/tokens.swift); the single consumed value `tokens.color.borderTint`
//          (= color.neutral20 = '#cfd2d7') is inlined verbatim in `defaultOption` below.

// ============================================================================
// The upstream `interface`/`type` declarations (CurveLineStyleOption, TreeSeriesStateOption,
// TreeStatesMixin, TreeSeriesNodeItemOption, TreeSeriesLeavesOption, TreeSeriesOption, TreeAncestors,
// TreeSeriesCallbackDataParams) describe the (dynamic) option tree. Per CONVENTIONS §2 the option tree
// is the `[String: Any]` bag; these types are kept as documentation only — no Swift types are emitted.
// ============================================================================

// PORT-NOTE: TreeNode `depth`/`dataIndex` are `number` upstream; the sibling data/Tree.swift tracks
//   `depth: Double` and `dataIndex: Int`. Float-math uses of `depth` stay `Double`; array-index uses
//   wrap in `Int(...)` (language difference, semantically equivalent).

// export const SERIES_TYPE_TREE = 'tree';
public let SERIES_TYPE_TREE = "tree"

// upstream: class TreeSeriesModel extends SeriesModel<TreeSeriesOption> implements RoamHostModel
open class TreeSeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_TREE;
    // readonly type = TreeSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_TREE }

    // can support the position parameters 'left', 'top','right','bottom', 'width',
    // 'height' in the setOption() with 'merge' mode normal.
    // static readonly layoutMode = 'box';
    public override class var layoutMode: Any? { return "box" }

    // coordinateSystem: View;
    //   Inherited from SeriesModel (`open var coordinateSystem: Any?`); upstream types it `View`.

    // layoutInfo: LayoutRect;
    //   A field slot populated by the tree layout stage (treeLayout). PORT-NOTE: LayoutRect == BoundingRect (typealias).
    open var layoutInfo: LayoutRect?

    // hasSymbolVisual = true;
    //   (class-field default; overrides the SeriesModel `false`.)
    open override var hasSymbolVisual: Bool {
        get { true }
        set { /* class-field default upstream */ }
    }

    // Do it self.
    // ignoreStyleOnData = true;
    open override var ignoreStyleOnData: Bool {
        get { true }
        set { /* class-field default upstream */ }
    }

    /**
     * Init a tree data structure from data in option series
     */
    // upstream: getInitialData(option: TreeSeriesOption): SeriesData  (ignores ecModel param).
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // create a virtual root
        // const root: TreeSeriesNodeItemOption = { name: option.name, children: option.data };
        var root: [String: Any] = [:]
        if let name = opt?["name"] {
            root["name"] = name
        }
        // `option.data` may be nil; assigning nil removes the key (JS `children: undefined`).
        root["children"] = opt?["data"]

        // const leaves = option.leaves || {};
        //   JS `||` falls through on a falsy `leaves` (nil / {} is truthy, only nil/undefined here);
        //   an empty bag is the fallback.
        let leaves = (opt?["leaves"] as? [String: Any]) ?? [:]
        // const leavesModel = new Model(leaves, this, this.ecModel);
        let leavesModel = Model(leaves, self, ecModel)

        // const tree = Tree.createTree(root, this, beforeLink);
        var treeRef: Tree! = nil

        // function beforeLink(nodeData: SeriesData) {
        //     nodeData.wrapMethod('getItemModel', function (model, idx) {
        //         const node = tree.getNodeByDataIndex(idx);
        //         if (!(node && node.children.length && node.isExpand)) {
        //             model.parentModel = leavesModel;
        //         }
        //         return model;
        //     });
        // }
        // PORT-NOTE: Swift cannot rebind a method by string name the way upstream's `wrapMethod` does, so
        //   `wrapMethod('getItemModel', fn)` stores `fn` in SeriesData's dedicated `_getItemModelInjections`
        //   list (see data/SeriesData.swift) and `getItemModel(idx)` threads its result through each stored
        //   injection. This closure IS therefore invoked on every `getItemModel` call, so the leaves-model
        //   parenting takes effect (leaf nodes inherit `leaves` itemStyle/label/lineStyle). The injection is
        //   also carried across `cloneShallow` via `transferProperties`, matching upstream's wrap chain.
        let beforeLink: (SeriesData) -> Void = { nodeData in
            nodeData.wrapMethod("getItemModel") { args in
                let model = args.first as? Model
                let idx = Int((args.count > 1 ? (args[1] as? Double) : nil) ?? 0)
                let node = treeRef.getNodeByDataIndex(idx)
                // if (!(node && node.children.length && node.isExpand))
                let expandedBranch = (node != nil) && (node!.children.count > 0) && node!.isExpand
                if !expandedBranch {
                    model?.parentModel = leavesModel
                }
                return model
            }
        }

        let tree = Tree.createTree(root, self, beforeLink)
        treeRef = tree

        // let treeDepth = 0;
        var treeDepth: Double = 0

        // tree.eachNode('preorder', function (node) { if (node.depth > treeDepth) { treeDepth = node.depth; } });
        tree.eachNode("preorder", { (node: TreeNode) -> Any? in
            if node.depth > treeDepth {
                treeDepth = node.depth
            }
            return nil
        })

        // const expandAndCollapse = option.expandAndCollapse;
        let expandAndCollapse = opt?["expandAndCollapse"]
        // const expandTreeDepth = (expandAndCollapse && option.initialTreeDepth >= 0)
        //     ? option.initialTreeDepth : treeDepth;
        //   JS `option.initialTreeDepth >= 0` is false when it is undefined (`undefined >= 0` -> false).
        let initialTreeDepth = opt?["initialTreeDepth"] as? Double
        let expandTreeDepth: Double
        if jsTruthy(expandAndCollapse), let itd = initialTreeDepth, itd >= 0 {
            expandTreeDepth = itd
        }
        else {
            expandTreeDepth = treeDepth
        }

        // tree.root.eachNode('preorder', function (node) { ... });
        tree.root.eachNode("preorder", { (node: TreeNode) -> Any? in
            // const item = node.hostTree.data.getRawDataItem(node.dataIndex) as TreeSeriesNodeItemOption;
            let item = node.hostTree.data.getRawDataItem(node.dataIndex)
            // Add item.collapsed != null, because users can collapse node original in the series.data.
            // node.isExpand = (item && item.collapsed != null) ? !item.collapsed : node.depth <= expandTreeDepth;
            if let itemDict = item as? [String: Any], let collapsed = itemDict["collapsed"], !(collapsed is NSNull) {
                node.isExpand = !jsTruthy(collapsed)
            }
            else {
                node.isExpand = node.depth <= expandTreeDepth
            }
            return nil
        })

        return tree.data
    }

    /**
     * Make the configuration 'orient' backward compatibly, with 'horizontal = LR', 'vertical = TB'.
     * @returns {string} orient
     */
    // getOrient() { let orient = this.get('orient'); ... return orient; }
    open func getOrient() -> String? {
        var orient = self.get("orient") as? String
        if orient == "horizontal" {
            orient = "LR"
        }
        else if orient == "vertical" {
            orient = "TB"
        }
        return orient
    }

    // formatTooltip(dataIndex, multipleSeries, dataType) { ... createTooltipMarkup('nameValue', {...}) }
    //   Faithful upstream body: walk the parent chain from the node up to the real root, joining
    //   names with '.', then emit a 'nameValue' markup block. `createTooltipMarkup` is now ported
    //   (component/tooltip/tooltipMarkup.swift).
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        _ = (multipleSeries, dataType)
        // const tree = this.getData().tree;
        guard let tree = self.getData().tree else {
            return nil
        }
        // const realRoot = tree.root.children[0];
        let realRoot = tree.root.children.first
        // let node = tree.getNodeByDataIndex(dataIndex);
        var node = tree.getNodeByDataIndex(Int(dataIndex))
        // const value = node.getValue();
        let value = node?.getValue()
        // let name = node.name;
        var name = node?.name ?? ""
        // while (node && (node !== realRoot)) { name = node.parentNode.name + '.' + name; node = node.parentNode; }
        while let n = node, n !== realRoot {
            name = (n.parentNode?.name ?? "") + "." + name
            node = n.parentNode
        }
        // noValue: isNaN(value as number) || value == null
        let numericValue = (value as? Double) ?? (value as? Int).map(Double.init)
        let noValue = numericValue.map { $0.isNaN } ?? true
        return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
            name: name,
            value: value,
            noValue: noValue
        ))
    }

    // Add tree path to tooltip param
    // getDataParams(dataIndex) { const params = super.getDataParams(...); params.treeAncestors = wrapTreePathInfo(node, this); params.collapsed = !node.isExpand; return params; }
    // PORT-TODO (blocked on util/types.CallbackDataParams.treeFields): `treeHelper.wrapTreePathInfo` IS
    //   fully ported (chart/helper/treeHelper.swift) and `super.getDataParams` IS available
    //   (model/Series.swift). The only remaining blocker is `CallbackDataParams` gaining the optional
    //   `treeAncestors` / `collapsed` slots. Wire the body below as soon as those fields land:
    //     const params = super.getDataParams.apply(this, arguments) as TreeSeriesCallbackDataParams;
    //     const node = this.getData().tree.getNodeByDataIndex(dataIndex);
    //     params.treeAncestors = wrapTreePathInfo(node, this);
    //     params.collapsed = !node.isExpand;
    //     return params;

    // __ownRoamView() { return this.coordinateSystem; }
    //   Part of the `RoamHostModel` interface. PORT-NOTE (deferred): requires the View coord-sys + roam
    //   (RoamController) modules; the `coordinateSystem` slot is `Any?`.
    open func __ownRoamView() -> Any? {
        return self.coordinateSystem
    }

    // static defaultOption: TreeSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            // `coordinateSystem` can be declared as 'matrix', 'calendar',
            //  which provides box layout container.
            "coordinateSystemUsage": "box",

            // the position of the whole view
            "left": "12%",
            "top": "12%",
            "right": "12%",
            "bottom": "12%",

            // the layout of the tree, two value can be selected, 'orthogonal' or 'radial'
            "layout": "orthogonal",

            // value can be 'polyline'
            "edgeShape": "curve",

            "edgeForkPosition": "50%",

            // true | false | 'move' | 'scale', see module:component/helper/RoamController.
            "roam": false,
            "roamTrigger": "global",

            // Symbol size scale ratio in roam
            "nodeScaleRatio": 0.4,

            // Default on center of graph
            // PORT-NOTE: upstream value is `null`; NSNull() retains the key in the [String: Any] bag
            //   (the codebase convention for a null-valued default option — consumers treat NSNull as null).
            "center": NSNull(),

            "zoom": 1.0,

            "orient": "LR",

            "symbol": "emptyCircle",

            "symbolSize": 7.0,

            "expandAndCollapse": true,

            "initialTreeDepth": 2.0,

            "lineStyle": [
                "color": "#cfd2d7",  // upstream: tokens.color.borderTint (= color.neutral20)
                "width": 1.5,
                "curveness": 0.5
            ] as [String: Any],

            "itemStyle": [
                "color": "lightsteelblue",
                // borderColor: '#c23531',
                "borderWidth": 1.5
            ] as [String: Any],

            "label": [
                "show": true
            ] as [String: Any],

            "animationEasing": "linear",

            "animationDuration": 700.0,

            "animationDurationUpdate": 500.0
        ] as [String: Any]
    }
}

// export default TreeSeriesModel;  -> `open class TreeSeriesModel` above.

// Mirrors JavaScript `||`/`&&` truthiness for a dynamic `Any?` value (nil / NSNull / false / 0 / NaN /
// "" are falsy). Used for `expandAndCollapse` and `!item.collapsed`. File-private per port convention.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
