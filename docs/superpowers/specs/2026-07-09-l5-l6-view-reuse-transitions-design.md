# L5/L6 — View Reuse + Update Matrix (faithful echarts.ts control flow) — Design

**Status:** design
**Date:** 2026-07-09
**Scope:** Promote the render-once `EChartsSlim` driver to the faithful `echarts.ts` update
control flow: reuse the `GlobalModel` and merge options across `setOption`, reuse views via
`prepareView` mark-and-sweep (honoring `__requireNewView`), let each view's already-ported
`data.diff` + `updateProps` produce cross-`setOption` tween transitions, and add the
`updateView`/`updateVisual`/`updateLayout`/`updateTransform` light-update matrix.

**Design mandate (user):** port *exactly* like upstream `echarts.ts`. No scope narrowing,
no "slim" shortcuts beyond what is genuinely host-specific (painter clear, Scheduler
progressive frames). Where a behavior is faithfully reproducible, reproduce it.

---

## 1. Motivation & current gap

The user has a real **live-data-update** use case: the same chart instance receives repeated
`setOption` calls with changed data, and expects smooth morphing (bars grow, points slide,
sectors sweep, added items fade in, removed items fade out) — exactly as web echarts does.

Today `EChartsSlim` cannot morph because it discards the two things a transition needs:

1. **Model reuse.** `setOption` (EChartsSlim.swift:1120) does `let ecModel = GlobalModel()`
   on *every* call. Upstream (echarts.ts:770-777) reuses `this._model` unless it is the first
   call or `notMerge`, and calls `this._model.setOption(option, {replaceMerge})` to **merge**.
   Model reuse is what preserves each `SeriesModel` instance — and thus its previous
   `getData()` DataStore — so the new render can diff against the old data.
2. **View reuse.** `render()` (EChartsSlim.swift:1438-1445) does `root.removeAll()` +
   `storage.delAllRoots()` + wipes `_chartsMap`/`_componentsMap`/`_*ViewByModel`. Every view is
   destroyed and rebuilt, so no view holds the old element references or old `_data` to tween
   from. Upstream `prepareView` (echarts.ts:1687-1770) instead **reuses** the view from the map
   (keyed `_ec_<id>_<type>`), marks it `__alive`, and disposes only views left `__alive === false`.

Everything downstream of those two gaps is **already ported**:

- **Model merge**: `Global.swift` has `setOption`/`resetOption`/`_resetOption`/`mergeOption`/
  `_mergeOption` with full `replaceMerge`, component reuse by id, and **`__requireNewView`**
  (Global.swift:548) — the exact flag upstream `prepareView` consumes. This machinery is
  dormant only because the driver never reuses the model.
- **Per-view diff/tween (L5 machinery)**: `DataDiffer`, `updateProps`, `saveOldStyle`,
  `SymbolDraw.updateData` (`data.diff` add/update/remove + `updateProps`), and `BarView`'s
  `data.diff(oldData)` are ported. When a view is reused and its `_data` persists, these already
  emit tweens — they simply never run today because the view is thrown away first.
- **Animation loop**: `EChartsHostView`/`EChartsView` drive `zr.animation` via `AnimationLoop`;
  `updateProps` schedules `Animator`s that the live host ticks (see `live-animation-host`).

So this is a **driver-layer** project. The risk is not building new subsystems; it is that
`render()`'s wipe has, until now, guaranteed every view starts from a blank slate. Removing it
requires every view's `render()` to be **idempotent under reuse** (re-rendering onto its own
prior element tree, diffing rather than appending). That is the cross-cutting risk this spec
manages with a per-view audit gate.

---

## 2. Faithful upstream reference (what we mirror)

Traced from `upstream/echarts/src/core/echarts.ts`:

- **`setOption`** (770-800): first call or `notMerge` → `new GlobalModel()` + `init`; else reuse
  `this._model` and `_model.setOption(option, {replaceMerge})`. Then `prepare(this)` +
  `updateMethods.update.call(this, null, updateParams)`. `updateParams.optionChanged = true`.
- **`updateMethods.update`** (1880-1938): `resetCachePerECFullUpdate` → `setUpdatePayload` →
  `restoreData` → `performSeriesTasks` → `coordSysMgr.create` → `performDataProcessorTasks` →
  `updateStreamModes` → `coordSysMgr.update` → `clearColorPalette` → `performVisualTasks` →
  `setBackgroundColor` → `render(...)`. (The slim `update()` already mirrors this order; the
  only change is what `render` does.)
- **`prepareView`** (1687-1770): (a) set every existing view `__alive = false`; (b) per model,
  `doPrepare`: `viewId = '_ec_' + model.id + '_' + model.type`; reuse `viewMap[viewId]` unless
  `model.__requireNewView`; else create+`init`+`zr.add(group)`; set `model.__viewId`,
  `view.__alive = true`, `view.__model = model`; (c) sweep: any view still `__alive === false` →
  `renderTask.dispose()` (series) + `zr.remove(group)` + `view.dispose()` + splice + delete map.
- **`render`** (doRender, 2400-2450) → **`renderComponents`** (2452-2467): for each component view
  `clearStates` → `render` → `updateZ` → `updateStates`. → **`renderSeries`** (2472-2539): per
  series set `chartView.__alive = true`, `clearStates`, `renderTask.perform` (calls
  `ChartView.render`), `updateBlend`, then a second pass `updateZ` + `updateStates`; finally
  `each(_chartsViews)` `if !__alive → chart.remove(ecModel, api)`.
- **Update matrix** (2011-2110): `updateView` (mark all series render tasks dirty + `renderSeries`
  with dirtyMap, no data reprocess), `updateVisual` (performVisualTasks then render with
  `remain`), `updateLayout` (performVisualTasks with `setDirty` layouts), `updateTransform`
  (per-view `updateTransform()` hook, coordinate transform only — used by roam/dataZoom).
- **`dispatchAction`** (actionType→updateMethod): each `ActionInfo.update` string
  (`'update'`/`'updateView'`/`'updateVisual'`/`'updateLayout'`/`'none'`/`'updateTransform:...'`)
  selects which `updateMethods.*` runs after the action handler mutates the model.

---

## 3. Architecture — decomposition into two sub-projects

### Sub-project L5: model reuse + view reuse + data-tween transitions (delivers the visible morphing)

Sequential, driver-layer, with a per-view idempotency audit. This is what makes live-data
`setOption` morph. Ordered by dependency:

**L5-1 — Driver model reuse in `setOption`.**
Replace the unconditional `GlobalModel()` with the faithful branch:
- Keep a persistent `self._model` and `self._optionManager`.
- First call **or** `notMerge` → new `GlobalModel()` + `init(...)` (current behavior).
- Else reuse `self._model`; call `ecModel.setOption(opt, InnerSetOptionOpts(replaceMerge: ...))`.
- Preprocessors (grid inject, graphic/radar/parallel/visualMap/marker/timeline/aria/axisPointer)
  must still run on the incoming `opt` before merge — hoist them into a helper called on both
  branches (upstream runs preprocessors inside `OptionManager.setOption`; the slim runs them in
  the driver, so keep them driver-side but shared).
- `notMerge` parameter: add `setOption(_ option:, notMerge: Bool = false)` overload; the existing
  1-arg call stays `notMerge:false` (merge — the upstream default). `EChartsHostView`'s
  demo-switch path passes `notMerge:true` (fresh chart per demo — correct, no cross-demo morph).

**L5-2 — `prepareView` faithful mark-and-sweep + `render()` reset removal.**
- Delete the wipe block (EChartsSlim.swift:1438-1445). Keep the background-rect logic but make it
  idempotent (remove the prior bg rect before re-adding, or reuse a stored `_bgRect`).
- `prepareView`: before `doPrepare`, set every view in `_componentsViews`/`_chartsViews`
  `__alive = false`. In `doPrepare`, honor `model.__requireNewView` (skip map reuse, force
  create) and reset the flag to `false`. Key `viewId` by **`model.id`** (upstream uses the model
  id, not the component index — required so a reordered/re-added series keeps its view). Set
  `model.__viewId = viewId`, `view.__alive = true`.
- After both prepare passes, run the **dead-view sweep**: for each view still `__alive === false`,
  `view.dispose(ecModel, api)` (+ `renderTask.dispose()` for series when Scheduler present),
  `root.remove(view.group)` / `storage.delRoot`, remove from list + map + `_*ViewByModel`.
- `renderSeries` tail: `each(_chartsViews) { if !$0.__alive { $0.remove(ecModel, api) } }` (already
  partially present; make faithful).

**L5-3 — Per-view idempotency audit + diff/tween verification (the breadth/risk task).**
Every registered `ChartView`/`ComponentView` must re-render correctly onto its *own* prior group
instead of a fresh one. Audit each view's `render()`:
- Views that already diff (`SymbolDraw`-based: scatter/effectScatter/line/graph nodes; `BarView`
  `data.diff`) — verify tween on reuse, no duplicate elements.
- Views that `group.removeAll()` at the top of their own `render()` (many components + simpler
  charts) — these are *already* idempotent (they clear their own subtree each render); confirm
  and leave them (they simply won't tween, which matches upstream for non-diffing views).
- Views that **append without clearing and without diffing** — these would duplicate elements on
  reuse. Fix by either adding a `data.diff` path (if upstream tweens that chart) or a
  `group.removeAll()` guard (if upstream rebuilds it). Cross-check each against its upstream view.
- Deliverable per chart type: a reuse test (`setOption` twice, assert element count stable + old
  element identity preserved for updates + `Animator` scheduled for changed values).

**L5-4 — `clearStates`/`updateStates`/`updateZ` on reuse + `saveOldStyle` seam.**
Upstream `renderComponents`/`renderSeries` wrap each `view.render` with `clearStates` (before) and
`updateZ`+`updateStates` (after). On a *reused* view, `clearStates` restores elements to normal
before the new render, and `saveOldStyle` stashes the pre-transition style so state (emphasis)
transitions interpolate. Wire these into the slim `renderComponents`/`renderSeries` (currently
`updateZ` is present but `clearStates`/`updateStates` are noted dropped). Gate on the states
engine already ported in Phase 30.

### Sub-project L6: the update-method matrix (faithful light-update dispatch)

Separable from L5 and sequenced after it. Today every action with `update:"update"` re-runs the
full `update()`. Faithful behavior routes to a lighter method:

**L6-1 — `updateView` / `updateVisual` / `updateLayout`.**
Port `updateMethods.updateView` (re-run `renderSeries` with all series marked dirty, no
restoreData/reprocess), `updateVisual` (re-run `performVisualTasks` + render `'remain'`),
`updateLayout` (re-run layout stages + render). These reuse the L5 view-reuse machinery (they
depend on views persisting).

**L6-2 — `updateTransform`.**
Port `updateMethods.updateTransform`: per component/chart view call its `updateTransform(model,
ecModel, api, payload)` hook (coordinate-transform-only re-render); views without the hook fall to
full dirty. This is the faithful home for roam/inside-dataZoom pan, which today do bespoke
partial re-renders.

**L6-3 — `dispatchAction` → update-method routing.**
Read each `ActionInfo.update` string and dispatch the matching `updateMethods.*` after the handler
mutates the model (replacing the current always-`update()` behavior), including the
`updateTransform:...` and `none` cases.

---

## 4. Data flow (a live-data `setOption` on a reused instance)

```
host.setOption(newOption)  // notMerge:false
  → run preprocessors on newOption
  → self._model.setOption(newOption, {replaceMerge})   // MERGE: SeriesModels reused, old getData() retained
  → update():
      restoreData / performSeriesTasks  // new DataStore built; old one still referenced by the view
      coordSysMgr.create/update; performVisualTasks
      render():
        prepareView: mark __alive=false → reuse views by _ec_<id>_<type> → mark alive → sweep dead
        renderComponents: clearStates → view.render → updateZ → updateStates
        renderSeries: per series clearStates → chartView.render(newModel):
            data.diff(view._data)  // add/update/remove vs OLD data
              enter  → element created, fade/scale in (updateProps 0→target)
              update → element reused, updateProps(old attrs → new attrs)  ← THE TWEEN
              remove → element fade/scale out then removed
            view._data = newData
          updateZ → updateStates
      Animators scheduled → AnimationLoop ticks → morph plays
```

## 5. Error handling & correctness constraints

- **Idempotency is the invariant.** Any view that appends-without-diff-or-clear on reuse
  duplicates elements. L5-3's audit + per-view reuse test is the guard. The full XCTest suite
  (`swift test`, currently green) is the regression gate on every task.
- **`notMerge` for demo-switch.** The gallery/demo-switch host path must pass `notMerge:true` so
  switching demos rebuilds fresh (no morph from an unrelated prior chart, no stale-view bleed).
  This preserves today's correct static-render + parity behavior byte-for-byte.
- **Headless PNG oracle.** Reused-view transitions schedule looping/finite animators; the static
  PNG path must `advanceAnimationsForStaticFrame` to the settled frame (see `live-animation-host`
  trap) so `--render`/`--compare` stay deterministic. Verify no demo's static PNG changes.
- **Background rect idempotency.** The bg rect must not accumulate across reused renders.
- **`__requireNewView`** already set by `_mergeOption` on type-change/replace — the driver must
  honor it (force new view) and reset it, exactly as upstream.

## 6. Testing strategy

- **Unit (per task):** L5-1 model-reuse test (two setOption calls → same SeriesModel identity,
  merged option); L5-2 prepareView test (reuse hit, `__requireNewView` miss, dead-view sweep
  disposes + unregisters); L5-3 one reuse+tween test **per chart view** (stable element count,
  reused-element identity, `Animator` scheduled on changed values, none on unchanged); L5-4
  states-on-reuse test; L6 one test per update method + a dispatch-routing test.
- **Regression:** full `swift test` green after every task (the standing gate).
- **Parity:** `swift run EChartsDemoGallery --render <name>` for a sample across chart families
  must be pixel-identical to pre-change (static frame unaffected by dormant transition machinery).
- **Live smoke:** a two-`setOption` harness on bar/line/scatter/pie asserting animators run
  (transition actually plays), since PNG can't see motion.

## 7. Sequencing & risk

L5-1 → L5-2 → L5-3 (breadth, the bulk) → L5-4, then L6-1 → L6-2 → L6-3. L5-3 is per-chart-view
and is the parallelizable/bulk portion, but each view integrates serially behind the full-suite
gate (a duplicated-element regression in one view must not land). L6 is optional-but-faithful and
strictly follows L5. Each task ends green + committed + pushed (project cadence: 0 new warnings,
`swift test` green, one commit per task, no backticks in messages,
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`).

## 8. Out of scope (genuinely, not "slim shortcut")

- **Universal transitions** (`series.universalTransition`, cross-series `id` morphing,
  `morphSeries`) — a distinct upstream subsystem, not part of the view-reuse/data-diff path. If
  the user later wants cross-type morphing it gets its own spec.
- **Scheduler progressive/incremental frame rendering** (`large`/`progressive`) — the render task
  runs synchronously in the slim; progressive framing is a NativePainter concern already noted
  deferred. `renderTask.perform` is invoked directly (as today).
- **`lazyUpdate`/`PENDING_UPDATE`/media-query re-resolve on resize** — not needed for the
  live-data path; `setOption` updates synchronously as today.
