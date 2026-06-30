// Ported from echarts/src/util/format.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                  -> ZRenderKit.util
//   import { encodeHTML } from 'zrender/src/core/dom';                -> NOT ported (zrender core/dom);
//        re-implemented below as a tiny helper (see `encodeHTML`).
//   import { parseDate, isNumeric, numericToNumber, isNullableNumberFinite } from './number';
//        -> EChartsKit `number` namespace (number.parseDate / number.isNumeric / ...).
//   import { TooltipRenderMode, ColorString, ZRColor, DimensionType } from './types'; -> EChartsKit types.swift
//   import { Dictionary } from 'zrender/src/core/types';              -> Dictionary<T> = [String: T]
//   import { GradientObject } from 'zrender/src/graphic/Gradient';    -> ZRenderKit.GradientObject
//   import { format as timeFormat, pad } from './time';               -> EChartsKit `time.format` / `time.pad`
//   import { deprecateReplaceLog } from './log';                      -> EChartsKit `log.deprecateReplaceLog`

// upstream module `format.ts` (free functions + re-exports) -> caseless enum namespace `format`
// (CONVENTIONS §2). Call sites: upstream `addCommas(x)` -> `format.addCommas(x)`.
public enum format {

    /**
     * Add a comma each three digit.
     */
    // upstream signature: `addCommas(x: string | number): string`. The `string | number` union is
    // modeled with two overloads forwarding to a private `Any?` impl (CONVENTIONS dynamic model).
    public static func addCommas(_ x: String) -> String { return _addCommas(x) }
    public static func addCommas(_ x: Double) -> String { return _addCommas(x) }
    static func _addCommas(_ x: Any?) -> String {
        if !number.isNumeric(x) {
            return util.isString(x) ? (x as! String) : "-"
        }
        let parts = _str(x).components(separatedBy: ".")
        // parts[0].replace(/(\d{1,3})(?=(?:\d{3})+(?!\d))/g, '$1,')
        let head = _regexReplaceAll(
            parts[0],
            "(\\d{1,3})(?=(?:\\d{3})+(?!\\d))",
            "$1,"
        )
        return head + (parts.count > 1 ? ("." + parts[1]) : "")
    }

    public static func toCamelCase(_ str: String, _ upperCaseFirst: Bool? = nil) -> String {
        // str = (str || '').toLowerCase().replace(/-(.)/g, fn(match, group1) -> group1.toUpperCase());
        var str = _replaceDashFollowedByUpper(str.lowercased())

        if upperCaseFirst == true, !str.isEmpty {
            // str.charAt(0).toUpperCase() + str.slice(1)
            str = str.prefix(1).uppercased() + str.dropFirst()
        }

        return str
    }

    // upstream: `export const normalizeCssArray = zrUtil.normalizeCssArray;`
    //   zrUtil overload: `normalizeCssArray(val: number | number[])`. Forwarded to ZRenderKit.util.
    public static func normalizeCssArray(_ val: Double) -> [Double] {
        return util.normalizeCssArray(val)
    }
    public static func normalizeCssArray(_ val: [Double]) -> [Double] {
        return util.normalizeCssArray(val)
    }

    // upstream: `export { encodeHTML };` (re-export of zrender core/dom). zrender core/dom is NOT
    //   ported; re-implemented faithfully here as a tiny helper.
    // Ported from zrender/src/core/dom.ts `encodeHTML` — keep in sync with upstream.
    public static func encodeHTML(_ source: String?) -> String {
        // source == null ? '' : (source + '').replace(/([&<>"'])/g, c -> replaceMap[c])
        guard let source = source else {
            return ""
        }
        // Order matters: `&` must be replaced first.
        var result = source
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    /**
     * Make value user readable for tooltip and label.
     * "User readable":
     *     Try to not print programmer-specific text like NaN, Infinity, null, undefined.
     *     Avoid to display an empty string, which users can not recognize there is
     *     a value and it might look like a bug.
     */
    public static func makeValueReadable(
        _ value: Any?,
        _ valueType: DimensionType,
        _ useUTC: Bool
    ) -> String {
        let USER_READABLE_DEFUALT_TIME_PATTERN = "{yyyy}-{MM}-{dd} {HH}:{mm}:{ss}"

        func stringToUserReadable(_ str: String) -> String {
            return (!str.isEmpty && !_trim(str).isEmpty) ? str : "-"
        }
        func isNumberUserReadable(_ num: Double) -> Bool {
            return number.isNullableNumberFinite(num)
        }

        let isTypeTime = valueType == .time
        let isValueDate = value is Date
        if isTypeTime || isValueDate {
            let date = isTypeTime ? number.parseDate(value) : (value as! Date)
            // !isNaN(+date) — `+date` is the timestamp; invalid Date is NaN.
            if !date.timeIntervalSince1970.isNaN {
                return time.format(date, USER_READABLE_DEFUALT_TIME_PATTERN, useUTC)
            }
            else if isValueDate {
                return "-"
            }
            // In other cases, continue to try to display the value in the following code.
        }

        if valueType == .ordinal {
            return util.isStringSafe(value)
                ? stringToUserReadable(value as! String)
                : util.isNumber(value)
                ? (isNumberUserReadable(value as! Double) ? _str(value as! Double) : "-")
                : "-"
        }
        // By default.
        let numericResult = number.numericToNumber(value)
        return isNumberUserReadable(numericResult)
            ? _addCommas(numericResult)
            : util.isStringSafe(value)
            ? stringToUserReadable(value as! String)
            : (value is Bool)
            ? ((value as! Bool) ? "true" : "false")
            : "-"
    }


    static let TPL_VAR_ALIAS = ["a", "b", "c", "d", "e", "f", "g"]

    static func wrapVar(_ varName: String, _ seriesIdx: Double? = nil) -> String {
        return "{" + varName + (seriesIdx == nil ? "" : _str(seriesIdx!)) + "}"
    }

    /**
     * Template formatter
     * @param {Array.<Object>|Object} paramsList
     */
    // upstream `paramsList: TplFormatterParam | TplFormatterParam[]`. `TplFormatterParam` is
    //   `interface extends Dictionary<any> { $vars: string[] }`; per the dynamic-bag convention it is
    //   modeled as `[String: Any]` with `$vars` carried under the `"$vars"` key.
    public typealias TplFormatterParam = Dictionary<Any>   // upstream: Dictionary<any> & { $vars: string[] }
    public static func formatTpl(
        _ tpl: String,
        _ paramsList: Any,
        _ encode: Bool? = nil
    ) -> String {
        var tpl = tpl
        var list: [TplFormatterParam]
        if !util.isArray(paramsList) {
            list = [paramsList as! TplFormatterParam]
        }
        else {
            list = paramsList as! [TplFormatterParam]
        }
        let seriesLen = list.count
        if seriesLen == 0 {
            return ""
        }

        let varList = (list[0]["$vars"] as? [String]) ?? []   // upstream: $vars
        var i = 0
        while i < varList.count {
            let alias = TPL_VAR_ALIAS[i]
            // .replace(...) replaces the FIRST occurrence only (JS string-arg replace).
            tpl = _replaceFirst(tpl, wrapVar(alias), wrapVar(alias, 0))
            i += 1
        }
        for seriesIdx in 0..<seriesLen {
            for k in 0..<varList.count {
                let val = list[seriesIdx][varList[k]]
                tpl = _replaceFirst(
                    tpl,
                    wrapVar(TPL_VAR_ALIAS[k], Double(seriesIdx)),
                    encode == true ? encodeHTML(_strOrNil(val)) : _str(val)
                )
            }
        }

        return tpl
    }

    /**
     * simple Template formatter
     */
    public static func formatTplSimple(_ tpl: String, _ param: Dictionary<Any>, _ encode: Bool? = nil) -> String {
        var tpl = tpl
        // upstream: `zrUtil.each(param, function (value, key) { ... })`. `util.each` has no dictionary
        //   overload in ZRenderKit, so the dict is iterated directly.
        // PORT-TODO: upstream iterates in JS object insertion order; Swift `Dictionary` iteration order
        //   is unspecified, so on overlapping `{key}` placeholders the replacement order may differ.
        for (key, value) in param {
            tpl = _replaceFirst(
                tpl,
                "{" + key + "}",
                encode == true ? encodeHTML(_strOrNil(value)) : _str(value)
            )
        }
        return tpl
    }

    public struct RichTextTooltipMarker {
        public var renderMode: TooltipRenderMode
        public var content: String
        public var style: Dictionary<Any>   // upstream: Dictionary<unknown>
        public init(renderMode: TooltipRenderMode, content: String, style: Dictionary<Any>) {
            self.renderMode = renderMode
            self.content = content
            self.style = style
        }
    }
    // upstream: `type TooltipMarker = string | RichTextTooltipMarker;` -> tagged enum (CONVENTIONS §2).
    //   (This replaces the `typealias TooltipMarker = Any` placeholder in util/types.swift.)
    public enum TooltipMarker {
        case string(String)
        case rich(RichTextTooltipMarker)
    }
    // upstream: `type TooltipMarkerType = 'item' | 'subItem';`
    public enum TooltipMarkerType: String {
        case item
        case subItem
    }
    public struct GetTooltipMarkerOpt {
        public var color: ColorString?
        public var extraCssText: String?
        // By default: 'item'
        public var type: TooltipMarkerType?
        public var renderMode: TooltipRenderMode?
        // id name for marker. If only one marker is in a rich text, this can be omitted.
        // By default: 'markerX'
        public var markerId: String?
        public init(
            color: ColorString? = nil,
            extraCssText: String? = nil,
            type: TooltipMarkerType? = nil,
            renderMode: TooltipRenderMode? = nil,
            markerId: String? = nil
        ) {
            self.color = color
            self.extraCssText = extraCssText
            self.type = type
            self.renderMode = renderMode
            self.markerId = markerId
        }
    }
    // Only support color string
    // upstream overloads:
    //   getTooltipMarker(color: ColorString, extraCssText?: string): TooltipMarker;
    //   getTooltipMarker(opt: GetTooltipMarkerOpt): TooltipMarker;
    public static func getTooltipMarker(_ color: ColorString, _ extraCssText: String? = nil) -> TooltipMarker {
        return _getTooltipMarker(GetTooltipMarkerOpt(color: color, extraCssText: extraCssText))
    }
    public static func getTooltipMarker(_ opt: GetTooltipMarkerOpt) -> TooltipMarker {
        return _getTooltipMarker(opt)
    }
    static func _getTooltipMarker(_ opt: GetTooltipMarkerOpt) -> TooltipMarker {
        // const opt = zrUtil.isString(inOpt) ? { color: inOpt, extraCssText } : (inOpt || {});
        //   (the string-vs-opt branch is handled by the two public overloads above)
        let color = opt.color
        let type = opt.type
        let extraCssText = opt.extraCssText
        let renderMode = opt.renderMode ?? .html

        guard let color = color, !color.isEmpty else {
            // if (!color) return '';
            return .string("")
        }

        if renderMode == .html {
            return type == .subItem
            ? .string("<span style=\"display:inline-block;vertical-align:middle;margin-right:8px;margin-left:3px;"
                + "border-radius:4px;width:4px;height:4px;background-color:"
                // Only support string
                + encodeHTML(color) + ";" + (extraCssText ?? "") + "\"></span>")
            : .string("<span style=\"display:inline-block;margin-right:4px;"
                + "border-radius:10px;width:10px;height:10px;background-color:"
                + encodeHTML(color) + ";" + (extraCssText ?? "") + "\"></span>")
        }
        else {
            // Should better not to auto generate style name by auto-increment number here.
            // Because this util is usually called in tooltip formatter, which is probably
            // called repeatedly when mouse move and the auto-increment number increases fast.
            // Users can make their own style name by theirselves, make it unique and readable.
            let markerId = opt.markerId ?? "markerX"
            return .rich(RichTextTooltipMarker(
                renderMode: renderMode,
                content: "{" + markerId + "|}  ",
                style: type == .subItem
                    ? [
                        "width": 4.0 as Double,
                        "height": 4.0 as Double,
                        "borderRadius": 2.0 as Double,
                        "backgroundColor": color
                    ]
                    : [
                        "width": 10.0 as Double,
                        "height": 10.0 as Double,
                        "borderRadius": 5.0 as Double,
                        "backgroundColor": color
                    ]
            ))
        }
    }


    /**
     * @deprecated Use `time/format` instead.
     * ISO Date format
     * @param {string} tpl
     * @param {number} value
     * @param {boolean} [isUTC=false] Default in local time.
     *           see `module:echarts/scale/Time`
     *           and `module:echarts/util/number#parseDate`.
     * @inner
     */
    public static func formatTime(_ tpl: String, _ value: Any?, _ isUTC: Bool? = nil) -> String {
        var tpl = tpl
        if __DEV__ {
            log.deprecateReplaceLog("echarts.format.formatTime", "echarts.time.format")
        }

        if tpl == "week"
            || tpl == "month"
            || tpl == "quarter"
            || tpl == "half-year"
            || tpl == "year"
        {
            tpl = "MM-dd\nyyyy"
        }

        let date = number.parseDate(value)
        // upstream uses `date['getUTC'+...]()` / `date['get'+...]()`. Modeled via Calendar in the
        //   matching time zone. `getMonth()+1` -> Swift `.month` is already 1-based.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = (isUTC == true) ? TimeZone(identifier: "UTC")! : TimeZone.current
        // PORT-TODO: an invalid Date (NaN) is guarded to epoch to avoid a Calendar trap; upstream would
        //   emit NaN-derived strings here. `formatTime` is deprecated, so this edge is tolerated.
        let safeDate = date.timeIntervalSince1970.isNaN ? Date(timeIntervalSince1970: 0) : date
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: safeDate)
        let y = Double(c.year ?? 0)
        let M = Double(c.month ?? 1)
        let d = Double(c.day ?? 1)
        let h = Double(c.hour ?? 0)
        let m = Double(c.minute ?? 0)
        let s = Double(c.second ?? 0)
        let S = Double((c.nanosecond ?? 0) / 1_000_000)

        tpl = _replaceFirst(tpl, "MM", time.pad(M, 2))
        tpl = _replaceFirst(tpl, "M", _str(M))
        tpl = _replaceFirst(tpl, "yyyy", _str(y))
        tpl = _replaceFirst(tpl, "yy", time.pad(_str(y.truncatingRemainder(dividingBy: 100)), 2))
        tpl = _replaceFirst(tpl, "dd", time.pad(d, 2))
        tpl = _replaceFirst(tpl, "d", _str(d))
        tpl = _replaceFirst(tpl, "hh", time.pad(h, 2))
        tpl = _replaceFirst(tpl, "h", _str(h))
        tpl = _replaceFirst(tpl, "mm", time.pad(m, 2))
        tpl = _replaceFirst(tpl, "m", _str(m))
        tpl = _replaceFirst(tpl, "ss", time.pad(s, 2))
        tpl = _replaceFirst(tpl, "s", _str(s))
        tpl = _replaceFirst(tpl, "SSS", time.pad(S, 3))

        return tpl
    }

    /**
     * Capital first
     * @param {string} str
     * @return {string}
     */
    public static func capitalFirst(_ str: String) -> String {
        // str ? str.charAt(0).toUpperCase() + str.substr(1) : str
        return !str.isEmpty ? (str.prefix(1).uppercased() + str.dropFirst()) : str
    }

    /**
     * @return Never be null/undefined.
     */
    // upstream `color: ZRColor` is the runtime union string | gradient | pattern. The Swift port
    //   models `ZRColor` as a tagged enum, so the `isString`/`isObject` runtime probing becomes a
    //   `switch` (CONVENTIONS §2). Behaviour preserved: gradient -> first stop color (else default);
    //   pattern/object-without-colorStops -> default.
    public static func convertToColorString(_ color: ZRColor, _ defaultColor: ColorString? = nil) -> ColorString {
        let defaultColor = defaultColor ?? "transparent"
        switch color {
        case .color(let s):
            return s
        case .linearGradient(let g):
            // (color.colorStops && (color.colorStops[0] || {}).color) || defaultColor
            return g.colorStops.first.map { $0.color } ?? defaultColor
        case .radialGradient(let g):
            return g.colorStops.first.map { $0.color } ?? defaultColor
        case .pattern:
            // A pattern is an object without `colorStops` -> falsy -> defaultColor.
            return defaultColor
        }
    }

    // upstream: `export { truncateText } from 'zrender/src/graphic/helper/parseText';`
    // PORT-TODO: zrender `graphic/helper/parseText` is NOT ported as a standalone module (its logic
    //   lives inside Text.swift/TSpan.swift). This re-export is a stub returning the text unchanged.
    public static func truncateText(
        _ text: String,
        _ containerWidth: Double,
        _ font: String,
        _ ellipsis: String? = nil,
        _ options: Any? = nil
    ) -> String {
        return text   // PORT-TODO
    }

    /**
     * open new tab
     * @param link url
     * @param target blank or self
     */
    // PORT-TODO: browser-only (`window.open`), CONVENTIONS §9 (renderer/host seam). No-op natively.
    public static func windowOpen(_ link: String, _ target: String) {
        _ = link
        _ = target
        // PORT-TODO: wire to the native host (e.g. UIApplication.open / NSWorkspace.open) when available.
    }


    // upstream: `export { getTextRect } from '../legacy/getTextRect';`
    // PORT-TODO: `legacy/getTextRect.ts` is NOT ported. It builds a `Text` and returns its bounding
    //   rect; stubbed here as an empty rect until the legacy module lands.
    public static func getTextRect(
        _ text: String?,
        _ font: String? = nil,
        _ align: TextAlign? = nil,
        _ verticalAlign: TextVerticalAlign? = nil,
        _ padding: Any? = nil,
        _ rich: Any? = nil,
        _ truncate: Bool? = nil,
        _ lineHeight: Double? = nil
    ) -> BoundingRect {
        return BoundingRect(0, 0, 0, 0)   // PORT-TODO
    }

    // -----------------------------------------------------------------------------------------------
    // Private helpers — not part of upstream `format.ts`. Introduced to faithfully reproduce JS
    // string/number coercions and the `./time` (pad/format) and `zrUtil.trim` calls that this file
    // depends on, none of which are available as ported modules yet.
    // -----------------------------------------------------------------------------------------------

    // JS `'' + x` / value coercion to string for number | string (and a few other primitives).
    static func _str(_ v: Any?) -> String {
        return _strOrNil(v) ?? "undefined"   // JS String(undefined) === 'undefined'
    }
    // Coercion that preserves nil (so `encodeHTML(nil)` can mirror `source == null ? '' : ...`).
    static func _strOrNil(_ v: Any?) -> String? {
        switch v {
        case nil: return nil
        case let s as String: return s
        case let d as Double: return number.jsNumberString(d)
        case let b as Bool: return b ? "true" : "false"
        case let i as Int: return String(i)
        default: return String(describing: v!)
        }
    }

    // zrUtil.trim — `str.replace(/^[\s﻿\xA0]+|[\s﻿\xA0]+$/g, '')`.
    // PORT-TODO: forward to `util.trim` once it is ported to ZRenderKit.util.
    static func _trim(_ str: String) -> String {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FEFF}\u{00A0}")
        return str.trimmingCharacters(in: set)
    }

    // JS `String.prototype.replace(searchString, replacement)` — replaces the FIRST occurrence only.
    // PORT-TODO: JS string-replacement treats `$&`, `$1`, ... specially; this does a literal range
    //   replacement (no `$` substitution).
    static func _replaceFirst(_ s: String, _ target: String, _ replacement: String) -> String {
        guard let r = s.range(of: target) else {
            return s
        }
        return s.replacingCharacters(in: r, with: replacement)
    }

    // JS global regex replace with `$1`/`$2` backreference templates (used by addCommas).
    static func _regexReplaceAll(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return s
        }
        let ns = s as NSString
        return re.stringByReplacingMatches(
            in: s,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: template
        )
    }

    // toCamelCase: `.replace(/-(.)/g, (match, group1) => group1.toUpperCase())`.
    static func _replaceDashFollowedByUpper(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "-(.)") else {
            return s
        }
        let ns = s as NSString
        let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var result = s
        // Replace from the back so earlier ranges stay valid.
        for match in matches.reversed() {
            let g1 = ns.substring(with: match.range(at: 1)).uppercased()
            let full = Range(match.range, in: result)!
            result.replaceSubrange(full, with: g1)
        }
        return result
    }
}
