# CONVENTIONS.md — Binding rulebook for the zrender/echarts → Swift port

This is a **faithful, line-by-line** port of Apache ECharts + ZRender (TypeScript) to
Swift. The single overriding goal is **structural fidelity to upstream** so we can diff a
ported Swift file against its `.ts` original and re-sync future upstream changes. When a
rule below trades elegance for faithfulness, **choose faithfulness**. Do not refactor,
rename, reorder, or "improve" upstream code.

These rules are **mandatory**. Every translator follows them verbatim.

---

## 0. File header & provenance (REQUIRED)

The very first line of **every** ported Swift file is a header comment naming its source:

```swift
// Ported from zrender/src/core/<File>.ts — keep in sync with upstream
```

(Use the real upstream path, e.g. `echarts/src/model/Series.ts`.)

- Preserve upstream **file names**, **identifier names**, and **code order** (declarations,
  functions, methods, cases — top to bottom, exactly as upstream).
- Keep meaningful upstream comments, **including the original Chinese comments** — copy them
  through unchanged. They are part of the diffable surface.
- Mark every skipped, stubbed, deferred, or uncertain piece with `// PORT-TODO: <why>`.
  Never silently drop code.

---

## 1. Primitive type mapping

| TypeScript | Swift |
|---|---|
| `number` | `Double` (always — even for things that look like ints, e.g. indices used in float math; see §7 for genuine integer loops) |
| `boolean` | `Bool` |
| `string` | `String` |
| `null` / `undefined` | `Optional` (`T?`); see §6 |
| `any` | avoid; use the most precise type you can, else `// PORT-TODO` and a concrete type |
| `T[]` / `Array<T>` | `[T]` |
| `Float32Array` | `ContiguousArray<Float>` |
| `Float64Array` | `ContiguousArray<Double>` |
| `Int32Array` / `Uint32Array` | `ContiguousArray<Int32>` / `ContiguousArray<UInt32>` |
| `Int8Array` / `Uint8Array` / `Uint8ClampedArray` | `ContiguousArray<Int8>` / `ContiguousArray<UInt8>` |
| `Int16Array` / `Uint16Array` | `ContiguousArray<Int16>` / `ContiguousArray<UInt16>` |
| `Record<string, T>` / `{ [k: string]: T }` | `[String: T]` |
| `ArrayLike<number>` | `[Double]` (or `SIMD2<Double>` where it is a 2-vector — see §3) |

Notes:
- zrender frequently types a buffer as `number[] | Float32Array`. Port as
  `ContiguousArray<Double>` and add `// PORT-TODO: upstream uses number[] | Float32Array`
  if the dynamic-vs-typed distinction is load-bearing for that file.
- `ContiguousArray` (not `[T]`) for the typed-array slots: it documents the
  fixed-element-type intent and avoids bridging overhead.

---

## 2. Module / class / namespace mapping

- **Free-function modules** (`vector.ts`, `matrix.ts`, `util.ts`, `bbox.ts`, `curve.ts`, …)
  → a **caseless `enum` namespace named exactly after the file**, so call sites stay
  identical to upstream:

  ```swift
  // Ported from zrender/src/core/vector.ts — keep in sync with upstream
  public enum vector {              // matches `import * as vec2 from './vector'`
      public static func create(_ x: Double? = nil, _ y: Double? = nil) -> VectorArray { ... }
  }
  ```

  Call sites: upstream `vec2.create()` → `vector.create()`, `matrix.mul(...)` →
  `matrix.mul(...)`. The enum has **no cases** (it is a pure namespace) and is never
  instantiated. Use the **file name** as the enum name (`vector`, `matrix`, `bbox`,
  `curve`, `util`), even though local imports alias it (`vec2`); add a one-line comment
  noting the upstream alias.
  - Lowercase enum names (`vector`, not `Vector`) are intentional — they keep call sites
    byte-identical to upstream and read as namespaces. Silence the linter, do not rename.
  - `export const length = len` style re-exports → `public static let length = len` (or a
    thin forwarding `static func`) so both names resolve.

- **TS `class`** → Swift **`final class`** (reference semantics). This is **REQUIRED** for
  every `Element`-like / scene-graph type (Element, Displayable, Path, Group, Eventful,
  Transformable, Animator, …). **Never** use `struct` for these — the scene graph relies on
  shared mutable identity and upstream mutates objects through aliases.
  - `extends` → `class Sub: Super`. `implements` / `interface` used as a contract →
    `protocol`. `interface` used as a plain data bag → `struct` (data, no identity) is OK.
  - `static` members → `static`. `private`/`protected` → `private`/`internal` (Swift has no
    `protected`; use `internal` and add `// upstream: protected`).
  - Mixins (`util.inherits` / applyMixin) → `// PORT-TODO` and replicate via protocol
    + protocol-extension or explicit forwarding; preserve the upstream method set.

- **`enum` (TS)**: numeric/string TS enums → Swift `enum` with matching raw values, or a
  caseless-enum of `static let` constants if upstream uses a `const` object as an enum
  (e.g. `PathProxy.CMD`). Keep the member names and values identical.

---

## 3. THE OUT-PARAM MUTATION HAZARD ⚠️ (read this twice)

zrender's math modules (`vector.ts`, `matrix.ts`, `bbox.ts`, parts of `curve.ts`) follow the
gl-matrix convention: the **first argument `out` is a caller-owned array that the function
mutates in place** and also returns:

```ts
export function add<T>(out: T, v1: VectorArray, v2: VectorArray): T {
    out[0] = v1[0] + v2[0];
    out[1] = v1[1] + v2[1];
    return out;
}
// caller relies on the mutation:
vec2.add(this.position, this.position, delta);   // this.position is updated IN PLACE
```

In Swift, **`Array` and `SIMD` are value types**. A naive `func add(_ out: [Double], ...)`
mutates a *copy*; the caller's array is untouched and the bug is **silent**. Worse, upstream
deliberately **aliases** `out` with a read argument:

```ts
vec2.min(min, min, min2);     // out === v1  (same array!)
matrix.mul(m, m2, m);         // out === m2
```

A faithful `inout [Double]` port of these **traps at compile/runtime** under Swift's
*exclusive access to memory* rules: you cannot pass `min` as `inout` while also reading
`min` for another parameter in the same call. So `inout` is **not** a viable uniform
strategy here.

### DECISION — mandatory, no exceptions

> **Strategy (b): value-returning. No math function ever mutates a caller-owned array
> through an out-parameter.**
>
> - **Vectors (`vector.ts`)** use **`SIMD2<Double>`** (`typealias VectorArray = SIMD2<Double>`).
>   Every function **returns a new `SIMD2<Double>`** instead of taking `out`.
> - **Matrices (`matrix.ts`)** use **`typealias MatrixArray = [Double]`** (6 elements,
>   same `[a,b,c,d,e,f]` order/indexing as upstream) and every function **returns a new
>   `[Double]`** instead of taking `out`. (We keep `[Double]` rather than a SIMD matrix so
>   `m[0]…m[5]` indexing stays byte-identical to upstream; value-return already removes the
>   aliasing hazard, so no `inout` is needed.)
> - **Multi-output functions** (e.g. `bbox.fromLine(..., min, max)` writes *two* arrays)
>   **return a tuple** `(min: SIMD2<Double>, max: SIMD2<Double>)`.
> - **Single scratch-array outputs** (e.g. `curve.cubicSubdivide(..., out)` fills one array)
>   **return that array** (`-> [Double]`).

**Why (b) and not (a) `inout [Double]`:** the self-aliasing calls above
(`vec2.min(min, min, min2)`, `matrix.mul(m, m2, m)`) are pervasive in upstream and violate
Swift's exclusivity enforcement, which would force per-call-site rewrites *anyway*. Given we
must touch those call sites regardless, value-returning is the choice that is **both** Swift-
safe **and** keeps the transformation **mechanical and diffable**: every `f(out, a, b)`
becomes `out = f(a, b)`. `SIMD2<Double>` additionally gives correct value semantics, fast
math, and free `+ - * /` should we want them — while still supporting `v[0]` / `v[1]`
subscripting so the function bodies stay line-for-line faithful.

### Concrete before/after — `vec2.add` (copy this pattern)

**Upstream `vector.ts`:**
```ts
export function add<T extends VectorArray>(out: T, v1: VectorArray, v2: VectorArray): T {
    out[0] = v1[0] + v2[0];
    out[1] = v1[1] + v2[1];
    return out;
}
```

**Ported `vector.swift`:**
```swift
// Ported from zrender/src/core/vector.ts — keep in sync with upstream
import simd

public typealias VectorArray = SIMD2<Double>

public enum vector {   // upstream alias: `vec2`

    /// 向量相加 (was: add(out, v1, v2) — out-param dropped, value-returning per CONVENTIONS §3)
    public static func add(_ v1: VectorArray, _ v2: VectorArray) -> VectorArray {
        var out = VectorArray()
        out[0] = v1[0] + v2[0]
        out[1] = v1[1] + v2[1]
        return out
    }
}
```

**Call-site transformation (mechanical):**
```ts
vec2.add(this._position, this._position, delta);   // upstream, in-place
vec2.min(min, min, min2);                           // upstream, self-aliased
```
```swift
self._position = vector.add(self._position, delta)  // assign the returned value
min = vector.min(min, min2)                          // aliasing hazard gone
```

`copy(out, v)` / `set(out, a, b)` style helpers become value-returning too
(`copy(_ v) -> VectorArray` returning `v`, `set(_ a, _ b) -> VectorArray`); at call sites
`vec2.copy(dst, src)` → `dst = vector.copy(src)`.

### Same pattern for `matrix.ts` and `bbox.ts`

```swift
// matrix: out-param dropped, returns new [Double]
// upstream: export function mul(out, m1, m2): MatrixArray
public static func mul(_ m1: MatrixArray, _ m2: MatrixArray) -> MatrixArray {
    var out = MatrixArray(repeating: 0, count: 6)
    let out0 = m1[0] * m2[0] + m1[2] * m2[1]
    // ... (body unchanged, line-for-line) ...
    out[5] = m1[1] * m2[4] + m1[3] * m2[5] + m1[5]
    return out
}
// call site: matrix.mul(m, m2, m)  →  m = matrix.mul(m2, m)
```

```swift
// bbox: two outputs → tuple
// upstream: export function fromLine(x0,y0,x1,y1, min, max)
public static func fromLine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double)
    -> (min: VectorArray, max: VectorArray) {
    var min = VectorArray(), max = VectorArray()
    min[0] = Swift.min(x0, x1); min[1] = Swift.min(y0, y1)
    max[0] = Swift.max(x0, x1); max[1] = Swift.max(y0, y1)
    return (min, max)
}
// call site: fromLine(xi, yi, x, y, min2, max2)  →  (min2, max2) = bbox.fromLine(xi, yi, x, y)
```

> If you hit a math function where value-returning genuinely cannot reproduce upstream
> behavior (e.g. a perf-critical hot loop that must write through a shared buffer), **do not
> improvise** — stub with `// PORT-TODO: out-param hazard, needs review` and flag it.

---

## 4. `Element`-like types & shared mutable state

- Everything in the scene graph (`Element`, `Displayable`, `Path`, `Image`, `Text`,
  `Group`, `Eventful`, `Animator`, `Transformable`, `Storage` entries) is a **`final class`**.
- A vector/matrix *stored on* such an object is just a `var` property of value type
  (`var _position: VectorArray`); mutate it by **reassignment** (`self._position = vector.add(...)`),
  per §3. Never expect a `vector.*` call to mutate it through a hidden pointer.
- TS object-literal "options"/"props" bags (e.g. `PathStyleProps`) → Swift `struct` (value
  data, no identity) **unless** upstream relies on identity/aliasing for that bag, in which
  case `final class`. When unsure, `final class` + `// PORT-TODO: confirm value vs ref`.

---

## 5. `Math.*`, bitwise, and numeric ops

| TypeScript | Swift |
|---|---|
| `Math.min/max` | `Swift.min` / `Swift.max` (qualify `Swift.` inside a type named `min`/`max` or the `vector` enum) |
| `Math.abs` | `Swift.abs` / `abs` |
| `Math.sqrt/pow/sin/cos/tan/atan2/...` | `Foundation` free functions `sqrt`, `pow`, `sin`, `cos`, `tan`, `atan2`, … (all `Double`) |
| `Math.round` | `(x).rounded()` (banker's? no — JS `Math.round` rounds half **up**; use `(x).rounded(.toNearestOrAwayFromZero)` only if sign-correct, else replicate `floor(x + 0.5)`; add `// PORT-TODO` if edge cases matter) |
| `Math.floor/ceil` | `floor(x)` / `ceil(x)` (return `Double`; cast to `Int` only at genuine index use) |
| `Math.PI` | `Double.pi` |
| `Math.max(...arr)` | `arr.max()!` (guard empties as upstream does) |
| `Number.MAX_VALUE` | `Double.greatestFiniteMagnitude` |
| `Infinity` / `-Infinity` | `Double.infinity` / `-Double.infinity` |
| `NaN`, `isNaN(x)` | `Double.nan`, `x.isNaN` |
| `x | 0`, `~~x` (truncate) | `Double(Int(x))` truncation — but keep the value as `Double`; `// PORT-TODO` if used as a fast floor on negatives |
| `a & b`, `a | b`, `a ^ b`, `~a`, `<<`, `>>`, `>>>` | operate on `Int`/`UInt32`; convert `Double`↔`Int` explicitly at the boundary, then back if upstream keeps it numeric |
| `a ?? b` (nullish) | `a ?? b` |
| `a && b` returning a value | rewrite to explicit `if`/optional logic; do not abuse Swift `&&` (Bool only) |
| `+x` (string→number) | `Double(x) ?? 0` with `// PORT-TODO` on the fallback |

**Integer division hazard:** JS `/` is always float; `5 / 2 === 2.5`. In Swift, `5 / 2 == 2`
for `Int`. Since all `number` → `Double` (§1), arithmetic stays float **as long as operands
are `Double`**. When you cast to `Int` for indexing, **do the math in `Double` first, cast
last**. Never let an intermediate silently become `Int`.

**`%` (modulo):** JS `%` is truncated remainder and works on floats. Swift `%` does **not**
work on `Double`; use `a.truncatingRemainder(dividingBy: b)`. For ints, Swift `%` matches JS
sign behavior. Watch negatives (JS and Swift both truncate toward zero — usually fine).

---

## 6. `null` / `undefined` → Optional

- `T | null` / `T | undefined` / optional property `x?: T` → `T?`.
- `x == null` (JS, catches both null and undefined) → `x == nil`.
- `x != null` → `x != nil`. Truthy guards (`if (x)`) on objects → `if let`/`x != nil`; on
  numbers/strings, replicate JS truthiness explicitly (`x != 0 && !x.isNaN`, `!s.isEmpty`)
  with a `// PORT-TODO` if the truthiness is subtle.
- Default-param `function f(a = 0)` → `func f(_ a: Double = 0)`.
- `obj?.prop?.method()` (optional chaining) → `obj?.prop?.method()`.
- Distinguishing `null` from `undefined` is almost never semantically required; collapse
  both to `nil`. If a file genuinely depends on the difference, `// PORT-TODO`.

---

## 7. Loops, indices, and control flow

- `for (let i = 0; i < n; i++)` → `for i in 0..<n` where possible; keep C-style
  (`var i = 0; while i < n { ...; i += 1 }`) when the body mutates `i` (very common in
  `PathProxy` command walking — keep it faithful, do not "clean up").
- Loop/index variables that index arrays are genuine `Int`. Convert at the boundary; keep
  the math in `Double` per §5.
- `break label:` / `continue label:` (JS labeled loops, e.g. `lo:` in `PathProxy.rebuildPath`)
  → Swift labeled loops (`lo: while ... { break lo }`). Same label names.
- `switch` with fallthrough: JS `switch` falls through without `break`; Swift does **not**.
  Replicate explicit `break`s as `case` boundaries; use Swift `fallthrough` only where
  upstream intentionally omits `break`.
- `arguments` object (e.g. `PathProxy.addData` uses `arguments.length`) → Swift variadic
  `_ args: Double...` or an explicit fixed-arg overload; preserve behavior, `// PORT-TODO`
  if variadic semantics differ.

---

## 8. Misc faithful mappings

- `===`/`!==` → `==`/`!=` (Swift `==` on value types is value equality; for class identity
  use `===` only where upstream means reference identity).
- Template literals `` `${a}-${b}` `` → `"\(a)-\(b)"`.
- `Array.prototype.slice/push/splice/indexOf/forEach/map/filter/reduce` → Swift
  `Array` equivalents (`dropFirst`/subranges, `append`, `remove`, `firstIndex(of:)`,
  `forEach`, `map`, `filter`, `reduce`). Keep callback order/semantics.
- `obj.hasOwnProperty(k)` → `dict[k] != nil`.
- `delete obj[k]` → `dict[k] = nil`.
- `typeof x === 'function'` / duck typing → model with protocols/closures; `// PORT-TODO`
  when upstream does runtime feature detection (e.g. `typeof Float32Array !== 'undefined'`)
  — pick the Swift-true branch and note the dropped branch.
- `instanceof` → `is` / `as?`.
- Getters/setters (`get x()`/`set x()`) → Swift computed properties.
- Closures capturing `this` → capture `self`; mind retain cycles (`[weak self]`) **only**
  where a cycle is real (event listeners, animators). Add `// PORT-TODO: verify capture`.

---

## 9. Renderer seam (do not translate the canvas backend)

zrender's `CanvasPainter`/`Layer`/`SVGPainter` are **not** ported faithfully. The native
backend (`NativePainter`) is hand-written against the seam protocols in `ZRenderKit`:
- `PathRebuilder` (`Sources/ZRenderKit/Core/PathRebuilder.swift`) — the consumer interface
  of `PathProxy.rebuildPath`. Anything that consumes path commands conforms to it.
- `Renderer` / `Painter` (`Sources/NativePainter`) — the ~8 paint ops.

When you port a file that would call into a `CanvasRenderingContext2D`, route it through
these protocols and leave `// PORT-TODO` for backend wiring. Do **not** invent Core Graphics
calls inside `ZRenderKit`.

---

## 10. Checklist before you submit a ported file

- [ ] Header comment `// Ported from <upstream path> — keep in sync with upstream` on line 1.
- [ ] Identifier names, file name, and declaration order match upstream.
- [ ] Upstream comments (incl. Chinese) preserved.
- [ ] `number` → `Double`; typed arrays → `ContiguousArray<…>`.
- [ ] No math function takes an out-param; all are value-returning per §3.
- [ ] All `Element`-like types are `final class`.
- [ ] `Math.*`, `%`, bitwise, and integer-division boundaries handled per §5.
- [ ] Every skipped/uncertain spot has a `// PORT-TODO:`.
