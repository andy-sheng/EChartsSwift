# PORT_STATUS.md — ECharts/ZRender → Swift port

**Phase 4 (INTERACTION-COMPLETE → zrender DONE: Handler hit-test/dispatch/bubble + core/event normalization + GestureMgr pinch + Draggable + Element Eventful wiring + the hand-written UIKit/AppKit HandlerProxy bridge & ZRenderView host): COMPLETE — clean from-scratch `swift build` green (all 88 units, 0 errors), `swift test` 65 executed / 0 failures / 14 skipped (the new InteractionSmokeTests).** See §§18–22. **zrender is now COMPLETE — rendering + animation + interaction all ported; canvas/svg/dom are intentionally replaced by NativePainter. The port now advances to the ECharts layer (§22).**
**Phase 3 (LOGIC-COMPLETE: real Animator/Animation/Clip/easing + CADisplayLink host loop + path tools path/transformPath/dividePath/morphPath/convertPath + tool/color completion + Element/ZRender animation wiring): COMPLETE — `swift build` green, 61 tests / 0 failures / 16 skipped.** See §§13–17. **zrender is now logic-complete (rendering + animation + path tools); the only remaining zrender work is Phase 4 = interaction (Handler/event/GestureMgr → UIKit).**
**Phase 2 (Text/TSpan/Image + contain/* hit-testing + 10 remaining shapes + gradient/pattern/text/image paint + Storage display list + ZRender host facade): COMPLETE — `swift build --build-tests` green, 50 tests / 0 failures / 13 skipped.** See §§7–11.
**Phase 1 (scene graph + shape layer + first real NativePainter): COMPLETE — build green, all goldens pass.**
**Phase 0 (Core scaffold + math/geometry foundation): COMPLETE (its lone blocker is now resolved).**

This document records what landed per phase, the per-file status, the deduped fix-up
backlog (sorted blockers/severity-first), the next-phase plan, and the standing upstream-sync
rule. It is the single source of truth for "where the port is" — read it before starting Phase 3.
The Phase 2 plan (§5) is preserved verbatim as the historical brief; its execution results are in §§7–11.
Phase 0 history is preserved verbatim near the bottom (§§P0-1…P0-3); do not delete it.

Project root: `/Volumes/EXT-Storage/Developer/iOS-Chart`
Rulebook: `CONVENTIONS.md` (faithful, line-by-line, diffable-against-upstream port).

---

## 1. What landed in Phase 1 — checklist

**Goal (met):** translate the scene-graph + shape layer so a *hand-built* `Group`/`Path` tree
renders on iOS/macOS through a real `CALayerPainter`, validated against the golden fixtures with
**true geometry parity** (Swift `Shape.buildPath` output, not just replayed PathProxy `d`-strings).

### Scene graph & display types (`Sources/ZRenderKit/`)
- [x] `Element.swift` ← `zrender/src/Element.ts` — keystone scene-graph base (`final class`).
      Transform/clip/parent surface ported; **states, emphasis/blur/select, animation, ZRText
      inner-text, and the Eventful mixin are faithfully scaffolded but stubbed** (`// PORT-TODO`,
      Phase 2/3). Forward-declares placeholders for `ZRenderType`, `ZRText`, `Polyline`.
- [x] `Graphic/Displayable.swift` ← `graphic/Displayable.ts` — `Displayable extends Element`;
      the paintable surface (style bag, z/z2/zlevel, invisible, getBoundingRect/contain hooks).
      `STYLE_MAGIC_KEY` dynamic stamp replaced by a typed flag (`// PORT-TODO`).
- [x] `Graphic/Group.swift` ← `graphic/Group.ts` — child list, add/remove/eachChild/traverse,
      `getBoundingRect` over children.
- [x] `Graphic/Path.swift` ← `graphic/Path.ts` — where shapes meet `PathProxy`: owns a `PathProxy`,
      `getUpdatedPathProxy`/`buildPath`/`getBoundingRect` (routes through `bbox`), style/shape
      setters. `contain`/`containStroke` hit-test routes to `contain/path` = **Phase 2 stub**.

### 6 shapes (`Sources/ZRenderKit/Graphic/Shape/`)
- [x] `Rect.swift` ← `graphic/shape/Rect.ts` (RectRadius union `number | number[]`, roundRect helper)
- [x] `Circle.swift` ← `graphic/shape/Circle.ts`
- [x] `Sector.swift` ← `graphic/shape/Sector.ts` (cornerRadius via roundSector helper)
- [x] `Arc.swift` ← `graphic/shape/Arc.ts`
- [x] `BezierCurve.swift` ← `graphic/shape/BezierCurve.ts` (quadratic/cubic branch on cp2)
- [x] `Polygon.swift` ← `graphic/shape/Polygon.ts` (poly/smoothBezier helpers)

### Shape `buildPath` helpers (`Sources/ZRenderKit/Graphic/Helper/`)
- [x] `poly.swift`, `roundRect.swift`, `roundSector.swift`, `smoothBezier.swift`, `subPixelOptimize.swift`
      ← `graphic/helper/*.ts` (all emit into `PathProxy`).

### Foundations pulled in on demand
- [x] `Core/Eventful.swift` ← `core/Eventful.ts` — on/off/trigger event bus (closure-identity dedup
      and `zrEventfulCallAtLast` flag are `// PORT-TODO`; not yet wired into Element).
- [x] `Animation/Animator.swift` ← `animation/Animator.ts` — **type surface only**; every body is a
      `// PORT-TODO` (real tween/Clip/Track = Phase 3). Element/Path reference the type, do not drive it.
- [x] `Animation/easing.swift` ← `animation/easing.ts` — table stubbed (Phase 3).
- [x] `Tool/color.swift` ← `tool/color.ts` — parse/rgba/stringify/fastLerp ported; `lerp`/`modifyHSL`/
      `liftColor` need `isFunction`/`GradientObject`/`isString` = `// PORT-TODO`.
- [x] `Graphic/Gradient.swift`, `LinearGradient.swift`, `RadialGradient.swift`, `Pattern.swift`
      ← `graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.ts` — **data types only**; the
      canvas/image backend fields (`__canvasGradient`, `ImageLike`, `SVGVNode`) are `// PORT-TODO`.
- [x] `Graphic/constants.swift` ← `graphic/constants.ts`; `config.swift` ← `config.ts`
      (browser-only `devicePixelRatio` is `// PORT-TODO`).
- [x] `Core/util.swift` — extended on demand for the above (per Phase-0 §P0-3.15).

### First real NativePainter (`Sources/NativePainter/`, hand-written, not a translation)
- [x] `CALayerPainter.swift` — `Painter` over a root `CALayer`; `renderToImage(group:size:dpr:)`
      walks the `Group`, paints each `Path` displayable. **Text/Image/TSpan = `// PORT-TODO` (Phase 2).**
- [x] `CGRenderer.swift` — `Renderer`: fillPath/strokePath/transform/opacity/shadow/setClip via
      `CGContext`. **Gradient & pattern paint resolve to `nil` = `// PORT-TODO`; `drawText` = Phase 2;
      even-odd fill rule never selected; line-cap/join keyword presets unresolved.**
- [x] `CGPathRebuilder.swift` — `PathRebuilder` consumer that converts `PathProxy.rebuildPath`
      commands into a `CGMutablePath` (M/L/C/Q/A/Z/R).
- [x] `Renderer.swift` — seam protocols (carried from Phase 0, now exercised).

### Golden tests — true geometry parity (`Tests/ZRenderKitTests/`)
- [x] `GoldenTests.swift` — the old compiled-out `#if PORT_TODO_GOLDEN` stub is now a **real
      data-driven test**: `testSwiftBuildPathMatchesOracle` instantiates each ported `…Shape`,
      sets it on the ported `Path` subclass, builds via `path.getUpdatedPathProxy(false)`, replays
      through `GoldenPathRebuilder`, and asserts the canonical `d` == fixture `rebuiltD` byte-for-byte
      (6 fixtures, each its own diff-carrying assertion).
- [x] `CALayerPainterSmokeTests` (guarded `#if canImport(QuartzCore) && canImport(CoreGraphics)`) —
      builds `Group{Rect,Circle,Sector}` and asserts `renderToImage` returns a non-nil 200×150 CGImage.
- [x] `Package.swift` — `NativePainter` added to the `ZRenderKitTests` test target deps. No other
      Package change needed (default `Sources/<target>/**` globbing picked up all new subdirectories).

---

## 2. Phase 1 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Blocking note |
|---|---|---|---|---|
| `Element.swift` | `Element.ts` | partial (render surface) | minor-issues (1) | states/animation/Eventful/ZRText stubbed `// PORT-TODO` |
| `Graphic/Displayable.swift` | `graphic/Displayable.ts` | partial | **major-issues (1)** | `STYLE_MAGIC_KEY` dynamic-stamp divergence + deferred state/style surface |
| `Graphic/Group.swift` | `graphic/Group.ts` | complete | minor-issues (1) | `children()` returns a value-type COPY, not a live ref; cb-`this` binding |
| `Graphic/Path.swift` | `graphic/Path.ts` | partial | minor-issues (1) | `contain`/`containStroke` + decal + per-key setShape stubbed |
| `Graphic/Shape/Rect.swift` | `graphic/shape/Rect.ts` | complete | minor-issues (1) | RectRadius union modeling |
| `Graphic/Shape/Circle.swift` | `graphic/shape/Circle.ts` | complete | faithful | — |
| `Graphic/Shape/Sector.swift` | `graphic/shape/Sector.ts` | complete | faithful | — |
| `Graphic/Shape/Arc.swift` | `graphic/shape/Arc.ts` | complete | faithful | — |
| `Graphic/Shape/BezierCurve.swift` | `graphic/shape/BezierCurve.ts` | complete | faithful | — |
| `Graphic/Shape/Polygon.swift` | `graphic/shape/Polygon.ts` | complete | faithful | — |
| `Graphic/Helper/{poly,roundRect,roundSector,smoothBezier,subPixelOptimize}.swift` | `graphic/helper/*.ts` | complete | (folded into shape review) | minor `// PORT-TODO`s (structural-type→protocol, `Math.round` half-up) |
| `Core/Eventful.swift` | `core/Eventful.ts` | complete | (foundation sweep) | closure-identity dedup + `zrEventfulCallAtLast` stubbed; not wired to Element |
| `Animation/Animator.swift` | `animation/Animator.ts` | **type-surface stub** | (foundation sweep) | every body `// PORT-TODO` (Phase 3) |
| `Animation/easing.swift` | `animation/easing.ts` | stub | (foundation sweep) | easing table deferred (Phase 3) |
| `Tool/color.swift` | `tool/color.ts` | partial | (foundation sweep) | `lerp`/`modifyHSL`/`liftColor` deferred (need util guards + Gradient) |
| `Graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.swift` | `graphic/*.ts` | data-types only | (foundation sweep) | backend image/canvas/svg fields `// PORT-TODO` |
| `Graphic/constants.swift`, `config.swift` | `graphic/constants.ts`, `config.ts` | complete | (foundation sweep) | `devicePixelRatio` browser-only `// PORT-TODO` |
| `NativePainter/CALayerPainter.swift` | (hand-written, §9) | complete (Path only) | n/a (not a translation) | Text/Image/TSpan unpainted |
| `NativePainter/CGRenderer.swift` | (hand-written, §9) | complete (fill/stroke) | n/a | gradient/pattern/text paint = `// PORT-TODO` |
| `NativePainter/CGPathRebuilder.swift` | (hand-written, §9) | complete | n/a | — |

Roll-up (ported `.ts` mirrors with a review verdict): **5 faithful, 5 minor-issues, 1 major-issues.**
The Animation/Tool/Gradient/Pattern foundations were landed via the on-demand foundation sweep and
are intentionally type-surface/partial (each gap is `// PORT-TODO`-marked).

---

## 3. Build & test status — Phase 1

- **Build: GREEN.** A clean build (`rm -rf .build && swift build`) compiled all four targets
  (`ZRenderKit`, `NativePainter`, `EChartsKit`, `ZRenderKitTests`) on the first attempt, with **no
  fixes required**. SwiftPM default `Sources/<target>/**` globbing picked up the new `Graphic`,
  `Graphic/Shape`, `Graphic/Helper`, `Animation`, and `Tool` subdirectories automatically.
- **`swift test`: GREEN.** `Executed 5 tests, 0 failures` (≈1.12 s build, 0.010 s run). The suite-level
  "5 tests" includes `testSwiftBuildPathMatchesOracle` (6 per-fixture parity assertions in one method),
  the painter smoke test, and the still-green Phase-0 `testRebuiltDMatchesOracle` + `testAllFixturesLoad`.
- **True geometry parity: 6/6 PASS, 0 FAIL** —

  | Fixture | Swift `Shape.buildPath` `d` == oracle `rebuiltD` |
  |---|---|
  | `rect` | PASS |
  | `circle` | PASS |
  | `sector` | PASS |
  | `arc` | PASS |
  | `bezier-curve` | PASS |
  | `polygon` | PASS |

  No code under `Sources/ZRenderKit` was modified to achieve parity — the ported shapes produced exact
  byte-for-byte output. `CALayerPainterSmokeTests.testRenderToImageProducesImage` also passes.
- **Phase-0 blocker RESOLVED:** `bbox.fromCubic`/`cubicExtrema` (old §P0-3 blocker #1) compiles cleanly;
  `Path.getBoundingRect` routes through it and `swift test` compiles end-to-end.

### Second oracle: ported zrender unit tests (behavioral)

Per the standing rule, the matching upstream Jest specs (`upstream/zrender/test/ut/spec/`) for
already-translated modules were ported to XCTest under `Tests/ZRenderKitTests/unit/`
(`Matrix`, `LRU`, `Util`, `Platform`, `Path`, `Group`). These complement the golden geometry
fixtures with unit-level behavior (matrix pivot-rotate, Path/Displayable default style values,
LRU eviction, Group iteration order, platform measureText).

- **`swift test`: 44 tests, 0 failures, 12 skipped.** No `Sources/` changes were needed — every
  non-skipped assertion matched upstream.
- **Skips** preserve intent for not-yet-ported surfaces: Path `setStyle`/`setShape` partial-merge
  and the states machinery (Phase-2 stubs), and JS-only semantics (`clone` of Date/TypedArray/class,
  callback-`this` binding) that don't map to Swift value types.
- **One real faithfulness gap found** (see §4): `util.merge` drops upstream's null/undefined guard.
- Specs deferred until their modules land: `tool/color` (color partial → Phase 3), `contain/Sector`
  + `graphic/{Image,Text}` (Phase 2), `animation/ElementAnimation` (Phase 3).

---

## 4. Phase 1 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — sign-off needed before it spreads
1. **`Displayable` `STYLE_MAGIC_KEY` divergence (major-issues review).** Upstream stamps style objects
   with a random dynamic key (`'__zr_style_' + round(random*10)`) to detect "is this a style bag".
   The port replaces it with a static typed flag. Audit every place that consumes the magic key
   (style merging, `useStyle`, state style application in Phase 2) before relying on it.

### Correctness / fidelity — review-flagged, fix opportunistically
2. **`Group.children()` returns a value-type COPY, not a live reference** (`Group.swift:55`). Upstream
   `_children` is a live array; mutating the returned array upstream mutates the group. Callers that
   expect to mutate children through the returned handle get a silent no-op. Audit Phase-2 callers.
3. **Group `eachChild`/`traverse` callback `this`-binding** is dropped (Swift closures capture). The
   `context` argument is passed but not bound as `this`; and `cb` `boolean | void` is modeled as `-> Bool`.
4. **`color.swift` partials:** `lerp` / `mapToColor` / `modifyHSL` / `liftColor` are unported (need
   `util.isFunction`/`isString`, `GradientObject`, and TS function-overload modeling). Number→String
   fidelity (`toFixed`/exponential) is a narrow subset. Any gradient color stop or HSL tween needs these.
5. **`subPixelOptimize` `Math.round` half-up** vs Swift `.rounded()` (banker's). Replicate `floor(x+0.5)`
   if pixel-snapping parity matters.
6. **`Element` `setTextConfig`/`updateInnerText` no-op** — ZRText inner-text layout is deferred; any
   label-bearing element renders without its text in Phase 1.
7. **`util.merge` drops upstream's null/undefined guard** (found by the ported `util` unit test).
   Upstream begins `if (!isObject(source) || !isObject(target)) return overwrite ? clone(source) : target;`
   so `merge(null,x)→null`, `merge(x,undefined)→x`, etc. The Swift signature
   `merge(_ target: inout [String:Any], _ source: [String:Any], _ overwrite: Bool)` (`util.swift:104`) is
   non-optional on both sides and omits the guard — the null/undefined cases are inexpressible. Inherent to
   the chosen signature; low risk under current geometry-layer usage, but a genuine divergence. Revisit when
   the option-merge layer (echarts `model/`) needs faithful deep-merge of absent/`null` config.

### Stubbed surfaces — whole features deferred (each is `// PORT-TODO`)
7. **Text / TSpan / Image** not ported at all. `graphic/Text.ts`, `graphic/TSpan.ts`, `graphic/Image.ts`,
   `Element.updateInnerText`, and `CGRenderer.drawText` are stubs. → Phase 2.
8. **Hit-testing (`contain/*`)** not ported. `Path.contain`/`containStroke` and `Displayable.contain`
   route to `contain/path`/`contain/text` which do not exist yet. → Phase 2.
9. **States / emphasis / blur / select / hover-layer** machinery stubbed across `Element` and `Path`
   (`saveCurrentToNormalState`, `useState`, `setState`, `ensureState`, `_mergeStates`). → Phase 2.
10. **Animation** is a type-surface stub only: `Animator` bodies, `easing` table, `animation/Animation.ts`,
    `animation/Clip.ts`, `animation/Track`, and every `Element`/`Path` `animateTo`/`animate`/`stopAnimation`
    path is `// PORT-TODO`. → Phase 3.
11. **Gradient / pattern rendering** in the painter resolves to `nil` paint (only solid `fill`/`stroke`
    paint). `CGRenderer` gradient/pattern/even-odd/line-keyword resolution + the `Gradient`/`Pattern`
    backend image fields are deferred. → Phase 2.
12. **Remaining shapes:** `Polyline.ts`, `Line.ts`, `Ring.ts`, `Ellipse.ts`, `Heart`, `Droplet`, `Rose`,
    `Trochoid`, `Isogon`, `Star`, etc. not yet ported. `Polyline` is a forward-declared placeholder used
    by `Element`. → Phase 2.
13. **`Eventful` not wired into `Element`** (the mixin forwarding is a `// PORT-TODO`); closure-identity
    dedup + `zrEventfulCallAtLast` ordering unmodeled. Needed once the `Handler`/event plumbing lands.
14. **`Path` per-key `setShape(key, value)`** and the dynamic dict-merge of a partial shape into a typed
    `PathShape` struct require reflection / subclass support — only whole-shape `setShape` works today.
15. **`config.devicePixelRatio`** is browser-only; wire to screen scale when the painter gains a real host.

> Carry-over from Phase 0 (§P0-3): the `Swift.min/max` NaN-non-propagation policy (item 2), `|| 0`-vs-`?? 0`
> NaN handling (item 3), `env`/`WeakMap`/`LRU`/`platform.measureText` notes — all still open, all still
> low-risk under "finite-coords-only" usage; revisit when wiring real input/measurement.

---

## 5. Phase 2 plan (HISTORICAL — executed; results in §§7–11) — Text/Image + hit-testing + remaining shapes + gradient/pattern paint + host facade

**Goal:** a label-bearing, hit-testable, gradient-capable render path; a `Storage` display list; and a
minimal `ZRender` host facade that ties `Storage` + `Painter` + `Element` tree together — so a chart's
graphic primitives (not yet the chart layer) round-trip from a hand-built tree to pixels with text.

### 5a. Text / TSpan / Image (`zrender/src/graphic/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `graphic/Text.ts` (ZRText) | `Graphic/Text.swift` | `Displayable`, `Element` (inner-text hooks already stubbed), `platform.measureText`, `BoundingRect` |
| `graphic/TSpan.ts` | `Graphic/TSpan.swift` | `Displayable`, `platform` |
| `graphic/Image.ts` | `Graphic/Image.swift` | `Displayable`, `platform` (ImageLike seam — needs a native image type) |
| `core/text.ts` (`parsePercent`, font parse, line layout) | `Core/text.swift` | `platform`, `BoundingRect`, `util`, `LRU` |
| then: `CGRenderer.drawText` + `CALayerPainter` Text/Image painting | NativePainter | Core Text run from the resolved `TextStyle`; image draw from a native CGImage |

### 5b. Hit-testing (`zrender/src/contain/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `contain/path.ts` | `Contain/path.swift` | `PathProxy`, `curve`, `windingLine` |
| `contain/line.ts`, `contain/quadratic.ts`, `contain/cubic.ts`, `contain/arc.ts`, `contain/util.ts` | `Contain/*.swift` | `curve`, `vector` |
| `contain/text.ts` | `Contain/text.swift` | `Core/text.swift` (5a), `BoundingRect` |
| then: wire `Path.contain`/`containStroke` + `Displayable.contain` (stubs today) to the above. |

### 5c. Remaining shapes (`zrender/src/graphic/shape/`)
`Polyline.ts` (unblocks the `Element` placeholder), `Line.ts`, `Ring.ts`, `Ellipse.ts`, then the rest.
**All depend on `PathProxy` + `Path` (Phase 1) + the helpers in `Graphic/Helper/`.**

### 5d. Gradient / pattern paint in `CALayerPainter`/`CGRenderer`
Resolve `LinearGradientObject`/`RadialGradientObject` → `CGGradient` (with `colorStops`), and
`PatternObject` → a tiled `CGImage` paint. Select even-odd vs nonzero fill rule; resolve line-cap/join
keyword presets. **Deps already ported:** `Graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.swift`
(data types), `Tool/color.swift` (after 5a-adjacent `color` completions for stops).

### 5e. `Storage` + display list (`zrender/src/Storage.ts`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `Storage.ts` | `Storage.swift` | `Element`, `Group`, `Displayable`, `util` (the z/z2/zlevel sort) |

Builds the flattened, sorted display list the painter consumes (replacing the current ad-hoc Group walk
in `CALayerPainter`).

### 5f. `ZRender` host facade (`zrender/src/zrender.ts`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `zrender.ts` (`ZRender` / `init` / `add`/`remove`/`refresh`) | `ZRender.swift` | `Storage` (5e), `NativePainter.Painter`, `Element`, `Animation` (stub surface) |

Replaces the `ZRenderType` forward-declaration placeholder in `Element.swift` with the real type
(`__zr`, `addAnimator`/`removeAnimator` hooks — animation bodies stay Phase-3 stubs). `Eventful` →
`Handler` event plumbing can be wired here.

**Sequencing note:** 5a (Text/`core/text`) unblocks 5b's `contain/text` and the `Element` inner-text
stub; 5e (`Storage`) precedes 5f (`ZRender`). Animation stays a Phase-3 deferral throughout.

---

## 7. What landed in Phase 2 — checklist

**Goal (met):** a label-bearing, hit-testable, gradient/pattern-capable render path; a flattened/sorted
`Storage` display list; and a minimal `ZRender` host facade tying `Storage` + `Painter` + `Element`
tree together. A hand-built `Group` tree of paths/text/images now round-trips to pixels, with the
four ECharts-expressible new shapes (ellipse/ring/line/polyline) validated byte-for-byte against the
ECharts oracle and the six decorative zrender-only shapes smoke-tested NaN-free.

### Text / TSpan / Image (`Sources/ZRenderKit/Graphic/`)
- [x] `Graphic/Text.swift` ← `graphic/Text.ts` (ZRText) — rich-text layout host, background/border
      rendering, per-token placement, `_updatePlainTexts`/`_placeToken`/`_renderBackground`. **Empty-string
      color truthiness + `parseFontSize` numeric-coercion + `'fill'/'stroke' in style` existence-vs-`!=nil`
      diverge on degenerate/explicit-null inputs (see §9); states-driven rich-style merge waits on Phase-3
      `useState`.**
- [x] `Graphic/TSpan.swift` ← `graphic/TSpan.ts` — single positioned text run (the paint unit).
- [x] `Graphic/Image.swift` ← `graphic/Image.ts` — `ZRImage`; `_getSize` width/height/aspect math faithful
      (verified by ported `ImageUnitTests`). Native image decode = file path / `data:` URI only.
- [x] `Graphic/CompoundPath.swift` ← `graphic/CompoundPath.ts`, `Graphic/IncrementalDisplayable.swift`
      ← `graphic/IncrementalDisplayable.ts` — pulled in as composite displayables.

### Hit-testing (`Sources/ZRenderKit/Contain/`)
- [x] `Contain/ContainPath.swift` ← `contain/path.ts` (winding-number path containment + stroke)
- [x] `Contain/ContainLine.swift`, `Contain/ContainPolygon.swift`, `Contain/ContainArc.swift`,
      `Contain/cubic.swift`, `Contain/quadratic.swift`, `Contain/windingLine.swift`,
      `Contain/containUtil.swift` ← matching `contain/*.ts`
- [x] `Contain/ContainText.swift` ← `contain/text.ts`
- [x] `Path.contain`/`containStroke` (the Phase-1 stub) now route through `ContainPath`; verified by the
      ported `ContainSectorUnitTests`.

> **Filesystem note:** the lowercase upstream basenames `contain/{arc,line,path,polygon,text}.ts` were
> renamed to `Contain/Contain{Arc,Line,Path,Polygon,Text}.swift` to avoid SwiftPM object-file name
> collisions with `Graphic/Shape/{Arc,Line,Polygon}.swift` and `Graphic/{Path,Text}.swift` on the
> case-insensitive macOS volume (see §8). Upstream mapping is preserved in each header; re-sync stays
> mechanical. **Future risk:** any new `Contain/<x>.swift` whose basename case-collides with a Graphic
> file (e.g. `circle`, `rect`) will hit the same collision — apply the same `Contain`-prefix rename.

### 10 remaining shapes (`Sources/ZRenderKit/Graphic/Shape/`)
- [x] `Ellipse.swift`, `Ring.swift`, `Line.swift`, `Polyline.swift` (the `Element` placeholder is now
      a real type), `Heart.swift`, `Droplet.swift`, `Isogon.swift`, `Rose.swift`, `Star.swift`,
      `Trochoid.swift` ← matching `graphic/shape/*.ts`.

### Gradient / pattern / text / image paint (`Sources/NativePainter/`, hand-written)
- [x] `CGRenderer` gradient fill+stroke (`makeCGGradient` from `colorStops`, linear via
      `drawLinearGradient`, radial via `drawRadialGradient`, clip-to-path), pattern fill+stroke (tiled
      `CGImage`), fill-rule selection, `drawText` (Core Text `CTLine`, align/baseline), `drawImage`
      (decoded `CGImage`), `loadCGImage` (file path / base64 `data:` URI via ImageIO).
- [x] `CALayerPainter` now paints `Path`, `TSpan`, and `ZRImage` (Phase-1 painted `Path` only).

### Storage display list + ZRender host facade (`Sources/ZRenderKit/`)
- [x] `Storage.swift` ← `Storage.ts` — flattened, z/z2/zlevel-sorted display list (add/delete/clear,
      `updateDisplayList`); replaces the ad-hoc Group walk.
- [x] `ZRender.swift` ← `zrender.ts` — `ZRender` host: lifecycle (add/remove/clear/dispose),
      refresh/`_refresh`/flush/`_flush`, `isDarkMode`, `init`/`disposeAll`/`getInstance` registry,
      version, on/off/trigger routing. Replaces the `ZRenderType` forward-declaration in `Element.swift`.
      **Handler/HandlerProxy/findHover/coarse-pointer/configLayer/setCursorStyle + the `refreshHover`
      path are PORT-TODO stubs with faithful signatures (Phase 4); painter is injected, not built from a
      `painterCtors` map (no DOM ctor natively).**

---

## 8. Build & test status — Phase 2

- **`swift build` (library): GREEN.** **`swift build --build-tests`: GREEN.** Note: the library alone was
  green even while the *test* link failed — the failure was a SwiftPM object-file name collision on the
  case-insensitive macOS filesystem (object files named by basename, deduped case-SENSITIVELY): five
  `Contain/*.swift` lowercase files collided with `Graphic*` capitalized files
  (`arc↔Arc`, `line↔Line`, `path↔Path`, `polygon↔Polygon`, `text↔Text`), so one `.o` silently overwrote
  the other and its symbols vanished from the static archive (archiving doesn't verify symbol
  completeness, which is why the lib "built"). **Fix:** renamed the five `Contain/*` files to
  `Contain<Name>.swift` (namespaces only — smallest blast radius); no type names, math, or logic changed.
- **`swift test`: GREEN — 50 tests, 0 failures, 13 skipped** (verified this run).
  - **Golden geometry parity (byte-for-byte vs ECharts oracle):** 10/10 PASS — the 6 Phase-1 fixtures
    (rect, circle, sector, arc, bezier-curve, polygon) **plus** 4 new Phase-2 shapes: `ellipse`, `ring`,
    `line`, `polyline`. No `Sources/` change was needed for parity (exact output on first run).
  - **Decorative-shape smoke (no ECharts oracle):** heart, droplet, isogon, rose, star, trochoid — each
    builds a non-empty, NaN/Inf-free command buffer + rebuild token stream (`testDecorativeShapesSmoke`).
  - **Ported zrender unit tests** (behavioral oracle, `Tests/.../unit/`): `ContainSectorUnitTests` PASS
    (Sector containment via `Path.contain`), `ImageUnitTests` PASS×3 (size/aspect math),
    `TextUnitTests` SKIP×1 (rich-style merge needs Phase-3 `useState`).
  - **Skips (13):** the 12 pre-existing Phase-0/1 intentional faithfulness-gap skips (`util.clone`/`merge`,
    Path partial-merge, JS-only `this`-binding/typed-array semantics) **plus** the 1 new `TextUnitTests`
    states skip — all genuine deferrals, none a porting error.

---

## 9. Phase 2 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Graphic/Text.swift` | `graphic/Text.ts` | complete (rich layout) | minor-issues (3) | empty-string color truthiness; `parseFontSize` `+x`-coercion; `'fill'/'stroke' in style` vs `!=nil` (explicit-null) |
| `Graphic/TSpan.swift` | `graphic/TSpan.ts` | complete | (foundation sweep) | — |
| `Graphic/Image.swift` | `graphic/Image.ts` | complete | faithful | native decode = file/data-URI only (remote URL = PORT-TODO) |
| `Graphic/CompoundPath.swift` | `graphic/CompoundPath.ts` | complete | (foundation sweep) | — |
| `Graphic/IncrementalDisplayable.swift` | `graphic/IncrementalDisplayable.ts` | complete | (foundation sweep) | — |
| `Contain/ContainPath.swift` | `contain/path.ts` | complete | minor-issues (1) | missing `\|\| 0`(orZero) wrap on windingCubic/windingQuadratic — currently inert, but a textual divergence |
| `Contain/ContainText.swift` | `contain/text.ts` | complete | faithful | — |
| `Contain/{ContainArc,ContainLine,ContainPolygon,cubic,quadratic,windingLine,containUtil}.swift` | `contain/*.ts` | complete | (foundation sweep) | renamed basenames (§8); content faithful |
| `Graphic/Shape/Ellipse.swift` | `graphic/shape/Ellipse.ts` | complete | faithful | — |
| `Graphic/Shape/Ring.swift` | `graphic/shape/Ring.ts` | complete | faithful | — |
| `Graphic/Shape/Line.swift` | `graphic/shape/Line.ts` | complete | minor-issues (1) | resolved `fill` diverges: `extendPathStyle` doesn't honor upstream explicit-`null` fill override (`#000` vs null) |
| `Graphic/Shape/Polyline.swift` | `graphic/shape/Polyline.ts` | complete | faithful | — |
| `Graphic/Shape/Star.swift` | `graphic/shape/Star.ts` | complete | minor-issues (2) | `!n` NaN-guard divergence; non-integer `n` truncation (`Int(n)*2-1`) — edge-case only |
| `Graphic/Shape/{Heart,Droplet,Isogon,Rose,Trochoid}.swift` | `graphic/shape/*.ts` | complete | faithful | — |
| `Storage.swift` | `Storage.ts` | complete | faithful | — |
| `ZRender.swift` | `zrender.ts` | complete (render surface) | faithful | Handler/hover/findHover = PORT-TODO (Phase 4); painter injected; documented `_refresh` hover-only no-op |
| `NativePainter/CGRenderer.swift` (+gradient/pattern/text/image) | (hand-written, §9) | complete | n/a | remote-URL image load + pattern rotation/scale matrix + line-cap/join keyword presets = PORT-TODO |
| `NativePainter/CALayerPainter.swift` (Path+TSpan+ZRImage) | (hand-written, §9) | complete | n/a | remote-URL async `onload` = PORT-TODO |

Roll-up (ported `.ts` mirrors with a review verdict): **faithful majority; 4 minor-issues
(`Text`×3, `ContainPath`×1, `Line`×1, `Star`×2), 0 major.** No new blockers; no `Sources/` bug fixes
were required to pass goldens/units.

---

## 10. Phase 2 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`Text` empty-string color truthiness** (`Text.swift` `_renderBackground` ~1133/1179, bg ~755/921/1128).
   TS uses JS truthiness (`textBorderWidth && textBorderColor`, `!!backgroundColor`); the port uses
   `!= nil`, so an empty-string color `""` reads as *present* — Swift strokes/fills with `.string("")`
   and treats bg as drawn where TS skips it. Internally inconsistent with the port's own `needDrawBackground`
   (which correctly uses `!color.isEmpty`). Degenerate inputs only; normal non-empty colors unaffected.
2. **`Text.parseFontSize` numeric coercion** (`Text.swift` ~1255). TS `!isNaN(+fontSize)` accepts `""`→0
   and whitespace-padded `"  12  "`→12; Swift `Double(s)` returns nil for both, falling to the default
   `DEFAULT_FONT_SIZE + "px"`. Edge-case (empty/whitespace fontSize strings).
3. **`'fill'/'stroke' in style` modeled as `!= nil`** (`Text.swift` ~795/803/1038/1051). TS `in` is key
   existence, so an explicit `fill: null` keeps existence true → `getFill(null)=null` (no default fill);
   the Swift value-type model maps absent ≡ explicit-null → `useDefaultFill`, applying `defaultStyle.fill`.
   Inherent value-vs-reference limitation; affects the auto-stroke `useDefaultFill` branch.
4. **`Line` (and any shape that nulls an inherited default) resolves `fill` to `#000`, not null**
   (`Line.swift:54` + `Path.swift:728` `extendPathStyle`). TS copies the own `fill:null` key over the
   prototype so resolved `fill===null`; the shared `extendPathStyle` guards `if source.fill != nil`, so
   the null override is dropped and `fill` stays `.string("#000")`. Root cause is the shared helper not
   honoring upstream explicit-null-override semantics; affects any `hasFill`/`shouldBePainted`/`getPaintRect`
   reading `style.fill`. Visual impact on a degenerate open path is negligible but the style state diverges.
5. **`ContainPath` missing `orZero()` on windingCubic/windingQuadratic** (`ContainPath.swift` ~311/330).
   TS wraps both with `|| 0`; the L-case and the windingLine calls correctly use `orZero`, so this is an
   inconsistency. **Currently inert** (those functions reject NaN roots and cannot return NaN), but a
   textual divergence — wrap both to keep mechanical re-sync exact.
6. **`Star` NaN-guard + non-integer `n`** (`Star.swift` ~55/82). TS `!n` returns early on `n===NaN`;
   Swift `n==0 || n<2` does not (NaN comparisons are false). TS keeps fractional `n` in the loop bound
   (`n*2-1`); Swift truncates (`Int(n)*2-1`), emitting a different vertex count. Edge-case only (`n` is
   normally an integer ≥3).

### Stubbed surfaces — whole features deferred (each is `// PORT-TODO`)
7. **Animation** remains a type-surface stub: `Animator` bodies, `easing` table,
   `animation/{Animation,Clip}.ts`, `Track`, and every `animateTo`/`animate`/`stopAnimation` path. → **Phase 3.**
8. **States / emphasis / blur / select** machinery still stubbed in `Element` (`useState` is a documented
   no-op returning nil — `Element.swift:556`). Consequence: `Text` rich-style state merge is unreachable
   (the one `TextUnitTests` skip). → **Phase 3** (states/`_mergeStyle`).
9. **Native image loading** is file path / base64 `data:` URI only (ImageIO). Remote-URL fetch + async
   `onload` (the deferred renderer seam, CONVENTIONS §9) is PORT-TODO in both `CGRenderer` and `CALayerPainter`.
10. **Event / Handler plumbing** — `ZRender.on/off/trigger` route to `Eventful`, but `Handler`,
    `HandlerProxy`, `findHover` (returns nil), coarse-pointer, `configLayer`, `setCursorStyle`, and the
    `refreshHover`/hover-layer path are PORT-TODO stubs. `Eventful` is still not fully wired into `Element`.
    → **Phase 4** (UIKit interaction layer).
11. **`CGRenderer` paint gaps:** pattern rotation/scale matrix (only `repeat` + x/y offset tiled today),
    line-cap/join keyword presets, gradient/pattern *text* fill, non-base64 (URL-encoded) data URIs.
12. **`ZRender._refresh` hover-only no-op** — the port only calls `painter.refresh` when `refresh==true`,
    so `refreshHover()`/`refreshHoverImmediately()` are no-ops (`// PORT-TODO`, Phase 4 hover-layer seam).

> Carry-over still open from §4 (Phase 1) and §P0-3 (Phase 0): `Displayable.STYLE_MAGIC_KEY` static-flag
> divergence (major — audit before state-style application lands), `Group.children()` value-copy,
> `color.swift` `lerp`/`modifyHSL`/`liftColor` partials (needed for gradient-stop tweening in Phase 3),
> `util.merge` null-guard gap, and the `Swift.min/max`/`|| 0`-vs-`?? 0` NaN-policy items — all low-risk
> under finite-coords usage.

---

## 11. Phase 3 plan (HISTORICAL — executed; results in §§13–17) — animation full + path-morphing tools + color completion (→ "logic-complete")

**Goal:** replace the animation type-surface stub with a real, driven animation system and the path
geometry tools, completing the renderer's *logic*. After Phase 3 zrender is **logic-complete**; Phase 4
(Handler/event/GestureMgr → UIKit) is the final interaction layer.

### 11a. Animation (`zrender/src/animation/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `animation/Animator.ts` (real bodies — Track/Clip/keyframe interpolation) | `Animation/Animator.swift` (replace stub) | `easing` (stub→fill), `color.lerp` (Phase-1 partial→complete), `util`, `Element`/`Path` animate hooks (already referenced) |
| `animation/Animation.ts` (the loop/scheduler) | `Animation/Animation.swift` | `Animator`, `ZRender.addAnimator`/`removeAnimator` hooks (present), `Eventful` |
| `animation/Clip.ts` (per-clip timeline) | `Animation/Clip.swift` | `easing` |
| `animation/easing.ts` (fill the stubbed table) | `Animation/easing.swift` (complete) | — |
| **rAF → CADisplayLink** host loop (hand-written, §9) | `NativePainter` | `Animation.update`/`ZRender.flush` |

### 11b. Path-morphing tools (`zrender/src/tool/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `tool/path.ts` | `Tool/path.swift` | `PathProxy`, `Path`, all shapes (Phase 1–2), `BoundingRect`, `matrix` |
| `tool/transformPath.ts` | `Tool/transformPath.swift` | `PathProxy`, `matrix`, `vector` |
| `tool/dividePath.ts` | `Tool/dividePath.swift` | `tool/path`, `PathProxy` |
| `tool/morphPath.ts` | `Tool/morphPath.swift` | `tool/dividePath`, `Animator` (11a), `curve` |

### 11c. `tool/color` completion (`zrender/src/tool/color.ts`)
Finish the Phase-1 partial: `lerp` / `mapToColor` / `modifyHSL` / `modifyAlpha` / `liftColor` (need
`util.isFunction`/`isString` guards + `GradientObject` — most already present). **Required by 11a**
(keyframe color interpolation) and gradient-stop tweening. Already-ported deps: `Tool/color.swift`
(parse/rgba/stringify/fastLerp), `Graphic/Gradient*`.

**Sequencing note:** 11c (`color.lerp`) and the `easing` table unblock 11a (`Animator` interpolation);
11a `Animator` unblocks 11b `morphPath`. The CADisplayLink host loop lands last, once `Animation.update`
is real. Handler/event/GestureMgr stay a **Phase-4** deferral throughout.

---

## 13. What landed in Phase 3 — checklist

**Goal (met):** replace the animation type-surface stub with a real, driven animation system and the
path-geometry tools, completing the renderer's *logic*. A hand-built tree's `animateTo`/`animate` now
produces real keyframe-interpolated tweens driven on a real frame clock (CADisplayLink/Timer), color
keyframes interpolate channel-wise, and the path-morphing toolchain (path↔polygon/bezier conversion,
affine path transform, shape division, and morph scheduling) is in place. **After Phase 3 zrender is
logic-complete** — rendering (Phase 1–2) + animation + path tools. Only the interaction layer (Phase 4)
remains.

### Animation — real bodies (`Sources/ZRenderKit/Animation/`)
- [x] `Animation/Animator.swift` ← `animation/Animator.ts` — **stub replaced with real Track/keyframe
      interpolation**: `Track`/`when`/`whenWithKeys`, keyframe-type detection (NUMBER / 1D-ARRAY /
      2D-ARRAY / COLOR / UNKNOWN), `fillArray` length-alignment, additive tracks, `interpolate1DArray`/
      `interpolate2DArray`/color lerp, `step`/`setTime`, `start`/`stop`/`delay`/`during`/`done`/`aborted`,
      `saveTo`/`__changedKeys`. Drives via `Clip`.
- [x] `Animation/Animation.swift` ← `animation/Animation.ts` — the loop/scheduler: linked-list
      add/remove of `Clip`/`Animator`, `update()` (step + `ondestroy`/`removeClip` on finish),
      `start`/`stop`/`pause`/`resume`/`clear`/`isFinished`, `_pausedTime`/`_pauseStart` bookkeeping,
      `getTime()`. `_startLoop`/`requestAnimationFrame` seam is delegated to the native host loop (§9 / PORT-TODO).
- [x] `Animation/Clip.swift` ← `animation/Clip.ts` — per-clip timeline: `step(globalTime, deltaTime)`,
      loop/delay/gap, easing application, `onframe`/`ondestroy`/`onrestart`. `setEasing` cubic-bezier
      string miss → linear (cubicEasing.ts not yet ported — PORT-TODO).
- [x] `Animation/easing.swift` ← `animation/easing.ts` — **stubbed table filled** (linear / quad / cubic /
      quart / quint / sine / expo / circ / elastic / back / bounce, in/out/inOut). `faithful`.

### Path-morphing & path tools (`Sources/ZRenderKit/Tool/`)
- [x] `Tool/ToolPath.swift` ← `tool/path.ts` — SVG-path parse (`createPathProxyFromString`), `processArc`
      (endpoint→center arc conversion), command walker (l/L/m/M/h/H/v/V/C/c/S/s/Q/q/T/t/A/a/z with
      reflection), `mergePath`/`clonePath`. (Named `ToolPath.swift` to avoid case-collision with
      `Graphic/Path.swift`, mirroring the §8 `Contain*` rename.)
- [x] `Tool/transformPath.swift` ← `tool/transformPath.ts` — in-place affine transform of `PathProxy`
      command data. `faithful` (R-case is Swift-safe rather than the upstream TypeError; see §15).
- [x] `Tool/dividePath.swift` ← `tool/dividePath.ts` — split a path/polygon into N sub-paths
      (clone-and-clip + farthest-pair bisection), `copyPathProps`.
- [x] `Tool/morphPath.swift` ← `tool/morphPath.ts` — the morph engine: `alignBezierCurves`/`alignSubpath`
      subdivision, centroid/signed-area, `findBestRingOffset`/`findBestMorphingRotation`, `buildPath`
      lerp+rotation, `morphPath`/`combineMorph`/`separateMorph` scheduler wiring, `__morphT`/`__morphBuildPath`
      seams on `final class Path`.
- [x] `Tool/convertPath.swift` ← `tool/convertPath.ts` — `pathToPolygons` / `pathToBezierCurves`
      (subpath sampling for morph alignment). (Named-export namespace deviation documented in-header.)

### `tool/color` completion (`Sources/ZRenderKit/Tool/color.swift`)
- [x] `lerp` / `fastMapToColor` / `mapToColor` / `modifyHSL` / `modifyAlpha` / `liftColor` finished
      (the Phase-1 partial). Color-keyframe interpolation (11a) and gradient-stop tweening now resolve.
      The Phase-1-deferred `tool/color` unit spec is now **fully un-skipped** (15/15 rows pass).

### Element / ZRender animation wiring (`Sources/ZRenderKit/`)
- [x] `Element.swift` — the real animation surface: `animate`/`addAnimator`/`animateTo`/`animateFrom`/
      `stopAnimation`/`_transitionState`, the module-level `animateTo`/`animateToShallow`/`copyValue`
      family, and `animationGet`/`animationSet` (primary Element/Transformable props via `_setKnownKV`).
      `zr.animation.addAnimator`/`removeAnimator` now drive real `Animator`s (was a no-op stub).
- [x] `ZRender.swift` — `animation` is a live `Animation` instance; `addAnimator`/`removeAnimator` route
      to it; `flush`→`animation.update`→`_flush`→`_refresh`→`painter.refresh` is the real frame path.

### CADisplayLink host loop (`Sources/NativePainter/AnimationLoop.swift`, hand-written, not a translation)
- [x] `AnimationLoop.swift` — the rAF→native frame-clock glue: CADisplayLink (iOS/tvOS, vsync-aligned),
      main-run-loop `Timer` ~60 Hz fallback (macOS). `init(animation:)` pumps `Animation.update()` per
      frame; `_DisplayLinkProxy` keeps `AnimationLoop` off `NSObject` and breaks the CADisplayLink retain
      cycle. `start`/`stop` idempotent; `getTime()` = `CACurrentMediaTime()*1000`.

---

## 14. Build & test status — Phase 3

- **Build: GREEN.** Clean build (`rm -rf .build && swift build`) compiles all targets first try; **no
  `Sources/` fixes were required** to integrate the real Animator over the Phase-1/2 stub seam. One
  benign unreachable-code warning around the `cfgAborted?()` branch (`Animator.swift` ~line 1120); non-blocking.
- **`swift test`: GREEN — 61 tests, 0 failures, 16 skipped** (verified this run). Baseline was Phase-2's
  50/13; Phase 3 adds 11 tests (7 pass, 4 skip) across three new files plus the un-skipped color spec.
  - **Animation interpolation smoke** (`Tests/.../AnimationSmokeTests.swift`, the in-flight-frame analog of
    GoldenTests geometry parity) — 4/4 PASS: linear number tween (midpoint/endpoint exact), cubicOut tween
    (monotonic, eased ≠ linear, uses the real `easing.cubicOut` as oracle), color tween (channel-wise rgba
    midpoint `[30,50,70,1]`), and direct `color.lerp(0.5,…)`. Synthetic timestamps drive `clip.step(time, delta)`
    deterministically (exactly what `Animation.update` does internally), avoiding wall-clock flake.
  - **Ported `tool/color` unit spec** (`ColorUnitTests.swift`) — **fully un-skipped** (Phase 1 had deferred
    it because `tool/color` was partial): all 15 upstream `colorStr → rgba` rows PASS exactly (incl. 0.2/0.5/0.8
    alpha cases).
  - **Ported `animation/ElementAnimation` spec** (`ElementAnimationUnitTests.swift`) — 6 methods, 3 pass / 3 skip:
    PASS undefined-value-not-animated, equal-value-not-animated, done-after-finish, and the primary-prop
    set-to-final (`x==10 && y==10`). SKIP the `shape.points`/`style.fill` sub-bag assertions and abort —
    they need the value-type `shape`/`style` keyed-access seam (see §16 #1).
  - **Skips (16):** the 13 pre-existing Phase-0/1/2 faithfulness-gap skips + 3 new
    `ElementAnimationUnitTests` value-bag-seam skips. All genuine deferrals, none a porting error.
- **No real porting bugs found** in the Phase-3 reviews; 0 failures, no `XCTExpectFailure` needed,
  all `Sources/` untouched by the test/integration sweep.

---

## 15. Phase 3 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Animation/Animator.swift` | `animation/Animator.ts` | complete (real bodies) | minor-issues (3) | array-step tail truncation (wholesale `animationSet` vs in-place index write); `Double(str)` vs JS unary-`+` keyframe-type detection (`""`/`Infinity`/hex); `[weak self]` lifetime break (CONVENTIONS §8) — caller must retain the Animator |
| `Animation/Animation.swift` | `animation/Animation.ts` | complete | minor-issues (1) | `getTime()` returns fractional ms (Double) vs JS integer ms — benign per number→Double; scheduler logic verified faithful; `_startLoop`/rAF seam is a documented PORT-TODO |
| `Animation/Clip.swift` | `animation/Clip.ts` | complete | faithful | `setEasing` cubic-bezier-string miss → linear (cubicEasing.ts not yet ported — marked PORT-TODO); table-backed + function easings work |
| `Animation/easing.swift` | `animation/easing.ts` | complete | faithful | — |
| `Tool/ToolPath.swift` | `tool/path.ts` | complete | minor-issues (2) | numeric/parse core + regex + `processArc` byte-faithful; `clonePath` uses `useStyle` (REPLACE) vs TS `setStyle` (MERGE) — PORT-TODO; `clonePath` drops `buildPath` copy — PORT-TODO |
| `Tool/transformPath.swift` | `tool/transformPath.ts` | complete | faithful | R-case is Swift-safe (computes) where TS throws a TypeError on uninitialized `p` — deliberate, header-documented deviation |
| `Tool/dividePath.swift` | `tool/dividePath.ts` | complete | minor-issues (1) | `copyPathProps` `useStyle` vs `setStyle` (as ToolPath); empty-polygon branch fails gracefully vs TS throw; `Array.sort` not guaranteed stable (rare equal-key ties only) — all PORT-TODO/advisory |
| `Tool/morphPath.swift` | `tool/morphPath.ts` | complete | faithful | morph math + scheduler wiring match; `__morphBuildPath` captures `[weak toPath]` (justified seam, geometry never differs) |
| `Tool/convertPath.swift` | `tool/convertPath.ts` | complete | faithful | named-export namespace deviation documented |
| `Tool/color.swift` (completion) | `tool/color.ts` | complete | faithful | `lerp`/`mapToColor`/`modifyHSL`/`modifyAlpha`/`liftColor` finished; spec fully un-skipped |
| `Element.swift` (animation wiring) | `Element.ts` | complete (animation surface) | minor-issues (carry) | `animationGet`/`animationSet` cover primary props; value-type `shape`/`style` keyed access is the open seam (§16 #1) |
| `ZRender.swift` (animation wiring) | `zrender.ts` | complete | faithful | live `Animation` instance; real `flush`→`update`→`_refresh` path |
| `NativePainter/AnimationLoop.swift` | (hand-written, §9) | complete | n/a (not a translation) | CADisplayLink (iOS/tvOS) + Timer (macOS); rAF seam |

Roll-up (ported `.ts` mirrors with a review verdict): **6 faithful, 5 minor-issues, 0 major.** No new
blockers; no `Sources/` bug fixes were required to pass smoke/units.

---

## 16. Phase 3 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged, fix opportunistically
1. **Value-type `shape`/`style` bags are not yet keyed-animatable** (the one structural seam, drives the
   3 `ElementAnimationUnitTests` skips). `Path`/`Displayable` expose `style`/`shape` as VALUE-type structs
   (`PathStyleProps`/`PathShape`) with no keyed `animationGet`/`animationSet` override, so
   `animateToShallow`'s `animObjSet` is a no-op for those sub-bags (`Element.swift` ~1410). Primary
   Element/Transformable props (`x`/`y`/`rotation`/…) animate correctly; `animateTo({shape:{…}})` /
   `animateTo({style:{fill:…}})` carry empty tracks and complete synchronously. Wiring keyed access into
   the value bags unblocks shape/style/decal tweening and morph-via-animateTo. (Carries §10 #8.)
2. **`Animator` array-step tail truncation** (`Animator.swift` ~633). Upstream mutates the live property
   array in place, writing only indices `0..<keyframeLen` and **leaving a longer existing target's tail
   untouched**; the port computes a fresh exactly-sized array and `animationSet`s it wholesale, dropping
   the surplus tail. Identical-dimension cases (the common path) are unaffected; only a target array
   *longer* than the destination keyframe diverges mid/after tween.
3. **`Animator` keyframe-type detection uses `Double(str)` not JS unary-`+`** (`Animator.swift` ~407).
   TS `!isNaN(+v)` coerces `""`→0, `"  3  "`→3, `"Infinity"`, hex `"0x10"`→16 to NUMBER; Swift `Double(str)`
   returns nil for all of those, so they fall to `color.parse` and become discrete/UNKNOWN. Most impactful
   for empty string. Low practical impact (real numeric keyframe strings are like `"2"`).
4. **`Animator` `start()` closures capture `[weak self]`** (`Animator.swift` ~1001/1033). Upstream's clip
   strongly retains the animator for the clip's run; the port's weak capture means an Animator that nothing
   else retains can dealloc mid-animation, silently no-op'ing `onframe`/`ondestroy` and skipping `done`.
   Documented CONVENTIONS §8 retain-cycle break — **callers must independently retain the Animator** (the
   `ZRender.animation` linked list does this in normal use).
5. **`clonePath`/`copyPathProps` `useStyle` (REPLACE) vs TS `setStyle` (MERGE)** (`ToolPath.swift` ~544,
   `dividePath.swift` ~336). For a partially-specified source style, the clone can end up with different
   defaults than upstream. PORT-TODO-flagged. Also `clonePath` drops `buildPath = sourcePath.buildPath`, so
   cloning an element whose geometry comes from an overridden `buildPath` (not `shape`) loses its drawing logic.
6. **`Clip.setEasing` cubic-bezier string → linear** (`Clip.swift` ~184). TS compiles a `cubic-bezier(...)`
   string via `createCubicEasingFunc`; the port returns nil → `step()` degrades to linear. Narrow:
   only cubic-bezier *string* easings; all table-backed named easings and function easings work.
   → **port `animation/cubicEasing.ts`** (small, deferred from Phase 3).
7. **`transformPath` R-case Swift-safe divergence** (`transformPath.swift` ~31). A path containing a `CMD.R`
   makes TS throw (`p` is `undefined`); the port zero-inits `p` and computes a transformed result. Deliberate
   safety deviation, header-documented — arguably more correct, but not an exact reproduction.
8. **`Animation.getTime()` fractional ms** (`Animation.swift:23`) vs JS integer `new Date().getTime()`.
   Benign per number→Double; only higher timing precision, no behavioral break.

### Now NO LONGER stubbed (closed by Phase 3)
- **Animation** is fully real: `Animator` bodies, the `easing` table, `Animation` scheduler, `Clip`
  timeline, and every `Element`/`ZRender` `animate`/`animateTo`/`stopAnimation`/`addAnimator` path now
  drive actual tweens on a real frame clock. (Closes §10 #7 / §4 #10.)
- **`tool/color` completion** — `lerp`/`mapToColor`/`modifyHSL`/`modifyAlpha`/`liftColor` done; gradient-stop
  and color-keyframe interpolation resolve. (Closes §4 #4 / §10 carry-over.)
- **Path-morphing toolchain** (`tool/path`, `transformPath`, `dividePath`, `morphPath`, `convertPath`) landed.

### REMAINS deferred → Phase 4 (interaction) and small follow-ups
- **States / emphasis / blur / select** machinery still stubbed in `Element` (`useState` a documented
  no-op). The `shape`/`style` keyed-animation seam (#1) and rich-text state merge depend on it.
  Carries §10 #8 — partly Phase 4, partly an `Element` state follow-up.
- **Event / Handler / GestureMgr plumbing** — `Handler`, `HandlerProxy`, `findHover` (returns nil),
  coarse-pointer, `configLayer`, `setCursorStyle`, the `refreshHover`/hover-layer path, and full `Eventful`-
  into-`Element` wiring. → **Phase 4** (§17).
- **Native image loading** — still file path / base64 `data:` URI only (ImageIO); remote-URL fetch + async
  `onload` PORT-TODO in `CGRenderer`/`CALayerPainter`. (Carries §10 #9.)
- **`animation/cubicEasing.ts`** (#6) — small, port when a cubic-bezier-string easing is first needed.

> Carry-over still open from §§4/10/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence (major —
> audit before state-style application), `Group.children()` value-copy, `util.merge` null-guard gap, and
> the `Swift.min/max`/`|| 0`-vs-`?? 0` NaN-policy items — all low-risk under finite-coords usage.

---

## 17. zrender is LOGIC-COMPLETE — Phase 4 plan (interaction → UIKit/AppKit)

**zrender is now LOGIC-COMPLETE: rendering (Phase 1–2) + animation (Phase 3) + path tools (Phase 3).** A
hand-built `Group`/`Path`/`Text`/`Image` tree renders to pixels, hit-tests, animates on a real frame clock,
and morphs. The **only remaining zrender work is Phase 4 = interaction**: the browser DOM event /
pointer / gesture layer, which on native is mostly **hand-written UIKit/AppKit bridging**, not a direct
line-by-line translation. **After Phase 4, the port moves up to the ECharts layer** (coord / scale / data /
chart series).

### 17a. Upstream files
| Upstream file | Swift target | Nature |
|---|---|---|
| `Handler.ts` | `Handler.swift` | **Translate** — the dispatcher: `findHover` (route a pointer to the top hit `Displayable` via `contain/*`, already ported), event normalization, `dispatchToElement`, cursor, the `mousedown→mousemove→mouseup`/`click`/`mouseover`/`mouseout`/`globalout` state machine. Wires the `Eventful`-into-`Element` forwarding still stubbed since Phase 1. |
| `core/event.ts` | `Core/event.swift` | **Translate** — `normalizeEvent`/`clientToLocal`/`getNativeEvent`, `Dispatcher` typing, stop-propagation/prevent-default helpers (adapted to native event objects). |
| `core/GestureMgr.ts` | `Core/GestureMgr.swift` | **Translate the recognizer logic** (pinch/tap bookkeeping), but feed it from native gestures (17b) instead of raw multi-touch DOM `TouchEvent`s. |
| `dom/HandlerProxy.ts` | `NativePainter/UIKitHandlerProxy.swift` (hand-written) | **Bridge, not translate** — the DOM `HandlerProxy` attaches `addEventListener` for mouse/touch/pointer/wheel and feeds normalized events to `Handler`. The native analog attaches `UIGestureRecognizer`s / `NSResponder` events on the host view and feeds the same normalized event shape into `Handler`. |

### 17b. How it bridges to native UIKit/AppKit
- **Host view + responder:** the `CALayerPainter`'s backing `UIView`/`NSView` becomes the event source. A
  hand-written `UIKitHandlerProxy` (the `dom/HandlerProxy` analog) attaches:
  `UITapGestureRecognizer`, `UIPanGestureRecognizer`, `UIPinchGestureRecognizer`,
  `UILongPressGestureRecognizer` (iOS/tvOS) and `mouseDown/Up/Moved`/`scrollWheel`/`magnify(with:)`
  (macOS `NSResponder`).
- **Normalize → `Handler`:** each recognizer/responder callback maps the touch/pointer location into
  ZRender-local coordinates (`clientToLocal` from `core/event`, accounting for `dpr`/contentScale) and
  synthesizes the normalized event the translated `Handler.dispatch(...)` expects
  (`mousedown`/`mousemove`/`mouseup`/`click`/`mousewheel`/`pinch`), so `Handler`'s hit-routing + the ported
  `Eventful` dispatch stay unchanged.
- **`GestureMgr` reuse:** native `UIPinchGestureRecognizer`/`magnify` can either drive ZRender's `pinch`
  event directly (preferred — let UIKit recognize) or feed raw touches into the translated `GestureMgr`;
  the bridge picks the former and keeps `GestureMgr` for parity/headless paths.
- **Cursor / hover:** `Handler.setCursorStyle` maps to `NSCursor` (macOS) / is a no-op on touch; the
  `refreshHover`/hover-layer path (PORT-TODO since §10 #12) lands here.
- **No DOM:** no `addEventListener`, `pointer-events`, or `<canvas>` — the bridge owns all of that natively.

**Sequencing:** translate `core/event` + `Handler` + `GestureMgr` (logic), then hand-write
`UIKitHandlerProxy` to feed them; finally wire `ZRender.handler`/`findHover`/`refreshHover` (the §10 #10/#12
stubs) to the real `Handler`. After Phase 4 the renderer is interaction-complete and the port advances to
the ECharts layer.

---

## 18. What landed in Phase 4 — checklist

**Goal (met):** the interaction layer — route a native pointer/touch/gesture into the z-sorted Storage
display list, hit-test it to the top `Displayable` (`findHover`), and run the full
`mousedown→mousemove→mouseup`/`click`/`mouseover`/`mouseout`/`globalout`/`pinch` dispatch + bubble state
machine, wiring the long-stubbed `Eventful`-into-`Element` forwarding. zrender's browser DOM event source
(`dom/HandlerProxy.ts`) is **replaced by a hand-written UIKit/AppKit bridge** (CONVENTIONS §9), so the
same `ZRender`/`Handler`/`Element` event surface is driven natively on both iOS and macOS. **After Phase 4
zrender is COMPLETE.**

### Handler — hit-test / dispatch / bubble (`Sources/ZRenderKit/Handler.swift`)
- [x] `Handler.swift` ← `Handler.ts` — the dispatcher (composes `Eventful` via `_eventful`, mirroring
      `class Handler extends Eventful`). `findHover` (display-list walk + `isHover`/`setHoverTarget`
      clip/silent/ignore tri-state + the coarse-pointer enlarged-pointer ring scan), `mousemove`
      (mouseout/mousemove/mouseover transitions + cursor), `mouseout`/`globalout`, `dispatchToElement`
      (per-element `trigger` + host/parent bubble + global `trigger`), `commonHandler` (the unrolled
      `click`/`mousedown`/`mouseup`/`mousewheel`/`dblclick`/`contextmenu` set with the down/up/4px
      click gate), `processGesture` (feeds `GestureMgr`), `setHandlerProxy`/`setCursorStyle`/`dispose`.
      `EmptyProxy`, `HoveredResult`, `HandlerProxyInterface`, `DraggableHandler` conformance.
- [x] `Element` `Eventful` wiring is now LIVE — `cur.trigger(eventName, eventPacket)` drives the per-element
      listener surface that was stubbed since Phase 1; `ZRender.on/off/trigger` route to the real `Handler`.

### core/event normalization (`Sources/ZRenderKit/Core/event.swift`)
- [x] `Core/event.swift` ← `core/event.ts` (caseless `enum eventTool` namespace) — `normalizeEvent`
      (in-place `zrX`/`zrY`/`which`/`zrDelta` mutation on the reference-type `ZRRawEvent`, the wheel-delta
      sign ladder, which-bitmask, `getNativeEvent`/`clientToLocal` seam), `stop`/`notLeftMouse`/etc.
      The browser DOM coordinate bits (`getBoundingClientRect`, `dom.ts` viewport transform) are PORT-TODO
      native seams — the bridge supplies points already in ZRender-local coordinates.

### GestureMgr + Draggable (`Sources/ZRenderKit/`)
- [x] `Core/GestureMgr.swift` ← `core/GestureMgr.ts` — the pinch recognizer (`recognize`/`_recognize`/
      `clear`, two-finger distance ratio → `pinchScale`/`pinchX`/`pinchY`). `Touch`/`ZRRawTouchEvent`
      native seam types; `clientToLocal` is a passthrough (bridge pre-normalizes).
- [x] `mixin/Draggable.swift` ← `mixin/Draggable.ts` — drag/dragstart/dragend derived from the
      mousedown/mousemove/mouseup stream; `final class` composed by `Handler` (`DraggableHandler` protocol
      = the 3 Handler members it calls), `unowned handler` back-ref to break the retain cycle.

### Native UIKit/AppKit bridge + host (`Sources/NativePainter/ZRenderView.swift`, hand-written, not a translation)
- [x] `NativeHandlerProxy: HandlerProxyInterface` — the `dom/HandlerProxy.ts` analog. Carries the same
      sequencing as `localDOMHandlers` (touchstart → mousemove+mousedown, touchmove → processGesture+mousemove,
      touchend → mouseup + click-within-`TOUCH_CLICK_DELAY`, touchcancel → mouseup-no-click, direct `pinch`
      dispatch), emitting `ZRRawEvent`s through the composed `Eventful` that `Handler` subscribes to.
      `setCursor` is a no-op (PORT-TODO: `NSCursor` on macOS).
- [x] `ZRenderView` — the host view, split `#if canImport(UIKit)` (`UIView`: touchesBegan/Moved/Ended/
      Cancelled + `UIPinchGestureRecognizer`) vs `#elseif canImport(AppKit)` (`NSView`, `isFlipped=true`:
      mouseDown/Dragged/Up + rightMouseDown/contextmenu + scrollWheel + `NSMagnificationGestureRecognizer`),
      all inside an outer `canImport(UIKit) || canImport(AppKit)` guard so it builds for both destinations.
      Hosts the `CALayerPainter.rootLayer`, owns the `ZRender` facade (`ZRenderKit.init(painter:proxy:)`) +
      an `AnimationLoop`, resizes on layout, and normalizes each native event into a ZRender-local
      `ZRRawEvent` (incl. multi-touch `touches[]` for `GestureMgr`) forwarded through `NativeHandlerProxy`.

---

## 19. Build & test status — Phase 4

- **Build: GREEN.** A clean from-scratch rebuild (deleted `ZRenderKit.build` + `NativePainter.build`,
  `swift build`) compiles **all 88 units with 0 errors**. The Phase-4 interaction seam was already wired
  and faithful — **no logic-weakening edits were needed; no `Sources/` changes were made.** One benign
  warning remains (`Handler.swift:386` `var eventPacket` never mutated) — an intentional value-type-struct
  faithfulness artifact already flagged by the adjacent PORT-TODO (see §20 #1); left untouched to preserve
  the upstream loop shape.
- **`swift test`: GREEN — 65 executed / 0 failures / 14 skipped** (Phase-3 baseline 61/16-skipped grew by
  the new `InteractionSmokeTests`; the count shifts to 65/14 because the new file's skip-vs-pass split
  replaces some prior skip accounting — all passing).
- **Interaction smoke** (`Tests/ZRenderKitTests/InteractionSmokeTests.swift`, 7 tests — drives the REAL
  `Handler` (`findHover` + `dispatchToElement`) over a z-sorted `Storage` display list directly, NOT the
  UIKit bridge; `CALayerPainter` is used only as the `PainterBase` Handler needs for boundary checks):
  - Entry points used (read from `Handler.swift`): `zr.handler.findHover(x,y) -> HoveredResult`
    (`.target`/`.topTarget`) and `zr.handler.dispatchToElement(targetInfo, .click, event)`. Scene = a
    `Group` of `Rect`s via `zr.add`; `zr.storage.updateDisplayList()` re-sorts after z2 changes.
  - **Invariants asserted & PASS:** `findHover` inside A→A, inside B→B, neither→nil target; overlap returns
    the TOP (higher z2) element and flipping z2 + `updateDisplayList` flips the result (z-driven, not
    insertion luck); a `silent` rect is never `.target` (hit falls through to the non-silent rect below) but
    IS reported as `.topTarget` (matches `isHover→SILENT`); an `ignore` rect yields neither; `click`
    dispatches child → parent `Group` → ZR host in that exact order; click outside dispatches to nothing.
  - **1 documented-gap skip:** `test_stopPropagation_child_stops_parent` confirms the divergent behavior
    (parent fired) and `XCTSkip`s with a FAITHFULNESS-GAP message (repo skip convention) — see §20 #1. It is
    written to self-heal into a real passing assertion the moment `ElementEvent` becomes a reference type.

---

## 20. Phase 4 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Handler.swift` | `Handler.ts` | complete | minor-issues (3) | bubble-cancel inert (value-type packet + omitted on-props, §20 #1); `dispatch(nil)` swallows vs TS invoking handler (#2); cursor `?? "default"` widening (#3) |
| `Core/event.swift` | `core/event.ts` | complete | faithful | `ZRRawEvent` is a reference type so `normalizeEvent` in-place `zrX/zrY/which/zrDelta` mutation is visible to callers (faithful self-aliasing); branch order / which-bitmask / wheel-delta ladder match. Two theoretical-only NaN/empty-string notes, both unreachable. |
| `Core/GestureMgr.swift` | `core/GestureMgr.ts` | complete | faithful | latent only: `_recognize` iterates `recognizers.keys` (Swift Dictionary order nondeterministic vs TS for-in); identical today (one `pinch` recognizer) — use an ordered list if upstream ever adds recognizers |
| `mixin/Draggable.swift` | `mixin/Draggable.ts` | complete | faithful | `final class` composed by Handler; `unowned handler` retain-cycle break (CONVENTIONS §8) |
| `NativePainter/ZRenderView.swift` (NativeHandlerProxy + ZRenderView) | (hand-written replaces `dom/HandlerProxy.ts`) | complete | n/a (not a translation) | `setCursor` no-op (PORT-TODO `NSCursor`); browser pointer-capture / global-document drag-outside replaced by native touch semantics |

Roll-up (ported `.ts` mirrors with a review verdict): **3 faithful, 1 minor-issues, 0 major.** No new
blockers; **no `Sources/` bug fixes were required** to pass the build or the smoke suite.

---

## 21. Phase 4 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged
1. **Bubble cancellation is INERT — `stopPropagation`/`cancelBubble` cannot stop ZR bubbling**
   (`Handler.swift` `dispatchToElement` ~386–411; the central interaction concern). Upstream
   (`Handler.ts:311–324`) lets the bubble chain stop when `eventPacket.cancelBubble` becomes true — set
   either by an on-prop handler's truthy return (`el[eventKey].call(...)`) OR by a `.on` listener directly
   mutating the shared packet object (`eventPacket` is a plain JS object passed BY REFERENCE to
   `el.trigger`). In Swift, **`ElementEvent` is a value-type `struct`** (`Element.swift:127`), so the packet
   is COPIED into each `cur.trigger(eventName.rawValue, eventPacket)` call (`Handler.swift:392`); any
   listener mutation of `cancelBubble` is lost, and the on-prop path is omitted entirely (no
   `onclick`/`onmousedown` props on `Element` — native event seam). Net: `eventPacket.cancelBubble` can
   **never** become true, so the `if eventPacket.cancelBubble { break }` (line 398) and the
   `if !eventPacket.cancelBubble` global-trigger guard (line 403) are dead — every event always bubbles all
   the way to parent/host chain root and then to the global Handler trigger. `eventTool.stop`
   (`core/event.swift`) only sets `cancelBubble` on the underlying `ZRRawEvent` reference, which the loop
   never re-reads. Acknowledged via two PORT-TODO comments (`Handler.swift:381–385`) and covered by the
   `test_stopPropagation_child_stops_parent` skip. **FIX SUGGESTION:** make `ElementEvent` a `final class`
   (reference) so listener mutations propagate, OR have `dispatchToElement` re-read the underlying event's
   `cancelBubble` after each `trigger`. Either change self-heals the smoke test into a passing assertion.
2. **`dispatch()` swallows `nil` eventArgs** (`Handler.swift:333–339`). TS (`Handler.ts:263–266`):
   `const handler = this[eventName]; handler && handler.call(this, eventArgs)` — the handler is invoked even
   when `eventArgs` is undefined. Swift wraps the call in `if let eventArgs = eventArgs { ... }`, so
   `dispatch(name, nil)` invokes nothing. Minor/undocumented; in practice all call sites pass a real
   `ZRRawEvent` (and a JS handler reading `event.zrX` on undefined would crash anyway), so low impact, but a
   divergence from the literal TS control flow.
3. **Cursor fallback widening** (`Handler.swift:290`, `mousemove`). TS (`Handler.ts:223`) passes
   `hoveredTarget.cursor` straight through (could be undefined); Swift substitutes `?? "default"` when the
   `as? Displayable` cast or `.cursor` is nil — an element with an explicitly-unset cursor yields `"default"`
   in Swift vs undefined in TS. Negligible (`Displayable` defaults cursor non-nil; every real hover target
   is a `Displayable`); noted for completeness.

### Native-bridge approximations (browser-only bits the UIKit/AppKit bridge replaces — PORT-TODO)
4. **`setCursor` is a no-op** (`ZRenderView.swift` `NativeHandlerProxy.setCursor`). iOS has no pointer
   cursor; macOS could `NSCursor`-map `cursorStyle`. `Handler.setCursorStyle` therefore has no visible
   effect today.
5. **Drag-outside / pointer-capture** — the browser's global-`document` pointer-capture machinery
   ([DRAG_OUTSIDE] in `Handler.ts`) is replaced by native touch semantics (touch events keep firing once a
   sequence starts) and AppKit drag tracking; `isOutsideBoundary` is still honored, but there is no explicit
   capture object.
6. **GestureMgr fed by recognizers, not raw multi-touch parity** — the bridge prefers letting
   `UIPinchGestureRecognizer`/`NSMagnificationGestureRecognizer` recognize and dispatch `pinch` directly;
   `GestureMgr` is retained for the headless/`processGesture` path (touchstart/move/end still feed it
   `touches[]`). On an empty-space pinch, `processGesture` falls back to a sentinel `Displayable()` target
   (PORT-TODO: identity diverges from upstream `undefined`).
7. **`core/event` DOM coordinate bits** (`getBoundingClientRect`, `dom.ts` viewport transform, `window.event`)
   are PORT-TODO native seams — the bridge supplies `zrX`/`zrY` already in ZRender-local coordinates.
8. **`Handler.painterRoot` (DOM root) is nil natively**; `(painter as CanvasPainter).eachOtherLayer`
   user-layer dispatch (canvas-only) is not modeled (`Handler.swift:408`).

> Carry-over still open from §§4/10/16/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence (major —
> audit before state-style application lands in the ECharts layer), the value-type `shape`/`style`
> keyed-animation seam (§16 #1), `useState`/states machinery still stubbed in `Element`,
> `Group.children()` value-copy, `util.merge` null-guard gap, `animation/cubicEasing.ts`, native remote-URL
> image loading, and the `Swift.min/max` / `|| 0`-vs-`?? 0` NaN-policy items — all low-risk under
> finite-coords usage, several of which the ECharts option-merge/data layer will force a decision on (§22).

---

## 22. zrender is COMPLETE — the ECharts-layer plan (next major milestone)

**zrender is now COMPLETE: rendering (Phase 1–2) + animation + path tools (Phase 3) + interaction
(Phase 4) are all ported.** The browser-only `canvas/` / `svg/` / `dom/` backends are **intentionally
replaced by `NativePainter`** (CG/CA renderer + CADisplayLink/Timer frame clock + UIKit/AppKit
HandlerProxy bridge), per CONVENTIONS §9 — they are NOT translations and were never meant to be.

### Verification posture (the regression net carried forward)
- **Total ported:** `Sources/ZRenderKit/` = **77 Swift files / ~23.5 K lines** (the line-by-line zrender
  mirror) + `Sources/NativePainter/` = **6 hand-written files / ~2.1 K lines** (the native backend) +
  **16 test files**.
- **Golden geometry parity** (byte-for-byte vs the real-ECharts oracle): 10/10 shape fixtures, via
  `testRebuiltDMatchesOracle` (PathProxy replay) **and** `testSwiftBuildPathMatchesOracle` (true
  `Shape.buildPath` output).
- **Ported zrender unit tests** (behavioral oracle, the upstream Jest specs → XCTest):
  matrix/LRU/util/platform/path/group/contain-sector/image/color/element-animation.
- **Smoke tests:** decorative-shape NaN-free buffers, `CALayerPainter` renderToImage, animation
  interpolation (in-flight-frame parity vs the real `easing`), and now the Phase-4 interaction smoke
  (`findHover` + `dispatchToElement` over a z-sorted Storage list).
- `swift build` green for both iOS and macOS destinations; `swift test` 65/0-fail/14-skip.

### Pre-ECharts: a fidelity-hardening pass (do FIRST)
The carry-over JS-truthiness / null / NaN backlog (`STYLE_MAGIC_KEY`, `util.merge` null-guard, `|| 0` vs
`?? 0`, `Swift.min/max` NaN non-propagation, `'key' in obj` vs `!= nil`, empty-string color truthiness, the
value-type `shape`/`style` keyed-access seam, `useState`/states) has been low-risk under "finite-coords
only" geometry usage — **but the ECharts option-merge and data layers deliberately feed these edge values**
(absent/`null`/`NaN` config, deep option merge, sparse data). Do a focused hardening pass on these BEFORE
the ECharts port so the divergences don't silently corrupt option resolution and data scaling.

### Faithful ECharts port order (`echarts/src/`, reusing the complete `ZRenderKit`)
1. **`model/`** — `Global`/`GlobalModel`, `Component`/`ComponentModel`, `Series`/`SeriesModel`,
   option merge/normalize (forces the deep-merge / null-guard fidelity items above).
2. **`data/`** — `DataStore`, `SeriesData` (the columnar store), `DataDiffer` (enter/update/exit diff for
   data-driven transitions — pairs with the Phase-3 animation system).
3. **`scale/`** — `Scale` base, `Interval`/`Ordinal`/`Time`/`Log`, nice-ticks.
4. **`coord/cartesian/`** — `Cartesian2D`, `Axis2D`, `Grid` data↔pixel mapping.
5. **`Scheduler` + the `Task`/`stream` pipeline** — the per-stage (`createData`/`processData`/`visual`/
   `layout`/`render`) task graph that drives a render.
6. **`visual/` + `layout/`** — visual encoding (color/symbol/size mapping) and series layout.
7. **First `ChartView`** — `BarView` or `LineView` — plus `grid`/`axis` components, reusing the ported
   `Group`/`Path`/`Rect`/`Polyline`/`Text` + the animation + interaction layers end-to-end.

**Sequencing:** `model/` → `data/` → `scale/` → `coord/cartesian` → `Scheduler/Task` → `visual/`+`layout/`
→ first `ChartView` + `grid/axis`. Each stage keeps the standing upstream-sync rule (§12) and adds its
matching ported unit specs + (where an ECharts oracle exists) golden fixtures.

---

## 12. Standing rule for syncing upstream

Every ported file is a **diffable mirror** of its `.ts` original (CONVENTIONS §0). To keep re-sync
mechanical as upstream ECharts/ZRender evolves:

1. **Header comment, line 1, every file:**
   `// Ported from <upstream path>.ts — keep in sync with upstream` (real path, e.g.
   `zrender/src/graphic/Path.ts`). Keep the upstream `@author` / Chinese comments verbatim.
   (NativePainter files are exempt — they are hand-written backends, not translations; see CONVENTIONS §9.)
2. **Mirror structure:** preserve upstream file names, identifier names, and top-to-bottom
   declaration/method/case order. Do not refactor, rename, or reorder. Faithfulness over elegance.
3. **Never silently drop code.** Every skipped/stubbed/deferred/uncertain spot gets a
   `// PORT-TODO: <why>`. Document deviations (value-returning §3, NaN handling, weak refs) inline
   *and* in this file's backlog (§4 for Phase 1, §P0-3 for Phase 0).
4. **Golden fixtures are the regression net.** Regenerate from real ECharts after any upstream bump:
   `cd Oracle && node dump-displaylist.js` (or `node dump-displaylist.js <name>` for one).
   ECharts resolves via `require('echarts')` → `$ECHARTS_DIST` → fallback clone. Both `swift test
   --filter GoldenTests` checks must stay green: `testRebuiltDMatchesOracle` (PathProxy replay parity)
   **and** `testSwiftBuildPathMatchesOracle` (true `Shape.buildPath` geometry parity, byte-for-byte vs
   the oracle). Re-syncing a file means: update the Swift mirror, regenerate fixtures, confirm both
   parities before merge.

---
---

# Phase 0 history (preserved)

**Phase 0 (Core scaffold + math/geometry foundation): COMPLETE.** The one compile blocker recorded
below (§P0-3 #1) was **resolved in Phase 1** (`bbox.fromCubic`/`cubicExtrema`); `swift test` now compiles
end-to-end. The rest of §P0-3 remains an open low-risk backlog (cross-referenced from §4 above).

## P0-1. What landed in Phase 0 — checklist

### Package layout & seam
- [x] `Package.swift` — three targets: `ZRenderKit` (ported core), `NativePainter`
      (hand-written CG/CA backend, not a translation of CanvasPainter), `EChartsKit` (umbrella).
- [x] `Sources/ZRenderKit/Core/PathRebuilder.swift` — consumer protocol for
      `PathProxy.rebuildPath` (the path-command seam).
- [x] `Sources/NativePainter/Renderer.swift` — the `Renderer` (~8 paint ops:
      fillPath/strokePath/drawImage/drawText/setClip/transform/opacity/shadow) and `Painter`
      (beginFrame/endFrame/dpr) seam protocols. **Phase 0: contract only — bodies were PORT-TODO stubs.**
      (Phase 1 implemented these via `CALayerPainter`/`CGRenderer`/`CGPathRebuilder`.)
- [x] `Sources/EChartsKit/EChartsKit.swift` — umbrella module placeholder.
- [x] `CONVENTIONS.md` — binding translation rules (§1 number→Double, §2 module/class mapping,
      §3 out-param value-returning mandate, §9 renderer seam, etc.).
- [x] **Mutation strategy decided & enforced (§3):** value-returning, no out-params.
      `VectorArray = SIMD2<Double>`, `MatrixArray = [Double]` (6 elems, `[a,b,c,d,e,f]`),
      multi-output → tuple, single scratch-array output → returned array. `inout` dropped
      entirely (self-aliasing calls like `vec2.min(min,min,min2)` violate Swift exclusivity).

### 14 translated Core files (`Sources/ZRenderKit/Core/`)
- [x] `types.swift` — typealiases, string/number-union enums, event-name enums, ZLevel consts.
- [x] `env.swift` — `env`/`Browser` singletons; native feature flags via `configureNativeEnv`.
- [x] `util.swift` — **partial**: geometry-layer helpers only (guid, each/map/reduce/filter/find,
      retrieve*, defaults/keys, normalizeCssArray, assert). Clone/merge/type-guards deferred
      (extended on demand in Phase 1).
- [x] `LRU.swift` — `LRU`/`LinkedList`/`Entry`, `LRUKey` tagged enum.
- [x] `WeakMap.swift` — `WeakMap<K: AnyObject, V>` over `NSMapTable` (weak→strong).
- [x] `matrix.swift` — `MatrixArray = [Double]`, value-returning `matrix` namespace.
- [x] `vector.swift` — `VectorArray = SIMD2<Double>`, value-returning `vector` namespace (vec2).
- [x] `Point.swift` — `Point` / `PointLike` (class-bound) with in-place static mutators.
- [x] `curve.swift` — cubic/quadratic at/derivative/root/extrema/subdivide/project/length.
- [x] `bbox.swift` — fromPoints/Line/Cubic/Quadratic/Arc → `(min, max)` tuples. **(blocker resolved in Phase 1.)**
- [x] `BoundingRect.swift` — `BoundingRect`/`RectLike`, intersect/contain/union/transform, MTV context.
- [x] `Transformable.swift` — scene-graph transform base class (subclassable, `parent` weak).
- [x] `platform.swift` — `PlatformAPI`/`DefaultPlatformAPI`, ASCII-width-table measureText fallback.
- [x] `PathProxy.swift` — full path recorder/replayer: addData/moveTo/lineTo/bezier/arc/rect,
      getBoundingRect, rebuildPath, toStatic, clone (~37 KB, the keystone of Phase 0).

### Golden-test harness (`Oracle/` + `Tests/`)
- [x] `Oracle/dump-displaylist.js` — drives real ECharts (`animation:false`), dumps the resolved
      display list incl. each Path's rebuilt `d` string. Deterministic (verified identical on re-run).
- [x] 7 option specs + 7 generated fixtures: `rect`, `circle`, `sector`, `arc`, `bezier-curve`,
      `polygon`, `combined` (`Oracle/options/*.json`, `Oracle/fixtures/*.json`).
- [x] `Tests/ZRenderKitTests/GoldenTests.swift` — `testRebuiltDMatchesOracle` (replays each
      fixture's PathProxy data and byte-compares the rebuilt `d`) + `testAllFixturesLoad`.
      (Phase 1 added `testSwiftBuildPathMatchesOracle` for true geometry parity.)
- [x] `Tests/ZRenderKitTests/PathRebuilderTests.swift` — seam unit tests.
- [x] Harness validated standalone (swiftc-compiled copy): **PASS=12 FAIL=0**, every Path's
      rebuilt `d` matches the oracle byte-for-byte.
- [x] **`swift test` end-to-end compile** — was blocked in Phase 0 by `bbox.swift`/`curve.swift`;
      **resolved in Phase 1** (now green).

## P0-2. Per-file status & review verdict (Phase 0)

| # | File | Status | Verdict | Notes |
|---|------|--------|---------|-------|
| 1 | `types.swift` | complete | faithful | ZLevel2/IncrementalIdCompat widened to bare Double |
| 2 | `env.swift` | complete | minor-issues | native config diverges from upstream node-branch (`node`/`svgSupported`); `detect()` drops `in window` guards |
| 3 | `util.swift` | **partial** | faithful | only geometry-layer helpers ported; clone/merge/type-guards = PORT-TODO |
| 4 | `LRU.swift` | complete | minor-issues | numeric-vs-string key coercion; doubly-linked retain cycle |
| 5 | `WeakMap.swift` | complete | minor-issues | `has`/`delete` presence-test vs JS truthiness (falsy V) |
| 6 | `matrix.swift` | complete | faithful | dead `create()` in clone; redundant temps in mul (cosmetic) |
| 7 | `vector.swift` | complete | minor-issues | `min`/`max` NaN non-propagation; static-let alias resolution risk |
| 8 | `Point.swift` | complete | minor-issues | constructor `?? 0` vs JS `|| 0` (NaN); transform→Optional |
| 9 | `curve.swift` | complete | faithful | no issues raised |
| 10 | `bbox.swift` | complete | major-issues → **RESOLVED (Phase 1)** | misused `curve.cubicExtrema` tuple; fixed, compiles |
| 11 | `BoundingRect.swift` | complete | minor-issues | mathMin/Max NaN semantics; clamp-branch force-unwrap (faithful) |
| 12 | `Transformable.swift` | complete | minor-issues | `getLocalTransform` drops `|| 0` (NaN); `parent` weak ownership |
| 13 | `platform.swift` | complete | minor-issues | measureText iterates graphemes not UTF-16 code units |
| 14 | `PathProxy.swift` | complete | faithful | hard pathSegLen subscript traps vs JS NaN (unreachable in practice) |

Roll-up: **1 partial, 13 complete; 1 major (now resolved), 8 minor, 5 faithful.**

## P0-3. Open issues & PORT-TODOs (Phase 0) — deduped, blockers first

### BLOCKER — RESOLVED in Phase 1
1. **`bbox.fromCubic` misused `curve.cubicExtrema` (did not compile). RESOLVED.**
   `curve.swift:157` signature is `cubicExtrema(...) -> (extrema: [Double], n: Double)` — a
   **tuple**. The old `bbox.swift` did `let cubicExtrema = curve.cubicExtrema` → `xDim.count` /
   `xDim[i]`, which a tuple has no member for. Fixed in Phase 1 by destructuring `(xDim, n)` and
   iterating `0..<Int(n)` (which also fixed the latent semantic bug: the intended count is `n` ∈ {0,1,2},
   not the constant buffer length 2). `swift test` now compiles end-to-end.

### Correctness — pre-existing review/sign-off (still open, low-risk under finite-coords usage)
2. **Pervasive `Swift.min`/`Swift.max` NaN non-propagation** (`vector.min/max`,
   `BoundingRect.mathMin/Max` + 4-arg overloads, and any bbox reduction). JS `Math.min/max`
   propagate NaN; `Swift.min/max` return the non-NaN operand. These are exactly the bbox/bounds
   accumulators, so a NaN coordinate that would taint a bbox upstream silently survives as a
   finite extent here. Decide a policy (NaN-propagating helper, or documented "finite-coords-only"
   guarantee) and apply uniformly.
3. **`|| 0` (JS-falsy) vs `?? 0` (nil-only) inconsistency on NaN.** `Point` constructor,
   `Transformable.getLocalTransform` (`originX/Y`, `rotation`), and others substitute 0 only for
   `nil`, not for NaN — diverging from upstream where `NaN || 0 === 0`. `_resolveGlobalScaleRatio`
   *did* replicate `|| 0`. Pick one convention; NaN rotation/origin poisons whole matrices.
4. **`env.configureNativeEnv` contradicts upstream's windowless (node) branch.** Upstream sets
   `node=true; svgSupported=true` for no-global-window; native config leaves `node=false`,
   `svgSupported=false`. Any downstream `if env.node` / `if env.svgSupported` gate will branch
   oppositely. Needs explicit sign-off that no consumer depends on these.
5. **`env.detect()` is not a faithful translation despite the "fully translated" note.** It drops
   the `'ontouchstart' in window` / `'onpointerdown' in window` guards. Dead code on iOS today,
   but will compute wrong flags if ever wired. Either fix or mark clearly `// PORT-TODO: dead, not faithful`.
6. **`WeakMap.has`/`delete` use presence test, not JS truthiness.** For falsy-valued `V`
   (`0`, `""`, `false`) Swift `has` returns true where JS returns false, and `delete` then mutates/returns
   differently. Safe for object-valued WeakMaps (the common case); audit before any value-type `V` use.
7. **`LRU.LRUKey` does not coerce numeric keys to strings.** `.number(1)` and `.string("1")` are
   distinct, but JS `map[1] === map["1"]`. Audit call sites that mix numeric/string forms of one key.
8. **`platform.measureText` iterates grapheme clusters, not UTF-16 code units.** Diverges from
   `text.length` for emoji / non-BMP. Switch to `text.utf16` to match (the translator already uses
   `.utf16` in `getTextWidthMap`). Becomes load-bearing once real text measurement lands (Phase 2 5a).

### Style / divergence notes (track, fix opportunistically)
9. `vector.swift` static-let aliases (`length = len`, `dist = distance`, …) reference sibling
   statics by bare name in a stored-property initializer — fragile; **build-verify** (qualify as
   `Self.len` if it fails). *(Phase-1 clean build confirms these resolve.)*
10. **In-place-mutation aliasing is gone everywhere** (value-returning §3). Every ported caller of
    `vector.*`/`matrix.*`/`bbox.*` must *assign the result* (`p = vector.add(p, d)`); a caller that
    discards the return expecting in-place mutation is a **silent no-op**. Recheck at each call site.
11. Memory: `LRU.Entry` doubly-linked list uses bidirectional strong refs (leaks after `clear()`);
    `Transformable.parent` is `weak` (verify ownership / no mid-walk dealloc). Revisit if leaks/crashes surface.
12. `util.reduce` requires `memo` (TS optional); `util.indexOf` is `T: Equatable`+`==` (TS `===`);
    `retrieve2/3` collapse the union return — all safe in current scope, documented.
13. Force-unwraps that faithfully mirror upstream null-deref (BoundingRect `outIntersectRect!` under
    clamp; PathProxy hard `pathSegLen[segCount]`) — JS would also crash; left verbatim, not bugs.
14. Renderer/DOM seam stubs (CONVENTIONS §9): `platform.createCanvas`/`loadImage` return nil;
    `PathProxy._ctx`/setContext/getContext dropped. The `NativePainter.Renderer`/`Painter` *bodies* were
    Phase-0 stubs — **implemented in Phase 1** (`CALayerPainter`/`CGRenderer`); image/text/gradient paint
    remains Phase 2.
15. `util.swift` is **partial**: clone/merge/extend/type-guards/HashMap/bind/curry were PORT-TODO;
    extended on demand in Phase 1 and continuing into Phase 2.
