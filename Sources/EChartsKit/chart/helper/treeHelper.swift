// Ported from echarts/src/chart/helper/treeHelper.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';   -> `util.*` (ZRenderKit).
//   import SeriesModel from '../../model/Series';       -> `SeriesModel`.
//   import { TreeNode } from '../../data/Tree';         -> sibling `TreeNode` (data/Tree.swift).

// upstream free functions of treeHelper.ts, mapped to a caseless-enum namespace (à la the module import
//   `import { retrieveTargetInfo, aboveViewRoot } from '../helper/treeHelper'`). Only the members used
//   by the ported sunburst action are translated; `wrapTreePathInfo` stays DEFERRED (referenced only by
//   the deferred tree/sunburst/treemap `getDataParams` — see those series' deferred PORT-NOTEs).
public enum treeHelper {

    // upstream: retrieveTargetInfo returns `{ node: TreeNode }` (or undefined).
    public struct TargetInfo {
        public var node: TreeNode
        public init(node: TreeNode) { self.node = node }
    }

    // export function retrieveTargetInfo(payload, validPayloadTypes, seriesModel)
    //   `payload.targetNode` is `string | TreeNode`; `payload.targetNodeId` is `string`. In the port these
    //   live in `payload.other["targetNode"]` / `payload.other["targetNodeId"]`.
    public static func retrieveTargetInfo(
        _ payload: Payload?,
        _ validPayloadTypes: [String],
        _ seriesModel: SeriesModel
    ) -> TargetInfo? {
        // if (payload && zrUtil.indexOf(validPayloadTypes, payload.type) >= 0) { ... }
        guard let payload = payload, util.indexOf(validPayloadTypes, payload.type) >= 0 else {
            return nil
        }

        // const root = seriesModel.getData().tree.root;
        guard let tree = seriesModel.getData().tree else { return nil }
        let root: TreeNode = tree.root   // `root` is IUO on Tree; annotate to unwrap.

        // let targetNode = payload.targetNode;
        var targetNode: TreeNode? = nil
        // if (zrUtil.isString(targetNode)) { targetNode = root.getNodeById(targetNode); }
        if let targetNodeStr = payload.other["targetNode"] as? String {
            targetNode = root.getNodeById(targetNodeStr)
        }
        else if let node = payload.other["targetNode"] as? TreeNode {
            targetNode = node
        }

        // if (targetNode && root.contains(targetNode)) { return { node: targetNode }; }
        if let node = targetNode, root.contains(node) {
            return TargetInfo(node: node)
        }

        // const targetNodeId = payload.targetNodeId;
        // if (targetNodeId != null && (targetNode = root.getNodeById(targetNodeId))) { return { node }; }
        if let targetNodeId = payload.other["targetNodeId"] as? String,
           let node = root.getNodeById(targetNodeId) {
            return TargetInfo(node: node)
        }

        return nil
    }

    // Not includes the given node at the last item.
    // export function getPathToRoot(node): TreeNode[]
    public static func getPathToRoot(_ node: TreeNode) -> [TreeNode] {
        var path: [TreeNode] = []
        var node: TreeNode? = node
        // while (node) { node = node.parentNode; node && path.push(node); }
        while let cur = node {
            node = cur.parentNode
            if let parent = node { path.append(parent) }
        }
        // return path.reverse();
        return path.reversed()
    }

    // export function aboveViewRoot(viewRoot, node): boolean
    public static func aboveViewRoot(_ viewRoot: TreeNode, _ node: TreeNode) -> Bool {
        let viewPath = getPathToRoot(viewRoot)
        // return zrUtil.indexOf(viewPath, node) >= 0;  (reference identity — TreeNode is a class)
        return viewPath.contains(where: { $0 === node })
    }

    // export function wrapTreePathInfo<T>(node, seriesModel)  — DEFERRED (see header note).
}
