// Ported from echarts/src/chart/tree/TreeView.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';                 -> `Group` / `BezierCurve` plus
//       animation/basicTransition's updateProps/removeElement.
//   import {getECData} from '../../util/innerStore';               -> `innerStore.getECData` (ported).
//   import SymbolClz from '../helper/Symbol';                      -> `Symbol` (chart/helper/SymbolElement.swift).
//       PORT NOTE: the node symbols are routed through the shared `SymbolDraw` (chart/helper/SymbolDraw),
//       mirroring the port's GraphView — each node becomes a `Symbol` (Group) carrying colour, the
//       useNameLabel node label, emphasis hover-scale, symbolRotate/offset and the entrance scale-in.
//       `TreeSymbol.__edge` is represented by TreeView's `_edges` registry; source-old position snapshots
//       are local TreeNodeLayout values. Edge blur-forward is reproduced on the symbol Path.
//   import {radialCoordinate} from './layoutHelper';               -> `layoutHelper.radialCoordinate` (sibling).
//   import * as bbox from 'zrender/src/core/bbox';                 -> `bbox.fromPoints` (ZRenderKit), used by
//       _updateViewCoordSys.
//   import { applyViewCoordSysTransToElement, calcCompensationScaleToPreserveNodeSize,
//            VIEW_COORD_SYS_TRANS_OVERALL } from '../../coord/View';  -> coord/View IS ported (coord/View.swift);
//       `applyViewCoordSysTransToElement` + `VIEW_COORD_SYS_TRANS_OVERALL` are wired in _updateViewCoordSys.
//       PORT-NOTE (deferred): calcCompensationScaleToPreserveNodeSize (node/link roam scale) stays deferred.
//   import RoamController from '../../component/helper/RoamController';   -> RoamController IS ported
//       (component/helper/RoamController.swift); PORT-NOTE (deferred): roam is not wired into this view.
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
//       -> PORT-NOTE: the VIEW-GROUP slice of roamHelper is ported (component/helper/roamHelperViewGroup.swift),
//          including `createViewCoordSysSimply` (called verbatim by _updateViewCoordSys),
//          `createIsInSelfByPointerCheckerEl` → `viewGroupRoamPointerRect` and
//          `updateRoamControllerSimply` → `updateViewGroupRoamControllerSimply`.

// PORT-NOTE: `tokens.color.*` (visual/tokens.ts, ported) — inlined here as the upstream literal values
//   (neutral99='#000', neutral00='#fff'), semantically equivalent to the token lookup.
private let tokens_color_neutral99 = "#000"
private let tokens_color_neutral00 = "#fff"

// upstream:
//   type TreeSymbol = SymbolClz & { __edge; __radialOldRawX; __radialOldRawY; __radialRawX; __radialRawY;
//     __oldX; __oldY };
// PORT-NOTE: SymbolClz (upstream chart/helper/Symbol) IS ported as `Symbol`; `_edges` mirrors `__edge`
//   by symbol identity and Symbol carries the four radial old/current raw-coordinate fields.

// upstream: class TreeEdgeShape { parentPoint; childPoints; orient; forkPosition; }
//   Conforms to `PathShape`; parent/child point arrays are exposed to keyed animation.
final class TreeEdgeShape: PathShape {
    var parentPoint: [Double] = []
    var childPoints: [[Double]] = []
    // upstream: orient: TreeSeriesOption['orient']  ('LR' | 'RL' | 'TB' | 'BT' | 'horizontal' | 'vertical')
    var orient: String?
    // upstream: forkPosition: TreeSeriesOption['edgeForkPosition']  (percent, e.g. '50%')
    var forkPosition: Any?

    init() {}

    func animationGet(_ key: String) -> Any? {
        switch key {
        case "parentPoint": return parentPoint
        case "childPoints": return childPoints
        default: return nil
        }
    }

    func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "parentPoint":
            if let point = value as? [Double] { parentPoint = point }
        case "childPoints":
            if let points = value as? [[Double]] { childPoints = points }
        default:
            break
        }
    }

    func animationProps() -> [String: Any] {
        ["parentPoint": parentPoint, "childPoints": childPoints]
    }
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

    // PORT: upstream routes the node symbols through `SymbolClz` instances managed directly by
    //   `data.diff(oldData)`. The port delegates that to the shared `SymbolDraw` (chart/helper/SymbolDraw) —
    //   like GraphView/ScatterView — which owns its OWN internal `_data` diff. It must therefore be RETAINED
    //   across renders (a fresh SymbolDraw per render would see `oldData == nil` every time and treat every
    //   node as an `.add`, replaying the enter scale-in — the reset-on-update bug). Reused like ScatterView.
    private var _symbolDraw: SymbolDraw?

    // PORT: the tree EDGES (links) are drawn inline (LineDraw not ported). Upstream caches each edge on its
    //   node symbol (`TreeSymbol.__edge`) and `updateProps` it on refresh; the port has no `__edge` field, so
    //   the edges are retained here by their owning Symbol identity, which is the Swift equivalent of
    //   `symbolEl.__edge`. Identity (rather than dataIndex) is required because data.diff can remap indices.
    private var _edges: [ObjectIdentifier: Path] = [:]

    // upstream: private _min: number[];  /  private _max: number[];
    //   The last computed node bounding box — kept so a collapse-after-roam that degenerates the box to a
    //   zero width/height falls back to the previous extent (see _updateViewCoordSys).
    //   (`VectorArray` — the ZRenderKit 2-vector `bbox.fromPoints` writes, upstream `number[]`.)
    private var _min: VectorArray?
    private var _max: VectorArray?

    // upstream: private _firstRender: boolean;
    //   Gates the VIEW_COORD_SYS placement animation: the first render applies the trans synchronously
    //   (`animatableModel == null`), later renders tween it through `updateProps`.
    private var _firstRender: Bool = true

    // upstream: init(ecModel, api) { this._controller = new RoamController(api.getZr());
    //   this.group.add(this._mainGroup); this._firstRender = true; }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): RoamController deferred (see the `_controller` note above).
        _ = self.group.add(self._mainGroup)
        self._firstRender = true
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
        //   The upstream `View` VIEW_COORD_SYS placement: builds the own coord sys over the node bounding box
        //   (`seriesModel.coordinateSystem`, which `TreeSeries.__ownRoamView()` hands to the roam modules) and
        //   applies its OVERALL trans to `this.group` via `applyViewCoordSysTransToElement`.
        //   PORT-NOTE: the ROAM pan/zoom itself is NOT driven through this coord sys in the port — the
        //   authorized view-group deviation (roamHelperViewGroup.swift) transforms `_mainGroup` directly at
        //   the END of render (see viewGroupRoamApplyStateToGroup below). To keep the two frames of reference
        //   from composing, `_updateViewCoordSys` explicitly resets the coord sys' roam option to neutral
        //   (see the PORT-NOTE there) — dataRect == viewRect, zoom 1 — so the trans applied to `self.group`
        //   is the identity unconditionally, i.e. placement-neutral; the call exists so the coord sys (and
        //   its sync-back element) is present and correct for `TreeSeries.__ownRoamView()` / `treeRoam`.
        self._updateViewCoordSys(seriesModel, api)

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
        // The SymbolDraw + the edge registry are RETAINED across renders (see the `_symbolDraw` / `_edges`
        //   fields): SymbolDraw's own `data.diff(oldData)` then routes a merge-mode refresh through its
        //   UPDATE path (reuse the node Symbol + `updateProps` its x/y) instead of rebuilding every node and
        //   replaying the entrance scale-in. This is the reset-on-update fix (cf. ScatterView's retained
        //   `_symbolDraw` and the GaugeView reset fix). The group is NOT wiped each render.
        //   PORT-NOTE (deferred): node/link roam-scale + radial label rotation remain DEFERRED.
        // ------------------------------------------------------------------------------------------

        // Symbol-visual stages populate the symbol / symbolSize / symbolRotate / symbolOffset /
        //   symbolKeepAspect data + item visuals SymbolDraw reads (TreeSeries.hasSymbolVisual = true).
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        // upstream `symbolEl = new SymbolClz(data, dataIndex, null, { symbolInnerColor, useNameLabel: true })`:
        //   route the node symbols through SymbolDraw with a ctor that sets `useNameLabel: true` so each
        //   node label's default text is the node NAME (not the value-derived getDefaultLabel).
        //   `symbolInnerColor` (the hollow inner fill for collapsed nodes) IS modelled by the shared
        //   Symbol (SymbolOpts.symbolInnerColor → ec.setColor), but SymbolDraw builds its own opts without
        //   it; it is re-applied per node in decorateNode (see the setColor block there).
        let treeSymbolCtor: SymbolLikeCtor = { data, idx, scope, opts in
            var o = opts ?? SymbolOpts()
            o.useNameLabel = true
            return Symbol(data, idx, scope, o)
        }
        // Retain ONE SymbolDraw across renders; add its group to `_mainGroup` exactly once. On the first
        //   render its internal `_data` is nil → all-`.add` (entrance); on refresh it diffs → `.update`
        //   (reuse + tween) / `.remove` (collapse). This is the crux of the reset fix.
        let symbolDraw = self._symbolDraw ?? SymbolDraw(treeSymbolCtor)
        if self._symbolDraw == nil {
            self._symbolDraw = symbolDraw
            _ = group.add(symbolDraw.group)
        }
        let oldData = self._data
        let entranceRootLayout = data.tree?.root.children.first.flatMap { treeNodeLayout($0.getLayout()) }
        var oldIndexByNew: [Int: Int] = [:]
        var enteringIndices = Set<Int>()
        var enteringStartLayouts: [Int: TreeNodeLayout] = [:]
        var disappearingIndices: [Int] = []
        data.diff(oldData)
            .add { newIndex in
                if symbolNeedsDraw(data, newIndex) { enteringIndices.insert(newIndex) }
            }
            .update { newIndex, oldIndex in
                oldIndexByNew[newIndex] = oldIndex
                let oldSymbol = oldData?.getItemGraphicEl(oldIndex) as? Symbol
                if symbolNeedsDraw(data, newIndex) {
                    if oldSymbol == nil { enteringIndices.insert(newIndex) }
                }
                else if oldSymbol != nil {
                    disappearingIndices.append(newIndex)
                }
            }
            .execute()
        func enteringStartLayout(_ dataIndex: Int, _ visiting: inout Set<Int>) -> TreeNodeLayout? {
            if let cached = enteringStartLayouts[dataIndex] { return cached }
            guard visiting.insert(dataIndex).inserted,
                  let node = data.tree?.getNodeByDataIndex(dataIndex) else { return nil }
            defer { visiting.remove(dataIndex) }
            if self._firstRender, let root = entranceRootLayout {
                enteringStartLayouts[dataIndex] = root
                return root
            }
            let virtualRoot = data.tree!.root
            let source = node.parentNode === virtualRoot ? node : (node.parentNode ?? node)
            guard let sourceLayout = treeNodeLayout(source.getLayout()) else { return nil }
            let oldSourceIndex = oldIndexByNew[source.dataIndex]
            let start: TreeNodeLayout
            if let oldSourceIndex,
               let oldSource = oldData?.getItemGraphicEl(oldSourceIndex) as? Symbol {
                start = TreeNodeLayout(
                    x: oldSource.x, y: oldSource.y,
                    rawX: oldSource.__radialRawX ?? sourceLayout.rawX,
                    rawY: oldSource.__radialRawY ?? sourceLayout.rawY
                )
            }
            else if source !== node,
                    enteringIndices.contains(source.dataIndex),
                    let sourceStart = enteringStartLayout(source.dataIndex, &visiting) {
                // Web has already created the new parent at its own sourceOldLayout before it creates
                // the child, so a wholly inserted subtree grows from one shared retained ancestor.
                start = sourceStart
            }
            else {
                start = sourceLayout
            }
            enteringStartLayouts[dataIndex] = start
            return start
        }
        for dataIndex in enteringIndices {
            var visiting = Set<Int>()
            _ = enteringStartLayout(dataIndex, &visiting)
        }

        var opt = SymbolDrawUpdateOpt()
        // Same bag the ctor closure applies, so `useNameLabel` survives the `.update()` diff branch too —
        //   upstream hands the identical opts to `new SymbolClz(...)` (TreeView.ts:357) and to
        //   `symbolEl.updateData(...)` (:365). Without it a re-render (e.g. a legend toggle) silently
        //   relabelled every node with its value, and internal nodes — which have none — lost their label.
        opt.symbolOpts = SymbolOpts(useNameLabel: true)
        // The node layout is a `{ x, y, rawX, rawY }` bag (treeLayout → setItemLayout); feed SymbolDraw
        //   the group-local `[x, y]` pixel point (nil skips the node — SymbolDraw's symbolNeedsDraw gate).
        opt.getSymbolPoint = { i in
            guard symbolNeedsDraw(data, i) else { return nil }
            guard let layout = data.getItemLayout(i) as? [String: Any],
                  let x = layout["x"] as? Double, let y = layout["y"] as? Double else { return nil }
            return [x, y]
        }
        // Upstream TreeView routes both an update that loses layout and a real diff removal through
        // removeNode(oldData,...). Keep SymbolDraw's shared lifecycle, but delegate only this removal
        // seam back to TreeView so the exact source-node node/label/edge leave animation is preserved.
        opt.removeSymbol = { [weak self] oldData, oldIndex, symbolEl, symbolGroup in
            self?.removeTreeNode(
                oldData, oldIndex, symbolEl, symbolGroup, group, seriesModel
            )
        }
        symbolDraw.updateData(data, opt)
        // In upstream the collapsed NEW SeriesData never receives the old graphic element: removeNode
        // operates on oldData only. SeriesData instances in this port can share the graphic-element slot,
        // so clear the new side explicitly after SymbolDraw invokes the old-data removal callback.
        for dataIndex in disappearingIndices {
            data.setItemGraphicEl(dataIndex, nil)
        }

        // Web creates every new/re-expanded node at sourceOldLayout, then updateProps-tweens it to its
        // target. On the first render all source-old coordinates resolve to the real root.
        for (dataIndex, start) in enteringStartLayouts {
            guard let symbolEl = data.getItemGraphicEl(dataIndex) as? Symbol,
                  let target = treeNodeLayout(data.getItemLayout(dataIndex)) else { continue }
            symbolEl.x = start.x
            symbolEl.y = start.y
            updateProps(symbolEl, ["x": target.x, "y": target.y], seriesModel, dataIndex)
        }

        // Per-node decoration the shared Symbol does not cover. Retain each edge by the owning Symbol,
        // exactly like upstream's `symbolEl.__edge`, so data-index reordering cannot swap edge identity.
        var liveEdges = Set<ObjectIdentifier>()
        for newIdx in 0..<data.count() {
            if symbolNeedsDraw(data, newIdx),
               let symbolEl = data.getItemGraphicEl(newIdx) as? Symbol,
               let targetLayout = treeNodeLayout(data.getItemLayout(newIdx)) {
                symbolEl.__radialOldRawX = symbolEl.__radialRawX
                symbolEl.__radialOldRawY = symbolEl.__radialRawY
                symbolEl.__radialRawX = targetLayout.rawX
                symbolEl.__radialRawY = targetLayout.rawY
                let owner = ObjectIdentifier(symbolEl)
                let edge = decorateNode(
                    data, newIdx, group, seriesModel, self._edges[owner],
                    enteringStartLayouts[newIdx]
                )
                if let edge = edge {
                    self._edges[owner] = edge
                    liveEdges.insert(owner)
                }
                else if let stale = self._edges[owner] {
                    // The node exists but no longer draws an edge (e.g. a now-collapsed polyline source).
                    _ = group.remove(stale)
                    self._edges[owner] = nil
                }
            }
        }
        // Remove edges whose owning symbol vanished / collapsed out this render.
        for (k, edge) in self._edges where !liveEdges.contains(k) {
            _ = group.remove(edge)
            self._edges[k] = nil
        }

        // this._updateNodeAndLinkScale(seriesModel);
        //   PORT-NOTE (deferred): setSymbolScale / calcCompensationScaleToPreserveNodeSize (roam) not ported.

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
                // upstream `el.off('click').on('click', ...)` — node Symbols are now REUSED across renders,
                //   so clear any handler bound on a previous render before re-binding (otherwise the click
                //   would dispatch `treeExpandAndCollapse` once per accumulated render).
                _ = el.off("click")
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

        // this._firstRender = false;
        //   PORT-NOTE: the two early `guard` bail-outs above (no `data.tree` / no `layoutInfo` — both
        //   non-null upstream) skip this on purpose: nothing was placed, so the NEXT render is still the
        //   first one and must apply the coord-sys trans synchronously rather than tween it.
        self._firstRender = false
    }

    // L3 Roam: the pointer-check element (upstream `createIsInSelfByPointerCheckerEl(this.group)`).
    func roamPointerCheckerGroup() -> Group { return self.group }

    // L3 Roam (test hook): the main group carrying the roam transform (position + scale).
    var _mainGroupForTest: Group { return self._mainGroup }

    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — the port re-renders via the full update()
    //   the `treeRoam` action triggers (see roamHelperViewGroup.swift DEVIATION note); no partial path.

    // upstream: private _updateViewCoordSys(seriesModel: TreeSeriesModel, api: ExtensionAPI) {
    //     const data = seriesModel.getData();
    //     const points: number[][] = [];
    //     data.each(function (idx) {
    //         const layout = data.getItemLayout(idx);
    //         if (layout && !isNaN(layout.x) && !isNaN(layout.y)) { points.push([+layout.x, +layout.y]); }
    //     });
    //     const min: number[] = []; const max: number[] = [];
    //     bbox.fromPoints(points, min, max);
    //     const oldMin = this._min; const oldMax = this._max;
    //     if (max[0] - min[0] === 0) { min[0] = oldMin ? oldMin[0] : min[0] - 1; max[0] = oldMax ? oldMax[0] : max[0] + 1; }
    //     if (max[1] - min[1] === 0) { min[1] = oldMin ? oldMin[1] : min[1] - 1; max[1] = oldMax ? oldMax[1] : max[1] + 1; }
    //     const ownCoordSys = seriesModel.coordinateSystem = createViewCoordSysSimply(
    //         seriesModel, api, min[0], min[1], max[0] - min[0], max[1] - min[1]);
    //     applyViewCoordSysTransToElement(this.group, VIEW_COORD_SYS_TRANS_OVERALL, ownCoordSys,
    //         this._firstRender ? null : seriesModel);
    //     this._min = min; this._max = max;
    // }
    private func _updateViewCoordSys(_ seriesModel: TreeSeriesModel, _ api: ExtensionAPI) {
        let data = seriesModel.getData()
        var points: [[Double]] = []
        // data.each(idx => ...) — the port iterates the data indices directly (same as render above).
        for idx in 0..<data.count() {
            // `layout && !isNaN(layout.x) && !isNaN(layout.y)`: the tree layout bag is `{x, y, rawX, rawY}`;
            //   a missing/NaN coordinate (an unlaid-out / collapsed node) is skipped.
            guard let layout = data.getItemLayout(idx) as? [String: Any],
                  let x = layout["x"] as? Double, let y = layout["y"] as? Double,
                  !x.isNaN, !y.isNaN else {
                continue
            }
            points.append([x, y])
        }
        // PORT-NOTE (deviation): upstream passes EMPTY `min`/`max` arrays into `bbox.fromPoints`, so with
        //   zero laid-out points they stay empty and `max[0] - min[0]` evaluates to NaN — the degenerate-box
        //   branch below is NOT taken and the coord sys ends up with a NaN dataRect (nothing renders). Swift
        //   has no NaN-by-missing-index, so the port bails out instead: with no points there is nothing to
        //   place, and leaving the previous coordinateSystem / `_min` / `_max` untouched is the closest safe
        //   analogue (it also avoids latching an origin-based ±1 box into `_min`/`_max`).
        guard !points.isEmpty else { return }

        // bbox.fromPoints(points, min, max) — the Swift port is value-returning (out-params dropped, §10).
        let (minOut, maxOut) = bbox.fromPoints(points, [0, 0], [0, 0])
        var min: VectorArray = minOut
        var max: VectorArray = maxOut

        // If don't Store min max when collapse the root node after roam,
        // the root node will disappear.
        let oldMin = self._min
        let oldMax = self._max

        // If width or height is 0
        if max[0] - min[0] == 0 {
            min[0] = oldMin?[0] ?? (min[0] - 1)
            max[0] = oldMax?[0] ?? (max[0] + 1)
        }
        if max[1] - min[1] == 0 {
            min[1] = oldMin?[1] ?? (min[1] - 1)
            max[1] = oldMax?[1] ?? (max[1] + 1)
        }

        // Here we use viewCoordSys just for computing the 'position' and 'scale' of the group,
        // and 'treeRoam' action.
        let ownCoordSys = createViewCoordSysSimply(
            seriesModel, api,
            min[0], min[1], max[0] - min[0], max[1] - min[1]
        )
        // PORT-NOTE (deviation): the roam pan/zoom of this view lives OUTSIDE the coord sys — it is applied
        //   to `_mainGroup` by viewGroupRoamApplyStateToGroup (roamHelperViewGroup.swift) in zr SCREEN-pixel
        //   units. `createViewCoordSysSimply` faithfully seeds the coord sys from the series' `center` /
        //   `zoom` / `scaleLimit` options, which would compose a SECOND (differently-anchored) transform onto
        //   `self.group` — the parent of `_mainGroup` — making the RoamController's screen-space dx/dy and
        //   originX/originY disagree with the space they are applied in. So the roam option is reset to
        //   neutral here (center nil, zoom 1, no limit), which makes the OVERALL trans applied below the
        //   identity unconditionally and keeps this call placement-neutral.
        //   PORT-TODO: honour `series.center` / `series.zoom` by seeding ViewGroupRoamState from them once
        //   (as roamHelperGeo does) rather than through the coord sys.
        viewCoordSysSetRoamOption(ownCoordSys, nil, 1, nil)
        seriesModel.coordinateSystem = ownCoordSys

        applyViewCoordSysTransToElement(
            self.group,
            VIEW_COORD_SYS_TRANS_OVERALL,
            ownCoordSys,
            self._firstRender ? nil : seriesModel
        )

        self._min = min
        self._max = max
    }

    // upstream: _updateNodeAndLinkScale(seriesModel)  — PORT-NOTE: setSymbolScale (roam) DEFERRED.

    private func removeTreeNode(
        _ data: SeriesData,
        _ dataIndex: Int,
        _ symbolEl: Symbol,
        _ symbolGroup: Group,
        _ edgeGroup: Group,
        _ seriesModel: TreeSeriesModel
    ) {
        guard let node = data.tree?.getNodeByDataIndex(dataIndex),
              let (_, sourceLayout) = treeSourceNode(data.tree!.root, node) else { return }

        var removeAnimation = AnimationOption()
        removeAnimation.duration = treeToDouble(seriesModel.get("animationDurationUpdate", false))
        if let easing = seriesModel.get("animationEasingUpdate", false) as? String {
            removeAnimation.easing = .named(easing)
        }

        removeElement(
            symbolEl,
            ["x": sourceLayout.x + 1.0, "y": sourceLayout.y + 1.0],
            seriesModel,
            AnimateOrSetPropsOption(
                dataIndex: dataIndex,
                cb: { [weak symbolEl, weak symbolGroup, weak data] in
                    if let symbolEl { _ = symbolGroup?.remove(symbolEl) }
                    data?.setItemGraphicEl(dataIndex, nil)
                },
                removeOpt: removeAnimation
            )
        )
        symbolEl.fadeOut(
            nil,
            data.hostModel as? TreeSeriesModel,
            SymbolFadeOutOpt(fadeLabel: true, animation: removeAnimation)
        )

        for child in node.children {
            removeTreeNodeEdge(child, data, edgeGroup, seriesModel, removeAnimation)
        }
        removeTreeNodeEdge(node, data, edgeGroup, seriesModel, removeAnimation)
    }

    private func removeTreeNodeEdge(
        _ node: TreeNode,
        _ data: SeriesData,
        _ group: Group,
        _ seriesModel: TreeSeriesModel,
        _ removeAnimation: AnimationOption
    ) {
        guard let tree = data.tree,
              let (source, sourceLayout) = treeSourceNode(tree.root, node) else { return }

        let symbolEl = data.getItemGraphicEl(node.dataIndex) as? Symbol
        let sourceSymbolEl = data.getItemGraphicEl(source.dataIndex) as? Symbol
        let nodeOwner = symbolEl.map(ObjectIdentifier.init)
        let sourceOwner = sourceSymbolEl.map(ObjectIdentifier.init)
        let sourceEdge = sourceOwner.flatMap { self._edges[$0] }
        let owner: ObjectIdentifier?
        if let nodeOwner, self._edges[nodeOwner] != nil {
            owner = nodeOwner
        }
        else if source.isExpand == false || source.children.count == 1, sourceEdge != nil {
            owner = sourceOwner
        }
        else {
            owner = nil
        }
        guard let owner, let edge = self._edges[owner] else { return }
        self._edges[owner] = nil

        let edgeShape = (seriesModel.get("edgeShape", false) as? String) ?? "curve"
        let layout = (seriesModel.get("layout", false) as? String) ?? "orthogonal"
        let orient = seriesModel.getOrient()
        let curvature = treeToDouble(seriesModel.get(["lineStyle", "curveness"], false))
        let targetShape: [String: Any]
        if edgeShape == "curve" {
            targetShape = bezierShapeDict(
                getEdgeShape(layout, orient, curvature, sourceLayout, sourceLayout)
            )
        }
        else if edgeShape == "polyline", layout == "orthogonal" {
            targetShape = [
                "parentPoint": [sourceLayout.x, sourceLayout.y],
                "childPoints": [[sourceLayout.x, sourceLayout.y]]
            ]
        }
        else {
            return
        }

        removeElement(
            edge,
            ["shape": targetShape, "style": ["opacity": 0.0] as [String: Any]],
            seriesModel,
            AnimateOrSetPropsOption(
                dataIndex: node.dataIndex,
                cb: { [weak edge, weak group] in
                    if let edge { _ = group?.remove(edge) }
                },
                removeOpt: removeAnimation
            )
        )
    }

    // upstream: dispose() { this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): RoamController.dispose DEFERRED (roam not wired into this view).
    }

    // upstream: remove() { this._mainGroup.removeAll(); this._data = null; }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self._mainGroup.removeAll()
        self._data = nil
        // The retained node-symbol draw + edge registry were just detached by removeAll — drop them so the
        //   next render rebuilds from a clean slate (re-adds a fresh SymbolDraw group).
        self._symbolDraw = nil
        self._edges = [:]
    }
}

private func treeSourceNode(
    _ virtualRoot: TreeNode,
    _ node: TreeNode
) -> (source: TreeNode, layout: TreeNodeLayout)? {
    var source = node.parentNode === virtualRoot ? node : (node.parentNode ?? node)
    while treeNodeLayout(source.getLayout()) == nil {
        source = source.parentNode === virtualRoot ? source : (source.parentNode ?? source)
    }
    guard let layout = treeNodeLayout(source.getLayout()) else { return nil }
    return (source, layout)
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
@discardableResult
private func decorateNode(
    _ data: SeriesData,
    _ dataIndex: Int,
    _ group: Group,
    _ seriesModel: TreeSeriesModel,
    _ existingEdge: Path?,
    _ sourceOldLayout: TreeNodeLayout?
) -> Path? {
    // const node = data.tree.getNodeByDataIndex(dataIndex);
    guard let node = data.tree?.getNodeByDataIndex(dataIndex) else { return nil }

    // The Symbol (Group) SymbolDraw created for this node + its symbol Path child.
    let symbolEl = data.getItemGraphicEl(dataIndex) as? Symbol
    let symbolPath = symbolEl?.getSymbolPath()

    // const virtualRoot = data.tree.root;
    let virtualRoot: TreeNode = data.tree!.root

    // const source = node.parentNode === virtualRoot ? node : node.parentNode || node;
    let source: TreeNode = node.parentNode === virtualRoot ? node : (node.parentNode ?? node)
    // const sourceLayout = source.getLayout() as TreeNodeLayout;
    let sourceLayout = treeNodeLayout(source.getLayout())
    // const targetLayout = node.getLayout();
    guard let targetLayout = treeNodeLayout(node.getLayout()) else { return nil }

    // const itemModel = node.getModel();  (used below for focus + by drawEdge for lineStyle)
    let itemModel = data.getItemModel(dataIndex)
    let emphasisModel = itemModel.getModel(["emphasis"])
    let focus: InnerFocus? = emphasisModel.get("focus")

    // upstream (updateNode TreeView.ts:337-339): the collapsed-node hollow inner-fill marker.
    //   `symbolInnerColor` is the inner fill of an empty-brush (hollow) symbol — the node's OWN colour when
    //   it is a COLLAPSED internal node (isExpand === false && children.length !== 0), else neutral00 (the
    //   hollow white centre). Upstream passes it to the SymbolClz ctor/updateData opts, which run
    //   `ec.setColor(visualColor, symbolInnerColor)`. The shared SymbolDraw creates its own opts without the
    //   inner colour, so re-apply it here (runs on both the add and update passes, so an expand/collapse
    //   toggle repaints the marker). Mirror Symbol's guard: only when the node has a visual fill.
    if let symbolPath = symbolPath, let ec = symbolPath as? ECSymbol,
       let visualColor = treeVisualFill(node.getVisual("style")) {
        let symbolInnerColor: ZRenderKit.ZRColor = (node.isExpand == false && !node.children.isEmpty)
            ? .string(visualColor)
            : .string(tokens_color_neutral00)
        ec.setColor(.string(visualColor), symbolInnerColor)
    }

    // Tree's outward label side + (radial) label rotation. For the ORTHOGONAL port the side is chosen per
    //   orientation — internal nodes label on the inner side, leaves on the outer. For the RADIAL layout,
    //   upstream (TreeView.ts:389-444) computes a per-node angle `rad`/`isLeft` and rotates the label to
    //   point radially outward (position left/right + rotation -rad + origin 'center' + verticalAlign
    //   'middle'). The shared Symbol already built the label (stamping `outsideFill`), so mutate the existing
    //   textConfig in place (upstream `setTextConfig` field-merges) rather than replacing it wholesale.
    if let symbolPath = symbolPath {
        let treeLayout = (seriesModel.get("layout", false) as? String) ?? "orthogonal"
        if treeLayout == "radial" {
            // upstream TreeView.ts:389-444 — radial label rotation.
            //   const realRoot = virtualRoot.children[0]; const rootLayout = realRoot.getLayout();
            if let realRoot = virtualRoot.children.first,
               let rootLayout = treeNodeLayout(realRoot.getLayout()) {
                let length = realRoot.children.count
                var rad: Double
                var isLeft: Bool

                if targetLayout.x == rootLayout.x && node.isExpand == true && length != 0,
                   let firstL = treeNodeLayout(realRoot.children[0].getLayout()),
                   let lastL = treeNodeLayout(realRoot.children[length - 1].getLayout()) {
                    // const center = { x: (first.x + last.x) / 2, y: (first.y + last.y) / 2 };
                    let centerX = (firstL.x + lastL.x) / 2
                    let centerY = (firstL.y + lastL.y) / 2
                    rad = atan2(centerY - rootLayout.y, centerX - rootLayout.x)
                    if rad < 0 { rad = Double.pi * 2 + rad }
                    isLeft = centerX < rootLayout.x
                    if isLeft { rad = rad - Double.pi }
                }
                else {
                    rad = atan2(targetLayout.y - rootLayout.y, targetLayout.x - rootLayout.x)
                    if rad < 0 { rad = Double.pi * 2 + rad }
                    if node.children.isEmpty || (!node.children.isEmpty && node.isExpand == false) {
                        isLeft = targetLayout.x < rootLayout.x
                        if isLeft { rad = rad - Double.pi }
                    }
                    else {
                        isLeft = targetLayout.x > rootLayout.x
                        if !isLeft { rad = rad - Double.pi }
                    }
                }

                let textPosition = isLeft ? "left" : "right"
                let normalLabelModel = itemModel.getModel(["label"])
                // const rotate = normalLabelModel.get('rotate'); labelRotateRadian = rotate * (PI/180);
                let rotateRaw = normalLabelModel.get("rotate")
                if let textContent = symbolPath.getTextContent() {
                    let pinned = normalLabelModel.get("position")
                    if symbolPath.textConfig == nil { symbolPath.textConfig = ElementTextConfig() }
                    symbolPath.textConfig?.position = pinned ?? textPosition
                    // rotation: rotate == null ? -rad : rotate * (PI/180)
                    if let rotateRaw = rotateRaw, !(rotateRaw is NSNull) {
                        symbolPath.textConfig?.rotation = treeToDouble(rotateRaw) * (Double.pi / 180)
                    }
                    else {
                        symbolPath.textConfig?.rotation = -rad
                    }
                    symbolPath.textConfig?.origin = "center"
                    // textContent.setStyle('verticalAlign', 'middle');
                    textContent.textStyle?.verticalAlign = .middle
                }
            }
        }
        else {
            // Orthogonal tree label side (port deviation): internal nodes inner, leaves outer. Only touch it
            //   when a label was actually created (normal `show != false`); respect a model-pinned position.
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
    //   Pass the node's retained edge (if any) so a refresh REUSES + `updateProps`-tweens it (upstream's
    //   `symbolEl.__edge` cache); a nil return means this node draws no edge this render.
    let edgeEl = drawEdge(
        seriesModel, node, virtualRoot, sourceLayout, targetLayout, group, existingEdge,
        sourceOldLayout
    )

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

    // Return the (reused or newly-created) edge so the caller can retain it in `_edges` for the next render.
    return edgeEl
}

// upstream: function drawEdge(seriesModel, node, virtualRoot, symbolEl, sourceOldLayout,
//     sourceLayout, targetLayout, group)
//   `symbolEl.__edge` is reproduced by the caller's `_edges` registry: an `existingEdge` (the node's edge
//   from the previous render) is REUSED and `updateProps`-tweened to the new shape (upstream's
//   `graphic.updateProps(edge, { shape })`) instead of building a fresh one; new edges start collapsed at
//   sourceOldLayout and tween to their target shape.
@discardableResult
private func drawEdge(
    _ seriesModel: TreeSeriesModel,
    _ node: TreeNode,
    _ virtualRoot: TreeNode,
    _ sourceLayout: TreeNodeLayout?,
    _ targetLayout: TreeNodeLayout,
    _ group: Group,
    _ existingEdge: Path?,
    _ sourceOldLayout: TreeNodeLayout?
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
            // upstream: `if (!edge) { edge = new BezierCurve({ shape: getEdgeShape(...sourceOld...) }); }
            //            graphic.updateProps(edge, { shape: getEdgeShape(...source...target...) }, seriesModel);`
            //   REUSE the node's retained BezierCurve if present (tween its shape to the new curve — the
            //   BezierCurveShape supports keyed animation), else build a fresh one at the final shape.
            let target = getEdgeShape(layout, orient, curvature, sourceLayout, targetLayout)
            if let existing = existingEdge as? BezierCurve {
                updateProps(existing, ["shape": bezierShapeDict(target)], seriesModel)
                edge = existing
            }
            else {
                var props: ElementProps = [:]
                if let sourceOldLayout {
                    props["shape"] = getEdgeShape(
                        layout, orient, curvature, sourceOldLayout, sourceOldLayout
                    ) as PathShape
                }
                else {
                    props["shape"] = target as PathShape
                }
                edge = BezierCurve(props)
                if let edge = edge, sourceOldLayout != nil {
                    updateProps(edge, ["shape": bezierShapeDict(target)], seriesModel, node.dataIndex)
                }
            }
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
                if let existing = existingEdge as? TreePath {
                    updateProps(existing, ["shape": treeEdgeShapeDict(shape)], seriesModel, node.dataIndex)
                    edge = existing
                }
                else {
                    // Upstream initializes a new/re-expanded polyline at its owning parent and then
                    // grows the fork out to all children. This applies even when the parent symbol was
                    // retained while collapsed, so it must not depend on a newly-entering node layout.
                    let collapsed = TreeEdgeShape()
                    collapsed.parentPoint = [targetLayout.x, targetLayout.y]
                    collapsed.childPoints = [[targetLayout.x, targetLayout.y]]
                    collapsed.orient = orient
                    collapsed.forkPosition = edgeForkPosition
                    edge = TreePath(["shape": collapsed as PathShape])
                    if let edge = edge {
                        updateProps(edge, ["shape": treeEdgeShapeDict(shape)], seriesModel, node.dataIndex)
                    }
                }
            }
        }
        else {
            // if (__DEV__) { throw new Error('The polyline edgeShape can only be used in orthogonal layout'); }
            if __DEV__ {
                log.error("The polyline edgeShape can only be used in orthogonal layout")
            }
        }
    }

    // show all edge when edgeShape is 'curve', filter node `isExpand` is false when edgeShape is 'polyline'
    if let edge = edge, !(edgeShape == "polyline" && !node.isExpand) {
        // If the edge shape changed type between renders (curve <-> polyline), the retained edge was NOT
        //   reused (a fresh one was built); drop the stale element so it doesn't linger in the un-wiped group.
        if let existingEdge = existingEdge, existingEdge !== edge {
            _ = group.remove(existingEdge)
        }
        // edge.useStyle(zrUtil.defaults({ strokeNoScale: true, fill: null }, lineStyle));
        edge.useStyle(treeEdgeStyle(lineStyle))
        // `useStyle` runs createStyle, which lays the style over DEFAULT_PATH_STYLE (fill '#000') and
        // SKIPS the nil `fill` — so the intended `fill: null` is dropped and the edge curve/fork fills
        // solid black (visual-parity trap class 1). Clear it directly to keep edges as thin strokes.
        edge.pathStyle.fill = nil

        // Phase 45: attach the emphasis-state lineStyle (upstream TreeView.ts drawEdge
        //   setStatesStylesFromModel(edge, itemModel, 'lineStyle')). The edge is not itself a highDown
        //   dispatcher (tree edges are anonymous children, not in edge-data), so this state takes effect
        //   via the node symbol's blur-propagation hook (see decorateNode's onHoverStateChange forwarder).
        if let itemModel = itemModel {
            states.setStatesStylesFromModel(edge, itemModel, "lineStyle")
        }
        // upstream: setDefaultStateProxy(edge) (TreeView.ts:555) — installs the default-state transition
        //   proxy so the edge's emphasis/blur states are applied through the shared highDown machinery.
        states.setDefaultStateProxy(edge)

        _ = group.add(edge)
        return edge
    }
    return nil
}

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

// `graphic.updateProps(edge, { shape: getEdgeShape(...) })` passes an object literal as the shape target;
//   the port's Animator interpolates a `["shape": [scalarKey: Double]]` bag (each key routed through
//   BezierCurveShape.animationSet). Flatten a computed BezierCurveShape into that scalar bag so a reused
//   curve edge TWEENS its control points to the new geometry.
private func bezierShapeDict(_ s: BezierCurveShape) -> [String: Any] {
    var d: [String: Any] = [
        "x1": s.x1, "y1": s.y1, "x2": s.x2, "y2": s.y2,
        "cpx1": s.cpx1, "cpy1": s.cpy1
    ]
    if let cpx2 = s.cpx2 { d["cpx2"] = cpx2 }
    if let cpy2 = s.cpy2 { d["cpy2"] = cpy2 }
    return d
}

private func treeEdgeShapeDict(_ shape: TreeEdgeShape) -> [String: Any] {
    ["parentPoint": shape.parentPoint, "childPoints": shape.childPoints]
}

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
