// Ported from echarts/src/animation/basicTransition.ts — keep in sync with upstream.
// Real animation replacing the per-view no-op shims (BarView/CandlestickView). `initProps`/`updateProps`
// animate via el.animateTo when the series has animation enabled, else set the props instantly.
//
// PORT-NOTE: `getAnimationConfig` now consumes the global animation override from
//   `ecModel.getUpdatePayload().animation` (dataZoom/resize actions), evaluates function-valued
//   `animationDuration`/`animationDelay(dataIndex)` (staggered enter), and honors a `removeOpt`
//   override on the leave path. The `getAnimationDelayParams` hook (pictorial bar per-element delay)
//   is still deferred: the Swift PictorialBar port does not monkeypatch that method onto its item
//   model and `Model` exposes no such member, so `extraDelayParams` is threaded but always nil here.
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
///
/// `extraDelayParams` is the pictorial-bar-only second argument passed to a function-valued
/// `animationDelay` (upstream's `getAnimationDelayParams` hook). The Swift port has no producer for
/// it yet, so it is always nil here (see the header PORT-NOTE).
func getAnimationConfig(
    _ type: ECAnimType, _ model: Model?, _ dataIndex: Int,
    _ extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)?,
    _ extraDelayParams: AnimationDelayCallbackParam? = nil
) -> (duration: Double, delay: Double, easing: AnimationEasing?)? {
    // Check if there is global animation configuration from dataZoom/resize that can override the
    // config in option. It only applies when animation is enabled; otherwise it is ignored.
    var animationPayload: PayloadAnimationPart?
    if let model = model, let ecModel = model.ecModel {
        animationPayload = ecModel.getUpdatePayload()?.animation
    }
    let isUpdate = (type == .update)
    guard let model = model, model.isAnimationEnabled() == true else { return nil }
    // duration/delay stay `Any?` until after the payload override so a function value can still be
    // superseded by a numeric payload value (upstream evaluates isFunction last).
    var durationVal: Any?
    var delayVal: Any?
    var easing: AnimationEasing?
    if let extra = extra {
        durationVal = extra.duration ?? 200.0
        easing = extra.easing ?? .named("cubicOut")
        delayVal = 0.0
    } else {
        durationVal = model.getShallow(isUpdate ? "animationDurationUpdate" : "animationDuration")
        delayVal = model.getShallow(isUpdate ? "animationDelayUpdate" : "animationDelay")
        let rawEasing = model.getShallow(isUpdate ? "animationEasingUpdate" : "animationEasing")
        if let e = rawEasing as? String {
            easing = .named(e)
        } else if let e = rawEasing as? AnimationEasing {
            easing = e
        } else {
            easing = nil
        }
    }
    // animation from payload has highest priority.
    if let p = animationPayload {
        if let d = p.duration { durationVal = d }
        if let e = p.easing { easing = e }
        if let dl = p.delay { delayVal = dl }
    }
    // Function-valued animationDelay(dataIndex, extraDelayParams) — per-index staggered enter.
    let delay: Double
    if let f = delayVal as? AnimationDelayCallback {
        delay = f(Double(dataIndex), extraDelayParams)
    } else {
        delay = transNum(delayVal) ?? 0
    }
    // Function-valued animationDuration(dataIndex).
    let duration: Double
    if let f = durationVal as? AnimationDurationCallback {
        duration = f(Double(dataIndex))
    } else {
        duration = transNum(durationVal) ?? 0
    }
    return (duration: duration, delay: delay, easing: easing)
}

private func animateOrSetProps(
    _ type: ECAnimType, _ el: Element, _ props: [String: Any], _ model: Model?,
    _ dataIndex: Int?, _ isFrom: Bool, _ cb: (() -> Void)?, _ during: ((Double) -> Void)?,
    _ removeOpt: AnimationOption? = nil
) {
    let isRemove = (type == .leave)
    if !isRemove {
        // Must stop the remove animation.
        _ = el.stopAnimation("leave")
    }
    // upstream: getAnimationConfig(type, animatableModel, dataIndex, isRemove ? (removeOpt || {}) : null)
    //   — a truthy (possibly-empty) extraOpts object forces getAnimationConfig's extraOpts branch,
    //   which defaults to 200ms/cubicOut/delay 0 for the leave path (independent of the series'
    //   animationDuration) but is overridden by any field the caller supplies via `removeOpt`.
    let extra: (duration: Double?, easing: AnimationEasing?, delay: Double?)? =
        isRemove ? (duration: removeOpt?.duration, easing: removeOpt?.easing, delay: removeOpt?.delay) : nil
    let cfg = getAnimationConfig(type, model, dataIndex ?? 0, extra, nil)
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
//   signature stays diffable. `removeOpt` only affects the leave path (upstream `removeElement`); it
//   is threaded through but inert on the enter/update forms that exist today.
struct AnimateOrSetPropsOption {
    var dataIndex: Int?
    var cb: (() -> Void)?
    var during: ((Double) -> Void)?
    var removeOpt: AnimationOption?
    var isFrom: Bool?
    init(dataIndex: Int? = nil, cb: (() -> Void)? = nil,
         during: ((Double) -> Void)? = nil, removeOpt: AnimationOption? = nil, isFrom: Bool? = nil) {
        self.dataIndex = dataIndex
        self.cb = cb
        self.during = during
        self.removeOpt = removeOpt
        self.isFrom = isFrom
    }
}

/// upstream `initProps(el, props, animatableModel, opt: AnimateOrSetPropsOption)` — the object form.
func initProps(_ el: Element, _ props: [String: Any], _ model: Model?, _ opt: AnimateOrSetPropsOption) {
    animateOrSetProps(.enter, el, props, model, opt.dataIndex, opt.isFrom ?? false, opt.cb, opt.during, opt.removeOpt)
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
