// Ported from zrender/src/animation/Animator.ts — keep in sync with upstream
//
// @module echarts/animation/Animator

import Foundation

// upstream: import Clip from './Clip';                            → Animation/Clip.swift
// upstream: import * as color from '../tool/color';              → Tool/color.swift
// upstream: import { eqNaN, extend, isArrayLike, isFunction, isGradientObject, isNumber,
//                    isString, keys, logError, map } from '../core/util';   → Core/util.swift
// upstream: import { ArrayLike, Dictionary } from '../core/types';          → Core/types.swift
// upstream: import easingFuncs, { AnimationEasing } from './easing';        → Animation/easing.swift
// upstream: import Animation from './Animation';                            → ZRender.swift (Animation stub)
// upstream: import { createCubicEasingFunc } from './cubicEasing';
//   PORT-TODO: animation/cubicEasing.ts not ported — named easings that miss `easingFuncs`
//   fall through to nil (same deferral as Clip.setEasing).
// upstream: import { isLinearGradient, isRadialGradient } from '../svg/helper';
//   PORT-TODO: svg/helper.ts not ported — modeled as local `.type` checks below.

// upstream: type NumberArray = ArrayLike<number>     → [Double]
// upstream: type InterpolatableType = string | number | NumberArray | NumberArray[];
//   Swift has no untagged union; the interpolatable value flows through opaquely as `Any?`
//   and the per-type dispatch uses the `valType` machinery (mirroring upstream's runtime
//   `isArrayLike`/`isNumber`/`isString` detection). Kept as a typealias for callers.
public typealias InterpolatableType = Any

/// upstream: `target[propName]` dynamic keyed read/write on `any`.
/// Swift has no dynamic member access on an arbitrary `T`, so the animation target conforms
/// to this protocol and `Track.step` / `Animator.whenWithKeys` / `saveTo` route keyed
/// get/set through it.
/// PORT-TODO: Element / style-bag / shape-bag will conform when the Element animate wiring
/// lands (PORT_STATUS §11a). Until a target conforms, `whenWithKeys` reads `nil` for every
/// initial value and builds no tracks (the animator is inert), which is the safe render-only
/// default.
public protocol AnimationTarget: AnyObject {
    func animationGet(_ key: String) -> Any?
    func animationSet(_ key: String, _ value: Any?)
}

// upstream: interface ParsedColorStop { color: number[], offset: number }
public struct ParsedColorStop {
    public var color: [Double]
    public var offset: Double
    public init(color: [Double], offset: Double) {
        self.color = color
        self.offset = offset
    }
}

// upstream: interface ParsedGradientObject (+ ParsedLinearGradientObject { x2, y2 }
//   / ParsedRadialGradientObject { r }). The TS subtype hierarchy is flattened into one
//   `final class` (reference type — `fillColorStops` mutates `.colorStops` in place); the
//   linear-only (x2/y2) and radial-only (r) fields coexist as optionals.
// PORT-TODO: confirm the flattened gradient parse against svg/helper once gradient tweening
//   is wired (this whole gradient path is currently dead — `util.isGradientObject` returns false).
public final class ParsedGradientObject {
    public var colorStops: [ParsedColorStop] = []
    public var x: Double = 0
    public var y: Double = 0
    public var global: Bool = false
    // ParsedLinearGradientObject
    public var x2: Double = 0
    public var y2: Double = 0
    // ParsedRadialGradientObject
    public var r: Double = 0
    public init() {}
}

// upstream: const arraySlice = Array.prototype.slice;  (Swift arrays are value types; a plain
//   assignment / `map { $0 }` already copies, so no shared slice helper is needed.)

fileprivate func interpolateNumber(_ p0: Double, _ p1: Double, _ percent: Double) -> Double {
    return (p1 - p0) * percent + p0
}

// out-param dropped, value-returning per CONVENTIONS §3.
fileprivate func interpolate1DArray(
    _ p0: [Double],
    _ p1: [Double],
    _ percent: Double
) -> [Double] {
    // TODO Handling different length TypedArray
    let len = p0.count
    var out = [Double](repeating: 0, count: len)
    for i in 0..<len {
        out[i] = interpolateNumber(p0[i], p1[i], percent)
    }
    return out
}

// out-param dropped, value-returning per CONVENTIONS §3.
fileprivate func interpolate2DArray(
    _ p0: [[Double]],
    _ p1: [[Double]],
    _ percent: Double
) -> [[Double]] {
    let len = p0.count
    // TODO differnt length on each item?
    let len2 = len != 0 ? p0[0].count : 0
    var out = [[Double]]()
    for i in 0..<len {
        var row = [Double](repeating: 0, count: len2)
        for j in 0..<len2 {
            row[j] = interpolateNumber(p0[i][j], p1[i][j], percent)
        }
        out.append(row)
    }
    return out
}

// out-param dropped, value-returning per CONVENTIONS §3. `sign` is upstream's `1 | -1`.
fileprivate func add1DArray(
    _ p0: [Double],
    _ p1: [Double],
    _ sign: Double
) -> [Double] {
    let len = p0.count
    var out = [Double](repeating: 0, count: len)
    for i in 0..<len {
        out[i] = p0[i] + p1[i] * sign
    }
    return out
}

// out-param dropped, value-returning per CONVENTIONS §3. `sign` is upstream's `1 | -1`.
fileprivate func add2DArray(
    _ p0: [[Double]],
    _ p1: [[Double]],
    _ sign: Double
) -> [[Double]] {
    let len = p0.count
    let len2 = len != 0 ? p0[0].count : 0
    var out = [[Double]]()
    for i in 0..<len {
        var row = [Double](repeating: 0, count: len2)
        for j in 0..<len2 {
            row[j] = p0[i][j] + p1[i][j] * sign
        }
        out.append(row)
    }
    return out
}

// upstream mutates the shorter `ParsedColorStop[]` in place. Since the parsed gradient is a
// `final class`, the two owning gradients are passed and the shorter one's `colorStops` is
// grown in place (faithful effect; the array-typed upstream signature is adapted).
fileprivate func fillColorStops(_ val0: ParsedGradientObject, _ val1: ParsedGradientObject) {
    let len0 = val0.colorStops.count
    let len1 = val1.colorStops.count

    let shorterArr = len0 > len1 ? val1 : val0
    let shorterLen = Swift.min(len0, len1)
    let last = shorterLen >= 1 ? shorterArr.colorStops[shorterLen - 1]
        : ParsedColorStop(color: [0, 0, 0, 0], offset: 0)
    var i = shorterLen
    while i < Swift.max(len0, len1) {
        // Use last color stop to fill the shorter array
        shorterArr.colorStops.append(ParsedColorStop(
            color: last.color,   // .slice() — Swift array value-copy
            offset: last.offset
        ))
        i += 1
    }
}
// arr0 is source array, arr1 is target array.
// Do some preprocess to avoid error happened when interpolating from arr0 to arr1
// out-param mutation dropped, value-returning per CONVENTIONS §3 (returns the adjusted arr0).
fileprivate func fillArray(
    _ val0: Any?,
    _ val1: Any?,
    _ arrDim: Int
) -> Any? {
    // TODO Handling different length TypedArray
    // upstream: `if (!arr0.push || !arr1.push) return;` — non-array values pass through.
    if !util.isArrayLike(val0) || !util.isArrayLike(val1) {
        return val0
    }
    if arrDim == 1 {
        var arr0 = asArray1D(val0)
        let arr1 = asArray1D(val1)
        let arr0Len = arr0.count
        let arr1Len = arr1.count
        if arr0Len != arr1Len {
            // FIXME Not work for TypedArray
            let isPreviousLarger = arr0Len > arr1Len
            if isPreviousLarger {
                // Cut the previous
                arr0 = Array(arr0[0..<arr1Len])
            }
            else {
                // Fill the previous
                for i in arr0Len..<arr1Len {
                    arr0.append(arr1[i])
                }
            }
        }
        // Handling NaN value
        for i in 0..<arr0.count {
            if arr0[i].isNaN {
                arr0[i] = arr1[i]
            }
        }
        return arr0
    }
    else {
        var arr0 = asArray2D(val0)
        let arr1 = asArray2D(val1)
        let arr0Len = arr0.count
        let arr1Len = arr1.count
        if arr0Len != arr1Len {
            let isPreviousLarger = arr0Len > arr1Len
            if isPreviousLarger {
                arr0 = Array(arr0[0..<arr1Len])
            }
            else {
                for i in arr0Len..<arr1Len {
                    arr0.append(arr1[i])   // arraySlice.call(arr1[i]) — Swift array value-copy
                }
            }
        }
        let len2 = arr0.count > 0 ? arr0[0].count : 0
        for i in 0..<arr0.count {
            for j in 0..<len2 {
                if arr0[i][j].isNaN {
                    arr0[i][j] = arr1[i][j]
                }
            }
        }
        return arr0
    }
}

public func cloneValue(_ value: InterpolatableType?) -> InterpolatableType? {
    if util.isArrayLike(value) {
        // upstream: deep one level for arrays-of-arrays, shallow slice otherwise. Swift arrays
        // are value types, so each concrete shape is copied on return.
        if let v2 = value as? [[Double]] {
            var ret: [[Double]] = []
            for i in 0..<v2.count {
                ret.append(v2[i])   // arraySlice.call(value[i])
            }
            return ret
        }
        if util.isArrayLike(firstElement(value)) {
            // PORT-TODO: a generic array-of-arrays that isn't [[Double]] (e.g. nested [Any])
            //   is value-copied shallowly; exact nested-clone fidelity unverified.
            if let vAny = value as? [Any] {
                var ret: [Any] = []
                for i in 0..<vAny.count {
                    ret.append(vAny[i])
                }
                return ret
            }
        }
        if let v1 = value as? [Double] {
            return v1   // arraySlice.call(value)
        }
        if let vAny = value as? [Any] {
            return vAny
        }
    }

    return value
}

fileprivate func rgba2String(_ rgba: [Double]) -> String {
    var rgba = rgba
    rgba[0] = floorOrZero(rgba[0])
    rgba[1] = floorOrZero(rgba[1])
    rgba[2] = floorOrZero(rgba[2])
    // upstream: rgba[3] = rgba[3] == null ? 1 : rgba[3];
    if rgba.count <= 3 {
        rgba.append(1)
    }

    // 'rgba(' + rgba.join(',') + ')'
    return "rgba(" + rgba.map { color.numToStr($0) }.joined(separator: ",") + ")"
}

fileprivate func guessArrayDim(_ value: Any?) -> Int {
    // isArrayLike(value && value[0]) ? 2 : 1
    return util.isArrayLike(firstElement(value)) ? VALUE_TYPE_2D_ARRAY : VALUE_TYPE_1D_ARRAY
}

fileprivate let VALUE_TYPE_NUMBER = 0
fileprivate let VALUE_TYPE_1D_ARRAY = 1
fileprivate let VALUE_TYPE_2D_ARRAY = 2
fileprivate let VALUE_TYPE_COLOR = 3
fileprivate let VALUE_TYPE_LINEAR_GRADIENT = 4
fileprivate let VALUE_TYPE_RADIAL_GRADIENT = 5
// Other value type that can only use discrete animation.
fileprivate let VALUE_TYPE_UNKOWN = 6

// upstream: type ValueType = 0 | 1 | 2 | 3 | 4 | 5 | 6;
fileprivate typealias ValueType = Int

// upstream: type Keyframe = { time, value, percent, rawValue, easing?, easingFunc?, additiveValue? }
//   A `final class` (reference type): keyframes are stored in an array and mutated through the
//   reference afterwards (`kf.percent = …`, `kf.additiveValue = …`) — CONVENTIONS §4.
fileprivate final class Keyframe {
    var time: Double
    var value: Any?
    var percent: Double
    // Raw value for discrete animation.
    var rawValue: Any?

    var easing: AnimationEasing?    // Raw easing
    var easingFunc: EasingFunc?
    var additiveValue: Any?

    init(time: Double, value: Any?, rawValue: Any?, percent: Double) {
        self.time = time
        self.value = value
        self.rawValue = rawValue
        self.percent = percent
    }
}

fileprivate func isGradientValueType(_ valType: ValueType) -> Bool {
    return valType == VALUE_TYPE_LINEAR_GRADIENT || valType == VALUE_TYPE_RADIAL_GRADIENT
}
fileprivate func isArrayValueType(_ valType: ValueType) -> Bool {
    return valType == VALUE_TYPE_1D_ARRAY || valType == VALUE_TYPE_2D_ARRAY
}

// upstream: let tmpRgba: number[] = [0, 0, 0, 0];
fileprivate var tmpRgba: [Double] = [0, 0, 0, 0]

/// upstream: class Track (module-private). Exposed via the public `AnimatorTrack` alias.
public final class Track {

    fileprivate var keyframes: [Keyframe] = []

    public var propName: String

    fileprivate var valType: ValueType = VALUE_TYPE_UNKOWN

    var discrete: Bool = false

    var _invalid: Bool = false

    private var _finished: Bool = false

    private var _needsSort: Bool = false

    private var _additiveTrack: Track?
    // Temporal storage for interpolated additive value.
    private var _additiveValue: Any?

    // Info for run
    /// Last frame
    private var _lastFr = 0
    /// Percent of last frame.
    private var _lastFrP: Double = 0

    public init(_ propName: String) {
        self.propName = propName
    }

    public func isFinished() -> Bool {
        return self._finished
    }

    public func setFinished() {
        self._finished = true
        // Also set additive track to finished.
        // Make sure the final value stopped on the latest track
        if let additiveTrack = self._additiveTrack {
            additiveTrack.setFinished()
        }
    }

    public func needsAnimate() -> Bool {
        return self.keyframes.count >= 1
    }

    fileprivate func getAdditiveTrack() -> Track? {
        return self._additiveTrack
    }

    @discardableResult
    fileprivate func addKeyframe(_ time: Double, _ rawValue: Any?, _ easing: AnimationEasing? = nil) -> Keyframe {
        self._needsSort = true

        let len = self.keyframes.count

        var discrete = false
        var valType: ValueType = VALUE_TYPE_UNKOWN
        var value: Any? = rawValue

        // Handling values only if it's possible to be interpolated.
        if util.isArrayLike(rawValue) {
            let arrayDim = guessArrayDim(rawValue)
            valType = arrayDim
            // Not a number array.
            if arrayDim == 1 && !util.isNumber(firstElement(rawValue))
                || arrayDim == 2 && !util.isNumber(firstElement(firstElement(rawValue))) {
                discrete = true
            }
        }
        else {
            if util.isNumber(rawValue) && !util.eqNaN(rawValue as! Double) {
                valType = VALUE_TYPE_NUMBER
            }
            else if util.isString(rawValue) {
                let rawStr = rawValue as! String
                if !(Double(rawStr) ?? Double.nan).isNaN {    // Can be string number like '2'
                    valType = VALUE_TYPE_NUMBER
                }
                else {
                    let colorArray = color.parse(rawStr)
                    if let colorArray = colorArray {
                        value = colorArray
                        valType = VALUE_TYPE_COLOR
                    }
                }
            }
            else if util.isGradientObject(rawValue) {
                // Parse the Gradient into a ParsedGradientObject (rgba color stops + geometry), so the
                // interpolation branch can tween it. `Gradient` is the concrete base class (the
                // GradientObject protocol isn't adopted — see util.isGradientObject).
                if let grad = rawValue as? Gradient {
                    let parsedGradient = ParsedGradientObject()
                    parsedGradient.colorStops = util.map(grad.colorStops) { colorStop, _ in
                        ParsedColorStop(
                            color: color.parse(colorStop.color) ?? [0, 0, 0, 0],
                            offset: colorStop.offset
                        )
                    }
                    parsedGradient.global = grad.global
                    if let lg = grad as? LinearGradient {
                        valType = VALUE_TYPE_LINEAR_GRADIENT
                        parsedGradient.x = lg.x; parsedGradient.y = lg.y
                        parsedGradient.x2 = lg.x2; parsedGradient.y2 = lg.y2
                    }
                    else if let rg = grad as? RadialGradient {
                        valType = VALUE_TYPE_RADIAL_GRADIENT
                        parsedGradient.x = rg.x; parsedGradient.y = rg.y; parsedGradient.r = rg.r
                    }
                    value = parsedGradient
                }
            }
        }

        if len == 0 {
            // Inference type from the first keyframe.
            self.valType = valType
        }
         // Not same value type or can't be interpolated.
        else if valType != self.valType || valType == VALUE_TYPE_UNKOWN {
            discrete = true
        }

        self.discrete = self.discrete || discrete

        let kf = Keyframe(
            time: time,
            value: value,
            rawValue: rawValue,
            percent: 0
        )
        if let easing = easing {
            // Save the raw easing name to be used in css animation output
            kf.easing = easing
            switch easing {
            case .function(let f):
                kf.easingFunc = f
            case .named(let name):
                // easingFuncs[easing] || createCubicEasingFunc(easing)
                kf.easingFunc = ZRenderKit.easing.easingFuncs[name]
                    ?? ZRenderKit.easing.createCubicEasingFunc(name)
            }
        }
        // Not check if value equal here.
        self.keyframes.append(kf)
        return kf
    }

    fileprivate func prepare(_ maxTime: Double, _ additiveTrack: Track? = nil) {
        if self._needsSort {
            // Sort keyframe as ascending
            self.keyframes.sort { a, b in
                a.time < b.time
            }
        }
        let kfs = self.keyframes

        let valType = self.valType
        let kfsLen = kfs.count
        let lastKf = kfs[kfsLen - 1]
        let isDiscrete = self.discrete
        let isArr = isArrayValueType(valType)
        let isGradient = isGradientValueType(valType)

        for i in 0..<kfsLen {
            let kf = kfs[i]
            let value = kf.value
            let lastValue = lastKf.value
            kf.percent = kf.time / maxTime
            if !isDiscrete {
                if isArr && i != kfsLen - 1 {
                    // Align array with target frame.
                    kf.value = fillArray(value, lastValue, valType)
                }
                else if isGradient {
                    if let v = value as? ParsedGradientObject, let lv = lastValue as? ParsedGradientObject {
                        fillColorStops(v, lv)
                    }
                }
            }
        }

        // Only apply additive animaiton on INTERPOLABLE SAME TYPE values.
        if !isDiscrete
            // TODO support gradient
            && valType != VALUE_TYPE_RADIAL_GRADIENT
            && additiveTrack != nil
            // If two track both will be animated and have same value format.
            && self.needsAnimate()
            && additiveTrack!.needsAnimate()
            && valType == additiveTrack!.valType
            && !additiveTrack!._finished {
            self._additiveTrack = additiveTrack

            let startValue = kfs[0].value
            // Calculate difference
            for i in 0..<kfsLen {
                if valType == VALUE_TYPE_NUMBER {
                    kfs[i].additiveValue = asNumber(kfs[i].value) - asNumber(startValue)
                }
                else if valType == VALUE_TYPE_COLOR {
                    kfs[i].additiveValue =
                        add1DArray(asArray1D(kfs[i].value), asArray1D(startValue), -1)
                }
                else if isArrayValueType(valType) {
                    kfs[i].additiveValue = valType == VALUE_TYPE_1D_ARRAY
                        ? add1DArray(asArray1D(kfs[i].value), asArray1D(startValue), -1)
                        : add2DArray(asArray2D(kfs[i].value), asArray2D(startValue), -1)
                }
            }
        }
    }

    public func step(_ target: Any, _ percent: Double) {
        if self._finished {   // Track may be set to finished.
            return
        }

        if let additiveTrack = self._additiveTrack, additiveTrack._finished {
            // Remove additive track if it's finished.
            self._additiveTrack = nil
        }
        let isAdditive = self._additiveTrack != nil
        // upstream: const valueKey = isAdditive ? 'additiveValue' : 'value';
        func valOf(_ kf: Keyframe) -> Any? { return isAdditive ? kf.additiveValue : kf.value }

        let valType = self.valType
        let keyframes = self.keyframes
        let kfsNum = keyframes.count
        let propName = self.propName
        let isValueColor = valType == VALUE_TYPE_COLOR
        // Find the range keyframes
        // kf1-----kf2---------current--------kf3
        // find kf2 and kf3 and do interpolation
        var frameIdx = 0
        let lastFrame = self._lastFr
        var frame: Keyframe?
        var nextFrame: Keyframe?
        if kfsNum == 1 {
            frame = keyframes[0]
            nextFrame = keyframes[0]
        }
        else {
            // In the easing function like elasticOut, percent may less than 0
            if percent < 0 {
                frameIdx = 0
            }
            else if percent < self._lastFrP {
                // Start from next key
                // PENDING start from lastFrame ?
                let start = Swift.min(lastFrame + 1, kfsNum - 1)
                frameIdx = start
                while frameIdx >= 0 {
                    if keyframes[frameIdx].percent <= percent {
                        break
                    }
                    frameIdx -= 1
                }
                frameIdx = Swift.min(frameIdx, kfsNum - 2)
            }
            else {
                frameIdx = lastFrame
                while frameIdx < kfsNum {
                    if keyframes[frameIdx].percent > percent {
                        break
                    }
                    frameIdx += 1
                }
                frameIdx = Swift.min(frameIdx - 1, kfsNum - 2)
            }

            nextFrame = safeIndex(keyframes, frameIdx + 1)
            frame = safeIndex(keyframes, frameIdx)
        }

        // Defensive coding.
        guard let frame = frame, let nextFrame = nextFrame else {
            return
        }

        self._lastFr = frameIdx
        self._lastFrP = percent

        let interval = nextFrame.percent - frame.percent
        var w = interval == 0 ? 1 : Swift.min((percent - frame.percent) / interval, 1)

        // Apply different easing of each keyframe.
        // Use easing specified in target frame.
        if let easingFunc = nextFrame.easingFunc {
            w = easingFunc(w)
        }

        // upstream seeds a scratch `targetArr` (= isAdditive ? _additiveValue : isValueColor ?
        //   tmpRgba : target[propName]) for the array/color interpolation out-param. Under §3
        //   value-returning interpolation this scratch is unneeded; each branch assigns the
        //   returned value to `_additiveValue` (additive) or to target[propName] directly.

        // PORT-TODO: see AnimationTarget — without a conforming target, keyed set/get no-op.
        let t = target as? AnimationTarget

        if self.discrete {
            // use raw value without parse in discrete animation.
            t?.animationSet(propName, w < 1 ? frame.rawValue : nextFrame.rawValue)
        }
        else if isArrayValueType(valType) {
            let out: Any = valType == VALUE_TYPE_1D_ARRAY
                ? interpolate1DArray(asArray1D(valOf(frame)), asArray1D(valOf(nextFrame)), w)
                : interpolate2DArray(asArray2D(valOf(frame)), asArray2D(valOf(nextFrame)), w)
            if isAdditive {
                self._additiveValue = out
            }
            else {
                t?.animationSet(propName, out)
            }
        }
        else if isGradientValueType(valType) {
            // PORT-TODO: gradient output is a plain dictionary mirroring the JS object literal;
            //   wire to a real LinearGradient/RadialGradient once gradient tweening lands.
            guard let val = valOf(frame) as? ParsedGradientObject,
                  let nextVal = valOf(nextFrame) as? ParsedGradientObject else {
                return
            }
            let isLinearGradient = valType == VALUE_TYPE_LINEAR_GRADIENT
            var output: [String: Any] = [
                "type": isLinearGradient ? "linear" : "radial",
                "x": interpolateNumber(val.x, nextVal.x, w),
                "y": interpolateNumber(val.y, nextVal.y, w),
                // TODO performance
                "colorStops": util.map(val.colorStops) { colorStop, idx -> [String: Any] in
                    let nextColorStop = nextVal.colorStops[idx]
                    return [
                        "offset": interpolateNumber(colorStop.offset, nextColorStop.offset, w),
                        "color": rgba2String(interpolate1DArray(
                            colorStop.color, nextColorStop.color, w
                        ))
                    ]
                },
                "global": nextVal.global
            ]
            if isLinearGradient {
                // Linear
                output["x2"] = interpolateNumber(val.x2, nextVal.x2, w)
                output["y2"] = interpolateNumber(val.y2, nextVal.y2, w)
            }
            else {
                // Radial
                output["r"] = interpolateNumber(val.r, nextVal.r, w)
            }
            t?.animationSet(propName, output)
        }
        else if isValueColor {
            tmpRgba = interpolate1DArray(asArray1D(valOf(frame)), asArray1D(valOf(nextFrame)), w)
            if isAdditive {
                self._additiveValue = tmpRgba
            }
            else {  // Convert to string later:)
                t?.animationSet(propName, rgba2String(tmpRgba))
            }
        }
        else {
            let value = interpolateNumber(asNumber(valOf(frame)), asNumber(valOf(nextFrame)), w)
            if isAdditive {
                self._additiveValue = value
            }
            else {
                t?.animationSet(propName, value)
            }
        }

        // Add additive to target
        if isAdditive {
            self._addToTarget(target)
        }
    }

    private func _addToTarget(_ target: Any) {
        let valType = self.valType
        let propName = self.propName
        let additiveValue = self._additiveValue
        let t = target as? AnimationTarget

        if valType == VALUE_TYPE_NUMBER {
            // Add a difference value based on the change of previous frame.
            t?.animationSet(propName, asNumber(t?.animationGet(propName)) + asNumber(additiveValue))
        }
        else if valType == VALUE_TYPE_COLOR {
            // TODO reduce unnecessary parse
            tmpRgba = color.parse(t?.animationGet(propName) as? String ?? "") ?? [0, 0, 0, 0]
            tmpRgba = add1DArray(tmpRgba, asArray1D(additiveValue), 1)
            t?.animationSet(propName, rgba2String(tmpRgba))
        }
        else if valType == VALUE_TYPE_1D_ARRAY {
            let cur = asArray1D(t?.animationGet(propName))
            t?.animationSet(propName, add1DArray(cur, asArray1D(additiveValue), 1))
        }
        else if valType == VALUE_TYPE_2D_ARRAY {
            let cur = asArray2D(t?.animationGet(propName))
            t?.animationSet(propName, add2DArray(cur, asArray2D(additiveValue), 1))
        }
    }
}

// upstream: type DoneCallback = () => void;
public typealias DoneCallback = () -> Void
// upstream: type AbortCallback = () => void;
public typealias AbortCallback = () -> Void
// upstream: export type OnframeCallback<T> = (target: T, percent: number) => void;
public typealias OnframeCallback<T> = (_ target: T, _ percent: Double) -> Void

// upstream: export type AnimationPropGetter<T> = (target: T, key: string) => InterpolatableType;
public typealias AnimationPropGetter<T> = (_ target: T, _ key: String) -> InterpolatableType
// upstream: export type AnimationPropSetter<T> = (target: T, key: string, value: InterpolatableType) => void;
public typealias AnimationPropSetter<T> = (_ target: T, _ key: String, _ value: InterpolatableType) -> Void

public final class Animator<T> {

    // upstream: animation?: Animation  (the Phase-3 Animation type-surface stub lives in ZRender.swift)
    public var animation: Animation?

    public var targetName: String?

    public var scope: String?

    public var __fromStateTransition: String?

    private var _tracks: Dictionary<Track> = [:]
    private var _trackKeys: [String] = []

    private var _target: T

    private var _loop: Bool
    private var _delay: Double = 0
    private var _maxTime: Double = 0

    /// If force run regardless of empty tracks when duration is set.
    private var _force: Bool = false

    /// If animator is paused
    private var _paused: Bool = false
    // 0: Not started
    // 1: Invoked started
    // 2: Has been run for at least one frame.
    private var _started: Double = 0

    /// If allow discrete animation
    private var _allowDiscrete: Bool = false

    private var _additiveAnimators: [Animator<Any>]?

    private var _doneCbs: [DoneCallback]?
    private var _onframeCbs: [OnframeCallback<T>]?

    private var _abortedCbs: [AbortCallback]?

    private var _clip: Clip? = nil

    public init(
        _ target: T,
        _ loop: Bool,
        _ allowDiscreteAnimation: Bool? = nil,  // If doing discrete animation on the values can't be interpolated
        _ additiveTo: [Animator<Any>]? = nil
    ) {
        self._target = target
        self._loop = loop
        if loop && additiveTo != nil {
            util.logError("Can' use additive animation on looped animation.")
            // upstream `return;` from a constructor leaves the remaining fields at their defaults.
            self._allowDiscrete = allowDiscreteAnimation ?? false
            return
        }
        self._additiveAnimators = additiveTo

        self._allowDiscrete = allowDiscreteAnimation ?? false
    }

    public func getMaxTime() -> Double {
        return self._maxTime
    }

    public func getDelay() -> Double {
        return self._delay
    }

    public func getLoop() -> Bool {
        return self._loop
    }

    public func getTarget() -> T {
        return self._target
    }

    /// Target can be changed during animation
    /// For example if style is changed during state change.
    /// We need to change target to the new style object.
    public func changeTarget(_ target: T) {
        self._target = target
    }

    /// Set Animation keyframe
    /// - time: time of keyframe in ms
    /// - props: key-value props of keyframe.
    @discardableResult
    public func when(_ time: Double, _ props: Dictionary<Any>, _ easing: AnimationEasing? = nil) -> Animator<T> {
        return self.whenWithKeys(time, props, util.keys(props), easing)
    }

    // Fast path for add keyframes of aniamteTo
    @discardableResult
    public func whenWithKeys(_ time: Double, _ props: Dictionary<Any>, _ propNames: [String], _ easing: AnimationEasing? = nil) -> Animator<T> {
        for i in 0..<propNames.count {
            let propName = propNames[i]

            var track = self._tracks[propName]
            if track == nil {
                track = Track(propName)
                self._tracks[propName] = track

                var initialValue: Any?
                let additiveTrack = self._getAdditiveTrack(propName)
                if let additiveTrack = additiveTrack {
                    let addtiveTrackKfs = additiveTrack.keyframes
                    let lastFinalKf = addtiveTrackKfs.count > 0 ? addtiveTrackKfs[addtiveTrackKfs.count - 1] : nil
                    // Use the last state of additived animator.
                    initialValue = lastFinalKf?.value
                    if additiveTrack.valType == VALUE_TYPE_COLOR, let iv = initialValue {
                        // Convert to rgba string
                        initialValue = rgba2String(asArray1D(iv))
                    }
                }
                else {
                    initialValue = (self._target as? AnimationTarget)?.animationGet(propName)
                }
                // Invalid value
                if initialValue == nil {
                    // zrLog('Invalid property ' + propName);
                    continue
                }
                // If time is <= 0
                //  Then props is given initialize value
                //  Note: initial percent can be negative, which means the initial value is before the animation start.
                // Else
                //  Initialize value from current prop value
                if time > 0 {
                    track!.addKeyframe(0, cloneValue(initialValue), easing)
                }

                self._trackKeys.append(propName)
            }
            track!.addKeyframe(time, cloneValue(props[propName]), easing)
        }
        self._maxTime = Swift.max(self._maxTime, time)
        return self
    }

    public func pause() {
        self._clip?.pause()
        self._paused = true
    }

    public func resume() {
        self._clip?.resume()
        self._paused = false
    }

    public func isPaused() -> Bool {
        return self._paused
    }

    /// Set duration of animator.
    /// Will run this duration regardless the track max time or if trackes exits.
    @discardableResult
    public func duration(_ duration: Double) -> Animator<T> {
        self._maxTime = duration
        self._force = true
        return self
    }

    private func _doneCallback() {
        self._setTracksFinished()
        // Clear clip
        self._clip = nil

        if let doneList = self._doneCbs {
            let len = doneList.count
            for i in 0..<len {
                doneList[i]()
            }
        }
    }
    private func _abortedCallback() {
        self._setTracksFinished()

        let animation = self.animation
        let abortedList = self._abortedCbs

        if let animation = animation, let clip = self._clip {
            animation.removeClip(clip)
        }
        self._clip = nil

        if let abortedList = abortedList {
            for i in 0..<abortedList.count {
                abortedList[i]()
            }
        }
    }
    private func _setTracksFinished() {
        let tracks = self._tracks
        let tracksKeys = self._trackKeys
        for i in 0..<tracksKeys.count {
            tracks[tracksKeys[i]]?.setFinished()
        }
    }

    private func _getAdditiveTrack(_ trackName: String) -> Track? {
        var additiveTrack: Track?
        let additiveAnimators = self._additiveAnimators
        if let additiveAnimators = additiveAnimators {
            for i in 0..<additiveAnimators.count {
                let track = additiveAnimators[i].getTrack(trackName)
                if let track = track {
                    // Use the track of latest animator.
                    additiveTrack = track
                }
            }
        }
        return additiveTrack
    }

    /// Start the animation
    @discardableResult
    public func start(_ easing: AnimationEasing? = nil) -> Animator<T> {
        if self._started > 0 {
            return self
        }
        self._started = 1

        // upstream `const self = this` — Swift closures capture `self`; use [weak self] to break
        //   the animator → _clip → onframe → self retain cycle (CONVENTIONS §8). When the owner
        //   drops the animator, the clip's callbacks no-op (the clip is also released on stop/done).

        var tracks: [Track] = []
        let maxTime = self._maxTime
        for i in 0..<self._trackKeys.count {
            let propName = self._trackKeys[i]
            let track = self._tracks[propName]!
            let additiveTrack = self._getAdditiveTrack(propName)
            let kfs = track.keyframes
            let kfsNum = kfs.count
            track.prepare(maxTime, additiveTrack)
            if track.needsAnimate() {
                // Set value directly if discrete animation is not allowed.
                if !self._allowDiscrete && track.discrete {
                    let lastKf = kfsNum > 0 ? kfs[kfsNum - 1] : nil
                    // Set final value.
                    if let lastKf = lastKf {
                        // use raw value without parse.
                        (self._target as? AnimationTarget)?.animationSet(track.propName, lastKf.rawValue)
                    }
                    track.setFinished()
                }
                else {
                    tracks.append(track)
                }
            }
        }
        // Add during callback on the last clip
        if tracks.count > 0 || self._force {
            let clip = Clip(ClipProps(
                life: maxTime,
                delay: self._delay,
                loop: self._loop,
                onframe: { [weak self] percent in
                    guard let self = self else { return }
                    self._started = 2
                    // Remove additived animator if it's finished.
                    // For the purpose of memory effeciency.
                    let additiveAnimators = self._additiveAnimators
                    if let additiveAnimators = additiveAnimators {
                        var stillHasAdditiveAnimator = false
                        for i in 0..<additiveAnimators.count {
                            if additiveAnimators[i]._clip != nil {
                                stillHasAdditiveAnimator = true
                                break
                            }
                        }
                        if !stillHasAdditiveAnimator {
                            self._additiveAnimators = nil
                        }
                    }

                    for i in 0..<tracks.count {
                        // NOTE: don't cache target outside.
                        // Because target may be changed.
                        tracks[i].step(self._target, percent)
                    }

                    let onframeList = self._onframeCbs
                    if let onframeList = onframeList {
                        for i in 0..<onframeList.count {
                            onframeList[i](self._target, percent)
                        }
                    }
                },
                ondestroy: { [weak self] in
                    self?._doneCallback()
                }
            ))
            self._clip = clip

            if let animation = self.animation {
                animation.addClip(clip)
            }

            if let easing = easing {
                clip.setEasing(easing)
            }
        }
        else {
            // This optimization will help the case that in the upper application
            // the view may be refreshed frequently, where animation will be
            // called repeatly but nothing changed.
            self._doneCallback()
        }

        return self
    }
    /// Stop animation
    /// - forwardToLast: If move to last frame before stop
    public func stop(_ forwardToLast: Bool? = nil) {
        guard let clip = self._clip else {
            return
        }
        if forwardToLast ?? false {
            // Move to last frame before stop
            clip.onframe(1)
        }

        self._abortedCallback()
    }
    /// Set when animation delay starts
    /// - time: 单位ms
    @discardableResult
    public func delay(_ time: Double) -> Animator<T> {
        self._delay = time
        return self
    }
    /// 添加动画每一帧的回调函数
    @discardableResult
    public func during(_ cb: OnframeCallback<T>?) -> Animator<T> {
        if let cb = cb {
            if self._onframeCbs == nil {
                self._onframeCbs = []
            }
            self._onframeCbs!.append(cb)
        }
        return self
    }
    /// Add callback for animation end
    @discardableResult
    public func done(_ cb: DoneCallback?) -> Animator<T> {
        if let cb = cb {
            if self._doneCbs == nil {
                self._doneCbs = []
            }
            self._doneCbs!.append(cb)
        }
        return self
    }

    @discardableResult
    public func aborted(_ cb: AbortCallback?) -> Animator<T> {
        if let cb = cb {
            if self._abortedCbs == nil {
                self._abortedCbs = []
            }
            self._abortedCbs!.append(cb)
        }
        return self
    }

    public func getClip() -> Clip? {
        return self._clip
    }

    public func getTrack(_ propName: String) -> Track? {
        return self._tracks[propName]
    }

    public func getTracks() -> [Track] {
        return util.map(self._trackKeys) { key, _ in self._tracks[key]! }
    }

    /// Return true if animator is not available anymore.
    @discardableResult
    public func stopTracks(_ propNames: [String], _ forwardToLast: Bool? = nil) -> Bool {
        if propNames.count == 0 || self._clip == nil {
            return true
        }
        let tracks = self._tracks
        let tracksKeys = self._trackKeys

        for i in 0..<propNames.count {
            let track = tracks[propNames[i]]
            if let track = track, !track.isFinished() {
                if forwardToLast ?? false {
                    track.step(self._target, 1)
                }
                // If the track has not been run for at least one frame.
                // The property may be stayed at the final state. when setToFinal is set true.
                // For example:
                // Animate x from 0 to 100, then animate to 150 immediately.
                // We want the x is translated from 0 to 150, not 100 to 150.
                else if self._started == 1 {
                    track.step(self._target, 0)
                }
                // Set track to finished
                track.setFinished()
            }
        }
        var allAborted = true
        for i in 0..<tracksKeys.count {
            if !(tracks[tracksKeys[i]]?.isFinished() ?? true) {
                allAborted = false
                break
            }
        }
        // Remove clip if all tracks has been aborted.
        if allAborted {
            self._abortedCallback()
        }

        return allAborted
    }

    /// Save values of final state to target.
    /// It is mainly used in state mangement. When state is switching during animation.
    /// We need to save final state of animation to the normal state. Not interpolated value.
    ///
    /// - target
    /// - trackKeys
    /// - firstOrLast: If save first frame or last frame
    public func saveTo(
        _ target: T?,
        _ trackKeys: [String]? = nil,
        _ firstOrLast: Bool? = nil
    ) {
        guard let target = target else {  // DO nothing if target is not given.
            return
        }

        let trackKeys = trackKeys ?? self._trackKeys

        for i in 0..<trackKeys.count {
            let propName = trackKeys[i]
            let track = self._tracks[propName]
            if track == nil || track!.isFinished() {   // Ignore finished track.
                continue
            }
            let kfs = track!.keyframes
            let kf = kfs[(firstOrLast ?? false) ? 0 : kfs.count - 1]
            // TODO CLONE?
            // Use raw value without parse.
            (target as? AnimationTarget)?.animationSet(propName, cloneValue(kf.rawValue))
        }
    }

    // Change final value after animator has been started.
    // NOTE: Be careful to use it.
    public func __changeFinalValue(_ finalProps: Dictionary<Any>, _ trackKeys: [String]? = nil) {
        let trackKeys = trackKeys ?? util.keys(finalProps)

        for i in 0..<trackKeys.count {
            let propName = trackKeys[i]

            let track = self._tracks[propName]
            if track == nil {
                continue
            }

            if track!.keyframes.count > 1 {
                // Remove the original last kf and add again.
                let lastKf = track!.keyframes.removeLast()

                track!.addKeyframe(lastKf.time, finalProps[propName])
                // Prepare again.
                track!.prepare(self._maxTime, track!.getAdditiveTrack())
            }
        }
    }
}

// upstream: export type AnimatorTrack = Track;
public typealias AnimatorTrack = Track

// ---------------------------------------------------------------------------------------
// Helpers backing the dynamic `any`/`unknown` value handling and JS built-ins that have no
// direct Swift equivalent. These reproduce the (narrow) semantics this file exercises.
// ---------------------------------------------------------------------------------------

/// `Math.floor(x) || 0` — JS-falsy fallback: 0 when floor is 0 or NaN.
fileprivate func floorOrZero(_ x: Double) -> Double {
    let f = floor(x)
    return (f == 0 || f.isNaN) ? 0 : f
}

/// `value[0]` on an array-like `any` (nil when empty / not array-like).
fileprivate func firstElement(_ value: Any?) -> Any? {
    if let arr = value as? [Any] {
        return arr.first ?? nil
    }
    return nil
}

/// Out-of-bounds → nil (mirrors JS `array[i]` returning `undefined`).
fileprivate func safeIndex<E>(_ array: [E], _ index: Int) -> E? {
    if index < 0 || index >= array.count {
        return nil
    }
    return array[index]
}

/// `value as number` — Double passthrough; a string-number coerces like JS unary `+`.
fileprivate func asNumber(_ v: Any?) -> Double {
    if let d = v as? Double {
        return d
    }
    if let s = v as? String {
        // PORT-TODO: not a complete ECMAScript ToNumber (subset matching color/number tweens).
        return Double(s) ?? Double.nan
    }
    return Double.nan
}

/// `value as NumberArray` — [Double] passthrough, else best-effort element coercion.
fileprivate func asArray1D(_ v: Any?) -> [Double] {
    if let a = v as? [Double] {
        return a
    }
    if let a = v as? [Any] {
        return a.map { ($0 as? Double) ?? Double.nan }
    }
    return []
}

/// `value as NumberArray[]` — [[Double]] passthrough, else best-effort element coercion.
fileprivate func asArray2D(_ v: Any?) -> [[Double]] {
    if let a = v as? [[Double]] {
        return a
    }
    if let a = v as? [Any] {
        return a.map { asArray1D($0) }
    }
    return []
}

// PORT-TODO: svg/helper.ts not ported — upstream `isLinearGradient`/`isRadialGradient` test
//   `gradient.type === 'linear'` / `=== 'radial'`; replicated as local `.type` checks.
fileprivate func isLinearGradient(_ g: GradientObject) -> Bool {
    return g.type == "linear"
}
fileprivate func isRadialGradient(_ g: GradientObject) -> Bool {
    return g.type == "radial"
}
