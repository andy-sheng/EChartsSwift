# Sub-project C — Scheduler task-pipeline wiring

**Date:** 2026-07-10
**Status:** design approved (user chose C over E / live-multi-layer / stop)

## Goal

Drive `ECharts.update()`'s render path through the already-ported `Scheduler`
task/pipeline graph instead of the current hand-called, source-ordered stage
handlers — unlocking upstream's progressive / stream / incremental render
capability (and `LargeSymbolDraw` large-mode incremental), which the direct
path cannot express.

## Background — what is already done

`Scheduler.swift` (787 L) and `task.swift` (594 L) are FULLY ported: every
upstream public method exists with matching signatures — `restoreData`,
`getPerformArgs`, `getPipeline`, `updateStreamModes`, `restorePipelines`,
`prepareStageTasks`, `prepareView`, `performDataProcessorTasks`,
`performVisualTasks`, `performSeriesTasks`, `plan`, `updatePayload`. The
`Scheduler` is constructed with `dataProcessorHandlers: [StageHandlerInternal]`
+ `visualHandlers: [StageHandlerInternal]` (both sorted internally by
`__prio`). `StageHandlerInternal = {uid, visualType, __prio, __raw, handler:
StageHandler}`.

**The gap:** `ECharts` never constructs a `Scheduler`. `update()` (ECharts.swift
~1169–1345) hand-calls ~12 processor/visual handlers in SOURCE order, from a
different registration model: `_registers.capturedProcessors: [(GlobalModel) ->
Void]` plus discretely-invoked handlers (`dataStack`, `dataZoomProcessor`,
`negativeDataFilters`, `dataFilters`, `dataSamplers`, `legendFilter`,
`graphCategoryFilterStageHandler`, `mapDataStatisticStageHandler`, axisPointer
`collect`, `performVisualStage`, `performVisualMapStage`, `aria`, `decal`).
Series data tasks are run as `dataTaskReset(seriesModel.dataTask.context)`
directly; series RENDER runs synchronously inside `render()`.

## Phasing (revised after verifying Scheduler internals)

Verified against the ported Scheduler: `performDataProcessorTasks`,
`performVisualTasks` (both via `_performStageTasks` reading `_stageTaskMap`
built by `prepareStageTasks` from `_allHandlers`) and `performSeriesTasks`
(`seriesModel.dataTask.perform()`, equivalent to today's `dataTaskReset` loop)
are ALL FUNCTIONAL. But `prepareView` is a PORT-TODO no-op: `ChartView` has no
`renderTask` / `incrementalPrepareRender`, so the series RENDER pipeline is not
built. This splits C:

- **C1 — control-flow spine (pure wiring, land first).** Seams 1, 2, 3a, 3b,
  3c below. Makes `update()` drive the three perform-stages through the
  Scheduler. No new visible capability; makes the control flow upstream-faithful
  and processor order = web-oracle order. Gated by the web-oracle invariant.
- **C2 — progressive render (requires a view-layer port).** Port
  `view/Chart.ts` `renderTask` + `incrementalPrepareRender` + `incrementalRender`
  onto `ChartView`, un-stub `prepareView` to `_pipe(model, renderTask)`, add the
  progressive render loop in `render()` + the animation-loop `unfinished` pump.
  THIS delivers actual progressive/incremental rendering.
- **C3 — `LargeSymbolDraw` large-mode incremental** on C2's progressive executor.

Registration unification (Task 1) assembles the two `[StageHandlerInternal]`
lists EXPLICITLY in ECharts (each known handler + its upstream `__prio`), rather
than rewiring every scattered/stubbed `install.swift` `registerProcessor`/
`registerVisual`. `EChartsInstallRegisters.registerProcessor` currently only
CAPTURES the axis-stat overallReset; `registerVisual` is a base no-op stub.

## Architecture

Four seams, wired one at a time behind the existing path, each gated:

1. **Registration unification.** `_registers` gains
   `dataProcessorHandlers: [StageHandlerInternal]` and
   `visualHandlers: [StageHandlerInternal]`. Add `registerProcessor(prio,
   StageHandler)` and `registerVisual(prio, StageHandler)` that append a
   `StageHandlerInternal` with the given `__prio`. Register every
   currently-hand-called handler at its UPSTREAM priority (see table). The
   old hand-called blocks stay in place and functional until each seam below
   replaces them, so the build never has a half-wired update().

2. **Scheduler construction.** `ECharts.init` builds
   `Scheduler(dataProcessorHandlers:, visualHandlers:, ecInstance:, api:)`.
   `setOption` calls `scheduler.restorePipelines(zr, ecModel)` +
   `scheduler.prepareStageTasks()` after model reuse/merge (before update()).

3. **Perform-stage routing (3 sub-seams, gated separately).**
   - 3a: replace the processor block with `scheduler.performDataProcessorTasks(ecModel, payload)`.
   - 3b: replace `performVisualStage/VisualMap/aria/decal` with `scheduler.performVisualTasks(ecModel, payload)`.
   - 3c: replace the `dataTaskReset` loop with `scheduler.performSeriesTasks(ecModel)`.

4. **Progressive render + pump.** `render()`'s series render becomes
   `renderTask.perform` per pipeline; `EChartsHostView`'s animation loop pumps
   `scheduler.unfinished` across frames (like the existing AnimationLoop).
   `LargeSymbolDraw` large-mode incremental hooks the progressive executor.

## Priority table (the crux)

The current hand-order is NOT upstream priority order. Switching to
Scheduler `__prio` sort REORDERS these. Upstream order (= web-oracle order):

| handler                     | upstream `__prio`        | current call position |
|-----------------------------|--------------------------|-----------------------|
| legendFilter                | SERIES_FILTER 800        | 7                     |
| dataStack                   | DATASTACK 900            | 2                     |
| axisStatistics (captured)   | AXIS_STATISTICS 920      | 3                     |
| dataZoomProcessor           | FILTER 1000              | 1                     |
| graphCategoryFilter         | FILTER 1000              | 8                     |
| negativeDataFilter          | DEFAULT 2000             | 4                     |
| dataFilter                  | DEFAULT 2000             | 5                     |
| dataSample                  | STATISTIC 5000           | 6                     |
| mapDataStatistic            | STATISTIC 5000           | 9                     |
| axisPointer collect         | STATISTIC 5000           | 10                    |

Visual side (`performVisualTasks`, sorted by `__prio`):
style LAYOUT/GLOBAL/CHART 1000–3000, visualMap COMPONENT 4000, brush BRUSH
5000 (runs post-layout, stays in render()), aria ARIA 6000, decal DECAL 7000.

## Invariant (the gate)

NOT "byte-identical to current native". The correct invariant:

> All existing tests green (currently 653) AND every demo PNG's fidelity to
> the WEB oracle does not get worse.

Rationale: the Scheduler order equals upstream priority order equals the web
oracle's order. Reordering can only move native TOWARD web. Any demo that
diverges from web after a seam is either (a) a latent order-dependent bug the
old hand-order happened to mask — a faithfulness WIN, keep it — or (b) a new
regression — a bug, fix it. Distinguish via `swift run EChartsDemoGallery
--compare <name> <dir>` (renders native + web panes) on the affected demo.

Per-seam gate: `swift build` (0 new warnings, known-set excepted) +
`swift test` green + `--render-all` + spot-`--compare` the demos most exposed
to the reordered handler (dataZoom, stacked bar/line, pie legend-toggle,
sampled line-lttb, map, graph legend).

## Risks & mitigations

- **Processor reorder changes output.** Mitigated by the web-oracle gate
  above + seam-at-a-time landing (3a/3b/3c separate commits).
- **Strong ref cycle** in task `_upstream`/`_downstream` (task.swift:184
  PORT-TODO) — audit for leaks once pipelines are live; break with `weak` if
  a retain cycle shows under the live host.
- **`getData()` force-unwrap** if `performSeriesTasks` doesn't populate the
  inner data slot the way `dataTaskReset` did — verify 3c keeps `getData()`
  non-nil for every series type before landing.
- **This is a sequential single-file rewire** of the render hot path; do NOT
  parallelize. Execute task-by-task with the gate.

## Out of scope (deferred)

Sub-project E (lifecycle/events: bindRenderedEvent, connect, loading, media
query) and live NativePainter per-zlevel multi-layer. Universal transitions.
