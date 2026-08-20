// Ported from echarts/src/chart/treemap/TreemapView.ts — keep in sync with upstream
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
//   import {bind, each, indexOf, curry, extend, normalizeCssArray, isFunction} from 'zrender/src/core/util';
//       -> `util.*` (ZRenderKit).
//   import * as graphic from '../../util/graphic';                  -> ZRenderKit `Group` / `Rect` (used directly).
//   import {getECData} from '../../util/innerStore';                -> `innerStore.getECData`.
//   import { isHighDownDispatcher, setAsHighDownDispatcher, setDefaultStateProxy, enableHoverFocus,
//            Z2_EMPHASIS_LIFT } from '../../util/states';
//       -> util/states IS ported (util/states.swift); treemap's states/emphasis/high-down dispatch is
//          still DEFERRED here. `Z2_EMPHASIS_LIFT` is inlined below as its upstream literal (10).
//   import DataDiffer from '../../data/DataDiffer';                 -> PORT-NOTE (deferred): DataDiffer IS ported, but treemap's hierarchical dualTravel diff/reuse is deferred; static rebuild used.
//   import * as helper from '../helper/treeHelper';                 -> treeHelper IS ported (chart/helper/treeHelper.swift)
//       and USED: `retrieveTargetInfo` in `render()`, `aboveViewRoot` in `_renderBreadcrumb`'s findTarget
//       and in treemapAction.swift. Only the `reRoot` descriptor / `_doAnimation` consumers are deferred.
//   import Breadcrumb from './Breadcrumb';                          -> sibling Breadcrumb.swift.
//   import RoamController, { RoamEventParams } from '../../component/helper/RoamController';
//       -> RoamController IS ported (component/helper/RoamController.swift); pan/zoom roam is still DEFERRED here.
//   import BoundingRect, { RectLike } from 'zrender/src/core/BoundingRect';  -> `BoundingRect` (ZRenderKit).
//   import * as matrix from 'zrender/src/core/matrix';             -> `matrix` (ZRenderKit) — used by the deferred zoom.
//   import * as animationUtil from '../../util/animation';         -> PORT-NOTE (deferred): the treemap _doAnimation subsystem is deferred; static render is the final state.
//   import makeStyleMapper from '../../model/mixin/makeStyleMapper';
//       -> PORT-NOTE: makeStyleMapper's treemap-custom mapping (strokeColor→stroke, strokeWidth→lineWidth)
//          is approximated by `Model.getItemStyle()` + the three-field clear below.
//   import ChartView from '../../view/Chart';                      -> `ChartView` (view/Chart.swift).
//   import Tree, { TreeNode } from '../../data/Tree';              -> `Tree` / `TreeNode` (data/Tree.swift).
//   import TreemapSeriesModel, { TreemapSeriesNodeItemOption } from './TreemapSeries';  -> sibling TreemapSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> `ExtensionAPI`.
//   import Model from '../../model/Model';                         -> `Model`.
//   import { LayoutRect } from '../../util/layout';                -> `LayoutRect` (== BoundingRect).
//   import { calculateCurrentZoom, treemapClampZoom, TreemapLayoutNode } from './treemapLayout';
//       -> sibling treemapLayout.swift (zoom helpers used only by the deferred roam).
//   import Element from 'zrender/src/Element';                     -> `Element`.
//   import Displayable from 'zrender/src/graphic/Displayable';     -> `Displayable`.
//   import { makeInner, convertOptionIdName } from '../../util/model';  -> `model.makeInner` / `model.convertOptionIdName`.
//   import { PathStyleProps, PathProps } from 'zrender/src/graphic/Path';  -> `PathStyleProps` / `PathProps`.
//   import { TreeSeriesNodeItemOption } from '../tree/TreeSeries';  -> type-only (the link-click item model).
//   import { TreemapRootToNodePayload, ... } from './treemapAction';  -> the payload interfaces are type-only;
//       the port carries their fields on the dynamic `Payload.other` bag (see treemapAction.swift).
//   import { ColorString, ECElement } from '../../util/types';     -> type-only.
//   import { windowOpen } from '../../util/format';                -> `format.windowOpen` (link node click).
//   import { TextStyleProps } from 'zrender/src/graphic/Text';     -> `TextStyleProps`.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> label/labelStyle IS ported (label/labelStyle.swift); treemap still uses a MINIMAL faithful
//          NORMAL-state label (node name, centered) instead of the full setLabelStyle path (see `prepareText`).

// const Group = graphic.Group;  /  const Rect = graphic.Rect;  -> ZRenderKit `Group` / `Rect` used directly.

// const DRAG_THRESHOLD = 3;  -> only used by the deferred roam pan.
private let DRAG_THRESHOLD: Double = 3
// const PATH_LABEL_NOAMAL = 'label';
private let PATH_LABEL_NOAMAL = "label"
// const PATH_UPPERLABEL_NORMAL = 'upperLabel';
private let PATH_UPPERLABEL_NORMAL = "upperLabel"
// PORT-NOTE: util/states.Z2_EMPHASIS_LIFT (== 10) inlined.
private let Z2_EMPHASIS_LIFT: Double = 10
// Should larger than emphasis states lift z
// const Z2_BASE = Z2_EMPHASIS_LIFT * 10;  // Should bigger than every z2.
private let Z2_BASE = Z2_EMPHASIS_LIFT * 10
// const Z2_BG = Z2_EMPHASIS_LIFT * 2;
private let Z2_BG = Z2_EMPHASIS_LIFT * 2
// const Z2_CONTENT = Z2_EMPHASIS_LIFT * 3;
private let Z2_CONTENT = Z2_EMPHASIS_LIFT * 3

// const getStateItemStyle = makeStyleMapper([ ['fill','color'], ['stroke','strokeColor'], ... ]);
// PORT-NOTE: makeStyleMapper IS ported (model/mixin/makeStyleMapper.swift), so the treemap-custom
//   option→style mapping is now ported EXACTLY (was previously approximated by `Model.getItemStyle()`).
//   `borderColor`/`borderWidth` are occupied (the container gap), so the rect stroke reads
//   `strokeColor`/`strokeWidth` instead. Closure params: (model, excludes, includes) — pass nils.
private let getStateItemStyle = makeStyleMapper([
    ["fill", "color"],
    // `borderColor` and `borderWidth` has been occupied,
    // so use `stroke` to indicate the stroke of the rect.
    ["stroke", "strokeColor"],
    ["lineWidth", "strokeWidth"],
    ["shadowBlur"],
    ["shadowOffsetX"],
    ["shadowOffsetY"],
    ["shadowColor"]
    // Option decal is in `DecalObject` but style.decal is in `PatternObject`.
    // So do not transfer decal directly.
], nil)
// const getItemStyleNormal = function (model) { const itemStyle = getStateItemStyle(model); itemStyle.stroke = itemStyle.fill = itemStyle.lineWidth = null; return itemStyle; };
private func getItemStyleNormal(_ model: Model) -> [String: Any] {
    // Normal style props should include emphasis style props.
    var itemStyle = getStateItemStyle(model, nil, nil)
    // Clear styles set by emphasis.
    itemStyle["stroke"] = nil
    itemStyle["fill"] = nil
    itemStyle["lineWidth"] = nil
    return itemStyle
}

// interface RenderElementStorage { nodeGroup: Group[]; background: Rect[]; content: Rect[] }
// PORT-NOTE: upstream arrays are indexed by rawIndex and iterated by the deferred diff/animation. The
//   static rebuild only needs by-rawIndex lookup (findTarget), so `[Int: T]` (keyed by rawIndex) is used;
//   lookup semantics (nil when absent) match `array[rawIndex]`.
private final class RenderElementStorage {
    var nodeGroup: [Int: Group] = [:]
    var background: [Int: Rect] = [:]
    var content: [Int: Rect] = [:]
}

// interface FoundTargetInfo { node: TreeNode; offsetX?: number; offsetY?: number }
public struct FoundTargetInfo {
    public var node: TreeNode
    public var offsetX: Double?
    public var offsetY: Double?
    public init(node: TreeNode, offsetX: Double? = nil, offsetY: Double? = nil) {
        self.node = node
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

// upstream: RenderResult / ReRoot / LastCfg / inner(makeInner) — DEFERRED (animation/diff subsystem).
// PORT-NOTE (deferred): the animation storage (`lastsForAnimation`, `willDeleteEls`, `willInvisibleEls`,
//   `renderFinally`), the reRoot drill/roll descriptor, and `inner(el).{nodeWidth,nodeHeight,willDelete}`
//   are not ported — the static render rebuilds the group each pass (SunburstView/PieView convention).

// upstream: class TreemapView extends ChartView
open class TreemapView: ChartView {

    // static type = 'treemap';  /  type = TreemapView.type;
    public static let treemapType = "treemap"
    open override var type: String {
        get { TreemapView.treemapType }
        set { /* readonly upstream */ }
    }

    // private _containerGroup: graphic.Group;
    private var _containerGroup: Group?
    // private _breadcrumb: Breadcrumb;
    private var _breadcrumb: Breadcrumb?
    // private _controller: RoamController;  -> DEFERRED (roam not ported).

    // private _oldTree: Tree;
    private var _oldTree: Tree?

    // private _state: 'ready' | 'animating' = 'ready';
    private var _state: String = "ready"

    // private _storage = createStorage();
    private var _storage = RenderElementStorage()

    // View REUSE (L5 fidelity, batch-A idiom): the per-node graphic elements in `_storage` PERSIST
    //   across renders so a merge-mode setOption value change MORPHS the tiles (each node group slides
    //   and its bg/content rect resizes to the new squarify slot) instead of rebuild-and-snap. This
    //   holds the node count of the last render; a same-count value change morphs, a count change
    //   rebuilds fresh (mirrors LineView's `_prevPointCount`). -1 before the first render.
    private var _prevNodeCount: Int = -1

    // seriesModel; api; ecModel; (injected in render)
    public var seriesModel: TreemapSeriesModel?
    public var api: ExtensionAPI?
    public var ecModel: GlobalModel?

    /**
     * @override
     */
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: TreemapSeriesModel`.
        let seriesModel = seriesModelBase as! TreemapSeriesModel

        // const models = ecModel.findComponents({ mainType: 'series', subType: 'treemap', query: payload });
        // if (indexOf(models, seriesModel) < 0) { return; }
        // upstream passes the whole `payload` as `query`; its component-query fields live in `payload.other`.
        let models = ecModel.findComponents(
            QueryConditionKindA(mainType: "series", query: payload.other, subType: "treemap")
        )
        if !models.contains(where: { ($0 as AnyObject) === (seriesModel as AnyObject) }) {
            return
        }

        self.seriesModel = seriesModel
        self.api = api
        self.ecModel = ecModel

        // const types = ['treemapZoomToNode', 'treemapRootToNode'];
        // const targetInfo = helper.retrieveTargetInfo(payload, types, seriesModel);
        //   The drill/zoom payloads are dispatched by `_zoomToNode` / `_rootToNode` below and handled by
        //   installTreemapAction (chart/treemap/treemapAction.swift). When the payload is neither type,
        //   `retrieveTargetInfo` returns nil and the breadcrumb tail falls back to `findTarget`
        //   (see `_renderBreadcrumb`), exactly as upstream.
        let types = ["treemapZoomToNode", "treemapRootToNode"]
        let targetInfo: FoundTargetInfo? = treeHelper.retrieveTargetInfo(payload, types, seriesModel)
            .map { FoundTargetInfo(node: $0.node) }
        // const payloadType = payload && payload.type;  -> consumed only by the deferred animation routing.
        // const layoutInfo = seriesModel.layoutInfo;
        //   `seriesModel.layoutInfo` is the treemapLayout output rect (`LayoutRect?` in the sibling port;
        //   non-null upstream after the layout stage). Bail if the layout has not run.
        guard let layoutInfo = seriesModel.layoutInfo else {
            return
        }
        // const isInit = !this._oldTree;  -> consumed by the deferred animation routing.
        // const thisStorage = this._storage;  -> `self._storage` exists and is LIVE (it is the persistent
        //   morph storage written by `renderNode`); only its use by the deferred reRoot descriptor below
        //   is unported.

        // Mark new root when action is treemapRootToNode.
        // const reRoot = (payloadType === 'treemapRootToNode' && targetInfo && thisStorage)
        //     ? { rootNodeGroup: thisStorage.nodeGroup[targetInfo.node.getRawIndex()], direction: payload.direction }
        //     : null;
        // PORT-TODO (deferred): reRoot descriptor.
        //   The `treemapRootToNode` action itself IS ported (installTreemapAction, treemapAction.swift):
        //   dispatching it re-roots the series via `model.resetViewRoot` and this render pass rebuilds from
        //   the new view root. Only the `reRoot` DESCRIPTOR is deferred. Its `rootNodeGroup` field IS
        //   available today (`self._storage.nodeGroup[targetInfo.node.getRawIndex()]` — `_storage` is the
        //   persistent morph storage, matching upstream's `this._storage` at this point). Its `direction`
        //   field is NOT: it is the dead write noted in treemapAction.swift (`Payload` is a value type, so
        //   the handler's `direction` stamp never reaches this pass). Since the descriptor's only consumers
        //   are the deferred `_doAnimation` (upstream TreemapView.ts:214/:378) and the deferred
        //   `prepareAnimationWhenNoOld` drill-down starting-rect choice (upstream TreemapView.ts:1090),
        //   constructing it now would be dead state — port it together with `_doAnimation`, threading
        //   `direction` per the treemapAction.swift PORT-TODO.

        // const containerGroup = this._giveContainerGroup(layoutInfo);
        let containerGroup = self._giveContainerGroup(layoutInfo)
        // const hasAnimation = seriesModel.get('animation');  -> DEFERRED (animation not ported).

        // const renderResult = this._doRender(containerGroup, seriesModel, reRoot);
        self._doRender(containerGroup, seriesModel)
        // PORT-NOTE (deferred): (hasAnimation && !isInit && ...) ? this._doAnimation(...) : renderResult.renderFinally();
        //   Animation + `renderFinally` (deferred removal / invisible flagging) DEFERRED — the static
        //   rebuild already reflects the final state.

        // this._resetController(api);
        //   The RoamController is wired live by EChartsView._setupTreemapRoam (the TreemapView is
        //   zr-less). DEVIATION: upstream treemap roam re-lays-out the tiles into a shifted/scaled
        //   `rootRect` (`treemapMove`/`treemapRender`); the port instead applies the accumulated roam as a
        //   TRANSFORM to the container group (see roamHelperViewGroup.swift). Base = (layoutInfo.x, .y)
        //   (set by _giveContainerGroup); identity roam state → the container is left exactly as-is.
        viewGroupRoamApplyStateToGroup(seriesModel, containerGroup, layoutInfo.x, layoutInfo.y)

        // this._renderBreadcrumb(seriesModel, api, targetInfo);
        self._renderBreadcrumb(seriesModel, api, targetInfo)
    }

    // L3 Roam: the pointer-check element (upstream Treemap._resetController isInSelf reads the container
    //   group's bounding rect). Returns nil before the first render (container not yet built).
    func roamPointerCheckerGroup() -> Group? { return self._containerGroup }

    // L3 Roam (test hook): the container group carrying the roam transform (position + scale).
    var _containerGroupForTest: Group? { return self._containerGroup }

    private func _giveContainerGroup(_ layoutInfo: LayoutRect) -> Group {
        // let containerGroup = this._containerGroup;
        var containerGroup = self._containerGroup
        if containerGroup == nil {
            // FIXME
            // 加一层containerGroup是为了clip，但是现在clip功能并没有实现。
            let g = Group()
            self._containerGroup = g
            containerGroup = g
            self._initEvents(g)
            _ = self.group.add(g)
        }
        // containerGroup.x = layoutInfo.x; containerGroup.y = layoutInfo.y;
        containerGroup!.x = layoutInfo.x
        containerGroup!.y = layoutInfo.y

        return containerGroup!
    }

    private func _doRender(_ containerGroup: Group, _ seriesModel: TreemapSeriesModel) {
        // const thisTree = seriesModel.getData().tree;
        guard let thisTree = seriesModel.getData().tree else {
            return
        }

        // ------------------------------------------------------------------------------------------
        // REUSE render deviation (batch-A morph idiom): upstream builds new/old element storage, runs a
        //   hierarchical `DataDiffer` (`dualTravel`) that reuses graphic elements by rawIndex/id and
        //   records `lastsForAnimation` for `_doAnimation`, then defers removal via `renderFinally`. The
        //   full diff + `_doAnimation` (fade/drill re-root) are still DEFERRED, but the per-node elements
        //   in `_storage` now PERSIST so a same-node-count value change MORPHS: each nodeGroup animates
        //   to its new (x,y) and its bg/content rect resizes to the new layout slot (renderNode reuses by
        //   rawIndex and `updateProps` the shape). A node-count change (or the first render) rebuilds
        //   fresh — the container is wiped and the storage reset (SunburstView/PieView convention).
        // ------------------------------------------------------------------------------------------
        // Count the view nodes of the new tree (structure is stable for a value-only merge). Compared to
        //   the previous render's count to gate morph-vs-rebuild — consistent with `_prevNodeCount`
        //   being stored as this same count below.
        func countNodes(_ node: TreeNode) -> Int {
            var n = 1
            for child in node.viewChildren { n += countNodes(child) }
            return n
        }
        let newNodeCount = countNodes(thisTree.root)
        // Morph iff we already hold persistent node elements AND the node count is unchanged (values
        //   changed → the layout re-laid the same tiles). Else rebuild fresh.
        let canMorph = !self._storage.nodeGroup.isEmpty && self._prevNodeCount == newNodeCount

        if !canMorph {
            _ = containerGroup.removeAll()
            self._storage = RenderElementStorage()
        }

        // dualTravel([thisTree.root], ...) collapsed to a static pre-order travel.
        func travel(_ thisNode: TreeNode, _ parentGroup: Group, _ depth: Double) {
            let group = self.renderNode(seriesModel, thisNode, parentGroup, depth, canMorph)
            // group && dualTravel(thisNode.viewChildren || [], group, depth + 1);
            if let group = group {
                for child in thisNode.viewChildren {
                    travel(child, group, depth + 1)
                }
            }
        }
        travel(thisTree.root, containerGroup, 0)

        // this._oldTree = thisTree; this._storage = thisStorage;
        self._oldTree = thisTree
        self._prevNodeCount = newNodeCount
    }

    // upstream: _doAnimation(...) — DEFERRED (util/animation not ported; static render is the final state).
    // PORT-NOTE (deferred): delete/other animations (fade-out to corner, drill/roll re-root transitions,
    //   fade-in) are not ported.

    // upstream: _resetController(api) / _clearController() / _onPan(e) / _onZoom(e) — DEFERRED.
    // PORT-NOTE (deferred): RoamController re-layout (pan/zoom roam → treemapMove/treemapRender dispatchAction)
    //   is not ported (roam is instead applied as a container transform; see viewGroupRoamApplyStateToGroup).

    private func _initEvents(_ containerGroup: Group) {
        // containerGroup.on('click', (e) => { ... }, this);
        //   The click bubbles up from the per-node rects to this container group, so a single listener
        //   (installed once, when the container group is created) serves every tile — as upstream.
        // PORT-NOTE: upstream's trailing `, this` context argument is DROPPED. `Eventful` retains the
        //   context strongly (EventHandler.ctx, ZRenderKit/Core/Eventful.swift), and this view owns
        //   `_containerGroup`, so passing `self` would form the cycle TreemapView -> Group -> handler.ctx
        //   -> TreemapView and leak the view (and its series data) on dispose. The closure reaches `self`
        //   through the weak capture and never reads the context param — matching SunburstView/TreeView.
        _ = containerGroup.on("click", { [weak self] _, args in
            guard let self = self else { return nil }
            // if (this._state !== 'ready') { return; }
            if self._state != "ready" {
                return nil
            }

            // const nodeClick = this.seriesModel.get('nodeClick', true);
            guard let seriesModel = self.seriesModel else { return nil }
            let nodeClickRaw = seriesModel.get("nodeClick", true)
            // if (!nodeClick) { return; }  — falsy is `false` / nil / '' here.
            if nodeClickRaw == nil || (nodeClickRaw as? Bool) == false || (nodeClickRaw as? String) == "" {
                return nil
            }
            // Bind WITHOUT returning on a non-String value: upstream only string-compares inside the
            //   `else` arm, so a truthy non-string `nodeClick` (e.g. `true`) must still reach the
            //   `isLeafRoot -> _rootToNode` roll-up below.
            let nodeClick = nodeClickRaw as? String

            // const targetInfo = this.findTarget(e.offsetX, e.offsetY);
            guard let e = args.first as? ZRElementEvent else { return nil }
            guard let targetInfo = self.findTarget(e.offsetX, e.offsetY) else {
                // if (!targetInfo) { return; }
                return nil
            }

            // const node = targetInfo.node;
            let node = targetInfo.node
            // if (node.getLayout().isLeafRoot) { this._rootToNode(targetInfo); }
            let isLeafRoot = ((node.getLayout() as? [String: Any])?["isLeafRoot"] as? Bool) ?? false
            if isLeafRoot {
                self._rootToNode(targetInfo)
            }
            else {
                // if (nodeClick === 'zoomToNode') { this._zoomToNode(targetInfo); }
                if nodeClick == "zoomToNode" {
                    self._zoomToNode(targetInfo)
                }
                // else if (nodeClick === 'link') { ... windowOpen(link, linkTarget) ... }
                else if nodeClick == "link" {
                    // const itemModel = node.hostTree.data.getItemModel(node.dataIndex);
                    //   `node.getModel()` is the ported equivalent (nil for dataIndex < 0).
                    let itemModel = node.getModel()
                    // const link = itemModel.get('link', true);
                    let link = itemModel?.get("link", true) as? String
                    // const linkTarget = itemModel.get('target', true) || 'blank';
                    //   JS `||` falls back for the EMPTY STRING too (PORTING.md §8: string truthiness
                    //   replicated explicitly), so `target: ''` must still yield 'blank'.
                    let targetRaw = itemModel?.get("target", true) as? String
                    let linkTarget = (targetRaw?.isEmpty ?? true) ? "blank" : targetRaw!
                    // link && windowOpen(link, linkTarget);
                    if let link = link, !link.isEmpty {
                        format.windowOpen(link, linkTarget)
                    }
                }
            }
            return nil
        })
    }

    private func _renderBreadcrumb(_ seriesModel: TreemapSeriesModel, _ api: ExtensionAPI, _ targetInfoIn: FoundTargetInfo?) {
        var targetInfo = targetInfoIn
        // if (!targetInfo) { targetInfo = leafDepth != null ? {node: getViewRoot()} : findTarget(center); }
        if targetInfo == nil {
            // `getViewRoot()` is `TreeNode?` in the sibling port (upstream is non-null).
            let leafDepth = seriesModel.get("leafDepth", true)
            let explicitSeriesName = seriesModel.get("name", true) as? String
            if let explicitSeriesName = explicitSeriesName, !explicitSeriesName.isEmpty,
               let viewRoot = seriesModel.getViewRoot() {
                // Named treemaps use their named view root as the initial breadcrumb tail. This is
                // what produces a stable root crumb such as `ALL` / `Disk Usage` in the reference;
                // anonymous treemaps instead derive the tail from the tile under the viewport center.
                targetInfo = FoundTargetInfo(node: viewRoot)
            }
            else if leafDepth != nil, !(leafDepth is NSNull), let viewRoot = seriesModel.getViewRoot() {
                targetInfo = FoundTargetInfo(node: viewRoot)
            }
            else {
                // FIXME better way? Find breadcrumb tail on center of containerGroup.
                targetInfo = self.findTarget(api.getWidth() / 2, api.getHeight() / 2)
            }

            // if (!targetInfo) { targetInfo = {node: seriesModel.getData().tree.root}; }
            if targetInfo == nil, let tree = seriesModel.getData().tree {
                targetInfo = FoundTargetInfo(node: tree.root)
            }
        }

        // (this._breadcrumb || (this._breadcrumb = new Breadcrumb(this.group))).render(seriesModel, api, node, onSelect);
        if self._breadcrumb == nil {
            self._breadcrumb = Breadcrumb(self.group)
        }
        guard let targetInfo = targetInfo else {
            return
        }
        self._breadcrumb!.render(seriesModel, api, targetInfo.node) { [weak self] node in
            // if (this._state !== 'animating') {
            //     helper.aboveViewRoot(seriesModel.getViewRoot(), node)
            //         ? this._rootToNode({node: node}) : this._zoomToNode({node: node});
            // }
            guard let self = self, self._state != "animating" else { return }
            // `getViewRoot()` is `TreeNode?` in the sibling port (upstream is non-null).
            guard let viewRoot = seriesModel.getViewRoot() else { return }
            if treeHelper.aboveViewRoot(viewRoot, node) {
                self._rootToNode(FoundTargetInfo(node: node))
            }
            else {
                self._zoomToNode(FoundTargetInfo(node: node))
            }
        }
    }

    /**
     * @override
     */
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // this._clearController();  -> DEFERRED (roam not ported).
        // this._containerGroup && this._containerGroup.removeAll();
        _ = self._containerGroup?.removeAll()
        // this._storage = createStorage();
        self._storage = RenderElementStorage()
        // Persistent-element reuse invariant: a cleared storage must not be treated as morphable next
        //   render, so drop the remembered node count (a subsequent render rebuilds fresh).
        self._prevNodeCount = -1
        // this._state = 'ready';
        self._state = "ready"
        // this._breadcrumb && this._breadcrumb.remove();
        self._breadcrumb?.remove()
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // this._clearController();  -> DEFERRED (roam not ported).
    }

    // private _zoomToNode(targetInfo: FoundTargetInfo) { this.api.dispatchAction({
    //     type: 'treemapZoomToNode', from: this.uid, seriesId: this.seriesModel.id,
    //     targetNode: targetInfo.node }); }
    //   `treemapZoomToNode` is registered (as a noop with update:'updateView') by installTreemapAction;
    //   the actual re-root is performed by the treemapLayout stage, which reads the payload's target node
    //   through `treeHelper.retrieveTargetInfo` on the ensuing update. The driver delivers this payload to
    //   that stage via `ECharts.runSeriesStageHandler(treemapLayout, …, _payload)` — without that thread
    //   the stage sees `payloadType == nil` and the drill-down is a no-op.
    private func _zoomToNode(_ targetInfo: FoundTargetInfo) {
        guard let seriesModel = self.seriesModel, let api = self.api else { return }
        var payload = Payload(type: "treemapZoomToNode")
        payload.other["from"] = self.uid
        payload.other["seriesId"] = seriesModel.id
        payload.other["targetNode"] = targetInfo.node
        api.dispatchAction(payload)
    }

    // private _rootToNode(targetInfo: FoundTargetInfo) { this.api.dispatchAction({
    //     type: 'treemapRootToNode', from: this.uid, seriesId: this.seriesModel.id,
    //     targetNode: targetInfo.node }); }
    private func _rootToNode(_ targetInfo: FoundTargetInfo) {
        guard let seriesModel = self.seriesModel, let api = self.api else { return }
        var payload = Payload(type: "treemapRootToNode")
        payload.other["from"] = self.uid
        payload.other["seriesId"] = seriesModel.id
        payload.other["targetNode"] = targetInfo.node
        api.dispatchAction(payload)
    }

    /**
     * @param x Global coord x.
     * @param y Global coord y.
     * @return info If not found, return undefined;
     */
    public func findTarget(_ x: Double, _ y: Double) -> FoundTargetInfo? {
        // let targetInfo;
        var targetInfo: FoundTargetInfo?
        // const viewRoot = this.seriesModel.getViewRoot();
        guard let viewRoot = self.seriesModel?.getViewRoot() else {
            return nil
        }

        viewRoot.eachNode(["attr": "viewChildren", "order": "preorder"], { (node: TreeNode) -> Any? in
            // const bgEl = this._storage.background[node.getRawIndex()];
            let bgEl = self._storage.background[node.getRawIndex()]
            // If invisible, there might be no element.
            if let bgEl = bgEl {
                // Breadcrumb rendering calls findTarget during the chart render pass, before Storage's
                // normal display-list update has propagated parent transforms. Force that propagation
                // here so nested node groups are hit-tested in global coordinates, matching zrender.
                _ = bgEl.getComputedTransform()
                // const point = bgEl.transformCoordToLocal(x, y);
                let point = bgEl.transformCoordToLocal(x, y)
                // const shape = bgEl.shape;
                let shape = bgEl.shape as! RectShape

                // For performance consideration, don't use 'getBoundingRect'.
                if shape.x <= point[0]
                    && point[0] <= shape.x + shape.width
                    && shape.y <= point[1]
                    && point[1] <= shape.y + shape.height
                {
                    targetInfo = FoundTargetInfo(node: node, offsetX: point[0], offsetY: point[1])
                }
                else {
                    return false // Suppress visit subtree.
                }
            }
            return nil
        })

        return targetInfo
    }

    /**
     * @return Return undefined means do not travel further.
     */
    // upstream: function renderNode(seriesModel, thisStorage, oldStorage, reRoot, lastsForAnimation,
    //   willInvisibleEls, thisNode, oldNode, parentGroup, depth): Group
    // STATIC form: the diff/animation params (oldStorage, reRoot, lastsForAnimation, willInvisibleEls,
    //   oldNode) are dropped; elements are freshly created into `self._storage` each render.
    private func renderNode(
        _ seriesModel: TreemapSeriesModel,
        _ thisNode: TreeNode,
        _ parentGroup: Group,
        _ depth: Double,
        _ canMorph: Bool = false
    ) -> Group? {
        // Whether under viewRoot. (Static: thisNode is always non-null.)

        // const thisLayout = thisNode.getLayout();
        let thisLayoutOpt = thisNode.getLayout() as? [String: Any]
        // const data = seriesModel.getData();
        let data = seriesModel.getData()
        // const nodeModel = thisNode.getModel<TreemapSeriesNodeItemOption>();
        //   PORT-NOTE: `Model?` — nil for dataIndex < 0; upstream assumes non-null. Guard defensively.
        let nodeModel = thisNode.getModel()

        // Only for enabling highlight/downplay. Clear firstly.
        // data.setItemGraphicEl(thisNode.dataIndex, null);
        data.setItemGraphicEl(thisNode.dataIndex, nil)

        // if (!thisLayout || !thisLayout.isInView) { return; }
        guard let thisLayout = thisLayoutOpt,
              (thisLayout["isInView"] as? Bool) ?? false,
              let nodeModel = nodeModel else {
            return nil
        }

        // const thisWidth = thisLayout.width; ... etc
        let thisWidth = (thisLayout["width"] as? Double) ?? 0
        let thisHeight = (thisLayout["height"] as? Double) ?? 0
        let borderWidth = (thisLayout["borderWidth"] as? Double) ?? 0
        let thisInvisible = (thisLayout["invisible"] as? Bool) ?? false

        let thisRawIndex = thisNode.getRawIndex()

        // MORPH reuse: on a same-node-count value change the storage persists, so the prior render's
        //   node group / bg / content for this rawIndex are still present — capture them BEFORE the
        //   creation blocks overwrite the storage slots, then animate (rather than recreate) them.
        let oldGroup = canMorph ? self._storage.nodeGroup[thisRawIndex] : nil
        let oldBg = canMorph ? self._storage.background[thisRawIndex] : nil
        let oldContent = canMorph ? self._storage.content[thisRawIndex] : nil

        // const thisViewChildren = thisNode.viewChildren;
        let thisViewChildren = thisNode.viewChildren
        let upperHeight = (thisLayout["upperHeight"] as? Double) ?? 0
        // const isParent = thisViewChildren && thisViewChildren.length;
        let isParent = !thisViewChildren.isEmpty
        let itemStyleNormalModel = nodeModel.getModel("itemStyle")
        // const itemStyleEmphasisModel = nodeModel.getModel(['emphasis', 'itemStyle']);
        // const itemStyleBlurModel = nodeModel.getModel(['blur', 'itemStyle']);
        // const itemStyleSelectModel = nodeModel.getModel(['select', 'itemStyle']);
        let itemStyleEmphasisModel = nodeModel.getModel(["emphasis", "itemStyle"])
        let itemStyleBlurModel = nodeModel.getModel(["blur", "itemStyle"])
        let itemStyleSelectModel = nodeModel.getModel(["select", "itemStyle"])
        // const borderRadius = itemStyleNormalModel.get('borderRadius') || 0;
        //   `borderRadius` may be a scalar OR a per-corner `number[]` (e.g. [8,8,0,0]); keep it raw
        //   and let makeRectShape map it to `.number`/`.array`. (`|| 0` = no rounding when falsy.)
        let borderRadius: Any? = itemStyleNormalModel.get("borderRadius")

        // Node group
        // const group = giveGraphic('nodeGroup', Group);
        // x,y are not set when el is above view root.
        // group.x = thisLayout.x || 0; group.y = thisLayout.y || 0;
        let layoutX = (thisLayout["x"] as? Double) ?? 0
        let layoutY = (thisLayout["y"] as? Double) ?? 0
        let group: Group
        if let g = oldGroup {
            // MORPH: reuse the node group (already parented in the container hierarchy) and SLIDE it to
            //   the new layout slot via updateProps (animates x/y when the series has animation on, else
            //   snaps). Storage slot already holds `g`.
            group = g
            updateProps(group, ["x": layoutX, "y": layoutY], seriesModel, thisNode.dataIndex)
            group.markRedraw()
        }
        else if thisInvisible {
            // If invisible and no old element, do not create new element (for optimizing).
            return nil
        }
        else {
            group = Group()
            self._storage.nodeGroup[thisRawIndex] = group
            // parentGroup.add(group);
            _ = parentGroup.add(group)
            group.x = layoutX
            group.y = layoutY
            group.markRedraw()
        }
        // inner(group).nodeWidth = thisWidth; inner(group).nodeHeight = thisHeight;  -> DEFERRED (animation).

        // if (thisLayout.isAboveViewRoot) { return group; }
        if (thisLayout["isAboveViewRoot"] as? Bool) ?? false {
            return group
        }

        // Background
        // const bg = giveGraphic('background', Rect, depth, Z2_BG);
        // MORPH: reuse the existing bg rect (already added to `group`) so its shape resizes rather than
        //   snapping; else create fresh.
        let bg: Rect
        let bgReuse: Bool
        if let oldBg = oldBg {
            bg = oldBg
            bgReuse = true
        }
        else {
            bg = Rect()
            bg.z2 = calculateZ2(depth, Z2_BG)
            self._storage.background[thisRawIndex] = bg
            bgReuse = false
        }
        // bg && renderBackground(group, bg, isParent && thisLayout.upperLabelHeight);
        let upperLabelHeight = (thisLayout["upperLabelHeight"] as? Double) ?? 0
        renderBackground(group, bg, isParent && upperLabelHeight != 0, bgReuse)

        // Phase 49 (hover-emphasis): upstream TreemapView.ts:817-825.
        //   const emphasisModel = nodeModel.getModel('emphasis');
        //   const focus = ...; const blurScope = ...; const isDisabled = ...;
        //   const focusOrIndices = focus === 'ancestor' ? thisNode.getAncestorsIndices()
        //       : focus === 'descendant' ? thisNode.getDescendantIndices() : focus;
        let emphasisModel = nodeModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let focusOrIndices = treemapResolveFocus(focus, thisNode)
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

        // No children, render content.
        if isParent {
            // Because of the implementation about "traverse" in graphic hover style, we can not set the
            // hover listener on the "group" of a non-leaf node — the descendants' hover events would be
            // heard. So the BACKGROUND rect is the highDown dispatcher (upstream TreemapView.ts:828-841).
            //   `toggleHoverEmphasis` == setAsHighDownDispatcher(bg, !isDisabled) + enableHoverFocus(bg,…)
            //   (freshly-created bg is not yet a dispatcher, so the upstream `if isHighDownDispatcher(group)
            //   setAsHighDownDispatcher(group,false)` reset is a no-op here).
            // Only for enabling highlight/downplay: data.setItemGraphicEl(thisNode.dataIndex, bg);
            data.setItemGraphicEl(thisNode.dataIndex, bg)
            states.toggleHoverEmphasis(bg, focusOrIndices, blurScope, isDisabled)
        }
        else {
            // const content = giveGraphic('content', Rect, depth, Z2_CONTENT);
            // MORPH: reuse the existing content rect (already added to `group`) so its shape resizes
            //   rather than snapping; else create fresh.
            let content: Rect
            let contentReuse: Bool
            if let oldContent = oldContent {
                content = oldContent
                contentReuse = true
            }
            else {
                content = Rect()
                content.z2 = calculateZ2(depth, Z2_CONTENT)
                self._storage.content[thisRawIndex] = content
                contentReuse = false
            }
            // content && renderContent(group, content);
            renderContent(group, content, contentReuse)

            // (bg as ECElement).disableMorphing = true;
            //   PORT-NOTE: `ECElement` is an augmentation interface Swift cannot add stored props for;
            //   the flag lives in the `makeInner` side store (animation/morphTransitionHelper.swift),
            //   read by `getPathList` — so the node BACKGROUND rect is not a universalTransition morph
            //   endpoint (only its content rect is), exactly as upstream.
            getMorphInner(bg).disableMorphing = true
            // Leaf node: the whole node GROUP is the highDown dispatcher (upstream TreemapView.ts:852-859) —
            //   its child traverse (in enableHoverEmphasis) attaches the state proxy to the bg + content.
            // Only for enabling highlight/downplay: data.setItemGraphicEl(thisNode.dataIndex, group);
            data.setItemGraphicEl(thisNode.dataIndex, group)

            // const cursorStyle = nodeModel.getShallow('cursor'); cursorStyle && content.attr('cursor', cursorStyle);
            if let cursorStyle = nodeModel.getShallow("cursor") {
                _ = content.attr("cursor", cursorStyle)
            }
            states.toggleHoverEmphasis(group, focusOrIndices, blurScope, isDisabled)
        }

        return group

        // ----------------------------
        // | Procedures in renderNode |
        // ----------------------------

        func renderBackground(_ group: Group, _ bg: Rect, _ useUpperLabel: Bool, _ reuse: Bool) {
            // const ecData = getECData(bg); ecData.dataIndex = thisNode.dataIndex; ecData.seriesIndex = ...;
            let ecData = innerStore.getECData(bg)
            ecData.dataIndex = Double(thisNode.dataIndex)
            ecData.seriesIndex = seriesModel.seriesIndex

            // bg.setShape({x: 0, y: 0, width: thisWidth, height: thisHeight, r: borderRadius});
            if reuse {
                // MORPH: keep the rect identity and RESIZE via updateProps (RectShape.animationGet/Set
                //   tween x/y/width/height as scalar Doubles). The corner radius `r` is not tweened, so
                //   fold it onto the current shape directly before animating.
                applyRectRadius(bg, borderRadius)
                updateProps(bg, ["shape": ["x": 0.0, "y": 0.0, "width": thisWidth, "height": thisHeight]], seriesModel, thisNode.dataIndex)
            }
            else {
                _ = bg.setShape(makeRectShape(0, 0, thisWidth, thisHeight, borderRadius))
            }

            if thisInvisible {
                // processInvisible(bg);  -> DEFERRED (delayed-invisible is an animation concern).
                bg.invisible = true
            }
            else {
                bg.invisible = false
                // const style = thisNode.getVisual('style'); const visualBorderColor = style.stroke;
                let style = (thisNode.getVisual("style") as? [String: Any]) ?? [:]
                let visualBorderColor = style["stroke"]
                var normalStyle = getItemStyleNormal(itemStyleNormalModel)
                // normalStyle.fill = visualBorderColor;
                normalStyle["fill"] = visualBorderColor
                // const emphasisStyle = getStateItemStyle(itemStyleEmphasisModel);
                // emphasisStyle.fill = itemStyleEmphasisModel.get('borderColor'); (blur/select likewise)
                //   The BACKGROUND rect's state fill is the state's `borderColor` (not `color`), since the
                //   background represents the container border/gap.
                var emphasisStyle = getStateItemStyle(itemStyleEmphasisModel, nil, nil)
                emphasisStyle["fill"] = itemStyleEmphasisModel.get("borderColor")
                var blurStyle = getStateItemStyle(itemStyleBlurModel, nil, nil)
                blurStyle["fill"] = itemStyleBlurModel.get("borderColor")
                var selectStyle = getStateItemStyle(itemStyleSelectModel, nil, nil)
                selectStyle["fill"] = itemStyleSelectModel.get("borderColor")

                if useUpperLabel {
                    // const upperLabelWidth = thisWidth - 2 * borderWidth;
                    let upperLabelWidth = thisWidth - 2 * borderWidth
                    prepareText(
                        bg, visualBorderColor as? String, style["opacity"] as? Double,
                        makeRectLike(borderWidth, 0, upperLabelWidth, upperHeight)
                    )
                }
                // For old bg. else { bg.removeTextContent(); }
                else {
                    bg.removeTextContent()
                }

                // bg.setStyle(normalStyle); — upstream does not fade a newly-created tile. Treemap's
                // own transition machinery handles drill/roll/update geometry separately.
                bg.useStyle(barStyleFromDict(normalStyle))
                // Phase 49 (hover-emphasis): upstream stamps the emphasis/blur/select itemStyle states +
                //   setDefaultStateProxy on the bg rect (TreemapView.ts:910-914). Ported faithfully via the
                //   treemap `getStateItemStyle` mapping (with the background's `fill = borderColor` override
                //   above) rather than `setStatesStylesFromModel` (standard itemStyle mapping), so the state
                //   colors now match upstream.
                // bg.ensureState('emphasis').style = emphasisStyle; (blur/select likewise)
                bg.ensureState("emphasis").style = emphasisStyle
                bg.ensureState("blur").style = blurStyle
                bg.ensureState("select").style = selectStyle
                // setDefaultStateProxy(bg);
                states.setDefaultStateProxy(bg)
            }

            // group.add(bg);
            // MORPH: a reused bg is already parented — only add a freshly-created rect.
            if !reuse {
                _ = group.add(bg)
            }
        }

        func renderContent(_ group: Group, _ content: Rect, _ reuse: Bool) {
            let ecData = innerStore.getECData(content)
            ecData.dataIndex = Double(thisNode.dataIndex)
            ecData.seriesIndex = seriesModel.seriesIndex

            // const contentWidth = Math.max(thisWidth - 2 * borderWidth, 0);
            let contentWidth = Swift.max(thisWidth - 2 * borderWidth, 0)
            let contentHeight = Swift.max(thisHeight - 2 * borderWidth, 0)

            content.culling = true
            // content.setShape({x: borderWidth, y: borderWidth, width, height, r: borderRadius});
            if reuse {
                // MORPH: resize the reused content rect (see renderBackground).
                applyRectRadius(content, borderRadius)
                updateProps(content, ["shape": ["x": borderWidth, "y": borderWidth, "width": contentWidth, "height": contentHeight]], seriesModel, thisNode.dataIndex)
            }
            else {
                _ = content.setShape(makeRectShape(borderWidth, borderWidth, contentWidth, contentHeight, borderRadius))
            }

            if thisInvisible {
                content.invisible = true
            }
            else {
                content.invisible = false
                // const nodeStyle = thisNode.getVisual('style'); const visualColor = nodeStyle.fill;
                let nodeStyle = (thisNode.getVisual("style") as? [String: Any]) ?? [:]
                let visualColor = nodeStyle["fill"]
                var normalStyle = getItemStyleNormal(itemStyleNormalModel)
                // normalStyle.fill = visualColor; normalStyle.decal = nodeStyle.decal;
                normalStyle["fill"] = visualColor
                normalStyle["decal"] = nodeStyle["decal"]
                // const emphasisStyle = getStateItemStyle(itemStyleEmphasisModel); (blur/select likewise)
                //   The CONTENT rect keeps the state's mapped `color`→`fill` (no borderColor override).
                let emphasisStyle = getStateItemStyle(itemStyleEmphasisModel, nil, nil)
                let blurStyle = getStateItemStyle(itemStyleBlurModel, nil, nil)
                let selectStyle = getStateItemStyle(itemStyleSelectModel, nil, nil)

                prepareText(content, visualColor as? String, nodeStyle["opacity"] as? Double, nil)

                // content.setStyle(normalStyle); — no ad-hoc opacity entrance in upstream.
                content.useStyle(barStyleFromDict(normalStyle))
                // Phase 49 (hover-emphasis): emphasis/blur/select itemStyle states + setDefaultStateProxy on
                //   the content rect (TreemapView.ts:961-962). Ported faithfully via `getStateItemStyle`.
                // content.ensureState('emphasis').style = emphasisStyle; (blur/select likewise)
                content.ensureState("emphasis").style = emphasisStyle
                content.ensureState("blur").style = blurStyle
                content.ensureState("select").style = selectStyle
                // setDefaultStateProxy(content);
                states.setDefaultStateProxy(content)
            }

            // group.add(content);
            // MORPH: a reused content rect is already parented — only add a freshly-created rect.
            if !reuse {
                _ = group.add(content)
            }
        }

        // upstream: processInvisible(element) — DEFERRED (delayed invisible is an animation concern).

        // upstream: prepareText(rectEl, visualColor, visualOpacity, upperLabelRect)
        // Routes the tile label through the shared label core (labelStyle.setLabelStyle /
        //   getLabelStatesModels) — the label is ATTACHED as `rectEl`'s textContent and positioned by
        //   the host's textConfig (createTextConfig writes position "inside" by default), so the view no
        //   longer builds/positions a ZRText by hand.
        func prepareText(
            _ rectEl: Rect,
            _ visualColor: String?,
            _ visualOpacity: Double?,
            _ upperLabelRect: RectLike?
        ) {
            // const normalLabelModel = nodeModel.getModel(upperLabelRect ? 'upperLabel' : 'label');
            let normalLabelModel = nodeModel.getModel(upperLabelRect != nil ? PATH_UPPERLABEL_NORMAL : PATH_LABEL_NOAMAL)

            // const defaultText = convertOptionIdName(nodeModel.get('name'), null);
            let defaultText = model.convertOptionIdName(nodeModel.get("name"), nil)

            // const isShow = normalLabelModel.getShallow('show');
            let isShow = (normalLabelModel.getShallow("show") as? Bool) ?? false

            // setLabelStyle(rectEl, getLabelStatesModels(nodeModel, upperLabelRect ? 'upperLabel' : 'label'),
            //   { defaultText: isShow ? defaultText : null, inheritColor, defaultOpacity, labelFetcher, labelDataIndex });
            // setLabelStyle owns show/hide (reads the label model `show` — hides when false) and attaches
            //   the label as `rectEl`'s textContent + textConfig; the painter renders textContent.
            labelStyle.setLabelStyle(
                rectEl,
                labelStyle.getLabelStatesModels(
                    nodeModel, upperLabelRect != nil ? PATH_UPPERLABEL_NORMAL : PATH_LABEL_NOAMAL
                ),
                SetLabelStyleOpt(
                    inheritColor: visualColor,
                    defaultOpacity: visualOpacity,
                    defaultText: isShow ? defaultText : nil,
                    labelFetcher: seriesModel,
                    labelDataIndex: Double(thisNode.dataIndex)
                )
            )

            // const textEl = rectEl.getTextContent(); if (!textEl) { return; }
            guard let textEl = rectEl.getTextContent() else {
                return
            }

            if let up = upperLabelRect {
                // upstream: rectEl.setTextConfig({ layoutRect: upperLabelRect }) — a field MERGE. The
                //   ported `setTextConfig` REPLACES the config (see Element.swift PORT-NOTE), so mutate
                //   the existing config to preserve the `position` just written by setLabelStyle.
                var tc = rectEl.textConfig ?? ElementTextConfig()
                tc.layoutRect = up
                rectEl.setTextConfig(tc)
                // (textEl as ECElement).disableLabelLayout = true -> DEFERRED (no ECElement.disableLabelLayout field).
            }

            // const textStyle = textEl.style;
            // const textPadding = normalizeCssArray(textStyle.padding || 0);
            var textStyle = textEl.textStyle ?? TextStyleProps()
            let textPadding = treemapNormalizeCssArray4(textStyle.padding)

            // upstream `textEl.beforeUpdate = function () { const width/height = (upperLabelRect ?
            //   upperLabelRect : rectEl.shape).{width,height} - textPadding[..]; textEl.setStyle({width,
            //   height}); }` — a per-frame hook (`Element.beforeUpdate` is a non-settable method in the
            //   port, so no closure hook). The rect shape / upperLabelRect are already at their final
            //   size by the time prepareText runs (renderContent/renderBackground set the shape first),
            //   so the width/height are computed ONCE here. Without them `overflow`/`lineOverflow:
            //   'truncate'` has no box to truncate against and the label is dropped entirely.
            let boxWidth = upperLabelRect?.width ?? ((rectEl.shape as? RectShape)?.width ?? 0)
            let boxHeight = upperLabelRect?.height ?? ((rectEl.shape as? RectShape)?.height ?? 0)
            let labelWidth = Swift.max(boxWidth - textPadding[1] - textPadding[3], 0)
            let labelHeight = Swift.max(boxHeight - textPadding[0] - textPadding[2], 0)
            textStyle.width = labelWidth
            textStyle.height = labelHeight

            // textStyle.truncateMinChar = 2; textStyle.lineOverflow = 'truncate';
            textStyle.truncateMinChar = 2
            textStyle.lineOverflow = "truncate"

            // addDrillDownIcon(textStyle, upperLabelRect, thisLayout): a leaf-root node (a node at
            //   `leafDepth` that still has hidden children — i.e. it is drillable) gets its label
            //   prefixed with the series `drillDownIcon` (default '▶'). Ported for the NORMAL,
            //   non-upperLabel label; the emphasis-state variant remains DEFERRED (states).
            if upperLabelRect == nil,
               (thisLayout["isLeafRoot"] as? Bool) ?? false,
               let icon = seriesModel.get("drillDownIcon", true) as? String, !icon.isEmpty,
               let curText = textStyle.text, !curText.isEmpty {
                textStyle.text = icon + "  " + curText
            }

            textEl.useStyle(textStyle)
            textEl.name = "treemapLabel"

        }
    }
}

// upstream: function createStorage() { return { nodeGroup: [], background: [], content: [] }; }
//   -> `RenderElementStorage()` (see the class above).

// We cannot set all background with the same z, because the behaviour of drill down and roll up differ
// background creation sequence from tree hierarchy sequence, which cause lower background elements to
// overlap upper ones. So we calculate z based on depth. Moreover, we try to shrink down z interval to
// [0, 1] to avoid that treemap with large z overlaps other components.
private func calculateZ2(_ depth: Double, _ z2InLevel: Double) -> Double {
    return depth * Z2_BASE + z2InLevel
}

// Helpers (not upstream symbols): build the `{x,y,width,height,r}` RectShape / RectLike bags.
private func makeRectShape(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ r: Any?) -> RectShape {
    var shape = RectShape()
    shape.x = x
    shape.y = y
    shape.width = width
    shape.height = height
    shape.r = rectRadiusFromOption(r)
    return shape
}

// upstream `r: borderRadius` where borderRadius = get('borderRadius') || 0 — a scalar OR a
// per-corner `number[]` ([r1,r2,r3,r4] shorthands). A falsy scalar (nil / 0) → no rounding.
private func rectRadiusFromOption(_ r: Any?) -> RectRadius? {
    if let arr = r as? [Double] {
        return arr.isEmpty ? nil : .array(arr)
    }
    if let arr = r as? [Any] {
        let ds = arr.map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) }
        return ds.isEmpty ? nil : .array(ds)
    }
    let d = (r as? Double) ?? Double((r as? Int) ?? 0)
    return d != 0 ? .number(d) : nil
}

// MORPH helper: fold the (possibly changed) corner radius onto a reused rect's CURRENT shape without
//   disturbing its x/y/width/height — those are animated separately by updateProps and must keep their
//   current values as the tween's start. `r` is not a tweened field, so it is applied directly.
private func applyRectRadius(_ rect: Rect, _ r: Any?) {
    guard var shape = rect.shape as? RectShape else { return }
    shape.r = rectRadiusFromOption(r)
    rect.shape = shape
    rect.dirtyShape()
}

private func makeRectLike(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> RectLike {
    // `RectLike` is a protocol (AnyObject); `BoundingRect` is the concrete conformer.
    return BoundingRect(x, y, width, height)
}

// upstream `zrUtil.normalizeCssArray(textStyle.padding || 0)` → [top, right, bottom, left]. Mirrors the
//   CSS-shorthand expansion (1→all, 2→[v,h], 3→[t,h,b]). `nil` padding (the `|| 0` fallback) → zeros.
private func treemapNormalizeCssArray4(_ p: NumberOrNumberArray?) -> [Double] {
    switch p {
    case .none:
        return [0, 0, 0, 0]
    case .some(.number(let v)):
        return [v, v, v, v]
    case .some(.array(let a)):
        switch a.count {
        case 0: return [0, 0, 0, 0]
        case 1: return [a[0], a[0], a[0], a[0]]
        case 2: return [a[0], a[1], a[0], a[1]]
        case 3: return [a[0], a[1], a[2], a[1]]
        default: return [a[0], a[1], a[2], a[3]]
        }
    }
}

// Phase 49 (hover-emphasis): resolve a treemap node `emphasis.focus` string to its lineage index set
//   (upstream TreemapView.ts:822-825). 'ancestor' / 'descendant' → that side's dataIndices (the
//   ARRAY-focus form `states.blurSeries` consumes); any other focus ('self'/'series'/indices/nil) passes
//   through unchanged.
private func treemapResolveFocus(_ focus: InnerFocus?, _ node: TreeNode) -> InnerFocus? {
    switch focus as? String {
    case "ancestor":   return node.getAncestorsIndices()
    case "descendant": return node.getDescendantIndices()
    default:           return focus
    }
}

// export default TreemapView;  -> `open class TreemapView` above.
