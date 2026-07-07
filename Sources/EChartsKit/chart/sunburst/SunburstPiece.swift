// Ported from echarts/src/chart/sunburst/SunburstPiece.ts — keep in sync with upstream
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
//   import * as graphic from '../../util/graphic';                 -> ZRenderKit `Sector` / `ZRText`;
//       `graphic.initProps`/`updateProps` are the animation helpers — DEFERRED (see PORT-TODO below).
//   import { toggleHoverEmphasis, SPECIAL_STATES, DISPLAY_STATES } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported (states/emphasis deferred).
//   import { createTextStyle } from '../../label/labelStyle';       -> `labelStyle` (label/labelStyle.swift).
//       PORT: `_updateLabel` routes text+style through `labelStyle.setLabelStyle` (on the label ZRText,
//       à la ChordPiece) rather than the upstream inline `createTextStyle` DISPLAY_STATES loop.
//   import { TreeNode } from '../../data/Tree';                     -> sibling `TreeNode` (data/Tree.swift).
//   import SunburstSeriesModel, {...} from './SunburstSeries';      -> sibling `SunburstSeriesModel`.
//   import GlobalModel from '../../model/Global';                   -> `GlobalModel`.
//   import { PathStyleProps } from 'zrender/src/graphic/Path';      -> `PathStyleProps` (ZRenderKit).
//   import { ColorString } from '../../util/types';                 -> `ColorString` (util/types.swift).
//   import Model from '../../model/Model';                          -> `Model`.
//   import { getECData } from '../../util/innerStore';              -> `innerStore.getECData`.
//   import { getSectorCornerRadius } from '../helper/sectorHelper'; -> `getSectorCornerRadius` (chart/helper/sectorHelper.swift).
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';  -> PORT-TODO: util/decal NOT ported (decal deferred).
//   import ExtensionAPI from '../../core/ExtensionAPI';             -> `ExtensionAPI`.
//   import { saveOldStyle } from '../../animation/basicTransition'; -> PORT-TODO: NOT ported (deferred).
//   import { normalizeRadian } from 'zrender/src/contain/util';     -> `contain_util.normalizeRadian` (ZRenderKit) — used by the deferred label-rotation math.
//   import { isRadianAroundZero } from '../../util/number';         -> `number.isRadianAroundZero` — used by the deferred label-rotation math.

// upstream: const DEFAULT_SECTOR_Z = 2;
private let DEFAULT_SECTOR_Z: Double = 2
// upstream: const DEFAULT_TEXT_Z = 4;
private let DEFAULT_TEXT_Z: Double = 4

// upstream: interface DrawTreeNode extends TreeNode { piece: SunburstPiece }
// PORT-TODO: Swift `TreeNode` (sibling) is a `final class` that can not be externally augmented with a
//   stored `piece` property. Upstream's `(node as DrawTreeNode).piece = this` write-back is used by
//   the SunburstView DataDiffer (add/update/remove). The static SunburstView.render() rebuilds every
//   render, so it does not consult `node.piece`; the write-back is therefore dropped here (marked at
//   its call site in `updateData`). Wire once `TreeNode` carries a `piece`/attached-state slot.

/**
 * Sunburstce of Sunburst including Sector, Label, LabelLine
 */
// upstream: class SunburstPiece extends graphic.Sector
open class SunburstPiece: Sector {

    // upstream: node: TreeNode;
    public var node: TreeNode!

    // upstream: private _seriesModel: SunburstSeriesModel;
    private var _seriesModel: SunburstSeriesModel!
    // upstream: private _ecModel: GlobalModel;
    private var _ecModel: GlobalModel!

    // upstream: constructor(node, seriesModel, ecModel, api)
    public init(_ node: TreeNode, _ seriesModel: SunburstSeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        super.init()

        // this.z2 = DEFAULT_SECTOR_Z;
        self.z2 = DEFAULT_SECTOR_Z
        // this.textConfig = { inside: true };
        var textConfig = ElementTextConfig()
        textConfig.inside = true
        self.textConfig = textConfig

        // getECData(this).seriesIndex = seriesModel.seriesIndex;
        innerStore.getECData(self).seriesIndex = seriesModel.seriesIndex

        // const text = new graphic.Text({ z2: DEFAULT_TEXT_Z, silent: node.getModel(...).get(['label', 'silent']) });
        //   node.getModel() is `Model?` (nil when dataIndex < 0, e.g. the roll-up virtualRoot).
        let text = ZRText([
            "z2": DEFAULT_TEXT_Z,
            "silent": (node.getModel()?.get(["label", "silent"]) as? Bool) ?? false
        ])
        // this.setTextContent(text);
        self.setTextContent(text)

        // this.updateData(true, node, seriesModel, ecModel, api);
        self.updateData(true, node, seriesModel, ecModel, api)
    }

    // upstream: updateData(firstCreate, node, seriesModel, ecModel, api)
    public func updateData(
        _ firstCreate: Bool,
        _ node: TreeNode,
        _ seriesModelIn: SunburstSeriesModel?,
        _ ecModelIn: GlobalModel?,
        _ api: ExtensionAPI
    ) {
        // this.node = node;
        self.node = node
        // (node as DrawTreeNode).piece = this;
        // PORT-TODO: `node.piece` write-back dropped — TreeNode carries no `piece` slot (see the
        //   DrawTreeNode PORT-TODO above). Not needed by the static SunburstView.render().

        // seriesModel = seriesModel || this._seriesModel;
        let seriesModel: SunburstSeriesModel = seriesModelIn ?? self._seriesModel
        // ecModel = ecModel || this._ecModel;
        let ecModel = ecModelIn ?? self._ecModel

        // const sector = this;
        let sector = self
        // getECData(sector).dataIndex = node.dataIndex;
        //   TreeNode.dataIndex is `Int`; ECData.dataIndex is `Double?`.
        innerStore.getECData(sector).dataIndex = Double(node.dataIndex)

        // const itemModel = node.getModel<SunburstSeriesNodeItemOption>();
        //   PORT-TODO: `node.getModel()` is `Model?` and returns nil for a node with dataIndex < 0
        //   (the roll-up virtualRoot). Upstream assumes non-null; guard defensively — a node with no
        //   item model can not be styled/labelled, so bail (no sector body drawn for it).
        guard let itemModel = node.getModel() else {
            return
        }
        // const emphasisModel = itemModel.getModel('emphasis');
        _ = itemModel.getModel("emphasis")   // emphasisModel — consumed by the deferred emphasis wiring.
        // const layout = node.getLayout();
        let layout = node.getLayout() as? [String: Any] ?? [:]

        // const sectorShape = zrUtil.extend({}, layout); sectorShape.label = null;
        //   `layout` is the per-node Sector layout (cx/cy/r0/r/startAngle/endAngle/clockwise/angle)
        //   set by sunburstLayout. `label = null` is a no-op on the Swift `SectorShape` (no label field).
        var sectorShape = sectorShapeFromLayout(layout)

        // const normalStyle = node.getVisual('style') as PathStyleProps;
        var normalStyle = barStyleFromDict(node.getVisual("style"))
        // normalStyle.lineJoin = 'bevel';
        normalStyle.lineJoin = "bevel"

        // const decal = node.getVisual('decal');
        // if (decal) { normalStyle.decal = createOrUpdatePatternFromDecal(decal, api); }
        // PORT-TODO: util/decal.createOrUpdatePatternFromDecal NOT ported (decal deferred).
        _ = api

        // const cornerRadius = getSectorCornerRadius(itemModel.getModel('itemStyle'), sectorShape, true);
        // zrUtil.extend(sectorShape, cornerRadius);
        if let cornerRadius = getSectorCornerRadius(itemModel.getModel("itemStyle"), sectorShape, true) {
            sectorShape.cornerRadius = cornerRadius
        }

        // zrUtil.each(SPECIAL_STATES, function (stateName) { ... ensureState ... getSectorCornerRadius ... });
        // PORT-TODO: SPECIAL_STATES per-state itemStyle + corner-radius (emphasis/blur/select) DEFERRED
        //   (util/states not ported). Static render only needs the normal state.

        if firstCreate {
            // sector.setShape(sectorShape);
            // sector.shape.r = layout.r0;
            // graphic.initProps(sector, { shape: { r: layout.r } }, seriesModel, node.dataIndex);
            // Entrance (angle-expansion form, mirroring PieView's PiePiece sweep): create the sector
            //   collapsed (endAngle == startAngle), then sweep endAngle open to the final layout angle
            //   via initProps below. Upstream sunburst animates `r` (r0 -> r); we use the angle-expansion
            //   form shared with pie (SectorShape has per-key animationSet). Shape props MUST be a dict of
            //   animatable fields (a full SectorShape struct is opaque to the animator). Instant (final
            //   angle, no animator) when the series' animation is disabled.
            let finalEndAngle = sectorShape.endAngle
            var collapsedShape = sectorShape
            collapsedShape.endAngle = sectorShape.startAngle
            _ = sector.setShape(collapsedShape)
            initProps(sector, ["shape": ["endAngle": finalEndAngle] as [String: Any]], seriesModel, node.dataIndex)
        }
        else {
            // graphic.updateProps(sector, { shape: sectorShape }, seriesModel);
            // saveOldStyle(sector);
            // PORT-TODO: animation/transition DEFERRED — apply the target shape directly.
            _ = sector.setShape(sectorShape)
        }

        // sector.useStyle(normalStyle);
        sector.useStyle(normalStyle)

        // this._updateLabel(seriesModel);
        self._updateLabel(seriesModel)

        // const cursorStyle = itemModel.getShallow('cursor');
        // cursorStyle && sector.attr('cursor', cursorStyle);
        if let cursorStyle = itemModel.getShallow("cursor") {
            _ = sector.attr("cursor", cursorStyle)
        }

        // this._seriesModel = seriesModel || this._seriesModel;
        //   `seriesModel` is already `seriesModelIn ?? self._seriesModel` (non-nil), so the
        //   upstream `|| this._seriesModel` guard is a no-op here.
        self._seriesModel = seriesModel
        // this._ecModel = ecModel || this._ecModel;
        self._ecModel = ecModel ?? self._ecModel

        // const focus = emphasisModel.get('focus'); ... toggleHoverEmphasis(...);
        // PORT-TODO: emphasis focus (relative/ancestor/descendant indices) + toggleHoverEmphasis
        //   DEFERRED (util/states not ported).
    }

    // upstream: _updateLabel(seriesModel)
    func _updateLabel(_ seriesModel: SunburstSeriesModel) {
        // const itemModel = this.node.getModel<SunburstSeriesNodeItemOption>();
        //   PORT-TODO: `Model?` — nil for dataIndex < 0 (roll-up virtualRoot); bail (no label).
        guard let itemModel = self.node.getModel() else { return }
        // const normalLabelModel = itemModel.getModel('label');
        let normalLabelModel = itemModel.getModel("label")

        // const layout = this.node.getLayout();
        let layout = self.node.getLayout() as? [String: Any] ?? [:]
        // const angle = layout.endAngle - layout.startAngle;
        let startAngle = (layout["startAngle"] as? Double) ?? 0
        let endAngle = (layout["endAngle"] as? Double) ?? 0
        let cx = (layout["cx"] as? Double) ?? 0
        let cy = (layout["cy"] as? Double) ?? 0
        let rLayout = (layout["r"] as? Double) ?? 0
        let r0Layout = (layout["r0"] as? Double) ?? 0
        let angle = endAngle - startAngle

        // const midAngle = (layout.startAngle + layout.endAngle) / 2;
        let midAngle = (startAngle + endAngle) / 2
        // const dx = Math.cos(midAngle); const dy = Math.sin(midAngle);
        let dx = cos(midAngle)
        let dy = sin(midAngle)

        // const sector = this;
        let sector = self
        // const label = sector.getTextContent();
        guard let label = sector.getTextContent() else { return }
        // const dataIndex = this.node.dataIndex;
        let dataIndex = self.node.dataIndex
        // const labelMinAngle = normalLabelModel.get('minAngle') / 180 * Math.PI;
        let labelMinAngle = ((normalLabelModel.get("minAngle") as? Double) ?? 0) / 180 * Double.pi
        // const isNormalShown = normalLabelModel.get('show') && !(labelMinAngle != null && Math.abs(angle) < labelMinAngle);
        let showFlag = (normalLabelModel.get("show") as? Bool) ?? false
        let isNormalShown = showFlag && !(Swift.abs(angle) < labelMinAngle)

        // ── Route text + per-state (normal/emphasis/blur/select) label STYLE through the shared label
        //    core (`labelStyle.setLabelStyle`), replacing the former hand-rolled normal-only text style.
        //
        // PORT-NOTE: upstream sunburst still hand-builds styles via `createTextStyle` inside its
        //   `DISPLAY_STATES` loop (with a standing `// TODO use setLabelStyle`). We take the migrated
        //   form, following the sibling **ChordPiece** (its radial-sector analog, which DID land on
        //   `setLabelStyle`): call `setLabelStyle` with the LABEL (the `ZRText` textContent) as the
        //   target element — NOT the sector — so the core writes the text/style straight onto the label
        //   and does NOT stamp a `textConfig.position` (which would otherwise force `updateInnerText` to
        //   re-place the label at the sector's bounding-box centre and clobber the RADIAL x/y/rotation
        //   computed below). Placement (position/distance/align/rotate + up-side-down flip) and the
        //   host `textConfig` (inside/outsideFill) stay owned by this method, matching upstream's
        //   per-state `sectorState.textConfig` + `state.x/y/rotation` writes.
        //
        // upstream text: `text = seriesModel.getFormattedLabel(dataIndex, stateName); text = text || node.name`.
        //   → labelFetcher = seriesModel (SeriesModel : DataFormatMixin), defaultText = node.name.
        let labelStateModels = labelStyle.getLabelStatesModels(itemModel)
        let inheritColor = _fillColorString(self.node.getVisual("style"))
        var opt = SetLabelStyleOpt()
        opt.labelFetcher = seriesModel
        opt.labelDataIndex = Double(dataIndex)
        opt.defaultText = self.node.name
        opt.inheritColor = inheritColor
        labelStyle.setLabelStyle(label, labelStateModels, opt)

        // label.ignore = !isNormalShown;  (after setLabelStyle, which sets its own `ignore` from `show`;
        //   re-apply so the sunburst min-angle guard wins.)
        label.ignore = !isNormalShown

        // ── Placement (upstream NORMAL-state branch of the DISPLAY_STATES loop). ──
        //   PORT-TODO: per-state placement (emphasis/blur/select can each carry a different position /
        //   rotate) DEFERRED — the static render applies the NORMAL geometry only (same deviation as the
        //   former code; setLabelStyle already supplied all four states' text/style above).
        let labelPosition = _labelAttr(normalLabelModel, "position") as? String
        let labelPadding = ((_labelAttr(normalLabelModel, "distance") as? Double) ?? 0)
        var textAlign = _labelAttr(normalLabelModel, "align") as? String
        let rotateType = _labelAttr(normalLabelModel, "rotate")

        let flipStartAngle = Double.pi * 0.5
        let flipEndAngle = Double.pi * 1.5
        // const midAngleNormal = normalizeRadian(rotateType === 'tangential' ? PI/2 - midAngle : midAngle);
        let midAngleNormal = containUtil.normalizeRadian(
            (rotateType as? String) == "tangential" ? (Double.pi / 2 - midAngle) : midAngle
        )
        // For text that is up-side down, rotate 180 degrees to make sure it's readable.
        let needsFlip = midAngleNormal > flipStartAngle
            && !number.isRadianAroundZero(midAngleNormal - flipStartAngle)
            && midAngleNormal < flipEndAngle

        var r: Double
        if labelPosition == "outside" {
            r = rLayout + labelPadding
            textAlign = needsFlip ? "right" : "left"
        }
        else {
            if textAlign == nil || textAlign == "center" {
                // Put label in the center if it's a circle.
                if r0Layout == 0 && number.isRadianAroundZero(angle - 2 * Double.pi) {
                    r = 0
                }
                else {
                    r = (rLayout + r0Layout) / 2
                }
                textAlign = "center"
            }
            else if textAlign == "left" {
                r = r0Layout + labelPadding
                textAlign = needsFlip ? "right" : "left"
            }
            else if textAlign == "right" {
                r = rLayout - labelPadding
                textAlign = needsFlip ? "left" : "right"
            }
            else {
                r = (rLayout + r0Layout) / 2
            }
        }

        // state.style.align / verticalAlign — merge onto the style setLabelStyle already installed
        //   (do NOT rebuild the style, or the inheritColor fill / font from the core is lost).
        var style = label.textStyle ?? TextStyleProps()
        if let a = textAlign, let ta = TextAlign(rawValue: a) { style.align = ta }
        let vAlign = (_labelAttr(normalLabelModel, "verticalAlign") as? String) ?? "middle"
        if let va = TextVerticalAlign(rawValue: vAlign) { style.verticalAlign = va }
        label.textStyle = style

        // state.x = r * dx + layout.cx; state.y = r * dy + layout.cy;
        label.x = r * dx + cx
        label.y = r * dy + cy

        // Rotation (sunburst default 'radial'): 'radial' aligns text with the radius, 'tangential'
        //   perpendicular; a number is degrees. `needsFlip` adds ±PI so text is never up-side-down.
        var rotate = 0.0
        if let s = rotateType as? String {
            if s == "radial" {
                rotate = containUtil.normalizeRadian(-midAngle) + (needsFlip ? Double.pi : 0)
            }
            else if s == "tangential" {
                rotate = containUtil.normalizeRadian(Double.pi / 2 - midAngle) + (needsFlip ? Double.pi : 0)
            }
        }
        else if let n = rotateType as? Double {
            rotate = n * Double.pi / 180
        }
        else if let n = rotateType as? Int {
            rotate = Double(n) * Double.pi / 180
        }
        label.rotation = containUtil.normalizeRadian(rotate)

        // sectorState.textConfig = { outsideFill: color==='inherit' ? fill : null, inside: position !== 'outside' };
        //   Owns the host transform anchor for the attached text (fill-color side of updateInnerText).
        var textConfig = self.textConfig ?? ElementTextConfig()
        textConfig.inside = (labelPosition != "outside")
        textConfig.outsideFill = ((normalLabelModel.get("color") as? String) == "inherit") ? inheritColor : nil
        self.textConfig = textConfig

        // label.dirtyStyle();
        label.dirtyStyle()
    }
}

// Extract a solid fill color string from a node's visual `style` dict (fill stored either as a raw
//   `String` or an EChartsKit `ZRColor.color(...)` by the visual stage). Mirrors BarView's
//   `barStyleFromDict` color bridging; used as `inheritColor` for the shared label core.
private func _fillColorString(_ style: Any?) -> ColorString? {
    guard let d = style as? [String: Any], let f = d["fill"] else { return nil }
    if let str = f as? String { return str }
    if let zr = f as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// upstream nested `getLabelAttr(model, name)`: for the NORMAL state this is just a direct read
//   (state-attr-with-normal-fallback collapses to the normal model itself).
private func _labelAttr(_ normalLabelModel: Model, _ name: String) -> Any? {
    return normalLabelModel.get(name)
}

// Build a `SectorShape` from the per-node layout dict stored by sunburstLayout
//   (keys: cx/cy/r0/r/startAngle/endAngle/clockwise/angle). Mirrors PieView.sectorShapeFromItemLayout.
private func sectorShapeFromLayout(_ layout: [String: Any]) -> SectorShape {
    var shape = SectorShape()
    shape.cx = (layout["cx"] as? Double) ?? 0
    shape.cy = (layout["cy"] as? Double) ?? 0
    shape.r0 = (layout["r0"] as? Double) ?? 0
    shape.r = (layout["r"] as? Double) ?? 0
    shape.startAngle = (layout["startAngle"] as? Double) ?? 0
    shape.endAngle = (layout["endAngle"] as? Double) ?? (Double.pi * 2)
    shape.clockwise = (layout["clockwise"] as? Bool) ?? true
    return shape
}

// export default SunburstPiece;  -> `open class SunburstPiece` above.
