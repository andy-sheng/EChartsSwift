// Ported (STATIC SUBSET) from echarts/src/chart/sankey/SankeyView.ts — keep in sync with upstream.
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
//   import * as graphic from '../../util/graphic';
//       -> `Group` / `Rect` / `LinearGradient` (ZRenderKit) + the local no-animation shims. PORT-TODO:
//          `util/graphic` (initProps) NOT ported; the grow-in clip animation is DEFERRED (see render).
//   import { enterEmphasis, leaveEmphasis, toggleHoverEmphasis, setStatesStylesFromModel } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported (states/emphasis prerequisite). All emphasis / focus-adjacency
//          / hover-blur handling is DEFERRED (same deviation as GraphView / FunnelView).
//   import { LayoutOrient, ECElement, RoamHostView, RoamPayload } from '../../util/types';
//       -> util/types.swift (type-only). `LayoutOrient` ('horizontal' | 'vertical') is a `String` here.
//   import type { PathProps, PathStyleProps } from 'zrender/src/graphic/Path';  -> ZRenderKit `PathProps` / `PathStyleProps`.
//   import SankeySeriesModel, { SankeyEdgeItemOption, SankeyNodeItemOption, SERIES_TYPE_SANKEY } from './SankeySeries';
//       -> sibling SankeySeries.swift (assumed ported alongside — provides `SankeySeriesModel` /
//          `SERIES_TYPE_SANKEY` / `layoutInfo` / `getGraph`).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import { RectLike } from 'zrender/src/core/BoundingRect';      -> `RectLike` (used only by the deferred clip).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> PORT-TODO: label/labelStyle NOT ported. A minimal plain-text reproduction is inlined in
//          `sankeySetLabel` below (same deviation as FunnelView).
//   import { getECData } from '../../util/innerStore';             -> PORT-TODO: innerStore NOT ported (ECData DEFERRED).
//   import { isString, retrieve3 } from 'zrender/src/core/util';   -> `util.isString` (retrieve3 only used by the deferred label formatter).
//   import type { GraphEdge } from '../../data/Graph';             -> data/Graph.swift `GraphEdge`.
//   import RoamController from '../../component/helper/RoamController';   -> PORT-TODO: roam NOT ported (DEFERRED).
//   import { applyViewCoordSysTransToElement, VIEW_COORD_SYS_TRANS_OVERALL } from '../../coord/View';
//       -> PORT-TODO: coord/View NOT ported (roam / view coord-system transform DEFERRED).
//   import { createIsInSelfByPointerCheckerEl, createViewCoordSysSimply, updateRoamControllerSimply }
//       from '../../component/helper/roamHelper';   -> PORT-TODO: roamHelper NOT ported (roam DEFERRED).

// ================================================================================================
// upstream: class SankeyPathShape { x1..y2, cpx1..cpy2, extent, orient }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker (CONVENTIONS §4;
//   see PointerShape / NormalBoxPathShape). `orient` is upstream's `LayoutOrient` string.
// ================================================================================================
public struct SankeyPathShape: PathShape {
    public var x1: Double = 0
    public var y1: Double = 0

    public var x2: Double = 0
    public var y2: Double = 0

    public var cpx1: Double = 0
    public var cpy1: Double = 0

    public var cpx2: Double = 0
    public var cpy2: Double = 0

    public var extent: Double = 0
    // upstream: orient: LayoutOrient;  ('horizontal' | 'vertical') — declared but not defaulted upstream.
    public var orient: String = ""

    public init() {}

    // Keyed access for animateTo({shape: {...}}). Exposes the animatable numeric fields (the two cubic
    //   endpoints + control points + extent). `orient` is a mode flag, not tweened.
    // PORT-TODO: upstream animates the ribbon via these fields; the enter/update transition itself is
    //   DEFERRED (static render), but the keyed seam is provided for parity with sibling shapes.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "x1": return x1
        case "y1": return y1
        case "x2": return x2
        case "y2": return y2
        case "cpx1": return cpx1
        case "cpy1": return cpy1
        case "cpx2": return cpx2
        case "cpy2": return cpy2
        case "extent": return extent
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x1": x1 = v
        case "y1": y1 = v
        case "x2": x2 = v
        case "y2": y2 = v
        case "cpx1": cpx1 = v
        case "cpy1": cpy1 = v
        case "cpx2": cpx2 = v
        case "cpy2": cpy2 = v
        case "extent": extent = v
        default: break
        }
    }
}

// upstream: interface SankeyPathProps extends PathProps { shape?: Partial<SankeyPathShape> }
// PORT-TODO: typed-interface fidelity dropped — PathProps is the dynamic `[String: Any]` prop bag
//   (== DisplayableProps); the `shape?` field is set via the `"shape"` key (see Path._init).
public typealias SankeyPathProps = PathProps

// upstream: class SankeyPath extends graphic.Path<SankeyPathProps>
//   The edge RIBBON: a FILLED closed path tracing the top edge (cubic bezier), across by `extent`, then
//   the bottom edge (cubic bezier) back, and closed. `extent` == the edge value (band thickness).
public final class SankeyPath: Path {

    // upstream: shape: SankeyPathShape — narrows the inherited `shape: PathShape!`.

    // upstream: constructor(opts?: SankeyPathProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
    }

    // upstream: getDefaultShape() { return new SankeyPathShape(); }
    public override func getDefaultShape() -> PathShape {
        return SankeyPathShape()
    }

    // upstream: buildPath(ctx: CanvasRenderingContext2D, shape: SankeyPathShape)
    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! SankeyPathShape
        let extent = shape.extent
        _ = ctx.moveTo(shape.x1, shape.y1)
        _ = ctx.bezierCurveTo(
            shape.cpx1, shape.cpy1,
            shape.cpx2, shape.cpy2,
            shape.x2, shape.y2
        )
        if shape.orient == "vertical" {
            _ = ctx.lineTo(shape.x2 + extent, shape.y2)
            _ = ctx.bezierCurveTo(
                shape.cpx2 + extent, shape.cpy2,
                shape.cpx1 + extent, shape.cpy1,
                shape.x1 + extent, shape.y1
            )
        }
        else {
            _ = ctx.lineTo(shape.x2, shape.y2 + extent)
            _ = ctx.bezierCurveTo(
                shape.cpx2, shape.cpy2 + extent,
                shape.cpx1, shape.cpy1 + extent,
                shape.x1, shape.y1 + extent
            )
        }
        _ = ctx.closePath()
    }

    // upstream: highlight() { enterEmphasis(this); }  /  downplay() { leaveEmphasis(this); }
    //   PORT-TODO: util/states (enterEmphasis/leaveEmphasis) NOT ported — DEFERRED.
}

// ================================================================================================
// upstream: class SankeyView extends ChartView implements RoamHostView
//   PORT-TODO: RoamHostView (`__updateOnOwnRoam`) NOT implemented — roam DEFERRED per CONVENTIONS §5.
// ================================================================================================
open class SankeyView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_SANKEY;  /  readonly type = SERIES_TYPE_SANKEY;
    public static let sankeyType = SERIES_TYPE_SANKEY
    open override var type: String {
        get { SERIES_TYPE_SANKEY }
        set { /* readonly upstream */ }
    }

    // upstream: private _mainGroup = new graphic.Group();
    private let _mainGroup = Group()

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?

    // PORT-TODO: private _controller: RoamController;  — roam NOT ported (DEFERRED).
    // upstream: private _firstRender: boolean;
    private var _firstRender: Bool = true

    // View REUSE (L5 fidelity): PERSIST the node rects (keyed by node dataIndex) and link ribbons (keyed
    //   by edge dataIndex) across renders — the `_mainGroup` is no longer `removeAll()`-ed every pass —
    //   so a merge-mode setOption value change (same node+edge count, same orient; the sankey layout only
    //   re-placed the node boxes / re-sized the ribbon bands) MORPHS each shape in place instead of
    //   rebuild-and-snap. `_prevNodeCount`/`_prevEdgeCount`/`_prevOrient` gate morph-vs-rebuild.
    private var _nodeEls: [Int: Rect] = [:]
    private var _linkEls: [Int: SankeyPath] = [:]
    private var _prevNodeCount: Int = -1
    private var _prevEdgeCount: Int = -1
    private var _prevOrient: String = ""

    // upstream: init(ecModel: GlobalModel, api: ExtensionAPI): void {
    //     this._controller = new RoamController(api.getZr());
    //     this.group.add(this._mainGroup);
    //     this._firstRender = true;
    // }
    open override func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: RoamController DEFERRED (roam not ported).
        _ = self.group.add(self._mainGroup)
        self._firstRender = true
    }

    // upstream: render(seriesModel: SankeySeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: SankeySeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! SankeySeriesModel

        // const graph = seriesModel.getGraph();
        let graph = seriesModel.getGraph()
        let mainGroup = self._mainGroup
        // const layoutInfo = seriesModel.layoutInfo;
        //   PORT-TODO: `layoutInfo` is `LayoutRect?` in the sibling port (upstream is non-null, set by
        //   sankeyLayout); guard and bail if absent (no geometry to draw).
        guard let layoutInfo = seriesModel.layoutInfo else { return }
        // view width / height
        let width = layoutInfo.width
        let height = layoutInfo.height
        let nodeData = seriesModel.getData()
        // const edgeData = seriesModel.getData('edge');
        let edgeData = seriesModel.getData(.edge)
        // const orient = seriesModel.get('orient');
        let orient: String = (seriesModel.get("orient", false) as? String) ?? "horizontal"

        // Morph iff we already drew the same number of nodes + edges in the same orient (only the layout
        //   geometry changed). A node/edge add/remove or an orient flip (or a first render) rebuilds fresh
        //   with the per-node entrance fade; a same-count/same-orient change morphs each rect + ribbon via
        //   `updateProps`. dragNode re-renders through this same path — moving one node is a same-count
        //   geometry change, so it morphs too.
        let nodeCount = nodeData.count()
        let edgeCount = edgeData.count()
        let canMorph = !_nodeEls.isEmpty && _prevNodeCount == nodeCount
            && _prevEdgeCount == edgeCount && _prevOrient == orient
        if !canMorph {
            _ = mainGroup.removeAll()
            _nodeEls.removeAll()
            _linkEls.removeAll()
        }

        // L3 Roam: capture the base (roam-free) placement; the roam transform is applied on top of it at
        //   the END of render (viewGroupRoamApplyStateToGroup). Identity roam state → mainGroup.x = baseX.
        let baseX = layoutInfo.x
        let baseY = layoutInfo.y
        mainGroup.x = baseX
        mainGroup.y = baseY

        // this._updateViewCoordSys(seriesModel, api);
        //   PORT-TODO: the upstream `View` VIEW_COORD_SYS placement (createViewCoordSysSimply +
        //   applyViewCoordSysTransToElement) is DEFERRED (coord/View not ported). The node/edge layout
        //   positions are already in the series' local pixel space (set by sankeyLayout), and `_mainGroup`
        //   is placed at `layoutInfo.x/y` above; the roam pan/zoom is applied to the group as a TRANSFORM
        //   at the end of render (see viewGroupRoamApplyStateToGroup / roamHelperViewGroup.swift).

        // updateRoamControllerSimply(seriesModel, api, this._controller, ...);  — the controller is wired
        //   live by EChartsView._setupSankeyRoam (the SankeyView is zr-less); the roam STATE it
        //   accumulates is re-applied to the group below.

        // generate a bezier curve (ribbon) for each edge
        graph.eachEdge({ edge, _ in
            // const ecData = getECData(curve); ecData.dataIndex/seriesIndex/dataType = ...
            //   PORT-TODO: innerStore (getECData) NOT ported — ECData tagging DEFERRED.
            guard let edgeModel = edge.getModel() else { return }
            let lineStyleModel = edgeModel.getModel("lineStyle")
            // const curvature = lineStyleModel.get('curveness');
            let curvature = sankeyNum(lineStyleModel.get("curveness")) ?? 0
            let n1Layout = sankeyLayoutDict(edge.node1.getLayout())
            guard let node1Model = edge.node1.getModel() else { return }
            // const dragX1 = node1Model.get('localX'); const dragY1 = node1Model.get('localY');
            let dragX1 = sankeyNum(node1Model.get("localX"))
            let dragY1 = sankeyNum(node1Model.get("localY"))
            let n2Layout = sankeyLayoutDict(edge.node2.getLayout())
            guard let node2Model = edge.node2.getModel() else { return }
            let dragX2 = sankeyNum(node2Model.get("localX"))
            let dragY2 = sankeyNum(node2Model.get("localY"))
            let edgeLayout = sankeyLayoutDict(edge.getLayout())

            // node layout fields {x, y, dx, dy}; edge layout fields {sy, ty, dy}.
            let n1x = sankeyNum(n1Layout["x"]) ?? 0
            let n1y = sankeyNum(n1Layout["y"]) ?? 0
            let n1dx = sankeyNum(n1Layout["dx"]) ?? 0
            let n1dy = sankeyNum(n1Layout["dy"]) ?? 0
            let n2x = sankeyNum(n2Layout["x"]) ?? 0
            let n2y = sankeyNum(n2Layout["y"]) ?? 0
            let edgeSy = sankeyNum(edgeLayout["sy"]) ?? 0
            let edgeTy = sankeyNum(edgeLayout["ty"]) ?? 0
            let edgeDy = sankeyNum(edgeLayout["dy"]) ?? 0

            let x1: Double
            let y1: Double
            let x2: Double
            let y2: Double
            let cpx1: Double
            let cpy1: Double
            let cpx2: Double
            let cpy2: Double

            var shape = SankeyPathShape()
            // curve.shape.extent = Math.max(1, edgeLayout.dy);
            shape.extent = Swift.max(1, edgeDy)
            // curve.shape.orient = orient;
            shape.orient = orient

            if orient == "vertical" {
                x1 = (dragX1 != nil ? dragX1! * width : n1x) + edgeSy
                y1 = (dragY1 != nil ? dragY1! * height : n1y) + n1dy
                x2 = (dragX2 != nil ? dragX2! * width : n2x) + edgeTy
                y2 = dragY2 != nil ? dragY2! * height : n2y
                cpx1 = x1
                cpy1 = y1 * (1 - curvature) + y2 * curvature
                cpx2 = x2
                cpy2 = y1 * curvature + y2 * (1 - curvature)
            }
            else {
                x1 = (dragX1 != nil ? dragX1! * width : n1x) + n1dx
                y1 = (dragY1 != nil ? dragY1! * height : n1y) + edgeSy
                x2 = dragX2 != nil ? dragX2! * width : n2x
                y2 = (dragY2 != nil ? dragY2! * height : n2y) + edgeTy
                cpx1 = x1 * (1 - curvature) + x2 * curvature
                cpy1 = y1
                cpx2 = x1 * curvature + x2 * (1 - curvature)
                cpy2 = y2
            }

            // curve.setShape({ x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2 });
            shape.x1 = x1
            shape.y1 = y1
            shape.x2 = x2
            shape.y2 = y2
            shape.cpx1 = cpx1
            shape.cpy1 = cpy1
            shape.cpx2 = cpx2
            shape.cpy2 = cpy2

            // Reuse the persisted ribbon (same count/orient) → MORPH its shape; else build fresh.
            let reuseCurve = canMorph ? self._linkEls[edge.dataIndex] : nil
            let curve: SankeyPath
            if let c = reuseCurve {
                curve = c
                // Animate the two cubic endpoints + control points + band `extent` to the new layout.
                //   SankeyPathShape.animationGet/Set expose exactly these numeric keys; `orient` is a mode
                //   flag (part of the morph gate, so unchanged) and need not be tweened. Targets are bare
                //   Doubles (not a VectorArray/[[Double]]), matching animationGet's scalar returns.
                updateProps(curve, ["shape": [
                    "x1": x1, "y1": y1, "x2": x2, "y2": y2,
                    "cpx1": cpx1, "cpy1": cpy1, "cpx2": cpx2, "cpy2": cpy2,
                    "extent": Swift.max(1, edgeDy)
                ]], seriesModel)
            } else {
                curve = SankeyPath()
                // curve.setShape({ x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2 });
                _ = curve.setShape(shape)
            }

            // curve.useStyle(lineStyleModel.getItemStyle());
            //   getItemStyle maps the lineStyle `color` option → `fill`; for sankey edges that option is a
            //   SENTINEL ('source' | 'target' | 'gradient'), resolved to a real paint by applyCurveStyle.
            curve.useStyle(sankeyStyleFromDict(lineStyleModel.getItemStyle()))
            // Special color, use source node color or target node color
            applyCurveStyle(curve, orient, edge)

            // Edge label — PLAIN-TEXT subset. Upstream:
            //   const defaultEdgeLabelText = `${edgeModel.get('value')}`;
            //   setLabelStyle(curve, getLabelStatesModels(edgeModel, 'edgeLabel'), { labelFetcher..., defaultText });
            //   curve.setTextConfig({ position: 'inside' });
            // PORT-TODO: label/labelStyle + getFormattedLabel (labelFetcher) + label states DEFERRED; the
            //   normal-state edgeLabel text/font/fill is reproduced by `sankeySetLabel`, forced 'inside'.
            let defaultEdgeLabelText = sankeyStringify(edgeModel.get("value"))
            sankeySetLabel(curve, edgeModel.getModel("edgeLabel"), defaultEdgeLabelText, "inside")

            // Phase 45: edge emphasis + topology focus (upstream SankeyView.ts:158-161 + 265-273). The curve
            //   is a highDown dispatcher carrying its emphasis-state lineStyle; `focus:'adjacency'`/
            //   `'trajectory'` resolve to the edge's index set (its own edge + the two endpoint nodes, or the
            //   whole up/downstream trajectory) so a hover keeps that subgraph bright and blurs the rest.
            //   The `ecData.dataType = 'edge'` tag is REQUIRED so `blurSeries`'s object-focus branch resolves
            //   this element against `getData(.edge)`.
            let edgeEmphasis = edgeModel.getModel(["emphasis"])
            let edgeFocusRaw: InnerFocus? = edgeEmphasis.get("focus")
            let edgeFocus: InnerFocus? = sankeyResolveEdgeFocus(edgeFocusRaw, edge)
            let edgeBlurScope = (edgeEmphasis.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let edgeDisabled = (edgeEmphasis.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(curve, edgeFocus, edgeBlurScope, edgeDisabled)
            states.setStatesStylesFromModel(curve, edgeModel, "lineStyle")

            if reuseCurve == nil {
                _ = mainGroup.add(curve)
                self._linkEls[edge.dataIndex] = curve
            }
            edgeData.setItemGraphicEl(edge.dataIndex, curve)
            let ecEdge = innerStore.getECData(curve)
            ecEdge.dataType = .edge
            ecEdge.dataIndex = Double(edge.dataIndex)
        })

        // Generate a rect for each node
        graph.eachNode({ node, _ in
            let layout = sankeyLayoutDict(node.getLayout())
            guard let itemModel = node.getModel() else { return }
            // const dragX = itemModel.get('localX'); const dragY = itemModel.get('localY');
            let dragX = sankeyNum(itemModel.get("localX"))
            let dragY = sankeyNum(itemModel.get("localY"))
            // const emphasisModel = itemModel.getModel('emphasis');  — PORT-TODO: states DEFERRED.
            // const borderRadius = itemModel.get(['itemStyle', 'borderRadius']) as number | number[] || 0;
            let borderRadius = sankeyBorderRadius(itemModel.get(["itemStyle", "borderRadius"]))

            let lx = sankeyNum(layout["x"]) ?? 0
            let ly = sankeyNum(layout["y"]) ?? 0
            let ldx = sankeyNum(layout["dx"]) ?? 0
            let ldy = sankeyNum(layout["dy"]) ?? 0

            // const rect = new graphic.Rect({ shape: { x, y, width: dx, height: dy, r: borderRadius },
            //     style: itemModel.getModel('itemStyle').getItemStyle(), z2: 10 });
            var rectShape = RectShape()
            let rx = dragX != nil ? dragX! * width : lx
            let ry = dragY != nil ? dragY! * height : ly
            rectShape.x = rx
            rectShape.y = ry
            rectShape.width = ldx
            rectShape.height = ldy
            rectShape.r = borderRadius

            // Reuse the persisted node rect (same count/orient) → MORPH its box; else build fresh.
            let reuseRect = canMorph ? self._nodeEls[node.dataIndex] : nil
            let rect: Rect
            if let r = reuseRect {
                rect = r
                // Animate the rect box to its new layout. RectShape.animationGet/Set cover x/y/width/height;
                //   the corner radius `r` is a mode value (left as-is on reuse — not tweened).
                updateProps(rect, ["shape": [
                    "x": rx, "y": ry, "width": ldx, "height": ldy
                ]], seriesModel, node.dataIndex)
            } else {
                rect = Rect([
                    "shape": rectShape as PathShape,
                    "z2": Double(10)
                ])
            }
            rect.useStyle(sankeyStyleFromDict(itemModel.getModel("itemStyle").getItemStyle()))

            // Node label — retrofitted onto the SHARED label core (label/labelStyle.swift). Upstream:
            //   setLabelStyle(rect, getLabelStatesModels(itemModel), {
            //     labelFetcher: { getFormattedLabel(dataIndex, stateName) {
            //       return seriesModel.getFormattedLabel(dataIndex, stateName, 'node'); } },
            //     labelDataIndex: node.dataIndex, defaultText: node.id });
            //   (rect as ECElement).disableLabelAnimation = true;
            // `setLabelStyle` ATTACHES the label as the rect's textContent (setTextContent + textConfig
            //   position — sankey node default 'right') across normal/emphasis/blur/select states, so the
            //   old inline `sankeySetLabel` node call is removed and the shared core owns the label.
            // PORT-NOTE: the shared `SetLabelStyleOpt.labelFetcher` (a `DataFormatMixin`) calls
            //   `getFormattedLabel` with `dataType == nil`; upstream passes 'node'. For the default node
            //   label (no formatter) this is inert — `getFormattedLabel` returns nil and the core falls
            //   back to `defaultText` (node.id) — so the resolved text is identical. `inheritColor` is the
            //   node fill so a color:'inherit' label tracks the node paint.
            let nodeLabelModels = labelStyle.getLabelStatesModels(itemModel)
            var nodeLabelOpt = SetLabelStyleOpt()
            nodeLabelOpt.labelFetcher = seriesModel
            nodeLabelOpt.labelDataIndex = Double(node.dataIndex)
            nodeLabelOpt.defaultText = node.id
            nodeLabelOpt.inheritColor = sankeyColorString(node.getVisual("color"))
            labelStyle.setLabelStyle(rect, nodeLabelModels, nodeLabelOpt)
            // PORT-TODO: `(rect as ECElement).disableLabelAnimation = true` — ECElement label-animation
            //   opt-out not bridged (label value animation is DEFERRED in labelStyle.swift anyway).

            // rect.setStyle('fill', node.getVisual('color'));
            if let fill = sankeyColor(node.getVisual("color")) {
                rect.pathStyle.fill = fill
            }

            // ENTRANCE ANIMATION — opacity fade-in (FunnelView pattern). Upstream reveals the whole
            //   diagram via a first-render grow-in clip (createGridClipShape + initProps), which is
            //   DEFERRED here (clip-path animation not ported per CONVENTIONS §5). As the closest
            //   available-infra faithful stand-in, fade each node Rect from invisible to its final
            //   opacity: capture the final opacity BEFORE zeroing, set the construction-time opacity to
            //   0, then animate (or, with animation off, instantly `attr` via Path.attrKV's partial
            //   "style"-dict merge) toward the final opacity via `initProps`.
            //   Only on a FRESH build — a morph reuse keeps the node at its final opacity (no re-fade).
            if reuseRect == nil {
                let finalNodeOpacity = rect.pathStyle.opacity ?? 1
                rect.pathStyle.opacity = 0
                initProps(rect, ["style": ["opacity": finalNodeOpacity] as [String: Any]], seriesModel, node.dataIndex)
            }
            // rect.setStyle('decal', node.getVisual('style').decal);
            //   PORT-TODO: node decal (Pattern) not bridged (decal out of the static-render scope).

            // upstream (SankeyView.ts:315): setStatesStylesFromModel(rect, itemModel); + (323-332)
            //   toggleHoverEmphasis. The node rect is marked a highDown dispatcher carrying its
            //   emphasis-state itemStyle, so a hover restyles it. Mirror ScatterView.render's block.
            //   PORT-TODO: `focus === 'adjacency'|'trajectory'` (getAdjacentDataIndices /
            //   getTrajectoryDataIndices) — the graph-topology focus that also blurs unrelated
            //   nodes/edges — is DEFERRED (raw focus passed through).
            let emphasisModel = itemModel.getModel(["emphasis"])
            let focusRaw: InnerFocus? = emphasisModel.get("focus")
            let focus: InnerFocus? = sankeyResolveNodeFocus(focusRaw, node)   // Phase 45: adjacency/trajectory
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(rect, focus, blurScope, isDisabled)
            states.setStatesStylesFromModel(rect, itemModel)

            rect.name = "node"
            if reuseRect == nil {
                _ = mainGroup.add(rect)
                self._nodeEls[node.dataIndex] = rect
            }

            nodeData.setItemGraphicEl(node.dataIndex, rect)
            let ecNode = innerStore.getECData(rect)     // Phase 45: dataType tag → blurSeries getData(.node)
            ecNode.dataType = .node
            ecNode.dataIndex = Double(node.dataIndex)
        })

        // Node dragging. upstream:
        //   nodeData.eachItemGraphicEl(function (el: graphic.Rect, dataIndex) {
        //     const itemModel = nodeData.getItemModel(dataIndex);
        //     if (itemModel.get('draggable')) {
        //       el.drift = function (dx, dy) {
        //         this.shape.x += dx; this.shape.y += dy; this.dirty();
        //         api.dispatchAction({ type: 'dragNode', seriesId: seriesModel.id,
        //           dataIndex: nodeData.getRawIndex(dataIndex),
        //           localX: this.shape.x / width, localY: this.shape.y / height });
        //       };
        //       el.draggable = true; el.cursor = 'move';
        //     }
        //   });
        // The assignable upstream `el.drift = fn` is the ported `Element.driftHandler` seam (Draggable's
        //   `_drag` calls `draggingTarget.drift(dx,dy,e)`, which delegates to `driftHandler` when set —
        //   fully replacing the default translate). The closure mutates the node rect's shape, then
        //   dispatches `dragNode` (update:'update' → full update re-reads the persisted localX/localY and
        //   re-routes the incident edge ribbons). `[weak el]` breaks the el → driftHandler → el cycle.
        nodeData.eachItemGraphicEl({ el, dataIndex in
            let itemModel = nodeData.getItemModel(dataIndex)
            if (itemModel.get("draggable") as? Bool) == true {
                guard el is Rect else { return }
                let rawIndex = nodeData.getRawIndex(dataIndex)
                el.driftHandler = { [weak el] dx, dy, _ in
                    guard let rect = el as? Rect, var shape = rect.shape as? RectShape else { return }
                    // this.shape.x += dx; this.shape.y += dy;
                    shape.x += dx
                    shape.y += dy
                    _ = rect.setShape(shape)
                    // this.dirty();
                    rect.dirty()
                    // api.dispatchAction({ type: 'dragNode', ... });
                    var p = Payload(type: "dragNode")
                    p.other["seriesId"] = seriesModel.id
                    p.other["dataIndex"] = rawIndex
                    p.other["localX"] = shape.x / width
                    p.other["localY"] = shape.y / height
                    api.dispatchAction(p)
                }
                el.draggable = .true
                // el.cursor = 'move';  — cursor lives on Displayable (Rect is one).
                (el as? Displayable)?.cursor = "move"
            }
        }, nil)

        // if (!this._data && seriesModel.isAnimationEnabled()) { mainGroup.setClipPath(createGridClipShape(...)); }
        //   PORT-TODO: the first-render grow-in clip animation (createGridClipShape + graphic.initProps)
        //   is DEFERRED (util/graphic initProps not ported; CONVENTIONS §5 — animation deferred).

        self._data = seriesModel.getData()

        // Record the morph gate for the next render.
        _prevNodeCount = nodeCount
        _prevEdgeCount = edgeCount
        _prevOrient = orient

        // L3 Roam: re-apply the accumulated roam transform to the main group (upstream applies center/zoom
        //   through the View coord sys; the port transforms the group directly — see roamHelperViewGroup).
        //   On first render / roam off, the state is identity → the placement above is left exactly as-is.
        viewGroupRoamApplyStateToGroup(seriesModel, mainGroup, baseX, baseY)

        self._firstRender = false
    }

    // L3 Roam: the pointer-check element (upstream `createIsInSelfByPointerCheckerEl(this.group)`).
    func roamPointerCheckerGroup() -> Group { return self.group }

    // L3 Roam (test hook): the main group carrying the roam transform (position + scale).
    var _mainGroupForTest: Group { return self._mainGroup }

    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — the port re-renders via the full update()
    //   the `sankeyRoam` action triggers (see roamHelperViewGroup.swift DEVIATION note); no partial path.

    // upstream: dispose() { this._controller && this._controller.dispose(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-TODO: RoamController.dispose DEFERRED (roam not ported).
    }

    // upstream: _updateViewCoordSys(seriesModel, api)  — PORT-TODO: coord/View + roam DEFERRED.

    // The base `ChartView.remove(ecModel, api)` clears the group; sankey has no bespoke remove upstream,
    //   but the mainGroup is a child of `group`, so removeAll cascades. Kept for _data reset symmetry.
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self._mainGroup.removeAll()
        // The persisted node/link elements were just detached by removeAll — clear the bookkeeping so a
        //   subsequent render rebuilds fresh rather than reusing orphaned elements.
        self._nodeEls.removeAll()
        self._linkEls.removeAll()
        self._prevNodeCount = -1
        self._prevEdgeCount = -1
        self._prevOrient = ""
        self._data = nil
    }
}

// ================================================================================================
// upstream: function applyCurveStyle(curveProps: PathStyleProps, orient, edge: GraphEdge)
//   Special color, use source node color or target node color.
//   PORT DEVIATION: upstream takes the `PathStyleProps` bag (so it can be reused by setStatesStylesFromModel);
//   states are DEFERRED here, so the resolver operates directly on `curve.pathStyle` (a settable IUO var).
//   The `fill` currently holds the lineStyle sentinel string ('source' | 'target' | 'gradient').
// ================================================================================================
private func applyCurveStyle(_ curve: SankeyPath, _ orient: String, _ edge: GraphEdge) {
    switch curve.pathStyle.fill {
    case .some(.string("source")):
        // curveProps.fill = edge.node1.getVisual('color');
        curve.pathStyle.fill = sankeyColor(edge.node1.getVisual("color"))
        // curveProps.decal = edge.node1.getVisual('style').decal;
        //   PORT-TODO: edge decal (Pattern) not bridged (out of static-render scope).
    case .some(.string("target")):
        curve.pathStyle.fill = sankeyColor(edge.node2.getVisual("color"))
    case .some(.string("gradient")):
        let sourceColor = sankeyColorString(edge.node1.getVisual("color"))
        let targetColor = sankeyColorString(edge.node2.getVisual("color"))
        // if (isString(sourceColor) && isString(targetColor)) { ... }
        if let sourceColor = sourceColor, let targetColor = targetColor {
            // new graphic.LinearGradient(0, 0, +(orient === 'horizontal'), +(orient === 'vertical'), [...])
            let x2: Double = (orient == "horizontal") ? 1 : 0
            let y2: Double = (orient == "vertical") ? 1 : 0
            let gradient = LinearGradient(0, 0, x2, y2, [
                GradientColorStop(offset: 0, color: sourceColor),
                GradientColorStop(offset: 1, color: targetColor)
            ])
            curve.pathStyle.fill = .linearGradient(gradient)
        }
    default:
        // Any other fill (a real color already, or nil) is left as-is.
        break
    }
}

// ================================================================================================
// upstream: function createGridClipShape(rect: RectLike, seriesModel, cb)
//   PORT-TODO: the first-render grow-in clip animation is DEFERRED. It builds a zero-width Rect and
//   `graphic.initProps` tweens its width to `rect.width + 20`, revealing the diagram left-to-right.
//   `util/graphic.initProps` is not ported (animation deferred per CONVENTIONS §5); reinstate with it.
// ================================================================================================

// export default SankeyView;  -> `open class SankeyView` above.

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// Node/edge layouts are stored by sankeyLayout as a `[String: Any]` dict ({x,y,dx,dy} / {sy,ty,dy}).
//   `getLayout()` returns `Any?`; coerce to the dict (empty when absent, matching JS `undefined` reads → NaN-safe defaults).
// Phase 45: resolve a sankey node/edge `emphasis.focus` string to the topology index set, bridged to the
//   `{node:[…], edge:[…]}` dict form `states.blurSeries`'s object branch consumes. Non-topology focus
//   values ('self'/'series'/indices/nil) pass through unchanged.
private func sankeyFocusDict(_ ix: GraphDataIndices) -> [String: Any] {
    return ["node": ix.node, "edge": ix.edge]
}
private func sankeyResolveNodeFocus(_ focus: InnerFocus?, _ node: GraphNode) -> InnerFocus? {
    switch focus as? String {
    case "adjacency":  return sankeyFocusDict(node.getAdjacentDataIndices())
    case "trajectory": return sankeyFocusDict(node.getTrajectoryDataIndices())
    default:           return focus
    }
}
private func sankeyResolveEdgeFocus(_ focus: InnerFocus?, _ edge: GraphEdge) -> InnerFocus? {
    switch focus as? String {
    case "adjacency":  return sankeyFocusDict(edge.getAdjacentDataIndices())
    case "trajectory": return sankeyFocusDict(edge.getTrajectoryDataIndices())
    default:           return focus
    }
}

private func sankeyLayoutDict(_ v: Any?) -> [String: Any] {
    return (v as? [String: Any]) ?? [:]
}

// TRAP #1 GUARD: `[String: Any]` layout/option values store numbers as bare `Int` OR `Double` OR
//   `NSNumber`. `as? Double` alone SILENTLY DROPS an Int. Coerce all three (nil for genuinely absent /
//   non-numeric so the `dragX != null` branch stays faithful to upstream's `!= null`).
private func sankeyNum(_ v: Any?) -> Double? {
    switch v {
    case nil: return nil
    case is NSNull: return nil
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}

// `itemModel.get(['itemStyle','borderRadius']) as number | number[] || 0` → RectRadius. The JS `|| 0`
//   makes a nil / 0 / falsy value fall to 0 (→ a plain, un-rounded rect via Rect's `!shape.r` check).
private func sankeyBorderRadius(_ v: Any?) -> RectRadius {
    if let n = sankeyNum(v) {
        return .number(n)
    }
    if let arr = v as? [Any] {
        return .array(arr.compactMap { sankeyNum($0) })
    }
    if let arr = v as? [Double] {
        return .array(arr)
    }
    return .number(0)
}

// Bridge a node/edge visual color (`getVisual('color')`, stored as an EChartsKit `ZRColor.color(String)`
//   or a raw `String`) to a ZRenderKit `ZRColor.string`. Gradient/pattern node colors out of scope.
private func sankeyColor(_ v: Any?) -> ZRenderKit.ZRColor? {
    if let s = sankeyColorString(v) { return .string(s) }
    return nil
}

// The raw solid-color string of a visual color (used by the 'gradient' branch, which needs both node
//   colors to be plain strings — upstream `isString(sourceColor) && isString(targetColor)`).
private func sankeyColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// `useStyle(model.getItemStyle())` bridge. getItemStyle / getLineStyle return a dynamic `[String: Any]`
//   bag; ZRenderKit `useStyle` takes a typed `PathStyleProps`. Reuses the shared visual-style →
//   PathStyleProps bridge (barStyleFromDict) — solid colors only (gradient/pattern out of scope; the
//   sankey 'gradient' edge fill is built directly by applyCurveStyle instead).
private func sankeyStyleFromDict(_ style: Any?) -> PathStyleProps {
    return barStyleFromDict(style)
}

// upstream `${edgeModel.get('value')}` template-string coercion → the plain edge-label default text.
private func sankeyStringify(_ v: Any?) -> String {
    switch v {
    case nil: return "undefined"
    case is NSNull: return "null"
    case let s as String: return s
    case let i as Int: return String(i)
    case let d as Double:
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: v!)
    }
}

// PLAIN-TEXT reproduction of setLabelStyle for the sankey node/edge label (label/labelStyle NOT ported).
//   Draws the normal-state label: text (formatter DEFERRED → defaultText), font, and fill from the label
//   model, attached to the host via setTextContent + a textConfig position. `label.show === false` hides it.
//   Same deviation as FunnelView's `funnelUpdateLabel`.
private func sankeySetLabel(_ host: Path, _ labelModel: Model, _ defaultText: String, _ forcedPosition: String?) {
    var textStyle = TextStyleProps()
    textStyle.text = defaultText
    textStyle.font = labelModel.getFont()
    if let c = labelModel.getTextColor() {
        textStyle.fill = c
    }

    let labelText = ZRText()
    labelText.useStyle(textStyle)

    // `label.show === false` hides the label (upstream drives this through the label states model).
    if let show = labelModel.get("show") as? Bool, !show {
        labelText.ignore = true
    }

    host.setTextContent(labelText)

    var textConfig = ElementTextConfig()
    // Edge labels are forced 'inside' (upstream `curve.setTextConfig({ position: 'inside' })`); node
    //   labels take the label model's `position` (sankey node default is 'right').
    if let forcedPosition = forcedPosition {
        textConfig.position = forcedPosition
    }
    else if let pos = labelModel.get("position") as? String {
        textConfig.position = pos
    }
    host.setTextConfig(textConfig)
}
