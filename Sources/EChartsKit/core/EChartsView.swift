// Ported (HOST-BINDING SUBSET) from echarts/src/core/echarts.ts `_initEvents` — keep in sync with upstream.
//
// ============================================================================
// WHAT THIS FILE IS
// ============================================================================
// Phase 33 makes interaction LIVE. `EChartsSlim` (core/EChartsSlim.swift) is the render driver — it
// builds a display list into its `storage`/`root` and owns `dispatchAction`. But upstream, the thing
// that turns a POINTER MOVE into an emphasis highlight is `ECharts._initEvents` (echarts.ts:1290),
// which binds `zr.on('mouseover' / 'mouseout' / 'click' / …)` against the LIVE zrender `Handler` and,
// for each element event, walks up to the nearest highDown dispatcher and enters/leaves emphasis.
//
// `EChartsSlim` is deliberately zrender-less (it owns a bare `Storage`, not a `ZRender`, so it can be
// unit-tested headlessly). This file is the missing seam: a HOST-BINDING that couples an `EChartsSlim`
// to a LIVE ZRenderKit `ZRender` whose `Handler` hit-tests + dispatches over the echarts display list,
// and reproduces the `_initEvents` binding so hovering a bar (etc.) enters emphasis end-to-end.
//
// It is NOT a UIView. It is platform-agnostic (EChartsKit depends only on ZRenderKit, never
// NativePainter), so the on-screen painter is INJECTED by the caller. For headless use (tests) a
// minimal no-op `HeadlessPainter` is supplied by default; a real host passes a `CALayerPainter`.
//
// ============================================================================
// FAITHFULNESS / DEVIATIONS vs upstream `_initEvents`
// ============================================================================
//   - Upstream iterates `MOUSE_EVENT_NAMES` (['click','dblclick','mouseover','mouseout','mousemove',
//     'mousedown','mouseup','globalout','contextmenu']) and binds ONE generic handler that assembles
//     `ECElementEvent` params (getDataParams) and `this.trigger(eveName, params)` on the ECharts
//     event bus. The Phase-33 brief scopes this to the EMPHASIS binding (mouseover/mouseout) plus a
//     MINIMAL click→dispatchAction; the full event-param assembly + the public ECharts event bus +
//     the tooltip/axisPointer `mousemove`→axisTrigger path are DEFERRED (see PORT-TODO below).
//   - The mouseover/mouseout → `enterEmphasisWhenMouseOver`/`leaveEmphasisWhenMouseOut` binding is done
//     HERE directly against the zr handler (in the slim path the views do not self-register their zr
//     listeners — no live zr at render time — so `EChartsView` owns the binding; documented deviation).
//     PORT-TODO (DEFERRED): upstream binds `handleGlobalMouseOverForHighDown`/`…OutForHighDown`
//     (echarts.ts:2331/2338), which ALSO runs the FOCUS fan-out (`blurSeries`/`blurComponent` to dim
//     the non-focused siblings when `emphasis.focus` is set) + `allLeaveBlur` on mouseout. This phase
//     wires only the enter/leave-emphasis of the hovered element; the focus-blur fan-out is deferred
//     (the `blurSeries` engine is ported — Phase 30 — but the global mouse-over focus handler is not).

import Foundation
import ZRenderKit

// ============================================================================
// HeadlessPainter — a minimal no-op `PainterBase` for headless hosts (tests).
// EChartsKit cannot depend on NativePainter's `CALayerPainter`, so this satisfies the `ZRender`/
// `Handler` painter requirement (used only for boundary/size reads; it draws nothing). A real host
// passes its own `PainterBase` (e.g. `CALayerPainter`) to `EChartsView.init(painter:)`.
// ============================================================================
public final class HeadlessPainter: PainterBase {
    private var _width: Double
    private var _height: Double
    public init(width: Double, height: Double) {
        self._width = width
        self._height = height
    }
    public func refresh(_ displayList: [Displayable]) {}      // draws nothing (headless)
    public func resize(_ width: Double?, _ height: Double?, _ dpr: Double?) {
        if let w = width { self._width = w }
        if let h = height { self._height = h }
    }
    public func clear() {}
    public func getWidth() -> Double { return _width }
    public func getHeight() -> Double { return _height }
    public func dispose() {}
    // type / ssrOnly / getViewportRoot / configLayer use the PainterBase protocol defaults.
}

// ============================================================================
// EChartsView — the echarts ↔ live ZRender host binding.
// ============================================================================
public final class EChartsView {

    /// The render driver (owns the model → coord → view pipeline + `dispatchAction`).
    public let ec: EChartsSlim

    /// The LIVE zrender instance whose `Handler` hit-tests + dispatches over the echarts display list.
    /// Exposed so a test can drive input directly (`view.zr.handler.mousemove(...)`) — see also
    /// `_injectPointerForTest`.
    public let zr: ZRender

    /// Whether `ec.getRoot()` has been wired into the zr storage yet (add-once; see `_syncRoot`).
    private var _rootAdded = false

    // ------------------------------------------------------------------------
    // tooltipView — Phase 34. `EChartsView` OWNS the (slim, trigger:'item') `TooltipView`; upstream a
    //   `ComponentView` reaches the live zr via `api.getZr()`, but `EChartsSlim` has no live zr, so the
    //   view is constructed over THIS view's live `zr` and its `TooltipRichContent` ZRText floats above
    //   `ec.getRoot()` (added to `zr` directly, NOT the ec render group — so a re-render does not wipe it
    //   and `findHover` still hit-tests the chart bars beneath). Built lazily on first hover (the global
    //   `TooltipModel` may not exist until `setOption` has run). Public so a headless test can assert the
    //   tooltip appeared (`view.tooltipView`).
    // ------------------------------------------------------------------------
    public private(set) var tooltipView: TooltipView?

    // ------------------------------------------------------------------------
    // Phase 36 — the visual axisPointer CROSSHAIR. WIRING APPROACH (documented deviation):
    //   Upstream, `AxisView._doUpdateAxisPointerClass` instantiates a per-axis `CartesianAxisPointer`
    //   (registered via `AxisView.registerAxisPointerClass`) and the `updateAxisPointer` action routes
    //   each axis' render. In THIS slim port there is no live per-axis `AxisView` hosting a zr at render
    //   time (EChartsSlim is zr-less), so — exactly like the Phase-34/35 tooltip — `EChartsView` OWNS the
    //   pointer managers and drives them DIRECTLY on hover, PARALLEL to the axis tooltip.
    //
    //   `axisTrigger` (run on every hover mousemove in `_bindAxisPointerListeners`) already computes and
    //   writes each axisPointer model's `status`/`value`/`seriesDataIndices` (via `updateModelActually`).
    //   So after `axisTrigger` returns, `_updateAxisPointers` walks the collected `CollectionResult`,
    //   and for each CARTESIAN axis renders its `CartesianAxisPointer` (reading value/status straight off
    //   the just-updated model — the exact path upstream's `BaseAxisPointer.render` reads). Each pointer's
    //   crosshair `Group` is hosted on the LIVE `zr` via the `hostAdd`/`hostRemove` seam (floats above
    //   `ec.getRoot()`, `silent=true` so it never blocks findHover — same rationale as the tooltip). A
    //   `status:"hide"` (off-grid / leave) makes `render` call `group.hide()`.
    //
    //   Pointer managers are keyed by axis key (`makeKey(axis.model)`) so their `group`/`_lastGraphicKey`
    //   persist across hovers. PORT-TODO: polar/single crosshairs (non-Axis2D) are deferred; move
    //   animation / drag handle / lineDash(dashed→solid) are deferred inside BaseAxisPointer/viewHelper.
    //   PORT-TODO: `axisPointer:{show:true}` WITHOUT a tooltip trigger:"axis" is not yet wired (the hover
    //   path is gated on `_isAxisTrigger`; enabling axisPointer-only needs the mousemove→hideTip guard
    //   reworked so it does not fight the trigger:"item" tooltip — see `_bindAxisPointerListeners`).
    // ------------------------------------------------------------------------
    private var _axisPointers: [String: CartesianAxisPointer] = [:]

    // ------------------------------------------------------------------------
    // Phase 39 — inside-dataZoom PAN (drag-to-roam). Mirrors `RoamController._dragging` + `_x`/`_y`.
    //   `nil` when no drag is in progress; otherwise the last pointer position (the pan anchor advanced
    //   on every mousemove, exactly like `RoamController._mousemoveHandler` writes `this._x = x`). A drag
    //   begins on a `mousedown` over a coord system that hosts an inside dataZoom with `moveOnMouseMove`,
    //   and ends on `mouseup`/`globalout`. While non-nil, hover-emphasis + tooltip + axisTrigger are
    //   SUPPRESSED (upstream `preventDefaultMouseMove` / roam consuming the move — see the mouseover/
    //   mouseout/globalListener drag gates).
    // ------------------------------------------------------------------------
    private var _insideZoomDrag: (lastX: Double, lastY: Double)?

    /// Lazily build the tooltip view over the live zr, then (re)bind it to the current ec model.
    private func _ensureTooltipView() -> TooltipView? {
        guard let ecModel = ec.getModel() else { return nil }
        let view: TooltipView
        if let existing = tooltipView {
            view = existing
        }
        else {
            view = TooltipView(zr: zr, ecModel: ecModel)
            tooltipView = view
        }
        // Rebind (idempotent) so a rebuilt model / late `setOption` refreshes the merge base.
        view.setModel(ecModel)
        return view
    }

    // ------------------------------------------------------------------------
    // init. Upstream `new ECharts(dom, theme, opts)` builds `this._zr = zrender.init(dom, {...})` then
    //   `this._initEvents()`. Here the `ZRender` is built via the ported `zrender.init(...)` helper with
    //   an INJECTED painter (headless by default), and `ec.getRoot()` is synced into the zr so the zr
    //   `storage` hit-tests + paints the echarts elements.
    // ------------------------------------------------------------------------
    public init(width: Double, height: Double, painter: PainterBase? = nil, proxy: HandlerProxyInterface? = nil) {
        self.ec = EChartsSlim(width: width, height: height)
        let painter = painter ?? HeadlessPainter(width: width, height: height)
        // Free `zrender.init(...)` helper (ZRender.swift). `proxy: nil` → Handler uses `EmptyProxy`,
        //   so synthetic input is driven directly through `zr.handler` (no native input bridge needed).
        self.zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        _initEvents()
    }

    /// Convenience: bind an already-built `EChartsSlim`. (The slim driver's size is fixed at its own
    /// init; `width`/`height` here only size the injected headless painter / zr surface.)
    public init(ec: EChartsSlim, width: Double, height: Double, painter: PainterBase? = nil, proxy: HandlerProxyInterface? = nil) {
        self.ec = ec
        let painter = painter ?? HeadlessPainter(width: width, height: height)
        self.zr = ZRenderKit.`init`(nil, nil, painter: painter, proxy: proxy)
        _initEvents()
    }

    // ------------------------------------------------------------------------
    // setOption. Upstream forwards to `ECharts.setOption` (which re-runs `update()` and repaints `zr`).
    //   Here: forward to the slim driver, then sync `ec.getRoot()` into the zr storage + `zr.refresh()`.
    // ------------------------------------------------------------------------
    public func setOption(_ option: [String: Any]) {
        ec.setOption(option)
        _syncRoot()
    }

    /// Add the ec root into the zr storage ONCE (subsequent `setOption`s rebuild the root's children
    /// in place — `root` is a stable `Group` identity — so a `refresh` re-flattens them). `Storage.addRoot`
    /// dedups on `__zr`, so a repeat `zr.add(root)` is a safe no-op; we still guard to avoid the churn.
    private func _syncRoot() {
        if !_rootAdded {
            zr.add(ec.getRoot())     // upstream analog: elements added to `zr`
            _rootAdded = true
        }
        zr.refresh()
    }

    // ------------------------------------------------------------------------
    // _initEvents — upstream `ECharts.prototype._initEvents` (echarts.ts:1290). Binds the zr element-event
    //   surface. Phase-33 scope: mouseover/mouseout → emphasis; click → minimal dispatchAction.
    // ------------------------------------------------------------------------
    private func _initEvents() {
        // mouseover: enter emphasis on the nearest highDown dispatcher (upstream: the ChartView's
        //   `enterEmphasisWhenMouseOver` bound via the emphasis low-level handler).
        // NOTE: ctx is `nil` (NOT `self`). `Handler`'s `Eventful` stores the ctx STRONGLY
        //   (EventHandler.ctx is non-weak), and zr→handler→eventful is strongly owned by this view — so
        //   passing `self` there would form a retain cycle (deinit/dispose would never run, leaking the
        //   whole chart graph). The closures already `[weak self]`; `Handler.on` defaults ctx to the handler.
        _ = zr.on("mouseover", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            // Phase 39: while an inside-dataZoom DRAG (roam/pan) is in progress, suppress hover-emphasis +
            //   tooltip (upstream `preventDefaultMouseMove` / `__ecRoamConsumed` consumes the move so the
            //   hover path does not fire during a drag).
            if self._insideZoomDrag != nil { return nil }
            // upstream binds `findEventDispatcher(el, isHighDownDispatcher)` WITHOUT returnFirstMatch →
            //   the OUTERMOST matching ancestor is emphasized (matters for nested dispatchers).
            if let dispatcher = self.findDispatcher(e.target, returnFirstMatch: false) {
                states.enterEmphasisWhenMouseOver(dispatcher, e)
                self.zr.refresh()
            }
            // Phase 34: ALSO drive the tooltip. Independent of the emphasis dispatcher walk (upstream the
            //   tooltip trigger reads the hovered element's ECData directly), so a hover fires BOTH the
            //   emphasis highlight AND the tooltip-on-hover.
            self._showTooltipForHover(e)
            return nil
        }, nil)

        // mouseout: leave emphasis on the nearest highDown dispatcher.
        _ = zr.on("mouseout", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            // Phase 39: suppress the leave-emphasis/tooltip-hide while dragging (see the mouseover gate).
            if self._insideZoomDrag != nil { return nil }
            if let dispatcher = self.findDispatcher(e.target, returnFirstMatch: false) {
                states.leaveEmphasisWhenMouseOut(dispatcher, e)
                self.zr.refresh()
            }
            // Phase 34: hide the tooltip when the pointer leaves the element (upstream `_hide`).
            self.tooltipView?.hide()
            self.zr.refresh()
            return nil
        }, nil)

        // click: minimal payload assembly + dispatchAction (see `_handleClick`). Upstream builds the
        //   full `ECElementEvent` + triggers the public event bus; the Phase-33 scope is the highlight
        //   dispatch for the clicked series/dataIndex (PORT-TODO: full param assembly + event bus).
        _ = zr.on("click", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            self._handleClick(e)
            return nil
        }, nil)   // ctx nil (NOT self) — see the mouseover note: avoids the zr↔handler↔eventful↔self cycle.

        // Phase 35: the `mousemove` → axisPointer/tooltip `axisTrigger` → showTip path. Binds the ported
        //   globalListener zr listeners (click/mousemove/mousewheel/globalout) whose fan-out drives
        //   `axisTrigger` for the tooltip trigger:"axis" combined tooltip (see `_bindAxisPointerListeners`).
        _bindAxisPointerListeners()

        // Phase 38: the mouse-wheel → inside-dataZoom interactive zoom (see `_bindInsideZoom`).
        _bindInsideZoom()

        // Phase 39: the drag (mousedown→mousemove→mouseup) → inside-dataZoom PAN/roam (see `_bindInsidePan`).
        _bindInsidePan()

        // PORT-TODO (DEFERRED): the generic `MOUSE_EVENT_NAMES` fan-out onto the public ECharts event bus
        //   (`this.trigger(eveName, ECElementEvent)`) — needs `getDataParams` param assembly + a message bus.
        // PORT-TODO (DEFERRED): `globalout` (no `e.target`) → `allLeaveBlur` / leave-emphasis reset.
    }

    // ------------------------------------------------------------------------
    // _bindAxisPointerListeners — Phase 35. Wire the tooltip trigger:"axis" chain end-to-end through the
    //   ported `globalListener` (component/axisPointer/globalListener.swift), exactly as that file
    //   documents. `globalListener.register` binds ONE set of zr listeners (click/mousemove/mousewheel/
    //   globalout); its fan-out calls our `handler(currTrigger, event, dispatchAction)`, which builds the
    //   axisTrigger payload (currTrigger + pointer x/y) and runs the ported `axisTrigger(payload, ecModel,
    //   api)`. axisTrigger computes `dataByCoordSys` and dispatches showTip/hideTip through the FORWARDED
    //   `dispatchAction` (so they flow through globalListener's pend/merge "final stage"); the merged action
    //   is then handed to our `realDispatch` (`_realDispatchAxisPointer`), which shows/hides THIS view's
    //   owned TooltipView via `_showAxisTooltip`/`hide` (upstream `api.dispatchAction` → the tooltip view).
    //   ctx is `nil` + `[weak self]` (Phase-33 retain-cycle rule: zr→handler→eventful is owned by self).
    // ------------------------------------------------------------------------
    private func _bindAxisPointerListeners() {
        globalListener.register("axisPointer", zr, realDispatch: { [weak self] payload in
            self?._realDispatchAxisPointer(payload)
        }, handler: { [weak self] currTrigger, event, dispatchAction in
            guard let self = self, let ecModel = self.ec.getModel() else { return }
            // Phase 39: suppress the axisPointer/tooltip axisTrigger while an inside-dataZoom drag is in
            //   progress (roam consumes the move — see `_insideZoomDrag`).
            guard self._insideZoomDrag == nil else { return }
            // Only drive the axis path when a tooltip with trigger:"axis" is configured; otherwise every
            //   mousemove would dispatch hideTip and fight the trigger:"item" hover tooltip (Phase 34).
            guard self._isAxisTrigger(ecModel) else { return }
            var payload = Payload(type: "axisTrigger")
            payload.other["currTrigger"] = currTrigger
            if let e = event {
                payload.other["x"] = e.offsetX
                payload.other["y"] = e.offsetY
            }
            // Route showTip/hideTip THROUGH the merge stage (globalListener pendings), not directly.
            payload.other["dispatchAction"] = dispatchAction
            axisTrigger(payload, ecModel, self.ec.api)
            // Phase 36: axisTrigger has just written each axisPointer model's status/value; render the
            //   visual crosshair(s) from those models, PARALLEL to the axis tooltip.
            self._updateAxisPointers(ecModel)
        })
    }

    // ------------------------------------------------------------------------
    // _bindInsideZoom — Phase 38. Wire the mouse WHEEL → inside-dataZoom interactive zoom.
    //
    //   WIRING APPROACH (documented deviation): upstream, `InsideZoomView.render` calls
    //   `roams.setViewInfoToCoordSysRecord`, and `roams.installDataZoomRoamProcessor` builds a
    //   `RoamController` PER coordinate system (`RoamController(api.getZr())`) that binds
    //   `zr.on('mousewheel')` and, on a wheel, computes each inside-dataZoom's new range via
    //   `getRangeHandlers.zoom` (InsideZoomView.ts) and dispatches ONE throttled `{type:'dataZoom', batch}`.
    //   In THIS slim port there is no live per-component `InsideZoomView` hosting a zr at render time
    //   (EChartsSlim is zr-less), so — exactly like the Phase-34/35 tooltip & Phase-36 axisPointer —
    //   `EChartsView` OWNS the wheel binding and reproduces the zoom MATH directly against the live `zr`.
    //
    //   FAITHFULNESS: the scale factor (`RoamController._mousewheelHandler`) and the range recompute
    //   (`InsideZoomView.getRangeHandlers.zoom` + `roams.getDirectionInfo.grid`) are ported exactly; the
    //   emitted action mirrors `roams.dispatchAction` (`{type:'dataZoom', batch:[{dataZoomId,start,end}]}`).
    //
    //   PORT-TODO (DEFERRED, mirroring upstream `RoamController`/`roams`):
    //     - pan/drag (`moveOnMouseMove` → getRangeHandlers.pan) and wheel-scroll-move (`moveOnMouseWheel`
    //       → getRangeHandlers.scrollMove); pinch/touch zoom (`_pinchHandler`).
    //     - the full `RoamController` state machine + `throttleUtil.createOrUpdate` throttle + the
    //       `{easing:'cubicOut', duration:100}` animated dataZoom transition (the slim driver renders the
    //       new window synchronously, so no animated tween yet).
    //     - polar / singleAxis coord systems (`getDirectionInfo.polar` / `.singleAxis`): only the grid
    //       (cartesian) direction info is ported here.
    //     - the SliderZoomView on-screen slider widget.
    //   ctx is `nil` + `[weak self]` (Phase-33 retain-cycle rule: zr→handler→eventful is owned by self).
    // ------------------------------------------------------------------------
    private func _bindInsideZoom() {
        _ = zr.on("mousewheel", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            self._handleInsideZoomWheel(e)
            return nil
        }, nil)
    }

    /// The wheel handler proper. Mirrors `RoamController._mousewheelHandler` (the zoom branch) + the
    /// `roams.createCoordSysRecord` fan-out that builds the `dataZoom` action batch.
    private func _handleInsideZoomWheel(_ e: ElementEvent) {
        guard let ecModel = ec.getModel() else { return }

        // upstream `RoamController._mousewheelHandler`: `e.wheelDelta` is the zr-normalized wheel delta
        //   (Handler.makeEventPacket sets `packet.wheelDelta = event.zrDelta`). `wheelDelta === 0` → no-op.
        let wheelDelta = e.wheelDelta ?? 0
        if wheelDelta == 0 { return }
        let originX = e.offsetX
        let originY = e.offsetY

        // factor / scale exactly as `RoamController._mousewheelHandler` (zoom branch): bigger |delta|
        //   (mouse wheel vs. touchpad) → stronger zoom. wheelDelta > 0 → zoom IN (scale > 1).
        let absWheelDelta = abs(wheelDelta)
        let factor: Double = absWheelDelta > 3 ? 1.4 : absWheelDelta > 1 ? 1.2 : 1.1
        let scale = wheelDelta > 0 ? factor : 1 / factor

        // Collect one batch item per affected inside-dataZoom (upstream `roams`' per-coordSys batch),
        //   then dispatch ONCE after the walk so the mid-iteration `update()` cannot invalidate the models
        //   we are still iterating.
        var batch: [PayloadItem] = []

        ecModel.eachComponent("dataZoom") { modelItem, _ in
            guard let dzModel = modelItem as? InsideZoomModel else { return }
            // Behavior gate — upstream `event.isAvailableBehavior(dzInfo.model.option)` (zoomOnMouseWheel)
            //   + `!dzInfo.model.get('disabled', true)`. Treat `zoomOnMouseWheel === false` as disabled;
            //   any other value (true / 'ctrl' / 'shift' / …) enables (modifier-key gating is DEFERRED).
            if (dzModel.get("disabled", true) as? Bool) == true { return }
            if (dzModel.get("zoomOnMouseWheel", true) as? Bool) == false { return }
            if dzModel.noTarget() { return }

            guard let newRange = self._computeInsideZoomRange(
                dzModel, originX: originX, originY: originY, scale: scale
            ) else { return }
            var item = PayloadItem()
            item.other["dataZoomId"] = dzModel.id
            item.other["start"] = newRange[0]
            item.other["end"] = newRange[1]
            batch.append(item)
        }

        if !batch.isEmpty {
            // upstream `roams.dispatchAction`: `{type:'dataZoom', animation:{easing:'cubicOut',
            //   duration:100}, batch}`. The slim driver renders the new window synchronously (no animated
            //   dataZoom tween yet — PORT-TODO), so the animation part is omitted; the batch is faithful.
            var payload = Payload(type: "dataZoom")
            payload.batch = batch
            ec.dispatchAction(payload)
            // A re-render rebuilt `ec.getRoot()`'s children (stable Group identity); re-flatten the zr
            //   display list + repaint so the live zr reflects the new (shrunk/grown) data window.
            _ = zr.storage.getDisplayList(true)
            zr.refresh()
        }
    }

    /// Compute the new [start, end] percent window for ONE inside-dataZoom, or `nil` if the cursor is
    /// outside its coord system or the window would not change. Faithful port of
    /// `InsideZoomView.getRangeHandlers.zoom` + `roams.getDirectionInfo.grid` (cartesian only).
    ///
    /// DEVIATION: upstream drives the recompute off `coordSysInfo.axisModels[0]` (from
    /// `collectReferCoordSysModelInfo`, which resolves the coord-sys via the axis model's
    /// `getReferringComponents('grid')`). In this slim port the stand-in axis models don't carry a
    /// model-level grid referring link, so `collectReferCoordSysModelInfo` yields no coord systems — we
    /// instead resolve the target axis via the dataZoom's REPRESENTATIVE axis proxy (the same path
    /// `dataZoomProcessor` uses). For a single-axis inside dataZoom (the common cartesian case) this IS
    /// `axisModels[0]`. PORT-TODO: multi-axis-per-grid grouping + polar/single coord systems.
    private func _computeInsideZoomRange(
        _ dzModel: InsideZoomModel,
        originX: Double,
        originY: Double,
        scale: Double
    ) -> [Double]? {
        guard let g = _resolveInsideZoomGeom(dzModel) else { return nil }

        // containPoint gate — upstream `roams.containsPoint` = `coordSysModel.coordinateSystem.containPoint`.
        //   Narrowed to the CONCRETE Cartesian2D that hosts this axis (see the geom resolver).
        guard g.cart.containPoint([originX, originY]) else { return nil }

        // `this.range` — the current [start, end] percents (upstream saves it in `render`; here read live).
        guard let lastRange = dzModel.getPercentRange(), lastRange.count == 2 else { return nil }
        var range = lastRange

        // getDirectionInfo['grid'] (roams.ts) with oldPoint = [0, 0], newPoint = [originX, originY].
        let pixel = g.isX ? originX : originY     // newPoint[dim] - oldPoint[dim] (oldPoint = 0)

        // The cursor as a PERCENT anchor within the current window (upstream `percentPoint`).
        let percentPoint = (
            g.signal > 0
                ? (g.pixelStart + g.pixelLength - pixel)
                : (pixel - g.pixelStart)
            ) / g.pixelLength * (range[1] - range[0]) + range[0]

        // Zoom around the anchor: `scale = Math.max(1 / e.scale, 0)`.
        let zoomScale = Swift.max(1 / scale, 0)
        range[0] = (range[0] - percentPoint) * zoomScale + percentPoint
        range[1] = (range[1] - percentPoint) * zoomScale + percentPoint

        // Restrict range (min/maxSpan) — upstream `findRepresentativeAxisProxy().getMinMaxSpan()`.
        let minMaxSpan = g.proxy.getMinMaxSpan()
        sliderMove(0, &range, [0, 100], .at(0), minMaxSpan.minSpan, minMaxSpan.maxSpan)

        // Only emit when the window actually changed (upstream returns `undefined` otherwise).
        if lastRange[0] != range[0] || lastRange[1] != range[1] {
            return range
        }
        return nil
    }

    // ------------------------------------------------------------------------
    // _resolveInsideZoomGeom — the SHARED cartesian direction context for an inside dataZoom, factored out
    //   of the wheel-zoom + pan paths. Faithful to `roams.getDirectionInfo.grid` (InsideZoomView.ts): the
    //   grid rect + the axis dim/inverse fix `pixelLength`/`pixelStart`/`signal`; NO cursor is baked in, so
    //   both the zoom (anchor point) and pan (drag delta) callers supply their own `pixel`. Returns `nil`
    //   for a non-cartesian (polar/single) axis — PORT-TODO, deferred.
    //
    //   DEVIATION (same as the wheel path): upstream drives the recompute off `coordSysInfo.axisModels[0]`
    //   (from `collectReferCoordSysModelInfo`); in this slim port the stand-in axis models don't carry the
    //   model-level grid referring link, so we resolve the target axis via the dataZoom's REPRESENTATIVE
    //   axis proxy (the same path `dataZoomProcessor` uses). PORT-TODO: multi-axis-per-grid grouping.
    // ------------------------------------------------------------------------
    private struct InsideZoomGeom {
        let isX: Bool
        let pixelLength: Double
        let pixelStart: Double
        let signal: Double
        let cart: Cartesian2D
        let proxy: AxisProxy
    }

    private func _resolveInsideZoomGeom(_ dzModel: InsideZoomModel) -> InsideZoomGeom? {
        guard let proxy = dzModel.findRepresentativeAxisProxy() else { return nil }
        let axisModel = proxy.getAxisModel()
        // Narrow to the CONCRETE Axis2D (protocol-witness trap): `.dim`/`.inverse`/`.grid`/`.index`.
        guard let axis = axisModel.axis as? Axis2D else {
            // PORT-TODO: polar (RadiusAxis/AngleAxis) & singleAxis direction info deferred.
            return nil
        }
        let grid = axis.grid!
        // Narrow to the CONCRETE Cartesian2D that hosts this axis (containPoint / coord system).
        let cartesian = (axis.dim == "x"
            ? grid.getCartesian(axis.index, nil)
            : grid.getCartesian(nil, axis.index)) ?? grid.getCartesians().first
        guard let cart = cartesian else { return nil }

        let rect = grid.getRect()
        let isX = axis.dim == "x"
        let pixelLength = isX ? rect.width : rect.height
        let pixelStart = isX ? rect.x : rect.y
        let signal: Double = isX ? (axis.inverse ? 1 : -1) : (axis.inverse ? -1 : 1)
        return InsideZoomGeom(
            isX: isX, pixelLength: pixelLength, pixelStart: pixelStart,
            signal: signal, cart: cart, proxy: proxy
        )
    }

    // ------------------------------------------------------------------------
    // _bindInsidePan — Phase 39. Wire the drag (mousedown → mousemove → mouseup) → inside-dataZoom PAN.
    //   Mirrors `RoamController`'s `_mousedownHandler`/`_mousemoveHandler`/`_mouseupHandler` state machine
    //   (the `pan` branch), reusing the same Phase-32 `{type:'dataZoom', batch}` action as the wheel-zoom.
    //   Binding APPROACH is identical to Phase-38 (`EChartsView` owns the zr binding; no live per-component
    //   `InsideZoomView`). ctx `nil` + `[weak self]` (Phase-33 retain-cycle rule).
    //
    //   PORT-TODO (DEFERRED): cursor style (`cursorGrab`/`cursorGrabbing`), the interactionMutex globalPan,
    //     `draggable` element opt-out, middle/right-button guard, throttle + the animated dataZoom tween,
    //     modifier-key gating of `moveOnMouseMove: 'ctrl'|'shift'|'alt'`, polar/single roam.
    // ------------------------------------------------------------------------
    private func _bindInsidePan() {
        _ = zr.on("mousedown", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            self._handleInsidePanDown(e)
            return nil
        }, nil)
        _ = zr.on("mousemove", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            self._handleInsidePanMove(e)
            return nil
        }, nil)
        _ = zr.on("mouseup", { [weak self] _, _ in
            self?._insideZoomDrag = nil            // upstream `_mouseupHandler`: `this._dragging = false`.
            return nil
        }, nil)
        _ = zr.on("globalout", { [weak self] _, _ in
            self?._insideZoomDrag = nil            // leaving the canvas ends the drag.
            return nil
        }, nil)
    }

    /// mousedown — begin a drag iff the cursor is over a coord system hosting an inside dataZoom that
    /// permits `moveOnMouseMove` (upstream `_mousedownHandler` → `_checkPointer` containsPoint, then
    /// `_dragging = true` with `_x`/`_y` = the down point).
    private func _handleInsidePanDown(_ e: ElementEvent) {
        guard let ecModel = ec.getModel() else { return }
        let x = e.offsetX
        let y = e.offsetY
        var eligible = false
        ecModel.eachComponent("dataZoom") { modelItem, _ in
            guard let dzModel = modelItem as? InsideZoomModel else { return }
            // Behavior gate — upstream `event.isAvailableBehavior('moveOnMouseMove', ...)` +
            //   `!dzInfo.model.get('disabled', true)`. `moveOnMouseMove === false` disables pan; any other
            //   value (true / 'ctrl' / 'shift' / …) enables (modifier-key gating DEFERRED). Note zoomLock
            //   maps to controlType 'move' upstream, i.e. it disables ZOOM not PAN — so it is NOT checked.
            if (dzModel.get("disabled", true) as? Bool) == true { return }
            if (dzModel.get("moveOnMouseMove", true) as? Bool) == false { return }
            if dzModel.noTarget() { return }
            guard let g = self._resolveInsideZoomGeom(dzModel) else { return }
            if g.cart.containPoint([x, y]) { eligible = true }
        }
        if eligible {
            _insideZoomDrag = (lastX: x, lastY: y)
        }
    }

    /// mousemove WHILE dragging — shift every eligible inside dataZoom's window by the drag delta, dispatch
    /// ONE `dataZoom` batch, and advance the drag anchor (upstream `_mousemoveHandler` writes `_x = x`).
    /// A no-op when not dragging, so a plain hover mousemove behaves exactly as before Phase 39.
    private func _handleInsidePanMove(_ e: ElementEvent) {
        guard let drag = _insideZoomDrag, let ecModel = ec.getModel() else { return }
        let newX = e.offsetX
        let newY = e.offsetY
        let oldX = drag.lastX
        let oldY = drag.lastY

        var batch: [PayloadItem] = []
        ecModel.eachComponent("dataZoom") { modelItem, _ in
            guard let dzModel = modelItem as? InsideZoomModel else { return }
            if (dzModel.get("disabled", true) as? Bool) == true { return }
            if (dzModel.get("moveOnMouseMove", true) as? Bool) == false { return }
            if dzModel.noTarget() { return }
            guard let newRange = self._computeInsidePanRange(
                dzModel, oldX: oldX, oldY: oldY, newX: newX, newY: newY
            ) else { return }
            var item = PayloadItem()
            item.other["dataZoomId"] = dzModel.id
            item.other["start"] = newRange[0]
            item.other["end"] = newRange[1]
            batch.append(item)
        }

        // Advance the anchor every move (upstream sets `_x = x; _y = y` before triggering 'pan'), even when
        //   the window was clamped and produced no batch — so the NEXT delta is measured from here.
        _insideZoomDrag = (lastX: newX, lastY: newY)

        if !batch.isEmpty {
            var payload = Payload(type: "dataZoom")
            payload.batch = batch
            ec.dispatchAction(payload)
            _ = zr.storage.getDisplayList(true)
            zr.refresh()
        }
    }

    /// Compute the pan-shifted [start, end] window for ONE inside-dataZoom, or `nil` if unchanged. Faithful
    /// port of `InsideZoomView.getRangeHandlers.pan` (`makeMover`) + `roams.getDirectionInfo.grid`: the
    /// percent delta = `signal * (range[1]-range[0]) * pixel / pixelLength` (pixel = the drag delta along
    /// the axis dim), then `sliderMove(percentDelta, range, [0,100], 'all')` moves the WHOLE window (both
    /// handles), clamped into [0,100] with the span preserved. NO containPoint gate here — upstream's pan
    /// handler does not re-check contains during a drag (the mouse may leave the target while moving).
    private func _computeInsidePanRange(
        _ dzModel: InsideZoomModel,
        oldX: Double,
        oldY: Double,
        newX: Double,
        newY: Double
    ) -> [Double]? {
        guard let g = _resolveInsideZoomGeom(dzModel) else { return nil }
        guard let lastRange = dzModel.getPercentRange(), lastRange.count == 2 else { return nil }
        var range = lastRange

        // getDirectionInfo['grid'] with oldPoint = [oldX, oldY], newPoint = [newX, newY].
        let pixel = g.isX ? (newX - oldX) : (newY - oldY)

        // makeMover's percentDelta, then sliderMove('all') = move both handles (whole window).
        let percentDelta = g.signal * (range[1] - range[0]) * pixel / g.pixelLength
        sliderMove(percentDelta, &range, [0, 100], .all)

        if lastRange[0] != range[0] || lastRange[1] != range[1] {
            return range
        }
        return nil
    }

    // ------------------------------------------------------------------------
    // _updateAxisPointers — Phase 36. After `axisTrigger` writes the per-axis axisPointer model status/
    //   value, render the visual crosshair for each CARTESIAN axis (upstream: `AxisView` +
    //   `updateAxisPointer` → `CartesianAxisPointer.render`; here driven directly — see the `_axisPointers`
    //   note). `BaseAxisPointer.render` itself reads `value`/`status` off the model and self-hides on
    //   `status:"hide"`, so a single unconditional `render` per axis handles both show and off-grid hide.
    // ------------------------------------------------------------------------
    private func _updateAxisPointers(_ ecModel: GlobalModel) {
        guard let apModel = ecModel.getComponent("axisPointer") as? AxisPointerModel,
              let result = apModel.coordSysAxesInfo as? CollectionResult else { return }
        let api = ec.api
        for (key, axisInfo) in result.axesInfo {
            // Only cartesian (Axis2D) axes get a Line/shadow crosshair (polar/single deferred).
            guard axisInfo.axis is Axis2D else { continue }
            let axisModelOpt: AxisBaseModel? = axisInfo.axis.model
            guard let axisModel = axisModelOpt else { continue }

            let pointer: CartesianAxisPointer
            if let existing = _axisPointers[key] {
                pointer = existing
            }
            else {
                let p = CartesianAxisPointer()
                // HOST SEAM (see BaseAxisPointer): host the crosshair group on the LIVE zr — floats above
                //   ec.getRoot() so a re-render does not wipe it (silent=true → never blocks findHover).
                //   [weak self] + no self capture in ctx (Phase-33 retain-cycle rule).
                p.hostAdd = { [weak self] g in self?.zr.add(g) }
                p.hostRemove = { [weak self] g in self?.zr.remove(g) }
                _axisPointers[key] = p
                pointer = p
            }
            pointer.render(axisModel, axisInfo.axisPointerModel, api, false)
        }
        zr.refresh()
    }

    /// Whether the current ec model asks for the trigger:"axis" combined tooltip (upstream: the tooltip
    /// `trigger` option). axisPointer-only (crosshair without tooltip) is DEFERRED (Phase 36 view).
    private func _isAxisTrigger(_ ecModel: GlobalModel) -> Bool {
        if let tooltip = ecModel.getComponent("tooltip"),
           (tooltip.get("trigger") as? String) == "axis" {
            return true
        }
        return false
    }

    /// The `realDispatch` seam handed to `globalListener.register`: the merged showTip/hideTip (and any
    /// other action) that survived the pend/merge stage. showTip carrying `dataByCoordSys` shows the axis
    /// tooltip in THIS view's TooltipView; hideTip hides it; anything else forwards to the driver.
    private func _realDispatchAxisPointer(_ payload: Payload) {
        switch payload.type {
        case "showTip":
            // Only the trigger:"axis" showTip carries `dataByCoordSys` (built by axisTrigger). A bare
            //   data-driven showTip (item path) is not routed through this seam.
            guard let list = payload.other["dataByCoordSys"] as? [DataByCoordSys] else { return }
            let x = _viewAsDouble(payload.other["x"]) ?? 0
            let y = _viewAsDouble(payload.other["y"]) ?? 0
            _ensureTooltipView()?._showAxisTooltip(list, x: x, y: y)
            zr.refresh()
        case "hideTip":
            tooltipView?.hide()
            zr.refresh()
        default:
            // highlight/downplay from axisTrigger's high-down fan-out already go to the real api directly
            //   (dispatchHighDownActually uses api.dispatchAction); forward any other merged action too.
            ec.dispatchAction(payload)
        }
    }

    // ------------------------------------------------------------------------
    // findDispatcher — upstream `findEventDispatcher(el, det, returnFirstMatch)` (util/event.ts:22):
    //   walk `el` up via `__hostTarget ?? parent`, collecting elements that `isHighDownDispatcher`.
    //   `returnFirstMatch=true` → the innermost (first) match (upstream click, echarts.ts:2343);
    //   `returnFirstMatch=false` → keep walking, return the OUTERMOST (last) match (upstream
    //   mouseover/mouseout, echarts.ts:2329/2336 — no returnFirstMatch).
    // ------------------------------------------------------------------------
    private func findDispatcher(_ target: Element?, returnFirstMatch: Bool) -> Element? {
        var found: Element? = nil
        var cur: Element? = target
        while let el = cur {
            if states.isHighDownDispatcher(el) {
                found = el
                if returnFirstMatch { break }
            }
            // upstream: `target = target.__hostTarget || target.parent`.
            cur = el.__hostTarget ?? (el.parent as? Element)
        }
        return found
    }

    // ------------------------------------------------------------------------
    // _showTooltipForHover — Phase 34. Walk up from the hovered element to the nearest ancestor carrying
    //   ECData with a seriesIndex + dataIndex (mirrors upstream `_tryShow`'s dispatcher det), resolve the
    //   `seriesModel`, and drive `TooltipView.tryShow` with the pointer (`e.offsetX/offsetY` are the zr
    //   coords — see Handler.makeEventPacket). No ECData → nothing to show (bail).
    // ------------------------------------------------------------------------
    private func _showTooltipForHover(_ e: ElementEvent) {
        guard let ecModel = ec.getModel() else { return }
        var cur: Element? = e.target
        while let el = cur {
            let ecData = innerStore.getECData(el)
            if let dataIndex = ecData.dataIndex, let seriesIndex = ecData.seriesIndex,
               let seriesModel = ecModel.getSeriesByIndex(seriesIndex),
               let tooltip = _ensureTooltipView() {
                tooltip.tryShow(
                    event: e,
                    seriesModel: seriesModel,
                    dataIndex: dataIndex,
                    dataType: ecData.dataType,
                    point: [e.offsetX, e.offsetY]
                )
                zr.refresh()
                return
            }
            cur = el.__hostTarget ?? (el.parent as? Element)
        }
    }

    // ------------------------------------------------------------------------
    // _handleClick — MINIMAL click→dispatch. Reads the clicked element's `ECData` (seriesIndex/dataIndex)
    //   and dispatches a `toggleSelect` action for it (upstream click on a highDown dispatcher toggles
    //   SELECTION — `dispatcher.selected ? 'unselect' : 'select'`, echarts.ts:2347; `toggleSelect` is the
    //   ported single-action equivalent). It flows through the already-ported dispatchAction/updateDirectly
    //   path. Upstream additionally assembles a full `ECElementEvent` + triggers the public 'click' bus;
    //   that user-facing param object + the message center is the documented PORT-TODO.
    // ------------------------------------------------------------------------
    private func _handleClick(_ e: ElementEvent) {
        // Click uses the INNERMOST dispatcher (upstream passes returnFirstMatch=true, echarts.ts:2343).
        guard let dispatcher = findDispatcher(e.target, returnFirstMatch: true) ?? e.target else { return }
        // Walk up for the nearest element carrying ECData with a dataIndex (mirrors the `findEventDispatcher`
        //   det in `_initEvents`, which accepts either a dataIndex-bearing or an eventData-bearing ancestor).
        var cur: Element? = dispatcher
        while let el = cur {
            let ecData = innerStore.getECData(el)
            if let dataIndex = ecData.dataIndex, let seriesIndex = ecData.seriesIndex {
                var payload = Payload(type: "toggleSelect")
                payload.other["seriesIndex"] = seriesIndex
                payload.other["dataIndex"] = dataIndex
                ec.dispatchAction(payload)
                zr.refresh()
                return
            }
            cur = el.__hostTarget ?? (el.parent as? Element)
        }
        // PORT-TODO: no ECData on the click target → upstream would still trigger the 'click' event with
        //   an empty param object on the public bus; the bus is deferred, so this is a no-op.
    }

    // ------------------------------------------------------------------------
    // _injectPointerForTest — headless input hook. Forwards a synthetic `ZRRawEvent` through the live
    //   `zr.handler` so a test can drive the emphasis binding without a native input bridge. `type` is a
    //   raw pointer name ('mousemove' / 'mouseout' / 'click'); `mousemove` at a point over a highDown
    //   dispatcher fires the element `mouseover` → `enterEmphasisWhenMouseOver` end-to-end.
    // ------------------------------------------------------------------------
    public func _injectPointerForTest(type: String, zrX: Double, zrY: Double) {
        let raw = ZRRawEvent()
        raw.type = type
        raw.zrX = zrX
        raw.zrY = zrY
        raw.which = 1
        switch type {
        case "mousemove": zr.handler.mousemove(raw)
        case "mouseout":  zr.handler.mouseout(raw)
        case "click":     zr.handler.click(raw)
        case "mousedown": zr.handler.mousedown(raw)
        case "mouseup":   zr.handler.mouseup(raw)
        case "mousewheel", "wheel": zr.handler.mousewheel(raw)
        default:          zr.handler.mousemove(raw)
        }
    }

    // ------------------------------------------------------------------------
    // _injectWheelForTest — headless WHEEL input hook (Phase 38). Builds a synthetic zr "mousewheel"
    //   `ZRRawEvent` carrying `zrDelta` (Handler.makeEventPacket maps it to `ElementEvent.wheelDelta`,
    //   which `_handleInsideZoomWheel` reads) + the cursor pixel, and forwards it through the live
    //   `zr.handler` — so a test can drive the inside-dataZoom wheel-zoom without a native input bridge.
    //   `zrDelta > 0` zooms IN (window shrinks), `< 0` zooms OUT.
    // ------------------------------------------------------------------------
    public func _injectWheelForTest(zrDelta: Double, zrX: Double, zrY: Double) {
        let raw = ZRRawEvent()
        raw.type = "mousewheel"
        raw.zrX = zrX
        raw.zrY = zrY
        raw.zrDelta = zrDelta
        raw.which = 1
        zr.handler.mousewheel(raw)
    }

    /// Coerce a JS-number-ish payload value (Int or Double) to Double (small numbers box as `Int`).
    private func _viewAsDouble(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }

    /// Dispose the live zr (releases the animation clock + input proxy + removes it from the module-global
    /// zrender `instances` registry). The slim `ec` has no lifecycle.
    public func dispose() {
        zr.dispose()
    }

    // Auto-dispose the zr when the view deallocs, so the module-global zrender `instances` registry does
    //   not retain the zr (+ its storage/animation clock) after the view is gone. Reachable only once the
    //   zr↔handler↔eventful↔self cycle is broken (all `_initEvents` listeners bind ctx `nil`, not `self`).
    deinit {
        zr.dispose()
    }
}
