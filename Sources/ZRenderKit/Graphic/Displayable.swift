// Ported from zrender/src/graphic/Displayable.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. `Displayable extends Element`. The display surface needed to
// build & render a STATIC scene graph is translated faithfully:
//   - CommonStyleProps (modeled as a Swift struct per CONVENTIONS §4) + DEFAULT_COMMON_STYLE
//   - z / z2 / zlevel z-order; invisible; culling; cursor; rectHover; incremental
//   - the `style` stored property + useStyle / createStyle / setStyle / isStyleObject
//   - dirtyStyle / styleChanged / styleUpdated (STYLE_CHANGED_BIT from graphic/constants)
//   - getBoundingRect (inherited hook) / contain / rectContain / shouldBePainted / getPaintRect
//   - beforeBrush / afterBrush / innerBeforeBrush / innerAfterBrush hooks (no-ops)
//
// STUBBED (PORT-TODO, deferred — inherited from Element's deferred animation/states surface):
//   - the states machinery (_innerSaveToNormal / _applyStateObj / _mergeStates / DisplayableState)
//   - the animation surface (animate('style') / animateStyle / getAnimationStyleProps)
//   - the canvas/svg painter caches (__canvasFillGradient / __svgEl / ...) — renderer seam §9.

import Foundation

// upstream imports (resolved to ported modules):
// import Element, {ElementProps, ElementStatePropNames, ElementAnimateConfig, ElementCommonState,
//   IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE} from '../Element';
// import BoundingRect from '../core/BoundingRect';
// import { PropType, Dictionary, MapToType, IncrementalIdCompat } from '../core/types';
// import Path from './Path';                       → forward-declared placeholder in Element.swift
// import { keys, extend, createObject } from '../core/util';   → util.*
// import Animator from '../animation/Animator';    → Phase-3 stub
// import { REDRAW_BIT, STYLE_CHANGED_BIT } from './constants';

// PORT-TODO: upstream `STYLE_MAGIC_KEY = '__zr_style_' + Math.round(Math.random() * 10)` is a
//   dynamic property key stamped onto created style objects to detect "is this a valid style
//   object". Swift structs have no dynamic keys, so we model the flag as the `zrStyleMagic`
//   field of `CommonStyleProps` (see below). The const is kept for provenance.
fileprivate let STYLE_MAGIC_KEY = "__zr_style_" + String(Int((Double.random(in: 0...1) * 10).rounded()))

public struct CommonStyleProps {
    public var shadowBlur: Double?
    public var shadowOffsetX: Double?
    public var shadowOffsetY: Double?
    public var shadowColor: String?

    public var opacity: Double?
    /// https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/globalCompositeOperation
    public var blend: String?

    // PORT-TODO: replaces upstream's dynamic STYLE_MAGIC_KEY stamp. `true` iff this style object
    //   was produced by `createStyle` (i.e. has the default values baked in). See `useStyle`.
    public var zrStyleMagic: Bool = false

    // PORT-TODO: subclass styles (PathStyleProps / TextStyleProps / ImageStyleProps) `extend`
    //   CommonStyleProps in upstream and `Displayable<Props>` is generic over `Props['style']`.
    //   Swift structs can't be subclassed and the stored `style` property can't be re-typed by
    //   a subclass, so the generic is collapsed to CommonStyleProps here; Path/Text model their
    //   richer style bags in their own files.

    public init() {}

    // Keyed access for animateTo({style: {...}}) — exposes the animatable fields (mirrors the
    //   shape side; see StyleAnimationAccessor below). The numeric fields tween directly; the
    //   color field `shadowColor` flows as a color string through the Animator's color-tween path
    //   (color.parse → interpolate → rgba2String), consistent with DEFAULT_COMMON_ANIMATION_PROPS.
    // PORT-TODO: `blend` (composite-op String) is not tweened.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "opacity": return opacity
        case "shadowBlur": return shadowBlur
        case "shadowOffsetX": return shadowOffsetX
        case "shadowOffsetY": return shadowOffsetY
        case "shadowColor": return shadowColor
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "opacity": if let v = value as? Double { opacity = v }
        case "shadowBlur": if let v = value as? Double { shadowBlur = v }
        case "shadowOffsetX": if let v = value as? Double { shadowOffsetX = v }
        case "shadowOffsetY": if let v = value as? Double { shadowOffsetY = v }
        case "shadowColor": if let v = value as? String { shadowColor = v }
        default: break
        }
    }
}

// Reference bridge between the by-reference animation machinery and the by-value
// `Displayable.style` struct — mirrors `ShapeAnimationAccessor` (Path.swift) for the style bag.
// Upstream animates `style` (a plain object) in place; in Swift `style` is a value type, so
// `Displayable.animationGet("style")` hands the Animator this accessor, whose keyed set writes back
// into the live `displayable.style` and marks the style dirty (instead of dirtyShape).
final class StyleAnimationAccessor: AnimationTarget {
    unowned let displayable: Displayable
    init(_ displayable: Displayable) { self.displayable = displayable }
    func animationGet(_ key: String) -> Any? {
        return displayable.style?.animationGet(key)
    }
    func animationSet(_ key: String, _ value: Any?) {
        guard var s = displayable.style else { return }
        s.animationSet(key, value)   // mutate local copy of the value-type struct
        displayable.style = s        // write back to the live property
        displayable.dirtyStyle()
    }
}

public let DEFAULT_COMMON_STYLE: CommonStyleProps = {
    var s = CommonStyleProps()
    s.shadowBlur = 0
    s.shadowOffsetX = 0
    s.shadowOffsetY = 0
    s.shadowColor = "#000"
    s.opacity = 1
    s.blend = "source-over"
    // (DEFAULT_COMMON_STYLE as any)[STYLE_MAGIC_KEY] = true;
    s.zrStyleMagic = true
    return s
}()

// PORT-TODO: upstream `MapToType<DisplayableProps, boolean>`; collapsed to a loose bag. Only read
//   by `getAnimationStyleProps` (animation surface deferred, Phase 3).
public let DEFAULT_COMMON_ANIMATION_PROPS: [String: Any] = [
    "style": [
        "shadowBlur": true,
        "shadowOffsetX": true,
        "shadowOffsetY": true,
        "shadowColor": true,
        "opacity": true
    ]
]

// PORT-TODO: interface DisplayableProps extends ElementProps. The `attr`/`attrKV` setter machinery
//   uses the dynamic `[String: Any]` prop bag (ElementProps); the typed-interface fidelity is
//   dropped. Added optional keys (for provenance):
//     style?, zlevel?, z?, z2?, culling?, cursor?, rectHover?, progressive?, incremental?,
//     ignoreCoarsePointer?, batch?, invisible?
public typealias DisplayableProps = ElementProps

// PORT-TODO: DisplayableStatePropNames / DisplayableState — `Pick<DisplayableProps, ...>` utility
//   types for the states machinery (Phase 2). Collapsed onto Element's ElementState.
public typealias DisplayableState = ElementState

fileprivate let PRIMARY_STATES_KEYS: [String] = ["z", "z2", "invisible"]
fileprivate let PRIMARY_STATES_KEYS_IN_HOVER_LAYER: [String] = ["invisible"]

public struct BeforeBrushParam {
    // [EXPERIMENTAL]
    // true means the layer is not cleared before this run of brush().
    public var contentRetained: Bool?
    public init() {}
}

// upstream: interface Displayable<Props> { animate / getState / ensureState / states / stateProxy }
//   — declaration-merging of the animation + states surface. Element already provides getState /
//   ensureState / states / stateProxy (with ElementState); not redeclared (PORT-TODO Phase 2/3).

open class Displayable: Element {

    /// Whether the displayable object is visible. when it is true, the displayable object
    /// is not drawn, but the mouse event can still trigger the object.
    public var invisible: Bool = false

    public var z: Double = 0

    public var z2: Double = 0

    /// The z level determines the displayable object can be drawn in which layer canvas.
    public var zlevel: Double = 0

    /// If enable culling
    public var culling: Bool = false

    /// Mouse cursor when hovered
    public var cursor: String = "pointer"

    /// If hover area is bounding rect
    public var rectHover: Bool = false

    public var incremental: Double = 0  // upstream: IncrementalIdCompat (widened to Double)

    /// For an incremental element. `true` can prevent its incremental layer from clearing even
    /// when `REDRAW_BIT` is set. See the long upstream comment on incremental drawing.
    public var notClear: Bool?
    /// See `notClear`
    public var __layerCleared: Bool?

    /// Never increase to target size
    public var ignoreCoarsePointer: Bool?

    // FIXME: do not use TS any.
    // PORT-TODO: upstream `style: Dictionary<any>` (dynamic bag). Modeled as the CommonStyleProps
    //   struct (CONVENTIONS §4). Implicitly-unwrapped to faithfully mirror upstream, where `style`
    //   is `undefined` until `useStyle` runs (see `_init` / `attrKV`'s `if (!this.style)` guards).
    public var style: CommonStyleProps!

    // PORT-TODO: upstream re-declares `protected _normalState: DisplayableState` to narrow the type.
    //   Swift can't redeclare an inherited stored property; we reuse Element's `_normalState`
    //   (typed ElementState; DisplayableState is a typealias to it). States are stubbed (Phase 2).

    internal var _rect: BoundingRect?       // upstream: protected
    internal var _paintRect: BoundingRect?  // upstream: protected
    internal var _prevPaintRect: BoundingRect?  // upstream: protected

    public var dirtyRectTolerance: Double = 0

    /************* Properties will be injected in other modules. *******************/

    // @deprecated.
    public var useHoverLayer: Bool?

    public var __hoverStyle: CommonStyleProps?

    // Shapes for cascade clipping.
    // PORT-TODO: upstream `__clipPaths?: Path[]` — inherited from Element (`__clipPaths`).

    // PORT-TODO: FOR CANVAS PAINTER — __canvasFillGradient / __canvasStrokeGradient /
    //   __canvasFillPattern / __canvasStrokePattern; FOR SVG PAINTER — __svgEl. Renderer seam
    //   (CONVENTIONS §9); not modeled in render-only Phase 1.

    public override init(_ props: ElementProps? = nil) {
        super.init(props)
        // upstream: protected static initDefaultProps (prototype defaults), applied per-instance:
        self.type = "displayable"
        // dispProto.__dirty = REDRAW_BIT | STYLE_CHANGED_BIT
        self.__dirty = Double(Int(REDRAW_BIT) | Int(STYLE_CHANGED_BIT))
    }

    internal override func _init(_ props: ElementProps? = nil) {  // upstream: protected
        // Init default properties
        let keysArr = util.keys(props ?? [:])
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            if key == "style" {
                if let s = props?[key] as? CommonStyleProps {
                    self.useStyle(s)
                }
                else {
                    // PORT-TODO: non-CommonStyleProps `style` value — fall back to empty style.
                    self.useStyle(CommonStyleProps())
                }
            }
            else {
                super.attrKV(key, props?[key])
            }
        }
        // Give a empty style
        if self.style == nil {
            self.useStyle(CommonStyleProps())
        }
    }

    // Hook provided to developers.
    public func beforeBrush(_ param: BeforeBrushParam) {}
    public func afterBrush() {}

    // Hook provided to inherited classes.
    // Executed between beforeBrush / afterBrush
    public func innerBeforeBrush() {}
    public func innerAfterBrush() {}

    public func shouldBePainted(
        _ viewWidth: Double,
        _ viewHeight: Double,
        _ considerClipPath: Bool,
        _ considerAncestors: Bool
    ) -> Bool {
        let m = self.transform
        if
            self.ignore
            // Ignore invisible element
            || self.invisible
            // Ignore transparent element
            || self.style.opacity == 0
            // Ignore culled element
            || (self.culling
                && isDisplayableCulled(self, viewWidth, viewHeight)
            )
            // Ignore scale 0 element, in some environment like node-canvas
            // Draw a scale 0 element can cause all following draw wrong
            // And setTransform with scale 0 will cause set back transform failed.
            // upstream `!m[0] && !m[3]` is JS falsy, which is also true for NaN (not just 0).
            // Match that: a degenerate/NaN scale on both axes triggers the cull.
            || (m != nil
                && (m![0] == 0 || m![0].isNaN)
                && (m![3] == 0 || m![3].isNaN))
        {
            return false
        }

        if considerClipPath, let clipPaths = self.__clipPaths, clipPaths.count > 0 {
            for i in 0..<clipPaths.count {
                // upstream: `if (this.__clipPaths[i].isZeroArea()) return false` — ignore zero area shape.
                if clipPaths[i].isZeroArea() { return false }
            }
        }

        if considerAncestors, self.parent != nil {
            var parent: Transformable? = self.parent
            while let p = parent {
                if let el = p as? Element, el.ignore {
                    return false
                }
                parent = p.parent
            }
        }

        return true
    }

    /// If displayable element contain coord x, y
    public func contain(_ x: Double, _ y: Double) -> Bool {
        return self.rectContain(x, y)
    }

    public override func traverse(_ cb: (_ el: Element) -> Void, _ context: Any? = nil) {
        cb(self)
    }

    /// If bounding rect of element contain coord x, y
    public func rectContain(_ x: Double, _ y: Double) -> Bool {
        let coord = self.transformCoordToLocal(x, y)
        // PORT-TODO: upstream assumes getBoundingRect() is non-null (provided by Path/Group).
        guard let rect = self.getBoundingRect() else { return false }
        return rect.contain(coord[0], coord[1])
    }

    public override func getPaintRect() -> BoundingRect? {
        var rect = self._paintRect
        if self._paintRect == nil || self.__dirty != 0 {
            let transform = self.transform
            let elRect = self.getBoundingRect()

            let style = self.style
            // PORT-TODO: `|| 0` is JS falsy (also coerces NaN → 0); modeled as `?? 0`.
            let shadowSize = style?.shadowBlur ?? 0
            let shadowOffsetX = style?.shadowOffsetX ?? 0
            let shadowOffsetY = style?.shadowOffsetY ?? 0

            if self._paintRect == nil {
                self._paintRect = BoundingRect(0, 0, 0, 0)
            }
            rect = self._paintRect
            let r = rect!
            if let transform = transform {
                // PORT-TODO: upstream assumes elRect non-null.
                if let elRect = elRect {
                    BoundingRect.applyTransform(r, elRect, transform)
                }
            }
            else {
                if let elRect = elRect {
                    r.copy(elRect)
                }
            }

            if shadowSize != 0 || shadowOffsetX != 0 || shadowOffsetY != 0 {
                r.width += shadowSize * 2 + Swift.abs(shadowOffsetX)
                r.height += shadowSize * 2 + Swift.abs(shadowOffsetY)
                r.x = Swift.min(r.x, r.x + shadowOffsetX - shadowSize)
                r.y = Swift.min(r.y, r.y + shadowOffsetY - shadowSize)
            }

            // For the accuracy tolerance of text height or line joint point
            let tolerance = self.dirtyRectTolerance
            if !r.isZero() {
                r.x = floor(r.x - tolerance)
                r.y = floor(r.y - tolerance)
                r.width = ceil(r.width + 1 + tolerance * 2)
                r.height = ceil(r.height + 1 + tolerance * 2)
            }
        }
        return rect
    }

    public func setPrevPaintRect(_ paintRect: BoundingRect?) {
        if let paintRect = paintRect {
            if self._prevPaintRect == nil {
                self._prevPaintRect = BoundingRect(0, 0, 0, 0)
            }
            self._prevPaintRect!.copy(paintRect)
        }
        else {
            self._prevPaintRect = nil
        }
    }

    public func getPrevPaintRect() -> BoundingRect? {
        return self._prevPaintRect
    }

    /// Alias for animate('style')
    @discardableResult
    public func animateStyle(_ loop: Bool) -> Animator<Any> {
        // PORT-TODO: upstream returns Animator<this['style']>; collapsed to Animator<Any>.
        return self.animate("style", loop)
    }

    // Override updateDuringAnimation
    public override func updateDuringAnimation(_ targetKey: String) {
        if targetKey == "style" {
            self.dirtyStyle()
        }
        else {
            self.markRedraw()
        }
    }

    // One reusable accessor per Displayable (holds an unowned back-ref — no retain cycle).
    private lazy var _styleAnimationAccessor = StyleAnimationAccessor(self)

    // Expose the `style` sub-bag to the animation machinery — mirrors Path's `shape` exposure.
    // `animationGet("style")` returns the reference accessor so animateToShallow can recurse into
    // the style's keys (e.g. {style: {opacity: 0.5}}). Other keys fall through to Element.
    public override func animationGet(_ key: String) -> Any? {
        if key == "style" {
            return _styleAnimationAccessor
        }
        return super.animationGet(key)
    }

    public override func animationSet(_ key: String, _ value: Any?) {
        if key == "style" {
            // Whole-style direct assign (the non-animated branch of animateToShallow).
            if let s = value as? CommonStyleProps {
                self.style = s
                self.dirtyStyle()
            }
            return
        }
        super.animationSet(key, value)
    }

    internal override func attrKV(_ key: String, _ value: Any?) {  // upstream: protected
        if key != "style" {
            // PORT-TODO: upstream delegates to `super.attrKV(key, value)`, which sets the property
            //   dynamically via `(this as any)[key] = value`. Swift has no dynamic assignment, so
            //   Displayable's own props are switched here before falling back to Element's setter.
            switch key {
            case "zlevel": if let v = value as? Double { self.zlevel = v }
            case "z": if let v = value as? Double { self.z = v }
            case "z2": if let v = value as? Double { self.z2 = v }
            case "culling": if let v = value as? Bool { self.culling = v }
            case "cursor": if let v = value as? String { self.cursor = v }
            case "rectHover": if let v = value as? Bool { self.rectHover = v }
            case "invisible": if let v = value as? Bool { self.invisible = v }
            case "incremental": if let v = value as? Double { self.incremental = v }
            case "ignoreCoarsePointer": if let v = value as? Bool { self.ignoreCoarsePointer = v }
            default: super.attrKV(key, value)
            }
        }
        else {
            if self.style == nil {
                self.useStyle((value as? CommonStyleProps) ?? CommonStyleProps())
            }
            else {
                _ = self.setStyle((value as? CommonStyleProps) ?? CommonStyleProps())
            }
        }
    }

    // upstream overloads: setStyle(obj) / setStyle(key, value)
    @discardableResult
    public func setStyle(_ obj: CommonStyleProps) -> Self {
        var s = self.style!
        extendCommonStyle(&s, obj)
        self.style = s
        self.dirtyStyle()
        return self
    }

    @discardableResult
    public func setStyle(_ key: String, _ value: Any?) -> Self {
        // upstream: this.style[key] = value
        var s = self.style!
        switch key {
        case "shadowBlur": s.shadowBlur = value as? Double
        case "shadowOffsetX": s.shadowOffsetX = value as? Double
        case "shadowOffsetY": s.shadowOffsetY = value as? Double
        case "shadowColor": s.shadowColor = value as? String
        case "opacity": s.opacity = value as? Double
        case "blend": s.blend = value as? String
        default: break  // PORT-TODO: unknown style key (subclass style field). Ignored.
        }
        self.style = s
        self.dirtyStyle()
        return self
    }

    public func dirtyStyle(_ notRedraw: Bool? = nil) {
        if !(notRedraw ?? false) {
            self.markRedraw()
        }
        self.__dirty = Double(Int(self.__dirty) | Int(STYLE_CHANGED_BIT))
        // Clear bounding rect.
        if self._rect != nil {
            self._rect = nil
        }
    }

    public override func dirty() {
        self.dirtyStyle()
    }

    /// Is style changed. Used with dirtyStyle.
    public func styleChanged() -> Bool {
        return (Int(self.__dirty) & Int(STYLE_CHANGED_BIT)) != 0
    }

    /// Mark style updated. Only useful when style is used for caching. Like in the text.
    public func styleUpdated() {
        self.__dirty = Double(Int(self.__dirty) & ~Int(STYLE_CHANGED_BIT))
    }

    /// Create a style object with default values in it's prototype.
    public func createStyle(_ obj: CommonStyleProps? = nil) -> CommonStyleProps {
        // upstream: createObject(DEFAULT_COMMON_STYLE, obj)
        var style = DEFAULT_COMMON_STYLE
        if let obj = obj {
            extendCommonStyle(&style, obj)
        }
        return style
    }

    /// Replace style property.
    /// It will create a new style if given obj is not a valid style object.
    // PENDING should not createStyle if it's an style object.
    public func useStyle(_ obj: CommonStyleProps) {
        var obj = obj
        if !obj.zrStyleMagic {
            obj = self.createStyle(obj)
        }
        // See the comment `HOVER_LAYER_CONSTRAINTS` for `hoverStyle` case.
        self.style = obj
        self.dirtyStyle()
    }

    internal func _useHoverStyle(_ obj: CommonStyleProps) {  // upstream: protected
        self.__hoverStyle = obj
        // this.dirtyStyle();  (see upstream comment — intentionally not called)
    }

    /// Determine if an object is a valid style object (created by `createStyle`).
    public func isStyleObject(_ obj: CommonStyleProps) -> Bool {
        return obj.zrStyleMagic
    }

    internal override func _innerSaveToNormal(_ toState: ElementState) {  // upstream: protected
        super._innerSaveToNormal(toState)
        // PORT-TODO: states machinery is Phase 2. Faithful body clones the style into
        //   `_normalState.style` (via `_mergeStyle(createStyle(), this.style)`) and saves the
        //   PRIMARY_STATES_KEYS (z / z2 / invisible) to normal. Deferred.
    }

    internal override func _applyStateObj(  // upstream: protected
        _ stateName: String,
        _ state: ElementState?,
        _ normalState: ElementState?,
        _ keepCurrentStates: Bool,
        _ transition: Bool,
        _ animationCfg: ElementAnimateConfig?
    ) {
        super._applyStateObj(stateName, state, normalState, keepCurrentStates, transition, animationCfg)
        // PORT-TODO: states machinery is Phase 2. Faithful body merges/animates the target style
        //   (with the IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE / hover-layer branches) and applies the
        //   PRIMARY_STATES_KEYS / PRIMARY_STATES_KEYS_IN_HOVER_LAYER. Deferred.
        _ = PRIMARY_STATES_KEYS
        _ = PRIMARY_STATES_KEYS_IN_HOVER_LAYER
        _ = IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE
    }

    internal override func _mergeStates(_ states: [ElementState]) -> ElementState {  // upstream: protected
        let mergedState = super._mergeStates(states)
        // PORT-TODO: states machinery is Phase 2. Faithful body merges each state's `style` into a
        //   single `mergedStyle` via `_mergeStyle` and assigns it onto `mergedState`. Deferred.
        return mergedState
    }

    @discardableResult
    internal func _mergeStyle(  // upstream: protected
        _ targetStyle: inout CommonStyleProps,
        _ sourceStyle: CommonStyleProps
    ) -> CommonStyleProps {
        extendCommonStyle(&targetStyle, sourceStyle)
        return targetStyle
    }

    public func getAnimationStyleProps() -> [String: Any] {
        return DEFAULT_COMMON_ANIMATION_PROPS
    }

    /// The string value of `textPosition` needs to be calculated to a real position.
    /// See `contain/text.js#calculateTextPosition`. Custom shapes (e.g. "pin", "flag") override
    /// `calculateTextPosition` (set externally) to customize the calculation.
    // PORT-TODO: calculateTextPosition hook is inherited from Element (depends on contain/text.ts).
}

// PORT-TODO: upstream `protected static initDefaultProps` (prototype seeding) is replaced by the
//   stored-property initializers above + the `init` override (type='displayable',
//   __dirty = REDRAW_BIT | STYLE_CHANGED_BIT).

private let tmpRect = BoundingRect(0, 0, 0, 0)
private let viewRect = BoundingRect(0, 0, 0, 0)
private func isDisplayableCulled(_ el: Displayable, _ width: Double, _ height: Double) -> Bool {
    // PORT-TODO: upstream assumes getBoundingRect() non-null.
    guard let r = el.getBoundingRect() else { return true }
    tmpRect.copy(r)
    if let m = el.transform {
        tmpRect.applyTransform(m)
    }
    viewRect.width = width
    viewRect.height = height
    return !tmpRect.intersect(viewRect)
}

// extend(target, source) over CommonStyleProps' known fields (value-copy of non-nil fields).
// PORT-TODO: upstream `extend` copies all own enumerable keys (dynamic bag); here we copy the
//   known CommonStyleProps fields only (subclass style fields handled in Path/Text).
private func extendCommonStyle(_ target: inout CommonStyleProps, _ source: CommonStyleProps) {
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.blend != nil { target.blend = source.blend }
}

// upstream: export default Displayable;
