// Ported from zrender/src/graphic/TSpan.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. A `TSpan` is a single positioned text run — the actual text
// primitive the painter draws. It is a `Displayable` subclass with a `TSpanStyleProps` style bag
// (text / font / textAlign / textBaseline / x / y plus the inherited fill/stroke path fields).
//
// STYLE DECISION (TS `TSpanStyleProps extends PathStyleProps` → Swift): mirrors the Path approach
//   (see Path.swift STYLE DECISION). Swift structs cannot subclass and the inherited
//   `Displayable.style` (CommonStyleProps) cannot be re-typed, so `TSpanStyleProps` FLATTENS the
//   PathStyleProps fields plus the text fields, and `TSpan` stores it in its OWN property
//   `tspanStyle` (upstream `this.style` → Swift `self.tspanStyle`). `_syncCommonStyle()` mirrors the
//   common subset into the inherited `Displayable.style` so the inherited machinery
//   (shouldBePainted / getPaintRect) reads correct shadow / opacity / blend.

import Foundation

// upstream imports (resolved to the ported modules):
// import Displayable, { DisplayableProps, DisplayableStatePropNames } from './Displayable';
// import BoundingRect from '../core/BoundingRect';
// import { PathStyleProps, DEFAULT_PATH_STYLE } from './Path';
// import { createObject, defaults } from '../core/util';   → util.* / inlined merge
// import { FontStyle, FontWeight } from '../core/types';
// import { DEFAULT_FONT } from '../core/platform';
// import { tSpanCreateBoundingRect, tSpanHasStroke } from './helper/parseText';
//   → PORT-NOTE: parseText is ported in Text.swift (fenced seam stub: tSpanCreateBoundingRect2 etc.),
//     not yet split into graphic/helper/parseText.swift. `tSpanHasStroke` is inlined here (trivial,
//     same predicate as Path.hasStroke). TSpan's own lazy bounding-rect fallback stays stubbed — the
//     rect is normally injected via setBoundingRect by the text layout layer (see getBoundingRect).

// upstream: interface TSpanStyleProps extends PathStyleProps { x?, y?, text?, font?, fontSize?,
//   fontWeight?, fontStyle?, fontFamily?, textAlign?, textBaseline? }
//   FLATTENED into one struct (PathStyleProps fields + text fields) — see the STYLE DECISION note.
public struct TSpanStyleProps {
    // ---- CommonStyleProps fields (via PathStyleProps `extends CommonStyleProps`) ----
    public var shadowBlur: Double?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?
    public var shadowColor: String?
    public var opacity: Double?
    /// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/globalCompositeOperation
    public var blend: String?
    // PORT-NOTE: replaces upstream's dynamic STYLE_MAGIC_KEY stamp (see Displayable.swift). `true`
    //   iff produced by `createStyle`.
    public var zrStyleMagic: Bool = false

    // ---- PathStyleProps fields (upstream: `extends PathStyleProps`) ----
    public var fill: ZRColor?
    public var stroke: ZRColor?
    public var decal: Pattern?   // upstream: PatternObject
    public var strokePercent: Double?
    public var strokeNoScale: Bool?
    public var fillOpacity: Double?
    public var strokeOpacity: Double?
    public var lineDash: LineDash?
    public var lineDashOffset: Double?
    public var lineWidth: Double?
    public var lineCap: String?   // upstream: CanvasLineCap
    public var lineJoin: String?  // upstream: CanvasLineJoin
    public var miterLimit: Double?
    public var strokeFirst: Bool?

    // ---- TSpanStyleProps own fields ----
    public var x: Double?
    public var y: Double?

    // TODO Text is assigned inside zrender
    public var text: String?

    /// Final generated font string. Used in canvas, and when developers specified it.
    public var font: String?

    // Value for each part of font. Used in svg.
    // NOTE: font should always been sync with these 4 properties.
    public var fontSize: Double?
    public var fontWeight: FontWeight?
    public var fontStyle: FontStyle?
    public var fontFamily: String?

    public var textAlign: String?      // upstream: CanvasTextAlign
    public var textBaseline: String?   // upstream: CanvasTextBaseline

    public init() {}
}

// upstream: export const DEFAULT_TSPAN_STYLE = defaults({ strokeFirst, font, x, y, textAlign,
//   textBaseline, miterLimit } as TSpanStyleProps, DEFAULT_PATH_STYLE);
//   `defaults(target, source)` copies source keys into target where target lacks them, so the
//   explicit overrides (strokeFirst:true, miterLimit:2) win over DEFAULT_PATH_STYLE, and the rest of
//   DEFAULT_PATH_STYLE fills in. Inlined here.
public let DEFAULT_TSPAN_STYLE: TSpanStyleProps = {
    var s = TSpanStyleProps()
    // from DEFAULT_PATH_STYLE (CommonStyleProps + path defaults):
    s.shadowBlur = 0
    s.shadowOffsetX = 0
    s.shadowOffsetY = 0
    s.shadowColor = "#000"
    s.opacity = 1
    s.blend = "source-over"
    s.zrStyleMagic = true
    s.fill = .string("#000")
    s.stroke = nil
    s.strokePercent = 1
    s.fillOpacity = 1
    s.strokeOpacity = 1
    s.lineDashOffset = 0
    s.lineWidth = 1
    s.lineCap = "butt"
    s.strokeNoScale = false
    // explicit overrides from the `defaults` target:
    s.strokeFirst = true
    s.font = DEFAULT_FONT
    s.x = 0
    s.y = 0
    s.textAlign = "left"
    s.textBaseline = "top"
    s.miterLimit = 2
    return s
}()

// PORT-NOTE: interface TSpanProps extends DisplayableProps { style?: TSpanStyleProps }. The
//   `attr`/`attrKV` setter machinery uses the dynamic prop bag (collapsed onto DisplayableProps ==
//   ElementProps). Typed-interface fidelity dropped.
public typealias TSpanProps = DisplayableProps

// PORT-NOTE: TSpanState = Pick<TSpanProps, DisplayableStatePropNames>. Collapsed onto DisplayableState
//   (typealias to ElementState); the states machinery lives on Element.
public typealias TSpanState = DisplayableState

// upstream: class TSpan extends Displayable<TSpanProps>
public final class TSpan: Displayable {

    // upstream: style: TSpanStyleProps. Swift cannot re-type the inherited `Displayable.style`
    //   (CommonStyleProps), so the rich style lives here (upstream `this.style` → `self.tspanStyle`).
    //   `_syncCommonStyle()` mirrors the common subset into the inherited `self.style`.
    public var tspanStyle: TSpanStyleProps!

    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "tspan"
        // upstream: protected static initDefaultProps → tspanProto.dirtyRectTolerance = 10
        // TODO Calculate tolerance smarter
        self.dirtyRectTolerance = 10
    }

    internal override func _init(_ props: ElementProps? = nil) {  // upstream: protected
        // PORT-NOTE: TSpan has no own `_init` upstream; it inherits Displayable._init, which routes
        //   `style` through `useStyle(CommonStyleProps)`. Overridden here so the `style` opt is typed
        //   as TSpanStyleProps (consistent with the Path style-bag bridge).
        let keysArr = util.keys(props ?? [:])
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            if key == "style" {
                if let s = props?[key] as? TSpanStyleProps {
                    self.useStyle(s)
                }
                else {
                    self.useStyle(TSpanStyleProps())
                }
            }
            else {
                super.attrKV(key, props?[key])
            }
        }
        // Give a empty style
        if self.tspanStyle == nil {
            self.useStyle(TSpanStyleProps())
        }
    }

    public func hasStroke() -> Bool {
        // upstream: return tSpanHasStroke(this.style);
        // PORT-NOTE: parseText.ts not ported; `tSpanHasStroke` inlined (stroke != null &&
        //   stroke !== 'none' && style.lineWidth > 0).
        let style = self.tspanStyle!
        let stroke = style.stroke
        let strokeIsNone: Bool
        if case .some(.string("none")) = stroke { strokeIsNone = true } else { strokeIsNone = (stroke == nil) }
        return !strokeIsNone && (style.lineWidth ?? 0) > 0
    }

    public func hasFill() -> Bool {
        let style = self.tspanStyle!
        let fill = style.fill
        // fill != null && fill !== 'none'
        if case .some(.string("none")) = fill { return false }
        return fill != nil
    }

    /// Create an image style object with default values in it's prototype.
    /// @override
    // upstream: createStyle(obj?: TSpanStyleProps) { return createObject(DEFAULT_TSPAN_STYLE, obj) }
    //   OVERLOAD (not override) of Displayable.createStyle(CommonStyleProps?).
    public func createStyle(_ obj: TSpanStyleProps? = nil) -> TSpanStyleProps {
        var style = DEFAULT_TSPAN_STYLE
        if let obj = obj {
            extendTSpanStyle(&style, obj)
        }
        return style
    }

    /// Replace style property. OVERLOAD of Displayable.useStyle(CommonStyleProps).
    public func useStyle(_ obj: TSpanStyleProps) {
        var obj = obj
        if !obj.zrStyleMagic {
            obj = self.createStyle(obj)
        }
        self.tspanStyle = obj
        self._syncCommonStyle()
        self.dirtyStyle()
    }

    // Mirror the CommonStyleProps subset of `tspanStyle` into the inherited `Displayable.style` so
    // the inherited machinery (shouldBePainted / getPaintRect) reads correct shadow / opacity /
    // blend. PORT-NOTE: a Swift-only bridge — upstream has a single `this.style` object.
    private func _syncCommonStyle() {
        var c = CommonStyleProps()
        c.shadowBlur = self.tspanStyle.shadowBlur
        c.shadowOffsetX = self.tspanStyle.shadowOffsetX
        c.shadowOffsetY = self.tspanStyle.shadowOffsetY
        c.shadowColor = self.tspanStyle.shadowColor
        c.opacity = self.tspanStyle.opacity
        c.blend = self.tspanStyle.blend
        c.zrStyleMagic = self.tspanStyle.zrStyleMagic
        self.style = c
    }

    /// Set bounding rect calculated from Text
    /// For reducing time of calculating bounding rect.
    public func setBoundingRect(_ rect: BoundingRect) {
        self._rect = rect
    }

    public override func getBoundingRect() -> BoundingRect? {
        if self._rect == nil {
            // upstream: this._rect = tSpanCreateBoundingRect(this.style);
            //   tSpanCreateBoundingRect measures the single line and delegates to
            //   tSpanCreateBoundingRect2 (both ported in Text.swift / ContainText.swift).
            //   formatText(text): coerce nil → "".
            let text = self.tspanStyle.text ?? ""
            let font = self.tspanStyle.font
            let contentWidth = ZRenderKit.text.measureWidth(ZRenderKit.text.ensureFontMeasureInfo(font), text)
            let contentHeight = ZRenderKit.text.getLineHeight(font)
            self._rect = parseText.tSpanCreateBoundingRect2(self.tspanStyle, contentWidth, contentHeight, nil)
        }
        return self._rect
    }
}

// upstream: TSpan.prototype.type = 'tspan'  → set in init (per-instance).

// extend(target, source) over TSpanStyleProps' known fields (value-copy of non-nil fields).
// PORT-NOTE: upstream `extend` copies all own enumerable keys (dynamic bag); here we copy the known
//   TSpanStyleProps fields only. `zrStyleMagic` is intentionally NOT copied (created-style marker).
func extendTSpanStyle(_ target: inout TSpanStyleProps, _ source: TSpanStyleProps) {
    // common fields
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.blend != nil { target.blend = source.blend }
    // path fields
    if source.fill != nil { target.fill = source.fill }
    if source.stroke != nil { target.stroke = source.stroke }
    if source.decal != nil { target.decal = source.decal }
    if source.strokePercent != nil { target.strokePercent = source.strokePercent }
    if source.strokeNoScale != nil { target.strokeNoScale = source.strokeNoScale }
    if source.fillOpacity != nil { target.fillOpacity = source.fillOpacity }
    if source.strokeOpacity != nil { target.strokeOpacity = source.strokeOpacity }
    if source.lineDash != nil { target.lineDash = source.lineDash }
    if source.lineDashOffset != nil { target.lineDashOffset = source.lineDashOffset }
    if source.lineWidth != nil { target.lineWidth = source.lineWidth }
    if source.lineCap != nil { target.lineCap = source.lineCap }
    if source.lineJoin != nil { target.lineJoin = source.lineJoin }
    if source.miterLimit != nil { target.miterLimit = source.miterLimit }
    if source.strokeFirst != nil { target.strokeFirst = source.strokeFirst }
    // tspan fields
    if source.x != nil { target.x = source.x }
    if source.y != nil { target.y = source.y }
    if source.text != nil { target.text = source.text }
    if source.font != nil { target.font = source.font }
    if source.fontSize != nil { target.fontSize = source.fontSize }
    if source.fontWeight != nil { target.fontWeight = source.fontWeight }
    if source.fontStyle != nil { target.fontStyle = source.fontStyle }
    if source.fontFamily != nil { target.fontFamily = source.fontFamily }
    if source.textAlign != nil { target.textAlign = source.textAlign }
    if source.textBaseline != nil { target.textBaseline = source.textBaseline }
}

// upstream: export default TSpan;
