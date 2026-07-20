// Ported (SLIM, trigger:"item" ONLY) from echarts/src/component/tooltip/TooltipView.ts
//   + the showTip/hideTip action registration from echarts/src/component/tooltip/install.ts.
//   Keep in sync with upstream.
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
//
// ============================================================================
// WHAT THIS FILE IS  (Phase 34, TASK 2)
// ============================================================================
// A `TooltipView` that makes the Phase-31 tooltip CONTENT actually APPEAR on hover: it hosts a
// `TooltipRichContent` (Phase-34 TASK 1) — a ZRText box — in the LIVE `EChartsView.zr`, and on hover of
// a series item resolves the tooltip model, builds the markup via `SeriesModel.formatTooltip` (Phase 31)
// and shows + positions the box near the pointer.
//
// SCOPE vs upstream `TooltipView.ts` (this phase ports ONLY the `trigger:'item'` path):
//   - `_tryShow` → `_showSeriesItemTooltip` → `_showTooltipContent` → `_updatePosition`  (item branch)
//   - `_hide`
//   - the `manuallyShowTip` (seriesIndex branch) / `manuallyHideTip` action entries
//   - the `showTip`/`hideTip` action REGISTRATION (install.ts)
//
// DEFERRED (left as PORT-NOTEs, exactly like the brief):
//   - `trigger:'axis'` — SINCE PORTED via `_showAxisTooltip` (invoked from EChartsView/axisTrigger, not this
//     item entry). Still deferred within the axis path: `_showComponentItemTooltip`, globalListener,
//     `_updateContentNotChangedOnAxis`, `_keepShow`, `_manuallyAxisShowTip`.
//   - the HTML content host (`TooltipHTMLContent`) — this port is native, renderMode is FORCED 'richText'
//   - `transitionDuration` animation + throttled `_updatePosition` (`createOrUpdate`/`clear`)
//   - the position CALLBACK (closure-in-option) + the STRING position around a graphic element
//     (needs an `el` bounding rect the slim entry does not thread). The `confine` gate, the array
//     `[x,y]` / box-layout object position exprs, and `align`/`verticalAlign` ARE ported.
//   - the FUNCTION `formatter` (closure + async ticket callback). The STRING `formatter` override
//     of the default markup IS ported (item path).
//   - `showDelay`/`hideDelay` timers (`_showOrMove` / `hideLater`) — shown synchronously here
//   - `findPointFromSeries` (the data-driven showTip position) — NO LONGER DEFERRED: it is wired in
//     `manuallyShowTip`, which `EChartsView` routes the item-path `showTip` action to. Still deferred
//     on that path: `target`/`position`/`positionDefault` (see the PORT-NOTE there).
//
// ARCHITECTURE (see MEMORY / phase brief):
//   Upstream `TooltipView` is a `ComponentView` that reaches the live zrender via `api.getZr()`. In THIS
//   port `ECharts` is render-once with NO live zr; the live zr lives in `EChartsView`. So this view is
//   a PLAIN class OWNED by `EChartsView`, constructed over the live `zr` passed in. Its `TooltipRichContent`
//   adds its `ZRText` to THAT zr, so the tooltip floats above the chart and is not cleared on re-render.
//   PORT-NOTE (deferred): re-unify with `ComponentView` (init/render(ecModel, api) + the `_componentViewFactories`
//   registry) once `ECharts` grows a live zr / `ExtensionAPI.getZr()`.
//
// ============================================================================
// INTEGRATION CONTRACT — TASK 1 `TooltipRichContent` (parallel task; reconcile at the single build)
// ============================================================================
// This view assumes TASK 1 produces `TooltipRichContent` with (faithful to TooltipRichContent.ts, but
// constructed over the live zr rather than `ExtensionAPI`):
//   init(zr: ZRender)
//   var el: ZRText?                         // set by setContent
//   func update(_ tooltipModel: Model)
//   func setContent(_ content: String, _ markupStyleCreator: TooltipMarkupStyleCreator,
//                   _ tooltipModel: Model, _ borderColor: String?, _ arrowPosition: Any?)
//       (upstream `borderColor: ZRColor` is cast `as string` into ZRText.style.borderColor; the port
//        models the color bag as a `String?` — this is the one place the borderColor type is asserted.)
//   func setEnterable(_ enterable: Bool?)
//   func show()                             // (rich content ignores the html-only show(model,color) args)
//   func getSize() -> [Double]              // [width, height]
//   func moveTo(_ x: Double, _ y: Double)
//   func hide()
//   func isShow() -> Bool
//   func dispose()
// If TASK 1's signatures differ, reconcile HERE (single call site each) — the coupling is intentionally
// small and localized.

import Foundation
import ZRenderKit

// ============================================================================
// TooltipView (slim)
// ============================================================================
public final class TooltipView {

    // upstream: `type = 'tooltip'`
    public static let type = "tooltip"

    // upstream: `private _renderMode: TooltipRenderMode;` — FORCED richText (native; no DOM host).
    private let _renderMode: TooltipRenderMode = .richText

    // The live zrender the content is hosted in (upstream `api.getZr()`).
    private let _zr: ZRender

    // upstream: `private _tooltipContent: TooltipHTMLContent | TooltipRichContent;`
    //   Native port → always `TooltipRichContent`.
    private let _tooltipContent: TooltipRichContent

    // upstream: `private _tooltipModel: TooltipModel;` — the GLOBAL tooltip model (the merge base).
    private var _globalTooltipModel: TooltipModel?

    // upstream: `private _ecModel: GlobalModel;`
    private weak var _ecModel: GlobalModel?

    // ------------------------------------------------------------------------
    // init — upstream `TooltipView.init(ecModel, api)` (TooltipView.ts:164): reads the global tooltip
    //   model, resolves renderMode, and builds `new TooltipRichContent(api)`. Here the live `zr` is passed
    //   in (see ARCHITECTURE) and renderMode is forced 'richText'.
    // ------------------------------------------------------------------------
    public init(zr: ZRender, ecModel: GlobalModel? = nil) {
        self._zr = zr
        self._tooltipContent = TooltipRichContent(zr)
        self._ecModel = ecModel
        // upstream reads `ecModel.getComponent('tooltip')` in init; do the same when ecModel is known.
        if let ecModel = ecModel {
            self._globalTooltipModel = ecModel.getComponent("tooltip") as? TooltipModel
        }
    }

    /// Late binding of the model (when the view is constructed before `setOption` has produced a model,
    /// or the model was rebuilt). Mirrors the (ecModel, tooltipModel) refresh done by upstream `render`.
    public func setModel(_ ecModel: GlobalModel) {
        self._ecModel = ecModel
        self._globalTooltipModel = ecModel.getComponent("tooltip") as? TooltipModel
        if let gm = self._globalTooltipModel {
            self._tooltipContent.update(gm)   // upstream render(): `tooltipContent.update(tooltipModel)`
        }
    }

    // ------------------------------------------------------------------------
    // tryShow — a SLIMMED `_tryShow` (TooltipView.ts:453) collapsed straight into the
    //   `_showSeriesItemTooltip` (TooltipView.ts:659) item path. The dispatcher-walk / `dataByCoordSys` /
    //   component-tooltip / legend branches of `_tryShow` are DEFERRED (the caller — EChartsView — has
    //   already resolved the hovered `seriesModel` + `dataIndex` from the element's ECData).
    //
    //   - `event`     : the hover ElementEvent (kept for faithful `e.target`/offset access; positioning
    //                   uses `point`). Optional (nil for action-driven shows).
    //   - `seriesModel`: the resolved series (upstream `ecModel.getSeriesByIndex(ecData.seriesIndex)`).
    //   - `dataIndex` / `dataType`: upstream `ecData.dataIndex` / `ecData.dataType`.
    //   - `point`     : `[x, y]` in zr coords — upstream `[e.offsetX, e.offsetY]`.
    // ------------------------------------------------------------------------
    public func tryShow(
        event: ElementEvent?,
        seriesModel: SeriesModel,
        dataIndex: Double,
        dataType: SeriesDataType? = nil,
        point: [Double]
    ) {
        _ = event
        guard let ecModel = self._ecModel, let globalTooltipModel = self._globalTooltipModel else {
            return
        }

        // --- buildTooltipModel (SLIM): series `tooltip` merged OVER the global tooltip model. --------
        // upstream cascades [data.getItemModel(dataIndex), seriesModel, coordSys.model] over the global
        //   model (TooltipView.ts:680). The per-data-item + coord-system layers are DEFERRED; the series
        //   `tooltip` option (ignoreParent) is layered over the global model so `.get(...)` falls through
        //   to the registered global defaults (show / trigger / textStyle / order / …).
        let tooltipModel: Model
        if let seriesTooltipOpt = seriesModel.get("tooltip", true) as? [String: Any] {
            tooltipModel = Model(seriesTooltipOpt, globalTooltipModel, ecModel)
        }
        else {
            tooltipModel = globalTooltipModel
        }

        // upstream `_showSeriesItemTooltip` guard (TooltipView.ts:690): trigger must be nil or 'item'.
        let tooltipTrigger = tooltipModel.get("trigger") as? String
        if let t = tooltipTrigger, t != "item" {
            // PORT-NOTE: this item-only entry bails on trigger:'axis'; the axis tooltip IS ported
            //   (`_showAxisTooltip`) and reached via the axisTrigger path (EChartsView), not from here.
            return
        }

        // --- build markup (upstream TooltipView.ts:695-717) -----------------------------------------
        let markupStyleCreator = TooltipMarkupStyleCreator()
        // PORT-NOTE (deferred): upstream pre-creates `params.marker` from `getDataParams().color` so a
        //   user `formatter` can reference it. The default markup path builds its own markers, so the
        //   pre-created marker is only needed once the `formatter` override lands (also deferred).

        let seriesTooltipResult = normalizeTooltipFormatResult(
            seriesModel.formatTooltip(dataIndex, false, dataType)   // Phase 31 — the item content source
        )
        let orderMode = (tooltipModel.get("order") as? String).flatMap(TooltipOrderMode.init(rawValue:))
        let useUTC = (ecModel.get("useUTC") as? Bool) ?? false
        let textStyle = (tooltipModel.get("textStyle") as? TooltipTextStyleOption) ?? [:]

        let markupText: String?
        if let frag = seriesTooltipResult.frag {
            // PORT-NOTE (deferred): upstream wraps the frag with `{ valueFormatter }` from the model.
            markupText = buildTooltipMarkup(
                frag, markupStyleCreator, self._renderMode, orderMode, useUTC, textStyle
            )
        }
        else {
            markupText = seriesTooltipResult.text
        }

        guard let html = markupText else {
            // No content → nothing to show (upstream would still call show with an empty string; a nil
            //   markup here means `formatTooltip` produced no fragment/text, so we bail).
            return
        }

        // upstream: `const params = dataModel.getDataParams(dataIndex, dataType)` (TooltipView.ts:695).
        //   Threaded into `_showTooltipContent` so a string `formatter` can reference the datum's vars.
        //   PORT-NOTE (deferred): `params.marker` pre-creation is only used by the (deferred) function
        //   formatter; the string formatter substitutes `$vars` only.
        let params = seriesModel.getDataParams(dataIndex, dataType)

        _showTooltipContent(
            tooltipModel: tooltipModel,
            markupText: html,
            markupStyleCreator: markupStyleCreator,
            seriesModel: seriesModel,
            params: params,
            x: point.count > 0 ? point[0] : 0,
            y: point.count > 1 ? point[1] : 0
        )
    }

    // ------------------------------------------------------------------------
    // _showAxisTooltip — ported from upstream `_showAxisTooltip` (TooltipView.ts:532). The trigger:"axis"
    //   path: given the `dataByCoordSys` tree built by `axisTrigger` (component/axisPointer/axisTrigger.swift),
    //   assemble ONE combined tooltip listing every series' value at the hovered axis value. Iterate
    //   `dataByCoordSys -> dataByAxis`; each axis becomes a `section` whose HEADER is the axis value label
    //   (e.g. the hovered category "B") and whose blocks are each series' `formatTooltip(dataIndex,
    //   /*multipleSeries*/ true)` fragment (e.g. "seriesName 20"). The sections are collected into one
    //   article section, built to a markup string, and shown in the SAME box on the live zr near the pointer.
    //
    //   DEFERRED (faithful PORT-NOTEs):
    //     - `axisPointerViewHelper.getValueLabel` full path (formatter callback + getAxisRawValue) — the
    //       label here is the `scale.parse + scale.getLabel` (viewHelper is Phase 36). The
    //       `label.formatter` override is not applied.
    //     - `cbParams`/`getDataParams` marker pre-creation (only needed once a `formatter` override lands).
    //     - `_showOrMove` (showDelay) + `_updateContentNotChangedOnAxis` (no-change position-only update) —
    //       shown synchronously here.
    //     - `e.tooltipOption`/`buildTooltipModel([e.tooltipOption], ...)` — the per-dispatch tooltip option
    //       override; the global tooltip model is used directly.
    // ------------------------------------------------------------------------
    public func _showAxisTooltip(_ dataByCoordSys: [DataByCoordSys], x: Double, y: Double) {
        guard let ecModel = self._ecModel, let globalTooltipModel = self._globalTooltipModel else {
            return
        }
        let renderMode = self._renderMode
        let markupStyleCreator = TooltipMarkupStyleCreator()
        // upstream: buildTooltipModel([e.tooltipOption], globalTooltipModel). Slim: the global model.
        let singleTooltipModel: Model = globalTooltipModel

        // upstream: const articleMarkup = createTooltipMarkup('section', { blocks: [], noHeader: true });
        let articleMarkup = createTooltipMarkup("section", TooltipMarkupSection(noHeader: true, blocks: []))
        // Only for legacy: `Series['formatTooltip']` returns a string.
        var markupTextArrLegacy: [String] = []

        for itemCoordSys in dataByCoordSys {
            for axisItem in itemCoordSys.dataByAxis {
                // upstream: ecModel.getComponent(axisItem.axisDim + 'Axis', axisItem.axisIndex) as AxisBaseModel
                let axisModel = ecModel.getComponent(axisItem.axisDim + "Axis", axisItem.axisIndex) as? AxisBaseModel
                let axisValue = axisItem.value
                // upstream: if (!axisModel || axisValue == null) return;
                guard let axisModel = axisModel, axisValue != nil, !(axisValue is NSNull) else {
                    continue
                }
                let axis = axisModel.axis as? Axis2D

                // upstream: axisValueLabel = axisPointerViewHelper.getValueLabel(...). Slim: scale label.
                let axisValueLabel = _axisValueLabel(axisValue, axis, axisItem.valueLabelPrecision)
                let axisSectionMarkup = createTooltipMarkup("section", TooltipMarkupSection(
                    header: axisValueLabel,
                    noHeader: axisValueLabel.trimmingCharacters(in: .whitespaces).isEmpty,
                    blocks: [],
                    sortBlocks: true
                ))
                articleMarkup.blocks?.append(axisSectionMarkup)

                for idxItem in axisItem.seriesDataIndices {
                    guard let series = ecModel.getSeriesByIndex(idxItem.seriesIndex) else { continue }
                    let dataIndex = idxItem.dataIndexInside
                    // upstream: series.formatTooltip(dataIndex, /*multipleSeries*/ true, null)
                    let seriesTooltipResult = normalizeTooltipFormatResult(
                        series.formatTooltip(dataIndex, true, nil)
                    )
                    if let frag = seriesTooltipResult.frag {
                        // PORT-NOTE (deferred): upstream wraps the frag with `{ valueFormatter }` from
                        //   buildTooltipModel([series], globalTooltipModel).get('valueFormatter').
                        axisSectionMarkup.blocks?.append(frag)
                    }
                    if let text = seriesTooltipResult.text {
                        markupTextArrLegacy.append(text)
                    }
                }
            }
        }

        // In most cases, the second axis is displayed upper on the first one. So we reverse it to look better.
        articleMarkup.blocks?.reverse()
        markupTextArrLegacy.reverse()

        let orderMode = (singleTooltipModel.get("order") as? String).flatMap(TooltipOrderMode.init(rawValue:))
        let useUTC = (ecModel.get("useUTC") as? Bool) ?? false
        let textStyle = (singleTooltipModel.get("textStyle") as? TooltipTextStyleOption) ?? [:]

        let builtMarkupText = buildTooltipMarkup(
            articleMarkup, markupStyleCreator, renderMode, orderMode, useUTC, textStyle
        )
        if let bmt = builtMarkupText, !bmt.isEmpty {
            markupTextArrLegacy.insert(bmt, at: 0)
        }
        let blockBreak = renderMode == .richText ? "\n\n" : "<br/>"
        let allMarkupText = markupTextArrLegacy.joined(separator: blockBreak)

        // upstream: this._showOrMove(...) → this._showTooltipContent(...). Slim: shown synchronously.
        _showTooltipContent(
            tooltipModel: singleTooltipModel,
            markupText: allMarkupText,
            markupStyleCreator: markupStyleCreator,
            seriesModel: nil,   // axis tooltip has no single series (multiple series listed)
            x: x,
            y: y
        )
    }

    // `axisPointerViewHelper.getValueLabel` (viewHelper.ts:147 — the crosshair VIEW helper is Phase
    //   36): parse the axis value and format it with the axis scale's label. For a category axis (Ordinal
    //   scale) this yields the category name (e.g. "B"); for a value axis (Interval scale) the numeric
    //   label (honouring the axisPointer `label.precision`). The `label.formatter` callback is DEFERRED.
    private func _axisValueLabel(_ value: Any?, _ axis: Axis2D?, _ precision: Any?) -> String {
        guard let axis = axis, let value = value, !(value is NSNull) else {
            return value.map { "\($0)" } ?? ""
        }
        let parsed = axis.scale.parse(value)
        let tick = ScaleTick(value: parsed)
        if let interval = axis.scale as? IntervalScale {
            var opt = IntervalScaleGetLabelOpt()
            if let p = precision, !(p is NSNull) { opt.precision = p }
            return interval.getLabel(tick, opt)
        }
        return axis.scale.getLabel(tick)
    }

    // ------------------------------------------------------------------------
    // _showTooltipContent — upstream (TooltipView.ts:812). The `formatter` (string/function) override,
    //   the async ticket, and `enterable` timers are DEFERRED; the default markup is shown synchronously.
    // ------------------------------------------------------------------------
    private func _showTooltipContent(
        tooltipModel: Model,
        markupText: String,
        markupStyleCreator: TooltipMarkupStyleCreator,
        seriesModel: SeriesModel?,
        params: CallbackDataParams? = nil,
        x: Double,
        y: Double
    ) {
        // upstream: `if (!tooltipModel.get('showContent') || !tooltipModel.get('show')) return;`
        let showContent = (tooltipModel.get("showContent") as? Bool) ?? true
        let show = (tooltipModel.get("show") as? Bool) ?? true
        if !showContent || !show {
            return
        }

        let content = self._tooltipContent
        content.setEnterable(tooltipModel.get("enterable") as? Bool)

        // upstream `_getNearestPoint` (item branch): `borderColor || params.color || params.borderColor`.
        //   PORT-NOTE (deferred): the `params.color`/`params.borderColor` fallback needs the hovered datum's
        //   getDataParams (now available), but `_showTooltipContent` is not passed the dataIndex — wiring
        //   it requires threading dataIndex from the caller. Until then: border color from the model,
        //   else the default border color.
        let nearPointColor: String? = (tooltipModel.get("borderColor") as? String)
            ?? (tooltipModel.get("defaultBorderColor", true) as? String)
        _ = seriesModel

        // upstream `formatter` override of the default markup (TooltipView.ts:835-873). The STRING
        //   formatter is ported: substitute the datum's `$vars` (a/b/c + named) into the template via
        //   `formatTpl`. The FUNCTION formatter (closure + async ticket callback) and the time-axis
        //   `timeFormat` pre-pass are DEFERRED (no closure-in-option plumbing / no `timeFormat` port).
        let formatter = tooltipModel.get("formatter")
        var html = markupText
        if let formatterStr = formatter as? String, let params = params {
            html = format.formatTpl(formatterStr, tplParamFromDataParams(params), true)
        }

        content.setContent(html, markupStyleCreator, tooltipModel, nearPointColor, nil)
        content.show()   // rich content: no-arg (upstream html `show(model, color)` args are html-only)
        _updatePosition(tooltipModel: tooltipModel, x: x, y: y)
    }

    // ------------------------------------------------------------------------
    // _updatePosition — (upstream TooltipView.ts:905). Ports the `position` option: an ARRAY `[x, y]`
    //   (percent-aware via `parsePercent`), an OBJECT box-layout (`getLayoutRect`), and `align`/
    //   `verticalAlign` offsets; falls back to the DEFAULT `refixTooltipPosition` (flip to the other
    //   side of the pointer, gap 20) when no positionExpr; then applies `confineTooltipPosition` gated
    //   by `shouldTooltipConfine` (true for richText unless `confine:false`).
    //   DEFERRED: the position CALLBACK (closure-in-option) and the STRING position around a graphic
    //   element (`calcTooltipPosition`) — the slim entry has no `el` bounding rect to anchor against,
    //   so a string positionExpr falls through to the default refix.
    // ------------------------------------------------------------------------
    private func _updatePosition(tooltipModel: Model, x: Double, y: Double) {
        let viewWidth = _zr.getWidth() ?? 0
        let viewHeight = _zr.getHeight() ?? 0

        // upstream: `positionExpr = positionExpr || tooltipModel.get('position')`. The payload `position`
        //   is not threaded in the slim entry, so this reduces to the model's `position`.
        let positionExpr = tooltipModel.get("position")

        let contentSize = _tooltipContent.getSize()
        let width = contentSize.count > 0 ? contentSize[0] : 0
        let height = contentSize.count > 1 ? contentSize[1] : 0
        var align = tooltipModel.get("align") as? String
        var vAlign = tooltipModel.get("verticalAlign") as? String

        var px = x
        var py = y

        // PORT-NOTE (deferred): `isFunction(positionExpr)` — the position callback (closure-in-option).

        if let arr = positionExpr as? [Any] {
            // upstream: x = parsePercent(positionExpr[0], viewWidth); y = parsePercent(positionExpr[1], viewHeight)
            px = number.parsePercent(arr.count > 0 ? arr[0] : nil, viewWidth)
            py = number.parsePercent(arr.count > 1 ? arr[1] : nil, viewHeight)
        }
        else if let obj = positionExpr as? [String: Any] {
            // upstream box-layout: seed width/height then `getLayoutRect`. align/vAlign are cleared.
            var boxLayoutPosition = obj
            boxLayoutPosition["width"] = width
            boxLayoutPosition["height"] = height
            let layoutRect = layout.getLayoutRect(
                boxLayoutPosition, LayoutRect(0, 0, viewWidth, viewHeight)
            )
            px = layoutRect.x
            py = layoutRect.y
            align = nil
            vAlign = nil
        }
        else {
            // upstream `refixTooltipPosition(x, y, content, viewW, viewH, align ? null : 20, vAlign ? null : 20)`:
            //   flip to the other side of the pointer when the box would overflow the right/bottom edge.
            //   The horizontal/vertical gap is suppressed when the corresponding align is set.
            if align == nil {
                let gapH: Double = 20
                // Add extra 2 pixels (float:right values wrap when the right edge hugs the viewport).
                if px + width + gapH + 2 > viewWidth {
                    px -= width + gapH
                }
                else {
                    px += gapH
                }
            }
            if vAlign == nil {
                let gapV: Double = 20
                if py + height + gapV > viewHeight {
                    py -= height + gapV
                }
                else {
                    py += gapV
                }
            }
        }

        // upstream: align && (x -= isCenterAlign ? w/2 : align==='right' ? w : 0)
        if let align = align {
            px -= isCenterAlign(align) ? width / 2 : (align == "right" ? width : 0)
        }
        if let vAlign = vAlign {
            py -= isCenterAlign(vAlign) ? height / 2 : (vAlign == "bottom" ? height : 0)
        }

        // upstream `confineTooltipPosition`, gated by `shouldTooltipConfine`: keep the box inside the view.
        if shouldTooltipConfine(tooltipModel) {
            px = min(px + width, viewWidth) - width
            py = min(py + height, viewHeight) - height
            px = max(px, 0)
            py = max(py, 0)
        }

        _tooltipContent.moveTo(px, py)
    }

    // ------------------------------------------------------------------------
    // hide / _hide — upstream `_hide` (TooltipView.ts:1034) dispatches `hideTip`; the actual DOM hide is
    //   `manuallyHideTip` → `tooltipContent.hideLater`. Slim: hide synchronously (no hideDelay timer).
    // ------------------------------------------------------------------------
    public func hide() {
        _tooltipContent.hide()
    }

    // ------------------------------------------------------------------------
    // manuallyShowTip — of upstream `manuallyShowTip` (TooltipView.ts:292), seriesIndex branch only.
    //   This is the `update:'tooltip:manuallyShowTip'` target of the `showTip` action. `EChartsView`
    //   invokes it when a `showTip` payload is dispatched (the analogue of the upstream per-instance
    //   view routing). Upstream's branch condition is `payload.seriesIndex != null` ONLY — the datum is
    //   then resolved by `findPointFromSeries` → `modelUtil.queryDataIndex`, which accepts any of
    //   `dataIndexInside` / `dataIndex` / `name` (TooltipView.ts:287 documents all three payload forms).
    // ------------------------------------------------------------------------
    public func manuallyShowTip(payload: Payload, ecModel: GlobalModel, api: ExtensionAPI?) {
        _ = api
        setModelIfNeeded(ecModel)

        // upstream: `if (payload.seriesIndex != null) { ... }` — no `dataIndex` requirement here.
        guard let seriesIndex = asDouble(payload.other["seriesIndex"]),
              let seriesModel = ecModel.getSeriesByIndex(seriesIndex) else {
            return
        }

        // Resolve the datum ONCE, exactly as `findPointFromSeries` does internally
        //   (`modelUtil.queryDataIndex(data, finder)`), and use that SAME index for the tooltip CONTENT.
        //   queryDataIndex maps a raw `dataIndex` through `data.indexOfRawIndex` → an INSIDE index, which
        //   is what `tryShow`/`formatTooltip`/`getDataParams` expect (upstream derives the content from
        //   `pointInfo.el`'s ecData, i.e. also the inside index). Passing the RAW payload `dataIndex` here
        //   would render datum A's markup at datum B's pixel whenever the data is filtered (dataZoom).
        let data = seriesModel.getData()
        let dataIndexAny = model.queryDataIndex(data, payload)
        // upstream (findPointFromSeries): `if (dataIndex == null || dataIndex < 0 || isArray(dataIndex)) return`
        if dataIndexAny is [Any] { return }
        guard let dataIndex = asDouble(dataIndexAny), dataIndex >= 0 else { return }

        // upstream (TooltipView.ts:356, the `payload.seriesIndex != null` branch):
        //   const pointInfo = findPointFromSeries(payload, ecModel);
        //   const cx = pointInfo.point[0]; const cy = pointInfo.point[1];
        //   if (cx != null && cy != null) { this._tryShow({offsetX: cx, offsetY: cy, target: pointInfo.el,
        //       position: payload.position, positionDefault: 'bottom'}, dispatchAction); }
        //   Note upstream reaches this branch BEFORE the `payload.x/y` branch, so the data-driven point
        //   wins over any x/y carried on the payload.
        //   Upstream passes the WHOLE payload as the finder, so mirror the full finder bag here
        //   (`isStacked` included — it selects the stackResultDimension branch).
        let pointInfo = findPointFromSeries(
            FindPointFinder(
                seriesIndex: seriesIndex,
                dataIndex: payload.other["dataIndex"],
                dataIndexInside: payload.other["dataIndexInside"],
                name: payload.other["name"],
                isStacked: payload.other["isStacked"] as? Bool
            ),
            ecModel
        )
        // PORT-NOTE (deferred): `pointInfo.el` (upstream's `target`), `position: payload.position` and
        //   `positionDefault: 'bottom'` are all dropped — `tryShow` has no target/position/positionDefault
        //   parameter here, so an action-driven tooltip is placed by the same hover-side offset logic in
        //   `_updatePosition` (upstream deliberately puts a MANUALLY triggered tooltip BELOW the point, and
        //   honours an explicit `payload.position`). The position-around-a-graphic-element expr is a
        //   documented deferral of this view — see the SCOPE note above.

        // upstream: `if (cx != null && cy != null)` — show NOTHING when the point could not be resolved.
        //   (No payload-x/y or view-centre fallback: upstream reaches the `payload.x/y` branch only when
        //   `payload.seriesIndex == null`.) The `.isFinite` test is the Swift analogue of the JS null
        //   check: `Cartesian2D.dataToPoint` returns `[NaN, NaN]` for an out-of-extent value, and the
        //   stacked branch seeds `[NaN, NaN]`, neither of which may be handed to `moveTo`.
        guard pointInfo.point.count >= 2,
              pointInfo.point[0].isFinite, pointInfo.point[1].isFinite else {
            return
        }
        let px: Double = pointInfo.point[0]
        let py: Double = pointInfo.point[1]

        tryShow(
            event: nil,
            seriesModel: seriesModel,
            dataIndex: dataIndex,
            dataType: nil,
            point: [px, py]
        )
    }

    // upstream `manuallyHideTip` (TooltipView.ts:389) — the `update:'tooltip:manuallyHideTip'` target.
    public func manuallyHideTip(payload: Payload, ecModel: GlobalModel, api: ExtensionAPI?) {
        _ = (payload, ecModel, api)
        hide()
    }

    private func setModelIfNeeded(_ ecModel: GlobalModel) {
        if self._globalTooltipModel == nil || self._ecModel !== ecModel {
            setModel(ecModel)
        }
    }

    /// Dispose the hosted content (removes the ZRText from the zr).
    public func dispose() {
        _tooltipContent.dispose()
    }

    // ------------------------------------------------------------------------
    // Test hooks — minimal accessors so a headless test can assert the tooltip appeared with the right
    //   content. Not part of upstream's surface.
    // ------------------------------------------------------------------------
    /// The hosted `ZRText` tooltip box element (nil until `setContent` has run at least once).
    public var contentEl: ZRText? { _tooltipContent.el }
    /// Whether the tooltip box is currently shown (upstream `_tooltipContent.isShow()`).
    public func isShown() -> Bool { _tooltipContent.isShow() }
}

// ----------------------------------------------------------------------------
// asDouble — coerce a JS-number-ish option/payload value (Int or Double) to Double. Mirrors the
//   Int-vs-Double option-read trap fix (payloads box small ints as `Int`).
// ----------------------------------------------------------------------------
private func asDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

// upstream `isCenterAlign` (TooltipView.ts:1205).
private func isCenterAlign(_ align: String) -> Bool {
    return align == "center" || align == "middle"
}

// upstream `shouldTooltipConfine` (component/tooltip/helper.ts:27): honour the explicit `confine`
//   option, else confine in richText mode (the outside part is not visible). This port forces
//   richText, so absent `confine` → confine.
private func shouldTooltipConfine(_ tooltipModel: Model) -> Bool {
    if let confine = tooltipModel.get("confine") as? Bool {
        return confine
    }
    // richText mode (forced in this native port).
    return true
}

// Bridge the typed `CallbackDataParams` to the dynamic `[String: Any]` bag `formatTpl` reads by
//   `$vars` (mirrors the private `callbackDataParamsToTplParam` in model/mixin/dataFormat.swift).
private func tplParamFromDataParams(_ params: CallbackDataParams) -> [String: Any] {
    var tplParam: [String: Any] = [:]
    tplParam["$vars"] = params.vars
    tplParam["seriesName"] = params.seriesName
    tplParam["name"] = params.name
    tplParam["value"] = params.value
    if let percent = params.percent {
        tplParam["percent"] = percent
    }
    return tplParam
}

// ============================================================================
// Action registration — ported from install.ts (showTip / hideTip).
// ============================================================================
//
// upstream install.ts registers `showTip`/`hideTip` with a `noop` handler; the REAL work is the
//   `update:'tooltip:manuallyShowTip'` / `'tooltip:manuallyHideTip'` routing to the per-instance view.
//   In the port there is no view-update routing, so `EChartsView` (which owns the single
//   `TooltipView`) calls `manuallyShowTip`/`manuallyHideTip` directly when it dispatches/observes these
//   actions. The action DESCRIPTORS are still registered faithfully (type/event/update) so the payloads
//   flow through the ported dispatchAction pipeline.
//
// PORT-NOTE (deferred): per-instance `update`-field routing (`tooltip:manuallyShowTip`) — needs the
//   ComponentView update dispatch, which the path does not have. Multi-chart correctness (each
//   chart's own tooltip view) rides on that routing; the single-chart headless path is driven by
//   `EChartsView` invoking `manuallyShowTip`/`manuallyHideTip` on its owned view.
//
// noop handler (upstream `noop`).
private let tooltipNoopAction: ActionHandler = { _, _, _ in nil }

/// `tooltipInstall`-style registration the integrator invokes (from `ECharts.installOnce` /
///   `EChartsView`). Idempotent: `registerAction` early-returns on a duplicate type.
public func installTooltipActions(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers   // mirror upstream signature; the `registerAction` is module-level (see below).

    // registers.registerAction({ type:'showTip', event:'showTip', update:'tooltip:manuallyShowTip' }, noop)
    var showTip = ActionInfo(type: "showTip")
    showTip.event = "showTip"
    showTip.update = "tooltip:manuallyShowTip"
    registerAction(showTip, tooltipNoopAction)

    // registers.registerAction({ type:'hideTip', event:'hideTip', update:'tooltip:manuallyHideTip' }, noop)
    var hideTip = ActionInfo(type: "hideTip")
    hideTip.event = "hideTip"
    hideTip.update = "tooltip:manuallyHideTip"
    registerAction(hideTip, tooltipNoopAction)

    // PORT-NOTE: `use(installAxisPointer)` (install.ts:27) — the trigger:'axis' path IS ported; axisPointer
    //   is installed via EChartsView's axisTrigger wiring (component/axisPointer), not a tooltip-side use().
}
