# Visual interaction testing

Use this workflow for regressions that appear only after a chart interaction and must be judged at
the final painter output (missing labels, markers, guide lines, clipping, or stale visual state).
It extends the existing deterministic screenshot/contact-sheet oracle with same-instance action
sequences and a fixed visual-agent review contract.

## Why this is separate from the existing sweep

`--scene-sweep-native/web` derives broad legend/dataZoom/timeline coverage and is the fast structural
gate. Each action slot starts from a fresh chart, so it intentionally cannot reproduce sequences such
as “click F, click F again without moving the pointer, then leave the legend.”

`capture-demo-screenshots.sh --action` also accepts one independent action. Its contact sheets remain
the right tool for entrance and single-action animation phases.

The interaction-visual workflow keeps one chart instance alive for the entire scenario. A
`clickLegend` step resolves the *current* rebuilt LegendItem and sends `mousemove` (when requested),
`mousedown`, `mouseup`, and `click` through ZRender's real Handler. It does not replace the click with
a direct `legendToggleSelect` dispatch.

## Run a scenario

```sh
scripts/capture-interaction-visuals.sh \
  Tests/VisualInteractionScenarios/official-chord-style-f-toggle.json
```

Outputs are written under `build/interaction-visuals/<case>/`:

- `frames/native/*.png` and `frames/web/*.png`: original screenshots for every named capture.
- `resolved.native.json` and `resolved.web.json`: the executed steps and resolved hit coordinates.
- `contact.png`: Native/Web rows ordered by scenario capture.
- `review-request.json`: semantic checks, image paths, and the required verdict schema.

Then give `review-request.json`, `contact.png`, and the original PNGs to a visual-recognition child
agent. The child agent must inspect pixels, apply the listed semantic checks, and return the declared
JSON shape. It should not use raw pixel equality as the verdict: Core Text/WebKit antialiasing and
equal-z ribbon overlap are expected to differ.

Native captures are painted from the live `view.zr.storage` display list. Do not snapshot only
`ec.getRoot()`: tooltip content, axisPointer lines/labels/handles and other host-owned overlays are
direct zrender roots and would disappear from the evidence.

## Run every official line case

```sh
DEMO_CAPTURE_BINARY=.build/debug/EChartsDemoGallery \
  scripts/capture-line-interaction-visuals.sh \
  build/line-interaction-scenarios \
  build/line-interaction-visuals-livezr
```

The gallery binary enumerates the official UI's `line` section, including cross-listed cases, and
generates one scenario per Native-supported demo. The batch continues after a single capture failure
and prints a final passed/failed summary. It covers representative line-series hovers and cleanup,
every backed visible legend item off/on, slider dataZoom drags, restore, the draggable-points graphic
target, and the tooltip-touch axisPointer handle.

## Run every official bar case

```sh
DEMO_CAPTURE_BINARY=.build/debug/EChartsDemoGallery \
  scripts/capture-bar-interaction-visuals.sh \
  build/bar-interaction-scenarios \
  build/bar-interaction-visuals
```

This uses the same same-instance runner and enumerates the official UI's complete `bar` section,
including dataset and matrix examples cross-listed by the gallery. Generated scenarios cover real
bar-element hover and cleanup, every backed visible legend item off/on, slider dataZoom drags,
toolbox restore, and click-driven drilldown targets. Keep intended interactions that were removed
from a static gallery option (for example upstream callbacks) separate from live-target discovery;
otherwise a missing handler can be mistaken for a passing non-interactive chart.

The orchestrating agent owns the final gate:

1. Fail immediately if capture or real Handler hit resolution fails.
2. Keep unit/structural assertions as deterministic coverage of model/state invariants.
3. Accept the painter layer only when the visual child agent returns `pass` with relevant evidence
   images; treat `uncertain` as requiring human review, never as a pass.

## Scenario format

```json
{
  "id": "case-id",
  "demo": "registered-demo-name",
  "checks": ["Visible semantic requirement"],
  "steps": [
    {"action": "settle", "capture": "baseline"},
    {"action": "clickLegend", "name": "F", "movePointer": true},
    {"action": "clickLegend", "name": "F", "movePointer": false},
    {"action": "pointerMove", "x": 1, "y": 1},
    {"action": "globalOut"},
    {"action": "settle", "capture": "final"}
  ]
}
```

Supported actions are `settle`, `clickLegend`, `hoverData`, `hoverSeries`, `clickData`,
`clickToolbox`, `dragDataZoom`, `dragGraphic`, `dragAxisPointer`, `pointerMove`, `globalOut`, and
`wait` (`milliseconds`, for real delayed UI cleanup such as tooltip hide or throttled handle moves).
Data actions accept `seriesIndex` plus `dataIndex`; use `dataName`
when earlier interactions rebuild/filter the series and therefore change indexes. `clickToolbox`
uses the stable feature name such as `restore`. Add a `capture` name
to any step that should produce a review frame. Scenario IDs and capture names are sanitized before
they become file names.
