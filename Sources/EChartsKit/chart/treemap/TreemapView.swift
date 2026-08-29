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
//       -> RoamController IS ported (component/helper/RoamController.swift); the live host owns the
//          controller, while this view ports upstream's controller options and pan/zoom handlers.
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

// const DRAG_THRESHOLD = 3;
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
// Swift dictionaries preserve the upstream sparse-array semantics while keeping raw-index lookup explicit.
private final class RenderElementStorage {
    var nodeGroup: [Int: Group] = [:]
    var background: [Int: Rect] = [:]
    var content: [Int: Rect] = [:]
}

private struct LastCfg {
    var oldX: Double?
    var oldY: Double?
    var oldShape: RectShape?
    var fadein = false
}

private final class LastCfgStorage {
    var nodeGroup: [Int: LastCfg] = [:]
    var background: [Int: LastCfg] = [:]
    var content: [Int: LastCfg] = [:]
}

private struct ReRoot {
    var rootNodeGroup: Group?
    var direction: String?
}

private struct RenderResult {
    var lastsForAnimation: LastCfgStorage
    var willDeleteEls: RenderElementStorage
    var willInvisibleEls: [Rect]
}

private struct TreemapElementMeta {
    var nodeWidth: Double = 0
    var nodeHeight: Double = 0
    var willDelete = false
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
    // private _controller: RoamController;
    // The live EChartsView owns the controller because it owns zr; its listeners are configured here.

    // private _oldTree: Tree;
    private var _oldTree: Tree?

    // private _state: 'ready' | 'animating' = 'ready';
    private var _state: String = "ready"

    // In upstream, `findTarget` reads zrender transforms from the last painted frame. The Swift model
    // update mutates the live hierarchy synchronously, so keep the center hit that belonged to that
    // painted frame for the current pan turn. A real zrender `rendered` event advances the snapshot,
    // preserving the same behavior when pointer moves span multiple frames.
    private weak var _roamZr: ZRenderType?
    private var _roamMouseDownToken: EventHandlerToken?
    private var _roamMouseUpToken: EventHandlerToken?
    private var _roamGlobalOutToken: EventHandlerToken?
    private var _roamRenderedToken: EventHandlerToken?
    private var _paintedPanBreadcrumbTarget: FoundTargetInfo?
    private var _pendingPanBreadcrumbTarget: FoundTargetInfo?

    // private _storage = createStorage();
    private var _storage = RenderElementStorage()

    // zrender's `inner(el)` fields used by the upstream treemap animation. Kept per element identity.
    private var _elementMeta: [ObjectIdentifier: TreemapElementMeta] = [:]

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
        // const payloadType = payload && payload.type;
        // const layoutInfo = seriesModel.layoutInfo;
        //   `seriesModel.layoutInfo` is the treemapLayout output rect (`LayoutRect?` in the sibling port;
        //   non-null upstream after the layout stage). Bail if the layout has not run.
        guard let layoutInfo = seriesModel.layoutInfo else {
            return
        }
        // const isInit = !this._oldTree;
        let isInit = self._oldTree == nil
        // const thisStorage = this._storage;
        let thisStorage = self._storage

        // Mark new root when action is treemapRootToNode.
        // const reRoot = (payloadType === 'treemapRootToNode' && targetInfo && thisStorage)
        //     ? { rootNodeGroup: thisStorage.nodeGroup[targetInfo.node.getRawIndex()], direction: payload.direction }
        //     : null;
        let payloadType = payload.type
        let reRoot: ReRoot? = payloadType == "treemapRootToNode" && targetInfo != nil
            ? ReRoot(
                rootNodeGroup: thisStorage.nodeGroup[targetInfo!.node.getRawIndex()],
                direction: seriesModel.consumeTreemapRootDirection()
            )
            : nil

        // const containerGroup = this._giveContainerGroup(layoutInfo);
        let containerGroup = self._giveContainerGroup(layoutInfo)
        // const hasAnimation = seriesModel.get('animation');
        let hasAnimation = (seriesModel.get("animation") as? Bool) != false
        let shouldAnimate = hasAnimation && !isInit && (
            payloadType.isEmpty
                || payloadType == "treemapZoomToNode"
                || payloadType == "treemapRootToNode"
        )

        // const renderResult = this._doRender(containerGroup, seriesModel, reRoot);
        let renderResult = self._doRender(containerGroup, seriesModel, reRoot)
        if shouldAnimate {
            self._doAnimation(containerGroup, renderResult, seriesModel, reRoot)
        }
        else {
            self._renderFinally(renderResult)
        }

        // this._renderBreadcrumb(seriesModel, api, targetInfo);
        let breadcrumbTargetInfo: FoundTargetInfo?
        if payloadType == "treemapMove" {
            breadcrumbTargetInfo = self._pendingPanBreadcrumbTarget
            self._pendingPanBreadcrumbTarget = nil
        }
        else {
            breadcrumbTargetInfo = targetInfo
        }
        self._renderBreadcrumb(seriesModel, api, breadcrumbTargetInfo)
    }

    // Test hook for the rendered container. Upstream roam changes the root layout rather than scaling it.
    var _containerGroupForTest: Group? { return self._containerGroup }

    // Upstream `_resetController`. EChartsView supplies the live controller after the view root is attached
    // to zr; all options, pointer containment and dispatched action payloads remain the upstream ones.
    func resetRoamController(_ controller: RoamController, _ api: ExtensionAPI) {
        guard let seriesModel = self.seriesModel else { controller.disable(); return }
        controller.enable(seriesModel.get("roam"), RoamOption(
            component: seriesModel,
            api: api,
            isInSelf: { [weak self] _, x, y in
                guard let group = self?._containerGroup,
                      let rect = group.getBoundingRect() else { return false }
                return rect.contain(x - group.x, y - group.y)
            },
            isInClip: nil,
            roamTrigger: seriesModel.get("roamTrigger") as? String
        ))
        controller
            .off("pan")
            .off("zoom")
            .on("pan", { [weak self] event in
                self?._onPan(event)
            })
            .on("zoom", { [weak self] event in
                self?._onZoom(event)
            })

        if let zr = api.getZr(), self._roamZr !== zr {
            self._unbindRoamFrameObservers()
            self._roamZr = zr
            self._roamMouseDownToken = zr.onWithToken("mousedown", { [weak self] _, _ in
                guard let self, let seriesModel = self.seriesModel, let api = self.api else { return nil }
                self._paintedPanBreadcrumbTarget = self._resolveBreadcrumbTarget(seriesModel, api)
                return nil
            })
            let clearPanSnapshot: EventCallback = { [weak self] _, _ in
                self?._paintedPanBreadcrumbTarget = nil
                return nil
            }
            self._roamMouseUpToken = zr.onWithToken("mouseup", clearPanSnapshot)
            self._roamGlobalOutToken = zr.onWithToken("globalout", clearPanSnapshot)
            self._roamRenderedToken = zr.onWithToken("rendered", { [weak self, weak controller] _, _ in
                guard let self, let controller, controller.isDragging(),
                      let seriesModel = self.seriesModel, let api = self.api else { return nil }
                self._paintedPanBreadcrumbTarget = self._resolveBreadcrumbTarget(seriesModel, api)
                return nil
            })
        }
    }

    // Upstream `_onPan`: move the root rect and let treemapLayout re-layout every tile.
    private func _onPan(_ event: RoamEventParams) {
        guard self._state != "animating",
              abs(event.dx) > DRAG_THRESHOLD || abs(event.dy) > DRAG_THRESHOLD,
              let seriesModel = self.seriesModel,
              let root = seriesModel.getData().tree?.root,
              let rootLayout = root.getLayout() as? [String: Any],
              let x = treemapNumber(rootLayout["x"]),
              let y = treemapNumber(rootLayout["y"]),
              let width = treemapNumber(rootLayout["width"]),
              let height = treemapNumber(rootLayout["height"]),
              let api = self.api else { return }

        var payload = Payload(type: "treemapMove")
        payload.other["from"] = self.uid
        payload.other["seriesId"] = seriesModel.id
        payload.other["rootRect"] = [
            "x": x + event.dx, "y": y + event.dy,
            "width": width, "height": height,
        ] as [String: Double]
        self._pendingPanBreadcrumbTarget = self._paintedPanBreadcrumbTarget
            ?? self._resolveBreadcrumbTarget(seriesModel, api)
        api.dispatchAction(payload)
    }

    // Upstream `_onZoom`: scale the current root rect about the pointer in container coordinates and
    // dispatch `treemapRender`, preserving border and label sizes because layout is recomputed.
    private func _onZoom(_ event: RoamEventParams) {
        guard self._state != "animating",
              let seriesModel = self.seriesModel,
              let root = seriesModel.getData().tree?.root,
              let rootLayout = root.getLayout() as? [String: Any],
              let rootX = treemapNumber(rootLayout["x"]),
              let rootY = treemapNumber(rootLayout["y"]),
              let rootWidth = treemapNumber(rootLayout["width"]),
              let rootHeight = treemapNumber(rootLayout["height"]),
              let layoutInfo = seriesModel.layoutInfo,
              let api = self.api else { return }

        let currentZoom = calculateCurrentZoom(
            (width: layoutInfo.width, height: layoutInfo.height),
            (width: rootWidth, height: rootHeight)
        )
        let newZoom = treemapClampZoom(currentZoom * event.scale, seriesModel)
        let zoomScale = newZoom / currentZoom
        let mouseX = event.originX - layoutInfo.x
        let mouseY = event.originY - layoutInfo.y

        var payload = Payload(type: "treemapRender")
        payload.other["from"] = self.uid
        payload.other["seriesId"] = seriesModel.id
        payload.other["rootRect"] = [
            "x": mouseX + (rootX - mouseX) * zoomScale,
            "y": mouseY + (rootY - mouseY) * zoomScale,
            "width": rootWidth * zoomScale,
            "height": rootHeight * zoomScale,
        ] as [String: Double]
        api.dispatchAction(payload)
    }

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

    private func _doRender(
        _ containerGroup: Group, _ seriesModel: TreemapSeriesModel, _ reRoot: ReRoot?
    ) -> RenderResult {
        guard let thisTree = seriesModel.getData().tree else {
            return RenderResult(
                lastsForAnimation: LastCfgStorage(),
                willDeleteEls: RenderElementStorage(),
                willInvisibleEls: []
            )
        }
        let oldTree = self._oldTree
        let lastsForAnimation = LastCfgStorage()
        let thisStorage = RenderElementStorage()
        let oldStorage = self._storage
        var willInvisibleEls: [Rect] = []

        func doRenderNode(
            _ thisNode: TreeNode?, _ oldNode: TreeNode?, _ parentGroup: Group, _ depth: Double
        ) -> Group? {
            self.renderNode(
                seriesModel, thisStorage, oldStorage, reRoot,
                lastsForAnimation, &willInvisibleEls,
                thisNode, oldNode, parentGroup, depth
            )
        }

        func dualTravel(
            _ thisViewChildren: [TreeNode], _ oldViewChildrenIn: [TreeNode],
            _ parentGroup: Group, _ sameTree: Bool, _ depth: Double
        ) {
            var oldViewChildren = oldViewChildrenIn

            func processNode(_ newIndex: Int?, _ oldIndex: Int?) {
                let thisNode = newIndex.map { thisViewChildren[$0] }
                let oldNode = oldIndex.map { oldViewChildren[$0] }
                let group = doRenderNode(thisNode, oldNode, parentGroup, depth)
                if let group = group {
                    dualTravel(
                        thisNode?.viewChildren ?? [], oldNode?.viewChildren ?? [],
                        group, sameTree, depth + 1
                    )
                }
            }

            if sameTree {
                oldViewChildren = thisViewChildren
                for (index, child) in thisViewChildren.enumerated() where !child.isRemoved() {
                    processNode(index, index)
                }
            }
            else {
                let oldAny = oldViewChildren.map { $0 as Any }
                let newAny = thisViewChildren.map { $0 as Any }
                let key: DiffKeyGetter = { value, _ in (value as! TreeNode).getId() }
                DataDiffer<Void>(oldAny, newAny, key, key)
                    .add { processNode($0, nil) }
                    .update { processNode($0, $1) }
                    .remove { processNode(nil, $0) }
                    .execute()
            }
        }

        dualTravel(
            [thisTree.root], oldTree.map { [$0.root] } ?? [], containerGroup,
            oldTree == nil || oldTree === thisTree, 0
        )

        let willDeleteEls = RenderElementStorage()
        func moveDeleted<T: Element>(_ source: inout [Int: T], _ destination: inout [Int: T]) {
            for (rawIndex, element) in source {
                destination[rawIndex] = element
                var meta = self._elementMeta[ObjectIdentifier(element)] ?? TreemapElementMeta()
                meta.willDelete = true
                self._elementMeta[ObjectIdentifier(element)] = meta
            }
            source.removeAll()
        }
        moveDeleted(&oldStorage.nodeGroup, &willDeleteEls.nodeGroup)
        moveDeleted(&oldStorage.background, &willDeleteEls.background)
        moveDeleted(&oldStorage.content, &willDeleteEls.content)

        self._oldTree = thisTree
        self._storage = thisStorage
        return RenderResult(
            lastsForAnimation: lastsForAnimation,
            willDeleteEls: willDeleteEls,
            willInvisibleEls: willInvisibleEls
        )
    }

    private func _renderFinally(_ renderResult: RenderResult) {
        let allDeleted: [Element] = Array(renderResult.willDeleteEls.nodeGroup.values)
            + Array(renderResult.willDeleteEls.background.values)
            + Array(renderResult.willDeleteEls.content.values)
        for element in allDeleted {
            if let parent = element.parent as? Group { _ = parent.remove(element) }
            self._elementMeta[ObjectIdentifier(element)] = nil
        }
        for element in renderResult.willInvisibleEls {
            element.invisible = true
            element.markRedraw()
        }
    }

    private func _doAnimation(
        _ containerGroup: Group, _ renderResult: RenderResult,
        _ seriesModel: TreemapSeriesModel, _ reRoot: ReRoot?
    ) {
        _ = containerGroup
        let duration = treemapNumber(seriesModel.get("animationDurationUpdate")) ?? 0
        let easing = (seriesModel.get("animationEasing") as? String).map(AnimationEasing.named)
            ?? .named("cubicOut")

        struct PendingAnimation {
            var element: Element
            var target: ElementProps
        }
        var animations: [PendingAnimation] = []

        func addDeleteAnimations<T: Element>(_ store: [Int: T], _ storageName: String) {
            for element in store.values {
                if let displayable = element as? Displayable, displayable.invisible { continue }
                guard let parent = element.parent else { continue }
                let innerStore = self._elementMeta[ObjectIdentifier(parent)] ?? TreemapElementMeta()
                var target: ElementProps = [:]

                if reRoot?.direction == "drillDown" {
                    if parent === reRoot?.rootNodeGroup, element is Rect {
                        target["shape"] = [
                            "x": 0.0, "y": 0.0,
                            "width": innerStore.nodeWidth, "height": innerStore.nodeHeight,
                        ] as [String: Any]
                        target["style"] = ["opacity": 0.0] as [String: Any]
                    }
                    else if element is Displayable {
                        target["style"] = ["opacity": 0.0] as [String: Any]
                    }
                }
                else {
                    var targetX = 0.0
                    var targetY = 0.0
                    if !innerStore.willDelete {
                        targetX = innerStore.nodeWidth / 2
                        targetY = innerStore.nodeHeight / 2
                    }
                    if storageName == "nodeGroup" {
                        target["x"] = targetX
                        target["y"] = targetY
                    }
                    else {
                        target["shape"] = [
                            "x": targetX, "y": targetY, "width": 0.0, "height": 0.0,
                        ] as [String: Any]
                        target["style"] = ["opacity": 0.0] as [String: Any]
                    }
                }
                if !target.isEmpty { animations.append(PendingAnimation(element: element, target: target)) }
            }
        }
        addDeleteAnimations(renderResult.willDeleteEls.nodeGroup, "nodeGroup")
        addDeleteAnimations(renderResult.willDeleteEls.background, "background")
        addDeleteAnimations(renderResult.willDeleteEls.content, "content")

        func addCurrentGroupAnimations(_ store: [Int: Group], _ lasts: [Int: LastCfg]) {
            for (rawIndex, element) in store {
                guard let last = lasts[rawIndex], let oldX = last.oldX, let oldY = last.oldY else { continue }
                let target: ElementProps = ["x": element.x, "y": element.y]
                element.x = oldX
                element.y = oldY
                element.markRedraw()
                animations.append(PendingAnimation(element: element, target: target))
            }
        }
        func addCurrentRectAnimations(_ store: [Int: Rect], _ lasts: [Int: LastCfg]) {
            for (rawIndex, element) in store {
                guard let last = lasts[rawIndex] else { continue }
                var target: ElementProps = [:]
                if let oldShape = last.oldShape, let finalShape = element.shape as? RectShape {
                    target["shape"] = [
                        "x": finalShape.x, "y": finalShape.y,
                        "width": finalShape.width, "height": finalShape.height,
                    ] as [String: Any]
                    _ = element.setShape(oldShape)
                }
                if last.fadein {
                    // `Rect` stores its rich style in `pathStyle`; the inherited Displayable
                    // `setStyle(key:value:)` writes the separate common-style bag and would leave the
                    // painted opacity unchanged. Upstream `el.setStyle('opacity', 0)` targets pathStyle.
                    if var style = element.pathStyle {
                        style.opacity = 0
                        element.pathStyle = style
                        element.dirtyStyle()
                    }
                    target["style"] = ["opacity": 1.0] as [String: Any]
                }
                else if (element.pathStyle.opacity ?? 1) != 1 {
                    target["style"] = ["opacity": 1.0] as [String: Any]
                }
                if !target.isEmpty { animations.append(PendingAnimation(element: element, target: target)) }
            }
        }
        addCurrentGroupAnimations(self._storage.nodeGroup, renderResult.lastsForAnimation.nodeGroup)
        addCurrentRectAnimations(self._storage.background, renderResult.lastsForAnimation.background)
        addCurrentRectAnimations(self._storage.content, renderResult.lastsForAnimation.content)

        guard !animations.isEmpty, duration > 0 else {
            self._renderFinally(renderResult)
            self._state = "ready"
            return
        }

        self._state = "animating"
        var remaining = animations.count
        let finishOne: () -> Void = { [weak self] in
            remaining -= 1
            if remaining == 0 {
                self?._state = "ready"
                self?._renderFinally(renderResult)
            }
        }
        func config() -> ElementAnimateConfig {
            var config = ElementAnimateConfig()
            config.duration = duration
            config.delay = 0
            config.easing = easing
            config.setToFinal = false
            config.scope = "treemap-transition"
            config.done = finishOne
            config.aborted = finishOne
            return config
        }
        for animation in animations {
            animation.element.animateTo(animation.target, config())
        }
    }

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

    private func _renderBreadcrumb(
        _ seriesModel: TreemapSeriesModel, _ api: ExtensionAPI,
        _ targetInfoIn: FoundTargetInfo?
    ) {
        // if (!targetInfo) { ... viewport center ... root fallback }
        var targetInfo = targetInfoIn
        if targetInfo == nil {
            let leafDepth = seriesModel.get("leafDepth", true)
            targetInfo = leafDepth != nil && !(leafDepth is NSNull)
                ? seriesModel.getViewRoot().map { FoundTargetInfo(node: $0) }
                // FIXME better way? Find breadcrumb tail on center of containerGroup.
                : self.findTarget(api.getWidth() / 2, api.getHeight() / 2)

            if targetInfo == nil {
                targetInfo = seriesModel.getData().tree.map { FoundTargetInfo(node: $0.root) }
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

    private func _resolveBreadcrumbTarget(
        _ seriesModel: TreemapSeriesModel, _ api: ExtensionAPI
    ) -> FoundTargetInfo? {
        let leafDepth = seriesModel.get("leafDepth", true)
        if leafDepth != nil, !(leafDepth is NSNull), let viewRoot = seriesModel.getViewRoot() {
            return FoundTargetInfo(node: viewRoot)
        }
        if let target = self.findTarget(api.getWidth() / 2, api.getHeight() / 2) {
            return target
        }
        return seriesModel.getData().tree.map { FoundTargetInfo(node: $0.root) }
    }

    private func _unbindRoamFrameObservers() {
        guard let zr = self._roamZr else { return }
        if let token = self._roamMouseDownToken { zr.off("mousedown", token: token) }
        if let token = self._roamMouseUpToken { zr.off("mouseup", token: token) }
        if let token = self._roamGlobalOutToken { zr.off("globalout", token: token) }
        if let token = self._roamRenderedToken { zr.off("rendered", token: token) }
        self._roamMouseDownToken = nil
        self._roamMouseUpToken = nil
        self._roamGlobalOutToken = nil
        self._roamRenderedToken = nil
        self._roamZr = nil
        self._paintedPanBreadcrumbTarget = nil
        self._pendingPanBreadcrumbTarget = nil
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
        self._elementMeta.removeAll()
        // this._state = 'ready';
        self._state = "ready"
        // this._breadcrumb && this._breadcrumb.remove();
        self._breadcrumb?.remove()
        self._unbindRoamFrameObservers()
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._unbindRoamFrameObservers()
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
    private func renderNode(
        _ seriesModel: TreemapSeriesModel,
        _ thisStorage: RenderElementStorage,
        _ oldStorage: RenderElementStorage,
        _ reRoot: ReRoot?,
        _ lastsForAnimation: LastCfgStorage,
        _ willInvisibleEls: inout [Rect],
        _ thisNodeIn: TreeNode?,
        _ oldNode: TreeNode?,
        _ parentGroup: Group,
        _ depth: Double
    ) -> Group? {
        // Whether under viewRoot.
        guard let thisNode = thisNodeIn else { return nil }

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
        let oldRawIndex = oldNode?.getRawIndex()

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

        func prepareAnimationWhenNoOld(_ isGroup: Bool) -> LastCfg {
            var last = LastCfg()
            if let parentNode = thisNode.parentNode,
               reRoot == nil || reRoot?.direction == "drillDown" {
                var parentOldX = 0.0
                var parentOldY = 0.0
                if reRoot == nil,
                   let parentOldShape = lastsForAnimation.background[parentNode.getRawIndex()]?.oldShape {
                    parentOldX = parentOldShape.width
                    parentOldY = parentOldShape.height
                }
                if isGroup {
                    last.oldX = 0
                    last.oldY = parentOldY
                }
                else {
                    var shape = RectShape()
                    shape.x = parentOldX
                    shape.y = parentOldY
                    shape.width = 0
                    shape.height = 0
                    last.oldShape = shape
                }
            }
            last.fadein = !isGroup
            return last
        }

        func giveGroup() -> Group? {
            var element: Group?
            if let oldRawIndex, let reused = oldStorage.nodeGroup.removeValue(forKey: oldRawIndex) {
                element = reused
                lastsForAnimation.nodeGroup[thisRawIndex] = LastCfg(oldX: reused.x, oldY: reused.y)
                var meta = self._elementMeta[ObjectIdentifier(reused)] ?? TreemapElementMeta()
                meta.willDelete = false
                self._elementMeta[ObjectIdentifier(reused)] = meta
            }
            else if !thisInvisible {
                let created = Group()
                element = created
                lastsForAnimation.nodeGroup[thisRawIndex] = prepareAnimationWhenNoOld(true)
            }
            thisStorage.nodeGroup[thisRawIndex] = element
            return element
        }

        func giveRect(
            _ storageName: String, _ old: inout [Int: Rect], _ current: inout [Int: Rect]
        ) -> Rect? {
            var element: Rect?
            if let oldRawIndex, let reused = old.removeValue(forKey: oldRawIndex) {
                element = reused
                setLastsForAnimation(storageName, LastCfg(oldShape: reused.shape as? RectShape))
                var meta = self._elementMeta[ObjectIdentifier(reused)] ?? TreemapElementMeta()
                meta.willDelete = false
                self._elementMeta[ObjectIdentifier(reused)] = meta
            }
            else if !thisInvisible {
                let created = Rect()
                element = created
                setLastsForAnimation(storageName, prepareAnimationWhenNoOld(false))
            }
            current[thisRawIndex] = element
            return element
        }

        func setLastsForAnimation(_ storageName: String, _ value: LastCfg) {
            if storageName == "background" { lastsForAnimation.background[thisRawIndex] = value }
            else { lastsForAnimation.content[thisRawIndex] = value }
        }

        // Node group
        // const group = giveGraphic('nodeGroup', Group);
        // x,y are not set when el is above view root.
        // group.x = thisLayout.x || 0; group.y = thisLayout.y || 0;
        let layoutX = (thisLayout["x"] as? Double) ?? 0
        let layoutY = (thisLayout["y"] as? Double) ?? 0
        guard let group = giveGroup() else { return nil }
        _ = parentGroup.add(group)
        group.x = layoutX
        group.y = layoutY
        group.markRedraw()
        var groupMeta = self._elementMeta[ObjectIdentifier(group)] ?? TreemapElementMeta()
        groupMeta.nodeWidth = thisWidth
        groupMeta.nodeHeight = thisHeight
        groupMeta.willDelete = false
        self._elementMeta[ObjectIdentifier(group)] = groupMeta

        // if (thisLayout.isAboveViewRoot) { return group; }
        if (thisLayout["isAboveViewRoot"] as? Bool) ?? false {
            return group
        }

        // Background
        // const bg = giveGraphic('background', Rect, depth, Z2_BG);
        // MORPH: reuse the existing bg rect (already added to `group`) so its shape resizes rather than
        //   snapping; else create fresh.
        let bgWasOld = oldRawIndex.flatMap { oldStorage.background[$0] } != nil
        let bg = giveRect("background", &oldStorage.background, &thisStorage.background)
        if !bgWasOld { bg?.z2 = calculateZ2(depth, Z2_BG) }
        // bg && renderBackground(group, bg, isParent && thisLayout.upperLabelHeight);
        let upperLabelHeight = (thisLayout["upperLabelHeight"] as? Double) ?? 0
        if let bg { renderBackground(group, bg, isParent && upperLabelHeight != 0, bgWasOld) }

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
            if let bg {
                data.setItemGraphicEl(thisNode.dataIndex, bg)
                states.toggleHoverEmphasis(bg, focusOrIndices, blurScope, isDisabled)
            }
        }
        else {
            // const content = giveGraphic('content', Rect, depth, Z2_CONTENT);
            // MORPH: reuse the existing content rect (already added to `group`) so its shape resizes
            //   rather than snapping; else create fresh.
            let contentWasOld = oldRawIndex.flatMap { oldStorage.content[$0] } != nil
            let content = giveRect("content", &oldStorage.content, &thisStorage.content)
            if !contentWasOld { content?.z2 = calculateZ2(depth, Z2_CONTENT) }
            // content && renderContent(group, content);
            if let content { renderContent(group, content, contentWasOld) }

            // (bg as ECElement).disableMorphing = true;
            //   PORT-NOTE: `ECElement` is an augmentation interface Swift cannot add stored props for;
            //   the flag lives in the `makeInner` side store (animation/morphTransitionHelper.swift),
            //   read by `getPathList` — so the node BACKGROUND rect is not a universalTransition morph
            //   endpoint (only its content rect is), exactly as upstream.
            if let bg { getMorphInner(bg).disableMorphing = true }
            // Leaf node: the whole node GROUP is the highDown dispatcher (upstream TreemapView.ts:852-859) —
            //   its child traverse (in enableHoverEmphasis) attaches the state proxy to the bg + content.
            // Only for enabling highlight/downplay: data.setItemGraphicEl(thisNode.dataIndex, group);
            data.setItemGraphicEl(thisNode.dataIndex, group)

            // const cursorStyle = nodeModel.getShallow('cursor'); cursorStyle && content.attr('cursor', cursorStyle);
            if let content, let cursorStyle = nodeModel.getShallow("cursor") {
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
            _ = reuse
            _ = bg.setShape(makeRectShape(0, 0, thisWidth, thisHeight, borderRadius))

            if thisInvisible {
                // Delay invisible until the shared transition finishes so the tile does not vanish.
                if !bg.invisible { willInvisibleEls.append(bg) }
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
            _ = reuse
            _ = content.setShape(makeRectShape(borderWidth, borderWidth, contentWidth, contentHeight, borderRadius))

            if thisInvisible {
                if !content.invisible { willInvisibleEls.append(content) }
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

            // textStyle.truncateMinChar = 2; textStyle.lineOverflow = 'truncate';
            textStyle.truncateMinChar = 2
            textStyle.lineOverflow = "truncate"

            // addDrillDownIcon(textStyle, upperLabelRect, thisLayout): a leaf-root node (a node at
            //   `leafDepth` that still has hidden children — i.e. it is drillable) gets its label
            //   prefixed with the series `drillDownIcon` (default '▶').
            if upperLabelRect == nil,
               (thisLayout["isLeafRoot"] as? Bool) ?? false,
               let icon = seriesModel.get("drillDownIcon", true) as? String, !icon.isEmpty,
               let curText = textStyle.text, !curText.isEmpty {
                textStyle.text = icon + "  " + curText
                if let emphasisState = textEl.getState("emphasis"),
                   var emphasisStyle = emphasisState.textStyle,
                   let emphasisText = emphasisStyle.text, !emphasisText.isEmpty {
                    emphasisStyle.text = icon + "  " + emphasisText
                    emphasisState.textStyle = emphasisStyle
                }
            }

            textEl.useStyle(textStyle)
            textEl.name = "treemapLabel"

            // Upstream assigns `textEl.beforeUpdate` so animation, roam and re-root always use the
            // current tile geometry for truncation. The ZRenderKit callback is the Swift equivalent
            // of that assignable per-instance lifecycle method.
            let updateLabelBox: () -> Void = { [weak textEl, weak rectEl] in
                guard let textEl, let rectEl else { return }
                var currentStyle = textEl.textStyle ?? TextStyleProps()
                let boxWidth = upperLabelRect?.width ?? ((rectEl.shape as? RectShape)?.width ?? 0)
                let boxHeight = upperLabelRect?.height ?? ((rectEl.shape as? RectShape)?.height ?? 0)
                let width = Swift.max(boxWidth - textPadding[1] - textPadding[3], 0)
                let height = Swift.max(boxHeight - textPadding[0] - textPadding[2], 0)
                if currentStyle.width != width || currentStyle.height != height {
                    currentStyle.width = width
                    currentStyle.height = height
                    textEl.useStyle(currentStyle)
                }
            }
            textEl.beforeUpdateCallback = updateLabelBox
            updateLabelBox()

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

private func treemapNumber(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber,
       !(value === kCFBooleanTrue || value === kCFBooleanFalse) {
        return value.doubleValue
    }
    return nil
}

// export default TreemapView;  -> `open class TreemapView` above.
