// Ported from echarts/src/component/title/install.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import * as zrUtil from 'zrender/src/core/util';                 -> `util.*` (ZRenderKit; `util.retrieve2`).
//   import * as graphic from '../../util/graphic';
//     -> `util/graphic` is NOT ported as a namespace. `graphic.Text` / `graphic.Rect` are the
//        ZRenderKit scene-graph types `ZRText` / `Rect` (used directly).
//   import {getECData} from '../../util/innerStore';                 -> `innerStore.getECData`
//        (event wiring — the `eventData` assignment is deferred, see PORT-TODO in `render`).
//   import {createTextStyle} from '../../label/labelStyle';
//     -> `label/labelStyle.swift` IS ported (`labelStyle.createTextStyle`, labelStyle.swift:417).
//        This view still uses a local minimal reproduction `createTextStyle` at the bottom of this
//        file because the real overload takes a different opt shape (`specifiedTextStyle: TextStyleProps?`
//        + `TextCommonParams`) than the title view's `{text, fill, y, verticalAlign}` literal; rewiring
//        is a deferred deviation, not a missing dep. Same local reproduction as AxisBuilder.swift.
//   import {createBoxLayoutReference, getLayoutRect} from '../../util/layout';
//     -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` (util/layout.swift).
//   import ComponentModel from '../../model/Component';              -> `ComponentModel` (model/Component.swift).
//   import { ... TitleOption field types ... } from '../../util/types';
//     -> option interfaces collapsed to the dynamic `[String: Any]` bag (CONVENTIONS §2); the
//        `TitleOption` interface below is preserved as commented source.
//   import ComponentView from '../../view/Component';               -> `ComponentView` (view/ComponentView.swift).
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel` (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> `ExtensionAPI` (core/ExtensionAPI.swift).
//   import {windowOpen} from '../../util/format';
//     -> PORT-TODO: `format.windowOpen` opens a URL — interaction only, deferred (see the `link`/
//        `sublink` click handlers in `render`).
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//     -> PORT-TODO: registration boilerplate deferred to the Orchestrate driver (see `install`
//        note at the bottom).
//   import tokens from '../../visual/tokens';
//     -> PORT-NOTE: `visual/tokens.ts` is ported (visual/tokens.swift). The `tokens.*` values consumed in
//        `defaultOption` are still inlined verbatim as their resolved constants (same deviation as
//        GridModel/axisDefault); could be re-wired to the real `tokens` namespace.
//          tokens.size.m            = 15                       (size.m)
//          tokens.color.transparent = 'rgba(0,0,0,0)'
//          tokens.color.primary     = color.neutral80 = '#3c3c41'
//          tokens.color.quaternary  = color.neutral50 = '#86878c'

// interface TitleTextStyleOption extends LabelOption { width?: number }
//   -> collapsed into the dynamic option bag.

// export interface TitleOption extends
//     ComponentOption, BoxLayoutOptionMixin, BorderOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin {
//     mainType?: 'title'
//     show?: boolean
//     text?: string
//     link?: string           // Link to url
//     target?: 'self' | 'blank'
//     subtext?: string
//     sublink?: string
//     subtarget?: 'self' | 'blank'
//     textAlign?: ZRTextAlign
//     textVerticalAlign?: ZRTextVerticalAlign
//     textBaseline?: ZRTextVerticalAlign   // @deprecated Use textVerticalAlign instead
//     backgroundColor?: ZRColor
//     padding?: number | number[]          // Padding between text and border.
//     itemGap?: number                     // Gap between text and subtext
//     textStyle?: TitleTextStyleOption
//     subtextStyle?: TitleTextStyleOption
//     triggerEvent?: boolean               // If trigger mouse or touch event
//     borderRadius?: number | number[]     // Radius of background border.
// }

// upstream: class TitleModel extends ComponentModel<TitleOption>
// CONVENTIONS §2: reference type extending the reference `ComponentModel` -> `final class`.
public final class TitleModel: ComponentModel {

    // static type = 'title' as const;
    // type = TitleModel.type;
    //   (mirrors GridModel: the static `type` and instance `type` both resolve to this class var;
    //   the class registry / `ComponentModel.type` read it.)
    public override class var type: ComponentFullType { return "title" }

    // readonly layoutMode = {type: 'box', ignoreSize: true} as const;
    public override class var layoutMode: Any? {
        return ["type": "box", "ignoreSize": true] as [String: Any]
    }

    // static defaultOption: TitleOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 6.0,
            "show": true,

            "text": "",
            "target": "blank",
            "subtext": "",

            "subtarget": "blank",

            "left": "center",
            "top": 15.0,                        // tokens.size.m

            "backgroundColor": "rgba(0,0,0,0)", // tokens.color.transparent

            "borderColor": "#3c3c41",           // tokens.color.primary (color.neutral80)

            "borderWidth": 0.0,

            "padding": 5.0,

            "itemGap": 10.0,
            "textStyle": [
                "fontSize": 18.0,
                "fontWeight": "bold",
                "color": "#3c3c41"              // tokens.color.primary (color.neutral80)
            ] as [String: Any],
            "subtextStyle": [
                "fontSize": 12.0,
                "color": "#86878c"              // tokens.color.quaternary (color.neutral50)
            ] as [String: Any]
        ] as [String: Any]
    }
}

// View
// upstream: class TitleView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` -> `final class`.
public final class TitleView: ComponentView {

    // static type = 'title' as const;
    public static let type = "title"
    // type = TitleView.type;
    public let type = "title"

    // upstream: render(titleModel: TitleModel, ecModel: GlobalModel, api: ExtensionAPI)
    //   The base `ComponentView.render` signature is (model, ecModel, api, payload); upstream
    //   TitleView.render declares only (titleModel, ecModel, api) (payload optional in JS). The
    //   override matches the full base signature and narrows `model` to `TitleModel` (cf. GridView.render).
    public override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let titleModel = model as! TitleModel

        _ = self.group.removeAll()

        // if (!titleModel.get('show')) { return; }
        if !jsTruthy(titleModel.get("show")) {
            return
        }

        let group = self.group

        let textStyleModel = titleModel.getModel("textStyle")
        let subtextStyleModel = titleModel.getModel("subtextStyle")

        // let textAlign = titleModel.get('textAlign');
        var textAlign = titleModel.get("textAlign") as? String
        // let textVerticalAlign = zrUtil.retrieve2(titleModel.get('textBaseline'), titleModel.get('textVerticalAlign'));
        var textVerticalAlign = util.retrieve2(
            titleModel.get("textBaseline") as? String,
            titleModel.get("textVerticalAlign") as? String
        )

        let textEl = ZRText([
            "style": createTextStyle(textStyleModel, CreateTextStyleOpt(
                text: titleModel.get("text") as? String,
                fill: textStyleModel.getTextColor()
            ), disableBox: true),
            "z2": 10.0
        ])

        let textRect = textEl.getBoundingRect()!

        let subText = titleModel.get("subtext") as? String
        let subTextEl = ZRText([
            "style": createTextStyle(subtextStyleModel, CreateTextStyleOpt(
                text: subText,
                fill: subtextStyleModel.getTextColor(),
                y: textRect.height + ((titleModel.get("itemGap") as? Double) ?? 0),
                verticalAlign: "top"
            ), disableBox: true),
            "z2": 10.0
        ])

        let link = titleModel.get("link") as? String
        let sublink = titleModel.get("sublink") as? String
        let triggerEvent = titleModel.get("triggerEvent", true)

        // textEl.silent = !link && !triggerEvent;
        textEl.silent = !jsTruthy(link) && !jsTruthy(triggerEvent)
        // subTextEl.silent = !sublink && !triggerEvent;
        subTextEl.silent = !jsTruthy(sublink) && !jsTruthy(triggerEvent)

        // PORT-TODO: interaction wiring deferred (CONVENTIONS §5 / task: STATIC RENDER ONLY).
        //   if (link) { textEl.on('click', () => windowOpen(link, '_' + titleModel.get('target'))); }
        //   if (sublink) { subTextEl.on('click', () => windowOpen(sublink, '_' + titleModel.get('subtarget'))); }

        // PORT-TODO: event data wiring deferred (CONVENTIONS §5).
        //   getECData(textEl).eventData = getECData(subTextEl).eventData = triggerEvent
        //       ? { componentType: 'title', componentIndex: titleModel.componentIndex }
        //       : null;

        _ = group.add(textEl)
        // subText && group.add(subTextEl);
        // If no subText, but add subTextEl, there will be an empty line.
        if jsTruthy(subText) {
            _ = group.add(subTextEl)
        }

        var groupRect = group.getBoundingRect(nil)
        var layoutOption = titleModel.getBoxLayoutParams()
        layoutOption.width = groupRect.width
        layoutOption.height = groupRect.height

        let layoutRef = layout.createBoxLayoutReference(titleModel, api)
        let layoutRect = layout.getLayoutRect(
            layoutOption, layoutRef.refContainer, titleModel.get("padding")
        )
        // Adjust text align based on position
        if !jsTruthy(textAlign) {
            // Align left if title is on the left. center and right is same
            // textAlign = (titleModel.get('left') || titleModel.get('right')) as ZRTextAlign;
            let leftOrRight = jsTruthy(titleModel.get("left"))
                ? titleModel.get("left")
                : titleModel.get("right")
            textAlign = leftOrRight as? String
            // @ts-ignore
            if textAlign == "middle" {
                textAlign = "center"
            }
            // Adjust layout by text align
            if textAlign == "right" {
                layoutRect.x += layoutRect.width
            }
            else if textAlign == "center" {
                layoutRect.x += layoutRect.width / 2
            }
        }
        if !jsTruthy(textVerticalAlign) {
            // textVerticalAlign = (titleModel.get('top') || titleModel.get('bottom')) as ZRTextVerticalAlign;
            // PORT-TODO: upstream assigns the raw `top`/`bottom` option here; when it is a NUMBER (e.g.
            //   the default `top: 15`) `textVerticalAlign` stays that number, none of the string
            //   comparisons below match, and the final `|| 'top'` keeps the (truthy) number — which
            //   zrender then renders as the default 'top'. We coerce non-string values to nil, so the
            //   `?? 'top'` below yields 'top' directly, matching the rendered result.
            let topOrBottom = jsTruthy(titleModel.get("top"))
                ? titleModel.get("top")
                : titleModel.get("bottom")
            textVerticalAlign = topOrBottom as? String
            // @ts-ignore
            if textVerticalAlign == "center" {
                textVerticalAlign = "middle"
            }
            if textVerticalAlign == "bottom" {
                layoutRect.y += layoutRect.height
            }
            else if textVerticalAlign == "middle" {
                layoutRect.y += layoutRect.height / 2
            }

            textVerticalAlign = textVerticalAlign ?? "top"
        }

        group.x = layoutRect.x
        group.y = layoutRect.y
        group.markRedraw()
        // const alignStyle = { align: textAlign, verticalAlign: textVerticalAlign };
        // textEl.setStyle(alignStyle); subTextEl.setStyle(alignStyle);
        // PORT-TODO: ZRText has no `setStyle(TextStyleProps)` overload (its rich style lives on
        //   `textStyle`, and the inherited `Displayable.setStyle` only touches the CommonStyleProps
        //   subset — align/verticalAlign are not in it). Set the two fields directly on `textStyle`
        //   and mark the element dirty, which is the faithful effect of `setStyle({align, verticalAlign})`.
        let alignEnum = textAlign.flatMap { TextAlign(rawValue: $0) }
        let verticalAlignEnum = textVerticalAlign.flatMap { TextVerticalAlign(rawValue: $0) }
        setAlignStyle(textEl, alignEnum, verticalAlignEnum)
        setAlignStyle(subTextEl, alignEnum, verticalAlignEnum)

        // Render background
        // Get groupRect again because textAlign has been changed
        groupRect = group.getBoundingRect(nil)
        // const padding = layoutRect.margin;
        // PORT-TODO: upstream reads the normalized css padding array off `layoutRect.margin`, but the
        //   partial util/layout.swift `LayoutRect` (== BoundingRect) has no `.margin` slot yet (see the
        //   PORT-TODO in layout.swift). Recompute it directly from the option — this is exactly the
        //   value `getLayoutRect` would have stored (`normalizeCssArray(titleModel.get('padding'))`).
        let padding = normalizeCssArrayAny(titleModel.get("padding"))
        // const style = titleModel.getItemStyle(['color', 'opacity']);
        var style = titleModel.getItemStyle(["color", "opacity"])
        // style.fill = titleModel.get('backgroundColor');
        style["fill"] = titleModel.get("backgroundColor")

        var shape = RectShape()
        shape.x = groupRect.x - padding[3]
        shape.y = groupRect.y - padding[0]
        shape.width = groupRect.width + padding[1] + padding[3]
        shape.height = groupRect.height + padding[0] + padding[2]
        shape.r = borderRadiusToRectRadius(titleModel.get("borderRadius"))

        let rect = Rect([
            "shape": shape as PathShape,
            // PORT-TODO: `getItemStyle` returns the dynamic `[String: Any]` style bag; bridge it to the
            //   typed `PathStyleProps` via the shared `barStyleFromDict` seam (BarView.swift).
            "style": barStyleFromDict(style),
            // PORT-TODO: `subPixelOptimize: true` is not round-tripped through the dict prop bag
            //   (Path.attrKV does not map it); it is a crisp-edge nicety with no layout effect. Set it
            //   explicitly below to preserve behavior.
            "subPixelOptimize": true,
            "silent": true
        ])
        rect.subPixelOptimize = true

        _ = group.add(rect)
    }
}


// export function install(registers: EChartsExtensionInstallRegisters) {
//     registers.registerComponentModel(TitleModel);
//     registers.registerComponentView(TitleView);
// }
// PORT-TODO: registration boilerplate belongs to the Orchestrate driver (Integrate stage), not
//   this render-layer file (same convention as grid/installSimple.swift). Preserved as commented
//   source for the diffable surface.


// ============================================================================
// PORT-TODO helpers — NOT part of title/install.ts upstream. These reproduce the
// out-of-phase sibling APIs referenced above so the static title render compiles.
// Delete each when its real sibling lands and call the sibling directly.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` / `!x` on `get(...)` results).
/// (CONVENTIONS §6: replicate JS truthiness explicitly for numbers/strings.)
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// The `{align, verticalAlign}` slice of `setStyle` for a `ZRText` (see PORT-TODO at the call site).
private func setAlignStyle(_ el: ZRText, _ align: TextAlign?, _ verticalAlign: TextVerticalAlign?) {
    el.textStyle.align = align
    el.textStyle.verticalAlign = verticalAlign
    el.dirtyStyle()
}

/// `formatUtil.normalizeCssArray(padding || 0)` on the dynamic `number | number[]` option value.
private func normalizeCssArrayAny(_ v: Any?) -> [Double] {
    if let arr = v as? [Double] {
        return format.normalizeCssArray(arr)
    }
    if let arr = v as? [Any] {
        return format.normalizeCssArray(arr.map { ($0 as? Double) ?? 0 })
    }
    if let d = v as? Double {
        return format.normalizeCssArray(d)
    }
    if let i = v as? Int {
        return format.normalizeCssArray(Double(i))
    }
    return format.normalizeCssArray(0.0)
}

/// upstream `shape.r = titleModel.get('borderRadius')` where borderRadius is `number | number[]`.
private func borderRadiusToRectRadius(_ v: Any?) -> RectRadius? {
    if let d = v as? Double { return .number(d) }
    if let i = v as? Int { return .number(Double(i)) }
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] { return .array(arr.map { ($0 as? Double) ?? 0 }) }
    return nil
}

/// The object-literal `opt` passed to `createTextStyle` at the two call sites above:
///   `{text, fill}` and `{text, fill, y, verticalAlign}`.
private struct CreateTextStyleOpt {
    var text: String?
    var fill: String?
    var x: Double?
    var y: Double?
    var verticalAlign: String?
    init(text: String? = nil, fill: String? = nil, x: Double? = nil, y: Double? = nil, verticalAlign: String? = nil) {
        self.text = text
        self.fill = fill
        self.x = x
        self.y = y
        self.verticalAlign = verticalAlign
    }
}

/// Local minimal reproduction of `label/labelStyle.createTextStyle`. `labelStyle.swift` IS ported
///   (`labelStyle.createTextStyle`, labelStyle.swift:417), but its overload takes a different opt shape
///   (`specifiedTextStyle: TextStyleProps?` + `TextCommonParams`) than this view's `{text, fill, y,
///   verticalAlign}` literal, so the rewire is deferred rather than a missing dep. Only the fields used
///   by the title view (text/font/fill/x/y/verticalAlign/width) are populated; the full rich-text /
///   state / inheritColor / background-box behavior (and the `disableBox` opt) lives in labelStyle.
///   (Distinct from AxisBuilder.swift's `createTextStyle` overload by its `CreateTextStyleOpt`
///   second parameter — no ambiguity.)
private func createTextStyle(
    _ textStyleModel: Model,
    _ opt: CreateTextStyleOpt,
    disableBox: Bool
) -> TextStyleProps {
    _ = disableBox   // PORT-TODO: background-box parsing (labelStyle) is out of static-render scope.
    var style = TextStyleProps()
    style.text = opt.text
    style.font = textStyleModel.getFont()
    style.fill = opt.fill
    style.x = opt.x
    style.y = opt.y
    style.verticalAlign = opt.verticalAlign.flatMap { TextVerticalAlign(rawValue: $0) }
    // TitleTextStyleOption.width (the only text-style extra beyond LabelOption).
    style.width = textStyleModel.get("width") as? Double
    return style
}
