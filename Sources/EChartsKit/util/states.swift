// Ported from echarts/src/util/states.ts — keep in sync with upstream
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
//
// PHASE-30 PORT — the emphasis/blur/select STATE ENGINE. This is the core of the interaction
// layer's visual-state application: highlight/downplay/select/blur actions ultimately land here.
//
// upstream imports (resolved to the ported modules):
//   import Displayable, { DisplayableState } from 'zrender/src/graphic/Displayable';  → ZRenderKit.Displayable
//   import Element, { ElementEvent } from 'zrender/src/Element';                       → ZRenderKit.Element
//   import Model from '../model/Model';                                                → model/Model.swift
//   import { ... } from './types';                                                     → sibling types.swift
//   import { extend, indexOf, isArrayLike, isObject, keys, isArray, each } from '.../util';  → util.*
//   import { getECData } from './innerStore';                                          → innerStore.getECData
//   import { liftColor } from 'zrender/src/tool/color';                                → color.liftColor
//   import { queryDataIndex, makeInner } from './model';                               → model.queryDataIndex / model.makeInner
//   import Path, { PathStyleProps } from 'zrender/src/graphic/Path';                   → ZRenderKit.Path
//   import ExtensionAPI, { getViewOfComponentOrSeries } from '../core/ExtensionAPI';   → core/ExtensionAPI.swift
//
// ───────────────────────────── PORT DEVIATION (the two-phase collapse) ─────────────────────────────
// Upstream is TWO-PHASE: `singleEnterEmphasis`/etc. ONLY set a flag (`el.hoverState` / `el.selected`)
// and note "States will be applied in the echarts.ts in next frame" — the render loop later reads
// those flags in `applyChangedStates` and calls `el.useState('emphasis')` / `useStates([...])`.
//
// The scene-graph `Element` here does NOT carry the echarts-internal `hoverState` / `selected` /
// `__highByOuter` / `__highDownDispatcher` fields (they live on the `ECElement` protocol in
// util/types.swift, which `Element` does not conform to). So those extended props are held in a
// per-element side store (`getHighDownInner`, built with `model.makeInner`, exactly like `getECData`).
// AND — because there is no live per-frame `applyChangedStates` host yet — this port COLLAPSES the two
// phases: after mutating the flag, `singleEnter*/singleLeave*` immediately re-derive and apply the ZR
// state list via `applyElementStates(el)` → `el.useStates([...])`. Same observable result (the element
// ends in the emphasis/blur/select ZR state), one frame earlier. When the live render-loop host lands,
// `applyElementStates` moves into `applyChangedStates` and the `singleEnter*` bodies revert to flag-only.

import Foundation
import ZRenderKit

// Free-function module → caseless enum namespace named after the file (CONVENTIONS §2).
// upstream call sites `enterEmphasis(el)` / `isHighDownDispatcher(el)` → `states.enterEmphasis(el)` / …
public enum states {

    // ───────────────────────────── constants (states.ts:78-94) ─────────────────────────────

    public static let HOVER_STATE_NORMAL: Double = 0
    public static let HOVER_STATE_BLUR: Double = 1
    public static let HOVER_STATE_EMPHASIS: Double = 2

    public static let SPECIAL_STATES = ["emphasis", "blur", "select"]
    public static let DISPLAY_STATES = ["normal", "emphasis", "blur", "select"]

    public static let Z2_EMPHASIS_LIFT: Double = 10
    public static let Z2_SELECT_LIFT: Double = 9

    public static let HIGHLIGHT_ACTION_TYPE = "highlight"
    public static let DOWNPLAY_ACTION_TYPE = "downplay"

    public static let SELECT_ACTION_TYPE = "select"
    public static let UNSELECT_ACTION_TYPE = "unselect"
    public static let TOGGLE_SELECT_ACTION_TYPE = "toggleSelect"
    public static let SELECT_CHANGED_EVENT_TYPE = "selectchanged"

    // ───────────────────────────── side stores ─────────────────────────────
    //
    // upstream `type ExtendedProps = { __highByOuter, __highDownSilentOnTouch, __highDownDispatcher }`
    //   augment `Element` directly (`el as ExtendedElement`). `Element` here can not host them, so they
    //   (plus the two-phase flags `hoverState`/`selected` and the `onHoverStateChange` hook and the
    //   z2 lift overrides — all from the `ECElement` interface) live in this per-element bag.
    //   SCOPE (see the augmentation-strategy PORT-NOTE on `ECElement`, util/types.swift): this bag owns
    //   the HIGH-DOWN half of `ECElement` ONLY. Its NON-highDown props (`tooltipDisabled` and, when they
    //   land, `disableLabelAnimation`/`forceLabelAnimation`/`disableLabelLayout`/`disableMorphing`) live
    //   in `innerStore.ECElementProps` / `innerStore.getECElementProps` (util/innerStore.swift) — do not
    //   add them here, and do not create a third bag.
    public final class HighDownInner {
        // ExtendedProps
        public var __highByOuter: Int = 0
        public var __highDownSilentOnTouch: Bool = false
        public var __highDownDispatcher: Bool = false
        // ECElement two-phase flags (0 normal / 1 blur / 2 emphasis)
        public var hoverState: Double = 0
        public var selected: Bool = false
        // ECElement hooks / lifts
        public var onHoverStateChange: ((DisplayState) -> Void)?
        public var z2EmphasisLift: Double?
        public var z2SelectLift: Double?
        public init() {}
    }
    // upstream: `el as ExtendedElement`. Lazily-created per Element (empty bag), keyed by identity.
    public static let getHighDownInner: (Element) -> HighDownInner = model.makeInner { HighDownInner() }

    // upstream: `const getComponentStates = makeInner<{ isBlured: boolean }, SeriesModel | ComponentModel>()`.
    //   `SeriesModel` is a subclass of `ComponentModel`, so the store is keyed on `ComponentModel`.
    public final class ComponentStatesInner {
        public var isBlured: Bool = false
        public init() {}
    }
    public static let getComponentStates: (ComponentModel) -> ComponentStatesInner = model.makeInner { ComponentStatesInner() }

    // upstream: `const getSavedStates = makeInner<{ normalFill, normalStroke, selectFill?, selectStroke? }, Path>()`.
    //   Holds the pre-emphasis fill/stroke so `createEmphasisDefaultState` can lift them. Colors are the
    //   `Path` `ZRColor` enum. NOTE: this is `ZRenderKit.ZRColor` (cases `.string`/`.linearGradient`/…),
    //   which is a DISTINCT type from the sibling `EChartsKit.ZRColor` (case `.color(...)`) in
    //   util/types.swift — every Path-paint value here is explicitly qualified to dodge that collision.
    public final class SavedPathStates {
        public var normalFill: ZRenderKit.ZRColor?
        public var normalStroke: ZRenderKit.ZRColor?
        public var selectFill: ZRenderKit.ZRColor?
        public var selectStroke: ZRenderKit.ZRColor?
        public init() {}
    }
    public static let getSavedStates: (Path) -> SavedPathStates = model.makeInner { SavedPathStates() }

    // ───────────────────────────── low-level helpers ─────────────────────────────

    // upstream: `hasFillOrStroke(fillOrStroke)` — treats null / 'none' as "no paint".
    static func hasFillOrStroke(_ c: ZRenderKit.ZRColor?) -> Bool {
        guard let c = c else { return false }
        if case let .string(s) = c { return s != "none" }
        return true   // gradient / pattern → has paint
    }

    // upstream: `doChangeHoverState(el, stateName, hoverStateEnum)`.
    static func doChangeHoverState(_ el: Element, _ stateName: DisplayState, _ hoverStateEnum: Double) {
        let inner = getHighDownInner(el)
        if let cb = inner.onHoverStateChange, inner.hoverState != hoverStateEnum {
            cb(stateName)
        }
        inner.hoverState = hoverStateEnum
        // PORT DEVIATION (see header): apply the derived ZR state list now instead of next frame.
        applyElementStates(el)
    }

    // The collapsed `applyChangedStates`: derive the ZR state name list from the element's flags and
    //   apply it via the ZRenderKit `useStates` API. `select` can coexist with `emphasis`/`blur`;
    //   `emphasis` (2) and `blur` (1) are mutually exclusive (both live on the single `hoverState`).
    //   Emphasis is applied LAST so its z2 lift / style wins in the merge.
    static func applyElementStates(_ el: Element) {
        let inner = getHighDownInner(el)
        var stateList: [String] = []
        if inner.selected { stateList.append("select") }
        if inner.hoverState == HOVER_STATE_EMPHASIS { stateList.append("emphasis") }
        else if inner.hoverState == HOVER_STATE_BLUR { stateList.append("blur") }
        el.useStates(stateList)
    }

    // upstream: `singleEnterEmphasis` / `singleLeaveEmphasis` / `singleEnterBlur` / `singleLeaveBlur` /
    //   `singleEnterSelect` / `singleLeaveSelect`. Upstream only flips the flag (states applied next
    //   frame); here `doChangeHoverState` also applies (header deviation).
    static func singleEnterEmphasis(_ el: Element) {
        doChangeHoverState(el, .emphasis, HOVER_STATE_EMPHASIS)
    }
    static func singleLeaveEmphasis(_ el: Element) {
        if getHighDownInner(el).hoverState == HOVER_STATE_EMPHASIS {
            doChangeHoverState(el, .normal, HOVER_STATE_NORMAL)
        }
    }
    static func singleEnterBlur(_ el: Element) {
        doChangeHoverState(el, .blur, HOVER_STATE_BLUR)
    }
    static func singleLeaveBlur(_ el: Element) {
        if getHighDownInner(el).hoverState == HOVER_STATE_BLUR {
            doChangeHoverState(el, .normal, HOVER_STATE_NORMAL)
        }
    }
    static func singleEnterSelect(_ el: Element) {
        getHighDownInner(el).selected = true
        applyElementStates(el)
    }
    static func singleLeaveSelect(_ el: Element) {
        getHighDownInner(el).selected = false
        applyElementStates(el)
    }

    // upstream: `updateElementState(el, updater, commonParam)` — the `commonParam` generic is unused by
    //   every call site's updater in scope, so it is dropped (the updaters take only `el`).
    static func updateElementState(_ el: Element, _ updater: (Element) -> Void) {
        updater(el)
    }

    // upstream: `traverseUpdateState(el, updater, commonParam)` — apply to `el`, then (if a group) to
    //   every descendant. NOTE: `Element.traverse` (base) is a no-op; `Group.traverse` is the real one,
    //   so the group cast is required (they are overloads, not an override, in the ZRenderKit port).
    static func traverseUpdateState(_ el: Element, _ updater: (Element) -> Void) {
        updateElementState(el, updater)
        if el.isGroup, let g = el as? Group {
            _ = g.traverse({ child in updateElementState(child, updater); return false })
        }
    }

    // upstream: `setStatesFlag(el, stateName)` (states.ts:168). Flag-ONLY (matches upstream; does NOT
    //   apply — used by the render pipeline to restore a flag before re-applying elsewhere).
    public static func setStatesFlag(_ el: Element, _ stateName: DisplayState) {
        let inner = getHighDownInner(el)
        switch stateName {
        case .emphasis: inner.hoverState = HOVER_STATE_EMPHASIS
        case .normal:   inner.hoverState = HOVER_STATE_NORMAL
        case .blur:     inner.hoverState = HOVER_STATE_BLUR
        case .select:   inner.selected = true
        }
    }

    // upstream: `clearStates(el)` (states.ts:189). Recurse into groups; otherwise clear this element.
    public static func clearStates(_ el: Element) {
        if el.isGroup, let g = el as? Group {
            _ = g.traverse({ child in child.clearStates(); return false })
        }
        else {
            el.clearStates()
        }
    }

    // ───────────────────────────── stateProxy default-state creation ─────────────────────────────
    //
    // These synthesize the DEFAULT emphasis (color-lift) / blur (opacity ×0.1) / select (z2 lift) states
    // when the element does not define an explicit one. Ported faithfully against `Path.pathStyle`
    // (upstream `el.style`) and the `ElementState.style` prop-bag.
    //
    // PORT-NOTE: the synthesized `style` bag lands in `ElementState.style` (a `[String: Any]`). Whether
    //   that bag is actually pushed into `Path.pathStyle` on `useState` depends on Path's keyed
    //   animation accessor for the value-type `style` sub-bag, which ZRenderKit's Element.swift marks as
    //   deferred. So the DEFAULT color-lift / opacity dim is faithful but only becomes VISIBLE once
    //   that Displayable/Path style-bag accessor lands. View-DEFINED emphasis states (set directly on
    //   `el.states["emphasis"]`) are unaffected — `useStates` reads them regardless of this proxy.

    static func createEmphasisDefaultState(
        _ el: Displayable, _ targetStates: [String]?, _ inState: ElementState?
    ) -> ElementState? {
        let hasSelect = targetStates != nil && util.indexOf(targetStates, "select") >= 0
        var state = inState
        var cloned = false
        if let p = el as? Path {
            let store = getSavedStates(p)
            let fromFill = hasSelect ? (store.selectFill ?? store.normalFill) : store.normalFill
            let fromStroke = hasSelect ? (store.selectStroke ?? store.normalStroke) : store.normalStroke
            if hasFillOrStroke(fromFill) || hasFillOrStroke(fromStroke) {
                if state == nil { state = ElementState() }
                var emphasisStyle = state!.style ?? [:]
                // inherit case (store the un-emphasized fill directly; unwrap so it is NOT boxed as
                //   an Optional under the `[String: Any]` key — later `as? ZRColor` reads must succeed).
                if let fillStr = emphasisStyle["fill"] as? String, fillStr == "inherit" {
                    cloned = true
                    if let f = fromFill { emphasisStyle["fill"] = f }
                }
                // Apply default color lift
                else if !hasFillOrStroke(emphasisStyle["fill"] as? ZRenderKit.ZRColor) && hasFillOrStroke(fromFill) {
                    cloned = true
                    // Already being applied 'emphasis'. DON'T lift color multiple times.
                    if let f = liftZRColor(fromFill) { emphasisStyle["fill"] = f }
                }
                // Not highlight stroke if fill has been highlighted.
                else if !hasFillOrStroke(emphasisStyle["stroke"] as? ZRenderKit.ZRColor) && hasFillOrStroke(fromStroke) {
                    if let s = liftZRColor(fromStroke) { emphasisStyle["stroke"] = s }
                }
                state!.style = emphasisStyle
            }
        }
        if let s = state {
            // TODO Share with textContent?
            if s.props["z2"] == nil {
                _ = cloned   // (upstream clones-on-write; ElementState is already a fresh ref here)
                let z2Lift = getHighDownInner(el).z2EmphasisLift ?? Z2_EMPHASIS_LIFT
                s.props["z2"] = el.z2 + z2Lift
            }
        }
        return state
    }

    static func createSelectDefaultState(_ el: Displayable, _ inState: ElementState?) -> ElementState? {
        let state = inState
        if let s = state {
            if s.props["z2"] == nil {
                let z2Lift = getHighDownInner(el).z2SelectLift ?? Z2_SELECT_LIFT
                s.props["z2"] = el.z2 + z2Lift
            }
        }
        return state
    }

    // upstream: `getFromStateStyle(el, props, toStateName, defaultValue)` (states.ts:200). Specialized to
    //   the single `['opacity']` call site (createBlurDefaultState); returns the mined opacity. Reads
    //   `el.style.opacity` (falling back to `defaultOpacity` when nil), then lets any in-flight style
    //   animator that is NOT a transition INTO `toStateName` overwrite it with its FINAL-frame value via
    //   `animator.saveTo(fromState, ['opacity'])`. So blurring mid style-animation dims from the
    //   animation's end opacity, not the interpolated current value.
    static func getFromStateStyleOpacity(_ el: Displayable, _ toStateName: String, _ defaultOpacity: Double) -> Double {
        // upstream `fromState: PathStyleProps = {}` scratch object — `saveTo` writes via `animationSet`,
        //   so a plain AnimationTarget bag stands in for the JS style literal.
        let fromState = StyleStateScratch()
        fromState.values["opacity"] = el.style?.opacity ?? defaultOpacity
        for animator in el.animators {
            if let fst = animator.__fromStateTransition,
               // Don't consider the animation to the target (blur) state.
               !fst.contains(toStateName),
               animator.targetName == "style" {
                animator.saveTo(fromState, ["opacity"])
            }
        }
        if let o = fromState.values["opacity"] as? Double { return o }
        if let n = fromState.values["opacity"] as? NSNumber { return n.doubleValue }
        return defaultOpacity
    }

    // Scratch AnimationTarget backing `getFromStateStyleOpacity` (upstream's `{}` literal): `saveTo`
    //   pushes the animator's final-frame value here via `animationSet`.
    final class StyleStateScratch: AnimationTarget {
        var values: [String: Any?] = [:]
        func animationGet(_ key: String) -> Any? { return values[key] ?? nil }
        func animationSet(_ key: String, _ value: Any?) { values[key] = value }
    }

    static func createBlurDefaultState(_ el: Displayable, _ inState: ElementState?) -> ElementState? {
        let hasBlur = util.indexOf(el.currentStates, "blur") >= 0
        let currentOpacity = el.style?.opacity
        // upstream `getFromStateStyle(el, ['opacity'], 'blur', {opacity: 1})` — mines any in-flight
        //   non-blur style animator for its final opacity (see getFromStateStyleOpacity).
        let fromOpacity: Double = hasBlur ? 0 : getFromStateStyleOpacity(el, "blur", 1)

        let state = inState ?? ElementState()
        var blurStyle = state.style ?? [:]
        if blurStyle["opacity"] == nil {
            // Already being applied 'emphasis'. DON'T mul opacity multiple times.
            blurStyle["opacity"] = hasBlur ? (currentOpacity ?? 1) : (fromOpacity * 0.1)
            state.style = blurStyle
        }
        return state
    }

    // upstream `elementStateProxy(this, stateName, targetStates)`.
    static func elementStateProxy(_ el: Displayable, _ stateName: String, _ targetStates: [String]?) -> ElementState? {
        let state = el.states[stateName]
        if el.style != nil {
            if stateName == "emphasis" {
                return createEmphasisDefaultState(el, targetStates, state)
            }
            else if stateName == "blur" {
                return createBlurDefaultState(el, state)
            }
            else if stateName == "select" {
                return createSelectDefaultState(el, state)
            }
        }
        return state
    }

    // upstream: `setDefaultStateProxy(el)` (states.ts:348). Installs the default-state proxy on the
    //   element and its attached text/guide.
    public static func setDefaultStateProxy(_ el: Displayable) {
        el.stateProxy = { [weak el] stateName, targetStates in
            guard let el = el else { return nil }
            return elementStateProxy(el, stateName, targetStates)
        }
        // upstream states.ts:350-353 — install the SAME default-state proxy on the attached text/guide so
        //   they enter emphasis alongside the host. This is what applies `createEmphasisDefaultState`'s
        //   z2 lift (state.z2 = textContent.z2 + Z2_EMPHASIS_LIFT) to the LABEL: without it the host's z2
        //   lifts to 10 on hover while the label stays at 0, so the emphasized fill/area then sorts ABOVE
        //   the label and OCCLUDES it (themeRiver band hiding its own name, and any labeled emphasis
        //   element). `useState`/`useStates` already propagate the state name to textContent+textGuide
        //   (Element.useState), so once the proxy is installed the label restyles AND lifts with the host.
        if let textContent = el.getTextContent() {
            textContent.stateProxy = { [weak textContent] stateName, targetStates in
                guard let textContent = textContent else { return nil }
                return elementStateProxy(textContent, stateName, targetStates)
            }
        }
        if let textGuide = el.getTextGuideLine() {
            textGuide.stateProxy = { [weak textGuide] stateName, targetStates in
                guard let textGuide = textGuide else { return nil }
                return elementStateProxy(textGuide, stateName, targetStates)
            }
        }
    }

    // upstream `savePathStates(el)` (states.ts:910). Snapshot the current + select fill/stroke so the
    //   emphasis default lift derives from the un-emphasized paint.
    public static func savePathStates(_ el: Path) {
        let store = getSavedStates(el)
        store.normalFill = el.pathStyle?.fill
        store.normalStroke = el.pathStyle?.stroke
        let selectState = el.states["select"]
        store.selectFill = selectState?.style?["fill"] as? ZRenderKit.ZRColor
        store.selectStroke = selectState?.style?["stroke"] as? ZRenderKit.ZRColor
    }

    // Bridge: upstream `liftColor(fill as ColorString)` only lifts STRING colors. `Path`'s `ZRColor`
    //   enum and `color.liftColor`'s `ColorValue` enum are distinct types, so extract the string,
    //   lift it, and re-box. Gradient/pattern fills are returned unchanged (upstream casts to
    //   ColorString, i.e. only strings are lifted). PORT-NOTE: gradient lift.
    static func liftZRColor(_ c: ZRenderKit.ZRColor?) -> ZRenderKit.ZRColor? {
        guard let c = c else { return nil }
        if case let .string(s) = c {
            if case let .string(lifted) = color.liftColor(.string(s)) {
                return .string(lifted)
            }
        }
        return c
    }

    // ───────────────────────────── public enter/leave primitives ─────────────────────────────
    //
    // Phase 33: `enterEmphasisWhenMouseOver` / `leaveEmphasisWhenMouseOut` (states.ts:360-372) are now
    //   LIVE — the mouse-driven emphasis entry points bound by `EChartsView._initEvents`. They gate on
    //   `shouldSilent` (touch-silent) and on `__highByOuter` (an "emphasis" event highlight, set by
    //   `enterEmphasis`, has higher priority than a mouse hover), then apply/clear the single emphasis
    //   flag via `traverseUpdateState`. `handleGlobalMouseOver/OutForHighDown` (states.ts:638-695) —
    //   the global blur/focus fan-out — are ported below and bound by `EChartsView._initEvents`.

    // upstream: `enterEmphasisWhenMouseOver(el, e)` (states.ts:360). Mouse-over emphasis entry.
    //   `!shouldSilent(el, e) && !el.__highByOuter && traverseUpdateState(el, singleEnterEmphasis)`.
    public static func enterEmphasisWhenMouseOver(_ el: Element, _ e: ZRenderKit.ElementEvent) {
        if !shouldSilent(el, e) && getHighDownInner(el).__highByOuter == 0 {
            traverseUpdateState(el, singleEnterEmphasis)
        }
    }

    // upstream: `leaveEmphasisWhenMouseOut(el, e)` (states.ts:366). Mouse-out emphasis exit.
    //   `!shouldSilent(el, e) && !el.__highByOuter && traverseUpdateState(el, singleLeaveEmphasis)`.
    public static func leaveEmphasisWhenMouseOut(_ el: Element, _ e: ZRenderKit.ElementEvent) {
        if !shouldSilent(el, e) && getHighDownInner(el).__highByOuter == 0 {
            traverseUpdateState(el, singleLeaveEmphasis)
        }
    }

    // upstream: `enterEmphasis(el, highlightDigit?)` (states.ts:374).
    public static func enterEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        let inner = getHighDownInner(el)
        inner.__highByOuter |= 1 << Int(highlightDigit ?? 0)
        traverseUpdateState(el, singleEnterEmphasis)
    }

    // upstream: `leaveEmphasis(el, highlightDigit?)` (states.ts:379). Only actually leaves when EVERY
    //   outer highlight digit has been cleared (`!(__highByOuter &= ~(1 << digit))`).
    public static func leaveEmphasis(_ el: Element, _ highlightDigit: Double? = nil) {
        let inner = getHighDownInner(el)
        inner.__highByOuter &= ~(1 << Int(highlightDigit ?? 0))
        if inner.__highByOuter == 0 {
            traverseUpdateState(el, singleLeaveEmphasis)
        }
    }

    // upstream: `enterBlur(el)` (states.ts:384).
    public static func enterBlur(_ el: Element) {
        traverseUpdateState(el, singleEnterBlur)
    }

    // upstream: `leaveBlur(el)` (states.ts:388).
    public static func leaveBlur(_ el: Element) {
        traverseUpdateState(el, singleLeaveBlur)
    }

    // upstream: `enterSelect(el)` (states.ts:392).
    public static func enterSelect(_ el: Element) {
        traverseUpdateState(el, singleEnterSelect)
    }

    // upstream: `leaveSelect(el)` (states.ts:396).
    public static func leaveSelect(_ el: Element) {
        traverseUpdateState(el, singleLeaveSelect)
    }

    // upstream: `shouldSilent(el, e)` (states.ts:400). Used only by the mouse-over/out handlers (deferred);
    //   kept for fidelity.
    static func shouldSilent(_ el: Element, _ e: ElementEvent) -> Bool {
        return getHighDownInner(el).__highDownSilentOnTouch && (e.zrByTouch ?? false)
    }

    // ───────────────────────────── blur orchestration ─────────────────────────────

    // upstream: `allLeaveBlur(api)` (states.ts:404). Walk every component/series view and clear any blur.
    public static func allLeaveBlur(_ api: ExtensionAPI) {
        let ecModel = api.getModel()
        var leaveBlurredSeries: [SeriesModel] = []
        var allComponentViews: [ComponentView] = []
        ecModel.eachComponent({ (componentType, componentModel, _) in
            let componentStates = getComponentStates(componentModel)
            let view = getViewOfComponentOrSeries(api, componentModel)
            let isSeries = (componentType == "series")
            if !isSeries, let cv = view as? ComponentView {
                allComponentViews.append(cv)
            }
            if componentStates.isBlured {
                // Leave blur anyway
                _ = viewGroup(view)?.traverse({ child in singleLeaveBlur(child); return false })
                if isSeries, let sm = componentModel as? SeriesModel {
                    leaveBlurredSeries.append(sm)
                }
            }
            componentStates.isBlured = false
        })
        util.each(allComponentViews) { view, _ in
            view.toggleBlurSeries(leaveBlurredSeries, false, ecModel)
        }
    }

    // upstream: `blurSeries(targetSeriesIndex, focus, blurScope, api)` (states.ts:429). Blur every
    //   non-focused series/data according to `focus` + `blurScope`.
    public static func blurSeries(
        _ targetSeriesIndex: Double?,
        _ focus: InnerFocus?,
        _ blurScope: BlurScope?,
        _ api: ExtensionAPI
    ) {
        let ecModel = api.getModel()
        let effectiveBlurScope = blurScope ?? .coordinateSystem

        func leaveBlurOfIndices(_ data: SeriesData, _ dataIndices: [Double]) {
            for i in 0..<dataIndices.count {
                if let itemEl = data.getItemGraphicEl(Int(dataIndices[i])) {
                    leaveBlur(itemEl)
                }
            }
        }

        guard let targetSeriesIndex = targetSeriesIndex else { return }

        let fs = focusString(focus)
        // upstream `if (!focus || focus === 'none') return;`
        if isNullish(focus) || fs == "none" || fs == "" {
            return
        }

        guard let targetSeriesModel = ecModel.getSeriesByIndex(targetSeriesIndex) else { return }
        let targetCoordSys = resolveMaster(targetSeriesModel.coordinateSystem)

        var blurredSeries: [SeriesModel] = []

        ecModel.eachSeries { seriesModel, _ in
            let sameSeries = (targetSeriesModel === seriesModel)
            let coordSys = resolveMaster(seriesModel.coordinateSystem)
            let sameCoordSys = (coordSys != nil && targetCoordSys != nil)
                ? (coordSys === targetCoordSys)
                : sameSeries   // If there is no coordinate system, use sameSeries instead.
            // upstream negated guard: skip when this series should NOT be blurred.
            let skip =
                (effectiveBlurScope == .series && !sameSeries)
                || (effectiveBlurScope == .coordinateSystem && !sameCoordSys)
                || (fs == "series" && sameSeries)
            if !skip, let view = api.getViewOfSeriesModel(seriesModel) {
                // nil view → a legend-filtered / unrendered series; nothing to blur.
                _ = view.group.traverse({ child in
                    // Elements highlighted by other components (`__highByOuter`) that are still required
                    // to be highlighted (self-focus, same series) are skipped so focus-self can win.
                    if getHighDownInner(child).__highByOuter != 0 && sameSeries && fs == "self" {
                        return false
                    }
                    singleEnterBlur(child)
                    return false
                })

                if util.isArrayLike(focus) {
                    if let indices = focusIndices(focus) {
                        leaveBlurOfIndices(seriesModel.getData(), indices)
                    }
                }
                else if util.isObject(focus), let dict = focus as? [String: Any] {
                    let dataTypes = util.keys(dict)
                    for d in 0..<dataTypes.count {
                        let dt = dataTypes[d]
                        if let indices = focusIndices(dict[dt]) {
                            leaveBlurOfIndices(seriesModel.getData(SeriesDataType(rawValue: dt)), indices)
                        }
                    }
                }

                blurredSeries.append(seriesModel)
                getComponentStates(seriesModel).isBlured = true
            }
        }

        ecModel.eachComponent({ (componentType, componentModel, _) in
            if componentType == "series" { return }
            // upstream `if (view && view.toggleBlurSeries)` — a viewless component (e.g. polar) is skipped.
            guard let view = api.getViewOfComponentModel(componentModel) else { return }
            view.toggleBlurSeries(blurredSeries, true, ecModel)
        })
    }

    // upstream: `blurComponent(componentMainType, componentIndex, api)` (states.ts:519).
    public static func blurComponent(
        _ componentMainType: ComponentMainType?,
        _ componentIndex: Double?,
        _ api: ExtensionAPI
    ) {
        guard let componentMainType = componentMainType, let componentIndex = componentIndex else { return }
        guard let componentModel = api.getModel().getComponent(componentMainType, componentIndex) else { return }

        getComponentStates(componentModel).isBlured = true

        // upstream (states.ts:536): `if (!view || !view.focusBlurEnabled) { return; }` — only blur views
        //   that opt in (base `ComponentView.focusBlurEnabled` defaults false; currently just GeoView=true).
        guard let view = api.getViewOfComponentModel(componentModel), view.focusBlurEnabled else { return }
        _ = view.group.traverse({ child in singleEnterBlur(child); return false })
    }

    // upstream: `blurSeriesFromHighlightPayload(seriesModel, payload, api)` (states.ts:545).
    public static func blurSeriesFromHighlightPayload(
        _ seriesModel: SeriesModel,
        _ payload: Payload,
        _ api: ExtensionAPI
    ) {
        let seriesIndex = seriesModel.seriesIndex
        // upstream `payload.dataType` — a dynamic payload key (carried in `.other`).
        let dataType = payload.other["dataType"] as? SeriesDataType
        let data = seriesModel.getData(dataType)
        var dataIndex = model.queryDataIndex(data, payload)
        // Pick the first one if there are multiple / none.
        if let arr = dataIndex as? [Any] { dataIndex = arr.first }
        // `Int(Double.nan)` traps in Swift; upstream `|| 0` coerces a NaN/absent index → 0. Guard finite.
        let firstIdx: Int = (dataIndex as? Double).flatMap { $0.isFinite ? Int($0) : nil }
            ?? (dataIndex as? Int) ?? 0

        var el = data.getItemGraphicEl(firstIdx)
        if el == nil {
            let count = data.count()
            var current = 0
            // If data on dataIndex is NaN.
            while el == nil && current < count {
                el = data.getItemGraphicEl(current)
                current += 1
            }
        }

        if let el = el {
            let ecData = innerStore.getECData(el)
            blurSeries(seriesIndex, ecData.focus, ecData.blurScope, api)
        }
        else {
            // If there is no element on the data, try getting it from the raw option.
            let focus = seriesModel.get(["emphasis", "focus"])
            let blurScopeRaw = seriesModel.get(["emphasis", "blurScope"])
            let blurScope = (blurScopeRaw as? String).flatMap { BlurScope(rawValue: $0) } ?? (blurScopeRaw as? BlurScope)
            if !isNullish(focus) {
                blurSeries(seriesIndex, focus, blurScope, api)
            }
        }
    }

    // upstream: `findComponentHighDownDispatchers(componentMainType, componentIndex, name, api)`
    //   (states.ts:588). `dispatchers == nil` ⇔ upstream `dispatchers: null` = "feature not supported
    //   for this target" (the series path / a view without `findHighDownDispatchers`).
    public struct ComponentHighDownDispatchers {
        public var focusSelf: Bool
        // If nil, do not support this feature.
        public var dispatchers: [Element]?
    }

    public static func findComponentHighDownDispatchers(
        _ componentMainType: ComponentMainType?,
        _ componentIndex: Double?,
        _ name: String?,
        _ api: ExtensionAPI
    ) -> ComponentHighDownDispatchers {
        let ret = ComponentHighDownDispatchers(focusSelf: false, dispatchers: nil)
        guard let componentMainType = componentMainType,
              componentMainType != "series",
              let componentIndex = componentIndex,
              let name = name else {
            return ret
        }

        guard let componentModel = api.getModel().getComponent(componentMainType, componentIndex) else {
            return ret
        }

        guard let view = api.getViewOfComponentModel(componentModel),
              let dispatchers = view.findHighDownDispatchers(name) else {
            return ret
        }

        // At present, the component (like Geo) only blurs inside itself. So we do not use
        // `blurScope` in component.
        var focusSelf = false
        for i in 0..<dispatchers.count {
            if focusString(innerStore.getECData(dispatchers[i]).focus) == "self" {
                focusSelf = true
                break
            }
        }

        return ComponentHighDownDispatchers(focusSelf: focusSelf, dispatchers: dispatchers)
    }

    // upstream: `handleGlobalMouseOverForHighDown(dispatcher, e, api)` (states.ts:638). The zr
    //   mouseover fan-out: blur every non-focused element (per the dispatcher's `ecData.focus` /
    //   `blurScope`) THEN emphasize the hovered dispatcher.
    public static func handleGlobalMouseOverForHighDown(
        _ dispatcher: Element,
        _ e: ZRenderKit.ElementEvent,
        _ api: ExtensionAPI
    ) {
        let ecData = innerStore.getECData(dispatcher)

        let found = findComponentHighDownDispatchers(
            ecData.componentMainType, ecData.componentIndex, ecData.componentHighDownName, api
        )
        // If `findHighDownDispatchers` is supported on the component,
        // highlight/downplay elements with the same name.
        if let dispatchers = found.dispatchers {
            if found.focusSelf {
                blurComponent(ecData.componentMainType, ecData.componentIndex, api)
            }
            util.each(dispatchers) { d, _ in enterEmphasisWhenMouseOver(d, e) }
        }
        else {
            // Try blur all in the related series. Then emphasis the hoverred.
            // TODO. progressive mode.
            blurSeries(ecData.seriesIndex, ecData.focus, ecData.blurScope, api)
            if focusString(ecData.focus) == "self" {
                blurComponent(ecData.componentMainType, ecData.componentIndex, api)
            }
            // Other than series, component that not support `findHighDownDispatcher` will
            // also use it. But in this case, highlight/downplay are only supported in
            // mouse hover but not in dispatchAction.
            enterEmphasisWhenMouseOver(dispatcher, e)
        }
    }

    // upstream: `handleGlobalMouseOutForHighDown(dispatcher, e, api)` (states.ts:674). The zr
    //   mouseout fan-out: leave every blur, then de-emphasize the dispatcher(s).
    public static func handleGlobalMouseOutForHighDown(
        _ dispatcher: Element,
        _ e: ZRenderKit.ElementEvent,
        _ api: ExtensionAPI
    ) {
        allLeaveBlur(api)

        let ecData = innerStore.getECData(dispatcher)
        let found = findComponentHighDownDispatchers(
            ecData.componentMainType, ecData.componentIndex, ecData.componentHighDownName, api
        )
        if let dispatchers = found.dispatchers {
            util.each(dispatchers) { d, _ in leaveEmphasisWhenMouseOut(d, e) }
        }
        else {
            leaveEmphasisWhenMouseOut(dispatcher, e)
        }
    }

    // ───────────────────────────── selection ─────────────────────────────

    // upstream: `toggleSelectionFromPayload(seriesModel, payload, api)` (states.ts:698).
    public static func toggleSelectionFromPayload(
        _ seriesModel: SeriesModel,
        _ payload: Payload,
        _ api: ExtensionAPI
    ) {
        if !isSelectChangePayload(payload) { return }
        let dataType = payload.other["dataType"] as? SeriesDataType
        let data = seriesModel.getData(dataType)
        let dataIndexAny = model.queryDataIndex(data, payload)
        let dataIndex: [Double]
        if let arr = dataIndexAny as? [Double] { dataIndex = arr }
        else if let arr = dataIndexAny as? [Int] { dataIndex = arr.map(Double.init) }   // Int-array index
        else if let d = dataIndexAny as? Double { dataIndex = [d] }
        else if let i = dataIndexAny as? Int { dataIndex = [Double(i)] }
        else { dataIndex = [] }

        switch payload.type {
        case TOGGLE_SELECT_ACTION_TYPE: seriesModel.toggleSelect(dataIndex, dataType)
        case SELECT_ACTION_TYPE:        seriesModel.select(dataIndex, dataType)
        default:                        seriesModel.unselect(dataIndex, dataType)
        }
    }

    // upstream: `updateSeriesElementSelection(seriesModel)` (states.ts:720).
    public static func updateSeriesElementSelection(_ seriesModel: SeriesModel) {
        let allData = seriesModel.getAllData()
        util.each(allData) { entry, _ in
            entry.data.eachItemGraphicEl({ el, idx in
                if seriesModel.isSelected(Double(idx), entry.type) {
                    enterSelect(el)
                }
                else {
                    leaveSelect(el)
                }
            })
        }
    }

    // upstream: `getAllSelectedIndices(ecModel)` (states.ts:729).
    public struct SelectedIndicesItem {
        public var seriesIndex: Double
        public var dataType: SeriesDataType?
        public var dataIndex: [Double]
    }
    public static func getAllSelectedIndices(_ ecModel: GlobalModel) -> [SelectedIndicesItem] {
        var ret: [SelectedIndicesItem] = []
        ecModel.eachSeries { seriesModel, _ in
            let allData = seriesModel.getAllData()
            util.each(allData) { entry, _ in
                let dataIndices = seriesModel.getSelectedDataIndices()
                if dataIndices.count > 0 {
                    ret.append(SelectedIndicesItem(
                        seriesIndex: seriesModel.seriesIndex,
                        dataType: entry.type,
                        dataIndex: dataIndices
                    ))
                }
            }
        }
        return ret
    }

    // ───────────────────────────── states-from-model ─────────────────────────────

    // upstream: `OTHER_STATES` (states.ts:797) — `['emphasis', 'blur', 'select']` (== `SPECIAL_STATES`).
    // upstream: `defaultStyleGetterMap` (states.ts:798) — styleType → Model getter. Swift has no
    //   dynamic `model[getterName]()` dispatch, so it is a `switch` on `styleType` below.
    //
    // upstream: `setStatesStylesFromModel(el, itemModel, styleType?, getter?)` (states.ts:806).
    //   Reads the model's `emphasis` / `blur` / `select` sub-models' `[styleType]` (default `itemStyle`)
    //   and stores the resulting style bag onto the element's `emphasis`/`blur`/`select` state, so that
    //   activating a state (via `useState`) restyles the element. Faithful: `el.ensureState(name).style`.
    public static func setStatesStylesFromModel(
        _ el: Displayable,
        _ itemModel: Model,
        _ styleType: String? = nil,     // default itemStyle
        _ getter: ((Model) -> Dictionary<Any>)? = nil
    ) {
        let styleType = styleType ?? "itemStyle"
        for stateName in SPECIAL_STATES {   // upstream OTHER_STATES
            let model = itemModel.getModel([stateName, styleType])
            let state = el.ensureState(stateName)
            // upstream: `state.style = getter ? getter(model) : model[defaultStyleGetterMap[styleType]]()`
            if let getter = getter {
                state.style = getter(model)
            }
            else {
                switch styleType {
                case "itemStyle": state.style = model.getItemStyle()
                case "lineStyle": state.style = model.getLineStyle()
                case "areaStyle": state.style = model.getAreaStyle()
                default:
                    // PORT-NOTE: upstream `defaultStyleGetterMap[styleType]` is undefined for other
                    //   styleTypes and would throw ("Let it throw error if getterType is not found");
                    //   we fall back to `getItemStyle` rather than trap.
                    state.style = model.getItemStyle()
                }
            }
        }
    }

    // ───────────────────────────── highDown dispatcher / hover enable ─────────────────────────────

    // upstream: `enableHoverEmphasis(el, focus?, blurScope?)` (states.ts:762).
    public static func enableHoverEmphasis(_ el: Element, _ focus: InnerFocus? = nil, _ blurScope: BlurScope? = nil) {
        setAsHighDownDispatcher(el, true)
        traverseUpdateState(el, { child in
            if let d = child as? Displayable { setDefaultStateProxy(d) }
        })
        enableHoverFocus(el, focus, blurScope)
    }

    // upstream: `disableHoverEmphasis(el)` (states.ts:769).
    public static func disableHoverEmphasis(_ el: Element) {
        setAsHighDownDispatcher(el, false)
    }

    // upstream: `toggleHoverEmphasis(el, focus, blurScope, isDisabled)` (states.ts:773).
    public static func toggleHoverEmphasis(_ el: Element, _ focus: InnerFocus?, _ blurScope: BlurScope?, _ isDisabled: Bool) {
        if isDisabled { disableHoverEmphasis(el) }
        else { enableHoverEmphasis(el, focus, blurScope) }
    }

    // upstream: `enableHoverFocus(el, focus, blurScope)` (states.ts:778).
    public static func enableHoverFocus(_ el: Element, _ focus: InnerFocus?, _ blurScope: BlurScope?) {
        let ecData = innerStore.getECData(el)
        if !isNullish(focus) {
            ecData.focus = focus
            ecData.blurScope = blurScope
        }
        else if ecData.focus != nil {
            ecData.focus = nil
        }
    }

    // upstream: `setAsHighDownDispatcher(el, asDispatcher)` (states.ts:842).
    public static func setAsHighDownDispatcher(_ el: Element, _ asDispatcher: Bool) {
        let disable = (asDispatcher == false)
        let inner = getHighDownInner(el)
        // upstream: Make `highDownSilentOnTouch` only work after `setAsHighDownDispatcher` is called
        //   (avoid it being modified by user unexpectedly). Copy `(el as ECElement).highDownSilentOnTouch`
        //   into the side-store flag. DORMANT for now — the cast is always nil until an Element type
        //   conforms to `ECElement`, and the only source (upstream `el.highDownSilentOnTouch`, set from
        //   the touch-mode Geo/Map paths) is itself deferred (both cross-file) — but this is the faithful
        //   upstream logic, ready to fire the moment those land.
        if let ec = el as? ECElement, let silentOnTouch = ec.highDownSilentOnTouch {
            inner.__highDownSilentOnTouch = silentOnTouch
        }
        // Simple optimize, since this method might be called for each element of a group in some cases.
        if !disable || inner.__highDownDispatcher {
            // __highByOuter already defaults to 0.
            inner.__highDownDispatcher = !disable
        }
    }

    // upstream: `isHighDownDispatcher(el)` (states.ts:861).
    public static func isHighDownDispatcher(_ el: Element?) -> Bool {
        guard let el = el else { return false }
        return getHighDownInner(el).__highDownDispatcher
    }

    // upstream: `enableComponentHighDownFeatures(el, componentModel, componentHighDownName)` (states.ts:870).
    public static func enableComponentHighDownFeatures(
        _ el: Element, _ componentModel: ComponentModel, _ componentHighDownName: String
    ) {
        let ecData = innerStore.getECData(el)
        ecData.componentMainType = componentModel.mainType
        ecData.componentIndex = componentModel.componentIndex
        ecData.componentHighDownName = componentHighDownName
    }

    // upstream: reserve 0 as default; `getHighlightDigit(highlightKey)` (states.ts:889).
    static var _highlightNextDigit: Int = 1
    static var _highlightKeyMap: [Int: Int] = [:]
    public static func getHighlightDigit(_ highlightKey: Int) -> Double? {
        if let existing = _highlightKeyMap[highlightKey] {
            return Double(existing)
        }
        if _highlightNextDigit <= 32 {
            let digit = _highlightNextDigit
            _highlightNextDigit += 1
            _highlightKeyMap[highlightKey] = digit
            return Double(digit)
        }
        return nil
    }

    // upstream: `isSelectChangePayload(payload)` (states.ts:897).
    public static func isSelectChangePayload(_ payload: Payload) -> Bool {
        let t = payload.type
        return t == SELECT_ACTION_TYPE || t == UNSELECT_ACTION_TYPE || t == TOGGLE_SELECT_ACTION_TYPE
    }

    // upstream: `isHighDownPayload(payload)` (states.ts:904).
    public static func isHighDownPayload(_ payload: Payload) -> Bool {
        let t = payload.type
        return t == HIGHLIGHT_ACTION_TYPE || t == DOWNPLAY_ACTION_TYPE
    }

    // ───────────────────────────── small internal utilities ─────────────────────────────

    // JS-truthy nil check for an `Any?` (nil or an explicit `NSNull` box). Unwrap first so `is NSNull`
    //   runs on a non-optional (avoids the "always succeeds when non-nil" optional-`is` warning).
    static func isNullish(_ v: Any?) -> Bool {
        guard let v = v else { return true }
        return v is NSNull
    }

    // upstream reads `focus` as `DefaultEmphasisFocus | ArrayLike<number> | Dictionary<...>` and compares
    //   the string cases directly. `InnerFocus` is `Any`; normalize the string-ish cases to a `String`.
    static func focusString(_ focus: Any?) -> String? {
        if let s = focus as? String { return s }
        if let e = focus as? DefaultEmphasisFocus { return e.rawValue }
        return nil
    }

    // Extract a `[Double]` index list from an arraylike focus (or a focus-dictionary value).
    static func focusIndices(_ v: Any?) -> [Double]? {
        if let a = v as? [Double] { return a }
        if let a = v as? [Int] { return a.map { Double($0) } }
        return nil
    }

    // upstream: `if (coordSys && coordSys.master) coordSys = coordSys.master`. `coordinateSystem` is
    //   `Any?`; resolve to the master (if any) and return an identity-comparable reference.
    static func resolveMaster(_ cs: Any?) -> AnyObject? {
        if let c = cs as? CoordinateSystem, let m = c.master {
            return m as AnyObject
        }
        return cs as AnyObject?
    }

    // `getViewOfComponentOrSeries` returns `AnyObject` (ChartView | ComponentView); both expose `.group`.
    static func viewGroup(_ view: AnyObject?) -> Group? {
        if let cv = view as? ChartView { return cv.group }
        if let cv = view as? ComponentView { return cv.group }
        return nil
    }
}
