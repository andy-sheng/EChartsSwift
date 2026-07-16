// Ported from echarts/src/model/mixin/dataFormat.ts — keep in sync with upstream

import Foundation
import ZRenderKit
// import * as zrUtil from 'zrender/src/core/util';                 -> util (ZRenderKit)
// import {retrieveRawValue} from '../../data/helper/dataProvider'; -> retrieveRawValue (EChartsKit, same module)
// import {formatTpl} from '../../util/format';                     -> format.formatTpl (EChartsKit)
// import { ... } from '../../util/types';                          -> EChartsKit (same module)
// import GlobalModel from '../Global';                             -> GlobalModel (sibling model/Global.swift)
// import { TooltipMarkupBlockFragment } from '../../component/tooltip/tooltipMarkup';
//                                                                  -> PORT-NOTE (see typealias below)
// import { error, makePrintable } from '../../util/log';           -> log.error / log.makePrintable (EChartsKit)

// const DIMENSION_LABEL_REG = /\{@(.+?)\}/g;
private let DIMENSION_LABEL_REG = try! NSRegularExpression(pattern: "\\{@(.+?)\\}")

// `TooltipMarkupBlockFragment` is now the real ported type — see
//   component/tooltip/tooltipMarkup.swift (base class `TooltipMarkupBlock`, discriminated by `.type`).
//   `normalizeTooltipFormatResult` below reads that `.type` via an `as?` downcast to the class.

// PORT-NOTE: upstream uses an inline anonymous object type
//   `{ interpolatedValue: InterpolatableValue }` for `getFormattedLabel`'s `extendParams`.
//   Modeled as a value struct per CONVENTIONS §4 (inline object literal -> struct).
public struct GetFormattedLabelExtendParams {
    public var interpolatedValue: InterpolatableValue
    public init(interpolatedValue: InterpolatableValue) {
        self.interpolatedValue = interpolatedValue
    }
}

// upstream: `export interface DataFormatMixin extends DataHost { ... }`
//   The TS `DataFormatMixin` is a mixin: a `class` whose methods are grafted onto
//   `ComponentModel`/`SeriesModel` via `zrUtil.mixin(...)`, with a companion `interface`
//   that declares the host-supplied properties the methods assume.
//
// PORT (mixin → protocol + protocol-extension, per CONVENTIONS §2):
//   - the `interface` arm (host-supplied state) becomes the protocol *requirements* below;
//   - the `class` arm (the four methods) becomes the protocol *extension* (default
//     implementations). A conforming `ComponentModel`/`SeriesModel` inherits the method set
//     exactly as `zrUtil.mixin` would graft it. `extends DataHost` -> protocol refinement.
public protocol DataFormatMixin: DataHost, AnyObject {
    // PORT: upstream declares `ecModel: GlobalModel` (non-optional). `Model.ecModel` is `GlobalModel?`
    //   (the Model port chose optional), and a subclass cannot re-type an inherited stored property, so
    //   the requirement is relaxed to `GlobalModel?` to let `SeriesModel` (and `ComponentModel`) conform.
    //   Neither extension method below reads `ecModel`, so the optionality is inert here.
    var ecModel: GlobalModel? { get }
    var mainType: ComponentMainType { get }
    var subType: ComponentSubType { get }
    var componentIndex: Double { get }
    var id: String { get }
    var name: String { get }
    var animatedValue: [OptionDataValue] { get }
}

extension DataFormatMixin {

    // PORT: upstream `animatedValue` is host-supplied state (only read by the animation/universal-transition
    //   path, which is deferred). Default to `[]` so a conforming model need not store it until that lands.
    public var animatedValue: [OptionDataValue] { return [] }

    // upstream accesses `(this as any).seriesIndex` in `getDataParams`. `seriesIndex` is only
    // defined on `SeriesModel`, not on the `DataFormatMixin` contract, so upstream reaches it
    // dynamically — modeled below as a `(self as? SeriesModel)` read at the use site.
    //   (Was a protocol-extension `var seriesIndex: Double? { nil }` — the classic protocol-witness
    //   trap: on a `SeriesModel`-typed OPTIONAL CHAIN, overload resolution preferred this nil-returning
    //   `Double?` member over the class's stored `Double`, so
    //   `(hostModel as? SeriesModel)?.seriesIndex` silently read nil → ECData.seriesIndex stamped 0
    //   for EVERY series and the focus/blur fan-out targeted series 0. Do not reintroduce a same-name
    //   optional member on a protocol extension.)

    /**
     * Get params for formatter
     */
    public func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil
    ) -> CallbackDataParams {

        let data = self.getData(dataType)
        let rawValue = self.getRawValue(dataIndex, dataType)
        let rawDataIndex = data.getRawIndex(Int(dataIndex))
        let name = data.getName(Int(dataIndex))
        let itemOpt = data.getRawDataItem(Int(dataIndex))
        let style = data.getItemVisual(Int(dataIndex), "style")
        // PORT-NOTE: the visual `style` bag is modeled as a dynamic `[String: Any]`.
        let styleDict = style as? [String: Any]
        // upstream: style && style[data.getItemVisual(dataIndex, 'drawType') || 'fill'] as ZRColor
        // The visual bag may store either a typed `ZRColor` (palette path, getColorFromPalette) OR a
        //   raw `ColorString` (an explicit `itemStyle.color: 'red'` kept un-wrapped in visual/style.swift).
        //   Accept both so an explicitly-colored series does not surface `color == nil`.
        let colorRaw = styleDict?[(data.getItemVisual(Int(dataIndex), "drawType") as? String) ?? "fill"]
        let color: ZRColor? = (colorRaw as? ZRColor) ?? (colorRaw as? ColorString).map { ZRColor.color($0) }
        // upstream: style && style.stroke as ColorString
        let borderColor = styleDict?["stroke"] as? ColorString
        let mainType = self.mainType
        let isSeries = mainType == "series"
        let userOutput = data.userOutput != nil ? data.userOutput.get() : nil

        return CallbackDataParams(
            componentType: mainType,
            componentSubType: self.subType,
            componentIndex: self.componentIndex,
            seriesType: isSeries ? self.subType : nil,
            seriesIndex: (self as? SeriesModel)?.seriesIndex,   // upstream `(this as any).seriesIndex`
            seriesId: isSeries ? self.id : nil,
            seriesName: isSeries ? self.name : nil,
            name: name,
            dataIndex: Double(rawDataIndex),
            data: itemOpt,
            dataType: dataType,
            value: rawValue as Any,
            color: color,
            borderColor: borderColor,
            // PORT-NOTE: `DimensionUserOuput.get().fullDimensions` is `[DimensionName?]` (the
            //   name may be absent), but `CallbackDataParams.dimensionNames` is `[DimensionName]?`
            //   (non-optional element). The absent names are coerced to `""`; element optionality
            //   is lost relative to upstream (semantically near-equivalent — an absent dim name has
            //   no meaningful use as a callback param key).
            dimensionNames: userOutput != nil ? userOutput!.fullDimensions.map { $0 ?? "" } : nil,
            encode: userOutput?.encode,

            marker: nil,
            status: nil,
            dimensionIndex: nil,
            percent: nil,

            // Param name list for mapping `a`, `b`, `c`, `d`, `e`
            vars: ["seriesName", "name", "value"]   // upstream: `$vars`
        )
    }

    /**
     * Format label
     * @param dataIndex
     * @param status 'normal' by default
     * @param dataType
     * @param labelDimIndex Only used in some chart that
     *        use formatter in different dimensions, like radar.
     * @param formatter Formatter given outside.
     * @return return null/undefined if no formatter
     */
    public func getFormattedLabel(
        _ dataIndex: Double,
        _ status: DisplayState? = nil,
        _ dataType: SeriesDataType? = nil,
        _ labelDimIndex: Double? = nil,
        // upstream: string | ((params: object) => string)
        _ formatter: Any? = nil,
        _ extendParams: GetFormattedLabelExtendParams? = nil
    ) -> String? {
        let status = status ?? .normal
        let data = self.getData(dataType)

        // upstream: `this.getDataParams(dataIndex, dataType)` — a virtual call that reaches the series'
        //   override (pie/funnel add `percent`, sankey/chord fill node name/value). In Swift the
        //   protocol-extension `self.getDataParams` is statically dispatched and would MISS those
        //   overrides, so route through the `SeriesModel` class method (an overridable witness) when
        //   `self` is a series; other `DataFormatMixin` conformers fall back to the extension default.
        var params: CallbackDataParams
        if let seriesSelf = self as? SeriesModel {
            params = seriesSelf.getDataParams(dataIndex, dataType)
        }
        else {
            params = self.getDataParams(dataIndex, dataType)
        }

        if let extendParams = extendParams {
            params.value = extendParams.interpolatedValue
        }

        if labelDimIndex != nil && util.isArray(params.value) {
            params.value = (params.value as! [Any])[Int(labelDimIndex!)]
        }

        var formatter = formatter
        // upstream: if (!formatter)  (JS-falsy: nil/undefined or empty string)
        if formatter == nil || (formatter as? String) == "" {
            let itemModel = data.getItemModel(Int(dataIndex))
            // @ts-ignore
            formatter = itemModel.get(status == .normal
                ? ["label", "formatter"]
                : [status.rawValue, "label", "formatter"]
            )
        }

        // upstream: zrUtil.isFunction(formatter)
        // PORT-NOTE: `util.isFunction` is unreliable for Swift closures (no introspectable
        //   metadata); resolve "is callable" statically via a cast to the formatter signature.
        if let formatterFn = formatter as? (CallbackDataParams) -> String {
            params.status = status
            params.dimensionIndex = labelDimIndex
            return formatterFn(params)
        }
        else if util.isString(formatter) {
            let str = format.formatTpl(formatter as! String, callbackDataParamsToTplParam(params))

            // Support 'aaa{@[3]}bbb{@product}ccc'.
            // Do not support '}' in dim name util have to.
            return replaceDimensionLabelReg(str) { dimStr in
                let len = dimStr.count

                var dimLoose: DimensionLoose = dimStr
                if dimStr.first == "[" && dimStr.last == "]" {
                    // upstream: dimLoose = +dimLoose.slice(1, len - 1); // Also support: '[]' => 0
                    let sliced = String(Array(dimStr)[1..<(len - 1)])
                    // PORT-NOTE: replicate JS `+s`: `''` => 0, numeric => value, else => NaN.
                    let dimNum: Double = sliced.isEmpty ? 0 : (Double(sliced) ?? Double.nan)
                    dimLoose = dimNum
                    if __DEV__ {
                        if dimNum.isNaN {
                            log.error("Invalide label formatter: @\(dimStr), only support @[0], @[1], @[2], ...")
                        }
                    }
                }

                var val = retrieveRawValue(data, dataIndex, dimLoose) as OptionDataValue

                if let extendParams = extendParams, util.isArray(extendParams.interpolatedValue) {
                    let dimIndex = data.getDimensionIndex(dimLoose)
                    if dimIndex >= 0 {
                        val = (extendParams.interpolatedValue as! [Any])[Int(dimIndex)]
                    }
                }

                // upstream: return val != null ? val + '' : '';
                // `format._str` reproduces JS `val + ''` (number.jsNumberString: `3` -> "3", not the
                //   "3.0" a bare Swift interpolation would produce).
                return val != nil ? format._str(val) : ""
            }
        }
        return nil
    }

    /**
     * Get raw value in option
     */
    public func getRawValue(
        _ idx: Double,
        _ dataType: SeriesDataType? = nil
    ) -> Any? {   // upstream: unknown
        return retrieveRawValue(self.getData(dataType), idx)
    }

    /**
     * Should be implemented.
     * @param {number} dataIndex
     * @param {boolean} [multipleSeries=false]
     * @param {string} [dataType]
     */
    public func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: String? = nil
    ) -> TooltipFormatResult? {
        // Empty function
        return nil
    }
}

// PORT-NOTE: `getFormattedLabel`'s string branch passes the `CallbackDataParams` *object* to
//   `formatTpl`, which dynamically reads keys named by `$vars`. `format.formatTpl` consumes a
//   dynamic `[String: Any]` bag, so the typed struct is bridged to a dict carrying exactly the
//   `$vars`-referenced keys (plus `$vars` itself). This mirrors upstream's dynamic access.
private func callbackDataParamsToTplParam(_ params: CallbackDataParams) -> [String: Any] {
    var tplParam: [String: Any] = [:]
    tplParam["$vars"] = params.vars
    tplParam["seriesName"] = params.seriesName
    tplParam["name"] = params.name
    tplParam["value"] = params.value
    // Pie/funnel push 'percent' onto `$vars` (the `{d}` alias); carry the computed value so `formatTpl`
    //   can substitute it. Upstream reads it off the dynamic params object; the typed struct exposes it
    //   as `percent`, mapped back under its `$vars` key here.
    if let percent = params.percent {
        tplParam["percent"] = percent
    }
    return tplParam
}

// upstream: `str.replace(DIMENSION_LABEL_REG, function (origin, dimStr) { ... })`.
//   Replicates JS `String.prototype.replace(regexp, fn)`: each `{@<dimStr>}` match is replaced
//   by `replacer(<dimStr>)`, where `<dimStr>` is capture group 1.
private func replaceDimensionLabelReg(_ str: String, _ replacer: (String) -> String) -> String {
    let ns = str as NSString
    let matches = DIMENSION_LABEL_REG.matches(in: str, range: NSRange(location: 0, length: ns.length))
    var result = ""
    var last = 0
    for m in matches {
        result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
        let dimStr = ns.substring(with: m.range(at: 1))
        result += replacer(dimStr)
        last = m.range.location + m.range.length
    }
    result += ns.substring(from: last)
    return result
}

// upstream:
//   type TooltipFormatResult =
//       // If `string`, means `TooltipFormatResultLegacyObject['html']`
//       string
//       // | TooltipFormatResultLegacyObject
//       | TooltipMarkupBlockFragment;
// PORT-NOTE: `string | TooltipMarkupBlockFragment` union modeled as `Any` (dynamic option bag).
public typealias TooltipFormatResult = Any

// PENDING: previously we accept this type when calling `formatTooltip`,
// but guess little chance has been used outside. Do we need to backward
// compat it?
// type TooltipFormatResultLegacyObject = {
//     // `html` means the markup language text, either in 'html' or 'richText'.
//     // The name `html` is not appropriate because in 'richText' it is not a HTML
//     // string. But still support it for backward compatibility.
//     html: string;
//     markers: Dictionary<ColorString>;
// };

/**
 * For backward compat, normalize the return from `formatTooltip`.
 */
public func normalizeTooltipFormatResult(_ result: TooltipFormatResult?) -> (
    // If `markupFragment` exists, `markupText` should be ignored.
    frag: TooltipMarkupBlockFragment?,
    // Can be `null`/`undefined`, means no tooltip.
    text: String?
    // Merged with `markersExisting`.
    // markers: Dictionary<ColorString>;
) {
    var markupText: String?
    // let markers: Dictionary<ColorString>;
    var markupFragment: TooltipMarkupBlockFragment?
    if util.isObject(result) {
        // upstream: if ((result as TooltipMarkupBlockFragment).type)
        //   The ported fragment is a `TooltipMarkupBlock` (always carries `.type`).
        if let frag = result as? TooltipMarkupBlockFragment {
            markupFragment = frag
        }
        else {
            if __DEV__ {
                // upstream: console.warn(...)
                log.warn("The return type of `formatTooltip` is not supported: " + log.makePrintable(result))
            }
        }
        // else {
        //     markupText = (result as TooltipFormatResultLegacyObject).html;
        //     markers = (result as TooltipFormatResultLegacyObject).markers;
        //     if (markersExisting) {
        //         markers = zrUtil.merge(markersExisting, markers);
        //     }
        // }
    }
    else {
        markupText = result as? String
    }

    return (
        // markers: markers || markersExisting,
        frag: markupFragment,
        text: markupText
    )
}
