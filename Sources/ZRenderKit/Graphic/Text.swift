// Ported from zrender/src/graphic/Text.ts — keep in sync with upstream
//
// PHASE-2 PORT. `ZRText` (RichText) is a COMPOSITE `Displayable`: a container that parses a text
// string + style into child `TSpan` / `Rect` / `ZRImage` nodes (one per line / token / background).
// This is the element that makes labels render.
//
// STYLE DECISION (TS `class ZRText extends Displayable<TextProps>` with `style: TextStyleProps`):
//   Swift structs cannot subclass and Swift cannot RE-TYPE the inherited `Displayable.style`
//   (`CommonStyleProps!`). Mirroring `Path`/`Image`/`TSpan` (see their STYLE DECISION notes),
//   `TextStyleProps` / `TextStylePropsPart` are flattened structs, and `ZRText` stores the rich style
//   in its OWN property `textStyle` (upstream `this.style`). `_syncCommonStyle()` mirrors the common
//   subset into the inherited `self.style` so the inherited machinery (shouldBePainted /
//   getPaintRect) reads correct shadow / opacity / blend.
//
// PORT-TODO (LAYOUT SEAM): the layout helpers `parsePlainText` / `parseRichText` /
//   `calcInnerTextOverflowArea` / `tSpanCreateBoundingRect2` and the content-block types live in
//   `graphic/helper/parseText.ts`, which is NOT ported yet. Until it lands, a clearly-fenced
//   PORT-TODO STUB of the `parseText` seam is provided at the BOTTOM of this file:
//     - `parsePlainText` implements only the no-wrap / no-truncate / no-lineOverflow subset
//       (overflow 'break'/'breakAll'/'truncate', lineOverflow, ellipsis/placeholder are PORT-TODO).
//     - `parseRichText` is a minimal PORT-TODO stub (returns an empty content block).
//     - `calcInnerTextOverflowArea` implements the no-`overflowRect` path (the common case).
//     - `tSpanCreateBoundingRect2` / `tSpanHasStroke` are ported in full (small, only need
//       `contain/text` which is ported).
//   When `graphic/helper/parseText.swift` is ported, REMOVE the fenced stub block.
//
// STUBBED (PORT-TODO, deferred — inherited from Displayable/Element):
//   - the states machinery (states / getState / ensureState / stateProxy) — Phase 2.
//   - the animation surface (animate('style') / Animator) — Phase 3.
//   - `getComputedTransform`'s host inner-text update relies on `Element.updateInnerText` (stub).

import Foundation

// upstream imports (resolved to ported modules):
// import { TextAlign, TextVerticalAlign, ImageLike, Dictionary, MapToType, FontWeight, FontStyle,
//   NullUndefined } from '../core/types';
// import { parseRichText, parsePlainText, CalcInnerTextOverflowAreaOut, calcInnerTextOverflowArea,
//   tSpanCreateBoundingRect2 } from './helper/parseText';   → PORT-TODO seam stub (bottom of file)
// import TSpan, { TSpanStyleProps } from './TSpan';         → Graphic/TSpan.swift
// import { retrieve2, each, normalizeCssArray, trim, retrieve3, extend, keys, defaults } from
//   '../core/util';                                          → util.*
// import { adjustTextX, adjustTextY } from '../contain/text';  → ZRenderKit.text.adjustTextX/Y
// import ZRImage from './Image';                            → Graphic/Image.swift
// import Rect from './shape/Rect';                          → Graphic/Shape/Rect.swift
// import BoundingRect from '../core/BoundingRect';
// import { MatrixArray } from '../core/matrix';
// import Displayable, { DisplayableStatePropNames, DisplayableProps, DEFAULT_COMMON_ANIMATION_PROPS }
//   from './Displayable';
// import { ZRenderType } from '../zrender';
// import Animator from '../animation/Animator';
// import Transformable from '../core/Transformable';
// import { ElementCommonState } from '../Element';
// import { GroupLike } from './Group';
// import { DEFAULT_FONT, DEFAULT_FONT_SIZE } from '../core/platform';

// PORT-TODO: type TextContentBlock = ReturnType<typeof parseRichText>; TextLine / TextToken are the
//   RichTextContentBlock line / token types — provided by the parseText seam stub (bottom of file).

// PORT-TODO: upstream `number | string` (used by `fontSize` / token `width`). Reuses the
//   `NumberOrString` tagged enum from contain/text.swift.
// PORT-TODO: upstream `number | number[]` (used by `padding` / `margin` / `borderRadius`). Tagged
//   enum — same pattern as `RectRadius` (Rect.swift).
public enum NumberOrNumberArray {
    case number(Double)
    case array([Double])
}

// PORT-TODO: upstream `backgroundColor?: string | { image: ImageLike | string }`. Tagged enum.
//   `.string` is a plain color / gradient string; `.image` wraps the `{ image }` object's source,
//   modeled with `ImageSource` (Image.swift: `.url(String) | .image(ImageLike)`).
public enum TextBackgroundColor {
    case string(String)
    case image(ImageSource)
}

// TODO Default value?
// upstream: export interface TextStylePropsPart
public struct TextStylePropsPart {
    // TODO Text is assigned inside zrender
    public var text: String?

    // PORT-TODO: upstream `fill?: string` / `stroke?: string` (NOT ZRColor here). `getFill`/`getStroke`
    //   cast to `any` to peek `.image`/`.colorStops` for gradients/patterns; that branch is unreachable
    //   for a Swift `String` (see getFill/getStroke PORT-TODOs).
    public var fill: String?
    public var stroke: String?
    public var strokeNoScale: Bool?

    public var opacity: Double?
    public var fillOpacity: Double?
    public var strokeOpacity: Double?
    /**
     * textStroke may be set as some color as a default
     * value in upper application, where the default value
     * of lineWidth should be 0 to make sure that
     * user can choose to do not use text stroke.
     */
    public var lineWidth: Double?
    public var lineDash: LineDash?           // upstream: false | number[]
    public var lineDashOffset: Double?
    public var borderDash: LineDash?         // upstream: false | number[]
    public var borderDashOffset: Double?

    /**
     * If `fontSize` or `fontFamily` exists, `font` will be reset by
     * `fontSize`, `fontStyle`, `fontWeight`, `fontFamily`.
     * So do not visit it directly in upper application (like echarts),
     * but use `contain/text#makeFont` instead.
     */
    public var font: String?
    /**
     * The same as font. Use font please.
     * @deprecated
     */
    public var textFont: String?

    /// It helps merging respectively, rather than parsing an entire font string.
    public var fontStyle: FontStyle?
    /// It helps merging respectively, rather than parsing an entire font string.
    public var fontWeight: FontWeight?
    /// It helps merging respectively, rather than parsing an entire font string.
    public var fontFamily: String?
    /// It helps merging respectively, rather than parsing an entire font string.
    /// Should be 12 but not '12px'.
    public var fontSize: NumberOrString?     // upstream: number | string

    public var align: TextAlign?
    public var verticalAlign: TextVerticalAlign?

    /// Line height. Default to be text height of '国'
    public var lineHeight: Double?
    /**
     * Width of text block. Not include padding
     * Used for background, truncate, wrap
     * If string - be 'auto'.
     */
    public var width: NumberOrString?        // upstream: number | string
    /**
     * Height of text block. Not include padding
     * Used for background, truncate
     */
    public var height: Double?
    /// Reserved for special functionality, like 'hr'.
    public var tag: String?

    public var textShadowColor: String?
    public var textShadowBlur: Double?
    public var textShadowOffsetX: Double?
    public var textShadowOffsetY: Double?

    // Shadow, background, border of text box.
    public var backgroundColor: TextBackgroundColor?

    /// Can be `2` or `[2, 4]` or `[2, 3, 4, 5]`
    public var padding: NumberOrNumberArray?
    /// Margin of label. Used when layouting the label.
    public var margin: NumberOrNumberArray?

    public var borderColor: String?
    public var borderWidth: Double?
    public var borderRadius: NumberOrNumberArray?

    /// Shadow color for background box.
    public var shadowColor: String?
    /// Shadow blur for background box.
    public var shadowBlur: Double?
    /// Shadow offset x for background box.
    public var shadowOffsetX: Double?
    /// Shadow offset y for background box.
    public var shadowOffsetY: Double?

    public init() {}
}

// upstream: export interface TextStyleProps extends TextStylePropsPart
//   FLATTENED into one struct (TextStylePropsPart fields + the own fields). `width` is NARROWED to
//   `number` (Double), unlike the Part's `number | string`.
public struct TextStyleProps {
    // ---- TextStylePropsPart fields (upstream: `extends TextStylePropsPart`) ----
    public var text: String?

    public var fill: String?
    public var stroke: String?
    public var strokeNoScale: Bool?

    public var opacity: Double?
    public var fillOpacity: Double?
    public var strokeOpacity: Double?
    public var lineWidth: Double?
    public var lineDash: LineDash?
    public var lineDashOffset: Double?
    public var borderDash: LineDash?
    public var borderDashOffset: Double?

    public var font: String?
    public var textFont: String?

    public var fontStyle: FontStyle?
    public var fontWeight: FontWeight?
    public var fontFamily: String?
    public var fontSize: NumberOrString?

    public var align: TextAlign?
    public var verticalAlign: TextVerticalAlign?

    public var lineHeight: Double?
    // NOTE (override): upstream narrows `width?: number` in the top block (only number supported).
    public var width: Double?
    public var height: Double?
    public var tag: String?

    public var textShadowColor: String?
    public var textShadowBlur: Double?
    public var textShadowOffsetX: Double?
    public var textShadowOffsetY: Double?

    public var backgroundColor: TextBackgroundColor?

    public var padding: NumberOrNumberArray?
    public var margin: NumberOrNumberArray?

    public var borderColor: String?
    public var borderWidth: Double?
    public var borderRadius: NumberOrNumberArray?

    public var shadowColor: String?
    public var shadowBlur: Double?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?

    // PORT-TODO: replaces upstream's dynamic STYLE_MAGIC_KEY stamp (see Displayable.swift). `true`
    //   iff produced by `createStyle`. NOT part of TextStylePropsPartLike.
    public var zrStyleMagic: Bool = false

    // ---- TextStyleProps own fields ----
    /**
     * The outer rect (including padding) is placed based on x/y.
     * By default 0.
     */
    public var x: Double?
    public var y: Double?

    /// Text styles for rich text.
    public var rich: [String: TextStylePropsPart]?

    /**
     * Strategy when calculated text width exceeds textWidth.
     * break: break by word
     * break: will break inside the word
     * truncate: truncate the text and show ellipsis
     * Do nothing if not set
     */
    public var overflow: String?     // 'break' | 'breakAll' | 'truncate' | 'none'

    /// Strategy when text lines exceeds textHeight. Do nothing if not set
    public var lineOverflow: String? // 'truncate'

    /// Epllipsis used if text is truncated
    public var ellipsis: String?
    /// Placeholder used if text is truncated to empty
    public var placeholder: String?
    /// Min characters for truncating
    public var truncateMinChar: Double?

    public init() {}
}

// PORT-TODO (Swift bridge): upstream relies on `TextStyleProps` being a SUBTYPE of
//   `TextStylePropsPart` so free functions typed on the base (`normalizeStyle`, `makeFont`,
//   `setSeparateFont`, `hasSeparateFont`, `needDrawBackground`, `_renderBackground`) accept both.
//   Swift has no struct subtyping, so we expose the shared base surface through this protocol; both
//   structs conform. `width` (which differs: `number | string` vs `number`) is intentionally NOT
//   part of the protocol.
public protocol TextStylePropsPartLike {
    var text: String? { get set }
    var fill: String? { get }
    var stroke: String? { get }
    var strokeNoScale: Bool? { get }
    var opacity: Double? { get }
    var fillOpacity: Double? { get }
    var strokeOpacity: Double? { get }
    var lineWidth: Double? { get }
    var lineDash: LineDash? { get }
    var lineDashOffset: Double? { get }
    var borderDash: LineDash? { get }
    var borderDashOffset: Double? { get }
    var font: String? { get set }
    var textFont: String? { get }
    var fontStyle: FontStyle? { get }
    var fontWeight: FontWeight? { get }
    var fontFamily: String? { get }
    var fontSize: NumberOrString? { get }
    var align: TextAlign? { get set }
    var verticalAlign: TextVerticalAlign? { get set }
    var lineHeight: Double? { get }
    var height: Double? { get }
    var tag: String? { get }
    var textShadowColor: String? { get }
    var textShadowBlur: Double? { get }
    var textShadowOffsetX: Double? { get }
    var textShadowOffsetY: Double? { get }
    var backgroundColor: TextBackgroundColor? { get }
    var padding: NumberOrNumberArray? { get set }
    var margin: NumberOrNumberArray? { get }
    var borderColor: String? { get }
    var borderWidth: Double? { get }
    var borderRadius: NumberOrNumberArray? { get }
    var shadowColor: String? { get }
    var shadowBlur: Double? { get }
    var shadowOffsetX: Double? { get }
    var shadowOffsetY: Double? { get }
}

extension TextStylePropsPart: TextStylePropsPartLike {}
extension TextStyleProps: TextStylePropsPartLike {}

// PORT-TODO: interface TextProps extends DisplayableProps { style?, zlevel?, z?, z2?, culling?,
//   cursor? }. The `attr`/`attrKV` setter machinery uses the dynamic `[String: Any]` prop bag
//   (collapsed onto DisplayableProps == ElementProps). Typed-interface fidelity dropped.
public typealias TextProps = DisplayableProps

// PORT-TODO: TextState = Pick<TextProps, DisplayableStatePropNames> & ElementCommonState. The states
//   machinery is Phase 2; collapsed onto Displayable's ElementState-based stub.
public typealias TextState = DisplayableState

// upstream: export type DefaultTextStyle = Pick<TextStyleProps, 'fill'|'stroke'|'align'|
//   'verticalAlign'> & { autoStroke?: boolean; overflowRect?: BoundingRect | NullUndefined }
//   Replaces the Phase-1 forward-declared placeholder in Element.swift.
public struct DefaultTextStyle {
    public var fill: String?
    public var stroke: String?
    public var align: TextAlign?
    public var verticalAlign: TextVerticalAlign?
    public var autoStroke: Bool?
    // In text local coord.
    // Exist if and only if `ElementTextConfig['autoOverflowArea']: true`
    public var overflowRect: BoundingRect?

    public init() {}
}

// upstream: const DEFAULT_RICH_TEXT_COLOR = { fill: '#000' };
private let DEFAULT_RICH_TEXT_COLOR: DefaultTextStyle = {
    var s = DefaultTextStyle()
    s.fill = "#000"
    return s
}()
private let DEFAULT_STROKE_LINE_WIDTH: Double = 2

// upstream: const tmpCITOverflowAreaOut = {} as CalcInnerTextOverflowAreaOut;
//   A reused mutable object (reference semantics) — modeled as a shared class instance.
private let tmpCITOverflowAreaOut = CalcInnerTextOverflowAreaOut()

// const DEFAULT_TEXT_STYLE: TextStyleProps = { ... }  (commented out upstream)

// PORT-TODO: upstream `MapToType<TextProps, boolean>` — recursive mapped utility type. Collapsed to
//   a loose `[String: Any]` bag (matches Displayable's DEFAULT_COMMON_ANIMATION_PROPS). Only read by
//   `getAnimationStyleProps` (animation surface deferred, Phase 3).
public let DEFAULT_TEXT_ANIMATION_PROPS: [String: Any] = [
    "style": [
        // from DEFAULT_COMMON_ANIMATION_PROPS.style:
        "shadowBlur": true,
        "shadowOffsetX": true,
        "shadowOffsetY": true,
        "shadowColor": true,
        "opacity": true,
        // text:
        "fill": true,
        "stroke": true,
        "fillOpacity": true,
        "strokeOpacity": true,
        "lineWidth": true,
        "fontSize": true,
        "lineHeight": true,
        "width": true,
        "height": true,
        "textShadowColor": true,
        "textShadowBlur": true,
        "textShadowOffsetX": true,
        "textShadowOffsetY": true,
        "backgroundColor": true,
        "padding": true,  // TODO needs normalize padding before animate
        "borderColor": true,
        "borderWidth": true,
        "borderRadius": true  // TODO needs normalize radius before animate
    ]
]

// upstream: interface ZRText { animate(...) overloads; getState / ensureState; states; stateProxy }
//   — declaration-merging of the animation + states surface. Provided by Element/Displayable stubs.

// upstream: class ZRText extends Displayable<TextProps> implements GroupLike
public final class ZRText: Displayable, GroupLike {

    // upstream: type = 'text' — set in init (per-instance).

    // upstream: style: TextStyleProps. Swift cannot re-type the inherited `Displayable.style`
    //   (CommonStyleProps), so the rich style lives here (upstream `this.style` → `self.textStyle`).
    public var textStyle: TextStyleProps!

    /// How to handling label overlap. hidden:
    public var overlap: String?     // 'hidden' | 'show' | 'blur'

    /**
     * Will use this to calculate transform matrix
     * instead of Element itself if it's give.
     * Not exposed to developers
     */
    // PORT-TODO: upstream non-optional `innerTransformable: Transformable`; `Element` assigns it
    //   (Transformable()) on attach and `nil` on detach, so it is Optional in the Swift port.
    public var innerTransformable: Transformable?

    // Be `true` if and only if the result text is modified due to overflow, due to
    // settings on either `overflow` or `lineOverflow`. Based on this the caller can
    // take some action like showing the original text in a particular tip.
    // Only take effect after rendering. So do not visit it before it.
    public var isTruncated: Bool = false

    // PORT-TODO: upstream union `(ZRImage | Rect | TSpan)[]`; all three are `Displayable` subclasses,
    //   so modeled as `[Displayable]`.
    private var _children: [Displayable] = []

    private var _childCursor: Int = 0

    private var _defaultStyle: DefaultTextStyle = DEFAULT_RICH_TEXT_COLOR

    // upstream: constructor(opts?) { super(); this.attr(opts); }
    //   Modeled (per the Image/TSpan/Path port convention) by routing the opts through the overridden
    //   `_init` (which types the `style` key as TextStyleProps); `super.init(opts)` reaches `_init`.
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "text"
    }

    internal override func _init(_ props: ElementProps? = nil) {  // upstream: protected (inherited)
        let keysArr = util.keys(props ?? [:])
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            let value = props?[key]
            if key == "style" {
                if let s = value as? TextStyleProps {
                    self.useStyle(s)
                }
                else {
                    // PORT-TODO: non-TextStyleProps `style` value — fall back to empty style.
                    self.useStyle(TextStyleProps())
                }
            }
            else {
                super.attrKV(key, value)
            }
        }
        // Give a empty style
        if self.textStyle == nil {
            self.useStyle(TextStyleProps())
        }
    }

    /// Create a style object with default values in it's prototype.
    /// @override (OVERLOAD of Displayable.createStyle(CommonStyleProps?))
    // upstream: ZRText inherits Displayable.createStyle = createObject(DEFAULT_COMMON_STYLE, obj),
    //   typed via generics as TextStyleProps. Modeled here: seed the DEFAULT_COMMON_STYLE subset +
    //   magic, then extend `obj`.
    public func createStyle(_ obj: TextStyleProps? = nil) -> TextStyleProps {
        var style = TextStyleProps()
        style.shadowBlur = 0
        style.shadowOffsetX = 0
        style.shadowOffsetY = 0
        style.shadowColor = "#000"
        style.opacity = 1
        // PORT-TODO: DEFAULT_COMMON_STYLE.blend ('source-over') has no field on TextStyleProps.
        style.zrStyleMagic = true
        if let obj = obj {
            extendTextStyle(&style, obj)
        }
        return style
    }

    /// Replace style property. OVERLOAD of Displayable.useStyle(CommonStyleProps).
    public func useStyle(_ obj: TextStyleProps) {
        var obj = obj
        if !obj.zrStyleMagic {
            obj = self.createStyle(obj)
        }
        self.textStyle = obj
        self._syncCommonStyle()
        self.dirtyStyle()
    }

    // Mirror the CommonStyleProps subset of `textStyle` into the inherited `Displayable.style` so the
    // inherited machinery (shouldBePainted / getPaintRect) reads correct shadow / opacity.
    // PORT-TODO: a Swift-only bridge — upstream has a single `this.style` object.
    private func _syncCommonStyle() {
        var c = CommonStyleProps()
        c.shadowBlur = self.textStyle.shadowBlur
        c.shadowOffsetX = self.textStyle.shadowOffsetX
        c.shadowOffsetY = self.textStyle.shadowOffsetY
        c.shadowColor = self.textStyle.shadowColor
        c.opacity = self.textStyle.opacity
        c.zrStyleMagic = self.textStyle.zrStyleMagic
        self.style = c
    }

    public func childrenRef() -> [Element] {
        return self._children
    }

    public override func update() {

        super.update()

        // Update children
        if self.styleChanged() {

            // PENDING: (See HOVER_LAYER_CONSTRAINTS_TEXT)
            // let originalStyle; const hoverStyle = this.__hoverStyle; ...

            self._updateSubTexts()

            // if (hoverStyle) { this.style = originalStyle; }
        }

        for i in 0..<self._children.count {
            let child = self._children[i]
            // Set common properties.
            child.zlevel = self.zlevel
            child.z = self.z
            child.z2 = self.z2
            child.culling = self.culling
            child.cursor = self.cursor
            child.invisible = self.invisible

            // PENDING: (See HOVER_LAYER_CONSTRAINTS_TEXT)
            // child.__inHover = this.__inHover;
        }
    }

    public override func updateTransform() {
        let innerTransformable = self.innerTransformable
        if let innerTransformable = innerTransformable {
            innerTransformable.updateTransform()
            if innerTransformable.transform != nil {
                self.transform = innerTransformable.transform
            }
        }
        else {
            super.updateTransform()
        }
    }

    public override func getLocalTransform(_ m: MatrixArray? = nil) -> MatrixArray {
        let innerTransformable = self.innerTransformable
        return innerTransformable != nil
            ? innerTransformable!.getLocalTransform(m)
            : super.getLocalTransform(m)
    }

    // TODO override setLocalTransform?
    public override func getComputedTransform() -> MatrixArray? {
        if let host = self.__hostTarget {
            // Update host target transform
            _ = host.getComputedTransform()
            // Update text position.
            host.updateInnerText(true)
        }

        return super.getComputedTransform()
    }

    private func _updateSubTexts() {
        // Reset child visit cursor
        self._childCursor = 0

        var s = self.textStyle!
        _ = normalizeTextStyle(&s)
        self.textStyle = s
        if self.textStyle.rich != nil {
            self._updateRichTexts()
        }
        else {
            self._updatePlainTexts()
        }

        // this._children.length = this._childCursor;
        if self._childCursor < self._children.count {
            self._children.removeSubrange(self._childCursor ..< self._children.count)
        }

        self.styleUpdated()
    }

    public override func addSelfToZr(_ zr: ZRenderType) {
        super.addSelfToZr(zr)
        for i in 0..<self._children.count {
            // Also need mount __zr for case like hover detection.
            self._children[i].__zr = zr
        }
    }

    public override func removeSelfFromZr(_ zr: ZRenderType) {
        super.removeSelfFromZr(zr)
        for i in 0..<self._children.count {
            self._children[i].__zr = nil
        }
    }

    public override func getBoundingRect() -> BoundingRect? {
        if self.styleChanged() {
            self._updateSubTexts()
        }
        if self._rect == nil {
            // TODO: Optimize when using width and overflow: wrap/truncate
            let tmpRect = BoundingRect(0, 0, 0, 0)
            let children = self._children
            let tmpMat: MatrixArray = []
            var rect: BoundingRect? = nil

            for i in 0..<children.count {
                let child = children[i]
                let childRect = child.getBoundingRect()
                let transform = child.getLocalTransform(tmpMat)

                // upstream `getLocalTransform` always returns a matrix (truthy); the empty-array case
                //   below is effectively dead, kept structurally for diffability.
                if !transform.isEmpty {
                    if let childRect = childRect {
                        tmpRect.copy(childRect)
                    }
                    tmpRect.applyTransform(transform)
                    rect = rect ?? tmpRect.clone()
                    rect!.union(tmpRect)
                }
                else {
                    if let childRect = childRect {
                        rect = rect ?? childRect.clone()
                        rect!.union(childRect)
                    }
                }
            }
            self._rect = rect ?? tmpRect
        }
        return self._rect
    }

    /// Can be set in Element. To calculate text fill automatically when textContent is inside element
    public func setDefaultTextStyle(_ defaultTextStyle: DefaultTextStyle?) {
        // Use builtin if defaultTextStyle is not given.
        self._defaultStyle = defaultTextStyle ?? DEFAULT_RICH_TEXT_COLOR
    }

    // upstream: setTextContent(textContent: never) — throws in dev: can't attach text on text.
    public override func setTextContent(_ textEl: ZRText?) {
        // PORT-TODO: dev-mode guard — upstream throws 'Can\'t attach text on another text'.
    }

    // getDefaultStyleValue<T>(key): on the prototype — commented out upstream.

    // upstream: protected _mergeStyle(targetStyle: TextStyleProps, sourceStyle: TextStyleProps)
    //   OVERLOAD (not override) of Displayable._mergeStyle(inout CommonStyleProps, CommonStyleProps)
    //   — different param/return types. Used by the (deferred) states machinery.
    @discardableResult
    internal func _mergeStyle(_ targetStyle: TextStyleProps, _ sourceStyle: TextStyleProps?) -> TextStyleProps {
        guard let sourceStyle = sourceStyle else {
            return targetStyle
        }
        var targetStyle = targetStyle

        // DO deep merge on rich configurations.
        let sourceRich = sourceStyle.rich
        // Create a new one if source have rich but target don't
        var targetRich = targetStyle.rich ?? (sourceRich != nil ? [:] : nil)

        extendTextStyle(&targetStyle, sourceStyle)

        if let sourceRich = sourceRich, targetRich != nil {
            // merge rich and assign rich again.
            self._mergeRich(&targetRich!, sourceRich)
            targetStyle.rich = targetRich
        }
        else if targetRich != nil {
            // If source rich not exists. DON'T override the target rich
            targetStyle.rich = targetRich
        }

        return targetStyle
    }

    private func _mergeRich(_ targetRich: inout [String: TextStylePropsPart], _ sourceRich: [String: TextStylePropsPart]) {
        let richNames = util.keys(sourceRich)
        // Merge by rich names.
        for i in 0..<richNames.count {
            let richName = richNames[i]
            var t = targetRich[richName] ?? TextStylePropsPart()
            extendTextStylePart(&t, sourceRich[richName]!)
            targetRich[richName] = t
        }
    }

    public override func getAnimationStyleProps() -> [String: Any] {
        return DEFAULT_TEXT_ANIMATION_PROPS
    }

    // upstream: overloaded private _getOrCreateChild(Ctor) for TSpan / ZRImage / Rect.
    //   Modeled as a generic over a factory closure. Reuses the child at the cursor if it is of the
    //   requested type, otherwise creates a new one.
    private func _getOrCreateChild<T: Displayable>(_ create: () -> T) -> T {
        let existing: Displayable? = self._childCursor < self._children.count
            ? self._children[self._childCursor] : nil
        let child: T
        if let existing = existing, existing is T {
            child = existing as! T
        }
        else {
            child = create()
        }
        // this._children[this._childCursor++] = child;
        if self._childCursor < self._children.count {
            self._children[self._childCursor] = child
        }
        else {
            self._children.append(child)
        }
        self._childCursor += 1
        child.__zr = self.__zr
        // TODO to users parent can only be group.
        child.parent = self
        return child
    }

    private func _updatePlainTexts() {
        let style = self.textStyle!
        let textFont = strOr(style.font, DEFAULT_FONT)        // style.font || DEFAULT_FONT
        let textPadding = asNumberArray(style.padding)        // style.padding as number[]

        let defaultStyle = self._defaultStyle
        var baseX = style.x ?? 0
        var baseY = style.y ?? 0
        let textAlign = style.align ?? defaultStyle.align ?? .left
        let verticalAlign = style.verticalAlign ?? defaultStyle.verticalAlign ?? .top

        parseText.calcInnerTextOverflowArea(
            tmpCITOverflowAreaOut, defaultStyle.overflowRect, baseX, baseY, textAlign, verticalAlign
        )
        baseX = tmpCITOverflowAreaOut.baseX
        baseY = tmpCITOverflowAreaOut.baseY

        let text = getStyleText(style)
        let contentBlock = parseText.parsePlainText(
            text,
            style,
            tmpCITOverflowAreaOut.outerWidth,
            tmpCITOverflowAreaOut.outerHeight
        )
        let needDrawBg = needDrawBackground(style)
        let bgColorDrawn = (style.backgroundColor != nil)

        let outerHeight = contentBlock.outerHeight
        let outerWidth = contentBlock.outerWidth

        let textLines = contentBlock.lines
        let lineHeight = contentBlock.lineHeight

        self.isTruncated = contentBlock.isTruncated

        var textX = baseX
        var textY = ZRenderKit.text.adjustTextY(baseY, contentBlock.contentHeight, verticalAlign)

        if needDrawBg || textPadding != nil {
            // Consider performance, do not call getTextWidth util necessary.
            let boxX = ZRenderKit.text.adjustTextX(baseX, outerWidth, textAlign)
            let boxY = ZRenderKit.text.adjustTextY(baseY, outerHeight, verticalAlign)
            if needDrawBg {
                self._renderBackground(style, style, boxX, boxY, outerWidth, outerHeight)
            }
        }
        // PENDING: bounding rect & padding/width/height (see upstream comment).

        // `textBaseline` is set as 'middle'.
        textY += lineHeight / 2

        if let textPadding = textPadding {
            textX = getTextXForPadding(baseX, textAlign.rawValue, textPadding)
            if verticalAlign == .top {
                textY += textPadding[0]
            }
            else if verticalAlign == .bottom {
                textY -= textPadding[2]
            }
        }

        var defaultLineWidth: Double = 0
        var usingDefaultStroke = false
        var useDefaultFill = false
        let textFill: String?
        if style.fill != nil {  // 'fill' in style
            textFill = getFill(style.fill)
        }
        else {
            useDefaultFill = true
            textFill = getFill(defaultStyle.fill)
        }
        let strokeArg: String?
        if style.stroke != nil {  // 'stroke' in style
            strokeArg = style.stroke
        }
        else if !bgColorDrawn
            // See the strategy explained `_updatePlainTexts` (upstream long comment, A/B cases).
            && (!(defaultStyle.autoStroke ?? false) || useDefaultFill)
        {
            defaultLineWidth = DEFAULT_STROKE_LINE_WIDTH
            usingDefaultStroke = true
            strokeArg = defaultStyle.stroke
        }
        else {
            strokeArg = nil
        }
        let textStroke = getStroke(strokeArg)

        let hasShadow = (style.textShadowBlur ?? 0) > 0

        for i in 0..<textLines.count {
            let el = self._getOrCreateChild { TSpan() }
            // Always create new style.
            el.useStyle(el.createStyle(nil as TSpanStyleProps?))
            // upstream: subElStyle === el.style — mutated in place via `el.tspanStyle`.
            el.tspanStyle.text = textLines[i]
            el.tspanStyle.x = textX
            el.tspanStyle.y = textY
            // Always set textAlign and textBaseline (see upstream comment).
            // upstream `if (textAlign)` — textAlign always truthy here (.left fallback).
            el.tspanStyle.textAlign = textAlign.rawValue
            // Force baseline to be "middle". (see upstream comment re Microsoft YaHei)
            el.tspanStyle.textBaseline = "middle"
            el.tspanStyle.opacity = style.opacity
            // Fill after stroke so the outline will not cover the main part.
            el.tspanStyle.strokeFirst = true

            if hasShadow {
                el.tspanStyle.shadowBlur = numOr(style.textShadowBlur, 0)
                el.tspanStyle.shadowColor = strOr(style.textShadowColor, "transparent")
                el.tspanStyle.shadowOffsetX = numOr(style.textShadowOffsetX, 0)
                el.tspanStyle.shadowOffsetY = numOr(style.textShadowOffsetY, 0)
            }

            // Always override default fill and stroke value.
            el.tspanStyle.stroke = textStroke.map { .string($0) }
            el.tspanStyle.fill = textFill.map { .string($0) }

            if let textStroke = textStroke {
                _ = textStroke
                // style.lineWidth || defaultLineWidth
                let lw = style.lineWidth ?? 0
                el.tspanStyle.lineWidth = lw != 0 ? lw : defaultLineWidth
                el.tspanStyle.lineDash = style.lineDash
                el.tspanStyle.lineDashOffset = numOr(style.lineDashOffset, 0)
            }

            el.tspanStyle.font = textFont
            setSeparateFont(&el.tspanStyle, style)

            textY += lineHeight

            // Always set tspan bounding rect to guarantee consistency (see upstream long comment on
            //   whether the bounding rect should include the (auto) stroke width).
            el.setBoundingRect(parseText.tSpanCreateBoundingRect2(
                el.tspanStyle,
                contentBlock.contentWidth,
                contentBlock.calculatedLineHeight,
                usingDefaultStroke ? 0 : nil
            ))
        }
    }

    private func _updateRichTexts() {
        let style = self.textStyle!
        let defaultStyle = self._defaultStyle

        let textAlign = style.align ?? defaultStyle.align
        let verticalAlign = style.verticalAlign ?? defaultStyle.verticalAlign
        var baseX = style.x ?? 0
        var baseY = style.y ?? 0

        parseText.calcInnerTextOverflowArea(
            tmpCITOverflowAreaOut, defaultStyle.overflowRect, baseX, baseY, textAlign, verticalAlign
        )
        baseX = tmpCITOverflowAreaOut.baseX
        baseY = tmpCITOverflowAreaOut.baseY

        // TODO Only parse when text changed?
        let text = getStyleText(style)
        let contentBlock = parseText.parseRichText(
            text,
            style,
            tmpCITOverflowAreaOut.outerWidth,
            tmpCITOverflowAreaOut.outerHeight,
            textAlign
        )

        let contentWidth = contentBlock.width
        let outerWidth = contentBlock.outerWidth
        let outerHeight = contentBlock.outerHeight
        let textPadding = asNumberArray(style.padding)

        self.isTruncated = contentBlock.isTruncated

        let boxX = ZRenderKit.text.adjustTextX(baseX, outerWidth, textAlign)
        let boxY = ZRenderKit.text.adjustTextY(baseY, outerHeight, verticalAlign)
        var xLeft = boxX
        var lineTop = boxY

        if let textPadding = textPadding {
            xLeft += textPadding[3]
            lineTop += textPadding[0]
        }

        let xRight = xLeft + contentWidth

        if needDrawBackground(style) {
            self._renderBackground(style, style, boxX, boxY, outerWidth, outerHeight)
        }
        let bgColorDrawn = (style.backgroundColor != nil)

        for i in 0..<contentBlock.lines.count {
            let line = contentBlock.lines[i]
            let tokens = line.tokens
            let tokenCount = tokens.count
            let lineHeight = line.lineHeight

            var remainedWidth = line.width
            var leftIndex = 0
            var lineXLeft = xLeft
            var lineXRight = xRight
            var rightIndex = tokenCount - 1
            var token: RichTextToken

            while leftIndex < tokenCount {
                token = tokens[leftIndex]
                if !(token.align == nil || token.align == .left) {
                    break
                }
                self._placeToken(token, style, lineHeight, lineTop, lineXLeft, "left", bgColorDrawn)
                remainedWidth -= token.width
                lineXLeft += token.width
                leftIndex += 1
            }

            while rightIndex >= 0 {
                token = tokens[rightIndex]
                if !(token.align == .right) {
                    break
                }
                self._placeToken(token, style, lineHeight, lineTop, lineXRight, "right", bgColorDrawn)
                remainedWidth -= token.width
                lineXRight -= token.width
                rightIndex -= 1
            }

            // The other tokens are placed as textAlign 'center' if there is enough space.
            lineXLeft += (contentWidth - (lineXLeft - xLeft) - (xRight - lineXRight) - remainedWidth) / 2
            while leftIndex <= rightIndex {
                token = tokens[leftIndex]
                // Consider width specified by user, use 'center' rather than 'left'.
                self._placeToken(
                    token, style, lineHeight, lineTop,
                    lineXLeft + token.width / 2, "center", bgColorDrawn
                )
                lineXLeft += token.width
                leftIndex += 1
            }

            lineTop += lineHeight
        }
    }

    private func _placeToken(
        _ token: RichTextToken,
        _ style: TextStyleProps,
        _ lineHeight: Double,
        _ lineTop: Double,
        _ x: Double,
        _ textAlign: String,
        _ parentBgColorDrawn: Bool
    ) {
        var x = x
        // const tokenStyle = style.rich[token.styleName] || {};
        var tokenStyle: TextStylePropsPart = {
            if let sn = token.styleName, let r = style.rich, let ts = r[sn] {
                return ts
            }
            return TextStylePropsPart()
        }()
        // PORT-TODO: upstream mutates the SHARED rich style object (`tokenStyle.text = token.text`);
        //   Swift value semantics make this a local copy (re-set on every token anyway).
        tokenStyle.text = token.text

        // 'ctx.textBaseline' is always set as 'middle' (sake of "Microsoft YaHei" bias).
        let verticalAlign = token.verticalAlign
        var y = lineTop + lineHeight / 2
        if verticalAlign == .top {
            y = lineTop + token.height / 2
        }
        else if verticalAlign == .bottom {
            y = lineTop + lineHeight - token.height / 2
        }

        let needDrawBg = !token.isLineHolder && needDrawBackground(tokenStyle)
        if needDrawBg {
            self._renderBackground(
                tokenStyle,
                style,
                textAlign == "right"
                    ? x - token.width
                    : textAlign == "center"
                    ? x - token.width / 2
                    : x,
                y - token.height / 2,
                token.width,
                token.height
            )
        }
        let bgColorDrawn = (tokenStyle.backgroundColor != nil)

        let textPadding = token.textPadding
        if let textPadding = textPadding {
            x = getTextXForPadding(x, textAlign, textPadding)
            y -= token.height / 2 - textPadding[0] - token.innerHeight / 2
        }

        let el = self._getOrCreateChild { TSpan() }
        // Always create new style. upstream: subElStyle === el.style (mutated via `el.tspanStyle`).
        el.useStyle(el.createStyle(nil as TSpanStyleProps?))

        let defaultStyle = self._defaultStyle
        var useDefaultFill = false
        var defaultLineWidth: Double = 0
        var usingDefaultStroke = false
        let fillArg: String?
        if tokenStyle.fill != nil {       // 'fill' in tokenStyle
            fillArg = tokenStyle.fill
        }
        else if style.fill != nil {       // 'fill' in style
            fillArg = style.fill
        }
        else {
            useDefaultFill = true
            fillArg = defaultStyle.fill
        }
        let textFill = getFill(fillArg)

        let strokeArg: String?
        if tokenStyle.stroke != nil {     // 'stroke' in tokenStyle
            strokeArg = tokenStyle.stroke
        }
        else if style.stroke != nil {     // 'stroke' in style
            strokeArg = style.stroke
        }
        else if !bgColorDrawn
            && !parentBgColorDrawn
            // See the strategy explained `_updatePlainTexts`.
            && (!(defaultStyle.autoStroke ?? false) || useDefaultFill)
        {
            defaultLineWidth = DEFAULT_STROKE_LINE_WIDTH
            usingDefaultStroke = true
            strokeArg = defaultStyle.stroke
        }
        else {
            strokeArg = nil
        }
        let textStroke = getStroke(strokeArg)

        let hasShadow = (tokenStyle.textShadowBlur ?? 0) > 0
            || (style.textShadowBlur ?? 0) > 0

        el.tspanStyle.text = token.text
        el.tspanStyle.x = x
        el.tspanStyle.y = y
        if hasShadow {
            el.tspanStyle.shadowBlur = numOr(numOr(tokenStyle.textShadowBlur, style.textShadowBlur), 0)
            el.tspanStyle.shadowColor = strOr(strOrOpt(tokenStyle.textShadowColor, style.textShadowColor), "transparent")
            el.tspanStyle.shadowOffsetX = numOr(numOr(tokenStyle.textShadowOffsetX, style.textShadowOffsetX), 0)
            el.tspanStyle.shadowOffsetY = numOr(numOr(tokenStyle.textShadowOffsetY, style.textShadowOffsetY), 0)
        }

        el.tspanStyle.textAlign = textAlign
        // Force baseline to be "middle". (see upstream comment re Microsoft YaHei)
        el.tspanStyle.textBaseline = "middle"
        el.tspanStyle.font = strOr(token.font, DEFAULT_FONT)    // token.font || DEFAULT_FONT
        el.tspanStyle.opacity = util.retrieve3(tokenStyle.opacity, style.opacity, 1)

        // TODO inherit each item from top style in token style?
        setSeparateFont(&el.tspanStyle, tokenStyle)

        if let textStroke = textStroke {
            el.tspanStyle.lineWidth = util.retrieve3(tokenStyle.lineWidth, style.lineWidth, defaultLineWidth)
            el.tspanStyle.lineDash = util.retrieve2(tokenStyle.lineDash, style.lineDash)
            el.tspanStyle.lineDashOffset = numOr(style.lineDashOffset, 0)
            el.tspanStyle.stroke = .string(textStroke)
        }
        if let textFill = textFill {
            el.tspanStyle.fill = .string(textFill)
        }

        // NOTE: Should not call dirtyStyle after setBoundingRect. Or it will be cleared.
        el.setBoundingRect(parseText.tSpanCreateBoundingRect2(
            el.tspanStyle,
            token.contentWidth,
            token.contentHeight,
            usingDefaultStroke ? 0 : nil
        ))
    }

    private func _renderBackground<S: TextStylePropsPartLike, T: TextStylePropsPartLike>(
        _ style: S,
        _ topStyle: T,
        _ x: Double,
        _ y: Double,
        _ width: Double,
        _ height: Double
    ) {
        let textBackgroundColor = style.backgroundColor
        let textBorderWidth = style.borderWidth
        let textBorderColor = style.borderColor
        var bgImageSource: ImageSource? = nil
        if case .some(.image(let src)) = textBackgroundColor {
            bgImageSource = src
        }
        let isImageBg = (bgImageSource != nil)
        let isPlainOrGradientBg = (textBackgroundColor != nil) && !isImageBg
        let textBorderRadius = style.borderRadius

        var rectEl: Rect? = nil
        var imgEl: ZRImage? = nil
        if isPlainOrGradientBg
            || (style.lineHeight ?? 0) != 0
            || ((textBorderWidth ?? 0) != 0 && textBorderColor != nil)
        {
            // Background is color
            rectEl = self._getOrCreateChild { Rect() }
            rectEl!.useStyle(rectEl!.createStyle(nil as PathStyleProps?))    // Create an empty style.
            rectEl!.pathStyle.fill = nil
            var rectShape = rectEl!.shape as! RectShape
            rectShape.x = x
            rectShape.y = y
            rectShape.width = width
            rectShape.height = height
            switch textBorderRadius {
            case .none: rectShape.r = nil
            case .some(.number(let n)): rectShape.r = .number(n)
            case .some(.array(let a)): rectShape.r = .array(a)
            }
            rectEl!.shape = rectShape
            rectEl!.dirtyShape()
        }

        if isPlainOrGradientBg {
            // rectStyle.fill = textBackgroundColor as string || null
            if case .some(.string(let s)) = textBackgroundColor {
                rectEl!.pathStyle.fill = .string(s)
            }
            else {
                rectEl!.pathStyle.fill = nil
            }
            rectEl!.pathStyle.fillOpacity = util.retrieve2(style.fillOpacity, 1)
        }
        else if isImageBg {
            imgEl = self._getOrCreateChild { ZRImage() }
            // Refresh and relayout after image loaded.
            // PORT-TODO: verify capture (CONVENTIONS §8) — weak self to avoid the el→self cycle.
            imgEl!.onload = { [weak self] _ in
                self?.dirtyStyle()
            }
            imgEl!.imageStyle.image = bgImageSource
            imgEl!.imageStyle.x = x
            imgEl!.imageStyle.y = y
            imgEl!.imageStyle.width = width
            imgEl!.imageStyle.height = height
        }

        // upstream: `if (textBorderWidth && textBorderColor)` — JS treats an empty-string
        // color as falsy, so "" must not draw a border (matches needDrawBackground below).
        if (textBorderWidth ?? 0) != 0, let bc = textBorderColor, !bc.isEmpty {
            rectEl!.pathStyle.lineWidth = textBorderWidth
            rectEl!.pathStyle.stroke = .string(bc)
            rectEl!.pathStyle.strokeOpacity = util.retrieve2(style.strokeOpacity, 1)
            rectEl!.pathStyle.lineDash = style.borderDash
            rectEl!.pathStyle.lineDashOffset = numOr(style.borderDashOffset, 0)
            rectEl!.strokeContainThreshold = 0

            // Making shadow looks better.
            if rectEl!.hasFill() && rectEl!.hasStroke() {
                rectEl!.pathStyle.strokeFirst = true
                rectEl!.pathStyle.lineWidth = (rectEl!.pathStyle.lineWidth ?? 0) * 2
            }
        }

        // const commonStyle = (rectEl || imgEl).style;
        // PORT-TODO: Rect & ZRImage carry their style in different struct types (pathStyle /
        //   imageStyle); the shared common-style writes are branched instead of one assignment.
        let shadowBlur = numOr(style.shadowBlur, 0)
        let shadowColor = strOr(style.shadowColor, "transparent")
        let shadowOffsetX = numOr(style.shadowOffsetX, 0)
        let shadowOffsetY = numOr(style.shadowOffsetY, 0)
        let opacity = util.retrieve3(style.opacity, topStyle.opacity, 1)
        if let rectEl = rectEl {
            rectEl.pathStyle.shadowBlur = shadowBlur
            rectEl.pathStyle.shadowColor = shadowColor
            rectEl.pathStyle.shadowOffsetX = shadowOffsetX
            rectEl.pathStyle.shadowOffsetY = shadowOffsetY
            rectEl.pathStyle.opacity = opacity
        }
        else if let imgEl = imgEl {
            imgEl.imageStyle.shadowBlur = shadowBlur
            imgEl.imageStyle.shadowColor = shadowColor
            imgEl.imageStyle.shadowOffsetX = shadowOffsetX
            imgEl.imageStyle.shadowOffsetY = shadowOffsetY
            imgEl.imageStyle.opacity = opacity
        }
    }

    // upstream: static makeFont(style: TextStylePropsPart): string
    public static func makeFont<U: TextStylePropsPartLike>(_ style: U) -> String? {
        // FIXME in node-canvas fontWeight is before fontStyle
        // Use `fontSize` `fontFamily` to check whether font properties are defined.
        var font = ""
        if hasSeparateFont(style) {
            font = [
                zrFontStyleString(style.fontStyle),
                zrFontWeightString(style.fontWeight),
                parseFontSize(style.fontSize),
                // If font properties are defined, `fontFamily` should not be ignored.
                strOr(style.fontFamily, "sans-serif")    // style.fontFamily || 'sans-serif'
            ].joined(separator: " ")
        }
        // font && trim(font) || style.textFont || style.font
        let trimmed = font.isEmpty ? "" : font.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let tf = style.textFont, !tf.isEmpty {
            return tf
        }
        return style.font
    }
}


// upstream: const VALID_TEXT_ALIGN = {left:true, right:1, center:1};
//   const VALID_TEXT_VERTICAL_ALIGN = {top:1, bottom:1, middle:1};
//   PORT-TODO: the validation maps are moot here — `TextAlign`/`TextVerticalAlign` are closed enums,
//   so an invalid value is unrepresentable. The 'middle'→'center' / 'center'→'middle' legacy-string
//   coercions in `normalizeStyle` are dead for the same reason (kept as comments).

// upstream: const FONT_PARTS = ['fontStyle', 'fontWeight', 'fontSize', 'fontFamily']
//   — the loop in `setSeparateFont` is unrolled below.

// upstream: export function parseFontSize(fontSize: number | string)
public func parseFontSize(_ fontSize: NumberOrString?) -> String {
    if case .some(.string(let s)) = fontSize,
       s.contains("px") || s.contains("rem") || s.contains("em")
    {
        return s
    }
    // else if (!isNaN(+fontSize))
    switch fontSize {
    case .some(.number(let n)):
        if !n.isNaN { return zrNumberToString(n) + "px" }
    case .some(.string(let s)):
        // +fontSize valid → fontSize + 'px' (keep the original string form)
        if let n = Double(s), !n.isNaN { return s + "px" }
    case .none:
        break    // +undefined = NaN
    }
    return zrNumberToString(DEFAULT_FONT_SIZE) + "px"
}

// upstream: function setSeparateFont(targetStyle: TSpanStyleProps, sourceStyle: TextStylePropsPart)
//   Loop over FONT_PARTS unrolled. `null != null` guard preserved per field.
func setSeparateFont<U: TextStylePropsPartLike>(_ targetStyle: inout TSpanStyleProps, _ sourceStyle: U) {
    if sourceStyle.fontStyle != nil { targetStyle.fontStyle = sourceStyle.fontStyle }
    if sourceStyle.fontWeight != nil { targetStyle.fontWeight = sourceStyle.fontWeight }
    if let fs = sourceStyle.fontSize {
        // PORT-TODO: TSpanStyleProps.fontSize is Double; the string arm of `number | string`
        //   (e.g. '12px') can't be represented there and is dropped (svg-only field).
        if case .number(let n) = fs { targetStyle.fontSize = n }
    }
    if sourceStyle.fontFamily != nil { targetStyle.fontFamily = sourceStyle.fontFamily }
}

// upstream: export function hasSeparateFont(style): style.fontSize != null || style.fontFamily ||
//   style.fontWeight
func hasSeparateFont<U: TextStylePropsPartLike>(_ style: U) -> Bool {
    return style.fontSize != nil
        || (style.fontFamily != nil && !style.fontFamily!.isEmpty)
        || style.fontWeight != nil
}

// upstream: export function normalizeTextStyle(style: TextStyleProps): TextStyleProps
@discardableResult
func normalizeTextStyle(_ style: inout TextStyleProps) -> TextStyleProps {
    normalizeStyle(&style)
    // TODO inherit each item from top style in token style?
    // each(style.rich, normalizeStyle)
    if var rich = style.rich {
        let names = util.keys(rich)
        for i in 0..<names.count {
            var v = rich[names[i]]!
            normalizeStyle(&v)
            rich[names[i]] = v
        }
        style.rich = rich
    }
    return style
}

// upstream: function normalizeStyle(style: TextStylePropsPart)
func normalizeStyle<U: TextStylePropsPartLike>(_ style: inout U) {
    // upstream `if (style)` — `style` is a non-nil Swift value here.
    style.font = ZRText.makeFont(style)
    let textAlign = style.align
    // 'middle' is invalid, convert it to 'center' — PORT-TODO: 'middle' not representable in the
    //   TextAlign enum; the coercion is dead. VALID_TEXT_ALIGN check is moot (enum guarantees validity).
    style.align = textAlign

    // Compatible with textBaseline.
    let verticalAlign = style.verticalAlign
    // 'center' → 'middle' — PORT-TODO: 'center' not representable; dead. Validation moot.
    style.verticalAlign = verticalAlign

    // TODO Should not change the orignal value.
    if let textPadding = style.padding {
        style.padding = .array(normalizeCssArrayPadding(textPadding))
    }
}

/**
 * @param stroke If specified, do not check style.textStroke.
 * @param lineWidth If specified, do not check style.textStroke.
 */
// upstream: function getStroke(stroke?, lineWidth?)
func getStroke(_ stroke: String?, _ lineWidth: Double? = nil) -> String? {
    if stroke == nil || (lineWidth != nil && lineWidth! <= 0) || stroke == "transparent" || stroke == "none" {
        return nil
    }
    // PORT-TODO: upstream `(stroke as any).image || (stroke as any).colorStops ? '#000' : stroke` —
    //   gradient/pattern strokes return '#000'. `stroke` is typed `String` here, so that branch is
    //   unreachable (gradient/pattern text stroke not representable).
    return stroke
}

// upstream: function getFill(fill?)
func getFill(_ fill: String?) -> String? {
    if fill == nil || fill == "none" {
        return nil
    }
    // PORT-TODO: upstream `(fill as any).image || (fill as any).colorStops ? '#000' : fill` —
    //   gradient/pattern fills return '#000'. `fill` is `String` here, so that branch is unreachable.
    return fill
}

// upstream: function getTextXForPadding(x, textAlign, textPadding): number
func getTextXForPadding(_ x: Double, _ textAlign: String, _ textPadding: [Double]) -> Double {
    return textAlign == "right"
        ? (x - textPadding[1])
        : textAlign == "center"
        ? (x + textPadding[3] / 2 - textPadding[1] / 2)
        : (x + textPadding[3])
}

// upstream: function getStyleText(style: TextStylePropsPart): string
func getStyleText(_ style: TextStyleProps) -> String? {
    // Compat: set number to text is supported. set null/undefined to text is supported.
    // PORT-TODO: upstream `text += ''` coerces a number → string; `text` is already `String?` here.
    let text = style.text
    return text
}

/**
 * If needs draw background
 * @param style Style of element
 */
// upstream: function needDrawBackground(style: TextStylePropsPart): boolean
func needDrawBackground<U: TextStylePropsPartLike>(_ style: U) -> Bool {
    return style.backgroundColor != nil
        || (style.lineHeight ?? 0) != 0
        || ((style.borderWidth ?? 0) != 0 && (style.borderColor != nil && !style.borderColor!.isEmpty))
}

// ===== Swift helpers (extend / JS `||` for numbers & strings / union conversions) =====

// extend(target, source) over TextStyleProps' known fields (value-copy of non-nil fields).
// PORT-TODO: upstream `extend` copies all own enumerable keys (dynamic bag); here we copy the known
//   fields only. `rich` is copied shallowly (the deep-merge of rich is handled by `_mergeStyle`).
func extendTextStyle(_ target: inout TextStyleProps, _ source: TextStyleProps) {
    if source.text != nil { target.text = source.text }
    if source.fill != nil { target.fill = source.fill }
    if source.stroke != nil { target.stroke = source.stroke }
    if source.strokeNoScale != nil { target.strokeNoScale = source.strokeNoScale }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.fillOpacity != nil { target.fillOpacity = source.fillOpacity }
    if source.strokeOpacity != nil { target.strokeOpacity = source.strokeOpacity }
    if source.lineWidth != nil { target.lineWidth = source.lineWidth }
    if source.lineDash != nil { target.lineDash = source.lineDash }
    if source.lineDashOffset != nil { target.lineDashOffset = source.lineDashOffset }
    if source.borderDash != nil { target.borderDash = source.borderDash }
    if source.borderDashOffset != nil { target.borderDashOffset = source.borderDashOffset }
    if source.font != nil { target.font = source.font }
    if source.textFont != nil { target.textFont = source.textFont }
    if source.fontStyle != nil { target.fontStyle = source.fontStyle }
    if source.fontWeight != nil { target.fontWeight = source.fontWeight }
    if source.fontFamily != nil { target.fontFamily = source.fontFamily }
    if source.fontSize != nil { target.fontSize = source.fontSize }
    if source.align != nil { target.align = source.align }
    if source.verticalAlign != nil { target.verticalAlign = source.verticalAlign }
    if source.lineHeight != nil { target.lineHeight = source.lineHeight }
    if source.width != nil { target.width = source.width }
    if source.height != nil { target.height = source.height }
    if source.tag != nil { target.tag = source.tag }
    if source.textShadowColor != nil { target.textShadowColor = source.textShadowColor }
    if source.textShadowBlur != nil { target.textShadowBlur = source.textShadowBlur }
    if source.textShadowOffsetX != nil { target.textShadowOffsetX = source.textShadowOffsetX }
    if source.textShadowOffsetY != nil { target.textShadowOffsetY = source.textShadowOffsetY }
    if source.backgroundColor != nil { target.backgroundColor = source.backgroundColor }
    if source.padding != nil { target.padding = source.padding }
    if source.margin != nil { target.margin = source.margin }
    if source.borderColor != nil { target.borderColor = source.borderColor }
    if source.borderWidth != nil { target.borderWidth = source.borderWidth }
    if source.borderRadius != nil { target.borderRadius = source.borderRadius }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
    if source.x != nil { target.x = source.x }
    if source.y != nil { target.y = source.y }
    if source.rich != nil { target.rich = source.rich }
    if source.overflow != nil { target.overflow = source.overflow }
    if source.lineOverflow != nil { target.lineOverflow = source.lineOverflow }
    if source.ellipsis != nil { target.ellipsis = source.ellipsis }
    if source.placeholder != nil { target.placeholder = source.placeholder }
    if source.truncateMinChar != nil { target.truncateMinChar = source.truncateMinChar }
}

// extend(target, source) over TextStylePropsPart' known fields.
func extendTextStylePart(_ target: inout TextStylePropsPart, _ source: TextStylePropsPart) {
    if source.text != nil { target.text = source.text }
    if source.fill != nil { target.fill = source.fill }
    if source.stroke != nil { target.stroke = source.stroke }
    if source.strokeNoScale != nil { target.strokeNoScale = source.strokeNoScale }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.fillOpacity != nil { target.fillOpacity = source.fillOpacity }
    if source.strokeOpacity != nil { target.strokeOpacity = source.strokeOpacity }
    if source.lineWidth != nil { target.lineWidth = source.lineWidth }
    if source.lineDash != nil { target.lineDash = source.lineDash }
    if source.lineDashOffset != nil { target.lineDashOffset = source.lineDashOffset }
    if source.borderDash != nil { target.borderDash = source.borderDash }
    if source.borderDashOffset != nil { target.borderDashOffset = source.borderDashOffset }
    if source.font != nil { target.font = source.font }
    if source.textFont != nil { target.textFont = source.textFont }
    if source.fontStyle != nil { target.fontStyle = source.fontStyle }
    if source.fontWeight != nil { target.fontWeight = source.fontWeight }
    if source.fontFamily != nil { target.fontFamily = source.fontFamily }
    if source.fontSize != nil { target.fontSize = source.fontSize }
    if source.align != nil { target.align = source.align }
    if source.verticalAlign != nil { target.verticalAlign = source.verticalAlign }
    if source.lineHeight != nil { target.lineHeight = source.lineHeight }
    if source.width != nil { target.width = source.width }
    if source.height != nil { target.height = source.height }
    if source.tag != nil { target.tag = source.tag }
    if source.textShadowColor != nil { target.textShadowColor = source.textShadowColor }
    if source.textShadowBlur != nil { target.textShadowBlur = source.textShadowBlur }
    if source.textShadowOffsetX != nil { target.textShadowOffsetX = source.textShadowOffsetX }
    if source.textShadowOffsetY != nil { target.textShadowOffsetY = source.textShadowOffsetY }
    if source.backgroundColor != nil { target.backgroundColor = source.backgroundColor }
    if source.padding != nil { target.padding = source.padding }
    if source.margin != nil { target.margin = source.margin }
    if source.borderColor != nil { target.borderColor = source.borderColor }
    if source.borderWidth != nil { target.borderWidth = source.borderWidth }
    if source.borderRadius != nil { target.borderRadius = source.borderRadius }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
}

// JS `a || b` for optional numbers (both `nil` and `0` are falsy). Single overload (returns Double?)
//   — every numeric target is Optional. `b` as a `Double` literal coerces to `Double?`.
private func numOr(_ a: Double?, _ b: Double?) -> Double? {
    if let a = a, a != 0 { return a }
    return b
}
// JS `a || b` for optional strings (both `nil` and `''` are falsy).
//   `strOr` returns a non-optional `String` (the default `b` is non-optional); `strOrOpt` keeps the
//   result Optional for nesting (`strOr(strOrOpt(a, b), c)`).
private func strOr(_ a: String?, _ b: String) -> String {
    if let a = a, !a.isEmpty { return a }
    return b
}
private func strOrOpt(_ a: String?, _ b: String?) -> String? {
    if let a = a, !a.isEmpty { return a }
    return b
}

// `style.padding as number[]` — reads the (normalized) padding array.
private func asNumberArray(_ v: NumberOrNumberArray?) -> [Double]? {
    switch v {
    case .none: return nil
    case .some(.array(let a)): return a
    case .some(.number(let n)): return [n, n, n, n]    // normalized form
    }
}
private func normalizeCssArrayPadding(_ v: NumberOrNumberArray) -> [Double] {
    switch v {
    case .number(let n): return util.normalizeCssArray(n)
    case .array(let a): return util.normalizeCssArray(a)
    }
}

// `[fontStyle, fontWeight, fontSize, fontFamily].join(' ')` element stringifiers (`undefined` → '').
private func zrFontStyleString(_ s: FontStyle?) -> String {
    return s?.rawValue ?? ""
}
private func zrFontWeightString(_ w: FontWeight?) -> String {
    switch w {
    case .none: return ""
    case .some(.normal): return "normal"
    case .some(.bold): return "bold"
    case .some(.bolder): return "bolder"
    case .some(.lighter): return "lighter"
    case .some(.number(let n)): return zrNumberToString(n)
    }
}
private func zrNumberToString(_ n: Double) -> String {
    if n.isFinite && n == n.rounded() { return String(Int(n)) }
    return String(n)
}

// upstream: export default ZRText;


// ============================================================================================
// PORT-TODO SEAM STUB — graphic/helper/parseText.ts (NOT yet ported).
//   The full layout engine (wrap / truncate / rich-text token measurement) lives upstream in
//   `graphic/helper/parseText.ts`. Until `Graphic/Helper/parseText.swift` is ported, this fence
//   provides the minimal surface `ZRText` consumes. REMOVE this whole block when parseText lands.
// ============================================================================================

// upstream: export type CalcInnerTextOverflowAreaOut = { baseX; baseY; outerWidth?; outerHeight? }
//   Modeled as a `final class` (reused mutable object, reference semantics — see upstream
//   `tmpCITOverflowAreaOut`).
public final class CalcInnerTextOverflowAreaOut {
    public var baseX: Double = 0
    public var baseY: Double = 0
    // Calculated outer size based on overflowRect. NaN/nil indicates "don't draw".
    public var outerWidth: Double?
    public var outerHeight: Double?
    public init() {}
}

// upstream: export interface PlainTextContentBlock (graphic/helper/parseText.ts)
public final class PlainTextContentBlock {
    public var lineHeight: Double = 0
    public var calculatedLineHeight: Double = 0
    public var contentWidth: Double = 0
    public var contentHeight: Double = 0
    public var width: Double = 0
    public var height: Double = 0
    public var outerWidth: Double = 0
    public var outerHeight: Double = 0
    public var lines: [String] = []
    public var isTruncated: Bool = false
    public init() {}
}

// upstream: class RichTextToken (graphic/helper/parseText.ts)
public final class RichTextToken {
    public var styleName: String?
    public var text: String = ""
    public var width: Double = 0
    public var height: Double = 0
    public var innerHeight: Double = 0
    public var contentHeight: Double = 0
    public var contentWidth: Double = 0
    public var lineHeight: Double = 0
    public var font: String = ""
    public var align: TextAlign?
    public var verticalAlign: TextVerticalAlign?
    public var textPadding: [Double]?
    public var percentWidth: String?
    public var isLineHolder: Bool = false
    public init() {}
}
// upstream: class RichTextLine
public final class RichTextLine {
    public var lineHeight: Double = 0
    public var width: Double = 0
    public var tokens: [RichTextToken] = []
    public init() {}
}
// upstream: export class RichTextContentBlock
public final class RichTextContentBlock {
    public var width: Double = 0
    public var height: Double = 0
    public var contentWidth: Double = 0
    public var contentHeight: Double = 0
    public var outerWidth: Double = 0
    public var outerHeight: Double = 0
    public var lines: [RichTextLine] = []
    public var isTruncated: Bool = false
    public init() {}
}

// upstream free-function module → caseless `enum` namespace (CONVENTIONS §2). Imported in Text.ts as
//   `import { parsePlainText, parseRichText, ... } from './helper/parseText'` → `parseText.*`.
public enum parseText {

    // upstream: const STYLE_REG = /\{([a-zA-Z0-9_]+)\|([^}]*)\}/g
    //   Token syntax: `{styleName|content}`. styleName ∈ [A-Za-z0-9_]+, content = any non-`}` run.
    fileprivate static let STYLE_REG = try! NSRegularExpression(
        pattern: "\\{([a-zA-Z0-9_]+)\\|([^}]*)\\}"
    )

    // ---- truncate -------------------------------------------------------------------------------

    // upstream: interface InnerPreparedTruncateOption (the prepared options bag).
    fileprivate final class PreparedTruncateOption {
        var maxIterations: Int = 2
        var minChar: Int = 0
        var placeholder: String = ""
        var ellipsis: String = ""
        var ellipsisWidth: Double = 0
        var contentWidth: Double = 0
        var containerWidth: Double = 0
        var fontMeasureInfo: FontMeasureInfo!
        init() {}
    }

    fileprivate struct TruncateLineOut {
        var textLine: String = ""
        var isTruncated: Bool = false
    }

    fileprivate struct TruncateOut {
        var text: String = ""
        var isTruncated: Bool = false
    }

    // upstream: export function truncateText(text, containerWidth, font, ellipsis?, options?): string
    public static func truncateText(
        _ text: String,
        _ containerWidth: Double,
        _ font: String?,
        _ ellipsis: String? = nil,
        _ minChar: Int? = nil,
        _ placeholder: String? = nil,
        _ maxIterations: Int? = nil
    ) -> String {
        var out = TruncateOut()
        truncateText2(&out, text, containerWidth, font, ellipsis, minChar, placeholder, maxIterations)
        return out.text
    }

    // upstream: function truncateText2(out, text, containerWidth, font, ellipsis?, options?): void
    fileprivate static func truncateText2(
        _ out: inout TruncateOut,
        _ text: String,
        _ containerWidth: Double,
        _ font: String?,
        _ ellipsis: String?,
        _ minChar: Int?,
        _ placeholder: String?,
        _ maxIterations: Int?
    ) {
        // upstream `if (!containerWidth)` — JS falsy: 0/NaN.
        if containerWidth == 0 || containerWidth.isNaN {
            out.text = ""
            out.isTruncated = false
            return
        }

        var textLines = text.components(separatedBy: "\n")
        let options = prepareTruncateOptions(containerWidth, font, ellipsis, minChar, placeholder, maxIterations)

        // FIXME (upstream): every line gets '...' when truncating multiple lines.
        var isTruncated = false
        var truncateOut = TruncateLineOut()
        for i in 0..<textLines.count {
            truncateSingleLine(&truncateOut, textLines[i], options)
            textLines[i] = truncateOut.textLine
            isTruncated = isTruncated || truncateOut.isTruncated
        }

        out.text = textLines.joined(separator: "\n")
        out.isTruncated = isTruncated
    }

    // upstream: function prepareTruncateOptions(containerWidth, font, ellipsis?, options?)
    fileprivate static func prepareTruncateOptions(
        _ containerWidth: Double,
        _ font: String?,
        _ ellipsis: String?,
        _ minChar: Int?,
        _ placeholder: String?,
        _ maxIterations: Int?
    ) -> PreparedTruncateOption {
        let preparedOpts = PreparedTruncateOption()

        var ellipsis = ellipsis ?? "..."   // retrieve2(ellipsis, '...')
        preparedOpts.maxIterations = maxIterations ?? 2
        let minChar = minChar ?? 0
        preparedOpts.minChar = minChar
        let fontMeasureInfo = ZRenderKit.text.ensureFontMeasureInfo(font)
        preparedOpts.fontMeasureInfo = fontMeasureInfo
        let ascCharWidth = fontMeasureInfo.asciiCharWidth
        preparedOpts.placeholder = placeholder ?? ""

        // Example 1: minChar: 3, text: 'asdfzxcv', truncate result: 'asdf', but not: 'a...'.
        // Example 2: minChar: 3, text: '维度', truncate result: '维', but not: '...'.
        let containerWidth = Swift.max(0, containerWidth - 1)   // Reserve some gap.
        var contentWidth = containerWidth
        var i = 0
        while i < minChar && contentWidth >= ascCharWidth {
            contentWidth -= ascCharWidth
            i += 1
        }

        var ellipsisWidth = ZRenderKit.text.measureWidth(fontMeasureInfo, ellipsis)
        if ellipsisWidth > contentWidth {
            ellipsis = ""
            ellipsisWidth = 0
        }

        contentWidth = containerWidth - ellipsisWidth

        preparedOpts.ellipsis = ellipsis
        preparedOpts.ellipsisWidth = ellipsisWidth
        preparedOpts.contentWidth = contentWidth
        preparedOpts.containerWidth = containerWidth

        return preparedOpts
    }

    // upstream: function truncateSingleLine(out, textLine, options): void
    fileprivate static func truncateSingleLine(
        _ out: inout TruncateLineOut,
        _ textLine: String,
        _ options: PreparedTruncateOption
    ) {
        let containerWidth = options.containerWidth
        let contentWidth = options.contentWidth
        let fontMeasureInfo = options.fontMeasureInfo!

        if containerWidth == 0 || containerWidth.isNaN {
            out.textLine = ""
            out.isTruncated = false
            return
        }

        var textLine = textLine
        var lineWidth = ZRenderKit.text.measureWidth(fontMeasureInfo, textLine)

        if lineWidth <= containerWidth {
            out.textLine = textLine
            out.isTruncated = false
            return
        }

        var j = 0
        while true {
            if lineWidth <= contentWidth || j >= options.maxIterations {
                textLine += options.ellipsis
                break
            }

            let subLength = j == 0
                ? estimateLength(textLine, contentWidth, fontMeasureInfo)
                : (lineWidth > 0
                    ? Int(Foundation.floor(Double(textLine.count) * contentWidth / lineWidth))
                    : 0)

            // textLine.substr(0, subLength)
            textLine = String(textLine.prefix(subLength))
            lineWidth = ZRenderKit.text.measureWidth(fontMeasureInfo, textLine)
            j += 1
        }

        if textLine == "" {
            textLine = options.placeholder
        }

        out.textLine = textLine
        out.isTruncated = true
    }

    // upstream: function estimateLength(text, contentWidth, fontMeasureInfo): number
    fileprivate static func estimateLength(
        _ text: String,
        _ contentWidth: Double,
        _ fontMeasureInfo: FontMeasureInfo
    ) -> Int {
        var width: Double = 0
        var i = 0
        // Iterate by UTF-16 code units to match JS `charCodeAt`/`.length` semantics.
        let units = Array(text.utf16)
        while i < units.count && width < contentWidth {
            width += ZRenderKit.text.measureCharWidth(fontMeasureInfo, Double(units[i]))
            i += 1
        }
        return i
    }

    // ---- plain text -----------------------------------------------------------------------------

    // upstream: export function parsePlainText(rawText, style, defaultOuterWidth, defaultOuterHeight)
    public static func parsePlainText(
        _ rawText: String?,
        _ style: TextStyleProps,
        _ defaultOuterWidth: Double?,
        _ defaultOuterHeight: Double?
    ) -> PlainTextContentBlock {
        let text = rawText ?? ""    // formatText

        // textPadding has been normalized
        let overflow = style.overflow
        let padding = asNumberArray(style.padding)
        let paddingH = padding != nil ? padding![1] + padding![3] : 0
        let paddingV = padding != nil ? padding![0] + padding![2] : 0
        let font = style.font
        let truncate = overflow == "truncate"
        let calculatedLineHeight = ZRenderKit.text.getLineHeight(font)
        let lineHeight = style.lineHeight ?? calculatedLineHeight

        let truncateLineOverflow = style.lineOverflow == "truncate"
        var isTruncated = false

        var width = style.width
        if width == nil, let dw = defaultOuterWidth {
            width = dw - paddingH
        }
        var height = style.height
        if height == nil, let dh = defaultOuterHeight {
            height = dh - paddingV
        }

        var lines: [String]
        if let width = width, overflow == "break" || overflow == "breakAll" {
            lines = text.isEmpty
                ? []
                : wrapText(text, style.font, width, overflow == "breakAll", 0).lines
        }
        else {
            lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        }

        var contentHeight = Double(lines.count) * lineHeight
        if height == nil {
            height = contentHeight
        }

        // Truncate lines.
        if contentHeight > height! && truncateLineOverflow {
            let lineCount = Int(Foundation.floor(height! / lineHeight))

            isTruncated = isTruncated || (lines.count > lineCount)
            lines = Array(lines.prefix(Swift.max(0, lineCount)))
            contentHeight = Double(lines.count) * lineHeight
            // TODO (upstream): show ellipsis for line truncate.
        }

        if !text.isEmpty && truncate, let width = width {
            let options = prepareTruncateOptions(
                width, font, style.ellipsis,
                style.truncateMinChar.map { Int($0) }, style.placeholder, nil
            )
            // Having every line has '...' when truncate multiple lines.
            var singleOut = TruncateLineOut()
            for i in 0..<lines.count {
                truncateSingleLine(&singleOut, lines[i], options)
                lines[i] = singleOut.textLine
                isTruncated = isTruncated || singleOut.isTruncated
            }
        }

        // Calculate real text width and height
        var outerHeight = height!
        var contentWidth: Double = 0
        let fontMeasureInfo = ZRenderKit.text.ensureFontMeasureInfo(font)
        for i in 0..<lines.count {
            contentWidth = Swift.max(ZRenderKit.text.measureWidth(fontMeasureInfo, lines[i]), contentWidth)
        }
        if width == nil {
            // When width is not explicitly set, use contentWidth as width.
            width = contentWidth
        }

        var outerWidth = width!
        outerHeight += paddingV
        outerWidth += paddingH

        let block = PlainTextContentBlock()
        block.lines = lines
        block.height = height!
        block.outerWidth = outerWidth
        block.outerHeight = outerHeight
        block.lineHeight = lineHeight
        block.calculatedLineHeight = calculatedLineHeight
        block.contentWidth = contentWidth
        block.contentHeight = contentHeight
        block.width = width!
        block.isTruncated = isTruncated
        return block
    }

    // ---- rich text ------------------------------------------------------------------------------

    // upstream: type WrapInfo = { width, accumWidth, breakAll }
    fileprivate final class WrapInfo {
        var width: Double
        var accumWidth: Double
        var breakAll: Bool
        init(_ width: Double, _ accumWidth: Double, _ breakAll: Bool) {
            self.width = width; self.accumWidth = accumWidth; self.breakAll = breakAll
        }
    }

    // upstream: export function parseRichText(rawText, style, defaultOuterWidth, defaultOuterHeight,
    //   topTextAlign): RichTextContentBlock
    public static func parseRichText(
        _ rawText: String?,
        _ style: TextStyleProps,
        _ defaultOuterWidth: Double?,
        _ defaultOuterHeight: Double?,
        _ topTextAlign: TextAlign?
    ) -> RichTextContentBlock {
        let contentBlock = RichTextContentBlock()

        let text = rawText ?? ""    // formatText
        if text.isEmpty {
            return contentBlock
        }

        let stlPadding = asNumberArray(style.padding)
        let stlPaddingH = stlPadding != nil ? stlPadding![1] + stlPadding![3] : 0
        let stlPaddingV = stlPadding != nil ? stlPadding![0] + stlPadding![2] : 0

        var topWidth = style.width
        if topWidth == nil, let dw = defaultOuterWidth {
            topWidth = dw - stlPaddingH
        }
        var topHeight = style.height
        if topHeight == nil, let dh = defaultOuterHeight {
            topHeight = dh - stlPaddingV
        }

        let overflow = style.overflow
        let wrapInfo: WrapInfo? = (overflow == "break" || overflow == "breakAll") && topWidth != nil
            ? WrapInfo(topWidth!, 0, overflow == "breakAll")
            : nil

        // Tokenize: walk STYLE_REG matches over UTF-16 ranges (JS `.lastIndex`/`.index`).
        let ns = text as NSString
        var lastIndex = 0
        STYLE_REG.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { result, _, _ in
            guard let result = result else { return }
            let matchedIndex = result.range.location
            if matchedIndex > lastIndex {
                pushTokens(contentBlock,
                           ns.substring(with: NSRange(location: lastIndex, length: matchedIndex - lastIndex)),
                           style, wrapInfo, nil)
            }
            let styleName = ns.substring(with: result.range(at: 1))
            let content = ns.substring(with: result.range(at: 2))
            pushTokens(contentBlock, content, style, wrapInfo, styleName)
            lastIndex = result.range.location + result.range.length
        }

        if lastIndex < ns.length {
            pushTokens(contentBlock,
                       ns.substring(with: NSRange(location: lastIndex, length: ns.length - lastIndex)),
                       style, wrapInfo, nil)
        }

        // For `textWidth: xx%`
        var pendingList: [RichTextToken] = []

        var calculatedHeight: Double = 0
        var calculatedWidth: Double = 0

        let truncate = overflow == "truncate"
        let truncateLine = style.lineOverflow == "truncate"
        var tmpTruncateOut = TruncateOut()

        func finishLine(_ line: RichTextLine, _ lineWidth: Double, _ lineHeight: Double) {
            line.width = lineWidth
            line.lineHeight = lineHeight
            calculatedHeight += lineHeight
            calculatedWidth = Swift.max(calculatedWidth, lineWidth)
        }

        // Calculate layout info of tokens.
        outer: for i in 0..<contentBlock.lines.count {
            let line = contentBlock.lines[i]
            var lineHeight: Double = 0
            var lineWidth: Double = 0

            for j in 0..<line.tokens.count {
                let token = line.tokens[j]
                let tokenStyle: TextStylePropsPart? = token.styleName.flatMap { style.rich?[$0] }
                // textPadding should not inherit from style.
                let textPadding = asNumberArray(tokenStyle?.padding)
                token.textPadding = textPadding
                let paddingH = textPadding != nil ? textPadding![1] + textPadding![3] : 0

                let font = strOrOpt(tokenStyle?.font, style.font)
                token.font = font ?? ""

                token.contentHeight = ZRenderKit.text.getLineHeight(font)
                // textHeight can be used when textVerticalAlign is specified in token.
                var tokenHeight = tokenStyle?.height ?? token.contentHeight
                token.innerHeight = tokenHeight

                if let tp = textPadding { tokenHeight += tp[0] + tp[2] }
                token.height = tokenHeight
                // Include padding in lineHeight.
                token.lineHeight = tokenStyle?.lineHeight ?? style.lineHeight ?? tokenHeight

                token.align = tokenStyle?.align ?? topTextAlign
                token.verticalAlign = tokenStyle?.verticalAlign ?? .middle

                if truncateLine, let th = topHeight, calculatedHeight + token.lineHeight > th {
                    let originalLength = contentBlock.lines.count
                    if j > 0 {
                        line.tokens = Array(line.tokens.prefix(j))
                        finishLine(line, lineWidth, lineHeight)
                        contentBlock.lines = Array(contentBlock.lines.prefix(i + 1))
                    }
                    else {
                        contentBlock.lines = Array(contentBlock.lines.prefix(i))
                    }
                    contentBlock.isTruncated = contentBlock.isTruncated || (contentBlock.lines.count < originalLength)
                    break outer
                }

                let styleTokenWidth = tokenStyle?.width
                // tokenWidthNotSpecified: width == null || width === 'auto'
                let tokenWidthNotSpecified: Bool
                switch styleTokenWidth {
                case .none: tokenWidthNotSpecified = true
                case .some(.string(let s)): tokenWidthNotSpecified = (s == "auto")
                case .some(.number): tokenWidthNotSpecified = false
                }

                // Percent width: '100%' style — drawn separately when box width is auto.
                if case .some(.string(let s)) = styleTokenWidth, s.hasSuffix("%") {
                    token.percentWidth = s
                    pendingList.append(token)
                    token.contentWidth = ZRenderKit.text.measureWidth(ZRenderKit.text.ensureFontMeasureInfo(font), token.text)
                    // Do not truncate in this case.
                }
                else {
                    if tokenWidthNotSpecified {
                        // FIXME (upstream): if bg image not loaded and textWidth not specified,
                        //   getBoundingRect() will be incorrect.
                        // PORT-TODO: the `backgroundColor.image` → token-width-from-image-size branch
                        //   needs the image-loading seam (imageHelper.findExistImage / isImageReady),
                        //   which is the canvas/browser image cache (CONVENTIONS §9), not ported.
                        //   Token width falls back to its measured text width below.
                    }

                    let remainTruncWidth: Double? = (truncate && topWidth != nil) ? topWidth! - lineWidth : nil

                    if let remain = remainTruncWidth, remain < token.width {
                        if !tokenWidthNotSpecified || remain < paddingH {
                            token.text = ""
                            token.width = 0
                            token.contentWidth = 0
                        }
                        else {
                            truncateText2(
                                &tmpTruncateOut,
                                token.text, remain - paddingH, font, style.ellipsis,
                                style.truncateMinChar.map { Int($0) }, nil, nil
                            )
                            token.text = tmpTruncateOut.text
                            contentBlock.isTruncated = contentBlock.isTruncated || tmpTruncateOut.isTruncated
                            let w = ZRenderKit.text.measureWidth(ZRenderKit.text.ensureFontMeasureInfo(font), token.text)
                            token.width = w
                            token.contentWidth = w
                        }
                    }
                    else {
                        token.contentWidth = ZRenderKit.text.measureWidth(ZRenderKit.text.ensureFontMeasureInfo(font), token.text)
                    }
                }

                token.width += paddingH

                lineWidth += token.width
                // upstream `tokenStyle && (lineHeight = ...)` — but token.lineHeight is set
                //   regardless; matching the observable max.
                lineHeight = Swift.max(lineHeight, token.lineHeight)
            }

            finishLine(line, lineWidth, lineHeight)
        }

        contentBlock.width = topWidth ?? calculatedWidth
        contentBlock.outerWidth = contentBlock.width
        contentBlock.height = topHeight ?? calculatedHeight
        contentBlock.outerHeight = contentBlock.height
        contentBlock.contentHeight = calculatedHeight
        contentBlock.contentWidth = calculatedWidth

        contentBlock.outerWidth += stlPaddingH
        contentBlock.outerHeight += stlPaddingV

        for token in pendingList {
            if let percentWidth = token.percentWidth {
                // parseInt(percentWidth, 10) / 100 * contentBlock.width
                let pct = color.parseInt(percentWidth, 10) / 100
                token.width = pct * contentBlock.width
            }
        }

        return contentBlock
    }

    // upstream: function pushTokens(block, str, style, wrapInfo, styleName?)
    fileprivate static func pushTokens(
        _ block: RichTextContentBlock,
        _ str: String,
        _ style: TextStyleProps,
        _ wrapInfo: WrapInfo?,
        _ styleName: String?
    ) {
        let isEmptyStr = (str == "")
        let tokenStyle: TextStylePropsPart? = styleName.flatMap { style.rich?[$0] }
        let lines = block.lines        // reference to the array's class elements; we mutate `block.lines`
        let font = strOrOpt(tokenStyle?.font, style.font)
        var newLine = false
        var strLines: [String]? = nil
        var linesWidths: [Double]? = nil

        if let wrapInfo = wrapInfo {
            let tokenPadding = asNumberArray(tokenStyle?.padding)
            let tokenPaddingH = tokenPadding != nil ? tokenPadding![1] + tokenPadding![3] : 0
            // tokenStyle.width != null && tokenStyle.width !== 'auto'
            var fixedWidth = false
            if case .some(.number) = tokenStyle?.width { fixedWidth = true }
            if case .some(.string(let s)) = tokenStyle?.width, s != "auto" { fixedWidth = true }

            if fixedWidth {
                // Wrap the whole token if tokenWidth is fixed.
                let widthVal: NumberOrString = tokenStyle!.width!
                let outerWidth = ZRenderKit.text.parsePercent(widthVal, wrapInfo.width) + tokenPaddingH
                if lines.count > 0 {   // Not first line
                    if outerWidth + wrapInfo.accumWidth > wrapInfo.width {
                        // TODO (upstream): support wrap text in token.
                        strLines = str.components(separatedBy: "\n")
                        newLine = true
                    }
                }
                wrapInfo.accumWidth = outerWidth
            }
            else {
                let res = wrapText(str, font, wrapInfo.width, wrapInfo.breakAll, wrapInfo.accumWidth)
                wrapInfo.accumWidth = res.accumWidth + tokenPaddingH
                linesWidths = res.linesWidths
                strLines = res.lines
            }
        }

        if strLines == nil {
            strLines = str.components(separatedBy: "\n")
        }

        let fontMeasureInfo = ZRenderKit.text.ensureFontMeasureInfo(font)
        for i in 0..<strLines!.count {
            let text = strLines![i]
            let token = RichTextToken()
            token.styleName = styleName
            token.text = text
            token.isLineHolder = text.isEmpty && !isEmptyStr

            if case .some(.number(let w)) = tokenStyle?.width {
                token.width = w
            }
            else {
                token.width = linesWidths != nil
                    ? linesWidths![i]   // Calculated width in the wrap
                    : ZRenderKit.text.measureWidth(fontMeasureInfo, text)
            }

            // The first token should be appended to the last line if not new line.
            if i == 0 && !newLine {
                // (lines[lines.length - 1] || (lines[0] = new RichTextLine())).tokens
                if block.lines.isEmpty {
                    block.lines.append(RichTextLine())
                }
                let lastLine = block.lines[block.lines.count - 1]
                let tokensLen = lastLine.tokens.count
                if tokensLen == 1 && lastLine.tokens[0].isLineHolder {
                    lastLine.tokens[0] = token
                }
                else if !text.isEmpty || tokensLen == 0 || isEmptyStr {
                    lastLine.tokens.append(token)
                }
            }
            // Other tokens always start a new line.
            else {
                let newRichLine = RichTextLine()
                newRichLine.tokens = [token]
                block.lines.append(newRichLine)
            }
        }
    }

    // upstream: function isAlphabeticLetter(ch)
    fileprivate static func isAlphabeticLetter(_ code: Int) -> Bool {
        return (code >= 0x20 && code <= 0x24F)      // Latin
            || (code >= 0x370 && code <= 0x10FF)    // Greek, Coptic, Cyrillic, etc.
            || (code >= 0x1200 && code <= 0x13FF)   // Ethiopic and Cherokee
            || (code >= 0x1E00 && code <= 0x206F)   // Latin and Greek extended
    }

    // upstream: const breakCharMap = reduce(',&?/;] '.split(''), ...)
    fileprivate static let breakCharMap: Set<Character> = [",", "&", "?", "/", ";", "]", " "]

    // upstream: function isWordBreakChar(ch)
    fileprivate static func isWordBreakChar(_ ch: Character, _ code: Int) -> Bool {
        if isAlphabeticLetter(code) {
            return breakCharMap.contains(ch)
        }
        return true
    }

    fileprivate struct WrapResult {
        var accumWidth: Double
        var lines: [String]
        var linesWidths: [Double]
    }

    // upstream: function wrapText(text, font, lineWidth, isBreakAll, lastAccumWidth)
    fileprivate static func wrapText(
        _ text: String,
        _ font: String?,
        _ lineWidth: Double,
        _ isBreakAll: Bool,
        _ lastAccumWidth: Double
    ) -> WrapResult {
        var lines: [String] = []
        var linesWidths: [Double] = []
        var line = ""
        var currentWord = ""
        var currentWordWidth: Double = 0
        var accumWidth: Double = 0
        let fontMeasureInfo = ZRenderKit.text.ensureFontMeasureInfo(font)

        // Iterate by UTF-16 code units to match JS charAt/charCodeAt semantics.
        let units = Array(text.utf16)
        for i in 0..<units.count {
            let unit = units[i]
            let scalar = Unicode.Scalar(unit)
            let ch: Character = scalar.map { Character($0) } ?? " "
            if unit == 0x0A {   // '\n'
                if !currentWord.isEmpty {
                    line += currentWord
                    accumWidth += currentWordWidth
                }
                lines.append(line)
                linesWidths.append(accumWidth)
                line = ""; currentWord = ""; currentWordWidth = 0; accumWidth = 0
                continue
            }

            let chWidth = ZRenderKit.text.measureCharWidth(fontMeasureInfo, Double(unit))
            let inWord = isBreakAll ? false : !isWordBreakChar(ch, Int(unit))

            let exceeds = lines.isEmpty
                ? (lastAccumWidth + accumWidth + chWidth > lineWidth)
                : (accumWidth + chWidth > lineWidth)

            if exceeds {
                if accumWidth == 0 {    // If nothing appended yet.
                    if inWord {
                        // The word is still too long for one line — force break the word.
                        lines.append(currentWord)
                        linesWidths.append(currentWordWidth)
                        currentWord = String(ch)
                        currentWordWidth = chWidth
                    }
                    else {
                        // lineWidth is too small for ch.
                        lines.append(String(ch))
                        linesWidths.append(chWidth)
                    }
                }
                else if !line.isEmpty || !currentWord.isEmpty {
                    if inWord {
                        if line.isEmpty {
                            // The one word is still too long for one line — force break.
                            line = currentWord
                            currentWord = ""
                            currentWordWidth = 0
                            accumWidth = currentWordWidth
                        }

                        lines.append(line)
                        linesWidths.append(accumWidth - currentWordWidth)

                        // Break the whole word.
                        currentWord += String(ch)
                        currentWordWidth += chWidth
                        line = ""
                        accumWidth = currentWordWidth
                    }
                    else {
                        // Append lastWord if have.
                        if !currentWord.isEmpty {
                            line += currentWord
                            currentWord = ""
                            currentWordWidth = 0
                        }
                        lines.append(line)
                        linesWidths.append(accumWidth)

                        line = String(ch)
                        accumWidth = chWidth
                    }
                }

                continue
            }

            accumWidth += chWidth

            if inWord {
                currentWord += String(ch)
                currentWordWidth += chWidth
            }
            else {
                // Append whole word.
                if !currentWord.isEmpty {
                    line += currentWord
                    currentWord = ""
                    currentWordWidth = 0
                }
                // Append character.
                line += String(ch)
            }
        }

        // Append last line.
        if !currentWord.isEmpty {
            line += currentWord
        }
        if !line.isEmpty {
            lines.append(line)
            linesWidths.append(accumWidth)
        }

        if lines.count == 1 {
            // No new line.
            accumWidth += lastAccumWidth
        }

        return WrapResult(accumWidth: accumWidth, lines: lines, linesWidths: linesWidths)
    }

    // upstream: export function calcInnerTextOverflowArea(out, overflowRect, baseX, baseY, textAlign,
    //   textVerticalAlign): void
    public static func calcInnerTextOverflowArea(
        _ out: CalcInnerTextOverflowAreaOut,
        _ overflowRect: BoundingRect?,
        _ baseX: Double,
        _ baseY: Double,
        _ textAlign: TextAlign?,
        _ textVerticalAlign: TextVerticalAlign?
    ) {
        out.baseX = baseX
        out.baseY = baseY
        out.outerWidth = nil
        out.outerHeight = nil

        guard let overflowRect = overflowRect else {
            return
        }

        let textWidth = overflowRect.width * 2
        let textHeight = overflowRect.height * 2
        BoundingRect.set(
            tmpCITCTextRect,
            ZRenderKit.text.adjustTextX(baseX, textWidth, textAlign),
            ZRenderKit.text.adjustTextY(baseY, textHeight, textVerticalAlign),
            textWidth,
            textHeight
        )
        // `clamp` so that `overflow: break` with no/insufficient intersection still displays text
        // on the edge (logically sound + helps debug).
        let intersectRect = BoundingRect(0, 0, 0, 0)
        var opt = BoundingRectIntersectOpt()
        opt.outIntersectRect = intersectRect
        opt.clamp = true
        _ = BoundingRect.intersect(overflowRect, tmpCITCTextRect, nil, opt)
        out.outerWidth = intersectRect.width
        out.outerHeight = intersectRect.height
        out.baseX = ZRenderKit.text.adjustTextX(intersectRect.x, intersectRect.width, textAlign, true)
        out.baseY = ZRenderKit.text.adjustTextY(intersectRect.y, intersectRect.height, textVerticalAlign, true)
    }

    fileprivate static let tmpCITCTextRect = BoundingRect(0, 0, 0, 0)

    // upstream: export function tSpanCreateBoundingRect2(style, contentWidth, contentHeight,
    //   forceLineWidth): BoundingRect  — ported in full (depends only on contain/text, which is ported).
    public static func tSpanCreateBoundingRect2(
        _ style: TSpanStyleProps,
        _ contentWidth: Double,
        _ contentHeight: Double,
        _ forceLineWidth: Double?
    ) -> BoundingRect {
        let rect = BoundingRect(
            ZRenderKit.text.adjustTextX(style.x ?? 0, contentWidth, style.textAlign.flatMap(TextAlign.init(rawValue:))),
            ZRenderKit.text.adjustTextY(style.y ?? 0, contentHeight, style.textBaseline.flatMap(TextVerticalAlign.init(rawValue:))),
            // Text boundary should be the real text width (see upstream comment).
            contentWidth,
            contentHeight
        )

        let lineWidth = forceLineWidth != nil
            ? forceLineWidth!
            : (tSpanHasStroke(style) ? (style.lineWidth ?? 0) : 0)
        if lineWidth > 0 {
            rect.x -= lineWidth / 2
            rect.y -= lineWidth / 2
            rect.width += lineWidth
            rect.height += lineWidth
        }

        return rect
    }

    // upstream: export function tSpanHasStroke(style: TSpanStyleProps): boolean
    public static func tSpanHasStroke(_ style: TSpanStyleProps) -> Bool {
        let stroke = style.stroke
        let isNone: Bool
        if case .some(.string("none")) = stroke { isNone = true } else { isNone = (stroke == nil) }
        return !isNone && (style.lineWidth ?? 0) > 0
    }
}
