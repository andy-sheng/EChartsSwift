// Ported from echarts/src/component/tooltip/tooltipMarkup.ts — keep in sync with upstream
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
//   import { Dictionary, TooltipRenderMode, ColorString, TooltipOrderMode, DimensionType,
//            CommonTooltipOption, OptionDataValue } from '../../util/types';
//     -> EChartsKit util/types.swift (same module). `Dictionary<T>` = `[String: T]`.
//   import { TooltipMarkerType, getTooltipMarker, encodeHTML, makeValueReadable,
//            convertToColorString } from '../../util/format';
//     -> EChartsKit `format` namespace (format.TooltipMarkerType / format.getTooltipMarker / ...).
//   import { isString, each, hasOwn, isArray, map, assert, extend } from 'zrender/src/core/util';
//     -> ZRenderKit.util / native Swift control flow (each/map/extend collapse to for-loops/`map`).
//   import { SortOrderComparator } from '../../data/helper/dataValueHelper';
//     -> `SortOrderComparator` (data/helper/dataValueHelper.swift, same module).
//   import SeriesModel from '../../model/Series';    -> `SeriesModel` (model/Series.swift).
//   import { getRandomIdBase } from '../../util/number';  -> `number.getRandomIdBase`.
//   import Model from '../../model/Model';           -> `Model` (model/Model.swift).
//   import { TooltipOption } from './TooltipModel';  -> `TooltipOption` (= [String: Any], TooltipModel.swift).
//   import tokens from '../../visual/tokens';        -> `tokens` (visual/tokens.swift, TASK 1).

// upstream:
//   type RichTextStyle = { fontSize: number | string, fill: string, fontWeight?: number | string };
//   type TextStyle = string | RichTextStyle;
// A `RichTextStyle` is modeled as the dynamic style bag `[String: Any]` (it is fed straight into
// `TooltipMarkupStyleCreator.wrapRichTextStyle`, which merges arbitrary style keys). The
// `string | RichTextStyle` union becomes a tagged enum (CONVENTIONS §2).
public typealias RichTextStyle = [String: Any]
public enum TextStyle {
    case html(String)
    case rich(RichTextStyle)
    // `nameStyle as string` / `nameStyle as RichTextStyle` accessors (render-mode is known at the
    // use-site, so the "wrong" branch is never taken — mirrors the upstream casts).
    var htmlString: String {
        if case .html(let s) = self { return s }
        return ""
    }
    var richStyle: RichTextStyle {
        if case .rich(let d) = self { return d }
        return [:]
    }
}

// upstream: `TooltipOption['textStyle']` — the `textStyle` sub-bag of the tooltip option.
public typealias TooltipTextStyleOption = [String: Any]

// upstream: `CommonTooltipOption<unknown>['valueFormatter']`
//   = (value: OptionDataValue | OptionDataValue[], dataIndex?: number) => string | string[]
public typealias TooltipValueFormatter = (_ value: Any?, _ dataIndex: Int?) -> Any

let TOOLTIP_LINE_HEIGHT_CSS = "line-height:1"

func getTooltipLineHeight(
    _ textStyle: TooltipTextStyleOption
) -> String {
    let lineHeight = textStyle["lineHeight"]
    if lineHeight == nil || lineHeight is NSNull {
        return TOOLTIP_LINE_HEIGHT_CSS
    }
    else {
        return "line-height:" + format.encodeHTML(number.jsString(lineHeight)) + "px"
    }
}
// TODO: more textStyle option
func getTooltipTextStyle(
    _ textStyle: TooltipTextStyleOption,
    _ renderMode: TooltipRenderMode
) -> (nameStyle: TextStyle, valueStyle: TextStyle) {
    // `textStyle.color || tokens.color.tertiary` — JS truthiness (empty string / null are falsy).
    let colorVal = textStyle["color"]
    let nameFontColor = jsTruthy(colorVal) ? number.jsString(colorVal) : tokens.color.tertiary
    let nameFontSize: Any = jsTruthy(textStyle["fontSize"]) ? textStyle["fontSize"]! : (12 as Double)
    let nameFontWeight: Any = jsTruthy(textStyle["fontWeight"]) ? textStyle["fontWeight"]! : "400"
    let valueFontColor = jsTruthy(colorVal) ? number.jsString(colorVal) : tokens.color.secondary
    let valueFontSize: Any = jsTruthy(textStyle["fontSize"]) ? textStyle["fontSize"]! : (14 as Double)
    let valueFontWeight: Any = jsTruthy(textStyle["fontWeight"]) ? textStyle["fontWeight"]! : "900"

    if renderMode == .html {
        // `textStyle` is probably from user input, should be encoded to reduce security risk.
        return (
            nameStyle: .html(
                "font-size:" + format.encodeHTML(number.jsString(nameFontSize))
                    + "px;color:" + format.encodeHTML(nameFontColor)
                    + ";font-weight:" + format.encodeHTML(number.jsString(nameFontWeight))
            ),
            valueStyle: .html(
                "font-size:" + format.encodeHTML(number.jsString(valueFontSize))
                    + "px;color:" + format.encodeHTML(valueFontColor)
                    + ";font-weight:" + format.encodeHTML(number.jsString(valueFontWeight))
            )
        )
    }
    else {
        return (
            nameStyle: .rich([
                "fontSize": nameFontSize,
                "fill": nameFontColor,
                "fontWeight": nameFontWeight
            ]),
            valueStyle: .rich([
                "fontSize": valueFontSize,
                "fill": valueFontColor,
                "fontWeight": valueFontWeight
            ])
        )
    }
}

// 0: no gap in this block.
// 1: has max gap in level 1 in this block.
// ...
// upstream: `type GapLevel = number;` — modeled as `Int`.
// See `TooltipMarkupLayoutIntent['innerGapLevel']`.
// (value from UI design)
// upstream: `const HTML_GAPS: Record<GapLevel, number> = [0, 10, 20, 30];`
private let HTML_GAPS: [Double] = [0, 10, 20, 30]
// upstream: `const RICH_TEXT_GAPS: Record<GapLevel, string> = ['', '\n', '\n\n', '\n\n\n'];`
private let RICH_TEXT_GAPS: [String] = ["", "\n", "\n\n", "\n\n\n"]

/**
 * This is an abstract layer to insulate the upper usage of tooltip content
 * from the different backends according to different `renderMode` ('html' or 'richText').
 *
 * upstream union:
 *   type TooltipMarkupBlockFragment = TooltipMarkupSection | TooltipMarkupNameValueBlock;
 * Swift has no TS unions -> a common base `class TooltipMarkupBlock` + a `type` discriminator tag,
 * with `TooltipMarkupBlockFragment` aliased to the base (CONVENTIONS §2). Reference semantics match
 * upstream, where `createTooltipMarkup` mutates the passed option object in place.
 */

// upstream:
//   interface TooltipMarkupBlock { sortParam?: unknown; }
// NOTE: upstream declares `valueFormatter` separately on both `TooltipMarkupSection` and
//   `TooltipMarkupNameValueBlock`; it is unified onto the base here so `buildTooltipMarkup` can read
//   `fragment.valueFormatter` off the union without downcasting (behaviour identical).
public class TooltipMarkupBlock {
    // The `type` discriminator (`'section'` | `'nameValue'`). Lives on the subclasses upstream; kept
    // on the base for `isSectionFragment`/`getBuilder` dispatch.
    public var type: String
    // Use to make comparison when `sortBlocks: true`.
    public var sortParam: Any?
    public var valueFormatter: TooltipValueFormatter?
    public init(type: String) {
        self.type = type
    }
}

// upstream union alias.
public typealias TooltipMarkupBlockFragment = TooltipMarkupBlock

public final class TooltipMarkupSection: TooltipMarkupBlock {
    // type: 'section'
    public var header: Any?
    // If `noHeader` is `true`, do not display header.
    // Otherwise, always display it even if it is null/undefined/NaN/''... (displayed as '-').
    public var noHeader: Bool?
    public var blocks: [TooltipMarkupBlockFragment]?
    // Enable to sort blocks when making final html or richText.
    public var sortBlocks: Bool?

    public init(
        header: Any? = nil,
        noHeader: Bool? = nil,
        blocks: [TooltipMarkupBlockFragment]? = nil,
        sortBlocks: Bool? = nil,
        valueFormatter: TooltipValueFormatter? = nil,
        sortParam: Any? = nil
    ) {
        self.header = header
        self.noHeader = noHeader
        self.blocks = blocks
        self.sortBlocks = sortBlocks
        super.init(type: "section")
        self.valueFormatter = valueFormatter
        self.sortParam = sortParam
    }
}

public final class TooltipMarkupNameValueBlock: TooltipMarkupBlock {
    // type: 'nameValue'
    // If `!markerType`, tooltip marker is not used.
    public var markerType: format.TooltipMarkerType?
    public var markerColor: ColorString?
    public var name: String?
    // Also support value is `[121, 555, 94.2]`.
    public var value: Any?
    // upstream: `valueType?: DimensionType | DimensionType[]` — modeled as `Any?`.
    // If not specified, treat value as normal string or numeric. 'time' / 'ordinal' as upstream.
    public var valueType: Any?
    // If `noName` or `noValue` is `true`, do not display name or value.
    public var noName: Bool?
    public var noValue: Bool?
    public var rawDataIndex: Int?

    public init(
        markerType: format.TooltipMarkerType? = nil,
        markerColor: ColorString? = nil,
        name: String? = nil,
        value: Any? = nil,
        valueType: Any? = nil,
        noName: Bool? = nil,
        noValue: Bool? = nil,
        rawDataIndex: Int? = nil,
        valueFormatter: TooltipValueFormatter? = nil,
        sortParam: Any? = nil
    ) {
        self.markerType = markerType
        self.markerColor = markerColor
        self.name = name
        self.value = value
        self.valueType = valueType
        self.noName = noName
        self.noValue = noValue
        self.rawDataIndex = rawDataIndex
        super.init(type: "nameValue")
        self.valueFormatter = valueFormatter
        self.sortParam = sortParam
    }
}

/**
 * Create tooltip markup by this function, we can get TS type check.
 *
 * upstream overloads (`createTooltipMarkup('section', option)` /
 * `createTooltipMarkup('nameValue', option)`) -> two Swift overloads distinguished by option type.
 * The `option.type = type` assignment is preserved (the initializers already set it; this keeps the
 * upstream call shape and re-tags defensively).
 */
@discardableResult
public func createTooltipMarkup(_ type: String, _ option: TooltipMarkupSection) -> TooltipMarkupSection {
    option.type = type
    return option
}
@discardableResult
public func createTooltipMarkup(_ type: String, _ option: TooltipMarkupNameValueBlock) -> TooltipMarkupNameValueBlock {
    option.type = type
    return option
}


// Can be null/undefined, which means generate nothing markup text.
// upstream: `type MarkupText = string;` used as `MarkupText` (nullable return) -> `String?`.
public typealias MarkupText = String

// upstream:
//   interface TooltipMarkupFragmentBuilder {
//       (ctx, fragment, topMarginForOuterGap: number, toolTipTextStyle): MarkupText
//   }
typealias TooltipMarkupFragmentBuilder =
    (TooltipMarkupBuildContext, TooltipMarkupBlockFragment, Double, TooltipTextStyleOption) -> MarkupText?

func isSectionFragment(_ frag: TooltipMarkupBlockFragment) -> Bool {
    return frag.type == "section"
}

func getBuilder(_ frag: TooltipMarkupBlockFragment) -> TooltipMarkupFragmentBuilder {
    return isSectionFragment(frag)
        ? { ctx, f, topMargin, ts in buildSection(ctx, f as! TooltipMarkupSection, topMargin, ts) }
        : { ctx, f, topMargin, ts in buildNameValue(ctx, f as! TooltipMarkupNameValueBlock, topMargin, ts) }
}

func getBlockGapLevel(_ frag: TooltipMarkupBlockFragment) -> Int {
    if let section = frag as? TooltipMarkupSection, isSectionFragment(frag) {
        var gapLevel = 0
        let subBlocks = section.blocks ?? []
        let subBlockLen = subBlocks.count
        let hasInnerGap = subBlockLen > 1 || (subBlockLen > 0 && !(section.noHeader ?? false))
        for subBlock in subBlocks {
            let subGapLevel = getBlockGapLevel(subBlock)
            // If the some of the sub-blocks have some gaps (like 10px) inside, this block
            // should use a larger gap (like 20px) to distinguish those sub-blocks.
            if subGapLevel >= gapLevel {
                // `+( hasInnerGap && ( !subGapLevel || (isSectionFragment(subBlock) && !subBlock.noHeader) ) )`
                //   — JS unary `+boolean` -> 0/1.
                let addGap = hasInnerGap && (
                    // 0 always can not be readable gap level.
                    subGapLevel == 0
                    // If no header, always keep the sub gap level. Otherwise look weird in case `multipleSeries`.
                    || (isSectionFragment(subBlock) && !((subBlock as! TooltipMarkupSection).noHeader ?? false))
                )
                gapLevel = subGapLevel + (addGap ? 1 : 0)
            }
        }
        return gapLevel
    }
    return 0
}

func buildSection(
    _ ctx: TooltipMarkupBuildContext,
    _ fragment: TooltipMarkupSection,
    _ topMarginForOuterGap: Double,
    _ toolTipTextStyle: TooltipTextStyleOption
) -> MarkupText {
    let noHeader = fragment.noHeader ?? false

    let gaps = getGap(getBlockGapLevel(fragment))

    var subMarkupTextList: [String] = []
    // upstream: `assert(!subBlocks || isArray(subBlocks));` — always an array in Swift.
    var subBlocks = fragment.blocks ?? []

    let orderMode = ctx.orderMode
    if (fragment.sortBlocks ?? false) && orderMode != nil {
        // upstream: `subBlocks = subBlocks.slice();` — `subBlocks` is already a value-type Array copy
        //   of `fragment.blocks`, so no explicit slice is needed before the in-place sort below.
        // upstream: `const orderMap = { valueAsc: 'asc', valueDesc: 'desc' } as const;`
        let orderMap: [TooltipOrderMode: String] = [.valueAsc: "asc", .valueDesc: "desc"]
        // hasOwn(orderMap, orderMode) -> `orderMap[orderMode] != nil`.
        if let mappedOrder = orderMap[orderMode!] {
            let comparator = SortOrderComparator(mappedOrder, nil)
            subBlocks.sort { comparator.evaluate($0.sortParam, $1.sortParam) < 0 }
        }
        // FIXME 'seriesDesc' necessary?
        else if orderMode == .seriesDesc {
            subBlocks.reverse()
        }
    }

    for (idx, subBlock) in subBlocks.enumerated() {
        let valueFormatter = fragment.valueFormatter
        // Inherit valueFormatter: `valueFormatter ? extend(extend({}, ctx), { valueFormatter }) : ctx`.
        var subCtx = ctx
        if let valueFormatter = valueFormatter {
            subCtx.valueFormatter = valueFormatter
        }
        let subMarkupText = getBuilder(subBlock)(
            subCtx,
            subBlock,
            idx > 0 ? gaps.html : 0,
            toolTipTextStyle
        )
        if let subMarkupText = subMarkupText {
            subMarkupTextList.append(subMarkupText)
        }
    }

    let subMarkupText = ctx.renderMode == .richText
        ? subMarkupTextList.joined(separator: gaps.richText)
        : wrapBlockHTML(
            toolTipTextStyle,
            subMarkupTextList.joined(),
            noHeader ? topMarginForOuterGap : gaps.html
        )

    if noHeader {
        return subMarkupText
    }

    let displayableHeader = format.makeValueReadable(fragment.header, .ordinal, ctx.useUTC)
    let nameStyle = getTooltipTextStyle(toolTipTextStyle, ctx.renderMode).nameStyle
    let tooltipLineHeight = getTooltipLineHeight(toolTipTextStyle)
    if ctx.renderMode == .richText {
        return wrapInlineNameRichText(ctx, displayableHeader, nameStyle.richStyle) + gaps.richText
            + subMarkupText
    }
    else {
        return wrapBlockHTML(
            toolTipTextStyle,
            "<div style=\"" + nameStyle.htmlString + ";" + tooltipLineHeight + ";\">"
                + format.encodeHTML(displayableHeader)
                + "</div>"
                + subMarkupText,
            topMarginForOuterGap
        )
    }
}

func buildNameValue(
    _ ctx: TooltipMarkupBuildContext,
    _ fragment: TooltipMarkupNameValueBlock,
    _ topMarginForOuterGap: Double,
    _ toolTipTextStyle: TooltipTextStyleOption
) -> MarkupText? {
    let renderMode = ctx.renderMode
    let noName = fragment.noName ?? false
    let noValue = fragment.noValue ?? false
    let noMarker = fragment.markerType == nil
    let name = fragment.name
    let useUTC = ctx.useUTC
    // `const valueTypeOption = fragment.valueType;` is declared AFTER the default `valueFormatter`
    //   upstream, but the arrow closes over it and is only invoked later (JS `const` init happens
    //   before the call). It is hoisted above the closure here so the capture is valid in Swift.
    let valueTypeOption = fragment.valueType
    let valueFormatter: TooltipValueFormatter = fragment.valueFormatter ?? ctx.valueFormatter ?? { value, _ in
        let arr: [Any?] = util.isArray(value) ? (value as! [Any]) : [value]
        return arr.enumerated().map { (idx, val) -> String in
            // `isArray(valueTypeOption) ? valueTypeOption[idx] : valueTypeOption`
            let vt: DimensionType?
            if let types = valueTypeOption as? [Any?] {
                vt = (idx < types.count ? types[idx] : nil) as? DimensionType
            }
            else {
                vt = valueTypeOption as? DimensionType
            }
            // `format.makeValueReadable` takes a non-optional `DimensionType`; an
            //   `undefined`/nil valueType takes the same "by default" branch as `.number`, so nil
            //   maps to `.number` here (identical output).
            return format.makeValueReadable(val, vt ?? .number, useUTC)
        }
    }

    if noName && noValue {
        return nil
    }

    let markerStr = noMarker
        ? ""
        : ctx.markupStyleCreator.makeTooltipMarker(
            fragment.markerType!,
            jsTruthy(fragment.markerColor) ? fragment.markerColor! : tokens.color.secondary,
            renderMode
        )
    let readableName = noName
        ? ""
        : format.makeValueReadable(name, .ordinal, useUTC)
    let readableValueList: Any = noValue
        ? [] as [String]
        : valueFormatter(fragment.value, fragment.rawDataIndex)
    let valueAlignRight = !noMarker || !noName
    // It little weird if only value next to marker but far from marker.
    let valueCloseToMarker = !noMarker && noName

    let styles = getTooltipTextStyle(toolTipTextStyle, renderMode)
    let nameStyle = styles.nameStyle
    let valueStyle = styles.valueStyle

    return renderMode == .richText
        ? (
            (noMarker ? "" : markerStr)
            + (noName ? "" : wrapInlineNameRichText(ctx, readableName, nameStyle.richStyle))
            // Value has commas inside, so use ' ' as delimiter for multiple values.
            + (noValue ? "" : wrapInlineValueRichText(
                ctx, readableValueList, valueAlignRight, valueCloseToMarker, valueStyle.richStyle
            ))
        )
        : wrapBlockHTML(
            toolTipTextStyle,
            (noMarker ? "" : markerStr)
            + (noName ? "" : wrapInlineNameHTML(readableName, !noMarker, nameStyle.htmlString))
            + (noValue ? "" : wrapInlineValueHTML(
                readableValueList, valueAlignRight, valueCloseToMarker, valueStyle.htmlString
            )),
            topMarginForOuterGap
        )
}

// upstream:
//   interface TooltipMarkupBuildContext { useUTC; renderMode; orderMode; markupStyleCreator; valueFormatter }
public struct TooltipMarkupBuildContext {
    var useUTC: Bool
    var renderMode: TooltipRenderMode
    // upstream `orderMode: TooltipOrderMode` (required) but `buildSection` guards `if (... && orderMode)`,
    //   so it can be falsy -> modeled Optional.
    var orderMode: TooltipOrderMode?
    var markupStyleCreator: TooltipMarkupStyleCreator
    var valueFormatter: TooltipValueFormatter?
}

/**
 * @return markupText. null/undefined means no content.
 */
public func buildTooltipMarkup(
    _ fragment: TooltipMarkupBlockFragment?,
    _ markupStyleCreator: TooltipMarkupStyleCreator,
    _ renderMode: TooltipRenderMode,
    _ orderMode: TooltipOrderMode?,
    _ useUTC: Bool,
    _ toolTipTextStyle: TooltipTextStyleOption
) -> MarkupText? {
    guard let fragment = fragment else {
        return nil
    }

    let builder = getBuilder(fragment)
    let ctx = TooltipMarkupBuildContext(
        useUTC: useUTC,
        renderMode: renderMode,
        orderMode: orderMode,
        markupStyleCreator: markupStyleCreator,
        valueFormatter: fragment.valueFormatter
    )
    return builder(ctx, fragment, 0, toolTipTextStyle)
}


func getGap(_ gapLevel: Int) -> (html: Double, richText: String) {
    // JS `HTML_GAPS[gapLevel]` returns `undefined` for out-of-range levels; the guarded
    //   Swift lookup returns 0 / "" instead (out-of-range gap levels are not reached in practice).
    //   Semantically equivalent — the guard clamps a JS `undefined` to the concrete Swift default.
    let html = (gapLevel >= 0 && gapLevel < HTML_GAPS.count) ? HTML_GAPS[gapLevel] : 0
    let richText = (gapLevel >= 0 && gapLevel < RICH_TEXT_GAPS.count) ? RICH_TEXT_GAPS[gapLevel] : ""
    return (html: html, richText: richText)
}

func wrapBlockHTML(
    _ textStyle: TooltipTextStyleOption,
    _ encodedContent: String,
    _ topGap: Double
) -> String {
    let clearfix = "<div style=\"clear:both\"></div>"
    let marginCSS = "margin: " + number.jsNumberString(topGap) + "px 0 0"
    let tooltipLineHeight = getTooltipLineHeight(textStyle)
    return "<div style=\"" + marginCSS + ";" + tooltipLineHeight + ";\">"
        + encodedContent + clearfix
        + "</div>"
}

func wrapInlineNameHTML(
    _ name: String,
    _ leftHasMarker: Bool,
    _ style: String
) -> String {
    let marginCss = leftHasMarker ? "margin-left:2px" : ""
    return "<span style=\"" + style + ";" + marginCss + "\">"
        + format.encodeHTML(name)
        + "</span>"
}

func wrapInlineValueHTML(
    _ valueList: Any,
    _ alignRight: Bool,
    _ valueCloseToMarker: Bool,
    _ style: String
) -> String {
    // Do not too close to marker, considering there are multiple values separated by spaces.
    let paddingStr = valueCloseToMarker ? "10px" : "20px"
    let alignCSS = alignRight ? "float:right;margin-left:" + paddingStr : ""
    let arr: [Any?] = util.isArray(valueList) ? (valueList as! [Any]) : [valueList]
    return (
        "<span style=\"" + alignCSS + ";" + style + "\">"
        // Value has commas inside, so use '  ' as delimiter for multiple values.
        + arr.map { value in format.encodeHTML((value as? String) ?? number.jsString(value)) }
            .joined(separator: "&nbsp;&nbsp;")
        + "</span>"
    )
}

func wrapInlineNameRichText(_ ctx: TooltipMarkupBuildContext, _ name: String, _ style: RichTextStyle) -> String {
    return ctx.markupStyleCreator.wrapRichTextStyle(name, style)
}

func wrapInlineValueRichText(
    _ ctx: TooltipMarkupBuildContext,
    _ values: Any,
    _ alignRight: Bool,
    _ valueCloseToMarker: Bool,
    _ style: RichTextStyle
) -> String {
    var styles: [RichTextStyle] = [style]
    let paddingLeft: Double = valueCloseToMarker ? 10 : 20
    if alignRight {
        styles.append(["padding": [0.0, 0.0, 0.0, paddingLeft], "align": "right"])
    }
    // Value has commas inside, so use '  ' as delimiter for multiple values.
    let text = util.isArray(values)
        ? (values as! [Any]).map { ($0 as? String) ?? number.jsString($0) }.joined(separator: "  ")
        : ((values as? String) ?? number.jsString(values))
    return ctx.markupStyleCreator.wrapRichTextStyle(text, styles)
}


public func retrieveVisualColorForTooltipMarker(
    _ series: SeriesModel,
    _ dataIndex: Int
) -> ColorString {
    let style = series.getData().getItemVisual(dataIndex, "style") as? [String: Any]
    let color = style?[series.visualDrawType]
    return convertToColorStringLoose(color)
}

// upstream calls `convertToColorString(color)` directly on the (statically-typed `ZRColor`) visual
// style color. Here the visual style bag is `[String: Any]`, so the color arrives as `Any?`; this
// coerces to `ZRColor` before delegating. A plain color string / gradient passes through; anything
// non-coercible (incl. nil) yields the `convertToColorString(undefined)` default ('transparent').
// The visual style bag may carry the color either as a String, an EChartsKit `ZRColor` (e.g. from
//   `getColorFromPalette` / an itemStyle color callback), or a `ZRenderKit.ZRColor` (a typed path
//   style `fill`/`stroke`); all three are handled so the marker dot keeps its color.
private func convertToColorStringLoose(_ v: Any?) -> ColorString {
    if let s = v as? String {
        return format.convertToColorString(.color(s))
    }
    if let z = v as? ZRColor {
        return format.convertToColorString(z)
    }
    // A visual style authored with a `ZRenderKit.ZRColor` (path style color). Mirror
    //   `format.convertToColorString` semantics: string passes through; gradient -> first stop
    //   color (else 'transparent'); pattern/object-without-colorStops -> 'transparent'.
    if let zr = v as? ZRenderKit.ZRColor {
        switch zr {
        case .string(let s):
            return format.convertToColorString(.color(s))
        case .linearGradient(let g):
            return g.colorStops.first.map { $0.color } ?? "transparent"
        case .radialGradient(let g):
            return g.colorStops.first.map { $0.color } ?? "transparent"
        case .pattern:
            return "transparent"
        }
    }
    return "transparent"
}

public func getPaddingFromTooltipModel(
    _ model: Model,
    _ renderMode: TooltipRenderMode
) -> Any {   // upstream: number | number[]
    let padding = model.get("padding")
    return (padding != nil && !(padding is NSNull))
        ? padding!
        // We give slightly different to look pretty.
        : (renderMode == .richText
            ? ([8.0, 10.0] as [Double]) as Any
            : (10.0 as Double) as Any)
}

/**
 * The major feature is generate styles for `renderMode: 'richText'`.
 * But it also serves `renderMode: 'html'` to provide
 * "renderMode-independent" API.
 */
public class TooltipMarkupStyleCreator {
    // upstream: `readonly richTextStyles: Dictionary<Dictionary<unknown>> = {};`
    public private(set) var richTextStyles: [String: [String: Any]] = [:]

    // Notice that "generate a style name" usually happens repeatedly when mouse is moving and
    // a tooltip is displayed. So we put the `_nextStyleNameId` as a member of each creator
    // rather than static shared by all creators (which will cause it increase to fast).
    private var _nextStyleNameId: Double = number.getRandomIdBase()

    public init() {}

    private func _generateStyleName() -> String {
        // upstream: `'__EC_aUTo_' + this._nextStyleNameId++` — post-increment: use, then bump.
        let name = "__EC_aUTo_" + number.jsNumberString(_nextStyleNameId)
        _nextStyleNameId += 1
        return name
    }

    public func makeTooltipMarker(
        _ markerType: format.TooltipMarkerType,
        _ colorStr: ColorString,
        _ renderMode: TooltipRenderMode
    ) -> String {
        let markerId = renderMode == .richText
            ? _generateStyleName()
            : nil
        let marker = format.getTooltipMarker(format.GetTooltipMarkerOpt(
            color: colorStr,
            type: markerType,
            renderMode: renderMode,
            markerId: markerId
        ))
        switch marker {
        case .string(let s):
            return s
        case .rich(let richMarker):
            if __DEV__ {
                assert(markerId != nil)
            }
            richTextStyles[markerId!] = richMarker.style
            return richMarker.content
        }
    }

    /**
     * The styles will be auto merged.
     *
     * upstream single method takes `Dictionary<unknown> | Dictionary<unknown>[]`; modeled as two
     * overloads (single style bag / array of style bags).
     */
    public func wrapRichTextStyle(_ text: String, _ styles: RichTextStyle) -> String {
        var finalStl: [String: Any] = [:]
        for (k, v) in styles { finalStl[k] = v }
        let styleName = _generateStyleName()
        richTextStyles[styleName] = finalStl
        return "{" + styleName + "|" + text + "}"
    }
    public func wrapRichTextStyle(_ text: String, _ styles: [RichTextStyle]) -> String {
        var finalStl: [String: Any] = [:]
        for stl in styles {
            for (k, v) in stl { finalStl[k] = v }
        }
        let styleName = _generateStyleName()
        richTextStyles[styleName] = finalStl
        return "{" + styleName + "|" + text + "}"
    }
}

// JS truthiness helper (`textStyle.color || default`, `fragment.markerColor || default`).
//   Reproduces `Boolean(x)` for the value kinds reachable here (string / number / bool / null).
private func jsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
