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
//       `graphic.initProps`/`updateProps` are the animation helpers — ported (animation/basicTransition.swift)
//       and wired below (sector entrance sweep / shape morph).
//   import { toggleHoverEmphasis, SPECIAL_STATES, DISPLAY_STATES } from '../../util/states';
//       -> states.toggleHoverEmphasis / states.SPECIAL_STATES / states.DISPLAY_STATES (util/states.swift).
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
//   import { createOrUpdatePatternFromDecal } from '../../util/decal';  -> `createOrUpdatePatternFromDecal` (util/decal.swift, ported).
//   import ExtensionAPI from '../../core/ExtensionAPI';             -> `ExtensionAPI`.
//   import { saveOldStyle } from '../../animation/basicTransition'; -> `saveOldStyle` (animation/basicTransition.swift;
//       real since universalTransition landed — the makeInner-backed saved style).
//   import { normalizeRadian } from 'zrender/src/contain/util';     -> `contain_util.normalizeRadian` (ZRenderKit) — used by the deferred label-rotation math.
//   import { isRadianAroundZero } from '../../util/number';         -> `number.isRadianAroundZero` — used by the deferred label-rotation math.

// upstream: const DEFAULT_SECTOR_Z = 2;
private let DEFAULT_SECTOR_Z: Double = 2
// upstream: const DEFAULT_TEXT_Z = 4;
private let DEFAULT_TEXT_Z: Double = 4

// upstream: interface DrawTreeNode extends TreeNode { piece: SunburstPiece }
// PORT-NOTE: Swift `TreeNode` (sibling) is a `final class` that can not be externally augmented with a
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
        // PORT-NOTE: `node.piece` write-back dropped — TreeNode carries no `piece` slot (see the
        //   DrawTreeNode PORT-NOTE above). Not needed by the static SunburstView.render().

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
        //   PORT-NOTE: `node.getModel()` is `Model?` and returns nil for a node with dataIndex < 0
        //   (the roll-up virtualRoot). Upstream assumes non-null; we guard defensively — a node with no
        //   item model can not be styled/labelled, so bail (no sector body drawn for it).
        guard let itemModel = node.getModel() else {
            return
        }
        // const emphasisModel = itemModel.getModel('emphasis');
        let emphasisModel = itemModel.getModel("emphasis")
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
        let decal = node.getVisual("decal")
        if decal != nil, let pat = createOrUpdatePatternFromDecal(decal, api) {
            normalStyle.decal = pat
        }

        // const cornerRadius = getSectorCornerRadius(itemModel.getModel('itemStyle'), sectorShape, true);
        // zrUtil.extend(sectorShape, cornerRadius);
        if let cornerRadius = getSectorCornerRadius(itemModel.getModel("itemStyle"), sectorShape, true) {
            sectorShape.cornerRadius = cornerRadius
        }

        // zrUtil.each(SPECIAL_STATES, function (stateName) { ... ensureState ... getSectorCornerRadius ... });
        //   The per-state itemStyle half of this upstream loop (`state.style =
        //   itemModel.getModel([stateName, 'itemStyle']).getItemStyle()` over emphasis/blur/select) IS
        //   wired via `states.setStatesStylesFromModel` further down (search for that call — it iterates
        //   the same SPECIAL_STATES and stores each state's itemStyle onto `ensureState(name).style`;
        //   it is kept at its ported position because it also has to run after `useStyle`).
        //   The corner-radius half of the same loop is ported HERE, at upstream's position (it is the
        //   part `setStatesStylesFromModel` does NOT cover — that writes `.style`, never `.shape`):
        //       const cornerRadius = getSectorCornerRadius(itemStyleModel, sectorShape);
        //       if (cornerRadius) { state.shape = cornerRadius; }
        //   `state.shape` is the dynamic prop bag, and upstream ASSIGNS the whole `{cornerRadius}`
        //   object returned by `getSectorCornerRadius`, so the ported form assigns a fresh one-key bag
        //   (not a merge) — same idiom as PieView's select/blur states.
        //   `SectorShape.animationGet`/`animationSet` both expose `cornerRadius` (Sector.swift), which is
        //   what carries it through the state machinery: `animationSet` applies the per-state value on
        //   ENTER and `animationGet` is what `Element._innerSaveToNormal` records so state EXIT restores
        //   the normal radius. It is not numerically tweened (a discrete jump), matching upstream, which
        //   only extends/assigns the shape.
        for stateName in EChartsKit.states.SPECIAL_STATES {
            let state = sector.ensureState(stateName)
            let itemStyleModel = itemModel.getModel([stateName, "itemStyle"])
            if let cornerRadius = getSectorCornerRadius(itemStyleModel, sectorShape) {
                state.shape = ["cornerRadius": cornerRadius]
            }
        }

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
            // MORPH: a merge-mode value change (or a same-count drill re-root) recomputes this node's
            //   angular span; animate the numeric Sector shape keys (SectorShape.animationSet tweens
            //   cx/cy/r0/r/startAngle/endAngle) so the wedge SWEEPS to its new geometry rather than
            //   snapping. The non-animated fields (clockwise, cornerRadius) are stamped onto the CURRENT
            //   shape first (angles preserved) so updateProps only tweens the numeric span, then animate.
            //   Instant (duration 0) when the series' animation is disabled — same as `attr`.
            if var cur = sector.shape as? SectorShape {
                cur.clockwise = sectorShape.clockwise
                cur.cornerRadius = sectorShape.cornerRadius
                _ = sector.setShape(cur)
            }
            updateProps(sector, ["shape": [
                "cx": sectorShape.cx,
                "cy": sectorShape.cy,
                "r0": sectorShape.r0,
                "r": sectorShape.r,
                "startAngle": sectorShape.startAngle,
                "endAngle": sectorShape.endAngle
            ] as [String: Any]], seriesModel, node.dataIndex)
            // saveOldStyle(sector);  — universalTransition style save.
            saveOldStyle(sector)
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

        // ── Per-state (emphasis/blur/select) itemStyle on the sector body ──
        //   upstream sets these inside the `SPECIAL_STATES` loop (ensureState(name).style =
        //   itemModel.getModel([name,'itemStyle']).getItemStyle()); `setStatesStylesFromModel` is the
        //   ported form of that loop's STYLE half; the corner-radius half of the same upstream loop is
        //   ported at its upstream position — see the `SPECIAL_STATES` loop above (which writes
        //   `ensureState(name).shape`). The label's per-state text styles are already installed by
        //   `setLabelStyle` in `_updateLabel` (getLabelStatesModels), so the sector body is all that
        //   remains here. Mirrors PieView / GraphView.
        // NOTE: `states` (the ported util/states enum) is qualified with the module name because a
        //   `Sector` (this class's superclass) already has an inherited `states` element-state dictionary
        //   that would otherwise shadow the enum inside instance methods.
        EChartsKit.states.setStatesStylesFromModel(sector, itemModel)

        // const focus = emphasisModel.get('focus');
        // const focusOrIndices = focus === 'relative'
        //     ? zrUtil.concatArray(node.getAncestorsIndices(), node.getDescendantIndices())
        //     : focus === 'ancestor' ? node.getAncestorsIndices()
        //         : focus === 'descendant' ? node.getDescendantIndices()
        //             : focus;
        //   Sunburst-specific focus modes ('relative'/'ancestor'/'descendant') resolve to a tree-adjacency
        //   index list (like graph adjacency); any other value ('self'/'none'/'series' or an explicit
        //   array) passes straight through to `toggleHoverEmphasis` unchanged.
        let focus = emphasisModel.get("focus")
        let focusOrIndices: InnerFocus?
        switch focus as? String {
        case "relative":
            focusOrIndices = node.getAncestorsIndices() + node.getDescendantIndices()
        case "ancestor":
            focusOrIndices = node.getAncestorsIndices()
        case "descendant":
            focusOrIndices = node.getDescendantIndices()
        default:
            focusOrIndices = focus
        }

        // toggleHoverEmphasis(this, focusOrIndices, emphasisModel.get('blurScope'), emphasisModel.get('disabled'));
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        EChartsKit.states.toggleHoverEmphasis(sector, focusOrIndices, blurScope, isDisabled)
    }

    // upstream: _updateLabel(seriesModel)
    func _updateLabel(_ seriesModel: SunburstSeriesModel) {
        // const itemModel = this.node.getModel<SunburstSeriesNodeItemOption>();
        //   PORT-NOTE: `Model?` — nil for dataIndex < 0 (roll-up virtualRoot); bail defensively (no label).
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
        //   The per-state (emphasis/blur/select) branch of the same loop is ported below (see the
        //   SPECIAL_STATES placement loop after this normal block); setLabelStyle already supplied all
        //   four states' text/style above.
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

        // ── Per-state (emphasis/blur/select) placement — the non-normal iterations of upstream's
        //    DISPLAY_STATES loop. Each state recomputes the SAME position/align/rotate math (with a
        //    per-state-model-with-normal-fallback read, upstream's nested `getLabelAttr`) and writes
        //    x/y/rotation onto `label.ensureState(name)` (applied generically by `Element._stateApply`
        //    on state entry) plus align/verticalAlign merged onto the per-state `textStyle` that
        //    setLabelStyle installed (applied by `ZRText._applyStateTextStyle`), and outsideFill/inside
        //    onto the sector's per-state `textConfig`. The label text/style itself is already installed
        //    per-state by `setLabelStyle` above (the migrated form of upstream's inline `createTextStyle`).
        //   upstream nested: `getLabelAttr(model, name)` == `model.get(name) ?? normalLabelModel.get(name)`.
        func getLabelAttr(_ model: Model, _ name: String) -> Any? {
            if let stateAttr = model.get(name) { return stateAttr }
            return normalLabelModel.get(name)
        }
        for stateName in EChartsKit.states.SPECIAL_STATES {
            // const labelStateModel = itemModel.getModel([stateName, 'label']);
            let labelStateModel = itemModel.getModel([stateName, "label"])
            let sLabelState = label.ensureState(stateName)

            // const isShown = labelStateModel.get('show'); if (isShown != null && !isNormal) state.ignore = !isShown;
            if let isShown = labelStateModel.get("show") as? Bool {
                sLabelState.ignore = !isShown
            }

            // const labelPosition = getLabelAttr(labelStateModel, 'position');
            let sPosition = getLabelAttr(labelStateModel, "position") as? String
            // const labelPadding = getLabelAttr(labelStateModel, 'distance') || 0;
            let sPadding = (getLabelAttr(labelStateModel, "distance") as? Double) ?? 0
            // let textAlign = getLabelAttr(labelStateModel, 'align');
            var sAlign = getLabelAttr(labelStateModel, "align") as? String
            // const rotateType = getLabelAttr(labelStateModel, 'rotate');
            let sRotateType = getLabelAttr(labelStateModel, "rotate")

            // const midAngleNormal = normalizeRadian(rotateType === 'tangential' ? PI/2 - midAngle : midAngle);
            let sMidAngleNormal = containUtil.normalizeRadian(
                (sRotateType as? String) == "tangential" ? (Double.pi / 2 - midAngle) : midAngle
            )
            let sNeedsFlip = sMidAngleNormal > flipStartAngle
                && !number.isRadianAroundZero(sMidAngleNormal - flipStartAngle)
                && sMidAngleNormal < flipEndAngle

            var sR: Double
            if sPosition == "outside" {
                sR = rLayout + sPadding
                sAlign = sNeedsFlip ? "right" : "left"
            }
            else {
                if sAlign == nil || sAlign == "center" {
                    if r0Layout == 0 && number.isRadianAroundZero(angle - 2 * Double.pi) {
                        sR = 0
                    }
                    else {
                        sR = (rLayout + r0Layout) / 2
                    }
                    sAlign = "center"
                }
                else if sAlign == "left" {
                    sR = r0Layout + sPadding
                    sAlign = sNeedsFlip ? "right" : "left"
                }
                else if sAlign == "right" {
                    sR = rLayout - sPadding
                    sAlign = sNeedsFlip ? "left" : "right"
                }
                else {
                    sR = (rLayout + r0Layout) / 2
                }
            }

            // state.style.align / verticalAlign — merge onto the per-state textStyle setLabelStyle installed.
            var sStyle = sLabelState.textStyle ?? TextStyleProps()
            if let a = sAlign, let ta = TextAlign(rawValue: a) { sStyle.align = ta }
            let sVAlign = (getLabelAttr(labelStateModel, "verticalAlign") as? String) ?? "middle"
            if let va = TextVerticalAlign(rawValue: sVAlign) { sStyle.verticalAlign = va }
            sLabelState.textStyle = sStyle

            // state.x = r * dx + layout.cx; state.y = r * dy + layout.cy;
            sLabelState.x = sR * dx + cx
            sLabelState.y = sR * dy + cy

            var sRotate = 0.0
            if let s = sRotateType as? String {
                if s == "radial" {
                    sRotate = containUtil.normalizeRadian(-midAngle) + (sNeedsFlip ? Double.pi : 0)
                }
                else if s == "tangential" {
                    sRotate = containUtil.normalizeRadian(Double.pi / 2 - midAngle) + (sNeedsFlip ? Double.pi : 0)
                }
            }
            else if let n = sRotateType as? Double {
                sRotate = n * Double.pi / 180
            }
            else if let n = sRotateType as? Int {
                sRotate = Double(n) * Double.pi / 180
            }
            sLabelState.rotation = containUtil.normalizeRadian(sRotate)

            // sectorState.textConfig = { outsideFill: labelStateModel.get('color') === 'inherit' ? labelColor : null,
            //                            inside: labelPosition !== 'outside' };
            //   labelColor = sectorState.style.fill (the per-state itemStyle fill installed by
            //   setStatesStylesFromModel onto sector.ensureState(name).style).
            let sectorState = sector.ensureState(stateName)
            var sTextConfig = sectorState.textConfig ?? ElementTextConfig()
            sTextConfig.inside = (sPosition != "outside")
            let sLabelColor = _fillColorString(sectorState.style)
            sTextConfig.outsideFill = ((labelStateModel.get("color") as? String) == "inherit") ? sLabelColor : nil
            sectorState.textConfig = sTextConfig
        }

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
