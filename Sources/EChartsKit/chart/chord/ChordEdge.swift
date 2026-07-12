// Ported from echarts/src/chart/chord/ChordEdge.ts — keep in sync with upstream
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
//   import type { PathProps, PathStyleProps } from 'zrender/src/graphic/Path'; -> ZRenderKit `PathProps` / `PathStyleProps`.
//   import type PathProxy from 'zrender/src/core/PathProxy';       -> ZRenderKit `PathProxy`.
//   import { extend, isString } from 'zrender/src/core/util';      -> shape-from-layout build + `isString` bridge (see below).
//   import * as graphic from '../../util/graphic';                 -> ZRenderKit `Path` / `LinearGradient`;
//       `graphic.updateProps` is ported (animation/basicTransition.swift); wiring the enter/update
//       ribbon transition into this static-render view is DEFERRED by design (see PORT-NOTE in updateData).
//   import SeriesData from '../../data/SeriesData';                -> `SeriesData`.
//   import { GraphEdge } from '../../data/Graph';                  -> data/Graph.swift `GraphEdge`.
//   import type Model from '../../model/Model';                    -> `Model`.
//   import { getSectorCornerRadius } from '../helper/sectorHelper';-> `getSectorCornerRadius`
//       (only consumed by the `extend(cornerRadius, layout)` merge — cornerRadius is not used by buildPath).
//   import { saveOldStyle } from '../../animation/basicTransition'; -> PORT-NOTE: animation/basicTransition.swift
//       IS ported (saveOldStyle/updateProps available), but this static-render view applies the target
//       shape directly, so the enter/update transition is intentionally not wired (see updateData).
//   import ChordSeriesModel, { ChordEdgeItemOption, ChordEdgeLineStyleOption, ChordNodeItemOption } from './ChordSeries';
//       -> sibling `ChordSeriesModel` (assumed ported alongside — the ChordSeries.swift port).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> util/states.swift (`states.setStatesStylesFromModel` / `states.toggleHoverEmphasis`), wired in updateData.
//   import { getECData } from '../../util/innerStore';             -> `innerStore.getECData`.

// ================================================================================================
// upstream: export class ChordPathShape { s1, s2, sStartAngle, sEndAngle, t1, t2, tStartAngle,
//   tEndAngle, cx, cy, r, clockwise }
//   The edge RIBBON parameter bag → `struct` conforming to the `PathShape` marker (CONVENTIONS §4;
//   see SankeyPathShape / PointerShape). `s1/s2` are the two source-arc endpoints, `t1/t2` the two
//   target-arc endpoints (each a `[x, y]` pair → `[Double]` of length 2). `r` is `series.r0`.
// ================================================================================================
public struct ChordPathShape: PathShape {
    // Souce node, two points forming an arc
    public var s1: [Double] = [0, 0]
    public var s2: [Double] = [0, 0]
    public var sStartAngle: Double = 0
    public var sEndAngle: Double = 0

    // Target node, two points forming an arc
    public var t1: [Double] = [0, 0]
    public var t2: [Double] = [0, 0]
    public var tStartAngle: Double = 0
    public var tEndAngle: Double = 0

    public var cx: Double = 0
    public var cy: Double = 0
    // series.r0 of ChordSeries
    public var r: Double = 0

    public var clockwise: Bool = true

    public init() {}

    // Keyed access for animateTo({shape: {...}}). Exposes the tweenable fields (the two endpoint pairs,
    //   the four arc angles, the center, and the radius). `clockwise` is a mode flag, not tweened.
    // PORT-NOTE (deferred): upstream animates the ribbon via these fields; the enter/update transition
    //   is intentionally not wired in this static-render view, but the keyed seam is provided for parity
    //   with sibling shapes (and for when the transition is wired via updateProps).
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "s1": return s1
        case "s2": return s2
        case "sStartAngle": return sStartAngle
        case "sEndAngle": return sEndAngle
        case "t1": return t1
        case "t2": return t2
        case "tStartAngle": return tStartAngle
        case "tEndAngle": return tEndAngle
        case "cx": return cx
        case "cy": return cy
        case "r": return r
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "s1": if let v = value as? [Double] { s1 = v }
        case "s2": if let v = value as? [Double] { s2 = v }
        case "sStartAngle": if let v = value as? Double { sStartAngle = v }
        case "sEndAngle": if let v = value as? Double { sEndAngle = v }
        case "t1": if let v = value as? [Double] { t1 = v }
        case "t2": if let v = value as? [Double] { t2 = v }
        case "tStartAngle": if let v = value as? Double { tStartAngle = v }
        case "tEndAngle": if let v = value as? Double { tEndAngle = v }
        case "cx": if let v = value as? Double { cx = v }
        case "cy": if let v = value as? Double { cy = v }
        case "r": if let v = value as? Double { r = v }
        default: break
        }
    }
}

// upstream: interface ChordEdgePathProps extends PathProps { shape?: Partial<ChordPathShape> }
// PORT-NOTE: typed-interface fidelity dropped — PathProps is the dynamic `[String: Any]` prop bag; the
//   `shape?` field is set via the `"shape"` key (see Path._init).
public typealias ChordEdgePathProps = PathProps

// upstream: export class ChordEdge extends graphic.Path<ChordEdgePathProps>
//   The edge RIBBON: a FILLED closed path tracing the source arc, a cubic bezier across to the target
//   arc, the target arc, then a cubic bezier back — closed. Same idea as SankeyPath, but between two
//   CIRCLE ARCS instead of two straight bands.
public final class ChordEdge: Path {

    // upstream: shape: ChordPathShape — narrows the inherited `shape: PathShape!`.

    // upstream: constructor(nodeData, edgeData, edgeIdx, startAngle)
    public init(
        _ nodeData: SeriesData,
        _ edgeData: SeriesData,
        _ edgeIdx: Int,
        _ startAngle: Double
    ) {
        super.init()
        // getECData(this).dataType = 'edge';
        innerStore.getECData(self).dataType = .edge
        // this.updateData(nodeData, edgeData, edgeIdx, startAngle, true);
        self.updateData(nodeData, edgeData, edgeIdx, startAngle, true)
    }

    // upstream: getDefaultShape() (implicit — new ChordPathShape())
    public override func getDefaultShape() -> PathShape {
        return ChordPathShape()
    }

    // upstream: buildPath(ctx: PathProxy | CanvasRenderingContext2D, shape: ChordPathShape): void
    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        let shape = shapeIn as! ChordPathShape

        // Start from n11
        // ctx.moveTo(shape.s1[0], shape.s1[1]);
        _ = ctx.moveTo(shape.s1[0], shape.s1[1])

        let ratio = 0.7
        let clockwise = shape.clockwise

        // Draw the arc from n11 to n12
        // ctx.arc(shape.cx, shape.cy, shape.r, shape.sStartAngle, shape.sEndAngle, !clockwise);
        _ = ctx.arc(shape.cx, shape.cy, shape.r, shape.sStartAngle, shape.sEndAngle, !clockwise)

        // Bezier curve to cp1 and then to n21
        _ = ctx.bezierCurveTo(
            (shape.cx - shape.s2[0]) * ratio + shape.s2[0],
            (shape.cy - shape.s2[1]) * ratio + shape.s2[1],
            (shape.cx - shape.t1[0]) * ratio + shape.t1[0],
            (shape.cy - shape.t1[1]) * ratio + shape.t1[1],
            shape.t1[0],
            shape.t1[1]
        )

        // Draw the arc from n21 to n22
        // ctx.arc(shape.cx, shape.cy, shape.r, shape.tStartAngle, shape.tEndAngle, !clockwise);
        _ = ctx.arc(shape.cx, shape.cy, shape.r, shape.tStartAngle, shape.tEndAngle, !clockwise)

        // Bezier curve back to cp2 and then to n11
        _ = ctx.bezierCurveTo(
            (shape.cx - shape.t2[0]) * ratio + shape.t2[0],
            (shape.cy - shape.t2[1]) * ratio + shape.t2[1],
            (shape.cx - shape.s1[0]) * ratio + shape.s1[0],
            (shape.cy - shape.s1[1]) * ratio + shape.s1[1],
            shape.s1[0],
            shape.s1[1]
        )

        _ = ctx.closePath()
    }

    // upstream: updateData(nodeData, edgeData, edgeIdx, startAngle, firstCreate?): void
    public func updateData(
        _ nodeData: SeriesData,
        _ edgeData: SeriesData,
        _ edgeIdx: Int,
        _ startAngle: Double,
        _ firstCreate: Bool = false
    ) {
        // upstream `startAngle` is declared but never read in the body (kept for signature parity).
        _ = startAngle

        // const seriesModel = nodeData.hostModel as ChordSeriesModel;
        let seriesModel = nodeData.hostModel as! ChordSeriesModel
        // const edge = edgeData.graph.getEdgeByIndex(edgeIdx);
        //   PORT-NOTE: `graph` is `Graph?` and `getEdgeByIndex` is `GraphEdge?` where upstream assumes
        //   non-null; the port guards defensively and returns early (skips this edge) rather than crash.
        guard let edge = edgeData.graph?.getEdgeByIndex(edgeIdx) else { return }
        // const layout = edge.getLayout();
        let layout = chordLayoutDict(edge.getLayout())
        // const itemModel = edge.node1.getModel<ChordNodeItemOption>();
        //   `GraphNode.getModel()` is `Model?`; guard (no model → cannot resolve cornerRadius, but the
        //   ribbon geometry does not depend on it, so continue with a default Model-less merge).
        let itemModel = edge.node1.getModel()
        // const edgeModel = edgeData.getItemModel<ChordEdgeItemOption>(edge.dataIndex);
        let edgeModel = edgeData.getItemModel(edge.dataIndex)
        // const lineStyle = edgeModel.getModel('lineStyle');
        let lineStyle = edgeModel.getModel("lineStyle")
        // const emphasisModel = edgeModel.getModel('emphasis');
        _ = edgeModel.getModel("emphasis")   // consumed by the DEFERRED emphasis wiring below.
        // const focus = emphasisModel.get('focus');
        // (read below at the DEFERRED toggleHoverEmphasis site.)

        // const shape = extend(getSectorCornerRadius(itemModel.getModel('itemStyle'), layout, true), layout);
        //   The ChordPathShape carried by `layout`, with cornerRadius merged on. cornerRadius is NOT a
        //   field of ChordPathShape (buildPath does not use it), so the merge is a no-op on the shape —
        //   mirror it by simply building the shape from the layout. (Call getSectorCornerRadius for the
        //   faithful side-effect-free parity; its result is unused by the ribbon geometry.)
        let shape = chordPathShapeFromLayout(layout)
        if let itemModel = itemModel {
            // extend(getSectorCornerRadius(...), layout) — result unused (no cornerRadius field on the ribbon).
            _ = getSectorCornerRadius(itemModel.getModel("itemStyle"), sectorRForCornerRadius(shape), true)
        }

        // const el = this;
        let el = self

        // Ignore NaN data.
        // if (isNaN(shape.sStartAngle) || isNaN(shape.tStartAngle)) { el.setShape(shape); return; }
        if shape.sStartAngle.isNaN || shape.tStartAngle.isNaN {
            // Use NaN shape to avoid drawing shape.
            _ = el.setShape(shape)
            return
        }

        if firstCreate {
            // el.setShape(shape);
            _ = el.setShape(shape)
            // applyEdgeFill(el, edge, nodeData, lineStyle);
            applyEdgeFill(el, edge, nodeData, lineStyle)
        }
        else {
            // saveOldStyle(el);  — PORT-NOTE (deferred): animation/basicTransition IS ported, but the
            //   enter/update ribbon transition is intentionally not wired in this static-render view.
            // applyEdgeFill(el, edge, nodeData, lineStyle);
            applyEdgeFill(el, edge, nodeData, lineStyle)
            // graphic.updateProps(el, { shape: shape }, seriesModel, edgeIdx);
            // PORT-NOTE (deferred): enter/update transition not wired — apply the target shape directly.
            _ = el.setShape(shape)
        }

        // Phase 46: edge emphasis + `focus:'adjacency'` (upstream ChordEdge.updateData). The ribbon is a
        //   highDown dispatcher; adjacency resolves to the edge's index set (bridged to the {node,edge}
        //   dict). `states` is qualified — inside a Path subclass the bare name resolves to `self.states`.
        let emphasisModel = edgeModel.getModel("emphasis")
        let focusRaw: InnerFocus? = emphasisModel.get("focus")
        let focus: InnerFocus? = (focusRaw as? String) == "adjacency"
            ? chordFocusDict(edge.getAdjacentDataIndices())
            : focusRaw
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        EChartsKit.states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
        EChartsKit.states.setStatesStylesFromModel(el, edgeModel, "lineStyle")

        // edgeData.setItemGraphicEl(edge.dataIndex, el);
        edgeData.setItemGraphicEl(edge.dataIndex, el)
        innerStore.getECData(el).dataIndex = Double(edge.dataIndex)

        _ = seriesModel   // consumed by the DEFERRED updateProps transition (see above).
    }
}

// ================================================================================================
// upstream: function applyEdgeFill(edgeShape, edge, nodeData, lineStyleModel)
//   Applies the base lineStyle, then resolves the special `color` sentinel ('source' | 'target' |
//   'gradient') against the two endpoint node fills.
//   PORT DEVIATION: the states-aware `edgeStyle` mutation is applied directly to `edgeShape.pathStyle`
//   (same approach as SankeyView.applyCurveStyle — states are DEFERRED).
// ================================================================================================
private func applyEdgeFill(
    _ edgeShape: ChordEdge,
    _ edge: GraphEdge,
    _ nodeData: SeriesData,
    _ lineStyleModel: Model
) {
    // const node1 = edge.node1; const node2 = edge.node2;
    let node1 = edge.node1
    let node2 = edge.node2

    // edgeShape.setStyle(lineStyleModel.getLineStyle());
    //   PORT DEVIATION: upstream `setStyle` MERGES; on the ribbon this is the first/only style call, so
    //   `useStyle` (replace) is equivalent. Bridge the dynamic lineStyle bag → PathStyleProps.
    edgeShape.useStyle(barStyleFromDict(lineStyleModel.getLineStyle()))

    // const color = lineStyleModel.get('color');
    let color = lineStyleModel.get("color") as? String
    switch color {
    case "source":
        // TODO: use visual and node1.getVisual('color');
        // edgeStyle.fill = nodeData.getItemVisual(node1.dataIndex, 'style').fill;
        if let fill = chordColorString(chordStyleDict(nodeData.getItemVisual(node1.dataIndex, "style"))["fill"]) {
            edgeShape.pathStyle.fill = .string(fill)
        }
        // edgeStyle.decal = node1.getVisual('style').decal;
        // PORT-NOTE (deferred): node decal (Pattern) not bridged (decal is out of the static-render scope).
    case "target":
        // edgeStyle.fill = nodeData.getItemVisual(node2.dataIndex, 'style').fill;
        if let fill = chordColorString(chordStyleDict(nodeData.getItemVisual(node2.dataIndex, "style"))["fill"]) {
            edgeShape.pathStyle.fill = .string(fill)
        }
        // edgeStyle.decal = node2.getVisual('style').decal;  — PORT-NOTE (deferred): decal (Pattern) not bridged.
    case "gradient":
        // const sourceColor = nodeData.getItemVisual(node1.dataIndex, 'style').fill;
        // const targetColor = nodeData.getItemVisual(node2.dataIndex, 'style').fill;
        let sourceColor = chordColorString(chordStyleDict(nodeData.getItemVisual(node1.dataIndex, "style"))["fill"])
        let targetColor = chordColorString(chordStyleDict(nodeData.getItemVisual(node2.dataIndex, "style"))["fill"])
        // if (isString(sourceColor) && isString(targetColor)) { ... }
        if let sourceColor = sourceColor, let targetColor = targetColor {
            // Gradient direction is perpendicular to the mid-angles of source and target nodes.
            let shape = edgeShape.shape as! ChordPathShape
            let sMidX = (shape.s1[0] + shape.s2[0]) / 2
            let sMidY = (shape.s1[1] + shape.s2[1]) / 2
            let tMidX = (shape.t1[0] + shape.t2[0]) / 2
            let tMidY = (shape.t1[1] + shape.t2[1]) / 2
            // new graphic.LinearGradient(sMidX, sMidY, tMidX, tMidY, [{0, source}, {1, target}], true);
            let gradient = LinearGradient(
                sMidX, sMidY, tMidX, tMidY,
                [
                    GradientColorStop(offset: 0, color: sourceColor),
                    GradientColorStop(offset: 1, color: targetColor)
                ],
                true
            )
            edgeShape.pathStyle.fill = .linearGradient(gradient)
        }
    default:
        // Any other color (a real color already, or nil) is left as the base lineStyle fill.
        break
    }
}

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// Coerce a `getItemVisual(idx, 'style')` value (a `[String: Any]` bag) to the dict (empty when absent).
private func chordStyleDict(_ v: Any?) -> [String: Any] {
    return (v as? [String: Any]) ?? [:]
}

// getSectorCornerRadius expects a `SectorShape` (reads r0/r). The ribbon carries only a single radius
//   `r` (== series.r0); wrap it so the faithful — but result-unused — cornerRadius call type-checks.
private func sectorRForCornerRadius(_ shape: ChordPathShape) -> SectorShape {
    var s = SectorShape()
    s.r = shape.r
    s.r0 = shape.r
    return s
}

// Build a `ChordPathShape` from the per-edge chord layout dict. Keys: s1/s2/t1/t2 (`[Double]` pairs),
//   sStartAngle/sEndAngle/tStartAngle/tEndAngle/cx/cy/r (numbers), clockwise (Bool). A missing arc-start
//   angle coerces to NaN so the upstream `isNaN(...)` NaN-data guard fires.
private func chordPathShapeFromLayout(_ layout: [String: Any]) -> ChordPathShape {
    var shape = ChordPathShape()
    shape.s1 = chordPoint(layout["s1"])
    shape.s2 = chordPoint(layout["s2"])
    shape.sStartAngle = chordNum(layout["sStartAngle"]) ?? Double.nan
    shape.sEndAngle = chordNum(layout["sEndAngle"]) ?? Double.nan
    shape.t1 = chordPoint(layout["t1"])
    shape.t2 = chordPoint(layout["t2"])
    shape.tStartAngle = chordNum(layout["tStartAngle"]) ?? Double.nan
    shape.tEndAngle = chordNum(layout["tEndAngle"]) ?? Double.nan
    shape.cx = chordNum(layout["cx"]) ?? 0
    shape.cy = chordNum(layout["cy"]) ?? 0
    shape.r = chordNum(layout["r"]) ?? 0
    shape.clockwise = (layout["clockwise"] as? Bool) ?? true
    return shape
}

// Coerce a layout `[x, y]` pair (stored as `[Double]` / `[Any]` / `[NSNumber]`) to `[Double]` of length 2.
private func chordPoint(_ v: Any?) -> [Double] {
    if let arr = v as? [Double], arr.count >= 2 { return [arr[0], arr[1]] }
    if let arr = v as? [Any], arr.count >= 2 {
        return [chordNum(arr[0]) ?? 0, chordNum(arr[1]) ?? 0]
    }
    return [0, 0]
}

// export { ChordEdge };  -> `public final class ChordEdge` above.
