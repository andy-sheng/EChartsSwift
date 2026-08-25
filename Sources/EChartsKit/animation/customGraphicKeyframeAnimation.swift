// Ported from echarts/src/animation/customGraphicKeyframeAnimation.ts — keep in sync with upstream.
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

// Helpers for creating keyframe-based animations in custom series and graphic components (option
//   `keyframeAnimation: { duration, loop, keyframes: [{ percent, easing, style/shape/... }] }`).
//
// upstream imports (mapped):
//   import { ELEMENT_ANIMATABLE_PROPS } from './customGraphicTransition';  -> provided by
//     animation/customGraphicTransition.swift (public top-level `let`, same module).
//   import { getAnimationConfig } from './basicTransition';  -> animation/basicTransition.swift.
//   import { makeInner } from '../util/model';               -> EChartsKit `model.makeInner`.
//   Element / Animator / AnimationEasing                     -> ZRenderKit.

import Foundation
import ZRenderKit

// upstream: import { ELEMENT_ANIMATABLE_PROPS } from './customGraphicTransition';
//   Now provided by animation/customGraphicTransition.swift (public top-level `let`, same module).
//   The former local duplicate was removed — customGraphicTransition is the SINGLE OWNER.

// upstream: const KEYFRAME_EXCLUDE_KEYS = ['percent', 'easing', 'shape', 'style', 'extra'];
private let KEYFRAME_EXCLUDE_KEYS: Set<String> = ["percent", "easing", "shape", "style", "extra"]

// upstream: type StateToRestore = Dictionary<any>;  const getStateToRestore = makeInner<StateToRestore, Element>();
//   `makeInner` requires a class payload, so the dict lives on a small reference holder.
private final class KeyframeStateToRestore {
    var props: [String: Any] = [:]
}
private let getStateToRestore: (Element) -> KeyframeStateToRestore = model.makeInner { KeyframeStateToRestore() }

// JS truthiness helper for the dynamic option bag values used here.
private func kfTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

private func kfDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// upstream `(el as any)[targetPropName]` existence test: does the element carry this animatable sub-bag?
private func kfElHasProp(_ el: Element, _ prop: String) -> Bool {
    switch prop {
    case "": return true
    case "style": return el is Displayable       // Path / ZRText / ZRImage all render from a style bag
    case "shape": return el is Path
    case "extra": return el.extra != nil
    default: return false
    }
}

// upstream: reads `((targetPropName ? (el as any)[targetPropName] : el) || {})[key]` for the state-restore
//   snapshot. Route through the element's animation accessors (same machinery the Animator reads with).
private func kfReadValue(_ el: Element, _ prop: String, _ key: String) -> Any? {
    if prop.isEmpty {
        return el.animationGet(key)
    }
    if let sub = el.animationGet(prop) as? AnimationTarget {
        return sub.animationGet(key)
    }
    if prop == "extra" {
        return el.extra?[key]
    }
    return nil
}

/**
 * Stop previous keyframe animation and restore the attributes.
 * Avoid new keyframe animation starts with wrong internal state when the percent: 0 is not set.
 */
// upstream: export function stopPreviousKeyframeAnimationAndRestore(el: Element)
public func stopPreviousKeyframeAnimationAndRestore(_ el: Element) {
    // Stop previous keyframe animation.
    el.stopAnimation("keyframe")
    // Restore.
    let store = getStateToRestore(el)
    if !store.props.isEmpty {
        _ = el.attr(store.props)
    }
}

// upstream: export function applyKeyframeAnimation(el, animationOpts, animatableModel)
public func applyKeyframeAnimation(_ el: Element, _ animationOptsAny: Any?, _ animatableModel: Model) {
    if animatableModel.isAnimationEnabled() != true || !kfTruthy(animationOptsAny) {
        return
    }

    // upstream: if (isArray(animationOpts)) { each(...); return; }
    if let list = animationOptsAny as? [Any] {
        for single in list {
            applyKeyframeAnimation(el, single, animatableModel)
        }
        return
    }
    guard let animationOpts = animationOptsAny as? [String: Any] else { return }

    let keyframes = animationOpts["keyframes"] as? [[String: Any]]
    var duration = kfDouble(animationOpts["duration"])

    if duration == nil {
        // Default to use duration of config.
        let config = getAnimationConfig(.enter, animatableModel, 0, nil)
        duration = config?.duration
    }

    guard let keyframesUnwrapped = keyframes, !keyframesUnwrapped.isEmpty,
          let durationUnwrapped = duration, durationUnwrapped != 0 else {
        return
    }

    let loop = animationOpts["loop"] as? Bool
    let delay = kfDouble(animationOpts["delay"]) ?? 0
    let optEasing = (animationOpts["easing"] as? String).map { AnimationEasing.named($0) }

    let stateToRestore = getStateToRestore(el)

    // Sort keyframes by percent (once — shared across all animatable-prop passes).
    let sortedKeyframes = keyframesUnwrapped.sorted { (kfDouble($0["percent"]) ?? 0) < (kfDouble($1["percent"]) ?? 0) }

    for targetPropName in ELEMENT_ANIMATABLE_PROPS {
        // upstream: if (targetPropName && !(el as any)[targetPropName]) return;  (skip absent sub-bag)
        if !targetPropName.isEmpty && !kfElHasProp(el, targetPropName) {
            continue
        }

        var animator: Animator<Any>? = nil

        for kf in sortedKeyframes {
            let animators = el.animators
            // kfValues = targetPropName ? kf[targetPropName] : kf
            let kfValues: [String: Any]?
            if targetPropName.isEmpty {
                kfValues = kf
            } else {
                kfValues = kf[targetPropName] as? [String: Any]
            }
            guard let kfValuesUnwrapped = kfValues else { continue }

            // propKeys = keys(kfValues); for the root pass, drop the meta/sub-bag keys.
            var propKeys = Array(kfValuesUnwrapped.keys)
            if targetPropName.isEmpty {
                propKeys = propKeys.filter { !KEYFRAME_EXCLUDE_KEYS.contains($0) }
            }
            if propKeys.isEmpty {
                continue
            }

            if animator == nil {
                // upstream: el.animate(targetPropName, animationOpts.loop, true). Pass nil for the root
                //   pass so `targetName` is not set (JS treats '' as falsy — see Element.animate).
                animator = el.animate(targetPropName.isEmpty ? nil : targetPropName, loop, true)
                // Upstream `Element.animate('style'|'shape'|'extra')` constructs the Animator with
                // that sub-object itself as its target. Swift's Element.animate keeps the host element
                // as a deferred target because the concrete style/shape bags are value types; point the
                // keyframe animator at the reference accessor now so it can read the initial values and
                // write every sampled frame. `_updateAnimationTargets` still re-points this accessor if
                // a later state application swaps the underlying bag.
                if !targetPropName.isEmpty,
                   let target = el.animationGet(targetPropName) {
                    animator!.changeTarget(target)
                }
                animator!.scope = "keyframe"
            }
            // Stop all other (non-keyframe) animators driving the same tracks on the same target.
            for other in animators where other !== animator! && other.targetName == animator!.targetName {
                _ = other.stopTracks(propKeys)
            }

            // Save original values so stopPreviousKeyframeAnimationAndRestore can restore them.
            if targetPropName.isEmpty {
                for key in propKeys {
                    stateToRestore.props[key] = kfReadValue(el, "", key) as Any
                }
            } else {
                var saved = (stateToRestore.props[targetPropName] as? [String: Any]) ?? [:]
                for key in propKeys {
                    saved[key] = kfReadValue(el, targetPropName, key) as Any
                }
                stateToRestore.props[targetPropName] = saved
            }

            let kfEasing = (kf["easing"] as? String).map { AnimationEasing.named($0) }
            _ = animator!.whenWithKeys(durationUnwrapped * (kfDouble(kf["percent"]) ?? 0), kfValuesUnwrapped, propKeys, kfEasing)
        }

        guard let animatorUnwrapped = animator else { continue }

        _ = animatorUnwrapped
            .delay(delay)
            .duration(durationUnwrapped)
            .start(optEasing)
    }
}
