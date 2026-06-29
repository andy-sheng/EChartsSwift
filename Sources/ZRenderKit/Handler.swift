// Ported from zrender/src/Handler.ts — keep in sync with upstream
//
// The interaction core: hit-testing the Storage display list (findHover) and the
// mousedown/up/move/click/dblclick/mouseover/mouseout/mousewheel/contextmenu event dispatch +
// bubbling. Composes Draggable (mixin/Draggable.swift), GestureMgr (core/GestureMgr.swift) and
// eventTool (core/event.swift).
//
// COMPOSITION NOTE (CONVENTIONS §2): upstream `class Handler extends Eventful`. The Swift
//   `Eventful` is a `final class` (mixin, not a superclass — see Core/Eventful.swift), so `Handler`
//   COMPOSES an inner `_eventful` and forwards the event surface (on/off/trigger/...), exactly like
//   `Element` and `ZRender` do. `handler.trigger(...)`/`handler.on(...)` therefore behave as
//   `extends Eventful`.
//
// NATIVE SEAM (CONVENTIONS §9): upstream `dom/HandlerProxy.ts` (the browser DOM event source) is
//   NOT translated — it is replaced by a hand-written UIKit bridge that conforms to the
//   `HandlerProxyInterface` protocol below, emitting normalized `ZRRawEvent`s into Handler's
//   `mousedown`/`mousemove`/... methods (the events listed in `handlerNames`) and exposing
//   `setCursor`. The browser-only proxy wiring stays behind that protocol.

import Foundation

// import * as util from './core/util';
// import * as vec2 from './core/vector';
// import Draggable from './mixin/Draggable';
// import Eventful from './core/Eventful';
// import * as eventTool from './core/event';
// import {GestureMgr} from './core/GestureMgr';
// import Displayable from './graphic/Displayable';
// import {PainterBase} from './PainterBase';
// import HandlerDomProxy, { HandlerProxyInterface } from './dom/HandlerProxy';
// import { ZRRawEvent, ZRPinchEvent, ElementEventName, ElementEventNameWithOn, ZRRawTouchEvent } from './core/types';
// import Storage from './Storage';
// import Element, {ElementEvent} from './Element';
// import CanvasPainter from './canvas/Painter';
// import BoundingRect from './core/BoundingRect';

/**
 * [The interface between `Handler` and `HandlerProxy`]:
 *
 * The default `HandlerProxy` only support the common standard web environment
 * (e.g., standalone browser, headless browser, embed browser in mobild APP, ...).
 * But `HandlerProxy` can be replaced to support more non-standard environment
 * (e.g., mini app), or to support more feature that the default `HandlerProxy`
 * not provided (like echarts-gl did).
 * So the interface between `Handler` and `HandlerProxy` should be stable. Do not
 * make break changes util inevitable. The interface include the public methods
 * of `Handler` and the events listed in `handlerNames` below, by which `HandlerProxy`
 * drives `Handler`.
 */

/**
 * [DRAG_OUTSIDE]:
 *
 * That is, triggering `mousemove` and `mouseup` event when the pointer is out of the
 * zrender area when dragging. That is important for the improvement of the user experience
 * when dragging something near the boundary without being terminated unexpectedly.
 *
 * We originally consider to introduce new events like `pagemovemove` and `pagemouseup`
 * to resolve this issue. But some drawbacks of it is described in
 * https://github.com/ecomfe/zrender/pull/536#issuecomment-560286899
 *
 * Instead, we referenced the specifications:
 * https://www.w3.org/TR/touch-events/#the-touchmove-event
 * https://www.w3.org/TR/2014/WD-DOM-Level-3-Events-20140925/#event-type-mousemove
 * where the the mousemove/touchmove can be continue to fire if the user began a drag
 * operation and the pointer has left the boundary. (for the mouse event, browsers
 * only do it on `document` and when the pointer has left the boundary of the browser.)
 *
 * So the default `HandlerProxy` supports this feature similarly: if it is in the dragging
 * state (see `pointerCapture` in `HandlerProxy`), the `mousemove` and `mouseup` continue
 * to fire until release the pointer. That is implemented by listen to those event on
 * `document`.
 * If we implement some other `HandlerProxy` only for touch device, that would be easier.
 * The touch event support this feature by default.
 * The term "pointer capture" is from the spec:
 * https://www.w3.org/TR/pointerevents2/#idl-def-element-setpointercapture-pointerid
 *
 * Note:
 * There might be some cases that the mouse event can not be received on `document`.
 * For example,
 * (A) When `useCapture` is not supported and some user defined event listeners on the ancestor
 * of zr dom throw Error.
 * (B) When `useCapture` is not supported and some user defined event listeners on the ancestor of
 * zr dom call `stopPropagation`.
 * In these cases, the `mousemove` event might be keep triggering event when the mouse is released.
 * We try to reduce the side-effect in those cases, that is, use `isOutsideBoundary` to prevent
 * it from do anything (especially, `findHover`).
 * (`useCapture` mean, `addEvnetListener(listener, {capture: true})`, althought it may not be
 * suppported in some environments.)
 *
 * Note:
 * If `HandlerProxy` listens to `document` with `useCapture`, `HandlerProxy` needs to
 * prevent user-registered-handler from calling `stopPropagation` and `preventDefault`
 * when the `event.target` is not a zrender dom element. Otherwise the user-registered-handler
 * may be able to prevent other elements (that not relevant to zrender) in the web page from receiving
 * dom events.
 */

private let SILENT = "silent"

// upstream: result of `isHover` — `false` (not hovered) | `'silent'` | `true`. Swift has no
//   `string | boolean` union, so the tri-state is an enum. setHoverTarget tests `!== SILENT`.
private enum IsHoverResult {
    case `false`
    case `true`
    case silent
}

private func makeEventPacket(_ eveType: ElementEventName, _ targetInfo: DraggableTargetInfo, _ event: ZRRawEvent) -> ElementEvent {
    var packet = ElementEvent()
    packet.type = eveType
    packet.event = event
    // target can only be an element that is not silent.
    packet.target = targetInfo.target
    // topTarget can be a silent element.
    packet.topTarget = targetInfo.topTarget
    packet.cancelBubble = false
    packet.offsetX = event.zrX ?? 0
    packet.offsetY = event.zrY ?? 0
    packet.gestureEvent = event.gestureEvent
    packet.pinchX = event.pinchX
    packet.pinchY = event.pinchY
    packet.pinchScale = event.pinchScale
    packet.wheelDelta = event.zrDelta
    packet.zrByTouch = event.zrByTouch
    packet.which = event.which
    // upstream: `stop: stopEvent` (the bound method below, with `this.event` === `event`).
    packet.stop = { stopEvent(event) }
    return packet
}

private func stopEvent(_ event: ZRRawEvent) {
    eventTool.stop(event)
}

// upstream: `class EmptyProxy extends Eventful`. Eventful is a `final class` here (CONVENTIONS §2),
//   so EmptyProxy COMPOSES an inner `_eventful` and forwards `on`, matching `extends Eventful`.
final class EmptyProxy: HandlerProxyInterface {
    private let _eventful = Eventful()
    var handler: Handler? = nil
    func dispose() {}
    func setCursor(_ cursorStyle: String?) {}

    @discardableResult
    func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> Eventful {
        return self._eventful.on(event, handler, context)
    }
}

public final class HoveredResult: DraggableTargetInfo {
    public var x: Double?
    public var y: Double?
    // upstream: target/topTarget are `Displayable`. Widened to `Element?` so `HoveredResult` can
    //   conform to `DraggableTargetInfo` (Draggable reads `.target` as `Element`). Every real hover
    //   target IS a `Displayable` (findHover only ever stores display-list items), so Displayable
    //   members (e.g. `cursor`) are read back via `as? Displayable`.
    public var target: Element?
    public var topTarget: Element?
    public init(_ x: Double? = nil, _ y: Double? = nil) {
        self.x = x
        self.y = y
    }
}

private let handlerNames = [
    "click", "dblclick", "mousewheel", "mouseout",
    "mouseup", "mousedown", "mousemove", "contextmenu"
]

// type HandlerName = 'click' | 'dblclick' | 'mousewheel' | 'mouseout' |
//     'mouseup' | 'mousedown' | 'mousemove' | 'contextmenu';
// (modeled as `String`; see `callHandler` / `dispatch`.)

private let tmpRect = BoundingRect(0, 0, 0, 0)

// upstream: `HandlerProxyInterface extends Eventful`. The native UIKit bridge (replacement for
//   `dom/HandlerProxy.ts`, CONVENTIONS §9) conforms to this — it drives Handler by emitting
//   normalized events through `on`, and exposes `setCursor`. Eventful's surface is reduced to the
//   `on` that `Handler.setHandlerProxy` actually calls.
public protocol HandlerProxyInterface: AnyObject {
    var handler: Handler? { get set }
    func dispose()
    func setCursor(_ cursorStyle: String?)

    @discardableResult
    func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject?) -> Eventful
}

// TODO draggable
public final class Handler: DraggableHandler {

    public var storage: Storage!
    public var painter: PainterBase!
    // upstream: `painterRoot: HTMLElement`. The DOM root is the native event seam (CONVENTIONS §9);
    //   nil natively. // PORT-TODO: provided by the native UIKit bridge.
    public var painterRoot: HTMLElement?

    public var proxy: HandlerProxyInterface!

    private var _hovered = HoveredResult(0, 0)

    private var _gestureMgr: GestureMgr?

    private var _draggingMgr: Draggable!

    private var _pointerSize: Double?

    var _downEl: Element?
    var _upEl: Element?
    var _downPoint: VectorArray?

    // upstream `Handler extends Eventful` — composed here (Eventful is a `final class`). See header.
    private let _eventful = Eventful()

    public init(
        _ storage: Storage,
        _ painter: PainterBase,
        _ proxy: HandlerProxyInterface?,
        _ painterRoot: HTMLElement?,
        _ pointerSize: Double?
    ) {
        // super();   (Eventful composed via `_eventful`)

        self.storage = storage

        self.painter = painter

        self.painterRoot = painterRoot

        self._pointerSize = pointerSize

        let proxy = proxy ?? EmptyProxy()

        /**
         * Proxy of event. can be Dom, WebGLSurface, etc.
         */
        self.proxy = nil

        self.setHandlerProxy(proxy)

        self._draggingMgr = Draggable(self)
    }

    public func setHandlerProxy(_ proxy: HandlerProxyInterface?) {
        if let existing = self.proxy {
            existing.dispose()
        }

        if let proxy = proxy {
            // util.each(handlerNames, function (name) {
            //     proxy.on && proxy.on(name, this[name as HandlerName], this);
            // }, this);
            for name in handlerNames {
                proxy.on(name, { [weak self] _, args in
                    guard let self = self, let e = args.first as? ZRRawEvent else { return nil }
                    self.callHandler(name, e)
                    return nil
                }, self)
            }
            // Attach handler
            proxy.handler = self
        }
        self.proxy = proxy
    }

    public func mousemove(_ event: ZRRawEvent) {
        let x = event.zrX ?? 0
        let y = event.zrY ?? 0

        let isOutside = isOutsideBoundary(self, x, y)

        var lastHovered = self._hovered
        var lastHoveredTarget = lastHovered.target

        // If lastHoveredTarget is removed from zr (detected by '__zr') by some API call
        // (like 'setOption' or 'dispatchAction') in event handlers, we should find
        // lastHovered again here. Otherwise 'mouseout' can not be triggered normally.
        // See #6198.
        if let lht = lastHoveredTarget, lht.__zr == nil {
            lastHovered = self.findHover(lastHovered.x ?? 0, lastHovered.y ?? 0)
            lastHoveredTarget = lastHovered.target
        }

        let hovered = isOutside ? HoveredResult(x, y) : self.findHover(x, y)
        self._hovered = hovered
        let hoveredTarget = hovered.target

        let proxy = self.proxy
        // proxy.setCursor && proxy.setCursor(hoveredTarget ? hoveredTarget.cursor : 'default')
        proxy?.setCursor(hoveredTarget != nil ? ((hoveredTarget as? Displayable)?.cursor ?? "default") : "default")

        // Mouse out on previous hovered element
        if lastHoveredTarget != nil && hoveredTarget !== lastHoveredTarget {
            self.dispatchToElement(lastHovered, .mouseout, event)
        }

        // Mouse moving on one element
        self.dispatchToElement(hovered, .mousemove, event)

        // Mouse over on a new element
        if hoveredTarget != nil && hoveredTarget !== lastHoveredTarget {
            self.dispatchToElement(hovered, .mouseover, event)
        }
    }

    public func mouseout(_ event: ZRRawEvent) {
        let eventControl = event.zrEventControl

        if eventControl != "only_globalout" {
            self.dispatchToElement(self._hovered, .mouseout, event)
        }

        if eventControl != "no_globalout" {
            // FIXME: if the pointer moving from the extra doms to realy "outside",
            // the `globalout` should have been triggered. But currently not.
            var globalOut = ElementEvent()
            globalOut.type = .globalout
            globalOut.event = event
            self.trigger("globalout", globalOut)
        }
    }

    /**
     * Resize
     */
    public func resize() {
        self._hovered = HoveredResult(0, 0)
    }

    /**
     * Dispatch event
     */
    public func dispatch(_ eventName: String, _ eventArgs: ZRRawEvent? = nil) {
        // const handler = this[eventName];
        // handler && handler.call(this, eventArgs);
        if let eventArgs = eventArgs {
            self.callHandler(eventName, eventArgs)
        }
    }

    /**
     * Dispose
     */
    public func dispose() {

        self.proxy.dispose()

        self.storage = nil
        self.proxy = nil
        self.painter = nil
    }

    /**
     * 设置默认的cursor style
     * @param cursorStyle 例如 crosshair，默认为 'default'
     */
    public func setCursorStyle(_ cursorStyle: String) {
        let proxy = self.proxy
        proxy?.setCursor(cursorStyle)
    }

    /**
     * 事件分发代理
     *
     * @private
     * @param {Object} targetInfo {target, topTarget} 目标图形元素
     * @param {string} eventName 事件名称
     * @param {Object} event 事件对象
     */
    public func dispatchToElement(_ targetInfo: DraggableTargetInfo, _ eventName: ElementEventName, _ event: Any?) {

        // upstream: `targetInfo = targetInfo || {}`. The DraggableHandler protocol types `targetInfo`
        //   non-optional, so the `|| {}` guard moved to the call sites (every caller passes a
        //   non-nil HoveredResult / Param).

        var el: Element? = targetInfo.target
        if let el = el, el.silent {
            return
        }
        // const eventKey = ('on' + eventName) as ElementEventNameWithOn;
        // PORT-TODO: the `on`-prop handlers (ElementEventHandlerProps: onclick/onmousedown/...) are
        //   not modeled on Element (native event seam, CONVENTIONS §9), so `el[eventKey]` and its
        //   `cancelBubble` write are omitted. Consequently bubble-cancel via on-props is inert.
        // PORT-TODO: ElementEvent is a value-type struct here; mutations a listener makes to the
        //   packet (e.g. `cancelBubble`) do not propagate back to this loop's `eventPacket`, so it
        //   is never reassigned (hence `let`). FIDELITY-GAP: make ElementEvent a `final class` so
        //   listener `cancelBubble` writes are visible here and stopPropagation works (see
        //   InteractionSmokeTests.test_stopPropagation_child_stops_parent). Tracked for the
        //   pre-echarts fidelity-hardening pass.
        let eventPacket = makeEventPacket(eventName, targetInfo, (event as? ZRRawEvent) ?? ZRRawEvent())

        while let cur = el {
            // el[eventKey]
            //     && (eventPacket.cancelBubble = !!el[eventKey].call(el, eventPacket));   // PORT-TODO above

            cur.trigger(eventName.rawValue, eventPacket)

            // Bubble to the host if on the textContent.
            // PENDING
            el = cur.__hostTarget != nil ? cur.__hostTarget : (cur.parent as? Element)

            if eventPacket.cancelBubble {
                break
            }
        }

        if !eventPacket.cancelBubble {
            // 冒泡到顶级 zrender 对象
            self.trigger(eventName.rawValue, eventPacket)
            // 分发事件到用户自定义层
            // 用户有可能在全局 click 事件中 dispose，所以需要判断下 painter 是否存在
            // PORT-TODO: `(this.painter as CanvasPainter).eachOtherLayer` — canvas-only user layers,
            //   not modeled by the native PainterBase (browser/canvas seam, CONVENTIONS §9).
            // if (this.painter && (this.painter as CanvasPainter).eachOtherLayer) { ... }
            _ = eventPacket
        }
    }

    @discardableResult
    public func findHover(_ x: Double, _ y: Double, _ exclude: Displayable? = nil) -> HoveredResult {
        let list = self.storage.getDisplayList()
        let out = HoveredResult(x, y)
        setHoverTarget(list, out, x, y, exclude)

        if let pointerSize = self._pointerSize, pointerSize != 0, out.target == nil {
            /**
             * If no element at pointer position, check intersection with
             * elements with pointer enlarged by target size.
             */
            var candidates: [Displayable] = []
            let targetSizeHalf = pointerSize / 2
            let pointerRect = BoundingRect(x - targetSizeHalf, y - targetSizeHalf, pointerSize, pointerSize)

            var i = list.count - 1
            while i >= 0 {
                let el = list[i]
                if el !== exclude
                    && !el.ignore
                    && !(el.ignoreCoarsePointer ?? false)
                    // If an element ignores, its textContent should also ignore.
                    // TSpan's parent is not a Group but a ZRText.
                    // See Text.js _getOrCreateChild
                    && (el.parent == nil || !((el.parent as? Displayable)?.ignoreCoarsePointer ?? false))
                {
                    // PORT-TODO: upstream assumes `getBoundingRect()` non-null (Path/Displayable).
                    if let rect = el.getBoundingRect() {
                        tmpRect.copy(rect)
                    }
                    if let transform = el.transform {
                        tmpRect.applyTransform(transform)
                    }
                    if tmpRect.intersect(pointerRect) {
                        candidates.append(el)
                    }
                }
                i -= 1
            }

            /**
             * If there are elements whose bounding boxes are near the pointer,
             * use the most top one that intersects with the enlarged pointer.
             */
            if candidates.count > 0 {
                let rStep = 4.0
                let thetaStep = Double.pi / 12
                let PI2 = Double.pi * 2
                var r = 0.0
                while r < targetSizeHalf {
                    var theta = 0.0
                    while theta < PI2 {
                        let x1 = x + r * cos(theta)
                        let y1 = y + r * sin(theta)
                        setHoverTarget(candidates, out, x1, y1, exclude)
                        if out.target != nil {
                            return out
                        }
                        theta += thetaStep
                    }
                    r += rStep
                }
            }
        }

        return out
    }

    public func processGesture(_ event: ZRRawEvent, _ stage: String? = nil) {
        if self._gestureMgr == nil {
            self._gestureMgr = GestureMgr()
        }
        let gestureMgr = self._gestureMgr!

        if stage == "start" { gestureMgr.clear() }

        // PORT-TODO: native seam — GestureMgr consumes a `ZRRawTouchEvent` (with `touches[]`); bridge
        //   it from the normalized `ZRRawEvent`. `(this.proxy as HandlerDomProxy).dom` (the DOM root)
        //   is browser-only and supplied as nil natively (CONVENTIONS §9).
        let touchEvent = ZRRawTouchEvent(touches: event.touches)
        let gestureInfo = gestureMgr.recognize(
            touchEvent,
            // upstream passes `findHover(...).target` (possibly undefined). GestureMgr requires a
            //   non-optional Displayable; on an empty-space pinch fall back to a sentinel.
            //   // PORT-TODO: target identity diverges from upstream `undefined` in that edge case.
            (self.findHover(event.zrX ?? 0, event.zrY ?? 0, nil).target as? Displayable) ?? Displayable(),
            nil
        )

        if stage == "end" { gestureMgr.clear() }

        // Do not do any preventDefault here. Upper application do that if necessary.
        if let gestureInfo = gestureInfo {
            let type = gestureInfo.type
            event.gestureEvent = type
            // The recognizer wrote pinchScale/pinchX/pinchY onto `touchEvent`; copy them onto the
            //   dispatched event so `makeEventPacket` can read them (upstream casts the same object).
            event.pinchScale = touchEvent.pinchScale
            event.pinchX = touchEvent.pinchX
            event.pinchY = touchEvent.pinchY

            let res = HoveredResult()
            res.target = gestureInfo.target
            self.dispatchToElement(res, ElementEventName(rawValue: type) ?? .pinch, event)
        }
    }

    // upstream declares `click`/`mousedown`/`mouseup`/`mousewheel`/`dblclick`/`contextmenu` as
    //   instance fields and installs the bodies via the `util.each([...])` prototype loop below.
    //   Swift has no prototype augmentation, so the shared body is `commonHandler` and each name is
    //   an explicit method (faithful method set; the loop is unrolled).
    public func click(_ event: ZRRawEvent) { self.commonHandler(.click, event) }
    public func mousedown(_ event: ZRRawEvent) { self.commonHandler(.mousedown, event) }
    public func mouseup(_ event: ZRRawEvent) { self.commonHandler(.mouseup, event) }
    public func mousewheel(_ event: ZRRawEvent) { self.commonHandler(.mousewheel, event) }
    public func dblclick(_ event: ZRRawEvent) { self.commonHandler(.dblclick, event) }
    public func contextmenu(_ event: ZRRawEvent) { self.commonHandler(.contextmenu, event) }

    // Common handlers
    // util.each(['click', 'mousedown', 'mouseup', 'mousewheel', 'dblclick', 'contextmenu'], function (name) {
    //     Handler.prototype[name] = function (event) { ... };
    // });
    private func commonHandler(_ name: ElementEventName, _ event: ZRRawEvent) {
        let x = event.zrX ?? 0
        let y = event.zrY ?? 0
        let isOutside = isOutsideBoundary(self, x, y)

        var hovered: HoveredResult?
        var hoveredTarget: Element?

        if name != .mouseup || !isOutside {
            // Find hover again to avoid click event is dispatched manually. Or click is triggered without mouseover
            hovered = self.findHover(x, y)
            hoveredTarget = hovered!.target
        }

        if name == .mousedown {
            self._downEl = hoveredTarget
            self._downPoint = VectorArray(event.zrX ?? 0, event.zrY ?? 0)
            // In case click triggered before mouseup
            self._upEl = hoveredTarget
        }
        else if name == .mouseup {
            self._upEl = hoveredTarget
        }
        else if name == .click {
            if self._downEl !== self._upEl
                // Original click event is triggered on the whole canvas element,
                // including the case that `mousedown` - `mousemove` - `mouseup`,
                // which should be filtered, otherwise it will bring trouble to
                // pan and zoom.
                || self._downPoint == nil
                // Arbitrary value
                || vector.dist(self._downPoint!, VectorArray(event.zrX ?? 0, event.zrY ?? 0)) > 4
            {
                return
            }
            self._downPoint = nil
        }

        // upstream `this.dispatchToElement(hovered, name, event)` — `hovered` may be undefined when
        //   `mouseup` outside; the `|| {}` guard (moved here, see dispatchToElement) supplies an
        //   empty HoveredResult.
        self.dispatchToElement(hovered ?? HoveredResult(), name, event)
    }

    private func callHandler(_ name: String, _ event: ZRRawEvent) {
        switch name {
        case "mousemove": self.mousemove(event)
        case "mouseout": self.mouseout(event)
        case "click": self.click(event)
        case "mousedown": self.mousedown(event)
        case "mouseup": self.mouseup(event)
        case "mousewheel": self.mousewheel(event)
        case "dblclick": self.dblclick(event)
        case "contextmenu": self.contextmenu(event)
        default: break
        }
    }

    // ---- Eventful mixin forwarding (upstream `class Handler extends Eventful`) ----
    // Forwards Eventful's public event surface to the composed `_eventful`, mirroring Element/ZRender.
    // The handler `ctx` defaults to the Handler (`context ?? self`), matching `ctx: context || this`.

    @discardableResult
    public func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> Eventful {
        return self._eventful.on(event, handler, context ?? self)
    }

    @discardableResult
    public func on(_ event: String, _ query: EventQuery?, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> Eventful {
        return self._eventful.on(event, query, handler, context ?? self)
    }

    @discardableResult
    public func off(_ eventType: String? = nil, _ handler: EventCallback? = nil) -> Eventful {
        return self._eventful.off(eventType, handler)
    }

    @discardableResult
    public func trigger(_ eventType: String, _ args: Any?...) -> Eventful {
        // Same variadic-splat limitation as Element.trigger; forward by arg count. Handler dispatch
        //   only ever carries a single eventPacket, so 0/1/2 covers every path.
        switch args.count {
        case 0:
            return self._eventful.trigger(eventType)
        case 1:
            return self._eventful.trigger(eventType, args[0])
        case 2:
            return self._eventful.trigger(eventType, args[0], args[1])
        default:
            return self._eventful.trigger(eventType, args[0], args[1], args[2])
        }
    }

    public func isSilent(_ eventName: String) -> Bool {
        return self._eventful.isSilent(eventName)
    }
}

private func isHover(_ displayable: Displayable, _ x: Double, _ y: Double) -> IsHoverResult {
    // displayable[displayable.rectHover ? 'rectContain' : 'contain'](x, y)
    if (displayable.rectHover ? displayable.rectContain(x, y) : displayable.contain(x, y)) {
        var el: Element? = displayable
        var isSilent = false
        var ignoreClip = false
        while let cur = el {
            // Ignore clip on any ancestors.
            if cur.ignoreClip {
                ignoreClip = true
            }
            if !ignoreClip {
                let clipPath = cur.getClipPath()
                // If clipped by ancestor.
                // FIXME: If clipPath has neither stroke nor fill,
                // el.clipPath.contain(x, y) will always return false.
                if let clipPath = clipPath, !clipPath.contain(x, y) {
                    return .false
                }
            }
            if cur.silent {
                isSilent = true
            }
            // Consider when el is textContent, also need to be silent
            // if any of its host el and its ancestors is silent.
            let hostEl = cur.__hostTarget
            el = hostEl != nil ? (cur.ignoreHostSilent ? nil : hostEl) : (cur.parent as? Element)
        }
        return isSilent ? .silent : .true
    }

    return .false
}

private func setHoverTarget(
    _ list: [Displayable],
    _ out: HoveredResult,
    _ x: Double,
    _ y: Double,
    _ exclude: Displayable?
) {
    var i = list.count - 1
    while i >= 0 {
        let el = list[i]
        // upstream folds the `hoverCheckResult = isHover(...)` assignment into the `if` condition;
        //   unrolled here (isHover is only evaluated when `el !== exclude && !el.ignore`).
        if el !== exclude
            // getDisplayList may include ignored item in VML mode
            && !el.ignore {
            let hoverCheckResult = isHover(el, x, y)
            if hoverCheckResult != .false {
                if out.topTarget == nil { out.topTarget = el }
                if hoverCheckResult != .silent {   // hoverCheckResult !== SILENT
                    out.target = el
                    break
                }
            }
        }
        i -= 1
    }
}

/**
 * See [DRAG_OUTSIDE].
 */
private func isOutsideBoundary(_ handlerInstance: Handler, _ x: Double, _ y: Double) -> Bool {
    let painter = handlerInstance.painter!
    return x < 0 || x > painter.getWidth() || y < 0 || y > painter.getHeight()
}

// export default Handler;
