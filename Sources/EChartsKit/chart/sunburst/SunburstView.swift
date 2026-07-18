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
//   import DataDiffer from '../../data/DataDiffer';                -> `DataDiffer` (data/DataDiffer.swift); the getId-keyed add/update/remove reconciliation IS wired below (dualTravel).
//   import SunburstSeriesModel, { SERIES_TYPE_SUNBURST, ... } from './SunburstSeries';  -> sibling SunburstSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> `ExtensionAPI`.
//   import { TreeNode } from '../../data/Tree';                    -> sibling `TreeNode` / `Tree` (data/Tree.swift).
//   import { ROOT_TO_NODE_ACTION } from './sunburstAction';        -> sunburstAction.swift (ROOT_TO_NODE_ACTION exists); click-driven dispatch deferred.
//   import { windowOpen } from '../../util/format';                -> `windowOpen` (util/format.swift); wired in the nodeClick:'link' branch (a documented host-seam no-op natively).

// upstream: interface DrawTreeNode extends TreeNode { parentNode; piece; children }
// PORT-NOTE: TreeNode is not externally augmentable in Swift (see SunburstPiece.swift DrawTreeNode
//   PORT-NOTE). The static render does not consult `node.piece`, so `TreeNode` is used directly.

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

    // Persistent per-node SunburstPiece registry keyed by `node.getId()` — the port's stand-in for
    //   upstream's `node.piece` slot (TreeNode carries no `piece` field; see the DrawTreeNode
    //   PORT-NOTE). `dualTravel` runs the DataDiffer add/update/remove against this map so an identity
    //   change (add/remove) at equal count reuses the RIGHT piece by id (not positionally), and an
    //   update MORPHS the matched wedge to its new angular span via `updateData(firstCreate: false)`.
    private var _pieceMap: [String: SunburstPiece] = [:]

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
        let oldChildren = self._oldChildren ?? []

        // dualTravel(newChildren, oldChildren);
        //   The getId-keyed DataDiffer (add/update/remove). Mirrors upstream: reuse the persisted
        //   SunburstPiece for a node whose id is unchanged (MORPH via updateData), create one for a
        //   new id (ADD), and drop one whose id vanished (REMOVE). `_pieceMap` is the port's `node.piece`
        //   slot (keyed by id), so an identity change at equal count reuses the correct piece.
        dualTravel(
            newChildren, oldChildren, virtualRoot, renderLabelForZeroData,
            seriesModel, ecModel, api, data, group
        )

        // renderRollUp(virtualRoot, newRoot);
        renderRollUp(virtualRoot, newRoot, seriesModel, ecModel, api, group)

        // this._initEvents();
        //   The upstream `group.on('click')` + `viewRoot.eachNode(node.piece === e.target)` dispatch is
        //   realised here as a per-SunburstPiece `on('click')` binding (see `_bindNodeClick`, wired at ADD
        //   time in `dualTravel` and in `renderRollUp`), because this port carries no `node.piece` slot.

        // this._oldChildren = newChildren;
        self._oldChildren = newChildren
    }

    // upstream: function dualTravel(newChildren, oldChildren) { ... }  (nested in render)
    //   Hoisted to a method (Swift has no nested-closure ergonomics for `self._pieceMap` capture). Runs
    //   the getId-keyed DataDiffer add/update/remove against the persisted `_pieceMap`.
    private func dualTravel(
        _ newChildren: [TreeNode], _ oldChildren: [TreeNode],
        _ virtualRoot: TreeNode, _ renderLabelForZeroData: Bool,
        _ seriesModel: SunburstSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI,
        _ data: SeriesData, _ group: Group
    ) {
        // if (newChildren.length === 0 && oldChildren.length === 0) return;
        if newChildren.isEmpty && oldChildren.isEmpty {
            return
        }

        // function getKey(node) { return node.getId(); }
        let getKey: DiffKeyGetter = { value, _ in (value as! TreeNode).getId() }

        // function processNode(newIdx, oldIdx?) { doRenderNode(newChildren[newIdx], oldChildren[oldIdx]); }
        //   new DataDiffer(oldChildren, newChildren, getKey, getKey).add.update.remove.execute()
        let differ = DataDiffer<TreeNode>(
            oldChildren.map { $0 as Any },
            newChildren.map { $0 as Any },
            getKey,
            getKey
        )
        differ.add { newIdx in
            self.doRenderNode(
                newChildren[newIdx], nil, virtualRoot, renderLabelForZeroData,
                seriesModel, ecModel, api, data, group
            )
        }
        differ.update { newIdx, oldIdx in
            self.doRenderNode(
                newChildren[newIdx], oldChildren[oldIdx], virtualRoot, renderLabelForZeroData,
                seriesModel, ecModel, api, data, group
            )
        }
        differ.remove { oldIdx in
            // upstream: zrUtil.curry(processNode, null) — newIdx bound to null.
            self.doRenderNode(
                nil, oldChildren[oldIdx], virtualRoot, renderLabelForZeroData,
                seriesModel, ecModel, api, data, group
            )
        }
        differ.execute()
    }

    // upstream: function doRenderNode(newNode, oldNode) { ... }  (nested in render)
    private func doRenderNode(
        _ newNodeIn: TreeNode?, _ oldNode: TreeNode?,
        _ virtualRoot: TreeNode, _ renderLabelForZeroData: Bool,
        _ seriesModel: SunburstSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI,
        _ data: SeriesData, _ group: Group
    ) {
        var newNode = newNodeIn
        // if (!renderLabelForZeroData && newNode && !newNode.getValue()) { newNode = null; }
        if !renderLabelForZeroData, let nn = newNode, !zrValueTruthy(nn.getValue()) {
            newNode = nil
        }

        // if (newNode !== virtualRoot && oldNode !== virtualRoot)  (a nil operand is never virtualRoot)
        if newNode !== virtualRoot && oldNode !== virtualRoot {
            // if (oldNode && oldNode.piece) — the port's `node.piece` is `_pieceMap[oldNode.getId()]`.
            if let oldNode = oldNode, let piece = self._pieceMap[oldNode.getId()] {
                if let nn = newNode {
                    // Update: oldNode.piece.updateData(false, newNode, ...)
                    piece.updateData(false, nn, seriesModel, ecModel, api)
                    // For tooltip: data.setItemGraphicEl(newNode.dataIndex, oldNode.piece);
                    data.setItemGraphicEl(nn.dataIndex, piece)
                    // Re-home the piece under the new node's id (old.getId() == new.getId() on an
                    //   id-matched update, so this is a same-key rewrite — the port's `node.piece = piece`).
                    self._pieceMap[nn.getId()] = piece
                } else {
                    // Remove: removeNode(oldNode) — group.remove(node.piece); node.piece = null;
                    _ = group.remove(piece)
                    self._pieceMap[oldNode.getId()] = nil
                }
            } else if let nn = newNode {
                // Add: const piece = new SunburstPiece(newNode, ...); group.add(piece);
                let piece = SunburstPiece(nn, seriesModel, ecModel, api)
                _ = group.add(piece)
                // For tooltip: data.setItemGraphicEl(newNode.dataIndex, piece);
                data.setItemGraphicEl(nn.dataIndex, piece)
                // upstream binds a single `group.on('click')` and matches `e.target` back to a node via
                //   `node.piece === e.target`; this port has no `node.piece` slot, so — following the
                //   established per-element pattern — bind the node's own SunburstPiece (the click bubbles
                //   from the hit child up to it). Same behaviour as upstream `_initEvents`.
                self._bindNodeClick(piece)
                self._pieceMap[nn.getId()] = piece
            }
        }
    }

    // Per-node click binding — the port's realisation of upstream `_initEvents()`. Reads the node's
    //   `nodeClick` (defaults to 'rootToNode' via the series option); 'rootToNode' drills the view root
    //   to that node, 'link' opens the node's URL (host-seam), `false` disables it.
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
            let itemModel = node.getModel()
            let nodeClick = (itemModel?.get("nodeClick")
                ?? self.seriesModel?.get("nodeClick")) as? String
            if nodeClick == "rootToNode" {
                self._rootToNode(node)
            } else if nodeClick == "link" {
                // const link = itemModel.get('link');
                if let link = itemModel?.get("link") as? String, !link.isEmpty {
                    // const linkTarget = itemModel.get('target', true) || '_blank';
                    let linkTarget = (itemModel?.get("target", true) as? String) ?? "_blank"
                    // windowOpen(link, linkTarget);  — host-seam no-op natively (util/format.swift).
                    format.windowOpen(link, linkTarget)
                }
            }
            return nil
        }, nil)
    }

    // upstream: function renderRollUp(virtualRoot, viewRoot) { ... }  (nested in render)
    //   Hoisted to a method (Swift has no nested `self.virtualPiece` closure capture ergonomics).
    private func renderRollUp(
        _ virtualRoot: TreeNode, _ viewRoot: TreeNode,
        _ seriesModel: SunburstSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ group: Group
    ) {
        // if (viewRoot.depth > 0) { ... }
        if viewRoot.depth > 0 {
            if let vp = self.virtualPiece {
                // Update: self.virtualPiece.updateData(false, virtualRoot, ...) — MORPH the roll-up sector
                //   to the new centre span rather than remove+recreate.
                vp.updateData(false, virtualRoot, seriesModel, ecModel, api)
            } else {
                // Add: self.virtualPiece = new SunburstPiece(virtualRoot, ...); group.add(...);
                self.virtualPiece = SunburstPiece(virtualRoot, seriesModel, ecModel, api)
                _ = group.add(self.virtualPiece!)
            }

            // viewRoot.piece.off('click'); self.virtualPiece.on('click', () => self._rootToNode(viewRoot.parentNode));
            //   Clicking the centre (the roll-up sector) roots back UP to the current view root's parent.
            //   PORT-NOTE: upstream's `viewRoot.piece.off('click')` is intentionally NOT replicated — in
            //   this port a node's own click handler drills via `_rootToNode(node)`, which is a guarded
            //   no-op when node IS the view root, so leaving it is harmless AND preserves the piece's
            //   handler for later renders (removing it would strand the reused piece with no click). The
            //   virtualPiece's own handler is re-bound (off+on) every render so the captured parentNode
            //   never goes stale across a morph-reuse (avoids handler accumulation too).
            let parentNode = viewRoot.parentNode
            _ = self.virtualPiece!.off("click")
            _ = self.virtualPiece!.on("click", { [weak self] _, _ in
                guard let self = self, let parent = parentNode else { return nil }
                self._rootToNode(parent)
                return nil
            }, nil)
        }
        // else if (self.virtualPiece) { group.remove(self.virtualPiece); self.virtualPiece = null; }
        else if let vp = self.virtualPiece {
            _ = group.remove(vp)
            self.virtualPiece = nil
        }
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
