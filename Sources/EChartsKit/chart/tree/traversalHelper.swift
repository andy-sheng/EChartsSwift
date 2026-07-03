// Ported from echarts/src/chart/tree/traversalHelper.ts — keep in sync with upstream
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

// upstream imports:
//   import { TreeNode } from '../../data/Tree';  -> TreeNode (data/Tree.swift, sibling track).

// upstream free-function module `traversalHelper` -> caseless enum namespace (CONVENTIONS §1).
public enum traversalHelper {

    /**
     * Traverse the tree from bottom to top and do something
     */
    // function eachAfter<T>(root, callback: (node, separation: T) => void, separation: T)
    public static func eachAfter<T>(
        _ root: TreeNode,
        _ callback: (TreeNode, T) -> Void,
        _ separation: T
    ) {
        var nodes: [TreeNode] = [root]
        var next: [TreeNode] = []

        // while (node = nodes.pop()) { ... } — nodes are objects (always truthy), so pop-until-empty.
        while let node = nodes.popLast() {
            next.append(node)
            if node.isExpand {
                let children = node.children
                if !children.isEmpty {
                    for i in 0..<children.count {
                        nodes.append(children[i])
                    }
                }
            }
        }

        while let node = next.popLast() {
            callback(node, separation)
        }
    }

    /**
     * Traverse the tree from top to bottom and do something
     */
    // function eachBefore(root, callback: (node) => void)
    public static func eachBefore(
        _ root: TreeNode,
        _ callback: (TreeNode) -> Void
    ) {
        var nodes: [TreeNode] = [root]
        while let node = nodes.popLast() {
            callback(node)
            if node.isExpand {
                let children = node.children
                if !children.isEmpty {
                    for i in stride(from: children.count - 1, through: 0, by: -1) {
                        nodes.append(children[i])
                    }
                }
            }
        }
    }
}
