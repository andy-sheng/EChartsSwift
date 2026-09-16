// Ported from zrender/src/core/event.ts — keep in sync with upstream
//
// Utilities for mouse or touch events.
//
// Upstream is a free-function module imported as `import * as eventTool from './core/event'`,
// so per CONVENTIONS §2 it becomes a caseless `enum eventTool` namespace; call sites stay
// `eventTool.normalizeEvent(...)` etc.
//
// This is the renderer-agnostic event layer: the coordinate-normalization MATH is ported
// faithfully. The BROWSER-specific DOM bits (actual `addEventListener` on a DOM node,
// `getBoundingClientRect`, `window.event`, `dom.ts`'s `isCanvasEl`/`transformCoordWithViewport`)
// have no native equivalent and are marked `// note: provided by the native UIKit bridge`.

import Foundation

// upstream: import Eventful from './Eventful';
// upstream: import env from './env';
// upstream: import { ZRRawEvent } from './types';
// upstream: import {isCanvasEl, transformCoordWithViewport} from './dom';

// ---------------------------------------------------------------------------
// Native-bridge seam types (DOM stand-ins).
// ---------------------------------------------------------------------------
// These model the shape of the DOM objects that upstream's math reads. On iOS the concrete
// instances are produced by the hand-written UIKit bridge (the replacement for
// dom/HandlerProxy.ts) and fed into these helpers.

// provided by the native UIKit bridge.
// upstream type union `ZRRawEvent | FirefoxMouseEvent | Touch` — the common set of
// coordinate fields read by `clientToLocal`. `layerX`/`layerY` are the `FirefoxMouseEvent`
// fields; `offsetX`/`offsetY` are the `MouseEvent` fields (Optional — they drive the null
// checks in `clientToLocal`); `clientX`/`clientY` are always present on `MouseEvent`/`Touch`.
public protocol PointerLike {
    var layerX: Double? { get }     // FirefoxMouseEvent
    var layerY: Double? { get }     // FirefoxMouseEvent
    var offsetX: Double? { get }
    var offsetY: Double? { get }
    var clientX: Double { get }
    var clientY: Double { get }
}

// upstream: a DOM `Touch` is one of the inputs to `clientToLocal`. Reuse the native-seam
// `Touch` (zrender/src/core/GestureMgr.ts) and expose the `PointerLike` coordinate surface;
// a Touch has no `offsetX`/`layerX`, so those read as nil.
extension Touch: PointerLike {
    public var layerX: Double? { nil }
    public var layerY: Double? { nil }
    public var offsetX: Double? { nil }
    public var offsetY: Double? { nil }
}

// provided by the native UIKit bridge — models a DOM `EventTarget`
// (`HTMLElement | HTMLDocument`) for add/removeEventListener.
public protocol DOMEventTarget: AnyObject {
    func addEventListener(_ name: String, _ handler: @escaping EventListener, _ opt: EventListenerOptions?)
    func removeEventListener(_ name: String, _ handler: @escaping EventListener, _ opt: EventListenerOptions?)
}

// provided by the native UIKit bridge — models a DOM `HTMLElement`.
public protocol HTMLElement: DOMEventTarget {
    func getBoundingClientRect() -> ClientRect?
    var nodeName: String { get }
}

// upstream: DOMRect-ish result of `getBoundingClientRect()`.
public struct ClientRect {
    public var left: Double
    public var top: Double
    public var width: Double
    public var height: Double
    public init(left: Double, top: Double, width: Double, height: Double) {
        self.left = left; self.top = top; self.width = width; self.height = height
    }
}

// upstream: `ZRRawEvent` (= MouseEvent|TouchEvent|PointerEvent & ZREventProperties).
// The native UIKit bridge populates one of these per gesture and passes it through
// `normalizeEvent`. The `zr*` fields are the zrender-extended properties (see types.ts
// `ZREventProperties`); they are Optional here so the `e.zrX != null` short-circuit in
// `normalizeEvent` ports faithfully.
// provided by the native UIKit bridge.
public final class ZRRawEvent: PointerLike {
    // raw event identity
    public var type: String?

    // MouseEvent coords
    public var offsetX: Double?
    public var offsetY: Double?
    // clientX/clientY are always present on a DOM MouseEvent/Touch (non-optional, default 0).
    public var clientX: Double = 0
    public var clientY: Double = 0
    // FirefoxMouseEvent coords
    public var layerX: Double?
    public var layerY: Double?

    // mouse button / wheel
    public var button: Double?
    public var which: Double?
    public var wheelDelta: Double?
    public var detail: Double?
    public var deltaX: Double?
    public var deltaY: Double?

    // modifier keys (DOM MouseEvent.shiftKey/ctrlKey/altKey). Consumed by
    //   echarts/src/component/helper/RoamController.ts isAvailableBehavior (~line 585).
    //   Populated per gesture by the native UIKit bridge. // note: provided by the bridge.
    public var shiftKey: Bool = false
    public var ctrlKey: Bool = false
    public var altKey: Bool = false

    // touch lists
    public var targetTouches: [Touch]?
    public var changedTouches: [Touch]?

    // zrender-extended props (ZREventProperties)
    public var zrX: Double?
    public var zrY: Double?
    public var zrDelta: Double?
    // 'no_globalout' means: do not trigger "globalout"; 'only_globalout' means: only trigger
    //   "globalout". Read by `Handler.mouseout`. upstream: ZREventProperties.zrEventControl.
    public var zrEventControl: String?
    public var zrByTouch: Bool = false

    // ZRPinchEvent fields. Swift has no untagged union, so `ZRRawEvent` collapses the upstream
    //   `ZRRawMouseEvent | ZRRawTouchEvent | ZRRawPointerEvent` union AND the `ZRPinchEvent`
    //   intersection (these are written by `GestureMgr`'s pinch recognizer and read by
    //   `Handler.makeEventPacket`). // note: provided by the native UIKit bridge.
    public var gestureEvent: String?
    public var pinchX: Double?
    public var pinchY: Double?
    public var pinchScale: Double?
    // ZRRawTouchEvent: the live touch list (distinct from targetTouches/changedTouches).
    public var touches: [Touch]?

    // bubbling control
    public var cancelBubble: Bool = false

    // provided by the native UIKit bridge — DOM `preventDefault`/`stopPropagation`.
    public var onPreventDefault: (() -> Void)?
    public var onStopPropagation: (() -> Void)?
    public func preventDefault() { onPreventDefault?() }
    public func stopPropagation() { onStopPropagation?() }

    public init() {}
}

// upstream: `addEventListener`'s third param is `boolean | AddEventListenerOptions`.
public struct EventListenerOptions {
    public var capture: Bool?
    public var passive: Bool?
    public init(capture: Bool? = nil, passive: Bool? = nil) {
        self.capture = capture
        self.passive = passive
    }
}

// upstream: the DOM event-listener callback.
public typealias EventListener = (ZRRawEvent) -> Void

// upstream: `clientToLocal`'s `out: {zrX?: number, zrY?: number}`.
// Value type; `clientToLocal`/`calculateZrXY` are value-returning per CONVENTIONS §3
// (no out-param mutation).
public struct ZrXY {
    public var zrX: Double?
    public var zrY: Double?
    public init(zrX: Double? = nil, zrY: Double? = nil) {
        self.zrX = zrX
        self.zrY = zrY
    }
}

// upstream: `isMiddleOrRightButtonOnMouseUpDown(e: { which: number })`.
public protocol HasWhich {
    var which: Double { get }
}

public enum eventTool {   // upstream alias: `import * as eventTool from './core/event'`

    static let MOUSE_EVENT_REG: NSRegularExpression =
        // /^(?:mouse|pointer|contextmenu|drag|drop)|click/
        try! NSRegularExpression(pattern: "^(?:mouse|pointer|contextmenu|drag|drop)|click")

    // shared scratch array used by `transformCoordWithViewport`; that helper is
    // provided by the native UIKit bridge, so this is retained only for diffability.
    static var _calcOut: [Double] = []

    static let firefoxNotSupportOffsetXY: Bool = env.browser.firefox
        // use offsetX/offsetY for Firefox >= 39
        // PENDING: consider Firefox for Android and Firefox OS? >= 43
        && (Double((env.browser.version ?? "0").split(separator: ".").first.map(String.init) ?? "0") ?? 0) < 39

    // type FirefoxMouseEvent = { layerX: number, layerY: number }
    // (modeled by `PointerLike.layerX`/`layerY`.)

    /**
     * Get the `zrX` and `zrY`, which are relative to the top-left of
     * the input `el`.
     * CSS transform (2D & 3D) is supported.
     *
     * The strategy to fetch the coords:
     * + If `calculate` is not set as `true`, users of this method should
     * ensure that `el` is the same or the same size & location as `e.target`.
     * Otherwise the result coords are probably not expected. Because we
     * firstly try to get coords from e.offsetX/e.offsetY.
     * + If `calculate` is set as `true`, the input `el` can be any element
     * and we force to calculate the coords based on `el`.
     * + The input `el` should be positionable (not position:static).
     *
     * The force `calculate` can be used in case like:
     * When mousemove event triggered on ec tooltip, `e.target` is not `el`(zr painter.dom).
     *
     * @param  el DOM element.
     * @param  e Mouse event or touch event.
     * @param  out Get `out.zrX` and `out.zrY` as the result.
     * @param  calculate Whether to force calculate
     *        the coordinates but not use ones provided by browser.
     */
    @discardableResult
    public static func clientToLocal(
        _ el: HTMLElement,
        _ e: PointerLike,
        _ out: ZrXY,
        _ calculate: Bool? = nil
    ) -> ZrXY {
        var out = out   // out = out || {}

        // According to the W3C Working Draft, offsetX and offsetY should be relative
        // to the padding edge of the target element. The only browser using this convention
        // is IE. Webkit uses the border edge, Opera uses the content edge, and FireFox does
        // not support the properties.
        // (see http://www.jacklmoore.com/notes/mouse-position/)
        // In zr painter.dom, padding edge equals to border edge.
        if calculate == true {
            out = calculateZrXY(el, e, out)
        }
        // Caution: In FireFox, layerX/layerY Mouse position relative to the closest positioned
        // ancestor element, so we should make sure el is positioned (e.g., not position:static).
        // BTW1, Webkit don't return the same results as FF in non-simple cases (like add
        // zoom-factor, overflow / opacity layers, transforms ...)
        // BTW2, (ev.offsetY || ev.pageY - $(ev.target).offset().top) is not correct in preserve-3d.
        // <https://bugs.jquery.com/ticket/8523#comment:14>
        // BTW3, In ff, offsetX/offsetY is always 0.
        else if firefoxNotSupportOffsetXY
            && e.layerX != nil
            && e.layerX != e.offsetX {
            out.zrX = e.layerX
            out.zrY = e.layerY
        }
        // For IE6+, chrome, safari, opera, firefox >= 39
        else if e.offsetX != nil {
            out.zrX = e.offsetX
            out.zrY = e.offsetY
        }
        // For some other device, e.g., IOS safari.
        else {
            out = calculateZrXY(el, e, out)
        }

        return out
    }

    // upstream casts `e` to `ZRRawEvent` but only reads `clientX`/`clientY`, both on `PointerLike`.
    static func calculateZrXY(
        _ el: HTMLElement,
        _ e: PointerLike,
        _ out: ZrXY
    ) -> ZrXY {
        var out = out
        // BlackBerry 5, iOS 3 (original iPhone) don't have getBoundingRect.
        // upstream also feature-detects `el.getBoundingClientRect`; on iOS
        // `env.domSupported` is false, so the native bridge supplies these coords instead.
        if env.domSupported {
            let ex = e.clientX     // (e as MouseEvent).clientX
            let ey = e.clientY     // (e as MouseEvent).clientY

            if isCanvasEl(el) {
                // Original approach, which do not support CSS transform.
                // marker can not be locationed in a canvas container
                // (getBoundingClientRect is always 0). We do not support
                // that input a pre-created canvas to zr while using css
                // transform in iOS.
                if let box = el.getBoundingClientRect() {
                    out.zrX = ex - box.left
                    out.zrY = ey - box.top
                    return out
                }
            }
            else {
                if let calc = transformCoordWithViewport(el, ex, ey) {
                    out.zrX = calc[0]
                    out.zrY = calc[1]
                    return out
                }
            }
        }
        out.zrX = 0
        out.zrY = 0   // out.zrX = out.zrY = 0
        return out
    }

    // from zrender/src/core/dom.ts — provided by the native UIKit bridge.
    // `isCanvasEl(el)` returns `el.nodeName.toUpperCase() === 'CANVAS'`.
    static func isCanvasEl(_ el: HTMLElement) -> Bool {
        return el.nodeName.uppercased() == "CANVAS"
    }

    // from zrender/src/core/dom.ts (CSS-transform viewport mapping) — provided by
    // the native UIKit bridge. Upstream writes into `out` and returns a Bool; here it is
    // value-returning (returns the `[x, y]` pair, or nil when transform is unavailable —
    // equivalent to upstream returning `false`).
    static func transformCoordWithViewport(_ el: HTMLElement, _ inX: Double, _ inY: Double) -> [Double]? {
        return nil
    }

    /**
     * Find native event compat for legency IE.
     * Should be called at the begining of a native event listener.
     *
     * @param e Mouse event or touch event or pointer event.
     *        For lagency IE, we use `window.event` is used.
     * @return The native event.
     */
    public static func getNativeEvent(_ e: ZRRawEvent) -> ZRRawEvent {
        // upstream falls back to `window.event` for legacy IE — no `window` on iOS.
        return e
    }

    /**
     * Normalize the coordinates of the input event.
     *
     * Get the `e.zrX` and `e.zrY`, which are relative to the top-left of
     * the input `el`.
     * Get `e.zrDelta` if using mouse wheel.
     * Get `e.which`, see the comment inside this function.
     *
     * Do not calculate repeatly if `zrX` and `zrY` already exist.
     *
     * Notice: see comments in `clientToLocal`. check the relationship
     * between the result coords and the parameters `el` and `calculate`.
     *
     * @param el DOM element.
     * @param e See `getNativeEvent`.
     * @param calculate Whether to force calculate
     *        the coordinates but not use ones provided by browser.
     * @return The normalized native UIEvent.
     */
    @discardableResult
    public static func normalizeEvent(
        _ el: HTMLElement,
        _ e: ZRRawEvent,
        _ calculate: Bool? = nil
    ) -> ZRRawEvent {

        let e = getNativeEvent(e)

        if e.zrX != nil {
            return e
        }

        let eventType = e.type
        let isTouch = (eventType != nil) && eventType!.contains("touch")

        if !isTouch {
            // out === e: `clientToLocal` is value-returning (CONVENTIONS §3), so seed `out`
            // from `e` and write the result back onto `e`.
            let out = clientToLocal(el, e, ZrXY(zrX: e.zrX, zrY: e.zrY), calculate)
            e.zrX = out.zrX
            e.zrY = out.zrY
            let wheelDelta = getWheelDeltaMayPolyfill(e)
            // FIXME: IE8- has "wheelDeta" in event "mousewheel" but hat different value (120 times)
            // with Chrome and Safari. It's not correct for zrender event but we left it as it was.
            if let wheelDelta = wheelDelta, wheelDelta != 0 {
                e.zrDelta = wheelDelta / 120
            }
            else {
                e.zrDelta = -(e.detail ?? 0) / 3
            }
        }
        else {
            let touch = eventType != "touchend"
                ? e.targetTouches?.first
                : e.changedTouches?.first
            if let touch = touch {
                let out = clientToLocal(el, touch, ZrXY(zrX: e.zrX, zrY: e.zrY), calculate)
                e.zrX = out.zrX
                e.zrY = out.zrY
            }
        }

        // Add which for click: 1 === left; 2 === middle; 3 === right; otherwise: 0;
        // See jQuery: https://github.com/jquery/jquery/blob/master/src/event.js
        // If e.which has been defined, it may be readonly,
        // see: https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/which
        let button = e.button
        if e.which == nil, let bd = button, let t = e.type, mouseEventRegTest(t) {
            let b = Int(bd)
            e.which = Double((b & 1) != 0 ? 1 : ((b & 2) != 0 ? 3 : ((b & 4) != 0 ? 2 : 0)))
        }
        // [Caution]: `e.which` from browser is not always reliable. For example,
        // when press left button and `mousemove (pointermove)` in Edge, the `e.which`
        // is 65536 and the `e.button` is -1. But the `mouseup (pointerup)` and
        // `mousedown (pointerdown)` is the same as Chrome does.

        return e
    }

    static func mouseEventRegTest(_ s: String) -> Bool {
        return MOUSE_EVENT_REG.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    // TODO: also provide prop "deltaX" "deltaY" in zrender "mousewheel" event.
    static func getWheelDeltaMayPolyfill(_ e: ZRRawEvent) -> Double? {
        // Although event "wheel" do not has the prop "wheelDelta" in spec,
        // agent like Chrome and Safari still provide "wheelDelta" like
        // event "mousewheel" did (perhaps for backward compat).
        // Since zrender has been using "wheelDeta" in zrender event "mousewheel".
        // we currently do not break it.
        // But event "wheel" in firefox do not has "wheelDelta", so we calculate
        // "wheelDeta" from "deltaX", "deltaY" (which is the props in spec).
        let rawWheelDelta = e.wheelDelta
        // Theroetically `e.wheelDelta` won't be 0 unless some day it has been deprecated
        // by agent like Chrome or Safari. So we also calculate it if rawWheelDelta is 0.
        if let rawWheelDelta = rawWheelDelta, rawWheelDelta != 0 {
            return rawWheelDelta
        }

        let deltaX = e.deltaX
        let deltaY = e.deltaY
        if deltaX == nil || deltaY == nil {
            return rawWheelDelta
        }

        // Test in Chrome and Safari (MacOS):
        // The sign is corrent.
        // The abs value is 99% corrent (inconsist case only like 62~63, 125~126 ...)
        let dx = deltaX!
        let dy = deltaY!
        let delta = dy != 0 ? Swift.abs(dy) : Swift.abs(dx)
        let sign: Double = dy > 0 ? -1
            : dy < 0 ? 1
            : dx > 0 ? -1
            : 1
        return 3 * delta * sign
    }

    /**
     * @param  el
     * @param  name
     * @param  handler
     * @param  opt If boolean, means `opt.capture`
     * @param  opt.capture
     * @param  opt.passive
     */
    public static func addEventListener(
        _ el: DOMEventTarget,
        _ name: String,
        _ handler: @escaping EventListener,
        _ opt: EventListenerOptions? = nil
    ) {
        // Reproduct the console warning:
        // [Violation] Added non-passive event listener to a scroll-blocking <some> event.
        // Consider marking event handler as 'passive' to make the page more responsive.
        // Just set console log level: verbose in chrome dev tool.
        // then the warning log will be printed when addEventListener called.
        // See https://github.com/WICG/EventListenerOptions/blob/gh-pages/explainer.md
        // We have not yet found a neat way to using passive. Because in zrender the dom event
        // listener delegate all of the upper events of element. Some of those events need
        // to prevent default. For example, the feature `preventDefaultMouseMove` of echarts.
        // Before passive can be adopted, these issues should be considered:
        // (1) Whether and how a zrender user specifies an event listener passive. And by default,
        // passive or not.
        // (2) How to tread that some zrender event listener is passive, and some is not. If
        // we use other way but not preventDefault of mousewheel and touchmove, browser
        // compatibility should be handled.

        // provided by the native UIKit bridge — actual DOM `addEventListener`
        // is replaced by the hand-written UIKit gesture/touch bridge.
        el.addEventListener(name, handler, opt)
    }

    /**
     * Parameter are the same as `addEventListener`.
     *
     * Notice that if a listener is registered twice, one with capture and one without,
     * remove each one separately. Removal of a capturing listener does not affect a
     * non-capturing version of the same listener, and vice versa.
     */
    public static func removeEventListener(
        _ el: DOMEventTarget,
        _ name: String,
        _ handler: @escaping EventListener,
        _ opt: EventListenerOptions? = nil
    ) {
        // provided by the native UIKit bridge — actual DOM `removeEventListener`.
        el.removeEventListener(name, handler, opt)
    }

    /**
     * preventDefault and stopPropagation.
     * Notice: do not use this method in zrender. It can only be
     * used by upper applications if necessary.
     *
     * @param {Event} e A mouse or touch event.
     */
    public static let stop: (ZRRawEvent) -> Void = { e in
        e.preventDefault()      // provided by the native UIKit bridge
        e.stopPropagation()     // provided by the native UIKit bridge
        e.cancelBubble = true
    }

    /**
     * This method only works for mouseup and mousedown. The functionality is restricted
     * for fault tolerance, See the `e.which` compatibility above.
     *
     * params can be MouseEvent or ElementEvent
     */
    public static func isMiddleOrRightButtonOnMouseUpDown(_ e: HasWhich) -> Bool {
        return e.which == 2 || e.which == 3
    }
}

// For backward compatibility
// upstream: export {Eventful as Dispatcher};
public typealias Dispatcher = Eventful
