// Ported from zrender/src/Element.ts — keep in sync with upstream
//
// PHASE-1 (render-only) PORT. This is the keystone of the scene graph. The parts needed
// to build and render a STATIC scene graph are translated faithfully; the rest is STUBBED
// with `// PORT-TODO` (faithful signatures, deferred to later phases) so it compiles.
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
// STUBBED (PORT-TODO, deferred):
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
// import Path from './graphic/Path';                     → forward-declared placeholder (PORT-TODO)
// import ZRText, { DefaultTextStyle } from './graphic/Text';  → forward-declared placeholder (Phase 2)
// import Polyline from './graphic/shape/Polyline';       → forward-declared placeholder (PORT-TODO)
// import Group from './graphic/Group';                   → forward-declared placeholder (PORT-TODO)
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
//   → PORT-TODO: contain/text.ts is Phase 1 (4c); not ported yet.

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
    // PORT-TODO: faithful data bag for the ZRText integration (Phase 2). The union-typed
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

public struct ElementEvent {
    // PORT-TODO: ElementEvent references ZRRawEvent and the gesture/touch fields, which belong
    // to the native event-dispatch seam (CONVENTIONS §9), not the render-only milestone. Minimal
    // placeholder so `drift`'s optional `e` param keeps a faithful type.
    public var type: ElementEventName?
    public var target: Element?
    public var topTarget: Element?
    public var cancelBubble: Bool = false
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    // PORT-TODO: `event` is the underlying ZRRawEvent (browser DOM event), modeled as Any? at
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

// PORT-TODO: ElementEventCallback / CbThis<Ctx, Impl> — `this`-bound event callback typing.
//   Collapses to the `EventCallback` defined in Core/Eventful.swift (event seam, CONVENTIONS §9).
// PORT-TODO: interface ElementEventHandlerProps — the `onclick`/`ondrag`/... handler-prop set.
//   These are the native event seam; not modeled in render-only Phase 1.

// PORT-TODO: interface ElementProps extends Partial<ElementEventHandlerProps> & Partial<Pick<
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

// PORT-TODO: ElementStatePropNames / ElementState / ElementCommonState — `Pick<ElementProps, ...>`
//   utility types. The states machinery is stubbed (Phase 2); `ElementState` is modeled as an
//   opaque prop bag carrying just the fields the stub references.
public struct ElementState {
    public var props: [String: Any] = [:]
    public var textConfig: ElementTextConfig?
    public var hoverLayer: Any?   // upstream: boolean | number
    public init() {}
}

// TextPositionCalculationResult is now ported in Contain/text.swift; the opaque stub is removed.
public typealias ElementCalculateTextPosition = (
    _ out: TextPositionCalculationResult,
    _ style: ElementTextConfig,
    _ rect: RectLike
) -> TextPositionCalculationResult

// Module scratch buffers (upstream module-level consts).
// PORT-TODO: tmpTextPosCalcRes / tmpInnerTextTrans support `updateInnerText` (Phase 2 text).
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
//   primary props (TRANSFORMABLE_PROPS + `ignore`). PORT-TODO: subclasses (Displayable/Path) would
//   override `animationGet`/`animationSet` to expose the value-type `style`/`shape` bags — those are
//   structs (no shared identity), so nested-bag animation stays deferred for now.
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

    /// When this element has `__hostTarget` (e.g., this is a `textContent`), whether
    /// its silent is controlled by that host silent.
    public var ignoreHostSilent: Bool = false

    /// 是否是 Group
    public var isGroup: Bool = false

    /// Whether it can be dragged.
    public var draggable: ElementDraggable = .false

    /// Whether is it dragging.
    public var dragging: Bool = false

    // upstream: parent: Group
    // PORT-TODO: upstream narrows `parent` to `Group`; we inherit `Transformable.parent`
    //   (typed `Transformable?`) and cast to `Element`/`Group` at use sites.

    public var animators: [Animator<Any>] = []

    /// If ignore clip from it's parent or hosts. Applied on itself and all it's children.
    public var ignoreClip: Bool = false

    /// If element is used as a component of other element.
    public var __hostTarget: Element?

    /// ZRender instance will be assigned when element is associated with zrender
    public var __zr: ZRenderType?

    // ===== morphPath seam (PORT-TODO: see Tool/morphPath.swift) =====
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
    // PORT-TODO: retain cycle — once a listener is bound, the inner Eventful stores `ctx = self`
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
    public func beforeUpdate() {}
    /// Hook after update
    public func afterUpdate() {}
    /// Update each frame
    public func update() {
        self.updateTransform()

        if self.__dirty != 0 {
            self.updateInnerText()
        }
    }

    public func updateInnerText(_ forceUpdate: Bool? = nil) {
        // PORT-TODO: ZRText (Text) integration is Phase 2. The faithful body lays out the
        //   attached `_textContent`: applies host transform, calculates text position via
        //   contain/text.ts `calculateTextPosition`, resolves inside/outside fill & stroke, and
        //   flags the text element dirty. Deferred — no-op for render-only.
        _ = forceUpdate
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
        let isDark = self.__zr!.isDarkMode()
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
            // PORT-TODO: Swift has no dynamic member assignment; the known Element/Transformable
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
            // PORT-TODO: unknown prop key — handled by subclass `attrKV` override or ignored.
            break
        }
    }

    // ---- AnimationTarget conformance ----
    //
    // upstream uses dynamic `(this as any)[key]` get/set on the animate target. The animator
    //   routes keyed read/write through `AnimationTarget` (Animator.swift). The base exposes the
    //   Element / Transformable primary props; `animationSet` reuses `_setKnownKV` (plain assign,
    //   NOT markRedraw — repaint is driven by `updateDuringAnimation` in the during callback,
    //   matching upstream `target[propName] = value`). PORT-TODO: Displayable/Path would override
    //   these to expose the value-type `style`/`shape` bags (deferred — see class note).
    public func animationGet(_ key: String) -> Any? {
        return self._getKnownKV(key)
    }

    public func animationSet(_ key: String, _ value: Any?) {
        self._setKnownKV(key, value)
    }

    // Explicit replacement for upstream's dynamic `(this as any)[key]` read.
    private func _getKnownKV(_ key: String) -> Any? {
        switch key {
        // Element props
        case "name": return self.name
        case "ignore": return self.ignore
        case "silent": return self.silent
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
            // PORT-TODO: unknown / sub-bag key — handled by subclass override or returns nil
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
        // PORT-TODO: states machinery is Phase 2. Faithful body saves the current value of each
        //   primary/animatable prop to `_normalState` (including final animation values). Deferred.
        self._innerSaveToNormal(toState)
    }

    internal func _innerSaveToNormal(_ toState: ElementState) {  // upstream: protected
        // PORT-TODO: states machinery is Phase 2. Deferred.
        if self._normalState == nil {
            self._normalState = ElementState()
        }
    }

    internal func _savePrimaryToNormal(  // upstream: protected
        _ toState: [String: Any], _ normalState: inout [String: Any], _ primaryKeys: [String]
    ) {
        // PORT-TODO: states machinery is Phase 2. Faithful body copies each `primaryKeys` value
        //   from `this` into `normalState` (when changed by `toState` and not yet saved). Deferred.
    }

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
    @discardableResult
    public func useState(
        _ stateName: String,
        _ keepCurrentStates: Bool? = nil,
        _ noAnimation: Bool? = nil,
        _ forceUseHoverLayer: Bool? = nil
    ) -> ElementState? {
        // PORT-TODO: states / emphasis / blur / select machinery is Phase 2. The faithful body
        //   resolves the named state (stateProxy → states), saves current-to-normal, enters/leaves
        //   the hover layer, applies the state object (with optional transition animation), and
        //   cascades to textContent / textGuide. Deferred — no-op for render-only.
        return nil
    }

    /// Apply multiple states.
    public func useStates(
        _ states: [String],
        _ noAnimation: Bool? = nil,
        _ forceUseHoverLayer: Bool? = nil
    ) {
        // PORT-TODO: states machinery is Phase 2 (merges state objects + applies). Deferred.
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
                // PORT-TODO: upstream `parent` is `Group`; we inherit `Transformable.parent`.
                el = cur.parent as? Element
            }
        }
        return false
    }

    /// Update animation targets when reference is changed.
    private func _updateAnimationTargets() {
        // PORT-TODO: animation surface deferred (Phase 3). Faithful body re-points each animator
        //   whose `targetName` is set at the (possibly replaced) sub-target. Deferred.
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
        // PORT-TODO: states machinery is Phase 2 (extends each state + merges textConfig). Deferred.
        return ElementState()
    }

    internal func _applyStateObj(  // upstream: protected
        _ stateName: String,
        _ state: ElementState?,
        _ normalState: ElementState?,
        _ keepCurrentStates: Bool,
        _ transition: Bool,
        _ animationCfg: ElementAnimateConfig?
    ) {
        // PORT-TODO: states machinery is Phase 2. The faithful body applies textConfig + each
        //   primary key (with optional transition), and keeps running animators consistent. Deferred.
    }

    /// Component is some elements attached on this element for specific purpose.
    /// Like clipPath, textContent
    private func _attachComponent(_ componentEl: Element) {
        if componentEl.__zr != nil && componentEl.__hostTarget == nil {
            // PORT-TODO: dev-mode `throw new Error('Text element has been added to zrender.')`.
            return
        }

        if componentEl === self {
            // PORT-TODO: dev-mode `throw new Error('Recursive component attachment.')`.
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
        // PORT-TODO: dev-mode guard `textEl.__zr && !textEl.__hostTarget` → throw.

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
        // PORT-TODO: upstream `extend(this.textConfig, cfg)` does a field-merge; the ZRText
        //   integration is Phase 2, so the stub assigns the latest `cfg` wholesale.
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
        // PORT-TODO: dynamic `(this as any)[key]` fetch of a sub-bag (e.g. 'style'/'shape') is not
        //   available on `Element` base — those bags are value-type structs on Displayable/Path
        //   (no shared identity). The target is `self` (an AnimationTarget); `targetName = key`
        //   still routes keyed get/set through `self`. A keyed sub-target needs the Displayable/Path
        //   override (deferred). The dev-mode `if (!target) logError(...)` existence check is dropped.
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
        if let zr = zr {
            zr.animation.addAnimator(animator)
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
            if scope == nil || scope == animator.scope {
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
    //   PORT-TODO: the legacy `position`/`scale`/`origin` array accessors (createLegacyProperty /
    //   enhanceArray) are deprecated DOM-defineProperty shims; not ported.

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
            // PORT-TODO: >2 trigger args can't be splatted into the inner variadic. zrender's
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
            // PORT-TODO: see `trigger` — variadic splat limitation. Not exercised by zrender's
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
            // upstream: animator.duration(cfg.duration). PORT-TODO: guarded — `duration` may be nil
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
            // PORT-TODO: number[] | Float32Array typed-array branch — no typed arrays natively;
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
    // PORT-TODO: if `obj` is a value-type `[String: Any]` bag, the set has no shared identity and
    //   is dropped. The animate targets in use are reference-type AnimationTargets (Element), so
    //   this is the safe default; style/shape value-bags stay deferred (see Element class note).
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
    // PORT-TODO: upstream values are booleans; a non-bool present value is treated as truthy.
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
    // PORT-TODO: states / hover-layer machinery is Phase 2 (see HOVER_LAYER_CONSTRAINTS_TEXT).
    //   Stub returns "not in hover layer" deterministically. Deferred.
    return IN_HOVER_LAYER_KIND_NO
}

// upstream: export default Element;


// ============================================================================
// Forward-declaration placeholders (PORT-TODO).
//
// These types are ported in later phases; declared here only so `Element` compiles.
// When the real files land, DELETE the corresponding placeholder and import the real type:
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
