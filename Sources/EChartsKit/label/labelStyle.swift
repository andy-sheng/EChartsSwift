// Ported from echarts/src/label/labelStyle.ts — keep in sync with upstream
//
// SHARED LABEL CORE. This is the foundational module every chart's label rendering routes through
// (`setLabelStyle` creates/updates the ZRText attached to a data element; `getLabelStatesModels`
// reads the normal/emphasis/blur/select `label` sub-models off an item model). Downstream chart
// views (Pie/Bar/Line/... — see the `labelStyle.`-referencing PORT-TODO comments already scattered
// across `chart/*/*.swift`) are expected to retrofit onto this API in a later phase; this phase only
// builds and tests the core in isolation.
//
// upstream imports (resolved to the ported modules):
//   import ZRText, { TextProps, TextStyleProps } from 'zrender/src/graphic/Text';   -> ZRenderKit.ZRText / TextStyleProps
//   import { Dictionary } from 'zrender/src/core/types';                            -> [String: T]
//   import Element, { ElementTextConfig } from 'zrender/src/Element';               -> ZRenderKit.Element / ElementTextConfig
//   import Model from '../model/Model';                                             -> EChartsKit.Model
//   import { LabelOption, DisplayState, ... } from '../util/types';                 -> util/types.swift
//   import GlobalModel from '../model/Global';                                      -> EChartsKit.GlobalModel
//   import { isFunction, retrieve2, extend, keys, trim, retrieve3, isNumber,
//     normalizeCssArray } from 'zrender/src/core/util';                             -> ZRenderKit.util
//   import { SPECIAL_STATES, DISPLAY_STATES } from '../util/states';                -> EChartsKit.states
//   import { deprecateReplaceLog } from '../util/log';                              -> EChartsKit.log
//   import { makeInner, interpolateRawValues } from '../util/model';                -> EChartsKit.model
//   import SeriesData from '../data/SeriesData';                                    -> EChartsKit.SeriesData
//   import { initProps, updateProps } from '../util/graphic';                       -> EChartsKit.graphic (DEFERRED path only)
//
// PORT (module -> namespace, CONVENTIONS §2): the whole file is a free-function module upstream, so —
//   exactly like `states`/`model`/`layout` — it becomes a caseless `public enum labelStyle` namespace;
//   call sites read `labelStyle.setLabelStyle(...)`, `labelStyle.getLabelStatesModels(...)`, etc.
//
// PORT (generics dropped, CONVENTIONS §2): upstream's `SetLabelStyleOpt<TLabelDataIndex>` /
//   `getLabelStatesModels<LabelName>` generics are dropped because the Swift codebase already
//   committed to concrete types at the seam this file plugs into:
//     - `DataFormatMixin.getFormattedLabel` (model/mixin/dataFormat.swift:137) already takes a
//       concrete `Double` `dataIndex` (not the TS union `number | string` used by MapDraw's region
//       names) — so `SetLabelStyleOpt.labelDataIndex` is modeled as `Double?` here, not generic.
//     - `getLabelStatesModels`'s `LabelName` generic (default `'label'`) narrows nothing at the
//       Swift call site (Model is untyped `ModelOption`), so it collapses to a plain `String`
//       parameter defaulting to `"label"`.
//
// GAP (documented, see the final report): `label.style.__marginType` (upstream `LabelExtendedTextStyle`,
//   L825-830) has no home on the ported `TextStyleProps` struct (ZRenderKit/Graphic/Text.swift) —
//   the margin VALUE is computed faithfully (`minMargin` takes precedence over `textMargin`), but the
//   tag distinguishing which one produced it is not stored. See the two PORT-TODOs in
//   `setTextStyleCommon` below.
//
// PORTED (L1a follow-up): `setLabelValueAnimation` (L739) and `animateLabelValue` (L763) — the
//   "number roll-up" label value animation — are now implemented below (near `labelInner`). They use
//   the ported `initProps`/`updateProps` (animation/basicTransition.swift) + `model.interpolateRawValues`
//   (util/modelUtil.swift). `labelInner`'s store carries the fields they need (`prevValue`/`value`/
//   `interpolatedValue`/`valueAnimation`/`precision`/`statesModels`/`defaultInterpolatedText`).
//   See the two functions' PORT-NOTEs for the synthetic-`percent` prop handling and the STATIC-oracle
//   deviation (settles to the final value; the live host renders intermediate frames).

import Foundation
import ZRenderKit

// upstream: `type TextCommonParams = { disableBox?, inheritColor?, defaultOpacity?,
//   defaultOutsidePosition?, textStyle?, defaultTextMargin?, autoOverflowArea?, layoutRect? }`
//   (labelStyle.ts:50-78). `textStyle` (a raw `ZRStyleProps` bag) and `defaultTextMargin` are declared
//   upstream but never READ anywhere in labelStyle.ts itself (they exist for OTHER callers of this
//   shared type, e.g. axisLabel.ts) — kept here for structural fidelity, inert in this file.
public struct TextCommonParams {
    public var disableBox: Bool?
    /// Specify a color when color is 'inherit'. If inheritColor specified, it is used as default textFill.
    public var inheritColor: ColorString?
    public var defaultOpacity: Double?
    /// upstream `LabelOption['position']` — a `BuiltinTextPosition` string or a `[number|string; 2]`
    ///   array; kept dynamic (`Any?`) like `ElementTextConfig.position`.
    public var defaultOutsidePosition: Any?
    /// upstream `ZRStyleProps` — unused within labelStyle.ts (see file header note).
    public var textStyle: [String: Any]?
    /// upstream `number | number[]` — unused within labelStyle.ts (see file header note).
    public var defaultTextMargin: Any?
    public var autoOverflowArea: Bool?
    public var layoutRect: RectLike?

    public init(
        disableBox: Bool? = nil,
        inheritColor: ColorString? = nil,
        defaultOpacity: Double? = nil,
        defaultOutsidePosition: Any? = nil,
        textStyle: [String: Any]? = nil,
        defaultTextMargin: Any? = nil,
        autoOverflowArea: Bool? = nil,
        layoutRect: RectLike? = nil
    ) {
        self.disableBox = disableBox
        self.inheritColor = inheritColor
        self.defaultOpacity = defaultOpacity
        self.defaultOutsidePosition = defaultOutsidePosition
        self.textStyle = textStyle
        self.defaultTextMargin = defaultTextMargin
        self.autoOverflowArea = autoOverflowArea
        self.layoutRect = layoutRect
    }
}

// upstream: `interface SetLabelStyleOpt<TLabelDataIndex> extends TextCommonParams { defaultText?,
//   labelFetcher?, labelDataIndex?, labelDimIndex?, enableTextSetter? }` (labelStyle.ts:81-113).
// PORT: `extends TextCommonParams` becomes flat field composition (Swift structs don't inherit);
//   `textCommonParams` below packages the shared subset back up for `createTextStyle`/
//   `createTextConfig`/`setTextStyleCommon`, mirroring the TS upcast at each call site.
public struct SetLabelStyleOpt {
    // ---- TextCommonParams fields ----
    public var disableBox: Bool?
    public var inheritColor: ColorString?
    public var defaultOpacity: Double?
    public var defaultOutsidePosition: Any?
    public var textStyle: [String: Any]?
    public var defaultTextMargin: Any?
    public var autoOverflowArea: Bool?
    public var layoutRect: RectLike?

    // ---- SetLabelStyleOpt-own fields ----
    /// upstream `string | ((labelDataIndex, opt, interpolatedValue?) => string)`. Modeled as `Any?`
    ///   (matching the `formatter` param convention already used by
    ///   `DataFormatMixin.getFormattedLabel`): cast to `String` or to `DefaultTextFn` at the call site.
    public var defaultText: Any?
    /// upstream `{ getFormattedLabel(...): string }` — a one-method object type. `DataFormatMixin`
    ///   (model/mixin/dataFormat.swift:41, `AnyObject`-bound) already declares exactly this method
    ///   with a matching signature, so it is reused directly as the existential type instead of
    ///   inventing a parallel protocol.
    public var labelFetcher: DataFormatMixin?
    public var labelDataIndex: Double?
    public var labelDimIndex: Double?
    /// Inject a setter of text for the text animation case. (Consumed only by the DEFERRED
    ///   value-animation path — see file header — but still threaded through so a caller can set it
    ///   without a compile error; `setLabelStyle` stores the closure on `labelInner` either way.)
    public var enableTextSetter: Bool?

    public init(
        disableBox: Bool? = nil,
        inheritColor: ColorString? = nil,
        defaultOpacity: Double? = nil,
        defaultOutsidePosition: Any? = nil,
        textStyle: [String: Any]? = nil,
        defaultTextMargin: Any? = nil,
        autoOverflowArea: Bool? = nil,
        layoutRect: RectLike? = nil,
        defaultText: Any? = nil,
        labelFetcher: DataFormatMixin? = nil,
        labelDataIndex: Double? = nil,
        labelDimIndex: Double? = nil,
        enableTextSetter: Bool? = nil
    ) {
        self.disableBox = disableBox
        self.inheritColor = inheritColor
        self.defaultOpacity = defaultOpacity
        self.defaultOutsidePosition = defaultOutsidePosition
        self.textStyle = textStyle
        self.defaultTextMargin = defaultTextMargin
        self.autoOverflowArea = autoOverflowArea
        self.layoutRect = layoutRect
        self.defaultText = defaultText
        self.labelFetcher = labelFetcher
        self.labelDataIndex = labelDataIndex
        self.labelDimIndex = labelDimIndex
        self.enableTextSetter = enableTextSetter
    }

    var textCommonParams: TextCommonParams {
        TextCommonParams(
            disableBox: disableBox, inheritColor: inheritColor, defaultOpacity: defaultOpacity,
            defaultOutsidePosition: defaultOutsidePosition, textStyle: textStyle,
            defaultTextMargin: defaultTextMargin, autoOverflowArea: autoOverflowArea, layoutRect: layoutRect
        )
    }
}

/// upstream inline callback type of `SetLabelStyleOpt.defaultText`'s function arm.
public typealias DefaultTextFn = (Double?, SetLabelStyleOpt, InterpolatableValue?) -> String

/// upstream: `type LabelStatesModels<LabelModel> = Partial<Record<DisplayStateNonNormal, LabelModel>>
///   & { normal: LabelModel }`. Modeled as a plain dictionary — `Model` is untyped `ModelOption`
///   already, so the generic parameter narrows nothing; the `normal`-is-required half of the TS
///   intersection is documentation-only here (call sites `guard`/default rather than rely on the
///   type system, since Swift dictionaries can't express "this one key is mandatory").
public typealias LabelStatesModels = [DisplayState: Model]

// upstream: `export const labelInner = makeInner<{...}, ZRText>();` (labelStyle.ts:701-737).
// PORT (makeInner side-store, CONVENTIONS §8 / see `getECData`/`getHighDownInner`/axis*Inner
//   precedents found via `grep makeInner`): `T` must be a class for `model.makeInner<T, Host>`, so the
//   anonymous inner-store record becomes a `final class`.
public final class LabelInnerStore {
    /// Previous target value stored used for label. It's mainly for text animation.
    public var prevValue: InterpolatableValue?
    /// Target value stored used for label.
    public var value: InterpolatableValue?
    /// Current value in text animation.
    public var interpolatedValue: InterpolatableValue?
    /// If enable value animation.
    public var valueAnimation: Bool?
    /// Label value precision during animation. upstream `number | 'auto'`.
    public var precision: Any?
    /// If enable value animation.
    public var statesModels: LabelStatesModels?
    /// Default text getter during interpolation.
    public var defaultInterpolatedText: ((InterpolatableValue) -> String)?
    /// Change label text from interpolated text during animation.
    public var setLabelText: ((InterpolatableValue?) -> Void)?
    public init() {}
}

public enum labelStyle {

    // ───────────────────────────── setLabelText (labelStyle.ts:130) ─────────────────────────────

    /// Set normal/emphasis/blur/select text on an ALREADY-ATTACHED `ZRText` (used directly by callers
    /// that manage their own text content, and by the DEFERRED value-animation `during` callback).
    public static func setLabelText(_ label: ZRText, _ labelTexts: [DisplayState: String]) {
        for stateName in states.SPECIAL_STATES {
            guard let stateEnum = DisplayState(rawValue: stateName) else { continue }
            let text = labelTexts[stateEnum]
            let state = label.ensureState(stateName)
            // upstream: `state.style = state.style || {}; state.style.text = text;` — `ZRText`'s
            //   per-state style lives in the additive `ElementState.textStyle` side-channel (see
            //   Element.swift PORT-NOTE), not the generic `ElementState.style` dict.
            var style = state.textStyle ?? TextStyleProps()
            style.text = text
            state.textStyle = style
        }

        let oldStates = label.currentStates  // upstream `.slice()` — Array is already value-type, this copies.
        label.clearStates(true)
        // upstream: `label.setStyle({ text: labelTexts.normal })` — a MERGE-set of just the `text`
        //   field. `ZRText` has no `TextStyleProps`-merge `setStyle` counterpart to `Displayable
        //   .setStyle(CommonStyleProps)` (its style lives in the separate `textStyle` property — see
        //   ZRText's STYLE DECISION note), so the single-field merge is reproduced by hand: read the
        //   current style, mutate just `.text`, then `useStyle` (full replace) — behaviorally
        //   equivalent since every other field is carried over unchanged.
        var normalStyle = label.textStyle ?? TextStyleProps()
        normalStyle.text = labelTexts[.normal]
        label.useStyle(normalStyle)
        label.useStates(oldStates, true)
    }

    // ───────────────────────────── getLabelText (labelStyle.ts:145) ─────────────────────────────

    static func getLabelText(
        _ opt: SetLabelStyleOpt,
        _ stateModels: LabelStatesModels,
        _ interpolatedValue: InterpolatableValue? = nil
    ) -> [DisplayState: String] {
        let labelFetcher = opt.labelFetcher
        let labelDataIndex = opt.labelDataIndex
        let labelDimIndex = opt.labelDimIndex
        let normalModel = stateModels[.normal]

        var baseText: String?
        if let labelFetcher = labelFetcher, let labelDataIndex = labelDataIndex {
            baseText = labelFetcher.getFormattedLabel(
                labelDataIndex, .normal, nil, labelDimIndex,
                normalModel?.get("formatter"),
                interpolatedValue != nil
                    ? GetFormattedLabelExtendParams(interpolatedValue: interpolatedValue!)
                    : nil
            )
        }
        if baseText == nil {
            if let fn = opt.defaultText as? DefaultTextFn {
                baseText = fn(labelDataIndex, opt, interpolatedValue)
            }
            else {
                baseText = opt.defaultText as? String
            }
        }

        var statesText: [DisplayState: String] = [:]
        statesText[.normal] = baseText

        for stateName in states.SPECIAL_STATES {
            guard let stateEnum = DisplayState(rawValue: stateName) else { continue }
            let stateModel = stateModels[stateEnum]
            var fetched: String?
            if let labelFetcher = labelFetcher, let labelDataIndex = labelDataIndex {
                fetched = labelFetcher.getFormattedLabel(
                    labelDataIndex, stateEnum, nil, labelDimIndex, stateModel?.get("formatter"), nil
                )
            }
            // upstream `retrieve2(fetched, baseText)` — nil-coalesce (an empty string from `fetched`
            //   is NOT nil, so it is kept, matching JS `retrieve2`'s null/undefined-only fallback).
            statesText[stateEnum] = fetched ?? baseText
        }
        return statesText
    }

    // ───────────────────────────── setLabelStyle (labelStyle.ts:200-306) ─────────────────────────────
    //
    // PORT: upstream declares THREE overloads (ZRText-specific / Element-generic / the shared impl
    //   body) purely to narrow `labelStatesModels`' `LabelModelForText` vs `LabelModel` generic
    //   (`LabelModelForText` = `LabelModel` minus `position`/`rotate`, since those make no sense once
    //   already applied directly to a bare ZRText). `Model` is untyped here, so the narrowing carries
    //   no runtime meaning — they collapse to the single function below, matching the impl overload's
    //   runtime body 1:1. `targetEl: Element` covers BOTH upstream overloads: `ZRText` already IS an
    //   `Element` in this port (`ZRText: Displayable, GroupLike` and `Displayable: Element`), so the
    //   `targetEl is ZRText` check below reproduces the overload dispatch upstream got from `instanceof`.
    ///
    /// Set normal styles and emphasis/blur/select styles about text on target element.
    /// If target is a ZRText, it will create a new style object on it directly.
    /// If target is another Element, it will create or reuse a ZRText attached on the target.
    ///
    /// NOTICE: Because the style on ZRText will be replaced with new (only x, y are kept),
    /// please update the style on ZRText AFTER calling this method.
    public static func setLabelStyle(
        _ targetEl: Element,
        _ labelStatesModels: LabelStatesModels,
        _ opt: SetLabelStyleOpt? = nil,
        _ stateSpecified: [DisplayState: TextStyleProps]? = nil
    ) {
        let opt = opt ?? SetLabelStyleOpt()
        let isSetOnText = targetEl is ZRText
        var needsCreateText = false
        for stateName in states.DISPLAY_STATES {
            guard let stateEnum = DisplayState(rawValue: stateName) else { continue }
            if let stateModel = labelStatesModels[stateEnum], (stateModel.getShallow("show") as? Bool) == true {
                needsCreateText = true
                break
            }
        }

        var textContent: ZRText? = isSetOnText ? (targetEl as? ZRText) : targetEl.getTextContent()
        if needsCreateText {
            if !isSetOnText {
                // Reuse the previous.
                if textContent == nil {
                    let created = ZRText()
                    targetEl.setTextContent(created)
                    textContent = created
                }
                // Use same state proxy.
                if let proxy = targetEl.stateProxy {
                    textContent!.stateProxy = proxy
                }
            }
            guard let textContent = textContent else { return }

            let labelStatesTexts = getLabelText(opt, labelStatesModels)

            // upstream assumes `labelStatesModels.normal` is non-optional (the TS intersection type
            //   guarantees it); Swift's plain dictionary cannot express that, so this guards instead.
            guard let normalModel = labelStatesModels[.normal] else { return }
            let showNormal = (normalModel.getShallow("show") as? Bool) ?? false
            var normalStyle = createTextStyle(
                normalModel, stateSpecified?[.normal], opt.textCommonParams, false, !isSetOnText
            )
            normalStyle.text = labelStatesTexts[.normal]
            if !isSetOnText {
                targetEl.setTextConfig(createTextConfig(normalModel, opt.textCommonParams, false))
            }

            for stateName in states.SPECIAL_STATES {
                guard let stateEnum = DisplayState(rawValue: stateName) else { continue }
                guard let stateModel = labelStatesModels[stateEnum] else { continue }

                let stateObj = textContent.ensureState(stateName)
                let stateShow = (stateModel.getShallow("show") as? Bool) ?? showNormal
                if stateShow != showNormal {
                    stateObj.ignore = !stateShow
                }
                var stObjStyle = createTextStyle(
                    stateModel, stateSpecified?[stateEnum], opt.textCommonParams, true, !isSetOnText
                )
                stObjStyle.text = labelStatesTexts[stateEnum]
                stateObj.textStyle = stObjStyle

                if !isSetOnText {
                    let targetElEmphasisState = targetEl.ensureState(stateName)
                    targetElEmphasisState.textConfig = createTextConfig(stateModel, opt.textCommonParams, true)
                }
            }

            // PENDING: if there is many requirements that emphasis position need to be different from
            // normal position, we might consider auto silent in those cases.
            textContent.silent = (normalModel.getShallow("silent") as? Bool) ?? false
            // Keep x and y.
            if textContent.textStyle.x != nil { normalStyle.x = textContent.textStyle.x }
            if textContent.textStyle.y != nil { normalStyle.y = textContent.textStyle.y }
            textContent.ignore = !showNormal
            // Always create new style.
            textContent.useStyle(normalStyle)
            textContent.dirty()

            if opt.enableTextSetter ?? false {
                let capturedOpt = opt
                let capturedModels = labelStatesModels
                labelInner(textContent).setLabelText = { [weak textContent] interpolatedValue in
                    guard let textContent = textContent else { return }
                    let texts = getLabelText(capturedOpt, capturedModels, interpolatedValue)
                    setLabelText(textContent, texts)
                }
            }
        }
        else if let textContent = textContent {
            // Not display rich text.
            textContent.ignore = true
        }
        targetEl.dirty()
    }

    // ───────────────────────────── getLabelStatesModels (labelStyle.ts:308) ─────────────────────────────

    /// upstream `getLabelStatesModels<LabelName extends string = 'label'>(itemModel, labelName?)` —
    /// the `LabelName` generic is dropped (see file header PORT note); `labelName` defaults to
    /// `"label"` exactly like the TS default.
    public static func getLabelStatesModels(_ itemModel: Model, _ labelName: String = "label") -> LabelStatesModels {
        var statesModels: LabelStatesModels = [.normal: itemModel.getModel(labelName)]
        for stateName in states.SPECIAL_STATES {
            guard let stateEnum = DisplayState(rawValue: stateName) else { continue }
            statesModels[stateEnum] = itemModel.getModel([stateName, labelName])
        }
        return statesModels
    }

    // ───────────────────────────── createTextStyle (labelStyle.ts:325) ─────────────────────────────

    /// Set basic textStyle properties.
    @discardableResult
    public static func createTextStyle(
        _ textStyleModel: Model,
        _ specifiedTextStyle: TextStyleProps? = nil,
        _ opt: TextCommonParams? = nil,
        _ isNotNormal: Bool? = nil,
        _ isAttached: Bool? = nil
    ) -> TextStyleProps {
        var textStyle = TextStyleProps()
        setTextStyleCommon(&textStyle, textStyleModel, opt, isNotNormal, isAttached)
        if let specifiedTextStyle = specifiedTextStyle {
            // upstream `extend(textStyle, specifiedTextStyle)` -> ZRenderKit.extendTextStyle
            //   (Graphic/Text.swift, widened `internal` -> `public` for this call site).
            ZRenderKit.extendTextStyle(&textStyle, specifiedTextStyle)
        }
        return textStyle
    }

    // ───────────────────────────── createTextConfig (labelStyle.ts:340) ─────────────────────────────

    public static func createTextConfig(
        _ textStyleModel: Model,
        _ opt: TextCommonParams? = nil,
        _ isNotNormal: Bool? = nil
    ) -> ElementTextConfig {
        let opt = opt ?? TextCommonParams()
        var textConfig = ElementTextConfig()
        var labelRotate = _num(textStyleModel.getShallow("rotate"))
        let labelDistanceFallback: Double? = (isNotNormal ?? false) ? nil : 5
        let labelDistance = _num(textStyleModel.getShallow("distance")) ?? labelDistanceFallback
        let labelOffset = _doubleArray(textStyleModel.getShallow("offset"))
        var labelPosition: Any? = textStyleModel.getShallow("position") ?? ((isNotNormal ?? false) ? nil : "inside")
        // 'outside' is not a valid zr textPosition value, but used in bar series, and magic type
        // should be considered.
        if let s = labelPosition as? String, s == "outside" {
            labelPosition = opt.defaultOutsidePosition ?? "top"
        }
        if labelPosition != nil {
            textConfig.position = labelPosition
        }
        if let labelOffset = labelOffset {
            textConfig.offset = labelOffset
        }
        if let lr = labelRotate {
            labelRotate = lr * Double.pi / 180
            textConfig.rotation = labelRotate
        }
        if let labelDistance = labelDistance {
            textConfig.distance = labelDistance
        }
        // fill and auto is determined by the color of path fill if it's not specified by developers.
        let colorOpt = textStyleModel.get("color") as? String
        textConfig.outsideFill = (colorOpt == "inherit") ? opt.inheritColor : "auto"
        if let autoOverflowArea = opt.autoOverflowArea {
            textConfig.autoOverflowArea = autoOverflowArea
        }
        if let layoutRect = opt.layoutRect {
            textConfig.layoutRect = layoutRect
        }
        return textConfig
    }

    // ───────────────────────────── setTextStyleCommon (labelStyle.ts:394) ─────────────────────────────
    //
    // The uniform entry of set text style, that is, retrieve style definitions from `model` and set to
    // `textStyle` object.
    //
    // Never in merge mode, but in overwrite mode, that is, all of the text style properties will be
    // set. (Consider the states of normal and emphasis and default value can be adopted, merge would
    // make the logic too complicated to manage.)
    public static func setTextStyleCommon(
        _ textStyle: inout TextStyleProps,
        _ textStyleModel: Model,
        _ opt: TextCommonParams? = nil,
        _ isNotNormal: Bool? = nil,
        _ isAttached: Bool? = nil
    ) {
        // Consider there will be abnormality when merging hover style into normal style if given a
        // default value.
        let opt = opt ?? TextCommonParams()
        let ecModel = textStyleModel.ecModel
        let globalTextStyle: [String: Any] = ((ecModel?.option as? [String: Any])?["textStyle"] as? [String: Any]) ?? [:]

        // Consider case:
        // { data: [{ value: 12, label: { rich: { /* no 'a' here but using parent 'a'. */ } } }],
        //   rich: { a: { ... } } }
        let richItemNames = getRichItemNames(textStyleModel)
        if let richItemNames = richItemNames, !richItemNames.isEmpty {
            var richResult: [String: TextStylePropsPart] = [:]
            let richInheritPlainLabel = (textStyleModel.get("richInheritPlainLabel") as? Bool)
                ?? (ecModel?.get("richInheritPlainLabel") as? Bool)
            for name in richItemNames.keys {
                // Cascade is supported in rich.
                let richTextStyle = textStyleModel.getModel(["rich", name])
                var part = TextStylePropsPart()
                setTokenTextStyle(
                    &part, richTextStyle, globalTextStyle, textStyleModel, richInheritPlainLabel,
                    opt, isNotNormal, isAttached, false, true
                )
                richResult[name] = part
            }
            textStyle.rich = richResult
        }

        if let overflow = textStyleModel.get("overflow") as? String { textStyle.overflow = overflow }
        if let lineOverflow = textStyleModel.get("lineOverflow") as? String { textStyle.lineOverflow = lineOverflow }

        // `minMargin` has a higher precedence than `textMargin`, because `textMargin` is allowed to be
        // set in `defaultOption`.
        if let minMarginRaw = textStyleModel.get("minMargin") {
            // `minMargin` only supports a number value.
            let mm: Double = util.isNumber(minMarginRaw) ? ((_num(minMarginRaw) ?? 0) / 2) : 0
            textStyle.margin = .array([mm, mm, mm, mm])
            // PORT-TODO (documented gap — see file header): upstream also stamps
            //   `__marginType = LabelMarginType.minMargin` on the style object here, for later
            //   margin-conflict resolution. `TextStyleProps` has no such field.
        }
        else if let textMarginRaw = textStyleModel.get("textMargin") {
            if let normalized = _normalizeCssArrayAny(textMarginRaw) {
                textStyle.margin = .array(normalized)
            }
            // PORT-TODO (documented gap — see file header): `__marginType = LabelMarginType.textMargin`
            //   not stored — same gap as above.
        }

        setTokenTextStyle(
            &textStyle, textStyleModel, globalTextStyle, nil, nil, opt, isNotNormal, isAttached, true, false
        )
    }

    // ───────────────────────────── getRichItemNames (labelStyle.ts:501) ─────────────────────────────
    //
    // Consider case:
    // { data: [{ value: 12, label: { rich: { /* no 'a' here but using parent 'a'. */ } } }],
    //   rich: { a: { ... } } }
    private static func getRichItemNames(_ textStyleModelIn: Model) -> [String: Int]? {
        // Use a dictionary to remove duplicated names.
        var richItemNameMap: [String: Int]?
        var textStyleModel: Model? = textStyleModelIn
        while let m = textStyleModel, m !== m.ecModel {
            let rich = (m.option as? [String: Any])?["rich"] as? [String: Any]
            if let rich = rich {
                if richItemNameMap == nil { richItemNameMap = [:] }
                for key in rich.keys { richItemNameMap![key] = 1 }
            }
            textStyleModel = m.parentModel
        }
        return richItemNameMap
    }

    // ───────────────────────────── setTokenTextStyle (labelStyle.ts:533) ─────────────────────────────
    //
    // PORT: upstream's single `setTokenTextStyle` is typed on `TextStyleProps['rich'][string]`
    //   (= `TextStylePropsPart`) and relies on `TextStyleProps` being a structural SUBTYPE (any caller
    //   passing a full `TextStyleProps` where a `TextStylePropsPart` is expected type-checks, since it
    //   has a superset of fields). Swift structs have no subtyping, so this collapses to a shared
    //   generic CORE (`_setTokenTextStyleCore<U: TextStylePropsPartLike>`, using the protocol widened
    //   in ZRenderKit's Text.swift for exactly this purpose — see the PORT-NOTE there) plus two thin
    //   public overloads that each handle the ONE field the two structs disagree on: `width`
    //   (`Double` on `TextStyleProps` vs `NumberOrString` on `TextStylePropsPart` — intentionally
    //   excluded from `TextStylePropsPartLike`). `ellipsis` (present only on `TextStyleProps`) is
    //   likewise handled only in that overload; upstream itself flags rich-text ellipsis handling as
    //   an open FIXME (`// FIXME: check/refactor for ellipsis handling of rich text.`,
    //   labelStyle.ts:535), so dropping it for the `TextStylePropsPart` overload mirrors that.
    public static func setTokenTextStyle(
        _ textStyle: inout TextStyleProps,
        _ textStyleModel: Model,
        _ globalTextStyle: [String: Any],
        _ plainTextModel: Model?,
        _ richInheritPlainLabel: Bool?,
        _ opt: TextCommonParams? = nil,
        _ isNotNormal: Bool? = nil,
        _ isAttached: Bool? = nil,
        _ isBlock: Bool? = nil,
        _ inRich: Bool? = nil
    ) {
        _setTokenTextStyleCore(
            &textStyle, textStyleModel, globalTextStyle, plainTextModel, richInheritPlainLabel,
            opt, isNotNormal, isAttached, isBlock, inRich
        )
        if let v = _num(textStyleModel.getShallow("width")) { textStyle.width = v }
        if let v = textStyleModel.getShallow("ellipsis") as? String { textStyle.ellipsis = v }
    }

    public static func setTokenTextStyle(
        _ textStyle: inout TextStylePropsPart,
        _ textStyleModel: Model,
        _ globalTextStyle: [String: Any],
        _ plainTextModel: Model?,
        _ richInheritPlainLabel: Bool?,
        _ opt: TextCommonParams? = nil,
        _ isNotNormal: Bool? = nil,
        _ isAttached: Bool? = nil,
        _ isBlock: Bool? = nil,
        _ inRich: Bool? = nil
    ) {
        _setTokenTextStyleCore(
            &textStyle, textStyleModel, globalTextStyle, plainTextModel, richInheritPlainLabel,
            opt, isNotNormal, isAttached, isBlock, inRich
        )
        if let v = textStyleModel.getShallow("width") {
            textStyle.width = _coerceNumberOrString(v)
        }
    }

    private static func _setTokenTextStyleCore<U: TextStylePropsPartLike>(
        _ textStyle: inout U,
        _ textStyleModel: Model,
        _ globalTextStyleIn: [String: Any],
        _ plainTextModel: Model?,
        _ richInheritPlainLabel: Bool?,
        _ opt: TextCommonParams?,
        _ isNotNormal: Bool?,
        _ isAttached: Bool?,
        _ isBlock: Bool?,
        _ inRich: Bool?
    ) {
        // In merge mode, default values should not be given.
        let globalTextStyle: [String: Any] = (!(isNotNormal ?? false)) ? globalTextStyleIn : [:]
        let inheritColor = opt?.inheritColor
        var fillColor = textStyleModel.getShallow("color") as? String
        var strokeColor = textStyleModel.getShallow("textBorderColor") as? String
        var opacity = _num(textStyleModel.getShallow("opacity")) ?? _num(globalTextStyle["opacity"])

        if fillColor == "inherit" || fillColor == "auto" {
            if fillColor == "auto" { log.deprecateReplaceLog("color: 'auto'", "color: 'inherit'") }
            fillColor = inheritColor
        }
        if strokeColor == "inherit" || strokeColor == "auto" {
            if strokeColor == "auto" { log.deprecateReplaceLog("color: 'auto'", "color: 'inherit'") }
            strokeColor = inheritColor
        }
        if !(isAttached ?? false) {
            // Only use default global textStyle.color if text is individual. Otherwise it will use
            // the strategy of attached text color because text may be on a path.
            fillColor = fillColor ?? (globalTextStyle["color"] as? String)
            strokeColor = strokeColor ?? (globalTextStyle["textBorderColor"] as? String)
        }
        if let fillColor = fillColor {
            // Might not be a string in upstream (e.g. a function in the axisLabel case); this port
            //   commits to `String` (see `TextStyleProps.fill: String?`).
            textStyle.fill = fillColor
        }
        if let strokeColor = strokeColor { textStyle.stroke = strokeColor }

        let textBorderWidth = _num(textStyleModel.getShallow("textBorderWidth")) ?? _num(globalTextStyle["textBorderWidth"])
        if let textBorderWidth = textBorderWidth { textStyle.lineWidth = textBorderWidth }

        let textBorderTypeRaw = textStyleModel.getShallow("textBorderType") ?? globalTextStyle["textBorderType"]
        if let ld = _coerceLineDash(textBorderTypeRaw) { textStyle.lineDash = ld }

        let textBorderDashOffset = _num(textStyleModel.getShallow("textBorderDashOffset"))
            ?? _num(globalTextStyle["textBorderDashOffset"])
        if let textBorderDashOffset = textBorderDashOffset { textStyle.lineDashOffset = textBorderDashOffset }

        if !(isNotNormal ?? false) && opacity == nil && !(inRich ?? false) {
            opacity = opt?.defaultOpacity
        }
        if let opacity = opacity { textStyle.opacity = opacity }

        // TODO
        if !(isNotNormal ?? false) && !(isAttached ?? false) {
            // Set default finally.
            if textStyle.fill == nil, let inheritColor = opt?.inheritColor {
                textStyle.fill = inheritColor
            }
        }

        // Do not use `getFont` here, because merge should be supported, where part of these
        // properties may be changed in emphasis style, and the others should remain their original
        // value got from normal style.
        // upstream TEXT_PROPS_WITH_GLOBAL = ['fontStyle','fontWeight','fontSize','fontFamily',
        //   'textShadowColor','textShadowBlur','textShadowOffsetX','textShadowOffsetY']
        if let v = _retrieveGlobalProp("fontStyle", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel),
           let fs = _coerceFontStyle(v) {
            textStyle.fontStyle = fs
        }
        if let v = _retrieveGlobalProp("fontWeight", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel),
           let fw = _coerceFontWeight(v) {
            textStyle.fontWeight = fw
        }
        if let v = _retrieveGlobalProp("fontSize", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel),
           let fs = _coerceNumberOrString(v) {
            textStyle.fontSize = fs
        }
        if let v = _retrieveGlobalProp("fontFamily", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel) as? String {
            textStyle.fontFamily = v
        }
        if let v = _retrieveGlobalProp("textShadowColor", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel) as? String {
            textStyle.textShadowColor = v
        }
        if let v = _num(_retrieveGlobalProp("textShadowBlur", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel)) {
            textStyle.textShadowBlur = v
        }
        if let v = _num(_retrieveGlobalProp("textShadowOffsetX", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel)) {
            textStyle.textShadowOffsetX = v
        }
        if let v = _num(_retrieveGlobalProp("textShadowOffsetY", textStyleModel, plainTextModel, globalTextStyle, richInheritPlainLabel)) {
            textStyle.textShadowOffsetY = v
        }

        // upstream TEXT_PROPS_SELF = ['align','lineHeight','width','height','tag','verticalAlign',
        //   'ellipsis'] — 'width'/'ellipsis' are handled by the two public overloads above (they
        //   differ per-type / are TextStyleProps-only, respectively).
        if let v = _coerceTextAlign(textStyleModel.getShallow("align")) { textStyle.align = v }
        if let v = _num(textStyleModel.getShallow("lineHeight")) { textStyle.lineHeight = v }
        if let v = _num(textStyleModel.getShallow("height")) { textStyle.height = v }
        if let v = textStyleModel.getShallow("tag") as? String { textStyle.tag = v }
        if let v = _coerceVerticalAlign(textStyleModel.getShallow("verticalAlign")) { textStyle.verticalAlign = v }

        if textStyle.verticalAlign == nil {
            if let v = _coerceVerticalAlign(textStyleModel.getShallow("baseline")) {
                textStyle.verticalAlign = v
            }
        }

        if !(isBlock ?? false) || !(opt?.disableBox ?? false) {
            // upstream TEXT_PROPS_BOX = ['padding','borderWidth','borderRadius','borderDashOffset',
            //   'backgroundColor','borderColor','shadowColor','shadowBlur','shadowOffsetX','shadowOffsetY']
            if let v = _coerceNumberOrNumberArray(textStyleModel.getShallow("padding")) { textStyle.padding = v }
            if let v = _num(textStyleModel.getShallow("borderWidth")) { textStyle.borderWidth = v }
            if let v = _coerceNumberOrNumberArray(textStyleModel.getShallow("borderRadius")) { textStyle.borderRadius = v }
            if let v = _num(textStyleModel.getShallow("borderDashOffset")) { textStyle.borderDashOffset = v }
            if let v = _coerceTextBackgroundColor(textStyleModel.getShallow("backgroundColor")) { textStyle.backgroundColor = v }
            if let v = textStyleModel.getShallow("borderColor") as? String { textStyle.borderColor = v }
            if let v = textStyleModel.getShallow("shadowColor") as? String { textStyle.shadowColor = v }
            if let v = _num(textStyleModel.getShallow("shadowBlur")) { textStyle.shadowBlur = v }
            if let v = _num(textStyleModel.getShallow("shadowOffsetX")) { textStyle.shadowOffsetX = v }
            if let v = _num(textStyleModel.getShallow("shadowOffsetY")) { textStyle.shadowOffsetY = v }

            if let borderType = _coerceLineDash(textStyleModel.getShallow("borderType")) {
                textStyle.borderDash = borderType
            }

            if case .string(let bg)? = textStyle.backgroundColor, (bg == "auto" || bg == "inherit"), let inheritColor = inheritColor {
                if bg == "auto" { log.deprecateReplaceLog("backgroundColor: 'auto'", "backgroundColor: 'inherit'") }
                textStyle.backgroundColor = .string(inheritColor)
            }
            if let bc = textStyle.borderColor, (bc == "auto" || bc == "inherit"), let inheritColor = inheritColor {
                if bc == "auto" { log.deprecateReplaceLog("borderColor: 'auto'", "borderColor: 'inherit'") }
                textStyle.borderColor = inheritColor
            }
        }
    }

    // upstream: `(richInheritPlainLabel !== false && plainTextModel) ? retrieve3(...) : retrieve2(...)`
    //   — a shared retrieval used by the TEXT_PROPS_WITH_GLOBAL loop.
    private static func _retrieveGlobalProp(
        _ key: String, _ textStyleModel: Model, _ plainTextModel: Model?,
        _ globalTextStyle: [String: Any], _ richInheritPlainLabel: Bool?
    ) -> Any? {
        if richInheritPlainLabel != false, let plainTextModel = plainTextModel {
            return textStyleModel.getShallow(key) ?? plainTextModel.getShallow(key) ?? globalTextStyle[key]
        }
        return textStyleModel.getShallow(key) ?? globalTextStyle[key]
    }

    // ───────────────────────────── getFont (labelStyle.ts:687) ─────────────────────────────

    /// upstream `getFont(opt: Pick<TextCommonOption, 'fontStyle'|'fontWeight'|'fontSize'|'fontFamily'>,
    ///   ecModel)`. `Pick<...>` collapses to four dynamic (`Any?`) fields, matching the values a
    ///   `Model.getShallow(key)` read produces.
    public struct GetFontOpt {
        public var fontStyle: Any?
        public var fontWeight: Any?
        public var fontSize: Any?
        public var fontFamily: Any?
        public init(fontStyle: Any? = nil, fontWeight: Any? = nil, fontSize: Any? = nil, fontFamily: Any? = nil) {
            self.fontStyle = fontStyle
            self.fontWeight = fontWeight
            self.fontSize = fontSize
            self.fontFamily = fontFamily
        }
    }

    /// Create a font string from fontStyle, fontWeight, fontSize, fontFamily.
    // PORT-NOTE: `model/mixin/textStyle.swift`'s `TextStyleMixin.getFont()` currently reproduces this
    //   exact body inline (`_labelStyleGetFont`, with an explicit PORT-TODO to call this once it
    //   landed) because it was ported OUT OF PHASE, before `label/labelStyle.swift` existed. Left
    //   as-is here (not retrofitted) to keep this phase's diff scoped to the two files it was asked to
    //   create; a follow-up can delete `_labelStyleGetFont` and forward to `labelStyle.getFont` instead.
    public static func getFont(_ opt: GetFontOpt, _ ecModel: GlobalModel?) -> String {
        let gTextStyleModel = ecModel?.getModel("textStyle")
        // FIXME in node-canvas fontWeight is before fontStyle
        let parts = [
            _jsTruthyString(opt.fontStyle, gTextStyleModel?.getShallow("fontStyle"), ""),
            _jsTruthyString(opt.fontWeight, gTextStyleModel?.getShallow("fontWeight"), ""),
            _jsNumberToString(_jsTruthyNumber(opt.fontSize, gTextStyleModel?.getShallow("fontSize"), 12)) + "px",
            _jsTruthyString(opt.fontFamily, gTextStyleModel?.getShallow("fontFamily"), "sans-serif")
        ]
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // ───────────────────────────── labelInner (labelStyle.ts:701) ─────────────────────────────

    public static let labelInner: (ZRText) -> LabelInnerStore = model.makeInner { LabelInnerStore() }

    // ───────────────────────────── setLabelValueAnimation (labelStyle.ts:739) ─────────────────────────────
    //
    // Store the (new) target value on `labelInner` and, when `valueAnimation` is enabled on the normal
    // label model, snapshot the precision / default-text getter / states-models needed by the number
    // roll-up animation that `animateLabelValue` later runs. Faithful 1:1 port; the only shape change is
    // `LabelStatesModels<LabelModelForText>` collapsing to the port's untyped `LabelStatesModels`.
    public static func setLabelValueAnimation(
        _ label: ZRText?,
        _ labelStatesModels: LabelStatesModels,
        _ value: InterpolatableValue?,
        _ getDefaultText: @escaping (InterpolatableValue) -> String
    ) {
        guard let label = label else { return }

        let obj = labelInner(label)
        obj.prevValue = obj.value
        obj.value = value
        // upstream reads `labelStatesModels.normal` unconditionally (the TS intersection guarantees it);
        //   the port's plain dictionary can't, so guard — no normal model ⇒ nothing to animate.
        guard let normalLabelModel = labelStatesModels[.normal] else { return }

        obj.valueAnimation = normalLabelModel.get("valueAnimation") as? Bool

        if obj.valueAnimation == true {
            obj.precision = normalLabelModel.get("precision")
            obj.defaultInterpolatedText = getDefaultText
            obj.statesModels = labelStatesModels
        }
    }

    // ───────────────────────────── animateLabelValue (labelStyle.ts:763) ─────────────────────────────
    //
    // Drive the label's displayed text from the previous value to the target value: each animation frame
    // interpolates the raw value (via the ported `interpolateRawValues`) and re-formats the label text.
    //
    // PORT-NOTE (`percent` prop): upstream animates a SYNTHETIC `percent` prop on the ZRText purely to
    //   keep the animator alive (#15916); the port has no dynamic per-element property, so `percent` is
    //   an unknown key — `initProps`/`updateProps` still create a forced animator (because a `during`
    //   callback is supplied, `animateOrSetProps` sets `force`), so the per-frame `during` fires exactly
    //   as upstream. When animation is DISABLED, `animateOrSetProps` synchronously calls `during(1)`, so
    //   the label settles to the final formatted value in one shot.
    //
    // STATIC PNG ORACLE DEVIATION: the headless oracle advances animators to completion (percent→1), so
    //   the label settles to the FINAL formatted number rather than showing a mid-roll intermediate — the
    //   live host renders the intermediate frames. (See MEMORY live-animation-host / advanceAnimations.)
    public static func animateLabelValue(
        _ textEl: ZRText,
        _ dataIndex: Double?,
        _ data: SeriesData,
        _ animatableModel: Model?,
        _ labelFetcher: DataFormatMixin?
    ) {
        let labelInnerStore = labelInner(textEl)
        if labelInnerStore.valueAnimation != true
            || _valuesStrictEqual(labelInnerStore.prevValue, labelInnerStore.value) {
            // Value not changed, no new label animation.
            return
        }

        let defaultInterpolatedText = labelInnerStore.defaultInterpolatedText
        // Consider the case that being animating: do not use `obj.value`, otherwise it will jump to
        //   `obj.value` when this new animation started.
        let currValue = util.retrieve2(labelInnerStore.interpolatedValue, labelInnerStore.prevValue)
        let targetValue = labelInnerStore.value

        let dataIndexInt: Int? = dataIndex.map { Int($0) }
        let statesModels = labelInnerStore.statesModels ?? [:]

        let during: (Double) -> Void = { percent in
            let interpolated = model.interpolateRawValues(
                data,
                labelInnerStore.precision,
                currValue,
                targetValue,
                percent
            )

            labelInnerStore.interpolatedValue = percent == 1 ? nil : interpolated

            var opt = SetLabelStyleOpt()
            opt.labelDataIndex = dataIndex
            opt.labelFetcher = labelFetcher
            opt.defaultText = defaultInterpolatedText != nil
                ? (interpolated.map { defaultInterpolatedText!($0) } ?? "")
                // upstream `interpolated + ''` — JS string coercion of the interpolated value.
                : _interpolatedValueToString(interpolated)

            let labelText = getLabelText(opt, statesModels, interpolated)
            setLabelText(textEl, labelText)
        }

        // upstream: `(textEl as ZRText & {percent?}).percent = 0` — a synthetic animatable prop (see
        //   PORT-NOTE above). Setting it here is a no-op in the port (unknown key), but harmless.
        _ = textEl.attr("percent", 0.0)
        let props: [String: Any] = ["percent": 1.0]
        if labelInnerStore.prevValue == nil {
            initProps(textEl, props, animatableModel, dataIndexInt, nil, during)
        }
        else {
            updateProps(textEl, props, animatableModel, dataIndexInt, nil, during)
        }
    }

    // upstream `interpolated + ''` — JS coercion of an `InterpolatableValue` to a string.
    private static func _interpolatedValueToString(_ v: InterpolatableValue?) -> String {
        guard let v = v else { return "" }   // JS `null + ''` → 'null'/'undefined'; empty is safer here.
        if let d = v as? Double { return _jsNumberToString(d) }
        if let i = v as? Int { return String(i) }
        if let s = v as? String { return s }
        return "\(v)"
    }

    // ───────────────────────────── LabelMarginType (labelStyle.ts:819) ─────────────────────────────
    //
    // PENDING (upstream comment): Temporary impl. unify them?
    // PORT: the enum itself is trivial and ported faithfully; ATTACHING the tag to a style object
    //   (`LabelExtendedTextStyle.__marginType`) is a documented gap — see the file header and the two
    //   PORT-TODOs in `setTextStyleCommon` above.
    public enum LabelMarginType: Int {
        case minMargin = 1
        case textMargin = 2
    }
}

// ============================================================================
// Swift coercion helpers (dynamic `ModelOption` (Any?) -> typed TextStyleProps/TextStylePropsPart
// fields). Mirrors the private helper convention already established in
// `model/mixin/textStyle.swift` (`_coerceFontStyle`/`_coerceFontWeight`/`_coerceNumberOrString`/
// `_coerceNumberOrNumberArray`/`_coerceVerticalAlign`) — duplicated here (file-private) rather than
// shared, matching this codebase's existing convention of per-file `numOpt`/`asDouble`-style helpers
// (see e.g. coord/parallel/*.swift, chart/pie/pieLayout.swift, component/tooltip/TooltipView.swift).
// ============================================================================

// Int-vs-Double option-read trap: `defaultOptions` box integral option values as `Int`, so a plain
// `as? Double` silently drops them. Bridges Double/Int/NSNumber uniformly.
private func _num(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

private func _doubleArray(_ v: Any?) -> [Double]? {
    if let a = v as? [Double] { return a }
    if let a = v as? [Any] {
        var out: [Double] = []
        for e in a {
            guard let d = _num(e) else { return nil }
            out.append(d)
        }
        return out
    }
    return nil
}

private func _normalizeCssArrayAny(_ v: Any) -> [Double]? {
    if let d = _num(v) { return util.normalizeCssArray(d) }
    if let arr = _doubleArray(v) { return util.normalizeCssArray(arr) }
    return nil
}

private func _coerceFontStyle(_ v: Any?) -> FontStyle? {
    if let f = v as? FontStyle { return f }
    if let s = v as? String { return FontStyle(rawValue: s) }
    return nil
}

private func _coerceFontWeight(_ v: Any?) -> FontWeight? {
    if let f = v as? FontWeight { return f }
    if let n = _num(v) { return .number(n) }
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
    if let n = _num(v) { return .number(n) }
    if let s = v as? String { return .string(s) }
    return nil
}

private func _coerceNumberOrNumberArray(_ v: Any?) -> NumberOrNumberArray? {
    if let x = v as? NumberOrNumberArray { return x }
    if let n = _num(v) { return .number(n) }
    if let a = _doubleArray(v) { return .array(a) }
    return nil
}

private func _coerceVerticalAlign(_ v: Any?) -> TextVerticalAlign? {
    if let x = v as? TextVerticalAlign { return x }
    if let s = v as? String { return TextVerticalAlign(rawValue: s) }
    return nil
}

private func _coerceTextAlign(_ v: Any?) -> TextAlign? {
    if let x = v as? TextAlign { return x }
    if let s = v as? String { return TextAlign(rawValue: s) }
    return nil
}

private func _coerceTextBackgroundColor(_ v: Any?) -> TextBackgroundColor? {
    if let x = v as? TextBackgroundColor { return x }
    if let s = v as? String { return .string(s) }
    return nil
}

// upstream `false | number[] | 'solid' | 'dashed' | 'dotted'`.
private func _coerceLineDash(_ v: Any?) -> LineDash? {
    if let x = v as? LineDash { return x }
    if let b = v as? Bool, b == false { return .false }
    if let arr = _doubleArray(v) { return .values(arr) }
    if let s = v as? String {
        switch s {
        case "solid": return .solid
        case "dashed": return .dashed
        case "dotted": return .dotted
        default: return nil
        }
    }
    return nil
}

// ---- `getFont`'s JS `||`-chain helpers (mirrors `model/mixin/textStyle.swift`'s private
//   `_labelStyleGetFont` support functions — duplicated per this file's own PORT-NOTE above) ----

private func _jsTruthyString(_ a: Any?, _ b: Any?, _ fallback: String) -> String {
    if let s = _jsStringOrNil(a) { return s }
    if let s = _jsStringOrNil(b) { return s }
    return fallback
}

private func _jsStringOrNil(_ v: Any?) -> String? {
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = _num(v) { return (n == 0 || n.isNaN) ? nil : _jsNumberToString(n) }
    return nil
}

private func _jsTruthyNumber(_ a: Any?, _ b: Any?, _ fallback: Double) -> Double {
    if let n = _jsNumberOrNil(a) { return n }
    if let n = _jsNumberOrNil(b) { return n }
    return fallback
}

private func _jsNumberOrNil(_ v: Any?) -> Double? {
    if let n = _num(v) { return (n == 0 || n.isNaN) ? nil : n }
    return nil
}

private func _jsNumberToString(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
    return String(n)
}

// upstream `labelInnerStore.prevValue === labelInnerStore.value` — a strict-equality change-detection.
//   `InterpolatableValue` is `ParsedValue | ParsedValue[]`; for the scalar case (the only one the number
//   roll-up animates) JS `===` is value equality, which this reproduces for Double/Int/String. Two nils
//   are equal (the init case where `value` was previously unset). Arrays / mixed types fall back to
//   `false` (upstream `===` on distinct array refs is also `false`), so a re-layout re-animates — the
//   conservative, upstream-matching choice.
private func _valuesStrictEqual(_ a: InterpolatableValue?, _ b: InterpolatableValue?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case (nil, _), (_, nil): return false
    default: break
    }
    if let da = _num(a), let db = _num(b) { return da == db }
    if let sa = a as? String, let sb = b as? String { return sa == sb }
    return false
}
