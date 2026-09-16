// Ported from echarts/src/util/throttle.ts — keep in sync with upstream

import Foundation

// upstream stores three per-function markers via reserved string symbols on the returned function:
//   const ORIGIN_METHOD = '\0__throttleOriginMethod';
//   const RATE          = '\0__throttleRate';
//   const THROTTLE_TYPE = '\0__throttleType';
//   In JS these are stamped onto the throttled Function object so `createOrUpdate` can read the
//   previous rate/type and the original method back off it. Swift functions carry no such slots, so
//   `ThrottledFunction` (below) holds them as stored properties — see the createOrUpdate note.

// upstream: export type ThrottleType = 'fixRate' | 'debounce';
public enum ThrottleType: Equatable {
    case fixRate
    case debounce
}

// upstream: export interface ThrottleController { clear(): void; debounceNextCall(debounceDelay): void; }
//   The `throttle` factory returns `T & ThrottleController`; here `ThrottledFunction` IS both the
//   callable (via `callAsFunction`) and the controller.
//
// upstream: export function throttle<T>(fn, delay?, debounce?): T & ThrottleController
public final class ThrottledFunction {

    // The wrapped call (`fn.apply(scope, args)` in JS). This port's consumers are nullary
    //   (`_doDispatchAxisPointer()` takes no args), so the closure carries no args/scope.
    private let fn: () -> Void

    private var delay: Double
    private let debounce: Bool

    // upstream locals captured in the closure: currCall / lastCall / lastExec / timer / diff / scope /
    //   args / debounceNextCall.
    private var currCall: Double = 0
    private var lastCall: Double = 0
    private var lastExec: Double = 0
    private var timer: DispatchWorkItem?
    private var diff: Double = 0
    private var debounceNextCallValue: Double?

    // createOrUpdate bookkeeping (upstream: the ORIGIN_METHOD / THROTTLE_TYPE / RATE symbol stamps).
    fileprivate let originMethod: () -> Void
    fileprivate let throttleTypeStored: ThrottleType
    fileprivate let rateStored: Double

    fileprivate init(
        _ fn: @escaping () -> Void,
        _ delay: Double?,
        _ debounce: Bool,
        originMethod: @escaping () -> Void,
        throttleType: ThrottleType,
        rate: Double
    ) {
        self.fn = fn
        // upstream: delay = delay || 0;
        self.delay = (delay == nil || delay == 0) ? 0 : delay!
        self.debounce = debounce
        self.originMethod = originMethod
        self.throttleTypeStored = throttleType
        self.rateStored = rate
    }

    // upstream: function exec() { lastExec = (new Date()).getTime(); timer = null; fn.apply(scope, args); }
    private func exec() {
        lastExec = Self.now()
        timer = nil
        fn()
    }

    // upstream: const cb = function (...cbArgs) { ... }
    public func callAsFunction() {
        currCall = Self.now()
        // upstream: const thisDelay = debounceNextCall || delay;
        //           const thisDebounce = debounceNextCall || debounce;
        //           debounceNextCall = null;
        let thisDelay = (debounceNextCallValue != nil && debounceNextCallValue != 0) ? debounceNextCallValue! : delay
        let thisDebounce = (debounceNextCallValue != nil && debounceNextCallValue != 0) ? true : debounce
        debounceNextCallValue = nil
        diff = currCall - (thisDebounce ? lastCall : lastExec) - thisDelay

        // clearTimeout(timer);
        timer?.cancel()
        timer = nil

        // Here we should make sure that: the `exec` SHOULD NOT be called later than a new call of `cb`,
        // that is, preserving the command order. (see upstream comment)
        if thisDebounce {
            scheduleExec(afterMs: thisDelay)
        }
        else {
            if diff >= 0 {
                exec()
            }
            else {
                scheduleExec(afterMs: -diff)
            }
        }

        lastCall = currCall
    }

    // upstream: timer = setTimeout(exec, ms);
    //   browser `setTimeout` → main-queue `asyncAfter` (the browser timer fires on the main
    //   thread). The FIRST fixRate call always runs synchronously (lastExec starts at 0, so
    //   diff >> 0 → exec()); only rapid subsequent calls are deferred to the queue.
    private func scheduleExec(afterMs ms: Double) {
        let work = DispatchWorkItem { [weak self] in self?.exec() }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, ms) / 1000.0, execute: work)
    }

    // upstream: cb.clear = function () { if (timer) { clearTimeout(timer); timer = null; } };
    public func clear() {
        timer?.cancel()
        timer = nil
    }

    // upstream: cb.debounceNextCall = function (debounceDelay) { debounceNextCall = debounceDelay; };
    public func debounceNextCall(_ debounceDelay: Double) {
        debounceNextCallValue = debounceDelay
    }

    // (new Date()).getTime() → epoch milliseconds.
    private static func now() -> Double {
        return Date().timeIntervalSince1970 * 1000
    }
}

// upstream `import * as throttleUtil from '../../util/throttle'` — the alias BaseAxisPointer imports.
//   Caseless-enum namespace (CONVENTIONS §2) so call sites stay `throttleUtil.createOrUpdate(...)` /
//   `throttleUtil.clear(...)`, matching upstream.
public enum throttleUtil {

    // upstream: export function throttle(fn, delay?, debounce?)
    //   Kept for API completeness / future consumers; `createOrUpdate` builds its own throttled fn.
    @discardableResult
    public static func throttle(
        _ fn: @escaping () -> Void,
        _ delay: Double? = nil,
        _ debounce: Bool = false
    ) -> ThrottledFunction {
        return ThrottledFunction(
            fn, delay, debounce,
            originMethod: fn,
            throttleType: debounce ? .debounce : .fixRate,
            rate: delay ?? 0
        )
    }

    /// Create throttle method or update throttle rate.
    ///
    /// upstream: `export function createOrUpdate(obj, fnAttr, rate, throttleType)` — reflectively reads
    ///   `obj[fnAttr]`, and, if the rate/type changed, REPLACES the method on `obj` with a throttled
    ///   wrapper (stashing the origin method under a symbol). Swift cannot swap a method on a live
    ///   instance, so this adaptation takes the CURRENT throttled wrapper (`existing`, i.e. `obj[fnAttr]`
    ///   when it is already a wrapper — else `nil`) + the raw `origin` closure, and RETURNS the wrapper
    ///   the caller should store back into its slot (BaseAxisPointer keeps it in `_doDispatchThrottled`).
    ///   Returning `nil` mirrors upstream returning the raw `originFn` (unthrottled) — the caller then
    ///   calls `origin` directly.
    // closure-slot adaptation of the reflective `obj[fnAttr]` swap (see above).
    public static func createOrUpdate(
        existing: ThrottledFunction?,
        origin: @escaping () -> Void,
        rate: Double?,
        throttleType: ThrottleType
    ) -> ThrottledFunction? {
        // const originFn = fn[ORIGIN_METHOD] || fn;
        let originFn = existing?.originMethod ?? origin
        // const lastThrottleType = fn[THROTTLE_TYPE]; const lastRate = fn[RATE];
        let lastThrottleType = existing?.throttleTypeStored
        let lastRate = existing?.rateStored

        if lastRate != rate || lastThrottleType != throttleType {
            // if (rate == null || !throttleType) { return (obj[fnAttr] = originFn); }
            guard let rate = rate else {
                return nil
            }

            // fn = obj[fnAttr] = throttle(originFn, rate, throttleType === 'debounce');
            return ThrottledFunction(
                originFn, rate, throttleType == .debounce,
                originMethod: originFn,
                throttleType: throttleType,
                rate: rate
            )
        }

        return existing
    }

    /// Clear throttle. Example see throttle.createOrUpdate.
    ///
    /// upstream: `export function clear(obj, fnAttr)` — if `obj[fnAttr]` is a throttled wrapper, calls
    ///   its `.clear()` and restores the origin method onto `obj[fnAttr]`. Here the caller passes its
    ///   current wrapper; we clear its pending timer and return `nil` for the caller to store back.
    // closure-slot adaptation of the reflective `obj[fnAttr]` restore.
    @discardableResult
    public static func clear(_ existing: ThrottledFunction?) -> ThrottledFunction? {
        existing?.clear()
        return nil
    }
}
