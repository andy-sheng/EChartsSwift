// Ported from echarts/src/chart/graph/forceHelper.ts — keep in sync with upstream
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
* Some formulas were originally copied from "d3.js" with some
* modifications made for this project.
* (See more details in the comment of the method "step" below.)
* The use of the source code of this file is also subject to the terms
* and consitions of the license of "d3.js" (BSD-3Clause, see
* </licenses/LICENSE-d3>).
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import * as vec2 from 'zrender/src/core/vector';                 -> `vector.*` (ZRenderKit).
//   import { RectLike } from 'zrender/src/core/BoundingRect';        -> RectLike (ZRenderKit).

// const scaleAndAdd = vec2.scaleAndAdd;  — referenced as `vector.scaleAndAdd` below.

// interface InputNode / LayoutNode — merged into one reference class (JS node objects are mutated in
//   place and SHARED by reference between edges: `edge.n1 === nodes[i]`). A Swift `class` preserves
//   that reference identity, which the force step relies on when it writes back into `n.p`/`n.pp`.
public final class ForceNode {
    // p?: vec2.VectorArray
    public var p: VectorArray?
    // fixed?: boolean
    public var fixed: Bool
    /** Weight */
    // w: number
    public var w: Double
    /** Repulsion */
    // rep: number
    public var rep: Double
    // LayoutNode extras:
    // pp?: vec2.VectorArray
    public var pp: VectorArray?
    // edges?: LayoutEdge[]
    public var edges: [ForceEdge]?

    public init(w: Double, rep: Double, fixed: Bool, p: VectorArray?) {
        self.w = w
        self.rep = rep
        self.fixed = fixed
        self.p = p
        self.pp = nil
        self.edges = nil
    }
}

// interface InputEdge / LayoutEdge — reference class (see ForceNode). `n1`/`n2` reference shared nodes.
public final class ForceEdge {
    // ignoreForceLayout?: boolean
    public var ignoreForceLayout: Bool
    // n1: LayoutNode
    public var n1: ForceNode
    // n2: LayoutNode
    public var n2: ForceNode
    /** Distance */
    // d: number
    public var d: Double
    // `curveness` is carried on the edge object built by forceLayout.ts (used by its afterStep write-back).
    //   forceHelper itself does not read it; kept here so the same class serves both InputEdge and the
    //   forceLayout.ts edge literal, matching the structural typing upstream.
    public var curveness: Double

    public init(n1: ForceNode, n2: ForceNode, d: Double, curveness: Double, ignoreForceLayout: Bool) {
        self.n1 = n1
        self.n2 = n2
        self.d = d
        self.curveness = curveness
        self.ignoreForceLayout = ignoreForceLayout
    }
}

// interface LayoutCfg { gravity?, friction?, rect? }
public struct ForceLayoutCfg {
    public var gravity: Double?
    public var friction: Double?
    public var rect: RectLike?
    public init(rect: RectLike?, gravity: Double?, friction: Double?) {
        self.rect = rect
        self.gravity = gravity
        self.friction = friction
    }
}

// The object literal returned by `forceLayout` (its structural shape is the exported
// `ForceLayoutInstance` interface in forceLayout.ts). Modeled as a reference class holding the
// mutable simulation state (`friction`, the step callbacks) that the closures close over in TS.
public final class ForceLayoutInstance {
    private let nodes: [ForceNode]
    private let edges: [ForceEdge]
    private let center: [Double]
    private let gravity: Double
    private let initialFriction: Double
    private var friction: Double

    private var beforeStepCallback: (([ForceNode], [ForceEdge]) -> Void)?
    private var afterStepCallback: (([ForceNode], [ForceEdge], Bool) -> Void)?

    fileprivate init(
        nodes: [ForceNode],
        edges: [ForceEdge],
        center: [Double],
        gravity: Double,
        initialFriction: Double
    ) {
        self.nodes = nodes
        self.edges = edges
        self.center = center
        self.gravity = gravity
        self.initialFriction = initialFriction
        self.friction = initialFriction
    }

    // warmUp: function () { friction = initialFriction * 0.8; }
    public func warmUp() {
        friction = initialFriction * 0.8
    }

    // setFixed: function (idx) { nodes[idx].fixed = true; }
    public func setFixed(_ idx: Int) {
        nodes[idx].fixed = true
    }

    // setUnfixed: function (idx) { nodes[idx].fixed = false; }
    public func setUnfixed(_ idx: Int) {
        nodes[idx].fixed = false
    }

    /** Before step hook */
    // beforeStep: function (cb) { beforeStepCallback = cb; }
    public func beforeStep(_ cb: @escaping ([ForceNode], [ForceEdge]) -> Void) {
        beforeStepCallback = cb
    }
    /** After step hook */
    // afterStep: function (cb) { afterStepCallback = cb; }
    public func afterStep(_ cb: @escaping ([ForceNode], [ForceEdge], Bool) -> Void) {
        afterStepCallback = cb
    }

    /**
     * Some formulas were originally copied from "d3.js"
     * https://github.com/d3/d3/blob/b516d77fb8566b576088e73410437494717ada26/src/layout/force.js
     * with some modifications made for this project.
     * See the license statement at the head of this file.
     */
    // step: function (cb?) { ... }
    @discardableResult
    public func step(_ cb: ((Bool) -> Void)? = nil) -> Bool {
        beforeStepCallback?(nodes, edges)

        // const v12: number[] = [];
        var v12 = VectorArray()
        let nLen = nodes.count
        for i in 0..<edges.count {
            let e = edges[i]
            if e.ignoreForceLayout {
                continue
            }
            let n1 = e.n1
            let n2 = e.n2

            // vec2.sub(v12, n2.p, n1.p);
            v12 = vector.sub(n2.p!, n1.p!)
            // const d = vec2.len(v12) - e.d;
            let d = vector.len(v12) - e.d
            // let w = n2.w / (n1.w + n2.w);
            var w = n2.w / (n1.w + n2.w)

            if w.isNaN {
                w = 0
            }

            // vec2.normalize(v12, v12);
            v12 = vector.normalize(v12)

            // !n1.fixed && scaleAndAdd(n1.p, n1.p, v12, w * d * friction);
            if !n1.fixed { n1.p = vector.scaleAndAdd(n1.p!, v12, w * d * friction) }
            // !n2.fixed && scaleAndAdd(n2.p, n2.p, v12, -(1 - w) * d * friction);
            if !n2.fixed { n2.p = vector.scaleAndAdd(n2.p!, v12, -(1 - w) * d * friction) }
        }
        // Gravity
        for i in 0..<nLen {
            let n = nodes[i]
            if !n.fixed {
                // vec2.sub(v12, center, n.p);
                v12 = vector.sub(VectorArray(center[0], center[1]), n.p!)
                // scaleAndAdd(n.p, n.p, v12, gravity * friction);
                n.p = vector.scaleAndAdd(n.p!, v12, gravity * friction)
            }
        }

        // Repulsive
        // PENDING
        for i in 0..<nLen {
            let n1 = nodes[i]
            for j in (i + 1)..<nLen {
                let n2 = nodes[j]
                // vec2.sub(v12, n2.p, n1.p);
                v12 = vector.sub(n2.p!, n1.p!)
                // let d = vec2.len(v12);
                var d = vector.len(v12)
                if d == 0 {
                    // Random repulse
                    // vec2.set(v12, Math.random() - 0.5, Math.random() - 0.5);
                    //   The port bans Math.random; substitute a deterministic non-zero unit-ish offset
                    //   seeded on the outer index `i` (this only fires when two nodes exactly overlap, so
                    //   any stable non-zero direction breaks the tie identically each render).
                    v12 = vector.set(detScatter(i, 0), detScatter(i, 1))
                    d = 1
                }
                // const repFact = (n1.rep + n2.rep) / d / d;
                let repFact = (n1.rep + n2.rep) / d / d
                // !n1.fixed && scaleAndAdd(n1.pp, n1.pp, v12, repFact);
                if !n1.fixed { n1.pp = vector.scaleAndAdd(n1.pp!, v12, repFact) }
                // !n2.fixed && scaleAndAdd(n2.pp, n2.pp, v12, -repFact);
                if !n2.fixed { n2.pp = vector.scaleAndAdd(n2.pp!, v12, -repFact) }
            }
        }
        // const v: number[] = [];
        var v = VectorArray()
        for i in 0..<nLen {
            let n = nodes[i]
            if !n.fixed {
                // vec2.sub(v, n.p, n.pp);
                v = vector.sub(n.p!, n.pp!)
                // scaleAndAdd(n.p, n.p, v, friction);
                n.p = vector.scaleAndAdd(n.p!, v, friction)
                // vec2.copy(n.pp, n.p);
                n.pp = vector.copy(n.p!)
            }
        }

        // friction = friction * 0.992;
        friction = friction * 0.992

        // const finished = friction < 0.01;
        let finished = friction < 0.01

        afterStepCallback?(nodes, edges, finished)

        cb?(finished)

        return finished
    }
}

// export function forceLayout(inNodes, inEdges, opts) { ... }
public func forceLayout(
    _ inNodes: [ForceNode],
    _ inEdges: [ForceEdge],
    _ opts: ForceLayoutCfg
) -> ForceLayoutInstance {
    // const nodes = inNodes as LayoutNode[]; const edges = inEdges as LayoutEdge[];
    let nodes = inNodes
    let edges = inEdges
    // const rect = opts.rect;
    let rect = opts.rect!
    let width = rect.width
    let height = rect.height
    // const center = [rect.x + width / 2, rect.y + height / 2];
    let center = [rect.x + width / 2, rect.y + height / 2]
    // const gravity = opts.gravity == null ? 0.1 : opts.gravity;
    let gravity = opts.gravity == nil ? 0.1 : opts.gravity!

    // Init position
    for i in 0..<nodes.count {
        let n = nodes[i]
        if n.p == nil {
            // n.p = vec2.create(
            //     width * (Math.random() - 0.5) + center[0],
            //     height * (Math.random() - 0.5) + center[1]
            // );
            //   The port bans Math.random/Date; substitute a deterministic low-discrepancy scatter seeded
            //   on the node index `i` so the (initLayout-less) start state — and therefore the settled
            //   static layout — is reproducible across renders. Faithful to the upstream INTENT (a spread
            //   initial cloud around the view center); the exact node coordinates differ from echarts.js
            //   because the seed is deterministic instead of random.
            n.p = vector.create(
                width * detScatter(i, 0) + center[0],
                height * detScatter(i, 1) + center[1]
            )
        }
        // n.pp = vec2.clone(n.p);
        n.pp = vector.clone(n.p!)
        // n.edges = null;
        n.edges = nil
    }

    // const initialFriction = opts.friction == null ? 0.6 : opts.friction;
    let initialFriction = opts.friction == nil ? 0.6 : opts.friction!

    return ForceLayoutInstance(
        nodes: nodes,
        edges: edges,
        center: center,
        gravity: gravity,
        initialFriction: initialFriction
    )
}

// MARK: - Port helpers (not upstream symbols)

// Deterministic replacement for `Math.random() - 0.5`, seeded on an integer index and an axis (0/1).
//   Two decorrelated additive-recurrence (Weyl / golden-ratio) sequences give a well-spread, stable
//   scatter in [-0.5, 0.5). The port bans Math.random/Date.now (see PORT_STATUS); this keeps the force
//   simulation's initial cloud + degenerate-overlap tiebreak fully reproducible.
private func detScatter(_ i: Int, _ axis: Int) -> Double {
    // 1/phi and 1/phi^2 for the plastic/golden constants — irrational, low-discrepancy.
    let alpha = axis == 0 ? 0.6180339887498949 : 0.3819660112501051
    let x = (Double(i) + 1.0) * alpha
    return (x - x.rounded(.down)) - 0.5
}
