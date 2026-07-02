# PORT_STATUS.md — ECharts/ZRender → Swift port

**Phase 6c (REAL DATA SOURCE PIPELINE — the faithful `data/helper/sourceManager.ts` port replaces the Series stub `SourceManager`): COMPLETE — `swift build` GREEN (0 warnings), `swift test` 216 executed / 0 failures / 58 skipped (no regression).** The reachable series-inline-data path (no dataset) is fully live and verified: no upstream → `data = seriesModel.get("data")`, `SOURCE_FORMAT_ORIGINAL`, `createSource` → `DataStore` via `DefaultDataProvider`; `getSharedDataStore` now ships on the real class. Dataset/transform arms are documented PORT-TODOs (unreachable this phase). Faithfulness review: faithful, 0 findings. See §36.
**Phase 6b (RENDERING VERTICAL — a REAL bar chart end-to-end: slim `EChartsSlim` driver + `view/` bases + `visual/style` + `layout/barGrid` + `chart/bar/{BaseBarSeries,BarSeries,BarView}` + `component/{grid/GridView,axis/CartesianAxisView+AxisBuilder}`): COMPLETE — `swift build` GREEN (0 warnings), `swift test` 215 executed / 0 failures / 58 skipped (was 212; +3 real 6b tests, no regression). A cartesian bar `option` renders four bar `Rect`s through `ZRenderKit` (`BarChartRenderTests`), also exercising `NativePainter.renderToImage`.** See §35. Closeout fixed one real defect the killed workflow left: `SeriesModel.getBaseAxis()` returned `nil` via an `Any?`-return conversion, so bar x/width were NaN (§35b).
**Phase 6b.1 (AXIS RENDERING): the cartesian axes now draw too — axisLine, split(grid)Lines, ticks, and tick LABELS (x: A/B/C/D, y: 0–40).** The native `EChartsDemoGallery` render now matches echarts.js essentially 1:1. Four defects fixed: (1) `Grid.createAxisBiulders` + `createOrUpdateAxesView` were no-op stubs → un-stubbed to `new AxisBuilder → build()` per shown axis (they call the already-ported `cartesianAxisHelper.create/updateCartesianAxisViewCommonPartBuilder`); (2) the slim stand-in axis models never merged the per-type `axisDefault` (deferred `mergeDefaultAndTheme`) → `show` was nil → `shouldAxisShow` false → axes hidden; now `EChartsSlim` merges `axisDefault.option[type]` under the option; (3) a STALE `getScaleExtentForTickUnsafe(OrdinalScale)` fatalError placeholder in `scale/helper.swift` shadowed the real `scaleMapper` impl (overload-resolution trap) → removed; (4) `NativePainter.flattenDisplayList` skipped the per-element `update()` that `Storage` runs, so `ZRText` never built its `TSpan` children and all text dropped → now mirrors `Storage` (`beforeUpdate/update/afterUpdate`). Added `Sources/EChartsDemoGallery` (native vs echarts.js side-by-side) + `scripts/build-echarts-gallery.sh`.
**Phase 6b.2 (LINE vertical): a cartesian `series.line` now renders natively too** — minimal `chart/line/{LineSeries,LineView}` (a `Polyline` through `coord.dataToPoint` per datum, palette stroke; symbols/areaStyle/step/stack are documented PORT-TODOs), registered in `EChartsSlim`. `line-basic` in the gallery now renders on BOTH panes and matches echarts.js (modulo point symbols). Key gotcha: `LineSeriesModel` MUST override `static defaultOption` with `coordinateSystem:'cartesian2d'` — `decideCoordSysUsageKind` reads `getShallow("coordinateSystem")`, so without it the coord system is never injected and `LineView` renders nothing. `LineChartRenderTests` locks it in (216 tests / 0 failures).
**Phase 6a (COORDINATE SYSTEM + PIPELINE + COMPONENT-INSTANTIATION: `coord/cartesian` Grid/Cartesian2D/Axis2D/AxisModel + axis-helper cluster + the REAL `scaleRawExtentInfo`; `core/` Scheduler/task/CoordinateSystemManager/ExtensionAPI; `GlobalModel` component/series instantiation wired so `getComponent`/`eachSeries` return REAL `GridModel`/`CartesianAxisModel`/bar `SeriesModel`): COMPLETE — `swift build` GREEN, `swift test` 212 executed / 155 passed / 0 failures / 57 skipped (was 208; +4 new coord tests = 2 pass + 2 skip; no regression).** See §§31–34. **The dynamic-option→component pipeline left inert in §29 is now live; `dataToPoint` is exercised by a pixel oracle. The rendering vertical (views + slim orchestrator) is Phase 6b (§34).**
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

## 23. What landed in Phase 5b — the ECharts data engine (`echarts/src/data/`)

**Phase 5b (DATA-ENGINE: the columnar store + series data facade + diff + source/dimension pipeline):
COMPLETE — `swift build` GREEN, `swift test` 143 executed / 0 failures / 16 skipped, and the FIRST
ported ECharts unit tests (number + scale-interval) landed as a behavioral oracle.** Builds on the
Phase-5a `util/` + `scale/` layers (no integration breakage; no source edits to the existing layers).
The MODEL layer (Phase 5c) is still absent — `SeriesModel`/option access points are minimal protocols
/ `// PORT-TODO` stubs so data compiles standalone.

### The columnar store + series-data facade (`Sources/EChartsKit/data/`)
- [x] `data/DataStore.swift` ← `data/DataStore.ts` — the low-level columnar store: chunked `_chunks`
      typed columns, `appendData`/`appendValues`, `getRawIndex`/`get`/`getValues`, `getDataExtent`,
      `indexOfRawIndex`/`indicesOfNearest`, ordinal collection (`collectOrdinalMeta`), `map`/`modify`/
      `filter`/`selectRange`/`downSample`/`lttbDownSample`, `getMedian`, `clone`/`_copyCommonProps`.
- [x] `data/SeriesData.swift` ← `data/SeriesData.ts` — the high-level facade over `DataStore`: dimension
      bookkeeping (`_dimInfos`/`_dimSummary`), `initData`/`appendData`/`appendValues`, `getId`/`getRawIndex`,
      `getName`/`getItemModel`(stubbed for 5c), `each`/`map`/`filterSelf`/`selectRange`/`mapArray`,
      visual/layout state bags, `diff` key-getters, `cloneShallow`/`downSample`.
- [x] `data/DataDiffer.swift` ← `data/DataDiffer.ts` — the enter/update/exit diff (`add`/`update`/`remove`/
      `updateManyToOne`/`updateOneToMany`/`updateManyToMany`, `_executeOneToOne`/`_executeMultiple`,
      key-array dedup). Pairs with the Phase-3 animation system for data-driven transitions.
- [x] `data/Source.swift` ← `data/Source.ts` — `Source` (seriesLayoutBy / sourceFormat / dimensionsDefine /
      startIndex / encodeDefine), `createSource`/`createSourceFromSeriesDataOption`, `detectSourceFormat`.
- [x] `data/SeriesDimensionDefine.swift` ← `data/SeriesDimensionDefine.ts` — the per-dimension descriptor.
- [x] `data/OrdinalMeta.swift` (already landed Phase-5a stub; relied on here) — ordinal category mapping.

### Data helpers (`Sources/EChartsKit/data/helper/`)
- [x] `helper/dataValueHelper.swift` ← `helper/dataValueHelper.ts` — value parse/compare (`parseDataValue`,
      `createOrdinalSortInfo`, `SortOrderComparator`).
- [x] `helper/SeriesDataSchema.swift` ← `helper/SeriesDataSchema.ts` — dimension schema + `createDimensions` glue.
- [x] `helper/dimensionHelper.swift` ← `helper/dimensionHelper.ts` — `summarizeDimensions`, dimension-type maps.
- [x] `helper/sourceHelper.swift` ← `helper/sourceHelper.ts` — `prepareSource`/`querySeriesUpstreamDatasetMetaRawData`-class glue.
- [x] `helper/createDimensions.swift` ← `helper/createDimensions.ts` — dimension inference from source + encode.
- [x] `helper/dataProvider.swift` ← `helper/dataProvider.ts` — `DefaultDataProvider`, `getRawSourceItemGetter`/`getDataItemValue` accessors.
- [x] `helper/dataStackHelper.swift` ← `helper/dataStackHelper.ts` — `enableDataStack`/`getStackedDimension` (via the `DataStackSeriesData` PORT-TODO bridge).

### Phase 5b — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `data/DataStore.swift` | `data/DataStore.ts` | complete | **minor-issues (3)** | `getMedian` can TRAP out-of-bounds on dims with NaN/empty points (upstream returns NaN) — §24 #1; `clone()`/`_copyCommonProps` value-copies `_dimensions` (struct) vs upstream reference-share — §24 #2; `downSample` drops `\|\| 0` (verified inert) |
| `data/SeriesData.swift` | `data/SeriesData.ts` | complete | **major-issues (1)** | `diff()` key-getters feed the loop index `i` to `getId` instead of the rawIndex `value` — wrong diff keys on FILTERED data (dataZoom) — §24 #0 (the one real bug to fix) |
| `data/DataDiffer.swift` | `data/DataDiffer.ts` | complete | faithful | — |
| `data/Source.swift` | `data/Source.ts` | complete | minor-issues (1) | `:486` dead `rawItem == nil` branch (loose dim is non-optional `Any`); coercion path always runs — faithful shape preserved |
| `data/SeriesDimensionDefine.swift` | `data/SeriesDimensionDefine.ts` | complete | (foundation sweep) | — |
| `data/helper/dataValueHelper.swift` | `helper/dataValueHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/SeriesDataSchema.swift` | `helper/SeriesDataSchema.ts` | complete | (foundation sweep) | — |
| `data/helper/dimensionHelper.swift` | `helper/dimensionHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/sourceHelper.swift` | `helper/sourceHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/createDimensions.swift` | `helper/createDimensions.ts` | complete | (foundation sweep) | — |
| `data/helper/dataProvider.swift` | `helper/dataProvider.ts` | complete | (foundation sweep) | — |
| `data/helper/dataStackHelper.swift` | `helper/dataStackHelper.ts` | complete | (foundation sweep) | `:309`/`:315` redundant `as? DataStackSeriesData` (always succeeds) — PORT-TODO bridge for `getCalculationInfo`, left to mirror upstream call shape until 5c |

Also reviewed (carried scale/util mirrors, all **faithful**): `scale/Interval.swift`, `scale/Scale.swift`
— no semantic divergences; two benign notes (`getLabel` `precision as! Double` traps on a non-Double
caller; `Scale._isBlank` initialized `false` vs TS `undefined`, both falsy).

Roll-up (ported `.ts` mirrors with a review verdict): **majority faithful; 1 major-issues
(`SeriesData.diff`), 3 minor (`DataStore`), plus `Source` minor.** One genuine bug surfaced (§24 #0).

---

## 24. Build & test status — Phase 5b (incl. the FIRST ported ECharts unit tests)

- **`swift build`: GREEN.** The data engine compiled cleanly against the already-ported `util/` and
  `scale/` layers on the first iteration — **no integration edits to existing sources were required**,
  no DataStore/SeriesData/diff math was weakened, and no call sites needed model stubs beyond what the
  parallel translation already added.
- **`swift test`: GREEN — 143 executed / 0 failures / 16 skipped** (up from Phase-5a's 115/14). The 14
  pre-existing skips are all ZRenderKit faithfulness-gaps (`util.clone` TypedArray/user-class,
  `util.merge` null/undefined target — unrelated to data); the 2 NEW skips are the scale extreme-ticks
  tests that need `createChart` + model/coord (Phase 5c).
- **FIRST ported ECharts unit tests** (a new `EChartsKitTests` target in `Package.swift`, deps
  EChartsKit + ZRenderKit — the first behavioral oracle for the Phase-5a scale math):
  - `Tests/EChartsKitTests/NumberUnitTests.swift` ← `test/ut/spec/util/number.test.ts` (24 methods):
    `linearMap` (accuracy/clamp/noClamp/zeroInterval), `parseDate`, `reformIntervals`, `getPrecision`/
    `getPrecisionSafe` (incl. the 500-iter fuzz), `addSafe` (full ~250-case decimal.js table),
    `getPercentWithPrecision`, `quantityExponent`, `quantity`, `nice`, `isNumeric`/`numericToNumber`,
    `getAcceptableTickPrecision`/`getPixelPrecision`.
  - `Tests/EChartsKitTests/ScaleIntervalUnitTests.swift` ← `test/ut/spec/scale/interval.test.ts`: the
    portable `helper.intervalScaleNiceTicks(...)` half of `doSingleTestDeal` (4 explicit cases +
    `randomCover` 500+200 iters, asserting finite interval/precision and niceTickExtent ⊂ extent).
  - **EChartsKitTests: 28 methods, 26 pass / 0 fail / 2 skip.** Skips: `test_extreme_ticks_min_max` and
    `test_extreme_ticks_small_value` (both need `createChart` + CartesianAxisModel + a full axis →
    Phase 5c). The `scaleCalcNice2`/new-IntervalScale half of the ticks cases was omitted in-place
    (documented in-test; depends on coord/axisNiceTicks, Phase 5c).
- **Specs NOT ported (no module/scope):** `util/format` has NO upstream spec; there is NO
  `data/DataStore.test.ts` upstream; `data/{dataValueHelper,createDimensions,SeriesData,dataTransform}.test.ts`
  exist but hinge on JS dynamic-typing of `unknown` values + Source/`SeriesModel`/`createSource` surfaces
  + deep object `toEqual` — deferred behind the scale-math priority until Phase 5c lands the model layer.
- **No `Sources/` was edited to paper over any behavioral divergence.** The only Source touches were a
  case-collision filename rename (build-system, not behavior) and header-provenance notes.

---

## 25. Phase 5b — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — the one real bug to fix (review-flagged)
0. **`SeriesData.diff()` key-getters pass the WRONG argument to `getId`** (`SeriesData.swift:1035–1040`).
   The closures `{ _, idx in SeriesData.getId(otherList!, idx) }` discard the value and pass the loop
   POSITION `idx`. `DataDiffer.swift:326` invokes `keyGetter(arr[i], i)` (value first), and upstream
   `SeriesData.ts:1149–1154` binds `idx` to that FIRST arg = the rawIndex from `getStore().getIndices()`.
   So the port keys items by display position, not rawIndex. **When `getIndices()` is identity (fresh/
   unfiltered data) `arr[i] === i` so there is no observable difference; but after `filterSelf`/
   `selectRange` (dataZoom) the indices are a non-identity subset (e.g. `[2,5,9]`) and the diff produces
   wrong ids → wrong add/update/remove classification → broken update animations / state continuity on
   filtered data.** Correct port: `{ value, _ in SeriesData.getId(otherList!, value as! Int) }` (and the
   same for `thisList`). FIX before any dataZoom/transition work in 5c+.

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`DataStore.getMedian` can TRAP out-of-bounds** (`DataStore.swift:559–579`). It faithfully copies
   upstream's index math using `len = count()` to index `dimDataArray`, but `dimDataArray` only holds the
   NON-NaN values. With any NaN/empty points (common in line charts) `dimDataArray.count < len`, so
   `dimDataArray[(len-1)/2]`/`[len/2]` go out of bounds → Swift fatal crash, where upstream TS
   (`DataStore.ts:525–531`) returns `undefined`→NaN. Behavioral divergence: crash vs NaN.
2. **`DataStore` value-vs-reference divergence across `clone()`** (`_copyCommonProps`, `DataStore.swift:1332`).
   Upstream `_copyCommonProps` shares `_dimensions` BY REFERENCE (`target._dimensions = this._dimensions`,
   `DataStore.ts:1258`) — and likewise non-picked `_chunks` columns. The port models
   `DataStoreDimensionDefine` as a `struct` and value-copies, so in-place dim mutations after a clone
   (`collectOrdinalMeta` setting `ordinalMeta`/`type`/`ordinalOffset`; `ensureCalculationDimension` adding
   dims) are visible to sibling clones in TS but NOT in Swift (each clone is independent), and non-picked
   columns are COW value-copies not shared objects. Practical trigger is narrow under the actual call order
   (collect/ensure run at init/stack time before filter/map/downSample clones), but it is a genuine
   reference-semantics divergence — audit before Phase-5c stack/transition wiring relies on shared dims.
3. **`Source.swift:486` dead null branch** — upstream guards `rawItem == null`; the Swift loose dimension
   value is non-optional `Any`, so the null branch (and its dependent ternary else) is unreachable. The
   `plusEmptyString` coercion path always runs, matching the non-null case. Faithful shape preserved.
4. **`DataStore.downSample` drops `Math.min(..., len-1) || 0`** (`DataStore.swift:1134`) — verified a true
   no-op (`sampleIndex` returns `Int`, cannot be NaN; sum is ≥ 0), the `|| 0` only ever mattered for a JS
   NaN that cannot occur in Swift. Noted for mechanical-resync exactness, not a behavioral divergence.

### MODEL refs stubbed for Phase 5c (PORT-TODOs the data layer left open)
5. **`SeriesData.getItemModel`/`getModel`/option access** are minimal-protocol / `// PORT-TODO` stubs —
   the real `SeriesModel`/`Model` does not exist yet. `getName`/visual defaults that read model option are
   the seams Phase 5c must wire.
6. **`dataStackHelper` `getCalculationInfo` bridge** (`dataStackHelper.swift:309/315`) — `data` is cast
   `as? DataStackSeriesData` (redundant today since `SeriesData` already conforms; emits a warning). Left
   to mirror upstream's `data.getCalculationInfo('stackedDimension'/'stackResultDimension')` call shape
   until 5c provides the real `getCalculationInfo`.
7. **`scale/Interval.getLabel` `precision as! Double`** traps if a caller stores `opt.precision` as a
   non-Double numeric. Consistent with number→Double; faithful callers (model `'auto' | number`) unaffected.

> Carry-over still open from §§4/10/16/21/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence
> (major — the ECharts option/visual layer will force this), the value-type `shape`/`style` keyed-animation
> seam, `useState`/states still stubbed in `Element`, `util.merge` null-guard gap (the §22 fidelity-hardening
> pass — the model option-merge in 5c is exactly where the deep-merge/null-guard items become load-bearing),
> `Group.children()` value-copy, and the `Swift.min/max` / `|| 0`-vs-`?? 0` NaN-policy items.

---

## 26. Phase 5c plan (HISTORICAL — executed; results in §§27–30) — the `model/` spine (HIGHEST-RISK layer: the dynamic option-merge system)

**Goal:** the ECharts model spine — `Model` + mixins, `ComponentModel`, `SeriesModel`, `GlobalModel`,
`OptionManager`, and `model/globalDefault` — i.e. the **dynamic option-merge / normalize / default-cascade
system**. This is the highest-risk layer: it is where ECharts' deeply-dynamic JS option object (absent /
`null` / `NaN` / mixed-type config, arbitrary nesting, `mergeOption`, default cascades, query paths) meets
Swift's value/type system, and it is what `data/` (§§23–25) was deliberately stubbed against. It directly
forces the §22 fidelity-hardening decisions (`util.merge` null-guard, `'key' in obj` vs `!= nil`, `|| 0`
vs `?? 0`, JS truthiness) — **do that hardening pass on `util/` FIRST, then port `model/`.**

### 26a. Upstream files (port order) — `echarts/src/model/`
| Upstream file | Swift target | Already-ported deps | Nature |
|---|---|---|---|
| `model/Model.ts` | `model/Model.swift` | `util/{clazz,model,component}` (Phase-5a), `util.merge`/`clone`/query | the base: `get`/`getShallow`/`getModel`/`option`, `mergeOption`, mixin host |
| `model/mixin/{lineStyle,areaStyle,textStyle,itemStyle}.ts` + `model/mixin/makeStyleMapper.ts` | `model/mixin/*.swift` | `Model`, `util` | the style-getter mixins (`getItemStyle`/`getLineStyle`/…) — Swift composition vs TS `mixin()` |
| `model/Component.ts` (`ComponentModel`) | `model/Component.swift` | `Model`, `util/{component,clazz}`, `ComponentType`/subType registry | component base + the `extend`/`registerClass`/`getClass` registry + `defaultOption` cascade |
| `model/Series.ts` (`SeriesModel`) | `model/Series.swift` | `ComponentModel`, `data/SeriesData`+helpers (§23 — wires the §25 #5 stubs), `Source`/`createSource` | series base: `getInitialData`/`getData`/`getRawData`, `formatTooltip`, `mergeDefaultAndTheme` |
| `model/Global.ts` (`GlobalModel`) | `model/Global.swift` | `ComponentModel`, `OptionManager`, `util/model` (`mappingToExists`/`makeIdAndName`) | the option root: `mergeOption`, component instance create/merge/remove, `getComponent`/`queryComponents`/`eachSeries` |
| `model/OptionManager.ts` | `model/OptionManager.swift` | `GlobalModel`, `util/model`, media-query/timeline | raw-option lifecycle: `setOption`/`mergeOption`, media-query resolution, timeline option, `getTimelineOption` |
| `model/globalDefault.ts` | `model/globalDefault.swift` | — | the top-level default option object |
| (support) `model/referHelper.ts`, `model/internalComponentCreator.ts` | as needed | `Global`, `util/model` | coord-sys refer + internal component creation |

### 26b. Risk surface + sequencing
- **Option merge is the crux:** `Model.mergeOption`/`GlobalModel.mergeOption` lean on faithful deep-merge
  with null/undefined semantics (`util.merge` — §25 carry-over) and `'key' in option` existence checks.
  The value-type `Any`/dictionary modeling of the option tree must preserve absent-vs-`null`-vs-falsy
  distinctions or default cascades silently diverge. **This is the §22 hardening pass's payoff point.**
- **Registry/`extend` dynamics:** `ComponentModel.extend`/`registerClass`/`getClass` and subType lookup are
  JS-prototype/`this`-dynamic; port to a Swift type-registry + protocol surface (mirror names, mark the
  deviation `// PORT-TODO`).
- **Mixins:** TS `mixin(Model, LineStyleMixin)` → Swift protocol-extension composition; keep getter names
  (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`) identical.
- **Sequencing:** `util/` fidelity-hardening (merge/null/`in`/NaN) → `Model` + mixins → `ComponentModel`
  (+registry) → `SeriesModel` (wires the §25 #5 `getItemModel`/`getModel` data stubs to real models) →
  `GlobalModel` → `OptionManager` + `globalDefault`. Each stage ports its matching upstream spec
  (`test/ut/spec/model/*`) as the behavioral oracle and keeps the §12 upstream-sync rule.
- **After 5c**, the data layer's model stubs (§25 #5/#6) resolve, unblocking `scale`↔`axisModel`,
  `coord/cartesian` (the original §22 step 4), and the first `ChartView`.

---

## 27. What landed in Phase 5c — the ECharts model spine (`echarts/src/model/`)

**Phase 5c (MODEL SPINE: the dynamic option-merge / normalize / default-cascade system —
`Model` + 7 mixins, `ComponentModel`, `SeriesModel`, `GlobalModel`, `OptionManager`, `globalDefault`
+ support): COMPLETE — clean `rm -rf .build && swift build` GREEN across ZRenderKit/NativePainter/
EChartsKit/DemoGallery, `swift build --build-tests` GREEN, `swift test` GREEN (208 executed / 55
skipped / 0 failures across the whole package; 26 NEW active model-layer tests all pass).** The
parallel-translated spine integrated with the Phase-5a/5b `util/`+`scale/`+`data/` layers with **no
source edits** to the existing layers. This is the crux dynamic-option layer: `Model` is a reference
type, dynamic bags are `[String: Any]`, deep-merge routes through `util.merge` (null/undefined guard),
and `Model.get(path)` does dynamic keyed/dotted-path access with parent-model cascade.

### The base + mixins (`Sources/EChartsKit/model/` + `model/mixin/`)
- [x] `model/Model.swift` ← `model/Model.ts` — the base: `get`/`getShallow`/`getModel`/`option`,
      `_doGet` keyed+dotted path access, parent-model cascade + `ignoreParent`, `mergeOption` deep-merge,
      `isEmpty`, `clone`, `isAnimationEnabled`, mixin host. Reference type (`final/open class`).
- [x] `model/mixin/makeStyleMapper.swift` ← `model/mixin/makeStyleMapper.ts` — the style-key → getter
      mapper factory shared by the style mixins.
- [x] `model/mixin/{itemStyle,lineStyle,areaStyle,textStyle}.swift` ← matching `model/mixin/*.ts` — the
      style-getter mixins (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`). **TS `mixin()`
      is realized as Swift protocol + protocol-extension composition; getter names kept identical.**
- [x] `model/mixin/palette.swift` ← `model/mixin/palette.ts` — `getColorFromPalette`/color-cache
      (`PaletteMixin` protocol).
- [x] `model/mixin/dataFormat.swift` ← `model/mixin/dataFormat.ts` — `getDataParams`/`formatTooltip`
      glue (`DataFormatMixin`).

### Component / Series / Global / OptionManager (`Sources/EChartsKit/model/`)
- [x] `model/Component.swift` ← `model/Component.ts` (`ComponentModel`) — component base + the
      `mergeDefaultAndTheme`/`mergeOption`/`getDefaultOption` default cascade, `mainType`/`subType`,
      `getBoxLayoutParams`, the class-registry surface (`registerClass`/`getClass`/`getAllClassMainTypes`/
      `topologicalTravel`).
- [x] `model/Series.swift` ← `model/Series.ts` (`SeriesModel`) — series base: `getInitialData`/`getData`/
      `getRawData`, `mergeDefaultAndTheme`, `mergeOption`, `isAnimationEnabled`. **Wires the §25 #5 data
      stubs to real types: `getInitialData(_:_:) -> SeriesData?`** (see §29 below).
- [x] `model/Global.swift` ← `model/Global.ts` (`GlobalModel`) — the option root: `mergeOption`/
      `_mergeOption`, `getTheme()` (returns a real `Model`), `mergeTheme`, `getComponent`/`queryComponents`/
      `eachSeries`/`getSeries*`/`reCreateSeriesIndices`, `isNotTargetSeries`. **Component/series
      instantiation from the option tree is stubbed to nil (documented — see §29/§30).**
- [x] `model/OptionManager.swift` ← `model/OptionManager.ts` — raw-option lifecycle: `setOption`/
      `mergeOption`, timeline `getTimelineOption`/`options`, media `getMediaOption`/`parseRawOption`.
- [x] `model/globalDefault.swift` ← `model/globalDefault.ts` — the top-level default option object.
- [x] `model/referHelper.swift` ← `model/referHelper.ts`, `model/internalComponentCreator.swift`
      ← `model/internalComponentCreator.ts` — coord-sys refer + internal-component creation support.

### Phase 5c — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `model/Model.swift` | `model/Model.ts` | complete | minor-issues (3) | `isAnimationEnabled` truthy-non-dict option skips parent-recursion (dict-cast gate); `getModel` returns a Model over a VALUE-COPY subtree (no mutate-through — inherent to `[String:Any]` bag); `clone()` returns base `Model` not the concrete subclass (PORT-TODO) |
| `model/mixin/makeStyleMapper.swift` | `model/mixin/makeStyleMapper.ts` | complete | (foundation sweep) | — |
| `model/mixin/{itemStyle,lineStyle,areaStyle,textStyle}.swift` | `model/mixin/*.ts` | complete | (foundation sweep) | TS `mixin()` → Swift protocol-extension composition |
| `model/mixin/palette.swift` | `model/mixin/palette.ts` | complete | (foundation sweep) | — |
| `model/mixin/dataFormat.swift` | `model/mixin/dataFormat.ts` | complete | (foundation sweep) | — |
| `model/Component.swift` | `model/Component.ts` | complete | minor-issues (2) | THEME-MERGE stub un-wired against a now-STALE reason (`getTheme()` exists — §615) → per-mainType theme options never merged (masked: new-component init is a documented no-op); layout-mode merge deferred (no `util/layout`) |
| `model/Series.swift` | `model/Series.ts` | complete | **major-issues (3)** | see §29 #0a/#0b/#0c (the two value-vs-reference bugs + the `animationThreshold ?? 0` NaN/`>undefined` divergence) |
| `model/Global.swift` | `model/Global.ts` | complete | minor-issues (3) | `isNotTargetSeries` coerces id/name before compare (upstream uses raw `!==`); `_mergeOption` value-copy write-back vs in-place; `visitComponent`/instantiation stubbed → dynamic-option→component pipeline presently inert (PORT-TODO, blocked by scaffolding) |
| `model/OptionManager.swift` | `model/OptionManager.ts` | complete | **major-issues (2)** | see §29 #0d (MEDIA UNITS silently dropped — dynamic bag cast to a foreign `MediaUnit` struct); minor `hasTimeline` malformed-input edge |
| `model/globalDefault.swift` | `model/globalDefault.ts` | complete | faithful | — |
| `model/referHelper.swift`, `model/internalComponentCreator.swift` | `model/{referHelper,internalComponentCreator}.ts` | complete | (foundation sweep) | — |

Roll-up (ported `.ts` mirrors with a review verdict): **majority faithful/foundation-sweep; 3
minor-issues (`Model`, `Component`, `Global`), 2 major-issues (`Series`, `OptionManager`).** The
dynamic option engine (`Model.get`/`mergeOption`) itself pins clean; the major-issues are the
value-vs-reference seam (`Series` passing un-merged option to `getInitialData`) and one real
correctness break (`OptionManager` media drop) — see §29.

---

## 28. Build & test status — Phase 5c (incl. the ported model unit tests)

- **`swift build`: GREEN.** Clean from-scratch build compiled ZRenderKit, NativePainter, EChartsKit,
  and DemoGallery first try; **no source edits to the existing 5a/5b layers were required** — the
  parallel-translated model spine integrated cleanly. `swift build --build-tests`: GREEN. One benign
  non-blocking warning at `Series.swift:582` (conditional downcast `GlobalModel?` → palette-mixin
  equivalent to an implicit optional conversion) left untouched to avoid behavior change.
- **`swift test`: GREEN — 208 executed / 55 skipped / 0 failures** (whole package; up from Phase-5b's
  143/16). Deterministic across repeated runs (ran `componentDependency` 3× + full suite). Model-layer
  tests added this phase: **65 across 6 new files = 26 active (ALL PASS) + 39 skipped.**
- **NEW test files** (all under `Tests/EChartsKitTests/`):
  - `ModelUnitTests.swift` — **15 pass.** The crux (no upstream `Model.test.ts` exists; pins the ported
    dynamic-option engine directly): `get()`/`get(path)`/`get([path])` keyed+dotted access, empty-segment
    skip, parent-model cascade + `ignoreParent`, `getShallow`, `getModel` sub-Model wrapping +
    `resolveParentPath` chain, `mergeOption` deep-merge, `isEmpty`, `clone` independence,
    `isAnimationEnabled` truthiness/inheritance.
  - `UtilModelUnitTests.swift` ← `test/ut/spec/util/model.test.ts` — **4 pass + 1 skip.** `compressBatches`
    (namespace `model`), `removeDuplicates` (resolve1/priority/edges).
  - `ComponentDependencyUnitTests.swift` ← `test/ut/spec/model/componentDependency.test.ts` — **7 pass.**
    `registerClass`/`getAllClassMainTypes`/`topologicalTravel` over fixed file-scope `ComponentModel`
    subclasses (upstream runtime class-gen has no Swift equivalent): base/empty/isolate/diamond/loop
    (Circular throw)/missingSomeNode/subType.
  - `GlobalModelUnitTests.swift` (22 skip), `TimelineMediaOptionsUnitTests.swift` (10 skip),
    `ComponentMissingUnitTests.swift` (6 skip) — every upstream `it` preserved as an `XCTSkip` with reason.
- **Skips (39) with reasons:** `Global.test.ts` (22) + `timelineMediaOptions.test.ts` (10) +
  `componentMissing.test.ts` (6) are all driven through `createChart()`/`init()`+`use()`/resize +
  `getData()`/`getInitialData()` — need the ChartView map + Scheduler + series-data pipeline + real
  component models (Phase 6). `removeDuplicates_no_resolve_has_value` (1): upstream keeps BOTH `undefined`
  and `null` (distinct `+''` keys); Swift collapses both to nil (CONVENTIONS §6) — cannot port faithfully.
- **ONE REAL BUG FOUND AND FIXED** (the only `Sources/` behavior change this phase) — a §3/§4
  value-vs-reference hazard: **`modelUtil.compressBatches` / `makeMap` mutated a value-type copy**
  (`Sources/EChartsKit/util/modelUtil.swift` ~line 992/998). Upstream `makeMap(batchB, mapB, mapA)`
  mutates `otherMap` (a JS reference object) in place via `otherDataIndices[dataIndex] = null` so
  cross-batch duplicates are removed from resultA; the Swift `otherMap` was a plain value parameter, so
  the nulling hit a throwaway copy and cross-batch duplicates were NEVER removed from batchA (failed 5/7
  `compressBatches_base` sub-cases). **Fix:** made `makeMap`'s `otherMap` parameter `inout` (matching
  upstream reference semantics) and pass `&mapA` / an empty `&noOtherMap`. All `compressBatches` cases pass.
- **DOCUMENTED FAITHFULNESS GAP (pre-existing PORT-TODO, not newly introduced):** Swift `Dictionary`
  key-iteration order is unspecified (`clazz.getAllClassMainTypes`, `modelUtil.compressBatches` maps),
  whereas upstream relies on JS object iteration order (integer-like keys ascending; string keys
  insertion-order). Consequence: `compressBatches` item/dataIndex ordering and `topologicalTravel`
  emission order are nondeterministic in the port. The ported tests assert order-normalized content
  (values faithful; only dict-order nondeterminism normalized). Content correctness is fully asserted;
  closing the ordering divergence needs an order-preserving dictionary.

---

## 29. Phase 5c — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — value-vs-reference / real-correctness (review-flagged, fix before Phase 6 wiring relies on them)
0a. **`Series.init` passes the UN-merged option to `getInitialData`** (`Series.swift:210`). TS
   `Series.ts:283-287` merges theme+defaults into `option` IN PLACE (option === `this.option`), so
   `getInitialData(option, ecModel)` receives the fully-merged option. In Swift the option bag is a value
   type: `mergeDefaultAndTheme` merges defaults into `self.option` and writes back there
   (`Series.swift:265-269`), but `Series.swift:210` then calls `getInitialData(option, …)` with the
   original, default-less PARAM. **Consequence:** concrete series whose `getInitialData` reads its
   `option` arg see none of the merged defaults/theme. **Fix:** pass `self.option`.
0b. **`Series.mergeOption` passes only the incremental delta to `getInitialData`** (`Series.swift:303`).
   TS `Series.ts:302` `newSeriesOption = merge(this.option, newSeriesOption, true)` rebinds the local to
   the merged `this.option`; Swift merges into `self.option` (`:288-292`) but does NOT rebind, so `:303`
   passes the raw partial delta. **Consequence:** data rebuilt from an option missing everything not in
   the incremental update. **Fix:** pass the merged `self.option` (`target`).
0c. **`OptionManager` MEDIA UNITS silently dropped** (`OptionManager.swift:390`, unflagged correctness
   break). `parseRawOption` does `util.each(mediaOnRoot as? [MediaUnit])`, but `mediaOnRoot =
   rawOption["media"]` comes from the dynamic `ECUnitOption=[String:Any]` bag and holds `[[String:Any]]`
   dicts, not the typed `MediaUnit` structs (`util/types.swift:1046`); `[[String:Any]] as? [MediaUnit]`
   returns nil, so the loop body never runs → `mediaList`/`mediaDefault` stay empty → `getMediaOption`
   short-circuits and returns `[]`. The sibling timeline `options` path survives only because
   `[ECUnitOption]` is itself `[[String:Any]]`. **Fix:** read media entries dynamically as `[[String:Any]]`
   and access `["option"]`/`["query"]` by key (as the timeline path already does).

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`Series.isAnimationEnabled` threshold default** (`Series.swift:556`): `getShallow("animationThreshold")
   as? Double ?? 0`. When absent, JS `count > undefined` = false (animation stays on); Swift `count > 0` =
   true for non-empty data, wrongly disabling animation. Treat missing threshold as no-cap (Infinity).
2. **`Component` THEME-MERGE un-wired against a now-STALE reason** (`Component.swift:196-211`). Upstream
   `mergeDefaultAndTheme` merges `ecModel.getTheme().get(mainType)` (overwrite=false) BEFORE the default
   (`Component.ts:169-171`); the port skips it (`_ = ecModel`). The PORT-TODO reason ("GlobalModel has no
   getTheme()") is no longer true — `Global.swift:615` defines `getTheme() -> Model`. **Wire to
   `ecModel.getTheme().get(mainType)` merged (overwrite=false) before the default.** Severity reduced
   (not eliminated): new-component init is itself a documented no-op (Global instantiation stubbed), so
   `mergeDefaultAndTheme` is not reached yet; the separate top-level `mergeTheme` (Global.swift:1069) does
   NOT substitute — upstream keeps both mechanisms.
3. **`Model.isAnimationEnabled` non-dict-option parent-recursion** (`Model.swift:244`). Upstream recurses
   into `parentModel` for a truthy non-dict option with no `animation`; the Swift dict-cast gate
   short-circuits to nil. Edge case (option is normally a dict for animatable models).
4. **`Model.getModel` returns a Model over a VALUE-COPY subtree** (`Model.swift:177-191`). Upstream
   `_doGet` returns a reference to the nested option object (mutate-through); Swift extracts a value copy,
   so a child-Model mutation does NOT propagate to the parent tree. Inherent to the `[String:Any]` bag
   modeling; document in header for any mutate-through-getModel pattern.
5. **`Model.clone()` drops the concrete subclass** (`Model.swift:210`, documented PORT-TODO). Upstream
   `new (this.constructor)(clone(option))` preserves the subtype; Swift always returns base `Model`.
6. **`Global.isNotTargetSeries` coerces before comparing** (`Global.swift:1062-1063`). Upstream uses raw
   `!==` (no coercion) on id/name; Swift runs `convertOptionIdName` first, so a numeric `seriesId`/
   `seriesName` in a `restoreData` payload matches a string component id/name in Swift but not upstream.
7. **`Global._mergeOption` value-copy write-back vs in-place** (`Global.swift:342` + `:564`). Upstream
   mutates the shared `this.option` reference throughout the merge; the port operates on a local copy and
   publishes only at the end, and `optionsByMainType.append(componentModel.option)` copies by value.
   Any reentrant read of `ecModel.option` during component init/merge would see the pre-merge snapshot.
   Masked today because component instantiation is stubbed; will surface once registry/init lands.
8. **`OptionManager.hasTimeline` malformed-input edge** (`:362-366`) — `as? [ECUnitOption]` is nil for a
   non-array `options`, whereas upstream uses truthiness; only affects malformed input.

### Dynamic-option-model decisions (design, standing)
- **`Model` is a reference type; dynamic bags are `[String: Any]`; deep-merge routes through `util.merge`
  (null/undefined guard); `Model.get(path)` does keyed/dotted-path access** — the mandated modeling
  (§26b). Two consequences are inherent, not bugs: `getModel` value-copy (#4) and the value-type
  write-back seam (#7) — both flow from `[String:Any]` being a value type rather than a JS reference.
- **Mixins:** TS `mixin()` is realized as Swift protocol + protocol-extension composition
  (`ItemStyleMixin`/`LineStyleMixin`/`AreaStyleMixin`/`TextStyleMixin`/`PaletteMixin`/`DataFormatMixin`),
  getter names kept identical (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`).

### Stubbed surfaces — whole features deferred to Phase 6 (each is `// PORT-TODO`, faithful signatures)
- **Component/series instantiation from the option tree is INERT.** `Global.visitComponent`
  (`:404-406`) + component-create (`:500-529`, `componentModel = nil`) are stubbed, and
  `normalizeToArray<ComponentOption>` over the dynamic `[String:Any]` bag returns `[]`, so
  `_componentsMap['series']` stays empty and `eachSeries`/`getSeries*`/`reCreateSeriesIndices` operate on
  nothing. The crux dynamic-option → component pipeline is present but presently inert — it lands with
  the registry/`ChartView` map in Phase 6.
- **Genuine Phase-6 deferrals** (faithful-signature PORT-TODO stubs, none weakening merge/get/data
  logic): `coord/CoordinateSystem`, `coord/Axis`, `core/Scheduler`+`task`, `data/helper/sourceManager`,
  `visual/LegendVisualProvider`, tooltip/legend/marker/brush components, `util/layout`, `util/symbol`.

### Does `Series.getInitialData` build a real `SeriesData`?
**Partially — the type wiring is real, the base body is intentionally an override seam.** The §25 #5
data stubs are now consumed via the real types: `Series.getInitialData(_:_:) -> SeriesData?` returns a
real `SeriesData?` (base returns `nil`, faithful to upstream's `return;` meant to be overridden by
concrete series), `Series.init` calls it and asserts non-nil (`Series.swift:213`), and `getData`/
`getRawData` traffic in the real `SeriesData`/`GlobalModel` types (no more minimal-protocol stubs).
**No concrete series (e.g. `BarSeries`) exists yet**, so no real column-building `getInitialData`
override runs end-to-end — that is the first thing Phase 6 lands (the §29 #0a/#0b un-merged-option fixes
must precede it so the override sees merged defaults).

---

## 30. The ECharts model spine is in place — Phase 6 plan (the first real chart: bar vertical → pixels through ZRenderKit)

**Goal:** the first END-TO-END vertical — a hand-built `option` (`{xAxis, yAxis, series:[{type:'bar',
data}]}`) flows through `GlobalModel` → coord/cartesian → `Scheduler`/`Task` (processor/visual/layout) →
`BarView` and renders a REAL bar chart through the complete `ZRenderKit` (`Group`/`Rect`/`Text` +
animation + interaction). This closes the dynamic-option → component pipeline left inert in §29 and
turns the 39 `createChart`-driven skips (§28) green.

### Pre-Phase-6 (do FIRST): resolve the §29 majors + the standing hardening carry-over
- Fix `Series` #0a/#0b (pass the MERGED `self.option` to `getInitialData`) and `OptionManager` #0c
  (read media dynamically) — they are load-bearing the moment a concrete series builds data / a media
  query resolves. Wire `Component` theme-merge #2 (now-unblocked by `getTheme()`).
- Close the `Global` instantiation stub (§29 stubbed surfaces): make `visitComponent` iterate the dynamic
  `[String:Any]` option bag (not `normalizeToArray<ComponentOption>`) and instantiate via the
  `ComponentModel` registry so `_componentsMap`/`eachSeries` are populated.
- The §22 fidelity-hardening carry-over (`util.merge` null-guard, `'key' in obj` vs `!= nil`, `|| 0` vs
  `?? 0`, JS truthiness) is now maximally load-bearing — the option→component→coord path feeds exactly
  these edge values.

### 30a. `coord/cartesian/` — Axis + Scale wiring + `dataToPoint` (`echarts/src/coord/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `coord/Axis.ts` | `coord/Axis.swift` | `scale/{Scale,Interval,Ordinal}` (5a), `util/number` |
| `coord/cartesian/Cartesian.ts`, `coord/cartesian/Cartesian2D.ts` | `coord/cartesian/*.swift` | `Axis`, `data/SeriesData` (5b) |
| `coord/cartesian/Axis2D.ts`, `coord/cartesian/AxisModel.ts`, `coord/cartesian/GridModel.ts` | `coord/cartesian/*.swift` | `ComponentModel` (5c — wires the §25 #5 `scale`↔`axisModel` seam) |
| `coord/cartesian/Grid.ts` (`dataToPoint`/`pointToData`, axis layout) | `coord/cartesian/Grid.swift` | `Cartesian2D`, `Axis2D`, `util/layout` (to port) |
| `coord/axisHelper.ts`, `coord/axisTickLabelBuilder.ts` | `coord/*.swift` | `scale` nice-ticks, `util/number` |

### 30b. `Scheduler` + the `Task`/`stream` pipeline (`echarts/src/core/` + `stream/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `core/task.ts` | `core/task.swift` | `util` |
| `core/Scheduler.ts` | `core/Scheduler.swift` | `task`, `GlobalModel` (5c), `data/SeriesData` (5b) |
| the per-stage graph: `createData`/`processData`/`visual`/`layout`/`render` | driven via Scheduler | pairs the 5b data engine with the 5c model |

### 30c. `visual/` + `layout/barGrid` (`echarts/src/visual/` + `layout/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `visual/style.ts`, `visual/seriesColor.ts`, `visual/VisualMapping.ts` | `visual/*.swift` | `model/mixin/palette` (5c), `data/SeriesData` |
| `layout/barGrid.ts` | `layout/barGrid.swift` | `coord/cartesian/Grid` (30a), `data/SeriesData`, `data/helper/dataStackHelper` (5b) |

### 30d. FIRST `ChartView` = `BarView` + `component/grid` + `component/axis` (`echarts/src/chart/` + `component/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `chart/bar/BarSeries.ts` (concrete `getInitialData` → real column build) | `chart/bar/BarSeries.swift` | `SeriesModel` (5c), `data/{SeriesData,helper/createDimensions}` (5b), `Source` |
| `chart/bar/BarView.ts` (`ChartView` → `Group{Rect}` per datum, enter/update/exit + animation) | `chart/bar/BarView.swift` | `ZRenderKit` `Group`/`Rect`/`Path` + animation (Phase 1–3), `DataDiffer` (5b) |
| `view/Chart.ts` (`ChartView` base), `view/Component.ts` | `view/*.swift` | `ZRenderKit` `Group`, `GlobalModel` |
| `component/grid/GridView.ts` | `component/grid/*.swift` | `coord/cartesian/Grid` (30a), `Group`/`Rect` |
| `component/axis/{CartesianAxisView,AxisBuilder}.ts` | `component/axis/*.swift` | `coord/Axis` (30a), `Group`/`Line`/`Text` (Phase 1–2) |
| `core/echarts.ts` (the `ECharts`/`init`/`setOption`/`_update` render driver — minimal slice) | `core/echarts.swift` | `GlobalModel`+`OptionManager` (5c), `Scheduler` (30b), `ZRender` host (Phase 4) |

**Sequencing:** §29 majors + instantiation stub → `coord/cartesian` (Axis+Scale+`dataToPoint`) →
`Scheduler`/`Task` → `visual/`+`layout/barGrid` → `BarSeries`+`BarView`+`grid`+`axis` + the minimal
`echarts.ts` driver. Each stage keeps the §12 upstream-sync rule and ports its matching upstream spec
as the behavioral oracle (turning the §28 `createChart`-driven skips green as `createChart`/`init`/
`getData` become real).

### After Phase 6: the simulator demo shows a REAL echarts-driven chart
Once §30d lands, the `DemoGallery` app can call the minimal `echarts.ts` driver with a real `option`
and render an actual ECharts-computed bar chart (data → scale → coord → layout → `Rect`s) on the
iOS/macOS simulator through `NativePainter` — the first time the full ECharts→ZRenderKit vertical is
visible on screen, not just hand-built `Group` trees.

---

## 31. What landed in Phase 6a — coord/cartesian + core pipeline + Global instantiation wiring

**Phase 6a (the §30 plan, executed up to but excluding the rendering views/orchestrator): COMPLETE.**
This lands the coordinate-system layer (`coord/cartesian` geometry + axis models + the full axis-helper
cluster + the REAL `scaleRawExtentInfo` replacing the §22 minimal stub), the core scheduling pipeline
(`Scheduler`/`task` + `CoordinateSystemManager` + `ExtensionAPI`), and closes the §29 **component/series
instantiation stub** in `GlobalModel` — so a hand-built bar-chart option now materializes real
`GridModel`/`CartesianAxisModel`/bar `SeriesModel` objects and `Cartesian2D.dataToPoint` maps data →
pixels. The rendering half (BarView/GridView/CartesianAxisView + the slim `echarts.ts` driver) is Phase
6b (§34). Six scout tiers landed as one integrated unit against the existing 5a/5b/5c layers.

### Coord — leaf helpers + coordinate-system interface (`Sources/EChartsKit/coord/`)
- [x] `coord/axisDefault.swift` ← `coord/axisDefault.ts` — per-axis-type default option.
- [x] `coord/axisStatistics.swift` + `coord/axisStatisticsMetricsImpl.swift` ←
      `coord/axisTickLabelBuilder`-adjacent metrics — tick/label statistics over the real `Axis`.
- [x] `coord/CoordinateSystem.swift` ← `coord/CoordinateSystem.ts` — `CoordinateSystem`/
      `CoordinateSystemMaster` protocols (`AnyObject`), `dataToPoint`/`pointToData`/`getViewRect`
      surface + `isGeoLikeCoordSys`.
- [x] `coord/axisModelCommonMixin.swift` ← `coord/axisModelCommonMixin.ts` — the axis-model mixin
      (`getCoordSysModel`, `axis`/`option` requirements).

### Coord — axis base + helper cluster + REAL scaleRawExtentInfo (landed as one unit)
- [x] `coord/Axis.swift` ← `coord/Axis.ts` — the `open class Axis`: `dataToCoord`/`coordToData`
      (`linearMap`), band layout (`getBandWidth`/`makeExtentWithBands`), `getTicksCoords`/
      `getMinorTicksCoords`/`fixOnBandTicksCoords`, `getExtent` copy semantics.
- [x] `coord/AxisBaseModel.swift` ← `coord/AxisBaseModel.ts` — axis-model base (`getCategories`,
      `axis`, scale/extent option surface).
- [x] `coord/axisHelper.swift` ← `coord/axisHelper.ts` — `createScaleByModel`/`niceScaleExtent`/
      `getAxisRawValue`/`makeLabelFormatter`/`getFormattedLabel`.
- [x] `coord/axisNiceTicks.swift` ← `coord/axisNiceTicks.ts` (extracted) — `scaleCalcNice`/
      `scaleCalcNice2`/`calcNiceForIntervalOrLogScale` + `adoptScaleExtentKindMapping`.
- [x] `coord/axisAlignTicks.swift` ← `coord/axisAlignTicks.ts` — multi-axis tick alignment.
- [x] `coord/axisBand.swift` ← axis-band layout helpers.
- [x] `coord/axisTickLabelBuilder.swift` ← `coord/axisTickLabelBuilder.ts` — `createAxisTicks`/
      `createAxisLabels`/`calculateCategoryInterval` (`AxisTicksCreated`/`AxisCategoryTicksCreated`).
- [x] `coord/scaleRawExtentInfo.swift` ← `coord/scaleRawExtentInfo.ts` — **THE REAL ONE** (replaces the
      §22 minimal PORT-TODO stub): `ScaleRawExtentInfo` (min/max/`fixMin`/`fixMax` resolution,
      `calculate`/`freeze`/`ensureScaleRawExtentInfo`, `parseAxisModelMinMax`).
- [x] `coord/axisModelCreator.swift` ← `coord/axisModelCreator.ts` — `axisModelCreator` factory +
      the base `AxisModel` (with `getCategories` override). `axisAction`/`axisBreakHelper` stubbed
      (`getAxisBreakHelper()->null`, PORT-TODO 6b).

### Coord — cartesian (`Sources/EChartsKit/coord/cartesian/`)
- [x] `Cartesian.swift` ← `coord/cartesian/Cartesian.ts` — generic N-axis container (`addAxis`/
      `getAxis`/`getAxes`).
- [x] `Cartesian2D.swift` ← `coord/cartesian/Cartesian2D.ts` — `dataToPoint`/`pointToData`/
      `dataToPoints`/`getOtherAxis`/`getArea`, `toGlobalCoord` wiring.
- [x] `Axis2D.swift` ← `coord/cartesian/Axis2D.ts` — cartesian axis (`getGlobalExtent`/`isHorizontal`/
      `toGlobalCoord`/`toLocalCoord`/`setCategorySortInfo`).
- [x] `AxisModel.swift` ← `coord/cartesian/AxisModel.ts` — `CartesianAxisModel` (now **subclasses
      `AxisBaseModel`** so it satisfies `Axis.model`); `getCoordSysModel` via `SINGLE_REFERRING`.
- [x] `GridModel.swift` ← `coord/cartesian/GridModel.ts` — grid component model + defaultOption.
- [x] `cartesianAxisHelper.swift` ← `coord/cartesian/cartesianAxisHelper.ts` — `layout`/
      `findAxisModels`/`rotateTextRect`.
- [x] `defaultAxisExtentFromData.swift` ← `coord/cartesian/defaultAxisExtentFromData.ts`.
- [~] `Grid.swift` ← `coord/cartesian/Grid.ts` — **PARTIAL**: `create`/`update`/`resize`/`_updateScale`/
      `getCartesian`/`convertToPixel`/`convertFromPixel`/`getTooltipAxes` ported and exercised;
      `createOrUpdateAxesView` is a documented no-op stub (needs `AxisBuilder`, 6b).

### Core — scheduling pipeline + API (`Sources/EChartsKit/core/`)
- [x] `core/task.swift` ← `core/task.ts` — `Task`/`createTask`, `TaskPlanCallback`/reset/progress,
      pipe-chaining.
- [x] `core/Scheduler.swift` ← `core/Scheduler.ts` — the stage graph (`getPipeline`/`updateStreamModes`/
      `performDataProcessorTasks`/`performVisualTasks`/`prepareStageTasks`).
- [x] `core/CoordinateSystemManager.swift` ← `core/CoordinateSystem.ts` — `CoordinateSystemManager`
      (register/get, `create`/`update` ordering, `getCoordinateSystems`).
- [x] `core/ExtensionAPI.swift` ← `core/ExtensionAPI.ts` — the `ExtensionAPI` forwarding surface
      (`getWidth`/`getHeight` faithful-signature PORT-TODO members for the layout-reference path).

### Support ports pulled in on demand (`Sources/EChartsKit/util/`)
- [x] `util/vendor.swift` ← `util/vendor.ts` — `TypedArrayCtor`/`CompatibleTypedArray`/
      `createFloat32Array` (consumed by axis statistics).
- [~] `util/layout.swift` ← `util/layout.ts` — **PARTIAL**: full `getLayoutRect` (2 overloads) +
      `createBoxLayoutReference` (viewport branch); the `boxCoordinateSystem` branch is a 6b PORT-TODO.

### Global instantiation wiring (`Sources/EChartsKit/model/Global.swift`)
- [~] **`GlobalModel` now instantiates REAL component/series models** — the §29 "inert" stub is CLOSED.
      `visitComponent`/component-create iterate the dynamic `[String:Any]` option bag and instantiate via
      the `ComponentModel` registry; `getComponent`/`queryComponents` return real objects. Marked
      **partial** because three downstream stubs (see §33) still block the full data pipeline.

### Phase 6a — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `coord/CoordinateSystem.swift` | `coord/CoordinateSystem.ts` | complete | minor-issues (3) | `isGeoLikeCoordSys` unguarded `dimensions[0]` subscript TRAPS on empty dims (TS short-circuits false); `getViewRect() != nil` tests RETURN not method-EXISTENCE; `GeoLikeCoordSys.getViewRect` mandatoriness not enforced (default supplies it) |
| `coord/Axis.swift` | `coord/Axis.ts` | complete | minor-issues (2) | `splitNumber`/threshold read via `as? Double` drops Int-boxed options → nan/default; `pointToData` base returns `.nan` vs TS `undefined`. Core math (dataToCoord/band margin/fixOnBandTicks) faithful |
| `coord/axisHelper.swift` | `coord/axisHelper.ts` | complete | minor-issues (3) | `util.isFunction`==false ⇒ functional `axisLabel.formatter` DEAD CODE (falls to default label); string-formatter `{value}` replaces ALL not first; `idx ?? 0`/`?? nan` fallback changes callback arg |
| `coord/axisNiceTicks.swift` | `coord/axisNiceTicks.ts` | complete | minor-issues (3) | empty `fixMinMax` OOB-index crash via public `scaleCalcNiceDirectly` (TS tolerant); Int-boxed `interval`/`splitNumber` silently dropped; `model.axis as? Axis` can no-op extent-kind adoption if `axis` isn't a real `Axis` |
| `coord/scaleRawExtentInfo.swift` | `coord/scaleRawExtentInfo.ts` | complete | (real port; foundation) | replaces the §22 stub; `fixMM` always `[false,false]` on the internal path so the axisNiceTicks OOB is external-caller-only |
| `coord/axisTickLabelBuilder.swift` | `coord/axisTickLabelBuilder.ts` | complete | (foundation) | `AxisTicksCreated`/`AxisCategoryTicksCreated` made public |
| `coord/axisAlignTicks.swift`, `axisBand.swift`, `axisModelCommonMixin.swift`, `AxisBaseModel.swift`, `axisDefault.swift`, `axisStatistics.swift`, `axisStatisticsMetricsImpl.swift`, `axisModelCreator.swift` | matching `.ts` | complete | (foundation) | `getCategories` moved to `AxisBaseModel` base (dynamic dispatch); `getFilter?()` optional-closure guard |
| `core/CoordinateSystemManager.swift` | `core/CoordinateSystem.ts` | complete | minor-issues (2) | dropped DEV `assert(!master.update)`; `update()` called unconditionally (safe: no-op default). create/update ordering faithful |
| `coord/cartesian/Cartesian.swift` | `coord/cartesian/Cartesian.ts` | complete | faithful | `getAxis` returns Optional (more honest than TS non-optional); force-unwraps safe under `addAxis` invariant |
| `coord/cartesian/AxisModel.swift` | `coord/cartesian/AxisModel.ts` | complete | minor-issues (2) | `getCoordSysModel().models[0]` unguarded subscript TRAPS when no grid (TS yields `undefined` → descriptive throw); `getCoordSysModel` static-dispatch via extension-default (not protocol requirement) — correct today via concrete types |
| `coord/cartesian/Axis2D.swift` | `coord/cartesian/Axis2D.ts` | complete | minor-issues (3) | `setCategorySortInfo` returns `true` vs TS implicit `undefined`; option write-back guarded (skips if not `[String:Any]`); `?? "value"`/`?? "bottom"` vs `||` on empty string |
| `coord/cartesian/Cartesian2D.swift`, `Axis2D` deps, `GridModel.swift`, `cartesianAxisHelper.swift`, `defaultAxisExtentFromData.swift` | matching `.ts` | complete | (foundation) | `dataToPoint`/`toGlobalCoord` pipeline exercised by the pixel oracle (§32) |
| `coord/cartesian/Grid.swift` | `coord/cartesian/Grid.ts` | **partial** | minor-issues | `createOrUpdateAxesView` no-op stub (AxisBuilder, 6b); `getBoxLayoutParams`/layout feed empty so grid rect fills container (§33) |
| `core/task.swift`, `core/Scheduler.swift`, `core/ExtensionAPI.swift` | matching `.ts` | complete | (foundation) | `ExtensionAPI.getWidth`/`getHeight` real forwarding = 6b PORT-TODO |
| `util/vendor.swift` | `util/vendor.ts` | complete | (support) | NEW |
| `util/layout.swift` | `util/layout.ts` | **partial** | (support) | `getLayoutRect` full; `createBoxLayoutReference` viewport-only, boxCoordinateSystem = 6b |
| `model/Global.swift` | `model/Global.ts` | **partial** | (instantiation wired) | component/series instantiation now live; blocked downstream by §33 stubs |

Roll-up: **coord/core geometry + scale/extent math faithful; the review-flagged issues are (a) a
cluster of Swift-traps-where-TS-tolerates on unguarded array subscripts (`isGeoLikeCoordSys` dims,
`getCoordSysModel().models[0]`), (b) the project-wide `as? Double` Int-boxing drop hitting axis
`splitNumber`/`interval`, and (c) `util.isFunction`==false making functional label-formatters dead
code.** None weaken the ported scale/axis-extent MATH; all are logged below.

---

## 32. Build & test status — Phase 6a (incl. the coord dataToPoint oracle + instantiation test)

- **`swift build`: GREEN.** The coord/cartesian + pipeline + Global instantiation were translated in
  parallel against the OLD §22 PORT-TODO stubs; integration reconciled the collisions with **minimal,
  faithful edits (no scale/axis-extent math weakened)** — see the integration log below.
- **`swift test`: GREEN — 212 executed / 155 passed / 0 failures / 57 skipped** (whole package; up from
  Phase-5c's 208/55). The new `CartesianCoordTests.swift` adds 4 (2 pass + 2 skip); **no pre-existing
  test regressed.**
- **NEW test file** `Tests/EChartsKitTests/CartesianCoordTests.swift` (4 tests):
  - **`testComponentInstantiationReturnsRealModels` — PASS.** Builds a `GlobalModel` from a minimal
    bar-chart option and asserts `getComponent("grid")` is a real `GridModel`, `getComponent("xAxis"/
    "yAxis")` are real `CartesianAxisModel`, and `eachSeries`/`getSeriesByType("bar")` return a real bar
    `SeriesModel` — **proving the §29 instantiation stub is closed and no longer inert.**
  - **`testDataToPointOracleAndInverse` — PASS.** Runs `Grid.create` with a fixed 400×300 `ExtensionAPI`,
    gets `Cartesian2D` (x0,y0), and asserts `dataToPoint` maps known (categoryIndex, value) → expected
    pixels, cross-checked against an independent `number.linearMap` re-derivation (grid fills the full
    400×300 container; X(rank)=rank/3·400, Y(v)=300−3v; ordinal N=4 onBand=false, value scale [0,100]),
    plus bounds checks and `pointToData` inverting `dataToPoint`.
  - `test_api_converter_cartesian`, `test_api_containPixel_cartesian` (ported upstream specs) — **SKIP**
    (need `createChart`/orchestrator + ChartView map + Scheduler = Phase 6b; the underlying
    `Grid.convertToPixel`/`convertFromPixel` + `Cartesian2D.dataToPoint` ARE ported and exercised by the
    oracle).
- **INTEGRATION LOG — minimal faithful edits to make the parallel work build (no math weakened):**
  removed obsolete §22 placeholder `Axis`/`AxisModelForAxisStat` protocols in `axisStatistics.swift`
  (source of the "`Axis` is ambiguous" clash) and rewired to the real `Axis`; NEW `util/vendor.swift` +
  `util/layout.swift`; `getFilter?()` optional-closure guard; reconciled `Axis.getTicksCoords` to the real
  `axisTickLabelBuilder` API; made `AxisTicksCreated`/`AxisCategoryTicksCreated` public; moved the base
  `getCategories` onto `AxisBaseModel` (dynamic dispatch); `CartesianAxisModel` now subclasses
  `AxisBaseModel`; `scaleCalcNice2` axis param `Any?`→`Axis?`; `Grid.createOrUpdateAxesView` `kind` param
  → `Double`; various `.model` → `.model!` IUO-bind fixups.
- **The oracle/data pipeline is reachable only through THREE documented TEST-SIDE workarounds**, each
  mapping to a real §33 Sources bug (NOT papered over, confined to private test doubles): (B1) probe series
  feeds an empty DataStore to dodge the `isFunction` assert; (B2) probe axis models override
  `getCoordSysModel` to resolve the grid via `ecModel.getComponent` (bypass the `queryReferringComponents`
  crash); (B3) ordinal scale extent set by hand to stand in for the blocked data-collection stage.

---

## 33. Phase 6a — new open issues & PORT-TODO backlog (deduped, blockers first)

### CRITICAL — real bugs the test doubles work around (fix FIRST in Phase 6b pre-work)
1. **`queryReferringComponents` still stubbed to always return `models: []`** (`util/modelUtil.swift:
   1256-1298`, both branches). Its PORT-TODO reason (GlobalModel has no `getComponent`/`queryComponents`)
   is now STALE — both exist (`Global.swift:665`/`:686`). Consequence: `CartesianAxisModel.getCoordSysModel()`
   (`AxisModel.swift:93`) does `.models[0]` → **index-out-of-range CRASH**, which crashes the entire
   `Grid.create`/cartesian pipeline via `isAxisUsedInTheGrid` (`Grid.swift:719`). **Primary blocker**; the
   test must override `getCoordSysModel` (workaround B2). **Fix:** implement `queryReferringComponents` over
   the now-real `getComponent`/`queryComponents`; also change `.models[0]` → `.models.first` (mirror TS
   `undefined` → the ported descriptive throw at `Grid.swift:679-684`).
2. **`util.isFunction` still hardcoded `false`** (ZRenderKit `Core/util.swift:304`, stub). Because
   `__DEV__` is hardcoded `true` (`util/log.swift:33`), `DataStore.initData` (`data/DataStore.swift:
   227-231`) asserts `isFunction(provider.getItem) && isFunction(provider.count)` and **ALWAYS
   fatalErrors "Invalid data provider."** ⇒ a `DefaultDataProvider` can never init a `DataStore` in a
   `__DEV__`/test build, making the whole `getInitialData`→`Source`→`DataStore` series-data pipeline
   unreachable (workaround B1). Also breaks the `axisHelper` functional-formatter branch (§31 verdict).
   **Fix:** port a real `isFunction` (`typeof x === 'function'` → Swift closure/`is` check).
3. **`OrdinalMeta.createByAxisModel` ignores its `axisModel` argument** (`data/OrdinalMeta.swift:90`,
   `_ = axisModel; let option: [String:Any] = [:]`). Its PORT-TODO reason (Model has no `.option`) is
   STALE. Consequence: a category axis NEVER collects categories from `xAxis.data`; `categories` stays
   nil, `needCollect` always true, `OrdinalScale.count()` is wrong ⇒ category `dataToPoint` is NaN out of
   the box (workaround B3). **Fix:** read `axisModel.get("data")`/`.option`.
4. **`ComponentModel.getBoxLayoutParams` returns an empty `BoxLayoutOptionMixin()`**
   (`model/Component.swift:349`). Its PORT-TODO reason (util/layout not ported) is STALE — `util/layout.
   swift` now exists and Grid consumes it. Consequence: `grid.left/right/top/bottom/width/height` are never
   read into layout, so `getLayoutRect` sees an empty position bag and the **grid rect ALWAYS fills the
   whole container** regardless of the option (and the `GridModel.defaultOption` left-15% etc. is never
   applied). **Fix:** read the box-layout keys off the model option.

### Correctness / fidelity — review-flagged, fix opportunistically (see §31 verdict table for the full set)
5. **Swift-traps-where-TS-tolerates on unguarded array subscripts:** `isGeoLikeCoordSys`
   `dimensions[0]` (`CoordinateSystem.swift:386`) on empty dims (parallel-style dimensionless coord
   systems are a documented reachable case); `getCoordSysModel().models[0]` (dup of #1). Bounds-guard
   both to mirror JS `undefined`.
6. **Project-wide `as? Double` drops Int-boxed options.** Axis `splitNumber`/`interval`/`minInterval`/
   `maxInterval` (`axisNiceTicks.swift:309-312`, `Axis.swift:280`) read via `model.get(...) as? Double`;
   an Int literal in the `[String:Any]` bag yields nil ⇒ user override silently ignored / default used.
   Only bites if option ingestion does not normalize numerics to Double — flag for the ingestion path.
7. **`util.isFunction`==false makes functional `axisLabel.formatter` dead code** (dup of #2 downstream)
   and the string-formatter `{value}` replaces ALL occurrences not just the first (`axisHelper.swift:241`).
8. **`isGeoLikeCoordSys` `getViewRect() != nil` tests RETURN value, not method existence** (TS `!!coordSys.
   getViewRect`) — a geo coord system with a transiently-nil view rect is misclassified. Documented PORT-TODO.
9. **`Axis2D.setCategorySortInfo` returns `true`** where TS implicitly returns `undefined` (falsy); only
   caller discards it. **`Axis2D` constructor defaulting** `?? "value"`/`?? "bottom"` diverges from TS `||`
   on empty string (unrealistic input).

### Deferred → Phase 6b (faithful-signature PORT-TODO stubs; none exercised by the 212 tests)
- **`core/echarts.ts` orchestrator** — the full ~125KB `ECharts`/`init`/`setOption`/`_update` driver; a
  SLIM driver comes in 6b (§34).
- **Rendering views** — `chart/*` (BarView etc.), `component/grid` `GridView`, `component/axis`
  `CartesianAxisView` + `AxisBuilder`/`AxisBuilderSharedContext`. `Grid`/`Axis2D`/`cartesianAxisHelper`
  reference `AxisBuilder` as PORT-TODO stubs; `Grid.createOrUpdateAxesView` is a documented no-op.
- **`component/axis/axisAction.ts` + `axisBreakHelper.ts`** — referenced by `axisModelCreator`; stubbed
  (`getAxisBreakHelper()->null`).
- **`util/layout` `createBoxLayoutReference` boxCoordinateSystem branch; `ExtensionAPI.getWidth/getHeight`
  real forwarding.**
- **`core/lifecycle.ts`, `core/locale.ts`, `core/impl.ts`, `core/ExtendedElement.ts`** — 6b orchestration.
- **Other coordinate systems:** polar, geo, single, radar, calendar, parallel, matrix, `coord/View.ts`;
  and `coord/cartesian/legacyContainLabel.ts` + `prepareCustom.ts` (out of scope); dataZoom/axisPointer/brush.

### Does `GlobalModel` now instantiate real component/series models?
**YES — the §29 stub is CLOSED (proven by `testComponentInstantiationReturnsRealModels`, §32).** From a
minimal bar-chart option, `GlobalModel` builds real `GridModel`, `CartesianAxisModel` (x/y), and a bar
`SeriesModel`; `getComponent`/`queryComponents`/`eachSeries`/`getSeriesByType` all operate on real
objects. **Caveat:** the pipeline BEYOND instantiation (grid resolution + series-data build) is blocked by
the four §33 CRITICAL stubs (`queryReferringComponents`, `isFunction`, `OrdinalMeta.createByAxisModel`,
`getBoxLayoutParams`) — the test uses private doubles to reach `dataToPoint`; closing those four is the
pre-work for Phase 6b.

---

## 34. Coord + pipeline are in place — Phase 6b plan (the rendering vertical: a REAL bar chart on screen)

**Goal:** finish the §30 vertical — after the §33 CRITICAL pre-work, a hand-built `option`
(`{xAxis, yAxis, series:[{type:'bar', data}]}`) flows through `GlobalModel` → coord/cartesian →
`Scheduler` → `visual`/`layout` → `BarView` and renders a REAL bar chart through the complete
`ZRenderKit` (`Group`/`Rect`/`Text` + animation + interaction) on the iOS/macOS simulator via
`NativePainter`. This turns the §28/§32 `createChart`-driven skips green.

### Pre-6b (do FIRST): close the four §33 CRITICAL stubs
`queryReferringComponents` (real impl over `getComponent`/`queryComponents` + `.models.first`),
`util.isFunction` (real closure check), `OrdinalMeta.createByAxisModel` (read `axisModel` data), and
`ComponentModel.getBoxLayoutParams` (read box-layout keys). Each removes a private test double and a real
divergence. Carry the §30 majors/hardening only if still open.

### 34a. Slim `ECharts` orchestrator (`echarts/src/core/echarts.ts` — documented subset)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `core/echarts.ts` (the `init`/`setOption`/`update` cycle — a SLIM hand-driven slice, not the full ~125KB driver; each ported/omitted method flagged) | `core/echarts.swift` | `GlobalModel`+`OptionManager` (5c), `Scheduler`+`CoordinateSystemManager` (6a), `ExtensionAPI` (6a), `ZRender` host (Phase 4) |

### 34b. `visual/` (style/color) + `layout/barGrid`
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `visual/style.ts`, `visual/seriesColor.ts`, `visual/VisualMapping.ts` | `visual/*.swift` | `model/mixin/palette` (5c), `data/SeriesData` (5b) |
| `layout/barGrid.ts` | `layout/barGrid.swift` | `coord/cartesian/Grid` (6a), `data/SeriesData`, `data/helper/dataStackHelper` (5b) |

### 34c. FIRST `ChartView` = `BarSeries` + `BarView` + `component/grid`(GridView) + `component/axis`(CartesianAxisView)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `chart/bar/BarSeries.ts` (concrete `getInitialData` → real column build) | `chart/bar/BarSeries.swift` | `SeriesModel` (5c), `data/{SeriesData,helper/createDimensions}` (5b), `Source` |
| `chart/bar/BarView.ts` (`ChartView` → `Group{Rect}` per datum, enter/update/exit + animation) | `chart/bar/BarView.swift` | `ZRenderKit` `Group`/`Rect`/`Path` + animation (Phase 1–3), `DataDiffer` (5b) |
| `view/Chart.ts` (`ChartView` base), `view/Component.ts` | `view/*.swift` | `ZRenderKit` `Group`, `GlobalModel` |
| `component/grid/GridView.ts` | `component/grid/*.swift` | `coord/cartesian/Grid` (6a), `Group`/`Rect` |
| `component/axis/{AxisBuilder,CartesianAxisView}.ts` (unstub the 6a `createOrUpdateAxesView` / `AxisBuilder` seams) | `component/axis/*.swift` | `coord/Axis`/`Axis2D` (6a), `Group`/`Line`/`Text` (Phase 1–2) |

**Sequencing:** §33 CRITICAL pre-work → slim `echarts.ts` driver → `visual/`+`layout/barGrid` →
`BarSeries`+`BarView`+`GridView`+`CartesianAxisView` (unstubbing the 6a `AxisBuilder` seams). Each stage
keeps the §12 upstream-sync rule and ports its matching upstream spec as the behavioral oracle (turning
the `createChart`-driven skips green as `createChart`/`init`/`getData` become real).

---

## 35. What landed in Phase 6b — the rendering vertical (a REAL bar chart end-to-end): COMPLETE

**Phase 6b (the §34 plan): COMPLETE — `swift build` GREEN (0 warnings, clean `rm -rf .build`),
`swift test` 215 executed / 0 failures / 58 skipped (was 212; +3 real 6b tests, no regression).**
An `option` `{grid, xAxis:category, yAxis:value, series:[{type:'bar', data}]}` now flows
`GlobalModel` → coord/cartesian → visual → layout → `BarView` and emits four bar `Rect`s in the
`ZRenderKit` scene graph, within the grid rect, heights monotonic with the data, palette fills —
asserted by `Tests/EChartsKitTests/BarChartRenderTests.testBarChartRendersFourBars` (which also
exercises `NativePainter.renderToImage`).

### 35a. New files
- **`core/EChartsSlim.swift`** — DELIBERATELY MINIMAL subset of `core/echarts.ts` (NOT the ~3400-line
  driver). Owns a `Storage` + root `Group`; `setOption` builds `GlobalModel` via `OptionManager`, then
  `update()` runs the faithful stage ORDER of `updateMethods.update` with minimal bodies (restoreData →
  performSeriesTasks(dataTaskReset) → coordSysMgr.create → axis-statistics processor → coordSysMgr.update
  → visual → layout → render). The `Scheduler` task graph, media/actions/lifecycle/states are documented
  PORT-TODO skips. Registration is explicit (`installOnce`) with `SlimXAxisModel`/`SlimYAxisModel`
  stand-ins for the runtime-generated `axisModelCreator` classes, and `()->View` factories (Swift can't
  `new` a bare metatype).
- **View bases:** `view/Chart.swift` (`ChartView`), `view/ComponentView.swift` (`ComponentView`),
  `chart/helper/createRenderPlanner.swift` (the incremental/large render planner).
- **Visual:** `visual/style.swift` (`seriesStyleTask` + `dataColorPaletteTask`: palette + series/data style).
- **Layout:** `layout/barGrid.swift` (cross-series `calcBarWidthAndOffset` + progressive layout),
  `layout/barCommon.swift` (per-item bar layout math).
- **Bar series + view:** `chart/bar/{BaseBarSeries,BarSeries}.swift`, `chart/bar/BarView.swift`
  (`ChartView` → `Group{Rect}` per datum, `data.diff` enter/update/leave + animation), helpers
  `chart/helper/{createSeriesData,createClipPathFromCoordSys}.swift`.
- **Axis + grid views:** `component/axis/{AxisView,CartesianAxisView}.swift` +
  `component/axis/AxisBuilder.swift` (axis line/tick/label/name builder — **partial**),
  `component/grid/installSimple.swift` (grid + axis registration; unstubs the 6a
  `createOrUpdateAxesView`/`AxisBuilder` seams).

### Per-file status & review verdict (Phase 6b)
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `core/EChartsSlim.swift` | `core/echarts.ts` (subset) | **partial** | (slim driver by design) | faithful stage ORDER; Scheduler/media/actions/lifecycle/states are documented skips |
| `view/Chart.swift` | `view/Chart.ts` | complete | minor-issues (2) | `eachRendered` uses `Group.traverse` (children only) — upstream `traverseElements` also visits the root group; `context.payload!`/`ecModel!`/`api!` force-unwraps in render tasks trap on a nil payload (TS tolerates undefined) |
| `view/ComponentView.swift` | `view/Component.ts` | complete | faithful | base only |
| `chart/helper/createRenderPlanner.swift` | `chart/helper/createRenderPlanner.ts` | complete | faithful | |
| `visual/style.swift` | `visual/style.ts` | complete | minor-issues (3) | palette-rotation skips filtered points (no global `colorFromPalette` fallback) so `colorBy:'data'` would shift after filtering; `== nil` vs JS-falsy on empty-string/0 color; optional key removed vs `undefined`. All out of bar-only scope (bars are `isColorBySeries()`) |
| `layout/barCommon.swift` | `layout/barGrid.ts` (item half) | complete | faithful | |
| `layout/barGrid.swift` | `layout/barGrid.ts` | complete | major → **FIXED** | the NaN-vs-JS-truthiness bar-width poisoning (`barWidth`/`barMaxWidth`/`barMinWidth`) is fixed via `barGridTruthy` (0/NaN → false); default no-`barWidth` chart now yields finite widths |
| `chart/helper/createSeriesData.swift` | `chart/helper/createSeriesData.ts` | complete | faithful | |
| `chart/helper/createClipPathFromCoordSys.swift` | `chart/helper/createClipPathFromCoordSys.ts` | complete | faithful | cartesian branch; polar `createPolarClipPath` deferred |
| `chart/bar/BaseBarSeries.swift` | `chart/bar/BaseBarSeries.ts` | complete | faithful | `getInitialData`/`defaultOption`/`getMarkerPosition` match upstream incl. JS-truthiness quirks |
| `chart/bar/BarSeries.swift` | `chart/bar/BarSeries.ts` | complete | faithful | |
| `chart/bar/BarView.swift` | `chart/bar/BarView.ts` | complete | major (1 OPEN) | **update-diff branch does NOT clip `layout` in place** — it clips a throwaway `clipLayout` then feeds the UNCLIPPED `layout` to `updateStyle`/`setShape`/`updateProps`, so a partially-overflowing bar renders unclamped on any steady-state (oldData) render. The add branch is correct; only fully-clipped bars are still handled. The render test exercises only the add path, so first-render bars are correct (§35c) |
| `component/axis/AxisView.swift` | `component/axis/AxisView.ts` | complete | faithful | base |
| `component/axis/AxisBuilder.swift` | `component/axis/AxisBuilder.ts` | **partial** | major (OPEN) | `axisTick`/`minorTick` `length` and `nameGap` read via `... as? Double` but their defaults are **Int** literals → cast fails → ticks collapse to zero length (invisible) and axis name gets 0 gap. Same Int-boxing class as §33 #6. Not caught by the render test (asserts bars only). Label/name overlap-nudge is a no-op stub |
| `component/axis/CartesianAxisView.swift` | `component/axis/CartesianAxisView.ts` | complete | faithful | drives `AxisBuilder`; splitLine/splitArea deferred |
| `component/grid/installSimple.swift` | `component/grid/install.ts` (subset) | complete | faithful | grid + axis registration |

Roll-up: **13 complete, 3 partial; 2 major FIXED-or-OPEN (barGrid width FIXED; BarView update-path clip
OPEN), 1 major OPEN in AxisBuilder (Int-boxed tick/name lengths); the rest faithful/minor.**

### 35b. Key bug found & fixed during closeout — `SeriesModel.getBaseAxis()` `Any?` conversion
The workflow was killed (session abort) before its Verify/Synthesize stages, leaving one real defect the
end-to-end test caught: **bars had `x`/`width` = NaN** (y/height were correct). Root cause chain:
`layout/barGrid` reads `data.getLayout("size"/"offset")` (→ NaN default) which the **cross-series bar
layout** (`createCrossSeriesLayoutHandler`) only writes for axes collected under the bar `AxisStatKey`.
Collection happens in `associateSeriesWithAxis` (`axisStatistics.swift`), gated by
`isBaseAxis = seriesModel.getBaseAxis() === axis`. **`SeriesModel.getBaseAxis()` (returns `Any?`) returned
`nil`**: `Cartesian2D` has a concrete `getBaseAxis(): Axis2D`, but its superprotocol `CoordinateSystem`
declares `getBaseAxis(): Axis?` WITH a nil-returning default (`CoordinateSystem.swift:316`). In an untyped
`Any?`-return position, Swift overload resolution prefers the protocol's `-> Axis?` member (its optional
result matches the `Any?` context) over the concrete `-> Axis2D`, so a direct `return coordSys.getBaseAxis()`
bound the DEFAULT → nil. **Fix** (`model/Series.swift:490+`): narrow to concrete `Cartesian2D`, then bind
the result to an explicit `let baseAxis: Axis2D` local (pins resolution to the concrete method) before
returning. With that, `isBaseAxis` is true for the category axis → statistics collect the series →
`size`/`offset` are set → bar geometry is finite. (NOT a compiler miscompile — an overload-resolution trap;
empirically confirmed by clean-build A/B on the direct vs. typed-local return.)

**Process note:** this bug was obscured for most of the investigation by STALE build artifacts — leftover
`PORTDIAG_*` diagnostic globals (added mid-debug, then removed from the source) left probe test files that
failed to compile, so `swift test` silently ran cached binaries. A `rm -rf .build` + removing the probe
tests was required to see the true (passing) state. Lesson for future closeouts: on contradictory probe
output, clean-build before trusting anything.

### 35c. Build + test status — DOES A BAR CHART RENDER?
- **`swift build`: GREEN** (clean `rm -rf .build`, 0 warnings, all targets).
- **`swift test`: 215 executed / 157 passed / 0 failures / 58 skipped** (was 212 in 6a; +3 new 6b tests, no
  regression). The 58 skips are the 57 pre-existing intentional gaps + 1 new `getVisual` skip.
- **End-to-end render test — `Tests/EChartsKitTests/BarChartRenderTests.testBarChartRendersFourBars`: PASS**
  (re-run and confirmed green this closeout, 0.003 s). **YES — a real ECharts bar `option` renders 4 bars
  through `ZRenderKit.`** Its 6 assertions all hold: (1) exactly 4 bar `Rect` elements (name `item`) in the
  root `Group`; (2) every bar rect lies within the injected `Cartesian2D.getArea()` (`{50,20,300,200}`);
  (3) bar x increases left→right (61.6/136.6/211.6/286.6); (4) `|height|` monotonic with data
  (50/100/150/200); (5) fills are REAL palette colors (`#5070dd`, not the `#000` default); (6)
  `CALayerPainter.renderToImage` returns a non-nil 400×300 `CGImage`. Plus 1 `XCTSkip`
  (`test_api_getVisual_barColorFromPalette`, needs `createChart`) and `EChartsSlimSmokeTests` (drives the
  slim update cycle; prints rects=0 because it uses an empty-DataStore double).
- **Real bugs found & fixed to get here (in Sources, not papered over in the test):** the `layout/barGrid`
  **NaN-vs-JS-truthiness** bar-width poisoning (`barGridTruthy`, §35a table) and the
  **`SeriesModel.getBaseAxis()` `Any?` overload-resolution trap** (§35b) — the latter is why x/width were
  NaN before this closeout.
- **Data source caveat (NOT a bug):** the real `BarSeriesModel.getInitialData → SourceManager.getSource()`
  is still a `fatalError` stub (`data/helper/sourceManager.ts` not ported), so all three render/coord tests
  supply data via a populated `DataStore` double — a documented substitute for a known-unported layer.

### 35d. New open issues & PORT-TODOs (deduped, severity-first)
**OPEN correctness bugs (carry into 6c pre-work):**
1. **`BarView` update-diff branch clips a throwaway copy, not the real `layout`** (see §35a table). Fix: make
   `layout` a `var` in the `.update` closure and `clipCartesian2D(coordSysClipArea, &layout)` in place, as the
   `.add` closure does. Latent today (render test hits only the add path); bites on the first re-render.
2. **`AxisBuilder` Int-boxed `axisTick.length`/`minorTick.length`/`nameGap` read via `... as? Double` → 0**
   → invisible ticks + zero name gap. Same `as? Double` Int-boxing class as §33 #6 (project-wide). Fix at
   ingestion (normalize option numerics to Double) or read with an Int-tolerant coercion helper.
3. **`Chart.eachRendered` visits children only** (`Group.traverse`), where upstream `traverseElements` first
   visits the root group; and `context.payload!`/`ecModel!`/`api!` force-unwraps in the render tasks trap on
   a nil payload the `Scheduler` may set (TS tolerates undefined). Both `view/Chart.swift`.
4. **`visual/style` palette rotation** skips filtered points (no global `colorFromPalette` fallback) so
   `colorBy:'data'` would shift after legend/dataZoom filtering. Out of bar-only scope (bars are
   `isColorBySeries()`), but mark before line/scatter land.

**Deferred features (faithful-signature PORT-TODO stubs; none block the bar vertical):**
- **Prereq util still unported** (blocks fuller BarView/AxisBuilder fidelity): `util/graphic`
  (`updateProps`/`initProps`/`subPixelOptimizeLine`/`removeElementWithFadeOut` — currently local shims),
  `util/states` (`toggleHoverEmphasis`/`setStatesStylesFromModel`), `label/labelStyle`
  (`createTextStyle`/`setLabelStyle`) — **the emphasis/states and label blocks in `BarView.updateStyle` are
  documented PORT-TODO no-ops.**
- **Label collision / layout:** `labelLayoutHelper` hideOverlap/OBB, `LabelManager`, axis-name move-overlap
  resolution, `sectorLabel` — all deferred.
- **BarView non-core paths:** large/progressive (`LargePath`, `throttle`), `realtimeSort`/`changeAxisOrder`,
  `showBackground`, polar `Sector`/`Sausage` branch, `pictorialBar`.
- **Axis extras:** `splitLine`/`splitArea` (`axisSplitHelper`), functional `axisLabel.formatter`
  (`AxisBuilder` `rawLabel` read-back), axis-break rendering; other axis views (Angle/Radius/Single/Parallel).
- **Slim driver skips:** the `Scheduler` task graph proper, media/actions/lifecycle/states, and the full
  `core/echarts.ts` orchestrator (`init`/`setOption`/`_update`).
- **Other chart types + components:** line/scatter/pie/etc.; tooltip/legend/dataZoom/brush/markLine/axisPointer;
  decal/aria; other coordinate systems (polar/geo/single/radar/calendar/parallel/matrix).

### 35e. The SIMULATOR DEMO is now updatable to a REAL echarts-option-driven bar chart
The hand-built-shapes demo can now be replaced by a chart driven end-to-end from an ECharts `option`. Exact
entry point (all public, exercised by `BarChartRenderTests`):
1. **Driver:** `EChartsSlim(width:height:)` → `.setOption(_ option: [String: Any])`
   (`Sources/EChartsKit/core/EChartsSlim.swift`).
2. **Scene-graph accessor:** `EChartsSlim.getRoot() -> ZRenderKit.Group` (the rendered display tree; also
   `.getStorage() -> Storage`, `.getModel() -> GlobalModel?`).
3. **Paint:** `NativePainter.renderToImage(group:size:dpr:backgroundColor:) -> CGImage?`
   (`Sources/NativePainter/CALayerPainter.swift:654`) for a still image; or attach `getRoot()` to the live
   host `ZRenderView` (`Sources/NativePainter/ZRenderView.swift`) for an on-screen/animated view.

So `Sources/DemoGallery` can add a demo that builds `{grid, xAxis, yAxis, series:[{type:'bar', data}]}`,
feeds it to `EChartsSlim.setOption`, and renders `getRoot()` — the first time the full ECharts→ZRenderKit
vertical (data → scale → coord → layout → `Rect`s) is on screen, not hand-built `Group` trees. (Until
`SourceManager.getSource` lands, a demo must supply data via a `DataStore` double, as the tests do.)

### 35f. Roadmap beyond Phase 6b
1. **6c pre-work:** fix the §35d OPEN bugs (BarView clip-in-place, AxisBuilder Int-boxed lengths) and port
   `SourceManager.getSource` so `BarSeriesModel.getInitialData` is real (removes the `DataStore` double).
2. **Emphasis/states + labels:** port `util/graphic`, `util/states`, `label/labelStyle` → real hover/select
   + bar value labels.
3. **More chart types:** line + scatter `ChartView`s (reuse the coord/visual/layout pipeline).
4. **More components:** tooltip, legend, dataZoom, axisPointer, splitLine/splitArea.
5. **More coordinate systems:** polar, then geo/single/radar as demand dictates.

---

## 36. Phase 6c — real data source pipeline (SourceManager)

**Goal (met):** replace the Series-local stub `SourceManager` with a faithful port of
`echarts/src/data/helper/sourceManager.ts`, making `BarSeriesModel.getInitialData`'s source/data-store
provisioning real (the §35d "6c pre-work" item: port `SourceManager.getSource` so the `DataStore`
double is removed). **`swift build` GREEN (0 warnings), `swift test` 216 executed / 0 failures /
58 skipped — no regression vs §35 (was 216/0/58).**

### What landed
- [x] `Sources/EChartsKit/data/helper/sourceManager.swift` ← `echarts/src/data/helper/sourceManager.ts` —
      all methods preserved in upstream name / order / control-flow: `dirty`, `_setLocalSource`,
      `_getVersionSign`, `prepareSource`, `_createSource`, `_applyTransform`, `_isDirty`, `getSource`,
      `getSharedDataStore`, `_innerGetDataStore`, `_getUpstreamSourceManagers`, `_getSourceMetaRawOption`,
      plus free funcs `isSeries` / `doThrow` / `disableTransformOptionMerge`. Reuses the already-ported
      `createSource` / `Source` / `DataStore` / `DefaultDataProvider` / `SeriesDataSchema` / `query*` —
      nothing re-ported.

### The faithful no-dataset path (series inline data → createSource) — fully live & verified
For a cartesian series with inline `data:` and no dataset, the reachable path is exercised end-to-end:
`_getUpstreamSourceManagers() == []` → `hasUpstream = false` → the `isSeries` else-branch →
`data = seriesModel.get("data", true)`, `sourceFormat = SOURCE_FORMAT_ORIGINAL`,
`needsCreateSource = true` → `createSource(...)`. `_innerGetDataStore` then builds a `DataStore` via
`DefaultDataProvider`, and `getSharedDataStore` now ships on the real class (the createSeriesData stub
extension was removed at integrate).

### Design choices
- **Host typing:** added `public protocol SourceManagerHost: AnyObject { var uid }` (mirrors upstream's
  `DatasetModel | SeriesModel` union) with `extension SeriesModel: SourceManagerHost {}` declared *in the
  sourceManager file* — no `Series.swift` edit needed. INTEGRATION NOTE: do **not** also add
  `: SourceManagerHost` to the `SeriesModel` class decl (that would duplicate-conform). `DatasetModel`
  conformance is deferred (dataset host unreachable this phase).
- **`isSeries` uses `host is SeriesModel`** — equivalent to upstream `mainType === 'series'` for the two
  host kinds, and robust against mainType-timing (avoids the `Global.swift` mainType-vs-lifecycle-init
  ordering fragility).
- **`DataStoreMap`:** added `public typealias DataStoreMap = [String: DataStore]`; `_storeList` uses
  auto-vivify + value-type write-back for the cache mutation (CONVENTIONS).
- **`getSource()` returns `Source?`** (upstream can return `undefined`) — an intended public-surface change
  vs the stub. On the reachable inline-data path a source is always created, so callers force-unwrap.

### Source.swift friction resolved (kept, +14/-5)
- `SourceMetaRawOption.seriesLayoutBy` made Optional (`SeriesLayoutBy?`) so the `retrieve2(...) || null`
  value is carried faithfully; ripple: `determineSourceDimensions` / `arrayRowsTravelFirst`
  `seriesLayoutBy` params → Optional (compared only vs `SERIES_LAYOUT_BY_ROW`), and `createSource`
  `sourceData` widened to Optional (upstream data may be `undefined`; no other callers).
- `needsCreateSource` reproduces the JS null-vs-undefined distinction: `upMetaRawOption` modeled as
  `SourceMetaRawOption?` (`nil` ≡ JS empty `{}`), so with no upstream a source IS created for inline data.
  A residual null/undefined subtlety in the (unreachable) upstream-present case is flagged
  `// PORT-TODO(ts:240)`.

### Dataset / transform PORT-TODO deferrals (unreachable this phase; exact upstream refs in-file)
- `_createSource` dataset-host branch (ts:249-268) — `fatalError`.
- `_applyTransform` whole body (ts:277-330) — needs `applyDataTransform` + `DatasetModel.get`.
- `_getUpstreamSourceManagers` dataset arm + series `getSourceManager()` call (ts:437, 439-444).
- `_getSourceMetaRawOption` dataset arm (ts:458-463).
- `disableTransformOptionMerge` (ts:471-474) — needs `setAsPrimitive`.

### Integration (stub → real)
- `Sources/EChartsKit/model/Series.swift`: removed the local stub `public final class SourceManager`
  (weak `_sourceHost`, no-op `prepareSource`/`dirty`, `fatalError` `getSource`), replaced with a comment
  pointing at the real `data/helper/sourceManager.swift`. `getSourceManager()` / init / `mergeOption`
  wiring unchanged. `getSource()` now force-unwraps the real `SourceManager.getSource()` (`Source?` →
  `Source`) with a comment noting upstream returns non-optional and a source is always created on the
  reachable inline-data path.
- `Sources/EChartsKit/chart/helper/createSeriesData.swift`: removed the private
  `extension SourceManager { getSharedDataStore }` PORT-TODO stub; line 184
  `source = sourceManager.getSource()` force-unwrapped to `getSource()!` (extra integration point found
  beyond the scout list, alongside the `Series.swift` `getSource()` force-unwrap).

### Build / test status
- **`swift build`: GREEN, 0 warnings.** **`swift test`: 216 executed / 0 failures / 58 skipped** — no
  regression vs §35. The stub-vs-real duplicate-`SourceManager` state that briefly made the tree red
  during pre-integration verification is resolved by the integrate step.

### Review findings & disposition
- **Faithfulness review: `faithful`, 0 findings.** No open bugs from this phase. The dataset/transform
  arms remain the only deferrals (all `// PORT-TODO`-marked with exact upstream line refs, above).

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
