// Ported from echarts/src/chart/sunburst/SunburstSeries.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import Tree, { TreeNode } from '../../data/Tree';                -> Tree / TreeNode (data/Tree.swift — the
//       sibling tree-data track). This file references `Tree.createTree`, `tree.data`,
//       `tree.getNodeByDataIndex`, `tree.root`, `node.depth`, `node.contains(...)`.
//   import {wrapTreePathInfo} from '../helper/treeHelper';
//       -> treeHelper.wrapTreePathInfo (chart/helper/treeHelper.swift, fully ported); consumed by the
//          `getDataParams` override below.
//   import { ... } from '../../util/types';                          -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2.
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import Model from '../../model/Model';                           -> Model (model/Model.swift).
//   import enableAriaDecalForTree from '../helper/enableAriaDecalForTree';
//       -> `enableAriaDecalForTree` (chart/helper/enableAriaDecalForTree.swift).

// ============================================================================
// The upstream `interface`/`type` declarations (SunburstItemStyleOption, SunburstLabelOption,
// SunburstDataParams, SunburstStatesMixin, SunburstStateOption, SunburstSeriesNodeItemOption,
// SunburstSeriesLevelOption, SortParam, SunburstSeriesOption, the `interface SunburstSeriesModel`
// declaration-merge) describe the (dynamic) option tree. Per CONVENTIONS §2 the option tree is the
// `[String: Any]` bag; these types are kept as documentation only — no Swift types are emitted, except
// `SortParam` which is materialized (below) because the `sort` callback consumes it by value.
// ============================================================================

// TreeNode `depth`/`height`/`dataIndex` are `number` upstream. The exact Swift numeric type
//   (Int vs Double) is owned by the sibling data/Tree.swift track. To stay build-robust regardless of
//   that choice, every float-math use here wraps the metric in `Double(...)` and every array-index use
//   wraps it in `Int(...)` (both compile whether the source is Int or Double). Integrate reconciles.

// export const SERIES_TYPE_SUNBURST = 'sunburst';
public let SERIES_TYPE_SUNBURST = "sunburst"

// upstream: class SunburstSeriesModel extends SeriesModel<SunburstSeriesOption>
open class SunburstSeriesModel: SeriesModel {

    // static readonly type = 'series.' + SERIES_TYPE_SUNBURST;
    // readonly type = SunburstSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_SUNBURST }

    // ignoreStyleOnData = true;
    //   (class-field default; overrides the SeriesModel `false`.)
    open override var ignoreStyleOnData: Bool {
        get { true }
        set { /* readonly upstream */ }
    }

    // private _viewRoot: TreeNode;
    private var _viewRoot: TreeNode?
    // private _levelModels: Model<SunburstSeriesLevelOption>[];
    private var _levelModels: [Model]?

    // upstream: getInitialData(option: SunburstSeriesOption, ecModel: GlobalModel)
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // Create a virtual root.
        // const root = { name: option.name, children: option.data } as SunburstSeriesNodeItemOption;
        var root: [String: Any] = [:]
        if let name = opt?["name"] {
            root["name"] = name
        }
        // `option.data` may be nil; assigning nil removes the key (JS `children: undefined`).
        root["children"] = opt?["data"]

        completeTreeValue(&root)

        // const levelModels = this._levelModels =
        //     zrUtil.map(option.levels || [], function (levelDefine) {
        //         return new Model(levelDefine, this, ecModel);
        //     }, this);
        let levels = (opt?["levels"] as? [Any]) ?? []
        let levelModels: [Model] = util.map(levels) { levelDefine, _ in
            // ModelOption is `Any`; `levelDefine` (Any) is already a valid ModelOption? arg.
            return Model(levelDefine, self, ecModel)
        }
        self._levelModels = levelModels

        // Make sure always a new tree is created when setOption,
        // in TreemapView, we check whether oldTree === newTree
        // to choose mappings approach among old shapes and new shapes.
        // const tree = Tree.createTree(root, this, beforeLink);
        var treeRef: Tree! = nil

        // function beforeLink(nodeData: SeriesData) {
        //     nodeData.wrapMethod('getItemModel', function (model, idx) {
        //         const node = tree.getNodeByDataIndex(idx);
        //         const levelModel = levelModels[node.depth];
        //         levelModel && (model.parentModel = levelModel);
        //         return model;
        //     });
        // }
        // SeriesData.wrapMethod cannot rebind a method by string name, so a `getItemModel`
        //   injection is routed into the dedicated `_getItemModelInjections` store, which
        //   `SeriesData.getItemModel` threads through its (possibly replaced) result — see
        //   data/SeriesData.swift. The closure below therefore DOES fire per datum: it resolves the node
        //   for `idx`, selects the per-depth `levelModels[node.depth]`, and sets it as `model.parentModel`,
        //   so `node.getModel('itemStyle'|'label')` inherits the matching `levels[]` entry (mirroring
        //   upstream's `beforeLink` wrap). (`getLevelModel` below independently resolves the per-depth
        //   level model for the layout path.)
        let beforeLink: (SeriesData) -> Void = { nodeData in
            nodeData.wrapMethod("getItemModel") { args in
                let model = args.first as? Model
                let idx = Int((args.count > 1 ? (args[1] as? Double) : nil) ?? 0)
                let node = treeRef.getNodeByDataIndex(idx)
                let depth = node != nil ? Int(node!.depth) : -1
                let levelModel = (depth >= 0 && depth < levelModels.count) ? levelModels[depth] : nil
                if let levelModel = levelModel {
                    model?.parentModel = levelModel
                }
                return model
            }
        }

        let tree = Tree.createTree(root, self, beforeLink)
        treeRef = tree
        return tree.data
    }

    // optionUpdated() { this.resetViewRoot(); }
    //   upstream ignores the base `(newCptOption, isInit)` params (JS overrides with a 0-arg form);
    //   the Swift override must match the base signature (Component.swift), so they are accepted+ignored.
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        self.resetViewRoot()
    }

    /*
     * @override
     */
    // getDataParams(dataIndex) {
    //     const params = super.getDataParams.apply(this, arguments) as SunburstDataParams;
    //     const node = this.getData().tree.getNodeByDataIndex(dataIndex);
    //     params.treePathInfo = wrapTreePathInfo<SunburstSeriesNodeItemOption['value']>(node, this);
    //     return params;
    // }
    open override func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil
    ) -> CallbackDataParams {
        // const params = super.getDataParams.apply(this, arguments) as SunburstDataParams;
        var params = super.getDataParams(dataIndex, dataType)

        // const node = this.getData().tree.getNodeByDataIndex(dataIndex);
        // params.treePathInfo = wrapTreePathInfo(node, this);
        //   upstream's `<SunburstSeriesNodeItemOption['value']>` only narrows the element
        //   `value` type; the Swift `TreePathInfoItem.value` is `Any?`, so the generic arg has no analogue.
        //   upstream types `tree`/`getNodeByDataIndex` optimistically, but `getNodeByDataIndex`
        //   indexes `this._nodes[rawIndex]` unchecked and yields `undefined` for an out-of-range index;
        //   `wrapTreePathInfo(undefined, ...)` then falls straight out of its `while (node)` loop and
        //   returns `[]`. So upstream ALWAYS assigns an array — never leaves the field absent. Map over
        //   the Optional node and default to `[]` so formatter callbacks see `[]`, not `nil`.
        let node: TreeNode? = self.getData().tree?.getNodeByDataIndex(Int(dataIndex))
        params.treePathInfo = node.map { treeHelper.wrapTreePathInfo($0, self) } ?? []

        return params
    }

    // getLevelModel(node: TreeNode) { return this._levelModels && this._levelModels[node.depth]; }
    open func getLevelModel(_ node: TreeNode) -> Model? {
        guard let levelModels = self._levelModels else { return nil }
        let depth = Int(node.depth)
        return (depth >= 0 && depth < levelModels.count) ? levelModels[depth] : nil
    }

    // static defaultOption: SunburstSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            // 默认全局居中
            "center": ["50%", "50%"],
            "radius": [0, "75%"] as [Any],
            // 默认顺时针
            "clockwise": true,
            "startAngle": 90.0,
            // 最小角度改为0
            "minAngle": 0.0,

            // If still show when all data zero.
            "stillShowZeroSum": true,

            // 'rootToNode', 'link', or false
            "nodeClick": "rootToNode",

            "renderLabelForZeroData": false,

            "label": [
                // could be: 'radial', 'tangential', or 'none'
                "rotate": "radial",
                "show": true,
                "opacity": 1.0,
                // 'left' is for inner side of inside, and 'right' is for outer
                // side for inside
                "align": "center",
                "position": "inside",
                "distance": 5.0,
                "silent": true
            ] as [String: Any],
            "itemStyle": [
                "borderWidth": 1.0,
                "borderColor": "white",
                "borderType": "solid",
                "shadowBlur": 0.0,
                "shadowColor": "rgba(0, 0, 0, 0.2)",
                "shadowOffsetX": 0.0,
                "shadowOffsetY": 0.0,
                "opacity": 1.0
            ] as [String: Any],

            "emphasis": [
                "focus": "descendant"
            ] as [String: Any],

            "blur": [
                "itemStyle": [
                    "opacity": 0.2
                ] as [String: Any],
                "label": [
                    "opacity": 0.1
                ] as [String: Any]
            ] as [String: Any],

            // Animation type can be expansion, scale.
            "animationType": "expansion",
            "animationDuration": 1000.0,
            "animationDurationUpdate": 500.0,

            "data": [],

            /**
             * Sort order.
             *
             * Valid values: 'desc', 'asc', null, or callback function.
             * 'desc' and 'asc' for descend and ascendant order;
             * null for not sorting;
             * example of callback function:
             * function(nodeA, nodeB) {
             *     return nodeA.getValue() - nodeB.getValue();
             * }
             */
            "sort": "desc"
        ] as [String: Any]
    }

    // getViewRoot() { return this._viewRoot; }
    open func getViewRoot() -> TreeNode {
        // upstream returns `this._viewRoot`, which is set by `optionUpdated()` (a model
        //   lifecycle hook). If the driver has not invoked `optionUpdated` yet, `_viewRoot` is
        //   nil; lazily reset here so the layout/view see a valid root (safe fallback per task rule 6).
        if self._viewRoot == nil {
            self.resetViewRoot()
        }
        return self._viewRoot!
    }

    // resetViewRoot(viewRoot?: TreeNode) { ... }
    open func resetViewRoot(_ viewRoot: TreeNode? = nil) {
        var viewRoot = viewRoot
        // viewRoot ? (this._viewRoot = viewRoot) : (viewRoot = this._viewRoot);
        if let vr = viewRoot {
            self._viewRoot = vr
        }
        else {
            viewRoot = self._viewRoot
        }

        let root: TreeNode = self.getRawData().tree!.root   // tree present once initTree has run; annotate to unwrap IUO `root`

        // if (!viewRoot || (viewRoot !== root && !root.contains(viewRoot)))
        if viewRoot == nil
            || (viewRoot !== root && !root.contains(viewRoot!)) {
            self._viewRoot = root
        }
    }

    // upstream: enableAriaDecal() { enableAriaDecalForTree(this); }
    open override var hasEnableAriaDecal: Bool { true }
    open override func enableAriaDecal() {
        enableAriaDecalForTree(self)
    }
}

// function completeTreeValue(dataNode: SunburstSeriesNodeItemOption) { ... }
//   Operates on the dynamic option node (`[String: Any]`). Upstream mutates each node's `value` (and
//   children's `value`) in place through object references; the Swift option node is a value dict, so
//   mutate a local copy and write it back (CONVENTIONS §3 value-type write-back).
func completeTreeValue(_ dataNode: inout [String: Any]) {
    // Postorder travel tree.
    // If value of none-leaf node is not set,
    // calculate it by suming up the value of all children.
    var sum: Double = 0

    // zrUtil.each(dataNode.children, function (child) { ... });
    var children = (dataNode["children"] as? [Any]) ?? []
    for i in 0..<children.count {
        guard var child = children[i] as? [String: Any] else {
            continue
        }

        completeTreeValue(&child)

        // let childValue = child.value;
        var childValue = child["value"]
        // TODO First value of array must be a number
        // zrUtil.isArray(childValue) && (childValue = childValue[0]);
        if let arr = childValue as? [Any] {
            childValue = arr.first ?? nil
        }
        // sum += childValue as number;
        sum += sunburstAsNumber(childValue)

        // write the mutated child back into the (value-type) children array.
        children[i] = child
    }
    if dataNode["children"] != nil {
        dataNode["children"] = children
    }

    // let thisValue = dataNode.value as number;
    var thisValue = sunburstAsNumber(dataNode["value"])
    // if (zrUtil.isArray(thisValue)) { thisValue = thisValue[0]; }
    //   (`sunburstAsNumber` already unwraps a leading array element; kept faithful below for the array
    //    write-back branch.)
    if let arr = dataNode["value"] as? [Any] {
        thisValue = sunburstAsNumber(arr.first ?? nil)
    }

    // if (thisValue == null || isNaN(thisValue)) { thisValue = sum; }
    if thisValue.isNaN {
        thisValue = sum
    }
    // Value should not less than 0.
    if thisValue < 0 {
        thisValue = 0
    }

    // zrUtil.isArray(dataNode.value)
    //     ? (dataNode.value[0] = thisValue)
    //     : (dataNode.value = thisValue);
    if var arr = dataNode["value"] as? [Any] {
        if arr.isEmpty {
            arr.append(thisValue)
        }
        else {
            arr[0] = thisValue
        }
        dataNode["value"] = arr
    }
    else {
        dataNode["value"] = thisValue
    }
}

// JS `x as number` coercion shim for the dynamic option bag: a number stays; a leading array element
// is unwrapped; everything else (null/undefined/non-numeric string) -> NaN (so `isNaN` replaces it with
// the children sum, matching upstream). Not an upstream symbol.
func sunburstAsNumber(_ v: Any?) -> Double {
    guard let v = v else { return Double.nan }
    if v is NSNull { return Double.nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let arr = v as? [Any] { return sunburstAsNumber(arr.first ?? nil) }
    return Double.nan
}

// export default SunburstSeriesModel;  -> `open class SunburstSeriesModel` above.
