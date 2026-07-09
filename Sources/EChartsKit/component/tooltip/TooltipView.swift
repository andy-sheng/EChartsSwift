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
// A SLIM `TooltipView` that makes the Phase-31 tooltip CONTENT actually APPEAR on hover: it hosts a
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
// DEFERRED (left as PORT-TODOs, exactly like the brief):
//   - `trigger:'axis'` (`_showAxisTooltip`, `_showComponentItemTooltip`, `dataByCoordSys`, axisPointer,
//     globalListener, `_updateContentNotChangedOnAxis`, `_keepShow`, `_manuallyAxisShowTip`)
//   - the HTML content host (`TooltipHTMLContent`) — this port is native, renderMode is FORCED 'richText'
//   - `transitionDuration` animation + throttled `_updatePosition` (`createOrUpdate`/`clear`)
//   - `confine` + the position CALLBACK / string / box-layout position exprs (only the default
//     below/right-of-pointer, clamped-to-rect position is ported)
//   - the `formatter` (string/function) override of the default markup
//   - `showDelay`/`hideDelay` timers (`_showOrMove` / `hideLater`) — shown synchronously here
//   - `findPointFromSeries` (the data-driven showTip position) — payload x/y is used instead
//
// ARCHITECTURE (see MEMORY / phase brief):
//   Upstream `TooltipView` is a `ComponentView` that reaches the live zrender via `api.getZr()`. In THIS
//   port `ECharts` is render-once with NO live zr; the live zr lives in `EChartsView`. So this view is
//   a PLAIN class OWNED by `EChartsView`, constructed over the live `zr` passed in. Its `TooltipRichContent`
//   adds its `ZRText` to THAT zr, so the tooltip floats above the chart and is not cleared on re-render.
//   PORT-TODO: re-unify with `ComponentView` (init/render(ecModel, api) + the `_componentViewFactories`
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
            // PORT-TODO (DEFERRED): trigger:'axis' → `_showAxisTooltip`. Not ported this phase.
            return
        }

        // --- build markup (upstream TooltipView.ts:695-717) -----------------------------------------
        let markupStyleCreator = TooltipMarkupStyleCreator()
        // PORT-TODO (DEFERRED): upstream pre-creates `params.marker` from `getDataParams().color` so a
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
            // PORT-TODO (DEFERRED): upstream wraps the frag with `{ valueFormatter }` from the model.
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

        _showTooltipContent(
            tooltipModel: tooltipModel,
            markupText: html,
            markupStyleCreator: markupStyleCreator,
            seriesModel: seriesModel,
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
    //   DEFERRED (faithful PORT-TODOs):
    //     - `axisPointerViewHelper.getValueLabel` full path (formatter callback + getAxisRawValue) — the
    //       label here is the slim `scale.parse + scale.getLabel` (viewHelper is Phase 36). The
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
                        // PORT-TODO (DEFERRED): upstream wraps the frag with `{ valueFormatter }` from
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

    // Slim `axisPointerViewHelper.getValueLabel` (viewHelper.ts:147 — the crosshair VIEW helper is Phase
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
        //   PORT-TODO (DEFERRED): `params.color`/`params.borderColor` (the series visual color) — needs
        //   `getDataParams`. Slim: border color from the model, else the default border color.
        let nearPointColor: String? = (tooltipModel.get("borderColor") as? String)
            ?? (tooltipModel.get("defaultBorderColor", true) as? String)
        _ = seriesModel

        content.setContent(markupText, markupStyleCreator, tooltipModel, nearPointColor, nil)
        content.show()   // rich content: no-arg (upstream html `show(model, color)` args are html-only)
        _updatePosition(tooltipModel: tooltipModel, x: x, y: y)
    }

    // ------------------------------------------------------------------------
    // _updatePosition — SLIM (upstream TooltipView.ts:905). Only the DEFAULT position is ported: place
    //   the box just below/right of the pointer (upstream `refixTooltipPosition` with gap 20), then clamp
    //   inside the chart rect (upstream `confineTooltipPosition`). The position callback / string / box-
    //   layout exprs, `align`/`verticalAlign`, and the `shouldTooltipConfine` gate are DEFERRED.
    // ------------------------------------------------------------------------
    private func _updatePosition(tooltipModel: Model, x: Double, y: Double) {
        _ = tooltipModel
        let viewWidth = _zr.getWidth() ?? 0
        let viewHeight = _zr.getHeight() ?? 0

        let size = _tooltipContent.getSize()
        let width = size.count > 0 ? size[0] : 0
        let height = size.count > 1 ? size[1] : 0

        // upstream `refixTooltipPosition` (gapH == gapV == 20): flip to the other side of the pointer
        //   when the box would overflow the right/bottom edge.
        let gap: Double = 20
        var px = x
        var py = y
        if px + width + gap + 2 > viewWidth {
            px -= width + gap
        }
        else {
            px += gap
        }
        if py + height + gap > viewHeight {
            py -= height + gap
        }
        else {
            py += gap
        }

        // upstream `confineTooltipPosition`: keep the box fully inside the view rect.
        px = min(px + width, viewWidth) - width
        py = min(py + height, viewHeight) - height
        px = max(px, 0)
        py = max(py, 0)

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
    // manuallyShowTip — SLIM of upstream `manuallyShowTip` (TooltipView.ts:292), seriesIndex branch only.
    //   This is the `update:'tooltip:manuallyShowTip'` target of the `showTip` action. `EChartsView`
    //   invokes it when a `showTip` payload is dispatched (the slim analogue of the upstream per-instance
    //   view routing). Reads `seriesIndex`/`dataIndex` (+ optional `x`/`y`) from the payload.
    // ------------------------------------------------------------------------
    public func manuallyShowTip(payload: Payload, ecModel: GlobalModel, api: ExtensionAPI?) {
        _ = api
        setModelIfNeeded(ecModel)

        guard let seriesIndex = asDouble(payload.other["seriesIndex"]),
              let dataIndex = asDouble(payload.other["dataIndex"]),
              let seriesModel = ecModel.getSeriesByIndex(seriesIndex) else {
            return
        }

        // PORT-TODO (DEFERRED): upstream `findPointFromSeries(payload, ecModel)` computes the on-chart
        //   point from the series layout when the payload has no x/y. Slim: use the payload's x/y, else
        //   fall back to the view centre (best-effort for a data-only showTip).
        let px = asDouble(payload.other["x"]) ?? ((_zr.getWidth() ?? 0) / 2)
        let py = asDouble(payload.other["y"]) ?? ((_zr.getHeight() ?? 0) / 2)

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

// ============================================================================
// Action registration — ported from install.ts (showTip / hideTip).
// ============================================================================
//
// upstream install.ts registers `showTip`/`hideTip` with a `noop` handler; the REAL work is the
//   `update:'tooltip:manuallyShowTip'` / `'tooltip:manuallyHideTip'` routing to the per-instance view.
//   In the slim port there is no view-update routing, so `EChartsView` (which owns the single
//   `TooltipView`) calls `manuallyShowTip`/`manuallyHideTip` directly when it dispatches/observes these
//   actions. The action DESCRIPTORS are still registered faithfully (type/event/update) so the payloads
//   flow through the ported dispatchAction pipeline.
//
// PORT-TODO (DEFERRED): per-instance `update`-field routing (`tooltip:manuallyShowTip`) — needs the
//   ComponentView update dispatch, which the slim path does not have. Multi-chart correctness (each
//   chart's own tooltip view) rides on that routing; the single-chart headless path is driven by
//   `EChartsView` invoking `manuallyShowTip`/`manuallyHideTip` on its owned view.
//
// noop handler (upstream `noop`).
private let tooltipNoopAction: ActionHandler = { _, _, _ in nil }

/// `tooltipInstall`-style registration the integrator invokes (from `ECharts.installOnce` /
///   `EChartsView`). Idempotent: `registerAction` early-returns on a duplicate type.
public func installTooltipActions(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers   // mirror upstream signature; the slim `registerAction` is module-level (see below).

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

    // PORT-TODO (DEFERRED): `use(installAxisPointer)` (install.ts:27) — the axisPointer install is part
    //   of the trigger:'axis' path, not ported this phase.
}
