// Ported from zrender/src/animation/Clip.ts — keep in sync with upstream

/**
 * 动画主控制器
 * @config target 动画对象，可以是数组，如果是数组的话会批量分发onframe等事件
 * @config life(1000) 动画时长
 * @config delay(0) 动画延迟时间
 * @config loop(true)
 * @config onframe
 * @config easing(optional)
 * @config ondestroy(optional)
 * @config onrestart(optional)
 *
 * TODO pause
 */

import Foundation

// upstream: import easingFuncs, {AnimationEasing} from './easing';
// upstream: import type Animation from './Animation';
// upstream: import { isFunction, noop } from '../core/util';
// upstream: import { createCubicEasingFunc } from './cubicEasing';

// upstream: type OnframeCallback = (percent: number) => void;
// NOTE: Animator.swift already declares a generic `OnframeCallback<T>` at module
// scope; Swift forbids the redeclaration, so Clip's nullary-percent variant is
// named `ClipOnframeCallback` here while staying byte-equivalent in shape.
public typealias ClipOnframeCallback = (_ percent: Double) -> Void
// upstream: type ondestroyCallback = () => void
public typealias ondestroyCallback = () -> Void
// upstream: type onrestartCallback = () => void
public typealias onrestartCallback = () -> Void

// upstream: export type DeferredEventTypes = 'destroy' | 'restart'
public enum DeferredEventTypes: String {
    case destroy
    case restart
}
// type DeferredEventKeys = 'ondestroy' | 'onrestart'

// upstream: export interface ClipProps
public struct ClipProps {
    public var life: Double?
    public var delay: Double?
    public var loop: Bool?
    public var easing: AnimationEasing?

    public var onframe: ClipOnframeCallback?
    public var ondestroy: ondestroyCallback?
    public var onrestart: onrestartCallback?

    public init(
        life: Double? = nil,
        delay: Double? = nil,
        loop: Bool? = nil,
        easing: AnimationEasing? = nil,
        onframe: ClipOnframeCallback? = nil,
        ondestroy: ondestroyCallback? = nil,
        onrestart: onrestartCallback? = nil
    ) {
        self.life = life
        self.delay = delay
        self.loop = loop
        self.easing = easing
        self.onframe = onframe
        self.ondestroy = ondestroy
        self.onrestart = onrestart
    }
}

public final class Clip {

    private var _life: Double
    private var _delay: Double

    private var _inited: Bool = false
    private var _startTime: Double = 0 // 开始时间单位毫秒

    private var _pausedTime: Double = 0
    private var _paused: Bool = false

    // upstream: animation: Animation
    // PORT-TODO: `Animation` (animation/Animation.ts) not ported yet — typed AnyObject?.
    public weak var animation: AnyObject?

    public var loop: Bool

    public var easing: AnimationEasing?
    public var easingFunc: ((_ p: Double) -> Double)?

    // For linked list. Readonly
    public var next: Clip?
    public var prev: Clip?

    public var onframe: ClipOnframeCallback
    public var ondestroy: ondestroyCallback
    public var onrestart: onrestartCallback

    public init(_ opts: ClipProps) {

        self._life = opts.life ?? 1000
        self._delay = opts.delay ?? 0

        self.loop = opts.loop ?? false

        // upstream: opts.onframe || noop — `noop` is nullary; onframe takes `percent`,
        // so an arg-ignoring closure stands in for the Swift type.
        self.onframe = opts.onframe ?? { _ in }
        self.ondestroy = opts.ondestroy ?? util.noop
        self.onrestart = opts.onrestart ?? util.noop

        if let easing = opts.easing {
            self.setEasing(easing)
        }
    }

    @discardableResult
    public func step(_ globalTime: Double, _ deltaTime: Double) -> Bool {
        // Set startTime on first step, or _startTime may has milleseconds different between clips
        // PENDING
        if !self._inited {
            self._startTime = globalTime + self._delay
            self._inited = true
        }

        if self._paused {
            self._pausedTime += deltaTime
            return false // upstream: return; (undefined → falsy)
        }

        let life = self._life
        let elapsedTime = globalTime - self._startTime - self._pausedTime
        var percent = elapsedTime / life

        // PENDING: Not begin yet. Still run the loop.
        // In the case callback needs to be invoked.
        // Or want to update to the begin state at next frame when `setToFinal` and `delay` are both used.
        // To avoid the unexpected blink.
        if percent < 0 {
            percent = 0
        }

        percent = Swift.min(percent, 1)

        let easingFunc = self.easingFunc
        let schedule = easingFunc != nil ? easingFunc!(percent) : percent

        self.onframe(schedule)

        // 结束
        if percent == 1 {
            if self.loop {
                // Restart
                let remainder = elapsedTime.truncatingRemainder(dividingBy: life)
                self._startTime = globalTime - remainder
                self._pausedTime = 0

                self.onrestart()
            }
            else {
                return true
            }
        }

        return false
    }

    public func pause() {
        self._paused = true
    }

    public func resume() {
        self._paused = false
    }

    public func setEasing(_ easing: AnimationEasing) {
        self.easing = easing
        // upstream: this.easingFunc = isFunction(easing)
        //     ? easing
        //     : easingFuncs[easing] || createCubicEasingFunc(easing);
        switch easing {
        case .function(let f):
            self.easingFunc = f
        case .named(let name):
            // easingFuncs[easing] || createCubicEasingFunc(easing)
            self.easingFunc = ZRenderKit.easing.easingFuncs[name]
                ?? ZRenderKit.easing.createCubicEasingFunc(name)
        }
    }
}
