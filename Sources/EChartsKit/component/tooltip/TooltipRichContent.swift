// Ported from echarts/src/component/tooltip/TooltipRichContent.ts — keep in sync with upstream
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

// upstream imports (resolved to ported modules):
//   import * as zrUtil from 'zrender/src/core/util';        -> ZRenderKit.util / native Swift.
//   import ExtensionAPI from '../../core/ExtensionAPI';     -> see ctor note (takes ZRender directly).
//   import { ZRenderType } from 'zrender/src/zrender';      -> ZRenderKit.ZRender (concrete).
//   import { TooltipOption } from './TooltipModel';         -> TooltipOption (= [String: Any]).
//   import { ZRColor } from '../../util/types';             -> modeled as String (color) here.
//   import Model from '../../model/Model';                  -> EChartsKit Model.
//   import ZRText, { TextStyleProps } from 'zrender/src/graphic/Text';  -> ZRenderKit ZRText / TextStyleProps.
//   import { TooltipMarkupStyleCreator, getPaddingFromTooltipModel } from './tooltipMarkup';  -> Phase 31.
//   import { throwError } from '../../util/log';            -> DEV-mode throw (see setContent PORT-NOTE).

// ARCHITECTURE (port): upstream `TooltipRichContent` reads the LIVE zrender via `api.getZr()`. In this
//   port `ECharts` is render-once with no live zr; the live zr lives in `EChartsView`. The caller
//   (TooltipView, driven by EChartsView) passes the LIVE `ZRender` to the ctor directly. `setContent`
//   adds `el` to that zr; `show()`/`hide()` toggle its visibility; `dispose()` removes it. The `el`
//   floats above the chart (added to the live zr, NOT to `ec.getRoot()`), so it survives chart re-render.

public final class TooltipRichContent {

    // upstream: private _zr: ZRenderType — the LIVE zrender the tooltip element is hosted in.
    private let _zr: ZRender

    private var _show = false

    // upstream: [left, top, ratioX, ratioY]
    private var _styleCoord: [Double] = [0, 0, 0, 0]

    // upstream: private _hideTimeout: number (setTimeout id). Modeled as a DispatchWorkItem so
    //   `clearTimeout` becomes `cancel()`.
    // PORT-NOTE: fires off the MAIN run loop (the `setTimeout` analogue used by util/throttle.swift).
    //   `TooltipView.hide()` routes every hide through `hideLater(tooltip.hideDelay)` (default 100ms),
    //   so this path IS live; `ZZTooltipDelayTests` pumps the run loop to assert the deferred hide lands.
    private var _hideTimeout: DispatchWorkItem?

    private var _alwaysShowContent = false

    private var _enterable = true

    private var _inContent = false

    private var _hideDelay: Double = 0

    // The native host always paints through ZRText, but the authored/rendered Web mode still controls
    // box measurement and placement. `auto` resolves to HTML in the browser; only an explicit
    // `richText` option uses TooltipRichContent's shadow-inclusive geometry.
    private var _usesRichTextLayout = false

    // upstream: el: ZRText (public). Created lazily by setContent.
    public var el: ZRText!

    // upstream: constructor(api: ExtensionAPI) { this._zr = api.getZr(); makeStyleCoord(..., api.getWidth()/2, api.getHeight()/2); }
    //   PORT: take the LIVE ZRender directly (see ARCHITECTURE note). `api.getWidth()/getHeight()`
    //   equal the zr viewport dims here, so they are read from the zr.
    public init(_ zr: ZRender) {
        self._zr = zr
        makeStyleCoord(&self._styleCoord, self._zr, (zr.getWidth() ?? 0) / 2, (zr.getHeight() ?? 0) / 2)
    }

    /// Update when tooltip is rendered
    public func update(_ tooltipModel: Model) {
        let alwaysShowContent = boolOr(tooltipModel.get("alwaysShowContent"), false)
        if alwaysShowContent {
            self._moveIfResized()
        }

        // update alwaysShowContent
        self._alwaysShowContent = alwaysShowContent
    }

    public func show() {
        if let t = self._hideTimeout {
            t.cancel()
            self._hideTimeout = nil
        }

        self.el.show()
        self._show = true
    }

    /// Set tooltip content
    // upstream signature: setContent(content, markupStyleCreator, tooltipModel, borderColor, arrowPosition)
    //   `content: string | HTMLElement | HTMLElement[]` — only the `string` case is supported in
    //   richText mode (DOM nodes throw). `borderColor: ZRColor` -> String. `arrowPosition` is unused
    //   in richText mode (kept for API parity with TooltipHTMLContent).
    public func setContent(
        _ content: String,
        _ markupStyleCreator: TooltipMarkupStyleCreator,
        _ tooltipModel: Model,
        _ borderColor: String?,
        _ arrowPosition: Any? = nil
    ) {
        // PORT-NOTE: upstream `if (isObject(content)) throwError('Passing DOM nodes ...')` — dev guard.
        //   `content` is a Swift String here, so the DOM-node branch is unrepresentable.
        _ = arrowPosition

        if self.el != nil {
            self._zr.remove(self.el)
        }

        let textStyleModel = tooltipModel.getModel("textStyle")
        self._usesRichTextLayout = str(tooltipModel.get("renderMode")) == "richText"

        // Native has no DOM-backed TooltipHTMLContent, so ZRText is also the host for the Web
        // default `renderMode: 'html'`. Keep the upstream HTML renderer's computed line-height
        // (`retrieve2(textStyle.lineHeight, Math.round(fontSize * 3 / 2))`) instead of the 22px
        // constant used only by upstream's explicitly selected richText renderer.
        // NOTE (port): TextStyleProps is a value type — useStyle copies it — so ALL style fields
        //   (including the ones upstream mutates AFTER construction via `this.el.style[...]=`) are set
        //   on the struct BEFORE useStyle, then applied in one shot.
        var style = TextStyleProps()
        // upstream `rich: markupStyleCreator.richTextStyles` — the `{styleName|text}` token style map.
        // Native formatter callbacks may return rich-text tokens in place of Web-only HTML spans, so
        // also retain authored `tooltip.textStyle.rich` entries. Generated marker/layout styles win on
        // collision, matching their role as the final markup-owned styles for this tooltip instance.
        var richTextStyles = (textStyleModel.get("rich") as? [String: Any])?.reduce(
            into: [String: [String: Any]]()
        ) { result, entry in
            if let bag = entry.value as? [String: Any] {
                result[entry.key] = bag
            }
        } ?? [:]
        for (name, bag) in markupStyleCreator.richTextStyles {
            richTextStyles[name] = bag
        }
        style.rich = richTextStylesToParts(richTextStyles)
        // The browser examples commonly return HTML line breaks from formatter callbacks. This
        // native host is intentionally rich-text-only, so leaving `<br/>` untouched paints the tag
        // literally. Preserve the formatter's line structure by translating every HTML break spelling
        // to the newline understood by ZRText.
        style.text = content.replacingOccurrences(
            of: #"(?i)<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        if self._usesRichTextLayout {
            style.lineHeight = 22
        }
        else {
            let fontSize = dbl(textStyleModel.get("fontSize")) ?? 14
            style.lineHeight = dbl(textStyleModel.get("lineHeight")) ?? (fontSize * 3 / 2).rounded()
        }
        style.borderWidth = 1
        style.borderColor = borderColor
        style.textShadowColor = str(textStyleModel.get("textShadowColor"))
        style.fill = str(tooltipModel.get(["textStyle", "color"]))
        style.padding = numberOrNumberArray(getPaddingFromTooltipModel(tooltipModel, .richText))
        style.verticalAlign = .top
        style.align = .left

        // TooltipHTMLContent appends `extraCssText` to the element style verbatim. Native rich text has
        // no CSS engine, but zrender exposes the equivalent fixed-width + wrapping primitives. Preserve
        // those upstream semantics generically for the supported CSS declarations instead of treating
        // any demo specially.
        if let extraCssText = tooltipModel.get("extraCssText") as? String {
            for declaration in extraCssText.split(separator: ";") {
                let pair = declaration.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                guard pair.count == 2 else { continue }
                if pair[0] == "width" {
                    let raw = pair[1].replacingOccurrences(of: "px", with: "")
                    if let width = Double(raw) { style.width = width }
                }
                else if pair[0] == "white-space" && pair[1] == "normal" {
                    style.overflow = "break"
                }
            }
        }

        // upstream each(['backgroundColor', 'borderRadius', 'shadowColor', 'shadowBlur',
        //   'shadowOffsetX', 'shadowOffsetY'], propName => el.style[propName] = tooltipModel.get(propName))
        if let bg = str(tooltipModel.get("backgroundColor")) {
            style.backgroundColor = .string(bg)
        }
        style.borderRadius = numberOrNumberArray(tooltipModel.get("borderRadius"))
        style.shadowColor = str(tooltipModel.get("shadowColor"))
        style.shadowBlur = dbl(tooltipModel.get("shadowBlur"))
        style.shadowOffsetX = dbl(tooltipModel.get("shadowOffsetX"))
        style.shadowOffsetY = dbl(tooltipModel.get("shadowOffsetY"))

        // upstream each(['textShadowBlur', 'textShadowOffsetX', 'textShadowOffsetY'],
        //   propName => el.style[propName] = textStyleModel.get(propName) || 0)
        style.textShadowBlur = dbl(textStyleModel.get("textShadowBlur")) ?? 0
        style.textShadowOffsetX = dbl(textStyleModel.get("textShadowOffsetX")) ?? 0
        style.textShadowOffsetY = dbl(textStyleModel.get("textShadowOffsetY")) ?? 0

        let el = ZRText()
        el.useStyle(style)
        // HTML mode appends `pointer-events:none` whenever enterable is false. Rich-text mode uses a
        // zrender element instead of a DOM node, so `silent` is the exact hit-test/event-routing
        // equivalent: data graphics underneath remain reachable while the tooltip is visible.
        el.silent = !self._enterable
        el.z = dbl(tooltipModel.get("z")) ?? 0
        // The native host has no DOM tooltip layer: rich text is inserted into the same zrender
        // storage as the chart. A series may use a positive zlevel (effectScatter commonly uses 1),
        // which otherwise wins before `z` is considered and paints symbols/labels over the tooltip.
        // Place the native tooltip one zlevel above the current scene to preserve the browser HTML
        // overlay contract while keeping the option's `z` ordering within that top layer.
        let highestSceneZLevel = self._zr.storage.getDisplayList(true).map(\.zlevel).max() ?? 0
        el.zlevel = highestSceneZLevel + 1
        self.el = el

        self._zr.add(el)

        // upstream: el.on('mouseover'/'mouseout', ...) — keep the tooltip alive while the pointer is
        //   over its own box (enterable). Bound weakly to avoid the el -> self retain cycle.
        el.on("mouseover", { [weak self] _, _ in
            guard let self = self else { return nil }
            // clear the timeout in hideLater and keep showing tooltip
            if self._enterable {
                self._hideTimeout?.cancel()
                self._hideTimeout = nil
                self._show = true
            }
            self._inContent = true
            return nil
        })
        el.on("mouseout", { [weak self] _, _ in
            guard let self = self else { return nil }
            if self._enterable {
                if self._show {
                    self.hideLater(self._hideDelay)
                }
            }
            self._inContent = false
            return nil
        })
    }

    public func setEnterable(_ enterable: Bool?) {
        self._enterable = enterable ?? false
        self.el?.silent = !self._enterable
    }

    // upstream: getSize(): [number, number]
    public func getSize() -> [Double] {
        let el = self.el!
        let bounding = el.getBoundingRect()
        if !self._usesRichTextLayout {
            // TooltipHTMLContent.getSize(): DOM offsetWidth/offsetHeight include the border box but
            // exclude the CSS box shadow.
            return [bounding?.width ?? 0, bounding?.height ?? 0]
        }
        // bounding rect does not include shadow. For renderMode richText,
        // if overflow, it will be cut. So calculate them accurately.
        let shadowOuterSize = calcShadowOuterSize(el.textStyle)
        return [
            (bounding?.width ?? 0) + shadowOuterSize.left + shadowOuterSize.right,
            (bounding?.height ?? 0) + shadowOuterSize.top + shadowOuterSize.bottom
        ]
    }

    public func moveTo(_ x: Double, _ y: Double) {
        guard let el = self.el else { return }
        var x = x
        var y = y
        makeStyleCoord(&self._styleCoord, self._zr, x, y)
        x = self._styleCoord[0]
        y = self._styleCoord[1]
        let style = el.textStyle!
        let borderWidth = mathMaxWith0(style.borderWidth ?? 0)
        let shadowOuterSize = self._usesRichTextLayout
            ? calcShadowOuterSize(style)
            : (left: 0, right: 0, top: 0, bottom: 0)
        // rich text x, y do not include border.
        el.x = x + borderWidth + shadowOuterSize.left
        el.y = y + borderWidth + shadowOuterSize.top
        el.markRedraw()
    }

    /// when `alwaysShowContent` is true, move the tooltip after chart resized
    func _moveIfResized() {
        // The ratio of left to width
        let ratioX = self._styleCoord[2]
        // The ratio of top to height
        let ratioY = self._styleCoord[3]
        self.moveTo(
            ratioX * (self._zr.getWidth() ?? 0),
            ratioY * (self._zr.getHeight() ?? 0)
        )
    }

    public func hide() {
        if let el = self.el {
            el.hide()
        }
        self._show = false
    }

    // upstream: hideLater(time?: number)
    public func hideLater(_ time: Double? = nil) {
        if self._show && !(self._inContent && self._enterable) && !self._alwaysShowContent {
            if let time = time, time != 0 {
                self._hideDelay = time
                // Set show false to avoid invoke hideLater multiple times
                self._show = false
                let work = DispatchWorkItem { [weak self] in
                    guard let self = self else { return }
                    // Release the slot before hiding: unlike upstream's numeric `setTimeout` id, a fired
                    //   `DispatchWorkItem` would otherwise be retained until the next `hideLater`.
                    //   `hide()` -> `el.hide()` -> `markRedraw()` already calls `zr.refresh()`, so the
                    //   deferred hide is painted on the next frame exactly like upstream zrender.
                    self._hideTimeout = nil
                    self.hide()
                }
                self._hideTimeout = work
                // PORT-NOTE: setTimeout(fn, ms) -> main-queue asyncAfter (ms -> seconds).
                DispatchQueue.main.asyncAfter(deadline: .now() + time / 1000.0, execute: work)
            }
            else {
                self.hide()
            }
        }
    }

    public func isShow() -> Bool {
        return self._show
    }

    public func dispose() {
        // PORT-NOTE (divergence, forced): a pending `hideLater` timer must not outlive dispose (it would
        //   touch an `el` already removed from the zr), and `_show` must go false so a later
        //   `TooltipView.hide()` cannot arm a FRESH timer against the torn-down content. Upstream is
        //   immune by accident — `TooltipView.dispose` nulls `_tooltipContent`, which this port (a `let`
        //   stored property) cannot do.
        self._hideTimeout?.cancel()
        self._hideTimeout = nil
        self._show = false
        self._zr.remove(self.el)
    }
}

// upstream: function mathMaxWith0(val): Math.max(0, val)
private func mathMaxWith0(_ val: Double) -> Double {
    return Swift.max(0, val)
}

// upstream: function calcShadowOuterSize(style: TextStyleProps)
private func calcShadowOuterSize(_ style: TextStyleProps) -> (left: Double, right: Double, top: Double, bottom: Double) {
    let shadowBlur = mathMaxWith0(style.shadowBlur ?? 0)
    let shadowOffsetX = mathMaxWith0(style.shadowOffsetX ?? 0)
    let shadowOffsetY = mathMaxWith0(style.shadowOffsetY ?? 0)
    return (
        left: mathMaxWith0(shadowBlur - shadowOffsetX),
        right: mathMaxWith0(shadowBlur + shadowOffsetX),
        top: mathMaxWith0(shadowBlur - shadowOffsetY),
        bottom: mathMaxWith0(shadowBlur + shadowOffsetY)
    )
}

// upstream: function makeStyleCoord(out, zr, zrX, zrY)
private func makeStyleCoord(_ out: inout [Double], _ zr: ZRender, _ zrX: Double, _ zrY: Double) {
    out[0] = zrX
    out[1] = zrY
    out[2] = out[0] / (zr.getWidth() ?? 0)
    out[3] = out[1] / (zr.getHeight() ?? 0)
}

// ---- Port seam: `richTextStyles: [String: [String: Any]]` -> `[String: TextStylePropsPart]` ----
// upstream assigns `rich: markupStyleCreator.richTextStyles` directly (TS structural typing). The
// Swift `TextStyleProps.rich` is strongly typed `[String: TextStylePropsPart]`, so each style bag
// produced by `TooltipMarkupStyleCreator` (keys: fontSize / fill / fontWeight / padding / align /
// width / height / borderRadius / backgroundColor / verticalAlign / lineHeight — see tooltipMarkup +
// format.getTooltipMarker) is converted into a `TextStylePropsPart`.
private func richTextStylesToParts(_ styles: [String: [String: Any]]) -> [String: TextStylePropsPart] {
    var out: [String: TextStylePropsPart] = [:]
    for (name, bag) in styles {
        var part = TextStylePropsPart()
        if let v = bag["fontSize"] { part.fontSize = numberOrString(v) }
        part.fill = str(bag["fill"]) ?? str(bag["color"])
        if let v = bag["fontWeight"] { part.fontWeight = fontWeight(v) }
        if let v = bag["fontStyle"], let s = v as? String { part.fontStyle = FontStyle(rawValue: s) }
        if let v = bag["fontFamily"] as? String { part.fontFamily = v }
        part.padding = numberOrNumberArray(bag["padding"])
        if let v = bag["align"] as? String { part.align = TextAlign(rawValue: v) }
        if let v = bag["verticalAlign"] as? String { part.verticalAlign = TextVerticalAlign(rawValue: v) }
        // `width` (NumberOrString) — REQUIRED: the series-color swatch marker is an empty-text token
        //   sized purely by explicit width+height+backgroundColor (`{width:10,height:10,borderRadius:5,
        //   backgroundColor:…}`). Without this branch the marker text is "" → ZRText measures width 0 →
        //   the color dot collapses. Upstream assigns the whole style bag wholesale (rich: richTextStyles),
        //   so it never drops width.
        if let v = bag["width"] { part.width = numberOrString(v) }
        part.height = dbl(bag["height"])
        part.lineHeight = dbl(bag["lineHeight"])
        part.borderRadius = numberOrNumberArray(bag["borderRadius"])
        if let bg = str(bag["backgroundColor"]) { part.backgroundColor = .string(bg) }
        out[name] = part
    }
    return out
}

// ---- Int/Double/String coercion helpers (defaultOptions box numbers as Int or Double; user input
//   may be either). Local to this file (no shared coercion helper exists; see MEMORY). ----
private func dbl(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

private func str(_ v: Any?) -> String? {
    if v == nil || v is NSNull { return nil }
    if let s = v as? String { return s }
    return nil
}

private func boolOr(_ v: Any?, _ def: Bool) -> Bool {
    if let b = v as? Bool { return b }
    return def
}

private func numberOrString(_ v: Any?) -> NumberOrString? {
    if let d = dbl(v) { return .number(d) }
    if let s = v as? String { return .string(s) }
    return nil
}

// upstream `padding` / `borderRadius`: `number | number[]`.
private func numberOrNumberArray(_ v: Any?) -> NumberOrNumberArray? {
    if v == nil || v is NSNull { return nil }
    if let arr = v as? [Double] { return .array(arr) }
    if let arr = v as? [Any] {
        let doubles = arr.compactMap { dbl($0) }
        return .array(doubles)
    }
    if let d = dbl(v) { return .number(d) }
    return nil
}

// FontWeight coercion: tooltip rich fontWeight values are numeric-weight strings ("400"/"900") or the
// named CSS keywords. A numeric string / number becomes `.number`; the keywords map to their cases.
private func fontWeight(_ v: Any?) -> FontWeight? {
    if let d = dbl(v) { return .number(d) }
    if let s = v as? String {
        switch s {
        case "normal": return .normal
        case "bold": return .bold
        case "bolder": return .bolder
        case "lighter": return .lighter
        default: return nil
        }
    }
    return nil
}
