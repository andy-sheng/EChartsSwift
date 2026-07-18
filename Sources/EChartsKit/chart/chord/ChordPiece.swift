// Ported from echarts/src/chart/chord/ChordPiece.ts — keep in sync with upstream
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
//   import { extend, retrieve3 } from 'zrender/src/core/util';
//       -> `extend` == building a SectorShape from the layout dict + merging cornerRadius (see below);
//          `retrieve3` only feeds the DEFERRED label formatter.
//   import * as graphic from '../../util/graphic';                 -> ZRenderKit `Sector` / `ZRText`;
//       `graphic.updateProps` is the enter/update animation helper — DEFERRED (see PORT-NOTE in updateData).
//   import SeriesData from '../../data/SeriesData';                -> `SeriesData`.
//   import { getSectorCornerRadius } from '../helper/sectorHelper';-> `getSectorCornerRadius` (chart/helper/sectorHelper.swift).
//   import ChordSeriesModel, { ChordNodeItemOption } from './ChordSeries';
//       -> sibling `ChordSeriesModel` (assumed ported alongside — the ChordSeries.swift port).
//   import type Model from '../../model/Model';                    -> `Model`.
//   import type { GraphNode } from '../../data/Graph';             -> data/Graph.swift `GraphNode`.
//   import { getLabelStatesModels, setLabelStyle } from '../../label/labelStyle';
//       -> label/labelStyle.swift (getLabelStatesModels:404, setLabelStyle:303). Both ARE ported, but this
//          view still inlines a minimal NORMAL-state label in `_updateLabel` below: upstream wraps
//          setLabelStyle in a CUSTOM `labelFetcher` (a retrieve3 name-formatter fallback + dataType 'node')
//          plus a 'startArc' outside position, none of which are wired here yet (see note in `_updateLabel`).
//   import type { BuiltinTextPosition } from 'zrender/src/core/types'; -> the `defaultOutsidePosition`
//       only feeds the DEFERRED setLabelStyle.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-NOTE: util/states.swift is ported; states/emphasis is just not wired here yet (DEFERRED per CONVENTIONS §5).
//   import { getECData } from '../../util/innerStore';             -> `innerStore.getECData`.

// upstream: export default class ChordPiece extends graphic.Sector
open class ChordPiece: Sector {

    // upstream: constructor(data: SeriesData, idx: number, startAngle: number)
    public init(_ data: SeriesData, _ idx: Int, _ startAngle: Double) {
        super.init()

        // getECData(this).dataType = 'node';
        innerStore.getECData(self).dataType = .node
        // this.z2 = 2;
        self.z2 = 2

        // const text = new graphic.Text();
        let text = ZRText()
        // this.setTextContent(text);
        self.setTextContent(text)

        // this.updateData(data, idx, startAngle, true);
        self.updateData(data, idx, startAngle, true)
    }

    // upstream: updateData(data, idx, startAngle?, firstCreate?): void
    public func updateData(
        _ data: SeriesData,
        _ idx: Int,
        _ startAngle: Double? = nil,
        _ firstCreate: Bool = false
    ) {
        // upstream `startAngle` is declared but never read in the body (kept for signature parity).
        _ = startAngle

        // const sector = this;
        let sector = self
        // const node = data.graph.getNodeByIndex(idx);
        //   PORT-NOTE: `data.graph` is `Graph?` and `getNodeByIndex` is `GraphNode?`; upstream assumes
        //   both non-null. Guard defensively (no node → nothing to draw) — semantically equivalent.
        guard let node = data.graph?.getNodeByIndex(idx) else { return }

        // const seriesModel = data.hostModel as ChordSeriesModel;
        //   PORT-NOTE: `hostModel` is `Model?`; force-cast mirrors the upstream `as ChordSeriesModel`.
        let seriesModel = data.hostModel as! ChordSeriesModel
        // const itemModel = node.getModel<ChordNodeItemOption>();
        //   `GraphNode.getModel()` is `Model?` (nil for dataIndex < 0); guard.
        guard let itemModel = node.getModel() else { return }
        // const emphasisModel = itemModel.getModel('emphasis');
        _ = itemModel.getModel("emphasis")   // consumed by the DEFERRED emphasis wiring below.

        // layout position is the center of the sector
        // const layout = data.getItemLayout(idx) as graphic.Sector['shape'];
        let layout = chordLayoutDict(data.getItemLayout(idx))
        // const shape = extend(getSectorCornerRadius(itemModel.getModel('itemStyle'), layout, true), layout);
        //   `extend(cornerRadius, layout)` → the SectorShape carried by `layout`, with the cornerRadius
        //   merged on. Build the SectorShape from the layout dict, then apply the corner radius.
        var shape = sectorShapeFromChordLayout(layout)
        if let cornerRadius = getSectorCornerRadius(itemModel.getModel("itemStyle"), shape, true) {
            shape.cornerRadius = cornerRadius
        }

        // const el = this;
        let el = self

        // Ignore NaN data.
        // if (isNaN(shape.startAngle)) { el.setShape(shape); return; }
        if shape.startAngle.isNaN {
            // Use NaN shape to avoid drawing shape.
            _ = el.setShape(shape)
            return
        }

        if firstCreate {
            // el.setShape(shape);
            _ = el.setShape(shape)
        }
        else {
            // graphic.updateProps(el, { shape: shape }, seriesModel, idx);
            //   Tween the whole shape from the element's current shape toward `shape`. `updateProps`
            //   captures the current shape as the animator source, sets the element to the final state
            //   immediately (setToFinal — so the shape-dependent label layout below is correct), then
            //   plays the tween; the unconditional `sector.setShape(sectorShape)` just below re-applies
            //   the identical final shape (upstream does the same). Shape props MUST be a DICT of the
            //   animatable numeric fields — a full SectorShape struct is opaque to the animator
            //   (the struct->dict rule). Instant (no animator) when the series' animation is disabled.
            updateProps(el, ["shape": chordShapeProps(shape)], seriesModel, idx)
        }

        // const sectorShape = extend(getSectorCornerRadius(itemModel.getModel('itemStyle'), layout, true), layout);
        //   (upstream rebuilds the identical shape a second time; mirror it faithfully.)
        var sectorShape = sectorShapeFromChordLayout(layout)
        if let cornerRadius = getSectorCornerRadius(itemModel.getModel("itemStyle"), sectorShape, true) {
            sectorShape.cornerRadius = cornerRadius
        }
        // sector.setShape(sectorShape);
        _ = sector.setShape(sectorShape)
        // sector.useStyle(data.getItemVisual(idx, 'style'));
        sector.useStyle(barStyleFromDict(data.getItemVisual(idx, "style")))
        // setStatesStylesFromModel(sector, itemModel);
        // PORT-NOTE: per-state itemStyle (emphasis/blur/select) not wired here yet (util/states.swift is ported).

        // this._updateLabel(seriesModel, itemModel, node);
        self._updateLabel(seriesModel, itemModel, node)

        // data.setItemGraphicEl(idx, el);
        data.setItemGraphicEl(idx, el)
        // Also tag the element's ecData dataIndex (needed for blurSeries's getData(dataType) lookup).
        innerStore.getECData(el).dataIndex = Double(idx)

        // Phase 46: setStatesStylesFromModel(el, itemModel, 'itemStyle') + the emphasis focus handling
        //   (upstream ChordPiece.updateData). The node sector is a highDown dispatcher; `focus:'adjacency'`
        //   resolves to the node's adjacency index set (bridged to the `{node,edge}` dict blurSeries reads).
        let emphasisModel = itemModel.getModel("emphasis")
        let focusRaw: InnerFocus? = emphasisModel.get("focus")
        let focus: InnerFocus? = (focusRaw as? String) == "adjacency"
            ? chordFocusDict(node.getAdjacentDataIndices())
            : focusRaw
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        // Qualify the `states` enum — inside a Sector subclass the bare name resolves to `self.states`.
        EChartsKit.states.toggleHoverEmphasis(el, focus, blurScope, isDisabled)
        EChartsKit.states.setStatesStylesFromModel(el, itemModel)
    }

    // upstream: protected _updateLabel(seriesModel, itemModel, node)
    open func _updateLabel(
        _ seriesModel: ChordSeriesModel,
        _ itemModel: Model,
        _ node: GraphNode
    ) {
        // const label = this.getTextContent();
        guard let label = self.getTextContent() else { return }
        // const layout = node.getLayout();
        let layout = chordLayoutDict(node.getLayout())
        let startAngle = chordNum(layout["startAngle"]) ?? 0
        let endAngle = chordNum(layout["endAngle"]) ?? 0
        let cx = chordNum(layout["cx"]) ?? 0
        let cy = chordNum(layout["cy"]) ?? 0
        let rLayout = chordNum(layout["r"]) ?? 0
        let r0Layout = chordNum(layout["r0"]) ?? 0
        // const midAngle = (layout.startAngle + layout.endAngle) / 2;
        let midAngle = (startAngle + endAngle) / 2
        // const dx = Math.cos(midAngle); const dy = Math.sin(midAngle);
        let dx = cos(midAngle)
        let dy = sin(midAngle)

        // const normalLabelModel = itemModel.getModel('label');
        let normalLabelModel = itemModel.getModel("label")
        // label.ignore = !normalLabelModel.get('show');
        label.ignore = !(jsTruthy(normalLabelModel.get("show")))

        // Set label style
        // const labelStateModels = getLabelStatesModels(itemModel);
        let labelStateModels = labelStyle.getLabelStatesModels(itemModel)
        // const style = node.getVisual('style');
        let style = node.getVisual("style") as? [String: Any] ?? [:]
        // setLabelStyle(label, labelStateModels, { labelFetcher: {...}, labelDataIndex,
        //     defaultText: node.dataIndex + '', inheritColor: style.fill, defaultOpacity: style.opacity,
        //     defaultOutsidePosition: 'startArc' });
        //   PORT-NOTE: upstream passes a CUSTOM inline labelFetcher whose getFormattedLabel forces
        //   `dataType: 'node'` and a `retrieve3(formatter, normal formatter, itemModel name)` formatter
        //   fallback. `DataFormatMixin.getFormattedLabel` is a STATICALLY-dispatched protocol-extension
        //   method, so a custom fetcher subtype's override would be bypassed by `getLabelText`'s
        //   existential `labelFetcher.getFormattedLabel(...)` call (the protocol-witness trap). Port the
        //   observable behaviour instead: pass `seriesModel` as the fetcher (its getFormattedLabel
        //   honours `label.formatter`; the node data is the default data here, so the forced 'node'
        //   dataType resolves to the same SeriesData) and fold upstream's `itemModel.name`
        //   formatter-fallback into `defaultText` — when no formatter yields text the node name (id) is
        //   used, else the data-index string (upstream's `node.dataIndex + ''`). This now wires the full
        //   setLabelStyle machinery: per-state (emphasis/blur/select) label styles + defaultOpacity +
        //   inheritColor. (`defaultOutsidePosition: 'startArc'` is passed for fidelity but is inert on a
        //   ZRText target — setLabelStyle's `isSetOnText` branch skips createTextConfig — and the outside
        //   position is overridden below by the explicit x/y placement, as upstream also does.)
        var opt = SetLabelStyleOpt()
        opt.labelFetcher = seriesModel
        opt.labelDataIndex = Double(node.dataIndex)
        opt.defaultText = node.id.isEmpty ? String(node.dataIndex) : node.id
        opt.inheritColor = chordColorString(style["fill"])
        opt.defaultOpacity = chordNum(style["opacity"])
        opt.defaultOutsidePosition = "startArc"
        labelStyle.setLabelStyle(label, labelStateModels, opt)

        // Set label position
        // const labelPosition = normalLabelModel.get('position') || 'outside';
        let labelPosition = (jsTruthy(normalLabelModel.get("position"))
            ? (normalLabelModel.get("position") as? String) : nil) ?? "outside"
        // const labelPadding = normalLabelModel.get('distance') || 0;
        let labelPadding = jsTruthy(normalLabelModel.get("distance"))
            ? (chordNum(normalLabelModel.get("distance")) ?? 0) : 0

        // let r; if (labelPosition === 'outside') { r = layout.r + labelPadding; } else { r = (layout.r + layout.r0) / 2; }
        let r: Double
        if labelPosition == "outside" {
            r = rLayout + labelPadding
        }
        else {
            r = (rLayout + r0Layout) / 2
        }

        // this.textConfig = { inside: labelPosition !== 'outside' };
        var textConfig = ElementTextConfig()
        textConfig.inside = (labelPosition != "outside")
        self.textConfig = textConfig

        // const align = labelPosition !== 'outside' ? (normalLabelModel.get('align') || 'center') : (dx > 0 ? 'left' : 'right');
        let align: TextAlign
        if labelPosition != "outside" {
            align = TextAlign(rawValue: (normalLabelModel.get("align") as? String) ?? "center") ?? .center
        }
        else {
            align = dx > 0 ? .left : .right
        }
        // const verticalAlign = labelPosition !== 'outside' ? (normalLabelModel.get('verticalAlign') || 'middle') : (dy > 0 ? 'top' : 'bottom');
        let verticalAlign: TextVerticalAlign
        if labelPosition != "outside" {
            verticalAlign = TextVerticalAlign(rawValue: (normalLabelModel.get("verticalAlign") as? String) ?? "middle") ?? .middle
        }
        else {
            verticalAlign = dy > 0 ? .top : .bottom
        }

        // label.attr({ x: dx * r + layout.cx, y: dy * r + layout.cy, rotation: 0, style: { align, verticalAlign } });
        //   `style: { align, verticalAlign }` is a MERGE-set onto the style `setLabelStyle` just built —
        //   ZRText has no field-merge `setStyle` counterpart (see setLabelText PORT-NOTE), so read the
        //   current style, mutate just align/verticalAlign, then `useStyle` (full replace); every other
        //   field carries over unchanged.
        var mergedStyle = label.textStyle ?? TextStyleProps()
        mergedStyle.align = align
        mergedStyle.verticalAlign = verticalAlign
        label.useStyle(mergedStyle)
        label.x = dx * r + cx
        label.y = dy * r + cy
        label.rotation = 0
        label.dirtyStyle()
    }
}

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------

// Node layouts are stored by the chord layout as a `[String: Any]` Sector shape
//   (cx/cy/r0/r/startAngle/endAngle/clockwise). `getItemLayout`/`getLayout` return `Any?`.
func chordLayoutDict(_ v: Any?) -> [String: Any] {
    return (v as? [String: Any]) ?? [:]
}

// Phase 46: bridge the chord node/edge `GraphDataIndices` → the `{node:[…], edge:[…]}` dict form that
//   `states.blurSeries`'s object-focus branch consumes (chord uses the shared Graph like sankey).
func chordFocusDict(_ ix: GraphDataIndices) -> [String: Any] {
    return ["node": ix.node, "edge": ix.edge]
}

// TRAP #1 GUARD: `[String: Any]` layout/option values store numbers as bare `Int` OR `Double` OR
//   `NSNumber`. `as? Double` alone SILENTLY DROPS an Int. Coerce all three (nil for genuinely absent /
//   non-numeric — so `isNaN` reads on a truly missing angle stay faithful to upstream's NaN guard).
func chordNum(_ v: Any?) -> Double? {
    switch v {
    case nil: return nil
    case is NSNull: return nil
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    default: return nil
    }
}

// The raw solid-color string of a visual color (used to bridge `style.fill` — a ZRColor `.color(String)`
//   OR a raw `String` — to a plain color string). Gradient/pattern visual colors out of scope.
func chordColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    if let zr = v as? ZRenderKit.ZRColor, case let .string(str) = zr { return str }
    return nil
}

// Build a `SectorShape` from the per-node chord layout dict. A missing `startAngle` coerces to NaN so
//   the upstream `isNaN(shape.startAngle)` NaN-data guard fires (mirrors JS reading an absent field).
private func sectorShapeFromChordLayout(_ layout: [String: Any]) -> SectorShape {
    var shape = SectorShape()
    shape.cx = chordNum(layout["cx"]) ?? 0
    shape.cy = chordNum(layout["cy"]) ?? 0
    shape.r0 = chordNum(layout["r0"]) ?? 0
    shape.r = chordNum(layout["r"]) ?? 0
    shape.startAngle = chordNum(layout["startAngle"]) ?? Double.nan
    shape.endAngle = chordNum(layout["endAngle"]) ?? Double.nan
    shape.clockwise = (layout["clockwise"] as? Bool) ?? true
    return shape
}

// The animatable numeric fields of a `SectorShape` as a `[String: Any]` dict — the form
//   `updateProps(el, { shape: … })` requires (the animator tweens keyed numeric fields; a full
//   SectorShape struct is opaque to it). `clockwise`/`cornerRadius` are not tweened (matching
//   SectorShape.animationGet), and are carried by the unconditional `setShape` that follows.
private func chordShapeProps(_ shape: SectorShape) -> [String: Any] {
    return [
        "cx": shape.cx,
        "cy": shape.cy,
        "r0": shape.r0,
        "r": shape.r,
        "startAngle": shape.startAngle,
        "endAngle": shape.endAngle
    ]
}

// JS `||` / `!x` falsiness (TRAP #1 companion). Mirrors the file-local `jsTruthy` in the sibling ports
//   (SankeyLayout / GraphSeries / TreeSeries): 0 / NaN / "" / null / undefined / false are falsy.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// export default ChordPiece;  -> `open class ChordPiece` above.
