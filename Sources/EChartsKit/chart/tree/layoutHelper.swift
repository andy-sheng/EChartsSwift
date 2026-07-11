// Ported from echarts/src/chart/tree/layoutHelper.ts — keep in sync with upstream
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

/*
* A third-party license is embedded for some of the code in this file:
* The tree layoutHelper implementation was originally copied from
* "d3.js"(https://github.com/d3/d3-hierarchy) with
* some modifications made for this project.
* (see more details in the comment of the specific method below.)
* The use of the source code of this file is also subject to the terms
* and consitions of the licence of "d3.js" (BSD-3Clause, see
* </licenses/LICENSE-d3>).
*/

/**
 * @file The layout algorithm of node-link tree diagrams. Here we using Reingold-Tilford algorithm to drawing
 *       the tree.
 */

import Foundation

// upstream imports:
//   import { TreeNode } from '../../data/Tree';  -> TreeNode (data/Tree.swift, sibling track).

// interface HierNode { defaultAncestor; ancestor; prelim; modifier; change; shift; i; thread }
// PORT: upstream `hierNode` is a plain JS object attached to each node and mutated in place.
//   Modeled as a `final class` (reference semantics, mutated in place like the JS object). See the
//   `TreeNode.hierNode` extension below for how it is attached to a node.
public final class HierNode {
    // PORT-NOTE: upstream `defaultAncestor: TreeLayoutNode` is initialized to `null`; modeled Optional.
    public var defaultAncestor: TreeNode?
    public var ancestor: TreeNode
    public var prelim: Double = 0
    public var modifier: Double = 0
    public var change: Double = 0
    public var shift: Double = 0
    public var i: Double = 0
    // PORT-NOTE: upstream `thread: TreeLayoutNode` is initialized to `null`; modeled Optional.
    public var thread: TreeNode?

    public init(defaultAncestor: TreeNode?, ancestor: TreeNode, i: Double, thread: TreeNode?) {
        self.defaultAncestor = defaultAncestor
        self.ancestor = ancestor
        self.i = i
        self.thread = thread
    }
}

// upstream `interface SeparationFunc { (node1, node2): number }`.
public typealias SeparationFunc = (TreeNode, TreeNode) -> Double

// PORT: upstream `interface TreeLayoutNode extends TreeNode { parentNode; hierNode; children }` is a
//   compile-time widening of `TreeNode` with an added `hierNode` field. `TreeNode` is a `final class`
//   (Tree.swift) that cannot be subclassed, so the added field lives in a side table keyed by node
//   identity (the same pattern as util/layout's `_newlineInner`), surfaced as a computed property so
//   call sites read exactly like upstream (`node.hierNode.prelim`).
private var _hierNodeStore: [ObjectIdentifier: HierNode] = [:]

extension TreeNode {
    var hierNode: HierNode {
        get { _hierNodeStore[ObjectIdentifier(self)]! }
        set { _hierNodeStore[ObjectIdentifier(self)] = newValue }
    }
}

// upstream free-function module `layoutHelper` -> caseless enum namespace (CONVENTIONS §1).
public enum layoutHelper {

    /**
     * Initialize all computational message for following algorithm.
     */
    // PORT: upstream `init` — kept verbatim via backticks (`init` is a Swift keyword).
    public static func `init`(_ inRoot: TreeNode) {
        let root = inRoot
        root.hierNode = HierNode(
            defaultAncestor: nil,
            ancestor: root,
            i: 0,
            thread: nil
        )

        var nodes: [TreeNode] = [root]

        // while (node = nodes.pop()) { ... }
        while let node = nodes.popLast() {
            let children = node.children
            if node.isExpand && !children.isEmpty {
                let n = children.count
                var i = n - 1
                while i >= 0 {
                    let child = children[i]
                    child.hierNode = HierNode(
                        defaultAncestor: nil,
                        ancestor: child,
                        i: Double(i),
                        thread: nil
                    )
                    nodes.append(child)
                    i -= 1
                }
            }
        }
    }

    /**
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     *
     * Computes a preliminary x coordinate for node. Before that, this function is
     * applied recursively to the children of node, as well as the function
     * apportion(). After spacing out the children by calling executeShifts(), the
     * node is placed to the midpoint of its outermost children.
     */
    public static func firstWalk(_ node: TreeNode, _ separation: SeparationFunc) {
        let children = node.isExpand ? node.children : []
        let siblings = node.parentNode!.children
        // const subtreeW = node.hierNode.i ? siblings[node.hierNode.i - 1] : null;
        //   JS `node.hierNode.i` is falsy when 0 (first child) -> null.
        let subtreeW: TreeNode? = node.hierNode.i != 0 ? siblings[Int(node.hierNode.i) - 1] : nil
        if !children.isEmpty {
            executeShifts(node)
            let midPoint = (children[0].hierNode.prelim + children[children.count - 1].hierNode.prelim) / 2
            if let subtreeW = subtreeW {
                node.hierNode.prelim = subtreeW.hierNode.prelim + separation(node, subtreeW)
                node.hierNode.modifier = node.hierNode.prelim - midPoint
            }
            else {
                node.hierNode.prelim = midPoint
            }
        }
        else if let subtreeW = subtreeW {
            node.hierNode.prelim = subtreeW.hierNode.prelim + separation(node, subtreeW)
        }
        // node.parentNode.hierNode.defaultAncestor = apportion(
        //     node, subtreeW, node.parentNode.hierNode.defaultAncestor || siblings[0], separation);
        //   JS `||`: a null defaultAncestor falls through to siblings[0].
        node.parentNode!.hierNode.defaultAncestor = apportion(
            node,
            subtreeW,
            node.parentNode!.hierNode.defaultAncestor ?? siblings[0],
            separation
        )
    }

    /**
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     *
     * Computes all real x-coordinates by summing up the modifiers recursively.
     */
    public static func secondWalk(_ node: TreeNode) {
        let nodeX = node.hierNode.prelim + node.parentNode!.hierNode.modifier
        node.setLayout(["x": nodeX], true)
        node.hierNode.modifier += node.parentNode!.hierNode.modifier
    }

    // export function separation(cb?): arguments.length ? cb : defaultSeparation
    //   Two overloads reproduce `arguments.length` at the two call sites (`sep()` / `sep(fn)`).
    public static func separation() -> SeparationFunc {
        return defaultSeparation
    }
    public static func separation(_ cb: @escaping SeparationFunc) -> SeparationFunc {
        return cb
    }

    /**
     * Transform the common coordinate to radial coordinate.
     */
    public static func radialCoordinate(_ rad: Double, _ r: Double) -> (x: Double, y: Double) {
        let rad = rad - Double.pi / 2
        return (
            x: r * cos(rad),
            y: r * sin(rad)
        )
    }

    /**
     * All other shifts, applied to the smaller subtrees between w- and w+, are
     * performed by this function.
     *
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     */
    static func executeShifts(_ node: TreeNode) {
        let children = node.children
        var n = children.count
        var shift: Double = 0
        var change: Double = 0
        // while (--n >= 0) { ... }
        while true {
            n -= 1
            if n < 0 { break }
            let child = children[n]
            child.hierNode.prelim += shift
            child.hierNode.modifier += shift
            change += child.hierNode.change
            shift += child.hierNode.shift + change
        }
    }

    /**
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     *
     * The core of the algorithm. Here, a new subtree is combined with the
     * previous subtrees. Threads are used to traverse the inside and outside
     * contours of the left and right subtree up to the highest common level.
     * Whenever two nodes of the inside contours conflict, we compute the left
     * one of the greatest uncommon ancestors using the function nextAncestor()
     * and call moveSubtree() to shift the subtree and prepare the shifts of
     * smaller subtrees. Finally, we add a new thread (if necessary).
     */
    static func apportion(
        _ subtreeV: TreeNode,
        _ subtreeW: TreeNode?,
        _ ancestor: TreeNode,
        _ separation: SeparationFunc
    ) -> TreeNode {
        var ancestor = ancestor

        if let subtreeW = subtreeW {
            var nodeOutRight: TreeNode = subtreeV
            var nodeInRight: TreeNode? = subtreeV
            var nodeOutLeft: TreeNode = nodeInRight!.parentNode!.children[0]
            var nodeInLeft: TreeNode? = subtreeW

            var sumOutRight = nodeOutRight.hierNode.modifier
            var sumInRight = nodeInRight!.hierNode.modifier
            var sumOutLeft = nodeOutLeft.hierNode.modifier
            var sumInLeft = nodeInLeft!.hierNode.modifier

            // while (nodeInLeft = nextRight(nodeInLeft), nodeInRight = nextLeft(nodeInRight),
            //        nodeInLeft && nodeInRight) { ... }
            while true {
                nodeInLeft = nextRight(nodeInLeft!)
                nodeInRight = nextLeft(nodeInRight!)
                guard let curInLeft = nodeInLeft, let curInRight = nodeInRight else {
                    break
                }

                // nodeOutRight/nodeOutLeft stay on the same depth as the inner contours, so upstream
                // relies on them being non-null here (never checks). Force-unwrap to match.
                nodeOutRight = nextRight(nodeOutRight)!
                nodeOutLeft = nextLeft(nodeOutLeft)!
                nodeOutRight.hierNode.ancestor = subtreeV
                let shift = curInLeft.hierNode.prelim + sumInLeft - curInRight.hierNode.prelim
                        - sumInRight + separation(curInLeft, curInRight)
                if shift > 0 {
                    moveSubtree(nextAncestor(curInLeft, subtreeV, ancestor), subtreeV, shift)
                    sumInRight += shift
                    sumOutRight += shift
                }
                sumInLeft += curInLeft.hierNode.modifier
                sumInRight += curInRight.hierNode.modifier
                sumOutRight += nodeOutRight.hierNode.modifier
                sumOutLeft += nodeOutLeft.hierNode.modifier
            }
            if nodeInLeft != nil && nextRight(nodeOutRight) == nil {
                nodeOutRight.hierNode.thread = nodeInLeft
                nodeOutRight.hierNode.modifier += sumInLeft - sumOutRight
            }
            if nodeInRight != nil && nextLeft(nodeOutLeft) == nil {
                nodeOutLeft.hierNode.thread = nodeInRight
                nodeOutLeft.hierNode.modifier += sumInRight - sumOutLeft
                ancestor = subtreeV
            }
        }
        return ancestor
    }

    /**
     * This function is used to traverse the right contour of a subtree.
     * It returns the rightmost child of node or the thread of node. The function
     * returns null if and only if node is on the highest depth of its subtree.
     */
    static func nextRight(_ node: TreeNode) -> TreeNode? {
        let children = node.children
        return (!children.isEmpty && node.isExpand) ? children[children.count - 1] : node.hierNode.thread
    }

    /**
     * This function is used to traverse the left contour of a subtree (or a subforest).
     * It returns the leftmost child of node or the thread of node. The function
     * returns null if and only if node is on the highest depth of its subtree.
     */
    static func nextLeft(_ node: TreeNode) -> TreeNode? {
        let children = node.children
        return (!children.isEmpty && node.isExpand) ? children[0] : node.hierNode.thread
    }

    /**
     * If nodeInLeft’s ancestor is a sibling of node, returns nodeInLeft’s ancestor.
     * Otherwise, returns the specified ancestor.
     */
    static func nextAncestor(
        _ nodeInLeft: TreeNode,
        _ node: TreeNode,
        _ ancestor: TreeNode
    ) -> TreeNode {
        return nodeInLeft.hierNode.ancestor.parentNode === node.parentNode
            ? nodeInLeft.hierNode.ancestor : ancestor
    }

    /**
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     *
     * Shifts the current subtree rooted at wr.
     * This is done by increasing prelim(w+) and modifier(w+) by shift.
     */
    static func moveSubtree(
        _ wl: TreeNode,
        _ wr: TreeNode,
        _ shift: Double
    ) {
        let change = shift / (wr.hierNode.i - wl.hierNode.i)
        wr.hierNode.change -= change
        wr.hierNode.shift += shift
        wr.hierNode.modifier += shift
        wr.hierNode.prelim += shift
        wl.hierNode.change += change
    }

    /**
     * The implementation of this function was originally copied from "d3.js"
     * <https://github.com/d3/d3-hierarchy/blob/4c1f038f2725d6eae2e49b61d01456400694bac4/src/tree.js>
     * with some modifications made for this program.
     * See the license statement at the head of this file.
     */
    static func defaultSeparation(_ node1: TreeNode, _ node2: TreeNode) -> Double {
        return node1.parentNode === node2.parentNode ? 1 : 2
    }
}
