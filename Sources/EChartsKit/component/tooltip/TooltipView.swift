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
//     `_keepShow`, `_manuallyAxisShowTip`.
//     (`_updateContentNotChangedOnAxis` — the no-change, position-only update branch — is NO LONGER
//     DEFERRED: it is ported below with its `_lastDataByCoordSys`/`_cbParamsList` memo, at upstream's
//     exact call site inside `_showAxisTooltip`'s `_showOrMove` callback. NOTE this makes the branch MORE
//     live than upstream, where the per-mousemove `globalListener('itemTooltip')` leg clears the memo
//     first — a deliberate divergence, documented in full on `_updateContentNotChangedOnAxis`, with the
//     resulting staleness window closed by `clearAxisTooltipMemo()`.)
//   - the HTML content host (`TooltipHTMLContent`) — this port is native, renderMode is FORCED 'richText'
//   - `transitionDuration` animation + throttled `_updatePosition` (`createOrUpdate`/`clear`)
//   - the `position` option — NO LONGER DEFERRED. Every upstream form is ported in `_updatePosition`:
//     the CALLBACK (`TooltipPositionCallback`, util/types.swift — a closure IS storable in an option bag
//     in this port), the STRING keywords 'inside'/'top'/'bottom'/'left'/'right' around the hovered
//     element (`calcTooltipPosition`, anchored on the `el` now threaded from `e.target` /
//     `findPointFromSeries`'s `pointInfo.el`), the array `[x,y]`, the box-layout object, `align`/
//     `verticalAlign` and the `confine` gate. `TryShowParams.positionDefault` ('bottom' on the
//     action-driven path) is ported too, as upstream's BASE model under the global option
//     (`buildTooltipModel(..., positionDefault ? {position: positionDefault} : null)`) so an explicit
//     `position` still wins. Still deferred: the PAYLOAD `position` override
//     (`TryShowParams.position`) — see the PORT-TODO in `manuallyShowTip`.
//     CONSTRAINT (Swift, no upstream analogue): a `position` CALLBACK must be stored in the option bag
//     annotated as `TooltipPositionCallback` — `["position": (cb as TooltipPositionCallback)]`. Swift
//     cannot dynamically cast between structurally-similar function types, so a closure written with any
//     other spelling of the same signature fails the `as? TooltipPositionCallback` read in
//     `_updatePosition` and is silently ignored (see the PORT-NOTE there).
//   - the `formatter` override of the default markup — NO LONGER DEFERRED: both the STRING formatter
//     and the FUNCTION formatter (closure-in-option + `asyncTicket`/`_ticket` async callback) are
//     ported, on BOTH the item and the axis path. See `_showTooltipContent` for the exact closure
//     arities a Swift `formatter` may be spelled with.
//     CAVEAT — the STRING formatter's time-axis `timeFormat` PRE-PASS is ported but DORMANT: its
//     `params0.axisType.indexOf('time')` gate can never match, because the axis models this port
//     instantiates report the MAIN type only ("xAxis") where upstream reports "xAxis.time". The gap is
//     in `EChartsXAxisModel`/`EChartsYAxisModel` (core/ECharts.swift), NOT here — see the PORT-TODO on
//     `isTimeAxis` in `_showTooltipContent`, and the test that pins both halves
//     (`ZZTooltipFormatterTests.testStringFormatterTimeAxisPrePassIsDormantOnTheKnownAxisTypeGap`).
//   - `showDelay`/`hideDelay` timers (`_showOrMove` / `hideLater`) — NO LONGER DEFERRED: `_showOrMove`
//     is ported below and every show path (`tryShow`, `_showAxisTooltip`) routes through it, exactly
//     where upstream does; `hide()` routes through `TooltipRichContent.hideLater(hideDelay)`.
//   - `findPointFromSeries` (the data-driven showTip position) — NO LONGER DEFERRED: it is wired in
//     `manuallyShowTip`, which `EChartsView` routes the item-path `showTip` action to. `target` and
//     `positionDefault` are threaded too; still deferred on that path: `position: payload.position`
//     (see the PORT-TODO there).
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
// The `formatter` callback contract (upstream types)
// ============================================================================
//
// upstream `type TooltipCallbackDataParams = CallbackDataParams & { axisDim?, axisIndex?, axisType?,
//   axisId?, axisValue?, axisValueLabel?, marker? }` (TooltipView.ts:127). Swift has no intersection
//   type and a `struct` cannot gain stored properties in an `extension`, so the extra slots were added
//   to `CallbackDataParams` itself (util/types.swift — see the PORT-NOTE there) and this alias keeps
//   upstream's spelling at the call sites.
public typealias TooltipCallbackDataParams = CallbackDataParams

// The REST of the `formatter` contract is declared at its UPSTREAM home, not here (PORTING.md §2 —
//   one upstream symbol, one definition):
//   - `TopLevelFormatterParams` (upstream TooltipModel.ts:34) -> component/tooltip/TooltipModel.swift:
//     the tagged enum for `TooltipCallbackDataParams | TooltipCallbackDataParams[]`, i.e. the `params`
//     `_showTooltipContent` threads (ONE for trigger:'item', the LIST for trigger:'axis').
//   - `TooltipFormatterCallback<T>` and its `callback` parameter (`TooltipFormatterAsyncCallback`)
//     (upstream util/types.ts) -> util/types.swift: the callable shape a user `formatter` closure must
//     be spelled with — the one `_callFunctionFormatter` casts to.

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

    // upstream: `private _ticket: string;` (TooltipView.ts:157) — the ASYNC ticket of the tooltip
    //   currently on screen. A function `formatter` may call its `callback(asyncTicket, html)` LATER;
    //   the content is only swapped in if the ticket is still the current one (i.e. the user has not
    //   hovered something else meanwhile).
    private var _ticket: String = ""

    // upstream: `private _showTimout: number;` (the `setTimeout` id — upstream's typo spelling is kept
    //   verbatim per PORTING.md §1). Modeled as a `DispatchWorkItem` so it can be cancelled, which is
    //   the Swift analogue of `clearTimeout` (same substitution `util/throttle.swift` makes).
    private var _showTimout: DispatchWorkItem?

    // upstream: `private _lastDataByCoordSys: DataByCoordSys[];` (TooltipView.ts:161) — the axis-tooltip
    //   payload tree the box on screen was built from, and the params list handed to its `formatter`.
    //   Used ONLY by the trigger:'axis' path (`_updateContentNotChangedOnAxis`), which compares the newly
    //   built tree against them to decide whether the content can be left alone and only MOVED.
    //   Every path that invalidates the shown content clears BOTH (the item path in `tryShow`, `hide()`,
    //   `dispose()`), exactly where upstream does.
    //   PORT-NOTE (deferred): upstream's `_keepShow` also reads `_lastDataByCoordSys` (to re-show the axis
    //     tooltip after a refresh, via `manuallyShowTip({x, y, dataByCoordSys})`); `_keepShow` itself is
    //     still deferred (it needs the `render`-time re-entry this port has no ComponentView for).
    private var _lastDataByCoordSys: [DataByCoordSys]?

    // upstream: `private _cbParamsList: TooltipCallbackDataParams[];` (TooltipView.ts:162)
    private var _cbParamsList: [TooltipCallbackDataParams]?

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
    //   - `target`    : upstream `TryShowParams['target']` (`e.target`) — the HOVERED element, handed to
    //                   `_updatePosition` as `el` so the STRING `position` keywords
    //                   ('inside'/'top'/'bottom'/'left'/'right') can anchor on its bounding rect and the
    //                   `position` CALLBACK receives a real `rect`. Defaults to the event's own target;
    //                   an action-driven show passes `findPointFromSeries`'s `pointInfo.el`.
    //   - `positionDefault`: upstream `TryShowParams['positionDefault']` — 'bottom' for a MANUALLY
    //                   triggered tooltip (the mouse is not on the el, so upstream anchors the box below
    //                   it). Applied exactly as upstream does, via `buildTooltipModel`'s
    //                   `defaultTooltipOption` — the BASE model UNDER the global option, so an explicit
    //                   `tooltip.position` (or a series-level one) still wins.
    // ------------------------------------------------------------------------
    public func tryShow(
        event: ElementEvent?,
        seriesModel: SeriesModel,
        dataIndex: Double,
        dataType: SeriesDataType? = nil,
        point: [Double],
        target: Element? = nil,
        positionDefault: String? = nil
    ) {
        // upstream `_showSeriesItemTooltip` passes `e.target` down as `el`.
        let el: Element? = target ?? event?.target
        guard let ecModel = self._ecModel, let globalTooltipModel = self._globalTooltipModel else {
            return
        }

        // upstream `_tryShow`, the `else if (el)` (item) branch (TooltipView.ts:477):
        //   `this._lastDataByCoordSys = null; this._cbParamsList = null;`
        //   The item path replaces whatever the axis path put on screen, so the axis no-change memo
        //   (`_updateContentNotChangedOnAxis`) must not match against it afterwards. Cleared BEFORE the
        //   trigger guard below, exactly like upstream (which clears in `_tryShow`, one frame above the
        //   guard that lives in `_showSeriesItemTooltip`).
        self._lastDataByCoordSys = nil
        self._cbParamsList = nil

        // --- buildTooltipModel (SLIM): series `tooltip` merged OVER the global tooltip model. --------
        // upstream cascades [data.getItemModel(dataIndex), seriesModel, coordSys.model] over the global
        //   model (TooltipView.ts:680). The per-data-item + coord-system layers are DEFERRED; the series
        //   `tooltip` option (ignoreParent) is layered over the global model so `.get(...)` falls through
        //   to the registered global defaults (show / trigger / textStyle / order / …).
        //
        // upstream `buildTooltipModel(cascade, globalTooltipModel, defaultTooltipOption)`
        //   (TooltipView.ts:1071-1086): when a `defaultTooltipOption` is supplied it becomes the model at
        //   the BOTTOM of the cascade and the GLOBAL option is re-parented onto it
        //   (`new Model(globalTooltipModel.option, new Model(defaultTooltipOption, ecModel, ecModel))`),
        //   i.e. every explicitly-configured layer outranks the default. `positionDefault` is upstream's
        //   only user of that argument.
        var baseModel: Model = globalTooltipModel
        if let positionDefault = positionDefault {
            let defaultOptionModel = Model(["position": positionDefault], ecModel, ecModel)
            baseModel = Model(globalTooltipModel.option, defaultOptionModel, ecModel)
        }
        let tooltipModel: Model
        if let seriesTooltipOpt = seriesModel.get("tooltip", true) as? [String: Any] {
            tooltipModel = Model(seriesTooltipOpt, baseModel, ecModel)
        }
        else {
            tooltipModel = baseModel
        }

        // upstream `_showSeriesItemTooltip` guard (TooltipView.ts:690): trigger must be nil or 'item'.
        let tooltipTrigger = tooltipModel.get("trigger") as? String
        if let t = tooltipTrigger, t != "item" {
            // PORT-NOTE: this item-only entry bails on trigger:'axis'; the axis tooltip IS ported
            //   (`_showAxisTooltip`) and reached via the axisTrigger path (EChartsView), not from here.
            return
        }

        // --- build markup (upstream TooltipView.ts:695-717) -----------------------------------------
        // upstream: `const params = dataModel.getDataParams(dataIndex, dataType)` (TooltipView.ts:695).
        //   Threaded into `_showTooltipContent` so a string/function `formatter` can reference the datum.
        var params = seriesModel.getDataParams(dataIndex, dataType)
        let markupStyleCreator = TooltipMarkupStyleCreator()
        // upstream (TooltipView.ts:698): Pre-create marker style for makers. Users can assemble richText
        //   text in `formatter` callback and use those markers style.
        //   `params.marker = markupStyleCreator.makeTooltipMarker('item', convertToColorString(params.color), renderMode)`
        params.marker = .string(markupStyleCreator.makeTooltipMarker(
            .item,
            format.convertToColorString(params.color),
            self._renderMode
        ))

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

        // upstream: `const asyncTicket = 'item_' + dataModel.name + '_' + dataIndex;` (TooltipView.ts:719)
        let asyncTicket = "item_" + seriesModel.name + "_" + number.jsNumberString(dataIndex)

        // upstream (TooltipView.ts:721): this._showOrMove(tooltipModel, function () {
        //   this._showTooltipContent(tooltipModel, markupText, params, asyncTicket, e.offsetX, e.offsetY,
        //                            e.position, e.target, markupStyleCreator); });
        let x = point.count > 0 ? point[0] : 0
        let y = point.count > 1 ? point[1] : 0
        _showOrMove(tooltipModel) { [weak self] in
            self?._showTooltipContent(
                tooltipModel: tooltipModel,
                defaultHtml: html,
                params: .single(params),
                asyncTicket: asyncTicket,
                x: x,
                y: y,
                // upstream: `e.position` — the payload `position` override. Not threaded by the slim
                //   entry (see the PORT-TODO in `manuallyShowTip`), so `_showTooltipContent` falls back
                //   to the model's `position`.
                positionExpr: nil,
                el: el,
                markupStyleCreator: markupStyleCreator
            )
        }
    }

    // ------------------------------------------------------------------------
    // _showOrMove — ported from upstream `_showOrMove` (TooltipView.ts:517). Every show path funnels its
    //   "actually put the content on screen" step through here so `tooltip.showDelay` takes effect.
    //
    //   PORT-NOTE (adaptation, faithful): browser `setTimeout(cb, delay)` / `clearTimeout(id)` →
    //     `DispatchQueue.main.asyncAfter` over a cancellable `DispatchWorkItem` — the substitution
    //     `util/throttle.swift` already makes (upstream delays are MILLISECONDS, hence `/ 1000`).
    //     Upstream's `cb = bind(cb, this)` has no analogue: a Swift closure already carries its own
    //     capture, and every call site captures `self` WEAKLY so a fired timer can never resurrect a
    //     tooltip whose view was disposed/released (see `dispose()`, which also cancels).
    //     No explicit repaint is needed around the deferred `cb`: `setContent` goes through
    //     `zr.remove`/`zr.add` and `show()`/`moveTo()` through `Element.markRedraw()`, each of which
    //     already calls `zr.refresh()` (marks `_needsRefresh` + wakes the animation loop) — the same
    //     next-frame model as upstream zrender.
    // ------------------------------------------------------------------------
    private func _showOrMove(_ tooltipModel: Model, _ cb: @escaping () -> Void) {
        // showDelay is used in this case: tooltip.enterable is set
        // as true. User intent to move mouse into tooltip and click
        // something. `showDelay` makes it easier to enter the content
        // but tooltip do not move immediately.
        let delay = asDouble(tooltipModel.get("showDelay")) ?? 0
        // upstream: clearTimeout(this._showTimout);
        self._showTimout?.cancel()
        self._showTimout = nil
        // upstream: delay > 0 ? (this._showTimout = setTimeout(cb, delay)) : cb();
        if delay > 0 {
            let work = DispatchWorkItem { [weak self] in
                // PORT-NOTE (adaptation): release the slot BEFORE running `cb`. Upstream's `_showTimout`
                //   is a plain `setTimeout` id (a number), so a fired timer retains nothing; a
                //   `DispatchWorkItem` retains its closure — and therefore the captured `SeriesModel`,
                //   params and markup — until the slot is reassigned. Clearing first is safe (a replaced
                //   item is always `cancel()`ed, so a RUNNING item is by construction the current one)
                //   and cannot clobber a newer timer `cb` itself might arm.
                self?._showTimout = nil
                cb()
            }
            self._showTimout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay / 1000.0, execute: work)
        }
        else {
            cb()
        }
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

        // upstream: `const cbParamsList: TooltipCallbackDataParams[] = [];` (TooltipView.ts:545) — the
        //   params handed to a `formatter` callback on the axis path (one entry per listed series).
        var cbParamsList: [TooltipCallbackDataParams] = []

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
                // upstream: `const axis = axisModel.axis;` — the BASE `Axis`. `AxisBaseModel.axis` is
                //   typed `Any` in this port, so it is narrowed twice: `rawAxis` is what upstream calls
                //   `axis` (and what `axisHelper.getAxisRawValue` takes — coord/axisHelper.swift), while
                //   the cartesian-only `Axis2D` narrowing is needed by the slim `_axisValueLabel` below.
                //   The axis path is also reached for polar (angle/radius) and single axes, which are NOT
                //   `Axis2D` — `cbParams.axisValue` must still be stamped for them.
                let rawAxis = axisModel.axis as? Axis
                let axis = axisModel.axis as? Axis2D
                // upstream: `const axisValueParsed = axis.scale.parse(axisValue);` (TooltipView.ts:558)
                //   — hoisted to the per-AXIS scope, above the `seriesDataIndices` loop.
                let axisValueParsed = rawAxis?.scale.parse(axisValue)

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

                    // upstream (TooltipView.ts:582-601): build this series' callback params and stamp the
                    //   hovered axis onto them, so a `formatter` callback can read `axisValue(Label)` etc.
                    var cbParams = series.getDataParams(dataIndex)
                    // upstream: `if (cbParams.dataIndex < 0) return;`  // Can't find data.
                    if cbParams.dataIndex < 0 { continue }
                    cbParams.axisDim = axisItem.axisDim
                    cbParams.axisIndex = axisItem.axisIndex
                    cbParams.axisType = axisItem.axisType
                    cbParams.axisId = axisItem.axisId
                    // upstream: `axisHelper.getAxisRawValue(axisModel.axis, { value: axisValueParsed })`
                    if let rawAxis = rawAxis, let axisValueParsed = axisValueParsed {
                        cbParams.axisValue = axisHelper.getAxisRawValue(
                            rawAxis, ScaleTick(value: axisValueParsed)
                        )
                    }
                    cbParams.axisValueLabel = axisValueLabel
                    // upstream: Pre-create marker style for makers. Users can assemble richText text in
                    //   `formatter` callback and use those markers style.
                    cbParams.marker = .string(markupStyleCreator.makeTooltipMarker(
                        .item,
                        format.convertToColorString(cbParams.color),
                        renderMode
                    ))

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
                    cbParamsList.append(cbParams)   // upstream: cbParamsList.push(cbParams);
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

        // upstream (TooltipView.ts:637-650):
        //   this._showOrMove(singleTooltipModel, function () {
        //       if (this._updateContentNotChangedOnAxis(dataByCoordSys, cbParamsList)) {
        //           this._updatePosition(singleTooltipModel, positionExpr, point[0], point[1],
        //                                this._tooltipContent, cbParamsList);
        //       }
        //       else {
        //           this._showTooltipContent(singleTooltipModel, allMarkupText, cbParamsList,
        //               Math.random() + '', point[0], point[1], positionExpr, null, markupStyleCreator);
        //       }
        //   });
        //   The no-change branch leaves the content element (and its rich-text layout) UNTOUCHED and only
        //   MOVES the box — the pointer sliding within one category must not rebuild the ZRText.
        //   upstream's asyncTicket on the rebuild branch is `Math.random() + ''` (TooltipView.ts:648).
        //   `positionExpr` is upstream's `const positionExpr = e.position` (the axis payload's position
        //   override); the ported `DataByCoordSys` payload carries no `position`, so it stays nil and
        //   `_showTooltipContent` falls back to the model's `position`.
        //   `el` is nil — upstream's axis branch also passes no element, so a STRING `position` keyword
        //   ('top'/'left'/…) is inert on the axis path in upstream too (it needs a hovered element).
        _showOrMove(singleTooltipModel) { [weak self] in
            guard let self = self else { return }
            // (the memo is updated by the call itself, so it must run before the branch is taken)
            let contentNotChanged = self._updateContentNotChangedOnAxis(dataByCoordSys, cbParamsList)
            // PORT-NOTE (divergence, safety — no upstream analogue): `&& self._tooltipContent.el != nil`.
            //   `TooltipRichContent.getSize()` (upstream TooltipRichContent.ts:118) reads `this.el`
            //   unguarded, and the richText `el` only exists once `setContent` has run. With
            //   `showContent: false` (or `show: false`) `_showTooltipContent` returns BEFORE building it,
            //   while `_updateContentNotChangedOnAxis` has already memoized the tree — so the next
            //   identical hover would take this branch and dereference a nil `el` (a JS TypeError
            //   upstream; a SIGTRAP here, PORTING.md §12). Falling through to `_showTooltipContent`
            //   instead reproduces upstream's INTENT exactly: with showContent:false it returns early
            //   again (nothing shown), and if the box is missing for any other reason it is rebuilt.
            if contentNotChanged && self._tooltipContent.el != nil {
                self._updatePosition(
                    tooltipModel: singleTooltipModel,
                    positionExpr: nil,
                    x: x, y: y,
                    content: self._tooltipContent,
                    params: .multiple(cbParamsList)
                    // upstream passes no `el` on this branch either.
                )
            }
            else {
                self._showTooltipContent(
                    tooltipModel: singleTooltipModel,
                    defaultHtml: allMarkupText,
                    params: .multiple(cbParamsList),   // the axis tooltip lists EVERY series at the value
                    asyncTicket: number.jsNumberString(Double.random(in: 0..<1)),
                    x: x,
                    y: y,
                    positionExpr: nil,
                    el: nil,
                    markupStyleCreator: markupStyleCreator
                )
            }
        }
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
    // _showTooltipContent — upstream (TooltipView.ts:812). The `formatter` (string/function) override
    //   and the async `_ticket` ARE ported (see below). Callers reach this only through `_showOrMove`,
    //   so `tooltip.showDelay` has already been honoured by the time it runs.
    // ------------------------------------------------------------------------
    private func _showTooltipContent(
        tooltipModel: Model,
        defaultHtml: String,
        params: TopLevelFormatterParams,
        asyncTicket: String,
        x: Double,
        y: Double,
        // upstream's `positionExpr` (`e.position`, the per-dispatch override) + `el` (the hovered
        //   element) sit between `y` and `markupStyleCreator` — the parameter order is upstream's verbatim.
        positionExpr positionExprIn: Any?,
        el: Element?,
        markupStyleCreator: TooltipMarkupStyleCreator
    ) {
        // upstream: `// Reset ticket` / `this._ticket = '';` (TooltipView.ts:825)
        self._ticket = ""

        // upstream: `if (!tooltipModel.get('showContent') || !tooltipModel.get('show')) return;`
        let showContent = (tooltipModel.get("showContent") as? Bool) ?? true
        let show = (tooltipModel.get("show") as? Bool) ?? true
        if !showContent || !show {
            return
        }

        let content = self._tooltipContent
        content.setEnterable(tooltipModel.get("enterable") as? Bool)

        // upstream:
        //   const nearPoint = this._getNearestPoint(
        //       [x, y], params, tooltipModel.get('trigger'),
        //       tooltipModel.get('borderColor'), tooltipModel.get('defaultBorderColor', true));
        //   const nearPointColor = nearPoint.color;
        let nearPointColor: ColorString? = _getNearestPoint(
            [x, y],
            params,
            tooltipModel.get("trigger") as? String,
            tooltipModel.get("borderColor") as? String,
            tooltipModel.get("defaultBorderColor", true) as? String
        )

        // upstream `formatter` override of the default markup (TooltipView.ts:835-873).
        //
        //   STRING formatter: the time-axis `timeFormat` pre-pass (`timeFormat` == this port's
        //     `time.format`) followed by `formatTpl`, which substitutes the datum's `$vars` (the
        //     a/b/c/d/e aliases + the named vars).
        //
        //   FUNCTION formatter: upstream's signature is
        //     `formatter(params, asyncTicket, callback) => string`,
        //     where `callback(cbTicket, html)` may be invoked LATER (async content). Both the
        //     synchronous return path and the async ticket path are ported.
        //     PORT-NOTE: `util.isFunction` is unreliable for Swift closures (no introspectable
        //       metadata), so "is callable" is resolved STATICALLY by casting the option value to the
        //       formatter signature — the established closure-in-option idiom (model/mixin/
        //       dataFormat.swift:197). The CANONICAL shape is the already-ported
        //       `TooltipFormatterCallback<T>` (util/types.swift) — the type `CommonTooltipOption.formatter`
        //       documents. A JS function is additionally arity-tolerant while a Swift closure type is
        //       not, so the 1-arg spelling upstream users most often write is accepted too:
        //         trigger:'item'  `TooltipFormatterCallback<TooltipCallbackDataParams>`
        //                         `(TooltipCallbackDataParams) -> String`
        //         trigger:'axis'  `TooltipFormatterCallback<[TooltipCallbackDataParams]>`
        //                         `([TooltipCallbackDataParams]) -> String`
        //       The arity is matched against the params shape actually passed (single for the item
        //       path, the list for the axis path) — exactly what upstream hands the JS function; an
        //       array-typed closure is NOT invoked with a synthesized one-element array, and vice versa.
        //
        //   PORT-NOTE: upstream's `html: string | HTMLElement | HTMLElement[]` union (and the final
        //     `else { html = formatter }` arm, which assigns a non-string non-function `formatter` —
        //     i.e. an `HTMLElement`) has no analogue here: renderMode is FORCED 'richText' and the
        //     content host is a `ZRText`. A non-string/non-closure `formatter` is therefore ignored
        //     (the default markup stands) rather than dropped into the box.
        let formatter = tooltipModel.get("formatter")
        var html = defaultHtml
        // upstream `if (formatter)` is a JS-truthy test, so an EMPTY-STRING formatter is falsy and the
        //   default markup stands (PORTING.md §8: string truthiness is replicated explicitly).
        if let formatter = formatter, (formatter as? String) != "" {
            if let formatterStr = formatter as? String {
                // upstream:
                //   const useUTC = tooltipModel.ecModel.get('useUTC');
                //   const params0 = isArray(params) ? params[0] : params;
                //   const isTimeAxis = params0 && params0.axisType && params0.axisType.indexOf('time') >= 0;
                //   html = formatter;
                //   if (isTimeAxis) { html = timeFormat(params0.axisValue, html, useUTC); }
                //   html = formatTpl(html, params, true);
                let useUTC = (tooltipModel.ecModel?.get("useUTC") as? Bool) ?? false
                let params0: TooltipCallbackDataParams?
                switch params {
                case .single(let one): params0 = one
                case .multiple(let list): params0 = list.first
                }
                // PORT-TODO: this test is DORMANT in the port. `axisType` is `axisModel.type`
                //   (component/axisPointer/axisTrigger.swift, faithful to axisTrigger.ts), and upstream's
                //   `ComponentModel.type` is `<mainType>.<subType>` — 'xAxis.time'. But the axis models
                //   `ECharts.setOption` actually instantiates (`EChartsXAxisModel` / `EChartsYAxisModel`,
                //   core/ECharts.swift) override `type` to the MAIN type alone ("xAxis"), so
                //   `indexOf('time') >= 0` can never match and a `{yyyy}`-style template is left
                //   unformatted on a time axis. The `subType` ("time") IS correct on those models — the
                //   fix belongs on `EChartsXAxisModel.type`, not here, so the upstream expression is
                //   kept verbatim. (`coord/axisModelCreator.swift`'s `AxisModel.type` already returns the
                //   upstream form; it is simply not the class that gets instantiated.)
                let isTimeAxis = params0?.axisType?.contains("time") ?? false
                html = formatterStr
                if isTimeAxis {
                    // `timeFormat` is upstream's alias of `util/time`'s `format` — ported as `time.format`.
                    html = time.format(params0?.axisValue, html, useUTC)
                }
                html = format.formatTpl(html, tplParamFromFormatterParams(params), true)
            }
            else if let formatterResult = _callFunctionFormatter(
                formatter, params, asyncTicket,
                // upstream:
                //   const callback = bind(function (cbTicket, html) {
                //       if (cbTicket === this._ticket) {
                //           tooltipContent.setContent(html, markupStyleCreator, tooltipModel,
                //               nearPointColor, positionExpr);
                //           this._updatePosition(tooltipModel, positionExpr, x, y, tooltipContent, params, el);
                //       }
                //   }, this);
                TooltipFormatterAsyncCallback { [weak self] cbTicket, asyncHtml in
                    guard let self = self else { return }
                    if cbTicket == self._ticket {
                        content.setContent(
                            asyncHtml, markupStyleCreator, tooltipModel, nearPointColor, positionExprIn
                        )
                        self._updatePosition(
                            tooltipModel: tooltipModel,
                            positionExpr: positionExprIn,
                            x: x, y: y,
                            content: content,
                            params: params,
                            el: el
                        )
                    }
                }
            ) {
                // upstream: `this._ticket = asyncTicket;` BEFORE the call, so a `callback` invoked
                //   synchronously from inside the formatter already sees the current ticket.
                //   (`_callFunctionFormatter` performs the assignment for the same reason.)
                html = formatterResult
            }
        }

        content.setContent(html, markupStyleCreator, tooltipModel, nearPointColor, positionExprIn)
        content.show()   // rich content: no-arg (upstream html `show(model, color)` args are html-only)
        _updatePosition(
            tooltipModel: tooltipModel,
            positionExpr: positionExprIn,
            x: x, y: y,
            content: content,
            params: params,
            el: el
        )
    }

    // ------------------------------------------------------------------------
    // The `isFunction(formatter)` arm of `_showTooltipContent` (TooltipView.ts:856-869), factored out
    //   so the accepted Swift closure spellings sit in one place. The canonical shape is the ported
    //   `TooltipFormatterCallback<T>` (util/types.swift), instantiated at the params shape actually
    //   passed; the 1-arg spelling is accepted alongside it only because a JS function is arity-tolerant
    //   and a Swift closure type is not. Returns `nil` when the option value is NOT callable at any of
    //   them (upstream's final `else { html = formatter }` arm).
    //   `this._ticket = asyncTicket` is assigned BEFORE the invocation, exactly like upstream, so a
    //   `callback` fired synchronously from inside the formatter already matches the live ticket.
    // ------------------------------------------------------------------------
    private func _callFunctionFormatter(
        _ formatter: Any,
        _ params: TopLevelFormatterParams,
        _ asyncTicket: String,
        _ callback: TooltipFormatterAsyncCallback
    ) -> String? {
        switch params {
        case .single(let params):
            // upstream: `html = formatter(params, asyncTicket, callback)`
            if let formatter = formatter as? TooltipFormatterCallback<TooltipCallbackDataParams> {
                self._ticket = asyncTicket
                return formatter(params, asyncTicket, callback)
            }
            // A 1-arg JS formatter (`params => ...`), the common spelling — arity-tolerant in JS, a
            //   DISTINCT closure type in Swift, so it needs its own cast.
            if let formatter = formatter as? (TooltipCallbackDataParams) -> String {
                self._ticket = asyncTicket
                return formatter(params)
            }
        case .multiple(let params):
            if let formatter = formatter as? TooltipFormatterCallback<[TooltipCallbackDataParams]> {
                self._ticket = asyncTicket
                return formatter(params, asyncTicket, callback)
            }
            if let formatter = formatter as? ([TooltipCallbackDataParams]) -> String {
                self._ticket = asyncTicket
                return formatter(params)
            }
        }
        return nil
    }

    // ------------------------------------------------------------------------
    // _getNearestPoint — upstream (TooltipView.ts:884). The tooltip box's BORDER colour: on the axis
    //   path (or whenever `params` is the LIST) the model's `borderColor` else `defaultBorderColor`;
    //   on the item path the hovered datum's OWN colour, so the border matches the hovered series.
    //   PORT-NOTE: upstream returns the single-field object `{ color }`; a one-field Swift tuple is not
    //     expressible, so the value itself is returned (the sole call site reads `.color`).
    //   PORT-NOTE: upstream's `ZRColor` return narrows to `ColorString` here — `TooltipRichContent.
    //     setContent` takes the border colour as a `String?` (upstream casts it `as string` too), and
    //     `params.borderColor` is already a `String?` on `CallbackDataParams`.
    // ------------------------------------------------------------------------
    private func _getNearestPoint(
        _ point: [Double],
        _ tooltipDataParams: TopLevelFormatterParams,
        _ trigger: String?,
        _ borderColor: ColorString?,
        _ defaultBorderColor: ColorString?
    ) -> ColorString? {
        _ = point   // upstream declares but does not read `point` either.
        // upstream: if (trigger === 'axis' || isArray(tooltipDataParams)) return { color: borderColor || defaultBorderColor };
        if trigger == "axis" {
            return borderColor ?? defaultBorderColor
        }
        switch tooltipDataParams {
        case .multiple:
            return borderColor ?? defaultBorderColor
        case .single(let tooltipDataParams):
            // upstream: return { color: borderColor || tooltipDataParams.color || tooltipDataParams.borderColor };
            //   `.color` is a `ZRColor` (a gradient/pattern is legal), so it goes through
            //   `convertToColorString` — but via `map`, so an ABSENT color still falls through to
            //   `.borderColor` instead of collapsing to the 'transparent' default.
            return borderColor
                ?? tooltipDataParams.color.map { format.convertToColorString($0) }
                ?? tooltipDataParams.borderColor
        }
    }

    // ------------------------------------------------------------------------
    // _updatePosition — (upstream TooltipView.ts:905). Ports the `position` option in every upstream
    //   form: the CALLBACK (`isFunction`), an ARRAY `[x, y]` (percent-aware via `parsePercent`), an
    //   OBJECT box-layout (`getLayoutRect`), the STRING keywords 'inside'/'top'/'bottom'/'left'/'right'
    //   around the hovered graphic element (`calcTooltipPosition`), and `align`/`verticalAlign` offsets;
    //   falls back to the DEFAULT `refixTooltipPosition` (flip to the other side of the pointer, gap 20)
    //   when no positionExpr; then applies `confineTooltipPosition` gated by `shouldTooltipConfine`
    //   (true for richText unless `confine:false`).
    //
    //   PORT-NOTE (divergence, faithful): upstream hands the callback `content.el`, typed
    //     `HTMLDivElement | ZRText` — the HTML host's DIV or the richText host's `ZRText`. This port
    //     forces renderMode 'richText' (no DOM host), so the third callback argument is ALWAYS the
    //     `TooltipRichContent`'s `ZRText` (the `TooltipPositionCallback` typealias types it `Any?`,
    //     matching the upstream union).
    //   PORT-NOTE (signature reconciliation): upstream's `params` here is the SAME
    //     `TooltipCallbackDataParams | TooltipCallbackDataParams[]` union the `formatter` receives, so it
    //     is threaded as the ported `TopLevelFormatterParams` enum (component/tooltip/TooltipModel.swift)
    //     and unwrapped to the `TooltipPositionCallbackParams` (= `Any`) arm the callback signature names
    //     — `.single` → one `CallbackDataParams`, `.multiple` → the `[CallbackDataParams]` list, exactly
    //     what upstream passes on the item / axis paths respectively.
    //   PORT-NOTE (divergence): upstream's `isObject(positionExpr)` arm receives a plain JS object cast
    //     to `BoxLayoutOptionMixin`. In this port an option object is an `[String: Any]` bag, so BOTH the
    //     bag AND the typed `TooltipBoxLayoutOption` (the arm the `TooltipPositionCallback` return union
    //     names) are accepted; the typed struct is normalized into the bag `getLayoutRect` reads.
    //   PORT-NOTE (divergence, LANGUAGE constraint — no upstream analogue): upstream's `isFunction(
    //     positionExpr)` accepts ANY callable. Swift's `as? TooltipPositionCallback` is an EXACT function
    //     -type cast: a closure written with a structurally-similar but differently-spelled signature
    //     (`-> [Double]` instead of `-> Any`, a `CallbackDataParams` params slot instead of
    //     `TooltipPositionCallbackParams`, …) is a DIFFERENT Swift type and fails the cast SILENTLY,
    //     degrading to the default `refixTooltipPosition` placement. A `position` callback MUST therefore
    //     be stored annotated: `["position": (cb as TooltipPositionCallback)]` (see the same note on
    //     `CommonTooltipOption.position`, util/types.swift).
    //   PORT-NOTE (divergence): upstream's string-keyword branch is gated on the ELEMENT
    //     (`isString(positionExpr) && el`) because `el.getBoundingRect()` is non-null there. This port's
    //     `Element.getBoundingRect()` returns `BoundingRect?` and the BASE implementation returns nil
    //     (Sources/ZRenderKit/Element.swift), so the branch is gated on the RECT instead: a non-nil `el`
    //     with no bounding rect (a bare `Element`/`Group`-like target) deliberately degrades to the
    //     default pointer-relative placement rather than anchoring at 0,0.
    // ------------------------------------------------------------------------
    private func _updatePosition(
        tooltipModel: Model,
        positionExpr positionExprIn: Any?,
        x: Double,   // Mouse x
        y: Double,   // Mouse y
        content: TooltipRichContent,
        params: TopLevelFormatterParams,
        el: Element? = nil
    ) {
        let viewWidth = _zr.getWidth() ?? 0
        let viewHeight = _zr.getHeight() ?? 0

        // upstream: `positionExpr = positionExpr || tooltipModel.get('position')`.
        var positionExpr = positionExprIn ?? tooltipModel.get("position")

        let contentSize = content.getSize()
        let width = contentSize.count > 0 ? contentSize[0] : 0
        let height = contentSize.count > 1 ? contentSize[1] : 0
        var align = tooltipModel.get("align") as? String
        var vAlign = tooltipModel.get("verticalAlign") as? String
        // upstream: const rect = el && el.getBoundingRect().clone(); el && rect.applyTransform(el.transform);
        let rect: BoundingRect? = el?.getBoundingRect()?.clone()
        if let el = el { rect?.applyTransform(el.transform) }

        var px = x
        var py = y

        // upstream: if (isFunction(positionExpr)) { positionExpr = positionExpr([x, y], params,
        //     content.el, rect, { viewSize: [...], contentSize: contentSize.slice() }); }
        //   Callback of position can be an array or a string specify the position.
        if let positionCb = positionExpr as? TooltipPositionCallback {
            positionExpr = positionCb(
                (px, py), positionCallbackParams(params), content.el, rect,
                TooltipPositionCallbackSize(
                    contentSize: (width, height),
                    viewSize: (viewWidth, viewHeight)
                )
            )
        }

        if let arr = positionExpr as? [Any] {
            // upstream: x = parsePercent(positionExpr[0], viewWidth); y = parsePercent(positionExpr[1], viewHeight)
            px = number.parsePercent(arr.count > 0 ? arr[0] : nil, viewWidth)
            py = number.parsePercent(arr.count > 1 ? arr[1] : nil, viewHeight)
        }
        else if let obj = boxLayoutOptionBag(positionExpr) {
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
            // When positionExpr is left/top/right/bottom,
            // align and verticalAlign will not work.
            vAlign = nil
        }
        // Specify tooltip position by string 'top' 'bottom' 'left' 'right' around graphic element
        // upstream: `else if (isString(positionExpr) && el)` — gated on `rect` here, see the PORT-NOTE
        //   above (`el.getBoundingRect()` is Optional in this port and nil on the Element base).
        else if let positionStr = positionExpr as? String, let rect = rect {
            let pos = calcTooltipPosition(
                positionStr, rect, contentSize, asDouble(tooltipModel.get("borderWidth")) ?? 0
            )
            px = pos[0]
            py = pos[1]
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

        content.moveTo(px, py)
    }

    // ------------------------------------------------------------------------
    // FIXME
    // Should we remove this but leave this to user?
    //
    // _updateContentNotChangedOnAxis — upstream (TooltipView.ts:983). The trigger:'axis' NO-CHANGE test:
    //   is the tree just built by `axisTrigger` EQUIVALENT to the one the box on screen was built from?
    //   If so the caller skips rebuilding the content entirely and only calls `_updatePosition`, so the
    //   pointer sliding within one category moves the SAME ZRText instead of discarding and re-laying-out
    //   a new one every mousemove. Also the (only) place that memoizes `_lastDataByCoordSys` /
    //   `_cbParamsList` — it stores the new tree/params on EVERY call, before returning.
    //
    //   Compared, recursively, exactly as upstream does (note it compares `value`/`axisType`/`axisId` but
    //   NOT `axisDim`/`axisIndex` — kept verbatim; the axis id already identifies the axis) plus, per
    //   series entry, `seriesIndex`/`dataIndex`; finally the hovered series' `cbParams.data` identity.
    //
    //   PORT-NOTE (adaptation): upstream's `arr[i] || {} as T` out-of-range reads become bounds-checked
    //     Optionals — an absent entry then fails every `===` below exactly like a `{}` placeholder's
    //     `undefined` fields do. (`contentNotChanged` is only ever ANDed, never re-raised, so upstream's
    //     `each` — which does not break — and these loops agree on the result regardless of order.)
    //   PORT-NOTE (adaptation): upstream `lastItem.value === thisItem.value` is JS strict equality over a
    //     `ScaleDataValue` (`number | string | Date`); `tooltipStrictEquals` below is that same-type-only
    //     test — the file-local `===` helper idiom `visual/VisualMapping.swift:986` and
    //     `data/helper/dataValueHelper.swift:422` already use, under a scoped name because this copy
    //     covers strictly more value kinds than either of those two (see its own note).
    //   PORT-NOTE (divergence, LANGUAGE constraint): upstream's LAST test is `lastCbParams.data !==
    //     cbParams.data`, an IDENTITY comparison of the raw data item (`data.getRawDataItem`). A raw item
    //     is a Swift VALUE in this port (a `Double`, a `[String: Any]` bag, an `[Any]` row), so reference
    //     identity is unrepresentable for the non-class cases; `tooltipStrictEquals` therefore compares
    //     them STRUCTURALLY (and by `===` when the item really is a class instance), which preserves
    //     upstream's intent — "the datum behind this tooltip line changed" — for the shapes this produces.
    //   PORT-NOTE (DIVERGENCE, wiring — read before trusting this memo): upstream this no-change branch is
    //     nearly unreachable for real pointer motion. Upstream registers the ITEM leg through
    //     `globalListener('itemTooltip')`, so `_tryShow` runs on EVERY mousemove, and both of its non-axis
    //     branches (`else if (el)` TooltipView.ts:477, `else` :511) null `_lastDataByCoordSys` BEFORE the
    //     pending axis `showTip` is dispatched — hence upstream's own `// FIXME Should we remove this`.
    //     In THIS port `tryShow` is wired only to zr `mouseover` (element ENTER), so the memo survives a
    //     mousemove and the branch is genuinely live. That is a deliberate divergence, not parity, and it
    //     has one observable consequence: while the pointer stays within one axis band, a `tooltip.
    //     formatter` callback is not re-invoked and content changed by a `setOption` (formatter/textStyle/
    //     valueFormatter, or data whose `getRawDataItem` is nil on both sides) would stay stale. The
    //     staleness window is closed from the RENDER side by `clearAxisTooltipMemo()` (see it below),
    //     which `EChartsView._afterSetOption()` calls on every setOption / post-action re-sync. It must
    //     NOT be done in `setModel(_:)`: `EChartsView._ensureTooltipView()` calls that immediately before
    //     every `_showAxisTooltip`, which would kill the feature outright.
    // ------------------------------------------------------------------------
    private func _updateContentNotChangedOnAxis(
        _ dataByCoordSys: [DataByCoordSys],
        _ cbParamsList: [TooltipCallbackDataParams]
    ) -> Bool {
        let lastCoordSys = self._lastDataByCoordSys
        let lastCbParamsList = self._cbParamsList
        // upstream: let contentNotChanged = !!lastCoordSys && lastCoordSys.length === dataByCoordSys.length;
        var contentNotChanged = lastCoordSys != nil
            && lastCoordSys?.count == dataByCoordSys.count

        // upstream: contentNotChanged && each(lastCoordSys, (lastItemCoordSys, indexCoordSys) => {
        if contentNotChanged, let lastCoordSys = lastCoordSys {
            for (indexCoordSys, lastItemCoordSys) in lastCoordSys.enumerated() {
                let lastDataByAxis = lastItemCoordSys.dataByAxis
                // upstream: const thisItemCoordSys = dataByCoordSys[indexCoordSys] || {} as DataByCoordSys;
                let thisDataByAxis = indexCoordSys < dataByCoordSys.count
                    ? dataByCoordSys[indexCoordSys].dataByAxis
                    : []
                contentNotChanged = contentNotChanged && lastDataByAxis.count == thisDataByAxis.count

                // upstream: contentNotChanged && each(lastDataByAxis, (lastItem, indexAxis) => {
                if contentNotChanged {
                    for (indexAxis, lastItem) in lastDataByAxis.enumerated() {
                        // upstream: const thisItem = thisDataByAxis[indexAxis] || {} as DataByAxis;
                        let thisItem: DataByAxis? = indexAxis < thisDataByAxis.count
                            ? thisDataByAxis[indexAxis]
                            : nil
                        let lastIndices = lastItem.seriesDataIndices
                        let newIndices = thisItem?.seriesDataIndices ?? []

                        contentNotChanged = contentNotChanged
                            && tooltipStrictEquals(lastItem.value, thisItem?.value)
                            && lastItem.axisType == thisItem?.axisType
                            && lastItem.axisId == thisItem?.axisId
                            && lastIndices.count == newIndices.count

                        // upstream: contentNotChanged && each(lastIndices, (lastIdxItem, j) => {
                        if contentNotChanged {
                            for (j, lastIdxItem) in lastIndices.enumerated() {
                                let newIdxItem = newIndices[j]   // counts are equal here
                                contentNotChanged = contentNotChanged
                                    && lastIdxItem.seriesIndex == newIdxItem.seriesIndex
                                    && lastIdxItem.dataIndex == newIdxItem.dataIndex
                            }
                        }

                        // check is cbParams data value changed
                        //   (upstream indexes BOTH lists by `seriesIndex`, not by push order — kept
                        //   verbatim; an out-of-range read is `undefined` there and nil here, and the
                        //   `if (cbParams && lastCbParams && …)` guard skips it either way.)
                        if let lastCbParamsList = lastCbParamsList {
                            for idxItem in lastItem.seriesDataIndices {
                                // `seriesIndex` is a `Double` (a JS `number`); a plain `Int(_:)` would
                                //   TRAP on NaN/±inf (PORTING.md §12) where JS just reads `undefined`.
                                guard let seriesIdx = asIntOrNil(idxItem.seriesIndex) else { continue }
                                let cbParams = elementAtOrNil(cbParamsList, seriesIdx)
                                let lastCbParams = elementAtOrNil(lastCbParamsList, seriesIdx)
                                if let cbParams = cbParams, let lastCbParams = lastCbParams,
                                   !tooltipStrictEquals(lastCbParams.data, cbParams.data) {
                                    contentNotChanged = false
                                }
                            }
                        }
                    }
                }
            }
        }

        self._lastDataByCoordSys = dataByCoordSys
        self._cbParamsList = cbParamsList

        return contentNotChanged
    }

    // ------------------------------------------------------------------------
    // clearAxisTooltipMemo — PORT-ONLY (no upstream analogue as a method; upstream nulls the same two
    //   fields inline). Invalidate the `_updateContentNotChangedOnAxis` memo so the NEXT axis hover
    //   rebuilds the content instead of only moving the box.
    //   WHY it exists: upstream's per-mousemove `_tryShow` item leg nulls `_lastDataByCoordSys` on every
    //   pointer move (TooltipView.ts:477/511), so a re-render can never leave stale content under the
    //   memo. This port only runs `tryShow` on element ENTER (see `_updateContentNotChangedOnAxis`'s
    //   wiring PORT-NOTE), so the invalidation has to come from the RENDER side instead:
    //   `EChartsView._afterSetOption()` calls this after every `setOption` / post-action re-sync.
    //   Deliberately NOT called from `setModel(_:)` — `EChartsView._ensureTooltipView()` runs that
    //   immediately before every `_showAxisTooltip`, which would disable the no-change branch entirely.
    // ------------------------------------------------------------------------
    public func clearAxisTooltipMemo() {
        _lastDataByCoordSys = nil
        _cbParamsList = nil
    }

    // ------------------------------------------------------------------------
    // hide / _hide — upstream `_hide` (TooltipView.ts:1034) only DISPATCHES `hideTip`; the actual content
    //   hide happens one hop later in `manuallyHideTip` (TooltipView.ts:398):
    //       `if (this._tooltipModel) { tooltipContent.hideLater(this._tooltipModel.get('hideDelay')); }`
    //   This port has no `update:'tooltip:manuallyHideTip'` view routing (see installTooltipActions'
    //   PORT-NOTE), so `EChartsView` calls `hide()` for BOTH hops — the `_hide` leave/mouseout leg and
    //   the `hideTip` action. Hence `hideLater` (i.e. `tooltip.hideDelay`) lives here: the box stays up
    //   for `hideDelay` ms after the pointer leaves, exactly as upstream, and `isShow()` flips to false
    //   immediately (upstream `hideLater` sets `_show = false` up front "to avoid invoke hideLater
    //   multiple times"). A subsequent `TooltipRichContent.show()` cancels the pending hide.
    //
    //   A pending DELAYED SHOW is deliberately NOT cancelled here: upstream `_hide`/`manuallyHideTip`
    //   never touch `_showTimout` (only `_showOrMove`'s own `clearTimeout` does), so a `showDelay` timer
    //   armed before the pointer left still fires. Faithful — see PORTING.md (fidelity over improvement).
    //   PORT-NOTE (divergence, small): when `_globalTooltipModel` is nil upstream skips the hide
    //     entirely (`if (this._tooltipModel)`); here that degrades to an IMMEDIATE hide
    //     (`hideLater(nil)`) so a model-less view can never strand a visible box.
    // ------------------------------------------------------------------------
    public func hide() {
        // upstream `_hide` (TooltipView.ts:1040) AND `manuallyHideTip` (TooltipView.ts:401) both clear the
        //   axis no-change memo before hiding — the box that is going away must never be reused by
        //   `_updateContentNotChangedOnAxis` as "unchanged content" on the next axis hover.
        _lastDataByCoordSys = nil
        _cbParamsList = nil
        _tooltipContent.hideLater(_globalTooltipModel.flatMap { asDouble($0.get("hideDelay")) })
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

        // upstream: `// Reset ticket` / `this._ticket = '';` (TooltipView.ts:305)
        self._ticket = ""

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
        // `pointInfo.el` (upstream's `target`) IS now threaded into `tryShow` → `_updatePosition`'s `el`,
        //   so a STRING `position` keyword ('inside'/'top'/'bottom'/'left'/'right') and the `rect`
        //   argument of a `position` CALLBACK work on the action-driven path too. `positionDefault:
        //   'bottom'` is threaded as well (see the `tryShow` doc): "When manully trigger, the mouse is not
        //   on the el, so we'd better to position tooltip on the bottom of the el".
        // PORT-TODO: `position: payload.position` — the per-dispatch position override
        //   (`TryShowParams.position`). `tryShow` has no `position` parameter yet, so a `showTip` payload
        //   carrying its own `position` is ignored and the model's (or the 'bottom' default) is used.

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
            point: [px, py],
            target: pointInfo.el,       // upstream: `target: pointInfo.el`
            positionDefault: "bottom"   // upstream: `positionDefault: 'bottom'`
        )
    }

    // upstream `manuallyHideTip` (TooltipView.ts:389) — the `update:'tooltip:manuallyHideTip'` target.
    //   Its content line — `tooltipContent.hideLater(this._tooltipModel.get('hideDelay'))` — is `hide()`
    //   (see the PORT-NOTEs there), which ALSO performs upstream's `_lastDataByCoordSys`/`_cbParamsList`
    //   reset (it stands in for both hops). The `_lastX/_lastY` reset and the `payload.from !== this.uid`
    //   re-dispatch of `_hide` have no analogue: this port keeps no last-POSITION state (`_keepShow` is
    //   deferred) and has no per-view action routing.
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
        // A pending `_showOrMove` timer must NOT fire after dispose — it would re-`setContent` and
        //   re-`zr.add` the box that was just removed. (Upstream's `dispose` does not clear
        //   `_showTimout` either, but its `_tooltipContent = null` makes the late callback throw
        //   harmlessly; Swift has no such accident, so cancel explicitly. The callbacks also capture
        //   `self` weakly, so a released view is doubly safe.)
        _showTimout?.cancel()
        _showTimout = nil
        // upstream `dispose` (TooltipView.ts:1058): `this._lastDataByCoordSys = null; this._cbParamsList = null;`
        _lastDataByCoordSys = nil
        _cbParamsList = nil
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
// asDouble — coerce a JS-number-ish option/payload/data value (Int, Double, or a bridged NSNumber) to
//   Double, and ONLY a number: a non-numeric value (String, Date, collection) and a real BOOLEAN both
//   yield nil, so a caller can tell "this is a JS number" apart from "this is something else"
//   (`tooltipStrictEquals` below relies on exactly that). Mirrors the Int-vs-Double option-read trap fix
//   (payloads box small ints as `Int`); the NSNumber arm covers raw data items arriving from bridged
//   JSON/plist collections (`SeriesData.getRawDataItem`).
// ----------------------------------------------------------------------------
private func asDouble(_ v: Any?) -> Double? {
    // A real boolean is NOT a number in JS (`typeof true === 'boolean'`), and it has to be rejected
    //   BEFORE the casts below: Foundation bridges `Bool` to an NSNumber that also casts to Double.
    if jsBoolOrNil(v) != nil { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// ----------------------------------------------------------------------------
// asIntOrNil — a NON-TRAPPING `Int(someDouble)`. `AxisTriggerDataIndex.seriesIndex`/`dataIndex` are
//   `Double` (a JS `number`), and `Int(Double.nan)` / `Int(±.infinity)` / an out-of-Int64-range value is
//   a runtime SIGTRAP in Swift, not a nil (PORTING.md §12 — do not mirror upstream's optimistic typing
//   with a construct that can crash). JS would just index with a non-integer key and get `undefined`,
//   which is what a nil result reproduces at the call site.
// ----------------------------------------------------------------------------
private func asIntOrNil(_ v: Double) -> Int? {
    return Int(exactly: v.rounded())
}

// ----------------------------------------------------------------------------
// jsBoolOrNil — is this value a JS BOOLEAN (and which one), as opposed to a number that merely happens
//   to be 0 or 1? A plain `v as? Bool` cannot answer that: Foundation conditionally bridges an
//   `NSNumber` holding 0/1 to `Bool`, so a numeric datum coming out of a bridged NSArray/NSDictionary
//   (JSON / plist-sourced series data — exactly what `getRawDataItem` can hand back) would read as a
//   boolean and never reach a numeric comparison. The CFBoolean type id is the reliable discriminator.
// ----------------------------------------------------------------------------
private func jsBoolOrNil(_ v: Any?) -> Bool? {
    if let n = v as? NSNumber {
        return CFGetTypeID(n) == CFBooleanGetTypeID() ? n.boolValue : nil
    }
    return v as? Bool
}

// ----------------------------------------------------------------------------
// `arr[i]` with a JS out-of-range read (-> `undefined` -> nil). Upstream `_updateContentNotChangedOnAxis`
//   indexes `cbParamsList` by SERIES INDEX, which may exceed its length; JS yields `undefined` and the
//   guard below skips the comparison, where Swift would trap.
// ----------------------------------------------------------------------------
private func elementAtOrNil<T>(_ arr: [T], _ i: Int) -> T? {
    return (i >= 0 && i < arr.count) ? arr[i] : nil
}

// ----------------------------------------------------------------------------
// tooltipStrictEquals — upstream `a === b` for the value kinds `_updateContentNotChangedOnAxis` compares
//   (a `ScaleDataValue` axis value: number | string | Date; and a raw data item: number | string | array
//   | object). Same-type only, exactly like JS (mixed types are never `===`).
//   PORT-NOTE (divergence, LANGUAGE constraint): JS `===` on two objects is REFERENCE identity. A raw
//     data item is a Swift VALUE here (an `[Any]` row, a `[String: Any]` bag), for which identity is
//     unrepresentable, so those arms compare STRUCTURALLY (element/key-wise, recursively). Class
//     instances still compare by `===`, matching upstream exactly. The structural arms are strictly more
//     permissive than upstream — i.e. they can only say "unchanged" where upstream (holding the same
//     stored item, hence the same reference) also says "unchanged".
//   NAMING (PORTING.md §2): deliberately NOT `jsStrictEquals`. Two file-private helpers of that name
//     already exist in this module — `visual/VisualMapping.swift:986` (String/number only) and
//     `data/helper/dataValueHelper.swift:422` (Bool/Double/String only; an Int-boxed number is `false`
//     there) — and this one must cover strictly more kinds (Int/NSNumber coercion, Date, the structural
//     collection arms, class identity). A third same-named copy giving DIFFERENT answers is the actual
//     trap §2 warns about, so the scope is carried in the name instead. (`===` is a JS operator, not an
//     upstream symbol, so §1 "names = upstream identifiers" does not pin the spelling.) If a canonical
//     shared `===` helper is ever hoisted into `util/`, this is the most complete of the three bodies.
// ----------------------------------------------------------------------------
private func tooltipStrictEquals(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (nil, _), (_, nil): return false
    default: break
    }
    // string === string
    if let sa = a as? String { return (b as? String) == sa }
    if b is String { return false }
    // boolean === boolean. Tested BEFORE the numeric arm, but via `jsBoolOrNil` (NOT `as? Bool`, which a
    //   bridged NSNumber holding 0/1 also satisfies — that would divert a numeric datum into this arm).
    //   Only a boolean-vs-boolean pair is decided here; a boolean vs anything else is `false` in JS
    //   (`true === 1` is false), and two NON-booleans fall through to the numeric arm untouched.
    let boolA = jsBoolOrNil(a)
    let boolB = jsBoolOrNil(b)
    if boolA != nil || boolB != nil {
        if let boolA = boolA, let boolB = boolB { return boolA == boolB }
        return false
    }
    // number === number (Int/Double/NSNumber all read as a Double here)
    if let na = asDouble(a), let nb = asDouble(b) { return na == nb }
    if asDouble(a) != nil || asDouble(b) != nil { return false }
    // Date === Date  (a `ScaleDataValue` arm; JS compares Date OBJECTS by reference, but a Swift `Date`
    //   is a value — same divergence as the collection arms below)
    if let da = a as? Date { return (b as? Date) == da }
    // structural arms (see the PORT-NOTE above) — tested BEFORE the class arm so a data item that IS a
    //   collection (including a bridged NSArray/NSDictionary) compares by content, not by box identity.
    if let aa = a as? [Any], let bb = b as? [Any] {
        if aa.count != bb.count { return false }
        for i in 0..<aa.count where !tooltipStrictEquals(aa[i], bb[i]) { return false }
        return true
    }
    if let ad = a as? [String: Any], let bd = b as? [String: Any] {
        if ad.count != bd.count { return false }
        for (k, v) in ad where !tooltipStrictEquals(v, bd[k]) { return false }
        return true
    }
    // object === object → reference identity when both really ARE class instances (upstream verbatim).
    if let ao = a, let bo = b, type(of: ao) is AnyClass, type(of: bo) is AnyClass {
        return (ao as AnyObject) === (bo as AnyObject)
    }
    return false
}

// upstream `calcTooltipPosition` (TooltipView.ts:1168): place the tooltip box around the hovered
//   graphic element's (already transformed) bounding `rect` for the STRING `position` keywords.
//   `position` is `TooltipOption['position']` upstream, narrowed to the builtin keyword string here —
//   any other string falls through the switch with x/y left at 0, exactly like upstream.
private func calcTooltipPosition(
    _ position: TooltipBuiltinPosition,
    _ rect: RectLike,
    _ contentSize: [Double],
    _ borderWidth: Double
) -> [Double] {
    let domWidth = contentSize.count > 0 ? contentSize[0] : 0
    let domHeight = contentSize.count > 1 ? contentSize[1] : 0
    let offset = ceil(2.0.squareRoot() * borderWidth) + 8   // upstream: Math.ceil(Math.SQRT2 * borderWidth) + 8
    var x: Double = 0
    var y: Double = 0
    let rectWidth = rect.width
    let rectHeight = rect.height
    switch position {
    case "inside":
        x = rect.x + rectWidth / 2 - domWidth / 2
        y = rect.y + rectHeight / 2 - domHeight / 2
    case "top":
        x = rect.x + rectWidth / 2 - domWidth / 2
        y = rect.y - domHeight - offset
    case "bottom":
        x = rect.x + rectWidth / 2 - domWidth / 2
        y = rect.y + rectHeight + offset
    case "left":
        x = rect.x - domWidth - offset
        y = rect.y + rectHeight / 2 - domHeight / 2
    case "right":
        x = rect.x + rectWidth + offset
        y = rect.y + rectHeight / 2 - domHeight / 2
    default:
        break   // upstream: no default case — x/y stay 0.
    }
    return [x, y]
}

// upstream's `isObject(positionExpr)` arm, adapted: a box-layout `position` is an `[String: Any]` option
//   bag in this port, but the `TooltipPositionCallback` return union also names the TYPED
//   `TooltipBoxLayoutOption` (util/types.swift). Normalize both into the bag `layout.getLayoutRect` reads.
//   Returns nil when `positionExpr` is neither (upstream: the `isObject` test failed).
// SEE ALSO `boxLayoutParamsToDict(_ p: BoxLayoutOptionMixin)` in component/visualMap/VisualMapView.swift —
//   the same typed-struct→layout-bag normalization for the OTHER box-layout struct. Do not add a third
//   copy; if a third consumer appears, hoist both next to `layout.getLayoutRect` (util/layout.swift).
private func boxLayoutOptionBag(_ positionExpr: Any?) -> [String: Any]? {
    if let bag = positionExpr as? [String: Any] {
        return bag
    }
    if let opt = positionExpr as? TooltipBoxLayoutOption {
        var bag: [String: Any] = [:]
        if let v = opt.top { bag["top"] = v }
        if let v = opt.left { bag["left"] = v }
        if let v = opt.right { bag["right"] = v }
        if let v = opt.bottom { bag["bottom"] = v }
        return bag
    }
    return nil
}

// Unwrap the ported `TopLevelFormatterParams` enum (upstream's `TooltipCallbackDataParams |
//   TooltipCallbackDataParams[]` union) into the `TooltipPositionCallbackParams` (= `Any`) arm a
//   `position` CALLBACK is spelled against: the SINGLE params bag on the item path, the per-series LIST
//   on the axis path — precisely the value upstream passes as the callback's 2nd argument.
private func positionCallbackParams(_ params: TopLevelFormatterParams) -> TooltipPositionCallbackParams {
    switch params {
    case .single(let one): return one
    case .multiple(let list): return list
    }
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
    // NOTE: no `marker` entry — `formatTpl` only ever reads the keys listed under `$vars` (util/
    //   format.swift), and `getDataParams` sets `$vars = [seriesName, name, value]` (+ `percent` for
    //   pie/funnel). Upstream's `callbackDataParamsToTplParam` does not carry it either: a `{marker}`
    //   token in a STRING formatter is left verbatim upstream too.
    return tplParam
}

// `format.formatTpl` takes upstream's `TplFormatterParam | TplFormatterParam[]` as a dynamic `Any`;
//   unwrap the params union into the matching shape (one bag for trigger:'item', the list of bags for
//   trigger:'axis' — upstream substitutes `{a0}`/`{b1}`/… per series from exactly that array).
private func tplParamFromFormatterParams(_ params: TopLevelFormatterParams) -> Any {
    switch params {
    case .single(let params):
        return tplParamFromDataParams(params)
    case .multiple(let params):
        return params.map(tplParamFromDataParams)
    }
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
