# Native/Web chart interaction workflow

Use paths relative to the repository root.

## 1. Establish the baseline

```sh
git status --short --branch
git log --oneline origin/main..HEAD
swift build --product EChartsDemoGallery
BIN="$(swift build --show-bin-path)/EChartsDemoGallery"
"$BIN" --list
```

For a new or synchronized demo, compare the Native definition with the original Web example. Inspect more than the final option:

- `myChart.on`, `dispatchAction`, `setOption`, `appendData`
- `setInterval`, `setTimeout`, animation callbacks and progressive updates
- DOM buttons/listeners, asynchronous assets and map registration
- formatter, `renderItem`, symbol sizing, drag callbacks and drilldown code
- Native `option`, `webOptionJS`, `liveOption`, `drive`, `mapRegistrations`, direct asset loads and registry entry

The pinned local ECharts bundle is the Web oracle. A missing feature on both sides is a coverage failure, not parity.

## 2. Inventory interactive targets

Cover distinct handlers and states rather than every homogeneous datum:

| Family | Targets and state to cover |
|---|---|
| Pointer | series/item hover, tooltip, axisPointer, emphasis/focus/blur, cross-target hover, leave cleanup |
| Legend | every backed visible item, authored initial selection, single/multiple mode, selector, scroll paging |
| Selection | pie selection, brush modes/clear, tree expand/collapse, treemap drilldown/breadcrumb |
| Navigation | dataZoom handles/window, inside zoom, geo/graph/series pan and wheel zoom |
| Components | continuous/piecewise visualMap, toolbox restore/dataView/saveAsImage, timeline controls |
| Live behavior | timer ticks, append/update, animation entrance/action/midpoint, custom DOM controls |

Use stable `dataName` when an earlier action can filter, rebuild, sort, or reindex data. A target obscured by another hit region remains a recorded coverage gap.

## 3. Generate and review scenarios

```sh
"$BIN" --interaction-generate-category <category> build/<category>-interaction-scenarios
```

Read both the generated JSON and `manifest.json`. Inspect `coverageNotes`; the generated `review-request.json` does not replace that check. Promote demo-specific behavior into `Tests/VisualInteractionScenarios/<demo>-interactions.json`.

Close a coverage note only by changing the generator so the note disappears for an auditable reason: the generated scenario now covers the behavior, or deterministic repository evidence proves it is not user-reachable/applicable. Adding a durable scenario while leaving the note intact does not close it. The repository currently has no structured `resolvedBy`/verified-not-applicable disposition, so a remaining note keeps the demo/category incomplete; never delete or subjectively ignore it merely to obtain a pass.

Category generation only covers official categories and uses model heuristics. A non-official demo needs a durable scenario directly. A graphic-only or callback-driven demo can produce only a baseline with empty `coverageNotes`; independently inspect keyframe midpoints, loops, timers, DOM/app controls and custom handlers instead of treating that baseline as coverage.

Do not infer durable coverage from filename suffixes. Enumerate every JSON whose decoded `demo` equals the target; one demo may have separate interaction, hover-cleanup, rapid-input or other scenarios:

```sh
jq -r 'select(.demo == "<demo>") | input_filename' \
  Tests/VisualInteractionScenarios/*.json
```

Capture and gate every returned scenario with a fresh output root. Also inspect every applicable official gallery category/manifest where the demo is cross-listed; one category sweep does not imply that another category's generated interaction family ran.

A durable scenario follows this shape:

```json
{
  "id": "official-example-interactions",
  "demo": "official-example",
  "checks": [
    "The interaction changes the same semantic target in Native and Web.",
    "The restored frame recovers all labels, symbols, overlays and normal states."
  ],
  "steps": [
    {"action": "settle", "capture": "baseline"},
    {"action": "hoverData", "seriesIndex": 0, "dataName": "stable-name"},
    {"action": "settle", "capture": "hovered"},
    {"action": "pointerMove", "x": 1, "y": 1},
    {"action": "globalOut"},
    {"action": "wait", "milliseconds": 700},
    {"action": "settle", "capture": "restored"}
  ]
}
```

For toggles and navigation, perform the real inverse UI action before the restored capture: click the legend again, click the breadcrumb, clear the brush, page back, or apply the inverse pan/zoom. End multi-interaction scenarios with a final cleanup/restoration capture to expose leaked state.

The authoritative action list is the Native and Web action switches in `Sources/EChartsDemoGallery/InteractionVisual.swift`. Current actions include:

```text
settle snapshot wait pointerMove globalOut wheelAt
clickLegend clickLegendPage clickVisibleLegendItem
hoverData hoverSeries clickData
clickTreemapBreadcrumbRoot clickTreemapDrillDownNode
clickToolbox editDataView saveToolboxImage
dragDataZoom dragGraphic dragAxisPointer dragTimeline dragBrush
dragGeoRoam wheelGeoRoam dragSeriesRoam wheelSeriesRoam
hoverGeoRegion dragVisualMap clickVisualMapPiece
driveTick driveAfterTick
```

Do not rely on an older documentation list when the switches differ.

### Animation and live-update coverage

Do not use ordinary interaction `snapshot` to compare animation phases: Native and Web start separately, and `settle` may fast-forward the animation. Derive offsets from the authored delay, duration, keyframe percentages and loop period. Include the start, immediately before/at/after every semantic keyframe, the endpoint, and at least one complete loop when `loop` is enabled. Sample Native/Web at those identical logical times with the wrapper that also creates contact sheets and TSV reports:

```sh
python3 -c 'from PIL import Image'
DEMO_CAPTURE_BINARY="$BIN" \
scripts/capture-demo-screenshots.sh \
  --renderers native,web \
  --cases <demo> \
  --times <derived-offsets-ms> \
  --output build/<demo>-animation-run-1 \
  --force
test -s build/<demo>-animation-run-1/<demo>/contacts/entrance-page-001.png
test -s build/<demo>-animation-run-1/<demo>/report/native-vs-web.tsv
```

Pillow is a hard dependency for animation visual evidence. The wrapper only warns and still exits zero when Pillow is absent, so a failed import or missing contact/TSV is `blocked`/`unrun`, never a pass.

Independently validate the original frame pairs for every requested offset; reports silently omit missing pairs. With `CHART_RUN_ROOT` set to the demo case root (the directory containing `frames/`) and `CHART_OFFSETS_MS` set to the exact CSV passed to capture, run:

```sh
for offset in ${(s:,:)CHART_OFFSETS_MS}; do
  printf -v tag '%04d' "$offset"
  for side in native web; do
    matches=("$CHART_RUN_ROOT/frames/$side"/*.t"$tag"."$side".png(N))
    (( ${#matches} == 1 )) || exit 1
    test -s "$matches[1]" || exit 1
    python3 -c 'from PIL import Image; import sys; Image.open(sys.argv[1]).verify()' \
      "$matches[1]" || exit 1
  done
done
```

Any missing, duplicate, empty or unreadable pair is a failed/unrun capture even when the wrapper or report exits zero.

An action animation still needs an interaction scenario first to prove real Handler hit, state change and same-instance restoration. `capture-demo-screenshots.sh --action <actionJSON>` is supplemental phase evidence for an already verified action; its frozen action seam and fresh chart per timestamp cannot replace the interaction scenario.

For deterministic timer/update demos, prefer interaction scenarios using `driveTick` and `driveAfterTick`. When a live loop cannot be logically driven, capture matching derived offsets into one fresh run, then explicitly build the visual artifacts that the raw `--anim-*` commands do not create:

```sh
RUN=build/<demo>-live-animation-run-1
mkdir -p "$RUN/frames/native" "$RUN/frames/web" "$RUN/contacts"
"$BIN" --anim-native <demo> "$RUN/frames/native" <derived-offsets-ms>
"$BIN" --anim-web    <demo> "$RUN/frames/web"    <derived-offsets-ms>
CHART_RUN_ROOT="$RUN" CHART_OFFSETS_MS=<derived-offsets-ms>
# Run the paired-frame gate above before generating the report.
python3 scripts/entrance-visual-report.py "$RUN/frames" \
  --platforms native,web \
  --native-platform native --web-platform web \
  --contacts "$RUN/contacts" --tsv "$RUN/native-vs-web.tsv"
test -s "$RUN/contacts/entrance-page-001.png"
test -s "$RUN/native-vs-web.tsv"
```

Repeat with a different `RUN` root to expose startup/timing instability. Do not claim exact phase parity from a single wall-clock capture.

## 4. Capture deterministic evidence

```sh
DEMO_CAPTURE_BINARY="$BIN" \
scripts/capture-interaction-visuals.sh \
Tests/VisualInteractionScenarios/<scenario>.json \
build/<demo>-interaction-run-1
```

For a whole category:

```sh
DEMO_CAPTURE_BINARY="$BIN" \
scripts/capture-category-interaction-visuals.sh \
<category> \
build/<category>-interaction-scenarios \
build/<category>-interaction-visuals
```

Before visual review, require:

- exit status zero and exactly one Native/Web PNG per named capture
- non-empty, readable PNGs and a generated contact sheet
- no `allowMissing` in the scenario and no `missingTarget` in either resolved JSON
- both sides resolved the same semantic component/series/datum
- the requested interaction produced a meaningful state change
- inverse action/restoration returned to the authored semantics
- a second run is deterministic enough to review

Use a new output root for every run. The capture script replaces frame PNGs but a mid-run failure can otherwise leave older resolved/contact/review files behind. The category script's `passed` count means only that capture commands exited successfully; it is not a resolved, coverage, or visual verdict. It also does not execute durable scenarios under `Tests/VisualInteractionScenarios/`.

Compare resolved records by scenario step index and action, not by whole-file JSON equality or raw coordinates. Native action evidence is commonly stored on the record itself; Web action evidence is commonly nested under `record.result`, and supported semantic fields differ by action. Normalize those shapes, then compare stable names, component/series/data identity, state/range changes, callback results and restoration evidence. Coordinates only need to hit the intended target within each renderer's bounds.

Native evidence must come from the live `view.zr.storage` display list so tooltips, axisPointer elements and other host-owned overlays remain visible.

## 5. Dispatch visual-recognition child agents

Do not use Computer Use. The main agent must inspect `coverageNotes` and both resolved JSON files first because an interaction `review-request.json` contains neither. Give each child that request, its contact sheet and original absolute PNG paths.

The screenshot wrapper creates animation contact sheets and TSV reports but no `review-request.json`; the raw `--anim-*` fallback creates only frames until `entrance-visual-report.py` is run as shown above. For an animation family, create an equivalent temporary review brief under `build/` containing the demo, authored duration/keyframe/loop semantics, derived offsets, contact paths and all original Native/Web PNG paths. Absence of an auto-generated request is not permission to skip visual review.

Use a prompt shaped like this:

```text
Independently review this Native/Web chart interaction evidence. First inspect the contact sheet, then open every original PNG needed to verify small labels, markers and transient overlays. Apply the semantic checks in review-request.json. Do not infer behavior from filenames or code and do not assume a proposed fix is correct.

Return:
- status: pass | fail | uncertain
- failing capture labels
- Native/Web semantic difference
- stale or missing labels, symbols, guide lines, tooltip, axisPointer, emphasis/blur or clipping
- absolute evidence image paths
- confidence and concise notes
```

For large cases, split review into independent families such as hover/cleanup, legend/selection, roam/zoom, toolbox/timeline and dynamic/animation. The main agent aggregates with an AND rule: every family must pass. Do not use majority voting. Open original PNGs whenever a contact-sheet detail is ambiguous.

Compare all four relationships:

1. Native interaction state versus Web interaction state.
2. Native restored state versus Native baseline.
3. Web restored state versus Web baseline.
4. Final restored state versus every earlier transient state that could leak.

Ignore font antialiasing and harmless subpixel geometry. Fail semantic omissions, wrong targets, persistent tooltip/axisPointer, stale emphasis/blur, lost labels/markers, wrong z-order, clipping, or mismatched restoration.

## 6. Fix and regress

For each failure:

1. Identify whether the gap is demo parity, event routing, model/action state, view update, animation lifecycle, z-order/painter, or harness coverage.
2. Add the narrowest deterministic regression before changing behavior.
3. Make the smallest upstream-faithful fix.
4. Rerun the failing scenario and its visual child review.
5. Re-enumerate `Tests/VisualInteractionScenarios/*.json` by decoded `demo` and rerun every returned scenario with a fresh output root; do not assume a filename suffix.
6. Rerun the applicable official category sweep and relevant unit/scene tests. Skip this step for non-official demos rather than inventing an unrelated category.
7. Run `swift test`, `git diff --check`, and a final independent visual review before completion.

An environment failure is `blocked` or `unrun`, never `pass`.

## 7. Commit and push boundaries

Do not add `build/` screenshots, contact sheets, generated manifests or review requests. Before committing or pushing, show:

```sh
git status --short --branch
git diff --check
git log --oneline origin/main..HEAD
git diff --stat origin/main..HEAD
```

Commit durable scenarios, focused tests, Skill changes, demo changes and minimal engine fixes. Push only when the user has authorized the target branch and the outgoing commit set. After pushing, read the remote ref and verify it equals the intended commit.
