// Ported from echarts/src/chart/funnel/FunnelView.ts — keep in sync with upstream
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
//   import * as graphic from '../../util/graphic';
//       -> `Polygon` / `Polyline` / `Text` (== ZRText) are the ZRenderKit shapes. PORT-TODO: `util/graphic`
//          (initProps/updateProps/removeElementWithFadeOut/Point) is NOT ported; the animation calls are
//          deferred (see the FunnelPiece PORT-TODO block).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> PORT-TODO: util/states NOT ported (states/emphasis deferred).
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import FunnelSeriesModel, {FunnelDataItemOption, SERIES_TYPE_FUNNEL} from './FunnelSeries';
//       -> sibling FunnelSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import { ColorString } from '../../util/types';                -> util/types.swift.
//   import { setLabelLineStyle, getLabelLineStatesModels } from '../../label/labelGuideHelper';
//       -> PORT-TODO: label/labelGuideHelper NOT ported (labelLine deferred).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> PORT-TODO: label/labelStyle NOT ported. A minimal plain-text reproduction is inlined in
//          `_updateLabel` below (same deviation as installTitle.swift's `createTextStyle`).
//   import { saveOldStyle } from '../../animation/basicTransition';  -> PORT-TODO: NOT ported (deferred).

// const opacityAccessPath = ['itemStyle', 'opacity'] as const;
private let opacityAccessPath = ["itemStyle", "opacity"]

// ================================================================================================
// upstream: class FunnelPiece extends graphic.Polygon { constructor(...); updateData(...); _updateLabel(...) }
//
// ZRenderKit's `Polygon` is `final` (it cannot be subclassed), so the upstream `FunnelPiece` (a Polygon
// carrying a Text child + a labelLine Polyline) is collapsed into a plain `Polygon` built directly in
// `FunnelView.render`, with `_updateLabel` reproduced as a free function below. This matches the
// PieView/BarView collapse.
//
// PORT-TODO (DEFERRED — separate upstream subsystems; a STATIC render faithfully omits them):
//   - labelLine: `setTextGuideLine`/`getTextGuideLine` (Polyline), `setLabelLineStyle`,
//     `getLabelLineStatesModels`, `textGuideLineConfig` are deferred with label/labelGuideHelper.
//   - Label EMPHASIS / states: `getLabelStatesModels`, `setStatesStylesFromModel`, `toggleHoverEmphasis`,
//     the `{ normal: {...} }` states arg to `setLabelStyle`, and the label formatter (`labelFetcher`)
//     are deferred; the PLAIN label text (`defaultText = data.getName(idx)`) IS drawn.
//   - Animation: `graphic.initProps`/`updateProps` (fade-in opacity 0 → opacity), `saveOldStyle` are
//     deferred with basicTransition.
// ================================================================================================

// upstream: class FunnelView extends ChartView
open class FunnelView: ChartView {

    // upstream: static readonly type = SERIES_TYPE_FUNNEL;  /  readonly type = SERIES_TYPE_FUNNEL;
    public static let funnelType = SERIES_TYPE_FUNNEL
    open override var type: String {
        get { SERIES_TYPE_FUNNEL }
        set { /* readonly upstream */ }
    }

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?

    public override init() {
        super.init()
        // upstream: ignoreLabelLineUpdate = true;  (class-field default; label line handled in-chart)
        self.ignoreLabelLineUpdate = true
    }

    // upstream: render(seriesModel: FunnelSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: FunnelSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! FunnelSeriesModel
        let data = seriesModel.getData()
        // let oldData = this._data;  — used only by the deferred diff/animation path.
        _ = self._data

        let group = self.group

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream diffs `oldData` → `FunnelPiece` add/update/remove. The
        //   SymbolDraw-style diff + FunnelPiece + emphasis/animation are deferred (see the FunnelPiece
        //   PORT-TODO block), so the group is rebuilt from scratch each render. Per-piece geometry,
        //   visual fill, and the PLAIN label text ARE drawn (mirroring `FunnelPiece.updateData` +
        //   `_updateLabel`).
        // ------------------------------------------------------------------------------------------
        _ = group.removeAll()

        for idx in 0..<data.count() {
            // upstream `FunnelPiece.updateData`:
            //   const layout = data.getItemLayout(idx);
            guard let layout = data.getItemLayout(idx) as? [String: Any],
                  let points = layout["points"] as? [[Double]] else {
                continue
            }

            let itemModel = data.getItemModel(idx)
            // let opacity = itemModel.get(opacityAccessPath); opacity = opacity == null ? 1 : opacity;
            let opacityOpt = itemModel.get(opacityAccessPath)
            let opacity: Double = (opacityOpt == nil || opacityOpt is NSNull)
                ? 1
                : ((opacityOpt as? Double) ?? ((opacityOpt as? Int).map { Double($0) } ?? 1))

            // polygon.setShape({ points: layout.points });
            var polygonShape = PolygonShape()
            polygonShape.points = points.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
            let polygon = Polygon(["shape": polygonShape as PathShape])

            // polygon.useStyle(data.getItemVisual(idx, 'style'));  +  polygon.style.lineJoin = 'round';
            //   The item visual 'style' bag is bridged to a typed `PathStyleProps` (palette fill etc.)
            //   via `barStyleFromDict` (BarView.swift) — the shared visual-style → PathStyleProps bridge.
            var style = barStyleFromDict(data.getItemVisual(idx, "style"))
            style.lineJoin = "round"
            // upstream animates opacity 0 → `opacity` via initProps; the static render sets the final
            //   opacity directly (animation deferred).
            style.opacity = opacity
            polygon.useStyle(style)

            // Name the piece 'item' (matches PieView/BarView per-datum element name; upstream leaves it
            //   unset — a harmless, non-load-bearing addition for hit-testing/debug parity).
            polygon.name = "item"

            // upstream (FunnelPiece.updateData):
            //   const emphasisModel = itemModel.getModel('emphasis');
            //   setStatesStylesFromModel(polygon, itemModel);
            //   toggleHoverEmphasis(polygon, emphasisModel.get('focus'), emphasisModel.get('blurScope'),
            //       emphasisModel.get('disabled'));
            //   Marks each piece a highDown dispatcher carrying its emphasis-state itemStyle so a hover
            //   (enterEmphasisWhenMouseOver) restyles it.
            let emphasisModel = itemModel.getModel(["emphasis"])
            states.setStatesStylesFromModel(polygon, itemModel)
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
            states.toggleHoverEmphasis(polygon, focus, blurScope, isDisabled)

            data.setItemGraphicEl(idx, polygon)
            _ = group.add(polygon)

            // this._updateLabel(data, idx);  — draws the plain label Text attached to the polygon.
            funnelUpdateLabel(polygon, data, idx, layout, group)
        }

        self._data = data
    }

    // upstream: remove() { this.group.removeAll(); this._data = null; }
    //   The base `ChartView.remove(ecModel, api)` carries the two args upstream's zero-arg override omits.
    open override func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        _ = self.group.removeAll()
        self._data = nil
    }

    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}
}

// upstream: FunnelPiece._updateLabel(data: SeriesData, idx: number)
//   PLAIN-TEXT subset (label EMPHASIS / states / formatter / labelLine are deferred — see the
//   FunnelPiece PORT-TODO block). Reproduces the geometry + color of the normal label:
//     - text        = data.getName(idx)                 (upstream's `defaultText`; formatter deferred)
//     - align/valign = labelLayout.textAlign / verticalAlign
//     - x/y          = labelLayout.x / y
//     - rotation/originX/originY/z2 = labelLayout.rotation / x / y / 10
//     - textConfig  = { local, inside, insideStroke, outsideFill } with overrideColor for 'inherit'
private func funnelUpdateLabel(
    _ polygon: Polygon, _ data: SeriesData, _ idx: Int, _ layout: [String: Any], _ group: Group
) {
    // const labelText = polygon.getTextContent();  — created here (upstream: in the FunnelPiece ctor).
    let itemModel = data.getItemModel(idx)
    // const labelLayout = layout.label;
    let labelLayout = (layout["label"] as? [String: Any]) ?? [:]
    // const style = data.getItemVisual(idx, 'style'); const visualColor = style.fill as ColorString;
    let visualColor = funnelVisualFill(data.getItemVisual(idx, "style"))

    let labelModel = itemModel.getModel("label")

    // setLabelStyle(labelText, ...): PLAIN reproduction — the normal-state label text/font/fill/align.
    // PORT-TODO: full setLabelStyle (formatter via labelFetcher, states models, defaultOpacity) deferred.
    var textStyle = TextStyleProps()
    // defaultText: data.getName(idx) — the plain label (formatter deferred).
    textStyle.text = data.getName(idx)
    // font from the label model's textStyle.
    textStyle.font = labelModel.getFont()

    // const labelColor = labelModel.get('color');
    // const overrideColor = labelColor === 'inherit' ? visualColor : null;
    let labelColor = labelModel.get("color")
    let overrideColor: String? = (labelColor as? String) == "inherit" ? visualColor : nil

    // Plain label fill: overrideColor (inherit → item color) else the label model's resolved text color.
    //   Left nil → Element.updateInnerText auto-resolves inside/outside from the host + textConfig.
    if let overrideColor = overrideColor {
        textStyle.fill = overrideColor
    }
    else if let c = labelModel.getTextColor() {
        textStyle.fill = c
    }

    // { normal: { align: labelLayout.textAlign, verticalAlign: labelLayout.verticalAlign } }
    textStyle.align = (labelLayout["textAlign"] as? String).flatMap { TextAlign(rawValue: $0) }
    textStyle.verticalAlign = (labelLayout["verticalAlign"] as? String).flatMap { TextVerticalAlign(rawValue: $0) }

    // graphic.updateProps(labelText, { style: { x: labelLayout.x, y: labelLayout.y } }, ...):
    //   animation deferred → set the final x/y directly.
    textStyle.x = labelLayout["x"] as? Double
    textStyle.y = labelLayout["y"] as? Double

    let labelText = ZRText()
    labelText.useStyle(textStyle)

    // labelText.attr({ rotation: labelLayout.rotation, originX: labelLayout.x, originY: labelLayout.y, z2: 10 });
    //   `labelLayout.rotation` is never set by funnelLayout (undefined) → left at the default 0.
    if let rotation = labelLayout["rotation"] as? Double {
        labelText.rotation = rotation
    }
    if let ox = labelLayout["x"] as? Double { labelText.originX = ox }
    if let oy = labelLayout["y"] as? Double { labelText.originY = oy }
    labelText.z2 = 10

    // `label.show === false` hides the label (setLabelStyle sets the text to ignore).
    // PORT-TODO: upstream drives visibility through the label states model; here the normal `show` flag
    //   is honored directly.
    if let show = labelModel.get("show") as? Bool, !show {
        labelText.ignore = true
    }

    // polygon.setTextContent(text) (upstream: in the ctor) + setTextConfig({...}).
    polygon.setTextContent(labelText)

    // polygon.setTextConfig({ local: true, inside: !!labelLayout.inside, insideStroke: overrideColor,
    //   outsideFill: overrideColor });
    var textConfig = ElementTextConfig()
    textConfig.local = true
    textConfig.inside = (labelLayout["inside"] as? Bool) ?? false
    textConfig.insideStroke = overrideColor
    textConfig.outsideFill = overrideColor
    polygon.setTextConfig(textConfig)

    // labelLine (leader) — funnelLayout already computed `linePoints`; draw them as a Polyline stroked
    //   in the item color (the label-guide states/anchor machinery is deferred). Only for outside labels.
    let labelLineModel = itemModel.getModel("labelLine")
    let isInside = (labelLayout["inside"] as? Bool) ?? false
    if !isInside,
       (labelLineModel.get("show") as? Bool) != false,
       let linePoints = labelLayout["linePoints"] as? [[Double]], linePoints.count >= 2 {
        var lineShape = PolylineShape()
        lineShape.points = linePoints.map { VectorArray($0[0], $0[1]) }
        let line = Polyline()
        line.setShape(lineShape)
        var lstyle = barStyleFromDict(labelLineModel.getLineStyle())
        if lstyle.stroke == nil, let vc = visualColor { lstyle.stroke = .string(vc) }
        line.useStyle(lstyle)
        line.pathStyle.fill = nil   // class-1 guard: a stroke-only polyline must not keep the black default
        line.z2 = 10
        _ = group.add(line)
    }
}

// upstream `const visualColor = style.fill as ColorString`. Extracts the solid-color fill string from
//   the item visual 'style' bag (stored as an EChartsKit `ZRColor.color` or a raw String).
private func funnelVisualFill(_ style: Any?) -> String? {
    guard let d = style as? [String: Any] else { return nil }
    if let str = d["fill"] as? String { return str }
    if let zr = d["fill"] as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// export default FunnelView;  -> `open class FunnelView` above.
