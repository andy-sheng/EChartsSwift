// Ported from zrender/src/zrender.ts — keep in sync with upstream
//
/*!
* ZRender, a high performance 2d drawing library.
*
* Copyright (c) 2013, Baidu Inc.
* All rights reserved.
*
* LICENSE
* https://github.com/ecomfe/zrender/blob/master/LICENSE
*/
//
// PHASE-2 (host facade) PORT. This is the `ZRender` host facade that ties `Storage` + `Painter`
// + the `Element` tree together. The build/render lifecycle (add / remove / refresh / resize /
// dispose) and the still-frame / flush bookkeeping are translated faithfully. The pieces that
// belong to deferred seams are STUBBED with `// PORT-NOTE` (faithful signatures):
//
// TRANSLATED (host lifecycle):
//   - class ZRender; constructor wiring of storage + painter (+ the real Animation clock:
//     ZRender owns an `Animation`, its `stage.update` hook drives `_flush`, `refresh`/`wakeUp`
//     start the loop, `_refresh` calls `animation.update`, and `dispose` stops it)
//   - add / remove / clear / dispose; refresh / refreshImmediately / _refresh / flush / _flush
//   - setBackgroundColor / getBackgroundColor / setDarkMode / isDarkMode / isDarkMode() helper
//   - resize / getWidth / getHeight; wakeUp / setSleepAfterStill; refreshHover(Immediately)
//   - on / off / trigger (routed through a local Eventful until Handler lands — see below)
//   - module-level: instances registry, init / dispose / disposeAll / getInstance,
//     registerPainter / painterCtors, SSR-data getter hooks, version
//
// PARTIALLY-STUBBED seams (PORT-NOTE — some have since landed; see the per-line notes below):
//   - Handler / HandlerProxy (the input / hit-dispatch seam, CONVENTIONS §9) — not ported.
//     `handler.*` calls (resize / setCursorStyle / findHover / on / off / trigger / dispose) are
//     stubbed; ZRender events are routed through a local `Eventful` (Handler extends Eventful
//     upstream) so on/off/trigger keep a real surface.
//   - Animation (animation/Animation.ts) — ported (Phase 3) at Animation/Animation.swift, along
//     with `getTime()`. The frame tick (requestAnimationFrame) is host-supplied (CADisplayLink).
//   - The browser `painterCtors` registry + DOM-ctor painter construction. Natively there is no
//     DOM, so the painter is INJECTED into the constructor (documented deviation). `registerPainter`
//     / `painterCtors` are kept for provenance.
//   - configLayer (forwarded to painter), useCoarsePointer / pointerSize (honored) are wired;
//     useDirtyRect is stored on opts but the dirty-rect render optimization itself is a
//     canvas-layer feature — PORT-NOTE (deferred): requires the CanvasLayer dirty-rect painter.

import Foundation

// upstream imports (resolved to the ported modules):
// import env from './core/env';                                  → env
// import * as zrUtil from './core/util';                         → util.*
// import Handler from './Handler';                               → Handler.swift (`Handler`, ported)
// import Storage from './Storage';                               → Storage
// import {PainterBase} from './PainterBase';                     → PainterBase protocol (below)
// import Animation, {getTime} from './animation/Animation';      → Animation/Animation.swift
// import HandlerProxy from './dom/HandlerProxy';                 → PORT-NOTE: DOM seam, not ported
// import Element, { ElementEventCallback } from './Element';     → Element
// import { Dictionary, ElementEventName, RenderedEvent, WithThisType } from './core/types';
// import { LayerConfig } from './canvas/Layer';                  → `LayerConfig` (ported below in this file)
// import { GradientObject } from './graphic/Gradient';           → Gradient
// import { PatternObject } from './graphic/Pattern';             → Pattern
// import { EventCallback } from './core/Eventful';               → EventCallback
// import Displayable from './graphic/Displayable';               → Displayable
// import { lum } from './tool/color';                            → color.lum
// import { DARK_MODE_THRESHOLD } from './config';                → DARK_MODE_THRESHOLD
// import Group from './graphic/Group';                           → Group
// import { CanvasPainterRefreshOpt } from './canvas/Painter';    → CanvasPainterRefreshOpt (below)

// PORT-NOTE: upstream `type PainterBaseCtor = { new(dom, storage, ...args): PainterBase }`. The
//   browser builds painters from a DOM ctor; natively the painter is injected (see constructor).
//   The registry is kept for provenance but is not exercised on the native path.
public typealias PainterBaseCtor = (Any?, Storage, ZRenderInitOpt?, Double) -> PainterBase

fileprivate var painterCtors: [String: PainterBaseCtor] = [:]

fileprivate var instances: [Double: ZRender] = [:]

fileprivate func delInstance(_ id: Double) {
    instances[id] = nil
}

// upstream: isDarkMode(backgroundColor: string | GradientObject | PatternObject): boolean
//   The union is modeled as `Any?` (CONVENTIONS §6) — the painter/background color seam carries
//   either a CSS string or a Gradient/Pattern object.
fileprivate func isDarkMode(_ backgroundColor: Any?) -> Bool {
    guard let backgroundColor = backgroundColor else {
        return false
    }
    if let s = backgroundColor as? String {
        return color.lum(s, 1) < DARK_MODE_THRESHOLD
    }
    else if let grad = backgroundColor as? Gradient {  // (backgroundColor as GradientObject).colorStops
        let colorStops = grad.colorStops
        var totalLum: Double = 0
        let len = colorStops.count
        // Simply do the math of average the color. Not consider the offset
        for i in 0..<len {
            totalLum += color.lum(colorStops[i].color, 1)
        }
        totalLum /= Double(len)

        return totalLum < DARK_MODE_THRESHOLD
    }
    // Can't determine
    return false
}

// NOTE (CONVENTIONS §2): upstream `class ZRender`. ZRender is not subclassed, so it is a
//   `final class`. `interface ZRenderType extends ZRender` → `typealias ZRenderType = ZRender`
//   (declared at the bottom of this file); `Element.__zr` is the real `ZRender`.
public final class ZRender {
    /// Not necessary if using SSR painter like svg-ssr
    // upstream: dom?: HTMLElement → no DOM natively (PORT-NOTE: input/host seam).
    public var dom: Any?

    public var id: Double

    // upstream non-optional; nulled in `dispose`. Implicitly-unwrapped to mirror upstream while
    //   allowing the dispose-time clear (CONVENTIONS §6).
    public var storage: Storage!
    public var painter: PainterBase!
    // upstream: handler: Handler. PHASE-4 (interaction): the real `Handler` is now constructed and
    //   owned here. `on`/`off`/`trigger`/`findHover`/`setCursorStyle` route through it (Handler
    //   `extends Eventful`, so the event surface stays real). Its `HandlerProxyInterface` is the
    //   native UIKit bridge (`NativeHandlerProxy` in Sources/NativePainter), injected through `init`,
    //   or `EmptyProxy` when headless (CONVENTIONS §9).
    public var handler: Handler!
    public var animation: Animation!

    private var _sleepAfterStill: Double = 10

    private var _stillFrameAccum: Double = 0

    private var _needsRefresh = true
    // true can lead to creating a hover layer. Do not set true unless required.
    private var _needsRefreshHover = false
    private var _disposed: Bool = false

    /// Whether `dispose()` has run. Native-only read accessor (no upstream analogue): a deferred
    /// closure that outlives the host view (e.g. a `DispatchQueue.asyncAfter` loop holding a strong
    /// element chain, which strongly back-references this zr via `Element.__zr`) can use this to stop
    /// rescheduling once the zr is torn down, instead of poking a disposed animation clock.
    public var isDisposed: Bool { return self._disposed }
    /// If theme is dark mode. It will determine the color strategy for labels.
    private var _darkMode = false

    private var _backgroundColor: Any?   // upstream: string | GradientObject | PatternObject

    // upstream: constructor(id: number, dom?: HTMLElement, opts?: ZRenderInitOpt).
    // PORT-NOTE (deviation): the painter is INJECTED rather than built from `painterCtors[rendererType]`
    //   — there is no DOM ctor natively. `opts.renderer` / `painterCtors` are kept for provenance.
    //   The `proxy` (HandlerProxyInterface) is likewise INJECTED — natively it is the hand-written
    //   UIKit bridge (`NativeHandlerProxy`); nil ⇒ Handler falls back to `EmptyProxy` (headless).
    public init(_ id: Double, _ dom: Any? = nil, _ opts: ZRenderInitOpt? = nil, painter: PainterBase, proxy: HandlerProxyInterface? = nil) {
        var opts = opts ?? ZRenderInitOpt()

        /**
         * @type {HTMLDomElement}
         */
        self.dom = dom

        self.id = id

        let storage = Storage()

        // upstream resolves `rendererType` against the painterCtors registry; on the native path
        //   the painter is supplied directly. Registry lookup kept as a no-op for provenance.
        _ = opts.renderer

        opts.useDirtyRect = opts.useDirtyRect == nil
            ? false
            : opts.useDirtyRect

        // const painter = new painterCtors[rendererType](dom, storage, opts, id);
        // const ssrMode = opts.ssr || painter.ssrOnly;
        let ssrMode = (opts.ssr ?? false) || painter.ssrOnly

        self.storage = storage
        self.painter = painter

        // upstream: const handlerProxy = (!env.node && !env.worker && !ssrMode) ? new HandlerProxy(...) : null;
        //   Natively the proxy (the UIKit bridge) is INJECTED. In SSR/headless mode no proxy is wired
        //   (Handler then uses `EmptyProxy`), matching the upstream `ssrMode` guard.
        let handlerProxy: HandlerProxyInterface? = ssrMode ? nil : proxy

        // upstream: useCoarsePointer / pointerSize (touch input — enlarge hit area).
        //   const useCoarsePointer = opts.useCoarsePointer;
        //   const usePointerSize = (useCoarsePointer == null || useCoarsePointer === 'auto')
        //       ? env.touchEventsSupported : !!useCoarsePointer;
        //   const defaultPointerSize = 44;
        //   let pointerSize;
        //   if (usePointerSize) { pointerSize = zrUtil.retrieve2(opts.pointerSize, defaultPointerSize); }
        // `useCoarsePointer` is modeled as `Bool?` — the `'auto'` string arm folds into the `nil`
        //   branch (it behaves identically to `nil`, so no runtime behavior is lost). When `nil`
        //   (or 'auto'), defaulting follows `env.touchEventsSupported` (true on the native touch
        //   path), so the native default enlarges the hit area to `defaultPointerSize` (44).
        let useCoarsePointer = opts.useCoarsePointer
        let usePointerSize = (useCoarsePointer == nil) ? env.touchEventsSupported : useCoarsePointer!
        let defaultPointerSize: Double = 44
        var pointerSize: Double? = nil
        if usePointerSize {
            pointerSize = util.retrieve2(opts.pointerSize, defaultPointerSize)
        }

        // upstream: this.handler = new Handler(storage, painter, handlerProxy, painter.root, pointerSize);
        //   `painter.root` (the DOM viewport root) is the native host view/layer — passed as nil to
        //   Handler's `painterRoot: HTMLElement?` seam (the proxy owns the real native root).
        self.handler = Handler(storage, painter, handlerProxy, nil, pointerSize)

        self.animation = Animation(AnimationOption(
            stage: Stage(
                update: ssrMode ? nil : { [weak self] in self?._flush(false) }
            )
        ))

        if !ssrMode {
            self.animation.start()
        }
    }

    /// 添加元素
    public func add(_ el: Element?) {
        if self._disposed || el == nil {
            return
        }
        let el = el!
        self.storage.addRoot(el)
        el.addSelfToZr(self)
        self.refresh()
    }

    /// 删除元素
    public func remove(_ el: Element?) {
        if self._disposed || el == nil {
            return
        }
        let el = el!
        self.storage.delRoot(el)
        el.removeSelfFromZr(self)
        self.refresh()
    }

    /// Change configuration of layer
    public func configLayer(_ zLevel: Double, _ config: Any?) {
        if self._disposed {
            return
        }
        // upstream: `this.painter.configLayer?.(zLevel, config)` — forward to the painter, then refresh.
        self.painter.configLayer(zLevel, config)
        self.refresh()
    }

    /// Set background color
    public func setBackgroundColor(_ backgroundColor: Any?) {
        if self._disposed {
            return
        }
        // upstream: `this.painter.setBackgroundColor?.(backgroundColor)` — optional painter hook.
        self.painter.setBackgroundColor(backgroundColor)
        self.refresh()
        self._backgroundColor = backgroundColor
        // module-qualify: the `isDarkMode()` instance method shadows the global helper.
        self._darkMode = ZRenderKit.isDarkMode(backgroundColor)
    }

    public func getBackgroundColor() -> Any? {
        return self._backgroundColor
    }

    /// Force to set dark mode
    public func setDarkMode(_ darkMode: Bool) {
        self._darkMode = darkMode
    }

    public func isDarkMode() -> Bool {
        return self._darkMode
    }

    /// Repaint the canvas immediately
    public func refreshImmediately(_ noAnimationUpdate: Bool? = nil) {
        if self._disposed {
            return
        }
        self._refresh(animUpdate: !(noAnimationUpdate ?? false), refresh: true, refreshHover: false)
    }

    private func _refresh(animUpdate: Bool, refresh: Bool, refreshHover: Bool) {
        if animUpdate {
            // Update animation if refreshImmediately is invoked from outside.
            // Not trigger stage update to call flush again. Which may refresh twice
            self.animation.update(true)
        }

        // Clear needsRefresh ahead to avoid something wrong happens in refresh
        // Or it will cause zrender refreshes again and again.
        self._needsRefresh = false
        self._needsRefreshHover = false
        // upstream: this.painter.refresh({refresh, refreshHover}). The CanvasPainter pulls the
        //   display list from storage internally; natively the painter does not own storage, so
        //   ZRender builds the Storage display list and hands it to the painter (documented seam).
        if refresh {
            let displayList = self.storage.getDisplayList(true)
            self.painter.refresh(displayList)
        }
        // PORT-NOTE: refreshHover → hover-layer painting (Phase 2 hover machinery / painter seam).
        // Avoid trigger zr.refresh in Element#beforeUpdate hook.
        // Hover layer is always refreshed when refreshing normal layers.
        self._needsRefresh = false
        self._needsRefreshHover = false
    }

    /// Mark and repaint the canvas in the next frame of browser
    public func refresh() {
        if self._disposed {
            return
        }

        self._needsRefresh = true
        // Active the animation again.
        self.animation.start()
    }

    /// Perform all refresh
    public func flush() {
        if self._disposed {
            return
        }
        self._flush(true)
    }

    private func _flush(_ animationUpdate: Bool) {
        var triggerRendered = false

        let start = getTime()
        let needsRefresh = self._needsRefresh
        let needsRefreshHover = self._needsRefreshHover

        if needsRefresh || needsRefreshHover {
            triggerRendered = true
            self._refresh(animUpdate: animationUpdate, refresh: needsRefresh, refreshHover: needsRefreshHover)
        }
        let end = getTime()

        if triggerRendered {
            self._stillFrameAccum = 0
            // upstream: this.trigger('rendered', { elapsedTime: end - start } as RenderedEvent)
            let ev = RenderedEvent(elapsedTime: end - start)
            self.trigger("rendered", ev)
        }
        else if self._sleepAfterStill > 0 {
            self._stillFrameAccum += 1
            // Stop the animation after still for 10 frames.
            if self._stillFrameAccum > self._sleepAfterStill {
                self.animation.stop()
            }
        }
    }

    /// Set sleep after still for frames.
    /// Disable auto sleep when it's 0.
    public func setSleepAfterStill(_ stillFramesCount: Double) {
        self._sleepAfterStill = stillFramesCount
    }

    /// Wake up animation loop. But not render.
    public func wakeUp() {
        if self._disposed {
            return
        }
        self.animation.start()
        // Reset the frame count.
        self._stillFrameAccum = 0
    }

    /// Refresh hover in next frame
    public func refreshHover() {
        self._needsRefreshHover = true
    }

    /// @deprecated
    /// Refresh hover immediately
    public func refreshHoverImmediately() {
        if self._disposed {
            return
        }
        self._refresh(animUpdate: false, refresh: false, refreshHover: true)
    }

    /// Resize the canvas.
    /// Should be invoked when container size is changed
    public func resize(_ opts: ZRenderResizeOpt? = nil) {
        if self._disposed {
            return
        }
        let opts = opts ?? ZRenderResizeOpt()
        self.painter.resize(opts.width, opts.height, opts.devicePixelRatio)
        self.handler.resize()
    }

    /// Stop and clear all animation immediately
    public func clearAnimation() {
        if self._disposed {
            return
        }
        self.animation.clear()
    }

    /// Get container width
    public func getWidth() -> Double? {
        if self._disposed {
            return nil
        }
        return self.painter.getWidth()
    }

    /// Get container height
    public func getHeight() -> Double? {
        if self._disposed {
            return nil
        }
        return self.painter.getHeight()
    }

    /// Set default cursor
    /// - cursorStyle: ='default' 例如 crosshair
    public func setCursorStyle(_ cursorStyle: String) {
        if self._disposed {
            return
        }
        self.handler.setCursorStyle(cursorStyle)
    }

    /// Find hovered element
    /// - x, y
    /// - return: {target, topTarget}
    public func findHover(_ x: Double, _ y: Double) -> (target: Displayable?, topTarget: Displayable?)? {
        if self._disposed {
            return nil
        }
        // upstream: return this.handler.findHover(x, y). Handler walks the z-sorted display list
        //   top-down via the ported contain/* hit-testing. HoveredResult.target/topTarget are
        //   widened to `Element?`; every real hover target is a `Displayable` (see Handler.swift).
        let res = self.handler.findHover(x, y, nil)
        return (res.target as? Displayable, res.topTarget as? Displayable)
    }

    /// Bind event
    @discardableResult
    public func on(_ eventName: String, _ eventHandler: @escaping EventCallback, _ context: AnyObject? = nil) -> Self {
        if !self._disposed {
            self.handler.on(eventName, eventHandler, context)
        }
        return self
    }

    /// Bind event, `callAtLast` variant. Upstream reads the flag off the function object
    /// (`handler.zrEventfulCallAtLast`; see `Eventful.on`) — echarts' `_initEvents` sets it on the
    /// chart-event handler so the public chart bus fires AFTER the inner component handlers (tooltip,
    /// brush, …), which may themselves `setOption`/`dispatchAction`. Separate overload (not a defaulted
    /// 4th parameter) so `Handler`'s `on(_:_:_:)` protocol witness stays intact.
    @discardableResult
    public func on(_ eventName: String, _ eventHandler: @escaping EventCallback, _ context: AnyObject?,
                   callAtLast: Bool) -> Self {
        if !self._disposed {
            self.handler.on(eventName, eventHandler, context, callAtLast: callAtLast)
        }
        return self
    }

    /// Unbind event
    /// - eventName: Event name
    /// - eventHandler: Handler function
    public func off(_ eventName: String? = nil, _ eventHandler: EventCallback? = nil) {
        if self._disposed {
            return
        }
        self.handler.off(eventName, eventHandler)
    }

    /// Trigger event manually
    /// - eventName: Event name
    /// - event: Event object
    public func trigger(_ eventName: String, _ event: Any? = nil) {
        if self._disposed {
            return
        }
        self.handler.trigger(eventName, event)
    }

    /// Clear all objects and the canvas.
    public func clear() {
        if self._disposed {
            return
        }
        let roots = self.storage.getRoots()
        for i in 0..<roots.count {
            if roots[i] is Group {
                roots[i].removeSelfFromZr(self)
            }
        }
        self.storage.delAllRoots()
        self.painter.clear()
    }

    /// Dispose self.
    public func dispose() {
        if self._disposed {
            return
        }

        self.animation.stop()

        self.clear()
        self.storage.dispose()
        self.painter.dispose()
        self.handler.dispose()

        self.animation = nil
        self.storage = nil
        self.painter = nil
        self.handler = nil

        self._disposed = true

        delInstance(self.id)
    }
}


public struct ZRenderInitOpt {
    public var renderer: String?    // 'canvas' or 'svg
    public var devicePixelRatio: Double?
    public var width: Double?       // upstream: number | string (10, 10px, 'auto') — PORT-NOTE string
    public var height: Double?      // upstream: number | string
    public var useDirtyRect: Bool?
    public var useCoarsePointer: Bool?  // upstream: 'auto' | boolean — PORT-NOTE 'auto'
    public var pointerSize: Double?
    public var ssr: Bool?   // If enable ssr mode.

    public init() {}
}

// upstream: resize(opts?: { width?, height?, devicePixelRatio? }). Modeled as a struct.
public struct ZRenderResizeOpt {
    public var width: Double?    // upstream: number | string — PORT-NOTE string
    public var height: Double?   // upstream: number | string
    public var devicePixelRatio: Double?

    public init() {}
}

/// Initializing a zrender instance
/// - dom: Not necessary if using SSR painter like svg-ssr
// PORT-NOTE (deviation): the painter is injected (no DOM ctor natively). `init` is a Swift keyword;
//   the free function is named with backticks to keep the upstream name.
@discardableResult
public func `init`(_ dom: Any? = nil, _ opts: ZRenderInitOpt? = nil, painter: PainterBase, proxy: HandlerProxyInterface? = nil) -> ZRender {
    let zr = ZRender(util.guid(), dom, opts, painter: painter, proxy: proxy)
    instances[zr.id] = zr
    return zr
}

/// Dispose zrender instance
public func dispose(_ zr: ZRender) {
    zr.dispose()
}

/// Dispose all zrender instances
public func disposeAll() {
    for (_, zr) in instances {
        zr.dispose()
    }
    instances = [:]
}

/// Get zrender instance by id
public func getInstance(_ id: Double) -> ZRender? {
    return instances[id]
}

public func registerPainter(_ name: String, _ ctor: @escaping PainterBaseCtor) {
    painterCtors[name] = ctor
}

// PORT-NOTE: ElementSSRData / ElementSSRDataGetter — `zrUtil.HashMap<unknown>` SSR-data hooks.
//   HashMap is not ported; modeled with `[String: Any]`.
public typealias ElementSSRData = [String: Any]
public typealias ElementSSRDataGetter = (_ el: Element) -> [String: Any]

fileprivate var ssrDataGetter: ElementSSRDataGetter?

public func getElementSSRData(_ el: Element) -> ElementSSRData? {
    if let getter = ssrDataGetter {
        return getter(el)
    }
    return nil
}

public func registerSSRDataGetter(_ getter: @escaping ElementSSRDataGetter) {
    ssrDataGetter = getter
}

/// @type {string}
public let version = "6.1.0"

// upstream: export interface ZRenderType extends ZRender {};
//   `interface X extends ZRender` is structurally identical to `ZRender`; modeled as a typealias.
//   This REPLACES the forward-declared `ZRenderType` protocol that previously lived in Element.swift.
public typealias ZRenderType = ZRender


// ============================================================================
// PainterBase — the renderer-host seam (CONVENTIONS §9).
//
// upstream `PainterBase.ts` is an interface implemented by CanvasPainter / SVGPainter. Natively the
// implementation is the hand-written `CALayerPainter` (Sources/NativePainter), which conforms to
// this protocol. ZRenderKit cannot import NativePainter (the dependency runs the other way), so the
// protocol is declared here and the concrete painter is INJECTED into `ZRender.init`.
//
// DEVIATION: upstream `refresh()` takes no list — the CanvasPainter pulls `storage.getDisplayList()`
// itself. Natively the painter does not own the storage, so `refresh(_:)` receives the already-built
// display list from `ZRender._refresh` ("build Storage display list -> Painter", per the task brief).
// ============================================================================
/// upstream: LayerConfig — per-zlevel canvas-layer options. The motion-blur subset is modeled here
/// (the native painter is single-layer, so `zLevel` is informational). `clearColor` is omitted.
public struct LayerConfig {
    /// Keep a faded copy of the previous frame instead of clearing → motion-blur trails.
    public var motionBlur: Bool
    /// Fraction of the previous frame retained each frame (e.g. 0.99 → long, slow-fading trails).
    public var lastFrameAlpha: Double
    public init(motionBlur: Bool = false, lastFrameAlpha: Double = 0) {
        self.motionBlur = motionBlur
        self.lastFrameAlpha = lastFrameAlpha
    }
}

public protocol PainterBase: AnyObject {

    /// upstream: type: string ('canvas' | 'svg'). Identifies the backend.
    var type: String { get }

    /// upstream: ssrOnly?: boolean — server-side-render-only painters skip the input/animation loop.
    var ssrOnly: Bool { get }

    /// Repaint the (already flattened + z-sorted) display list. See the DEVIATION note above.
    func refresh(_ displayList: [Displayable])

    /// Resize the drawing surface. upstream width/height are `number | string` (PORT-NOTE string).
    func resize(_ width: Double?, _ height: Double?, _ dpr: Double?)

    /// Clear the surface.
    func clear()

    func getWidth() -> Double

    func getHeight() -> Double

    /// upstream: getViewportRoot(): HTMLElement. The host view/layer the native `HandlerProxy`
    /// observes for input and to which the painter's surface is attached. Modeled as `Any?`
    /// (the native `CALayer` / `UIView` / `NSView`); nil for headless painters.
    func getViewportRoot() -> Any?

    /// upstream: configLayer?(zLevel, config) — optional per-layer config (e.g. motion blur).
    func configLayer(_ zLevel: Double, _ config: Any?)

    /// upstream: setBackgroundColor?(backgroundColor) — optional painter hook.
    func setBackgroundColor(_ backgroundColor: Any?)

    func dispose()
}

// Provide faithful defaults for the optional-ish surface so minimal painters need not implement all.
extension PainterBase {
    public var type: String { return "native" }
    public var ssrOnly: Bool { return false }
    public func getViewportRoot() -> Any? { return nil }
    public func configLayer(_ zLevel: Double, _ config: Any?) {}
    public func setBackgroundColor(_ backgroundColor: Any?) {}
}


// upstream: `getTime()` and the `Animation` class now live in Animation/Animation.swift (Phase 3
//   port). The former type-surface stub here has been deleted.

// upstream: export type CanvasPainterRefreshOpt (refresh / refreshHover booleans). Kept for
//   provenance; the native PainterBase.refresh takes the display list directly (see DEVIATION).
public struct CanvasPainterRefreshOpt {
    public var refresh: Bool?
    public var refreshHover: Bool?
    public init() {}
}
