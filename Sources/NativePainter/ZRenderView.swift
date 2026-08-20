// NativePainter — the hand-written UIKit/AppKit replacement for zrender's `dom/HandlerProxy.ts`.
//
// This is NOT a translation. `dom/HandlerProxy.ts` is the browser-DOM event source that drives
// zrender's `Handler` (it `addEventListener`s on the canvas DOM node, normalizes each DOM event into
// a `ZRRawEvent`, and `trigger`s the `mousedown`/`mousemove`/`mouseup`/`click`/`mousewheel`/...
// events that `Handler.setHandlerProxy` subscribes to). Natively there is no DOM, so this file is the
// native equivalent (CONVENTIONS §9):
//
//   * `NativeHandlerProxy` conforms to the `HandlerProxyInterface` that `Handler` defines. It carries
//     the same event-sequencing logic as `HandlerProxy.ts`'s `localDOMHandlers` (touchstart →
//     mousemove+mousedown, touchend → mouseup (+ click within `TOUCH_CLICK_DELAY`), pinch via
//     `Handler.processGesture` / direct `pinch` dispatch), but emits `ZRRawEvent`s that the host view
//     has already normalized into ZRender-local coordinates (so the browser-only `normalizeEvent`
//     coordinate math is bypassed — `e.zrX`/`e.zrY` are set directly).
//
//   * `ZRenderView` is the native host (the analog of zrender's canvas DOM node + its container). It
//     HOSTS the `CALayerPainter`'s `rootLayer`, sizes it to the view, resizes the painter on layout,
//     captures interaction (touchesBegan/Moved/Ended/Cancelled + a `UIPinchGestureRecognizer` on iOS;
//     mouseDown/Dragged/Up + scrollWheel + magnify on macOS), normalizes each into a `ZRRawEvent`, and
//     forwards it through the `NativeHandlerProxy`. It owns the `ZRender` host facade (which now owns
//     the real `Handler` wired to this proxy) and an `AnimationLoop` frame clock.
//
// Drag is NOT mapped here directly: zrender's `Draggable` mixin (owned by `Handler`) derives
// drag/dragstart/dragend from the `mousedown`/`mousemove`/`mouseup` stream, so a pan on a draggable
// element falls out of the touch → mouse sequencing automatically.

import Foundation

#if canImport(UIKit) || canImport(AppKit)
import QuartzCore
import ZRenderKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - NativeHandlerProxy

/// The native replacement for `HandlerProxy.ts`. Conforms to the `HandlerProxyInterface` that
/// `Handler.setHandlerProxy` consumes: it COMPOSES an inner `Eventful` and `trigger`s the zr event
/// names (the events in `handlerNames`) that `Handler` subscribes to, mirroring `extends Eventful`.
public final class NativeHandlerProxy: HandlerProxyInterface {

    private let _eventful = Eventful()

    /// Set by `Handler.setHandlerProxy`. `weak` to break the Handler ⇄ proxy retain cycle (Handler
    /// strongly owns its proxy).
    public weak var handler: Handler?

    /// See [DRAG_OUTSIDE] in `Handler.ts`. On native touch devices "drag outside" is supported by the
    /// platform automatically (touch events keep firing once a touch sequence starts), so we do not
    /// need the browser's global-document pointer-capture machinery.
    private static let TOUCH_CLICK_DELAY: Double = 300

    private var __lastTouchMoment: Date?

    /// Last cursor requested by zrender's hit-test. Public for host diagnostics/tests; iOS records the
    /// semantic value but has no system mouse cursor to update.
    public private(set) var currentCursorStyle: String = "default"

    public init() {}

    // MARK: HandlerProxyInterface

    public func dispose() {
        self._eventful.off(nil, nil)
        self.handler = nil
    }

    /// Apply zrender's CSS cursor semantic to the native pointer on macOS.
    public func setCursor(_ cursorStyle: String?) {
        let style = cursorStyle ?? "default"
        currentCursorStyle = style
#if canImport(AppKit)
        let cursor: NSCursor
        switch style {
        case "pointer": cursor = .pointingHand
        case "crosshair": cursor = .crosshair
        case "text": cursor = .iBeam
        case "move", "grab": cursor = .openHand
        case "grabbing": cursor = .closedHand
        case "ew-resize", "e-resize", "w-resize", "col-resize": cursor = .resizeLeftRight
        case "ns-resize", "n-resize", "s-resize", "row-resize": cursor = .resizeUpDown
        case "not-allowed": cursor = .operationNotAllowed
        default: cursor = .arrow
        }
        cursor.set()
#endif
    }

    @discardableResult
    public func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject?) -> Eventful {
        return self._eventful.on(event, handler, context)
    }

    // MARK: Emission seam (the analog of `localDOMHandlers.*` calling `this.trigger(...)`)

    /// Emit a normalized event to `Handler` (which subscribed through `on`). Mirrors
    /// `localDOMHandlers.<name>` doing `this.trigger(name, event)`.
    private func emit(_ name: String, _ event: ZRRawEvent) {
        _ = self._eventful.trigger(name, event)
    }

    // Mark touch, which is useful to distinguish touch and mouse event in the upper application.
    private func markTouch(_ event: ZRRawEvent) {
        event.zrByTouch = true
    }

    // MARK: Mouse stream (the host calls these after building a normalized ZRRawEvent)

    public func mousedown(_ event: ZRRawEvent) { self.emit("mousedown", event) }
    public func mousemove(_ event: ZRRawEvent) { self.emit("mousemove", event) }
    public func mouseup(_ event: ZRRawEvent)   { self.emit("mouseup", event) }
    public func mouseout(_ event: ZRRawEvent)  { self.emit("mouseout", event) }
    public func click(_ event: ZRRawEvent)     { self.emit("click", event) }
    public func dblclick(_ event: ZRRawEvent)  { self.emit("dblclick", event) }
    public func contextmenu(_ event: ZRRawEvent) { self.emit("contextmenu", event) }
    // Follow `HandlerProxy.ts`: the zrender event name for a wheel is still 'mousewheel'.
    public func wheel(_ event: ZRRawEvent)     { self.emit("mousewheel", event) }

    // MARK: Touch stream — faithful port of `localDOMHandlers.touchstart/touchmove/touchend`.

    public func touchstart(_ event: ZRRawEvent) {
        markTouch(event)

        self.__lastTouchMoment = Date()

        self.handler?.processGesture(event, "start")

        // For consistent event listeners across touch and mouse, we simulate "mouseover→mousedown"
        // on touch: trigger `mousemove` here (so `mouseover` fires inside), then `mousedown`.
        self.mousemove(event)
        self.mousedown(event)
    }

    public func touchmove(_ event: ZRRawEvent) {
        markTouch(event)

        self.handler?.processGesture(event, "change")

        // Mouse move should always be triggered no matter whether there is a gesture event, because
        // mouse move and pinch may be used at the same time.
        self.mousemove(event)
    }

    public func touchend(_ event: ZRRawEvent) {
        markTouch(event)

        self.handler?.processGesture(event, "end")

        self.mouseup(event)

        // Do not trigger `mouseout` here (see the long note in `HandlerProxy.ts`): "hover style" set
        // on `mouseover` should remain after a touch lifts.
        //
        // click should always be triggered no matter whether there is a gesture event.
        if let last = self.__lastTouchMoment,
           Date().timeIntervalSince(last) * 1000 < NativeHandlerProxy.TOUCH_CLICK_DELAY {
            self.click(event)
        }
    }

    /// touchcancel has no DOM analog in `HandlerProxy.ts`; treat it as a touchend WITHOUT the click
    /// (a cancelled touch must not be interpreted as a tap).
    public func touchcancel(_ event: ZRRawEvent) {
        markTouch(event)
        self.handler?.processGesture(event, "end")
        self.mouseup(event)
    }

    // MARK: Pinch — the analog of `onMSGestureChange` in `HandlerProxy.ts`.

    /// Dispatch a `pinch` directly to the hovered element. `event` must already carry
    /// `pinchScale`/`pinchX`/`pinchY` and ZRender-local `zrX`/`zrY` (set by the host). Mirrors the
    /// commented-out `onMSGestureChange`: `proxy.handler.dispatchToElement(target, 'pinch', event)`.
    public func pinch(_ event: ZRRawEvent) {
        guard let handler = self.handler else { return }
        markTouch(event)
        event.gestureEvent = "pinch"
        let hovered = handler.findHover(event.zrX ?? 0, event.zrY ?? 0, nil)
        handler.dispatchToElement(hovered, .pinch, event)
    }
}

// MARK: - ZRenderView (iOS: UIView / macOS: NSView)

#if canImport(UIKit)

/// A `UIView` that hosts a `CALayerPainter` scene graph and routes UIKit interaction into ZRender's
/// `Handler` through a `NativeHandlerProxy`. Add elements via `view.zr.add(...)`.
public final class ZRenderView: UIView {

    /// The painter whose `rootLayer` this view hosts. `CALayerPainter` by default; an
    /// alternative backend (e.g. the Metal `RasterizerPainter`) can be injected at init.
    public let painter: LayerHostedPainter

    /// The ZRender host facade (owns the `Handler` wired to `proxy`).
    public let zr: ZRender

    /// The native event bridge.
    public let proxy: NativeHandlerProxy

    private let animationLoop: AnimationLoop

    public init(frame: CGRect, dpr: Double? = nil, backgroundColor bg: CGColor? = nil,
                painter injected: LayerHostedPainter? = nil) {
        let size = frame.size == .zero ? CGSize(width: 1, height: 1) : frame.size
        let painter = injected ?? CALayerPainter(size: size, dpr: dpr, backgroundColor: bg)
        let proxy = NativeHandlerProxy()
        var opts = ZRenderInitOpt()
        opts.useCoarsePointer = true
        let zr = ZRenderKit.`init`(nil, opts, painter: painter, proxy: proxy)

        self.painter = painter
        self.proxy = proxy
        self.zr = zr
        self.animationLoop = AnimationLoop(animation: zr.animation)

        super.init(frame: frame)

        self.isMultipleTouchEnabled = true
        self.layer.addSublayer(painter.rootLayer)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinch)

        self.animationLoop.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        self.animationLoop.stop()
        self.zr.dispose()
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        painter.rootLayer.frame = CGRect(origin: .zero, size: size)
        var opt = ZRenderResizeOpt()
        opt.width = Double(size.width)
        opt.height = Double(size.height)
        zr.resize(opt)
        zr.refresh()
    }

    // MARK: Touch capture → normalized ZRRawEvent → proxy

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchstart(makeTouchEvent("touchstart", touches, event))
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchmove(makeTouchEvent("touchmove", touches, event))
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchend(makeTouchEvent("touchend", touches, event))
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchcancel(makeTouchEvent("touchend", touches, event))
    }

    /// Build a `ZRRawEvent` already normalized into ZRender-local coordinates (UIView space is
    /// top-left / y-down, matching zrender's coordinate convention, so no flip is needed). The
    /// primary touch drives `zrX`/`zrY`; every active touch is copied into `touches` so
    /// `Handler.processGesture` (GestureMgr) can recognize a pinch.
    private func makeTouchEvent(_ type: String, _ changed: Set<UITouch>, _ uiEvent: UIEvent?) -> ZRRawEvent {
        let e = ZRRawEvent()
        e.type = type

        let allTouches = uiEvent?.allTouches ?? changed
        // Prefer a non-ended touch for the anchor; fall back to a changed touch (e.g. touchend).
        let primary = allTouches.first(where: { $0.phase != .ended && $0.phase != .cancelled }) ?? changed.first
        if let primary = primary {
            let p = primary.location(in: self)
            e.zrX = Double(p.x)
            e.zrY = Double(p.y)
            e.clientX = Double(p.x)
            e.clientY = Double(p.y)
        }
        e.which = 1

        var list: [Touch] = []
        for t in allTouches where t.phase != .ended && t.phase != .cancelled {
            let p = t.location(in: self)
            list.append(Touch(clientX: Double(p.x), clientY: Double(p.y)))
        }
        // On touchend the changed touch may already be in `.ended`; ensure `touches` is non-empty so
        // GestureMgr's final track is recorded.
        if list.isEmpty, let primary = primary {
            let p = primary.location(in: self)
            list.append(Touch(clientX: Double(p.x), clientY: Double(p.y)))
        }
        e.touches = list
        e.targetTouches = list
        e.changedTouches = changed.map { t in
            let p = t.location(in: self)
            return Touch(clientX: Double(p.x), clientY: Double(p.y))
        }
        return e
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        let c = g.location(in: self)
        let e = ZRRawEvent()
        e.type = "pinch"
        e.zrX = Double(c.x)
        e.zrY = Double(c.y)
        e.clientX = Double(c.x)
        e.clientY = Double(c.y)
        e.pinchX = Double(c.x)
        e.pinchY = Double(c.y)
        e.pinchScale = Double(g.scale)
        proxy.pinch(e)
        // Reset so each delta is reported relative to the last (matches the per-step pinch ratio the
        // GestureMgr recognizer produces from successive touch frames).
        g.scale = 1
    }
}

#elseif canImport(AppKit)

/// An `NSView` that hosts a `CALayerPainter` scene graph and routes AppKit interaction into ZRender's
/// `Handler` through a `NativeHandlerProxy`. Add elements via `view.zr.add(...)`.
public final class ZRenderView: NSView {

    /// `CALayerPainter` by default; an alternative backend (e.g. the Metal
    /// `RasterizerPainter`) can be injected at init.
    public let painter: LayerHostedPainter
    public let zr: ZRender
    public let proxy: NativeHandlerProxy

    private let animationLoop: AnimationLoop
    /// Tracking area so bare pointer movement (no button) is delivered as `mouseMoved`. The browser
    /// fires `mousemove` on hover, which zrender turns into hover dispatch (mouseover/mouseout) and
    /// which demos listen to via `zr.on("mousemove")`; without this, AppKit only delivers movement
    /// while a button is held (`mouseDragged`). `.inVisibleRect` keeps it sized to the view.
    private var movementTrackingArea: NSTrackingArea?

    /// Latest un-dispatched pointer move, coalesced to the frame clock. AppKit can deliver
    /// `mouseMoved`/`mouseDragged` faster than the ~60Hz frame loop (ProMotion / high-rate
    /// trackpads), and dispatching each one immediately re-runs every `mousemove` listener at
    /// that raw rate — which on heavy handlers (e.g. animationStart restarts 500 animators per
    /// call) causes lag. The browser coalesces pointer events to the rAF cadence; we mirror that
    /// by keeping only the most recent move and flushing it once per frame (see `flushPendingMove`).
    private var pendingMove: ZRRawEvent?
    private let _loopBox = _FrameHook()

    public init(frame: CGRect, dpr: Double? = nil, backgroundColor bg: CGColor? = nil,
                painter injected: LayerHostedPainter? = nil) {
        let size = frame.size == .zero ? CGSize(width: 1, height: 1) : frame.size
        let painter = injected ?? CALayerPainter(size: size, dpr: dpr, backgroundColor: bg)
        let proxy = NativeHandlerProxy()
        var opts = ZRenderInitOpt()
        opts.useCoarsePointer = false
        let zr = ZRenderKit.`init`(nil, opts, painter: painter, proxy: proxy)

        self.painter = painter
        self.proxy = proxy
        self.zr = zr
        // Drive frames through a hook so the coalesced pointer move is flushed BEFORE the animation
        // update — any animators a `mousemove` handler starts then advance + paint in the same frame.
        let hook = self._loopBox
        self.animationLoop = AnimationLoop { [weak hook] in hook?.run?() }

        super.init(frame: frame)

        hook.run = { [weak self] in
            self?.flushPendingMove()
            zr.animation.update()
        }

        self.wantsLayer = true
        self.layer?.addSublayer(painter.rootLayer)

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
        self.addGestureRecognizer(magnify)

        self.animationLoop.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        self.animationLoop.stop()
        self.zr.dispose()
    }

    /// Top-left / y-down coordinates (matching zrender's convention and the painter's flipped
    /// AppKit root layer), so mouse points map straight to `zrX`/`zrY`.
    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let size = bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        painter.rootLayer.frame = CGRect(origin: .zero, size: size)
        var opt = ZRenderResizeOpt()
        opt.width = Double(size.width)
        opt.height = Double(size.height)
        zr.resize(opt)
        zr.refresh()
    }

    // MARK: Mouse capture → normalized ZRRawEvent → proxy

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = movementTrackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.activeInActiveApp, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        movementTrackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        // Coalesce to the frame clock (browser-like): keep only the latest, flush once per frame.
        pendingMove = makeMouseEvent("mousemove", event, which: 0)
    }

    public override func mouseDown(with event: NSEvent) {
        flushPendingMove()   // preserve ordering: a pending move is delivered before the press.
        proxy.mousedown(makeMouseEvent("mousedown", event, which: 1))
    }

    public override func mouseDragged(with event: NSEvent) {
        pendingMove = makeMouseEvent("mousemove", event, which: 1)
    }

    public override func mouseUp(with event: NSEvent) {
        flushPendingMove()   // deliver the final drag position before the release/click.
        let e = makeMouseEvent("mouseup", event, which: 1)
        proxy.mouseup(e)
        // A press-release without drag is a click (the Handler's own down/up/distance gate filters
        // the drag case; see `Handler.commonHandler`).
        if event.clickCount >= 2 {
            proxy.dblclick(makeMouseEvent("dblclick", event, which: 1))
        }
        else {
            proxy.click(makeMouseEvent("click", event, which: 1))
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        proxy.mousedown(makeMouseEvent("mousedown", event, which: 3))
        proxy.contextmenu(makeMouseEvent("contextmenu", event, which: 3))
    }

    /// Deliver the most recent coalesced pointer move (if any). Called once per frame from the
    /// animation loop, and before any press/release so event ordering is preserved.
    private func flushPendingMove() {
        guard let event = pendingMove else { return }
        pendingMove = nil
        proxy.mousemove(event)
    }

    public override func scrollWheel(with event: NSEvent) {
        let e = makeMouseEvent("mousewheel", event, which: 0)
        e.zrDelta = Double(event.scrollingDeltaY)
        proxy.wheel(e)
    }

    @objc private func handleMagnify(_ g: NSMagnificationGestureRecognizer) {
        let c = g.location(in: self)
        let e = ZRRawEvent()
        e.type = "pinch"
        e.zrX = Double(c.x)
        e.zrY = Double(c.y)
        e.clientX = Double(c.x)
        e.clientY = Double(c.y)
        e.pinchX = Double(c.x)
        e.pinchY = Double(c.y)
        // NSEvent.magnification is an incremental delta around 0; map to a per-step scale ratio.
        e.pinchScale = 1 + Double(g.magnification)
        proxy.pinch(e)
    }

    private func makeMouseEvent(_ type: String, _ event: NSEvent, which: Double) -> ZRRawEvent {
        let p = convert(event.locationInWindow, from: nil)
        let e = ZRRawEvent()
        e.type = type
        e.zrX = Double(p.x)
        e.zrY = Double(p.y)
        e.clientX = Double(p.x)
        e.clientY = Double(p.y)
        e.which = which
        e.button = which > 0 ? which - 1 : nil
        return e
    }
}

/// Mutable indirection so the `AnimationLoop` callback (captured at init, before `self` is fully
/// available) can call back into the view each frame without a retain cycle.
private final class _FrameHook {
    var run: (() -> Void)?
}

#endif // UIKit / AppKit

#endif // canImport(UIKit) || canImport(AppKit)
