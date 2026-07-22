// Ported from echarts/src/chart/treemap/TreemapSeries.ts — keep in sync with upstream
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
//       `tree.getNodeByDataIndex`, `tree.root`, `node.depth`, `root.contains(...)`.
//   import Model from '../../model/Model';                           -> Model (model/Model.swift).
//   import {wrapTreePathInfo} from '../helper/treeHelper';
//       -> treeHelper.wrapTreePathInfo (chart/helper/treeHelper.swift, fully ported); consumed by the
//          `getDataParams` override below.
//   import { ... } from '../../util/types';                          -> type-only; the dynamic option tree is
//       the `[String: Any]` bag per CONVENTIONS §2.
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { LayoutRect } from '../../util/layout';                  -> LayoutRect (typealias for BoundingRect).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import { normalizeToArray } from '../../util/model';             -> `model.normalizeToArray` (util/modelUtil.swift).
//   import { createTooltipMarkup } from '../../component/tooltip/tooltipMarkup';
//       -> createTooltipMarkup (component/tooltip/tooltipMarkup.swift); used by `formatTooltip` below.
//   import enableAriaDecalForTree from '../helper/enableAriaDecalForTree';
//       -> enableAriaDecalForTree (chart/helper/enableAriaDecalForTree.swift).
//   import tokens from '../../visual/tokens';
//       -> PORT-NOTE: tokens (visual/tokens.swift) is ported; every `tokens.*` value in `defaultOption` is
//          inlined below as its resolved constant, with the token path kept in a trailing comment.

// ============================================================================
// The upstream `type`/`interface` declarations (TreemapSeriesDataValue, BreadcrumbItemStyleOption,
// TreemapSeriesLabelOption, TreemapSeriesItemStyleOption, TreePathInfo, TreemapSeriesCallbackDataParams,
// ExtraStateOption, TreemapStateOption, TreemapSeriesVisualOption, TreemapSeriesLevelOption,
// TreemapSeriesNodeItemOption, TreemapSeriesOption) describe the (dynamic) option tree. Per CONVENTIONS §2
// the option tree is the `[String: Any]` bag; these types are kept as documentation only — no Swift types
// are emitted. The virtual-root node and each `levels[]`/`data[]` entry are all `[String: Any]`.
// ============================================================================

// upstream: class TreemapSeriesModel extends SeriesModel<TreemapSeriesOption>
open class TreemapSeriesModel: SeriesModel {

    // static type = 'series.treemap';
    // type = TreemapSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.treemap" }

    // static layoutMode = 'box' as const;
    open override class var layoutMode: Any? { return "box" }

    // layoutInfo: LayoutRect;
    public var layoutInfo: LayoutRect?

    // designatedVisualItemStyle: TreemapSeriesItemStyleOption;
    //   The dynamic itemStyle bag; set (and shared with `designatedVisualModel`) in `getInitialData`.
    // PORT-NOTE: upstream relies on this being a LIVE-SHARED object: it is the `itemStyle` of
    //   `designatedVisualModel`, and every `Model` derived from that model (`getModel`, the node item
    //   models re-parented onto it) keeps a REFERENCE to it — so `treemapVisual`'s per-node writes here
    //   are observed by `nodeItemStyleModel.get(visualName)` through the parent chain. That aliasing IS
    //   the "visual priority" trick documented in `getInitialData` below. A Swift `[String: Any]` is a
    //   value type: it would be copied into the option bag (and re-copied by every `getModel` snapshot),
    //   silently dropping the write-through. The bag is therefore a reference-typed `NSMutableDictionary`
    //   stored directly in the option tree — `Model._doGet`'s `obj as? [String: Any]` bridge reads its
    //   CURRENT contents at read time, so the copies all observe the same live object, exactly like JS.
    //   INVARIANT: the bag must never pass through `util.clone` / `Model.clone()`. `util.clone` matches it
    //   via `source as? [String: Any]` and rebuilds an IMMUTABLE Swift dict, which severs the write-through
    //   silently (and its `return result as! T` would trap if `T` were statically `NSMutableDictionary`).
    //   Nothing on the treemap path clones the option tree today; a future clone seam must special-case it.
    //   NOTE: values read back through the bag are Foundation-BRIDGED (Double→NSNumber, String→NSString,
    //   non-bridgeable Swift values→`__SwiftValue`). Consumers must therefore keep using tolerant `as?`
    //   casts on anything resolved through `designatedVisualModel` — never `is` / `type(of:)` identity
    //   checks (in particular an Int-boxed option value now succeeds `as? Double` through this chain).
    public var designatedVisualItemStyle: NSMutableDictionary = NSMutableDictionary()

    // private _viewRoot: TreeNode;
    private var _viewRoot: TreeNode?
    // private _idIndexMap: zrUtil.HashMap<number>;
    private var _idIndexMap: [String: Int]?
    // private _idIndexMapCount: number;
    private var _idIndexMapCount: Int = 0

    // zoom: number;
    public var zoom: Double?
    // zoomLimit: { max?: number; min?: number };
    public var zoomLimit: [String: Double]?

    // preventUsingHoverLayer = true;  (class-field default overriding the SeriesModel `false`.)
    //   `preventUsingHoverLayer` is a stored `var` on the base, so it cannot be overridden with a
    //   computed property; instead it is assigned in the `init` lifecycle hook below.
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        super.`init`(option, parentModel, ecModel)
        self.preventUsingHoverLayer = true
    }

    /**
     * @override
     */
    // upstream: getInitialData(option: TreemapSeriesOption, ecModel: GlobalModel)
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        let opt = option as? [String: Any]

        // Create a virtual root.
        // const root: TreemapSeriesNodeItemOption = { name: option.name, children: option.data };
        var root: [String: Any] = [:]
        if let name = opt?["name"] {
            root["name"] = name
        }
        // `option.data` may be nil; assigning nil removes the key (JS `children: undefined`).
        root["children"] = opt?["data"]

        // completeTreeValue(root);
        //   Reuse the sibling `completeTreeValue(inout [String: Any])` (chart/sunburst/SunburstSeries.swift):
        //   both upstream files declare byte-identical implementations, and two module-scope funcs of the
        //   same signature would collide in the EChartsKit target — so the single shared definition is used.
        completeTreeValue(&root)

        // let levels = option.levels || [];
        var levels: [[String: Any]] = ((opt?["levels"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }

        // Used in "visual priority" in `treemapVisual.js`.
        // This way is a little tricky, must satisfy the precondition:
        //   1. There is no `treeNode.getModel('itemStyle.xxx')` used.
        //   2. The `Model.prototype.getModel()` will not use any clone-like way.
        // const designatedVisualItemStyle = this.designatedVisualItemStyle = {};
        // const designatedVisualModel = new Model({itemStyle: designatedVisualItemStyle}, this, ecModel);
        //   The bag is a reference-typed `NSMutableDictionary` (see the property declaration) and is stored
        //   AS-IS in the model option, so `designatedVisualModel.get(['itemStyle', ...])` — and every model
        //   derived from it — observes `treemapVisual`'s later writes, exactly like the shared JS object.
        //   A fresh instance per `getInitialData` mirrors upstream's `this.designatedVisualItemStyle = {}`.
        let designatedVisualItemStyle = NSMutableDictionary()
        self.designatedVisualItemStyle = designatedVisualItemStyle
        let designatedVisualModel = Model(["itemStyle": designatedVisualItemStyle], self, ecModel)

        // levels = option.levels = setDefault(levels, ecModel);
        levels = setDefault(&levels, ecModel)
        // `option.levels` is written back so downstream reads see the defaulted levels.
        if var mutOpt = opt {
            mutOpt["levels"] = levels
            self.option = mutOpt
        }

        // const levelModels = zrUtil.map(levels || [], function (levelDefine) {
        //     return new Model(levelDefine, designatedVisualModel, ecModel);
        // }, this);
        let levelModels: [Model] = util.map(levels) { levelDefine, _ in
            return Model(levelDefine, designatedVisualModel, ecModel)
        }

        // Make sure always a new tree is created when setOption,
        // in TreemapView, we check whether oldTree === newTree
        // to choose mappings approach among old shapes and new shapes.
        // const tree = Tree.createTree(root, this, beforeLink);
        var treeRef: Tree! = nil

        // function beforeLink(nodeData: SeriesData) {
        //     nodeData.wrapMethod('getItemModel', function (model, idx) {
        //         const node = tree.getNodeByDataIndex(idx);
        //         const levelModel = node ? levelModels[node.depth] : null;
        //         // If no levelModel, we also need `designatedVisualModel`.
        //         model.parentModel = levelModel || designatedVisualModel;
        //         return model;
        //     });
        // }
        // POTENTIAL-BUG: SeriesData.wrapMethod only invokes injections for the hard-coded wrappable methods
        //   (cloneShallow/transferProperties); `getItemModel` never calls its registered injection, so the
        //   injected closure below is stored but NOT invoked, and the per-depth level-model /
        //   designatedVisualModel parenting does not take effect through this path. Preserved faithfully for
        //   the diffable surface and for when getItemModel invokes wrapMethod injections.
        let beforeLink: (SeriesData) -> Void = { nodeData in
            nodeData.wrapMethod("getItemModel") { args in
                let model = args.first as? Model
                let idx = Int((args.count > 1 ? (args[1] as? Double) : nil) ?? 0)
                let node = treeRef.getNodeByDataIndex(idx)
                let depth = node != nil ? Int(node!.depth) : -1
                let levelModel = (depth >= 0 && depth < levelModels.count) ? levelModels[depth] : nil
                // model.parentModel = levelModel || designatedVisualModel;
                model?.parentModel = levelModel ?? designatedVisualModel
                return model
            }
        }

        let tree = Tree.createTree(root, self, beforeLink)
        treeRef = tree

        // PORT-NOTE (level-model wiring): upstream reparents each node's item model onto its depth's
        //   level model inside the `beforeLink` `wrapMethod('getItemModel')` injection. The port's
        //   getItemModel does not run wrapMethod injections, so the level models (and the designated-
        //   visual fallback) are published on the tree here and applied in `TreeNode.getModel()`.
        //   Without this the `levels[]` config (per-depth color / colorMappingBy / itemStyle
        //   borderWidth·gapWidth·borderColor / upperLabel) never reaches the nodes — treemapVisual then
        //   falls back to the global palette and treemapLayout to the series-default border/gap, which
        //   is the treemap parity bug this restores.
        tree.levelModels = levelModels
        tree.designatedVisualModel = designatedVisualModel

        // return tree.data;
        return tree.data
    }

    // optionUpdated() { this.resetViewRoot(); }
    //   upstream ignores the base `(newCptOption, isInit)` params (JS overrides with a 0-arg form);
    //   the Swift override must match the base signature (Component.swift), so they are accepted+ignored.
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        self.resetViewRoot()
    }

    /**
     * @override
     */
    open override func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        _ = (multipleSeries, dataType)
        let data = self.getData()
        let value = self.getRawValue(dataIndex)
        let name = data.getName(Int(dataIndex))
        return createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(name: name, value: value))
    }

    /**
     * Add tree path to tooltip param
     * @override
     */
    // upstream: getDataParams(dataIndex) {
    //     const params = super.getDataParams.apply(this, arguments) as TreemapSeriesCallbackDataParams;
    //     const node = this.getData().tree.getNodeByDataIndex(dataIndex);
    //     params.treeAncestors = wrapTreePathInfo(node, this);
    //     // compatitable the previous code.
    //     params.treePathInfo = params.treeAncestors;
    //     return params;
    // }
    open override func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil
    ) -> CallbackDataParams {
        // const params = super.getDataParams.apply(this, arguments) as TreemapSeriesCallbackDataParams;
        var params = super.getDataParams(dataIndex, dataType)

        // const node = this.getData().tree.getNodeByDataIndex(dataIndex);
        // PORT-NOTE: upstream types `tree`/`getNodeByDataIndex` optimistically; both are Optional here.
        //   With no node there is no path to wrap, so the base params are returned untouched.
        guard let node = self.getData().tree?.getNodeByDataIndex(Int(dataIndex)) else {
            return params
        }
        // params.treeAncestors = wrapTreePathInfo(node, this);
        params.treeAncestors = treeHelper.wrapTreePathInfo(node, self)
        // compatitable the previous code.
        params.treePathInfo = params.treeAncestors

        return params
    }

    /**
     * @public
     * @param layoutInfo { x, y, width, height } of the containerGroup.
     */
    // setLayoutInfo(layoutInfo: LayoutRect) {
    //     this.layoutInfo = this.layoutInfo || {} as LayoutRect;
    //     zrUtil.extend(this.layoutInfo, layoutInfo);
    // }
    public func setLayoutInfo(_ layoutInfo: LayoutRect) {
        // this.layoutInfo = this.layoutInfo || {} as LayoutRect;
        let target: LayoutRect = self.layoutInfo ?? BoundingRect(0, 0, 0, 0)
        // zrUtil.extend(this.layoutInfo, layoutInfo) — copy the (x, y, width, height) fields of a LayoutRect.
        target.x = layoutInfo.x
        target.y = layoutInfo.y
        target.width = layoutInfo.width
        target.height = layoutInfo.height
        self.layoutInfo = target
    }

    /**
     * @param id
     * @return index
     */
    public func mapIdToIndex(_ id: String) -> Int {
        // A feature is implemented:
        // index is monotone increasing with the sequence of
        // input id at the first time.
        // This feature can make sure that each data item and its
        // mapped color have the same index between data list and
        // color list at the beginning, which is useful for user
        // to adjust data-color mapping.

        // let idIndexMap = this._idIndexMap;
        // if (!idIndexMap) { idIndexMap = this._idIndexMap = zrUtil.createHashMap(); this._idIndexMapCount = 0; }
        if self._idIndexMap == nil {
            self._idIndexMap = [:]
            self._idIndexMapCount = 0
        }

        // let index = idIndexMap.get(id);
        // if (index == null) { idIndexMap.set(id, index = this._idIndexMapCount++); }
        if let index = self._idIndexMap![id] {
            return index
        }
        let index = self._idIndexMapCount
        self._idIndexMapCount += 1
        self._idIndexMap![id] = index
        return index
    }

    // getViewRoot() { return this._viewRoot; }
    public func getViewRoot() -> TreeNode? {
        // PORT-NOTE: upstream returns `this._viewRoot`, which is set by `optionUpdated()` (a model
        //   lifecycle hook). If the driver has not invoked `optionUpdated` yet, `_viewRoot` is nil;
        //   lazily reset here so the layout/view see a valid root (safe fallback, mirrors SunburstSeries).
        if self._viewRoot == nil {
            self.resetViewRoot()
        }
        return self._viewRoot
    }

    // resetViewRoot(viewRoot?: TreeNode) { ... }
    public func resetViewRoot(_ viewRoot: TreeNode? = nil) {
        var viewRoot = viewRoot
        // viewRoot ? (this._viewRoot = viewRoot) : (viewRoot = this._viewRoot);
        if let vr = viewRoot {
            self._viewRoot = vr
        }
        else {
            viewRoot = self._viewRoot
        }

        // const root = this.getRawData().tree.root;
        let root: TreeNode = self.getRawData().tree!.root   // tree present once createTree has run; annotate to unwrap IUO `root`

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

    // static defaultOption: TreemapSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // Disable progressive rendering
            "progressive": 0.0,
            // size: ['80%', '80%'],            // deprecated, compatible with ec2.

            // `coordinateSystem` can be declared as 'matrix', 'calendar',
            //  which provides box layout container.
            "coordinateSystemUsage": "box",

            "left": 20.0,       // tokens.size.l
            "top": 50.0,        // tokens.size.xxxl
            "right": 20.0,      // tokens.size.l
            "bottom": 50.0,     // tokens.size.xxxl

            "sort": true,

            "clipWindow": "origin",
            "squareRatio": 0.5 * (1 + 5.0.squareRoot()),   // golden ratio
            "leafDepth": NSNull(),

            "drillDownIcon": "▶",           // Use html character temporarily because it is complicated
                                            // to align specialized icon. ▷▶❒❐▼✚

            "zoomToNodeRatio": 0.32 * 0.32,

            "scaleLimit": [
                "max": 5.0,
                "min": 0.2
            ] as [String: Any],

            "roam": true,
            "roamTrigger": "global",
            "nodeClick": "zoomToNode",
            "animation": true,
            "animationDurationUpdate": 900.0,
            "animationEasing": "quinticInOut",
            "breadcrumb": [
                "show": true,
                "height": 22.0,
                "left": "center",
                "bottom": 15.0,         // tokens.size.m
                // right
                // bottom
                "emptyItemWidth": 25.0,             // Width of empty node.
                "itemStyle": [
                    "color": "#e0e6f1",             // tokens.color.backgroundShade
                    "textStyle": [
                        "color": "#6e7079"          // tokens.color.secondary
                    ] as [String: Any]
                ] as [String: Any],
                "emphasis": [
                    "itemStyle": [
                        "color": "#fff"             // tokens.color.background
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "label": [
                "show": true,
                // Do not use textDistance, for ellipsis rect just the same as treemap node rect.
                "distance": 0.0,
                "padding": 5.0,
                "position": "inside", // Can be [5, '5%'] or position string like 'insideTopLeft', ...
                // formatter: null,
                "color": "#fff",        // tokens.color.neutral00
                "overflow": "truncate"
                // align
                // verticalAlign
            ] as [String: Any],
            "upperLabel": [                 // Label when node is parent.
                "show": false,
                "position": [0, "50%"] as [Any],
                "height": 20.0,
                // formatter: null,
                // color: '#fff',
                "overflow": "truncate",
                // align: null,
                "verticalAlign": "middle"
            ] as [String: Any],
            "itemStyle": [
                "color": NSNull(),          // Can be 'none' if not necessary.
                "colorAlpha": NSNull(),     // Can be 'none' if not necessary.
                "colorSaturation": NSNull(), // Can be 'none' if not necessary.
                "borderWidth": 0.0,
                "gapWidth": 0.0,
                "borderColor": "#fff",      // tokens.color.neutral00
                "borderColorSaturation": NSNull()   // If specified, borderColor will be ineffective, and the
                                            // border color is evaluated by color of current node and
                                            // borderColorSaturation.
            ] as [String: Any],
            "emphasis": [
                "upperLabel": [
                    "show": true,
                    "position": [0, "50%"] as [Any],
                    "overflow": "truncate",
                    "verticalAlign": "middle"
                ] as [String: Any]
            ] as [String: Any],

            "visualDimension": 0.0,             // Can be 0, 1, 2, 3.
            "visualMin": NSNull(),
            "visualMax": NSNull(),

            "color": [] as [Any],       // + treemapSeries.color should not be modified. Please only modified
                                        // level[n].color (if necessary).
                                        // + Specify color list of each level. level[0].color would be global
                                        // color list if not specified. (see method `setDefault`).
                                        // + But set as a empty array to forbid fetch color from global palette
                                        // when using nodeModel.get('color'), otherwise nodes on deep level
                                        // will always has color palette set and are not able to inherit color
                                        // from parent node.
                                        // + TreemapSeries.color can not be set as 'none', otherwise effect
                                        // legend color fetching (see seriesColor.js).
            "colorAlpha": NSNull(),     // Array. Specify color alpha range of each level, like [0.2, 0.8]
            "colorSaturation": NSNull(), // Array. Specify color saturation of each level, like [0.2, 0.5]
            "colorMappingBy": "index",  // 'value' or 'index' or 'id'.
            "visibleMin": 10.0,         // If area less than this threshold (unit: pixel^2), node will not
                                        // be rendered. Only works when sort is 'asc' or 'desc'.
            "childrenVisibleMin": NSNull(), // If area of a node less than this threshold (unit: pixel^2),
                                        // grandchildren will not show.
                                        // Why grandchildren? If not grandchildren but children,
                                        // some siblings show children and some not,
                                        // the appearance may be mess and not consistent,
            "levels": [] as [Any]       // Each item: {
                                        //     visibleMin, itemStyle, visualDimension, label
                                        // }
        ] as [String: Any]
    }
}

// function completeTreeValue(dataNode: TreemapSeriesNodeItemOption) { ... }
//   NOTE: intentionally NOT re-declared here. Upstream TreemapSeries.ts and SunburstSeries.ts declare
//   byte-identical `completeTreeValue` functions; the ported `completeTreeValue(inout [String: Any])` lives
//   in chart/sunburst/SunburstSeries.swift and is reused directly (two same-signature module-scope funcs
//   would collide in the EChartsKit target). See `getInitialData` above.

/**
 * set default to level configuration
 */
// function setDefault(levels: TreemapSeriesLevelOption[], ecModel: GlobalModel) { ... }
//   File-private (so the generic name cannot collide with other ports). `levels` is passed `inout` to
//   mirror the upstream in-place `levels[0] = {}` mutation and to be usable as the return value.
private func setDefault(_ levels: inout [[String: Any]], _ ecModel: GlobalModel?) -> [[String: Any]] {
    // const globalColorList = normalizeToArray(ecModel.get('color')) as ColorString[];
    let globalColorList: [Any] = model.normalizeToArray(ecModel?.get("color"))
    // const globalDecalList = normalizeToArray((ecModel as Model<AriaOptionMixin>).get(['aria', 'decal', 'decals'])) as DecalObject[];
    let globalDecalList: [Any] = model.normalizeToArray(ecModel?.get(["aria", "decal", "decals"]))

    // if (!globalColorList) { return; }
    //   Upstream `globalColorList` is a `normalizeToArray(...)` result, i.e. always a (possibly empty)
    //   JS array — and any JS array is truthy — so `!globalColorList` is always `false` and this guard
    //   never fires. The ported `normalizeToArray` likewise always yields a non-nil `[Any]`, so the guard
    //   is a faithful no-op and is intentionally not emitted.

    // levels = levels || [];
    // (already a non-nil array in Swift.)
    var hasColorDefine = false
    var hasDecalDefine = false
    // zrUtil.each(levels, function (levelDefine) { ... });
    util.each(levels) { levelDefine, _ in
        let m = Model(levelDefine)
        let modelColor = m.get("color")
        let modelDecal = m.get("decal")

        // if (model.get(['itemStyle', 'color']) || (modelColor && modelColor !== 'none')) { hasColorDefine = true; }
        if jsTruthy(m.get(["itemStyle", "color"]))
            || (jsTruthy(modelColor) && !((modelColor as? String) == "none")) {
            hasColorDefine = true
        }
        // if (model.get(['itemStyle', 'decal']) || (modelDecal && modelDecal !== 'none')) { hasDecalDefine = true; }
        if jsTruthy(m.get(["itemStyle", "decal"]))
            || (jsTruthy(modelDecal) && !((modelDecal as? String) == "none")) {
            hasDecalDefine = true
        }
    }

    // const level0 = levels[0] || (levels[0] = {});
    if levels.isEmpty {
        levels.append([:])
    }
    // if (!hasColorDefine) { level0.color = globalColorList.slice(); }
    if !hasColorDefine {
        levels[0]["color"] = globalColorList   // slice() -> Swift array copy (value type)
    }
    // if (!hasDecalDefine && globalDecalList) { level0.decal = globalDecalList.slice(); }
    if !hasDecalDefine && !globalDecalList.isEmpty {
        levels[0]["decal"] = globalDecalList
    }

    // return levels;
    return levels
}

// jsTruthy: mirrors JavaScript `||`/`&&` truthiness for a dynamic `Any?` value (nil / NSNull / false /
// 0 / NaN / "" are falsy). Declared file-private here (the sibling copies in Tree.swift / SunburstSeries.swift
// are also file-private, so there is no module-level collision).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// export default TreemapSeriesModel;  -> `open class TreemapSeriesModel` above.
