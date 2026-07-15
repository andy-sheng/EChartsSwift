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

---

## Parity sweep results (2026-07-15)

Full native-vs-echarts.js pixel diff over 244 native official demos. 171/244 are within 4% — the port
body is sound. Divergence clusters, and each cluster is one framework hole:

**FIXED — top-level backgroundColor painted black (commit 0d3c0c8).** The single biggest cause. A
dozen demos at 25-93% collapsed to <4%: sankey-itemstyle 93.47→0.32, heatmap-map 27.66→3.13,
effectScatter-map 26.78→1.26, geo-lines 26.47→0.76, scatter-map 25.53→0.35. The geo/map rendering was
correct all along, hidden under a black fill.

**Still open, by cluster (each likely one root cause):**
- `pie-pattern` (89.79, WHITE bg so NOT the bg bug): the whole pie is grey-black. Slices should carry
  colour + a `decal` texture ("pie with textures"). Either pie itemStyle colour isn't applied or
  decal/pattern fill is unported. Root-cause with a render once the concurrent LineView/axisPointer
  agents free up the tree.
- matrix cluster: matrix-stock 25.29, matrix-covariance 21.43, matrix-mini-bar-geo 18.01,
  matrix-grid-layout 16.71, matrix-sparkline 16.27 (no longer crashes — a recent framework fix revived
  it). Not yet root-caused.
- parallel cluster: parallel-nutrients 26.37, parallel-aqi 18.42.
- treemap cluster: treemap-show-parent 25.55, treemap-visual 17.22.
- CRASH: bar-large, scatter-nebula (were also crashing in the earlier sweep).

Method note: `--compare` writes native + echarts.js PNGs; scratchpad/imgdiff scores mean per-channel
difference 0-100. The scores.tsv is the ranked worklist.

## Build hygiene (learned the hard way)
Two `helper.swift` in the same SwiftPM target break the ENTIRE module build ("multiple producers ...
helper.swift.o") — object-file names are flattened per target. When porting an upstream file whose
basename already exists (helper.ts, install.ts, index.ts), give the Swift file a disambiguated name
(lineHelper.swift, installMarkArea.swift). This bites hardest with concurrent agents: one agent's
name collision blocks every other agent's build too.
