// Ported from zrender/src/animation/Animation.ts — keep in sync with upstream

/**
 * Animation main class, dispatch and manage all animation controllers
 *
 */
// TODO Additive animation
// http://iosoteric.com/additive-animations-animatewithduration-in-ios-8/
// https://developer.apple.com/videos/wwdc2014/#236

import Foundation

// upstream: import Eventful from '../core/Eventful';                        → Core/Eventful.swift
// upstream: import requestAnimationFrame from './requestAnimationFrame';
//   animation/requestAnimationFrame.ts not ported — the per-frame tick is supplied
//   by the host. On iOS NativePainter drives a CADisplayLink that calls `update()` each frame
//   (Morph+Wire phase) instead of the browser's requestAnimationFrame recursion.
// upstream: import Animator from './Animator';                              → Animation/Animator.swift
// upstream: import Clip from './Clip';                                      → Animation/Clip.swift

public func getTime() -> Double {
    // upstream: return new Date().getTime();
    return Date().timeIntervalSince1970 * 1000
}

// upstream: interface Stage { update?: () => void }
public struct Stage {
    public var update: (() -> Void)?
    public init(update: (() -> Void)? = nil) {
        self.update = update
    }
}

// upstream: interface AnimationOption { stage?: Stage }
public struct AnimationOption {
    public var stage: Stage?
    public init(stage: Stage? = nil) {
        self.stage = stage
    }
}
/**
 * @example
 *     const animation = new Animation();
 *     const obj = {
 *         x: 100,
 *         y: 100
 *     };
 *     animation.animate(node.position)
 *         .when(1000, {
 *             x: 500,
 *             y: 500
 *         })
 *         .when(2000, {
 *             x: 100,
 *             y: 100
 *         })
 *         .start();
 */

// upstream: export default class Animation extends Eventful
// NOTE (CONVENTIONS §2): `Eventful` is a `final class` and is applied as a MIXIN elsewhere
// (see Element), so it cannot be subclassed. Animation composes an Eventful and forwards the
// event surface (`on`/`off`/`trigger`) — the same pattern Element uses for its Eventful mixin.
// complete the Eventful surface forwarding if more event methods are needed.
public final class Animation {

    // upstream: mixin via `extends Eventful` — composed + forwarded here.
    private let _eventful = Eventful()

    public var stage: Stage

    // Use linked list to store clip
    private var _head: Clip?
    private var _tail: Clip?

    private var _running = false

    private var _time: Double = 0
    private var _pausedTime: Double = 0
    private var _pauseStart: Double = 0

    private var _paused = false

    public init(_ opts: AnimationOption? = nil) {
        // super();

        let opts = opts ?? AnimationOption()

        self.stage = opts.stage ?? Stage()
    }

    /**
     * Add clip
     */
    public func addClip(_ clip: Clip) {
        if clip.animation != nil {
            // Clip has been added
            self.removeClip(clip)
        }

        if self._head == nil {
            self._head = clip
            self._tail = clip
        }
        else {
            self._tail!.next = clip
            clip.prev = self._tail
            clip.next = nil
            self._tail = clip
        }
        clip.animation = self
    }
    /**
     * Add animator
     */
    public func addAnimator(_ animator: Animator<Any>) {
        animator.animation = self
        let clip = animator.getClip()
        if let clip = clip {
            self.addClip(clip)
        }
    }
    /**
     * Delete animation clip
     */
    public func removeClip(_ clip: Clip) {
        if clip.animation == nil {
            return
        }
        let prev = clip.prev
        let next = clip.next
        if let prev = prev {
            prev.next = next
        }
        else {
            // Is head
            self._head = next
        }
        if let next = next {
            next.prev = prev
        }
        else {
            // Is tail
            self._tail = prev
        }
        clip.next = nil
        clip.prev = nil
        clip.animation = nil
    }

    /**
     * Delete animation clip
     */
    public func removeAnimator(_ animator: Animator<Any>) {
        let clip = animator.getClip()
        if let clip = clip {
            self.removeClip(clip)
        }
        animator.animation = nil
    }

    public func update(_ notTriggerFrameAndStageUpdate: Bool? = nil) {
        let time = getTime() - self._pausedTime
        let delta = time - self._time
        var clip = self._head

        while let c = clip {
            // Save the nextClip before step.
            // So the loop will not been affected if the clip is removed in the callback
            let nextClip = c.next
            let finished = c.step(time, delta)
            if finished {
                c.ondestroy()
                self.removeClip(c)
                clip = nextClip
            }
            else {
                clip = nextClip
            }
        }

        self._time = time

        if !(notTriggerFrameAndStageUpdate ?? false) {

            // 'frame' should be triggered before stage, because upper application
            // depends on the sequence (e.g., echarts-stream and finish
            // event judge)
            self.trigger("frame", delta)

            self.stage.update?()
        }
    }

    func _startLoop() {
        // upstream: const self = this;

        self._running = true

        // requestAnimationFrame seam — upstream recursively schedules `step` via
        //   requestAnimationFrame; on iOS the host (NativePainter's CADisplayLink) drives the
        //   loop by calling `update()` each frame while `_running` && !`_paused`. The recursive
        //   `step` below is retained for provenance; the actual frame tick is host-supplied.
        // function step() {
        //     if (self._running) {
        //         requestAnimationFrame(step);
        //         !self._paused && self.update();
        //     }
        // }
        // requestAnimationFrame(step);
    }

    /**
     * Start animation.
     */
    public func start() {
        if self._running {
            return
        }

        self._time = getTime()
        self._pausedTime = 0

        self._startLoop()
    }

    /**
     * Stop animation.
     */
    public func stop() {
        self._running = false
    }

    /**
     * Pause animation.
     */
    public func pause() {
        if !self._paused {
            self._pauseStart = getTime()
            self._paused = true
        }
    }

    /**
     * Resume animation.
     */
    public func resume() {
        if self._paused {
            self._pausedTime += getTime() - self._pauseStart
            self._paused = false
        }
    }

    /**
     * Clear animation.
     */
    public func clear() {
        var clip = self._head

        while let c = clip {
            let nextClip = c.next
            c.prev = nil
            c.next = nil
            c.animation = nil
            clip = nextClip
        }

        self._head = nil
        self._tail = nil
    }

    /**
     * Whether animation finished.
     */
    public func isFinished() -> Bool {
        return self._head == nil
    }

    /**
     * Creat animator for a target, whose props can be animated.
     */
    // TODO Gap
    public func animate<T>(_ target: T, _ options: AnimateOptions?) -> Animator<T> {
        let options = options ?? AnimateOptions()

        // Start animation loop
        self.start()

        let animator = Animator(
            target,
            options.loop ?? false
        )

        // upstream: this.addAnimator(animator)
        // `addAnimator` is typed `Animator<Any>` (matching the Element drive); inline
        //   the body here so the generic `Animator<T>` can be registered without an unsafe cast.
        animator.animation = self
        let clip = animator.getClip()
        if let clip = clip {
            self.addClip(clip)
        }

        return animator
    }

    // ---- Eventful mixin forwarding (note: composed `_eventful`, see class note) ----

    @discardableResult
    public func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> Animation {
        self._eventful.on(event, handler, context)
        return self
    }

    @discardableResult
    public func off(_ eventType: String? = nil, _ handler: EventCallback? = nil) -> Animation {
        self._eventful.off(eventType, handler)
        return self
    }

    @discardableResult
    public func trigger(_ eventType: String, _ args: Any?...) -> Animation {
        // upstream variadic `trigger(type, ...args)`; forward through the composed Eventful.
        switch args.count {
        case 0:
            self._eventful.trigger(eventType)
        case 1:
            self._eventful.trigger(eventType, args[0])
        default:
            // Swift cannot splat `args` into the variadic forward; Animation only
            //   triggers 'frame' with a single delta arg, so >1 is unused here.
            self._eventful.trigger(eventType, args[0])
        }
        return self
    }
}

// upstream: the inline `animate` options object literal `{ loop?: boolean }`.
public struct AnimateOptions {
    public var loop: Bool?  // Whether loop animation
    public init(loop: Bool? = nil) {
        self.loop = loop
    }
}
