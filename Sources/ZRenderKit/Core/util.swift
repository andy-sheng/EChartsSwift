// Ported from zrender/src/core/util.ts — keep in sync with upstream
//
// SCOPE NOTE (per port guidance): `util.ts` is a large general-purpose helper module.
// Only the numeric/array helpers actually consumed by the geometry layer
// (vector/matrix/bbox/curve and the Path* family) are translated faithfully here —
// `each`/`map`/`reduce`/`filter`/`find`/`indexOf`, `retrieve`/`retrieve2`/`retrieve3`,
// `defaults`, `normalizeCssArray`, `eqNaN`, `guid`, `assert`, `noop`, and the
// `RADIAN_TO_DEGREE` / `EPSILON` constants.
//
// The JS object-merge / runtime duck-typing / DOM / polyfill helpers do NOT map onto
// Swift's static type system and are intentionally left as `// note` stubs below,
// in their original upstream position, so the file still diffs line-for-line against
// `util.ts`. See the consolidated note list at the bottom.

import Foundation

// upstream import aliases the module as `zrUtil`; call sites read `util.each(...)` etc.
public enum util {

    // 用于处理merge时无法遍历Date等对象的问题
    // BUILTIN_OBJECT — JS runtime type tag table for merge/clone; no Swift analogue.

    // TYPED_ARRAY — JS `[object Float32Array]` tag table; not needed by geometry.

    // objToString / arrayProto / nativeForEach / nativeFilter / nativeSlice /
    //            nativeMap / ctorFunction / protoFunction / protoKey — JS prototype plumbing.

    private static var idStart: Double = 0x0907

    private static let MAX_SAFE_INTEGER: Double = pow(2, 53) - 1

    /**
     * Generate unique id
     */
    public static func guid() -> Double {
        if idStart >= MAX_SAFE_INTEGER {
            idStart = 0
        }
        let v = idStart
        idStart += 1
        return v
    }

    public static func logError(_ args: Any...) {
        // upstream forwards to console.error; geometry never calls this.
        // print(args)
    }

    /**
     * Those data types can be cloned:
     *     Plain object, Array, TypedArray, number, string, null, undefined.
     * Those data types will be assigned using the original data:
     *     BUILTIN_OBJECT
     * Instance of user defined class will be cloned to a plain object, without
     * properties in prototype.
     * Other data types is not supported (not sure what will happen).
     *
     * Caution: do not support clone Date, for performance consideration.
     * (There might be a large number of date in `series.data`).
     * So date should not be modified in and out of echarts.
     *
     * NOTE (port): Swift value types (struct / enum / Array / Dictionary of value
     * types) already deep-copy on assignment (copy-on-write), so the generic path
     * here is the identity. We additionally walk `[String: Any]` / `[Any]` bags so
     * heterogeneous option/style dictionaries clone recursively, matching upstream's
     * `[object Array]` / plain-object branches. Reference-typed (class) graphs are
     * NOT deep-cloned — mirroring "instance of user defined class" being out of the
     * faithful set we can reproduce statically.
     */
    public static func clone<T>(_ source: T) -> T {
        // if (source == null || typeof source !== 'object') return source;
        if let dict = source as? [String: Any] {
            // !BUILTIN_OBJECT[typeStr] && !isPrimitive(source) && !isDom(source)
            if isPrimitiveBag(dict) {
                // result stays === source: a primitive-tagged bag is assigned, not traversed.
                return source
            }
            var result: [String: Any] = [:]
            for key in dict.keys {
                // Check if key is __proto__ to avoid prototype pollution — N/A in Swift.
                let cloned: Any = clone(dict[key]!)
                result[key] = cloned
            }
            // safe: T is [String: Any] in this branch
            return result as! T
        }
        else if let arr = source as? [Any] {
            // if (!isPrimitive(source)) — ALWAYS FALSE here; see the `[Any]` TODO on
            // setAsPrimitive: a Swift array has neither an in-band slot nor a stable identity,
            // so it can never carry the tag. Left as a comment-only structural mirror rather
            // than a live call, which would cost an `Any` box + a failed dictionary cast per
            // array node of the option tree on every clone.
            var result: [Any] = []
            for i in 0..<arr.count {
                result.append(clone(arr[i]))
            }
            // safe: T is [Any] (or a covariant element array) in this branch
            return result as! T
        }
        // TYPED_ARRAY branch (ContiguousArray<Float/Double/…>) — value
        //            semantics already copy on assignment, so the passthrough below
        //            reproduces it (and subsumes upstream's `!isPrimitive` guard on that
        //            branch: a tagged typed array is likewise never traversed);
        //            BUILTIN_OBJECT / isDom have no Swift analogue and collapse here too.
        return source
    }

    /**
     * Recursive object-literal merge (JS `for ... in`). Faithful structural port over
     * `[String: Any]` bags. When both `target[key]` and `source[key]` are nested
     * dictionaries they are merged recursively; otherwise the value is overwritten
     * (when `overwrite` is set or the key is absent in `target`).
     */
    @discardableResult
    public static func merge(
        _ target: inout [String: Any],
        _ source: [String: Any],
        _ overwrite: Bool = false
    ) -> [String: Any] {
        // We should escapse that source is string and enter for ... in ...
        // (Statically guaranteed here: both are dictionaries.)
        for key in source.keys {
            // Check if key is __proto__ to avoid prototype pollution — N/A in Swift.
            let targetProp = target[key]
            let sourceProp = source[key]

            // isObject(sourceProp) && isObject(targetProp) && !isArray(...) && !isDom(...)
            // && !isBuiltInObject(...) && !isPrimitive(...): nested plain objects only.
            if let sp = sourceProp as? [String: Any], var tp = targetProp as? [String: Any],
               !isPrimitiveBag(sp), !isPrimitiveBag(tp) {
                // 如果需要递归覆盖，就递归调用merge
                target[key] = merge(&tp, sp, overwrite)
            }
            else if overwrite || target[key] == nil {
                // 否则只处理overwrite为true，或者在目标对象中没有此属性的情况
                // NOTE，在 target[key] 不存在的时候也是直接覆盖
                let cloned: Any = clone(sourceProp!)
                target[key] = cloned
            }
        }
        return target
    }

    /**
     * @param targetAndSources The first item is target, and the rests are source.
     * @param overwrite
     * @return Merged result
     */
    @discardableResult
    public static func mergeAll(_ targetAndSources: [[String: Any]], _ overwrite: Bool = false) -> [String: Any] {
        var result = targetAndSources[0]
        for i in 1..<targetAndSources.count {
            result = merge(&result, targetAndSources[i], overwrite)
        }
        return result
    }

    /**
     * Object.assign over dictionaries — copy every key of `source` onto `target`.
     */
    @discardableResult
    public static func extend<T>(_ target: inout [String: T], _ source: [String: T]) -> [String: T] {
        // Object.assign(target, source)
        for key in source.keys {
            // Check if key is __proto__ to avoid prototype pollution — N/A in Swift.
            target[key] = source[key]
        }
        return target
    }

    // assignProps(tar, src, props) — copies a key subset between option bags.
    //            Use Swift `extend` over a filtered key list at call sites.

    /**
     * defaults — fill missing keys of `target` from `source`.
     * Swift-idiomatic dictionary form (the only shape geometry needs).
     */
    @discardableResult
    public static func defaults<T>(
        _ target: inout [String: T],
        _ source: [String: T],
        _ overlay: Bool = false
    ) -> [String: T] {
        let keysArr = keys(source)
        for i in 0..<keysArr.count {
            let key = keysArr[i]
            // (overlay ? source[key] != null : target[key] == null)
            if overlay ? (source[key] != nil) : (target[key] == nil) {
                target[key] = source[key]
            }
        }
        return target
    }

    /// Get all object keys. (Swift dictionary form.)
    public static func keys<T>(_ obj: [String: T]) -> [String] {
        return Array(obj.keys)
    }

    // createCanvas = platformApi.createCanvas — renderer seam (§9), not ported.

    /**
     * 查询数组中元素的index
     */
    public static func indexOf<T: Equatable>(_ array: [T]?, _ value: T) -> Double {
        if let array = array {
            for i in 0..<array.count {
                if array[i] == value {
                    return Double(i)
                }
            }
        }
        return -1
    }

    // inherits(clazz, baseClazz) — prototype-chain mixin; use `class Sub: Super`
    //            (CONVENTIONS §2) at the Swift class definitions instead.

    // mixin(target, source, override) — prototype property copy; model with
    //            protocol + protocol-extension per CONVENTIONS §2.

    /**
     * Consider typed array.
     * @param data
     */
    public static func isArrayLike(_ data: Any?) -> Bool {
        // upstream is JS `.length` duck typing; here we approximate with the
        //            concrete array shapes the port produces. Non-string sequences with a
        //            count qualify; `String` is explicitly excluded (matches upstream).
        guard let data = data else {
            return false
        }
        if data is String {
            return false
        }
        return data is [Any]
    }

    /**
     * 数组或对象遍历 (array form — the shape the geometry layer uses)
     */
    public static func each<T>(_ arr: [T]?, _ cb: (T, Int) -> Void) {
        guard let arr = arr else { return }
        for i in 0..<arr.count {
            // FIXME: should the elided item be travelled? like `[33,,55]`.
            cb(arr[i], i)
        }
    }

    /**
     * 数组或对象遍历 (object form) — mirrors upstream's `else { for (key in arr) … }`
     * branch, which iterates a `Dictionary<any>` invoking `cb(value, key)`. Key order is
     * unspecified in Swift (as it is a duck-typed `for...in` upstream on non-array bags).
     */
    public static func each<T>(_ obj: [String: T]?, _ cb: (T, String) -> Void) {
        guard let obj = obj else { return }
        for (key, value) in obj {
            cb(value, key)
        }
    }

    /**
     * Array mapping.
     * @return Must be an array.
     */
    public static func map<T, R>(_ arr: [T]?, _ cb: (T, Int) -> R) -> [R] {
        // Take the same behavior with lodash when !arr.
        guard let arr = arr else { return [] }
        var result: [R] = []
        for i in 0..<arr.count {
            // FIXME: should the elided item be travelled, like `[33,,55]`.
            result.append(cb(arr[i], i))
        }
        return result
    }

    public static func reduce<T, S>(_ arr: [T]?, _ cb: (S, T, Int) -> S, _ memo: S) -> S {
        guard let arr = arr else { return memo }
        var memo = memo
        for i in 0..<arr.count {
            memo = cb(memo, arr[i], i)
        }
        return memo
    }

    /**
     * Array filtering.
     * @return Must be an array.
     */
    public static func filter<T>(_ arr: [T]?, _ cb: (T, Int) -> Bool) -> [T] {
        // Take the same behavior with lodash when !arr.
        guard let arr = arr else { return [] }
        var result: [T] = []
        for i in 0..<arr.count {
            // FIXME: should the elided items be travelled? like `[33,,55]`.
            if cb(arr[i], i) {
                result.append(arr[i])
            }
        }
        return result
    }

    /**
     * 数组项查找
     */
    public static func find<T>(_ arr: [T]?, _ cb: (T, Int) -> Bool) -> T? {
        guard let arr = arr else { return nil }
        for i in 0..<arr.count {
            if cb(arr[i], i) {
                return arr[i]
            }
        }
        return nil
    }

    // bind / curry — JS Function.prototype.bind partial application; use Swift
    //            closures directly at call sites.

    public static func isArray(_ value: Any?) -> Bool {
        guard let value = value else {
            return false
        }
        // Array.isArray(value) — Swift dynamic cast covers covariant element arrays
        // ([Double], [String], …) as well as [Any].
        return value is [Any]
    }

    public static func isFunction(_ value: Any?) -> Bool {
        // typeof value === 'function'
        // Swift closures carry no protocol conformance, but a function value's dynamic type
        // description always contains "->" (e.g. "(Int) -> String"), which no non-function value
        // produces. This heuristic covers the callers that matter (e.g. DataStore's provider
        // getItem/count sanity assert). Non-function values (incl. metatypes) never match.
        guard let value = value else { return false }
        return String(describing: Swift.type(of: value)).contains("->")
    }

    public static func isString(_ value: Any?) -> Bool {
        // Faster than `objToString.call` several times in chromium and webkit.
        // And `new String()` is rarely used.
        return value is String
    }

    public static func isStringSafe(_ value: Any?) -> Bool {
        return value is String
    }

    public static func isNumber(_ value: Any?) -> Bool {
        // Faster than `objToString.call` several times in chromium and webkit.
        // And `new Number()` is rarely used.
        // (All `number` map to `Double` per CONVENTIONS §1.)
        return value is Double
    }

    // Usage: `isObject(xxx)`
    public static func isObject(_ value: Any?) -> Bool {
        // type === 'function' || (!!value && type === 'object')
        guard let value = value else {
            return false
        }
        // JS: arrays and dictionaries are `typeof === 'object'`; class instances too.
        if value is [Any] || value is [String: Any] {
            return true
        }
        if isFunction(value) {
            return true
        }
        // upstream `typeof === 'object'` also matches user class instances /
        //            option bags. We approximate with reference (class) types here.
        return Mirror(reflecting: value).displayStyle == .class
    }

    public static func isBuiltInObject(_ value: Any?) -> Bool {
        // !!BUILTIN_OBJECT[objToString.call(value)]
        // BUILTIN_OBJECT tag table (Function/RegExp/Date/Error/CanvasGradient/
        //            CanvasPattern/Image/Canvas) has no faithful Swift analogue; none of
        //            these participate in the ported geometry/style bags, so `false`.
        _ = value
        return false
    }

    public static func isTypedArray(_ value: Any?) -> Bool {
        // !!TYPED_ARRAY[objToString.call(value)]
        guard let value = value else {
            return false
        }
        return value is ContiguousArray<Float>
            || value is ContiguousArray<Double>
            || value is ContiguousArray<Int8>
            || value is ContiguousArray<UInt8>
            || value is ContiguousArray<Int16>
            || value is ContiguousArray<UInt16>
            || value is ContiguousArray<Int32>
            || value is ContiguousArray<UInt32>
    }

    public static func isDom(_ value: Any?) -> Bool {
        // typeof value === 'object' && typeof value.nodeType === 'number'
        //     && typeof value.ownerDocument === 'object'
        // DOM / HTMLElement detection — renderer/DOM seam (CONVENTIONS §9),
        //            no HTMLElement in the native port; always false.
        _ = value
        return false
    }

    public static func isGradientObject(_ value: Any?) -> Bool {
        // upstream: (value as GradientObject).colorStops != null. `Gradient` is the concrete base of
        // LinearGradient/RadialGradient (those can't adopt the `GradientObject` protocol — its
        // `global: Bool?` clashes with Gradient's stored `global: Bool`), so detect the base class.
        return value is Gradient
    }

    public static func isImagePatternObject(_ value: Any?) -> Bool {
        // upstream: (value as ImagePatternObject).image != null. `ImagePatternObject`
        // (graphic/Pattern) carries a non-optional `image: String`, so any conformer
        // necessarily has it present — the faithful check is just the type test.
        return value is ImagePatternObject
    }

    public static func isRegExp(_ value: Any?) -> Bool {
        // objToString.call(value) === '[object RegExp]'
        return value is NSRegularExpression
    }

    /**
     * Whether is exactly NaN. Notice isNaN('a') returns true.
     */
    public static func eqNaN(_ value: Double) -> Bool {
        /* eslint-disable-next-line no-self-compare */
        return value != value
    }

    /**
     * If value1 is not null, then return value1, otherwise judget rest of values.
     * Low performance.
     * @return Final value
     */
    public static func retrieve<T>(_ args: T?...) -> T? {
        for i in 0..<args.count {
            if args[i] != nil {
                return args[i]
            }
        }
        return nil
    }

    public static func retrieve2<T>(_ value0: T?, _ value1: T?) -> T? {
        return value0 != nil
            ? value0
            : value1
    }

    public static func retrieve3<T>(_ value0: T?, _ value1: T?, _ value2: T?) -> T? {
        return value0 != nil
            ? value0
            : value1 != nil
            ? value1
            : value2
    }

    // slice(arr, ...args) — JS Array.prototype.slice forwarding; use Swift
    //            subranges (`arr[i..<j]`) at call sites.

    /**
     * Normalize css liked array configuration
     * e.g.
     *  3 => [3, 3, 3, 3]
     *  [4, 2] => [4, 2, 4, 2]
     *  [4, 3, 2] => [4, 3, 2, 3]
     */
    public static func normalizeCssArray(_ val: Double) -> [Double] {
        return [val, val, val, val]
    }

    public static func normalizeCssArray(_ val: [Double]) -> [Double] {
        let len = val.count
        if len == 2 {
            // vertical | horizontal
            return [val[0], val[1], val[0], val[1]]
        }
        else if len == 3 {
            // top | horizontal | bottom
            return [val[0], val[1], val[2], val[1]]
        }
        return val
    }

    public static func assert(_ condition: Bool, _ message: String? = nil) {
        if !condition {
            // upstream: throw new Error(message)
            preconditionFailure(message ?? "")
        }
    }

    // trim(str) — String trimming; use Swift
    //            `str.trimmingCharacters(in: .whitespacesAndNewlines)` at call sites.

    // const primitiveKey = '__ec_primitive__';
    //
    // upstream stamps a hidden own-property on the object itself
    //   (`obj[primitiveKey] = true`) and relies on JS reference semantics, so every later
    //   holder of that reference observes the tag. Swift splits this into two cases:
    //     · plain option/style bags are `[String: Any]` VALUE types — they can carry the key
    //       in-band exactly like upstream, but only through an `inout` parameter, so the
    //       mutation is written back into the caller's storage (dict overload below).
    //     · reference (class) objects have no dynamic property slot, so they are recorded in
    //       an identity side-set (weak, so the tag dies with the object like the JS property).
    //   `isPrimitive` consults both, so call sites read exactly as upstream.
    // TODO: `[Any]` (e.g. `dataset.transform` given as an ARRAY of transforms) cannot
    //   carry the tag — a Swift array has neither an in-band slot nor a stable identity. Two
    //   divergences follow from that, both inert today:
    //     (a) `merge` — NO divergence in effect: upstream's nested-merge branch is itself
    //         guarded by `!isArray(...)`, so an array-valued option is replaced wholesale with
    //         or without the tag, which is exactly what `disableTransformOptionMerge` wants.
    //     (b) `clone` — REAL divergence: upstream returns a tagged array by reference,
    //         untraversed, whereas this port deep-copies it (the `[Any]` branch of `clone`),
    //         so both identity and tag are lost on every clone of the option tree. Harmless
    //         only because no consumer relies on transform-option identity today; revisit if
    //         one appears.
    private static let primitiveKey = "__ec_primitive__"

    private static let primitiveObjects = NSHashTable<AnyObject>.weakObjects()

    /**
     * Set an object as primitive to be ignored traversing children in clone or merge
     */
    // The `T: AnyObject` generic constraint is load-bearing and must NOT be relaxed back to a
    // plain `AnyObject` parameter: Swift would then implicitly box `[String: Any]`, `[Any]` or
    // any struct into a temporary `__SwiftValue`/`NSDictionary`, add THAT box to the weak
    // table, and deallocate it on return — a silent permanent no-op with no compile error.
    // The constraint is checked statically (Dictionary/Array/structs do not conform), so a
    // value bag fails to compile here and the caller is pointed at the `inout` overload below.
    public static func setAsPrimitive<T: AnyObject>(_ obj: T) {
        // obj[primitiveKey] = true;
        primitiveObjects.add(obj)
    }

    /// Value-bag overload — see the note above. `inout` so the in-band key lands in the
    /// caller's own storage (upstream mutates through the shared reference). Option/style bags
    /// MUST use this overload; it is the load-bearing one in-tree.
    public static func setAsPrimitive(_ obj: inout [String: Any]) {
        // obj[primitiveKey] = true;
        obj[primitiveKey] = true
    }

    public static func isPrimitive(_ obj: Any) -> Bool {
        // return obj[primitiveKey];
        // The identity side-set is consulted FIRST: a class object that bridges to a Swift
        // dictionary (NSDictionary/NSMutableDictionary, anything from Obj-C or
        // JSONSerialization) would otherwise match the in-band branch, find no key, and report
        // false — silently dropping a tag `setAsPrimitive` really did record.
        if type(of: obj) is AnyClass, primitiveObjects.contains(obj as AnyObject) {
            return true
        }
        if let dict = obj as? [String: Any] {
            return isPrimitiveBag(dict)
        }
        return false
    }

    /// Fast path for call sites that already hold the bag: avoids re-boxing to `Any` and
    /// repeating the `as? [String: Any]` dynamic cast. `clone`/`merge` run this per node of
    /// the whole option tree on every `setOption`, so the saved cast is not academic.
    private static func isPrimitiveBag(_ d: [String: Any]) -> Bool {
        return (d[primitiveKey] as? Bool) == true
    }

    // MapPolyfill / maybeNativeMap / HashMap / createHashMap — JS Map shim;
    //            use Swift `Dictionary` directly where geometry needs key/value storage.

    // concatArray(a, b) — typed-array concat preserving constructor; use Swift
    //            `a + b` for `[T]` / `ContiguousArray`.

    public static func createObject<T>(_ proto: [String: T] = [:], _ properties: [String: T]? = nil) -> [String: T] {
        // Performance of Object.create
        // https://jsperf.com/style-strategy-proto-or-others
        //
        // upstream `Object.create(proto)` builds a new object with a LIVE
        //            prototype link, so missing keys resolve up the chain and later
        //            mutations of `proto` are visible. Swift has no prototype chain, so
        //            we materialize (flatten) the proto's keys into the new object and
        //            overlay `properties`. Reads still resolve identically; writes shadow
        //            instead of being trapped, and `keys()` now enumerates inherited keys.
        var obj = proto
        if let properties = properties {
            extend(&obj, properties)
        }
        return obj
    }

    // disableUserSelect(dom) — DOM style mutation; renderer/DOM seam, not ported.

    // hasOwn(own, prop) — JS hasOwnProperty; use `dict[prop] != nil`.

    public static func noop() {}

    public static let RADIAN_TO_DEGREE: Double = 180 / Double.pi

    // Number.EPSILON (=== 2^-52) maps to Swift's Double.ulpOfOne.
    public static let EPSILON: Double = Double.ulpOfOne
}
