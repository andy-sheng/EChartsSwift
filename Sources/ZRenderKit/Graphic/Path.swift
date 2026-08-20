// Ported from zrender/src/graphic/Path.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. This is where shapes meet PathProxy: a `Path` owns a `PathProxy`,
// a typed `shape` bag, and a `PathStyleProps` style bag, and exposes the overridable `buildPath`
// that subclasses (Rect/Circle/Sector/...) implement to emit PathProxy commands. The path-building
// lifecycle (createPathProxy / getUpdatedPathProxy / pathUpdated / dirtyShape / SHAPE_CHANGED_BIT)
// and `getBoundingRect` (routed through PathProxy + bbox, exercising the Phase-0 bbox.fromCubic fix)
// are translated faithfully.
//
// WIRED (Phase 2): contain() / pathContain hit-testing now routes to Contain/path.swift
//   (`path.contain` / `path.containStroke`) — fill winding + stroke containment are live.
// PORT-NOTE (previously stubbed; now wired except where noted):
//   - gradient / pattern paint resolution: rendered by the native painter (NativePainter/CALayerPainter.swift).
//   - the animation surface (animate('shape') / animateShape): the real Animator (Phase 3) — see below.
//   - the states machinery (_innerSaveToNormal / _applyStateObj / _mergeStates): the live state path
//     routes through Element's useState→_stateApply→animateTo; these _applyStateObj-family hooks are
//     not-the-live-path (mirrors Displayable's siblings, see below).
//   - update()'s `decal` element synthesis: implemented in update() (see `_decalEl` below).
//   - the deprecated static `extend` (runtime class synthesis has no Swift equivalent) — not translated.
//
// GENERICS DECISION (TS `Path<Props, Shape>` → Swift):
//   Upstream `Path<Props extends PathProps, Shape>` is generic over a per-subclass `Shape` bag.
//   Swift cannot make `Path` generic here because `Element`/`Displayable` reference `Path`
//   NON-generically (`__clipPaths: [Path]`, `_clipPath: Path?`, `setClipPath(_: Path)`), and a
//   generic `Path<Shape>` is not usable as a bare `Path` type. Following CONVENTIONS §2 (faithful,
//   integrable) and the task's sanctioned option ("a base class with a typed 'shape'"), `Path` is a
//   NON-generic `public class` and `shape` is typed as the existential `PathShape!`. A subclass
//   defines its shape as a `struct …Shape: PathShape { … }`, returns it from `getDefaultShape()`,
//   and downcasts the `shape` argument inside its `buildPath` override:
//       struct CircleShape: PathShape { var cx = 0.0; var cy = 0.0; var r = 0.0 }
//       final class Circle: Path {
//           override func getDefaultShape() -> PathShape { CircleShape() }
//           override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
//               let shape = shape as! CircleShape
//               _ = ctx.arc(shape.cx, shape.cy, shape.r, 0, Double.pi * 2)
//           }
//       }
//   The downcast is the documented deviation (TS narrows the property type statically per subclass;
//   Swift uses an existential + `as!`). This satisfies the KEY requirement: a subclass defines a
//   shape struct + overrides buildPath to emit PathProxy commands, exactly like upstream.
//
// STYLE DECISION (TS `PathStyleProps extends CommonStyleProps` → Swift):
//   Swift structs cannot subclass, and Swift cannot RE-TYPE the inherited `Displayable.style`
//   (`CommonStyleProps!`) to `PathStyleProps` (a subclass stored property of a different type is a
//   hard compile error). So `PathStyleProps` FLATTENS the CommonStyleProps fields plus the path
//   fields, and `Path` stores it in its OWN property `pathStyle` (upstream `this.style` → Swift
//   `self.pathStyle`). The inherited `Displayable.style` (CommonStyleProps) is kept in sync with the
//   common subset via `_syncCommonStyle()` so the inherited Displayable machinery
//   (`shouldBePainted` / `getPaintRect`, which read `self.style`) stays correct.

import Foundation

// upstream imports (resolved to the ported modules):
// import Displayable, { DisplayableProps, CommonStyleProps, DEFAULT_COMMON_STYLE,
//   DisplayableStatePropNames, DEFAULT_COMMON_ANIMATION_PROPS } from './Displayable';
// import Element, {ElementAnimateConfig, ElementCommonState,
//   IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE} from '../Element';
// import PathProxy from '../core/PathProxy';
// import * as pathContain from '../contain/path';    → `path` enum (Contain/path.swift); call
//   sites module-qualify as `ZRenderKit.path.*` (the enum name collides with `self.path`).
// import { PatternObject } from './Pattern';          → Pattern
// import { Dictionary, PropType, MapToType } from '../core/types';
// import BoundingRect from '../core/BoundingRect';
// import { LinearGradientObject } from './LinearGradient';   → LinearGradient
// import { RadialGradientObject } from './RadialGradient';   → RadialGradient
// import { defaults, keys, extend, clone, isString, createObject } from '../core/util';  → util.*
// import Animator from '../animation/Animator';
// import { lum } from '../tool/color';               → color.lum
// import { DARK_LABEL_COLOR, LIGHT_LABEL_COLOR, DARK_MODE_THRESHOLD, LIGHTER_LABEL_COLOR } from '../config';
// import { REDRAW_BIT, SHAPE_CHANGED_BIT, STYLE_CHANGED_BIT } from './constants';
// import { TRANSFORMABLE_PROPS } from '../core/Transformable';

// PORT-NOTE: upstream `ZRColor` union `string | PatternObject | LinearGradientObject |
//   RadialGradientObject`. Modeled as a tagged enum (no untagged unions in Swift). Gradient/Pattern
//   paint resolution (rendering) is deferred (STUB).
public enum ZRColor {
    case string(String)
    case linearGradient(LinearGradient)
    case radialGradient(RadialGradient)
    case pattern(Pattern)
}

// PORT-NOTE: upstream `lineDash?: false | number[] | 'solid' | 'dashed' | 'dotted'`. Tagged enum.
//   `true` is not supported (upstream); `false`/`null`/`undefined` are the same.
public enum LineDash {
    case `false`
    case values([Double])   // number[]
    case solid
    case dashed
    case dotted
}

// upstream: interface PathStyleProps extends CommonStyleProps { ... }
//   FLATTENED into one struct (CommonStyleProps fields + path fields) — see the STYLE DECISION
//   header note. Stored on `Path` as `self.pathStyle` (upstream `this.style`).
public struct PathStyleProps {
    // ---- CommonStyleProps fields (upstream: `extends CommonStyleProps`) ----
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

    // ---- PathStyleProps own fields ----
    public var fill: ZRColor?
    public var stroke: ZRColor?
    public var decal: Pattern?   // upstream: PatternObject

    /// Still experimental, not works weel on arc with edge cases(large angle).
    public var strokePercent: Double?
    public var strokeNoScale: Bool?
    public var fillOpacity: Double?
    public var strokeOpacity: Double?

    /// `true` is not supported.
    /// `false`/`null`/`undefined` are the same.
    /// `false` is used to remove lineDash in some
    /// case that `null`/`undefined` can not be set.
    /// (e.g., emphasis.lineStyle in echarts)
    public var lineDash: LineDash?
    public var lineDashOffset: Double?

    public var lineWidth: Double?
    public var lineCap: String?   // upstream: CanvasLineCap
    public var lineJoin: String?  // upstream: CanvasLineJoin

    public var miterLimit: Double?
    /// Paint order, if do stroke first. Similar to SVG paint-order
    /// https://developer.mozilla.org/en-US/docs/Web/SVG/Attribute/paint-order
    public var strokeFirst: Bool?

    public init() {}

    // Keyed access for animateTo({style: {...}}) — mirrors the shape side. Exposes the animatable
    //   fields listed in DEFAULT_PATH_ANIMATION_PROPS: the numeric fields tween directly; the COLOR
    //   fields `fill`/`stroke` (and `shadowColor`) flow as a color string through the Animator's
    //   color-tween path (color.parse → interpolate1DArray → rgba2String), the same path
    //   AnimationSmokeTests drives for `style.fill`.
    // PORT-NOTE: gradient `fill`/`stroke` values ARE keyed for animation (via zrColorToAnimValue → the
    //   Animator's gradient tween); pattern values are not keyed; `lineDash` / `lineCap` / `lineJoin` / `blend`
    //   are not tweened.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "opacity": return opacity
        case "fillOpacity": return fillOpacity
        case "strokeOpacity": return strokeOpacity
        case "lineWidth": return lineWidth
        case "lineDashOffset": return lineDashOffset
        case "lineDash":
            if case .some(.values(let arr)) = lineDash { return arr }
            return nil
        case "strokePercent": return strokePercent
        case "miterLimit": return miterLimit
        case "shadowBlur": return shadowBlur
        case "shadowOffsetX": return shadowOffsetX
        case "shadowOffsetY": return shadowOffsetY
        case "shadowColor": return shadowColor
        case "fill": return zrColorToAnimValue(fill)
        case "stroke": return zrColorToAnimValue(stroke)
        default: return nil
        }
    }

    // PORT-NOTE: this is the per-key setter for BOTH the animated tween path (values arrive as
    //   `Double`) and the untyped per-state style bags that flow through `useState` →
    //   `_transitionState` → `animateToShallow` → `animObjSet` (e.g. `labelGuideHelper`'s
    //   `stateObj.style = getLineStyle()` bag, `ECLine.swift`). Those bags are raw option values, so a
    //   plain `value as? Double` silently DROPS an Int-boxed `lineStyle.width: 2` (the Int-vs-Double
    //   option-read trap) and the String presets of `lineStyle.type`. Coerce at this seam — the same
    //   normalization `Path.attrKV` already applies — so every state bag benefits.
    public mutating func animationSet(_ key: String, _ value: Any?) {
        switch key {
        case "opacity": if let v = coerceToDouble(value) { opacity = v }
        case "fillOpacity": if let v = coerceToDouble(value) { fillOpacity = v }
        case "strokeOpacity": if let v = coerceToDouble(value) { strokeOpacity = v }
        case "lineWidth": if let v = coerceToDouble(value) { lineWidth = v }
        case "lineDashOffset": if let v = coerceToDouble(value) { lineDashOffset = v }
        case "lineDash": if let d = coerceToLineDash(value) { lineDash = d }
        case "strokePercent": if let v = coerceToDouble(value) { strokePercent = v }
        case "miterLimit": if let v = coerceToDouble(value) { miterLimit = v }
        case "shadowBlur": if let v = coerceToDouble(value) { shadowBlur = v }
        case "shadowOffsetX": if let v = coerceToDouble(value) { shadowOffsetX = v }
        case "shadowOffsetY": if let v = coerceToDouble(value) { shadowOffsetY = v }
        case "shadowColor": if let v = value as? String { shadowColor = v }
        case "fill": if let c = animValueToZRColor(value) { fill = c }
        case "stroke": if let c = animValueToZRColor(value) { stroke = c }
        default: break
        }
    }
}

// ZRColor ⟷ animation-value bridge for the color-tween path. The Animator interpolates colors as
// rgba strings (color.parse → interpolate → rgba2String), so `fill`/`stroke` are exposed/accepted
// as color strings (gradients flow through as Gradient objects, see below); pattern colors are not keyed
// (PORT-NOTE: faithful — upstream's color-tween interpolates only color strings + gradients, never patterns).
private func zrColorToAnimValue(_ c: ZRColor?) -> Any? {
    switch c {
    case .some(.string(let s)):
        return s
    // Gradient fill/stroke tweening: hand the Animator the Gradient object — it detects it
    // (util.isGradientObject), parses it to a ParsedGradientObject, and interpolates the stops +
    // geometry, writing back the dict that `animValueToZRColor` reconstructs.
    case .some(.linearGradient(let g)):
        return g
    case .some(.radialGradient(let g)):
        return g
    // PORT-NOTE: pattern fills are not color-tweened — faithful to upstream (patterns fall through the
    //   color-interpolation path, so they are not keyed for animation). Returns nil (no tween).
    default:
        return nil
    }
}
private func animValueToZRColor(_ v: Any?) -> ZRColor? {
    // A ZRColor passthrough: a duration-0 state jump (the emphasis/select default-lift) settles the
    //   track with the RAW target value, which for a lifted default-emphasis fill is a `ZRColor`
    //   (not the interpolated rgba-string the animated path produces). Without this case the lifted
    //   fill was dropped and hover had no visible colour change.
    if let c = v as? ZRColor {
        return c
    }
    if let s = v as? String {
        return .string(s)
    }
    // The Animator writes back a color string (rgba2String); a raw [r,g,b,a] is also accepted
    // defensively and serialized to an rgba string.
    if let arr = v as? [Double], arr.count >= 3 {
        let a = arr.count > 3 ? arr[3] : 1
        return .string("rgba(\(Int(floor(arr[0]))),\(Int(floor(arr[1]))),\(Int(floor(arr[2]))),\(a))")
    }
    // The Animator writes an interpolated gradient back as a `[String: Any]` dict (type / x / y /
    // colorStops / global / x2,y2 | r) — rebuild a Linear/RadialGradient ZRColor from it.
    if let d = v as? [String: Any], let type = d["type"] as? String {
        let stops = (d["colorStops"] as? [[String: Any]] ?? []).map {
            GradientColorStop(offset: $0["offset"] as? Double ?? 0, color: $0["color"] as? String ?? "#000")
        }
        let global = d["global"] as? Bool
        if type == "linear" {
            return .linearGradient(LinearGradient(
                d["x"] as? Double, d["y"] as? Double, d["x2"] as? Double, d["y2"] as? Double, stops, global))
        }
        else if type == "radial" {
            return .radialGradient(RadialGradient(
                d["x"] as? Double, d["y"] as? Double, d["r"] as? Double, stops, global))
        }
    }
    return nil
}

// upstream: export const DEFAULT_PATH_STYLE = defaults({ ... } as PathStyleProps, DEFAULT_COMMON_STYLE);
//   Inlines the DEFAULT_COMMON_STYLE merge (CommonStyleProps defaults) + the path defaults.
public let DEFAULT_PATH_STYLE: PathStyleProps = {
    var s = PathStyleProps()
    // from DEFAULT_COMMON_STYLE:
    s.shadowBlur = 0
    s.shadowOffsetX = 0
    s.shadowOffsetY = 0
    s.shadowColor = "#000"
    s.opacity = 1
    s.blend = "source-over"
    s.zrStyleMagic = true
    // path defaults:
    s.fill = .string("#000")
    s.stroke = nil
    s.strokePercent = 1
    s.fillOpacity = 1
    s.strokeOpacity = 1
    s.lineDashOffset = 0
    s.lineWidth = 1
    s.lineCap = "butt"
    s.miterLimit = 10
    s.strokeNoScale = false
    s.strokeFirst = false
    return s
}()

// PORT-NOTE: upstream `MapToType<PathProps, boolean>` — recursive mapped utility type. Collapsed to
//   a loose `[String: Any]` bag (matches Displayable's DEFAULT_COMMON_ANIMATION_PROPS). Only read by
//   `getAnimationStyleProps` (animation surface deferred, Phase 3).
public let DEFAULT_PATH_ANIMATION_PROPS: [String: Any] = [
    "style": [
        // from DEFAULT_COMMON_ANIMATION_PROPS.style:
        "shadowBlur": true,
        "shadowOffsetX": true,
        "shadowOffsetY": true,
        "shadowColor": true,
        "opacity": true,
        // path:
        "fill": true,
        "stroke": true,
        "strokePercent": true,
        "fillOpacity": true,
        "strokeOpacity": true,
        "lineDashOffset": true,
        "lineWidth": true,
        "miterLimit": true
    ]
]

// PORT-NOTE: interface PathProps extends DisplayableProps { strokeContainThreshold?, ...,
//   style?: PathStyleProps, shape?: Dictionary<any>, autoBatch?, __value?, buildPath? }. The
//   `attr`/`attrKV` setter machinery uses the dynamic `[String: Any]` prop bag (collapsed onto
//   DisplayableProps == ElementProps). Typed-interface fidelity dropped.
public typealias PathProps = DisplayableProps

// PORT-NOTE: PathKey / PathPropertyType — TS `keyof` / `PropType` utility types; no Swift equivalent.

// upstream marker: per-subclass `shape` is a `Dictionary<any>`. Modeled as an existential marker
//   protocol (see the GENERICS DECISION header note). Subclass shape structs conform.
public protocol PathShape {
    // Keyed access to the shape's animatable numeric fields. Upstream `shape` is a plain object
    // animated in place via `shape[key]`; here the value-type struct exposes get/set by key so the
    // animation seam (ShapeAnimationAccessor) can drive `animateTo({shape: {...}})`.
    func animationGet(_ key: String) -> Any?
    mutating func animationSet(_ key: String, _ value: Any?)

    // The shape as a per-key animatable bag, i.e. upstream's plain `shape` object itself.
    // PORT-NOTE: upstream code that snapshots a shape for animation writes `props.shape =
    //   clone(el.shape)` and hands the resulting PLAIN OBJECT to `animateTo` (see
    //   `util/graphic.ts groupTransition`), where `animateToShallow` recurses into it key by key
    //   (`isObject(targetVal)`) and tweens each field. A Swift `PathShape` is a struct, so
    //   `util.isObject` is false for it and the whole shape would be treated as ONE discrete leaf
    //   value — instantly set, never tweened. Exposing the shape as `[String: Any]` restores
    //   upstream's nested per-key recursion; it is also the convention every hand-written call site
    //   already uses (e.g. BarView's `rectShapeAnimShape` -> ["x":…,"y":…,"width":…,"height":…]).
    func animationProps() -> [String: Any]
}

public extension PathShape {
    // Default no-op so shapes not yet wired for keyed animation still compile and behave as before
    // (their shape animation is simply inert until they override these).
    // PORT-NOTE: each *Shape overrides animationGet/animationSet to expose its numeric fields.
    func animationGet(_ key: String) -> Any? { nil }
    mutating func animationSet(_ key: String, _ value: Any?) {}

    // Default: enumerate the struct's stored properties (upstream enumerates the shape object's own
    //   keys in `clone`) and keep those the shape exposes through its own `animationGet` — i.e.
    //   exactly the fields that `animationSet` can write back. Shapes without a keyed accessor yield
    //   an empty bag, which is inert (same as their shape animation being inert today).
    //   Reflection is acceptable here: this runs once per transition snapshot, not per frame.
    func animationProps() -> [String: Any] {
        var props: [String: Any] = [:]
        for child in Mirror(reflecting: self).children {
            guard let key = child.label else { continue }
            if let value = animationGet(key) {
                props[key] = value
            }
        }
        return props
    }
}

// Reference bridge between the by-reference animation machinery and the by-value `Path.shape`
// struct. Upstream animates `shape` (a plain object) in place; in Swift `shape` is a value type,
// so `Path.animationGet("shape")` hands the Animator this accessor, whose keyed set writes back
// into the live `path.shape` and marks the shape dirty — mirroring upstream's in-place mutation.
final class ShapeAnimationAccessor: AnimationTarget {
    unowned let path: Path
    init(_ path: Path) { self.path = path }
    func animationGet(_ key: String) -> Any? {
        return path.shape?.animationGet(key)
    }
    func animationSet(_ key: String, _ value: Any?) {
        guard var s = path.shape else { return }
        s.animationSet(key, value)   // mutate local copy of the value-type struct
        path.shape = s               // write back to the live property
        path.dirtyShape()
    }
}

// Reference bridge between the by-reference animation machinery and the by-value `Path.pathStyle`
// struct — mirrors `ShapeAnimationAccessor` for the style bag. A `Path`'s rich style lives in
// `pathStyle` (PathStyleProps), not the inherited `Displayable.style` (CommonStyleProps), so Path
// routes `animationGet("style")` through THIS accessor (not Displayable's) so e.g. `style.fill`
// resolves against the real PathStyleProps. Keyed set writes back into `path.pathStyle` and marks
// the style dirty (instead of dirtyShape).
final class PathStyleAnimationAccessor: AnimationTarget {
    unowned let path: Path
    init(_ path: Path) { self.path = path }
    func animationGet(_ key: String) -> Any? {
        return path.pathStyle?.animationGet(key)
    }
    func animationSet(_ key: String, _ value: Any?) {
        guard var s = path.pathStyle else { return }
        s.animationSet(key, value)   // mutate local copy of the value-type struct
        path.pathStyle = s           // write back to the live property
        path.dirtyStyle()
    }
    func animationNormalize(_ key: String, _ value: Any?) -> Any? {
        // ElementState style bags use the native ZRColor enum, while upstream state bags contain
        // plain color strings/gradient objects. Normalize the target before Track type inference so
        // hover emphasis is a color tween rather than a discrete immediate assignment.
        if key == "fill" || key == "stroke", let color = value as? ZRColor {
            return zrColorToAnimValue(color)
        }
        return value
    }
}

// The base `Path`'s default shape (upstream `getDefaultShape() { return {} }` — an empty bag).
public struct EmptyPathShape: PathShape {
    public init() {}
}

// PORT-NOTE: PathStatePropNames = DisplayableStatePropNames | 'shape'. The states machinery is
//   Phase 2; collapsed onto Displayable's stub.
public typealias PathStatePropNames = String
// PORT-NOTE: PathState = Pick<PathProps, PathStatePropNames> & { hoverLayer? }. The `shape` field of
//   the state bag is deferred (Phase 2); reuse Displayable's ElementState-based stub.
public typealias PathState = DisplayableState

// upstream: const pathCopyParams = TRANSFORMABLE_PROPS.concat(['invisible','culling','z','z2',
//   'zlevel','parent']). Only used by `update()`'s decal synthesis (stubbed); kept for provenance.
let pathCopyParams: [String] = TRANSFORMABLE_PROPS + [
    "invisible", "culling", "z", "z2", "zlevel", "parent"
]

// upstream: interface Path<Props> { animate(...) overloads; getState / ensureState; states;
//   stateProxy } — declaration-merging of the animation + states surface. `getState`/`ensureState`/
//   `states`/`stateProxy` are provided by Element; the `animate('shape')` overload is exposed via
//   `animateShape` (PORT-NOTE: the TS multi-overload set collapses to Swift's single `animate` signature; the animation seam is ported, Phase 3).

// NOTE (CONVENTIONS §2): upstream `class Path<Props> extends Displayable<Props>`. `Path` is itself
//   subclassed by every shape (Rect/Circle/...), so it CANNOT be `final`; it is a `public class`
//   over the (also non-final) `Displayable` base. In-module shape subclasses override `buildPath` /
//   `getDefaultShape` / `getDefaultStyle` (public overridable within the module).
//
// OPEN: upstream `Path` is the public subclassing seam (`zrender.Path.extend` / `class X extends Path`
//   in user code — e.g. test/pin.html). To keep that faithful for out-of-module consumers (a custom
//   shape that supplies its own `buildPath`), the class and its four designed override points
//   (`init` / `buildPath` / `getDefaultShape` / `getDefaultStyle`) are `open`.
open class Path: Displayable {

    // upstream: path: PathProxy — created lazily by `createPathProxy` (undefined until then).
    public var path: PathProxy!

    public var strokeContainThreshold: Double = 5   // initDefaultProps default

    // This item default to be false. But in map series in echarts,
    // in order to improve performance, it should be set to true,
    // so the shorty segment won't draw.
    public var segmentIgnoreThreshold: Double = 0   // initDefaultProps default

    public var subPixelOptimize: Bool = false       // initDefaultProps default

    // upstream: style: PathStyleProps. Swift cannot re-type the inherited `Displayable.style`
    //   (CommonStyleProps), so the rich style lives here (upstream `this.style` → `self.pathStyle`).
    //   See the STYLE DECISION header note. `_syncCommonStyle()` mirrors the common subset into the
    //   inherited `self.style` for Displayable machinery.
    public var pathStyle: PathStyleProps!

    /// Whether elements can be batched (call `fill()` and `stroke()` only once) if possible.
    /// Users should guarantee batched elements are consecutive in display list (sorted by
    /// zlevel, z, z2) and has the same style, otherwise the effect may be unexpected.
    public var autoBatch: Bool = false              // initDefaultProps default

    private var _rectStroke: BoundingRect?   // upstream: private _rectStroke: BoundingRect

    // PORT-NOTE: upstream `protected _normalState: PathState` narrows the inherited type; states are
    //   stubbed (Phase 2), so Element's `_normalState` is reused.

    private var _decalEl: Path?   // upstream: protected

    // upstream: `shape: Dictionary<any>` — "Must have an initial value on shape." Typed as the
    //   `PathShape` existential (see GENERICS DECISION). Assigned in `_init` via `getDefaultShape()`.
    public var shape: PathShape!

    // ===== morphPath seam (PORT-NOTE: see Tool/morphPath.swift) =====
    // upstream `interface MorphingPath extends Path { __morphT: number }`. Default -1 ("not morphing":
    //   `isMorphing` tests `__morphT >= 0`; upstream's undefined and our -1 both read as false).
    public var __morphT: Double = -1
    // upstream `interface CombineMorphingPath extends Path { childrenRef(); __isCombineMorphing }`.
    public var __isCombineMorphing: Bool = false
    // Upstream `prepareMorphPath` / `combineMorph` monkey-patch `buildPath` (replace) and `childrenRef`
    //   (assign) on the live instance. Swift can't reassign methods, so these typed hooks stand in:
    //   `getUpdatedPathProxy` / `getBoundingRect` call `__morphBuildPath` instead of `buildPath` when set.
    internal var __morphBuildPath: ((PathProxy) -> Void)?
    internal var __morphChildrenRef: (() -> [Path])?

    // upstream `(toPath as CombineMorphingPath).childrenRef()` — added/cleared by `combineMorph`.
    public func childrenRef() -> [Element] {
        return (self.__morphChildrenRef?() ?? []).map { $0 as Element }
    }

    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: protected static initDefaultProps (prototype defaults), applied per-instance.
        //   (strokeContainThreshold / segmentIgnoreThreshold / subPixelOptimize / autoBatch are set
        //   as stored-property defaults above so they are live during `_init`, which runs inside
        //   `super.init`.)
        self.type = "path"
        // pathProto.__dirty = REDRAW_BIT | STYLE_CHANGED_BIT | SHAPE_CHANGED_BIT
        self.__dirty = Double(Int(REDRAW_BIT) | Int(STYLE_CHANGED_BIT) | Int(SHAPE_CHANGED_BIT))
    }

    public override func update() {
        super.update()

        // upstream: when `style.decal` is set, synthesize a hidden `_decalEl: Path` that mirrors this
        //   path's geometry, copies the style + `pathCopyParams`, and is filled with the decal pattern.
        //   Storage adds `getDecalElement()` to the display list right after this element, so the decal
        //   texture paints clipped to the same shape, over the fill.
        let style = self.pathStyle!
        if let decalPattern = style.decal {
            // const decalEl: Path = this._decalEl = this._decalEl || new Path();
            let decalEl: Path = self._decalEl ?? Path()
            self._decalEl = decalEl

            // upstream:
            //   if (decalEl.buildPath === Path.prototype.buildPath) {
            //       decalEl.buildPath = ctx => { this.buildPath(ctx, this.shape); };
            //   }
            // Swift methods are not reassignable; use the `__morphBuildPath` build-hook (honored by
            //   getUpdatedPathProxy/getCachedPathProxy in place of `buildPath`) to copy host geometry.
            if decalEl.__morphBuildPath == nil {
                decalEl.__morphBuildPath = { [weak self] ctx in
                    guard let self = self else { return }
                    self.buildPath(ctx, self.shape, false)
                }
            }

            decalEl.silent = true

            // upstream: for (let key in style) copy every style key onto decalEl.style. PathStyleProps is
            //   a value struct, so a whole-struct copy is equivalent to copying all keys.
            var decalElStyle = style
            // upstream: decalElStyle.fill = style.fill ? style.decal : null;
            decalElStyle.fill = (style.fill != nil) ? .pattern(decalPattern) : nil
            // upstream: decalElStyle.decal = null;
            decalElStyle.decal = nil
            // upstream: decalElStyle.shadowColor = null;
            decalElStyle.shadowColor = nil
            // upstream: style.strokeFirst && (decalElStyle.stroke = null);
            if style.strokeFirst == true { decalElStyle.stroke = nil }
            decalEl.pathStyle = decalElStyle
            decalEl.dirtyStyle()

            // upstream: for (i in pathCopyParams) decalEl[pathCopyParams[i]] = this[pathCopyParams[i]];
            //   pathCopyParams = TRANSFORMABLE_PROPS + ['invisible','culling','z','z2','zlevel','parent'].
            decalEl.copyTransform(self)
            decalEl.invisible = self.invisible
            decalEl.culling = self.culling
            decalEl.z = self.z
            decalEl.z2 = self.z2
            decalEl.zlevel = self.zlevel
            decalEl.parent = self.parent

            // decalEl.__dirty |= REDRAW_BIT;
            decalEl.__dirty = Double(Int(decalEl.__dirty) | Int(REDRAW_BIT))
        }
        else if self._decalEl != nil {
            self._decalEl = nil
        }
    }

    public func getDecalElement() -> Path? {
        return self._decalEl
    }

    internal override func _init(_ props: ElementProps? = nil) {  // upstream: protected
        // Init default properties
        let keysArr = util.keys(props ?? [:])

        self.shape = self.getDefaultShape()
        let defaultStyle = self.getDefaultStyle()
        if let defaultStyle = defaultStyle {
            self.useStyle(defaultStyle)
            // upstream: useStyle(createObject(DEFAULT_PATH_STYLE, defaultStyle)) — the object RETURNED
            //   by getDefaultStyle is laid over DEFAULT_PATH_STYLE by `createObject`, so ITS OWN keys
            //   SHADOW the prototype defaults. The stroke-only line shapes (Line/Polyline/BezierCurve/
            //   Arc/Rose/Trochoid) declare an explicit `fill: null` there to UNSET the '#000' default.
            //   Our PathStyleProps struct can't distinguish "key present == null" from "absent", and
            //   `extendPathStyle` (used by createStyle) skips nil — so that explicit-null `fill` would
            //   NOT override DEFAULT_PATH_STYLE.fill ('#000'), leaving those shapes spuriously
            //   `hasFill()`==true. That defeats the no-fill stroke policy in getBoundingRect()/contain()
            //   (the `!hasFill()` → max(lineWidth, strokeContainThreshold) inflation), so their styled
            //   bounding rect grows by lineWidth/2 instead of strokeContainThreshold/2 (the divergence
            //   documented by GeometryGoldenTests.test_strokeOnly_styledBoundingRect_knownDivergence).
            //   Re-apply the default style's `fill` as the upstream own-key value to restore the shadow.
            //   `fill` is the only DEFAULT_PATH_STYLE field these defaults null out; FILLED shapes don't
            //   override getDefaultStyle, so this is inert for them (their fill stays '#000').
            self.pathStyle.fill = defaultStyle.fill
        }

        for i in 0..<keysArr.count {
            let key = keysArr[i]
            let value = props?[key]
            if key == "style" {
                if self.pathStyle == nil {
                    // PENDING Reuse style object if possible?
                    self.useStyle((value as? PathStyleProps) ?? PathStyleProps())
                }
                else {
                    if let v = value as? PathStyleProps {
                        extendPathStyle(&self.pathStyle, v)
                        self._syncCommonStyle()
                    }
                }
            }
            else if key == "shape" {
                // upstream: extend(this.shape, value). A full typed `PathShape` replaces wholesale; a
                //   partial `[String: Any]` merges only the given keys via each *Shape's keyed
                //   `animationSet` (same seam as attrKV's "shape" branch below), coercing Int/NSNumber →
                //   Double (Int-vs-Double option-read trap).
                if let v = value as? PathShape {
                    self.shape = v
                }
                else if let partial = value as? [String: Any], var s = self.shape {
                    for (innerKey, innerValue) in partial {
                        s.animationSet(innerKey, coerceToDouble(innerValue) ?? innerValue)
                    }
                    self.shape = s
                }
            }
            else {
                super.attrKV(key, value)
            }
        }

        // Create an empty one if no style object exists.
        if self.pathStyle == nil {
            self.useStyle(PathStyleProps())
        }
    }

    // upstream: protected getDefaultStyle(): Props['style'] { return null }
    open func getDefaultStyle() -> PathStyleProps? {
        return nil
    }

    // Needs to override
    // upstream: protected getDefaultShape() { return {} }
    open func getDefaultShape() -> PathShape {
        return EmptyPathShape()
    }

    internal override func canBeInsideText() -> Bool {  // upstream: protected
        return self.hasFill()
    }

    internal override func getInsideTextFill() -> String? {  // upstream: protected
        let pathFill = self.pathStyle.fill
        // if (pathFill !== 'none')
        if !isNoneColor(pathFill) {
            if case .some(.string(let s)) = pathFill {
                let fillLum = color.lum(s, 0)
                // Determin text color based on the lum of path fill.
                // TODO use (1 - DARK_MODE_THRESHOLD)?
                if fillLum > 0.5 {   // TODO Consider background lum?
                    return DARK_LABEL_COLOR
                }
                else if fillLum > 0.2 {
                    return LIGHTER_LABEL_COLOR
                }
                return LIGHT_LABEL_COLOR
            }
            else if pathFill != nil {
                // pathFill is a truthy non-string (gradient / pattern).
                return LIGHT_LABEL_COLOR
            }
        }
        return DARK_LABEL_COLOR
    }

    internal override func getInsideTextStroke(_ textFill: String?) -> String? {  // upstream: protected
        let pathFill = self.pathStyle.fill
        // Not stroke on none fill object or gradient object
        if case .some(.string(let pathFillStr)) = pathFill {
            let zr = self.__zr
            let isDarkMode = (zr != nil && zr!.isDarkMode())
            // PORT-NOTE: upstream `lum(textFill, 0)` tolerates `textFill === undefined`; `color.lum`
            //   takes a non-optional String, so we pass `textFill ?? ""` (parse → nil → lum 0).
            let isDarkLabel = color.lum(textFill ?? "", 0) < DARK_MODE_THRESHOLD
            // All dark or all light.
            if isDarkMode == isDarkLabel {
                return pathFillStr
            }
        }
        return nil
    }

    // When bundling path, some shape may decide if use moveTo to begin a new subpath or closePath
    // Like in circle
    // upstream: buildPath(ctx: PathProxy | CanvasRenderingContext2D, shapeCfg, inBatch?) {}
    //   The renderer seam (CONVENTIONS §9): subclasses emit into the `PathProxy` (the
    //   CanvasRenderingContext2D branch is handled by the native backend). Base is a no-op.
    open func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {}

    /// Large-symbol "boost" hook — the port of zrender `LargeSymbolDraw.afterBrush`'s canvas
    /// `ctx.fillRect(...)` fast path (LargeSymbolDraw.ts:138). When a large-mode symbol path is
    /// small enough to boost (`size[0] < BOOST_SIZE_THRESHOLD`), building one giant PathProxy with
    /// N circle sub-paths and filling it in a single `CGContext.fillPath` is super-linear in the
    /// sub-path count (Core Graphics scan-converts the whole path at once), so a 10⁶-point cloud
    /// never finishes. Upstream sidesteps this by drawing each datum as its own `fillRect` — N cheap
    /// primitive fills instead of one pathological path fill. Here that boost is renderer-agnostic:
    /// a boostable path returns its per-point axis-aligned squares as packed `[x, y, w, h, ...]`
    /// (element-LOCAL coords, NaN/soft-clip already applied) and the native painter issues one
    /// batched `CGContext.fill([CGRect])`. Returns nil for every non-boostable path (normal draw).
    open func largeSymbolBoostRects() -> [Double]? { return nil }

    public func pathUpdated() {
        self.__dirty = Double(Int(self.__dirty) & ~Int(SHAPE_CHANGED_BIT))
    }

    @discardableResult
    public func getUpdatedPathProxy(_ inBatch: Bool = false) -> PathProxy {
        // Update path proxy data to latest.
        if self.path == nil { self.createPathProxy() }
        _ = self.path.beginPath()
        // morphPath seam: `buildPath` may be replaced by the interpolating morph builder.
        if let morphBuildPath = self.__morphBuildPath {
            morphBuildPath(self.path)
        }
        else {
            self.buildPath(self.path, self.shape, inBatch)
        }
        return self.path
    }

    /// Cached path proxy for the per-frame render path. Mirrors upstream `canvas/graphic.ts`'s
    /// `brushPath` (line 204): the PathProxy command buffer is rebuilt ONLY on first draw or when
    /// SHAPE_CHANGED_BIT is set — otherwise the existing buffer is reused and just replayed via
    /// `rebuildPath`. This is what keeps a moving-but-not-reshaping element (e.g. 5000 circles that
    /// only translate) cheap: `getUpdatedPathProxy` instead rebuilds the geometry every frame, which
    /// dominated the per-frame cost. Honors the morph seam exactly like `getUpdatedPathProxy`.
    public func getCachedPathProxy(_ inBatch: Bool = false) -> PathProxy {
        var firstInvoke = false
        if self.path == nil {
            firstInvoke = true
            self.createPathProxy()
        }
        if firstInvoke || self.shapeChanged() {
            _ = self.path.beginPath()
            if let morphBuildPath = self.__morphBuildPath {
                morphBuildPath(self.path)
            }
            else {
                self.buildPath(self.path, self.shape, inBatch)
            }
            self.pathUpdated()
        }
        return self.path
    }

    public func createPathProxy() {
        self.path = PathProxy(false)
    }

    public func hasStroke() -> Bool {
        let style = self.pathStyle!
        let stroke = style.stroke
        // !(stroke == null || stroke === 'none' || !(style.lineWidth > 0))
        let strokeIsNone = stroke == nil || isNoneColor(stroke)
        let lineWidthPositive = (style.lineWidth ?? 0) > 0
        return !(strokeIsNone || !lineWidthPositive)
    }

    public func hasFill() -> Bool {
        let style = self.pathStyle!
        let fill = style.fill
        // fill != null && fill !== 'none'
        return fill != nil && !isNoneColor(fill)
    }

    // `open` (not merely `public override`): `getBoundingRect` is a subclassing seam for out-of-module
    //   Path subclasses that cache/derive their own rect (e.g. EChartsKit's LargeSymbolPath, which
    //   ignores stroke and derives the rect from its packed points — faithful to upstream).
    open override func getBoundingRect() -> BoundingRect? {
        var rect = self._rect
        let style = self.pathStyle!
        let needsUpdateRect = (rect == nil)
        if needsUpdateRect {
            var firstInvoke = false
            if self.path == nil {
                firstInvoke = true
                // Create path on demand.
                self.createPathProxy()
            }
            let path = self.path!
            if firstInvoke || (Int(self.__dirty) & Int(SHAPE_CHANGED_BIT)) != 0 {
                _ = path.beginPath()
                // morphPath seam: `buildPath` may be replaced by the interpolating morph builder.
                if let morphBuildPath = self.__morphBuildPath {
                    morphBuildPath(path)
                }
                else {
                    self.buildPath(path, self.shape, false)
                }
                self.pathUpdated()
            }
            rect = path.getBoundingRect()
        }
        self._rect = rect

        if self.hasStroke() && self.path != nil && self.path.len() > 0 {
            // Needs update rect with stroke lineWidth when
            // 1. Element changes scale or lineWidth
            // 2. Shape is changed
            if self._rectStroke == nil {
                self._rectStroke = rect!.clone()
            }
            let rectStroke = self._rectStroke!
            if self.__dirty != 0 || needsUpdateRect {
                rectStroke.copy(rect!)
                // PENDING, Min line width is needed when line is horizontal or vertical
                let lineScale = (style.strokeNoScale ?? false) ? self.getLineScale() : 1
                // FIXME Must after updateTransform
                var w = style.lineWidth ?? 0

                // Only add extra hover lineWidth when there are no fill
                if !self.hasFill() {
                    // PORT-NOTE: upstream `strokeContainThreshold == null ? 4 : strokeContainThreshold`;
                    //   our `strokeContainThreshold` is a non-optional Double (prototype default 5).
                    let strokeContainThreshold = self.strokeContainThreshold
                    w = Swift.max(w, strokeContainThreshold)
                }
                // Consider line width
                // Line scale can't be 0;
                if lineScale > 1e-10 {
                    rectStroke.width += w / lineScale
                    rectStroke.height += w / lineScale
                    rectStroke.x -= w / lineScale / 2
                    rectStroke.y -= w / lineScale / 2
                }
            }

            // Return rect with stroke
            return rectStroke
        }

        return rect
    }

    // `open` (subclassing seam): a custom Path (e.g. LargeSymbolPath) overrides `contain` to run its
    //   own hit-test (findDataIndex) instead of fill/stroke winding.
    open override func contain(_ x: Double, _ y: Double) -> Bool {
        let localPos = self.transformCoordToLocal(x, y)
        let rect = self.getBoundingRect()
        let style = self.pathStyle!
        let x = localPos[0]
        let y = localPos[1]

        if let rect = rect, rect.contain(x, y) {
            let pathProxy = self.path
            if self.hasStroke() {
                let lineWidth = style.lineWidth ?? 0
                let lineScale = (style.strokeNoScale ?? false) ? self.getLineScale() : 1
                // Line scale can't be 0;
                if lineScale > 1e-10 {
                    // Only add extra hover lineWidth when there are no fill
                    var lw = lineWidth
                    if !self.hasFill() {
                        lw = Swift.max(lineWidth, self.strokeContainThreshold)
                    }
                    // pathContain.containStroke(pathProxy, lineWidth / lineScale, x, y)
                    // NOTE: the `contain/path` enum is named `path` (upstream file name), which
                    //   collides with the instance property `self.path`; module-qualify to reach it.
                    if let pathProxy = pathProxy,
                        ZRenderKit.path.containStroke(pathProxy, lw / lineScale, x, y) {
                        return true
                    }
                }
            }
            if self.hasFill() {
                // return pathContain.contain(pathProxy, x, y)
                if let pathProxy = pathProxy {
                    return ZRenderKit.path.contain(pathProxy, x, y)
                }
            }
        }
        return false
    }

    /// Shape changed
    // `open` (subclassing seam): a custom Path overrides `dirtyShape` to invalidate its own caches
    //   (e.g. LargeSymbolPath's derived bounding rect) before delegating to `super`.
    open func dirtyShape() {
        self.__dirty = Double(Int(self.__dirty) | Int(SHAPE_CHANGED_BIT))
        if self._rect != nil {
            self._rect = nil
        }
        if let decalEl = self._decalEl {
            decalEl.dirtyShape()
        }
        self.markRedraw()
    }

    public override func dirty() {
        self.dirtyStyle()
        self.dirtyShape()
    }

    /// Alias for animate('shape')
    @discardableResult
    public func animateShape(_ loop: Bool) -> Animator<Any> {
        // PORT-NOTE: returns the real Animator from Element.animate('shape') (the Phase 3 animation seam is ported).
        return self.animate("shape", loop)
    }

    // Override updateDuringAnimation
    public override func updateDuringAnimation(_ targetKey: String) {
        if targetKey == "style" {
            self.dirtyStyle()
        }
        else if targetKey == "shape" {
            self.dirtyShape()
        }
        else {
            self.markRedraw()
        }
    }

    // One reusable accessor per Path (holds an unowned back-ref — no retain cycle).
    private lazy var _shapeAnimationAccessor = ShapeAnimationAccessor(self)
    // The Path-level style accessor bridges `pathStyle` (PathStyleProps), overriding Displayable's
    //   `style` (CommonStyleProps) accessor so `animateTo({style:{fill}})` resolves correctly.
    private lazy var _pathStyleAnimationAccessor = PathStyleAnimationAccessor(self)

    // Expose the `shape` (and `style`) sub-bags to the animation machinery. Upstream resolves
    // `this.shape` / `this.style` dynamically; here `animationGet` returns the reference accessor so
    // animateToShallow can recurse into the sub-bag's keys (e.g. {shape: {height: 10}} /
    // {style: {fill: 'red'}}). `style` is routed through the Path-level accessor (pathStyle), NOT
    // Displayable's (whose CommonStyleProps lacks fill/stroke).
    public override func animationGet(_ key: String) -> Any? {
        if key == "shape" {
            return _shapeAnimationAccessor
        }
        if key == "style" {
            return _pathStyleAnimationAccessor
        }
        // `__morphT` is a plain animatable scalar on the path (upstream `MorphingPath.__morphT`),
        // driven by `morphPath()`'s `animateTo({__morphT: 1})`. Expose it so the animator gets a
        // real start value (nil would make the track inert — the morph never runs).
        if key == "__morphT" {
            return __morphT
        }
        return super.animationGet(key)
    }

    public override func animationSet(_ key: String, _ value: Any?) {
        if key == "__morphT" {
            if let v = value as? Double { self.__morphT = v }
            return
        }
        if key == "shape" {
            // Whole-shape direct assign (the non-animated branch of animateToShallow).
            if let s = value as? PathShape {
                self.shape = s
                self.dirtyShape()
            }
            return
        }
        if key == "style" {
            // Whole-style direct assign (the non-animated branch of animateToShallow).
            if let s = value as? PathStyleProps {
                self.pathStyle = s
                self._syncCommonStyle()
                self.dirtyStyle()
            }
            return
        }
        super.animationSet(key, value)
    }

    // upstream: animate(key, loop) { let target = key ? this[key] : this; ... }
    // Element's base `animate` targets `self` for every key (it can't reach the value-type sub-bags);
    // a Path's `shape` / `style` ARE animatable sub-bags, so route the Animator at the reference
    // accessor that bridges them (the same accessors `animateTo` recurses into). This makes the manual
    // `el.animate('shape')` / `el.animate('style')` form work exactly like upstream (e.g. a looping
    // `animate('style', true).when(t, {strokePercent: 1})`), writing back into `path.shape`/`pathStyle`.
    @discardableResult
    public override func animate(_ key: String? = nil, _ loop: Bool? = nil, _ allowDiscreteAnimation: Bool? = nil) -> Animator<Any> {
        let target: Any
        if key == "shape" {
            target = self._shapeAnimationAccessor
        } else if key == "style" {
            target = self._pathStyleAnimationAccessor
        } else {
            return super.animate(key, loop, allowDiscreteAnimation)
        }
        let animator = Animator<Any>(target, loop ?? false, allowDiscreteAnimation)
        animator.targetName = key
        self.addAnimator(animator, key ?? "")
        return animator
    }

    // Overwrite attrKV
    internal override func attrKV(_ key: String, _ value: Any?) {  // upstream: protected
        // FIXME
        if key == "shape" {
            if let v = value as? PathShape {
                _ = self.setShape(v)
            }
            else if let partial = value as? [String: Any], var s = self.shape {
                // upstream: `extend(this.shape, obj)` — merge only the given keys into the existing
                //   shape (basicTransition's disabled-animation instant-set path calls
                //   `el.attr(["shape": ["height": 100.0]])` with a partial dict, not a full `PathShape`).
                // Coerce Int/NSNumber → Double before handing to animationSet: each *Shape's
                //   `animationSet` only accepts `Double` (e.g. RectShape's `guard let v = value as?
                //   Double`), so an Int-boxed literal (e.g. `["height": 100]`) would otherwise be
                //   silently dropped — the known Int-vs-Double option-read trap.
                for (innerKey, innerValue) in partial {
                    s.animationSet(innerKey, coerceToDouble(innerValue) ?? innerValue)
                }
                self.shape = s
                self.dirtyShape()
            }
        }
        else if key == "style", let partial = value as? [String: Any], var s = self.pathStyle {
            // upstream: routes through Displayable's generic `style` handling, which merges a partial
            //   style object into the existing style (`extend`/`setStyle`). Mirrors the "shape" branch
            //   above: merge only the given keys into the existing `pathStyle` via the same
            //   `PathStyleAnimationAccessor`-style per-key setter (`PathStyleProps.animationSet`),
            //   coercing Int/NSNumber → Double (Int-vs-Double option-read trap — see the "shape"
            //   branch's comment). This unlocks the animation-OFF `el.attr(["style": ["opacity": v]])`
            //   path (e.g. `initProps`/`fadeOutDisplayable` when `animationSet(cfg).duration == 0`),
            //   which previously fell into the `else` below and was silently dropped (a `PathStyleProps`
            //   cast failure), leaving pieces stuck at their construction-time opacity (e.g. invisible
            //   funnel pieces built with opacity 0 for the fade-in).
            for (innerKey, innerValue) in partial {
                s.animationSet(innerKey, coerceToDouble(innerValue) ?? innerValue)
            }
            self.pathStyle = s
            self.dirtyStyle()
        }
        else {
            // PORT-NOTE (deferred): upstream routes the `style` key through `super.attrKV` → Displayable,
            //   which types the value as CommonStyleProps. A FULL `PathStyleProps` set via `attr('style', …)`
            //   will not round-trip through Displayable's CommonStyleProps handler; style is set via
            //   `_init` opts on the critical path. Edge case deferred (no known caller passes a full
            //   `PathStyleProps` through `attr`/`attrKV` post-construction; only the partial-dict form
            //   above is exercised).
            super.attrKV(key, value)
        }
    }

    // upstream overloads: setShape(obj) / setShape(key, value)
    @discardableResult
    public func setShape(_ obj: PathShape) -> Self {
        // upstream: extend(shape, keyOrObj). For the typed existential we replace wholesale.
        // PORT-NOTE: upstream merges into the existing shape; replacement is acceptable for the
        //   typed-struct model (subclasses construct a full shape).
        self.shape = obj
        self.dirtyShape()
        return self
    }

    @discardableResult
    public func setShape(_ key: String, _ value: Any?) -> Self {
        // upstream: setShape(key, value) { this.shape[key] = value; this.dirtyShape(); }
        //   The typed value-type `PathShape` exposes keyed mutation via `animationSet` (each *Shape
        //   overrides it for its numeric fields — the same seam `ShapeAnimationAccessor` drives).
        //   Coerce Int/NSNumber → Double before the set (Int-vs-Double option-read trap: each *Shape's
        //   `animationSet` only accepts `Double`, so an Int-boxed literal would otherwise be dropped).
        if var s = self.shape {
            s.animationSet(key, coerceToDouble(value) ?? value)
            self.shape = s
        }
        self.dirtyShape()
        return self
    }

    /// If shape changed. used with dirtyShape
    public func shapeChanged() -> Bool {
        return (Int(self.__dirty) & Int(SHAPE_CHANGED_BIT)) != 0
    }

    /// Create a path style object with default values in it's prototype.
    /// @override
    // upstream: createStyle(obj?: Props['style']) { return createObject(DEFAULT_PATH_STYLE, obj) }
    //   OVERLOAD (not override) of Displayable.createStyle(CommonStyleProps?) — different param /
    //   return type. Builds from DEFAULT_PATH_STYLE.
    public func createStyle(_ obj: PathStyleProps? = nil) -> PathStyleProps {
        var style = DEFAULT_PATH_STYLE
        if let obj = obj {
            extendPathStyle(&style, obj)
        }
        return style
    }

    /// Replace style property. OVERLOAD of Displayable.useStyle(CommonStyleProps).
    public func useStyle(_ obj: PathStyleProps) {
        var obj = obj
        if !obj.zrStyleMagic {
            obj = self.createStyle(obj)
        }
        self.pathStyle = obj
        self._syncCommonStyle()
        self.dirtyStyle()
    }

    /// Merge `obj` into the current style. OVERLOAD of Displayable.setStyle(CommonStyleProps).
    // upstream: Displayable.setStyle (Displayable.ts:400) — `extend(this.style, obj)`; the
    //   Path-level style is `PathStyleProps`, so the merge goes through `extendPathStyle` (skips nil
    //   source fields, preserving already-set target values) rather than a wholesale replace. Consumed
    //   by tool/path.ts:495 clonePath.
    @discardableResult
    public func setStyle(_ obj: PathStyleProps) -> Self {
        var s = self.pathStyle!
        extendPathStyle(&s, obj)
        self.pathStyle = s
        self._syncCommonStyle()
        self.dirtyStyle()
        return self
    }

    // Mirror the CommonStyleProps subset of `pathStyle` into the inherited `Displayable.style` so the
    // inherited machinery (shouldBePainted / getPaintRect) reads correct shadow / opacity / blend.
    // PORT-NOTE: a Swift-only bridge — upstream has a single `this.style` object.
    private func _syncCommonStyle() {
        var c = CommonStyleProps()
        c.shadowBlur = self.pathStyle.shadowBlur
        c.shadowOffsetX = self.pathStyle.shadowOffsetX
        c.shadowOffsetY = self.pathStyle.shadowOffsetY
        c.shadowColor = self.pathStyle.shadowColor
        c.opacity = self.pathStyle.opacity
        c.blend = self.pathStyle.blend
        c.zrStyleMagic = self.pathStyle.zrStyleMagic
        self.style = c
    }

    internal override func _innerSaveToNormal(_ toState: ElementState) {  // upstream: protected
        super._innerSaveToNormal(toState)
        // PORT-NOTE: not the live path — state save/apply routes through Element's useState→_stateApply→
        //   animateTo (mirrors Displayable's siblings). Upstream's faithful body clones the current `shape`
        //   into `_normalState.shape` (`extend({}, this.shape)`) when the target state changes shape.
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
        // PORT-NOTE: not the live path (see the useState routing note above). Upstream's faithful body
        //   merges/animates the target `shape` (with the IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE early-out,
        //   primary-prop split, and `dirtyShape`).
        _ = IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE
    }

    internal override func _mergeStates(_ states: [ElementState]) -> ElementState {  // upstream: protected
        let mergedState = super._mergeStates(states)
        // PORT-NOTE: not the live path (see the useState routing note above). Upstream's faithful body
        //   merges each state's `shape` into a single `mergedShape` (via `_mergeStyle`) and assigns it onto `mergedState`.
        return mergedState
    }

    public override func getAnimationStyleProps() -> [String: Any] {
        return DEFAULT_PATH_ANIMATION_PROPS
    }

    /// If path shape is zero area
    public func isZeroArea() -> Bool {
        return false
    }

    // upstream: static extend<Shape>(defaultProps) { class Sub extends Path { ... }; return Sub }
    // PORT-NOTE (unportable): the deprecated `Path.extend(...)` synthesizes a NEW subclass at runtime
    //   (assigning `buildPath` / `init` / style / shape from a config object). Swift has no runtime class
    //   synthesis; the upstream JSDoc already marks it `@DEPRECATED Use class extends`. Shapes are
    //   ported as real `final class … : Path` subclasses (Phase 1, 4b). Permanently not translated.

    // upstream: protected static initDefaultProps = (function () { pathProto.type = 'path';
    //   pathProto.strokeContainThreshold = 5; pathProto.segmentIgnoreThreshold = 0;
    //   pathProto.subPixelOptimize = false; pathProto.autoBatch = false;
    //   pathProto.__dirty = REDRAW_BIT | STYLE_CHANGED_BIT | SHAPE_CHANGED_BIT })()
    //   — replaced by the stored-property initializers above + the `init` override.
}

// upstream: pathFill !== 'none' / stroke === 'none' — treats the string 'none' specially.
//   Returns true iff the color is the string "none".
private func isNoneColor(_ c: ZRColor?) -> Bool {
    if case .some(.string("none")) = c {
        return true
    }
    return false
}

// Int/NSNumber → Double coercion helper for the `attrKV` partial-shape merge (see the Int-vs-Double
//   option-read trap: `value as? Double` returns nil on an Int-boxed literal, silently dropping it).
private func coerceToDouble(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let n = value as? NSNumber { return n.doubleValue }
    return nil
}

// Any → LineDash for the untyped per-state style bags handed to `PathStyleProps.animationSet`.
//   upstream `lineDash?: false | number[] | 'solid' | 'dashed' | 'dotted'` — the option-level
//   `lineStyle.type` presets arrive as Strings and the arrays as Int/Double mixes, neither of which a
//   bare `value as? [Double]` accepts.
private func coerceToLineDash(_ value: Any?) -> LineDash? {
    if let d = value as? LineDash { return d }
    if let b = value as? Bool { return b ? nil : LineDash.false }
    if let s = value as? String {
        switch s {
        case "solid": return .solid
        case "dashed": return .dashed
        case "dotted": return .dotted
        default: return nil
        }
    }
    if let arr = value as? [Double] { return .values(arr) }
    if let arr = value as? [Any] {
        let nums = arr.compactMap { coerceToDouble($0) }
        return nums.count == arr.count ? .values(nums) : nil
    }
    return nil
}

// extend(target, source) over PathStyleProps' known fields (value-copy of non-nil fields).
// PORT-NOTE: upstream `extend` copies all own enumerable keys (dynamic bag); here we copy the known
//   PathStyleProps fields only.
func extendPathStyle(_ target: inout PathStyleProps, _ source: PathStyleProps) {
    // common fields
    if source.shadowBlur != nil { target.shadowBlur = source.shadowBlur }
    if source.shadowOffsetX != nil { target.shadowOffsetX = source.shadowOffsetX }
    if source.shadowOffsetY != nil { target.shadowOffsetY = source.shadowOffsetY }
    if source.shadowColor != nil { target.shadowColor = source.shadowColor }
    if source.opacity != nil { target.opacity = source.opacity }
    if source.blend != nil { target.blend = source.blend }
    // NOTE: zrStyleMagic is intentionally NOT copied by `extend` upstream (it is a created-style
    //   marker, stamped by `createStyle`, not an `extend`-able field).
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
}

// upstream: export default Path;
