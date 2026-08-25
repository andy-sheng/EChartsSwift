---
name: testing-native-web-chart-interactions
description: Use when adding or changing an ECharts demo, synchronizing a Web example to Native, or diagnosing Native/Web differences after hover, click, legend, tooltip, drag, zoom, roam, drilldown, toolbox, timeline, animation, or pointer cleanup.
---

# Testing Native/Web Chart Interactions

## Overview

Test visible interaction semantics on the same live chart instance. Static screenshots and direct model actions cannot prove pointer routing, transient painter state, or cleanup behavior.

Read [references/workflow.md](references/workflow.md) before running or changing interaction tests.

## Non-negotiable rules

- Do not use Computer Use. Drive the repository's headless interaction harness and delegate pixel review to visual-recognition child agents.
- Compare Native with the pinned local real ECharts Web renderer, not memory or a network page.
- Discover behavior from the upstream Web source, Native demo definition, and runtime-generated manifest. Two silent/no-op renderers are not parity.
- Exercise real hit-tested Handler paths. Do not replace an unreachable legend, datum, slider, breadcrumb, or toolbox control with `dispatchAction` and call it covered.
- Keep one chart instance alive from baseline through interaction and restoration. Recreating the chart is not state restoration.
- Treat scenario `allowMissing`, resolved `missingTarget`, non-empty `coverageNotes`, missing image pairs, unstable reruns, and `uncertain` visual verdicts as incomplete coverage.
- Do not commit generated `build/` evidence. Commit durable scenarios, focused tests, demo/engine fixes, and Skill changes only.

## Required workflow

1. Inventory distinct interaction state machines and target equivalence classes. Include callbacks, timers, DOM controls, dynamic updates, hover/emphasis/blur, legends, selections, sliders, roam, toolbox, timeline, drilldown, and cleanup where present.
2. For official-category demos, generate the category scenario, inspect its manifest, and supplement gaps with a durable JSON scenario under `Tests/VisualInteractionScenarios/`. For non-official demos or behavior the generator cannot discover, write the durable scenario directly.
3. Capture paired Native/Web frames plus `resolved.native.json`, `resolved.web.json`, contact sheet, and `review-request.json` using the existing scripts.
4. Verify exits, paired captures, semantic target resolution, real state changes, inverse/restored state, and repeatability before visual review.
5. Dispatch independent visual child agents. Give them evidence and semantic checks, but no suspected root cause or proposed fix. Split large cases by interaction family.
6. Accept only unanimous `pass`. A child must name failing capture labels and absolute evidence paths; `uncertain` requires recapture or human review.
7. Fix the smallest root cause, add a focused regression, rerun the failed scenario, the demo's full scenarios, any applicable category sweep, relevant structural tests, and final visual review.

## Completion contract

Report separately: interactions discovered, scenarios executed, visual verdicts, fixes made, tests run, remaining gaps, and whether commits were pushed. Never describe an environment-blocked or unreviewed case as passed.
