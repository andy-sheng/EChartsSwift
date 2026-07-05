# Interaction-Layer Plan — the remaining upstream surface

**Status at time of writing:** the entire *static-render* surface + the *data* layer are ported and
functional (see `PORT_STATUS.md` §1–§59): all 22 chart types, all 8 coordinate systems, visualMap
encoding, static components, and the dataset → transform → series data pipeline. From `option` to a
native `CGImage` is end-to-end complete.

Everything that remains upstream is the **interaction-component layer**, which `CONVENTIONS.md` §5
(an *overriding* project rule) explicitly defers as PORT-TODO:

| Component | Nature |
|---|---|
| `axisPointer` | crosshair + value readout that follows the pointer |
| `tooltip` | hover-triggered floating content |
| `dataZoom` (inside + slider) | drag / wheel zoom of an axis range |
| `brush` | drag-select regions, cross-highlight |
| `toolbox` | on-canvas buttons (saveAsImage, restore, dataView, …) |
| `timeline` | play/scrub across option snapshots |
| `thumbnail` | minimap for large graph/roam |
| `component/helper` | `BrushController`, `RoamController`, `cursorHelper`, `interactionMutex`, `sliderMove`, `MapDraw` — the interaction helpers the above build on |
| `aria` | accessibility output — **inert in this port** (label writes to a nonexistent DOM; decal needs an unported decal→CoreGraphics pattern-fill path). Not worth porting until decal rendering exists. |

## Why this is not "port N more components"

Interaction is blocked on a **substrate that does not exist yet**, because the port was deliberately
built render-once:

- **`EChartsSlim`** (`core/EChartsSlim.swift`) is a snapshot driver: `setOption() → update() →
  render()` produces a flattened, z-sorted display list (`Storage`, upstream `zr.storage`) that a host
  painter rasterizes. There is **no** `dispatchAction`, no event loop, no re-render-on-action path.
- **`ExtensionAPI`** (`core/ExtensionAPI.swift`) — the object every component/view receives as `api` —
  has its whole action/emphasis surface (`dispatchAction`, `getZr`, `enterEmphasis`/`leaveEmphasis`,
  `enterSelect`, `enterBlur`, `getViewOfComponentModel`, …) as **abstract `fatalError` PORT-TODO**.
  Upstream these forward to the ECharts instance facade.
- **`core/echarts.ts`** (the `EChartsType` facade, **3434 lines, NOT ported**) is that missing owner:
  it holds the live `zr` (ZRender) instance, binds `zr.on('mousemove'/'click'/…)` → `axisTrigger` /
  `dispatchAction`, and implements `dispatchAction(payload) → action handler → model mutation →
  updateMethods.update → re-render`. `EChartsSlim` is the intentional slim stand-in that skipped it.
- **ZRenderKit already has the low-level event infra** (`Handler.swift`, `GestureMgr.swift`,
  `Core/event.swift`, `Core/Eventful.swift`, `mixin/Draggable.swift`) — the render engine can receive
  pointer/gesture events. Nothing consumes them on the EChartsKit side yet.

So every interaction component calls `api.dispatchAction(...)` and `api.getZr().on(...)` — both of
which are unimplemented. **The substrate must land first.**

## Recommended sequencing

### Phase A — action / event substrate (prerequisite for everything below)
1. **`registerAction` + action registry** — the `(actionType → handler)` map + `registerAction` on the
   install-registers, mirroring `core/echarts.ts`. Components register their actions here.
2. **`dispatchAction` + the update round-trip on `EChartsSlim`** — `dispatchAction(payload)` looks up
   the handler, mutates the model, and re-runs the (already-ported) `update()`/`render()` pipeline
   (upstream `updateMethods.update`). This is a *focused subset* of `echarts.ts`, not the whole 3434
   lines.
3. **A concrete `ExtensionAPI`** — implement the abstract methods (`dispatchAction`, `getZr`,
   `enterEmphasis`/`leave…`, `getViewOf…`) against the live `EChartsSlim` instance.
4. **A live-view host** — a small `EChartsView` (UIView/NSView, or a headless harness) that owns a
   ZRenderKit `ZRender` + `Handler`, feeds pointer/gesture events into the ec instance, and re-paints
   the display list on each update. This is what turns the snapshot renderer into a live chart.

*Note:* this is the point that departs from the "slim, render-only" design. Confirm the architectural
direction before building it — it is a deliberate expansion, not a mechanical port.

### Phase B — interaction components (each consumes the Phase-A substrate)
Ordered by value / dependency:
1. **`axisPointer`** — foundational; tooltip's cartesian/polar/single trigger rides on it
   (`axisTrigger` → `updateAxisPointer`). Ports `CartesianAxisPointer`/`PolarAxisPointer`/
   `SingleAxisPointer` + `axisTrigger` + `globalListener`.
2. **`tooltip`** — the highest-visibility feature. Needs a content host: upstream uses an HTML/rich
   DOM tooltip (`TooltipHTMLContent`) — in a native app this becomes a native overlay
   (`TooltipRichContent`-style, drawn with ZRenderKit text/rect, or a platform popover). The
   `tooltipMarkup` / `seriesFormatTooltip` content model is platform-independent and ports directly.
3. **`dataZoom`** — `InsideZoom` (wheel/drag on the coord) then `SliderZoom` (the slider widget);
   both drive `dataZoomProcessor` → axis extent → re-render. Reuses `RoamController` from
   `component/helper`.
4. **`brush`**, **`toolbox`**, **`timeline`**, **`thumbnail`** — in decreasing generality.

### Emphasis / states (orthogonal, also §5-deferred)
`enterEmphasis`/`select`/`blur` on hover/click are used by tooltip + legend highlight. These land as
part of Phase A's concrete `ExtensionAPI` plus per-view state application (currently every view builds
elements without state layers). Can be staged incrementally alongside Phase B.

## The scope decision

`CONVENTIONS.md` §5 defers this entire layer; the session goal is "迁移完 echarts" (finish migrating
echarts). At this boundary the two point in opposite directions, and Phase A is a real architectural
expansion (a live-view host + action loop the slim design intentionally skipped). Two coherent paths:

- **Hold** — treat the §5-scoped migration (all rendering + data) as the completion milestone; leave
  interaction as the documented, deliberate PORT-TODO it already is.
- **Proceed** — lift §5, build Phase A, then Phase B in the order above, one phase at a time with the
  established build/test/faithfulness-review/commit cadence.

This document exists so that whichever is chosen, the next step is unambiguous and grounded in the
actual code (not a guess).
