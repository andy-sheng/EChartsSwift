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

            let sector = Sector(["shape": sectorShape as PathShape])
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

            data.setItemGraphicEl(idx, sector)
            _ = group.add(sector)

            // MINIMAL pie label (name text + leader line). The full label subsystem (setLabelStyle /
            //   labelLayout collision avoidance / rich labelLine) is DEFERRED; this renders the datum name
            //   at the sector's mid-angle so pie demos match ECharts' default `label:{show:true}` output.
            renderPieLabel(seriesModel, data, idx, layout, group)
        }

        // labelLayout(seriesModel);
        // PORT-TODO: chart/pie/labelLayout.ts NOT ported (full label placement/collision deferred).

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

    // MINIMAL pie label: the datum name at the sector's mid-angle. `position:'inside'` centers it in the
    //   sector (white); the default `'outside'` places it beyond the rim with a straight leader line in the
    //   sector colour. Full labelLayout collision-avoidance + rich formatter are DEFERRED.
    private func renderPieLabel(
        _ seriesModel: PieSeriesModel, _ data: SeriesData, _ idx: Int, _ layout: [String: Any], _ group: Group
    ) {
        let labelModel = seriesModel.getModel("label")
        guard ((labelModel.get("show") as? Bool) ?? true) else { return }
        let cx = (layout["cx"] as? Double) ?? 0
        let cy = (layout["cy"] as? Double) ?? 0
        let r = (layout["r"] as? Double) ?? 0
        let startAngle = (layout["startAngle"] as? Double) ?? 0
        let endAngle = (layout["endAngle"] as? Double) ?? 0
        let midAngle = (startAngle + endAngle) / 2
        let name = data.getName(idx)
        if name.isEmpty { return }

        let position = (labelModel.get("position") as? String) ?? "outside"
        // The sector's own fill, as a colour STRING (outside label text + leader-line colour).
        let sectorFill: String? = (data.getItemVisual(idx, "style") as? [String: Any])
            .flatMap { pieFillToString($0["fill"]) }

        var style = TextStyleProps()
        style.text = name
        style.font = labelModel.getFont()
        style.verticalAlign = .middle

        if position == "inside" || position == "inner" || position == "center" {
            let lr = (r) * 0.6
            style.x = cx + lr * cos(midAngle)
            style.y = cy + lr * sin(midAngle)
            style.align = .center
            // Inside labels default to white (upstream `inheritColor` resolves to a contrasting light
            //   text over the sector fill). `getTextColor()` returns the generic dark default, so only
            //   honour a color the user set EXPLICITLY; otherwise use white.
            if let explicit = labelModel.get("color") as? String, explicit != "inherit", explicit != "auto" {
                style.fill = explicit
            } else {
                style.fill = "#ffffff"
            }
        }
        else {
            let dxu = cos(midAngle), dyu = sin(midAngle)
            let isRight = dxu >= 0
            let edgeX = cx + r * dxu, edgeY = cy + r * dyu
            let bendX = cx + (r + 15) * dxu, bendY = cy + (r + 15) * dyu
            let textX = bendX + (isRight ? 12 : -12)
            style.x = textX
            style.y = bendY
            style.align = isRight ? .left : .right
            // Outside label TEXT defaults to the neutral dark label color (echarts draws the text dark, not
            //   in the sector colour); only the leader LINE adopts the sector colour. Honour an explicit
            //   user color if set.
            let textFill: String = labelModel.getTextColor() ?? "#54555a"
            style.fill = textFill
            let lineColor: String = sectorFill ?? textFill
            // Leader line: sector edge → bend → short horizontal toward the text.
            var lineShape = PolylineShape()
            lineShape.points = [
                VectorArray(edgeX, edgeY),
                VectorArray(bendX, bendY),
                VectorArray(textX + (isRight ? -3 : 3), bendY)
            ]
            let line = Polyline(["shape": lineShape as PathShape, "silent": true, "z2": 9.0])
            var ls = PathStyleProps()
            ls.stroke = .string(lineColor)
            line.useStyle(ls)
            line.pathStyle.fill = nil   // stroke-only (see visual-parity: clear the black default)
            _ = group.add(line)
        }
        let textEl = ZRText(["z2": 10.0, "silent": true])
        textEl.useStyle(style)
        _ = group.add(textEl)
    }
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
