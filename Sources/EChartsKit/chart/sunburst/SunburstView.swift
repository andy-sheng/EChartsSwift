// Ported from echarts/src/chart/sunburst/SunburstView.ts — keep in sync with upstream
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
//   import ChartView from '../../view/Chart';                      -> `ChartView` (view/Chart.swift).
//   import SunburstPiece from './SunburstPiece';                   -> `SunburstPiece` (chart/sunburst/SunburstPiece.swift).
//   import DataDiffer from '../../data/DataDiffer';                -> PORT-TODO: `DataDiffer` diff DEFERRED (static rebuild).
//   import SunburstSeriesModel, { SERIES_TYPE_SUNBURST, ... } from './SunburstSeries';  -> sibling SunburstSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> `ExtensionAPI`.
//   import { TreeNode } from '../../data/Tree';                    -> sibling `TreeNode` / `Tree` (data/Tree.swift).
//   import { ROOT_TO_NODE_ACTION } from './sunburstAction';        -> PORT-TODO: sunburstAction NOT ported (actions deferred).
//   import { windowOpen } from '../../util/format';                -> PORT-TODO: only used by click events (deferred).

// upstream: interface DrawTreeNode extends TreeNode { parentNode; piece; children }
// PORT-TODO: TreeNode is not externally augmentable in Swift (see SunburstPiece.swift DrawTreeNode
//   PORT-TODO). The static render does not consult `node.piece`, so `TreeNode` is used directly.

// upstream: class SunburstView extends ChartView
open class SunburstView: ChartView {

    // static readonly type = SERIES_TYPE_SUNBURST;  /  readonly type = SERIES_TYPE_SUNBURST;
    public static let sunburstType = SERIES_TYPE_SUNBURST
    open override var type: String {
        get { SERIES_TYPE_SUNBURST }
        set { /* readonly upstream */ }
    }

    // upstream: seriesModel; api; ecModel; (injected in render)
    public var seriesModel: SunburstSeriesModel?
    public var api: ExtensionAPI?
    // NOTE: `ecModel` shadows no base member — ChartView has none; kept as-is for provenance.
    public var ecModel: GlobalModel?

    // upstream: virtualPiece: SunburstPiece;
    public var virtualPiece: SunburstPiece?

    // upstream: private _oldChildren: DrawTreeNode[];
    private var _oldChildren: [TreeNode]?

    // Persistent per-node SunburstPiece sectors (view REUSE, L5 fidelity) so a merge-mode setOption
    //   value change — or a same-count drill re-root — MORPHS each wedge to its new angular span rather
    //   than rebuilding-and-snapping. In emission order (preorder, virtualRoot + zero-value nodes
    //   skipped). Reused when the emitted-node count is unchanged (`canMorph`); a node-count change
    //   rebuilds fresh (with the sweep-open entrance). NOT the DataDiffer add/update/remove (deferred).
    private var _sectorPieces: [SunburstPiece] = []

    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: SunburstSeriesModel`; base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! SunburstSeriesModel

        // const self = this;
        // this.seriesModel = seriesModel; this.api = api; this.ecModel = ecModel;
        self.seriesModel = seriesModel
        self.api = api
        self.ecModel = ecModel

        // const data = seriesModel.getData();
        let data = seriesModel.getData()
        // const virtualRoot = data.tree.root as DrawTreeNode;
        // `data.tree` is `Tree?` on SeriesData; bail if not present (matches an empty render).
        guard let tree = data.tree else {
            return
        }
        let virtualRoot: TreeNode = tree.root   // annotate: `root` is IUO; a bare `let` infers Optional

        // const newRoot = seriesModel.getViewRoot() as DrawTreeNode;
        let newRoot = seriesModel.getViewRoot()

        // const group = this.group;
        let group = self.group

        // const renderLabelForZeroData = seriesModel.get('renderLabelForZeroData');
        let renderLabelForZeroData = (seriesModel.get("renderLabelForZeroData") as? Bool) ?? false

        // const newChildren: DrawTreeNode[] = [];
        // newRoot.eachNode(function (node) { newChildren.push(node); });
        //   eachNode's callback is `TreeTraverseCallback = (TreeNode) -> Any?` (return false in preorder
        //   suppresses the subtree); return nil to keep traversing.
        var newChildren: [TreeNode] = []
        newRoot.eachNode({ (node: TreeNode) -> Any? in
            newChildren.append(node)
            return nil
        })
        // const oldChildren = this._oldChildren || [];
        _ = self._oldChildren ?? []

        // ------------------------------------------------------------------------------------------
        // MORPH render (view reuse): upstream `dualTravel(newChildren, oldChildren)` runs a `DataDiffer`
        //   (add/update/remove) keyed by `node.getId()`, mutating `node.piece` and reusing SunburstPiece
        //   instances. The full add/update/remove DIFF is still deferred, but the reuse+morph is realised
        //   here: emit the drawable nodes (skip the virtualRoot and, unless renderLabelForZeroData, the
        //   zero-value nodes — the `doRenderNode` `newNode = null` filter), then reuse the persisted
        //   SunburstPieces positionally when the emitted-node count is unchanged (`canMorph`) — each piece
        //   morphs its sector to the new angular span via `updateData(firstCreate: false)`. A node-count
        //   change rebuilds fresh (sweep-open entrance).
        // ------------------------------------------------------------------------------------------

        // Drawable nodes in preorder emission order (`doRenderNode`'s filter, statically applied):
        //   skip the virtualRoot, and (unless renderLabelForZeroData) any zero/NaN-value node.
        var emitNodes: [TreeNode] = []
        for n in newChildren {
            if n === virtualRoot { continue }
            // if (!renderLabelForZeroData && !newNode.getValue()) { newNode = null; }  — not drawn.
            if !renderLabelForZeroData, !zrValueTruthy(n.getValue()) { continue }
            emitNodes.append(n)
        }

        // Morph iff we already have pieces and the drawable-node count is unchanged (values/angles
        //   changed, or a same-count re-root). A count change (or first render) rebuilds fresh.
        let canMorph = !self._sectorPieces.isEmpty && self._sectorPieces.count == emitNodes.count
        if canMorph {
            for (i, n) in emitNodes.enumerated() {
                let piece = self._sectorPieces[i]
                // updateData(false, ...) morphs the sector shape (updateProps sweep) and refreshes
                //   style/label/states + the live `node` (so the persisted click binding drills to the
                //   CURRENT node — see `_bindNodeClick`, which reads `piece.node`).
                piece.updateData(false, n, seriesModel, ecModel, api)
                // For tooltip: data.setItemGraphicEl(newNode.dataIndex, piece);
                data.setItemGraphicEl(n.dataIndex, piece)
            }
        } else {
            // Rebuild fresh: drop the persisted pieces (and the roll-up) and re-create.
            _ = group.removeAll()
            self.virtualPiece = nil
            self._sectorPieces = []
            for n in emitNodes {
                // const piece = new SunburstPiece(newNode, seriesModel, ecModel, api);
                let piece = SunburstPiece(n, seriesModel, ecModel, api)
                // group.add(piece);
                _ = group.add(piece)
                // For tooltip: data.setItemGraphicEl(newNode.dataIndex, piece);
                //   TreeNode.dataIndex is already `Int`.
                data.setItemGraphicEl(n.dataIndex, piece)

                // upstream binds a single `group.on('click')` and matches `e.target` back to a node via
                //   `node.piece === e.target`; this port has no `node.piece` slot (see DrawTreeNode
                //   PORT-TODO), so — following the established per-element binding pattern — bind the
                //   node's own SunburstPiece: the click BUBBLES from the hit child up to it. Same behaviour
                //   as upstream `_initEvents` (nodeClick 'rootToNode' → `_rootToNode(node)`).
                self._bindNodeClick(piece)
                self._sectorPieces.append(piece)
            }
        }

        // renderRollUp(virtualRoot, newRoot);
        renderRollUp(virtualRoot, newRoot, seriesModel, ecModel, api, group)

        // this._initEvents();
        //   The upstream `group.on('click')` + `viewRoot.eachNode(node.piece === e.target)` dispatch is
        //   realised here as a per-SunburstPiece `on('click')` binding (see `_bindNodeClick`, wired in the
        //   render loop and in `renderRollUp`), because this port carries no `node.piece` slot. The `link`
        //   branch (`windowOpen`) is DEFERRED (no URL side effects in the native host).

        // this._oldChildren = newChildren;
        self._oldChildren = newChildren
    }

    // Per-node click binding — the port's realisation of upstream `_initEvents()`. Reads the node's
    //   `nodeClick` (defaults to 'rootToNode' via the series option) and, when it is 'rootToNode', drills
    //   the view root to that node. The `'link'` branch (windowOpen) is DEFERRED. `false` disables it.
    private func _bindNodeClick(_ piece: SunburstPiece) {
        // Read the node off the PIECE (not a captured `node`) so the binding — installed once at create
        //   time and NOT re-installed when the piece is reused/morphed — always drills to the piece's
        //   CURRENT node (updateData refreshes `piece.node`). This keeps one handler per piece (no
        //   duplicate-handler accumulation across morphs).
        _ = piece.on("click", { [weak self, weak piece] _, _ in
            guard let self = self, let piece = piece, let node = piece.node else { return nil }
            // const nodeClick = node.getModel().get('nodeClick');
            //   `node.getModel()` is `Model?`; fall back to the series-level option so a node without an
            //   item model still honours the default ('rootToNode').
            let nodeClick = (node.getModel()?.get("nodeClick")
                ?? self.seriesModel?.get("nodeClick")) as? String
            if nodeClick == "rootToNode" {
                self._rootToNode(node)
            }
            // else if (nodeClick === 'link') { ... windowOpen(link, target) }  — DEFERRED.
            return nil
        }, nil)
    }

    // upstream: function renderRollUp(virtualRoot, viewRoot) { ... }  (nested in render)
    //   Hoisted to a method (Swift has no nested `self.virtualPiece` closure capture ergonomics for a
    //   pure static rebuild). Click-off/-on wiring DEFERRED (events not ported).
    private func renderRollUp(
        _ virtualRoot: TreeNode, _ viewRoot: TreeNode,
        _ seriesModel: SunburstSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ group: Group
    ) {
        // Drop any previously drawn roll-up sector first. The rebuild path already cleared it (removeAll
        //   + virtualPiece = nil, so this is a no-op there); the MORPH path leaves the old roll-up in the
        //   group, so remove it here before re-adding for the current view root.
        if let vp = self.virtualPiece {
            _ = group.remove(vp)
            self.virtualPiece = nil
        }
        // if (viewRoot.depth > 0) { ... Add virtualPiece ... }
        if viewRoot.depth > 0 {
            self.virtualPiece = SunburstPiece(virtualRoot, seriesModel, ecModel, api)
            _ = group.add(self.virtualPiece!)

            // viewRoot.piece.off('click'); self.virtualPiece.on('click', () => self._rootToNode(viewRoot.parentNode));
            //   Clicking the centre (the roll-up sector) roots back UP to the current view root's parent.
            let parentNode = viewRoot.parentNode
            _ = self.virtualPiece!.on("click", { [weak self] _, _ in
                guard let self = self, let parent = parentNode else { return nil }
                self._rootToNode(parent)
                return nil
            }, nil)
        }
        // else if (self.virtualPiece) { group.remove(...); self.virtualPiece = null; }  — subsumed by removeAll().
    }

    // upstream: _rootToNode(node) { if (node !== this.seriesModel.getViewRoot()) { this.api.dispatchAction({
    //   type: ROOT_TO_NODE_ACTION, from: this.uid, seriesId: this.seriesModel.id, targetNode: node }); } }
    private func _rootToNode(_ node: TreeNode) {
        guard let seriesModel = self.seriesModel, let api = self.api else { return }
        // if (node !== this.seriesModel.getViewRoot())
        if node !== seriesModel.getViewRoot() {
            var payload = Payload(type: ROOT_TO_NODE_ACTION)
            payload.other["from"] = self.uid
            payload.other["seriesId"] = seriesModel.id
            payload.other["targetNode"] = node
            api.dispatchAction(payload)
        }
    }

    // upstream: containPoint(point, seriesModel): boolean  @implement
    open override func containPoint(_ point: [Double], _ seriesModelBase: SeriesModel) -> Bool {
        let seriesModel = seriesModelBase as! SunburstSeriesModel
        // const treeRoot = seriesModel.getData();
        let treeRoot = seriesModel.getData()
        // const itemLayout = treeRoot.getItemLayout(0);
        let itemLayout = treeRoot.getItemLayout(0) as? [String: Any]
        if let itemLayout = itemLayout {
            // const dx = point[0] - itemLayout.cx; const dy = point[1] - itemLayout.cy;
            let cx = (itemLayout["cx"] as? Double) ?? Double.nan
            let cy = (itemLayout["cy"] as? Double) ?? Double.nan
            let r = (itemLayout["r"] as? Double) ?? Double.nan
            let r0 = (itemLayout["r0"] as? Double) ?? Double.nan
            let dx = point[0] - cx
            let dy = point[1] - cy
            // const radius = Math.sqrt(dx * dx + dy * dy);
            let radius = sqrt(dx * dx + dy * dy)
            // return radius <= itemLayout.r && radius >= itemLayout.r0;
            return radius <= r && radius >= r0
        }
        // upstream returns `undefined` (falsy) when there is no item layout.
        return false
    }
}

// Models upstream `!newNode.getValue()`: a `number` value is JS-falsy when 0 or NaN. `getValue()`
//   returns `Any?` (Double | nil) in the sibling Tree port.
private func zrValueTruthy(_ value: Any?) -> Bool {
    guard let v = value as? Double else { return false }
    return v != 0 && !v.isNaN
}

// export default SunburstView;  -> `open class SunburstView` above.
