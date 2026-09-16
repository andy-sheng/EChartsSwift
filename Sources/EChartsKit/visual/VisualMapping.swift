// Ported from echarts/src/visual/VisualMapping.ts — keep in sync with upstream

import Foundation
import ZRenderKit
// import * as zrUtil from 'zrender/src/core/util';   -> ZRenderKit `util`
// import * as zrColor from 'zrender/src/tool/color';  -> ZRenderKit `color`
// import {linearMap} from '../util/number';           -> EChartsKit `number.linearMap`
// import { AllPropTypes, Dictionary } from 'zrender/src/core/types';  -> Dictionary = [String: T]
// import { ColorString, BuiltinVisualProperty, VisualOptionPiecewise, VisualOptionUnit, ParsedValue }
//     from '../util/types';  -> EChartsKit util/types.swift
// import { warn } from '../util/log';                 -> EChartsKit `log.warn`

// const each = zrUtil.each;      -> util.each (array form); dict iteration is spelled inline
// const isObject = zrUtil.isObject;  -> util.isObject

private let CATEGORY_DEFAULT_VISUAL_INDEX: Double = -1

// Type of raw value
// upstream: type RawValue = ParsedValue;
typealias RawValue = ParsedValue                 // Any
// Type of mapping visual value
// upstream: type VisualValue = AllPropTypes<VisualOptionUnit>;
typealias VisualValue = Any                      // AllPropTypes<VisualOptionUnit>
// Type of value after normalized. 0 - 1
// upstream: type NormalizedValue = number;
typealias NormalizedValue = Double

// upstream: type MappingMethod = 'linear' | 'piecewise' | 'category' | 'fixed';
public typealias MappingMethod = String          // 'linear' | 'piecewise' | 'category' | 'fixed'

// May include liftZ. which is not provided to developers.

// upstream: interface Normalizer { (this: VisualMapping, value?: RawValue): NormalizedValue }
//   The `this` binding is modeled as an explicit first parameter.
typealias Normalizer = (VisualMapping, RawValue?) -> NormalizedValue
// upstream: interface ColorMapper {
//     (this, value: RawValue | NormalizedValue, isNormalized?: boolean, out?: number[]): ColorString | number[]
// }
// DEFERRED usage helper. Return is ColorString | number[] modeled as `Any`.
public typealias ColorMapper = (_ value: Any, _ isNormalized: Bool, _ out: [Double]?) -> Any
// upstream: interface DoMap { (this, normalzied?, value?): VisualValue }
typealias DoMap = (VisualMapping, NormalizedValue, RawValue?) -> VisualValue?
// upstream: interface VisualValueGetter { (key: string): VisualValue }
public typealias VisualValueGetter = (String) -> Any?
// upstream: interface VisualValueSetter { (key: string, value: VisualValue): void }
public typealias VisualValueSetter = (String, Any?) -> Void

// upstream: interface VisualHandler { applyVisual; _normalizedToVisual { linear/category/piecewise/fixed }; getColorMapper? }
final class VisualHandler {
    let applyVisual: (VisualMapping, RawValue, VisualValueGetter, VisualValueSetter) -> Void
    let _normalizedToVisual: NormalizedToVisual
    /**
     * Get color mapping for the outside usage.
     * Currently only used in `color` visual.
     *
     * The last parameter out is cached color array.
     */
    let getColorMapper: ((VisualMapping) -> ColorMapper)?

    init(
        applyVisual: @escaping (VisualMapping, RawValue, VisualValueGetter, VisualValueSetter) -> Void,
        _normalizedToVisual: NormalizedToVisual,
        getColorMapper: ((VisualMapping) -> ColorMapper)? = nil
    ) {
        self.applyVisual = applyVisual
        self._normalizedToVisual = _normalizedToVisual
        self.getColorMapper = getColorMapper
    }
}

// upstream: the `_normalizedToVisual` object with one entry per MappingMethod. Some are `null`.
struct NormalizedToVisual {
    let linear: DoMap?
    let category: DoMap?
    let piecewise: DoMap?
    let fixed: DoMap?

    // upstream indexes it as `_normalizedToVisual[mappingMethod]`.
    func get(_ method: MappingMethod) -> DoMap? {
        switch method {
        case "linear": return linear
        case "category": return category
        case "piecewise": return piecewise
        case "fixed": return fixed
        default: return nil
        }
    }
}

// upstream: interface VisualMappingPiece (also extended by VisualMappingInnerPiece which adds originIndex).
//   Modeled as a value struct (data bag, no identity — CONVENTIONS §4); `originIndex` folded in.
public struct VisualMappingPiece {
    public var index: Double?

    public var value: Any?               // number | string
    public var interval: [Double]?       // [number, number]
    public var close: [Double]?          // [0 | 1, 0 | 1]

    public var text: String?

    // upstream: visual?: VisualOptionPiecewise (VisualOptionUnit). Indexed dynamically by the
    //   visual type string (`piece.visual[this.type]`), so kept as a `[String: Any]` bag.
    public var visual: [String: Any]?

    // upstream VisualMappingInnerPiece: originIndex: number
    public var originIndex: Double = 0

    public init() {}
}

// upstream: export interface VisualMappingOption { type; mappingMethod; dataExtent; pieceList; categories; loop; visual }
public struct VisualMappingOption {
    public var type: BuiltinVisualProperty?

    public var mappingMethod: MappingMethod?

    /**
     * required when mappingMethod is 'linear'
     */
    public var dataExtent: [Double]?    // [number, number]
    /**
     *  required when mappingMethod is 'piecewise'.
     *  Visual for only each piece can be specified
     */
    public var pieceList: [VisualMappingPiece]?
    /**
     * required when mappingMethod is 'category'. If no option.categories, categories is set as [0, 1, 2, ...].
     */
    public var categories: [Any]?       // (string | number)[]
    /**
     * Whether loop mapping when mappingMethod is 'category'.
     * @default false
     */
    public var loop: Bool?
    /**
     * Visual data
     * when mappingMethod is 'category', visual data can be array or object
     * (like: {cate1: '#222', none: '#fff'})
     * or primary types (which represents default category visual), otherwise visual
     * can be array or primary (which will be normalized to array).
     */
    // upstream: VisualValue[] | Dictionary<VisualValue> | VisualValue
    public var visual: Any?

    public init() {}

    /**
     * Bridge the dynamic `[String: Any]` mapping-option bag that the (still-deferred) visualMap /
     * treemap / sankey consumers build. Numeric fields are read through the Int|Double coercion
     * helper (never a bare `as? Double`), per the port's INT-vs-DOUBLE trap.
     */
    public init(_ bag: [String: Any]) {
        self.type = bag["type"] as? String
        self.mappingMethod = bag["mappingMethod"] as? String
        self.dataExtent = coerceDoubleArray(bag["dataExtent"])
        self.categories = bag["categories"] as? [Any]
        self.loop = bag["loop"] as? Bool
        self.visual = bag["visual"]
        if let rawPieces = bag["pieceList"] as? [[String: Any]] {
            self.pieceList = rawPieces.map { d -> VisualMappingPiece in
                var p = VisualMappingPiece()
                p.value = d["value"]
                p.interval = coerceDoubleArray(d["interval"])
                p.close = coerceDoubleArray(d["close"])
                p.text = d["text"] as? String
                p.visual = d["visual"] as? [String: Any]
                if let idx = d["index"] { p.index = asDouble(idx) }
                return p
            }
        }
    }
}

// upstream: interface VisualMappingInnerOption extends VisualMappingOption. Modeled as a `final class`
//   (reference) because the free preprocess/normalize functions mutate it in place and the mutations
//   must propagate through `this.option` (CONVENTIONS §3/§4).
final class VisualMappingInnerOption {
    var type: BuiltinVisualProperty?
    var mappingMethod: MappingMethod?
    var dataExtent: [Double]?
    var pieceList: [VisualMappingPiece]?
    var categories: [Any]?
    var loop: Bool?

    // Have converted primary value to array (once normalized). Holds the raw input first, then the
    // normalized `[Any?]` array (JS arrays may be sparse — holes are `nil`).
    var visual: Any?

    var hasSpecialVisual: Bool = false
    /**
     * Map to get category index
     */
    // upstream: categoryMap: Dictionary<number>  (JS object keys are strings)
    var categoryMap: [String: Double] = [:]
    /**
     * Cached parsed rgba array from string to avoid parse every time.
     */
    var parsedVisual: [[Double]] = []

    // JS stores the CATEGORY_DEFAULT_VISUAL_INDEX (-1) default as the `arr[-1]` object
    //   property on the visual array. Swift arrays have no negative index, so it is held separately.
    var categoryDefaultVisual: Any?

    // upstream: `this.option = zrUtil.clone(option)`. Deep-copy the input option's fields (structs and
    //   Swift arrays/dicts copy by value; the input is never mutated).
    init(cloning option: VisualMappingOption) {
        self.type = option.type
        self.mappingMethod = option.mappingMethod
        self.dataExtent = option.dataExtent
        self.pieceList = option.pieceList
        self.categories = option.categories
        self.loop = option.loop
        self.visual = option.visual
    }
}

final class VisualMapping {

    var option: VisualMappingInnerOption

    var type: BuiltinVisualProperty

    var mappingMethod: MappingMethod

    // upstream stores the (bound) handler functions on the instance; the `this` first parameter is
    // supplied by the wrapper closures below.
    var applyVisual: (RawValue, VisualValueGetter, VisualValueSetter) -> Void = { _, _, _ in }

    var getColorMapper: (() -> ColorMapper)?

    var _normalizeData: (RawValue?) -> NormalizedValue = { _ in 0 }

    var _normalizedToVisual: (NormalizedValue, RawValue?) -> VisualValue? = { _, _ in nil }

    init(_ option: VisualMappingOption) {
        // upstream force-treats type/mappingMethod as defined (the class fields are non-optional).
        let mappingMethod: MappingMethod = option.mappingMethod!
        let visualType: BuiltinVisualProperty = option.type!

        let thisOption = VisualMappingInnerOption(cloning: option)
        self.option = thisOption

        self.type = visualType
        self.mappingMethod = mappingMethod

        let visualHandler = VisualMapping.visualHandlers[visualType]!

        // All stored properties are initialized above; bind the handler wrappers capturing self.
        // upstream: this._normalizeData = normalizers[mappingMethod];
        self._normalizeData = { [unowned self] value in normalizers[mappingMethod]!(self, value) }

        // upstream: this.applyVisual = visualHandler.applyVisual;
        self.applyVisual = { [unowned self] value, getter, setter in
            visualHandler.applyVisual(self, value, getter, setter)
        }

        // upstream: this.getColorMapper = visualHandler.getColorMapper;
        if let gcm = visualHandler.getColorMapper {
            self.getColorMapper = { [unowned self] in gcm(self) }
        }

        // upstream: this._normalizedToVisual = visualHandler._normalizedToVisual[mappingMethod];
        let doMap = visualHandler._normalizedToVisual.get(mappingMethod)
        self._normalizedToVisual = { [unowned self] normalized, value in doMap?(self, normalized, value) }

        if mappingMethod == "piecewise" {
            normalizeVisualRange(thisOption)
            preprocessForPiecewise(thisOption)
        }
        else if mappingMethod == "category" {
            thisOption.categories != nil
                ? preprocessForSpecifiedCategory(thisOption)
                // categories is ordinal when thisOption.categories not specified,
                // which need no more preprocess except normalize visual.
                : normalizeVisualRange(thisOption, true)
        }
        else { // mappingMethod === 'linear' or 'fixed'
            util.assert(mappingMethod != "linear" || thisOption.dataExtent != nil)
            normalizeVisualRange(thisOption)
        }
    }

    func mapValueToVisual(_ value: RawValue) -> VisualValue? {
        let normalized = self._normalizeData(value)
        return self._normalizedToVisual(normalized, value)
    }

    func getNormalizer() -> (RawValue?) -> NormalizedValue {
        // upstream: return zrUtil.bind(this._normalizeData, this);
        return self._normalizeData
    }

    static let visualHandlers: [BuiltinVisualProperty: VisualHandler] = [
        "color": VisualHandler(
            applyVisual: makeApplyVisual("color"),
            _normalizedToVisual: NormalizedToVisual(
                linear: { mapping, normalized, _ in
                    color.stringify(
                        color.fastLerp(normalized, mapping.option.parsedVisual) ?? [],
                        "rgba"
                    )
                },
                category: doMapCategory,
                piecewise: { mapping, normalized, value in
                    var result = getSpecifiedVisual(mapping, asDouble(value))
                    if result == nil {
                        result = color.stringify(
                            color.fastLerp(normalized, mapping.option.parsedVisual) ?? [],
                            "rgba"
                        )
                    }
                    return result
                },
                fixed: doMapFixed
            ),
            getColorMapper: { (mapping: VisualMapping) -> ColorMapper in
                let thisOption = mapping.option

                if thisOption.mappingMethod == "category" {
                    return { (value: Any, isNormalized: Bool, _ out: [Double]?) -> Any in
                        var value: Any = value
                        if !isNormalized { value = mapping._normalizeData(value) }
                        return doMapCategory(mapping, asDouble(value), nil) as Any
                    }
                }
                else {
                    return { (value: Any, isNormalized: Bool, out: [Double]?) -> Any in
                        // If output rgb array
                        // which will be much faster and useful in pixel manipulation
                        let returnRGBArray = out != nil
                        let v: Double = !isNormalized ? mapping._normalizeData(value) : asDouble(value)
                        let res = color.fastLerp(v, thisOption.parsedVisual, out)
                        return returnRGBArray ? (res as Any) : (color.stringify(res ?? [], "rgba") as Any)
                    }
                }
            }
        ),

        "colorHue": makePartialColorVisualHandler { (col: VisualValue?, value: Double) -> VisualValue? in
            guard let s = col as? String else { return nil }
            return color.modifyHSL(s, .number(value))
        },

        "colorSaturation": makePartialColorVisualHandler { (col: VisualValue?, value: Double) -> VisualValue? in
            guard let s = col as? String else { return nil }
            return color.modifyHSL(s, nil, .number(value))
        },

        "colorLightness": makePartialColorVisualHandler { (col: VisualValue?, value: Double) -> VisualValue? in
            guard let s = col as? String else { return nil }
            return color.modifyHSL(s, nil, nil, .number(value))
        },

        "colorAlpha": makePartialColorVisualHandler { (col: VisualValue?, value: Double) -> VisualValue? in
            guard let s = col as? String else { return nil }
            return color.modifyAlpha(s, value)
        },

        "decal": VisualHandler(
            applyVisual: makeApplyVisual("decal"),
            _normalizedToVisual: NormalizedToVisual(
                linear: nil,
                category: doMapCategory,
                piecewise: nil,
                fixed: nil
            )
        ),

        "opacity": VisualHandler(
            applyVisual: makeApplyVisual("opacity"),
            _normalizedToVisual: createNormalizedToNumericVisual([0, 1])
        ),

        "liftZ": VisualHandler(
            applyVisual: makeApplyVisual("liftZ"),
            _normalizedToVisual: NormalizedToVisual(
                linear: doMapFixed,
                category: doMapFixed,
                piecewise: doMapFixed,
                fixed: doMapFixed
            )
        ),

        "symbol": VisualHandler(
            applyVisual: { mapping, value, _, setter in
                let symbolCfg = mapping.mapValueToVisual(value)
                setter("symbol", symbolCfg)   // as string
            },
            _normalizedToVisual: NormalizedToVisual(
                linear: doMapToArray,
                category: doMapCategory,
                piecewise: { mapping, normalized, value in
                    var result = getSpecifiedVisual(mapping, asDouble(value))
                    if result == nil {
                        result = doMapToArray(mapping, normalized, nil)
                    }
                    return result
                },
                fixed: doMapFixed
            )
        ),

        "symbolSize": VisualHandler(
            applyVisual: makeApplyVisual("symbolSize"),
            _normalizedToVisual: createNormalizedToNumericVisual([0, 1])
        )
    ]


    /**
     * List available visual types.
     *
     * @public
     * @return {Array.<string>}
     */
    // Swift dictionaries are unordered, so the returned order differs from upstream's
    //   JS object insertion order.
    static func listVisualTypes() -> [String] {
        return util.keys(VisualMapping.visualHandlers)
    }

    /**
     * @public
     */
    static func isValidType(_ visualType: String) -> Bool {
        return VisualMapping.visualHandlers[visualType] != nil
    }

    /**
     * Convenient method.
     * Visual can be Object or Array or primary type.
     */
    static func eachVisual(_ visual: Any?, _ callback: (Any?, Any?) -> Void) {
        if util.isObject(visual) {
            if let dict = visual as? [String: Any] {
                for (key, v) in dict { callback(v, key) }
            }
            else if let arr = visual as? [Any] {
                for (i, v) in arr.enumerated() { callback(v, Double(i)) }
            }
            else if let arr = visual as? [Any?] {
                for (i, v) in arr.enumerated() { callback(v, Double(i)) }
            }
        }
        else {
            callback(visual, nil)
        }
    }

    static func mapVisual(_ visual: Any?, _ callback: (Any?, Any?) -> Any?) -> Any? {
        let isArr = util.isArray(visual)
        let isObj = !isArr && util.isObject(visual)
        let isPrimary = !isArr && !isObj

        var arrOut: [Any?] = []
        var dictOut: [String: Any] = [:]
        var primaryOut: Any?

        VisualMapping.eachVisual(visual) { v, key in
            let newVal = callback(v, key)
            if isPrimary {
                primaryOut = newVal
            }
            else if isArr {
                if let k = key as? Double {
                    let idx = Int(k)
                    while arrOut.count <= idx { arrOut.append(nil) }
                    arrOut[idx] = newVal
                }
            }
            else {
                if let k = key as? String { dictOut[k] = newVal }
            }
        }

        if isPrimary { return primaryOut }
        return isArr ? arrOut : dictOut
    }

    /**
     * Retrieve visual properties from given object.
     */
    static func retrieveVisuals(_ obj: [String: Any]?) -> [String: Any]? {
        var ret: [String: Any] = [:]
        var hasVisual = false

        if let obj = obj {
            for (visualType, _) in VisualMapping.visualHandlers {
                if let val = obj[visualType] {   // obj.hasOwnProperty(visualType)
                    ret[visualType] = val
                    hasVisual = true
                }
            }
        }

        return hasVisual ? ret : nil
    }

    /**
     * Give order to visual types, considering colorSaturation, colorAlpha depends on color.
     *
     * @public
     * @param {(Object|Array)} visualTypes If Object, like: {color: ..., colorSaturation: ...}
     *                                     IF Array, like: ['color', 'symbol', 'colorSaturation']
     * @return {Array.<string>} Sorted visual types.
     */
    static func prepareVisualTypes(_ visualTypes: Any?) -> [String] {
        var types: [String]
        if let arr = visualTypes as? [String] {
            types = arr   // visualTypes.slice()
        }
        else if util.isObject(visualTypes), let dict = visualTypes as? [String: Any] {
            var collected: [String] = []
            for (type, _) in dict {
                // upstream's visualSolution.createMappings() stashes the extra opacity->colorAlpha
                //   mapping in a prototype-hidden slot (`mappings.__hidden.__alphaForOpacity`), so this
                //   `each` — which iterates own properties only — never sees it. A Swift dictionary has no
                //   hidden slot, so skip the key explicitly to match. The caller's dict still holds the
                //   entry, so the `type === 'opacity' ? '__alphaForOpacity' : type` lookups still resolve.
                if type == alphaForOpacityKey { continue }
                collected.append(type)
            }
            types = collected
        }
        else {
            return []
        }

        // Swift dictionaries have no source insertion order, so establish the actual dependency
        // deterministically: the base `color` mapping must run before colorLightness/colorAlpha/etc.
        // Preserve all unrelated visual types in their collected order.
        if let colorIndex = types.firstIndex(of: "color"),
           let firstDerivedIndex = types.firstIndex(where: { $0 != "color" && $0.hasPrefix("color") }),
           colorIndex > firstDerivedIndex {
            types.remove(at: colorIndex)
            types.insert("color", at: firstDerivedIndex)
        }

        return types
    }

    /**
     * 'color', 'colorSaturation', 'colorAlpha', ... are depends on 'color'.
     * Other visuals are only depends on themself.
     */
    static func dependsOn(_ visualType1: BuiltinVisualProperty, _ visualType2: BuiltinVisualProperty) -> Bool {
        return visualType2 == "color"
            ? (!visualType1.isEmpty && visualType1.hasPrefix("color"))
            : visualType1 == visualType2
    }

    /**
     * @param value
     * @param pieceList [{value: ..., interval: [min, max]}, ...]
     *                         Always from small to big.
     * @param findClosestWhenOutside Default to be false
     * @return index
     */
    // upstream types `value: number`, but the parameter is loosely used — for a `categories`
    //   visualMap the caller passes the raw CATEGORY VALUE, which can be a string (e.g. a food-group
    //   name). The equality clause below (`pieceValue === value || (isString(pieceValue) && pieceValue ===
    //   value + '')`) relies on that. Narrowing `value` to `Double` (as the old port did) coerced string
    //   categories to NaN, so a piecewise-categories visualMap never matched any piece → every datum fell
    //   to outOfRange. Kept as `Any?` here to preserve the string path; the interval / findClosest math
    //   below reads it through `numValue = asDouble(value)` (NaN for non-numeric, which correctly matches
    //   no numeric interval).
    static func findPieceIndex(
        _ value: Any?,
        _ pieceList: [VisualMappingPiece],
        _ findClosestWhenOutside: Bool = false
    ) -> Double? {
        var possibleI: Double? = nil
        var abs = Double.infinity
        let numValue = asDouble(value)

        // upstream `updatePossible` is a hoisted function declaration; defined up front here.
        func updatePossible(_ val: Double, _ index: Int) {
            let newAbs = Swift.abs(val - numValue)
            if newAbs < abs {
                abs = newAbs
                possibleI = Double(index)
            }
        }

        // value has the higher priority.
        for i in 0..<pieceList.count {
            let pieceValue = pieceList[i].value
            if pieceValue != nil {
                if jsStrictEquals(pieceValue, value)
                    // FIXME
                    // It is supposed to compare value according to value type of dimension,
                    // but currently value type can exactly be string or number.
                    // Compromise for numeric-like string (like '12'), especially
                    // in the case that visualMap.categories is ['22', '33'].
                    || (util.isString(pieceValue) && (pieceValue as? String) == jsLooseStr(value)) {
                    return Double(i)
                }
                if findClosestWhenOutside { updatePossible(asDouble(pieceValue), i) }
            }
        }

        for i in 0..<pieceList.count {
            let piece = pieceList[i]
            let interval = piece.interval
            let close = piece.close

            if let interval = interval {
                let c0 = close?[0] ?? 0
                let c1 = close?[1] ?? 0
                if interval[0] == -Double.infinity {
                    if littleThan(c1, numValue, interval[1]) {
                        return Double(i)
                    }
                }
                else if interval[1] == Double.infinity {
                    if littleThan(c0, interval[0], numValue) {
                        return Double(i)
                    }
                }
                else if littleThan(c0, interval[0], numValue)
                    && littleThan(c1, numValue, interval[1]) {
                    return Double(i)
                }
                if findClosestWhenOutside { updatePossible(interval[0], i) }
                if findClosestWhenOutside { updatePossible(interval[1], i) }
            }
        }

        if findClosestWhenOutside {
            return numValue == Double.infinity
                ? Double(pieceList.count - 1)
                : (numValue == -Double.infinity
                    ? 0
                    : possibleI)
        }

        return possibleI   // upstream falls off end → undefined (possibleI is nil unless findClosest set it)
    }
}

private func preprocessForPiecewise(_ thisOption: VisualMappingInnerOption) {
    var pieceList = thisOption.pieceList ?? []
    thisOption.hasSpecialVisual = false

    for index in 0..<pieceList.count {
        pieceList[index].originIndex = Double(index)
        // piece.visual is "result visual value" but not
        // a visual range, so it does not need to be normalized.
        if pieceList[index].visual != nil {
            thisOption.hasSpecialVisual = true
        }
    }
    thisOption.pieceList = pieceList
}

private func preprocessForSpecifiedCategory(_ thisOption: VisualMappingInnerOption) {
    // Hash categories.
    var categories = thisOption.categories ?? []
    var categoryMap: [String: Double] = [:]
    thisOption.categoryMap = categoryMap

    var visual = thisOption.visual
    for index in 0..<categories.count {
        categoryMap[categoryKey(categories[index])] = Double(index)
    }

    // Process visual map input.
    if !util.isArray(visual) {
        var visualArr: [Any?] = []

        if util.isObject(visual), let dict = visual as? [String: Any] {
            for (cate, v) in dict {
                let index = categoryMap[cate]
                if let index = index {
                    setAt(&visualArr, Int(index), v)
                }
                else {
                    // visualArr[CATEGORY_DEFAULT_VISUAL_INDEX] = v
                    thisOption.categoryDefaultVisual = v
                }
            }
        }
        else { // Is primary type, represents default visual.
            // visualArr[CATEGORY_DEFAULT_VISUAL_INDEX] = visual
            thisOption.categoryDefaultVisual = visual
        }

        visual = setVisualToOption(thisOption, visualArr)
    }

    // Remove categories that has no visual,
    // then we can mapping them to CATEGORY_DEFAULT_VISUAL_INDEX.
    var i = categories.count - 1
    while i >= 0 {
        if elementAt(visual, i) == nil {
            categoryMap[categoryKey(categories[i])] = nil   // delete categoryMap[categories[i]]
            categories.removeLast()                         // categories.pop()
        }
        i -= 1
    }

    thisOption.categories = categories
    thisOption.categoryMap = categoryMap
}

private func normalizeVisualRange(_ thisOption: VisualMappingInnerOption, _ isCategory: Bool = false) {
    let visual = thisOption.visual
    var visualArr: [Any?] = []

    // upstream: if (isObject(visual)) each(visual, v => visualArr.push(v)); else if (visual != null) push(visual)
    //   `isObject` is true for arrays and objects alike in JS.
    if let arr = visual as? [Any] {
        for v in arr { visualArr.append(v) }
    }
    else if let arr = visual as? [Any?] {
        for v in arr { visualArr.append(v) }
    }
    else if let dict = visual as? [String: Any] {
        // POTENTIAL-BUG (SEMANTIC_RISK): Swift dict iteration order is nondeterministic; upstream relies
        //   on JS object insertion order here, so the flattened visualArr order (and thus paired visual
        //   assignment) can differ. Rare (visual for linear/fixed is usually an array, not an object).
        for (_, v) in dict { visualArr.append(v) }
    }
    else if visual != nil {
        visualArr.append(visual)
    }

    let doNotNeedPair: [String: Int] = ["color": 1, "symbol": 1]

    if !isCategory
        && visualArr.count == 1
        && doNotNeedPair[thisOption.type!] == nil {   // !doNotNeedPair.hasOwnProperty(thisOption.type)
        // Do not care visualArr.length === 0, which is illegal.
        visualArr.append(visualArr[0])   // visualArr[1] = visualArr[0]
    }

    _ = setVisualToOption(thisOption, visualArr)
}

private func makePartialColorVisualHandler(
    _ applyValue: @escaping (VisualValue?, NormalizedValue) -> VisualValue?
) -> VisualHandler {
    return VisualHandler(
        applyVisual: { mapping, value, getter, setter in
            // Only used in HSL
            let colorChannel = mapping.mapValueToVisual(value)
            // Must not be array value.
            //   PORT BRIDGE: the seed `color` visual may be a plain `String` (upstream form) OR a
            //   `ZRColor.color(String)` enum — the palette assigns colors wrapped in `ZRColor`
            //   (getColorFromPalette). The HSL math (`applyValue` → `color.modifyHSL`) works on the raw
            //   color string, so unwrap the enum first; otherwise the `as? String` guard inside applyValue
            //   fails and every mapped color collapses to nil (→ black). Mirrors `symbolColorString`.
            let baseColor = visualMapColorString(getter("color"))
            setter("color", applyValue(baseColor, asDouble(colorChannel)))
        },
        _normalizedToVisual: createNormalizedToNumericVisual([0, 1])
    )
}

private func doMapToArray(_ mapping: VisualMapping, _ normalized: NormalizedValue, _ value: RawValue?) -> VisualValue? {
    let visual = asAnyOptArray(mapping.option.visual)
    let idx = Int(number.mathRound(number.linearMap(normalized, [0, 1], [0, Double(visual.count - 1)], true)))
    let el = (idx >= 0 && idx < visual.count) ? visual[idx] : nil
    // upstream: `visual[...] || {}`  (TODO {}?)
    return jsTruthy(el) ? el : [String: Any]()
}

private func makeApplyVisual(_ visualType: String) -> (VisualMapping, RawValue, VisualValueGetter, VisualValueSetter) -> Void {
    return { mapping, value, _, setter in
        setter(visualType, mapping.mapValueToVisual(value))
    }
}

private func doMapCategory(_ mapping: VisualMapping, _ normalized: NormalizedValue, _ value: RawValue?) -> VisualValue? {
    let visual = asAnyOptArray(mapping.option.visual)
    let count = visual.count
    let idx: Int
    if mapping.option.loop == true && normalized != CATEGORY_DEFAULT_VISUAL_INDEX {
        // JS `normalized % visual.length`
        idx = count == 0 ? Int(normalized) : Int(normalized).jsMod(count)
    }
    else {
        idx = Int(normalized)
    }
    if idx == Int(CATEGORY_DEFAULT_VISUAL_INDEX) {
        return mapping.option.categoryDefaultVisual   // arr[-1]
    }
    if idx >= 0 && idx < count {
        return visual[idx]
    }
    return nil
}

private func doMapFixed(_ mapping: VisualMapping, _ normalized: NormalizedValue, _ value: RawValue?) -> VisualValue? {
    // visual will be convert to array.
    let visual = asAnyOptArray(mapping.option.visual)
    return visual.first ?? nil   // (this.option.visual as VisualValue[])[0]
}

/**
 * Create mapped to numeric visual
 */
private func createNormalizedToNumericVisual(_ sourceExtent: [Double]) -> NormalizedToVisual {
    return NormalizedToVisual(
        linear: { mapping, normalized, _ in
            number.linearMap(normalized, sourceExtent, visualAsDoublePair(mapping.option), true)
        },
        category: doMapCategory,
        piecewise: { mapping, normalized, value in
            var result = getSpecifiedVisual(mapping, asDouble(value))
            if result == nil {
                result = number.linearMap(normalized, sourceExtent, visualAsDoublePair(mapping.option), true)
            }
            return result
        },
        fixed: doMapFixed
    )
}

private func getSpecifiedVisual(_ mapping: VisualMapping, _ value: Double) -> Any? {
    let thisOption = mapping.option
    let pieceList = thisOption.pieceList ?? []
    if thisOption.hasSpecialVisual {
        let pieceIndex = VisualMapping.findPieceIndex(value, pieceList)
        if let pieceIndex = pieceIndex {
            let idx = Int(pieceIndex)
            if idx >= 0 && idx < pieceList.count {
                let piece = pieceList[idx]
                if let visual = piece.visual {   // piece && piece.visual
                    return visual[mapping.type]
                }
            }
        }
    }
    return nil
}

@discardableResult
private func setVisualToOption(_ thisOption: VisualMappingInnerOption, _ visualArr: [Any?]) -> [Any?] {
    thisOption.visual = visualArr
    if thisOption.type == "color" {
        thisOption.parsedVisual = util.map(visualArr) { (item, _) -> [Double] in
            let parsed = (item as? String).flatMap { color.parse($0) }
            if parsed == nil {
                // upstream: if (!color && __DEV__) warn(`'${item}' is an illegal color, ...`, true);
                log.warn("'\(item ?? "")' is an illegal color, fallback to '#000000'", true)
            }
            return parsed ?? [0, 0, 0, 1]
        }
    }
    return visualArr
}


/**
 * Normalizers by mapping methods.
 */
// upstream: const normalizers: { [key in MappingMethod]: Normalizer }
private let normalizers: [MappingMethod: Normalizer] = [
    "linear": { mapping, value in
        number.linearMap(asDouble(value), mapping.option.dataExtent ?? [], [0, 1], true)
    },

    "piecewise": { mapping, value in
        let pieceList = mapping.option.pieceList ?? []
        let pieceIndex = VisualMapping.findPieceIndex(asDouble(value), pieceList, true)
        if let pieceIndex = pieceIndex {
            return number.linearMap(pieceIndex, [0, Double(pieceList.count - 1)], [0, 1], true)
        }
        // upstream returns undefined; NaN flows into fastLerp's `>=0 && <=1` guard → nil.
        return Double.nan
    },

    "category": { mapping, value in
        let index: Double?
        if mapping.option.categories != nil {
            index = mapping.option.categoryMap[categoryKey(value)]
        }
        else {
            index = value == nil ? nil : asDouble(value)   // ordinal value
        }
        return index == nil ? CATEGORY_DEFAULT_VISUAL_INDEX : index!
    },

    // upstream: zrUtil.noop as Normalizer (normalized unused by doMapFixed)
    "fixed": { _, _ in Double.nan }
]


private func littleThan(_ close: Double, _ a: Double, _ b: Double) -> Bool {
    // upstream: close: boolean | 0 | 1 — jsTruthy is `!= 0`
    return close != 0 ? a <= b : a < b
}

// MARK: - Port helpers (not upstream symbols)

/// Int|Double|NSNumber|String -> Double coercion (never a bare `as? Double`, per the INT-vs-DOUBLE trap).
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

/// JS truthiness shim (`nil`/`NSNull`/`false`/`0`/`NaN`/`""` are falsy).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// JS `value + ''` for a number (matches color.numToStr behavior: integral values print without ".0").
private func jsNumStr(_ n: Double) -> String {
    if n.isNaN { return "NaN" }
    if n.isInfinite { return n > 0 ? "Infinity" : "-Infinity" }
    if n == n.rounded(.towardZero) && Swift.abs(n) < 1e16 {
        return String(Int(n))
    }
    return String(n)
}

/// JS object key coercion for a category value (number -> its JS string form, string -> itself).
private func categoryKey(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let d = v as? Double { return jsNumStr(d) }
    if let i = v as? Int { return String(i) }
    return String(describing: v ?? "")
}

/// Read a (possibly `[Any]` or `[Any?]`) normalized visual array as `[Any?]` (holes = nil).
private func asAnyOptArray(_ v: Any?) -> [Any?] {
    if let a = v as? [Any?] { return a }
    if let a = v as? [Any] { return a.map { $0 as Any? } }
    return []
}

/// `this.option.visual as [number, number]` — coerce the (paired) numeric visual array.
private func visualAsDoublePair(_ option: VisualMappingInnerOption) -> [Double] {
    return asAnyOptArray(option.visual).map { asDouble($0) }
}

/// Bridge a `color` visual to a plain color string. Upstream color visuals are always strings; the
///   port wraps palette colors as `ZRColor.color(String)` (getColorFromPalette), so the partial-color
///   HSL handlers must unwrap that enum before running `color.modifyHSL`. Mirrors the
///   `symbolColorString` bridge in chart/helper/SymbolElement.swift.
private func visualMapColorString(_ v: Any?) -> String? {
    if let s = v as? String { return s }
    if let zr = v as? ZRColor, case let .color(str) = zr { return str }
    return nil
}

/// JS sparse-array assignment `arr[idx] = v` (grows with nil holes; idx assumed >= 0).
private func setAt(_ arr: inout [Any?], _ idx: Int, _ v: Any?) {
    if idx < 0 { return }
    while arr.count <= idx { arr.append(nil) }
    arr[idx] = v
}

/// JS `visual[i]` read (out-of-range -> nil).
private func elementAt(_ v: Any?, _ i: Int) -> Any? {
    let arr = asAnyOptArray(v)
    if i >= 0 && i < arr.count { return arr[i] }
    return nil
}

/// upstream JS strict equality `a === b` for the number|string values a piece / data value can hold.
///   Same-type only: number===number or string===string (mixed types are never `===` in JS).
private func jsStrictEquals(_ a: Any?, _ b: Any?) -> Bool {
    // string === string
    if let sa = a as? String { return (b as? String) == sa }
    if b is String { return false }
    // number === number (Int/Double/NSNumber all read as a Double here)
    let na = numericOrNil(a)
    let nb = numericOrNil(b)
    if let na = na, let nb = nb { return na == nb }
    return false
}

/// A numeric coercion that returns nil (not NaN) for non-numeric values, so `jsStrictEquals` can tell a
///   number apart from a string/other. (`asDouble` returns NaN for strings, which would break `===`.)
private func numericOrNil(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(v is Bool) { return n.doubleValue }
    return nil
}

/// upstream `value + ''` (JS string coercion): string -> itself, number -> its JS numeric string form.
private func jsLooseStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    return jsNumStr(asDouble(v))
}

/// Coerce an `Any?` (array of Int/Double/NSNumber) to `[Double]?` for the `[String: Any]` option bag.
private func coerceDoubleArray(_ v: Any?) -> [Double]? {
    guard let arr = v as? [Any] else { return nil }
    return arr.map { asDouble($0) }
}

private extension Int {
    /// JS `%` for the non-negative counts used here (Swift `%` matches JS truncated remainder for Int).
    func jsMod(_ m: Int) -> Int {
        return self % m
    }
}
