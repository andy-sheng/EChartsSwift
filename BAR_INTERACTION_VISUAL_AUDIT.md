# Official bar interaction visual audit

Primary run: `build/bar-interaction-visuals-final3`

Targeted reruns after harness fixes: `build/bar-interaction-visuals-harness-fix`

Method: same-instance Native/Web action sequences, real ZRender pointer hit testing, per-step
screenshots, resolved interaction records, and independent visual-agent review. Computer Use was not
used.

Capture result: 46/46 scenarios executed successfully. Conservative visual verdict: 34 PASS,
11 PARTIAL, 1 UNCERTAIN, with no high-confidence Native product defect remaining in the interactions
that were exercised. `PARTIAL` means the generated hover/legend/dataZoom checks passed but an
example-specific interaction was not exercised.

| Demo | Verdict | Note |
| --- | --- | --- |
| official-bar-animation-delay | PASS | Two series hover, cleanup, and both legend cycles match Web. |
| official-bar-background | PASS | Hover emphasis and cleanup match Web. |
| official-bar-breaks-brush | PARTIAL | Hover and four legend cycles pass; creating/resetting an axis break by brushing is not wired in this static demo. |
| official-bar-breaks-simple | PARTIAL | Hover and four legend cycles pass; click-to-expand/collapse axis breaks is not implemented by the Native demo path. |
| official-bar-brush | PARTIAL | Hover and four legend cycles pass; toolbox brush selection and clear are not captured. |
| official-bar-data-color | PASS | Per-item color emphasis and cleanup match Web. |
| official-bar-drilldown | PARTIAL | Hover and cleanup pass; the static demo omits the upstream click handler, so the click frame does not drill down on either pane. |
| official-bar-gradient | PARTIAL | Gradient emphasis and cleanup now match Web; the example's click-zoom behavior remains uncovered. |
| official-bar-label-rotation | PASS | Hover, four legend cycles, neutral cleanup, and toolbox restore pass after the pointer-path fix. |
| official-bar-large | PARTIAL | Real slider drag changes both panes from 0–100 to 10–100 and clears correctly; large-mode per-item hover has no resolvable visual target. |
| official-bar-multi-drilldown | PARTIAL | Hover and cleanup pass; the static demo omits the upstream drilldown callback and option stack. |
| official-bar-negative | PASS | Three hovers, axisPointer cleanup, and three legend cycles match Web. |
| official-bar-negative2 | PASS | Horizontal tooltip/axisPointer and cleanup match Web. |
| official-bar-polar-label-radial | PASS | Polar tooltip and cleanup match Web. |
| official-bar-polar-label-tangential | PASS | Polar tooltip and cleanup match Web. |
| official-bar-polar-real-estate | PASS | Combined Lowest/Highest/Average formatter, cleanup, and two legend cycles match Web. |
| official-bar-polar-stack-radial | PASS | Three focus hovers and three legend cycles match Web. |
| official-bar-polar-stack | PASS | Three focus hovers and three legend cycles match Web. |
| official-bar-race-country | PARTIAL | Static frame and cleanup agree; timer-driven ranking updates and hover feedback are not visibly exercised. |
| official-bar-race | PARTIAL | Legend off/on passes; timer-driven ranking updates and hover feedback are not visibly exercised. |
| official-bar-rich-text | PASS | Tooltip, rich labels, cleanup, and three legend cycles match Web. |
| official-bar-simple | PASS | Hover emphasis and cleanup match Web. |
| official-bar-stack-borderRadius | PASS | Stacked geometry and cleanup match Web; hover feedback is visually subtle. |
| official-bar-stack-normalization-and-variation | PASS | Normalized labels, variation bands, and cleanup match Web. |
| official-bar-stack-normalization | PASS | Normalized labels, geometry, and cleanup match Web. |
| official-bar-stack | PASS | Nine-series tooltip, cleanup, and all nine legend cycles match Web. |
| official-bar-tick-align | PASS | Shared tooltip, shadow axisPointer, and cleanup match Web. |
| official-bar-waterfall | PASS | Tooltip hides the Placeholder helper series and cleanup matches Web. |
| official-bar-waterfall2 | PASS | Income/Expenses formatter, cleanup, labels, and legend cycles match Web. |
| official-bar-y-category-stack | PASS | Five-series tooltip, cleanup, labels, and five legend cycles match Web. |
| official-bar-y-category | PASS | Two hovers, cleanup, and two legend cycles match Web. |
| official-bar1 | PASS | Two hovers, cleanup, two legend cycles, and final restore match Web after the pointer-path fix. |
| official-data-transform-sort-bar | PASS | Sorted-bar emphasis and cleanup match Web. |
| official-dataset-encode0 | PASS | VisualMap indicator and cleanup match Web. |
| official-dataset-series-layout-by | PASS | Seven legend cycles restore every linked chart without stale blur after the pointer-path fix. |
| official-dataset-simple0 | PASS | Three hovers and three legend cycles restore all series without stale blur. |
| official-dataset-simple1 | PASS | Three hovers and three legend cycles restore all series without stale blur. |
| official-dynamic-data | PARTIAL | Hover, cleanup, and both legend cycles pass; timer-driven append/update behavior is not advanced by this deterministic runner. |
| official-matrix-mini-bar-geo | PASS | Three hovers, cleanup, and both linked legend cycles match Web. |
| official-mix-line-bar | PASS | Two hovers, cleanup, three legend cycles, and final restore match Web. |
| official-mix-timeline-finance | PARTIAL | Hover and six linked legend cycles pass; timeline year switching/playback is not captured. |
| official-mix-zoom-on-value | PASS | Semantic 2% dataZoom pan, cleanup, and restore match Web; its visible legend overlaps the slider hit region and is explicitly skipped. |
| official-multiple-y-axis | PASS | Two hovers, cleanup, three legend cycles, and final restore match Web. |
| official-polar-endAngle | PASS | Both polar series tooltips and cleanup match Web. |
| official-polar-roundCap | UNCERTAIN | Both legend cycles pass, but the two hover frames have no visible response on either pane. |
| official-watermark | PASS | Heatmap/markLine tooltips and cleanup match Web across the composite layout. |

## Fixes verified by the sweep

- Browser-oracle pointer exit now clears the real DOM tooltip before comparison.
- Waterfall helper-series tooltip entries and polar real-estate combined formatter match the official examples.
- Bar emphasis/blur/select states now accept gradient fills and strokes.
- dataZoom target selection distinguishes a selected-window pan from a full-window handle resize and records the resulting ranges.
- Every legend restore uses a physical pointer path before click, so its subsequent pointer-out genuinely clears focus/blur state.

## Explicit coverage gaps

- Axis-break expand/collapse is not implemented on the Native path; `official-bar-breaks-brush` also drops the upstream brush-created-break harness.
- `official-bar-brush` still needs a toolbox brush arm, real rectangle gesture, selection verification, and clear gesture.
- The drilldown demos deliberately omit their upstream click callbacks in the static gallery options.
- Timer/timeline-specific transitions in race, dynamic-data, and timeline-finance are outside the deterministic generic sequence.
- `official-bar-gradient` click zoom and `official-polar-roundCap` visible hover feedback need dedicated scenarios.
- `official-mix-zoom-on-value` places the horizontal legend and slider on overlapping hit regions; the manifest records that pointer-routing gap instead of bypassing it with `dispatchAction`.
