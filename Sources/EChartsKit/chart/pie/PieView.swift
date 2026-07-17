// Ported from echarts/src/chart/pie/PieView.ts — keep in sync with upstream
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
//   import { clone, extend, retrieve3 } from 'zrender/src/core/util';  -> `util.clone` / `util.extend` /
//       `util.retrieve3` (ZRenderKit).
//   import * as graphic from '../../util/graphic';
//       -> `Sector` / `Text` / `Polyline` are the ZRenderKit shapes. PORT-NOTE: `util/graphic` (util/graphic.swift,
//          which re-exports `initProps`/`updateProps` from animation/basicTransition + `removeElementWithFadeOut`)
//          is ported; the PieView static render still omits the animation calls (see the PiePiece PORT-NOTE block).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> util/states.swift (ported); the PieView static render omits states/emphasis wiring.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { Payload, ColorString } from '../../util/types';       -> util/types.swift.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import PieSeriesModel, {PieDataItemOption, SERIES_TYPE_PIE} from './PieSeries';  -> sibling PieSeries.swift.
//   import labelLayout from './labelLayout';                       -> `pieLabelLayout` (sibling
//       labelLayout.swift); wired in render() after every sector is built.
//   import { setLabelLineStyle, getLabelLineStatesModels } from '../../label/labelGuideHelper';
//       -> label/labelGuideHelper.swift. The leader-line Polyline IS drawn (line style inlined in
//          `_updateLabel`, points filled by `pieLabelLayout`); the state-driven `setLabelLineStyle`/
//          `getLabelLineStatesModels` helpers themselves remain DEFERRED.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> label/labelStyle.swift (`setLabelStyle`/`getLabelStatesModels`); wired in `_updateLabel`.
//   import { getSectorCornerRadius } from '../helper/sectorHelper';
//       -> chart/helper/sectorHelper.swift (ported); PieView still defaults cornerRadius to `0` (getSectorCornerRadius
//          not wired here), so the plain SectorShape from the item layout suffices for a static render.
//   import { saveOldStyle } from '../../animation/basicTransition';  -> `saveOldStyle` IS ported
//       (animation/basicTransition.swift) and NOW wired: the `.update` (firstCreate:false) branch of
//       `updatePieSectorData` calls it before `updateProps`-tweening the reused sector's shape.
//   import { getSeriesLayoutData } from './pieLayout';             -> `getSeriesLayoutData` (sibling pieLayout.swift).

// ================================================================================================
// upstream: class PiePiece extends graphic.Sector { constructor(...); updateData(...); _updateLabel(...) }
//
// PORT-NOTE: `PiePiece` is modeled as a plain ZRenderKit `Sector` (the sanctioned DRAWING deviation —
//   no Sector subclass) built + mutated by `createPiePiece` / `updatePieSectorData` / `_updateLabel`,
//   which are the port of the PiePiece constructor + `updateData` + `_updateLabel`. `render` runs the
//   upstream `data.diff(oldData).add/update/remove(...).execute()` (NOT a `group.removeAll()` rebuild),
//   so each sector's element identity is RETAINED across a merge-mode `setOption` refresh and its shape
//   is `updateProps`-TWEENED to the new layout — the reset-on-update fix (cf. GaugeView, commit 8bf756e).
//   Now wired: `graphic.initProps` (the expansion enter on `.add`), `graphic.updateProps` (the shape
//   tween on `.update`), `saveOldStyle`, `removeElementWithFadeOut` (the `.remove` fade-out), the
//   label / leader-line subsystem (`setLabelStyle` / `getLabelStatesModels` / `setTextGuideLine` +
//   `pieLabelLayout`), and states / emphasis (`setStatesStylesFromModel`, `toggleHoverEmphasis`,
//   `ensureState('emphasis')` radius grow).
// STILL DEFERRED (unchanged): the state-driven `setLabelLineStyle`/`getLabelLineStatesModels`
//   labelGuideHelper helpers; the `select`-state `selectedOffset` dx/dy translate (exploded slice) and
//   the blur focus fan-out; the SSR `scaleX/scaleY` enter branch and the `animationType === 'scale'`
//   r-grow enter (the expansion sweep is the port's chosen enter form); and the
//   `getSectorCornerRadius(...)` corner-radius merges (chart/helper/sectorHelper is ported but not wired
//   here — cornerRadius defaults to `0`).
// ================================================================================================

// upstream: class PieView extends ChartView
open class PieView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_PIE;  /  readonly type = SERIES_TYPE_PIE;
    public static let pieType = SERIES_TYPE_PIE
    open override var type: String {
        get { SERIES_TYPE_PIE }
        set { /* readonly upstream */ }
    }

    private var _data: SeriesData?
    // upstream: private _emptyCircleSector: graphic.Sector;
    private var _emptyCircleSector: Sector?

    public override init() {
        super.init()
        // upstream: ignoreLabelLineUpdate = true;  (class-field default; label line handled in-chart)
        self.ignoreLabelLineUpdate = true
    }

    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: PieSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! PieSeriesModel

        let data = seriesModel.getData()

        let oldData = self._data
        let group = self.group

        // upstream: `let startAngle: number;` (starts `undefined`) — kept for provenance. Only consumed
        //   by the expansion draw-on animation in `PiePiece` (deferred), so it is otherwise unused here.
        var startAngle: Double = Double.nan
        // First render
        if oldData == nil && data.count() > 0 {
            // let shape = data.getItemLayout(0);
            var shape = data.getItemLayout(0) as? [String: Any]
            // for (let s = 1; isNaN(shape && shape.startAngle) && s < data.count(); ++s) { shape = ...; }
            //   `isNaN(shape && shape.startAngle)`: a nil shape is falsy → isNaN(undefined) === true.
            var s = 1
            while pieShapeStartAngleIsNaN(shape) && s < data.count() {
                shape = data.getItemLayout(s) as? [String: Any]
                s += 1
            }
            if let shape = shape {
                startAngle = (shape["startAngle"] as? Double) ?? Double.nan
            }
        }
        _ = startAngle  // consumed by the enter-expansion animation on the `.add` path only.

        // ------------------------------------------------------------------------------------------
        // upstream: data.diff(oldData).add/update/remove(...).execute();
        //
        // RESET-ON-UPDATE FIX (was: STATIC render deviation). The port previously did `group.removeAll()`
        //   here and rebuilt one Sector per datum every render, so every merge-mode `setOption` refresh
        //   destroyed all sectors and replayed the ENTER animation (the expansion sweep) from scratch
        //   instead of TWEENING each sector to the new layout — the same disease as the GaugeView reset
        //   bug (commit 8bf756e). The group is now NO LONGER wiped; `data.diff(oldData)` routes each
        //   datum through `.add` (first appearance — the existing expansion enter) / `.update` (reuse the
        //   retained sector and `updateProps`-tween its shape+style to the new layout) / `.remove` (fade
        //   the orphan out). Labels + leader lines ride along, attached to each reused sector.
        // ------------------------------------------------------------------------------------------

        // remove empty-circle if it exists
        // upstream: if (this._emptyCircleSector) { group.remove(this._emptyCircleSector); }
        //   The group is no longer blanket-cleared, so the previous empty-circle sector (if any) must be
        //   removed explicitly — exactly as upstream does (its render likewise never wipes the group).
        if let emptyCircle = self._emptyCircleSector {
            _ = group.remove(emptyCircle)
            self._emptyCircleSector = nil
        }

        // when all data are filtered, show lightgray empty circle
        if data.count() == 0 && ((seriesModel.get("showEmptyCircle") as? Bool) ?? false) {
            let layoutData = getSeriesLayoutData(seriesModel)
            // const sector = new graphic.Sector({ shape: clone(layoutData) });
            //   `layoutData` is the `PieSeriesLayoutData` record (cx/cy/r/r0/startAngle/endAngle/clockwise);
            //   cloned into a fresh `SectorShape`.
            let sector = Sector(["shape": sectorShapeFromLayoutData(util.clone(layoutData)) as PathShape])
            // sector.useStyle(seriesModel.getModel('emptyCircleStyle').getItemStyle());
            sector.useStyle(barStyleFromDict(seriesModel.getModel("emptyCircleStyle").getItemStyle()))
            self._emptyCircleSector = sector
            _ = group.add(sector)
        }

        // upstream: data.diff(oldData).add(...).update(...).remove(...).execute();
        data.diff(oldData)
            .add { idx in
                // upstream: `const piePiece = new PiePiece(data, idx, startAngle); ...; group.add(piePiece)`.
                let piePiece = self.createPiePiece(data, idx, startAngle, seriesModel)
                data.setItemGraphicEl(idx, piePiece)
                _ = group.add(piePiece)
            }
            .update { newIdx, oldIdx in
                // upstream: `const piePiece = oldData.getItemGraphicEl(oldIdx) as PiePiece;
                //   piePiece.updateData(data, newIdx, startAngle); piePiece.off('click');
                //   group.add(piePiece); data.setItemGraphicEl(newIdx, piePiece);`
                //   REUSE the retained sector — this is the fix. `updateData(..., firstCreate:false)`
                //   tweens instead of re-entering.
                guard let piePiece = oldData?.getItemGraphicEl(oldIdx) as? Sector else {
                    // Defensive: no retained element to reuse (should not happen) — create fresh.
                    let created = self.createPiePiece(data, newIdx, startAngle, seriesModel)
                    data.setItemGraphicEl(newIdx, created)
                    _ = group.add(created)
                    return
                }
                self.updatePieSectorData(piePiece, data, newIdx, startAngle, false, seriesModel)
                // upstream `piePiece.off('click')` — no per-piece click handler is bound in the port,
                //   so there is nothing to detach (provenance note).
                _ = group.add(piePiece)
                data.setItemGraphicEl(newIdx, piePiece)
            }
            .remove { oldIdx in
                // upstream: `graphic.removeElementWithFadeOut(oldData.getItemGraphicEl(idx), seriesModel, idx)`.
                if let piePiece = oldData?.getItemGraphicEl(oldIdx) {
                    removeElementWithFadeOut(piePiece, seriesModel, oldIdx)
                }
            }
            .execute()

        // labelLayout(seriesModel);
        //   L1c: chart/pie/labelLayout.swift places outer labels + leader lines and resolves
        //   vertical overlap (avoidOverlap → shiftLayoutOnXY). Runs AFTER every sector (and its
        //   label + labelLine) is built, matching upstream (labelLayout reads the finished shapes).
        pieLabelLayout(seriesModel)

        // Always use initial animation.
        // upstream: if (seriesModel.get('animationTypeUpdate') !== 'expansion') { this._data = data; }
        //   Under 'expansion' `_data` is deliberately NOT retained, so the next render sees oldData == nil
        //   and every piece routes through `.add` (replaying the expansion enter) rather than tweening —
        //   the upstream behavior for that update mode.
        if (seriesModel.get("animationTypeUpdate") as? String) != "expansion" {
            self._data = data
        }
    }

    // upstream: `new PiePiece(data, idx, startAngle)` — the PiePiece constructor sets `z2 = 2`, attaches
    //   an (empty) Text child, then calls `updateData(data, idx, startAngle, firstCreate: true)`. Modeled
    //   here as a plain ZRenderKit `Sector` (the sanctioned DRAWING deviation — no PiePiece subclass),
    //   built by `updatePieSectorData` with firstCreate == true.
    private func createPiePiece(
        _ data: SeriesData, _ idx: Int, _ startAngle: Double, _ seriesModel: PieSeriesModel
    ) -> Sector {
        let sector = Sector()
        // upstream `PiePiece` constructor: `this.z2 = 2;`
        sector.z2 = 2
        // Name the piece 'item' (matches BarView's per-datum element name; upstream `PiePiece` leaves it
        //   unset — a harmless, non-load-bearing addition for hit-testing/debug parity).
        sector.name = "item"
        updatePieSectorData(sector, data, idx, startAngle, true, seriesModel)
        return sector
    }

    // upstream: PiePiece.updateData(data, idx, startAngle?, firstCreate?) (PieView.ts:56-171).
    //   firstCreate == true  → first appearance: seed the collapsed shape + `initProps` the enter sweep.
    //   firstCreate == false → refresh: `saveOldStyle` + `updateProps`-TWEEN the whole shape from the
    //     sector's CURRENT (previous-layout) angles/radii to the new layout. Reusing the SAME sector
    //     object (the diff `.update` path) both preserves its identity and drives the tween — the
    //     reset-on-update fix. Style/states/label are (re)applied for every datum, either way.
    //   PORT-NOTE (deferred, unchanged): the `select`-state selectedOffset dx/dy (exploded slice) +
    //     blur focus fan-out + getSectorCornerRadius corner-radius merges are still omitted (cornerRadius
    //     defaults to 0); the SSR scaleX/scaleY branch and the `animationType === 'scale'` r-grow enter
    //     are likewise not wired (the expansion enter below is the port's chosen form).
    private func updatePieSectorData(
        _ sector: Sector, _ data: SeriesData, _ idx: Int,
        _ startAngle: Double, _ firstCreate: Bool, _ seriesModel: PieSeriesModel
    ) {
        // `startAngle` is consumed only by upstream's shared-running expansion form; the independent
        //   collapsed-sweep used by the firstCreate branch below opens each sector from its OWN
        //   startAngle, so it needs no cross-piece threading. Kept in the signature for provenance.
        _ = startAngle

        // const layout = data.getItemLayout(idx) as graphic.Sector['shape'];
        guard let layout = data.getItemLayout(idx) as? [String: Any] else {
            return
        }
        // const sectorShape = extend(getSectorCornerRadius(...), layout);
        //   cornerRadius/innerCornerRadius default to `0` (getSectorCornerRadius deferred), so the
        //   plain layout → SectorShape mapping is faithful.
        let sectorShape = sectorShapeFromItemLayout(layout)

        // Ignore NaN data. upstream: `sector.setShape(sectorShape); return;` — set the (NaN) shape so the
        //   sector draws nothing, and skip styling/label.
        if sectorShape.startAngle.isNaN {
            _ = sector.setShape(sectorShape)
            return
        }

        if firstCreate {
            // Entrance (upstream PiePiece expansion) — KEEP the existing independent collapsed-sweep so
            //   the first-frame behavior is unchanged: seed the sector collapsed (endAngle == startAngle)
            //   and sweep endAngle open to the final layout angle via initProps. Shape props MUST be a
            //   dict of animatable fields (a full SectorShape struct is opaque to the animator — the
            //   struct->dict rule). Instant (final angle, no animator) when the series' animation is off.
            let finalEndAngle = sectorShape.endAngle
            var collapsedShape = sectorShape
            collapsedShape.endAngle = sectorShape.startAngle
            _ = sector.setShape(collapsedShape)
            initProps(sector, ["shape": ["endAngle": finalEndAngle] as [String: Any]], seriesModel, idx)
        } else {
            // upstream: `saveOldStyle(sector); graphic.updateProps(sector, { shape: sectorShape }, ...)`.
            //   TWEEN the whole shape from the reused sector's current angles/radii to the new layout.
            //   The animatable numeric fields are passed as a dict (struct->dict rule); `clockwise`/
            //   `cornerRadius` are not animated (they do not change across a pie refresh).
            saveOldStyle(sector)
            updateProps(sector, ["shape": [
                "cx": sectorShape.cx, "cy": sectorShape.cy,
                "r0": sectorShape.r0, "r": sectorShape.r,
                "startAngle": sectorShape.startAngle, "endAngle": sectorShape.endAngle
            ] as [String: Any]], seriesModel, idx)
        }

        // sector.useStyle(data.getItemVisual(idx, 'style'));
        //   The item visual 'style' bag is bridged to a typed `PathStyleProps` (palette fill etc.) via
        //   `barStyleFromDict` (BarView.swift) — the shared visual-style → PathStyleProps bridge.
        sector.useStyle(barStyleFromDict(data.getItemVisual(idx, "style")))

        // upstream (PiePiece.updateData): the sector is a highDown dispatcher carrying its emphasis-state
        //   itemStyle so a hover restyles it. Mirror BarView.updateStyle.
        let itemModel = data.getItemModel(idx)
        let emphasisModel = itemModel.getModel(["emphasis"])
        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        states.toggleHoverEmphasis(sector, focus, blurScope, isDisabled)
        states.setStatesStylesFromModel(sector, itemModel)

        // upstream (PieView.ts:142-145): the emphasis state grows the outer radius by `scaleSize` when
        //   `emphasis.scale` is on — the hover "enlarge" effect.
        let scaleOn = (emphasisModel.get("scale") as? Bool) ?? false
        let scaleSize = symbolAsDouble(emphasisModel.get("scaleSize")) ?? 0   // Int/Double/NSNumber
        sector.ensureState("emphasis").shape = ["r": sectorShape.r + (scaleOn ? scaleSize : 0)]

        // Label + leader line (upstream PiePiece._updateLabel).
        _updateLabel(sector, seriesModel, data, idx)
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    // upstream: containPoint(point: number[], seriesModel: PieSeriesModel): boolean
    open override func containPoint(_ point: [Double], _ seriesModelBase: SeriesModel) -> Bool {
        let seriesModel = seriesModelBase as! PieSeriesModel
        let data = seriesModel.getData()
        let itemLayout = data.getItemLayout(0) as? [String: Any]
        if let itemLayout = itemLayout {
            let cx = (itemLayout["cx"] as? Double) ?? Double.nan
            let cy = (itemLayout["cy"] as? Double) ?? Double.nan
            let r = (itemLayout["r"] as? Double) ?? Double.nan
            let r0 = (itemLayout["r0"] as? Double) ?? Double.nan
            let dx = point[0] - cx
            let dy = point[1] - cy
            let radius = (dx * dx + dy * dy).squareRoot()
            return radius <= r && radius >= r0
        }
        // upstream returns `undefined` (falsy) when there is no item layout.
        return false
    }

    // upstream: PiePiece._updateLabel(seriesModel, data, idx) (PieView.ts:173-227).
    //   Retrofit onto the shared label core: `labelStyle.setLabelStyle` creates/attaches the label as
    //   the sector's textContent (the painter renders textContent automatically) and stamps the
    //   sector's textConfig from the label model's `position`/`rotate`/`distance`.
    //
    // DEFERRED (L1c, unchanged from upstream's own deferral notes above): the leader-line
    //   (`setTextGuideLine`/`setLabelLineStyle` Polyline) and `labelLayout` collision-avoidance /
    //   absolute re-placement are NOT ported — text only for now.
    //
    // PORT DEVIATION: upstream follows `setLabelStyle` with
    //   `sector.setTextConfig({ position: null, rotation: null })`, delegating final placement to
    //   `labelLayout`. Since `labelLayout` is DEFERRED, that reset would leave the label unpositioned;
    //   we instead KEEP the textConfig `position` (e.g. pie default `'outer'`) that `createTextConfig`
    //   derived from the label model, so the painter places the label relative to the sector.
    private func _updateLabel(_ sector: Sector, _ seriesModel: PieSeriesModel, _ data: SeriesData, _ idx: Int) {
        let itemModel = data.getItemModel(idx)

        // const style = data.getItemVisual(idx, 'style');
        // const visualColor = style && style.fill; const visualOpacity = style && style.opacity;
        let visualStyle = data.getItemVisual(idx, "style") as? [String: Any]
        let visualColor: ColorString? = pieFillToString(visualStyle?["fill"])
        let visualOpacity = visualStyle?["opacity"] as? Double

        // setLabelStyle(sector, getLabelStatesModels(itemModel), { labelFetcher, labelDataIndex,
        //   inheritColor, defaultOpacity, defaultText: getFormattedLabel(idx,'normal') || getName(idx) })
        //   `sector` is the (reused-or-fresh) PiePiece; `setLabelStyle` REUSES the sector's existing
        //   textContent when present (so a refreshed sector keeps its label element identity).
        let models = labelStyle.getLabelStatesModels(itemModel)
        let opt = SetLabelStyleOpt(
            inheritColor: visualColor,
            defaultOpacity: visualOpacity,
            // upstream: `getFormattedLabel(idx, 'normal') || data.getName(idx)` — no formatter yields
            //   nil, so the datum name is the default label text.
            defaultText: seriesModel.getFormattedLabel(Double(idx), .normal) ?? data.getName(idx),
            labelFetcher: seriesModel,
            labelDataIndex: Double(idx)
        )
        labelStyle.setLabelStyle(sector, models, opt)

        // upstream: `labelText.attr({ z2: 10 })`.
        if let labelText = sector.getTextContent() {
            labelText.z2 = 10
        }

        // Leader-line (labelLine) — L1c. Upstream calls
        //   `setLabelLineStyle(sector, getLabelLineStatesModels(itemModel), ...)`; that state-driven
        //   helper is still DEFERRED, so the line style is inlined here (mirrors FunnelView): a
        //   stroke-only Polyline attached as the sector's textGuideLine. Its POINTS are filled later
        //   by `pieLabelLayout` (which also flips `ignore` for inside / hidden labels).
        //   REUSE the existing guide line on a refresh (upstream: `let polyline = getTextGuideLine();
        //   if (!polyline) { polyline = new Polyline(); setTextGuideLine(polyline); }`) so the reused
        //   sector keeps its leader-line element identity.
        let labelLineModel = itemModel.getModel("labelLine")
        if (labelLineModel.get("show") as? Bool) != false {
            let line: Polyline
            if let existing = sector.getTextGuideLine() {
                line = existing
            } else {
                line = Polyline()
                sector.setTextGuideLine(line)
            }
            var lstyle = barStyleFromDict(labelLineModel.getLineStyle())
            if lstyle.stroke == nil, let vc = visualColor { lstyle.stroke = .string(vc) }
            line.useStyle(lstyle)
            // A stroke-only leader line must not keep the black default fill.
            line.pathStyle.fill = nil
            line.z2 = 10
        } else if sector.getTextGuideLine() != nil {
            // `labelLine.show: false` on a refresh: drop the previously-attached leader line.
            sector.removeTextGuideLine()
        }
    }
}

// Auto-contrast colour for a label drawn INSIDE a filled element (pie sector / graph node / sunburst
//   sector): white text over a dark fill, dark text over a light fill — the upstream inside-label
//   contrast rule. `color.lum` returns luminance in 0…1 (higher = lighter). Module-internal so the
//   graph/sunburst inside labels can share it.
func insideAutoTextColor(_ fill: String?) -> String {
    guard let fill = fill else { return "#ffffff" }
    return ZRenderKit.color.lum(fill, 0) > 0.5 ? "#333333" : "#ffffff"
}

// Bridge an item-visual `fill` (ZRColor / String / palette ZRColor) to a colour STRING for the pie label.
private func pieFillToString(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    // The item-visual palette fill is an EChartsKit.ZRColor `.color(String)`.
    if let z = v as? EChartsKit.ZRColor, case let .color(s) = z { return s }
    return nil
}

// Models upstream `isNaN(shape && shape.startAngle)`: a nil (falsy) shape yields `isNaN(undefined)`
//   === true; otherwise it is `isNaN(shape.startAngle)`.
private func pieShapeStartAngleIsNaN(_ shape: [String: Any]?) -> Bool {
    guard let shape = shape else { return true }
    let startAngle = (shape["startAngle"] as? Double) ?? Double.nan
    return startAngle.isNaN
}

// Build a `SectorShape` from the per-item layout dict stored by `pieLayout` (keys: cx/cy/r0/r/
//   startAngle/endAngle/clockwise). `startAngle` may be NaN for NaN data (the caller NaN-guards).
private func sectorShapeFromItemLayout(_ layout: [String: Any]) -> SectorShape {
    var shape = SectorShape()
    shape.cx = (layout["cx"] as? Double) ?? Double.nan
    shape.cy = (layout["cy"] as? Double) ?? Double.nan
    shape.r0 = (layout["r0"] as? Double) ?? Double.nan
    shape.r = (layout["r"] as? Double) ?? Double.nan
    shape.startAngle = (layout["startAngle"] as? Double) ?? Double.nan
    shape.endAngle = (layout["endAngle"] as? Double) ?? Double.nan
    shape.clockwise = (layout["clockwise"] as? Bool) ?? true
    return shape
}

// Build a `SectorShape` from the `PieSeriesLayoutData` record (the empty-circle branch).
private func sectorShapeFromLayoutData(_ d: PieSeriesLayoutData) -> SectorShape {
    var shape = SectorShape()
    shape.cx = d.cx
    shape.cy = d.cy
    shape.r0 = d.r0
    shape.r = d.r
    shape.startAngle = d.startAngle
    shape.endAngle = d.endAngle
    shape.clockwise = d.clockwise
    return shape
}

// export default PieView;  -> `open class PieView` above.
