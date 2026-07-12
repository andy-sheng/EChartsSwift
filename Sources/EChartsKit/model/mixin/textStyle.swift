// Ported from echarts/src/model/mixin/textStyle.ts — keep in sync with upstream

import Foundation
import ZRenderKit
// import * as graphicUtil from '../../util/graphic';                   -> graphicUtil.BoundingRect == ZRenderKit.BoundingRect
// import {getFont} from '../../label/labelStyle';                      -> labelStyle.getFont (ported, label/labelStyle.swift; reproduced inline here — see note below)
// import Model from '../Model';                                        -> Model            (sibling model/Model.swift: ref type with `getShallow`/`get`/`getModel`/`ecModel`)
// import { LabelOption, ColorString } from '../../util/types';         -> LabelOption / ColorString (EChartsKit util/types.swift)
// import ZRText, {TextStyleProps} from 'zrender/src/graphic/Text';     -> ZRenderKit.ZRText / TextStyleProps

// const PATH_COLOR = ['textStyle', 'color'] as const;
private let PATH_COLOR: [String] = ["textStyle", "color"]

// export type LabelFontOption = Pick<LabelOption, 'fontStyle' | 'fontWeight' | 'fontSize' | 'fontFamily'>;
// type LabelRectRelatedOption = Pick<LabelOption,
//     'align' | 'verticalAlign' | 'padding' | 'lineHeight' | 'baseline' | 'rich'
//     | 'width' | 'height' | 'overflow'
// > & LabelFontOption;
// PORT-NOTE: these TS `Pick<...>` types only narrow the generic `Model<Opt>` type parameter, which
//   we drop (the Swift `Model` is non-generic). They have no faithful Swift analogue; the per-key set
//   they describe is the `textStyleParams` list below and the explicit getShallow reads in getFont().

// const textStyleParams = [
//     'fontStyle', 'fontWeight', 'fontSize', 'fontFamily', 'padding',
//     'lineHeight', 'rich', 'width', 'height', 'overflow'
// ] as const;
private let textStyleParams: [String] = [
    "fontStyle", "fontWeight", "fontSize", "fontFamily", "padding",
    "lineHeight", "rich", "width", "height", "overflow"
]

// TODO Performance improvement?
// const tmpText = new ZRText();
//   Module-level shared, mutable ZRText scratch instance (final class — reference semantics, faithful).
private let tmpText = ZRText()

// upstream: `class TextStyleMixin { ... getTextColor/getFont/getTextRect(this: Model, ...) }`, mixed
//   into Model via `mixin(Model, TextStyleMixin)`. Per CONVENTIONS §2, ported as a protocol that
//   preserves the upstream class name + a constrained extension; Model conforms to `TextStyleMixin`,
//   and each method sees `self` typed as Model via the `where Self: Model` constraint (mirroring the
//   upstream `this: Model` binding). Matches the sibling itemStyle.swift convention.
public protocol TextStyleMixin {}

extension TextStyleMixin where Self: Model {

    /**
     * Get color property or get color from option.textStyle.color
     */
    // TODO Callback
    public func getTextColor(_ isEmphasis: Bool? = nil) -> ColorString? {
        let ecModel = self.ecModel
        // upstream: return this.getShallow('color')
        //     || ((!isEmphasis && ecModel) ? ecModel.get(PATH_COLOR) : null);
        //   `||` returns the first truthy operand; an empty string is falsy in JS, so we reproduce that.
        if let color = self.getShallow("color") as? ColorString, !color.isEmpty {
            return color
        }
        if !(isEmphasis ?? false), let ecModel = ecModel {
            // PORT-NOTE: GlobalModel.get(path) conventional signature — PATH_COLOR is the ['textStyle','color'] path.
            return ecModel.get(PATH_COLOR) as? ColorString
        }
        return nil
    }

    /**
     * Create font string from fontStyle, fontWeight, fontSize, fontFamily
     * @return {string}
     */
    public func getFont() -> String {
        // upstream:
        //   return getFont({
        //       fontStyle: this.getShallow('fontStyle'),
        //       fontWeight: this.getShallow('fontWeight'),
        //       fontSize: this.getShallow('fontSize'),
        //       fontFamily: this.getShallow('fontFamily')
        //   }, this.ecModel);
        // PORT-NOTE: `getFont` is now ported in label/labelStyle.swift (labelStyle.getFont). Its body
        //   is also reproduced inline in `_labelStyleGetFont` below (kept from when this file predated
        //   label/labelStyle.swift); this could call `labelStyle.getFont(opt, self.ecModel)` directly.
        return _labelStyleGetFont(
            fontStyle: self.getShallow("fontStyle"),
            fontWeight: self.getShallow("fontWeight"),
            fontSize: self.getShallow("fontSize"),
            fontFamily: self.getShallow("fontFamily"),
            self.ecModel
        )
    }

    public func getTextRect(_ text: String) -> BoundingRect {
        // const style: TextStyleProps = {
        //     text: text,
        //     verticalAlign: this.getShallow('verticalAlign') || this.getShallow('baseline')
        // };
        var style = TextStyleProps()
        style.text = text
        style.verticalAlign = _coerceVerticalAlign(self.getShallow("verticalAlign"))
            ?? _coerceVerticalAlign(self.getShallow("baseline"))
        // upstream:
        //   for (let i = 0; i < textStyleParams.length; i++) {
        //       (style as any)[textStyleParams[i]] = this.getShallow(textStyleParams[i]);
        //   }
        // PORT-NOTE: upstream sets the style fields by dynamic string key (`(style as any)[k] = ...`).
        //   `TextStyleProps` is a fixed-field Swift struct, so the per-key loop is unrolled below into
        //   explicit, type-coerced assignments (the dynamic option bag stores raw String/Double/[Double];
        //   each is coerced into the typed field). Order matches `textStyleParams`.
        _ = textStyleParams
        style.fontStyle = _coerceFontStyle(self.getShallow("fontStyle"))
        style.fontWeight = _coerceFontWeight(self.getShallow("fontWeight"))
        style.fontSize = _coerceNumberOrString(self.getShallow("fontSize"))
        style.fontFamily = self.getShallow("fontFamily") as? String
        style.padding = _coerceNumberOrNumberArray(self.getShallow("padding"))
        style.lineHeight = self.getShallow("lineHeight") as? Double
        // PORT-NOTE: `rich` is a nested option object (`{ [name]: TextStylePropsPart }`); coercing the
        //   dynamic [String: Any] bag into typed `[String: TextStylePropsPart]` is non-mechanical, so it
        //   is passed through only if already typed.
        style.rich = self.getShallow("rich") as? [String: TextStylePropsPart]
        style.width = self.getShallow("width") as? Double
        style.height = self.getShallow("height") as? Double
        style.overflow = self.getShallow("overflow") as? String
        tmpText.useStyle(style)
        tmpText.update()
        // POTENTIAL-BUG: ZRText.getBoundingRect() returns BoundingRect? in the Swift port; after update()
        //   it is EXPECTED to be populated, so force-unwrap to match upstream's non-optional return.
        //   Force-unwrap mirroring upstream optimistic typing is a latent SIGTRAP if update() ever
        //   leaves the bounding rect nil.
        return tmpText.getBoundingRect()!
    }
}

// export default TextStyleMixin;

// ============================================================================
// PORT-NOTE: inline reproduction of `getFont` from '../../label/labelStyle'.
//   Mirrors labelStyle.getFont faithfully; label/labelStyle.swift is now ported, so this could be
//   deleted in favor of calling it directly.
//
//   upstream:
//     export function getFont(opt, ecModel) {
//         const gTextStyleModel = ecModel && ecModel.getModel('textStyle');
//         return trim([
//             opt.fontStyle || gTextStyleModel && gTextStyleModel.getShallow('fontStyle') || '',
//             opt.fontWeight || gTextStyleModel && gTextStyleModel.getShallow('fontWeight') || '',
//             (opt.fontSize || gTextStyleModel && gTextStyleModel.getShallow('fontSize') || 12) + 'px',
//             opt.fontFamily || gTextStyleModel && gTextStyleModel.getShallow('fontFamily') || 'sans-serif'
//         ].join(' '));
//     }
// ============================================================================
private func _labelStyleGetFont(
    fontStyle: Any?,
    fontWeight: Any?,
    fontSize: Any?,
    fontFamily: Any?,
    _ ecModel: GlobalModel?
) -> String {
    // PORT-NOTE: GlobalModel.getModel(path) conventional signature, returns a Model (or nil when ecModel nil).
    let gTextStyleModel: Model? = ecModel?.getModel("textStyle")
    // FIXME in node-canvas fontWeight is before fontStyle
    let parts = [
        _jsTruthyString(fontStyle, gTextStyleModel?.getShallow("fontStyle"), ""),
        _jsTruthyString(fontWeight, gTextStyleModel?.getShallow("fontWeight"), ""),
        _jsNumberToString(_jsTruthyNumber(fontSize, gTextStyleModel?.getShallow("fontSize"), 12)) + "px",
        _jsTruthyString(fontFamily, gTextStyleModel?.getShallow("fontFamily"), "sans-serif")
    ]
    // trim([...].join(' '))
    return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
}

// JS `a || b || fallback` over string-ish slots: nil/undefined/'' are falsy. A number coerces to its
// JS string form (upstream fontWeight may be a number).
private func _jsTruthyString(_ a: Any?, _ b: Any?, _ fallback: String) -> String {
    if let s = _jsStringOrNil(a) { return s }
    if let s = _jsStringOrNil(b) { return s }
    return fallback
}

private func _jsStringOrNil(_ v: Any?) -> String? {
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? Double { return n == 0 || n.isNaN ? nil : _jsNumberToString(n) }
    return nil
}

// JS `a || b || fallback` over the numeric fontSize slot: 0/NaN/nil are falsy.
private func _jsTruthyNumber(_ a: Any?, _ b: Any?, _ fallback: Double) -> Double {
    if let n = _jsNumberOrNil(a) { return n }
    if let n = _jsNumberOrNil(b) { return n }
    return fallback
}

private func _jsNumberOrNil(_ v: Any?) -> Double? {
    if let n = v as? Double { return n == 0 || n.isNaN ? nil : n }
    return nil
}

// JS `Number -> string`: integral values print without a decimal point (12 -> "12"), else as-is.
private func _jsNumberToString(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
    return String(n)
}

// ============================================================================
// PORT-NOTE: dynamic-option (`getShallow` -> Any?) → typed-TextStyleProps-field coercions.
//   The option tree stores raw primitives (String/Double/[Double]); ZRText.useStyle needs the typed
//   `TextStyleProps`. Upstream copies values untyped via the string-key loop. Each coercion accepts an
//   already-typed value first, then falls back to coercing the raw primitive. Best-effort.
// ============================================================================
private func _coerceFontStyle(_ v: Any?) -> FontStyle? {
    if let f = v as? FontStyle { return f }
    if let s = v as? String { return FontStyle(rawValue: s) }
    return nil
}

private func _coerceFontWeight(_ v: Any?) -> FontWeight? {
    if let f = v as? FontWeight { return f }
    if let n = v as? Double { return .number(n) }
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

private func _coerceNumberOrString(_ v: Any?) -> NumberOrString? {
    if let x = v as? NumberOrString { return x }
    if let n = v as? Double { return .number(n) }
    if let s = v as? String { return .string(s) }
    return nil
}

private func _coerceNumberOrNumberArray(_ v: Any?) -> NumberOrNumberArray? {
    if let x = v as? NumberOrNumberArray { return x }
    if let n = v as? Double { return .number(n) }
    if let a = v as? [Double] { return .array(a) }
    return nil
}

private func _coerceVerticalAlign(_ v: Any?) -> TextVerticalAlign? {
    if let x = v as? TextVerticalAlign { return x }
    if let s = v as? String { return TextVerticalAlign(rawValue: s) }
    return nil
}
