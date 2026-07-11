// Ported (STATIC SUBSET) from echarts/src/chart/tree/TreeView.ts — keep in sync with upstream.
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
//   import * as zrUtil from 'zrender/src/core/util';               -> `util.*` (ZRenderKit).
//   import * as graphic from '../../util/graphic';                 -> `Group` / `BezierCurve` (ZRenderKit shapes).
//       PORT-TODO: util/graphic's updateProps/removeElement (animation) NOT ported — the static render
//       sets final geometry directly (same deviation as FunnelView/PieView/SunburstView).
//   import {getECData} from '../../util/innerStore';               -> `innerStore.getECData` (ported).
//   import SymbolClz from '../helper/Symbol';                      -> `Symbol` (chart/helper/SymbolElement.swift).
//       PORT NOTE: the node symbols are routed through the shared `SymbolDraw` (chart/helper/SymbolDraw),
//       mirroring the port's GraphView — each node becomes a `Symbol` (Group) carrying colour, the
//       useNameLabel node label, emphasis hover-scale, symbolRotate/offset and the entrance scale-in.
//       `TreeSymbol`'s `__edge`/`__radial*`/`__old*` augmentation (used only by the DEFERRED enter/update/
//       remove animation + radial label rotation) has no Swift analogue; the edge blur-forward that
//       `__edge` powers is reproduced via the symbol Path's `onHoverStateChange` hook (see decorateNode).
//   import {radialCoordinate} from './layoutHelper';               -> `layoutHelper.radialCoordinate` (sibling).
//   import * as bbox from 'zrender/src/core/bbox';                 -> PORT-TODO: only used by _updateViewCoordSys (deferred).
//   import { applyViewCoordSysTransToElement, calcCompensationScaleToPreserveNodeSize,
//            VIEW_COORD_SYS_TRANS_OVERALL } from '../../coord/View';  -> PORT-TODO: coord/View NOT ported (roam deferred).
//   import RoamController from '../../component/helper/RoamController';   -> PORT-TODO: roam NOT ported.
//   import {parsePercent} from '../../util/number';                -> `number.parsePercent`.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import TreeSeriesModel, { TreeSeriesOption, TreeSeriesNodeItemOption, SERIES_TYPE_TREE } from './TreeSeries';
//       -> sibling TreeSeries.swift.
//   import Path, { PathProps, PathStyleProps } from 'zrender/src/graphic/Path';  -> Path / PathStyleProps (ZRenderKit).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { TreeNode } from '../../data/Tree';                    -> TreeNode (data/Tree.swift, sibling track).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import { setStatesStylesFromModel, setStatesFlag, setDefaultStateProxy, HOVER_STATE_BLUR }
//       from '../../util/states';                                  -> `states.*` (util/states.swift, ported).
//       decorateNode/drawEdge use states.setStatesStylesFromModel, states.getHighDownInner,
//       states.leaveBlur and states.HOVER_STATE_BLUR for the node/edge emphasis + blur wiring.
//   import { AnimationOption, ECElement, RoamPayload } from '../../util/types';  -> util/types.swift (type-only).
//   import tokens from '../../visual/tokens';
//       -> visual/tokens.ts IS ported (visual/tokens.swift). `tokens.color.neutral99` (='#000') and
//          `tokens.color.neutral00` (='#fff') are still inlined as their upstream literals below.
//   import { createIsInSelfByPointerCheckerEl, createViewCoordSysSimply, isRoamPayloadHasZoom,
//            updateRoamControllerSimply } from '../../component/helper/roamHelper';
//       -> PORT-TODO: roamHelper NOT ported (roam deferred).

// PORT-TODO: `tokens.color.*` (visual/tokens.ts). Inlined as the upstream literal values.
private let tokens_color_neutral99 = "#000"
private let tokens_color_neutral00 = "#fff"

// upstream:
//   type TreeSymbol = SymbolClz & { __edge; __radialOldRawX; __radialOldRawY; __radialRawX; __radialRawY;
//     __oldX; __oldY };
// PORT-NOTE: SymbolClz (upstream chart/helper/Symbol) IS ported as `Symbol` (chart/helper/SymbolElement.swift);
//   the augmented `TreeSymbol` (edge back-pointer +
//   radial/old raw-coordinate caches used only by the DEFERRED enter/update/remove animation) has no
//   Swift analogue. The static render adds node symbols + edges to the group directly.

// upstream: class TreeEdgeShape { parentPoint; childPoints; orient; forkPosition; }
//   Conforms to `PathShape` (the per-subclass shape marker). Keyed animation is inert (deferred).
final class TreeEdgeShape: PathShape {
    var parentPoint: [Double] = []
    var childPoints: [[Double]] = []
    // upstream: orient: TreeSeriesOption['orient']  ('LR' | 'RL' | 'TB' | 'BT' | 'horizontal' | 'vertical')
    var orient: String?
    // upstream: forkPosition: TreeSeriesOption['edgeForkPosition']  (percent, e.g. '50%')
    var forkPosition: Any?

    init() {}
}

// upstream: interface TreeEdgePathProps extends PathProps { shape?: Partial<TreeEdgeShape> }
//   collapsed onto the dynamic PathProps bag (see Path.swift's PathProps typealias).
typealias TreeEdgePathProps = PathProps

// upstream: interface TreeNodeLayout { x; y; rawX; rawY }
struct TreeNodeLayout {
    var x: Double
    var y: Double
    var rawX: Double
    var rawY: Double
}

// upstream: class TreePath extends Path<TreeEdgePathProps>
final class TreePath: Path {

    // upstream: shape: TreeEdgeShape — narrows the inherited existential `shape: PathShape!`.

    // upstream: constructor(opts?: TreeEdgePathProps) { super(opts); }
    override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "TreePath"   // provenance: upstream leaves the prototype type unset for this anon class.
    }

    // upstream: getDefaultStyle() { return { stroke: tokens.color.neutral99, fill: null as string }; }
    override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string(tokens_color_neutral99)
        style.fill = nil   // upstream: fill: null as string
        return style
    }

    // upstream: getDefaultShape() { return new TreeEdgeShape(); }
    override func getDefaultShape() -> PathShape {
        return TreeEdgeShape()
    }

    // upstream: buildPath(ctx: CanvasRenderingContext2D, shape: TreeEdgeShape)
    override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        // `TreeEdgeShape` is a reference type here (its arrays are not value-copied on assignment);
        //   the port keeps upstream's field reads verbatim.
        let shape = shapeIn as! TreeEdgeShape
        let childPoints = shape.childPoints
        let childLen = childPoints.count
        let parentPoint = shape.parentPoint
        let firstChildPos = childPoints[0]
        let lastChildPos = childPoints[childLen - 1]

        if childLen == 1 {
            _ = ctx.moveTo(parentPoint[0], parentPoint[1])
            _ = ctx.lineTo(firstChildPos[0], firstChildPos[1])
            return
        }

        let orient = shape.orient
        let forkDim = (orient == "TB" || orient == "BT") ? 0 : 1
        let otherDim = 1 - forkDim
        let forkPosition = number.parsePercent(shape.forkPosition, 1)
        // const tmpPoint = [];  — a 2-element scratch array indexed by forkDim/otherDim.
        var tmpPoint: [Double] = [0, 0]
        tmpPoint[forkDim] = parentPoint[forkDim]
        tmpPoint[otherDim] = parentPoint[otherDim] + (lastChildPos[otherDim] - parentPoint[otherDim]) * forkPosition

        _ = ctx.moveTo(parentPoint[0], parentPoint[1])
        _ = ctx.lineTo(tmpPoint[0], tmpPoint[1])
        _ = ctx.moveTo(firstChildPos[0], firstChildPos[1])
        tmpPoint[forkDim] = firstChildPos[forkDim]
        _ = ctx.lineTo(tmpPoint[0], tmpPoint[1])
        tmpPoint[forkDim] = lastChildPos[forkDim]
        _ = ctx.lineTo(tmpPoint[0], tmpPoint[1])
        _ = ctx.lineTo(lastChildPos[0], lastChildPos[1])

        for i in 1..<(childLen - 1) {
            let point = childPoints[i]
            _ = ctx.moveTo(point[0], point[1])
            tmpPoint[forkDim] = point[forkDim]
            _ = ctx.lineTo(tmpPoint[0], tmpPoint[1])
        }
    }
}

// upstream: class TreeView extends ChartView
open class TreeView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_TREE;  /  readonly type = SERIES_TYPE_TREE;
    public static let treeType = SERIES_TYPE_TREE
    open override var type: String {
        get { SERIES_TYPE_TREE }
        set { /* readonly upstream */ }
    }

    // upstream: private _mainGroup = new graphic.Group();
    private let _mainGroup = Group()

    // PORT-NOTE: private _controller: RoamController;  — RoamController IS ported
    //   (component/helper/RoamController.swift) but roam is not wired in this view (deferred).

    // upstream: private _data: SeriesData<TreeSeriesModel>;
    private var _data: SeriesData?

    // PORT-TODO: private _min/_max/_firstRender — only used by _updateViewCoordSys/roam (deferred).

    // upstream: init(ecModel, api) { this._controller = new RoamController(api.getZr());
    //   this.group.add(this._mainGroup); this._firstRender = true; }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: RoamController + _firstRender (roam) deferred.
        _ = self.group.add(self._mainGroup)
    }

    // upstream: render(seriesModel: TreeSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: TreeSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! TreeSeriesModel

        let data = seriesModel.getData()
        // `data.tree` is `Tree?` on SeriesData; bail if not present (matches an empty render).
        guard data.tree != nil else { return }

        // const layoutInfo = seriesModel.layoutInfo;
        //   `layoutInfo` is `LayoutRect?` in the sibling port (upstream is non-null, set by treeLayout);
        //   bail if absent (an unlaid-out series can not be positioned).
        guard let layoutInfo = seriesModel.layoutInfo else { return }

        let group = self._mainGroup

        // const layout = seriesModel.get('layout');
        let layout = (seriesModel.get("layout", false) as? String) ?? "orthogonal"

        // L3 Roam: capture the base (roam-free) placement; the roam transform is applied on top of it at
        //   the END of render (viewGroupRoamApplyStateToGroup). Identity roam state → group.x = baseX etc.
        let baseX: Double
        let baseY: Double
        if layout == "radial" {
            baseX = layoutInfo.x + layoutInfo.width / 2
            baseY = layoutInfo.y + layoutInfo.height / 2
        }
        else {
            baseX = layoutInfo.x
            baseY = layoutInfo.y
        }
        group.x = baseX
        group.y = baseY

        // this._updateViewCoordSys(seriesModel, api);
        //   PORT-TODO: the upstream `View` VIEW_COORD_SYS placement (bbox + createViewCoordSysSimply +
        //   applyViewCoordSysTransToElement) is DEFERRED (coord/View not ported). The group position set
        //   above is the static subset of that placement; the roam pan/zoom is applied to the group as a
        //   TRANSFORM at the end of render (see viewGroupRoamApplyStateToGroup / roamHelperViewGroup.swift).

        // updateRoamControllerSimply(seriesModel, api, this._controller, ...);  — the controller is wired
        //   live by EChartsView._setupTreeRoam (the TreeView is zr-less); the roam STATE it accumulates
        //   is re-applied to the group below.

        // ------------------------------------------------------------------------------------------
        // NODE SYMBOLS routed through the shared SymbolDraw (chart/helper/SymbolDraw), mirroring the
        //   port's GraphView. Upstream TreeView manages `SymbolClz` instances directly through
        //   `data.diff(oldData)`; the port delegates the node-symbol lifecycle to SymbolDraw (colour,
        //   node label, emphasis hover-scale, symbolRotate/offset, entrance scale-in) — the same helper
        //   scatter/line/graph use — and keeps the tree EDGES (links) drawn inline (LineDraw not ported).
        //
        // STATIC render deviation: a FRESH SymbolDraw is built each render (its `_data` starts nil → the
        //   diff is all-`.add`), so every node hits the ctor branch (which carries `useNameLabel: true`),
        //   and the group is rebuilt from scratch. The keyed reuse + expand/collapse click + node/link
        //   scale + radial label rotation are DEFERRED (see PORT-TODOs).
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // Symbol-visual stages populate the symbol / symbolSize / symbolRotate / symbolOffset /
        //   symbolKeepAspect data + item visuals SymbolDraw reads (TreeSeries.hasSymbolVisual = true).
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        // upstream `symbolEl = new SymbolClz(data, dataIndex, null, { symbolInnerColor, useNameLabel: true })`:
        //   route the node symbols through SymbolDraw with a ctor that sets `useNameLabel: true` so each
        //   node label's default text is the node NAME (not the value-derived getDefaultLabel).
        //   PORT-TODO: `symbolInnerColor` (the hollow inner fill for collapsed nodes) is a SymbolClz init
        //   opt not modelled by the shared Symbol yet — DEFERRED.
        let treeSymbolCtor: SymbolLikeCtor = { data, idx, scope, opts in
            var o = opts ?? SymbolOpts()
            o.useNameLabel = true
            return Symbol(data, idx, scope, o)
        }
        let symbolDraw = SymbolDraw(treeSymbolCtor)
        var opt = SymbolDrawUpdateOpt()
        // The node layout is a `{ x, y, rawX, rawY }` bag (treeLayout → setItemLayout); feed SymbolDraw
        //   the group-local `[x, y]` pixel point (nil skips the node — SymbolDraw's symbolNeedsDraw gate).
        opt.getSymbolPoint = { i in
            guard symbolNeedsDraw(data, i) else { return nil }
            guard let layout = data.getItemLayout(i) as? [String: Any],
                  let x = layout["x"] as? Double, let y = layout["y"] as? Double else { return nil }
            return [x, y]
        }
        symbolDraw.updateData(data, opt)
        _ = group.add(symbolDraw.group)

        // Per-node decoration the shared Symbol does not cover: the tree's outward label side, the parent/
        //   child EDGE (drawn inline), the topology `emphasis.focus` index set, and the edge blur-forward.
        for newIdx in 0..<data.count() {
            if symbolNeedsDraw(data, newIdx) {
                decorateNode(data, newIdx, group, seriesModel)
            }
        }

        // this._updateNodeAndLinkScale(seriesModel);
        //   PORT-TODO: DEFERRED — setSymbolScale / calcCompensationScaleToPreserveNodeSize (roam) not ported.

        // if (seriesModel.get('expandAndCollapse') === true) {
        //     data.eachItemGraphicEl(function (el, dataIndex) {
        //         el.off('click').on('click', function () {
        //             api.dispatchAction({ type: 'treeExpandAndCollapse', seriesId: seriesModel.id,
        //                 dataIndex: dataIndex });
        //         });
        //     });
        // }
        //   Each node symbol (a Symbol Group) binds click → dispatch 'treeExpandAndCollapse' with the series
        //   id + the node dataIndex. The click BUBBLES from the hit child (the symbol Path) up to this Group
        //   via Handler.dispatchToElement — the same bubbling the legend click uses. The action toggles
        //   node.isExpand (chart/tree/treeAction.swift) and re-runs the full update() (update:'update'), so a
        //   now-collapsed subtree's nodes lose their layout and drop out on the next render.
        if (seriesModel.get("expandAndCollapse", true) as? Bool) == true {
            let seriesId = seriesModel.id
            data.eachItemGraphicEl { el, dataIndex in
                // upstream `el.off('click')` — the group is rebuilt each static render (no stale handler to
                //   clear), so bind directly.
                _ = el.on("click", { _, _ in
                    var p = Payload(type: "treeExpandAndCollapse")
                    p.other["seriesId"] = seriesId
                    p.other["dataIndex"] = dataIndex
                    api.dispatchAction(p)
                    return nil
                }, nil)
            }
        }

        self._data = data

        // L3 Roam: re-apply the accumulated roam transform to the main group (upstream applies center/zoom
        //   through the View coord sys; the port transforms the group directly — see roamHelperViewGroup).
        //   On first render / roam off, the state is identity → the placement above is left exactly as-is.
        viewGroupRoamApplyStateToGroup(seriesModel, group, baseX, baseY)

        // this._firstRender = false;  — PORT-TODO: the enter/roam animation flag stays DEFERRED.
    }

    // L3 Roam: the pointer-check element (upstream `createIsInSelfByPointerCheckerEl(this.group)`).
    func roamPointerCheckerGroup() -> Group { return self.group }

    // L3 Roam (test hook): the main group carrying the roam transform (position + scale).
    var _mainGroupForTest: Group { return self._mainGroup }

    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — the port re-renders via the full update()
    //   the `treeRoam` action triggers (see roamHelperViewGroup.swift DEVIATION note); no partial path.

    // upstream: private _updateViewCoordSys(seriesModel, api)  — PORT-TODO: coord/View + bbox DEFERRED.

    // upstream: _updateNodeAndLinkScale(seriesModel)  — PORT-TODO: setSymbolScale (roam) DEFERRED.

    // upstream: dispose() { this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: RoamController.dispose DEFERRED (roam not ported).
    }

    // upstream: remove() { this._mainGroup.removeAll(); this._data = null; }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self._mainGroup.removeAll()
        self._data = nil
    }
}

// upstream: function symbolNeedsDraw(data: SeriesData, dataIndex: number)
//   return layout && !isNaN(layout.x) && !isNaN(layout.y);
func symbolNeedsDraw(_ data: SeriesData, _ dataIndex: Int) -> Bool {
    guard let layout = data.getItemLayout(dataIndex) as? [String: Any] else {
        return false
    }
    guard let x = layout["x"] as? Double, let y = layout["y"] as? Double else {
        return false
    }
    return !x.isNaN && !y.isNaN
}

// Per-node decoration applied AFTER SymbolDraw has built the node symbols. SymbolDraw/Symbol handle the
//   node's colour, name label (useNameLabel), emphasis hover-scale and entrance scale-in; this function
//   adds the tree-specific pieces upstream `updateNode` also does that the shared Symbol does not cover:
//   the outward LABEL SIDE, the parent/child EDGE (drawn inline), the topology `emphasis.focus` index set
//   and the edge blur-forward hook. `data.getItemGraphicEl(dataIndex)` is the node's `Symbol` (a Group);
//   its child symbol Path (name "item") is the label/emphasis carrier.
private func decorateNode(
    _ data: SeriesData,
    _ dataIndex: Int,
    _ group: Group,
    _ seriesModel: TreeSeriesModel
) {
    // const node = data.tree.getNodeByDataIndex(dataIndex);
    guard let node = data.tree?.getNodeByDataIndex(dataIndex) else { return }

    // The Symbol (Group) SymbolDraw created for this node + its symbol Path child.
    let symbolEl = data.getItemGraphicEl(dataIndex) as? Symbol
    let symbolPath = symbolEl?.getSymbolPath()

    // const virtualRoot = data.tree.root;
    let virtualRoot: TreeNode = data.tree!.root

    // const source = node.parentNode === virtualRoot ? node : node.parentNode || node;
    let source: TreeNode = node.parentNode === virtualRoot ? node : (node.parentNode ?? node)
    // const sourceLayout = source.getLayout() as TreeNodeLayout;
    //   (sourceOldLayout — the animation snapshot — is DEFERRED; the static render uses sourceLayout.)
    let sourceLayout = treeNodeLayout(source.getLayout())
    // const targetLayout = node.getLayout();
    guard let targetLayout = treeNodeLayout(node.getLayout()) else { return }

    // const itemModel = node.getModel();  (used below for focus + by drawEdge for lineStyle)
    let itemModel = data.getItemModel(dataIndex)
    let emphasisModel = itemModel.getModel(["emphasis"])
    let focus: InnerFocus? = emphasisModel.get("focus")

    // Tree's outward label side. Upstream overrides the label `position` to `normalLabelModel.get('position')
    //   || (isLeft ? 'left' : 'right')` (TreeView.ts:437); for the orthogonal port the side is chosen per
    //   orientation — internal nodes label on the inner side, leaves on the outer. The shared Symbol already
    //   built the label (through the label core's createTextConfig, which stamps `outsideFill`), defaulting
    //   the normal position to "inside"; override it to the tree's outward side unless the label model pins
    //   a position. Only touch it when a label was actually created (normal `show != false`).
    if let symbolPath = symbolPath {
        let treeOrient = seriesModel.getOrient()
        let textPosition = treeLabelPosition(treeOrient, isLeaf: node.children.isEmpty)
        let labelModels = labelStyle.getLabelStatesModels(itemModel)
        if let normalModel = labelModels[.normal],
           (normalModel.getShallow("show") as? Bool) != false {
            let pinned = normalModel.get("position")
            if symbolPath.textConfig == nil { symbolPath.textConfig = ElementTextConfig() }
            symbolPath.textConfig?.position = pinned ?? textPosition
        }
    }

    // Phase 45: `emphasis.focus:'relative'|'ancestor'|'descendant'` (upstream TreeView.ts:447-456).
    //   Overwrite the node symbol's `ecData.focus` (Symbol.toggleHoverEmphasis stored the RAW focus on the
    //   Symbol group) with the topology index SET (ancestors and/or descendants — all node dataIndices), so
    //   hovering the node keeps that lineage bright and blurs the rest. The value is a plain `[Int]` (the
    //   ARRAY-focus form `states.blurSeries` consumes; tree edges are anonymous children with no edge-data,
    //   so there is no edge dataType). Set it on the Symbol group — the element `blurSeriesFromHighlightPayload`
    //   reads via `data.getItemGraphicEl(dataIndex)`.
    if let symbolEl = symbolEl, let resolved = treeResolveFocus(focus, node) {
        innerStore.getECData(symbolEl).focus = resolved
    }

    // drawEdge(seriesModel, node, virtualRoot, symbolEl, sourceOldLayout, sourceLayout, targetLayout, group);
    let edgeEl = drawEdge(seriesModel, node, virtualRoot, sourceLayout, targetLayout, group)

    // Phase 48: `symbolEl.__edge` blur propagation (upstream TreeView.ts:464-477). Tree edges are anonymous
    //   children (not in edge-data), so they are blurred by the blurSeries group-traverse but never
    //   un-blurred by the focus index set. Mirror upstream: when the node symbol's hover state changes to a
    //   NON-blur state (emphasis/normal), forward it to the edge — UNLESS the parent node is itself blurred
    //   (so an edge into a blurred subtree stays dim). This makes an in-lineage edge brighten with its node
    //   under `focus:'ancestor'|'descendant'|'relative'`. The hook is placed on the Symbol's `item` Path (so
    //   it fires when `leaveBlur`/`singleEnterBlur` traverses the Symbol group down onto that child).
    if let edgeEl = edgeEl, let symbolPath = symbolPath {
        states.getHighDownInner(symbolPath).onHoverStateChange = { [weak edgeEl] toState in
            guard let edgeEl = edgeEl, toState != .blur else { return }
            let parentEl = node.parentNode.flatMap { data.getItemGraphicEl($0.dataIndex) }
            let parentBlurred = parentEl.map { states.getHighDownInner($0).hoverState == states.HOVER_STATE_BLUR } ?? false
            if !parentBlurred {
                // toState is emphasis or normal → clear the edge's blur so it follows its node.
                states.leaveBlur(edgeEl)
            }
        }
    }
}

// upstream: function drawEdge(seriesModel, node, virtualRoot, symbolEl, sourceOldLayout,
//     sourceLayout, targetLayout, group)
//   STATIC form: no `symbolEl.__edge` cache / animation. `sourceOldLayout` (the pre-animation snapshot,
//   used only to init the edge before `updateProps`) is dropped; the edge is built at its final shape.
@discardableResult
private func drawEdge(
    _ seriesModel: TreeSeriesModel,
    _ node: TreeNode,
    _ virtualRoot: TreeNode,
    _ sourceLayout: TreeNodeLayout?,
    _ targetLayout: TreeNodeLayout,
    _ group: Group
) -> Path? {
    let itemModel = node.getModel()
    // const edgeShape = seriesModel.get('edgeShape');
    let edgeShape = (seriesModel.get("edgeShape", false) as? String) ?? "curve"
    // const layout = seriesModel.get('layout');
    let layout = (seriesModel.get("layout", false) as? String) ?? "orthogonal"
    // const orient = seriesModel.getOrient();
    let orient = seriesModel.getOrient()
    // const curvature = seriesModel.get(['lineStyle', 'curveness']);
    let curvature = treeToDouble(seriesModel.get(["lineStyle", "curveness"], false))
    // const edgeForkPosition = seriesModel.get('edgeForkPosition');
    let edgeForkPosition = seriesModel.get("edgeForkPosition", false)
    // const lineStyle = itemModel.getModel('lineStyle').getLineStyle();
    let lineStyle = (itemModel?.getModel("lineStyle").getLineStyle()) ?? [:]

    var edge: Path? = nil
    // curve edge from node -> parent
    // polyline edge from node -> children
    if edgeShape == "curve" {
        if let parentNode = node.parentNode, parentNode !== virtualRoot, let sourceLayout = sourceLayout {
            // edge = new graphic.BezierCurve({ shape: getEdgeShape(layout, orient, curvature, sourceLayout, targetLayout) });
            //   (the source-old-layout init + updateProps to the final shape collapse to one static build.)
            var props: ElementProps = [:]
            props["shape"] = getEdgeShape(layout, orient, curvature, sourceLayout, targetLayout) as PathShape
            edge = BezierCurve(props)
        }
    }
    else if edgeShape == "polyline" {
        if layout == "orthogonal" {
            if node !== virtualRoot && node.children.count != 0 && node.isExpand == true {
                // const children = node.children;
                let children = node.children
                var childPoints: [[Double]] = []
                for i in 0..<children.count {
                    // const childLayout = children[i].getLayout();
                    if let childLayout = treeNodeLayout(children[i].getLayout()) {
                        childPoints.append([childLayout.x, childLayout.y])
                    }
                }

                let shape = TreeEdgeShape()
                shape.parentPoint = [targetLayout.x, targetLayout.y]
                shape.childPoints = childPoints
                shape.orient = orient
                shape.forkPosition = edgeForkPosition
                var props: ElementProps = [:]
                props["shape"] = shape as PathShape
                edge = TreePath(props)
            }
        }
        else {
            // PORT-TODO: upstream `if (__DEV__) throw new Error('The polyline edgeShape can only be used
            //   in orthogonal layout')` — dev-only guard dropped.
        }
    }

    // show all edge when edgeShape is 'curve', filter node `isExpand` is false when edgeShape is 'polyline'
    if let edge = edge, !(edgeShape == "polyline" && !node.isExpand) {
        // edge.useStyle(zrUtil.defaults({ strokeNoScale: true, fill: null }, lineStyle));
        edge.useStyle(treeEdgeStyle(lineStyle))
        // `useStyle` runs createStyle, which lays the style over DEFAULT_PATH_STYLE (fill '#000') and
        // SKIPS the nil `fill` — so the intended `fill: null` is dropped and the edge curve/fork fills
        // solid black (visual-parity trap class 1). Clear it directly to keep edges as thin strokes.
        edge.pathStyle.fill = nil

        // Phase 45: attach the emphasis-state lineStyle (upstream TreeView.ts drawEdge
        //   setStatesStylesFromModel(edge, itemModel, 'lineStyle')). The edge is not itself a highDown
        //   dispatcher (tree edges are anonymous children, not in edge-data), so this state only takes
        //   effect via the node symbol's blur-propagation hook — DEFERRED (needs TreeSymbol.__edge + the
        //   symbol's onHoverStateChange forwarder, TreeView.ts:464-477). Adding the state styles now keeps
        //   the edge faithful for when that hook lands.
        if let itemModel = itemModel {
            states.setStatesStylesFromModel(edge, itemModel, "lineStyle")
        }

        _ = group.add(edge)
        return edge
    }
    return nil
}

// PORT-TODO: function removeNodeEdge / getSourceNode / removeNode — the enter/update/remove ANIMATION
//   subsystem (graphic.removeElement, fadeOut, removeAnimationOpt) is DEFERRED per CONVENTIONS §5. The
//   static render rebuilds the group each pass, so per-node removal animation is not needed. `getSourceNode`
//   (walks up to the first ancestor with a non-null layout) is subsumed by `updateNode`'s inline
//   `source` computation for the static case.

// upstream: function getEdgeShape(layoutOpt, orient, curvature, sourceLayout, targetLayout)
//   Returns the BezierCurve shape (x1/y1/x2/y2 + control points cpx1/cpy1/cpx2/cpy2).
func getEdgeShape(
    _ layoutOpt: String?,
    _ orient: String?,
    _ curvature: Double,
    _ sourceLayout: TreeNodeLayout,
    _ targetLayout: TreeNodeLayout
) -> BezierCurveShape {
    var cpx1: Double = 0
    var cpy1: Double = 0
    var cpx2: Double = 0
    var cpy2: Double = 0
    let x1: Double
    let x2: Double
    let y1: Double
    let y2: Double

    var shape = BezierCurveShape()

    if layoutOpt == "radial" {
        x1 = sourceLayout.rawX
        y1 = sourceLayout.rawY
        x2 = targetLayout.rawX
        y2 = targetLayout.rawY

        // PORT-NOTE: `radialCoordinate(rad, r)` from sibling ./layoutHelper (exposed as
        //   `layoutHelper.radialCoordinate` returning `(x, y)`). `|| 0` reproduces JS
        //   falsy-fallthrough (0/NaN → 0) via `treeNumOr`.
        let radialCoor1 = layoutHelper.radialCoordinate(x1, y1)
        let radialCoor2 = layoutHelper.radialCoordinate(x1, y1 + (y2 - y1) * curvature)
        let radialCoor3 = layoutHelper.radialCoordinate(x2, y2 + (y1 - y2) * curvature)
        let radialCoor4 = layoutHelper.radialCoordinate(x2, y2)

        shape.x1 = treeNumOr(radialCoor1.x, 0)
        shape.y1 = treeNumOr(radialCoor1.y, 0)
        shape.x2 = treeNumOr(radialCoor4.x, 0)
        shape.y2 = treeNumOr(radialCoor4.y, 0)
        shape.cpx1 = treeNumOr(radialCoor2.x, 0)
        shape.cpy1 = treeNumOr(radialCoor2.y, 0)
        shape.cpx2 = treeNumOr(radialCoor3.x, 0)
        shape.cpy2 = treeNumOr(radialCoor3.y, 0)
        return shape
    }
    else {
        x1 = sourceLayout.x
        y1 = sourceLayout.y
        x2 = targetLayout.x
        y2 = targetLayout.y

        if orient == "LR" || orient == "RL" {
            cpx1 = x1 + (x2 - x1) * curvature
            cpy1 = y1
            cpx2 = x2 + (x1 - x2) * curvature
            cpy2 = y2
        }
        if orient == "TB" || orient == "BT" {
            cpx1 = x1
            cpy1 = y1 + (y2 - y1) * curvature
            cpx2 = x2
            cpy2 = y2 + (y1 - y2) * curvature
        }
    }

    shape.x1 = x1
    shape.y1 = y1
    shape.x2 = x2
    shape.y2 = y2
    shape.cpx1 = cpx1
    shape.cpy1 = cpy1
    shape.cpx2 = cpx2
    shape.cpy2 = cpy2
    return shape
}

// export default TreeView;  -> `open class TreeView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// Reads the `{ x, y, rawX, rawY }` layout bag stored by treeLayout (setItemLayout) into a
//   TreeNodeLayout. Returns nil when there is no layout (upstream `getLayout() == null`).
// Phase 45: resolve a tree node `emphasis.focus` string to its lineage index set (upstream
//   TreeView.ts:447-456). 'relative' = ancestors ∪ descendants, 'ancestor' / 'descendant' = one side.
//   Non-topology focus ('self'/'series'/indices/nil) passes through unchanged.
private func treeResolveFocus(_ focus: InnerFocus?, _ node: TreeNode) -> InnerFocus? {
    switch focus as? String {
    case "relative":   return node.getAncestorsIndices() + node.getDescendantIndices()
    case "ancestor":   return node.getAncestorsIndices()
    case "descendant": return node.getDescendantIndices()
    default:           return focus
    }
}

private func treeNodeLayout(_ v: Any?) -> TreeNodeLayout? {
    guard let d = v as? [String: Any] else { return nil }
    return TreeNodeLayout(
        x: (d["x"] as? Double) ?? Double.nan,
        y: (d["y"] as? Double) ?? Double.nan,
        rawX: (d["rawX"] as? Double) ?? Double.nan,
        rawY: (d["rawY"] as? Double) ?? Double.nan
    )
}

// `const visualColor = (node.getVisual('style') as PathStyleProps).fill`. The item visual 'style'
//   bag stores paint as an EChartsKit `ZRColor.color` or a raw String (same bridge as FunnelView).
private func treeVisualFill(_ style: Any?) -> String? {
    guard let d = style as? [String: Any] else { return nil }
    if let str = d["fill"] as? String { return str }
    if let zr = d["fill"] as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// `zrUtil.defaults({ strokeNoScale: true, fill: null }, lineStyle)` → a PathStyleProps built from the
//   lineStyle bag (stroke/lineWidth/opacity/…) with fill cleared and strokeNoScale set. Reuses the
//   shared visual-style → PathStyleProps bridge (barStyleFromDict) then applies the two defaults.
private func treeEdgeStyle(_ lineStyle: [String: Any]) -> PathStyleProps {
    var s = barStyleFromDict(lineStyle)
    s.fill = nil            // fill: null
    s.strokeNoScale = true  // strokeNoScale: true
    return s
}

// The tree label's outward side, per series orientation (upstream chooses 'left'/'right' for the
//   horizontal orthogonal tree; TreeView.ts:429). Internal nodes (with children) label on the inner
//   side pointing back toward the root; leaves label on the outer side. Vertical orients map onto
//   top/bottom analogously.
private func treeLabelPosition(_ orient: String?, isLeaf: Bool) -> String {
    switch orient {
    case "RL": return isLeaf ? "left" : "right"
    case "TB", "vertical": return isLeaf ? "bottom" : "top"
    case "BT": return isLeaf ? "top" : "bottom"
    // "LR" / "horizontal" / nil (default) → the common horizontal tree.
    default: return isLeaf ? "right" : "left"
    }
}

// JS `x || 0` for a Double (0 / NaN are falsy → fall back to `d`).
private func treeNumOr(_ v: Double, _ d: Double) -> Double {
    return (v != 0 && !v.isNaN) ? v : d
}

// `store.get(...)`-style numeric coercion for a dynamic option value (curveness).
private func treeToDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}
