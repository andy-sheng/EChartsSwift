# B1 — Transition Animation Infrastructure — Design

Date: 2026-07-07
Status: Approved (design)
Parent: sub-project B of the full echarts.ts port (see docs/superpowers/specs/2026-07-07-live-animation-host-design.md and memory full-echarts-port-decomposition).

## Goal

Port the shared `animation/basicTransition` helpers (real animation, not the current no-op shims) and wire the two views that already have the enter/update/leave diff structure (Bar, Candlestick), so entrance/update/leave transitions actually animate. Add a gallery toggle so the (HTML-invisible, because the HTML pane is `animation:false`) transitions are visually verifiable on demand.

## Context found (code review)

- `SeriesData.diff`/`DataDiffer` are ported. `BarView.render` and `CandlestickView.render` already call `data.diff(oldData)` with add/update/remove callbacks that call `initProps`/`updateProps`/`removeElementWithFadeOut`/`saveOldStyle`.
- Those helpers are **per-view local NO-OP shims** (BarView.swift:613-660, CandlestickView.swift:531-545): they set the final shape instantly, fire `during(1)`/`cb()`, and remove immediately. Zero animation.
- There is **no shared `animation/basicTransition`** (`util/graphic.swift` is 79 lines of PORT-TODO).
- Plumbing exists: `SeriesModel.isAnimationEnabled()` (Series.swift:605, reads `animation`/`animationThreshold`), `Model.getShallow` (for `animationDuration`/`Easing`/`Delay` + `…Update`), `globalDefault` has the defaults, `ElementAnimateConfig{duration,delay,easing,during,done,aborted}`, `el.animateTo(props,cfg)`/`animateFrom`/`stopAnimation(scope)`/`attr(props)`. `el.animateTo` accepts a `[String:Any]` props dict and drives shape/style sub-bags (proven by ShapeAnimationWiringTests).

## Design

### 1. New shared module `Sources/EChartsKit/animation/basicTransition.swift`

Faithful port of `upstream/echarts/src/animation/basicTransition.ts`:

- `getAnimationConfig(_ type: AnimationType, _ model: Model?, _ dataIndex: Int, _ extraOpts: (duration:Double?,easing:AnimationEasing?,delay:Double?)?) -> (duration:Double, delay:Double, easing:AnimationEasing?)?`
  - `type` is `enter`/`update`/`leave`. `isUpdate = (type == .update)`.
  - if `model?.isAnimationEnabled() == true`: read `animationDuration(Update)`/`animationEasing(Update)`/`animationDelay(Update)` via `getShallow` (or the `extraOpts` for leave), coerce Int/Double, return config; else return nil. (The `getUpdatePayload` dataZoom/resize override and function-valued duration/delay are documented PORT-TODO for B1 — no demo needs them.)
- `animateOrSetProps(_ type, _ el, _ props: [String:Any], _ model, _ dataIndex, _ isFrom: Bool, _ cb, _ during)`:
  - if not leave: `el.stopAnimation("leave")`.
  - `cfg = getAnimationConfig(...)`; if `cfg.duration > 0`: build `ElementAnimateConfig{duration,delay,easing,during,done:cb}`; `isFrom ? el.animateFrom(props,cfg) : el.animateTo(props,cfg)`.
  - else: `el.stopAnimation(); if !isFrom { el.attr(props) }; during?(1); cb?()` — exactly today's no-op behavior.
- `initProps(el, props, model, dataIndex, cb?, during?)` = `animateOrSetProps(.enter, …, isFrom:false, …)`.
  (Upstream initProps is enter with isFrom=false; the "from" variant is only used via the options object — out of B1 scope.)
- `updateProps(…)` = `animateOrSetProps(.update, …)`.
- `removeElement` / `removeElementWithFadeOut(el, model, dataIndex)` — fade `style.opacity → 0` via `animateOrSetProps(.leave, …)`, then remove from parent in the done callback; group→traverse displayables. `isElementRemoved` guard to avoid double-remove.
- `saveOldStyle`/`getOldStyle` — store/read the element's style for universalTransition. B1 stub (store on a side table or a stored property); real use is a later sub-project.

Deviations to document (ElementAnimateConfig lacks upstream's `force`/`setToFinal`/`scope`): the leave animator can't be tagged `scope:'leave'`, so `isElementRemoved`/`stopAnimation("leave")` fidelity is partial — acceptable for B1 (documented PORT-TODO). `setToFinal` (final-state pre-set for path post-processing) is not modelled; shapes are set to final by the diff layout anyway.

### 2. Wire Bar + Candlestick

Delete the local shims in `BarView.swift` (`initProps`/`updateProps`/`saveOldStyle`/`removeElementWithFadeOut`, lines ~605-660) and `CandlestickView.swift` (lines ~525-545). Route the existing call sites (BarView: 345/375/403/414/444/454/585; Candlestick: 184/222/224) to the shared module functions. The call-site argument order already matches (`el, props, seriesModel, dataIndex[, group]`); adjust `removeElementWithFadeOut`'s signature (shared version takes `(el, model, dataIndex)` and removes via `el.parent`, so the trailing `group` arg is dropped — the element removes itself from its actual parent).

### 3. Gallery native-animation toggle

`Sources/EChartsDemoGallery/Entry.swift` GUI (`GalleryWindowController`): add an `NSSwitch` labelled "Native 动画" near the native caption. State drives `show(demo)`:
- OFF (default): feed the native host `demo.option` with `animation: false` injected → instant final state, matches the static HTML pane.
- ON: feed `demo.option` unmodified (echarts default `animation:true`) → the live host runs entrance/update transitions.
Toggling re-invokes `show(currentDemo)`.

### 4. Static PNG oracle

`renderNativeGroup` injects `animation:false` into the option (parity with the HTML pane's `opt.animation=false`), so `--render`/`--render-all`/`--compare` are deterministic instant-final frames. effectScatter's ripple is unaffected (it is not gated on `isAnimationEnabled`); `advanceAnimationsForStaticFrame` still lands it on a representative frame.

## Testing

- **Unit (headless, EChartsKitTests):** with `animation:true`, an entering bar builds an animator whose clip interpolates the rect `shape.height` from 0→final across synthetic times (ShapeAnimationWiringTests pattern); with `animation:false`, no animator is built and the rect is at final height immediately (the no-op branch). Same for a candlestick shape.
- **`getAnimationConfig`:** returns nil when animation disabled; returns duration 1000/easing cubicOut for enter, 500/cubicInOut for update (from globalDefault) when enabled; Int-literal `animationDuration` is coerced (not dropped).
- **Regression:** full `swift test` stays green; `--render effectscatter-basic` + a bar demo still produce correct final-state PNGs.
- **Manual:** gallery GUI, toggle ON → bars grow / candles draw in; toggle OFF → instant, matches HTML pane.

## Non-goals (later B increments)

- Per-view fan-out to Line/Pie/Scatter/… (they lack the diff/enter seam; add it per view — workflow-parallelizable).
- True view reuse across setOption for update-in-place transitions (the reset-fix currently rebuilds each render → every setOption is an "enter"; fine for demo-switching).
- universalTransition / morph / keyframe / function-valued duration&delay / getUpdatePayload override.

## Risks

- `ElementProps` vs `[String:Any]`: confirm `el.animateTo`/`animateFrom`/`attr` accept the `[String:Any]` props dict the call sites pass (ShapeAnimationWiringTests indicates yes). If `attr(props)` needs `ElementProps`, add the dict bridge in the no-op branch.
- Leave-path fidelity (no `scope:'leave'` tag) — partial; documented.
