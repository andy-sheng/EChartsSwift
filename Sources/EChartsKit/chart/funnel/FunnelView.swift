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
//       -> `Polygon` / `Polyline` / `Text` (== ZRText) are the ZRenderKit shapes. initProps/updateProps/
//          removeElementWithFadeOut ARE ported (animation/basicTransition.swift); initProps is wired below.
//          Funnel's STATIC render still defers the updateProps-driven diff-update transitions (see the
//          FunnelPiece deferral block).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//       -> util/states IS ported (util/states.swift); both are wired per-piece in render() below.
//   import ChartView from '../../view/Chart';                      -> ChartView (view/Chart.swift).
//   import FunnelSeriesModel, {FunnelDataItemOption, SERIES_TYPE_FUNNEL} from './FunnelSeries';
//       -> sibling FunnelSeries.swift.
//   import GlobalModel from '../../model/Global';                  -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';            -> ExtensionAPI.
//   import SeriesData from '../../data/SeriesData';                -> SeriesData.
//   import { ColorString } from '../../util/types';                -> util/types.swift.
//   import { setLabelLineStyle, getLabelLineStatesModels } from '../../label/labelGuideHelper';
//       -> PORT-NOTE: BOTH helpers now EXIST in label/labelGuideHelper.swift
//          (`labelGuideHelper.getLabelLineStatesModels` and `labelGuideHelper.setLabelLineStyle`).
//          Only the CALL SITE is pending here — the leader polyline is still drawn inline (single
//          stroke) in funnelUpdateLabel below. See the `// PORT-TODO: wire setLabelLineStyle` marker
//          there. Do NOT re-derive a second copy of the helper.
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//       -> label/labelStyle IS ported (label/labelStyle.swift); both are wired in funnelUpdateLabel
//          below, replacing the former inline plain-text reproduction.
//   import { saveOldStyle } from '../../animation/basicTransition';  -> saveOldStyle IS ported
//       (animation/basicTransition.swift) and IS wired: the diff-update path calls it before restyling a
//       reused piece (so a merge-mode color change can tween through the style transition).

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
// PORT provenance (deferred subsystems below; a STATIC render faithfully omits them):
//   - labelLine: `setTextGuideLine`/`getTextGuideLine` (Polyline) + `textGuideLineConfig` (the anchor
//     turn-point) ARE wired. `setLabelLineStyle` / `getLabelLineStatesModels` (the per-state label-line
//     styling) are now PORTED in labelGuideHelper.swift; only the call site here is pending, so the
//     leader polyline is still drawn inline (single stroke) in funnelUpdateLabel for the moment.
//   - Label EMPHASIS / states: `getLabelStatesModels`, `setStatesStylesFromModel`, `toggleHoverEmphasis`,
//     the `{ normal: {...} }` states arg to `setLabelStyle`, and the label formatter (`labelFetcher`)
//     ARE now wired (see render() + funnelUpdateLabel below); the plain `defaultText = data.getName(idx)`
//     remains the fallback label text.
//   - Animation: piece fade-in (opacity 0 → opacity) via `initProps` IS wired (see the firstCreate
//     branch of `funnelPieceUpdateData`); the `updateProps`-driven diff-UPDATE transitions (shape.points
//     + opacity tween) and `saveOldStyle` ARE now wired too — `render` diffs `_data` and reuses the
//     retained Polygon on update (the reset-on-update fix), rather than rebuilding the group each render.
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
        // const oldData = this._data;
        let oldData = self._data

        let group = self.group

        // ------------------------------------------------------------------------------------------
        // upstream: data.diff(oldData).add(...).update(...).remove(...).execute();
        //   The FunnelPiece lifecycle is diffed against the previous render so a merge-mode setOption
        //   (upstream's refresh idiom) TWEENS each piece — `updateProps({shape:{points}, style:{opacity}})`
        //   slides the polygon and the label to their new positions — instead of rebuilding the group and
        //   replaying the enter (opacity 0 → opacity) animation. Retaining `_data` + reusing the retained
        //   Polygon element (via `oldData.getItemGraphicEl`) is what fixes the reset-on-update bug (cf. the
        //   GaugeView reset fix). `FunnelPiece` (a Polygon carrying a text child + a labelLine guide line)
        //   is collapsed into a plain Polygon built by `funnelPieceUpdateData` below.
        // ------------------------------------------------------------------------------------------
        data.diff(oldData)
            // .add(idx => { const funnelPiece = new FunnelPiece(data, idx); ... group.add(funnelPiece); })
            .add { newIdx in
                if let piece = self.funnelPieceUpdateData(nil, data, seriesModel, newIdx, firstCreate: true) {
                    data.setItemGraphicEl(newIdx, piece)
                    _ = group.add(piece)
                }
            }
            // .update((newIdx, oldIdx) => { const piece = oldData.getItemGraphicEl(oldIdx);
            //     piece.updateData(data, newIdx); group.add(piece); data.setItemGraphicEl(newIdx, piece); })
            .update { newIdx, oldIdx in
                let existing = oldData?.getItemGraphicEl(oldIdx) as? Polygon
                if let piece = self.funnelPieceUpdateData(existing, data, seriesModel, newIdx, firstCreate: false) {
                    _ = group.add(piece)
                    data.setItemGraphicEl(newIdx, piece)
                }
            }
            // .remove(idx => { const piece = oldData.getItemGraphicEl(idx);
            //     graphic.removeElementWithFadeOut(piece, seriesModel, idx); })
            .remove { oldIdx in
                if let piece = oldData?.getItemGraphicEl(oldIdx) {
                    removeElementWithFadeOut(piece, seriesModel, oldIdx)
                }
            }
            .execute()

        self._data = data
    }

    // upstream: FunnelPiece.constructor(data, idx) + FunnelPiece.updateData(data, idx, firstCreate?)
    //   ZRenderKit's `Polygon` is `final`, so the upstream FunnelPiece (a Polygon carrying a Text child +
    //   a labelLine Polyline guide line) is reproduced here as a free function that BUILDS (firstCreate)
    //   or REUSES (`polygonIn`) a plain Polygon. Returns nil when the datum has no layout.
    @discardableResult
    private func funnelPieceUpdateData(
        _ polygonIn: Polygon?, _ data: SeriesData, _ seriesModel: FunnelSeriesModel, _ idx: Int,
        firstCreate: Bool
    ) -> Polygon? {
        // const layout = data.getItemLayout(idx);
        guard let layout = data.getItemLayout(idx) as? [String: Any],
              let points = layout["points"] as? [[Double]] else {
            return nil
        }

        let itemModel = data.getItemModel(idx)
        let emphasisModel = itemModel.getModel(["emphasis"])
        // let opacity = itemModel.get(opacityAccessPath); opacity = opacity == null ? 1 : opacity;
        let opacityOpt = itemModel.get(opacityAccessPath)
        let opacity: Double = (opacityOpt == nil || opacityOpt is NSNull)
            ? 1
            : ((opacityOpt as? Double) ?? ((opacityOpt as? Int).map { Double($0) } ?? 1))

        let ptsVec: [VectorArray] = points.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
        let finalPoints: [[Double]] = points.map { [$0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0] }

        let polygon: Polygon
        if firstCreate {
            // upstream FunnelPiece ctor: new Polygon; setTextContent(new Text); setTextGuideLine(new Polyline).
            var polygonShape = PolygonShape()
            polygonShape.points = ptsVec
            polygon = Polygon(["shape": polygonShape as PathShape])
            polygon.setTextContent(ZRText())
            polygon.setTextGuideLine(Polyline())
            // Name the piece 'item' (matches PieView/BarView per-datum element name; upstream leaves it
            //   unset — a harmless, non-load-bearing addition for hit-testing/debug parity).
            polygon.name = "item"
        }
        else {
            // upstream: `if (!firstCreate) { saveOldStyle(polygon); }` — snapshot the pre-update style so a
            //   merge-mode color change can tween through the style transition.
            polygon = polygonIn!
            saveOldStyle(polygon)
        }

        // polygon.useStyle(data.getItemVisual(idx, 'style'));  +  polygon.style.lineJoin = 'round';
        //   The item visual 'style' bag is bridged to a typed `PathStyleProps` (palette fill etc.)
        //   via `barStyleFromDict` (BarView.swift) — the shared visual-style → PathStyleProps bridge.
        var style = barStyleFromDict(data.getItemVisual(idx, "style"))
        style.lineJoin = "round"

        if firstCreate {
            // upstream: polygon.setShape({ points }); polygon.style.opacity = 0;
            //   initProps(polygon, { style: { opacity } }, seriesModel, idx);
            //   Pieces fade in from invisible to their final opacity. Set the CONSTRUCTION-time opacity to 0,
            //   then animate (or, with animation off, instantly `attr`) toward the final `opacity` via
            //   `initProps`. The animation-off path relies on `Path.attrKV`'s partial-"style"-dict merge to
            //   actually land the final opacity — without it the piece would stay invisible.
            style.opacity = 0
            polygon.useStyle(style)
            initProps(polygon, ["style": ["opacity": opacity] as [String: Any]], seriesModel, idx)
        }
        else {
            // upstream: polygon.useStyle(...); graphic.updateProps(polygon,
            //     { style: { opacity }, shape: { points } }, seriesModel, idx);
            //   REUSE the retained polygon and TWEEN its opacity + shape.points to the new value (the
            //   reset-on-update fix). Target points as `[[Double]]` — the shape the Animator's 2D-array
            //   interpolation consumes; a `[VectorArray]` target is not recognised and SNAPS instead.
            polygon.useStyle(style)
            updateProps(polygon, [
                "style": ["opacity": opacity] as [String: Any],
                "shape": ["points": finalPoints] as [String: Any]
            ], seriesModel, idx)
        }

        // upstream (FunnelPiece.updateData):
        //   setStatesStylesFromModel(polygon, itemModel);
        //   this._updateLabel(data, idx);
        //   toggleHoverEmphasis(this, emphasisModel.get('focus'), emphasisModel.get('blurScope'),
        //       emphasisModel.get('disabled'));
        //   Marks each piece a highDown dispatcher carrying its emphasis-state itemStyle so a hover
        //   (enterEmphasisWhenMouseOver) restyles it.
        states.setStatesStylesFromModel(polygon, itemModel)

        // this._updateLabel(data, idx);  — draws the label (via the shared label core) attached to the polygon.
        funnelUpdateLabel(polygon, seriesModel, data, idx, layout, firstCreate)

        let focus: InnerFocus? = emphasisModel.get("focus")
        let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
        let isDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
        states.toggleHoverEmphasis(polygon, focus, blurScope, isDisabled)

        return polygon
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
//   Now routed through the SHARED LABEL CORE (`labelStyle.setLabelStyle` / `getLabelStatesModels`),
//   replacing the previous inline plain-text reproduction. Faithful to upstream's `_updateLabel`:
//     - setLabelStyle(labelText, getLabelStatesModels(itemModel),
//         { labelFetcher: seriesModel, labelDataIndex: idx, defaultOpacity: style.opacity,
//           defaultText: data.getName(idx) },
//         { normal: { align: labelLayout.textAlign, verticalAlign: labelLayout.verticalAlign } })
//       — upstream calls it on the ATTACHED `labelText` (a ZRText), i.e. the `isSetOnText` overload:
//       "position will not be used in setLabelStyle" (funnel places the label by absolute x/y from the
//       layout, below). This sets the normal text/font/fill AND the emphasis/blur/select per-state
//       label styles on the ZRText (the previous inline code set only the normal text).
//     - x/y          = labelLayout.x / y     (set AFTER setLabelStyle, which replaces the style)
//     - rotation/originX/originY/z2 = labelLayout.rotation / x / y / 10
//     - textConfig  = { local, inside, insideStroke, outsideFill } with overrideColor for 'inherit'
//     - textGuideLineConfig = { anchor: linePoints ? new Point(linePoints[0][0], linePoints[0][1]) : null }
//       IS wired (below) — the guide-line turn/anchor point.
// PORT-TODO: wire setLabelLineStyle. `labelGuideHelper.setLabelLineStyle` and
//   `labelGuideHelper.getLabelLineStatesModels` are BOTH ported and available — only this call site is
//   still pending, so the leader polyline is drawn inline (single stroke) at the end. Upstream is:
//     labelGuideHelper.setLabelLineStyle(
//         polygon, labelGuideHelper.getLabelLineStatesModels(itemModel), <stroke/opacity defaultStyle>)
//   which should REPLACE the inline single-stroke drawing below (not sit alongside it).
private func funnelUpdateLabel(
    _ polygon: Polygon, _ seriesModel: FunnelSeriesModel, _ data: SeriesData, _ idx: Int,
    _ layout: [String: Any], _ firstCreate: Bool
) {
    let itemModel = data.getItemModel(idx)
    // const labelLine = this.getTextGuideLine();  const labelText = polygon.getTextContent();
    //   (both were created + attached in funnelPieceUpdateData's firstCreate branch.)
    let labelLine = polygon.getTextGuideLine()
    let labelText = polygon.getTextContent() ?? ZRText()
    if polygon.getTextContent() == nil { polygon.setTextContent(labelText) }

    // const labelLayout = layout.label;
    let labelLayout = (layout["label"] as? [String: Any]) ?? [:]
    // const style = data.getItemVisual(idx, 'style'); const visualColor = style.fill as ColorString;
    let visualStyle = data.getItemVisual(idx, "style")
    let visualColor = funnelVisualFill(visualStyle)
    // `style.opacity` (upstream `defaultOpacity`) read off the item visual 'style' bag.
    let styleOpacity: Double? = {
        guard let d = visualStyle as? [String: Any] else { return nil }
        if let o = d["opacity"] as? Double { return o }
        if let o = d["opacity"] as? Int { return Double(o) }
        return nil
    }()

    // setLabelStyle(labelText, getLabelStatesModels(itemModel), { ... }, { normal: { align, verticalAlign } }).
    var opt = SetLabelStyleOpt()
    opt.labelFetcher = seriesModel
    opt.labelDataIndex = Double(idx)
    opt.defaultOpacity = styleOpacity
    // defaultText: data.getName(idx) — upstream uses the datum NAME (not getDefaultLabel).
    opt.defaultText = data.getName(idx)

    var normalSpecified = TextStyleProps()
    normalSpecified.align = (labelLayout["textAlign"] as? String).flatMap { TextAlign(rawValue: $0) }
    normalSpecified.verticalAlign = (labelLayout["verticalAlign"] as? String).flatMap { TextVerticalAlign(rawValue: $0) }

    labelStyle.setLabelStyle(
        labelText,
        labelStyle.getLabelStatesModels(itemModel),
        opt,
        [.normal: normalSpecified]
    )

    let labelModel = itemModel.getModel("label")
    // const labelColor = labelModel.get('color');
    // const overrideColor = labelColor === 'inherit' ? visualColor : null;
    let labelColor = labelModel.get("color")
    let overrideColor: String? = (labelColor as? String) == "inherit" ? visualColor : nil

    // polygon.setTextConfig({ local: true, inside: !!labelLayout.inside, insideStroke: overrideColor,
    //   outsideFill: overrideColor });
    var textConfig = ElementTextConfig()
    textConfig.local = true
    textConfig.inside = (labelLayout["inside"] as? Bool) ?? false
    textConfig.insideStroke = overrideColor
    textConfig.outsideFill = overrideColor
    polygon.setTextConfig(textConfig)

    // labelLine (leader) — funnelLayout already computed `linePoints`. Upstream attaches it as the
    //   polygon's textGuideLine (Storage renders it right after the polygon); the label-guide states/anchor
    //   machinery is deferred, so its shape + stroke are set directly here. The guide line is IGNORED for
    //   inside labels / labelLine.show === false / missing linePoints (so no stroke is painted).
    if let labelLine = labelLine {
        let labelLineModel = itemModel.getModel("labelLine")
        let isInside = (labelLayout["inside"] as? Bool) ?? false
        if !isInside,
           (labelLineModel.get("show") as? Bool) != false,
           let linePoints = labelLayout["linePoints"] as? [[Double]], linePoints.count >= 2 {
            labelLine.ignore = false
            var lineShape = PolylineShape()
            lineShape.points = linePoints.map { VectorArray($0[0], $0[1]) }
            _ = labelLine.setShape(lineShape)
            var lstyle = barStyleFromDict(labelLineModel.getLineStyle())
            if lstyle.stroke == nil, let vc = visualColor { lstyle.stroke = .string(vc) }
            labelLine.useStyle(lstyle)
            labelLine.pathStyle.fill = nil   // class-1 guard: a stroke-only polyline must not keep the black default
            labelLine.z2 = 10
        }
        else {
            labelLine.ignore = true
        }
    }

    // polygon.textGuideLineConfig = { anchor: linePoints ? new graphic.Point(linePoints[0][0],
    //   linePoints[0][1]) : null };
    //   Upstream sets the guide-line anchor UNCONDITIONALLY (regardless of inside / labelLine.show) — it is
    //   the label-guide machinery's turn point (the sector/pyramid midpoint the leader connects to). Matches
    //   pie's labelLayout.swift, which stamps the same anchor from linePoints[0].
    let anchorLinePoints = labelLayout["linePoints"] as? [[Double]]
    var guideConfig = ElementTextGuideLineConfig()
    if let lp = anchorLinePoints, let first = lp.first, first.count >= 2 {
        guideConfig.anchor = Point(first[0], first[1])
    }
    polygon.textGuideLineConfig = guideConfig

    // "Make sure update style on labelText after setLabelStyle. Because setLabelStyle will replace a
    //   new style on it." graphic.updateProps(labelText, { style: { x, y } }, seriesModel, idx) —
    //   on a REUSE (update) the label TWEENS to its new x/y; on firstCreate the position is set directly
    //   (the enter tween for the label position is deferred, matching the prior static render).
    if firstCreate {
        labelText.textStyle.x = labelLayout["x"] as? Double
        labelText.textStyle.y = labelLayout["y"] as? Double
    }
    else {
        var target: [String: Any] = [:]
        if let x = labelLayout["x"] as? Double { target["x"] = x }
        if let y = labelLayout["y"] as? Double { target["y"] = y }
        updateProps(labelText, ["style": target], seriesModel, idx)
    }

    // labelText.attr({ rotation: labelLayout.rotation, originX: labelLayout.x, originY: labelLayout.y, z2: 10 });
    //   `labelLayout.rotation` is never set by funnelLayout (undefined) → left at the default 0.
    if let rotation = labelLayout["rotation"] as? Double {
        labelText.rotation = rotation
    }
    if let ox = labelLayout["x"] as? Double { labelText.originX = ox }
    if let oy = labelLayout["y"] as? Double { labelText.originY = oy }
    labelText.z2 = 10
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
