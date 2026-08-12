// Ported from echarts/src/component/toolbox/ToolboxView.ts — keep in sync with upstream
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

// upstream imports (mapped to this port):
//   import * as textContain from 'zrender/src/contain/text';   -> `text.getBoundingRect` (title-overflow adjust block).
//   import * as graphic from '../../util/graphic';             -> `createIcon` reproduced via `makePath`
//     (util/graphic.ts createIcon not ported as a namespace; same seam as ScrollableLegendView /
//     SliderTimelineView). `graphic.setTooltipConfig` is the file-scope `setTooltipConfig`
//     (util/graphic.swift; ported) — wired at the per-icon tooltip config below.
//   import { enterEmphasis, leaveEmphasis } from '../../util/states';  -> `states.enterEmphasis` /
//     `states.leaveEmphasis` (ported; applied per iconStatus below).
//   import Model from '../../model/Model';                     -> `Model`.
//   import DataDiffer from '../../data/DataDiffer';            -> DROPPED: the feature DIFF is reduced to a
//     rebuild-each-render (no view reuse across setOption — same reduction as the other ported views).
//   import * as listComponentHelper from '../helper/listComponent'; -> `makeBackground` reproduced below
//     (component/helper/listComponent not ported — same PORT-NOTE as LegendView).
//   import ComponentView from '../../view/Component';          -> `ComponentView`.
//   import ToolboxModel from './ToolboxModel';                 -> `ToolboxModel`.
//   import { getFeature, ToolboxFeature, ... } from './featureManager'; -> `getFeature` / `ToolboxFeature`
//     / `ToolboxFeatureModel` (toolboxFeatureManager.swift).
//   import { getUID } from '../../util/component';             -> `component.getUID`.
//   import ZRText from 'zrender/src/graphic/Text';             -> `ZRText`.
//   import { getFont } from '../../label/labelStyle';          -> `labelStyle.getFont`.
//   import { box, createBoxLayoutReference, getLayoutRect, positionElement } from '../../util/layout';
//     -> `layout.*`.
//   import tokens from '../../visual/tokens';                  -> `tokens`.

// class ToolboxView extends ComponentView
open class ToolboxView: ComponentView {

    // static type = 'toolbox' as const;
    public static let type = "toolbox"
    open var type: String { return ToolboxView.type }

    // upstream: `_features: HashMap<...>` + `_featureNames: string[]` — carried across renders for the
    //   DataDiffer add/update/remove + dispose. The port rebuilds each render (no reuse), so only a
    //   plain per-render dict of live features is kept (used by `updateView`/`dispose`).
    //   (internal getter so a headless test can reach a live feature's onclick — e.g. saveAsImage).
    private(set) var _features: [String: ToolboxFeature] = [:]

    // render(toolboxModel, ecModel, api, payload)
    open override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let toolboxModel = model as! ToolboxModel

        let group = self.group
        _ = group.removeAll()

        // if (!toolboxModel.get('show')) return;
        if !toolboxTruthy(toolboxModel.get("show")) {
            return
        }

        // const itemSize = +toolboxModel.get('itemSize');
        let itemSize = toolboxNum(toolboxModel.get("itemSize")) ?? 0
        // const isVertical = toolboxModel.get('orient') === 'vertical';
        let isVertical = (toolboxModel.get("orient") as? String) == "vertical"
        // const featureOpts = toolboxModel.get('feature') || {};
        let featureOpts = (toolboxModel.get("feature") as? [String: Any]) ?? [:]

        var features: [String: ToolboxFeature] = [:]

        // JavaScript object keys preserve insertion order, while Swift Dictionary iteration does not.
        // Official options consistently declare the built-in toolbox features in this order; use the
        // same stable order and append custom/unknown features deterministically.
        let builtInOrder = ["dataZoom", "dataView", "magicType", "restore", "saveAsImage", "brush"]
        // A Swift Dictionary cannot preserve the JavaScript object's authored key order reliably.
        // Demo/options that need a different order can carry that source order explicitly.
        let explicitOrder = (toolboxModel.get("_featureOrder") as? [String]) ?? []
        let preferredOrder = explicitOrder + builtInOrder.filter { !explicitOrder.contains($0) }
        let orderedFeatureNames = preferredOrder.filter { featureOpts[$0] != nil }
            + featureOpts.keys.filter { !preferredOrder.contains($0) }.sorted()
        for featureName in orderedFeatureNames {
            var featureOpt = (featureOpts[featureName] as? [String: Any]) ?? [:]

            // FIX#11236, merge feature title from MagicType newOption. TODO: consider seriesIndex ?
            //   if (payload && payload.newTitle != null && payload.featureName === featureName) {
            //       featureOpt.title = payload.newTitle;
            //   }
            //   Upstream mutates `featureOpt.title` AFTER the Model is built (its JS option holds
            //   `featureOpt` by reference, so the later `featureModel.get('title')` read sees it). The
            //   Swift `Model` copies the dict, so apply the merge BEFORE constructing the Model to get the
            //   identical `featureModel.get('title')` result.
            if let newTitle = payload.other["newTitle"],
               (payload.other["featureName"] as? String) == featureName {
                featureOpt["title"] = newTitle
            }

            // const featureModel = new Model(featureOpt, toolboxModel, ecModel);
            let featureModel = Model(featureOpt, toolboxModel, ecModel)
            // const isFeatureShow = featureModel && featureModel.get('show');
            let isFeatureShow = toolboxTruthy(featureModel.get("show"))
            if !isFeatureShow {
                continue
            }

            let feature: ToolboxFeature
            if isUserFeatureName(featureName) {
                // UserDefinedToolboxFeature { onclick: featureModel.option.onclick, featureName }.
                // PORT-NOTE (deferred): the user `my*` feature's `onclick` closure carried on the
                //   option bag is not modeled (no on-canvas dispatch target — requires interaction dispatch). Skip.
                continue
            }
            else {
                // const Feature = getFeature(featureName); if (!Feature) return; feature = new Feature();
                guard let registration = getFeature(featureName) else {
                    continue
                }
                feature = registration.create()
            }

            // feature.uid = getUID('toolbox-feature');
            feature.uid = component.getUID("toolbox-feature")
            feature.model = featureModel
            feature.ecModel = ecModel
            feature.api = api

            createIconPaths(
                featureModel, feature, featureName,
                toolboxModel: toolboxModel, ecModel: ecModel, api: api,
                itemSize: itemSize, isVertical: isVertical, group: group
            )

            features[featureName] = feature

            // if (isTooltipFeature(feature) && feature.render) feature.render(featureModel, ecModel, api, payload);
            //   PORT: the only feature with a `render` is DataZoom (mounts its BrushController) — DEFERRED
            //   (the base `render` is a no-op), so this call is harmless. Kept for the diffable surface.
            feature.render(featureModel, ecModel, api, payload)
        }

        // Diff-remove (upstream DataDiffer `.remove(curry(processFeature, null))`): any feature that was
        //   live in the previous render but is gone or now `show:false` this render must be disposed
        //   (`if (isDiffRemove || !isFeatureShow) { feature.dispose(ecModel, api); }`). The port rebuilds
        //   fresh features each render, so compare the retained set against the previous `_features`.
        for (name, oldFeature) in self._features where features[name] == nil {
            oldFeature.dispose(ecModel, api)
        }

        self._features = features

        // Perform layout.
        // const refContainer = createBoxLayoutReference(toolboxModel, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(toolboxModel, api).refContainer
        let boxLayoutParams = toolboxModel.getBoxLayoutParams()
        let padding = toolboxModel.get("padding")
        let viewRect = layout.getLayoutRect(boxLayoutParams, refContainer, padding)
        // box(orient, group, itemGap, viewRect.width, viewRect.height);
        layout.box(
            (toolboxModel.get("orient") as? String) ?? "horizontal",
            group,
            toolboxNum(toolboxModel.get("itemGap")) ?? 0,
            viewRect.width,
            viewRect.height
        )
        // positionElement(group, boxLayoutParams, refContainer, padding);
        //   Value-returning port (CONVENTIONS §3): apply the computed x/y back to the group.
        let posResult = layout.positionElement(
            group, boxLayoutParamsToDict(boxLayoutParams), refContainer, padding, nil
        )
        group.x = posResult.out["x"] ?? group.x
        group.y = posResult.out["y"] ?? group.y

        // Render background after group is layout
        if let bounding = group.getBoundingRect() {
            _ = group.add(toolboxMakeBackground(bounding, toolboxModel))
        }

        // Adjust icon title positions to avoid them out of screen
        // isVertical || group.eachChild(function (icon: IconPath) { ... });
        if !isVertical {
            _ = group.eachChild({ icon, _ in
                // const titleText = (icon as ExtendedPath).__title;
                //   The port carries the title on the icon's textContent normal style (`textStyle.text`).
                let textContent = icon.getTextContent()
                let titleText = textContent?.textStyle?.text

                // const emphasisState = icon.ensureState('emphasis');
                // const emphasisTextConfig = emphasisState.textConfig || (emphasisState.textConfig = {});
                //   ensureState returns the SAME stored state; read its textConfig (default `{}`) and
                //   write it back below (mirrors upstream's `|| (= {})` assignment, even for background els).
                let emphasisState = icon.ensureState("emphasis")
                var emphasisTextConfig = emphasisState.textConfig ?? ElementTextConfig()

                // const emphasisTextState = textContent && textContent.ensureState('emphasis');
                let emphasisTextState = textContent?.ensureState("emphasis")

                // May be background element
                // if (emphasisTextState && !isFunction(emphasisTextState) && titleText) { ... }
                if let emphasisTextState = emphasisTextState,
                   let titleText = titleText, !titleText.isEmpty {
                    // const emphasisTextStyle = emphasisTextState.style || (emphasisTextState.style = {});
                    //   The port's ZRText per-state style lives in the typed `textStyle` side channel.
                    var emphasisTextStyle = emphasisTextState.textStyle ?? TextStyleProps()
                    let rect = text.getBoundingRect(
                        titleText, ZRText.makeFont(emphasisTextStyle) ?? ""
                    )
                    let offsetX = icon.x + group.x
                    let offsetY = icon.y + group.y + itemSize

                    var needPutOnTop = false
                    if offsetY + rect.height > api.getHeight() {
                        emphasisTextConfig.position = "top"
                        needPutOnTop = true
                    }
                    let topOffset: Double = needPutOnTop ? (-5 - rect.height) : (itemSize + 10)
                    if offsetX + rect.width / 2 > api.getWidth() {
                        emphasisTextConfig.position = ["100%", topOffset] as [Any]
                        emphasisTextStyle.align = .right
                    }
                    else if offsetX - rect.width / 2 < 0 {
                        emphasisTextConfig.position = [0.0, topOffset] as [Any]
                        emphasisTextStyle.align = .left
                    }
                    emphasisTextState.textStyle = emphasisTextStyle
                }

                emphasisState.textConfig = emphasisTextConfig
            })
        }
    }

    // function createIconPaths(featureModel, feature, featureName)
    private func createIconPaths(
        _ featureModel: ToolboxFeatureModel,
        _ feature: ToolboxFeature,
        _ featureName: String,
        toolboxModel: ToolboxModel,
        ecModel: GlobalModel,
        api: ExtensionAPI,
        itemSize: Double,
        isVertical: Bool,
        group: Group
    ) {
        let iconStyleModel = featureModel.getModel("iconStyle")
        let iconStyleEmphasisModel = featureModel.getModel(["emphasis", "iconStyle"])

        // const icons = (feature.getIcons) ? feature.getIcons() : featureModel.get('icon');
        let iconsAny: Any? = feature.getIcons() ?? featureModel.get("icon")
        // const titles = featureModel.get('title') || {};
        let titlesAny: Any? = featureModel.get("title")

        // isString(icons) ? { [featureName]: icons } : icons
        var iconsMap: [String: String] = [:]
        if let iconStr = iconsAny as? String {
            iconsMap[featureName] = iconStr
        }
        else if let map = iconsAny as? [String: Any] {
            for (k, v) in map { if let s = v as? String { iconsMap[k] = s } }
        }
        else if let map = iconsAny as? [String: String] {
            iconsMap = map
        }

        // isString(titles) ? { [featureName]: titles } : titles
        var titlesMap: [String: String] = [:]
        if let titleStr = titlesAny as? String {
            titlesMap[featureName] = titleStr
        }
        else if let map = titlesAny as? [String: Any] {
            for (k, v) in map { if let s = v as? String { titlesMap[k] = s } }
        }

        let iconPathsStore = toolboxIconPathsInner(featureModel)
        iconPathsStore.paths = [:]

        // Grouped features also use ordered JS objects upstream. Preserve their semantic type order
        // (dataZoom: zoom/back, magicType: the user-specified type list) instead of Dictionary order.
        var orderedIconNames: [String] = []
        if let types = featureModel.get("type") as? [Any] {
            orderedIconNames = types.compactMap { $0 as? String }.filter { iconsMap[$0] != nil }
        }
        if orderedIconNames.isEmpty, featureName == "dataZoom" {
            orderedIconNames = ["zoom", "back"].filter { iconsMap[$0] != nil }
        }
        orderedIconNames += iconsMap.keys.filter { !orderedIconNames.contains($0) }.sorted()

        for iconName in orderedIconNames {
            guard let iconStr = iconsMap[iconName] else { continue }
            // const path = graphic.createIcon(iconStr, {}, { x:-itemSize/2, y:-itemSize/2, width:itemSize, height:itemSize });
            let path = toolboxCreateIcon(
                iconStr,
                BoundingRect(-itemSize / 2, -itemSize / 2, itemSize, itemSize)
            )
            // path.setStyle(iconStyleModel.getItemStyle());  (createIcon default strokeNoScale is kept)
            var style = iconStyleModel.getItemStyle()
            style["strokeNoScale"] = true
            path.useStyle(barStyleFromDict(style))
            path.pathStyle.strokeNoScale = true
            path.dirtyStyle()

            // const pathEmphasisState = path.ensureState('emphasis');
            // pathEmphasisState.style = iconStyleEmphasisModel.getItemStyle();
            //   Wired: the icon's emphasis (hover) recolour is the emphasis icon style. `useStates` reads
            //   this view-defined state directly (the highDown proxy only ADDS a default lift), and Path's
            //   `PathStyleAnimationAccessor` writes the fill/stroke into `pathStyle` on state entry.
            path.ensureState("emphasis").style = iconStyleEmphasisModel.getItemStyle()

            // Text position calculation → the title text content (hidden until hover).
            var textStyle = TextStyleProps()
            textStyle.text = titlesMap[iconName]
            textStyle.align = (iconStyleEmphasisModel.get("textAlign") as? String).flatMap { TextAlign(rawValue: $0) }
            // fill: null (shown on hover); font from the emphasis icon style's text* fields.
            textStyle.fill = nil
            textStyle.font = labelStyle.getFont(labelStyle.GetFontOpt(
                fontStyle: iconStyleEmphasisModel.get("textFontStyle"),
                fontWeight: iconStyleEmphasisModel.get("textFontWeight"),
                fontSize: iconStyleEmphasisModel.get("textFontSize"),
                fontFamily: iconStyleEmphasisModel.get("textFontFamily")
            ), ecModel)
            // upstream normal textStyle also carries the title-chip borderRadius/padding (the fill /
            //   backgroundColor are applied on the hover — see the emphasis text state below).
            textStyle.borderRadius = toolboxNumberOrArray(iconStyleEmphasisModel.get("textBorderRadius"))
            textStyle.padding = toolboxNumberOrArray(iconStyleEmphasisModel.get("textPadding"))
            let textContent = ZRText(["style": textStyle])
            // Hidden until hover: normal = ignored (upstream `ignore: true` + `fill: null`).
            textContent.ignore = true
            path.setTextContent(textContent)

            // upstream: graphic.setTooltipConfig({ el: path, componentModel: toolboxModel,
            //   itemName: iconName, formatterParamsExtra: { title: titlesMap[iconName] } });
            // PORT-NOTE: `formatterParamsExtra` is typed `KeyValuePairs<String, Any>` (not a Swift
            //   `Dictionary`) so this literal's key order reaches `formatterParams.$vars` exactly as
            //   upstream's object literal does (`format.formatTpl` aliases `$vars` POSITIONALLY onto
            //   `a`/`b`/`c`/...).
            // PORT-NOTE: `titlesMap[iconName]` is `String?` here (upstream's lookup may be `undefined`).
            //   It is coalesced to `""` rather than boxed into `Any`, because an `Any`-boxed
            //   `Optional<String>.none` would fail the downstream `as? String` casts (Any-boxing
            //   unwraps `.some`, so only `.none` survives as a boxed Optional) and interpolate as
            //   "nil"; upstream's `undefined` formats as empty likewise.
            setTooltipConfig(
                el: path,
                componentModel: toolboxModel,
                itemName: iconName,
                formatterParamsExtra: [
                    "title": titlesMap[iconName] ?? ""
                ]
            )

            // Hover-title reveal — the port's faithful adaptation of upstream's mouseover
            //   (`textContent.setStyle({fill, backgroundColor}); textContent.ignore = !showTitle;
            //    api.enterEmphasis(this)`) / mouseout (`api.leaveEmphasis(this); textContent.hide()`):
            //   attach an EMPHASIS state to the title text that is VISIBLE (`ignore: false`) and coloured,
            //   while its normal state stays hidden. `Element.useState`/`useStates` propagates the icon's
            //   state down to its `textContent` (Element.swift:983/1051), so the title appears exactly when
            //   the icon enters emphasis and hides again on downplay — no per-element mouse handlers needed.
            let hoverStyle = iconStyleEmphasisModel.getItemStyle()
            // fill: iconStyleEmphasisModel.get('textFill') || hoverStyle.fill || hoverStyle.stroke
            //       || tokens.color.neutral99
            let titleFill = (iconStyleEmphasisModel.get("textFill") as? String)
                ?? (hoverStyle["fill"] as? String)
                ?? (hoverStyle["stroke"] as? String)
                ?? tokens.color.neutral99
            var emphasisTextStyle = TextStyleProps()
            emphasisTextStyle.fill = titleFill
            if let bg = iconStyleEmphasisModel.get("textBackgroundColor") as? String {
                emphasisTextStyle.backgroundColor = .string(bg)
            }
            let textEmphasisState = textContent.ensureState("emphasis")
            textEmphasisState.textStyle = emphasisTextStyle
            textEmphasisState.ignore = false    // upstream: shown on hover (`!showTitle` → false here)

            // Title default position. Upstream sets `path.setTextConfig({position})` on mouseover; the
            //   default is bottom (horizontal) / right (vertical) unless the toolbox is anchored there.
            //   PORT-NOTE (deferred): the emphasis title-overflow reposition (the `emphasisState
            //   .textConfig` block in render()) reads api.getWidth/Height; the default position is used.
            let defaultTextPosition: String = isVertical
                ? ((toolboxModel.get("right") == nil && (toolboxModel.get("left") as? String) != "right")
                    ? "right" : "left")
                : ((toolboxModel.get("bottom") == nil && (toolboxModel.get("top") as? String) != "bottom")
                    ? "bottom" : "top")
            var titleTextConfig = ElementTextConfig()
            titleTextConfig.position = (iconStyleEmphasisModel.get("textPosition") as? String) ?? defaultTextPosition
            path.setTextConfig(titleTextConfig)

            // Mark the icon a highDown dispatcher so a live-host hover (mouseover → enterEmphasisWhenMouseOver)
            //   enters emphasis (recolouring the icon + revealing the title). Replaces upstream's per-icon
            //   mouseover/mouseout handlers with the ported states-engine hover binding (EChartsView).
            states.toggleHoverEmphasis(path, nil, nil, false)

            // (featureModel.get(['iconStatus', iconName]) === 'emphasis' ? enterEmphasis : leaveEmphasis)(path);
            //   Apply the persisted icon status (e.g. magicType's active type is kept in `emphasis`).
            if (featureModel.get(["iconStatus", iconName]) as? String) == "emphasis" {
                states.enterEmphasis(path)
            }
            else {
                states.leaveEmphasis(path)
            }

            _ = group.add(path)

            // path.on('click', bind(feature.onclick, feature, ecModel, api, iconName));
            //   Wired faithfully: a live-host click dispatches the feature's action (restore / magicType
            //   are pure option/dispatch → end-to-end). The headless render pipeline never fires it.
            path.on("click", { [weak feature] _, _ in
                feature?.onclick(ecModel, api, iconName)
                return nil
            })

            iconPathsStore.paths[iconName] = path
        }
    }

    // updateView(toolboxModel, ecModel, api, payload)
    open override func updateView(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        for (_, feature) in self._features {
            feature.updateView(feature.model, ecModel, api, payload)
        }
    }

    // dispose(ecModel, api)
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        for (_, feature) in self._features {
            feature.dispose(ecModel, api)
        }
    }
}

// function isUserFeatureName(featureName) { return featureName.indexOf('my') === 0; }
private func isUserFeatureName(_ featureName: String) -> Bool {
    return featureName.hasPrefix("my")
}

// export default ToolboxView;  -> `open class ToolboxView` above.

// ════════════════════════════════════════════════════════════════════════════════════════════
// PORT-NOTE helpers — NOT part of toolbox/ToolboxView.ts upstream. They reproduce out-of-phase
// sibling APIs / JS idioms so the static toolbox render compiles. Delete each when its real sibling
// lands and call the sibling directly.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// Reproduce `graphic.createIcon`'s `path://` / direct-svg branch: `makePath(str.replace('path://',''),
///   {rectHover:true, style:{strokeNoScale:true}}, rect, 'center')`. (The `image://` branch is DEFERRED.)
private func toolboxCreateIcon(_ iconStr: String, _ rect: BoundingRect) -> SVGPath {
    // PORT-NOTE (deferred): `image://` icons (a ZRImage) — requires the ZRImage icon branch; only path/svg reproduced.
    let pathData = iconStr.hasPrefix("path://") ? String(iconStr.dropFirst("path://".count)) : iconStr
    let path = ZRenderKit.makePath(pathData, nil, rect, "center")
    path.pathStyle.strokeNoScale = true
    path.dirtyStyle()
    return path
}

/// JS truthiness for the dynamic option bag (`if (x)` / `!x`). (CONVENTIONS §6.)
private func toolboxTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// Coerce a `number | number[]` option value into `TextStyleProps.borderRadius`/`padding`
///   (the title-chip fields). Mirrors `labelStyle._coerceNumberOrNumberArray` (file-private there).
private func toolboxNumberOrArray(_ v: Any?) -> NumberOrNumberArray? {
    if let x = v as? NumberOrNumberArray { return x }
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] { return .array(arr.map { toolboxNum($0) ?? 0 }) }
    if let d = toolboxNum(v) { return .number(d) }
    return nil
}

/// `+toolboxModel.get('itemSize')` — coerce an option number boxed as Int OR Double (CRITICAL trap #2).
func toolboxNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s) }
    return nil
}

/// Faithful minimal reproduction of `component/helper/listComponent.makeBackground` (same PORT-NOTE as
///   LegendView.makeBackground). Delete when component/helper/listComponent.swift lands.
private func toolboxMakeBackground(_ rect: BoundingRect, _ componentModel: ComponentModel) -> Rect {
    let padding = toolboxNormalizeCssArray(componentModel.get("padding"))
    var style = componentModel.getItemStyle(["color", "opacity"])
    style["fill"] = componentModel.get("backgroundColor")

    var shape = RectShape()
    shape.x = rect.x - padding[3]
    shape.y = rect.y - padding[0]
    shape.width = rect.width + padding[1] + padding[3]
    shape.height = rect.height + padding[0] + padding[2]
    shape.r = toolboxBorderRadius(componentModel.get("borderRadius"))

    return Rect([
        "shape": shape as PathShape,
        "style": barStyleFromDict(style),
        "silent": true,
        "z2": -1.0
    ])
}

/// `formatUtil.normalizeCssArray(padding || 0)` on the dynamic `number | number[]` option value.
private func toolboxNormalizeCssArray(_ v: Any?) -> [Double] {
    if let arr = v as? [Double] { return format.normalizeCssArray(arr) }
    if let arr = v as? [Any] { return format.normalizeCssArray(arr.map { toolboxNum($0) ?? 0 }) }
    if let d = toolboxNum(v) { return format.normalizeCssArray(d) }
    return format.normalizeCssArray(0.0)
}

/// upstream `shape.r = componentModel.get('borderRadius')` where borderRadius is `number | number[]`.
private func toolboxBorderRadius(_ v: Any?) -> RectRadius? {
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] { return .array(arr.map { toolboxNum($0) ?? 0 }) }
    if let d = toolboxNum(v) { return .number(d) }
    return nil
}
