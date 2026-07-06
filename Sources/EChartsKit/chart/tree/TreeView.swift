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
//   import {getECData} from '../../util/innerStore';               -> PORT-TODO: innerStore NOT ported (focus/ECData deferred).
//   import SymbolClz from '../helper/Symbol';                      -> PORT-TODO: chart/helper/Symbol NOT ported.
//       The node symbol is built inline with `symbol.createSymbol` (same deviation as ScatterView),
//       so `TreeSymbol`'s `__edge`/`__radial*`/`__old*` augmentation + updateData/useNameLabel/
//       setSymbolScale/fadeOut are DEFERRED.
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
//       from '../../util/states';                                  -> PORT-TODO: util/states NOT ported (emphasis/blur deferred).
//   import { AnimationOption, ECElement, RoamPayload } from '../../util/types';  -> util/types.swift (type-only).
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts NOT ported. `tokens.color.neutral99` (='#000') and
//          `tokens.color.neutral00` (='#fff') are inlined as their upstream literals below.
//   import { createIsInSelfByPointerCheckerEl, createViewCoordSysSimply, isRoamPayloadHasZoom,
//            updateRoamControllerSimply } from '../../component/helper/roamHelper';
//       -> PORT-TODO: roamHelper NOT ported (roam deferred).

// PORT-TODO: `tokens.color.*` (visual/tokens.ts). Inlined as the upstream literal values.
private let tokens_color_neutral99 = "#000"
private let tokens_color_neutral00 = "#fff"

// upstream:
//   type TreeSymbol = SymbolClz & { __edge; __radialOldRawX; __radialOldRawY; __radialRawX; __radialRawY;
//     __oldX; __oldY };
// PORT-TODO: SymbolClz (chart/helper/Symbol) NOT ported; the augmented `TreeSymbol` (edge back-pointer +
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

    // PORT-TODO: private _controller: RoamController;  — roam NOT ported (deferred).

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

        if layout == "radial" {
            group.x = layoutInfo.x + layoutInfo.width / 2
            group.y = layoutInfo.y + layoutInfo.height / 2
        }
        else {
            group.x = layoutInfo.x
            group.y = layoutInfo.y
        }

        // this._updateViewCoordSys(seriesModel, api);
        //   PORT-TODO: view coord system (bbox + createViewCoordSysSimply + applyViewCoordSysTransToElement)
        //   is DEFERRED (coord/View + roamHelper not ported). The group position set above is the static
        //   subset of the placement it performs; roam pan/zoom is not applied.

        // updateRoamControllerSimply(...);  — PORT-TODO: roam DEFERRED.

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream `data.diff(oldData)` runs add/update/remove keyed by id,
        //   reusing TreeSymbol instances + enter/update/remove animation. The diff + SymbolClz reuse +
        //   expand/collapse click action + node/link scale are DEFERRED (see PORT-TODOs), so the group
        //   is rebuilt from scratch each render: one node symbol + its parent/child edge per node.
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // .add / .update: `if (symbolNeedsDraw(data, newIdx)) { updateNode(...); }`
        for newIdx in 0..<data.count() {
            if symbolNeedsDraw(data, newIdx) {
                updateNode(data, newIdx, group, seriesModel)
            }
        }

        // this._updateNodeAndLinkScale(seriesModel);
        //   PORT-TODO: DEFERRED — setSymbolScale / calcCompensationScaleToPreserveNodeSize (roam) not ported.

        // if (seriesModel.get('expandAndCollapse') === true) { ... el.on('click', treeExpandAndCollapse) }
        //   PORT-TODO: expand/collapse click action DEFERRED (actions not ported).

        self._data = data

        // this._firstRender = false;  — PORT-TODO: roam state DEFERRED.
    }

    // upstream: __updateOnOwnRoam(payload, seriesModel, api)  — PORT-TODO: roam DEFERRED.

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

// upstream: function updateNode(data, dataIndex, symbolEl, group, seriesModel)
//   STATIC form: `symbolEl` (the reused TreeSymbol) is always nil here — the group is rebuilt each render.
//   The enter/update animation (graphic.updateProps of x/y & radial label rotation), SymbolClz.updateData,
//   useNameLabel, symbolInnerColor, and the emphasis focus (getECData / onHoverStateChange) are DEFERRED.
private func updateNode(
    _ data: SeriesData,
    _ dataIndex: Int,
    _ group: Group,
    _ seriesModel: TreeSeriesModel
) {
    // const node = data.tree.getNodeByDataIndex(dataIndex);
    guard let node = data.tree?.getNodeByDataIndex(dataIndex) else { return }
    // const itemModel = node.getModel();  (used by drawEdge for lineStyle)

    // const visualColor = (node.getVisual('style') as PathStyleProps).fill;
    let visualColor = treeVisualFill(node.getVisual("style"))
    // const symbolInnerColor = node.isExpand === false && node.children.length !== 0
    //     ? visualColor : tokens.color.neutral00;
    //   PORT-TODO: symbolInnerColor is a SymbolClz init opt (inner "hollow" fill for collapsed nodes);
    //   SymbolClz is not ported so it is unused by the plain `symbol.createSymbol` node below.
    _ = node.isExpand == false && node.children.count != 0 ? visualColor : tokens_color_neutral00

    // const virtualRoot = data.tree.root;
    let virtualRoot: TreeNode = data.tree!.root

    // const source = node.parentNode === virtualRoot ? node : node.parentNode || node;
    let source: TreeNode = node.parentNode === virtualRoot ? node : (node.parentNode ?? node)
    // const sourceLayout = source.getLayout() as TreeNodeLayout;
    //   (sourceOldLayout — the animation snapshot — is DEFERRED; the static render uses sourceLayout.)
    let sourceLayout = treeNodeLayout(source.getLayout())
    // const targetLayout = node.getLayout();
    guard let targetLayout = treeNodeLayout(node.getLayout()) else { return }

    // ------------------------------------------------------------------------------------------
    // symbolEl = new SymbolClz(data, dataIndex, null, { symbolInnerColor, useNameLabel: true });
    //   PORT-TODO: SymbolClz not ported. Build the node symbol with `symbol.createSymbol` (ScatterView
    //   deviation): item visual symbol/symbolSize/style-fill, centered on targetLayout. useNameLabel
    //   (the node-name label) + symbolInnerColor + emphasis are DEFERRED.
    // ------------------------------------------------------------------------------------------
    let seriesSymbol = (seriesModel.get("symbol", false) as? String) ?? "emptyCircle"
    let seriesSymbolSize: Any = seriesModel.get("symbolSize", false) ?? 7.0
    let symbolType = (data.getItemVisual(dataIndex, "symbol") as? String) ?? seriesSymbol
    let (sizeW, sizeH) = symbol.normalizeSymbolSize(data.getItemVisual(dataIndex, "symbolSize") ?? seriesSymbolSize)

    var fill: ZRenderKit.ZRColor? = nil
    if let cs = visualColor { fill = .string(cs) }

    // graphic.updateProps(symbolEl, { x: targetLayout.x, y: targetLayout.y }, seriesModel):
    //   animation deferred → place the symbol at its final position (centered on the layout point).
    let symbolEl = symbol.createSymbol(
        symbolType, targetLayout.x - sizeW / 2, targetLayout.y - sizeH / 2, sizeW, sizeH, fill
    )
    if let path = symbolEl as? Path {
        path.name = "item"

        // upstream (SymbolClz → chart/helper/Symbol._updateCommon, Symbol.ts:357): the node symbol is
        //   marked a highDown dispatcher carrying its emphasis-state itemStyle, so a hover restyles it.
        //   Mirror ScatterView.render's block.
        //   PORT-TODO: `focus === 'relative'|'ancestor'|'descendant'` (getAncestorsIndices /
        //   getDescendantIndices, TreeView.ts:447-456) — the tree-topology focus that also blurs
        //   unrelated nodes — is DEFERRED (raw focus passed through).
        let itemModel = data.getItemModel(dataIndex)
        let emphasisModel = itemModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        states.toggleHoverEmphasis(path, focus, blurScope, isDisabled)
        states.setStatesStylesFromModel(path, itemModel)

        // group.add(symbolEl); data.setItemGraphicEl(dataIndex, symbolEl);
        _ = group.add(path)
        data.setItemGraphicEl(dataIndex, path)

        // Phase 45: `emphasis.focus:'relative'|'ancestor'|'descendant'` (upstream TreeView.ts:447-456).
        //   Overwrite the node symbol's `ecData.focus` with the topology index SET (ancestors and/or
        //   descendants — all node dataIndices), so hovering the node keeps that lineage bright and blurs
        //   the rest. The value is a plain `[Int]` (the ARRAY-focus form `states.blurSeries` consumes; tree
        //   edges are anonymous children with no edge-data, so there is no edge dataType).
        if let resolved = treeResolveFocus(focus, node) {
            innerStore.getECData(path).focus = resolved
        }
    }

    // Radial label position/rotation block — PORT-TODO: DEFERRED (SymbolClz text content + setTextConfig
    //   not available without the ported chart/helper/Symbol node label).

    // Handle status (emphasis focus 'relative'|'ancestor'|'descendant' → getECData(symbolEl).focus):
    //   PORT-TODO: DEFERRED (util/innerStore + states not ported).

    // drawEdge(seriesModel, node, virtualRoot, symbolEl, sourceOldLayout, sourceLayout, targetLayout, group);
    drawEdge(seriesModel, node, virtualRoot, sourceLayout, targetLayout, group)

    // symbolEl.__edge onHoverStateChange (blur propagation) — PORT-TODO: DEFERRED (states not ported).
}

// upstream: function drawEdge(seriesModel, node, virtualRoot, symbolEl, sourceOldLayout,
//     sourceLayout, targetLayout, group)
//   STATIC form: no `symbolEl.__edge` cache / animation. `sourceOldLayout` (the pre-animation snapshot,
//   used only to init the edge before `updateProps`) is dropped; the edge is built at its final shape.
private func drawEdge(
    _ seriesModel: TreeSeriesModel,
    _ node: TreeNode,
    _ virtualRoot: TreeNode,
    _ sourceLayout: TreeNodeLayout?,
    _ targetLayout: TreeNodeLayout,
    _ group: Group
) {
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
    }
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

        // PORT-TODO: `radialCoordinate(rad, r)` from sibling ./layoutHelper (assumed exposed as
        //   `layoutHelper.radialCoordinate` returning a value with `.x`/`.y`). `|| 0` reproduces JS
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
