# PORTING.md — Hard rulebook for TS → Swift ports (zrender/echarts)

> Companion to `CONVENTIONS.md`. This page is the **mechanical checklist** you run for every symbol you translate. Overriding goal: **structural fidelity** — a ported `.swift` must diff cleanly against its `.ts` original. When fidelity fights elegance, pick fidelity. Every file starts with `// Ported from <upstream/path>.ts — keep in sync with upstream` and marks gaps with `// PORT-TODO:`.

---

## 1. Names = upstream identifiers, verbatim

Every public/shared symbol (type, method, property, function, constant, enum case) keeps its **exact upstream spelling** — same casing, no "Swiftification". This is what makes call sites and diffs line up.

```ts
export function addCommas(x) { … }      // upstream
```
```swift
public static func addCommas(_ x: String) -> String { … }   // NOT addCommasTo / commafy
```

Do **not** rename to satisfy the linter. Lowercase namespace enums (`vector`, `number`, `format`) are intentional (§2).

---

## 2. Grep before you create a shared symbol — reuse if it exists

Before adding any shared type, namespace, or helper, **search first**:

```bash
rg -n 'enum number|func parseDate|struct BoundingRect' Sources/
```

If the upstream symbol is already ported, **reuse it** — never make a second `number`, a parallel `BoundingRect`, or a private copy of a util function. Two definitions of one upstream symbol is a port bug. Cross-module symbols already live in `ZRenderKit` (`util`, `vector`, `matrix`, `Path`, `BoundingRect`) or `EChartsKit/util` (`number`, `format`, `graphic`, `layout`, …).

---

## 3. Free-function module → caseless `enum <FileName>` namespace

A TS module of free functions (`vector.ts`, `number.ts`, `format.ts`) becomes a **caseless `enum` named after the file**, so call sites stay byte-identical to `import * as X`.

```swift
// Ported from echarts/src/util/number.ts — keep in sync with upstream
public enum number {                       // upstream alias: none; file name wins
    public static let RADIAN_EPSILON = 1e-4
    public static func parseDate(_ value: Any?) -> Date? { … }
}
// call: number.parseDate(v)   ← matches upstream `parseDate(v)`
```

Use the **file name** as the enum (`vector`, not `Vector`; even when locally aliased `vec2` — note the alias in a comment). Never instantiate it; it has no cases. `export const length = len` → `public static let length = len`.

---

## 4. `class` → `final class`; `interface` → `protocol` (+ extension for defaults)

- TS `class` → Swift **`final class`** (reference semantics). Mandatory for every `Element`-like / scene-graph type (`Element`, `Displayable`, `Path`, `Group`, `Animator`, …). Never `struct` for these — the graph relies on shared mutable identity.
- `extends` → `class Sub: Super`. `implements` / contract `interface` → `protocol`; shared method **bodies** go in a `protocol extension`.
- `interface` used as a plain data bag → `struct` (value data, no identity).

```swift
protocol DataFormatMixin: AnyObject { var seriesIndex: Int? { get } }
extension DataFormatMixin { func getDataParams(_ i: Int) -> …  { … } }   // default impl
```

> ⚠️ **Witness trap:** a concrete method with a *narrower* signature than the protocol requirement does NOT witness it — calls silently hit the nil-returning default. Match the protocol signature exactly. (See MEMORY: Swift protocol-witness trap.)

---

## 5. Adding a method to an existing type → `extension`, not a new type

To port a method onto an already-ported type, **add it in an `extension` of that type** (in a file named for its upstream source). Do not fork the class or wrap it.

```swift
// Ported from echarts/src/chart/helper/labelHelper.ts — keep in sync with upstream
extension SeriesData {
    func getName(_ idx: Int) -> String { … }
}
```

Mixins (`util.inherits` / `applyMixin`) → protocol + protocol-extension replicating the exact upstream method set; leave a `// PORT-TODO:` noting the mixin.

---

## 6. Canvas2D → `PathProxy` / seam protocols; never raw Core Graphics in `ZRenderKit`

Anything that would call a `CanvasRenderingContext2D` routes through `PathProxy` (build) and the seam protocols (`PathRebuilder`, `Renderer`/`Painter`). Subclasses emit geometry in `buildPath`:

```swift
override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
    let shape = shape as! CircleShape
    _ = ctx.arc(shape.cx, shape.cy, shape.r, 0, Double.pi * 2)
}
```

Do **not** invent `CGContext`/`CGPath` calls inside `ZRenderKit`. Leave `// PORT-TODO: backend wiring` at the paint seam; the native backend (`NativePainter`) is hand-written, not ported.

---

## 7. `number[]` / `Float32Array` → `ContiguousArray`; `number` → `Double`

- `number` → `Double` **always** (indices too; cast to `Int` only at the genuine subscript, math in `Double` first).
- `Float32Array`→`ContiguousArray<Float>`, `Float64Array`→`ContiguousArray<Double>`, `Int32Array`→`ContiguousArray<Int32>`, etc. Plain `T[]`→`[T]`.
- `number[] | Float32Array` buffer → `ContiguousArray<Double>` (+ `// PORT-TODO` if the typed/dynamic split is load-bearing).

> ⚠️ **O(n²) trap:** never write `concreteArray as? [Any?]` inside a per-datum loop — it copies all n elements each call. Bridge once. (See MEMORY: O(n²) data-init trap.)

---

## 8. `null` / `undefined` → `Optional`

`T | null` / `T | undefined` / `x?: T` → `T?`. `x == null` → `x == nil`; `x != null` → `x != nil`. Optional chaining `a?.b?.c()` ports verbatim. Collapse null and undefined to `nil` (they almost never differ; `// PORT-TODO` if a file truly depends on the distinction). Object truthy guard `if (x)` → `if let`/`!= nil`; numeric/string truthiness replicated explicitly (`x != 0 && !x.isNaN`, `!s.isEmpty`).

> ⚠️ **Int-vs-Double read trap:** `get(...) as? Double` returns nil on an Int-boxed option → value silently dropped. Use an Int/Double coercion helper. (See MEMORY.)

---

## 9. `const` object used as an enum → caseless enum of `static let`

A TS `const X = { A: 0, B: 1 }` used as a namespaced constant set → a caseless enum with matching names and values.

```ts
PathProxy.CMD = { M: 1, L: 2, C: 3, Q: 4, A: 5, Z: 6, R: 7 };
```
```swift
enum CMD { static let M = 1; static let L = 2; static let C = 3
           static let Q = 4; static let A = 5; static let Z = 6; static let R = 7 }
```

A genuine numeric/string TS `enum` → Swift `enum` with matching raw values. An untagged union (`string | PatternObject | …`) → a **tagged enum** with a case per arm (`ZRColor`, `LineDash`).

---

## 10. Out-param `out` → value-return (never `inout` for the math modules)

gl-matrix style `f(out, a, b)` mutates+returns `out`, and upstream **self-aliases** (`vec2.min(min, min, min2)`), which Swift exclusivity forbids. **Drop the out-param; return a new value.**

- vectors → `SIMD2<Double>` (`VectorArray`), returned by value.
- matrices → `[Double]` (6 elts, upstream indexing), returned by value.
- two outputs → tuple `(min:, max:)`; single scratch buffer → return the array.

```ts
vec2.add(this._pos, this._pos, delta);   // in-place upstream
```
```swift
self._pos = vector.add(self._pos, delta)  // out = f(a, b)
```

Store vectors/matrices as `var` value-type properties and mutate by **reassignment** — never expect a hidden-pointer mutation. If value-return genuinely can't reproduce upstream (perf hot buffer), stub `// PORT-TODO: out-param hazard, needs review`.

---

## 11. Faithful spelling map (quick reference)

`Math.min/max`→`Swift.min/max` · `Math.PI`→`Double.pi` · `Math.floor/ceil`→`floor/ceil` (→`Double`) · `Number.MAX_VALUE`→`Double.greatestFiniteMagnitude` · `Infinity`→`Double.infinity` · `isNaN(x)`→`x.isNaN` · `Double %`→`x.truncatingRemainder(dividingBy:)` · `===`→`==` (value) / `===` (class identity) · `` `${a}-${b}` ``→`"\(a)-\(b)"` · `hasOwnProperty(k)`→`dict[k] != nil` · `delete obj[k]`→`dict[k] = nil` · `instanceof`→`is`/`as?` · `get x()/set x()`→computed property · labeled `break lo:`→Swift labeled loop (same label). JS `switch` fall-through is explicit `break` in Swift; use `fallthrough` only where upstream omits `break`.

---

## 12. The one liability to hunt before debugging

A `// PORT-TODO: deferred` sitting where upstream calls 2–5 real lines is the #1 source of user-visible bugs (killed hover, drag, brush). The infra is almost always already ported — **grep the file for `PORT-TODO` first**, then wire the dormant call, before writing new code. Force-unwraps that "mirror upstream optimistic typing" are latent `SIGTRAP`s — port them as optionals with a guard, not `!`.

---

**Submit checklist:** header line 1 · names = upstream · order = upstream · Chinese comments preserved · `number`→`Double`, typed arrays→`ContiguousArray` · no math out-params (all value-return) · `Element`-types are `final class` · grepped-before-creating · every gap has `// PORT-TODO:`.
