// Ported from echarts/src/component/graphic/GraphicView.ts — keep in sync with upstream
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

import Foundation
import ZRenderKit

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit).
//   import { TextStyleProps } from 'zrender/src/graphic/Text';       -> ZRenderKit `TextStyleProps`.
//   import Displayable from 'zrender/src/graphic/Displayable';       -> ZRenderKit `Displayable`.
//   import Element from 'zrender/src/Element';                       -> ZRenderKit `Element`.
//   import * as modelUtil from '../../util/model';                   -> `model.*` (util/modelUtil.swift).
//   import * as graphicUtil from '../../util/graphic';               -> PORT-NOTE: `util/graphic.ts` NOT
//     ported as a namespace. `graphicUtil.Group`/`Image`/`Text` are the ZRenderKit `Group`/`ZRImage`/
//     `ZRText`. `graphicUtil.getShapeClass` (shape registry) and `graphicUtil.setTooltipConfig` are
//     DEFERRED (see `newEl` / `_updateElements`).
//   import * as layoutUtil from '../../util/layout';                 -> `layout.*` (util/layout.swift).
//     `layout.positionElement` / `layout.LOCATION_PARAMS` are referenced as newDeps (not yet ported).
//   import { parsePercent } from '../../util/number';                -> `number.parsePercent`.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel`.
//   import ComponentView from '../../view/Component';                -> `ComponentView` (view/ComponentView.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI`.
//   import { getECData } from '../../util/innerStore';               -> `innerStore.getECData`.
//   import { isEC4CompatibleStyle, convertFromEC4CompatibleStyle } from '../../util/styleCompat';
//     -> DEFERRED: `util/styleCompat.ts` NOT ported (EC4 back-compat style conversion).
//   import { ElementMap, GraphicComponentModel, GraphicComponentDisplayableOption,
//     GraphicComponentZRPathOption, GraphicComponentGroupOption, GraphicComponentElementOption }
//     from './GraphicModel';                                        -> sibling GraphicModel.swift.
//   import { applyLeaveTransition, applyUpdateTransition, isTransitionAll, updateLeaveTo }
//     from '../../animation/customGraphicTransition';               -> DEFERRED (transition system).
//   import { updateProps } from '../../animation/basicTransition';  -> DEFERRED (animation system).
//   import { applyKeyframeAnimation, stopPreviousKeyframeAnimationAndRestore }
//     from '../../animation/customGraphicKeyframeAnimation';        -> DEFERRED (keyframe animation).

// upstream:
//   const nonShapeGraphicElements = {
//       path: null, compoundPath: null,      // Reserved but not supported in graphic component.
//       group: graphicUtil.Group, image: graphicUtil.Image, text: graphicUtil.Text
//   } as const;
// Realized inline in `newEl` (Swift cannot store heterogeneous class metatypes keyed by string as a
// `const` dictionary cleanly); the string set of supported non-shape types is preserved there.

// upstream:
//   export const inner = modelUtil.makeInner<{
//       width: number; height: number; isNew: boolean;
//       id: string; type: string; option: GraphicComponentElementOption
//   }, Element>();
final class GraphicInnerStore {
    var width: Double = 0
    var height: Double = 0
    var isNew: Bool = false
    var id: String = ""
    var type: String = ""
    var option: GraphicComponentElementOption?
    init() {}
}
private let inner: (Element) -> GraphicInnerStore = model.makeInner { GraphicInnerStore() }

// ------------------------
// View
// ------------------------
// upstream: export class GraphicComponentView extends ComponentView
open class GraphicComponentView: ComponentView {

    // static type = 'graphic';
    public static let graphicType = "graphic"
    // type = GraphicComponentView.type; — ComponentView has no `type` stored prop; kept as a static.

    // upstream: private _elMap: ElementMap;
    // PORT-NOTE: defaulted to a fresh HashMap at declaration (and re-set in `init`) so `render` never
    //   sees a nil map even if the framework skips the `init()` lifecycle hook. Base ComponentView
    //   forbids declaration-place init only for the legacy `extend` hazard, which is N/A in Swift.
    private var _elMap: ElementMap = createHashMap()
    // upstream: private _lastGraphicModel: GraphicComponentModel;
    private var _lastGraphicModel: GraphicComponentModel?

    // upstream: init() { this._elMap = zrUtil.createHashMap(); }
    //   Upstream declares `init()` with no params; the base lifecycle hook here is
    //   `init(ecModel, api)`. Overridden to match; the args are ignored (as upstream).
    open override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._elMap = createHashMap()
    }

    // upstream: render(graphicModel: GraphicComponentModel, ecModel, api): void
    //   The base `ComponentView.render` signature carries `payload` (unused here); downcast the model.
    open override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let graphicModel = model as! GraphicComponentModel

        // Having leveraged between use cases and algorithm complexity, a very
        // simple layout mechanism is used:
        // The size(width/height) can be determined by itself or its parent (not
        // implemented yet), but can not by its children. (Top-down travel)
        // The location(x/y) can be determined by the bounding rect of itself
        // (can including its descendants or not) and the size of its parent.
        // (Bottom-up travel)

        // When `chart.clear()` or `chart.setOption({...}, true)` with the same id,
        // view will be reused.
        if graphicModel !== self._lastGraphicModel {
            self._clear()
        }
        self._lastGraphicModel = graphicModel

        self._updateElements(graphicModel)
        self._relocate(graphicModel, api)
    }

    /**
     * Update graphic elements.
     */
    // upstream: private _updateElements(graphicModel): void
    private func _updateElements(_ graphicModel: GraphicComponentModel) {
        let elOptionsToUpdate = graphicModel.useElOptionsToUpdate()

        guard let elOptionsToUpdate = elOptionsToUpdate else {
            return
        }

        let elMap = self._elMap
        let rootGroup = self.group

        let globalZ = graphicModel.get("z") as? Double
        let globalZLevel = graphicModel.get("zlevel") as? Double

        // Top-down tranverse to assign graphic settings to each elements.
        util.each(elOptionsToUpdate) { elOption, _ in
            let id = model.convertOptionIdName(elOption.id, nil)
            let elExisting: Element? = id != nil ? elMap.get(id) : nil
            let parentId = model.convertOptionIdName(elOption.parentId, nil)
            let targetElParent: Group? = (parentId != nil ? (elMap.get(parentId) as? Group) : rootGroup)

            let elType = elOption.type
            let elOptionStyle = elOption["style"] as? [String: Any]
            if elType == "text", var elOptionStyle = elOptionStyle {
                // In top/bottom mode, textVerticalAlign should not be used, which cause
                // inaccurately locating.
                if let hv = elOption.hv, hv.count > 1, hv[1] {
                    elOptionStyle["textVerticalAlign"] = nil
                    elOptionStyle["textBaseline"] = nil
                    elOptionStyle["verticalAlign"] = nil
                    elOptionStyle["align"] = nil
                    elOption["style"] = elOptionStyle
                }
            }

            let textContentOption = elOption["textContent"] as? [String: Any]
            let textConfig = elOption["textConfig"] as? [String: Any]
            // upstream:
            //   if (elOptionStyle && isEC4CompatibleStyle(elOptionStyle, elType, !!textConfig, !!textContentOption)) {
            //       const convertResult = convertFromEC4CompatibleStyle(elOptionStyle, elType, true);
            //       if (!textConfig && convertResult.textConfig) { textConfig = elOption.textConfig = convertResult.textConfig; }
            //       if (!textContentOption && convertResult.textContent) { textContentOption = convertResult.textContent; }
            //   }
            // PORT-NOTE (deferred): requires `util/styleCompat` (isEC4CompatibleStyle /
            //   convertFromEC4CompatibleStyle), NOT ported (EC4 back-compat). Modern (EC5+) style options
            //   do not hit this branch; `textConfig`/`textContentOption` keep their option values.

            // Remove unnecessary props to avoid potential problems.
            let elOptionCleaned = getCleanedElOption(elOption)

            // For simple, do not support parent change, otherwise reorder is needed.
            if __DEV__ {
                if let elExisting = elExisting {
                    util.assert(
                        targetElParent === elExisting.parent,
                        "Changing parent is not supported."
                    )
                }
            }

            let action = elOption.action ?? "merge"
            let isMerge = action == "merge"
            let isReplace = action == "replace"
            if isMerge {
                let isInit = elExisting == nil
                var el = elExisting
                if isInit {
                    el = createEl(id, targetElParent, elOption.type, elMap)
                }
                else {
                    if let el = el { inner(el).isNew = false }
                    // Stop and restore before update any other attributes.
                    // PORT-NOTE (deferred): requires keyframe animation — stopPreviousKeyframeAnimationAndRestore(el).
                }
                if let el = el {
                    applyUpdateTransitionStatic(el, elOptionCleaned)
                    updateCommonAttrs(el, elOption, globalZ, globalZLevel)
                }
            }
            else if isReplace {
                removeEl(elExisting, elOption, elMap, graphicModel)
                let el = createEl(id, targetElParent, elOption.type, elMap)
                if let el = el {
                    applyUpdateTransitionStatic(el, elOptionCleaned)
                    updateCommonAttrs(el, elOption, globalZ, globalZLevel)
                }
            }
            else if action == "remove" {
                // PORT-NOTE (deferred): requires leave transition — updateLeaveTo(elExisting, elOption).
                removeEl(elExisting, elOption, elMap, graphicModel)
            }

            let el: Element? = id != nil ? elMap.get(id) : nil

            if let el = el, let textContentOption = textContentOption {
                if isMerge {
                    let textContentExisting = el.getTextContent()
                    if let textContentExisting = textContentExisting {
                        _ = textContentExisting.attr(textContentOption)
                    }
                    else {
                        el.setTextContent(ZRText(textContentOption))
                    }
                }
                else if isReplace {
                    el.setTextContent(ZRText(textContentOption))
                }
            }

            if let el = el {
                // upstream: const clipPathOption = elOption.clipPath;
                let clipPathOption = elOption.clipPath as? [String: Any]
                if let clipPathOption = clipPathOption {
                    let clipPathType = clipPathOption["type"] as? String
                    var clipPath: Path?
                    var isInit = false
                    if isMerge {
                        let oldClipPath = el.getClipPath()
                        isInit = oldClipPath == nil
                            || inner(oldClipPath!).type != clipPathType
                        clipPath = isInit ? (newEl(clipPathType ?? "") as? Path) : oldClipPath
                    }
                    else if isReplace {
                        isInit = true
                        clipPath = newEl(clipPathType ?? "") as? Path
                    }

                    if let clipPath = clipPath {
                        el.setClipPath(clipPath)
                        applyUpdateTransitionStatic(clipPath, GraphicComponentElementOption(clipPathOption))
                        // PORT-NOTE (deferred): requires keyframe animation — applyKeyframeAnimation(clipPath, clipPathOption.keyframeAnimation, graphicModel).
                    }
                }

                let elInner = inner(el)

                // upstream: el.setTextConfig(textConfig)
                //   `Element.setTextConfig` takes the typed `ElementTextConfig` struct (not the raw
                //   `[String: Any]` bag). Bridge the common keys; nil bag → nil (faithful no-op).
                el.setTextConfig(bridgeElementTextConfig(textConfig))

                elInner.option = elOption
                setEventData(el, graphicModel, elOption)

                // PORT-NOTE (deferred): requires graphicUtil.setTooltipConfig — setTooltipConfig({ el,
                //   componentModel: graphicModel, itemName: el.name, itemTooltipOption: elOption.tooltip }).

                // PORT-NOTE (deferred): requires keyframe animation — applyKeyframeAnimation(el, elOption.keyframeAnimation, graphicModel).
            }
        }
    }

    /**
     * Locate graphic elements.
     */
    // upstream: private _relocate(graphicModel, api): void
    private func _relocate(_ graphicModel: GraphicComponentModel, _ api: ExtensionAPI) {
        let elOptions = graphicModel.option.flatMap { ($0 as? [String: Any])?["elements"] as? [GraphicComponentElementOption] } ?? []
        let rootGroup = self.group
        let elMap = self._elMap
        let apiWidth = api.getWidth()
        let apiHeight = api.getHeight()

        let xy = ["x", "y"]

        // Top-down to calculate percentage width/height of group
        for i in 0..<elOptions.count {
            let elOption = elOptions[i]
            let id = model.convertOptionIdName(elOption.id, nil)
            let el: Element? = id != nil ? elMap.get(id) : nil

            if el == nil || !(el!.isGroup) {
                continue
            }
            let parentEl = el!.parent
            let isParentRoot = (parentEl === rootGroup)
            // Like 'position:absolut' in css, default 0.
            let elInner = inner(el!)
            let parentElInner: GraphicInnerStore? = parentEl != nil ? inner(parentEl! as! Element) : nil
            elInner.width = jsOr0(number.parsePercent(
                elInner.option?.width,
                isParentRoot ? apiWidth : (parentElInner?.width ?? 0)
            ))
            elInner.height = jsOr0(number.parsePercent(
                elInner.option?.height,
                isParentRoot ? apiHeight : (parentElInner?.height ?? 0)
            ))
        }

        // Bottom-up tranvese all elements (consider ec resize) to locate elements.
        var i = elOptions.count - 1
        while i >= 0 {
            let elOption = elOptions[i]
            let id = model.convertOptionIdName(elOption.id, nil)
            let el: Element? = id != nil ? elMap.get(id) : nil

            guard let el = el else {
                i -= 1
                continue
            }

            let parentEl = el.parent
            let parentElInner: GraphicInnerStore? = parentEl != nil ? inner(parentEl! as! Element) : nil
            let containerInfo: BoundingRect = (parentEl === rootGroup)
                ? BoundingRect(0, 0, apiWidth, apiHeight)
                : BoundingRect(0, 0, parentElInner?.width ?? 0, parentElInner?.height ?? 0)

            // PENDING
            // Currently, when `bounding: 'all'`, the union bounding rect of the group
            // does not include the rect of [0, 0, group.width, group.height], which
            // is probably weird for users. Should we make a break change for it?
            //
            // upstream:
            //   const layoutPos = {} as Record<'x' | 'y', number>;
            //   const layouted = layoutUtil.positionElement(
            //       el, elOption, containerInfo, null,
            //       { hv: elOption.hv, boundingMode: elOption.bounding }, layoutPos);
            //
            // PORT-NOTE: `layout.positionElement` (util/layout.swift) is ported and called below.
            //   Per CONVENTIONS §3 the `out` param is dropped: it returns
            //   `(layouted: Bool, out: [String: Double])` (out carries the computed x/y).
            let posResult = layout.positionElement(
                el, elOption.option, containerInfo, nil,
                ["hv": elOption.hv as Any, "boundingMode": elOption.bounding as Any]
            )
            let layouted = posResult.layouted
            let layoutPos = posResult.out

            if !inner(el).isNew && layouted {
                let transition = elOption.transition
                var animatePos: [String: Double] = [:]
                for k in 0..<xy.count {
                    let key = xy[k]
                    let val = layoutPos[key] ?? 0
                    // upstream: if (transition && (isTransitionAll(transition) || zrUtil.indexOf(transition, key) >= 0))
                    // PORT-NOTE (deferred): requires customGraphicTransition.isTransitionAll → treated as
                    //   false; the `zrUtil.indexOf(transition, key) >= 0` arm handles the `transition: ['x','y']` case.
                    if jsTruthy(transition) && transitionIndexOf(transition, key) >= 0 {
                        animatePos[key] = val
                    }
                    else {
                        // el[key] = val;
                        _ = el.attr(key, val)
                    }
                }
                // PORT-NOTE (deferred): updateProps(el, animatePos, graphicModel, 0) — the transition tween
                //   is a deliberate static-render deviation; the animated x/y are applied directly (no
                //   tween) so the final geometry is correct.
                for (key, val) in animatePos {
                    _ = el.attr(key, val)
                }
            }
            else {
                _ = el.attr(layoutPos.mapValues { $0 as Any })
            }

            i -= 1
        }
    }

    /**
     * Clear all elements.
     */
    // upstream: private _clear(): void
    private func _clear() {
        let elMap = self._elMap
        elMap.each { el, _ in
            removeEl(el, inner(el).option, elMap, self._lastGraphicModel)
        }
        self._elMap = createHashMap()
    }

    // upstream: dispose(): void { this._clear(); }
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._clear()
    }
}

// upstream: function newEl(graphicType: string)
private func newEl(_ graphicType: String) -> Element? {
    if __DEV__ {
        util.assert(!graphicType.isEmpty, "graphic type MUST be set")
    }

    // upstream:
    //   const Clz = (zrUtil.hasOwn(nonShapeGraphicElements, graphicType)
    //       ? nonShapeGraphicElements[graphicType]
    //       : graphicUtil.getShapeClass(graphicType)) as { new(opt): Element };
    //   ... const el = new Clz({});
    let el: Element?
    switch graphicType {
    case "group":
        el = Group([:])
    case "image":
        el = ZRImage([:])
    case "text":
        el = ZRText([:])
    case "path", "compoundPath":
        // Reserved but not supported in graphic component (upstream maps these to `null`).
        el = nil
    default:
        // graphicUtil.getShapeClass(graphicType)
        el = getShapeClass(graphicType).map { $0(nil) }
    }

    if __DEV__ {
        util.assert(el != nil, "graphic type \(graphicType) can not be found")
    }

    if let el = el {
        inner(el).type = graphicType
    }
    return el
}

// upstream: function createEl(id, targetElParent, graphicType, elMap): Element
private func createEl(
    _ id: String?,
    _ targetElParent: Group?,
    _ graphicType: String?,
    _ elMap: ElementMap
) -> Element? {

    let el = newEl(graphicType ?? "")

    guard let el = el else {
        return nil
    }

    _ = targetElParent?.add(el)
    elMap.set(id, el)
    inner(el).id = id ?? ""
    inner(el).isNew = true

    return el
}

// upstream: function removeEl(elExisting, elOption, elMap, graphicModel): void
private func removeEl(
    _ elExisting: Element?,
    _ elOption: GraphicComponentElementOption?,
    _ elMap: ElementMap,
    _ graphicModel: GraphicComponentModel?
) {
    let existElParent = elExisting?.parent
    if let existElParent = existElParent {
        _ = existElParent
        if elExisting!.type == "group" {
            elExisting!.traverse { el in
                removeEl(el, elOption, elMap, graphicModel)
            }
        }
        // PORT-NOTE (deferred): requires customGraphicTransition.applyLeaveTransition(elExisting, elOption,
        //   graphicModel) — leave transition. Static fallback: detach from parent immediately.
        if let p = elExisting!.parent as? Group {
            _ = p.remove(elExisting!)
        }
        // elMap.removeKey(inner(elExisting).id);
        // PORT-NOTE: `HashMap.removeKey` is present on the ported HashMap shim (util/modelUtil.swift)
        //   and called below.
        elMap.removeKey(inner(elExisting!).id)
    }
}

// upstream: function updateCommonAttrs(el, elOption, defaultZ, defaultZlevel)
private func updateCommonAttrs(
    _ el: Element,
    _ elOption: GraphicComponentElementOption,
    _ defaultZ: Double?,
    _ defaultZlevel: Double?
) {
    if !el.isGroup {
        // upstream iterates [['cursor', Displayable.prototype.cursor], ['zlevel', defaultZlevel || 0],
        //   ['z', defaultZ || 0], ['z2', 0]] and retrieve2()s option-or-default.
        let items: [(String, Any)] = [
            ("cursor", "pointer"),   // Displayable.prototype.cursor default
            // We should not support configure z and zlevel in the element level.
            // But seems we didn't limit it previously. So here still use it to avoid breaking.
            ("zlevel", (defaultZlevel != nil && defaultZlevel! != 0) ? defaultZlevel! : 0.0),
            ("z", (defaultZ != nil && defaultZ! != 0) ? defaultZ! : 0.0),
            // z2 must not be null/undefined, otherwise sort error may occur.
            ("z2", 0.0)
        ]
        for item in items {
            let prop = item.0
            if elOption.option[prop] != nil {   // zrUtil.hasOwn(elOption, prop)
                // zrUtil.retrieve2(elOption[prop], item[1]) ≡ elOption[prop] ?? item[1] (value present).
                _ = el.attr(prop, elOption.option[prop] ?? item.1)
            }
            else {
                // else if ((el as any)[prop] == null) { (el as any)[prop] = item[1]; }
                // PORT-NOTE: Swift cannot read arbitrary `el[prop]` back generically; set the default
                //   unconditionally when the option does not specify it (matches the common case where
                //   a freshly created element has no explicit z/z2/cursor).
                _ = el.attr(prop, item.1)
            }
        }
    }

    // Assign event handlers.
    // PORT-NOTE (deferred): the `on*` event-handler assignment loop requires the interaction/events layer
    //   (out of static-render scope): upstream copies each `on<Event>` function from the option onto the element.

    // if (zrUtil.hasOwn(elOption, 'draggable')) { el.draggable = elOption.draggable; }
    // PORT-NOTE (deferred): `el.draggable` (ElementDraggable) is interaction; drag not wired this phase.

    // Other attributes
    if elOption.name != nil {   // elOption.name != null && (el.name = elOption.name)
        el.name = model.convertOptionIdName(elOption.name, "") ?? ""
    }
    if elOption.id != nil {     // elOption.id != null && ((el as any).id = elOption.id)
        // PORT-NOTE: upstream sets a dynamic `el.id`; Element has no `id` slot in ZRenderKit, so this
        //   is tracked via `inner(el).id` (set in createEl). No-op here.
    }
}

// Remove unnecessary props to avoid potential problems.
// upstream: function getCleanedElOption(elOption): Omit<GraphicComponentElementOption, 'textContent'>
private func getCleanedElOption(_ elOption: GraphicComponentElementOption) -> GraphicComponentElementOption {
    // elOption = zrUtil.extend({}, elOption);
    var bag: [String: Any] = [:]
    util.extend(&bag, elOption.option)
    let cleaned = GraphicComponentElementOption(bag)
    // zrUtil.each(['id', 'parentId', '$action', 'hv', 'bounding', 'textContent', 'clipPath']
    //     .concat(layoutUtil.LOCATION_PARAMS), function (name) { delete elOption[name]; });
    // PORT-NOTE: `layout.LOCATION_PARAMS` (util/layout.swift) is ported and used below.
    let names = ["id", "parentId", "$action", "hv", "bounding", "textContent", "clipPath"]
        + layout.LOCATION_PARAMS
    util.each(names) { name, _ in
        cleaned.option[name] = nil
    }
    return cleaned
}

// upstream: function setEventData(el, graphicModel, elOption): void
private func setEventData(
    _ el: Element,
    _ graphicModel: GraphicComponentModel,
    _ elOption: GraphicComponentElementOption
) {
    let ecData = innerStore.getECData(el)
    var eventData = ecData.eventData
    // Simple optimize for large amount of elements that no need event.
    if !el.silent && !el.ignore && eventData == nil {
        var data: [String: Any] = [:]
        data["componentType"] = "graphic"
        data["componentIndex"] = graphicModel.componentIndex
        data["name"] = el.name
        eventData = data
        ecData.eventData = data
    }

    // `elOption.info` enables user to mount some info on
    // elements and use them in event handlers.
    if var eventData = eventData {
        eventData["info"] = elOption["info"]
        ecData.eventData = eventData
    }
}

// ================================================================================================
// Static-render substitute for `applyUpdateTransition` (animation/customGraphicTransition).
//
// PORT-NOTE (deferred): `applyUpdateTransition(el, elOption, animatableModel, {isInit})` (animation/
//   customGraphicTransition) runs the full enter/update transition: it splits the option into transition
//   vs non-transition props, animates the transition props (updateProps/updatePropsFromKeyframe), and
//   applies the rest immediately. The transition/animation half is deferred (customGraphicTransition not
//   ported). The static substitute below applies the cleaned option
//   directly (`el.attr`), which is exactly the no-transition-config result — the correct final
//   geometry/style. `Element.attr` consumes the `[String: Any]` bag (shape/style/x/y/rotation/...).
// ================================================================================================
private func applyUpdateTransitionStatic(_ el: Element, _ elOption: GraphicComponentElementOption) {
    _ = el.attr(elOption.option)
}

// ---- small JS-semantics shims (per-file, matching the port's convention) ----

// `x || 0` where x is a Double that may be NaN/0 (parsePercent result).
private func jsOr0(_ v: Double) -> Double {
    return (v.isNaN || v == 0) ? 0 : v
}

// JS truthiness for the deferred `transition` value.
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let arr as [Any]: return !arr.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    default: return true
    }
}

// zrUtil.indexOf(transition, key) >= 0 — `transition` is a string or string[].
private func transitionIndexOf(_ transition: Any?, _ key: String) -> Double {
    if let arr = transition as? [String] {
        return util.indexOf(arr, key)
    }
    if let s = transition as? String {
        return s == key ? 0 : -1
    }
    return -1
}

// Bridge a raw `textConfig` option bag into the typed `ElementTextConfig` struct. Minimal faithful
// mapping of the common keys; PORT-NOTE: `rich`/union-typed fields not fully bridged.
private func bridgeElementTextConfig(_ bag: [String: Any]?) -> ElementTextConfig? {
    guard let bag = bag else {
        return nil
    }
    var cfg = ElementTextConfig()
    cfg.position = bag["position"]
    cfg.rotation = bag["rotation"] as? Double
    cfg.offset = bag["offset"] as? [Double]
    cfg.origin = bag["origin"]
    cfg.distance = bag["distance"] as? Double
    cfg.local = bag["local"] as? Bool
    cfg.insideFill = bag["insideFill"] as? String
    cfg.insideStroke = bag["insideStroke"] as? String
    cfg.outsideFill = bag["outsideFill"] as? String
    cfg.outsideStroke = bag["outsideStroke"] as? String
    cfg.inside = bag["inside"] as? Bool
    return cfg
}
