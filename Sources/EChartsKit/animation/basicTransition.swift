// Ported from echarts/src/animation/basicTransition.ts — keep in sync with upstream.
// Real animation replacing the per-view no-op shims (BarView/CandlestickView). `initProps`/`updateProps`
// animate via el.animateTo when the series has animation enabled, else set the props instantly.
//
// PORT-TODO (scope for this task): upstream's `getAnimationConfig` also reads a global animation
//   override from `ecModel.getUpdatePayload()` (dataZoom/resize actions) and supports a
//   `getAnimationDelayParams` hook (pictorial bar only) plus a `removeOpt` override for the leave
//   path. None of those are wired here — they are out of scope for the shared-helper port and are
//   left for the task(s) that actually need them (dataZoom/pictorial bar).
import Foundation
import ZRenderKit

enum ECAnimType { case enter, update, leave }

private func transNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

/// Return nil if animation is disabled.
func getAnimationConfig(
    _ type: ECAnimType, _ model: Model?, _ dataIndex: Int,
    _ extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)?
) -> (duration: Double, delay: Double, easing: AnimationEasing?)? {
    _ = dataIndex
    let isUpdate = (type == .update)
    guard let model = model, model.isAnimationEnabled() == true else { return nil }
    let duration: Double
    let delay: Double
    let easing: AnimationEasing?
    if let extra = extra {
        duration = extra.duration ?? 200
        easing = extra.easing ?? .named("cubicOut")
        delay = 0
    } else {
        duration = transNum(model.getShallow(isUpdate ? "animationDurationUpdate" : "animationDuration")) ?? 0
        delay = transNum(model.getShallow(isUpdate ? "animationDelayUpdate" : "animationDelay")) ?? 0
        if let e = model.getShallow(isUpdate ? "animationEasingUpdate" : "animationEasing") as? String {
            easing = .named(e)
        } else {
            easing = nil
        }
    }
    return (duration: duration, delay: delay, easing: easing)
}

private func animateOrSetProps(
    _ type: ECAnimType, _ el: Element, _ props: [String: Any], _ model: Model?,
    _ dataIndex: Int?, _ isFrom: Bool, _ cb: (() -> Void)?, _ during: ((Double) -> Void)?
) {
    let isRemove = (type == .leave)
    if !isRemove {
        // Must stop the remove animation.
        _ = el.stopAnimation("leave")
    }
    let cfg = getAnimationConfig(type, model, dataIndex ?? 0, nil)
    if let cfg = cfg, cfg.duration > 0 {
        var ac = ElementAnimateConfig()
        ac.duration = cfg.duration
        ac.delay = cfg.delay
        ac.easing = cfg.easing
        ac.during = during
        ac.done = cb
        // upstream: force: !!cb || !!during — guarantees the callback fires (and an animator
        //   exists to carry `scope`) even when the target values already equal the current ones.
        // PORT-TODO deviation: forced unconditionally here (not only when cb/during are given) so
        //   an "enter"/"update" transition always yields a scoped animator (needed by
        //   isElementRemoved's scope=="leave" check on the *next* leave transition, and asserted by
        //   BasicTransitionTests). Revisit if a perf-sensitive caller needs the upstream economy.
        ac.force = true
        // Set to final state in update/init animation, so post-processing based on the path shape
        // (e.g. label layout) can be done correctly.
        ac.setToFinal = !isRemove
        ac.scope = type == .enter ? "enter" : (type == .update ? "update" : "leave")
        if isFrom {
            el.animateFrom(props, ac)
        } else {
            el.animateTo(props, ac)
        }
    } else {
        _ = el.stopAnimation()
        // If `isFrom`, `props` is the "from" props — do not assign it as the current state.
        if !isFrom {
            _ = el.attr(props)
        }
        // Call `during` at least once.
        during?(1)
        cb?()
    }
}

/// Init graphic element properties with or without animation according to the configuration in
/// series. Caution: this stops any previous animation — do not call it twice on the same element
/// before the animation starts, unless intentional.
func initProps(_ el: Element, _ props: [String: Any], _ model: Model? = nil,
               _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil) {
    animateOrSetProps(.enter, el, props, model, dataIndex, false, cb, during)
}

/// Update graphic element properties with or without animation according to the configuration in
/// series. Caution: this stops any previous animation — do not call it twice on the same element
/// before the animation starts, unless intentional.
func updateProps(_ el: Element, _ props: [String: Any], _ model: Model? = nil,
                  _ dataIndex: Int? = nil, _ cb: (() -> Void)? = nil, _ during: ((Double) -> Void)? = nil) {
    animateOrSetProps(.update, el, props, model, dataIndex, false, cb, during)
}

/// If the element is removed, or is currently mid-way through a "leave" (remove) animation.
private func isElementRemoved(_ el: Element) -> Bool {
    if el.__zr == nil {
        return true
    }
    for animator in el.animators {
        if animator.scope == "leave" {
            return true
        }
    }
    return false
}

private func fadeOutDisplayable(_ el: Displayable, _ model: Model?, _ dataIndex: Int, _ done: (() -> Void)?) {
    el.removeTextContent()
    el.removeTextGuideLine()
    animateOrSetProps(.leave, el, ["style": ["opacity": 0.0] as [String: Any]], model, dataIndex, false, done, nil)
}

/// Remove a graphic element, fading it (and its Group descendants) out first.
func removeElementWithFadeOut(_ el: Element, _ model: Model? = nil, _ dataIndex: Int = -1) {
    // Don't do remove animation twice.
    if isElementRemoved(el) {
        return
    }
    func doRemove() {
        if let p = el.parent as? Group {
            _ = p.remove(el)
        }
    }
    // Hide label and labelLine first.
    if let g = el as? Group {
        _ = g.traverse { child in
            if let disp = child as? Displayable, !(child is Group) {
                // Can invoke doRemove multiple times.
                fadeOutDisplayable(disp, model, dataIndex, doRemove)
            }
            return false
        }
    } else if let disp = el as? Displayable {
        fadeOutDisplayable(disp, model, dataIndex, doRemove)
    } else {
        doRemove()
    }
}

// ---- Saved old style for style transition in universalTransition (later sub-project). ----
// PORT-TODO (B1 stub): upstream stores `Displayable['style']` (the concrete style bag, whatever
//   subtype it is) via a `makeInner`-style per-element WeakMap. Our `Displayable.style` is typed
//   `CommonStyleProps!`, not `PathStyleProps` — the two are not interchangeable, and `model.makeInner`
//   requires an `AnyObject` value type, which a style struct is not. Since nothing in this task's
//   interface/tests exercises save/get, this is left an honest no-op stub (matching the produced
//   `PathStyleProps?` signature promised to later tasks) rather than silently miscoercing types.
//   A real implementation needs its own `WeakMap<Displayable, PathStyleProps>` once a universalTransition
//   task actually needs the saved style.
func saveOldStyle(_ el: Displayable) {
    _ = el
}

func getOldStyle(_ el: Displayable) -> PathStyleProps? {
    _ = el
    return nil
}
