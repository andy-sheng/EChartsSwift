# Official line interaction visual audit

Final run: `build/line-interaction-visuals-final`

Method: same-instance Native/Web action sequences, live ZRender display-list screenshots, and
independent visual-agent review. Computer Use was not used.

Capture result: 40/40 succeeded. Visual verdict: 33 PASS, 4 FAIL, 3 UNCERTAIN.

| Demo | Verdict | Note |
| --- | --- | --- |
| official-area-basic | PASS | Hover has no visible response; cleanup is stable. |
| official-area-pieces | PASS | Hover has no visible response; cleanup is stable. |
| official-area-rainfall | UNCERTAIN | Legend target overlaps the slider in part of the sequence; final restore passes. |
| official-area-simple | UNCERTAIN | Native/Web hover resolver selected different dates; zoom and restore pass. |
| official-area-stack | PASS | Hover cleanup and all legend cycles pass. |
| official-area-stack-gradient | PASS | Hover cleanup and all legend cycles pass. |
| official-area-time-axis | PASS | Hover, zoom, cleanup and restore pass. |
| official-bump-chart | PASS | Series focus and cleanup pass. |
| official-confidence-band | PASS | Hover and cleanup pass. |
| official-data-transform-filter | PASS | Both series hover and cleanup pass. |
| official-dataset-link | PASS | Line hover updates the pie; all four linked legend cycles pass. |
| official-dynamic-data2 | PASS | Hover and cleanup pass. |
| official-grid-multiple | UNCERTAIN | Legend/slider hit regions interfere; hover, zoom and final restore pass. |
| official-intraday-breaks-1 | PASS | Hover passes; dataZoom movement coverage is weak. |
| official-intraday-breaks-2 | PASS | Hover passes; dataZoom movement coverage is weak. |
| official-line-aqi | PASS | Hover and restored initial dataZoom window pass. |
| official-line-draggable | PASS | Graphic drag updates point, line and tooltip coordinates. |
| official-line-easing | PASS | No visible hover response; cleanup is stable. |
| official-line-fisheye-lens | PASS | Hover and legend cycle pass; brush/fisheye gesture remains uncovered. |
| official-line-function | PASS | No visible hover response; cleanup is stable. |
| official-line-gradient | PASS | Both grids hover and clean up correctly. |
| official-line-graphic | PASS | Hover passes; graphic click/drag remains uncovered. |
| official-line-in-cartesian-coordinate-system | PASS | No visible hover response; cleanup is stable. |
| official-line-log | PASS | Three hovers and three legend cycles pass. |
| official-line-marker | FAIL | Native series hover does not lift the related horizontal markLine like Web. |
| official-line-markline | PASS | No visible hover response; cleanup is stable. |
| official-line-pen | PASS | Hover passes; click-to-add-point remains uncovered. |
| official-line-polar | FAIL | Native hover lacks polar tooltip and polar axisPointer. |
| official-line-polar2 | FAIL | Native hover lacks polar tooltip and polar axisPointer. |
| official-line-race | PASS | Three series-focus hovers and cleanup pass. |
| official-line-sections | PASS | Tooltip, crosshair and cleanup pass. |
| official-line-simple | PASS | No visible hover response; cleanup is stable. |
| official-line-smooth | PASS | No visible hover response; cleanup is stable. |
| official-line-stack | PASS | Three hovers and five legend cycles pass. |
| official-line-step | PASS | Three hovers and three legend cycles pass. |
| official-line-style | PASS | No visible hover response; cleanup is stable. |
| official-line-tooltip-touch | PASS | Persistent handle and dragged combined tooltip pass. |
| official-line-y-category | PASS | Horizontal pointer, tooltip, legend cycle and cleanup pass. |
| official-matrix-sparkline | FAIL | Test-infrastructure failure: generated dataZoom drag is a no-op on both panes. |
| official-multiple-x-axis | PASS | Crosshair, both axis labels, data values, emphasis and legend cycles pass. |

## Product issues still open

- `official-line-marker`: marker/markLine series-hover state propagation differs from Web.
- `official-line-polar` and `official-line-polar2`: polar tooltip and polar axisPointer rendering are
  not implemented in the Native interaction host.

## Harness work still open

- Resolve legend targets that overlap slider dataZoom controls without moving the chart state.
- Make hover target selection choose the same semantic datum on Native and Web time-series charts.
- Add intended-interaction overrides for click-to-add, graphic click/drag, fisheye/brush, and slider
  cases where the generated drag does not visibly change the window.
