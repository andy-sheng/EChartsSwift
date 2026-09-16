// Ported from zrender/src/Element.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. This is the keystone of the scene graph. The parts needed
// to build and render a STATIC scene graph are translated faithfully; the rest is STUBBED
// with `// note` (faithful signatures, deferred to later phases) so it compiles.
//
// TRANSLATED (render-only):
//   - class Element extends Transformable (+ Eventful composed via forwarding)
//   - id / name / type; the __dirty bit machinery (REDRAW_BIT from graphic/constants)
//   - parent / __zr / __hostTarget hierarchy; addSelfToZr / removeSelfFromZr plumbing
//   - clipPath: getClipPath / setClipPath / removeClipPath / _clipPath / _attachComponent
//   - getBoundingRect / getPaintRect; drift / update / beforeUpdate / afterUpdate
//   - attr / attrKV setter machinery; hide / show; markRedraw / dirty
//   - ignore / silent / ignoreHostSilent / isGroup / draggable / dragging / ignoreClip
//   - isSilent; the inside/outside text-color hooks (canBeInsideText / getInside*/getOutside*)
//   - text-content / text-guide attach plumbing (setTextContent / setTextGuideLine / ...)
//
// STUBBED AT FIRST PORT (note: all now ported in later phases):
//   - the animation surface (animate / addAnimator / animateTo / animateFrom / stopAnimation /
//     _transitionState and the module-level animateTo / animateToShallow / copyValue family)
//     — Animator is a Phase-3 stub.
//   - updateInnerText / ZRText (Text) integration — graphic/Text.ts is Phase 2.
//   - the states / emphasis / blur / select machinery (saveCurrentToNormalState / useState /
//     useStates / _applyStateObj / _mergeStates / ...) — Phase 2.
//
// NOTE: z / z2 / zlevel / invisible / cursor mentioned in the task brief live on
// `graphic/Displayable.ts` (the next file), NOT on `Element` — they are intentionally absent here.

import Foundation

// upstream imports (resolved to the ported Core/graphic modules):
// import Transformable, {TRANSFORMABLE_PROPS, TransformProp} from './core/Transformable';
// import Animator, {cloneValue} from './animation/Animator';  (Phase-3 stub)
// import { AnimationEasing } from './animation/easing';
// import { ZRenderType } from './zrender';  → real type: `typealias ZRenderType = ZRender` (ZRender.swift)
// import Path from './graphic/Path';                     → ported: ZRenderKit Graphic/Path.swift
// import ZRText, { DefaultTextStyle } from './graphic/Text';  → forward-declared placeholder (Phase 2)
// import Polyline from './graphic/shape/Polyline';       → ported: ZRenderKit Graphic/Shape/Polyline.swift
// import Group from './graphic/Group';                   → ported: ZRenderKit Graphic/Group.swift
// import BoundingRect, { RectLike } from './core/BoundingRect';
// import Eventful from './core/Eventful';
// import Point from './core/Point';
// import { LIGHT_LABEL_COLOR, DARK_LABEL_COLOR } from './config';
// import { parse, stringify } from './tool/color';  → color.parse / color.stringify
// import { REDRAW_BIT } from './graphic/constants';
// import { invert } from './core/matrix';
// import { guid, isObject, keys, extend, indexOf, logError, mixin, isArrayLike,
//          isTypedArray, isGradientObject, filter, reduce } from './core/util';  → util.*
// import { calculateTextPosition, TextPositionCalculationResult, parsePercent } from './contain/text';
//   → note: contain/text.ts is ported (ZRenderKit Contain/ContainText.swift).

public struct ElementAnimateConfig {
    public var duration: Double?
    public var delay: Double?
    public var easing: AnimationEasing?
    public var during: ((_ percent: Double) -> Void)?

    // `done` will be called when all of the animations of the target props are
    // "done" or "aborted", and at least one "done" happened.
    public var done: (() -> Void)?      // upstream: Function
    // `aborted` will be called when all of the animations of the target props are "aborted".
    public var aborted: (() -> Void)?

    public var scope: String?
    /// If force animate. Prevent stop animation and callback immediently when target
    /// values are the same as current values.
    public var force: Bool?
    /// If use additive animation.
    public var additive: Bool?
    /// If set to final state before animation started. (Only available in animateTo)
    public var setToFinal: Bool?

    public init() {}
}

public struct ElementTextConfig {
    // faithful data bag for the ZRText integration (Phase 2). The union-typed
    // fields (`position`, `origin`) are typed `Any?` until contain/text.ts lands.

    /// Position relative to the element bounding rect. @default 'inside'
    /// upstream: BuiltinTextPosition | (number | string)[]
    public var position: Any?

    /// Rotation of the label.
    public var rotation: Double?

    /// Rect that text will be positioned. Default to be the boundingRect of the host element.
    public var layoutRect: RectLike?

    /// Offset of the label.
    public var offset: [Double]?

    /// Origin or rotation. upstream: (number | string)[] | 'center'
    public var origin: Any?

    /// Distance to the rect. @default 5
    public var distance: Double?

    /// If use local user space (apply host's transform). @default false
    public var local: Bool?

    public var insideFill: String?
    public var insideStroke: String?
    public var outsideFill: String?
    public var outsideStroke: String?

    /// Tell zrender I can sure this text is inside or not.
    public var inside: Bool?

    /// Auto calculate overflow area by `textConfig.layoutRect` (if any) or `host.boundingRect`.
    public var autoOverflowArea: Bool?

    public init() {}
}

public struct ElementTextGuideLineConfig {
    /// Anchor for text guide line.
    public var anchor: Point?
    /// If above the target element.
    public var showAbove: Bool?
    /// Candidates of connectors. upstream: ('left'|'top'|'right'|'bottom')[]
    public var candidates: [String]?

    public init() {}
}

// upstream: export class ElementEvent. Modeled as a `final class` (reference type) — critical for
//   event bubbling: a listener that sets `e.cancelBubble = true` must mutate the SAME packet the
//   dispatch loop (`Handler.dispatchToElement`) re-reads after each `el.trigger`, so stopPropagation
//   works. (A struct would hand each listener a copy, leaving the loop's packet untouched.)
public final class ElementEvent {
    // ElementEvent references ZRRawEvent and the gesture/touch fields, which belong
    // to the native event-dispatch seam (CONVENTIONS §9), not the render-only milestone. Minimal
    // placeholder so `drift`'s optional `e` param keeps a faithful type.
    public var type: ElementEventName?
    public var target: Element?
    public var topTarget: Element?
    public var cancelBubble: Bool = false
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    // `event` is the underlying ZRRawEvent (browser DOM event), modeled as Any? at
    //   the native event seam (CONVENTIONS §9). Draggable forwards it to dispatchToElement.
    public var event: Any?
    // The remaining `Handler.makeEventPacket` fields (gesture / wheel / button). Optional so an
    //   ElementEvent built outside the dispatch path (e.g. `drift`) leaves them nil.
    public var gestureEvent: String?
    public var pinchX: Double?
    public var pinchY: Double?
    public var pinchScale: Double?
    public var wheelDelta: Double?
    public var zrByTouch: Bool?
    public var which: Double?
    // upstream: `stop: stopEvent` — a bound method that preventDefaults the underlying DOM event.
    public var stop: (() -> Void)?
    public init() {}
}

// ElementEventCallback / CbThis<Ctx, Impl> — `this`-bound event callback typing.
//   Collapses to the `EventCallback` defined in Core/Eventful.swift (event seam, CONVENTIONS §9).
// interface ElementEventHandlerProps — the `onclick`/`ondrag`/... handler-prop set.
//   These are the native event seam; not modeled in render-only Phase 1.

// interface ElementProps extends Partial<ElementEventHandlerProps> & Partial<Pick<
//   Transformable, TransformProp>>. For the `attr` setter machinery, the props bag is modeled
//   as `[String: Any]` (see `attr` / `attrKV` below); the typed-interface fidelity is dropped.
public typealias ElementProps = [String: Any]

// Properties can be used in state.
public let PRESERVED_NORMAL_STATE = "__zr_normal__"
// export const PRESERVED_MERGED_STATE = '__zr_merged__';

fileprivate let PRIMARY_STATES_KEYS: [String] = TRANSFORMABLE_PROPS + ["ignore"]
// upstream: reduce(TRANSFORMABLE_PROPS, (obj, key) => { obj[key] = true; return obj; }, {ignore: false})
fileprivate let DEFAULT_ANIMATABLE_MAP: [String: Bool] = {
    var obj: [String: Bool] = ["ignore": false]
    for key in TRANSFORMABLE_PROPS {
        obj[key] = true
    }
    return obj
}()

// ElementStatePropNames / ElementState / ElementCommonState — `Pick<ElementProps, ...>`
//   utility types. `ElementState` is modeled as a prop bag (`props`), carrying the overrides a named
//   state applies (transform keys as scalars; `shape` / `style` as `[String: Any]` sub-bags — the
//   same shape an `animateTo` target takes).
//
// REFERENCE TYPE: upstream states are plain mutable objects (`el.ensureState('x').x = 1` mutates the
//   stored state in place). A Swift value type would hand `ensureState` a COPY, so the mutation would
//   be lost. `ElementState` is therefore a `class`.
public final class ElementState {
    public var props: [String: Any] = [:]
    public var textConfig: ElementTextConfig?
    public var hoverLayer: Any?   // upstream: boolean | number
    public init() {}

    // Convenience accessors so a state reads like upstream (`state.x = 200`, `state.shape = {...}`).
    // All are stored in `props` (the generic bag the state machinery operates on).
    public var x: Double? { get { props["x"] as? Double } set { props["x"] = newValue } }
    public var y: Double? { get { props["y"] as? Double } set { props["y"] = newValue } }
    public var rotation: Double? { get { props["rotation"] as? Double } set { props["rotation"] = newValue } }
    public var scaleX: Double? { get { props["scaleX"] as? Double } set { props["scaleX"] = newValue } }
    public var scaleY: Double? { get { props["scaleY"] as? Double } set { props["scaleY"] = newValue } }
    /// A partial shape override, as shape-key → value (e.g. `["width": 200]`).
    public var shape: [String: Any]? { get { props["shape"] as? [String: Any] } set { props["shape"] = newValue } }
    /// A partial style override, as style-key → value (e.g. `["fill": ZRColor.string("green")]`).
    public var style: [String: Any]? { get { props["style"] as? [String: Any] } set { props["style"] = newValue } }
    /// upstream: `Pick<ElementProps, ...>` includes `ignore` — a per-state visibility override
    /// (e.g. `label/labelStyle.ts` sets `stateObj.ignore = !stateShow`). Stored in `props` like the
    /// other convenience accessors above.
    public var ignore: Bool? { get { props["ignore"] as? Bool } set { props["ignore"] = newValue } }

    // ADDITIVE (not in upstream `ElementState`, which is an untyped prop bag): a typed side-channel
    // for a `ZRText`'s per-state RICH style. Upstream's `state.style` is the SAME untyped bag used for
    // every Element subclass (Path/Image/...); `ZRText` stores its style in its own `textStyle:
    // TextStyleProps` property (not the inherited `Displayable.style: CommonStyleProps`, see ZRText's
    // STYLE DECISION note in Text.swift), and the generic `style: [String: Any]?` accessor above has
    // no faithful way to carry a typed `TextStyleProps` for `label/labelStyle.swift`'s
    // `setLabelStyle`/`setLabelText` (`stateObj.style = createTextStyle(...)` upstream). This mirrors
    // the existing `textConfig: ElementTextConfig?` precedent just above (also a typed field bolted
    // onto the generic bag for the same reason). The live emphasis/blur/select state-APPLICATION path
    // for `ZRText` (reading this field back out when `useState`/`useStates` runs) is not wired yet —
    // (the store/apply seam is noted at the `attrKV` note) — so this is currently a faithful STORE
    // with an application seam left for the interaction-layer phase that lands it.
    public var textStyle: TextStyleProps?
}

// upstream `saveCurrentToNormalState` writes a running animator's FINAL value into the normal state
//   via `animator.saveTo(target)`, where `target` is either the normal state itself (top-level
//   transform props) or `normalState[targetName]` (a `shape` / `style` sub-bag). `saveTo` routes
//   through the dynamic `(target as any)[key] = value`, which the port models as `AnimationTarget`.
//   `ElementState` (top-level, backed by `props`) and `_RefBag` (a sub-bag write-back wrapper)
//   provide that reference-typed keyed set.
extension ElementState: AnimationTarget {
    public func animationGet(_ key: String) -> Any? { return self.props[key] }
    public func animationSet(_ key: String, _ value: Any?) { self.props[key] = value }
}

// A reference-typed wrapper over a value-type `[String: Any]` sub-bag, so `Animator.saveTo` can
//   write the animation's final sub-bag values through `AnimationTarget`; the caller reads `.dict`
//   back out and stores it into the normal state's sub-bag (`normalState.props[targetName]`).
fileprivate final class _RefBag: AnimationTarget {
    var dict: [String: Any]
    init(_ dict: [String: Any]) { self.dict = dict }
    func animationGet(_ key: String) -> Any? { return self.dict[key] }
    func animationSet(_ key: String, _ value: Any?) { self.dict[key] = value }
}

/// Reference view over `Element.extra`, matching zrender's ordinary mutable `el.extra` object.
/// Custom-series transitions animate nested keys through `animationGet("extra")`; returning a copied
/// Swift dictionary would lose every per-frame write, so the accessor writes each key back to the owner.
fileprivate final class _ElementExtraAnimationAccessor: AnimationTarget {
    weak var element: Element?
    init(_ element: Element) { self.element = element }
    func animationGet(_ key: String) -> Any? { element?.extra?[key] }
    func animationSet(_ key: String, _ value: Any?) {
        guard let element else { return }
        var bag = element.extra ?? [:]
        bag[key] = value
        element.extra = bag
    }
}

// TextPositionCalculationResult is now ported in Contain/text.swift; the opaque stub is removed.
public typealias ElementCalculateTextPosition = (
    _ out: TextPositionCalculationResult,
    _ style: ElementTextConfig,
    _ rect: RectLike
) -> TextPositionCalculationResult

// Module scratch buffers (upstream module-level consts).
// tmpTextPosCalcRes / tmpInnerTextTrans support `updateInnerText` (ported, Phase 2 text).
fileprivate let tmpBoundingRect = BoundingRect(0, 0, 0, 0)
fileprivate var tmpInnerTextTrans: [Double] = []


// It indicates a status of the element - whether it should be rendered or have been rendered
// in a hover layer. A falsy value means not in hover layer; a truthy value means in hover layer.
// upstream: InHoverLayerKind = typeof IN_HOVER_LAYER_KIND_NO | typeof IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE
public typealias InHoverLayerKind = Double
// Not in hover layer.
public let IN_HOVER_LAYER_KIND_NO: Double = 0
// In hover layer and only style change when entering hover layer.
public let IN_HOVER_LAYER_KIND_ONLY_STYLE_CHANGE: Double = 1

// upstream: `boolean | 'horizontal' | 'vertical'` — tagged enum (no untagged unions in Swift).
public enum ElementDraggable: Equatable {
    case `false`    // boolean false
    case `true`     // boolean true
    case horizontal
    case vertical
}

// upstream: interface Element extends Transformable, Eventful<...>, ElementEventHandlerProps {}
// (declaration-merging of the mixin method sets). See `mixin(Element, Eventful/Transformable)` below.

// NOTE (CONVENTIONS §2): upstream `class Element extends Transformable`. Element is itself
// subclassed (Displayable, Group, Path, Text, ...), so it CANNOT be `final`; it is a plain
// `public class` over the (also non-final) `Transformable` base.
//
// AnimationTarget: upstream the animator reads/writes props via the dynamic `(this as any)[key]`.
//   Swift has no dynamic member access, so `Element` conforms to `AnimationTarget` (Animator.swift)
//   to expose the keyed get/set the animate machinery needs. The base covers Element / Transformable
//   primary props (TRANSFORMABLE_PROPS + `ignore`). note: subclasses (Displayable/Path) now
//   override `animationGet`/`animationSet` to expose the value-type `style`/`shape` bags via keyed
//   accessors, so nested-bag animation is wired.
open class Element: Transformable, AnimationTarget {

    public var id: Double = util.guid()
    /// Element type
    public var type: String = "element"

    /// Element name
    public var name: String = ""

    /// If ignore drawing and events of the element object
    public var ignore: Bool = false

    /// Whether to respond to mouse events.
    public var silent: Bool = false

    /// ECharts extended-element flag: keep this element/subtree's authored z values when a component
    /// model propagates its own z. Used by axis-break overlays and other intentionally lifted graphics.
    public var ignoreModelZ: Bool = false

    /// When this element has `__hostTarget` (e.g., this is a `textContent`), whether
    /// its silent is controlled by that host silent.
    public var ignoreHostSilent: Bool = false

    /// 是否是 Group
    public var isGroup: Bool = false

    /// Whether it can be dragged.
    public var draggable: ElementDraggable = .false

    /// Whether is it dragging.
    public var dragging: Bool = false

    // upstream zrender exposes `drift` as an assignable *property* (`Element.prototype.drift`), so
    //   consumers can override the default translate-in-place behavior by writing `el.drift = customFn`
    //   (e.g. echarts `SliderZoomView` sets `handle.attr({ drift: bind(this._onDragMove, ...) })` so the
    //   handle does NOT move itself — the view repositions everything from absolute coords). Swift makes
    //   `drift` a method, which is not reassignable, so this optional closure is the faithful seam: when
    //   set, `drift(dx,dy,e)` calls it *instead of* the default translate (upstream's assigned fn fully
    //   replaces the method). Set to `nil` to restore the default drag-translate behavior.
    public var driftHandler: ((Double, Double, ElementEvent?) -> Void)?

    // upstream: parent: Group
    // upstream narrows `parent` to `Group`; we inherit `Transformable.parent`
    //   (typed `Transformable?`) and cast to `Element`/`Group` at use sites.

    public var animators: [Animator<Any>] = []

    /// If ignore clip from it's parent or hosts. Applied on itself and all it's children.
    public var ignoreClip: Bool = false

    /// If element is used as a component of other element.
    public var __hostTarget: Element?

    /// ZRender instance will be assigned when element is associated with zrender
    public var __zr: ZRenderType?

    // ===== morphPath seam (note: see Tool/morphPath.swift) =====
    // Upstream `combineMorph` monkey-patches `addSelfToZr` / `removeSelfFromZr` with an `after` hook
    //   that adds/removes the split sub-paths. Swift can't reassign methods on a live instance, so
    //   `addSelfToZr` / `removeSelfFromZr` invoke these optional after-hooks at their tail.
    //   `saveAndModifyMethod` / `restoreMethod` set & clear them.
    internal var __morphAddSelfToZrAfter: ((ZRenderType) -> Void)?
    internal var __morphRemoveSelfFromZrAfter: ((ZRenderType) -> Void)?

    /// Dirty bits. From which painter will determine if this displayable object needs brush.
    public var __dirty: Double = REDRAW_BIT

    /// If element was painted on the screen
    public var __isRendered: Bool = false

    /// Whether this element has been moved to the hover layer.
    /// (See upstream for the long [HOVER_LAYER_CONSTRAINTS] discussion.)
    public var __inHover: InHoverLayerKind = IN_HOVER_LAYER_KIND_NO

    public var __clipPaths: [Path]?

    /// path to clip the elements and its children, if it is a group.
    private var _clipPath: Path?     // upstream: private

    /// Attached text element. `position`, `style.textAlign`, `style.textVerticalAlign`
    /// of element will be ignored if textContent.position is set.
    private var _textContent: ZRText?   // upstream: private

    /// Text guide line.
    private var _textGuide: Polyline?   // upstream: private

    /// Config of textContent. Including layout, color, ...etc.
    public var textConfig: ElementTextConfig?

    /// Config for guide line calculating.
    public var textGuideLineConfig: ElementTextGuideLineConfig?

    // FOR ECHARTS
    /// Id for mapping animation
    public var anid: String?

    public var extra: Dictionary<Any>?

    public var currentStates: [String] = []
    // prevStates is for storager in echarts.
    public var prevStates: [String]?
    /// Store of element state. '__normal__' key is preserved for default properties.
    public var states: Dictionary<ElementState> = [:]

    /// Animation config applied on state switching.
    public var stateTransition: ElementAnimateConfig?

    /// Proxy function for getting state with given stateName.
    public var stateProxy: ((_ stateName: String, _ targetStates: [String]?) -> ElementState?)?

    internal var _normalState: ElementState?    // upstream: protected

    // Temporary storage for inside text color configuration.
    private var _innerTextDefaultStyle: DefaultTextStyle?

    /// See upstream — customizable text-position hook (set externally for custom shapes).
    public var calculateTextPosition: ElementCalculateTextPosition?

    // upstream: mixin(Element, Eventful) — Eventful is applied as a MIXIN (not a superclass).
    //   Eventful is a `final class` (CONVENTIONS §2), so it cannot be a Swift superclass of
    //   Element (whose super is Transformable). It is composed here and its full public event
    //   surface (`on`/`off`/`trigger`/`triggerWithContext`) is forwarded below, so `Element`
    //   behaves as `extends Eventful` for the Handler dispatch path
    //   (`el.trigger(eventName, eventPacket)`).
    // POTENTIAL-BUG: retain cycle — once a listener is bound, the inner Eventful stores `ctx = self`
    //   (the Element, to keep the handler's `this` faithful), and Element strongly holds
    //   `_eventful`, forming a cycle. Upstream relies on JS GC; here it is broken when callers
    //   `off()` (which drops the handler list). Listener closures should still capture
    //   `[weak self]` where a real cycle exists (CONVENTIONS §8).
    private let _eventful = Eventful()

    public init(_ props: ElementProps? = nil) {
        super.init()
        self._init(props)
    }

    internal func _init(_ props: ElementProps? = nil) {  // upstream: protected
        // Init default properties
        _ = self.attr(props ?? [:])
    }

    /// Drift element
    /// - dx: dx on the global space
    /// - dy: dy on the global space
    public func drift(_ dx: Double, _ dy: Double, _ e: ElementEvent? = nil) {
        // upstream: an assigned `el.drift = fn` fully replaces the default method body. When a
        //   `driftHandler` is set, delegate to it and skip the built-in translate.
        if let driftHandler = self.driftHandler {
            driftHandler(dx, dy, e)
            return
        }
        var dx = dx
        var dy = dy
        switch self.draggable {
        case .horizontal:
            dy = 0
        case .vertical:
            dx = 0
        default:
            break
        }

        var m = self.transform
        if m == nil {
            m = [1, 0, 0, 1, 0, 0]
            self.transform = m
        }
        // m[4]/m[5] mutate a value-type [Double]; reassign self.transform (CONVENTIONS §3/§4).
        m![4] += dx
        m![5] += dy
        self.transform = m

        self.decomposeTransform()
        self.markRedraw()
    }

    /// Hook before update
    // JavaScript permits views to replace `el.beforeUpdate` per instance. Swift methods are not
    // assignable, so expose the equivalent hook while retaining the upstream lifecycle entry point.
    public var beforeUpdateCallback: (() -> Void)?

    public func beforeUpdate() {
        self.beforeUpdateCallback?()
    }
    /// Hook after update
    public func afterUpdate() {}
    /// Update each frame
    public func update() {
        self.updateTransform()

        if self.__dirty != 0 {
            self.updateInnerText()
        }
    }

    /// Lay out the attached `_textContent`: position it from `textConfig` (position / rotation /
    /// offset / origin) via contain/text `calculateTextPosition`, written into the text's
    /// `innerTransformable` (which `ZRText.getLocalTransform` renders from), and resolve inside/outside
    /// fill+stroke into the text's default style. Storage already adds the attached text to the
    /// display list, so this is what makes `setTextContent` + `textConfig.position` actually render.
    ///
    /// the `autoOverflowArea` / `overflowRect` inverse-transform clamp IS ported (the
    /// overflow area is computed in the text's local coord by inverse-transforming the host-space
    /// layoutRect); the downstream `parseText` overflow/ellipsis engine that consumes `overflowRect`
    /// lives in Text.swift's `calcInnerTextOverflowArea`.
    public func updateInnerText(_ forceUpdate: Bool? = nil) {
        guard let textEl = self._textContent, (!textEl.ignore || (forceUpdate ?? false)) else { return }
        if self.textConfig == nil { self.textConfig = ElementTextConfig() }
        let textConfig = self.textConfig!
        let isLocal = textConfig.local ?? false
        guard let innerTransformable = textEl.innerTransformable else { return }

        var textAlign: TextAlign? = nil
        var textVerticalAlign: TextVerticalAlign? = nil
        var textStyleChanged = false

        // Apply host's transform (local → positioned in host space; else global).
        innerTransformable.parent = isLocal ? self : nil
        var innerOrigin = false
        innerTransformable.copyTransform(textEl)   // reset x/y/rotation from the text

        let hasPosition = textConfig.position != nil
        let autoOverflowArea = textConfig.autoOverflowArea ?? false

        var layoutRect: BoundingRect? = nil
        if autoOverflowArea || hasPosition {
            let lr = tmpBoundingRect
            if let lrc = textConfig.layoutRect {
                lr.copy(BoundingRect(lrc.x, lrc.y, lrc.width, lrc.height))
            }
            else if let br = self.getBoundingRect() {
                lr.copy(br)
            }
            // Attached labels are collected as separate display-list elements. Resolve the host's full
            // ancestor chain here; reading the cached transform can be stale/nil when a symbol group was
            // positioned after its child path last updated (graph nodes then stacked labels at 0,0).
            if !isLocal, let t = self.getComputedTransform() {
                lr.applyTransform(t)
            }
            layoutRect = lr
        }

        // Force-set the attached text's position if `position` is in config.
        if hasPosition, let layoutRect = layoutRect {
            var opts = CalculateTextPositionOpts()
            opts.position = _textConfigPositionOpt(textConfig.position)
            opts.distance = textConfig.distance
            let res: TextPositionCalculationResult
            if let calculateTextPosition = self.calculateTextPosition {
                res = calculateTextPosition(TextPositionCalculationResult(), textConfig, layoutRect)
            }
            else {
                res = ZRenderKit.text.calculateTextPosition(nil, opts, layoutRect)
            }

            innerTransformable.x = res.x
            innerTransformable.y = res.y
            // User align/verticalAlign has higher priority (useful when the text is rotated 90°).
            textAlign = res.align
            textVerticalAlign = res.verticalAlign

            if let origin = textConfig.origin, textConfig.rotation != nil {
                var relOriginX = 0.0
                var relOriginY = 0.0
                if let s = origin as? String, s == "center" {
                    relOriginX = layoutRect.width * 0.5
                    relOriginY = layoutRect.height * 0.5
                }
                else if let arr = origin as? [Double], arr.count >= 2 {
                    relOriginX = ZRenderKit.text.parsePercent(.number(arr[0]), layoutRect.width)
                    relOriginY = ZRenderKit.text.parsePercent(.number(arr[1]), layoutRect.height)
                }
                innerOrigin = true
                innerTransformable.originX = -innerTransformable.x + relOriginX + (isLocal ? 0 : layoutRect.x)
                innerTransformable.originY = -innerTransformable.y + relOriginY + (isLocal ? 0 : layoutRect.y)
            }
        }

        if let rot = textConfig.rotation {
            innerTransformable.rotation = rot
        }

        if let textOffset = textConfig.offset, textOffset.count >= 2 {
            innerTransformable.x += textOffset[0]
            innerTransformable.y += textOffset[1]
            if !innerOrigin {
                innerTransformable.originX = -textOffset[0]
                innerTransformable.originY = -textOffset[1]
            }
        }

        // Ensure the inner-text default-style bag exists (upstream creates it here, before the
        // autoOverflowArea branch and the fill/stroke computation below).
        if self._innerTextDefaultStyle == nil { self._innerTextDefaultStyle = DefaultTextStyle() }
        var defStyle = self._innerTextDefaultStyle!

        // upstream: compute the inside-text overflow area in the text's LOCAL coord by inverse-
        //   transforming the (host-space) layoutRect. `overflowRect` exists iff autoOverflowArea.
        //   The overflowRect BoundingRect is a persisted reference: handed to the text once (via
        //   setDefaultTextStyle when it first appears / disappears), then mutated in place on later
        //   frames — so the text sees updates without re-setting (mirrors upstream's shared object).
        let hadOverflowRect = (defStyle.overflowRect != nil)
        if autoOverflowArea, let layoutRect = layoutRect {
            let overflowRect = defStyle.overflowRect ?? BoundingRect(0, 0, 0, 0)
            defStyle.overflowRect = overflowRect
            tmpInnerTextTrans = innerTransformable.getLocalTransform(tmpInnerTextTrans)
            if let inv = matrix.invert(tmpInnerTextTrans) {
                tmpInnerTextTrans = inv
            }
            BoundingRect.copy(overflowRect, layoutRect)
            // If transform to a non-orthogonal state (e.g. rotate PI/3), the result of this "apply"
            // is not expected. But we don't need to address it until a real scenario arises.
            overflowRect.applyTransform(tmpInnerTextTrans)
        }
        else {
            defStyle.overflowRect = nil
        }
        let overflowRectChanged = (defStyle.overflowRect != nil) != hadOverflowRect
        // [CAUTION] Do not change `innerTransformable` below.

        // Calculate text color (inside vs outside).
        let isInside: Bool
        if let inside = textConfig.inside {
            isInside = inside
        }
        else if let posStr = textConfig.position as? String {
            isInside = posStr.contains("inside")
        }
        else {
            isInside = false
        }

        var textFill: String?
        var textStroke: String?
        var autoStroke: Bool? = nil
        if isInside && self.canBeInsideText() {
            textFill = textConfig.insideFill
            textStroke = textConfig.insideStroke
            if textFill == nil || textFill == "auto" { textFill = self.getInsideTextFill() }
            if textStroke == nil || textStroke == "auto" {
                textStroke = self.getInsideTextStroke(textFill); autoStroke = true
            }
        }
        else {
            textFill = textConfig.outsideFill
            textStroke = textConfig.outsideStroke
            if textFill == nil || textFill == "auto" { textFill = self.getOutsideFill() }
            if textStroke == nil || textStroke == "auto" {
                textStroke = self.getOutsideStroke(textFill); autoStroke = true
            }
        }
        textFill = textFill ?? "#000"

        if textFill != defStyle.fill || textStroke != defStyle.stroke || autoStroke != defStyle.autoStroke
            || textAlign != defStyle.align || textVerticalAlign != defStyle.verticalAlign {
            textStyleChanged = true
            defStyle.fill = textFill
            defStyle.stroke = textStroke
            defStyle.autoStroke = autoStroke
            defStyle.align = textAlign
            defStyle.verticalAlign = textVerticalAlign
        }
        // Persist the (possibly overflowRect- and/or fill-updated) default style, and hand it to the
        // text when the style changed OR the overflowRect reference appeared/disappeared (value-type
        // struct: the text needs the fresh reference once; see the autoOverflowArea note above).
        self._innerTextDefaultStyle = defStyle
        if textStyleChanged || overflowRectChanged {
            textEl.setDefaultTextStyle(defStyle)
        }

        // Mark textEl to update transform (NOT markRedraw — that would re-dirty the host).
        textEl.__dirty = Double(Int(textEl.__dirty) | Int(REDRAW_BIT))
        if textStyleChanged {
            textEl.dirtyStyle(true)
        }
    }

    /// Convert `textConfig.position` (the `Any?` union — a `BuiltinTextPosition` string, or upstream's
    /// `(number | string)[]`, where a string entry is a percent like `"29.3%"`) into the typed opts the
    /// contain/text `calculateTextPosition` takes. `calculateTextPosition`'s `.array` branch routes each
    /// entry through `parsePercent`, so percent strings must be carried through as `.string` rather than
    /// dropped — a `[String]` position (MapDraw.resetLabelForRegion) previously fell through to `nil`
    /// here and silently defaulted the label to `.inside` (region bbox centre, not the projected centroid).
    private func _textConfigPositionOpt(_ pos: Any?) -> BuiltinTextPositionOrArray? {
        if let bp = pos as? BuiltinTextPosition { return .position(bp) }
        if let s = pos as? String, let bp = BuiltinTextPosition(rawValue: s) { return .position(bp) }
        if let arr = pos as? [Any] {
            return .array(arr.map { v in
                if let d = v as? Double { return NumberOrString.number(d) }
                if let i = v as? Int { return NumberOrString.number(Double(i)) }
                if let n = v as? NSNumber { return NumberOrString.number(n.doubleValue) }
                return NumberOrString.string(v as? String ?? "")
            })
        }
        return nil
    }

    internal func canBeInsideText() -> Bool {  // upstream: protected
        return true
    }

    internal func getInsideTextFill() -> String? {  // upstream: protected
        return "#fff"
    }

    internal func getInsideTextStroke(_ textFill: String?) -> String? {  // upstream: protected
        return "#000"
    }

    internal func getOutsideFill() -> String? {  // upstream: protected
        return (self.__zr != nil && self.__zr!.isDarkMode()) ? LIGHT_LABEL_COLOR : DARK_LABEL_COLOR
    }

    internal func getOutsideStroke(_ textFill: String?) -> String {  // upstream: protected
        let backgroundColor = (self.__zr != nil) ? self.__zr!.getBackgroundColor() : nil
        var colorArr: [Double]? = nil
        if let bg = backgroundColor as? String {
            colorArr = color.parse(bg)
        }
        if colorArr == nil {
            colorArr = [255, 255, 255, 1]
        }
        // Assume blending on a white / black(dark) background.
        let alpha = colorArr![3]
        // Guard `__zr` like getOutsideFill/getOutsideStroke's backgroundColor read above: in the
        //   headless render path (no zrender instance attached) `__zr` is nil; default to light mode.
        let isDark = (self.__zr != nil) ? self.__zr!.isDarkMode() : false
        for i in 0..<3 {
            colorArr![i] = colorArr![i] * alpha + (isDark ? 0 : 255) * (1 - alpha)
        }
        colorArr![3] = 1
        return color.stringify(colorArr!, "rgba") ?? ""
    }

    public func traverse(_ cb: (_ el: Element) -> Void, _ context: Any? = nil) {}

    internal func attrKV(_ key: String, _ value: Any?) {  // upstream: protected
        if key == "textConfig" {
            self.setTextConfig(value as? ElementTextConfig)
        }
        else if key == "textContent" {
            self.setTextContent(value as? ZRText)
        }
        else if key == "clipPath" {
            if let v = value as? Path {
                self.setClipPath(v)
            }
        }
        else if key == "extra" {
            var e = self.extra ?? [:]
            if let v = value as? Dictionary<Any> {
                _ = util.extend(&e, v)
            }
            self.extra = e
        }
        else {
            // upstream: (this as any)[key] = value.
            // Swift has no dynamic member assignment; the known Element/Transformable
            //   props are switched explicitly below. Subclasses (Displayable/Group/Path) override
            //   `attrKV` to handle their own props; unknown keys fall through and are ignored.
            self._setKnownKV(key, value)
        }
    }

    // Explicit replacement for upstream's dynamic `(this as any)[key] = value`.
    private func _setKnownKV(_ key: String, _ value: Any?) {
        switch key {
        // Element props
        case "name": if let v = value as? String { self.name = v }
        case "ignore": if let v = value as? Bool { self.ignore = v }
        case "silent": if let v = value as? Bool { self.silent = v }
        case "ignoreModelZ": if let v = value as? Bool { self.ignoreModelZ = v }
        case "ignoreHostSilent": if let v = value as? Bool { self.ignoreHostSilent = v }
        case "isGroup": if let v = value as? Bool { self.isGroup = v }
        case "ignoreClip": if let v = value as? Bool { self.ignoreClip = v }
        case "dragging": if let v = value as? Bool { self.dragging = v }
        case "draggable":
            if let v = value as? Bool {
                self.draggable = v ? .true : .false
            }
            else if let s = value as? String {
                self.draggable = (s == "horizontal") ? .horizontal
                    : ((s == "vertical") ? .vertical : .false)
            }
        case "anid": if let v = value as? String { self.anid = v }
        case "extra": if let v = value as? [String: Any] { self.extra = v }
        case "globalScaleRatio": if let v = value as? Double { self.globalScaleRatio = v }
        // Transformable props (TRANSFORMABLE_PROPS)
        case "x": if let v = value as? Double { self.x = v }
        case "y": if let v = value as? Double { self.y = v }
        case "originX": if let v = value as? Double { self.originX = v }
        case "originY": if let v = value as? Double { self.originY = v }
        case "anchorX": if let v = value as? Double { self.anchorX = v }
        case "anchorY": if let v = value as? Double { self.anchorY = v }
        case "rotation": if let v = value as? Double { self.rotation = v }
        case "scaleX": if let v = value as? Double { self.scaleX = v }
        case "scaleY": if let v = value as? Double { self.scaleY = v }
        case "skewX": if let v = value as? Double { self.skewX = v }
        case "skewY": if let v = value as? Double { self.skewY = v }
        default:
            // unknown prop key — handled by subclass `attrKV` override or ignored.
            break
        }
    }

    // ---- AnimationTarget conformance ----
    //
    // upstream uses dynamic `(this as any)[key]` get/set on the animate target. The animator
    //   routes keyed read/write through `AnimationTarget` (Animator.swift). The base exposes the
    //   Element / Transformable primary props; `animationSet` reuses `_setKnownKV` (plain assign,
    //   NOT markRedraw — repaint is driven by `updateDuringAnimation` in the during callback,
    //   matching upstream `target[propName] = value`). note: Displayable/Path now override
    //   these to expose the value-type `style`/`shape` bags (wired — see class note).
    public func animationGet(_ key: String) -> Any? {
        if key == "extra" { return _ElementExtraAnimationAccessor(self) }
        return self._getKnownKV(key)
    }

    public func animationSet(_ key: String, _ value: Any?) {
        if key == "extra", let v = value as? [String: Any] {
            self.extra = v
            return
        }
        self._setKnownKV(key, value)
    }

    // Explicit replacement for upstream's dynamic `(this as any)[key]` read.
    private func _getKnownKV(_ key: String) -> Any? {
        switch key {
        // Element props
        case "name": return self.name
        case "ignore": return self.ignore
        case "silent": return self.silent
        case "ignoreModelZ": return self.ignoreModelZ
        case "ignoreHostSilent": return self.ignoreHostSilent
        case "isGroup": return self.isGroup
        case "ignoreClip": return self.ignoreClip
        case "dragging": return self.dragging
        case "anid": return self.anid
        case "globalScaleRatio": return self.globalScaleRatio
        // Transformable props (TRANSFORMABLE_PROPS)
        case "x": return self.x
        case "y": return self.y
        case "originX": return self.originX
        case "originY": return self.originY
        case "anchorX": return self.anchorX
        case "anchorY": return self.anchorY
        case "rotation": return self.rotation
        case "scaleX": return self.scaleX
        case "scaleY": return self.scaleY
        case "skewX": return self.skewX
        case "skewY": return self.skewY
        default:
            // unknown / sub-bag key — handled by subclass override or returns nil
            //   (a nil initial value makes the animator track inert, the safe default).
            return nil
        }
    }

    /// Hide the element
    public func hide() {
        self.ignore = true
        self.markRedraw()
    }

    /// Show the element
    public func show() {
        self.ignore = false
        self.markRedraw()
    }

    // upstream overloads: attr(keyOrObj) / attr(key, value). Expressed as two Swift methods.
    @discardableResult
    public func attr(_ keyOrObj: ElementProps) -> Self {
        let keysArr = util.keys(keyOrObj)
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            self.attrKV(key, keyOrObj[key])
        }
        self.markRedraw()
        return self
    }

    @discardableResult
    public func attr(_ key: String, _ value: Any?) -> Self {
        self.attrKV(key, value)
        self.markRedraw()
        return self
    }

    // Save current state to normal
    public func saveCurrentToNormalState(_ toState: ElementState) {
        self._innerSaveToNormal(toState)

        // If we are switching from normal to other state during animation, we need to save the FINAL
        //   value of the animation to the normal state (not the interpolated value) so that removing
        //   the state restores to where the animation was heading. Loop animators and state-transition
        //   animators (except normal) are ignored.
        guard let normalState = self._normalState else { return }
        for i in 0..<self.animators.count {
            let animator = self.animators[i]
            let fromStateTransition = animator.__fromStateTransition
            if animator.getLoop()
                || (fromStateTransition != nil && fromStateTransition != PRESERVED_NORMAL_STATE) {
                continue
            }
            let targetName = animator.targetName
            // Respecting the order of animation if multiple animators animate on the same property
            //   (if additive animation is used). Sub-bag (`shape`/`style`) targets are written through
            //   a reference wrapper and stored back into the value-type normal-state sub-bag.
            if let tn = targetName, !tn.isEmpty {
                let wrapper = _RefBag((normalState.props[tn] as? [String: Any]) ?? [:])
                animator.saveTo(wrapper)
                normalState.props[tn] = wrapper.dict
            }
            else {
                animator.saveTo(normalState)
            }
        }
    }

    // Save the CURRENT value of every prop a target state will change — once — so it can be restored
    // when that state is removed. Sub-bag props (`shape` / `style`) are saved key-by-key, read through
    // the element's keyed animation accessor (which mirrors the subclass's value-type bag).
    internal func _innerSaveToNormal(_ toState: ElementState) {  // upstream: protected
        if self._normalState == nil {
            self._normalState = ElementState()
        }
        let normalState = self._normalState!
        if toState.textConfig != nil && normalState.textConfig == nil {
            normalState.textConfig = self.textConfig
        }
        for key in util.keys(toState.props) {
            if let subDict = toState.props[key] as? [String: Any] {
                let accessor = self.animationGet(key) as? AnimationTarget
                var normalSub = (normalState.props[key] as? [String: Any]) ?? [:]
                for subKey in util.keys(subDict) where normalSub[subKey] == nil {
                    normalSub[subKey] = accessor?.animationGet(subKey)
                }
                normalState.props[key] = normalSub
            }
            else if normalState.props[key] == nil {
                normalState.props[key] = self.animationGet(key)
            }
        }
    }

    // Deep-merge `from` into `into` (recursing one level into shape/style sub-bags).
    private func _deepMergeProps(_ into: inout [String: Any], _ from: [String: Any]) {
        for key in util.keys(from) {
            if let vDict = from[key] as? [String: Any],
               let existing = into[key] as? [String: Any] {
                var merged = existing
                self._deepMergeProps(&merged, vDict)
                into[key] = merged
            }
            else {
                into[key] = from[key]
            }
        }
    }

    // The apply target for a set of active states. Only properties touched by either the previous or
    // the next active states participate. `_normalState` can also contain the FINAL values of unrelated
    // in-flight animations (saved by `saveCurrentToNormalState`); including every normal key here would
    // make a style-only highlight write an updating shape to its final frame and abort its animator.
    //
    // Within shape/style bags the same rule is applied per sub-key: restore keys dropped by the old
    // state, apply keys owned by the new state, and leave every unrelated animated key alone.
    private func _computeRestoreTarget(_ stateObjects: [ElementState]) -> [String: Any] {
        var merged: [String: Any] = [:]
        for s in stateObjects {
            self._deepMergeProps(&merged, s.props)
        }
        var previous: [String: Any] = [:]
        for stateName in self.currentStates {
            var stateObj: ElementState?
            if let proxy = self.stateProxy {
                stateObj = proxy(stateName, self.currentStates)
            }
            if stateObj == nil {
                stateObj = self.states[stateName]
            }
            if let stateObj = stateObj {
                self._deepMergeProps(&previous, stateObj.props)
            }
        }
        let normal = self._normalState?.props ?? [:]
        var target: [String: Any] = [:]
        var allKeys = Set(previous.keys)
        allKeys.formUnion(merged.keys)
        for key in allKeys {
            if let mv = merged[key] {
                if let mDict = mv as? [String: Any] {
                    let nDict = normal[key] as? [String: Any] ?? [:]
                    let pDict = previous[key] as? [String: Any] ?? [:]
                    var sub: [String: Any] = [:]
                    var subKeys = Set(pDict.keys)
                    subKeys.formUnion(mDict.keys)
                    for subKey in subKeys {
                        if let value = mDict[subKey] {
                            sub[subKey] = value
                        }
                        else if let value = nDict[subKey] {
                            sub[subKey] = value
                        }
                    }
                    target[key] = sub
                }
                else {
                    target[key] = mv
                }
            }
            else if let nv = normal[key] {
                target[key] = nv                          // dropped by all active states → restore normal
            }
        }
        return target
    }

    // `textConfig` lives outside the generic `props` bag, so it cannot participate in
    // `_computeRestoreTarget`. Track whether the states being replaced own it, which lets the
    // state paths restore the saved normal config without erasing an unrelated live config.
    private func _statesTouchTextConfig(_ stateNames: [String]) -> Bool {
        for stateName in stateNames {
            var stateObj: ElementState?
            if let proxy = self.stateProxy {
                stateObj = proxy(stateName, stateNames)
            }
            if stateObj == nil {
                stateObj = self.states[stateName]
            }
            if stateObj?.textConfig != nil {
                return true
            }
        }
        return false
    }

    // Upstream state text configs are partial objects and are extended over the saved normal
    // config. Assigning the Swift struct wholesale drops fields such as `local` and `layoutRect`,
    // which makes an emphasized attached label fall back to canvas coordinates.
    private func _mergeTextConfig(
        _ base: ElementTextConfig?,
        _ overlay: ElementTextConfig
    ) -> ElementTextConfig {
        var result = base ?? ElementTextConfig()
        if let value = overlay.position { result.position = value }
        if let value = overlay.rotation { result.rotation = value }
        if let value = overlay.layoutRect { result.layoutRect = value }
        if let value = overlay.offset { result.offset = value }
        if let value = overlay.origin { result.origin = value }
        if let value = overlay.distance { result.distance = value }
        if let value = overlay.local { result.local = value }
        if let value = overlay.insideFill { result.insideFill = value }
        if let value = overlay.insideStroke { result.insideStroke = value }
        if let value = overlay.outsideFill { result.outsideFill = value }
        if let value = overlay.outsideStroke { result.outsideStroke = value }
        if let value = overlay.inside { result.inside = value }
        if let value = overlay.autoOverflowArea { result.autoOverflowArea = value }
        return result
    }

    // Apply a state target. With a transition it animates (tagging the animators with the state name,
    // exactly like `_transitionState`); otherwise it jumps via a duration-0 transition.
    private func _stateApply(_ stateName: String, _ target: [String: Any], _ transition: Bool) {
        if target.isEmpty { return }
        if transition {
            self._transitionState(stateName, target, self.stateTransition)
        }
        else {
            var cfg = self.stateTransition ?? ElementAnimateConfig()
            cfg.duration = 0
            self._transitionState(stateName, target, cfg)
        }
    }

    // upstream splits out `_savePrimaryToNormal(toState, normalState, PRIMARY_STATES_KEYS)`
    //   to copy the transformable/primary keys. This port's `_innerSaveToNormal` (above) instead
    //   iterates ALL of `toState.props` (a superset of PRIMARY_STATES_KEYS) and copies each via
    //   `self.animationGet(key)`, subsuming the primary-key case — so the separate helper is dead and
    //   is not ported.

    /// If has any state.
    public func hasState() -> Bool {
        return self.currentStates.count > 0
    }

    /// Get state object
    public func getState(_ name: String) -> ElementState? {
        return self.states[name]
    }

    /// Ensure state exists. If not, will create one and return.
    @discardableResult
    public func ensureState(_ name: String) -> ElementState {
        if self.states[name] == nil {
            self.states[name] = ElementState()
        }
        return self.states[name]!
    }

    /// Clear all states.
    public func clearStates(_ noAnimation: Bool? = nil) {
        _ = self.useState(PRESERVED_NORMAL_STATE, false, noAnimation)
        // TODO set _normalState to null?
    }

    /// Use state. State is a collection of properties.
    ///
    /// upstream routes application through `_applyStateObj` (per-class, with a transform /
    /// style / shape split + hover-layer branches). This port instead computes the full target prop
    /// bag and applies it via `animateTo` (`_stateApply`), which already drives transform / shape /
    /// style uniformly — same observable result (animated transition to the active states, restoring
    /// dropped props to normal). Hover-layer (`shouldUseHoverLayer`) is a no-op for non-text elements
    /// and is omitted; `_applyStateObj` is left unused.
    @discardableResult
    public func useState(
        _ stateName: String,
        _ keepCurrentStates: Bool? = nil,
        _ noAnimation: Bool? = nil,
        _ forceUseHoverLayer: Bool? = nil
    ) -> ElementState? {
        let toNormalState = (stateName == PRESERVED_NORMAL_STATE)
        let hasStates = self.hasState()
        let keep = keepCurrentStates ?? false
        let previousStatesTouchTextConfig = self._statesTouchTextConfig(self.currentStates)

        // Switching from normal to normal — nothing to do.
        if !hasStates && toNormalState {
            return nil
        }

        // No need to change: keeping current states and it's already applied, or it's the only state.
        if util.indexOf(self.currentStates, stateName) >= 0 && (keep || self.currentStates.count == 1) {
            return nil
        }

        var state: ElementState?
        if let proxy = self.stateProxy, !toNormalState {
            state = proxy(stateName, nil)
        }
        if state == nil {
            state = self.states[stateName]
        }
        if state == nil && !toNormalState {
            util.logError("State \(stateName) not exists.")
            return nil
        }

        if !toNormalState, let st = state {
            self.saveCurrentToNormalState(st)
        }

        let canTransition = !(noAnimation ?? false) && (self.stateTransition?.duration ?? 0) > 0

        let target: [String: Any]
        if toNormalState {
            target = self._computeRestoreTarget([])           // restore only props owned by old states
        }
        else if keep {
            target = state!.props                              // additive: lay this state over current
        }
        else {
            target = self._computeRestoreTarget([state!])      // sole state: over normal, restore others
        }
        self._stateApply(stateName, target, canTransition)

        if toNormalState {
            if previousStatesTouchTextConfig {
                self.textConfig = self._normalState?.textConfig
            }
        }
        else if let stateTextConfig = state?.textConfig {
            self.textConfig = self._mergeTextConfig(self._normalState?.textConfig, stateTextConfig)
        }
        else if !keep && previousStatesTouchTextConfig {
            self.textConfig = self._normalState?.textConfig
        }

        // upstream Element.useState (Element.ts:1006-1014): propagate the state to the attached
        //   `textContent` (and `textGuide`) so a labeled element's LABEL restyles per its
        //   emphasis/blur/select `label` model when the host enters/leaves a state. This is the seam
        //   that makes hover-to-highlight also recolor/resize/re-weight the attached label text
        //   (`label/labelStyle.swift` writes the per-state textStyle onto `textContent.states[name]`;
        //   `ZRText.useState`/`useStates` read it back — see the override there). Hover-layer is
        //   dropped in this port (see the `useState` note), so `forceUseHoverLayer` is `false`.
        if let textContent = self._textContent {
            _ = textContent.useState(stateName, keepCurrentStates, noAnimation, false)
        }
        if let textGuide = self._textGuide {
            _ = textGuide.useState(stateName, keepCurrentStates, noAnimation, false)
        }

        if toNormalState {
            self.currentStates = []
            self._normalState = ElementState()
        }
        else if !keep {
            self.currentStates = [stateName]
        }
        else {
            self.currentStates.append(stateName)
        }

        self._updateAnimationTargets()
        self.markRedraw()
        return state
    }

    /// Apply multiple states (the merged union of them; props no longer covered restore to normal).
    public func useStates(
        _ states: [String],
        _ noAnimation: Bool? = nil,
        _ forceUseHoverLayer: Bool? = nil
    ) {
        if states.isEmpty {
            self.clearStates(noAnimation)
            return
        }

        // No change if the requested list equals the current one (same order).
        if states.count == self.currentStates.count {
            var notChange = true
            for i in 0..<states.count where states[i] != self.currentStates[i] {
                notChange = false
                break
            }
            if notChange { return }
        }

        var stateObjects: [ElementState] = []
        for stateName in states {
            var stateObj: ElementState?
            if let proxy = self.stateProxy {
                stateObj = proxy(stateName, states)
            }
            if stateObj == nil {
                stateObj = self.states[stateName]
            }
            if let s = stateObj {
                stateObjects.append(s)
            }
        }

        let mergedState = self._mergeStates(stateObjects)
        let canTransition = !(noAnimation ?? false) && (self.stateTransition?.duration ?? 0) > 0
        let previousStatesTouchTextConfig = self._statesTouchTextConfig(self.currentStates)

        self.saveCurrentToNormalState(mergedState)
        let target = self._computeRestoreTarget(stateObjects)
        self._stateApply(states.joined(separator: ","), target, canTransition)
        if let stateTextConfig = mergedState.textConfig {
            self.textConfig = self._mergeTextConfig(self._normalState?.textConfig, stateTextConfig)
        }
        else if previousStatesTouchTextConfig {
            self.textConfig = self._normalState?.textConfig
        }

        // upstream Element.useStates (Element.ts:1113-1119): propagate to the attached text content /
        //   guide (same seam as `useState` above — this is the primary path the interaction layer hits,
        //   since `states.applyElementStates` drives emphasis/blur/select via `useStates`).
        if let textContent = self._textContent {
            textContent.useStates(states, noAnimation, false)
        }
        if let textGuide = self._textGuide {
            textGuide.useStates(states, noAnimation, false)
        }

        self._updateAnimationTargets()
        self.currentStates = states
        self.markRedraw()
    }

    /// Return if el.silent or any ancestor element has silent true.
    public func isSilent() -> Bool {
        // Follow the logic of `Handler.ts`#`isHover`.
        var el: Element? = self
        while let cur = el {
            if cur.silent {
                return true
            }
            let hostEl = cur.__hostTarget
            if let hostEl = hostEl {
                el = cur.ignoreHostSilent ? nil : hostEl
            }
            else {
                // upstream `parent` is `Group`; we inherit `Transformable.parent`.
                el = cur.parent as? Element
            }
        }
        return false
    }

    /// Update animation targets when reference is changed (re-point each sub-bag animator at the
    /// element's current accessor after a state swap).
    private func _updateAnimationTargets() {
        for animator in self.animators {
            if let targetName = animator.targetName, let newTarget = self.animationGet(targetName) {
                animator.changeTarget(newTarget)
            }
        }
    }

    /// Remove state
    public func removeState(_ state: String) {
        let idx = util.indexOf(self.currentStates, state)
        if idx >= 0 {
            var currentStates = self.currentStates
            currentStates.remove(at: Int(idx))
            self.useStates(currentStates)
        }
    }

    /// Replace exists state.
    public func replaceState(_ oldState: String, _ newState: String, _ forceAdd: Bool) {
        var currentStates = self.currentStates
        let idx = util.indexOf(currentStates, oldState)
        let newStateExists = util.indexOf(currentStates, newState) >= 0
        if idx >= 0 {
            if !newStateExists {
                // Replace the old with the new one.
                currentStates[Int(idx)] = newState
            }
            else {
                // Only remove the old one.
                currentStates.remove(at: Int(idx))
            }
        }
        else if forceAdd && !newStateExists {
            currentStates.append(newState)
        }
        self.useStates(currentStates)
    }

    /// Toggle state.
    public func toggleState(_ state: String, _ enable: Bool) {
        if enable {
            _ = self.useState(state, true)
        }
        else {
            self.removeState(state)
        }
    }

    internal func _mergeStates(_ states: [ElementState]) -> ElementState {  // upstream: protected
        let mergedState = ElementState()
        var mergedTextConfig: ElementTextConfig?
        for state in states {
            self._deepMergeProps(&mergedState.props, state.props)
            if let tc = state.textConfig {
                mergedTextConfig = self._mergeTextConfig(mergedTextConfig, tc)
            }
        }
        mergedState.textConfig = mergedTextConfig
        return mergedState
    }

    // upstream `_applyStateObj` (per-class transform/style/shape split + hover-layer
    //   branches) is intentionally not the live path. This port computes the full target prop bag and
    //   applies it via `animateTo` (`_stateApply`) — see the `useState` note above — yielding the
    //   same observable result. The empty base is kept so `Displayable`/`Path` can override it.
    internal func _applyStateObj(  // upstream: protected
        _ stateName: String,
        _ state: ElementState?,
        _ normalState: ElementState?,
        _ keepCurrentStates: Bool,
        _ transition: Bool,
        _ animationCfg: ElementAnimateConfig?
    ) {
    }

    /// Component is some elements attached on this element for specific purpose.
    /// Like clipPath, textContent
    private func _attachComponent(_ componentEl: Element) {
        if componentEl.__zr != nil && componentEl.__hostTarget == nil {
            // dev-mode `throw new Error('Text element has been added to zrender.')`.
            return
        }

        if componentEl === self {
            // dev-mode `throw new Error('Recursive component attachment.')`.
            return
        }

        let zr = self.__zr
        if let zr = zr {
            // Needs to add self to zrender. For rerender triggering, or animation.
            componentEl.addSelfToZr(zr)
        }

        componentEl.__zr = zr
        componentEl.__hostTarget = self
    }

    private func _detachComponent(_ componentEl: Element) {
        if let zr = componentEl.__zr {
            componentEl.removeSelfFromZr(zr)
        }

        componentEl.__zr = nil
        componentEl.__hostTarget = nil
    }

    /// Get clip path
    public func getClipPath() -> Path? {
        return self._clipPath
    }

    /// Set clip path. clipPath can't be shared between two elements.
    public func setClipPath(_ clipPath: Path) {
        // Remove previous clip path
        if let cp = self._clipPath, cp !== clipPath {
            self.removeClipPath()
        }

        self._attachComponent(clipPath)

        self._clipPath = clipPath
        self.markRedraw()
    }

    /// Remove clip path
    public func removeClipPath() {
        let clipPath = self._clipPath
        if let clipPath = clipPath {
            self._detachComponent(clipPath)
            self._clipPath = nil
            self.markRedraw()
        }
    }

    /// Get attached text content.
    public func getTextContent() -> ZRText? {
        return self._textContent
    }

    /// Attach text on element
    public func setTextContent(_ textEl: ZRText?) {
        guard let textEl = textEl else { return }
        let previousTextContent = self._textContent
        if previousTextContent === textEl {
            return
        }
        // Remove previous textContent
        if let prev = previousTextContent, prev !== textEl {
            self.removeTextContent()
        }
        // dev-mode guard `textEl.__zr && !textEl.__hostTarget` → throw.

        textEl.innerTransformable = Transformable()

        self._attachComponent(textEl)

        self._textContent = textEl

        self.markRedraw()
    }

    /// Set layout of attached text. Will merge with the previous.
    public func setTextConfig(_ cfg: ElementTextConfig?) {
        guard let cfg = cfg else { return }
        // TODO hide cfg property?
        if self.textConfig == nil {
            self.textConfig = ElementTextConfig()
        }
        // upstream `extend(this.textConfig, cfg)` field-merges, but a Swift Optional cannot
        //   distinguish "field absent on cfg" from "field explicitly nil"; callers (pieLabelLayout /
        //   themeRiver) build a fresh config with position == nil to RESET the position, which a
        //   field-merge would silently keep. So we assign `cfg` wholesale, which preserves the
        //   reset-on-nil semantics the layout stages depend on.
        self.textConfig = cfg
        self.markRedraw()
    }

    /// Remove text config
    public func removeTextConfig() {
        self.textConfig = nil
        self.markRedraw()
    }

    /// Remove attached text element.
    public func removeTextContent() {
        let textEl = self._textContent
        if let textEl = textEl {
            textEl.innerTransformable = nil
            self._detachComponent(textEl)
            self._textContent = nil
            self._innerTextDefaultStyle = nil
            self.markRedraw()
        }
    }

    public func getTextGuideLine() -> Polyline? {
        return self._textGuide
    }

    public func setTextGuideLine(_ guideLine: Polyline) {
        // Remove previous clip path
        if let tg = self._textGuide, tg !== guideLine {
            self.removeTextGuideLine()
        }

        self._attachComponent(guideLine)

        self._textGuide = guideLine

        self.markRedraw()
    }

    public func removeTextGuideLine() {
        let textGuide = self._textGuide
        if let textGuide = textGuide {
            self._detachComponent(textGuide)
            self._textGuide = nil
            self.markRedraw()
        }
    }

    /// Mark element needs to be repainted
    public func markRedraw() {
        // this.__dirty |= REDRAW_BIT  (bitwise on a Double mask → via Int per CONVENTIONS §5)
        self.__dirty = Double(Int(self.__dirty) | Int(REDRAW_BIT))
        let zr = self.__zr
        if let zr = zr {
            if self.__inHover != 0 {
                zr.refreshHover()
            }
            else {
                zr.refresh()
            }
        }

        // Used as a clipPath or textContent
        if let host = self.__hostTarget {
            host.markRedraw()
        }
    }

    /// Besides marking elements to be refreshed. It will also invalid all cache and
    /// doing recalculate next frame.
    public func dirty() {
        self.markRedraw()
    }

    /// Add self from zrender instance.
    /// Not recursively because it will be invoked when element added to storage.
    public func addSelfToZr(_ zr: ZRenderType) {
        if self.__zr === zr {
            return
        }

        self.__zr = zr
        // 添加动画
        let animators = self.animators
        for i in 0..<animators.count {
            zr.animation.addAnimator(animators[i])
        }

        if let cp = self._clipPath {
            cp.addSelfToZr(zr)
        }
        if let tc = self._textContent {
            tc.addSelfToZr(zr)
        }
        if let tg = self._textGuide {
            tg.addSelfToZr(zr)
        }

        // morphPath seam: `combineMorph` installs an `after` hook to add the split sub-paths.
        self.__morphAddSelfToZrAfter?(zr)
    }

    /// Remove self from zrender instance.
    /// Not recursively because it will be invoked when element added to storage.
    public func removeSelfFromZr(_ zr: ZRenderType) {
        if self.__zr == nil {
            return
        }

        self.__zr = nil
        // Remove animation
        let animators = self.animators
        for i in 0..<animators.count {
            zr.animation.removeAnimator(animators[i])
        }

        if let cp = self._clipPath {
            cp.removeSelfFromZr(zr)
        }
        if let tc = self._textContent {
            tc.removeSelfFromZr(zr)
        }
        if let tg = self._textGuide {
            tg.removeSelfFromZr(zr)
        }

        // morphPath seam: `combineMorph` installs an `after` hook to remove the split sub-paths.
        self.__morphRemoveSelfFromZrAfter?(zr)
    }

    /// 动画
    /// - path: The key to fetch value from object. Mostly style or shape.
    /// - loop: Whether to loop animation.
    /// - allowDiscreteAnimation: Whether to allow discrete animation
    @discardableResult
    public func animate(_ key: String? = nil, _ loop: Bool? = nil, _ allowDiscreteAnimation: Bool? = nil) -> Animator<Any> {
        // upstream: let target = key ? (this as any)[key] : this;
        // dynamic `(this as any)[key]` fetch of a sub-bag (e.g. 'style'/'shape') is not
        //   available on `Element` base — those bags are value-type structs on Displayable/Path
        //   (no shared identity). The target is `self` (an AnimationTarget); `targetName = key`
        //   still routes keyed get/set through `self`, which Displayable/Path override to expose the
        //   `style`/`shape` bags. The dev-mode `if (!target) logError(...)` existence check is dropped.
        let target: Any = self

        let animator = Animator<Any>(target, loop ?? false, allowDiscreteAnimation)
        if let key = key {
            animator.targetName = key
        }
        self.addAnimator(animator, key ?? "")
        return animator
    }

    public func addAnimator(_ animator: Animator<Any>, _ key: String) {
        let zr = self.__zr

        // upstream `const el = this;` — captured weakly to break the animator → onframe/done → el
        //   retain cycle (CONVENTIONS §8: weak only where a cycle is real — animators). The `done`
        //   callback removes the animator from `el.animators` to release it (FIXME upstream: not
        //   removed when stopped via `Animator#stop`).
        animator.during { [weak self] _, _ in
            self?.updateDuringAnimation(key)
        }.done { [weak self, weak animator] in
            guard let self = self, let animator = animator else { return }
            // FIXME Animator will not be removed if use `Animator#stop` to stop animation
            // upstream: indexOf(animators, animator) — identity match (CONVENTIONS §8 / §10).
            if let idx = self.animators.firstIndex(where: { $0 === animator }) {
                self.animators.remove(at: idx)
            }
        }

        self.animators.append(animator)

        // If animate after added to the zrender
        // DEVIATION (robustness): upstream does `if (zr) { zr.animation.addAnimator(...) }` and would
        //   TypeError if `zr.animation` were null. Natively `zr.animation` is nulled by `dispose()`
        //   (ZRender.swift), and a still-referenced element (e.g. a deferred morph/asyncAfter closure
        //   firing after the host view tore down its zr) can reach here with a disposed `zr`. Bind the
        //   IUO so a disposed clock is a no-op rather than an implicit-unwrap trap.
        if let zr = zr, let animation = zr.animation {
            animation.addAnimator(animator)
        }

        // Wake up zrender to start the animation loop.
        zr?.wakeUp()
    }

    public func updateDuringAnimation(_ key: String) {
        self.markRedraw()
    }

    /// 停止动画
    /// - forwardToLast: If move to last frame before stop
    @discardableResult
    public func stopAnimation(_ scope: String? = nil, _ forwardToLast: Bool? = nil) -> Self {
        let animators = self.animators
        let len = animators.count
        var leftAnimators: [Animator<Any>] = []
        for i in 0..<len {
            let animator = animators[i]
            // upstream: `if (!scope || scope === animator.scope)` — JS `!scope` is also
            // true for the empty string, so `stopAnimation("")` stops every animator.
            if scope == nil || scope!.isEmpty || scope == animator.scope {
                animator.stop(forwardToLast)
            }
            else {
                leftAnimators.append(animator)
            }
        }
        self.animators = leftAnimators

        return self
    }

    public func animateTo(_ target: ElementProps, _ cfg: ElementAnimateConfig? = nil, _ animationProps: [String: Any]? = nil) {
        // module-qualify: the module-level free function `animateTo` is shadowed by this method.
        _ = ZRenderKit.animateTo(self, target, cfg, animationProps)
    }

    /// Animate from the target state to current state.
    /// The params and the value are the same as `this.animateTo`.
    public func animateFrom(_ target: ElementProps, _ cfg: ElementAnimateConfig?, _ animationProps: [String: Any]? = nil) {
        _ = ZRenderKit.animateTo(self, target, cfg, animationProps, true)
    }

    internal func _transitionState(  // upstream: protected
        _ stateName: String, _ target: ElementProps, _ cfg: ElementAnimateConfig? = nil, _ animationProps: [String: Any]? = nil
    ) {
        let animators = ZRenderKit.animateTo(self, target, cfg, animationProps)
        for i in 0..<animators.count {
            animators[i].__fromStateTransition = stateName
        }
    }

    /// Interface of getting the minimum bounding box.
    public func getBoundingRect() -> BoundingRect? {
        return nil
    }

    public func getPaintRect() -> BoundingRect? {
        return nil
    }

    // upstream: protected static initDefaultProps — seeds prototype defaults (type='element',
    //   name='', ignore/silent/...=false, __inHover=IN_HOVER_LAYER_KIND_NO, __dirty=REDRAW_BIT)
    //   and installs the deprecated `position`/`scale`/`origin` array accessors via
    //   Object.defineProperty.
    //   Defaults are replaced by stored-property initializers above.
    //   TODO: the legacy `position`/`scale`/`origin` array accessors
    //   (createLegacyProperty / enhanceArray) are deprecated Object.defineProperty shims for
    //   backward compat; not ported.

    // ---- Eventful mixin forwarding (upstream `mixin(Element, Eventful)`; see `_eventful` above) ----
    //
    // Forwards Eventful's public event surface to the composed `_eventful`. The handler `ctx`
    // defaults to the Element (`context ?? self`), matching upstream where the mixed-in Eventful's
    // `this` IS the Element (`ctx: context || this`) — NOT the inner object. This is what makes the
    // Handler dispatch path real: `el.trigger(eventName, eventPacket)` now reaches bound listeners.
    //
    // NOTE: upstream Eventful exposes `isSilent(eventName)`, but Element defines its own no-arg
    //   `isSilent()` (the ancestor-silent cascade, above), which fully shadows the mixed-in one in
    //   upstream too — so the `eventName` overload is intentionally NOT forwarded. Upstream Eventful
    //   has no `one` method; nothing to forward there.

    @discardableResult
    public func on(_ event: String, _ handler: @escaping EventCallback, _ context: AnyObject? = nil) -> Self {
        self._eventful.on(event, handler, context ?? self)
        return self
    }

    /// Bind a handler with a query (used on event filter). upstream: `on(event, query, handler, context)`.
    @discardableResult
    public func on(
        _ event: String,
        _ query: EventQuery?,
        _ handler: @escaping EventCallback,
        _ context: AnyObject? = nil
    ) -> Self {
        self._eventful.on(event, query, handler, context ?? self)
        return self
    }

    @discardableResult
    public func off(_ eventType: String? = nil, _ handler: EventCallback? = nil) -> Self {
        self._eventful.off(eventType, handler)
        return self
    }

    /// Dispatch a event. Forwards to the composed Eventful.
    @discardableResult
    public func trigger(_ eventType: String, _ args: Any?...) -> Self {
        // Swift variadics cannot be splatted into Eventful's variadic `trigger`, so dispatch on
        // arg count (mirroring Eventful's own backbone-style 0/1/2 switch).
        switch args.count {
        case 0:
            self._eventful.trigger(eventType)
        case 1:
            self._eventful.trigger(eventType, args[0])
        case 2:
            self._eventful.trigger(eventType, args[0], args[1])
        default:
            // >2 trigger args can't be splatted into the inner variadic. zrender's
            //   element events only ever carry a single eventPacket (Handler.dispatchToElement),
            //   so this branch is not reached; if a >2-arg element trigger is ever needed, add an
            //   array entry point on Eventful. Forwarding the first three for safety.
            self._eventful.trigger(eventType, args[0], args[1], args[2])
        }
        return self
    }

    /// Dispatch a event with context, which is specified at the last parameter.
    @discardableResult
    public func triggerWithContext(_ type: String, _ args: Any?...) -> Self {
        // Same variadic-splat limitation as `trigger`; forward by arg count. The inner
        // triggerWithContext preserves the "last arg is ctx" semantics for the counts forwarded.
        switch args.count {
        case 0:
            self._eventful.triggerWithContext(type)
        case 1:
            self._eventful.triggerWithContext(type, args[0])
        case 2:
            self._eventful.triggerWithContext(type, args[0], args[1])
        default:
            // see `trigger` — variadic splat limitation. Not exercised by zrender's
            //   element dispatch path. Forwarding the first three for safety.
            self._eventful.triggerWithContext(type, args[0], args[1], args[2])
        }
        return self
    }
}

// upstream: mixin(Element, Eventful); mixin(Element, Transformable);
//   Transformable is faithfully the `super` of Element (CONVENTIONS §2); Eventful is composed
//   (`_eventful`) and its full public surface — on / off / trigger / triggerWithContext — is
//   forwarded above, so Element behaves as `extends Eventful`. (`isSilent(eventName)` is shadowed
//   by Element's own no-arg `isSilent()`, matching upstream; `one` does not exist upstream.)

// ---- module-level helpers ----

@discardableResult
func animateTo(
    _ animatable: Element,
    _ target: [String: Any],
    _ cfg: ElementAnimateConfig?,
    _ animationProps: Any?,
    _ reverse: Bool? = nil
) -> [Animator<Any>] {
    let cfg = cfg ?? ElementAnimateConfig()
    var animators: [Animator<Any>] = []
    animateToShallow(
        animatable,
        "",
        animatable,
        target,
        cfg,
        animationProps,
        &animators,
        reverse ?? false
    )

    // Captured-by-reference mutable counters (Swift closures capture `var` by reference) — these
    //   stand in for the upstream closure-captured `finishCount` / `doneHappened`.
    var finishCount = animators.count
    var doneHappened = false
    let cfgDone = cfg.done
    let cfgAborted = cfg.aborted

    // Upstream inlines the same `finishCount-- ; if (<=0) doneHappened ? cfgDone : cfgAborted`
    // body in BOTH doneCb and abortedCb. Factored into one `finish` closure here so the ternary's
    // `doneHappened` is a captured var (not provably-constant) — otherwise Swift flags the
    // false-branch as dead code inside doneCb (where doneHappened is always true). Behaviour is
    // identical to upstream; see zrender/src/Element.ts doneCb/abortedCb.
    let finish: () -> Void = {
        finishCount -= 1
        if finishCount <= 0 {
            let cb = doneHappened ? cfgDone : cfgAborted
            cb?()
        }
    }

    let doneCb: DoneCallback = {
        doneHappened = true
        finish()
    }

    let abortedCb: AbortCallback = {
        finish()
    }

    // No animators. This should be checked before animators[i].start(),
    // because 'done' may be executed immediately if no need to animate.
    if finishCount == 0 {
        cfgDone?()
    }

    // Adding during callback to the first animator
    if animators.count > 0, let cfgDuring = cfg.during {
        // TODO If there are two animators in animateTo, and the first one is stopped by other animator.
        animators[0].during { _, percent in
            cfgDuring(percent)
        }
    }

    // Start after all animators created
    // Incase any animator is done immediately when all animation properties are not changed
    for i in 0..<animators.count {
        let animator = animators[i]
        animator.done(doneCb)
        animator.aborted(abortedCb)
        if cfg.force ?? false {
            // upstream: animator.duration(cfg.duration). note: guarded — `duration` may be nil
            //   (upstream would pass undefined). Only forced when a duration is supplied.
            if let d = cfg.duration {
                animator.duration(d)
            }
        }
        animator.start(cfg.easing)
    }

    return animators
}

fileprivate func copyArrShallow(_ source: inout [Double], _ target: [Double], _ len: Int) {
    for i in 0..<len {
        if i < source.count {
            source[i] = target[i]
        }
        else {
            source.append(target[i])
        }
    }
}

fileprivate func is2DArray(_ value: Any?) -> Bool {
    // upstream: isArrayLike(value[0]). `[Double]`/`[[Double]]` both bridge to `[Any]`.
    if let arr = value as? [Any] {
        return util.isArrayLike(arr.first ?? nil)
    }
    return false
}

fileprivate func copyValue(_ target: Any, _ source: [String: Any], _ key: String) {
    // upstream copies source[key] into target[key], preserving the array reference & length.
    //   Natively `target` is an `AnimationTarget` (keyed set) and Swift arrays are value types,
    //   so the in-place copy collapses to setting a value-copied array (CONVENTIONS §3/§4). The
    //   typed-array / 2D-array length-reconciliation branches are preserved structurally.
    let t = target as? AnimationTarget
    let srcVal = source[key]
    if util.isArrayLike(srcVal) {
        if util.isTypedArray(srcVal) {
            // number[] | Float32Array typed-array branch — no typed arrays natively;
            //   falls through to the plain value-copy below (CONVENTIONS §1).
        }
        if is2DArray(srcVal) {
            // NOTE: each item should have same length
            t?.animationSet(key, srcVal as? [[Double]] ?? [])   // Array.prototype.slice — value copy
        }
        else {
            t?.animationSet(key, srcVal as? [Double] ?? [])     // copyArrShallow — value copy
        }
    }
    else {
        t?.animationSet(key, srcVal)
    }
}

fileprivate func isValueSame(_ val1: Any?, _ val2: Any?) -> Bool {
    return anyStrictEqual(val1, val2)
        // Only check 1 dimension array
        || (util.isArrayLike(val1) && util.isArrayLike(val2) && is1DArraySame(val1, val2))
}

fileprivate func is1DArraySame(_ arr0: Any?, _ arr1: Any?) -> Bool {
    let a0 = asNumberArray(arr0)
    let a1 = asNumberArray(arr1)
    let len = a0.count
    if len != a1.count {
        return false
    }
    for i in 0..<len {
        if a0[i] != a1[i] {
            return false
        }
    }
    return true
}

func animateToShallow(
    _ animatable: Element,
    _ topKey: String,
    _ animateObj: Any,
    _ target: [String: Any],
    _ cfg: ElementAnimateConfig,
    _ animationProps: Any?,    // upstream: Dictionary<any> | true
    _ animators: inout [Animator<Any>],
    _ reverse: Bool    // If `true`, animate from the `target` to current state.
) {
    // Swift style/shape storage may use strongly-typed values (notably `ZRColor`) where upstream's
    // JavaScript target object contains a string/gradient. Let the live animation target bridge that
    // representation before equality checks and Track value-type inference.
    var target = target
    if let normalizer = animateObj as? AnimationTarget {
        for key in target.keys {
            target[key] = normalizer.animationNormalize(key, target[key])
        }
    }
    let targetKeys = util.keys(target)
    let duration = cfg.duration
    let delay = cfg.delay
    let additive = cfg.additive
    let setToFinal = cfg.setToFinal
    let animateAll = !util.isObject(animationProps)
    // Find last animator animating same prop.
    let existsAnimators = animatable.animators

    var animationKeys: [String] = []
    for k in 0..<targetKeys.count {
        let innerKey = targetKeys[k]
        let targetVal = target[innerKey]
        let animObjVal = animObjGet(animateObj, innerKey)

        if targetVal != nil && animObjVal != nil
            && (animateAll || isTruthyAnimProp(nestedAnimationProps(animationProps, innerKey))) {
            if util.isObject(targetVal)
                && !util.isArrayLike(targetVal)
                && !util.isGradientObject(targetVal) {
                if !topKey.isEmpty {
                    // logError('Only support 1 depth nest object animation.');
                    // Assign directly.
                    // TODO richText?
                    if !reverse {
                        animObjSet(animateObj, innerKey, targetVal)
                        animatable.updateDuringAnimation(topKey)
                    }
                    continue
                }
                animateToShallow(
                    animatable,
                    innerKey,
                    animObjVal!,
                    targetVal as? [String: Any] ?? [:],
                    cfg,
                    nestedAnimationProps(animationProps, innerKey),
                    &animators,
                    reverse
                )
            }
            else {
                animationKeys.append(innerKey)
            }
        }
        else if !reverse {
            // Assign target value directly.
            animObjSet(animateObj, innerKey, targetVal)
            animatable.updateDuringAnimation(topKey)
            // Previous animation will be stopped on the changed keys.
            // So direct assign is also included.
            animationKeys.append(innerKey)
        }
    }

    var keyLen = animationKeys.count
    // Stop previous animations on the same property.
    if !(additive ?? false) && keyLen > 0 {
        // Stop exists animation on specific tracks. Only one animator available for each property.
        // TODO Should invoke previous animation callback?
        for i in 0..<existsAnimators.count {
            let animator = existsAnimators[i]
            if animator.targetName == topKey {
                let allAborted = animator.stopTracks(animationKeys)
                if allAborted {   // This animator can't be used.
                    // upstream: indexOf(existsAnimators, animator); splice. `existsAnimators` is the
                    //   same array as `animatable.animators` upstream; natively the snapshot is a
                    //   value copy, so remove from `animatable.animators` directly (identity match).
                    if let idx = animatable.animators.firstIndex(where: { $0 === animator }) {
                        animatable.animators.remove(at: idx)
                    }
                }
            }
        }
    }

    // Ignore values not changed.
    // NOTE: Must filter it after previous animation stopped
    // and make sure the value to compare is using initial frame if animation is not started yet when setToFinal is used.
    if !(cfg.force ?? false) {
        animationKeys = util.filter(animationKeys) { key, _ in
            !isValueSame(target[key], animObjGet(animateObj, key))
        }
        keyLen = animationKeys.count
    }

    if keyLen > 0
        // cfg.force is mainly for keep invoking onframe and ondone callback even if animation is not necessary.
        // So if there is already has animators. There is no need to create another animator if not necessary.
        // Or it will always add one more with empty target.
        || ((cfg.force ?? false) && animators.count == 0) {
        var revertedSource: [String: Any]?
        var reversedTarget: [String: Any]?
        var sourceClone: [String: Any]?
        if reverse {
            reversedTarget = [:]
            if setToFinal ?? false {
                revertedSource = [:]
            }
            for i in 0..<keyLen {
                let innerKey = animationKeys[i]
                reversedTarget![innerKey] = animObjGet(animateObj, innerKey)
                if setToFinal ?? false {
                    revertedSource![innerKey] = target[innerKey]
                }
                else {
                    // The usage of "animateFrom" expects that the element props has been updated dirctly to
                    // "final" values outside, and input the "from" values here (i.e., in variable `target` here).
                    // So here we assign the "from" values directly to element here (rather that in the next frame)
                    // to prevent the "final" values from being read in any other places (like other running
                    // animator during callbacks).
                    // But if `setToFinal: true` this feature can not be satisfied.
                    animObjSet(animateObj, innerKey, target[innerKey])
                }
            }
        }
        else if setToFinal ?? false {
            sourceClone = [:]
            for i in 0..<keyLen {
                let innerKey = animationKeys[i]
                // NOTE: Must clone source after the stopTracks. The property may be modified in stopTracks.
                sourceClone![innerKey] = cloneValue(animObjGet(animateObj, innerKey))
                // Use copy, not change the original reference
                // Copy from target to source.
                copyValue(animateObj, target, innerKey)
            }
        }

        let additiveTo: [Animator<Any>]? = (additive ?? false)
            // Use key string instead object reference because ref may be changed.
            ? util.filter(existsAnimators) { animator, _ in animator.targetName == topKey }
            : nil
        let animator = Animator<Any>(animateObj, false, false, additiveTo)

        animator.targetName = topKey
        if let scope = cfg.scope {
            animator.scope = scope
        }

        if (setToFinal ?? false), let revertedSource = revertedSource {
            animator.whenWithKeys(0, revertedSource, animationKeys)
        }
        if let sourceClone = sourceClone {
            animator.whenWithKeys(0, sourceClone, animationKeys)
        }

        animator.whenWithKeys(
            duration ?? 500,
            reverse ? reversedTarget! : target,
            animationKeys
        ).delay(delay ?? 0)

        animatable.addAnimator(animator, topKey)
        animators.append(animator)
    }
}

// ---- PORT helpers (no upstream analogue) ----
// Backing for upstream's dynamic `(obj as any)[key]` get/set and JS `===` over `any`.

/// `(obj as any)[key]` read — routes through `AnimationTarget`, or a plain `[String: Any]` bag.
fileprivate func animObjGet(_ obj: Any, _ key: String) -> Any? {
    if let d = obj as? [String: Any] {
        return d[key]
    }
    return (obj as? AnimationTarget)?.animationGet(key)
}

/// `(obj as any)[key] = value` write — routes through `AnimationTarget` (reference identity).
fileprivate func animObjSet(_ obj: Any, _ key: String, _ value: Any?) {
    (obj as? AnimationTarget)?.animationSet(key, value)
    // if `obj` is a value-type `[String: Any]` bag, the set has no shared identity and
    //   is dropped. The animate targets in use are reference-type AnimationTargets (Element), so
    //   this is the safe default; style/shape value-bags are handled by the Displayable/Path
    //   animationGet/animationSet overrides (see Element class note).
}

/// `animationProps && (animationProps as Dictionary)[key]` (upstream truthy-and).
fileprivate func nestedAnimationProps(_ ap: Any?, _ key: String) -> Any? {
    if util.isObject(ap) {
        return (ap as? [String: Any])?[key]
    }
    return ap
}

/// Truthiness of a `MapToType<Props, boolean>` entry (values are booleans upstream).
fileprivate func isTruthyAnimProp(_ v: Any?) -> Bool {
    if let b = v as? Bool {
        return b
    }
    // upstream values are booleans; JS truthiness treats a non-bool present value as
    //   truthy, which `v != nil` faithfully reproduces here.
    return v != nil
}

/// JS `a === b`: value-equality for number/string/boolean, reference identity otherwise.
fileprivate func anyStrictEqual(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil {
        return true
    }
    if a == nil || b == nil {
        return false
    }
    if let x = a as? Double, let y = b as? Double {
        return x == y
    }
    if let x = a as? String, let y = b as? String {
        return x == y
    }
    if let x = a as? Bool, let y = b as? Bool {
        return x == y
    }
    // upstream unions that Swift models as tagged enums (e.g. `cornerRadius:
    //   number | number[]` -> `CornerRadius`) box to a FRESH AnyObject on every bridge, so the
    //   identity fallback below would report "changed" for two identical values and defeat
    //   `animateToShallow`'s unchanged-value filter (an animator per element per update).
    //   Compare them by value instead.
    if let x = a as? CornerRadius, let y = b as? CornerRadius {
        return x == y
    }
    return (a as AnyObject) === (b as AnyObject)
}

/// `value as ArrayLike<number>` → `[Double]` (best-effort element coercion).
fileprivate func asNumberArray(_ v: Any?) -> [Double] {
    if let a = v as? [Double] {
        return a
    }
    if let a = v as? [Any] {
        return a.map { ($0 as? Double) ?? Double.nan }
    }
    return []
}

func isTextRelatedEl(_ el: Element) -> Bool {
    return el.type == "text" || el.type == "tspan"
}

func canTransition(
    _ el: Element,
    _ noAnimation: Bool?,
    _ animationCfg: ElementAnimateConfig?
) -> Bool {
    return !(noAnimation ?? false)
        && el.__inHover == 0
        && animationCfg != nil
        && (animationCfg!.duration ?? 0) > 0
}

func shouldUseHoverLayer(
    _ el: Element,
    _ textContent: Element?,
    _ nextState: ElementState?,
    _ forceUseHoverLayer: Bool?
) -> InHoverLayerKind {
    // TODO: the hover-layer machinery (HOVER_LAYER_CONSTRAINTS_TEXT) is
    //   intentionally dropped in this port (see the `useState` note) — emphasis/blur/select
    //   apply directly rather than promoting elements to a separate hover layer. This always
    //   reports "not in hover layer".
    return IN_HOVER_LAYER_KIND_NO
}

// upstream: export default Element;


// ============================================================================
// Forward-declaration placeholders (note: all removed — see the per-type NOTES below).
//
// These types were placeholders until later phases; they are now all ported (see NOTES below).
// Their real locations:
//   - Path     → graphic/Path.ts          (Phase 1, 4a)
//   - Group    → graphic/Group.ts         (Phase 1, 4a)
//   - ZRText   → graphic/Text.ts          (Phase 2)
//   - Polyline → graphic/shape/Polyline.ts (Phase 1, 4b)
//   - ZRenderType → zrender.ts            (the ZRender instance interface)
//   - DefaultTextStyle → graphic/Text.ts  (Phase 2)
// ============================================================================

// NOTE: `ZRenderType` is now the real type, ported in ZRender.swift as
//   `public typealias ZRenderType = ZRender` (upstream `interface ZRenderType extends ZRender`).
//   The forward-declared placeholder protocol previously here has been removed; `Element.__zr` is
//   the real `ZRender` (refresh / refreshHover / wakeUp / isDarkMode / getBackgroundColor / storage /
//   animation all resolve on it). Animation registration is wired in addSelfToZr / removeSelfFromZr
//   below (Animation is a Phase-3 type-surface stub — see ZRender.swift).

// NOTE: `Path` is now ported for real in graphic/Path.swift (extends Displayable extends Element);
//   the forward-declaration placeholder previously here (`public class Path: Element {}`) has been
//   removed. `Element`'s `__clipPaths` / `_clipPath` / `setClipPath` / `getClipPath` references
//   resolve to the real `Path` (still an `Element` subclass).

// NOTE: `Group` is now ported for real in graphic/Group.swift (extends Element); the
//   forward-declaration placeholder previously here has been removed.

// NOTE: `ZRText` is now ported for real in graphic/Text.swift (extends Displayable extends Element,
//   implements GroupLike); the forward-declaration placeholder previously here
//   (`public final class ZRText: Element { var innerTransformable }`) has been removed. `Element`'s
//   `_textContent` / `getTextContent` / `setTextContent` / `innerTransformable` references resolve to
//   the real `ZRText`.

// NOTE: `Polyline` is now ported for real in graphic/Shape/Polyline.swift (extends Path extends
//   Displayable extends Element); the forward-declaration placeholder previously here
//   (`public final class Polyline: Element {}`) has been removed. `Element`'s `_textGuide` /
//   `getTextGuideLine` / `setTextGuideLine` references resolve to the real `Polyline`.

// NOTE: `DefaultTextStyle` is now ported for real in graphic/Text.swift (the inside-text default-style
//   bag: fill/stroke/align/verticalAlign/autoStroke/overflowRect); the placeholder empty struct
//   previously here has been removed.
