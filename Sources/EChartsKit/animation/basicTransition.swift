// Ported from echarts/src/animation/basicTransition.ts — keep in sync with upstream.
// Real animation replacing the per-view no-op shims (BarView/CandlestickView). `initProps`/`updateProps`
// animate via el.animateTo when the series has animation enabled, else set the props instantly.
//
// PORT-NOTE (deferred): upstream's `getAnimationConfig` also reads a global animation
//   override from `ecModel.getUpdatePayload()` (dataZoom/resize actions — the method IS ported on
//   Global but not consumed here) and supports a `getAnimationDelayParams` hook (pictorial bar only)
//   plus a `removeOpt` override for the leave path. None of those are wired here — they are out of
//   scope for the shared-helper port and land with the task(s) that need them (dataZoom/pictorial bar).
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
    // upstream: getAnimationConfig(type, animatableModel, dataIndex, isRemove ? (removeOpt || {}) : null)
    //   — a truthy (possibly-empty) extraOpts object forces getAnimationConfig's extraOpts branch,
    //   which hardcodes 200ms/cubicOut/delay 0 for the leave path, independent of the series'
    //   animationDuration.
    let extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)? =
        isRemove ? (duration: nil, easing: nil, delay: nil) : nil
    let cfg = getAnimationConfig(type, model, dataIndex ?? 0, extra)
    if let cfg = cfg, cfg.duration > 0 {
        var ac = ElementAnimateConfig()
        ac.duration = cfg.duration
        ac.delay = cfg.delay
        ac.easing = cfg.easing
        ac.during = during
        ac.done = cb
        // upstream: force: !!cb || !!during — guarantees the callback fires (and an animator
        //   exists to carry `scope`) even when the target values already equal the current ones.
        ac.force = (cb != nil) || (during != nil)
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

// upstream `AnimateOrSetPropsOption` — the OBJECT form of `initProps`/`updateProps`'s 4th parameter
//   (`dataIndex?: number | AnimateOrSetPropsOption`). The scalar form is the overload above; this
//   struct carries the fields the object form adds. Only `isFrom` is actually needed by a ported call
//   site today (universalTransition's `fadeInElement`), but the whole (modeled) bag is kept so the
//   signature stays diffable. `removeOpt` is NOT modeled — see the header PORT-NOTE (the leave-path
//   override is out of scope and unported).
struct AnimateOrSetPropsOption {
    var dataIndex: Int?
    var cb: (() -> Void)?
    var during: ((Double) -> Void)?
    var isFrom: Bool?
    init(dataIndex: Int? = nil, cb: (() -> Void)? = nil,
         during: ((Double) -> Void)? = nil, isFrom: Bool? = nil) {
        self.dataIndex = dataIndex
        self.cb = cb
        self.during = during
        self.isFrom = isFrom
    }
}

/// upstream `initProps(el, props, animatableModel, opt: AnimateOrSetPropsOption)` — the object form.
func initProps(_ el: Element, _ props: [String: Any], _ model: Model?, _ opt: AnimateOrSetPropsOption) {
    animateOrSetProps(.enter, el, props, model, opt.dataIndex, opt.isFrom ?? false, opt.cb, opt.during)
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
    // Don't do remove animation twice on the same Displayable (upstream checks this per-Displayable
    // inside removeElement, not once on the top-level element — a Group itself never carries a
    // leave-scoped animator, only its faded children do).
    if isElementRemoved(el) {
        return
    }
    el.removeTextContent()
    el.removeTextGuideLine()
    animateOrSetProps(.leave, el, ["style": ["opacity": 0.0] as [String: Any]], model, dataIndex, false, done, nil)
}

/// Remove a graphic element, fading it (and its Group descendants) out first.
func removeElementWithFadeOut(_ el: Element, _ model: Model? = nil, _ dataIndex: Int = -1) {
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

// ---- Saved old style for style transition in universalTransition. ----
// upstream:
//   const getOldStyle = makeInner<Displayable['style'], Displayable>();
//   export function saveOldStyle(el: Displayable) { getOldStyle(el).oldStyle = el.style; }
//   export function getOldStyle(el: Displayable) { return getOldStyle(el).oldStyle; }
//   (upstream names the inner store and the getter the same; renamed `oldStyleInner` here.)
//
// PORT-NOTE: `model.makeInner` keys by object identity and requires a CLASS record, so the saved style
//   (a `PathStyleProps` VALUE struct) is boxed in `OldStyleRecord`. Upstream stores `el.style` — whatever
//   the concrete Displayable's style subtype is. Here only `Path`'s `pathStyle` is captured (a `ZRText`/
//   `ZRImage` style is a different Swift type and is not a morph endpoint), so `saveOldStyle` on a
//   non-Path Displayable records nothing and `getOldStyle` returns nil for it — the sole consumer
//   (universalTransition's `animateElementStyles`) only tweens `Path` styles.
final class OldStyleRecord {
    var oldStyle: PathStyleProps?
    init() {}
}
private let oldStyleInner: (Displayable) -> OldStyleRecord = model.makeInner { OldStyleRecord() }

func saveOldStyle(_ el: Displayable) {
    oldStyleInner(el).oldStyle = (el as? Path)?.pathStyle
}

func getOldStyle(_ el: Displayable) -> PathStyleProps? {
    return oldStyleInner(el).oldStyle
}
