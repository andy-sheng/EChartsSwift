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
//   import SymbolDraw from '../helper/SymbolDraw';                 -> PORT-TODO: helper/SymbolDraw NOT ported.
//       The node symbol is built inline with `symbol.createSymbol` (same deviation as ScatterView /
//       TreeView); SymbolDraw's enter/update/leave diff + `SymbolClz` reuse are DEFERRED.
//   import LineDraw from '../helper/LineDraw';                     -> PORT-TODO: helper/LineDraw NOT ported.
//       Each edge is drawn inline with a ZRenderKit `Line` (straight) or `BezierCurve` (curveness),
//       exactly how TreeView draws its parent->child links; LineDraw's diff + `ECLinePath` + fromSymbol/
//       toSymbol arrow markers + effect/label are DEFERRED.
//   import RoamController from '../../component/helper/RoamController';   -> PORT-TODO: roam NOT ported.
//   import { isRoamPayloadHasZoom, updateRoamControllerSimply } from '../../component/helper/roamHelper';
//       -> PORT-TODO: roamHelper NOT ported (roam DEFERRED).
//   import * as graphic from '../../util/graphic';                 -> `Group` / `Line` / `BezierCurve` (ZRenderKit).
//       PORT-TODO: graphic.updateProps/removeElement (animation) NOT ported — the static render sets
//       final geometry directly (same deviation as FunnelView/PieView/SunburstView/TreeView).
//   import adjustEdge from './adjustEdge';                         -> PORT-TODO: adjustEdge NOT ported.
//       adjustEdge trims each edge's endpoints back to the node symbol boundary (so an arrow head does
//       not sit under the node). It mutates the edge layout points in place and depends on
//       getNodeGlobalScale (roam). DEFERRED: edges are drawn node-center to node-center.
//   import {getNodeGlobalScale} from './graphHelper';             -> PORT-TODO: graphHelper NOT ported.
//       getNodeGlobalScale = calcCompensationScaleToPreserveNodeSize (coord/View, roam) — DEFERRED (== 1).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import GraphSeriesModel, { GraphNodeItemOption, GraphEdgeItemOption, SERIES_TYPE_GRAPH } from './GraphSeries';
//       -> sibling GraphSeries.swift (assumed ported alongside data/Graph.swift).
//   import View, { applyViewCoordSysTransToElement, getOwnRoamViewCoordSys,
//            VIEW_COORD_SYS_TRANS_OVERALL, viewCoordSysCopyOverallMatrix } from '../../coord/View';
//       -> PORT-TODO: coord/View NOT ported (roam / view coord-system transform DEFERRED).
//   import Symbol from '../helper/Symbol';                         -> PORT-TODO: helper/Symbol NOT ported.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import Line from '../helper/Line';                             -> PORT-TODO: helper/Line NOT ported (inline shape instead).
//   import { getECData } from '../../util/innerStore';             -> PORT-TODO: innerStore NOT ported (focus/ECData DEFERRED).
//   import { simpleLayoutEdge } from './simpleLayoutHelper';       -> sibling simpleLayoutHelper.swift (used by drag; DEFERRED).
//   import { circularLayout, rotateNodeLabel } from './circularLayoutHelper';  -> sibling circularLayoutHelper.swift.
//   import { clone, extend } from 'zrender/src/core/util';         -> ZRenderKit.util (only used by thumbnail; DEFERRED).
//   import ECLinePath from '../helper/LinePath';                   -> PORT-TODO: helper/LinePath NOT ported.
//   import { NullUndefined, RoamHostView, RoamPayload } from '../../util/types';  -> util/types.swift (type-only).
//   import { getThumbnailBridge, ThumbnailBridge } from '../../component/helper/thumbnailBridge';
//       -> PORT-TODO: thumbnailBridge NOT ported (thumbnail DEFERRED).
//   import { ListForSymbolDraw } from '../helper/baseDraw';        -> PORT-TODO: helper/baseDraw NOT ported.

// upstream: class GraphView extends ChartView implements RoamHostView
//   PORT-TODO: RoamHostView (`__updateOnOwnRoam`) NOT implemented — roam DEFERRED per CONVENTIONS §5.
open class GraphView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_GRAPH;  /  readonly type = SERIES_TYPE_GRAPH;
    public static let graphType = SERIES_TYPE_GRAPH
    open override var type: String {
        get { SERIES_TYPE_GRAPH }
        set { /* readonly upstream */ }
    }

    // upstream: private _symbolDraw: SymbolDraw;  private _lineDraw: LineDraw;
    //   PORT-TODO: SymbolDraw / LineDraw NOT ported. The static render adds node symbols + edges to
    //   `_mainGroup` directly (rebuilt each pass), so the two sub-draw groups collapse into one.

    // PORT-TODO: private _controller: RoamController;  — roam NOT ported (DEFERRED).
    // PORT-TODO: private _firstRender / _active — only used by roam + thumbnail (DEFERRED).
    // PORT-TODO: private _layoutTimeout / _layouting — forceLayout iteration (DEFERRED, see render).

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
        // PORT-TODO: RoamController + the SymbolDraw/LineDraw sub-groups + _firstRender DEFERRED.
        _ = self.group.add(self._mainGroup)
    }

    // upstream: render(seriesModel: GraphSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: GraphSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! GraphSeriesModel

        // const ownCoordSys = getOwnRoamViewCoordSys(seriesModel);
        //   PORT-TODO: getOwnRoamViewCoordSys / applyViewCoordSysTransToElement / roam controller /
        //   thumbnail — the whole view-coord-system transform + roam block is DEFERRED (coord/View not
        //   ported). The node/edge layout positions are already in the series' local pixel space (set by
        //   circularLayout / simpleLayout), so the static render places `_mainGroup` at the origin.

        self._model = seriesModel
        self._api = api

        let group = self._mainGroup

        // adjustEdge(seriesModel.getGraph(), getNodeGlobalScale(seriesModel));
        //   PORT-TODO: adjustEdge (endpoint trim to node boundary) + getNodeGlobalScale (roam) DEFERRED.

        let data: SeriesData = seriesModel.getData()
        // const edgeData = seriesModel.getEdgeData();
        let edgeData: SeriesData = seriesModel.getEdgeData()

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream delegates to `symbolDraw.updateData(data)` (per-node symbol
        //   enter/update/leave diff, reusing SymbolClz instances) and `lineDraw.updateData(edgeData)`
        //   (per-edge Line diff). Both diffs + SymbolClz/ECLinePath reuse + draggable/emphasis-focus
        //   handlers + node/link scale + circular label rotation + thumbnail + forceLayout iteration are
        //   DEFERRED (see PORT-TODOs), so `_mainGroup` is rebuilt from scratch each render: one symbol
        //   per node, then one Line/BezierCurve per edge. Both loops read the layout positions the layout
        //   stage already stored on the two SeriesData stores (exactly what SymbolDraw / LineDraw consume).
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // clearTimeout(this._layoutTimeout);  const forceLayout = seriesModel.forceLayout; ...
        //   PORT-TODO: forceLayout (iterative physics) + layoutAnimation iteration DEFERRED this phase
        //   (forceLayout / forceHelper not ported). Only circularLayout + simpleLayout are shipped, and
        //   both write final node/edge layouts before render, so no iteration is needed here.

        // --- Nodes: symbolDraw.updateData(data) --------------------------------------------------
        //   SymbolDraw iterates `data`, reading `data.getItemLayout(i)` (the `[x, y]` the layout stage
        //   stored via node.setLayout) and the item visual `symbol` / `symbolSize` / `style.fill`.
        let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "circle"
        let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 10.0
        // Series-level style fallback (visual/style writes the palette color into the series visual
        //   `style` bag; item-level visuals override it when present).
        let seriesNodeStyle = data.getVisual("style") as? [String: Any]

        for i in 0..<data.count() {
            // const layout = data.getItemLayout(i);  → `[x, y]` (node.setLayout([x, y])).
            guard let pos = graphPointFromLayout(data.getItemLayout(i)) else { continue }
            if !pos.x.isFinite || !pos.y.isFinite { continue }

            let symbolType = (data.getItemVisual(i, "symbol") as? String)
                ?? (data.getItemModel(i).get("symbol") as? String)
                ?? seriesSymbol
            // The per-node `symbolSize` is authored on the data item; the symbol visual stage does not
            //   populate it for graph nodes, so fall back to the item model (matches getSymbolSize, which
            //   adjustEdge already relies on) before the series default.
            let (sizeW, sizeH) = symbol.normalizeSymbolSize(
                data.getItemVisual(i, "symbolSize")
                    ?? data.getItemModel(i).get("symbolSize")
                    ?? seriesSymbolSize
            )

            // Resolve fill: item visual style first, then the series visual style.
            let itemStyle = (data.getItemVisual(i, "style") as? [String: Any]) ?? seriesNodeStyle
            var fill: ZRenderKit.ZRColor? = nil
            if let cs = graphColorString(itemStyle?["fill"]) { fill = .string(cs) }

            // createSymbol places the symbol centered on the point (`x - size/2`, `y - size/2`).
            //   PORT-TODO: symbolRotate / symbolOffset / symbolKeepAspect / emphasis scale + the node
            //   name label (SymbolClz useNameLabel) not applied (SymbolDraw states DEFERRED).
            let el = symbol.createSymbol(
                symbolType, pos.x - sizeW / 2, pos.y - sizeH / 2, sizeW, sizeH, fill
            )
            if let path = el as? Path {
                path.name = "node"

                // upstream (SymbolDraw → chart/helper/Symbol._updateCommon, Symbol.ts:357): each node
                //   symbol is marked a highDown dispatcher carrying its emphasis-state itemStyle, so a
                //   hover restyles it. Mirror ScatterView.render's block.
                //   PORT-TODO: `focus === 'adjacency'` (getAdjacentDataIndices) — the adjacency focus that
                //   also blurs non-neighbour nodes/edges — is DEFERRED (raw focus passed through).
                let itemModel = data.getItemModel(i)
                let emphasisModel = itemModel.getModel(["emphasis"])
                let focus: InnerFocus? = emphasisModel.get("focus")
                let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
                let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
                states.toggleHoverEmphasis(path, focus, blurScope, isDisabled)
                states.setStatesStylesFromModel(path, itemModel)

                // Node name label (SymbolClz `useNameLabel`, DEFERRED). Minimal NORMAL-state label,
                //   gated on label.show (graph default is false). Graph node labels default to 'inside'
                //   the symbol with a contrasting (white) fill; rendered via the textContent painter walk.
                let labelModel = itemModel.getModel("label")
                if (labelModel.get("show") as? Bool) == true {
                    let nm = data.getName(i)
                    if !nm.isEmpty {
                        let position = (labelModel.get("position") as? String) ?? "inside"
                        var ts = TextStyleProps()
                        ts.text = nm
                        ts.font = labelModel.getFont()
                        // Inside labels sit centered on the (dark) symbol with a contrasting white fill
                        //   (echarts' inheritColor auto-contrast); outside labels use the label color.
                        if position == "inside" {
                            ts.fill = (labelModel.getShallow("color") as? String) ?? "#fff"
                            ts.align = .center
                            ts.verticalAlign = .middle
                        } else {
                            ts.fill = labelModel.getTextColor()
                        }
                        let labelText = ZRText()
                        labelText.useStyle(ts)
                        path.setTextContent(labelText)
                        var tc = ElementTextConfig()
                        tc.position = position
                        if position != "inside" { tc.distance = (labelModel.get("distance") as? Double) ?? 5 }
                        path.setTextConfig(tc)
                    }
                }

                _ = group.add(path)
                data.setItemGraphicEl(i, path)
            }
        }

        // --- Edges: lineDraw.updateData(edgeData) ------------------------------------------------
        //   LineDraw iterates `edgeData`, reading `edgeData.getItemLayout(i)` — the point list the layout
        //   stage stored via edge.setLayout: `[[x1, y1], [x2, y2]]`, or `[[x1, y1], [x2, y2], [cpx, cpy]]`
        //   with a quadratic control point when `curveness` is non-zero (simpleLayoutEdge). The presence
        //   of the third point selects a BezierCurve over a straight Line — the same branch Line.ts uses.
        let seriesEdgeStyle = edgeData.getVisual("style") as? [String: Any]

        for i in 0..<edgeData.count() {
            guard let pts = graphEdgePoints(edgeData.getItemLayout(i)) else { continue }
            let p1 = pts.0
            let p2 = pts.1
            if !p1.x.isFinite || !p1.y.isFinite || !p2.x.isFinite || !p2.y.isFinite { continue }

            // const lineStyle = edgeItemModel.getModel('lineStyle').getLineStyle();
            let edgeItemModel = edgeData.getItemModel(i)
            let lineStyle = edgeItemModel.getModel("lineStyle").getLineStyle()

            // Edge stroke: item visual style first (the graph visual stage writes the edge color into
            //   `stroke`), then the series edge visual style, then whatever lineStyle carries.
            let edgeItemStyle = (edgeData.getItemVisual(i, "style") as? [String: Any]) ?? seriesEdgeStyle
            var edgeStyle = graphEdgeStyle(lineStyle)
            if let cs = graphColorString(edgeItemStyle?["stroke"]) { edgeStyle.stroke = .string(cs) }

            let edge: Path
            if let cp = pts.2 {
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
            // Phase 45: edge emphasis (upstream chart/helper/Line.ts:336). The edge is a highDown dispatcher
            //   carrying its emphasis-state lineStyle, so a hover restyles it. `focus` is resolved to the
            //   adjacency set in the post-loop below (raw value stored here; overwritten there).
            let edgeEmphasis = edgeItemModel.getModel(["emphasis"])
            let edgeFocus: InnerFocus? = edgeEmphasis.get("focus")
            let edgeBlurScope = (edgeEmphasis.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let edgeDisabled = (edgeEmphasis.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(edge, edgeFocus, edgeBlurScope, edgeDisabled)
            states.setStatesStylesFromModel(edge, edgeItemModel, "lineStyle")
            // fromSymbol / toSymbol arrow markers (ECLinePath.setLinePoints + Symbol) — PORT-TODO: DEFERRED.
            _ = group.add(edge)
            edgeData.setItemGraphicEl(i, edge)
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

        // this._updateNodeAndLinkScale();  — PORT-TODO: setSymbolScale (roam) DEFERRED.
        // updateRoamControllerSimply(...);  — PORT-TODO: roam DEFERRED.
        // data.graph.eachNode(... draggable / emphasis focus ...);  — PORT-TODO: DEFERRED (states/actions).
        // data.graph.eachEdge(... emphasis focus 'adjacency' ...);  — PORT-TODO: DEFERRED.
        // rotateNodeLabel(node, circularRotateLabel, cx, cy);  — PORT-TODO: node label rotation DEFERRED.
        // this._renderThumbnail(...);  — PORT-TODO: thumbnail DEFERRED.

        // this._firstRender = false;  — PORT-TODO: roam state DEFERRED.
    }

    // upstream: dispose() { this.remove(); this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: RoamController.dispose DEFERRED (roam not ported).
        self.remove(ecModel, api)
    }

    // upstream: _startForceLayoutIteration(...)  — PORT-TODO: forceLayout iteration DEFERRED this phase.
    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — PORT-TODO: roam DEFERRED.
    // upstream: _updateNodeAndLinkScale()  — PORT-TODO: setSymbolScale (roam) DEFERRED.
    // upstream: updateLayout(seriesModel)  — PORT-TODO: adjustEdge + SymbolDraw/LineDraw.updateLayout DEFERRED.

    // upstream: remove() {
    //     this._active = false;  clearTimeout(this._layoutTimeout);  this._layouting = false;
    //     this._layoutTimeout = null;
    //     this._symbolDraw && this._symbolDraw.remove();  this._lineDraw && this._lineDraw.remove();
    //     this._controller && this._controller.disable();
    // }
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: _layoutTimeout / _layouting (forceLayout) + RoamController.disable DEFERRED.
        _ = self._mainGroup.removeAll()
    }

    // upstream: _getThumbnailInfo / _updateThumbnailWindow / _renderThumbnail
    //   -> PORT-TODO: thumbnail (thumbnailBridge + coord/View) DEFERRED.
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

// The palette color lands under the item/series visual style as an EChartsKit `ZRColor.color(String)`
//   or a raw `String`. Bridge both to a solid color string (same bridge as ScatterView / TreeView).
//   Gradient / pattern out of scope.
private func graphColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// `store.get(...)`-style numeric coercion for a dynamic layout value.
private func graphToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return Double.nan
}
