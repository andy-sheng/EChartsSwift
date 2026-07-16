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
//   import LineDraw from '../helper/LineDraw';                     -> PORT-NOTE (deferred): requires chart/helper/LineDraw (not ported).
//       Each edge is drawn inline with a ZRenderKit `Line` (straight) or `BezierCurve` (curveness),
//       exactly how TreeView draws its parent->child links; LineDraw's diff + `ECLinePath` + fromSymbol/
//       toSymbol arrow markers + effect/label are DEFERRED.
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
//   import Line from '../helper/Line';                             -> PORT-NOTE (deferred): requires chart/helper/Line (not ported; inline Line/BezierCurve shape used instead).
//   import { getECData } from '../../util/innerStore';             -> getECData (util/innerStore.swift).
//   import { simpleLayoutEdge } from './simpleLayoutHelper';       -> sibling simpleLayoutHelper.swift (used by drag; DEFERRED).
//   import { circularLayout, rotateNodeLabel } from './circularLayoutHelper';  -> sibling circularLayoutHelper.swift.
//   import { clone, extend } from 'zrender/src/core/util';         -> ZRenderKit.util (only used by thumbnail; DEFERRED).
//   import ECLinePath from '../helper/LinePath';                   -> PORT-NOTE (deferred): requires chart/helper/LinePath / ECLinePath (not ported).
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
    // PORT-NOTE (deferred): private _layoutTimeout / _layouting — forceLayout iteration (deferred, see render).

    // upstream: private _model: GraphSeriesModel;  private _api: ExtensionAPI;
    private var _model: GraphSeriesModel?
    private var _api: ExtensionAPI?

    // upstream: private _mainGroup: graphic.Group;
    private let _mainGroup = Group()

    // upstream: init(ecModel, api) {
    //     const symbolDraw = new SymbolDraw();  const lineDraw = new LineDraw();
    //     const group = this.group;  const mainGroup = new graphic.Group();
    //     this._controller = new RoamController(api.getZr());
    //     mainGroup.add(symbolDraw.group);  mainGroup.add(lineDraw.group);  group.add(mainGroup);
    //     this._symbolDraw = symbolDraw;  this._lineDraw = lineDraw;  this._mainGroup = mainGroup;
    //     this._firstRender = true;
    // }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): RoamController + the SymbolDraw/LineDraw sub-groups + _firstRender deferred.
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
        //   (per-edge Line diff). Both diffs + SymbolClz/ECLinePath reuse + draggable/emphasis-focus
        //   handlers + node/link scale + circular label rotation + thumbnail + forceLayout iteration are
        //   DEFERRED (see PORT-NOTEs), so `_mainGroup` is rebuilt from scratch each render: one symbol
        //   per node, then one Line/BezierCurve per edge. Both loops read the layout positions the layout
        //   stage already stored on the two SeriesData stores (exactly what SymbolDraw / LineDraw consume).
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // clearTimeout(this._layoutTimeout);  const forceLayout = seriesModel.forceLayout; ...
        //   PORT-NOTE (deferred): forceLayout (iterative physics) + layoutAnimation iteration deferred this phase
        //   (forceLayout.swift / forceHelper.swift are ported, but the animated iteration is not driven here). Only circularLayout + simpleLayout are shipped, and
        //   both write final node/edge layouts before render, so no iteration is needed here.

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
        func fitPoint(_ p: GraphPoint) -> GraphPoint {
            guard let vc = viewCoord else { return p }
            let m = vc.dataToPoint([p.x, p.y], nil)
            return GraphPoint(x: m[0], y: m[1])
        }

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
        let symbolDraw = SymbolDraw()
        var nodeOpt = SymbolDrawUpdateOpt()
        nodeOpt.getSymbolPoint = { i in
            guard let raw = graphPointFromLayout(data.getItemLayout(i)) else { return nil }
            let p = fitPoint(raw)
            return (p.x.isFinite && p.y.isFinite) ? [p.x, p.y] : nil
        }
        symbolDraw.updateData(data, nodeOpt)
        _ = group.add(symbolDraw.group)

        // --- Edges: lineDraw.updateData(edgeData) ------------------------------------------------
        //   LineDraw iterates `edgeData`, reading `edgeData.getItemLayout(i)` — the point list the layout
        //   stage stored via edge.setLayout: `[[x1, y1], [x2, y2]]`, or `[[x1, y1], [x2, y2], [cpx, cpy]]`
        //   with a quadratic control point when `curveness` is non-zero (simpleLayoutEdge). The presence
        //   of the third point selects a BezierCurve over a straight Line — the same branch Line.ts uses.
        let seriesEdgeStyle = edgeData.getVisual("style") as? [String: Any]

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

            let edge: Path
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
                edge = BezierCurve(props)
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
                edge = Line(props)
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
            // fromSymbol / toSymbol arrow markers (ECLinePath.setLinePoints + Symbol) — PORT-NOTE (deferred): requires chart/helper/LinePath (ECLinePath).
            _ = group.add(edge)
            edgeData.setItemGraphicEl(i, edge)

            // Edge label — upstream chart/helper/Line.ts `_updateCommonStl` (setLabelStyle with the
            //   edge's label states models + defaultText = edge name) followed by `beforeUpdate`'s
            //   along-the-edge placement (midpoint + tangent rotation). Rebuilt inline here because the
            //   port draws each edge as a bare Line/BezierCurve rather than the upstream `Line` Group
            //   (which carries the label as its textContent and repositions it every frame in
            //   beforeUpdate). The static render computes the final label transform directly.
            graphAddEdgeLabel(
                group: group, edgeData: edgeData, idx: i,
                edgeItemModel: edgeItemModel, seriesModel: seriesModel,
                p1: p1, p2: p2, cp: cp, edgeStroke: edgeStyle.stroke
            )
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
        // rotateNodeLabel(node, circularRotateLabel, cx, cy);  — PORT-NOTE (deferred): node label rotation deferred.
        // this._renderThumbnail(...);  — PORT-NOTE (deferred): thumbnail deferred.

        // this._firstRender = false;  — PORT-NOTE (deferred): roam state deferred.
    }

    // upstream: dispose() { this.remove(); this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE: no RoamController is wired in GraphView, so there is nothing to dispose (roam DEFERRED).
        self.remove(ecModel, api)
    }

    // upstream: _startForceLayoutIteration(...)  — PORT-NOTE (deferred): forceLayout iteration deferred this phase.
    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — PORT-NOTE (deferred): roam deferred.
    // upstream: _updateNodeAndLinkScale()  — PORT-NOTE (deferred): setSymbolScale (roam) deferred.
    // upstream: updateLayout(seriesModel)  — PORT-NOTE (deferred): requires SymbolDraw/LineDraw.updateLayout (LineDraw not ported); adjustEdge itself is ported.

    // upstream: remove() {
    //     this._active = false;  clearTimeout(this._layoutTimeout);  this._layouting = false;
    //     this._layoutTimeout = null;
    //     this._symbolDraw && this._symbolDraw.remove();  this._lineDraw && this._lineDraw.remove();
    //     this._controller && this._controller.disable();
    // }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): _layoutTimeout / _layouting (forceLayout) + RoamController.disable deferred.
        _ = self._mainGroup.removeAll()
    }

    // upstream: _getThumbnailInfo / _updateThumbnailWindow / _renderThumbnail
    //   -> PORT-NOTE (deferred): thumbnail requires component/helper/thumbnailBridge (not ported).
}

// export default GraphView;  -> `open class GraphView` above.

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
//      parent lookup via `resolveParentPath` ('label' → 'edgeLabel'). That JS-prototype method swap is a
//      stub in this port (see GraphSeries PORT-NOTE), so it is reproduced here by passing the series
//      `edgeLabel` model as the explicit parent to `edgeItemModel.getModel('label', edgeLabelParent)`.
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
    edgeStroke: ZRenderKit.ZRColor?
) {
    // Build the edge label states models. Own option = the link's `label`; parent = the series
    //   `edgeLabel` model (the 'label' → 'edgeLabel' parent redirect, done explicitly here).
    var labelStatesModels: LabelStatesModels = [:]
    labelStatesModels[.normal] = edgeItemModel.getModel("label", seriesModel.getModel("edgeLabel"))
    for stateName in states.SPECIAL_STATES {
        guard let st = DisplayState(rawValue: stateName) else { continue }
        labelStatesModels[st] = edgeItemModel.getModel(
            [stateName, "label"], seriesModel.getModel([stateName, "edgeLabel"])
        )
    }

    guard let normalModel = labelStatesModels[.normal] else { return }

    // The edge stroke colour is the label's inheritColor (upstream `visualColor`).
    var inheritColor: ColorString? = nil
    if case let .string(s)? = edgeStroke { inheritColor = s }

    var labelOpt = SetLabelStyleOpt()
    // No labelFetcher: the edge's default label IS its name; a node-indexed fetcher would format the
    //   NODE at this index with the wrong dataType. defaultText = edge name matches upstream's
    //   `defaultText: rawVal == null ? lineData.getName(idx) : …` (graph edges carry no value dim).
    labelOpt.defaultText = edgeData.getName(idx)
    labelOpt.labelDataIndex = Double(idx)
    labelOpt.inheritColor = inheritColor

    let label = ZRText()
    labelStyle.setLabelStyle(label, labelStatesModels, labelOpt)

    // setLabelStyle sets `ignore = true` when no state has `show: true` (i.e. no visible label).
    if label.ignore { return }

    // beforeUpdate placement. midpoint + tangent from the already-fitted endpoints / control point.
    let mid: GraphPoint
    if let cp = cp {
        // quadraticAt(t=0.5): 0.25·p1 + 0.5·cp + 0.25·p2
        mid = GraphPoint(x: 0.25 * p1.x + 0.5 * cp.x + 0.25 * p2.x,
                         y: 0.25 * p1.y + 0.5 * cp.y + 0.25 * p2.y)
    }
    else {
        mid = GraphPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
    }
    // tangent at the midpoint == normalize(p2 - p1) for both a line and a quadratic curve.
    let dx = p2.x - p1.x
    let dy0 = p2.y - p1.y

    // distance → [distanceX, distanceY]; only distanceY (dy) is used for 'middle'.
    var distanceY = 5.0
    if let arr = normalModel.get("distance") as? [Any], arr.count >= 2 {
        distanceY = graphToNumber(arr[1])
    }
    else if let d = normalModel.get("distance") as? Double {
        distanceY = d
    }

    // rotation = -atan2(tangent.y, tangent.x); flip by π when the edge points right→left so the text
    //   never renders upside down (upstream `if (toPos[0] < fromPos[0]) rotation = Math.PI + rotation`).
    var rotation = -atan2(dy0, dx)
    if p2.x < p1.x { rotation = Double.pi + rotation }

    // 'middle': dy = -distanceY, verticalAlign 'bottom', align 'center'; origin at (0, -dy).
    let dy = -distanceY
    label.x = mid.x
    label.y = mid.y + dy
    label.rotation = rotation
    label.originX = 0
    label.originY = -dy

    // Use the user-specified align/verticalAlign first, else the computed 'center'/'bottom'.
    if label.textStyle.align == nil { label.textStyle.align = .center }
    if label.textStyle.verticalAlign == nil { label.textStyle.verticalAlign = .bottom }
    label.dirty()

    _ = group.add(label)
}
