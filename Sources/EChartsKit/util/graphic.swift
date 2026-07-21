// Ported from echarts/src/util/graphic.ts — keep in sync with upstream
// (Partial: `expandOrShrinkRect` / `expandRectOnOneDimension`, the transform helpers, the shape-class
//  registry, and `createIcon` are landed here so far.
//  Also landed: clipRectByRect, groupTransition, setTooltipConfig, calcZ2Range, extendPath.
//  PORT-NOTE (deferred): extendShape (needs a `Path.extend` runtime-subclass synthesizer in ZRenderKit)
//  and a few driver-layer helpers (traverseElements/traverseUpdateZ/decomposeTransform/…) are not ported here yet.)

import Foundation
import ZRenderKit

// upstream: export function expandOrShrinkRect<TRect extends RectLike>(rect, delta, shrinkOrExpand, noNegative, minSize?)
//   Grows (or shrinks, when `shrinkOrExpand`) `rect` on each side. `delta` is a scalar (applied to all four
//   sides) or a `[top, right, bottom, left]` array; `noNegative` clamps the deltas to >= 0. `minSize`
//   ([w, h], default [0, 0]) is the floor each dimension collapses to. Mutates `rect` IN PLACE — matching the
//   JS (BoundingRect is a reference type). Returns the same rect for chaining.
@discardableResult
public func expandOrShrinkRect(
    _ rect: RectLike,
    _ delta: Any?,
    _ shrinkOrExpand: Bool,
    _ noNegative: Bool,
    _ minSize: [Double]? = nil
) -> RectLike {
    // if (delta == null) { return rect; }
    guard let delta = delta else { return rect }
    var d: [Double]
    if let n = delta as? Double {
        d = [n, n, n, n]
    }
    else if let i = delta as? Int {
        let n = Double(i); d = [n, n, n, n]
    }
    else if let arr = delta as? [Double], arr.count == 4 {
        d = arr
    }
    else if let arr = delta as? [Any], arr.count == 4 {
        d = arr.map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) }
    }
    else {
        return rect
    }
    // if (noNegative) { each delta = max(0, delta) }
    if noNegative {
        for k in 0..<4 { d[k] = Swift.max(0, d[k]) }
    }
    // if (shrinkOrExpand) { negate each delta }
    if shrinkOrExpand {
        for k in 0..<4 { d[k] = -d[k] }
    }
    // expandRectOnOneDimension(rect, delta, 'x', 'width', 3, 1, minSize?[0] || 0);
    expandRectOnOneDimension(rect, d, true, 3, 1, (minSize.flatMap { $0.count > 0 ? $0[0] : nil }) ?? 0)
    // expandRectOnOneDimension(rect, delta, 'y', 'height', 0, 2, minSize?[1] || 0);
    expandRectOnOneDimension(rect, d, false, 0, 2, (minSize.flatMap { $0.count > 1 ? $0[1] : nil }) ?? 0)
    return rect
}

// upstream: const AXIS_ALIGN_EPSILON = 1e-5;
private let AXIS_ALIGN_EPSILON = 1e-5

/// upstream: export function isBoundingRectAxisAligned(transform)
/// After a boundingRect applying a `transform`, whether to be still parallel screen X and Y.
public func isBoundingRectAxisAligned(_ transform: MatrixArray?) -> Bool {
    guard let transform = transform else { return true }
    return (Swift.abs(transform[1]) < AXIS_ALIGN_EPSILON && Swift.abs(transform[2]) < AXIS_ALIGN_EPSILON)
        || (Swift.abs(transform[0]) < AXIS_ALIGN_EPSILON && Swift.abs(transform[3]) < AXIS_ALIGN_EPSILON)
}

/// upstream: export function ensureCopyRect(target, source)
/// Create or copy to the existing bounding rect to avoid modifying `source`.
public func ensureCopyRect(_ target: BoundingRect?, _ source: BoundingRect) -> BoundingRect {
    if let target = target {
        return BoundingRect.copy(target, source)
    }
    return source.clone()
}

/// upstream: export function ensureCopyTransform(target, source)
/// Create or copy to the existing transform to avoid modifying `source`. `nil` if no transform,
/// following zrender's convention (enables bypassing unnecessary calculation).
/// PORT-NOTE: `matrix.copy` is value-returning here (CONVENTIONS §3), so the incoming `target`
/// scratch buffer is unused and a fresh MatrixArray is returned.
public func ensureCopyTransform(_ target: MatrixArray?, _ source: MatrixArray?) -> MatrixArray? {
    guard let source = source else { return nil }
    return matrix.copy(source)
}

// upstream: function expandRectOnOneDimension(rect, delta, xy, wh, ltIdx, rbIdx, minSize)
//   `isX` selects the x/width pair (true) vs y/height (false). `ltIdx`/`rbIdx` index the left-top /
//   right-bottom delta for that dimension.
private func expandRectOnOneDimension(
    _ rect: RectLike, _ delta: [Double], _ isX: Bool, _ ltIdx: Int, _ rbIdx: Int, _ minSizeIn: Double
) {
    let deltaSum = delta[rbIdx] + delta[ltIdx]
    let oldSize = isX ? rect.width : rect.height
    var newSize = oldSize + deltaSum
    // minSize = max(0, min(minSize, oldSize));
    let minSize = Swift.max(0, Swift.min(minSizeIn, oldSize))
    if newSize < minSize {
        newSize = minSize
        // Try to make the position of the zero rect reasonable in most visual cases.
        let shift: Double =
            delta[ltIdx] >= 0 ? -delta[ltIdx]
            : delta[rbIdx] >= 0 ? oldSize + delta[rbIdx]
            : Swift.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[ltIdx] / deltaSum
            : 0
        if isX { rect.x += shift } else { rect.y += shift }
    }
    else {
        if isX { rect.x -= delta[ltIdx] } else { rect.y -= delta[ltIdx] }
    }
    if isX { rect.width = newSize } else { rect.height = newSize }
}

// ============================================================================
// Transform helpers (upstream util/graphic.ts:331-394) — the pieces the brush cover-drag
// (component/helper/BrushController) needs: the accumulated ancestor transform of an element, a
// vertex transform, and the "which global edge is my local edge" cursor mapping.
// ============================================================================

// upstream: export function getTransform(target: Transformable, ancestor?: Transformable): matrix.MatrixArray
public func getTransform(_ target: Transformable?, _ ancestor: Transformable? = nil) -> MatrixArray {
    // const mat = matrix.identity([]);
    var mat = matrix.identity()

    var target = target
    // while (target && target !== ancestor) { matrix.mul(mat, target.getLocalTransform(), mat); target = target.parent; }
    //   CONVENTIONS §3: `matrix.mul(out, m1, m2)` is value-returning here, so the self-aliased
    //   `mul(mat, ..., mat)` becomes `mat = mul(..., mat)`.
    while let t = target, t !== ancestor {
        mat = matrix.mul(t.getLocalTransform(), mat)
        target = t.parent
    }

    return mat
}

/**
 * Apply transform to an vertex.
 * @param target [x, y]
 * @param transform Transform matrix: like [1, 0, 0, 1, 0, 0]
 * @param invert Whether use invert matrix.
 * @return [x, y]
 */
// upstream: export function applyTransform(target, transform: Transformable | matrix.MatrixArray, invert?)
//   PORT-NOTE: the `Transformable` arm of the union (`transform = Transformable.getLocalTransform(transform)`)
//   is dropped — every call site in the ported code passes a MatrixArray. Pass
//   `Transformable.getLocalTransform(t)` explicitly if a Transformable is ever needed.
public func applyTransform(
    _ target: VectorArray,
    _ transform: MatrixArray?,
    _ invert: Bool? = nil
) -> [Double] {
    var transform = transform

    if invert == true, let t = transform {
        // transform = matrix.invert([], transform);
        transform = matrix.invert(t)
    }

    // return vector.applyTransform([], target, transform);
    guard let t = transform else { return [target[0], target[1]] }
    let out = vector.applyTransform(target, t)
    return [out[0], out[1]]
}

// upstream: export function transformDirection(direction, transform, invert?): 'left'|'right'|'top'|'bottom'
public func transformDirection(
    _ direction: String,
    _ transform: MatrixArray,
    _ invert: Bool? = nil
) -> String {

    // Pick a base, ensure that transform result will not be (0, 0).
    let hBase: Double = (transform[4] == 0 || transform[5] == 0 || transform[0] == 0)
        ? 1 : Swift.abs(2 * transform[4] / transform[0])
    let vBase: Double = (transform[4] == 0 || transform[5] == 0 || transform[2] == 0)
        ? 1 : Swift.abs(2 * transform[4] / transform[2])

    var vertex: VectorArray = VectorArray(
        direction == "left" ? -hBase : direction == "right" ? hBase : 0,
        direction == "top" ? -vBase : direction == "bottom" ? vBase : 0
    )

    let applied = applyTransform(vertex, transform, invert)
    vertex = VectorArray(applied[0], applied[1])

    return Swift.abs(vertex[0]) > Swift.abs(vertex[1])
        ? (vertex[0] > 0 ? "right" : "left")
        : (vertex[1] > 0 ? "bottom" : "top")
}

// upstream: export function clipPointsByRect(points: vector.VectorArray[], rect: ZRRectLike): number[][]
public func clipPointsByRect(_ points: [[Double]], _ rect: RectLike) -> [[Double]] {
    // FIXME: This way might be incorrect when graphic clipped by a corner
    // and when element has a border.
    return util.map(points) { point, _ in
        var x = point[0]
        x = Swift.max(x, rect.x)
        x = Swift.min(x, rect.x + rect.width)
        var y = point[1]
        y = Swift.max(y, rect.y)
        y = Swift.min(y, rect.y + rect.height)
        return [x, y]
    }
}

/**
 * Return a new clipped rect. If rect size are negative, return undefined.
 */
// upstream: export function clipRectByRect(targetRect: ZRRectLike, rect: ZRRectLike): ZRRectLike | undefined
public func clipRectByRect(_ targetRect: RectLike, _ rect: RectLike) -> RectLike? {
    let x = Swift.max(targetRect.x, rect.x)
    let x2 = Swift.min(targetRect.x + targetRect.width, rect.x + rect.width)
    let y = Swift.max(targetRect.y, rect.y)
    let y2 = Swift.min(targetRect.y + targetRect.height, rect.y + rect.height)

    // If the total rect is cliped, nothing, including the border,
    // should be painted. So return undefined.
    if x2 >= x && y2 >= y {
        return BoundingRect(x, y, x2 - x, y2 - y)
    }
    // upstream falls off the end -> `undefined`.
    return nil
}

/**
 * Return `true` if the given line (line `a`) and the given polygon
 * are intersect.
 * Note that we do not count colinear as intersect here because no
 * requirement for that. We could do that if required in future.
 */
// upstream: export function linePolygonIntersect(a1x, a1y, a2x, a2y, points): boolean
public func linePolygonIntersect(
    _ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
    _ points: [[Double]]
) -> Bool {
    if points.isEmpty { return false }
    var p2 = points[points.count - 1]
    for i in 0..<points.count {
        let p = points[i]
        if lineLineIntersect(a1x, a1y, a2x, a2y, p[0], p[1], p2[0], p2[1]) {
            return true
        }
        p2 = p
    }
    // upstream falls off the end -> `undefined` (falsy).
    return false
}

/**
 * Return `true` if the given two lines (line `a` and line `b`)
 * are intersect.
 * Note that we do not count colinear as intersect here because no
 * requirement for that. We could do that if required in future.
 */
// upstream: export function lineLineIntersect(a1x, a1y, a2x, a2y, b1x, b1y, b2x, b2y): boolean
public func lineLineIntersect(
    _ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
    _ b1x: Double, _ b1y: Double, _ b2x: Double, _ b2y: Double
) -> Bool {
    // let `vec_m` to be `vec_a2 - vec_a1` and `vec_n` to be `vec_b2 - vec_b1`.
    let mx = a2x - a1x
    let my = a2y - a1y
    let nx = b2x - b1x
    let ny = b2y - b1y

    // `vec_m` and `vec_n` are parallel iff
    //     existing `k` such that `vec_m = k · vec_n`, equivalent to `vec_m X vec_n = 0`.
    let nmCrossProduct = crossProduct2d(nx, ny, mx, my)
    if nearZero(nmCrossProduct) {
        return false
    }

    // `vec_m` and `vec_n` are intersect iff
    //     existing `p` and `q` in [0, 1] such that `vec_a1 + p * vec_m = vec_b1 + q * vec_n`,
    //     such that `q = ((vec_a1 - vec_b1) X vec_m) / (vec_n X vec_m)`
    //           and `p = ((vec_a1 - vec_b1) X vec_n) / (vec_n X vec_m)`.
    let b1a1x = a1x - b1x
    let b1a1y = a1y - b1y
    let q = crossProduct2d(b1a1x, b1a1y, mx, my) / nmCrossProduct
    if q < 0 || q > 1 {
        return false
    }
    let p = crossProduct2d(b1a1x, b1a1y, nx, ny) / nmCrossProduct
    if p < 0 || p > 1 {
        return false
    }

    return true
}

/**
 * Cross product of 2-dimension vector.
 */
// upstream: function crossProduct2d(x1, y1, x2, y2)
private func crossProduct2d(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
    return x1 * y2 - x2 * y1
}

// upstream: function nearZero(val)
private func nearZero(_ val: Double) -> Bool {
    return val <= 1e-6 && val >= -1e-6
}

// ============================================================================
// groupTransition (upstream util/graphic.ts:396-447) — apply group transition animation from g1 to g2.
//   Used by parallel-axis (and legacy `graphic` group) transition: matches elements across the two
//   groups by their `anid`, snaps each new element to the old element's pose, then animates it to its
//   own pose. If no `animatableModel`, the animation degrades to an instant set (see `updateProps`).
// ============================================================================

// upstream: function isNotGroup(el: Element): el is Displayable { return !el.isGroup; }
private func isNotGroup(_ el: Element) -> Bool {
    return !el.isGroup
}
// upstream: function isPath(el: Displayable): el is Path { return (el as Path).shape != null; }
private func isPath(_ el: Displayable) -> Bool {
    return el is Path
}

// upstream: export function groupTransition(g1: Group, g2: Group, animatableModel: Model<AnimationOptionMixin>)
public func groupTransition(_ g1: Group?, _ g2: Group?, _ animatableModel: Model?) {
    guard let g1 = g1, let g2 = g2 else {
        return
    }

    func getElMap(_ g: Group) -> [String: Displayable] {
        var elMap: [String: Displayable] = [:]
        _ = g.traverse { (el: Element) -> Bool in
            if isNotGroup(el), let anid = el.anid, let disp = el as? Displayable {
                elMap[anid] = disp
            }
            return false
        }
        return elMap
    }
    func getAnimatableProps(_ el: Displayable) -> [String: Any] {
        // const obj: PathProps = { x: el.x, y: el.y, rotation: el.rotation };
        var obj: [String: Any] = [
            "x": el.x,
            "y": el.y,
            "rotation": el.rotation
        ]
        // if (isPath(el)) { obj.shape = clone(el.shape); }
        // PORT-TODO: the "shape" entry below is a whole `PathShape` STRUCT, and `animateToShallow`'s
        //   recursion guard is `util.isObject`, which is false for a struct — so the track is
        //   classified VALUE_TYPE_UNKOWN / `discrete` and `Animator.start()` sets it straight to the
        //   final value. Every shape-carrying element therefore SNAPS instead of tweening (cartesian
        //   axis splitLine `line_*` / minorSplitLine `minor_line_*` / splitArea `area_*` and
        //   AxisBuilder's axisLine + ticks, while their labels tween via x/y — a visible
        //   inconsistency vs upstream). Fix: emit `shape` as a scalar `[String: Any]` sub-bag (the
        //   TreeView `bezierShapeDict` / ParallelView / SankeyView precedent) so `animateToShallow`
        //   recurses into `ShapeAnimationAccessor`; that needs a key-enumeration hook on
        //   `protocol PathShape` (ZRenderKit/Graphic/Path.swift).
        if isPath(el), let path = el as? Path, let shape = path.shape {
            obj["shape"] = util.clone(shape)
        }
        return obj
    }
    let elMap1 = getElMap(g1)

    _ = g2.traverse { (el: Element) -> Bool in
        if isNotGroup(el), let anid = el.anid, let newDisp = el as? Displayable {
            if let oldEl = elMap1[anid] {
                let newProp = getAnimatableProps(newDisp)
                // el.attr(getAnimatableProps(oldEl));
                _ = newDisp.attr(getAnimatableProps(oldEl))
                // updateProps(el, newProp, animatableModel, getECData(el).dataIndex);
                updateProps(newDisp, newProp, animatableModel,
                            innerStore.getECData(newDisp).dataIndex.map { Int($0) })
            }
        }
        return false
    }
}

// ============================================================================
// setTooltipConfig (upstream util/graphic.ts:675-720) — attach a component-level item tooltip config
//   (title/legend/geo/graphic/timeline) onto an element's ECData, so the tooltip component can resolve
//   a per-item tooltip for a component that is not a series datum.
// ============================================================================

// upstream: export function setTooltipConfig(opt: { el, componentModel, itemName, itemTooltipOption?, formatterParamsExtra? }): void
//   PORT-NOTE: upstream's single options bag is spread to labeled parameters here.
//   `itemTooltipOption` is `string | CommonTooltipOption<unknown>` -> `Any?`.
public func setTooltipConfig(
    el: Element,
    componentModel: ComponentModel,
    itemName: String,
    itemTooltipOption: Any? = nil,
    formatterParamsExtra: [String: Any]? = nil
) {
    // const itemTooltipOptionObj = isString(...) ? { formatter: ... } : itemTooltipOption;
    var itemTooltipOptionObj = CommonTooltipOption<Any>()
    var hasTooltipOptionObj = false
    if let s = itemTooltipOption as? String {
        itemTooltipOptionObj.formatter = s
        hasTooltipOptionObj = true
    }
    else if let o = itemTooltipOption as? CommonTooltipOption<Any> {
        itemTooltipOptionObj = o
        hasTooltipOptionObj = true
    }

    let mainType = componentModel.mainType
    let componentIndex = componentModel.componentIndex

    // const formatterParams = { componentType: mainType, name: itemName, $vars: ['name'] };
    // (formatterParams as any)[mainType + 'Index'] = componentIndex;
    var formatterParams = ComponentItemTooltipLabelFormatterParams(
        componentType: mainType,
        name: itemName,
        vars: ["name"]
    )
    formatterParams.other[mainType + "Index"] = componentIndex

    // if (formatterParamsExtra) { each(keys(...), key => { if (!hasOwn(formatterParams, key)) {...} }); }
    if let formatterParamsExtra = formatterParamsExtra {
        util.each(util.keys(formatterParamsExtra)) { key, _ in
            if !formatterParamsHasOwn(formatterParams, key) {
                formatterParams.other[key] = formatterParamsExtra[key]
                formatterParams.vars.append(key)
            }
        }
    }

    let ecData = innerStore.getECData(el)
    ecData.componentMainType = mainType
    ecData.componentIndex = componentIndex
    // ecData.tooltipConfig = { name, option: defaults({ content, encodeHTMLContent, formatterParams }, itemTooltipOptionObj) };
    //   PORT-NOTE: `defaults` merges the CommonTooltipOption fields (`itemTooltipOptionObj`) beneath the
    //     own `content`/`encodeHTMLContent`/`formatterParams`; in this model the common tooltip fields
    //     live on `ComponentItemTooltipOption.common`, so the merge is expressed structurally.
    ecData.tooltipConfig = ECData.TooltipConfig(
        name: itemName,
        option: ComponentItemTooltipOption<Any>(
            common: hasTooltipOptionObj ? itemTooltipOptionObj : CommonTooltipOption<Any>(),
            content: itemName,
            encodeHTMLContent: true,
            formatterParams: formatterParams
        )
    )
}

// upstream inline `hasOwn(formatterParams, key)` — whether `formatterParams` already carries `key`.
private func formatterParamsHasOwn(_ fp: ComponentItemTooltipLabelFormatterParams, _ key: String) -> Bool {
    return key == "componentType" || key == "name" || key == "$vars" || fp.other[key] != nil
}

// upstream: function traverseElement(el: Element, cb: (el: Element) => boolean | void)
//   Polyfill for zrender group traverse not visiting its own root.
private func traverseElement(_ el: Element, _ cb: (_ el: Element) -> Bool) {
    var stopped = false
    if el.isGroup {
        stopped = cb(el)
    }
    if !stopped, let g = el as? Group {
        _ = g.traverse(cb)
    }
}

// ============================================================================
// calcZ2Range (upstream util/graphic.ts:801-840) — compute the [min, max] z2 across an element tree
//   (including its state overrides, textContent, and textGuideLine). Used to lift labels above glyphs.
//   Assumes all elements share the same `z`/`zlevel`.
// ============================================================================

// upstream: export function calcZ2Range(el: Element): { min: number, max: number }
public func calcZ2Range(_ el: Element) -> (min: Double, max: Double) {
    var maxV = -Double.infinity
    var minV = Double.infinity

    func calcZ2(_ z2: Double?) {
        // Consider z2 may be NullUndefined
        if let z2 = z2 {
            if z2 > maxV {
                maxV = z2
            }
            if z2 < minV {
                minV = z2
            }
        }
    }
    func visitEl(_ el: Element?) {
        guard let el = el, !el.isGroup else {
            return
        }
        let currentStates = el.currentStates
        if currentStates.count > 0 {
            for idx in 0..<currentStates.count {
                // el.states[currentStates[idx]] as Displayable — reads a state's z2 override (may be absent).
                if let state = el.states[currentStates[idx]] {
                    calcZ2(state.props["z2"] as? Double)
                }
            }
        }
        calcZ2((el as? Displayable)?.z2)
    }

    traverseElement(el) { e -> Bool in
        visitEl(e)
        visitEl(e.getTextContent())
        visitEl(e.getTextGuideLine())
        return false
    }

    if minV > maxV {
        minV = 0
        maxV = 0
    }
    return (min: minV, max: maxV)
}

// ============================================================================
// extendPath (upstream util/graphic.ts:118-127) — user-facing "extend a Path subclass from an SVG path
//   string" API. Mirrors upstream `extendPath = pathTool.extendFromString`.
//   PORT-NOTE: `extendShape` (upstream :114-116, `Path.extend(opts)`) is NOT ported here — it needs a
//     `Path.extend` runtime-subclass synthesizer in ZRenderKit's Path, which does not exist yet.
// ============================================================================

// upstream: export function extendPath(pathData: string, opts: SVGPathOption): SVGPathCtor
//   Returns a factory closure (the ported stand-in for the synthesized `class Sub extends SVGPath`),
//   matching `ZRenderKit.extendFromString`'s convention.
@discardableResult
public func extendPath(_ pathData: String, _ opts: SVGPathOption? = nil) -> (SVGPathOption?) -> SVGPath {
    return extendFromString(pathData, opts)
}

// ============================================================================
// The name -> shape-class registry (upstream util/graphic.ts:95-175 + the registrations at :952-960).
//
// `graphic: [{ type: 'polygon', ... }]` names its element by STRING; upstream resolves it through
// this map. It was never ported, so GraphicView could only build group/image/text and asserted on
// everything else — `graphic type polygon can not be found`. 14 official examples use `graphic`.
// ============================================================================

// const _customShapeMap: Dictionary<{ new(): Path }> = {};
//   -> the value is a FACTORY, not a metatype: ZRenderKit's shapes take `init(_ opts: ElementProps?)`,
//      and Swift cannot express "a Path subclass constructible from opts" as a single existential.
private var _customShapeMap: [String: (ElementProps?) -> Path] = [
    // registerShape('circle', Circle); … (upstream util/graphic.ts:952-960)
    "circle":      { Circle($0) },
    "ellipse":     { Ellipse($0) },
    "sector":      { Sector($0) },
    "ring":        { Ring($0) },
    "polygon":     { Polygon($0) },
    "polyline":    { Polyline($0) },
    "rect":        { Rect($0) },
    "line":        { Line($0) },
    "bezierCurve": { BezierCurve($0) }
]

// export function registerShape(name: string, ShapeClass: {new(): Path})
public func registerShape(_ name: String, _ factory: @escaping (ElementProps?) -> Path) {
    _customShapeMap[name] = factory
}

// export function getShapeClass(name: string): {new(): Path}
//   -> returns the FACTORY (see above); nil when the name is unknown, exactly as upstream returns
//      `undefined` (its callers assert on it in DEV).
public func getShapeClass(_ name: String) -> ((ElementProps?) -> Path)? {
    return _customShapeMap[name]
}

// ============================================================================
// createIcon (upstream util/graphic.ts:484) — build a draggable icon element from an icon string.
//   Used by the axisPointer draggable HANDLE (BaseAxisPointer._renderHandle), the dataZoom slider
//   handles, the toolbox feature buttons, etc. Supports 'image://…' (→ ZRImage) or a 'path://…' /
//   raw SVG path string (→ SVGPath via `makePath`).
// ============================================================================

// upstream:
//   export function createIcon(
//       iconStr: string,                       // 'image://' or 'path://' or direct svg path.
//       opt?: Omit<DisplayableProps, 'style'>,
//       rect?: ZRRectLike
//   ): SVGPath | ZRImage {
//       const innerOpts: DisplayableProps = extend({rectHover: true}, opt);
//       const style: ZRStyleProps = innerOpts.style = {strokeNoScale: true};
//       rect = rect || {x: -1, y: -1, width: 2, height: 2};
//       if (iconStr) {
//           return iconStr.indexOf('image://') === 0
//               ? ( (style as ImageStyleProps).image = iconStr.slice(8),
//                   defaults(style, rect),
//                   new ZRImage(innerOpts) )
//               : ( makePath(iconStr.replace('path://', ''), innerOpts, rect, 'center') );
//       }
//   }
//
//   PORT-NOTE (event handlers): upstream's `opt` may also carry the native handler props
//   (`onmousemove`/`onmousedown`/`drift`/`ondragend`) — those live at the event seam (CONVENTIONS §9)
//   and are NOT modeled on `DisplayableProps` here. Callers (BaseAxisPointer) wire them onto the
//   returned element AFTER construction (via `el.on(...)` + `el.driftHandler`). The `opt` bag passed
//   here therefore carries only the plain displayable props (`cursor`, `draggable`, …).
public func createIcon(
    _ iconStr: String?,
    _ opt: [String: Any]? = nil,
    _ rect: RectLike? = nil
) -> Displayable? {
    // const innerOpts = extend({rectHover: true}, opt);
    var innerOpts: [String: Any] = ["rectHover": true]
    if let opt = opt {
        _ = util.extend(&innerOpts, opt)
    }
    // rect = rect || {x: -1, y: -1, width: 2, height: 2};
    let r: RectLike = rect ?? BoundingRect(-1, -1, 2, 2)

    guard let iconStr = iconStr, !iconStr.isEmpty else {
        // upstream: `if (iconStr) { ... }` with no else — returns `undefined` when the icon is empty.
        return nil
    }

    if iconStr.hasPrefix("image://") {
        // (style as ImageStyleProps).image = iconStr.slice(8); defaults(style, rect); new ZRImage(innerOpts)
        var imageStyle = ImageStyleProps()
        imageStyle.image = .url(String(iconStr.dropFirst("image://".count)))
        // defaults(style, rect) — fill the missing x/y/width/height from `rect`.
        imageStyle.x = r.x
        imageStyle.y = r.y
        imageStyle.width = r.width
        imageStyle.height = r.height
        innerOpts["style"] = imageStyle
        return ZRImage(innerOpts)
    }
    else {
        // makePath(iconStr.replace('path://', ''), innerOpts, rect, 'center')
        // const style = innerOpts.style = {strokeNoScale: true};
        var style = PathStyleProps()
        style.strokeNoScale = true
        innerOpts["style"] = style
        let pathData = iconStr.replacingOccurrences(of: "path://", with: "")
        return makePath(pathData, innerOpts, r, "center")
    }
}
