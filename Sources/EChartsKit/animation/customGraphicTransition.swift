// Ported from echarts/src/animation/customGraphicTransition.ts — keep in sync with upstream.
// Helpers for creating transitions in custom series and graphic components.
//
// upstream imports (mapped):
//   Element, ElementAnimateConfig, ElementProps          -> ZRenderKit.
//   makeInner, normalizeToArray from '../util/model'      -> EChartsKit `model.makeInner` / `model.normalizeToArray`.
//   assert/bind/each/eqNaN/extend/hasOwn/indexOf/isArrayLike/keys/reduce -> ZRenderKit `util`.
//   cloneValue from 'zrender/src/animation/Animator'      -> ZRenderKit `cloneValue`.
//   Displayable, DisplayableProps                         -> ZRenderKit.
//   Model                                                 -> EChartsKit `Model`.
//   getAnimationConfig from './basicTransition'           -> animation/basicTransition.swift.
//   Path from '../util/graphic'                           -> ZRenderKit `Path`.
//   TRANSFORMABLE_PROPS, TransformProp                    -> ZRenderKit.
//
// The dynamic `TransitionElementOption` / `LooseElementProps` option bags are modeled as
//   `[String: Any]` throughout (the same convention CustomView / GraphicView already use for the
//   `elOption` they pass in). `el.attr(...)` / `el.animateFrom(...)` / `el.animateTo(...)` decompose a
//   nested `["shape": [...], "style": [...]]` bag into the typed value-struct sub-bags (see Path.attrKV /
//   animateToShallow), so a dict-based `propsToSet` / `transFromProps` round-trips into `Path` elements.

import Foundation
import ZRenderKit

// upstream:
//   const LEGACY_TRANSFORM_PROPS_MAP = { position: ['x','y'], scale: ['scaleX','scaleY'], origin: ['originX','originY'] };
//   const LEGACY_TRANSFORM_PROPS = keys(LEGACY_TRANSFORM_PROPS_MAP);
private let LEGACY_TRANSFORM_PROPS_MAP: [(legacy: String, xy: [String])] = [
    ("position", ["x", "y"]),
    ("scale", ["scaleX", "scaleY"]),
    ("origin", ["originX", "originY"])
]

// upstream:
//   const TRANSFORM_PROPS_MAP = reduce(TRANSFORMABLE_PROPS, (obj, key) => { obj[key] = 1; return obj; }, {});
//   const transformPropNamesStr = TRANSFORMABLE_PROPS.join(', ');
private let TRANSFORM_PROPS_MAP: Set<String> = Set(TRANSFORMABLE_PROPS)
private let transformPropNamesStr = TRANSFORMABLE_PROPS.joined(separator: ", ")

// upstream: export const ELEMENT_ANIMATABLE_PROPS = ['', 'style', 'shape', 'extra'] as const;
//   '' means root (targets the element's transform props); the others target the like-named sub-bag.
//   SINGLE OWNER: this replaces the former non-public duplicate in customGraphicKeyframeAnimation.swift
//   (which imported it from this module upstream). Widened to `public` deliberately.
public let ELEMENT_ANIMATABLE_PROPS: [String] = ["", "style", "shape", "extra"]

// upstream: type TransitionProps = string | string[];  (modeled as `Any?`: a String or [String].)

// upstream `opts` bag of `applyUpdateTransition`.
public struct ApplyUpdateTransitionOpts {
    public var dataIndex: Int?
    public var isInit: Bool?
    public var clearStyle: Bool?
    public init(dataIndex: Int? = nil, isInit: Bool? = nil, clearStyle: Bool? = nil) {
        self.dataIndex = dataIndex
        self.isInit = isInit
        self.clearStyle = clearStyle
    }
}

// upstream `TransitionDuringAPI` — the object handed to a user `during(params)` callback. `this`-return
//   chaining preserved (each setter returns the API). See `transitionDuringAPI` singleton below.
public protocol TransitionDuringAPI: AnyObject {
    @discardableResult func setTransform(_ key: String, _ val: Double) -> TransitionDuringAPI
    func getTransform(_ key: String) -> Double
    @discardableResult func setExtra(_ key: String, _ val: Any?) -> TransitionDuringAPI
    func getExtra(_ key: String) -> Any?
    @discardableResult func setShape(_ key: String, _ val: Any?) -> TransitionDuringAPI
    func getShape(_ key: String) -> Any?
    @discardableResult func setStyle(_ key: String, _ val: Any?) -> TransitionDuringAPI
    func getStyle(_ key: String) -> Any?
}

// upstream: const transitionInnerStore = makeInner<{ leaveToProps; userDuring }, Element>();
//   `makeInner` needs a class payload, so the two fields live on a small reference holder.
final class TransitionInnerStore {
    var leaveToProps: [String: Any]?
    var userDuring: ((TransitionDuringAPI) -> Void)?
    init() {}
}
private let transitionInnerStore: (Element) -> TransitionInnerStore = model.makeInner { TransitionInnerStore() }

// upstream: `${animationType}Animation` — the option key holding this phase's AnimationOption override.
private func animationPropKey(_ animationType: ECAnimType) -> String {
    switch animationType {
    case .enter: return "enterAnimation"
    case .update: return "updateAnimation"
    case .leave: return "leaveAnimation"
    }
}

private func animationScope(_ animationType: ECAnimType) -> String {
    switch animationType {
    case .enter: return "enter"
    case .update: return "update"
    case .leave: return "leave"
    }
}

private func getElementAnimationConfig(
    _ animationType: ECAnimType,   // upstream: 'enter' | 'update' | 'leave'
    _ el: Element,
    _ elOption: [String: Any],
    _ parentModel: Model?,
    _ dataIndex: Int? = nil
) -> ElementAnimateConfig {
    // upstream: getAnimationConfig(animationType, parentModel, dataIndex) || {}
    //   The Swift `getAnimationConfig` returns a (duration, delay, easing) tuple (or nil when animation
    //   is disabled) instead of a mutable ElementAnimateConfig, so unpack it into a fresh config.
    var config = ElementAnimateConfig()
    if let cfg = getAnimationConfig(animationType, parentModel, dataIndex ?? 0, nil, nil) {
        config.duration = cfg.duration
        config.delay = cfg.delay
        config.easing = cfg.easing
    }

    let userDuring = transitionInnerStore(el).userDuring
    // Only set when duration is > 0 and it's need to be animated.
    if (config.duration ?? 0) > 0 {
        // For simplicity, if during not specified, the previous during will not work any more.
        //   upstream: config.during = userDuring ? bind(duringCall, { el, userDuring }) : null;
        if let userDuring = userDuring {
            config.during = { _ in duringCall(el, userDuring) }
        } else {
            config.during = nil
        }
        config.setToFinal = true
        config.scope = animationScope(animationType)
    }

    // extend(config, elOption[animationProp]) — an AnimationOption override bag. Upstream copies ALL own
    //   keys of the AnimationOption ({ duration?, easing?, delay?, additive? }), so `additive` is included.
    if let anim = elOption[animationPropKey(animationType)] as? [String: Any] {
        if let d = toDouble(anim["duration"]) { config.duration = d }
        if let dl = toDouble(anim["delay"]) { config.delay = dl }
        if let e = anim["easing"] as? String { config.easing = .named(e) }
        else if let e = anim["easing"] as? AnimationEasing { config.easing = e }
        if let a = anim["additive"] as? Bool { config.additive = a }
    }
    return config
}

public func applyUpdateTransition(
    _ el: Element,
    _ elOption: [String: Any],
    _ animatableModel: Model?,
    _ opts: ApplyUpdateTransitionOpts? = nil
) {
    let opts = opts ?? ApplyUpdateTransitionOpts()
    let dataIndex = opts.dataIndex
    let isInit = opts.isInit ?? false
    let clearStyle = opts.clearStyle

    // upstream force-derefs `animatableModel.isAnimationEnabled()`; here the model is optional.
    let hasAnimation = animatableModel?.isAnimationEnabled() ?? false
    // Save the meta info for further morphing. Like apply on the sub morphing elements.
    let store = transitionInnerStore(el)
    let styleOpt = elOption["style"] as? [String: Any]
    store.userDuring = elOption["during"] as? ((TransitionDuringAPI) -> Void)

    var transFromProps: [String: Any] = [:]
    var propsToSet: [String: Any] = [:]

    prepareTransformAllPropsFinal(el, elOption, &propsToSet)

    if el.type == "compound" {
        // We cannot directly clone shape for compoundPath, because it makes the path to be an object
        //   instead of a Path instance, and thus missing `buildPath` method.
        // TODO: compound-path branch. Upstream writes a `.shape` dict directly onto each child
        //   `Path` element (`prepareShapeOrExtraAllPropsFinal('shape', optionPaths[i], paths[i])`),
        //   relying on Path's dynamic-object `shape`. Path.shape is a typed value-struct here, so the
        //   per-child final-shape application needs a typed bridge (as in CustomView.applyShape). Rare
        //   (compound custom elements); deferred — the non-compound path below is fully wired.
    }
    else {
        prepareShapeOrExtraAllPropsFinal("shape", elOption, &propsToSet)
        prepareShapeOrExtraAllPropsFinal("extra", elOption, &propsToSet)
    }

    if !isInit && hasAnimation {
        prepareTransformTransitionFrom(el, elOption, &transFromProps)
        prepareShapeOrExtraTransitionFrom("shape", el, elOption, &transFromProps)
        prepareShapeOrExtraTransitionFrom("extra", el, elOption, &transFromProps)
        prepareStyleTransitionFrom(el, elOption, styleOpt, &transFromProps)
    }

    if let styleOpt = styleOpt {
        propsToSet["style"] = styleOpt
    }

    applyPropsDirectly(el, &propsToSet, clearStyle)
    applyMiscProps(el, elOption)

    if hasAnimation {
        if isInit {
            var enterFromProps: [String: Any] = [:]
            for propName in ELEMENT_ANIMATABLE_PROPS {
                // upstream: const prop = propName ? elOption[propName] : elOption;
                let prop: [String: Any]? = propName.isEmpty ? elOption : (elOption[propName] as? [String: Any])
                if let prop = prop, let enterFrom = prop["enterFrom"] as? [String: Any] {
                    if !propName.isEmpty {
                        var sub = (enterFromProps[propName] as? [String: Any]) ?? [:]
                        _ = util.extend(&sub, enterFrom)
                        enterFromProps[propName] = sub
                    } else {
                        _ = util.extend(&enterFromProps, enterFrom)
                    }
                }
            }
            let config = getElementAnimationConfig(.enter, el, elOption, animatableModel, dataIndex)
            if (config.duration ?? 0) > 0 {
                el.animateFrom(enterFromProps, config)
            }
        }
        else {
            applyPropsTransition(el, elOption, dataIndex ?? 0, animatableModel, transFromProps)
        }
    }
    // Store leave to be used in leave transition.
    updateLeaveTo(el, elOption)

    if styleOpt != nil {
        el.dirty()
    } else {
        el.markRedraw()
    }
}

public func updateLeaveTo(_ el: Element, _ elOption: [String: Any]) {
    // Try merge to previous set leaveTo
    let store = transitionInnerStore(el)
    var leaveToProps: [String: Any]? = store.leaveToProps
    for i in 0..<ELEMENT_ANIMATABLE_PROPS.count {
        let propName = ELEMENT_ANIMATABLE_PROPS[i]
        let prop: [String: Any]? = propName.isEmpty ? elOption : (elOption[propName] as? [String: Any])
        if let prop = prop, let leaveTo = prop["leaveTo"] as? [String: Any] {
            if leaveToProps == nil {
                leaveToProps = [:]
            }
            if !propName.isEmpty {
                var sub = (leaveToProps?[propName] as? [String: Any]) ?? [:]
                _ = util.extend(&sub, leaveTo)
                leaveToProps?[propName] = sub
            } else {
                var merged = leaveToProps ?? [:]
                _ = util.extend(&merged, leaveTo)
                leaveToProps = merged
            }
        }
    }
    store.leaveToProps = leaveToProps
}

public func applyLeaveTransition(
    _ el: Element,
    _ elOption: [String: Any],
    _ animatableModel: Model,
    _ onRemove: (() -> Void)? = nil
) {
    // upstream guards `if (el)`; `el` is non-optional here.
    let parent = el.parent as? Group
    let leaveToProps = transitionInnerStore(el).leaveToProps
    if let leaveToProps = leaveToProps {
        // TODO TODO use leave after leaveAnimation in series is introduced
        // TODO Data index?
        var config = getElementAnimationConfig(.update, el, elOption, animatableModel, 0)
        // note (divergence, intentional): `el` and `parent` are captured WEAKLY. The config is handed
        //   to `el.animateTo` below, so a strong capture would form el -> animator -> done -> el, a cycle
        //   that only breaks when the animation completes; a chart disposed mid-leave-transition would leak
        //   the whole element subtree. Upstream relies on JS GC and has no equivalent hazard.
        config.done = { [weak el, weak parent] in
            if let el = el {
                parent?.remove(el)
            }
            onRemove?()
        }
        el.animateTo(leaveToProps, config)
    }
    else {
        parent?.remove(el)
        onRemove?()
    }
}

public func isTransitionAll(_ transition: Any?) -> Bool {
    return (transition as? String) == "all"
}

private func applyPropsDirectly(
    _ el: Element,
    // Can be null/undefined
    _ allPropsFinal: inout [String: Any],
    _ clearStyle: Bool?
) {
    let styleOpt = allPropsFinal["style"] as? [String: Any]
    if !el.isGroup, let styleOpt = styleOpt, let disp = el as? Displayable {
        if clearStyle == true {
            disp.useStyle(CommonStyleProps())

            // When style object changed, how to trade the existing animation? See upstream comment: to
            //   continue an in-flight `style` init animation the animator must be re-pointed at the new
            //   style object after `useStyle`.
            let animators = el.animators
            for i in 0..<animators.count {
                let animator = animators[i]
                if animator.targetName == "style" {
                    // TODO: animator.changeTarget((el as Displayable).style). The Swift style
                    //   accessor is a per-Displayable reference bridge (PathStyleAnimationAccessor); a
                    //   faithful retarget needs that accessor exposed. Rare (mid-init style clear);
                    //   deferred.
                    _ = animator
                }
            }
        }
        // (el as Displayable).setStyle(styleOpt) — merge the style dict into the typed style bag.
        //   Routed through `attr(["style": dict])` (Path.attrKV merges a partial style dict, coercing
        //   Int→Double). note: a non-Path Displayable (Text/Image) types `style` as CommonStyleProps
        //   and only round-trips the shared keys — the same typed-struct FRAMEWORK GAP the consumers note.
        _ = disp.attr(["style": styleOpt])
    }

    // Not set style here. Set el to the final state firstly, then restore styleOpt onto the bag.
    allPropsFinal["style"] = nil
    _ = el.attr(allPropsFinal)
    if let styleOpt = styleOpt {
        allPropsFinal["style"] = styleOpt
    }
}

private func applyPropsTransition(
    _ el: Element,
    _ elOption: [String: Any],
    _ dataIndex: Int,
    _ model: Model?,
    // Can be null/undefined (always a dict here — see applyUpdateTransition).
    _ transFromProps: [String: Any]?
) {
    if let transFromProps = transFromProps {
        let config = getElementAnimationConfig(.update, el, elOption, model, dataIndex)
        if (config.duration ?? 0) > 0 {
            el.animateFrom(transFromProps, config)
        }
    }
}

private func applyMiscProps(
    _ el: Element,
    _ elOption: [String: Any]
) {
    // Merge by default.
    if elOption["silent"] != nil, let v = elOption["silent"] as? Bool { el.silent = v }
    if elOption["ignore"] != nil, let v = elOption["ignore"] as? Bool { el.ignore = v }
    if let disp = el as? Displayable {
        if elOption["invisible"] != nil, let v = elOption["invisible"] as? Bool { disp.invisible = v }
    }
    if let path = el as? Path {
        if elOption["autoBatch"] != nil, let v = elOption["autoBatch"] as? Bool { path.autoBatch = v }
    }
}

// Use it to avoid it be exposed to user.
private final class TmpDuringScope {
    var el: Element?
}
private let tmpDuringScope = TmpDuringScope()

private final class TransitionDuringAPIImpl: TransitionDuringAPI {
    // Usually other props do not need to be changed in animation during.
    @discardableResult func setTransform(_ key: String, _ val: Double) -> TransitionDuringAPI {
        // upstream __DEV__ assert(hasOwn(TRANSFORM_PROPS_MAP, key), ...): dev-only guard, dropped.
        tmpDuringScope.el?.animationSet(key, val)
        return self
    }
    func getTransform(_ key: String) -> Double {
        return (tmpDuringScope.el?.animationGet(key) as? Double) ?? 0
    }
    func setShape(_ key: String, _ val: Any?) -> TransitionDuringAPI {
        if let path = tmpDuringScope.el as? Path {
            _ = path.setShape(key, val)   // upstream: shape[key] = val; el.dirtyShape();
        }
        return self
    }
    func getShape(_ key: String) -> Any? {
        return (tmpDuringScope.el as? Path)?.shape?.animationGet(key)
    }
    func setStyle(_ key: String, _ val: Any?) -> TransitionDuringAPI {
        if let text = tmpDuringScope.el as? ZRText {
            // ZRText renders from `textStyle` rather than Displayable's common `style` bag.
            // The inherited per-key setter intentionally only knows common keys, so routing
            // custom-series `during` updates through it silently drops `text` (and the other
            // text-only fields). `attr` dispatches to ZRText.attrKV and merges into textStyle.
            _ = text.attr("style", [key: val])
        }
        else if let disp = tmpDuringScope.el as? Displayable, disp.style != nil {
            // upstream __DEV__ warns when val is NaN; dropped (dev-only).
            _ = disp.setStyle(key, val)
        }
        return self
    }
    func getStyle(_ key: String) -> Any? {
        if let text = tmpDuringScope.el as? ZRText {
            return (text.animationGet("style") as? AnimationTarget)?.animationGet(key)
        }
        return (tmpDuringScope.el as? Displayable)?.style?.animationGet(key)
    }
    func setExtra(_ key: String, _ val: Any?) -> TransitionDuringAPI {
        var extra = tmpDuringScope.el?.extra ?? [:]
        extra[key] = val
        tmpDuringScope.el?.extra = extra
        return self
    }
    func getExtra(_ key: String) -> Any? {
        return tmpDuringScope.el?.extra?[key]
    }
}
private let transitionDuringAPI: TransitionDuringAPI = TransitionDuringAPIImpl()

private func duringCall(_ el: Element, _ userDuring: @escaping (TransitionDuringAPI) -> Void) {
    // Do not provide "percent" until some requirements come (see upstream comment).
    // If el is removed from zr by reason like legend, during still needs to be called.
    // TODO: upstream releases the scope when `transitionInnerStore(el).userDuring !== scopeUserDuring`
    //   to ensure a during is only called once per frame. Swift closures are not identity-comparable, so
    //   that de-dup guard is dropped; the user during may fire once per active animator in a frame.
    tmpDuringScope.el = el
    // Give no `this` to user in "during" calling.
    userDuring(transitionDuringAPI)
}

private func prepareShapeOrExtraTransitionFrom(
    _ mainAttr: String,   // 'shape' | 'extra'
    _ fromEl: Element,
    _ elOption: [String: Any],
    _ transFromProps: inout [String: Any]
) {
    let attrOpt = elOption[mainAttr] as? [String: Any]
    guard let attrOpt = attrOpt else {
        return
    }

    // upstream: `const elPropsInAttr = (fromEl as LooseElementProps)[mainAttr];` — the element's live
    //   'shape' / 'extra' bag. Here that bag is a typed value-struct (shape) or a dict (extra) with no
    //   uniform key enumeration, so it is sampled per-key via `looseElementValue` below. `hasAttr`
    //   reproduces the `if (elPropsInAttr)` truthy guard.
    guard elementHasAttr(fromEl, mainAttr) else {
        return
    }

    var transFromPropsInAttr: [String: Any] = (transFromProps[mainAttr] as? [String: Any]) ?? [:]
    var touched = false

    let transition = elOption["transition"]
    let attrTransition = attrOpt["transition"]
    if attrTransition != nil {
        touched = true
        if isTransitionAll(attrTransition) {
            // upstream: extend(transFromPropsInAttr, elPropsInAttr) copies ALL live keys. PathShape has
            //   no key enumeration, so approximate with the option's keys (the keys actually being
            //   animated). note: minor fidelity gap for keys present on the live shape but absent
            //   from the option.
            let keysInAttr = util.keys(attrOpt)
            for key in keysInAttr where key != "transition" {
                if let elVal = looseElementValue(fromEl, mainAttr, key) {
                    transFromPropsInAttr[key] = elVal
                }
            }
        }
        else {
            let transitionKeys: [String] = model.normalizeToArray(attrTransition)
            for i in 0..<transitionKeys.count {
                let key = transitionKeys[i]
                let elVal = looseElementValue(fromEl, mainAttr, key)
                if let elVal = elVal { transFromPropsInAttr[key] = elVal }
            }
        }
    }
    else if isTransitionAll(transition) || transitionIndexOf(transition, mainAttr) >= 0 {
        touched = true
        // upstream iterates `keys(elPropsInAttr)` (all live keys) then filters by
        //   `isNonStyleTransitionEnabled(attrOpt[key], elVal)`. A key NOT present in `attrOpt`
        //   (attrOpt[key] == undefined) fails that filter, so iterating only `attrOpt` keys is
        //   equivalent to iterating the live keys and filtering.
        let elPropsInAttrKeys = util.keys(attrOpt)
        for i in 0..<elPropsInAttrKeys.count {
            let key = elPropsInAttrKeys[i]
            if key == "transition" { continue }
            let elVal = looseElementValue(fromEl, mainAttr, key)
            if isNonStyleTransitionEnabled(attrOpt[key], elVal) {
                if let elVal = elVal { transFromPropsInAttr[key] = elVal }
            }
        }
    }

    if touched {
        transFromProps[mainAttr] = transFromPropsInAttr
    }
}

private func prepareShapeOrExtraAllPropsFinal(
    _ mainAttr: String,   // 'shape' | 'extra'
    _ elOption: [String: Any],
    _ allProps: inout [String: Any]
) {
    let attrOpt = elOption[mainAttr] as? [String: Any]
    guard let attrOpt = attrOpt else {
        return
    }
    var allPropsInAttr: [String: Any] = [:]
    let keysInAttr = util.keys(attrOpt)
    for i in 0..<keysInAttr.count {
        let key = keysInAttr[i]
        // To avoid share one object with different element, and to avoid user modify the object
        //   inexpectedly, have to clone.
        if let cloned = cloneValue(attrOpt[key]) {
            allPropsInAttr[key] = cloned
        }
    }
    allProps[mainAttr] = allPropsInAttr
}

private func prepareTransformTransitionFrom(
    _ el: Element,
    _ elOption: [String: Any],
    _ transFromProps: inout [String: Any]
) {
    let transition = elOption["transition"]
    let transitionKeys: [String] = isTransitionAll(transition)
        ? TRANSFORMABLE_PROPS
        : model.normalizeToArray(transition ?? [])
    for i in 0..<transitionKeys.count {
        let key = transitionKeys[i]
        if key == "style" || key == "shape" || key == "extra" {
            continue
        }
        let elVal = el.animationGet(key)
        // upstream __DEV__ checkTransformPropRefer(key, 'el.transition') — dev-only warn, dropped.
        // Do not clone, animator will perform that clone.
        transFromProps[key] = elVal
    }
}

private func prepareTransformAllPropsFinal(
    _ el: Element,
    _ elOption: [String: Any],
    _ allProps: inout [String: Any]
) {
    for i in 0..<LEGACY_TRANSFORM_PROPS_MAP.count {
        let legacyName = LEGACY_TRANSFORM_PROPS_MAP[i].legacy
        let xyName = LEGACY_TRANSFORM_PROPS_MAP[i].xy
        if let legacyArr = elOption[legacyName] as? [Any], legacyArr.count >= 2 {
            allProps[xyName[0]] = legacyArr[0]
            allProps[xyName[1]] = legacyArr[1]
        }
    }

    for i in 0..<TRANSFORMABLE_PROPS.count {
        let key = TRANSFORMABLE_PROPS[i]
        if elOption[key] != nil {
            allProps[key] = elOption[key]
        }
    }
}

private func prepareStyleTransitionFrom(
    _ fromEl: Element,
    _ elOption: [String: Any],
    _ styleOpt: [String: Any]?,
    _ transFromProps: inout [String: Any]
) {
    guard let styleOpt = styleOpt else {
        return
    }

    // upstream: `const fromElStyle = (fromEl as LooseElementProps).style;` — sampled per-key below via
    //   the style animation accessor; `guard` reproduces the `if (fromElStyle)` truthy check.
    guard let fromDisp = fromEl as? Displayable, fromDisp.style != nil else {
        return
    }

    var transFromStyleProps: [String: Any] = (transFromProps["style"] as? [String: Any]) ?? [:]
    var touched = false

    let styleTransition = styleOpt["transition"]
    let elTransition = elOption["transition"]
    if styleTransition != nil && !isTransitionAll(styleTransition) {
        let transitionKeys: [String] = model.normalizeToArray(styleTransition)
        touched = true
        for i in 0..<transitionKeys.count {
            let key = transitionKeys[i]
            let elVal = fromDisp.style?.animationGet(key)
            // Do not clone, see `checkNonStyleTansitionRefer`.
            if let elVal = elVal { transFromStyleProps[key] = elVal }
        }
    }
    else if isTransitionAll(elTransition)
        || isTransitionAll(styleTransition)
        || transitionIndexOf(elTransition, "style") >= 0 {
        // upstream: `const animationProps = getAnimationStyleProps(); const animationStyleProps =
        //   animationProps ? animationProps.style : null;` — the wrapper is shaped `["style": ["fill":
        //   true, ...]]`, so the inner `.style` sub-dict must be unwrapped before checking per-key.
        //   `touched`/`transFromProps.style` is only set when that inner bag is present (upstream gate).
        let animationProps = fromDisp.getAnimationStyleProps()
        if let animationStyleProps = animationProps["style"] as? [String: Any] {
            touched = true
            let styleKeys = util.keys(styleOpt)
            for i in 0..<styleKeys.count {
                let key = styleKeys[i]
                if animationStyleProps[key] != nil {
                    let elVal = fromDisp.style?.animationGet(key)
                    if let elVal = elVal { transFromStyleProps[key] = elVal }
                }
            }
        }
    }

    if touched {
        transFromProps["style"] = transFromStyleProps
    }
}

private func isNonStyleTransitionEnabled(_ optVal: Any?, _ elVal: Any?) -> Bool {
    // The same as `checkNonStyleTansitionRefer`.
    if !util.isArrayLike(optVal) {
        if let d = toDouble(optVal) {
            return d.isFinite
        }
        return false   // optVal == null (or non-numeric)
    }
    // optVal !== elVal (array reference / value inequality)
    return !anyEqual(optVal, elVal)
}

// ---- small helpers (dict-model shims) ----

// upstream `if ((fromEl as LooseElementProps)[mainAttr])` — does the element carry a live 'shape' /
//   'extra' bag? (`shape` is a typed value-struct on a Path; `extra` is a `[String: Any]?`.)
private func elementHasAttr(_ el: Element, _ mainAttr: String) -> Bool {
    if mainAttr == "extra" {
        return el.extra != nil
    }
    if mainAttr == "shape" {
        return (el as? Path)?.shape != nil
    }
    return false
}

// Read a single live shape/extra key off the element (accessor-backed) — the per-key form of upstream's
//   `elPropsInAttr[key]`. PathShape exposes keyed reads via `animationGet`.
private func looseElementValue(_ el: Element, _ mainAttr: String, _ key: String) -> Any? {
    if mainAttr == "extra" {
        return el.extra?[key]
    }
    if mainAttr == "shape" {
        return (el as? Path)?.shape?.animationGet(key)
    }
    return nil
}

// zrUtil.indexOf(transition, key) >= 0 — `transition` is a String or [String].
private func transitionIndexOf(_ transition: Any?, _ key: String) -> Double {
    if let arr = transition as? [String] {
        return util.indexOf(arr, key)
    }
    if let s = transition as? String {
        return s == key ? 0 : -1
    }
    return -1
}

// Numeric coercion (Int/Double/NSNumber → Double); the option bags box literals as Int.
private func toDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// upstream `optVal !== elVal` for the isNonStyleTransitionEnabled array branch — best-effort value
//   equality for the primitive / array shapes the option bags carry.
private func anyEqual(_ a: Any?, _ b: Any?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (x?, y?):
        if let dx = toDouble(x), let dy = toDouble(y) { return dx == dy }
        if let sx = x as? String, let sy = y as? String { return sx == sy }
        if let ax = x as? [Double], let ay = y as? [Double] { return ax == ay }
        return false
    default: return false
    }
}
