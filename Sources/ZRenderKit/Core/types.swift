// Ported from zrender/src/core/types.ts — keep in sync with upstream

public typealias Dictionary<T> = [String: T]

/**
 * Not readonly ArrayLike
 * Include Array, TypedArray
 */
// PORT-TODO: upstream ArrayLike<T> is a structural `{ [key: number]: T; length: number }`.
// Swift `[T]` (and ContiguousArray<T>) satisfies that shape for our purposes.
public typealias ArrayLike<T> = [T]

/**
 * NOTICE: For historical reason, zrender have not enabled TS config
 * `strictNullChecks` yet. Therefore, a explicitly declared `NullUndefined` can
 * indicate a variable can be `null` or `undefined` without more investigation,
 * but a variable without `NullUndefined` may also be `null` or `undefined`,
 * which has to be determined by the implementation.
 */
// PORT-TODO: `NullUndefined = null | undefined` has no Swift equivalent as a standalone
// type; per CONVENTIONS §6, both null and undefined collapse to `nil` at use sites (`T?`).

// PORT-TODO: ImageLike = HTMLImageElement | HTMLCanvasElement | HTMLVideoElement —
// browser image-source types; backend seam (CONVENTIONS §9). Needs native equivalent.
// public typealias ImageLike = ...

// subset of CanvasTextBaseline
public enum TextVerticalAlign: String {
    case top
    case middle
    case bottom
    // case center // DEPRECATED
}

// TODO: Have not support 'start', 'end' yet.
// subset of CanvasTextAlign
public enum TextAlign: String {
    case left
    case center
    case right
    // case middle // DEPRECATED
}

// FontWeight = 'normal' | 'bold' | 'bolder' | 'lighter' | number
public enum FontWeight {
    case normal
    case bold
    case bolder
    case lighter
    case number(Double)
}

public enum FontStyle: String {
    case normal
    case italic
    case oblique
}

public enum BuiltinTextPosition: String {
    case left
    case right
    case top
    case bottom
    case inside
    case insideLeft
    case insideRight
    case insideTop
    case insideBottom
    case insideTopLeft
    case insideTopRight
    case insideBottomLeft
    case insideBottomRight
}

// PORT-TODO: WXCanvasRenderingContext = CanvasRenderingContext2D & { draw: () => void } —
// canvas backend type (CONVENTIONS §9), routed through Renderer/Painter seam.

// PORT-TODO: ZRCanvasRenderingContext = CanvasRenderingContext2D & { dpr; __attrCachedBy } —
// canvas backend type (CONVENTIONS §9), routed through Renderer/Painter seam.

// Properties zrender will extended to the raw event
struct ZREventProperties {
    var zrX: Double = 0
    var zrY: Double = 0
    var zrDelta: Double = 0

    // 'no_globalout' means: do not trigger "globalout" event to zr user.
    // 'only_globalout" means: only trigger "globalout" event, but do not
    //     trigger other event to zr user.
    enum ZREventControl: String {
        case no_globalout
        case only_globalout
    }
    var zrEventControl: ZREventControl?

    var zrByTouch: Bool = false
}

// PORT-TODO: ZRRawMouseEvent / ZRRawTouchEvent / ZRRawPointerEvent = (MouseEvent|TouchEvent)
// & ZREventProperties — browser DOM event types; handled at the native event seam.

// PORT-TODO: ZRRawEvent = ZRRawMouseEvent | ZRRawTouchEvent | ZRRawPointerEvent — see above.

// PORT-TODO: ZRPinchEvent = ZRRawEvent & { pinchScale; pinchX; pinchY; gestureEvent } —
// browser gesture event; handled at the native event seam.

public enum ElementEventName: String {
    case click
    case dblclick
    case mousewheel
    case mouseout
    case mouseover
    case mouseup
    case mousedown
    case mousemove
    case contextmenu
    case drag
    case dragstart
    case dragend
    case dragenter
    case dragleave
    case dragover
    case drop
    case globalout
    // upstream dispatches the gesture type (e.g. 'pinch') through `type as ElementEventName`
    //   in `Handler.processGesture` — a TS cast that bypasses the union, so 'pinch' is not a
    //   literal member upstream. Added here so the Swift enum can carry it. // PORT-TODO: deviation.
    case pinch
}

public enum ElementEventNameWithOn: String {
    case onclick
    case ondblclick
    case onmousewheel
    case onmouseout
    case onmouseup
    case onmousedown
    case onmousemove
    case oncontextmenu
    case ondrag
    case ondragstart
    case ondragend
    case ondragenter
    case ondragleave
    case ondragover
    case ondrop
}

public struct RenderedEvent {
    public var elapsedTime: Double
}

// Useful type methods
// PORT-TODO: PropType<TObj, TProp> — TS keyof/index-access utility type; no Swift equivalent.
// PORT-TODO: AllPropTypes<T> — TS utility type; no Swift equivalent.
// PORT-TODO: FunctionPropertyNames<T> — TS mapped/conditional utility type; no Swift equivalent.
// PORT-TODO: MapToType<T, S> — TS recursive mapped utility type; no Swift equivalent.

// See https://www.staging-typescript.org/docs/handbook/advanced-types.html#distributive-conditional-types
// For the case:
// `keyof A | B` does not equals to `Keyof A | Keyof B`
// KeyOfDistributive<A | B> equals to `KeyOfDistributive<A> | KeyOfDistributive<B>`
// PORT-TODO: KeyOfDistributive<T> — TS distributive conditional type; no Swift equivalent.

// PORT-TODO: WithThisType<Func, This> — TS `this`-parameter utility type; no Swift equivalent.


/**
 * - `0` means incremental rendering is disabled.
 * - A positive integer enables increamental rendering,
 *  And distinguish different runs of consecutive incremental elements.
 * - `1` is preserved from backward compatibility - truthy value will be converted
 *   to `1`.
 *
 * @see DISPLAY_LIST_SORTING_AND_LAYERING for more details.
 */
public typealias IncrementalId = Double
// Previously `el.incremental` is boolean. This is only used
// for both TS type and value backward compatibility.
// Internal conversion: true => 1, false => 0.
// PORT-TODO: IncrementalIdCompat = number | boolean — modeled as Double; the boolean
// arm is converted at use sites per the comment above (true => 1, false => 0).
public typealias IncrementalIdCompat = Double
public let INCREMENTAL_ID_FALSE: Double = 0
public let INCREMENTAL_ID_TRUE_COMPAT: Double = 1


public typealias ZLevel = Double
// zlevel2 can not be specified by users. It is assigned internally
// and always be 0, 1, 2; never be greater than 2.
// PORT-TODO: ZLevel2 = typeof ZLEVEL2_NORMAL_ABOVE | typeof ZLEVEL2_INCREMENTAL
// | typeof ZLEVEL2_NORMAL_BELOW — a literal-typeof union (values 2 | 1 | 0); modeled as Double.
public typealias ZLevel2 = Double

public let ZLEVEL2_NORMAL_ABOVE: Double = 2
public let ZLEVEL2_INCREMENTAL: Double = 1
public let ZLEVEL2_NORMAL_BELOW: Double = 0
