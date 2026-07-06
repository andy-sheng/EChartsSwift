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
            // upstream binds `findEventDispatcher(el, isHighDownDispatcher)` WITHOUT returnFirstMatch →
            //   the OUTERMOST matching ancestor is emphasized (matters for nested dispatchers).
            if let dispatcher = self.findDispatcher(e.target, returnFirstMatch: false) {
                states.enterEmphasisWhenMouseOver(dispatcher, e)
                self.zr.refresh()
            }
            return nil
        }, nil)

        // mouseout: leave emphasis on the nearest highDown dispatcher.
        _ = zr.on("mouseout", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            if let dispatcher = self.findDispatcher(e.target, returnFirstMatch: false) {
                states.leaveEmphasisWhenMouseOut(dispatcher, e)
                self.zr.refresh()
            }
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

        // PORT-TODO (DEFERRED — later phase): the `mousemove` → axisPointer/tooltip `axisTrigger` → showTip
        //   path (upstream tooltip/axisPointer views bind their own zr `mousemove` listener). Not wired here.
        // PORT-TODO (DEFERRED): the generic `MOUSE_EVENT_NAMES` fan-out onto the public ECharts event bus
        //   (`this.trigger(eveName, ECElementEvent)`) — needs `getDataParams` param assembly + a message bus.
        // PORT-TODO (DEFERRED): `globalout` (no `e.target`) → `allLeaveBlur` / leave-emphasis reset.
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
        default:          zr.handler.mousemove(raw)
        }
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
