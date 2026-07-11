// Ported from zrender/src/core/Eventful.ts — keep in sync with upstream

// upstream: import { Dictionary, WithThisType } from './types';
//
// Generic-typing notes (CONVENTIONS §2, §8):
//  - Upstream `Eventful<EvtDef>` is generic purely for TS compile-time event-name /
//    event-param type checking. Swift has no faithful analogue, so the `EvtDef` type
//    parameter is dropped: event names become `String` and event params `[Any?]`.
//    // PORT-NOTE: EvtDef compile-time event typing not modeled.
//  - Upstream callbacks are `(...args) => boolean | void`; the bound `this`
//    (introduced by `WithThisType` at the `on` overloads) is modeled here as an
//    explicit leading `thisCtx` parameter so `triggerWithContext`'s receiver binding
//    stays faithful. `boolean | void` → `Bool?` (return `true` to cancel bubble).

// Return true to cancel bubble
public typealias EventCallbackSingleParam = (_ thisCtx: AnyObject?, _ params: Any?) -> Bool?

public typealias EventCallback = (_ thisCtx: AnyObject?, _ args: [Any?]) -> Bool?

public typealias EventQuery = Any

// type CbThis<Ctx, Impl> = unknown extends Ctx ? Impl : Ctx;
// (compile-time `this`-type selection; collapses to `AnyObject?` here.)

// type EventHandler<Ctx, Impl, EvtParams> = { h, ctx, query, callAtLast }
private struct EventHandler {
    var h: EventCallback
    var ctx: AnyObject?
    var query: EventQuery?

    var callAtLast: Bool
}

// type DefaultEventDefinition = Dictionary<EventCallback<any[]>>;

// export interface EventProcessor<EvtDef = DefaultEventDefinition>
//
// Modeled as a struct of optional closures (CONVENTIONS §2): an interface whose three
// methods are all optional (`?`) maps cleanly onto optional stored closures, preserving
// the upstream "is this method defined?" presence checks. The upstream `EvtDef` generic
// is dropped; `eventType` is `String`.
public struct EventProcessor {
    public var normalizeQuery: ((_ query: EventQuery) -> EventQuery)?
    public var filter: ((_ eventType: String, _ query: EventQuery) -> Bool)?
    public var afterTrigger: ((_ eventType: String) -> Void)?

    public init(
        normalizeQuery: ((_ query: EventQuery) -> EventQuery)? = nil,
        filter: ((_ eventType: String, _ query: EventQuery) -> Bool)? = nil,
        afterTrigger: ((_ eventType: String) -> Void)? = nil
    ) {
        self.normalizeQuery = normalizeQuery
        self.filter = filter
        self.afterTrigger = afterTrigger
    }
}

/**
 * Event dispatcher.
 *
 * Event can be defined in EvtDef to enable type check. For example:
 * ```ts
 * interface FooEvents {
 *     // key: event name, value: the first event param in `trigger` and `callback`.
 *     myevent: {
 *        aa: string;
 *        bb: number;
 *     };
 * }
 * class Foo extends Eventful<FooEvents> {
 *     fn() {
 *         // Type check of event name and the first event param is enabled here.
 *         this.trigger('myevent', {aa: 'xx', bb: 3});
 *     }
 * }
 * let foo = new Foo();
 * // Type check of event name and the first event param is enabled here.
 * foo.on('myevent', (eventParam) => { ... });
 * ```
 *
 * @param eventProcessor The object eventProcessor is the scope when
 *        `eventProcessor.xxx` called.
 * @param eventProcessor.normalizeQuery
 *        param: {string|Object} Raw query.
 *        return: {string|Object} Normalized query.
 * @param eventProcessor.filter Event will be dispatched only
 *        if it returns `true`.
 *        param: {string} eventType
 *        param: {string|Object} query
 *        return: {boolean}
 * @param eventProcessor.afterTrigger Called after all handlers called.
 *        param: {string} eventType
 */
// NOTE (CONVENTIONS §2): upstream `Eventful` is applied to `Element` as a MIXIN
// (`applyMixin`), not as a superclass, so it is faithfully a standalone `final class`
// here. Element composes it via forwarding (see `mixin(Element, Eventful)` in Element.swift).
public final class Eventful {

    private var _$handlers: [String: [EventHandler]]?

    internal var _$eventProcessor: EventProcessor?    // upstream: protected

    public init(_ eventProcessors: EventProcessor? = nil) {
        if let eventProcessors = eventProcessors {
            self._$eventProcessor = eventProcessors
        }
    }

    // Upstream declares three `on` overloads (handler-only / query+handler / the
    // implementation that runtime-dispatches on `typeof query === 'function'`). Swift's
    // static overloading expresses the two public shapes directly, so the runtime
    // `typeof` dispatch is unnecessary and is folded away.

    @discardableResult
    public func on(
        _ event: String,
        _ handler: @escaping EventCallback,
        _ context: AnyObject? = nil
    ) -> Eventful {
        return self.on(event, nil, handler, context)
    }

    /**
     * Bind a handler.
     *
     * @param event The event name.
     * @param Condition used on event filter.
     * @param handler The event handler.
     * @param context
     */
    @discardableResult
    public func on(
        _ event: String,
        _ query: EventQuery?,
        _ handler: @escaping EventCallback,
        _ context: AnyObject? = nil
    ) -> Eventful {
        var query = query
        let context = context

        if self._$handlers == nil {
            self._$handlers = [:]
        }

        // const _h = this._$handlers;  (Swift dict is a value type; mutate `_$handlers` directly.)

        // upstream `if (typeof query === 'function')` argument shuffle handled by overloads above.

        // if (!handler || !event) — `handler` is non-optional here; replicate the `!event` guard.
        if event.isEmpty {
            return self
        }

        let eventProcessor = self._$eventProcessor
        if query != nil, let eventProcessor = eventProcessor, let normalizeQuery = eventProcessor.normalizeQuery {
            query = normalizeQuery(query!)
        }

        if self._$handlers![event] == nil {
            self._$handlers![event] = []
        }

        // PORT-TODO: closure identity — upstream dedups via `_h[event][i].h === handler`,
        // but Swift closures have no comparable identity, so the dedup loop cannot be
        // ported. Re-binding the same closure will currently register it twice.
        // for (let i = 0; i < _h[event].length; i++) {
        //     if (_h[event][i].h === handler) { return this; }
        // }

        let wrap = EventHandler(
            h: handler,
            ctx: (context ?? self) as AnyObject?,
            query: query,
            // FIXME
            // Do not publish this feature util it is proved that it makes sense.
            // PORT-NOTE: `handler.zrEventfulCallAtLast` — JS tacks a flag onto the
            // function object; Swift closures cannot carry properties, so default false.
            callAtLast: false
        )

        let lastIndex = self._$handlers![event]!.count - 1
        let lastWrap: EventHandler? = lastIndex >= 0 ? self._$handlers![event]![lastIndex] : nil
        if let lastWrap = lastWrap, lastWrap.callAtLast {
            self._$handlers![event]!.insert(wrap, at: lastIndex)
        }
        else {
            self._$handlers![event]!.append(wrap)
        }

        return self
    }

    /**
     * Whether any handler has bound.
     */
    public func isSilent(_ eventName: String) -> Bool {
        let _h = self._$handlers
        return _h == nil || _h![eventName] == nil || _h![eventName]!.isEmpty
    }

    /**
     * Unbind a event.
     *
     * @param eventType The event name.
     *        If no `event` input, "off" all listeners.
     * @param handler The event handler.
     *        If no `handler` input, "off" all listeners of the `event`.
     */
    @discardableResult
    public func off(_ eventType: String? = nil, _ handler: EventCallback? = nil) -> Eventful {
        // const _h = this._$handlers;  (mutate `_$handlers` directly — Swift value-type dict.)

        if self._$handlers == nil {
            return self
        }

        guard let eventType = eventType else {
            self._$handlers = [:]
            return self
        }

        if let handler = handler {
            _ = handler
            // PORT-TODO: closure identity — upstream rebuilds the list keeping every
            // `_h[eventType][i].h !== handler`, but Swift closures are not comparable, so
            // a specific handler cannot be filtered out. Left as a no-op pending an
            // identity scheme; only the empty-list cleanup below is preserved.
            if let list = self._$handlers![eventType], list.isEmpty {
                self._$handlers![eventType] = nil
            }
        }
        else {
            self._$handlers![eventType] = nil
        }

        return self
    }

    /**
     * Dispatch a event.
     *
     * @param {string} eventType The event name.
     */
    @discardableResult
    public func trigger(_ eventType: String, _ args: Any?...) -> Eventful {
        if self._$handlers == nil {
            return self
        }

        let _h = self._$handlers![eventType]
        let eventProcessor = self._$eventProcessor

        if let _h = _h {
            let argLen = args.count

            let len = _h.count
            for i in 0..<len {
                let hItem = _h[i]
                if let eventProcessor = eventProcessor,
                   let filter = eventProcessor.filter,
                   hItem.query != nil,
                   !filter(eventType, hItem.query!)
                {
                    continue
                }

                // Optimize advise from backbone
                switch argLen {
                case 0:
                    _ = hItem.h(hItem.ctx, [])
                case 1:
                    _ = hItem.h(hItem.ctx, [args[0]])
                case 2:
                    _ = hItem.h(hItem.ctx, [args[0], args[1]])
                default:
                    // have more than 2 given arguments
                    _ = hItem.h(hItem.ctx, args)
                }
            }
        }

        if let eventProcessor = eventProcessor, let afterTrigger = eventProcessor.afterTrigger {
            afterTrigger(eventType)
        }

        return self
    }

    /**
     * Dispatch a event with context, which is specified at the last parameter.
     *
     * @param {string} type The event name.
     */
    @discardableResult
    public func triggerWithContext(_ type: String, _ args: Any?...) -> Eventful {
        if self._$handlers == nil {
            return self
        }

        let _h = self._$handlers![type]
        let eventProcessor = self._$eventProcessor

        if let _h = _h {
            let argLen = args.count
            // upstream: `const ctx = args[argLen - 1]` — JS reads args[-1] as undefined
            // when there are no args. Swift Array traps on a negative index, so guard it.
            let ctx = argLen > 0 ? (args[argLen - 1] as? AnyObject) : nil

            let len = _h.count
            for i in 0..<len {
                let hItem = _h[i]
                if let eventProcessor = eventProcessor,
                   let filter = eventProcessor.filter,
                   hItem.query != nil,
                   !filter(type, hItem.query!)
                {
                    continue
                }

                // Optimize advise from backbone
                switch argLen {
                case 0:
                    _ = hItem.h(ctx, [])
                case 1:
                    _ = hItem.h(ctx, [args[0]])
                case 2:
                    _ = hItem.h(ctx, [args[0], args[1]])
                default:
                    // have more than 2 given arguments
                    _ = hItem.h(ctx, Array(args[1..<(argLen - 1)]))
                }
            }
        }

        if let eventProcessor = eventProcessor, let afterTrigger = eventProcessor.afterTrigger {
            afterTrigger(type)
        }

        return self
    }

}
