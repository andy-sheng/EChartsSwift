// Ported (STATIC SUBSET) from echarts/src/chart/graph/GraphView.ts — keep in sync with upstream.
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
//   import SymbolDraw from '../helper/SymbolDraw';                 -> SymbolDraw (chart/helper/SymbolDraw.swift).
//       The node symbol is built inline with `symbol.createSymbol` (same deviation as ScatterView /
//       TreeView); SymbolDraw's enter/update/leave diff + `SymbolClz` reuse are DEFERRED.
//   import LineDraw from '../helper/LineDraw';                     -> ported as chart/helper/LineDraw.swift
//       (wired in LinesView). NOT used here: this view draws each edge inline with a ZRenderKit `Line`
//       (straight) or `BezierCurve` (curveness), exactly how TreeView draws its parent->child links.
//       WIRING GraphView onto LineDraw (per-edge diff + fromSymbol/toSymbol markers + effect/label) is DEFERRED.
//   import RoamController from '../../component/helper/RoamController';   -> RoamController (component/helper/RoamController.swift); not wired in GraphView (roam DEFERRED).
//   import { isRoamPayloadHasZoom, updateRoamControllerSimply } from '../../component/helper/roamHelper';
//       -> roamHelper (component/helper/roamHelper*.swift); not wired in GraphView (roam DEFERRED).
//   import * as graphic from '../../util/graphic';                 -> `Group` / `Line` / `BezierCurve` (ZRenderKit).
//       PORT-NOTE: graphic.updateProps/removeElement (animation/basicTransition.swift) exist; the static render sets
//       final geometry directly (same deviation as FunnelView/PieView/SunburstView/TreeView).
//   import adjustEdge from './adjustEdge';                         -> adjustEdge (chart/graph/adjustEdge.swift, ported).
//       adjustEdge trims each edge's endpoints back to the node symbol boundary (so an arrow head does
//       not sit under the node). It mutates the edge layout points in place and depends on
//       getNodeGlobalScale (roam fallback == 1). Wired in render() after the symbol-visual stage.
//   import {getNodeGlobalScale} from './graphHelper';             -> getNodeGlobalScale (chart/graph/graphHelper.swift).
//       getNodeGlobalScale = calcCompensationScaleToPreserveNodeSize (coord/View, roam) — DEFERRED (== 1).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import GraphSeriesModel, { GraphNodeItemOption, GraphEdgeItemOption, SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> sibling GraphSeries.swift (assumed ported alongside data/Graph.swift).
//   import View, { applyViewCoordSysTransToElement, getOwnRoamViewCoordSys,
//            VIEW_COORD_SYS_TRANS_OVERALL, viewCoordSysCopyOverallMatrix } from '../../coord/View';
//       -> PORT-NOTE: coord/View NOT ported (roam / view coord-system transform DEFERRED).
//   import Symbol from '../helper/Symbol';                         -> SymbolElement (chart/helper/SymbolElement.swift).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import Line from '../helper/Line';                             -> ported as chart/helper/ECLine.swift
//       (renamed to avoid colliding with the ZRenderKit `Line` SHAPE). NOT used here — this view builds an
//       inline `Line`/`BezierCurve` per edge; wiring GraphView onto LineDraw/ECLine is DEFERRED.
//   import { getECData } from '../../util/innerStore';             -> getECData (util/innerStore.swift).
//   import { simpleLayoutEdge } from './simpleLayoutHelper';       -> sibling simpleLayoutHelper.swift (used by drag; DEFERRED).
//   import { circularLayout, rotateNodeLabel } from './circularLayoutHelper';  -> sibling circularLayoutHelper.swift.
//   import { clone, extend } from 'zrender/src/core/util';         -> ZRenderKit.util (only used by thumbnail; DEFERRED).
//   import ECLinePath from '../helper/LinePath';                   -> PORT-NOTE: no ECLinePath TYPE exists in
//       this port. Its behaviour is modelled inside chart/helper/ECLine.swift by the `Line` (straight) /
//       `BezierCurve` (quadratic) pair — see `createLine` / `setLineShapePoints` / `setCurveShapePoints`
//       plus the `setChildPercent` / `pointAtOf` / `tangentAtOf` helpers. Upstream references ECLinePath
//       in THIS file ONLY inside `_renderThumbnail` (GraphView.ts:410-412), which is DEFERRED here along
//       with thumbnailBridge (note below) — so there is nothing for this file to reference.
//   import { NullUndefined, RoamHostView, RoamPayload } from '../../util/types';  -> util/types.swift (type-only).
//   import { getThumbnailBridge, ThumbnailBridge } from '../../component/helper/thumbnailBridge';
//       -> PORT-NOTE (deferred): requires component/helper/thumbnailBridge (not ported; thumbnail deferred).
//   import { ListForSymbolDraw } from '../helper/baseDraw';        -> PORT-NOTE (deferred): requires chart/helper/baseDraw (not ported).

// upstream: class GraphView extends ChartView implements RoamHostView
//   PORT-NOTE (deferred): RoamHostView (`__updateOnOwnRoam`) NOT implemented — roam deferred per CONVENTIONS §5.
open class GraphView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_GRAPH;  /  readonly type = SERIES_TYPE_GRAPH;
    public static let graphType = SERIES_TYPE_GRAPH
    open override var type: String {
        get { SERIES_TYPE_GRAPH }
        set { /* readonly upstream */ }
    }

    // upstream: private _symbolDraw: SymbolDraw;  private _lineDraw: LineDraw;
    //   PORT-NOTE: SymbolDraw is ported (used by render); a graph-edge LineDraw is not. The static render adds node symbols + edges to
    //   `_mainGroup` directly (rebuilt each pass), so the two sub-draw groups collapse into one.

    // PORT-NOTE: private _controller: RoamController;  — RoamController is ported but not wired in GraphView (roam DEFERRED).
    // PORT-NOTE (deferred): private _firstRender / _active — only used by roam + thumbnail (deferred).
    // upstream: private _layoutTimeout: number;  private _layouting: boolean;
    //   `setTimeout(step, 16)` → a main-queue `DispatchWorkItem` (this port's established `setTimeout`
    //   idiom — see util/throttle.swift and component/timeline/SliderTimelineView.swift), so
    //   `clearTimeout(this._layoutTimeout)` becomes `_layoutTimeout?.cancel()`.
    private var _layoutTimeout: DispatchWorkItem?
    private var _layouting: Bool = false

    // upstream: private _model: GraphSeriesModel;  private _api: ExtensionAPI;
    private var _model: GraphSeriesModel?
    private var _api: ExtensionAPI?

    // upstream: private _mainGroup: graphic.Group;
    private let _mainGroup = Group()

    // Element LIFECYCLE (fix reset-on-update): upstream keeps ONE SymbolDraw (nodes) + ONE LineDraw
    //   (edges) whose sub-groups live under `_mainGroup` for the view's whole life, and each render
    //   DIFFS the data into them (enter/update/leave), so a merge-mode setOption REUSES + tweens the
    //   node symbols and edge shapes instead of `group.removeAll()`-rebuilding them. The port persists
    //   the SymbolDraw (its own enter/update/leave diff) and an `_edgeGroup` holding the inline edge
    //   Line/BezierCurve elements, keyed by data index in `_edgeEls` and MORPHED (updateProps) in place.
    //   PORT-NOTE: the edges are NOT routed through the shared `chart/helper/LineDraw` class — the graph
    //   bakes the (deferred) view-coord transform into each endpoint per-render via `fitPoint`, and edge
    //   labels come from the `edgeLabel` parent-redirect, neither of which the faithful ECLine models;
    //   so the edge geometry/label code is kept inline and only its lifecycle (reuse vs rebuild) changes.
    private let _symbolDraw = SymbolDraw()
    private let _edgeGroup = Group()
    private var _edgeEls: [Int: Path] = [:]
    // GraphView keeps its edge geometry inline instead of using ECLine, so keep the corresponding
    // from/to endpoint symbols here as siblings of each edge. The visual stage has already resolved
    // `edgeSymbol` / `edgeSymbolSize` into the edge data's `fromSymbol*` / `toSymbol*` item visuals.
    private var _edgeEndSymbolEls: [Int: [_GraphEdgeEndSymbol]] = [:]
    // The per-edge label (wave-1 `graphAddEdgeLabel`) is a free-standing element added to `_mainGroup`.
    //   Now that `_mainGroup` is no longer wiped each render, track it by edge index so it can be
    //   removed-and-rebuilt on update (and dropped on leave) instead of accumulating every render.
    private var _edgeLabelEls: [Int: ZRText] = [:]
    // The per-edge label's resolved `distance` Y offset, cached so the force-layout iteration can
    //   RE-PLACE the label along the moved edge (upstream re-runs Line's `beforeUpdate` every frame)
    //   without rebuilding its style models. Keyed by edge index, alongside `_edgeLabelEls`.
    private var _edgeLabelDistanceY: [Int: Double] = [:]

    // upstream: private _active: boolean;  — set true by render(), false by remove(); `updateLayout`
    //   early-returns when it is false, so a late force-layout step after a teardown does not
    //   re-materialize elements into an emptied group.
    private var _active: Bool = false

    // The box holding the self-referencing force-layout `step` closure (upstream's named function
    //   expression). OWNED by the view so every abandonment path (re-render / remove) can break the
    //   closure cycle, not just the settled path.
    private var _forceStepBox: _GraphForceStepBox?

    // upstream: init(ecModel, api) {
    //     const symbolDraw = new SymbolDraw();  const lineDraw = new LineDraw();
    //     const group = this.group;  const mainGroup = new graphic.Group();
    //     this._controller = new RoamController(api.getZr());
    //     mainGroup.add(symbolDraw.group);  mainGroup.add(lineDraw.group);  group.add(mainGroup);
    //     this._symbolDraw = symbolDraw;  this._lineDraw = lineDraw;  this._mainGroup = mainGroup;
    //     this._firstRender = true;
    // }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): RoamController + _firstRender deferred. The SymbolDraw (node) group and
        //   the edge group are added to `_mainGroup` ONCE here (upstream `mainGroup.add(symbolDraw.group);
        //   mainGroup.add(lineDraw.group)`) and PERSIST across renders — the render diffs into them.
        _ = self._mainGroup.add(self._symbolDraw.group)
        _ = self._mainGroup.add(self._edgeGroup)
        _ = self.group.add(self._mainGroup)
    }

    // upstream: render(seriesModel: GraphSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: GraphSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! GraphSeriesModel

        // const ownCoordSys = getOwnRoamViewCoordSys(seriesModel);
        //   PORT-NOTE: getOwnRoamViewCoordSys / applyViewCoordSysTransToElement / roam controller /
        //   thumbnail — the whole view-coord-system transform + roam block is DEFERRED (coord/View not
        //   ported). The node/edge layout positions are already in the series' local pixel space (set by
        //   circularLayout / simpleLayout), so the static render places `_mainGroup` at the origin.

        self._model = seriesModel
        self._api = api
        // upstream: `this._active = true;` (render entry) — the guard `updateLayout` checks.
        self._active = true

        let group = self._mainGroup

        // adjustEdge(seriesModel.getGraph(), getNodeGlobalScale(seriesModel));
        //   Both adjustEdge (chart/graph/adjustEdge.swift) and getNodeGlobalScale
        //   (chart/graph/graphHelper.swift, roam fallback == 1) are ported. The call is relocated to
        //   just after the symbol-visual stage below, because adjustEdge's endpoint-trim reads each
        //   node's symbolSize visual (getSymbolSize) — which this port populates in that visual stage
        //   rather than in a pre-render pipeline pass.

        let data: SeriesData = seriesModel.getData()
        // const edgeData = seriesModel.getEdgeData();
        let edgeData: SeriesData = seriesModel.getEdgeData()

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream delegates to `symbolDraw.updateData(data)` (per-node symbol
        //   enter/update/leave diff, reusing SymbolClz instances) and `lineDraw.updateData(edgeData)`
        //   (per-edge Line diff). SymbolClz/ECLinePath fromSymbol arrows + draggable + node/link scale +
        //   circular label rotation + thumbnail + forceLayout iteration are DEFERRED (see PORT-NOTEs).
        //   The node symbols DIFF through the persistent `_symbolDraw`; the edges are index-keyed reused
        //   in `_edgeGroup`. Both read the layout positions the layout stage stored on the two SeriesData
        //   stores. `_mainGroup` is NOT wiped — reuse is what keeps a merge-mode setOption from resetting.
        // ------------------------------------------------------------------------------------------

        // clearTimeout(this._layoutTimeout);  const forceLayout = seriesModel.forceLayout; ...
        //   The forceLayout iteration block is wired — but placed further down, at upstream's own
        //   position (GraphView.ts:147-153, AFTER symbolDraw.updateData / lineDraw.updateData), because
        //   `updateLayout` repositions the elements those two calls create.

        // --- Nodes: symbolDraw.updateData(data) --------------------------------------------------
        // L2 breadth: the shared SymbolDraw (chart/helper) draws graph node symbols — each a Symbol
        //   (Group) with the symbol Path child, carrying colour (from the item visual style.fill),
        //   the node label, emphasis hover-scale, symbolRotate/offset and the entrance scale-in.
        //   Edges stay inline (LineDraw not ported). The node/edge layouts are in the graph's DATA
        //   space; the View coord maps them onto the pixel view rect (fit-to-fill), so feed fitPoint'd
        //   points to SymbolDraw via getSymbolPoint.

        // The node/edge layouts are in the graph's DATA space; the View coord maps them onto the pixel
        //   view rect (fit-to-fill). Apply it here so `layout:'none'` graphs (raw x/y) fill the view like
        //   upstream, instead of rendering at their raw coordinates. `fitPoint` is identity when there is
        //   no view coord.
        let viewCoord = seriesModel.coordinateSystem as? GraphViewCoordSys
        func fitPoint(_ p: GraphPoint) -> GraphPoint { self._fitPoint(p, viewCoord) }

        // Symbol-visual stages populate the symbol / symbolSize / symbolRotate / symbolOffset /
        //   symbolKeepAspect data + item visuals SymbolDraw reads (GraphSeries.hasSymbolVisual = true).
        symbolVisual.seriesSymbolTask(seriesModel, ecModel)
        symbolVisual.dataSymbolTask(seriesModel)

        // adjustEdge(seriesModel.getGraph(), getNodeGlobalScale(seriesModel)); — relocated here (see the
        //   note above): trims each edge's endpoints back to the node symbol boundary. It reads node
        //   symbolSize (populated by the symbol-visual stage above) and is a no-op for edges without a
        //   from/toSymbol arrow (the default), so it faithfully matches upstream where arrows are absent
        //   and correctly shrinks endpoints where they are present. getNodeGlobalScale is the roam
        //   fallback (== 1) this phase.
        adjustEdge(seriesModel.getGraph(), graphHelper.getNodeGlobalScale(seriesModel))

        // upstream: `symbolDraw.updateData(data)`. Each node → a Symbol (Group) whose child path carries
        //   the node colour (item visual style.fill), the node label, emphasis hover-scale and the
        //   entrance scale-in. Node layouts are in DATA space → fitPoint maps them to the pixel view.
        //   PORT-NOTE: `focus === 'adjacency'` adjacency focus IS wired — in the post-loop below (search
        //   `emphasis.focus:'adjacency'`) using getAdjacentDataIndices (data/Graph.swift).
        var nodeOpt = SymbolDrawUpdateOpt()
        nodeOpt.getSymbolPoint = { i in
            guard let raw = graphPointFromLayout(data.getItemLayout(i)) else { return nil }
            let p = fitPoint(raw)
            return (p.x.isFinite && p.y.isFinite) ? [p.x, p.y] : nil
        }
        // Persistent SymbolDraw — diffs `data` against the previous render, reusing + tweening the node
        //   symbols instead of rebuilding them (its group was added to `_mainGroup` once in init_).
        self._symbolDraw.updateData(data, nodeOpt)

        // --- Edges: lineDraw.updateData(edgeData) ------------------------------------------------
        //   LineDraw iterates `edgeData`, reading `edgeData.getItemLayout(i)` — the point list the layout
        //   stage stored via edge.setLayout: `[[x1, y1], [x2, y2]]`, or `[[x1, y1], [x2, y2], [cpx, cpy]]`
        //   with a quadratic control point when `curveness` is non-zero (simpleLayoutEdge). The presence
        //   of the third point selects a BezierCurve over a straight Line — the same branch Line.ts uses.
        let seriesEdgeStyle = edgeData.getVisual("style") as? [String: Any]

        // Edge index-keyed reuse: track which indices produced a live edge this render so stale ones
        //   (a datum that vanished / no longer draws) can be dropped from `_edgeGroup` afterwards.
        var seenEdgeIdx = Set<Int>()

        for i in 0..<edgeData.count() {
            guard let pts = graphEdgePoints(edgeData.getItemLayout(i)) else { continue }
            let p1 = fitPoint(pts.0)
            let p2 = fitPoint(pts.1)
            let cp = pts.2.map { fitPoint($0) }
            if !p1.x.isFinite || !p1.y.isFinite || !p2.x.isFinite || !p2.y.isFinite { continue }

            // const lineStyle = edgeItemModel.getModel('lineStyle').getLineStyle();
            let edgeItemModel = edgeData.getItemModel(i)
            let lineStyle = edgeItemModel.getModel("lineStyle").getLineStyle()

            // Edge stroke: item visual style first (the graph visual stage writes the edge color into
            //   `stroke`), then the series edge visual style, then whatever lineStyle carries.
            let edgeItemStyle = (edgeData.getItemVisual(i, "style") as? [String: Any]) ?? seriesEdgeStyle
            var edgeStyle = graphEdgeStyle(lineStyle)
            if let cs = zrPaintFromStyleValue(edgeItemStyle?["stroke"]) { edgeStyle.stroke = cs }

            // Geometry: BezierCurve (quadratic, control point present) or straight Line. The SHAPE
            //   computation is unchanged; only the element LIFECYCLE differs — a same-type edge already
            //   at index `i` is REUSED and its shape MORPHED (updateProps) rather than rebuilt.
            let needCurve = (cp != nil)
            let edge: Path
            var isNewEdge = false
            if let existing = self._edgeEls[i], (existing is BezierCurve) == needCurve {
                edge = existing
                if let cp = cp {
                    updateProps(edge, ["shape": ["x1": p1.x, "y1": p1.y, "x2": p2.x, "y2": p2.y,
                                                 "cpx1": cp.x, "cpy1": cp.y]], seriesModel, i)
                } else {
                    updateProps(edge, ["shape": ["x1": p1.x, "y1": p1.y, "x2": p2.x, "y2": p2.y]], seriesModel, i)
                }
            }
            else {
                isNewEdge = true
                if let old = self._edgeEls[i] { _ = self._edgeGroup.remove(old) }
                let fresh: Path
                if let cp = cp {
                    // BezierCurve — quadratic (single control point cpx1/cpy1; cpx2/cpy2 unset).
                    var shape = BezierCurveShape()
                    shape.x1 = p1.x
                    shape.y1 = p1.y
                    shape.x2 = p2.x
                    shape.y2 = p2.y
                    shape.cpx1 = cp.x
                    shape.cpy1 = cp.y
                    var props: ElementProps = [:]
                    props["shape"] = shape as PathShape
                    fresh = BezierCurve(props)
                }
                else {
                    // Straight line.
                    var shape = LineShape()
                    shape.x1 = p1.x
                    shape.y1 = p1.y
                    shape.x2 = p2.x
                    shape.y2 = p2.y
                    var props: ElementProps = [:]
                    props["shape"] = shape as PathShape
                    fresh = Line(props)
                }
                _ = self._edgeGroup.add(fresh)
                self._edgeEls[i] = fresh
                edge = fresh
            }

            // Upstream LineDraw creates a new ECLine with `shape.percent = 0` and lets initProps draw
            // it to 1. Without this, graph nodes scale in while every edge is already fully visible in
            // the first frame. Both LineShape and BezierCurveShape expose percent to the animator.
            if isNewEdge {
                if var shape = edge.shape as? LineShape {
                    shape.percent = 0
                    _ = edge.setShape(shape)
                }
                else if var shape = edge.shape as? BezierCurveShape {
                    shape.percent = 0
                    _ = edge.setShape(shape)
                }
            }

            edge.name = "edge"
            edge.useStyle(edgeStyle)
            // upstream Line._updateCommonStl: `line.useStyle(lineStyle); line.style.fill = null;
            //   line.style.strokeNoScale = true;` — the fill is nulled DIRECTLY on the applied style
            //   (ECLinePath.getDefaultStyle also returns `fill: null`). `graphEdgeStyle` sets `fill = nil`,
            //   but `useStyle`→`createStyle`→`extendPathStyle` SKIPS nil, so DEFAULT_PATH_STYLE.fill
            //   ('#000') survives — filling every curved (BezierCurve) edge as a solid black lens (a
            //   straight Line has zero area so its stray fill is invisible). Re-null it here, like upstream.
            edge.pathStyle.fill = nil
            edge.pathStyle.strokeNoScale = true
            // Phase 45: edge emphasis (upstream chart/helper/Line.ts:336). The edge is a highDown dispatcher
            //   carrying its emphasis-state lineStyle, so a hover restyles it. `focus` is resolved to the
            //   adjacency set in the post-loop below (raw value stored here; overwritten there).
            let edgeEmphasis = edgeItemModel.getModel(["emphasis"])
            let edgeFocus: InnerFocus? = edgeEmphasis.get("focus")
            let edgeBlurScope = (edgeEmphasis.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let edgeDisabled = (edgeEmphasis.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(edge, edgeFocus, edgeBlurScope, edgeDisabled)
            states.setStatesStylesFromModel(edge, edgeItemModel, "lineStyle")
            // GraphView does not use ECLine, so reproduce ECLine's resolved endpoint-symbol creation,
            // styling and tangent placement for inline graph edges. Rebuild on render because the symbol
            // type/size/offset can change independently of the reusable line geometry.
            if let oldSymbols = self._edgeEndSymbolEls[i] {
                for old in oldSymbols { _ = self._edgeGroup.remove(old.path) }
            }
            let endSymbols = graphMakeEdgeEndSymbols(edgeData, i, edge.pathStyle.stroke, edge.pathStyle.opacity)
            for endSymbol in endSymbols {
                graphPlaceEdgeEndSymbol(
                    endSymbol, edge: edge, p1: p1, p2: p2, cp: cp,
                    percent: isNewEdge ? 0 : 1
                )
                _ = self._edgeGroup.add(endSymbol.path)
            }
            self._edgeEndSymbolEls[i] = endSymbols
            edgeData.setItemGraphicEl(i, edge)

            // Edge label (wave-1) — upstream chart/helper/Line.ts `_updateCommonStl` (setLabelStyle with
            //   the edge's label states models + defaultText = edge name) followed by `beforeUpdate`'s
            //   along-the-edge placement (midpoint + tangent rotation). The port draws each edge as a bare
            //   Line/BezierCurve, so the label is a free-standing sibling in `_mainGroup`. With the edge
            //   now REUSED across renders (`_mainGroup` no longer wiped), remove this edge's previous label
            //   before rebuilding it at the new endpoints, or labels would accumulate every render.
            if let oldLabel = self._edgeLabelEls[i] {
                _ = group.remove(oldLabel)
                self._edgeLabelEls[i] = nil
                self._edgeLabelDistanceY[i] = nil
            }
            if let built = graphAddEdgeLabel(
                group: group, edgeData: edgeData, idx: i,
                edgeItemModel: edgeItemModel, seriesModel: seriesModel,
                p1: p1, p2: p2, cp: cp, edgeStroke: edgeStyle.stroke,
                percent: isNewEdge ? 0 : 1
            ) {
                self._edgeLabelEls[i] = built.label
                // Cache the resolved `distance` Y offset so the force iteration can RE-PLACE the label
                //   along the moved edge without re-resolving its label models (see `_updateEdgeLayout`).
                self._edgeLabelDistanceY[i] = built.distanceY
            }
            if isNewEdge {
                // ECLine derives endpoint symbols and labels from the line's animated percent: the
                // arrow travels with the growing line and scales from zero, while the label sits
                // halfway along the revealed segment. Keep this bare-path port on that same clock.
                initProps(
                    edge,
                    ["shape": ["percent": 1.0] as [String: Any]],
                    seriesModel,
                    i,
                    nil,
                    { [weak self, weak edge] _ in
                        guard let self, let edge else { return }
                        let percent = graphEdgePercent(edge)
                        for endSymbol in self._edgeEndSymbolEls[i] ?? [] {
                            graphPlaceEdgeEndSymbol(
                                endSymbol, edge: edge, p1: p1, p2: p2, cp: cp,
                                percent: percent
                            )
                        }
                        if let label = self._edgeLabelEls[i] {
                            graphPlaceEdgeLabel(
                                label, p1: p1, p2: p2, cp: cp,
                                distanceY: self._edgeLabelDistanceY[i] ?? 5,
                                percent: percent
                            )
                        }
                    }
                )
            }
            seenEdgeIdx.insert(i)
        }

        // Drop edges (and their labels) whose datum no longer draws (leave).
        for (idx, old) in self._edgeEls where !seenEdgeIdx.contains(idx) {
            _ = self._edgeGroup.remove(old)
            self._edgeEls[idx] = nil
            if let oldSymbols = self._edgeEndSymbolEls.removeValue(forKey: idx) {
                for oldSymbol in oldSymbols { _ = self._edgeGroup.remove(oldSymbol.path) }
            }
            if let lbl = self._edgeLabelEls[idx] {
                _ = group.remove(lbl)
                self._edgeLabelEls[idx] = nil
                self._edgeLabelDistanceY[idx] = nil
            }
        }

        // upstream GraphView.ts:147-153 (runs here, right after symbolDraw.updateData + lineDraw.updateData):
        //   clearTimeout(this._layoutTimeout);
        //   const forceLayout = seriesModel.forceLayout;
        //   const layoutAnimation = seriesModel.get(['force', 'layoutAnimation']);
        //   if (forceLayout) { isForceLayout = true; this._startForceLayoutIteration(forceLayout, api, layoutAnimation); }
        // `seriesModel.forceLayout` is typed `Any?` (GraphSeries.swift:98) — downcast to the concrete
        //   instance chart/graph/forceLayout.swift stores there.
        self._layoutTimeout?.cancel()
        self._layoutTimeout = nil
        // Abandoning a pending iteration must also break its self-referencing closure (ARC; JS just
        //   drops the step function on the floor).
        self._forceStepBox?.step = nil
        self._forceStepBox = nil
        var isForceLayout = false
        if let forceLayout = seriesModel.forceLayout as? ForceLayoutInstance {
            isForceLayout = true
            // `layoutAnimation` is consumed for JS TRUTHINESS upstream (`layoutAnimation ? … : …`), so
            //   read it the same way GraphSeries.isAnimationEnabled reads this very option
            //   (`jsTruthy(get(['force','layoutAnimation']))`) — `as? Bool` would drop `layoutAnimation: 1`
            //   and make the two readers disagree (Int-vs-Double option-read trap, PORTING.md §8).
            let layoutAnimation = graphJsTruthy(seriesModel.get(["force", "layoutAnimation"]))
            self._startForceLayoutIteration(forceLayout, api, layoutAnimation)
        }

        // Phase 45: `emphasis.focus:'adjacency'` — after all node/edge elements exist, overwrite each
        //   dispatcher's `ecData.focus` with the ADJACENCY index set (nodes + their edges), so hovering a
        //   node/edge keeps its neighbourhood bright and blurs the rest (upstream GraphView.ts:204-225).
        //   The focus is stored as a `{node:[…], edge:[…]}` dict — the object form `states.blurSeries`
        //   consumes (its dataType keys resolve `getData(.node)` / `getData(.edge)`).
        let graph = seriesModel.getGraph()
        graph.eachNode({ node, _ in
            guard node.dataIndex >= 0, let el = node.getGraphicEl() else { return }
            let f = data.getItemModel(node.dataIndex).getModel(["emphasis"]).get("focus")
            if (f as? String) == "adjacency" {
                innerStore.getECData(el).focus = graphFocusDict(node.getAdjacentDataIndices())
            }
        })
        graph.eachEdge({ edge, _ in
            guard edge.dataIndex >= 0, let el = edge.getGraphicEl() else { return }
            let f = edgeData.getItemModel(edge.dataIndex).getModel(["emphasis"]).get("focus")
            if (f as? String) == "adjacency" {
                // Upstream uses the inline {edge:[self], node:[n1,n2]} (NOT getAdjacentDataIndices).
                innerStore.getECData(el).focus = [
                    "edge": [edge.dataIndex],
                    "node": [edge.node1.dataIndex, edge.node2.dataIndex]
                ] as [String: Any]
            }
        })

        // this._updateNodeAndLinkScale();  — PORT-NOTE (deferred): setSymbolScale (roam) deferred.
        // updateRoamControllerSimply(...);  — PORT-NOTE (deferred): roam not wired in GraphView (infra ported).
        // data.graph.eachNode(... draggable ...);  — PORT-NOTE (deferred): node drag requires states/actions.
        //   (The emphasis-focus part of this upstream loop IS wired — see the adjacency post-loop above.)
        // data.graph.eachEdge(... emphasis focus 'adjacency' ...);  — PORT-NOTE: adjacency focus IS wired above (see the eachEdge post-loop).

        // upstream GraphView.ts:227-233 — node label rotation. `rotateNodeLabel`
        //   (circularLayoutHelper.swift) sets each node symbol's text config rotation: in a `circular`
        //   layout with `circular.rotateLabel` it rotates the label to the radial tangent (position
        //   left/right per hemisphere); otherwise it applies the node's `label.rotate` (degrees → rad)
        //   for every layout. Runs after symbolDraw.updateData so the symbol paths exist.
        let circularRotateLabel = ((seriesModel.get("layout") as? String) == "circular")
            && ((seriesModel.get(["circular", "rotateLabel"]) as? Bool) ?? false)
        let cx = graphToNumber(data.getLayout("cx"))
        let cy = graphToNumber(data.getLayout("cy"))
        graph.eachNode({ node, _ in
            rotateNodeLabel(node, circularRotateLabel, cx, cy)
        })

        // upstream: `if (!isForceLayout) { this._renderThumbnail(seriesModel, api, this._symbolDraw, this._lineDraw); }`
        //   — the `isForceLayout` gate is restored (force layout renders its thumbnail from
        //   `_startForceLayoutIteration` instead), but the call itself is PORT-NOTE (deferred): the
        //   thumbnail requires component/helper/thumbnailBridge (not ported).
        // PORT-TODO: if (!isForceLayout) this._renderThumbnail(seriesModel, api, this._symbolDraw,
        //   this._lineDraw) — needs component/helper/thumbnailBridge.
        _ = isForceLayout

        // this._firstRender = false;  — PORT-NOTE (deferred): roam state deferred.
    }

    // upstream: dispose() { this.remove(); this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE: no RoamController is wired in GraphView, so there is nothing to dispose (roam DEFERRED).
        self.remove(ecModel, api)
    }

    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — PORT-NOTE (deferred): roam deferred.
    // upstream: _updateNodeAndLinkScale()  — PORT-NOTE (deferred): setSymbolScale (roam) deferred.

    // upstream:
    //   updateLayout(seriesModel: GraphSeriesModel) {
    //       if (!this._active) { return; }
    //       adjustEdge(seriesModel.getGraph(), getNodeGlobalScale(seriesModel));
    //       this._symbolDraw.updateLayout();
    //       this._lineDraw.updateLayout();
    //   }
    // Repositions the EXISTING node symbols / edge shapes against the (mutated) layouts, without
    //   re-running the visual + style pass — this is what each force-layout iteration calls per frame.
    //   `this._lineDraw.updateLayout()` → `_updateEdgeLayout` below, because this view inlines its edge
    //   geometry in `_edgeGroup` instead of driving the shared LineDraw (see the class PORT-NOTE).
    open func updateLayout(_ seriesModel: GraphSeriesModel) {
        // upstream: `if (!this._active) { return; }` — a step that lands after remove()/dispose() must
        //   NOT re-materialize symbols into the group remove() just emptied.
        guard self._active else {
            return
        }

        adjustEdge(seriesModel.getGraph(), graphHelper.getNodeGlobalScale(seriesModel))

        self._symbolDraw.updateLayout()
        self._updateEdgeLayout(seriesModel)
    }

    // `this._lineDraw.updateLayout()` stand-in: re-derive each live edge element's shape from the edge
    //   datum's (mutated) layout points. Geometry only — style/label/emphasis are untouched, matching
    //   LineDraw.updateLayout → Line.updateLayout, which only calls setLinePoints.
    //   The edge LABEL is re-placed too — upstream's Line re-runs its `beforeUpdate` along-the-edge
    //   placement every frame, so a moving edge drags its label with it (this port's label is a
    //   free-standing sibling, so the placement block is factored into `graphPlaceEdgeLabel`).
    private func _updateEdgeLayout(_ seriesModel: GraphSeriesModel) {
        let edgeData: SeriesData = seriesModel.getEdgeData()
        let viewCoord = seriesModel.coordinateSystem as? GraphViewCoordSys
        func fitPoint(_ p: GraphPoint) -> GraphPoint { self._fitPoint(p, viewCoord) }
        for (i, edge) in self._edgeEls {
            guard i < edgeData.count(), let pts = graphEdgePoints(edgeData.getItemLayout(i)) else { continue }
            let p1 = fitPoint(pts.0)
            let p2 = fitPoint(pts.1)
            if !p1.x.isFinite || !p1.y.isFinite || !p2.x.isFinite || !p2.y.isFinite { continue }
            // PORT-NOTE (deviation): upstream's `Line.updateLayout` → `setLinePoints` does NOT stop
            //   animators. Here the geometry is written directly, so an in-flight shape tween from the
            //   previous render's `updateProps` would fight the force iteration frame by frame; drop it
            //   first. (With force layout `isAnimationEnabled()` is false, so usually there is none.)
            _ = edge.stopAnimation()
            _ = edge.setShape("x1", p1.x)
            _ = edge.setShape("y1", p1.y)
            _ = edge.setShape("x2", p2.x)
            _ = edge.setShape("y2", p2.y)
            let cp = pts.2.map { fitPoint($0) }
            if edge is BezierCurve {
                // No control point in the new layout (curveness dropped to 0): collapse the curve onto
                //   the degenerate straight-line control point (the midpoint) rather than keeping the
                //   stale one from the previous layout.
                let c = cp ?? GraphPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                _ = edge.setShape("cpx1", c.x)
                _ = edge.setShape("cpy1", c.y)
            }
            edge.markRedraw()

            if let endSymbols = self._edgeEndSymbolEls[i] {
                for endSymbol in endSymbols {
                    graphPlaceEdgeEndSymbol(endSymbol, edge: edge, p1: p1, p2: p2, cp: cp)
                }
            }

            // Re-place this edge's label along the moved edge (upstream Line.beforeUpdate).
            if let label = self._edgeLabelEls[i] {
                graphPlaceEdgeLabel(
                    label, p1: p1, p2: p2, cp: cp,
                    distanceY: self._edgeLabelDistanceY[i] ?? 5.0
                )
            }
        }
    }

    // Shared graph-layout → pixel mapping: the node/edge layouts are in the graph's DATA space and the
    //   View coord maps them onto the pixel view rect (identity when there is no view coord). Used by
    //   both `render` and `_updateEdgeLayout` so the two cannot drift.
    fileprivate func _fitPoint(_ p: GraphPoint, _ viewCoord: GraphViewCoordSys?) -> GraphPoint {
        guard let vc = viewCoord else { return p }
        let m = vc.dataToPoint([p.x, p.y], nil)
        return GraphPoint(x: m[0], y: m[1])
    }

    // upstream: remove() {
    //     this._active = false;  clearTimeout(this._layoutTimeout);  this._layouting = false;
    //     this._layoutTimeout = null;
    //     this._symbolDraw && this._symbolDraw.remove();  this._lineDraw && this._lineDraw.remove();
    //     this._controller && this._controller.disable();
    // }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream: `clearTimeout(this._layoutTimeout); this._layouting = false; this._layoutTimeout = null;`
        //   — the pending force-layout step is cancelled so a removed view stops iterating.
        //   PORT-NOTE (deferred): RoamController.disable deferred.
        self._active = false
        self._layoutTimeout?.cancel()
        self._layouting = false
        self._layoutTimeout = nil
        // Break the abandoned step closure's self-reference (ARC).
        self._forceStepBox?.step = nil
        self._forceStepBox = nil
        //   upstream `this._symbolDraw.remove(); this._lineDraw.remove();` — CLEAR the sub-draws' contents
        //   but keep their groups attached to `_mainGroup` (init_ runs only once, so a later render must
        //   still find them wired). Do NOT `_mainGroup.removeAll()` (that would orphan them permanently).
        self._symbolDraw.remove()
        _ = self._edgeGroup.removeAll()
        self._edgeEls.removeAll()
        self._edgeEndSymbolEls.removeAll()
        // The edge labels are free-standing children of `_mainGroup` (not of `_edgeGroup`), so they must
        //   be detached explicitly or they survive the remove() as orphans.
        for (_, lbl) in self._edgeLabelEls { _ = self._mainGroup.remove(lbl) }
        self._edgeLabelEls.removeAll()
        self._edgeLabelDistanceY.removeAll()
    }

    // upstream: _getThumbnailInfo / _updateThumbnailWindow / _renderThumbnail
    //   -> PORT-NOTE (deferred): thumbnail requires component/helper/thumbnailBridge (not ported).
}

// export default GraphView;  -> `open class GraphView` above.

// MARK: - force layout iteration (upstream GraphView.ts:247-268)

extension GraphView {

    // upstream:
    //   private _startForceLayoutIteration(
    //       forceLayout: GraphSeriesModel['forceLayout'], api: ExtensionAPI, layoutAnimation?: boolean
    //   ) {
    //       const self = this;
    //       let firstRendered = false;
    //       (function step() {
    //           forceLayout.step(function (stopped) {
    //               self.updateLayout(self._model);
    //               if (stopped || !firstRendered) {
    //                   firstRendered = true;
    //                   self._renderThumbnail(self._model, api, self._symbolDraw, self._lineDraw);
    //               }
    //               (self._layouting = !stopped) && (
    //                   layoutAnimation
    //                       ? (self._layoutTimeout = setTimeout(step, 16) as any)
    //                       : step()
    //               );
    //           });
    //       })();
    //   }
    //
    // `forceLayout` is the concrete `ForceLayoutInstance` (forceHelper.swift) the layout stage stored on
    //   the series (`GraphSeriesModel.forceLayout`, typed `Any?`); the caller does the downcast.
    // The IIFE `function step()` recursion → a boxed self-referencing closure (`_GraphForceStepBox`),
    //   Swift's equivalent of a named function expression that an escaping callback re-enters.
    private func _startForceLayoutIteration(
        _ forceLayout: ForceLayoutInstance,
        _ api: ExtensionAPI,
        _ layoutAnimation: Bool?
    ) {
        // PORT SEAM (`setTimeout(step, 16)`): the animated branch needs a LIVE frame host to run the
        //   main-queue timer. In the headless still-frame harness there is no host and no run loop, so a
        //   scheduled step would never fire and the frame would show the un-settled FIRST iteration;
        //   there we must fall back to upstream's OWN non-animated branch (step() until the simulation
        //   reports stopped), which settles the graph exactly like `layoutAnimation: false` does. That
        //   replaces the 1500-iteration while-loop compensation that used to live in forceLayout.swift.
        //
        //   Detecting "no live host" CANNOT be a one-shot `api.getZr()` probe taken during render:
        //   `getZr()` resolves `root.__zr`, and the root is attached to a zr by `EChartsView._syncRoot`
        //   only AFTER `setOption` returns — i.e. AFTER this render (the same trap LinesView documents).
        //   A render-time probe is therefore false on the FIRST render even on a live host, which would
        //   make every single-setOption chart take the synchronous branch and never animate. So:
        //     * re-probe `getZr()` lazily at EACH step (it self-corrects once _syncRoot has run), and
        //     * before the host exists, fall back to the chart's global `animation` flag — the
        //       still-frame harness renders with `animation: false`, a live chart keeps the default on.
        //   Deviation: an explicit `animation: false` on a LIVE host settles the force layout
        //   synchronously in the first render instead of animating it (the settled result is the same).
        let animatedBranchAllowed: () -> Bool = { [weak self] in
            guard let self = self else { return false }
            if self._api?.getZr() != nil { return true }
            guard let raw = self._model?.ecModel?.getShallow("animation") else { return true }
            return graphJsTruthy(raw)
        }

        let box = _GraphForceStepBox()
        self._forceStepBox = box
        var firstRendered = false

        box.step = { [weak self, weak box] in
            guard let self = self else { return }
            // Upstream's non-animated branch is `step()` RE-ENTERED from inside the callback; ~510 steps
            //   of that would nest ~510 closure frames (each also running a full `updateLayout`), so the
            //   synchronous branch is driven ITERATIVELY here. The scheduled branch still re-enters via
            //   the work item, exactly like `setTimeout(step, 16)`.
            var again = true
            while again {
                again = false
                let animated = animatedBranchAllowed() && (layoutAnimation ?? false)
                forceLayout.step({ stopped in
                    // Reposition on every frame when something can observe it; in the still-frame
                    //   (synchronous settle) branch only the LAST frame is ever painted, so skip the
                    //   ~510 redundant full element repositions and place elements once, at the end.
                    if (stopped || animated), let model = self._model {
                        self.updateLayout(model)
                    }
                    if stopped || !firstRendered {
                        firstRendered = true
                        // self._renderThumbnail(self._model, api, self._symbolDraw, self._lineDraw)
                        //   PORT-NOTE (deferred): thumbnail requires component/helper/thumbnailBridge.
                    }
                    self._layouting = !stopped
                    if self._layouting {
                        if animated {
                            // this._layoutTimeout = setTimeout(step, 16)
                            let work = DispatchWorkItem { box?.step?() }
                            self._layoutTimeout = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
                        }
                        else {
                            again = true
                        }
                    }
                    else {
                        // The simulation is settled: drop the self-referencing closure (JS would just let
                        //   the step function become garbage; ARC needs the cycle broken explicitly).
                        box?.step = nil
                        self._forceStepBox = nil
                    }
                })
            }
        }

        box.step?()
    }
}

// Box holding the self-referencing `step` closure (upstream's named function expression `function step()`,
//   which the escaping `forceLayout.step` callback re-enters). Not an upstream symbol.
private final class _GraphForceStepBox {
    var step: (() -> Void)?
}

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// A node layout point. `node.setLayout([x, y])` stores the position as a 2-element numeric array; read
//   it back into a struct. Returns nil when there is no layout (upstream `getLayout() == null`).
private struct GraphPoint {
    var x: Double
    var y: Double
}

private func graphPointFromLayout(_ v: Any?) -> GraphPoint? {
    guard let arr = graphNumberArray(v), arr.count >= 2 else { return nil }
    return GraphPoint(x: arr[0], y: arr[1])
}

// Bridge the data-layer `GraphDataIndices` struct → the `{node:[…], edge:[…]}` dict form that
//   `states.blurSeries`'s object-focus branch consumes (its keys map to `getData(.node)`/`getData(.edge)`).
private func graphFocusDict(_ ix: GraphDataIndices) -> [String: Any] {
    return ["node": ix.node, "edge": ix.edge]
}

// `edge.setLayout(points)` stores `[[x1, y1], [x2, y2]]` (straight) or appends a third `[cpx, cpy]`
//   quadratic control point when curveness is non-zero. Returns (p1, p2, controlPoint?) or nil.
private func graphEdgePoints(_ v: Any?) -> (GraphPoint, GraphPoint, GraphPoint?)? {
    guard let outer = v as? [Any], outer.count >= 2 else { return nil }
    guard let a = graphNumberArray(outer[0]), a.count >= 2,
          let b = graphNumberArray(outer[1]), b.count >= 2 else { return nil }
    let p1 = GraphPoint(x: a[0], y: a[1])
    let p2 = GraphPoint(x: b[0], y: b[1])
    var cp: GraphPoint? = nil
    if outer.count >= 3, let c = graphNumberArray(outer[2]), c.count >= 2 {
        cp = GraphPoint(x: c[0], y: c[1])
    }
    return (p1, p2, cp)
}

// Coerce a dynamic `[x, y]`-ish array (stored as `[Double]`, `[Any]`, or `[NSNumber]`) to `[Double]`.
private func graphNumberArray(_ v: Any?) -> [Double]? {
    if let d = v as? [Double] { return d }
    if let arr = v as? [Any] { return arr.map { graphToNumber($0) } }
    return nil
}

// Inline counterpart of chart/helper/ECLine's endpoint symbol support. GraphView owns bare
// Line/BezierCurve paths rather than ECLine groups, but consumes the same item-visual keys written by
// graph/edgeVisual.swift and follows the same endpoint tangent-rotation convention.
private struct _GraphEdgeEndSymbol {
    let path: Path
    let isFrom: Bool
    let specifiedRotation: Double?
}

private func graphMakeEdgeEndSymbols(
    _ edgeData: SeriesData,
    _ idx: Int,
    _ edgeColor: ZRenderKit.ZRColor?,
    _ edgeOpacity: Double?
) -> [_GraphEdgeEndSymbol] {
    var result: [_GraphEdgeEndSymbol] = []
    for (category, isFrom) in [("fromSymbol", true), ("toSymbol", false)] {
        guard let symbolType = edgeData.getItemVisual(idx, category) as? String,
              symbolType != "none" else { continue }

        let size = symbol.normalizeSymbolSize(edgeData.getItemVisual(idx, category + "Size") ?? 0)
        let offset = symbol.normalizeSymbolOffset(
            edgeData.getItemVisual(idx, category + "Offset") ?? 0,
            [size.0, size.1]
        ) ?? (0, 0)
        let keepAspect = edgeData.getItemVisual(idx, category + "KeepAspect") as? Bool
        guard let path = symbol.createSymbol(
            symbolType,
            -size.0 / 2 + offset.0,
            -size.1 / 2 + offset.1,
            size.0,
            size.1,
            nil,
            keepAspect
        ) as? Path else { continue }

        path.name = isFrom ? "from" : "to"
        if let edgeColor {
            if let ecSymbol = path as? ECSymbol {
                ecSymbol.setColor(edgeColor, nil)
            } else {
                path.pathStyle.fill = edgeColor
                path.pathStyle.stroke = edgeColor
            }
        }
        path.pathStyle.opacity = edgeOpacity

        var specifiedRotation: Double?
        let rawRotation = edgeData.getItemVisual(idx, category + "Rotate")
        let degrees = graphToNumber(rawRotation)
        if degrees.isFinite { specifiedRotation = degrees * Double.pi / 180 }
        result.append(_GraphEdgeEndSymbol(path: path, isFrom: isFrom, specifiedRotation: specifiedRotation))
    }
    return result
}

private func graphPlaceEdgeEndSymbol(
    _ endSymbol: _GraphEdgeEndSymbol,
    edge: Path,
    p1: GraphPoint,
    p2: GraphPoint,
    cp: GraphPoint?,
    percent: Double = 1
) {
    let t = Swift.max(0, Swift.min(percent, 1))
    let endpoint = endSymbol.isFrom ? p1 : graphEdgePoint(p1, p2, cp, t)
    let tangent = graphEdgeTangent(p1, p2, cp, endSymbol.isFrom ? 0 : t)

    endSymbol.path.setPosition([endpoint.x, endpoint.y])
    endSymbol.path.rotation = endSymbol.specifiedRotation
        ?? ((endSymbol.isFrom ? Double.pi / 2 : -Double.pi / 2) - atan2(tangent.y, tangent.x))
    endSymbol.path.scaleX = t
    endSymbol.path.scaleY = t
    endSymbol.path.z2 = edge.z2 + 1
    endSymbol.path.markRedraw()
}

private func graphEdgePercent(_ edge: Path) -> Double {
    if let shape = edge.shape as? LineShape { return shape.percent }
    if let shape = edge.shape as? BezierCurveShape { return shape.percent }
    return 1
}

private func graphEdgePoint(
    _ p1: GraphPoint, _ p2: GraphPoint, _ cp: GraphPoint?, _ t: Double
) -> GraphPoint {
    guard let cp else {
        return GraphPoint(x: p1.x + (p2.x - p1.x) * t, y: p1.y + (p2.y - p1.y) * t)
    }
    let oneMinusT = 1 - t
    return GraphPoint(
        x: oneMinusT * oneMinusT * p1.x + 2 * oneMinusT * t * cp.x + t * t * p2.x,
        y: oneMinusT * oneMinusT * p1.y + 2 * oneMinusT * t * cp.y + t * t * p2.y
    )
}

private func graphEdgeTangent(
    _ p1: GraphPoint, _ p2: GraphPoint, _ cp: GraphPoint?, _ t: Double
) -> GraphPoint {
    var tangent: GraphPoint
    if let cp {
        tangent = GraphPoint(
            x: 2 * ((1 - t) * (cp.x - p1.x) + t * (p2.x - cp.x)),
            y: 2 * ((1 - t) * (cp.y - p1.y) + t * (p2.y - cp.y))
        )
    }
    else {
        tangent = GraphPoint(x: p2.x - p1.x, y: p2.y - p1.y)
    }
    if abs(tangent.x) + abs(tangent.y) < 1e-12 {
        return GraphPoint(x: p2.x - p1.x, y: p2.y - p1.y)
    }
    return tangent
}

// `zrUtil.defaults({ strokeNoScale: true, fill: null }, lineStyle)` → a PathStyleProps built from the
//   lineStyle bag (stroke / lineWidth / opacity / …) with fill cleared and strokeNoScale set. Reuses the
//   shared visual-style → PathStyleProps bridge (barStyleFromDict), then applies the two defaults —
//   the same construction TreeView uses for its link style.
private func graphEdgeStyle(_ lineStyle: [String: Any]) -> PathStyleProps {
    var s = barStyleFromDict(lineStyle)
    s.fill = nil            // fill: null
    s.strokeNoScale = true  // strokeNoScale: true
    return s
}

// The palette color lands under the item/series visual style as an EChartsKit `ZRColor.color(String)`,
//   a raw `String`, or a gradient dict; edge strokes now bridge via the shared `zrPaintFromStyleValue`
//   (BarView.swift), so no local `String`-only color helper is needed here.

// `store.get(...)`-style numeric coercion for a dynamic layout value.
private func graphToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}

// ---- Edge label (upstream chart/helper/Line.ts) -----------------------------------------------------
//
// Reproduces upstream's edge-label behaviour for the STATIC render:
//   1. `_updateCommonStl`: build the edge's label states models and call `setLabelStyle` with
//      defaultText = the edge name (`edgeData.getName(idx)`, e.g. "0 > 1") and inheritColor = the edge
//      stroke colour — exactly the `setLabelStyle(this, labelStatesModels, { defaultText, inheritColor,
//      ... })` call. The edge label config lives under `edgeLabel` (not `label`): upstream swaps the
//      parent lookup via `resolveParentPath` ('label' → 'edgeLabel'). That redirect IS LIVE in this port —
//      `GraphEdgeLabelItemModel` / `GraphEdgeLabelChildModel` in GraphSeries.swift wrap the edge item model
//      returned by `getItemModel`, so `edgeItemModel.getModel('label')` resolves its parent to
//      `seriesModel.getModel(['edgeLabel'])` automatically (and `[state,'label']` to `[state,'edgeLabel']`),
//      exactly as upstream Line.ts relies on. No explicit parent argument is passed here.
//   2. `beforeUpdate`: place the label along the edge. For the default `position: 'middle'` the label
//      sits at the curve midpoint, rotated to the edge tangent (which at the midpoint of both a straight
//      line and a quadratic curve is simply `normalize(p2 - p1)`), lifted `distance` px above the line
//      (verticalAlign 'bottom', align 'center'). start/end/inside* positions collapse to the middle
//      placement (none of the ported graph demos use them; noted as a deviation).
private func graphAddEdgeLabel(
    group: Group,
    edgeData: SeriesData,
    idx: Int,
    edgeItemModel: Model,
    seriesModel: GraphSeriesModel,
    p1: GraphPoint,
    p2: GraphPoint,
    cp: GraphPoint?,
    edgeStroke: ZRenderKit.ZRColor?,
    percent: Double = 1
) -> (label: ZRText, distanceY: Double)? {
    // upstream Line.ts:252 — `labelStatesModels = getLabelStatesModels(itemModel)`. The default
    //   labelName "label" is correct: the parent resolves through the live 'label' → 'edgeLabel'
    //   redirect installed on the edge item model by GraphSeries.swift, so no explicit parent is passed.
    let labelStatesModels = labelStyle.getLabelStatesModels(edgeItemModel)

    guard let normalModel = labelStatesModels[.normal] else { return nil }

    // The edge stroke colour is the label's inheritColor (upstream `visualColor`).
    var inheritColor: ColorString? = nil
    if case let .string(s)? = edgeStroke { inheritColor = s }

    var labelOpt = SetLabelStyleOpt()
    // upstream Line.ts:
    //   labelFetcher: { getFormattedLabel(dataIndex, stateName) {
    //       return seriesModel.getFormattedLabel(dataIndex, stateName, lineData.dataType);
    //   } }
    // The forced `dataType` is what keeps the fetcher on the EDGE data (a bare model fetcher would
    //   format the NODE at this index). Without it an `edgeLabel.formatter` was ignored entirely.
    //   Captures the MODEL only (no view) — see the LabelFetcherFn lifetime warning.
    let edgeDataType = edgeData.dataType
    labelOpt.labelFetcher = LabelFetcherFn { dataIndex, status, _, labelDimIndex, formatter, extendParams in
        return seriesModel.getFormattedLabel(
            dataIndex, status, edgeDataType, labelDimIndex, formatter, extendParams
        )
    }
    // defaultText = edge name matches upstream's `defaultText: rawVal == null ? lineData.getName(idx)
    //   : …` (graph edges carry no value dim).
    labelOpt.defaultText = edgeData.getName(idx)
    labelOpt.labelDataIndex = Double(idx)
    labelOpt.inheritColor = inheritColor

    let label = ZRText()
    labelStyle.setLabelStyle(label, labelStatesModels, labelOpt)

    // setLabelStyle sets `ignore = true` when no state has `show: true` (i.e. no visible label).
    if label.ignore { return nil }

    // distance → [distanceX, distanceY]; only distanceY (dy) is used for 'middle'.
    var distanceY = 5.0
    if let arr = normalModel.get("distance") as? [Any], arr.count >= 2 {
        distanceY = graphToNumber(arr[1])
    }
    else if let d = normalModel.get("distance") as? Double {
        distanceY = d
    }

    // Use the user-specified align/verticalAlign first, else the computed 'center'/'bottom'.
    if label.textStyle.align == nil { label.textStyle.align = .center }
    if label.textStyle.verticalAlign == nil { label.textStyle.verticalAlign = .bottom }

    // beforeUpdate placement (factored out — the force-layout iteration re-runs it every frame).
    graphPlaceEdgeLabel(
        label, p1: p1, p2: p2, cp: cp, distanceY: distanceY,
        percent: percent
    )

    _ = group.add(label)
    return (label, distanceY)
}

// upstream chart/helper/Line.ts `beforeUpdate`: place the label along the edge. Split out of
//   `graphAddEdgeLabel` so `GraphView._updateEdgeLayout` (the `LineDraw.updateLayout` stand-in the force
//   iteration drives) can re-place the label on the moved edge every frame, like upstream does.
private func graphPlaceEdgeLabel(
    _ label: ZRText,
    p1: GraphPoint,
    p2: GraphPoint,
    cp: GraphPoint?,
    distanceY: Double,
    percent: Double = 1
) {
    let t = Swift.max(0, Swift.min(percent, 1)) / 2
    let mid = graphEdgePoint(p1, p2, cp, t)
    let tangent = graphEdgeTangent(p1, p2, cp, t)
    let dx = tangent.x
    let dy0 = tangent.y

    // rotation = -atan2(tangent.y, tangent.x); flip by π when the edge points right→left so the text
    //   never renders upside down (upstream `if (toPos[0] < fromPos[0]) rotation = Math.PI + rotation`).
    var rotation = -atan2(dy0, dx)
    let toPos = graphEdgePoint(p1, p2, cp, Swift.max(0, Swift.min(percent, 1)))
    if toPos.x < p1.x { rotation = Double.pi + rotation }

    // 'middle': dy = -distanceY, verticalAlign 'bottom', align 'center'; origin at (0, -dy).
    let dy = -distanceY
    label.x = mid.x
    label.y = mid.y + dy
    label.rotation = rotation
    label.originX = 0
    label.originY = -dy
    label.dirty()
}

// JS truthiness for a dynamic option read — the file-private idiom used across this port (see
//   GraphSeries.swift / forceLayout.swift), needed because `as? Bool` silently drops `1`/`"x"`.
private func graphJsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let i = v as? Int { return i != 0 }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
