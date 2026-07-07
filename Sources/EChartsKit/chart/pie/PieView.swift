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
//       -> `Sector` / `Text` / `Polyline` are the ZRenderKit shapes. PORT-TODO: `util/graphic` (which
//          re-exports `initProps`/`updateProps` from animation/basicTransition + `removeElementWithFadeOut`)
//          is NOT ported; the animation calls are deferred (see the PiePiece PORT-TODO block).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported (states/emphasis deferred).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import { Payload, ColorString } from '../../util/types';       -> util/types.swift.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import PieSeriesModel, {PieDataItemOption, SERIES_TYPE_PIE} from './PieSeries';  -> sibling PieSeries.swift.
//   import labelLayout from './labelLayout';                       -> PORT-TODO: chart/pie/labelLayout.ts NOT
//       ported (label placement deferred).
//   import { setLabelLineStyle, getLabelLineStatesModels } from '../../label/labelGuideHelper';
//       -> PORT-TODO: label/labelGuideHelper NOT ported (labelLine deferred).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> PORT-TODO: label/labelStyle NOT ported (labels deferred).
//   import { getSectorCornerRadius } from '../helper/sectorHelper';
//       -> PORT-TODO: chart/helper/sectorHelper NOT ported; cornerRadius defaults to `0`, so the plain
//          SectorShape from the item layout suffices for a static render.
//   import { saveOldStyle } from '../../animation/basicTransition';  -> PORT-TODO: NOT ported (deferred).
//   import { getSeriesLayoutData } from './pieLayout';             -> `getSeriesLayoutData` (sibling pieLayout.swift).

// ================================================================================================
// upstream: class PiePiece extends graphic.Sector { constructor(...); updateData(...); _updateLabel(...) }
//
// PORT-TODO (DEFERRED — separate upstream subsystems; a STATIC render faithfully omits them):
//   - `PiePiece` (a Sector carrying a Text child + labelLine Polyline) collapses, for the static render,
//     to a plain ZRenderKit `Sector` built directly in `PieView.render` (see below).
//   - Label / labelLine: `_updateLabel`, `setLabelStyle`, `getLabelStatesModels`, `setLabelLineStyle`,
//     `getLabelLineStatesModels`, `getTextGuideLine`/`setTextGuideLine` (Polyline), `setTextConfig`,
//     and the module-level `labelLayout(seriesModel)` call are all deferred with the label subsystem.
//   - States / emphasis: `setStatesStylesFromModel`, `ensureState('emphasis'|'select'|'blur')`,
//     `toggleHoverEmphasis`, and the `selectedOffset` dx/dy select-state offset are deferred with
//     util/states.
//   - Animation: `graphic.initProps`/`updateProps` (expansion/scale draw-on), `saveOldStyle`,
//     `removeElementWithFadeOut`, and the SSR `scaleX/scaleY` branch are deferred with basicTransition.
//   - `getSectorCornerRadius(itemModel.getModel('itemStyle'), layout, true)` corner-radius merge is
//     deferred (chart/helper/sectorHelper not ported); cornerRadius defaults to `0`.
// Faithful upstream `PiePiece.updateData` body preserved above in the .ts oracle for the eventual port.
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
        _ = startAngle  // consumed by the deferred expansion animation only.

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream diffs `oldData` → `PiePiece` add/update/remove and calls
        //   `labelLayout(seriesModel)`. The SymbolDraw-style diff + PiePiece + label/emphasis/animation
        //   are deferred (see the PiePiece PORT-TODO block), so the group is rebuilt from scratch each
        //   render. Clearing the group also drops any previous empty-circle sector, so the explicit
        //   `group.remove(this._emptyCircleSector)` below is subsumed by `removeAll()`.
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        // remove empty-circle if it exists
        // upstream: if (this._emptyCircleSector) { group.remove(this._emptyCircleSector); }
        self._emptyCircleSector = nil

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

        // upstream: data.diff(oldData).add/update/remove(...).execute();
        //   STATIC replacement — one Sector per datum, straight from the item layout stored by pieLayout.
        for idx in 0..<data.count() {
            // const layout = data.getItemLayout(idx) as graphic.Sector['shape'];
            guard let layout = data.getItemLayout(idx) as? [String: Any] else {
                continue
            }
            // const sectorShape = extend(getSectorCornerRadius(...), layout);
            //   cornerRadius/innerCornerRadius default to `0` (getSectorCornerRadius deferred), so the
            //   plain layout → SectorShape mapping is faithful.
            let sectorShape = sectorShapeFromItemLayout(layout)

            // Ignore NaN data. Upstream sets the NaN shape on the sector to avoid drawing; the static
            //   render simply skips creating a sector for it (no element is added for NaN data).
            if sectorShape.startAngle.isNaN {
                continue
            }

            // Entrance (upstream PiePiece expansion): create the sector collapsed (endAngle ==
            //   startAngle), then sweep endAngle open to the final layout angle via initProps below.
            //   We use the independent-sweep form (each sector opens from its own startAngle), which
            //   needs no cross-piece startAngle threading (unlike upstream's shared running startAngle).
            let finalEndAngle = sectorShape.endAngle
            var collapsedShape = sectorShape
            collapsedShape.endAngle = sectorShape.startAngle
            let sector = Sector(["shape": collapsedShape as PathShape])
            // upstream `PiePiece` sets `this.z2 = 2;` in its constructor.
            sector.z2 = 2
            // sector.useStyle(data.getItemVisual(idx, 'style'));
            //   The item visual 'style' bag is bridged to a typed `PathStyleProps` (palette fill etc.)
            //   via `barStyleFromDict` (BarView.swift) — the shared visual-style → PathStyleProps bridge.
            sector.useStyle(barStyleFromDict(data.getItemVisual(idx, "style")))
            // Name the piece 'item' (matches BarView's per-datum element name; upstream `PiePiece`
            //   leaves it unset — a harmless, non-load-bearing addition for hit-testing/debug parity).
            sector.name = "item"

            // upstream (PiePiece.updateData, PieView.ts): the sector is marked a highDown dispatcher
            //   carrying its emphasis-state itemStyle so a hover restyles it. Mirror BarView.updateStyle.
            //   PORT-TODO (still deferred): the select-state `selectedOffset` dx/dy offset and blur focus
            //   fan-out (upstream computes them in PiePiece) are not applied.
            let itemModel = data.getItemModel(idx)
            let emphasisModel = itemModel.getModel(["emphasis"])
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(sector, focus, blurScope, isDisabled)
            states.setStatesStylesFromModel(sector, itemModel)

            // Sweep the collapsed sector open to its final angle (shared basicTransition helper).
            //   Shape props MUST be a dict of animatable fields (a full SectorShape struct is opaque
            //   to the animator — the struct->dict rule). Instant (final angle, no animator) when the
            //   series' animation is disabled.
            initProps(sector, ["shape": ["endAngle": finalEndAngle] as [String: Any]], seriesModel, idx)

            data.setItemGraphicEl(idx, sector)
            _ = group.add(sector)

            // Label (upstream PiePiece._updateLabel): retrofit onto the shared label core —
            //   `labelStyle.setLabelStyle` attaches the label as the sector's textContent and the
            //   painter renders it. The leader-line (labelLine) + labelLayout collision-avoidance are
            //   DEFERRED (L1c) — text only for now.
            _updateLabel(seriesModel, data, idx)
        }

        // labelLayout(seriesModel);
        //   L1c: chart/pie/labelLayout.swift places outer labels + leader lines and resolves
        //   vertical overlap (avoidOverlap → shiftLayoutOnXY). Runs AFTER every sector (and its
        //   label + labelLine) is built, matching upstream (labelLayout reads the finished shapes).
        pieLabelLayout(seriesModel)

        // Always use initial animation.
        // upstream: if (seriesModel.get('animationTypeUpdate') !== 'expansion') { this._data = data; }
        if (seriesModel.get("animationTypeUpdate") as? String) != "expansion" {
            self._data = data
        }
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
    private func _updateLabel(_ seriesModel: PieSeriesModel, _ data: SeriesData, _ idx: Int) {
        let itemModel = data.getItemModel(idx)

        // const style = data.getItemVisual(idx, 'style');
        // const visualColor = style && style.fill; const visualOpacity = style && style.opacity;
        let visualStyle = data.getItemVisual(idx, "style") as? [String: Any]
        let visualColor: ColorString? = pieFillToString(visualStyle?["fill"])
        let visualOpacity = visualStyle?["opacity"] as? Double

        // setLabelStyle(sector, getLabelStatesModels(itemModel), { labelFetcher, labelDataIndex,
        //   inheritColor, defaultOpacity, defaultText: getFormattedLabel(idx,'normal') || getName(idx) })
        let sector = data.getItemGraphicEl(idx)!
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
        let labelLineModel = itemModel.getModel("labelLine")
        if (labelLineModel.get("show") as? Bool) != false {
            let line = Polyline()
            var lstyle = barStyleFromDict(labelLineModel.getLineStyle())
            if lstyle.stroke == nil, let vc = visualColor { lstyle.stroke = .string(vc) }
            line.useStyle(lstyle)
            // A stroke-only leader line must not keep the black default fill.
            line.pathStyle.fill = nil
            line.z2 = 10
            sector.setTextGuideLine(line)
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
