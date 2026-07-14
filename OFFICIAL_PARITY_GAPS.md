# Official-examples parity gaps

What the official-examples tab has surfaced by putting our native pane next to real echarts.js.
Every entry is a **framework** gap, not a demo bug — the rule is: align with upstream, never simplify
the demo to fit what the port can do.

Status: `confirmed` = root-caused against upstream source. `unresolved` = reported, not yet
root-caused (needs a real render — do NOT guess).

---

## LineView — the epicentre

`chart/line/LineView.swift` was built to "draw the line" and skipped almost everything decorative.
Those decorations are exactly what the official examples exist to demonstrate. All five are in the
same file, so they are one task.

| # | Missing | Upstream | Symptom / demos | Status |
|---|---|---|---|---|
| L1 | `getVisualGradient` + `clipColorStops` | `LineView.ts:222,268`, applied at `stroke:837` and `fill:869` | The line's stroke AND the area's fill should carry a visualMap-derived gradient, so the chart is coloured by region. We paint a flat colour. `line-aqi`, `line-sections`, `area-pieces`, `line-gradient`, + 4 more | confirmed |
| L2 | `_initSymbolLabelAnimation` | `LineView.ts:1078` | Symbols should pop in left-to-right, each delayed by its position along the base axis, in step with the clip sweep. Ours appear all at once. `bump-chart` | confirmed |
| L3 | `lineAnimationDiff` (**whole 185-line file unported**) + a bogus reuse gate | `lineAnimationDiff.ts`; upstream reuses the polyline when `prevCoordSys.type === coordSys.type && step === this._step` | Our gate adds `_prevPointCount == linePoints.count`. A dataZoom CHANGES the point count → gate fails → polyline rebuilt → **the clip-reveal enter animation replays on every zoom**. Upstream just re-shapes. Affects every demo with a dataZoom | confirmed |
| L4 | `endLabel` (upstream 41 refs, ours **0**) | `LineView.ts` | The label that rides the end of each line (the series name). `line-race` | confirmed |
| L5 | `createPolarClipPath` never called | `LineView.ts:575` | Both clip-path builders EXIST in `chart/helper/createClipPathFromCoordSys.swift`; LineView only ever calls `createGridClipPath`, so a POLAR line has no clip path and **no enter animation**. `line-polar`, `line-polar2` | confirmed |

## Other components

| # | Missing | Upstream | Symptom / demos | Status |
|---|---|---|---|---|
| A1 | `axisPointer.handle` (the draggable touch handle) | `BaseAxisPointer.ts` — 41 refs to `handle`; ours has 14 | `line-tooltip-touch` has no drag handle | confirmed |
| B1 | brush: `lineX`/`lineY`/`polygon` selectors, BrushView, BrushController, geo targets | `component/brush/*`, `component/helper/Brush*` | Cover never draws; a brush cannot be painted or dispatched on geo. 13 demos | in progress |

## Reported, NOT yet root-caused — needs a real render, no guessing

| Demo | Report |
|---|---|
| `line-function` | No axis ticks. NOTE: `minorTick` IS implemented (AxisBuilder 17 refs vs upstream 12; the four scales all implement `getMinorTicks`) — so the cause is elsewhere. Render it before theorising. |
| `line-y-category` | Tooltip differs from html |
| `line-markline` | Missing the markLine labels ("tips") and three background-coloured regions |
| `line-draggable` | Native shows an EXTRA tip html does not |
| `intraday-breaks-1` | Native completely different from html |
| `matrix-sparkline` | Native completely different. KNOWN: this is the one demo still hard-CRASHING in the headless render sweep (`--render` exits non-zero), so the native pane is not "wrong", it is dead. Fix the crash first, then re-compare. |
| `dataset-link` (a) | Highlighting a pie sector does not hide/blur the other labels the way html does |
| `dataset-link` (b) | Hiding a line (legend toggle) fades out in html; native just disappears. NOTE: `removeElementWithFadeOut` IS ported and IS used by PieView/BarView/ChordView/SymbolElement — but by LineView never (and upstream's LineView does not call it either), so the fade must originate somewhere else. Render before theorising. |

---

## Why these were not caught earlier, and what replaces the manual reporting

The port's oracle was (a) demos we wrote ourselves, which only ever exercised what we had already
implemented, and (b) a SINGLE STATIC FRAME with animation forced off. Anything that only exists in
TIME — an enter animation, a transition, a morph — was invisible to it **by construction**. That is
how `universalTransition` hid for a year, and it is why L2/L3/L5 above were reported by a human
watching the screen rather than by the test suite.

The replacement, once the tree is green:

1. **Full static diff** — `--compare` every official demo, score native-vs-echarts.js pixel
   difference, rank. Finds every demo that merely *looks* wrong.
2. **Time-aware diff** — sample both panes at t = 0.2 / 0.5 / 1.0s. This is the oracle the port never
   had; `line-polar`'s missing enter animation is invisible to a still frame.
