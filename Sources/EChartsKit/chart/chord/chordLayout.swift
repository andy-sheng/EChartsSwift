// Ported from echarts/src/chart/chord/chordLayout.ts — keep in sync with upstream
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
//   import { normalizeArcAngles } from 'zrender/src/core/PathProxy';
//       -> `normalizeArcAngles` (free func in ZRenderKit, Core/PathProxy.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import ChordSeriesModel, { SERIES_TYPE_CHORD } from './ChordSeries';
//       -> ChordSeriesModel / `SERIES_TYPE_CHORD` (sibling ChordSeries.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { getCircleLayout } from '../../util/layout';             -> `layout.getCircleLayout` (util/layout.swift).
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import { CircleLayoutOptionMixin, SeriesOption } from '../../util/types'; -> util/types.swift (typing only).
//   import { createSimpleOverallStageHandler } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` (util/modelUtil.swift).

// const RADIAN = Math.PI / 180;
private let RADIAN = Double.pi / 180

// upstream:
//   export const chordCircularLayoutStageHandler = createSimpleOverallStageHandler(
//       SERIES_TYPE_CHORD, chordCircularLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `chordCircularLayout` is `(ecModel, api)` (2-arg). Adapt with a thin
// wrapper that drops the (unused) payload, keeping `chordCircularLayout` byte-faithful below (see sankeyLayout).
public let chordCircularLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_CHORD,
    { ecModel, api, _ in chordCircularLayout(ecModel, api) }
)

// Exposed for the driver to call directly (mirrors sankeyLayout), matching upstream's module-private
// `function chordCircularLayout(ecModel, api)`.
public func chordCircularLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    ecModel.eachSeriesByType(SERIES_TYPE_CHORD) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: ChordSeriesModel`.
        let seriesModel = seriesModelBase as! ChordSeriesModel
        chordLayout(seriesModel, api)
    }
}

private func chordLayout(_ seriesModel: ChordSeriesModel, _ api: ExtensionAPI) {
    let nodeData = seriesModel.getData()
    // SeriesData.graph is typed `Graph?`; force-unwrap to the ported Graph. Faithful to
    //   upstream's non-optional typing — createGraphFromNodeEdge guarantees it for chord, like sankey/graph.
    let nodeGraph: Graph = nodeData.graph!
    let edgeData = seriesModel.getEdgeData()
    let edgeCount = edgeData.count()

    if edgeCount == 0 {
        return
    }

    let circle = layout.getCircleLayout(seriesModel, api)
    let cx = circle.cx
    let cy = circle.cy
    let r = circle.r
    let r0 = circle.r0

    // `padAngle` / `minAngle` are option reads (Int-boxed defaults) with a JS `|| 0` fallback — coerce
    //   through chordNumOr0 (falsy -> 0), never a bare `as? Double`.
    var padAngle = Swift.max(chordNumOr0(seriesModel.get("padAngle")) * RADIAN, 0)
    var minAngle = Swift.max(chordNumOr0(seriesModel.get("minAngle")) * RADIAN, 0)
    // const startAngle = -seriesModel.get('startAngle') * RADIAN;
    let startAngle = -clNum(seriesModel.get("startAngle")) * RADIAN
    let endAngle = startAngle + Double.pi * 2
    // const clockwise = seriesModel.get('clockwise');
    let clockwise = jsBool(seriesModel.get("clockwise"))
    let dir: Double = clockwise ? 1 : -1

    // Normalize angles
    var angles = [startAngle, endAngle]
    normalizeArcAngles(&angles, !clockwise)
    let normalizedStartAngle = angles[0]
    let normalizedEndAngle = angles[1]
    let totalAngle = normalizedEndAngle - normalizedStartAngle

    let allZero = nodeData.getSum("value") == 0 && edgeData.getSum("value") == 0

    // Sum of each node's edge values
    // upstream uses a sparse JS array `nodeValues[]`; modeled as `[Int: Double]` so the `|| 0` default reads
    //   line-for-line.
    var nodeValues: [Int: Double] = [:]
    var renderedNodeCount = 0.0
    nodeGraph.eachEdge { edge, _ in
        // All links use the same value 1 when allZero is true
        let value = allZero ? 1 : clNum(edge.getValue("value"))
        if allZero && (value > 0 || minAngle != 0) {
            // When allZero is true, angle is in direct proportion to number
            // of links both in and out of the node.
            renderedNodeCount += 2
        }
        let node1Index = edge.node1.dataIndex
        let node2Index = edge.node2.dataIndex
        nodeValues[node1Index] = (orZero(nodeValues[node1Index])) + value
        nodeValues[node2Index] = (orZero(nodeValues[node2Index])) + value
    }

    // Update nodeValues with data.value if exists
    var nodeValueSum = 0.0
    nodeGraph.eachNode { node, _ in
        let dataValue = clNum(node.getValue("value"))
        if !dataValue.isNaN {
            nodeValues[node.dataIndex] = Swift.max(dataValue, orZero(nodeValues[node.dataIndex]))
        }
        if !allZero && ((orZero(nodeValues[node.dataIndex])) > 0 || minAngle != 0) {
            // When allZero is false, angle is in direct proportion to node's
            // value
            renderedNodeCount += 1
        }
        nodeValueSum += orZero(nodeValues[node.dataIndex])
    }

    if renderedNodeCount == 0 || nodeValueSum == 0 {
        return
    }
    if padAngle * renderedNodeCount >= Swift.abs(totalAngle) {
        // Not enough angle to render the pad, minAngle has higher priority, and padAngle takes the rest
        padAngle = Swift.max(0, (Swift.abs(totalAngle) - minAngle * renderedNodeCount) / renderedNodeCount)
    }
    if (padAngle + minAngle) * renderedNodeCount >= Swift.abs(totalAngle) {
        // Not enough angle to render the minAngle, so ignore the minAngle
        minAngle = (Swift.abs(totalAngle) - padAngle * renderedNodeCount) / renderedNodeCount
    }

    let unitAngle = (totalAngle - padAngle * renderedNodeCount * dir)
        / nodeValueSum

    var totalDeficit = 0.0 // sum of deficits of nodes with span < minAngle
    var totalSurplus = 0.0 // sum of (spans - minAngle) of nodes with span > minAngle
    var totalSurplusSpan = 0.0 // sum of spans of nodes with span > minAngle
    var minSurplus = Double.infinity // min of (spans - minAngle) of nodes with span > minAngle
    nodeGraph.eachNode { node, _ in
        let value = orZero(nodeValues[node.dataIndex])
        let spanAngle = unitAngle * (nodeValueSum != 0 ? value : 1) * dir
        if Swift.abs(spanAngle) < minAngle {
            totalDeficit += minAngle - Swift.abs(spanAngle)
        }
        else {
            minSurplus = Swift.min(minSurplus, Swift.abs(spanAngle) - minAngle)
            totalSurplus += Swift.abs(spanAngle) - minAngle
            totalSurplusSpan += Swift.abs(spanAngle)
        }
        node.setLayout([
            "angle": spanAngle,
            "value": value
        ])
    }
    _ = minSurplus // upstream assigns `minSurplus` but never reads it afterward.

    var surplusAsMuchAsPossible = false
    if totalDeficit > totalSurplus {
        // Not enough angle to spread the nodes, scale all
        let scale = totalDeficit / totalSurplus
        nodeGraph.eachNode { node, _ in
            let spanAngle = lget(node.getLayout(), "angle")
            if Swift.abs(spanAngle) >= minAngle {
                node.setLayout([
                    "angle": spanAngle * scale,
                    "ratio": scale
                ], true)
            }
            else {
                node.setLayout([
                    "angle": minAngle,
                    "ratio": minAngle == 0 ? 1 : spanAngle / minAngle
                ], true)
            }
        }
    }
    else {
        // For example, if totalDeficit is 60 degrees and totalSurplus is 70
        // degrees but one of the sector can only reduced by 1 degree,
        // if we decrease it with the ratio of value to other surplused nodes,
        // it will have smaller angle than minAngle itself.
        // So we need to borrow some angle from other nodes.
        nodeGraph.eachNode { node, _ in
            if surplusAsMuchAsPossible {
                return
            }
            let spanAngle = lget(node.getLayout(), "angle")
            let borrowRatio = Swift.min(spanAngle / totalSurplusSpan, 1)
            let borrowAngle = borrowRatio * totalDeficit
            if spanAngle - borrowAngle < minAngle {
                // It will have less than minAngle after borrowing
                surplusAsMuchAsPossible = true
            }
        }
    }

    var restDeficit = totalDeficit
    nodeGraph.eachNode { node, _ in
        if restDeficit <= 0 {
            return
        }

        let spanAngle = lget(node.getLayout(), "angle")
        if spanAngle > minAngle && minAngle > 0 {
            let borrowRatio = surplusAsMuchAsPossible
                ? 1
                : Swift.min(spanAngle / totalSurplusSpan, 1)
            let maxBorrowAngle = spanAngle - minAngle
            let borrowAngle = Swift.min(maxBorrowAngle,
                Swift.min(restDeficit, totalDeficit * borrowRatio)
            )
            restDeficit -= borrowAngle
            node.setLayout([
                "angle": spanAngle - borrowAngle,
                "ratio": (spanAngle - borrowAngle) / spanAngle
            ], true)
        }
        else if minAngle > 0 {
            node.setLayout([
                "angle": minAngle,
                "ratio": spanAngle == 0 ? 1 : minAngle / spanAngle
            ], true)
        }
    }

    var angle = normalizedStartAngle
    var edgeAccAngle: [Int: Double] = [:]
    nodeGraph.eachNode { node, _ in
        let spanAngle = Swift.max(lget(node.getLayout(), "angle"), minAngle)
        node.setLayout([
            "cx": cx,
            "cy": cy,
            "r0": r0,
            "r": r,
            "startAngle": angle,
            "endAngle": angle + spanAngle * dir,
            "clockwise": clockwise
        ], true)
        edgeAccAngle[node.dataIndex] = angle
        angle += (spanAngle + padAngle) * dir
    }

    nodeGraph.eachEdge { edge, _ in
        let value = allZero ? 1 : clNum(edge.getValue("value"))
        let spanAngle = unitAngle * (nodeValueSum != 0 ? value : 1) * dir

        let node1Index = edge.node1.dataIndex
        let sStartAngle = edgeAccAngle[node1Index] ?? 0
        let sSpan = Swift.abs(lnumOr(edge.node1.getLayout(), "ratio", 1) * spanAngle)
        let sEndAngle = sStartAngle + sSpan * dir
        let s1 = [
            cx + r0 * cos(sStartAngle),
            cy + r0 * sin(sStartAngle)
        ]
        let s2 = [
            cx + r0 * cos(sEndAngle),
            cy + r0 * sin(sEndAngle)
        ]

        let node2Index = edge.node2.dataIndex
        let tStartAngle = edgeAccAngle[node2Index] ?? 0
        let tSpan = Swift.abs(lnumOr(edge.node2.getLayout(), "ratio", 1) * spanAngle)
        let tEndAngle = tStartAngle + tSpan * dir
        let t1 = [
            cx + r0 * cos(tStartAngle),
            cy + r0 * sin(tStartAngle)
        ]
        let t2 = [
            cx + r0 * cos(tEndAngle),
            cy + r0 * sin(tEndAngle)
        ]

        edge.setLayout([
            "s1": s1,
            "s2": s2,
            "sStartAngle": sStartAngle,
            "sEndAngle": sEndAngle,
            "t1": t1,
            "t2": t2,
            "tStartAngle": tStartAngle,
            "tEndAngle": tEndAngle,
            "cx": cx,
            "cy": cy,
            "r": r0,
            "value": value,
            "clockwise": clockwise
        ])

        edgeAccAngle[node1Index] = sEndAngle
        edgeAccAngle[node2Index] = tEndAngle
    }
}

// ─── JS coercion / option-read shims (not upstream symbols) ───────────────────────────────────────

// TRAP (1): `[String: Any]` defaultOptions store numbers as bare Int literals (startAngle: 90, padAngle: 0,
//   minAngle: 0, ...). `as? Double` returns nil on an Int and SILENTLY DROPS the value. Read every numeric
//   option / value through these helpers (Int | Double | NSNumber | numeric-String -> Double).
// JS `nodeValues[i] || 0`: a nil OR NaN read coerces to 0 (a value-less link makes the
// accumulator NaN; upstream `|| 0` sheds it each read, so nodeValueSum/unitAngle stay finite).
private func orZero(_ v: Double?) -> Double {
    guard let v = v, !v.isNaN else { return 0 }
    return v
}

private func clNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

// Models the JS `(seriesModel.get(...) || 0)` falsy fallback: 0 / NaN / null / undefined -> 0.
private func chordNumOr0(_ v: Any?) -> Double {
    let d = clNum(v)
    return (d != 0 && !d.isNaN) ? d : 0
}

// Reads a numeric field out of a node/edge layout dict (`node.getLayout().<key>`). JS `undefined`
//   participating in arithmetic yields NaN, so a missing key returns NaN to match.
private func lget(_ layout: Any?, _ key: String) -> Double {
    guard let dict = layout as? [String: Any] else { return Double.nan }
    return clNum(dict[key])
}

// Reads a numeric layout field with the JS `x || fallback` falsy fallback (used for `getLayout().ratio || 1`).
private func lnumOr(_ layout: Any?, _ key: String, _ fallback: Double) -> Double {
    let d = lget(layout, key)
    return (d != 0 && !d.isNaN) ? d : fallback
}

// Mirrors JS truthiness for `const clockwise = seriesModel.get('clockwise')` used as `clockwise ? 1 : -1`
//   (nil / NSNull / false / 0 / NaN / "" -> falsy).
private func jsBool(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
