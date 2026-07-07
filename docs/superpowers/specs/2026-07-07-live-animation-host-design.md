# Live Animation Host — Design (Sub-project A of the full `echarts.ts` port)

Date: 2026-07-07
Status: Approved (design), pending spec review

## Context

The user is doing a faithful, phased port of `echarts` to Swift (currently Phase 45). The
long-term goal chosen this session is a **full port of `echarts/src/core/echarts.ts`**, replacing
the deliberately render-once `EChartsSlim` driver. That full port decomposes into sub-projects:

- **A — Live animation host** (this spec)
- B — View reuse + data diff → entrance/update transitions
- C — Scheduler task pipeline
- D — `update*` fast-path methods
- E — Full lifecycle / events

Sub-project A is first because it is small, independent, and delivers the capability that
originally surfaced the gap: **`effectscatter-basic` / `effectscatter-grid` have no animation in
native, while the HTML echarts version does.**

## Key finding that scopes A

The native side has **no live/animated host at all**. The gallery's native pane is a static image:
`renderNativeGroup(demo)` → `EChartsSlim` → `Group` → `renderToImage` → `CGImage`. It never uses
`EChartsView` and has no frame loop. Even the macOS GUI comparison window shows a still `NSImage`
on the left against a live echarts `WebView` on the right. So "html animates, native doesn't" is
not effectScatter-specific — native is fundamentally a frozen frame.

Therefore A must **build the missing live host**, not merely toggle a loop. The proven pattern
already exists: `ZRenderView` (NativePainter) drives `AnimationLoop` (CADisplayLink/Timer) →
`Animation.update()` → `stage.update` → `zr._flush` → `CALayerPainter.refresh` → CALayer repaint.
`ZRenderView` hosts a raw `zr`; we need the same wrapper hosting an `EChartsView`.

## Layering constraint (must respect)

`EChartsKit` depends **only on ZRenderKit, not NativePainter** (`AnimationLoop` lives in
NativePainter). So the animation loop cannot live inside `EChartsView`. The host (NativePainter
layer) drives `echartsView.zr.animation`. `EChartsView` already exposes `public let zr: ZRender`,
and `zr.animation` is reachable.

## Design — three parts

### A1 — `EChartsHostView` (new file, `Sources/NativePainter/EChartsHostView.swift`)

An `NSView`/`UIView` mirroring `ZRenderView`, but hosting an `EChartsView`:

- Build a `CALayerPainter` sized to the view.
- Build `EChartsView(width:, height:, painter: caLayerPainter, proxy: nativeProxy)` — the same
  native input proxy `ZRenderView` uses, so hover/click also work live.
- Build `AnimationLoop(animation: echartsView.zr.animation)` and `start()` it (stop on
  removal/dispose, matching `ZRenderView`).
- Per frame the existing chain repaints: `animation.update()` → `stage.update` → `zr._flush` →
  `painter.refresh` → CALayer.
- Forward `setOption(_:)` to `echartsView.setOption`.
- Forward `resize` to the painter + `echartsView` surface.

This reuses `ZRenderView`'s lifecycle exactly (it already owns the `animationLoop` field + start/
stop); `EChartsHostView` is "ZRenderView but its content is an EChartsView instead of a raw zr".

**Gallery GUI swap:** the macOS comparison window's native pane switches from the static
`NSImageView(renderNativeImage(demo))` to a live `EChartsHostView` fed `demo.option`. The left pane
now animates next to the live HTML on the right. The headless `--render` / `--render-all` /
`--compare` PNG paths are unchanged (still `EChartsSlim` → `renderToImage`) — they remain the
static-parity oracle.

### A2 — Ensure element animators register with `zr.animation`

For a tick to have any effect, each element's `.animators` must be registered with `zr.animation`.
Upstream: `el.animate()` creates an `Animator`; when the element is added to a zr (`addSelfToZr`),
its animators are added to `zr.animation`. `_syncRoot()` adds `ec.getRoot()` to `zr` — verify that
path calls `addSelfToZr` and registers existing animators, **and** that animators created *after*
the element is already in the zr (the effectScatter case: rings built during render, then synced)
still reach `zr.animation`. If the sync path doesn't register them, fix it (register on add + on
`el.animate` when `__zr` is already set — the upstream behavior).

### A3 — effectScatter ripple → looping animators

Replace the current static concentric-ring approximation in `EffectScatterView` with real looping
animation, faithful to `chart/helper/EffectSymbol.ts`:

- Per ripple ring `i` in `0..<rippleNumber`:
  - start at `scaleX = scaleY = 0.5`
  - `ring.animate("", loop: true).when(period, { scaleX: rippleScale/2, scaleY: rippleScale/2 }).delay(-i/rippleNumber * period + effectOffset).start()`
  - `ring.animateStyle(loop: true).when(period, { opacity: 0 }).start()` (opacity fades over the period)
- Config (from `itemModel.get(['rippleEffect', …])`), upstream defaults:
  `scale` → `rippleScale` (default 2.5), `period` (default 4, ×1000 = 4000 ms), `number`
  (default 3), `brushType` (default `'fill'`), `color`/`rippleEffectColor`.
- `brushType: 'fill'` fills the ring; `'stroke'` strokes it — matching upstream `symbol.setStyle`.
- Keep the ring below the base symbol (existing `z2` handling).

If the port's `Element` lacks `animateStyle`, use the existing style-animation seam (the `animate`
key that targets `style`, as `ShapeAnimationWiringTests` exercises) — confirm the exact API during
implementation; do not invent one.

## Testing / verification

- **Static PNG gallery cannot validate animation** — stated plainly. `--render-all` staying green
  proves no static regression, nothing about motion.
- **Automated oracle (headless unit test, matches `AnimationSmokeTests`):** build an effectScatter
  option, drive `Animation.update()` for N synthetic frames, assert a ripple element's `scaleX`
  (and style `opacity`) changes monotonically across frames and loops. This is the CI-checkable
  proof that the animators are wired and tick.
- **Manual:** macOS GUI — live `EChartsHostView` (native) beside live HTML echarts; visually
  confirm the ripple matches.
- Standing cadence: build 0 warnings, `swift test` green (310 tests), commit + push.

## Non-goals (explicitly deferred to later sub-projects)

- View reuse / data diff / entrance transitions (B).
- Scheduler task pipeline (C).
- `update*` fast paths (D).
- No change to the headless PNG render path or its parity semantics.

## Risks

- **Animator-after-add registration (A2)** is the likeliest hidden bug: if `_syncRoot` doesn't
  register late-created animators, the ripple builds but never ticks. The unit test in A's
  verification catches this before the GUI.
- `animateStyle` API shape uncertainty — resolve by reading the existing animation tests, not by
  inventing an API.
