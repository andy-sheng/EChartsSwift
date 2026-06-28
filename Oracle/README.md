# Oracle — the Golden Test harness

This directory is the **oracle** that makes a faithful ZRender/ECharts → Swift port
verifiable. It runs the *real* ECharts/ZRender (in headless SSR mode) and records, for a
set of input options, the exact geometry their `PathProxy` produces. The Swift port is
"correct" precisely when our ported `PathProxy` + shape `buildPath` reproduce these
recordings.

```
Oracle/
  dump-displaylist.js   # the generator: ECharts SSR → fixtures
  options/*.json        # inputs: minimal ECharts options, one per geometry case
  fixtures/*.json       # outputs: the golden recordings (generated; commit them)
  README.md             # this file
```

The Swift consumer lives at `Tests/ZRenderKitTests/GoldenTests.swift`.

---

## What a fixture captures

For each input option the generator:

1. inits ECharts with `renderer:'svg'`, `ssr:true`, fixed `200x150` canvas,
2. `setOption(option)` (animation forced off → deterministic, final display list),
3. walks `chart.getZr().storage.getDisplayList(true)` — the **sorted paint order**,
4. dumps per element `{ type, shape, style, transform, z, zlevel, z2 }`, and for every
   **Path** element the renderer-independent path math:

| field          | meaning |
|----------------|---------|
| `pathData`     | raw `PathProxy.data` — CMD codes interleaved with coords (`M=1,L=2,C=3,Q=4,A=5,Z=6,R=7`) |
| `pathDataOps`  | just the opcode sequence, e.g. `["M","A","L","A","Z"]` (readability) |
| `pathCommands` | `PathProxy.rebuildPath()` replayed into a recorder — the exact `moveTo/lineTo/bezierCurveTo/arc/...` stream the Swift `PathRebuilder` protocol must emit |
| `rebuiltD`     | a canonical, deterministic string form of `pathCommands` — the byte-for-byte golden string the Swift test asserts |

5. and the **real** SVG `<path d=...>` strings ECharts emitted (`svgPaths`, top-level),
   as an independent cross-check. (Primitives like circle/rect/line render as native SVG
   elements, so they won't appear in `svgPaths` — their geometry is still fully captured
   in `pathCommands`, which is the primary oracle.)

All floats are rounded to `precision` (6) decimal places for stable diffs.

> **`rebuiltD` is not SVG `d`.** Arcs are kept as arcs (token `ARC cx cy r start end acw`),
> not flattened to cubics, so the comparison stays 1:1 with `PathProxy` rather than with a
> renderer's arc approximation. `svgPaths` is the SVG-grammar cross-check.

---

## Running the dumper

```bash
cd Oracle
node dump-displaylist.js            # regenerate every fixture from options/*.json
node dump-displaylist.js sector     # just options/sector.json → fixtures/sector.json
node dump-displaylist.js path/to/opt.json myname   # arbitrary option file
```

### Getting ECharts (node_modules-free checkout supported)

The script resolves ECharts in this order:

1. `require('echarts')` — if installed normally;
2. `ECHARTS_DIST=/abs/path/to/echarts/dist/echarts.js` env var;
3. a hard-coded fallback to the clone this harness was authored against.

If none resolve it prints the fix and exits non-zero. The simplest durable setup:

```bash
cd Oracle && npm init -y && npm i echarts@6
```

The CommonJS UMD bundle (`dist/echarts.js`) runs under plain `node` — no jsdom/browser
needed; the SVG renderer and SSR path are bundled in. (We pin to the ECharts version
recorded in each fixture's `echartsVersion` field; bump deliberately and re-baseline.)

---

## How fixtures map to tests

`Tests/ZRenderKitTests/GoldenTests.swift` has two layers:

- **`testRebuiltDMatchesOracle()` — runs today.** For every Path element it drives a
  Swift `PathRebuilder` (`GoldenPathRebuilder`) with the fixture's `pathCommands` and
  asserts our canonical formatter reproduces `rebuiltD` exactly. This pins down the
  `PathRebuilder` surface **and** the JS↔Swift number-formatting contract *before* any
  geometry is ported. `testAllFixturesLoad()` checks the fixtures decode.

- **`testSwiftBuildPathMatchesOracle()` — the intended end state**, written out but
  compiled out behind `#if PORT_TODO_GOLDEN` because it references not-yet-ported types
  (`PathProxy`, `Sector`, …). It shows the real pattern: build the path the Swift way
  (`Sector.buildPath(proxy, shape)`), replay through `proxy.rebuildPath(rb, 1)`, then make
  the *identical* assertion `rb.dString == el.rebuiltD`.

### Number-format parity (load-bearing)

`GoldenPathRebuilder.fmt` in Swift **must** match `fmt()` in `dump-displaylist.js`: round
to 6 decimals, drop trailing zeros / trailing dot, normalise `-0 → 0`. Because every
recorded number is already rounded to 6 dp, `%.6f` + trim reproduces JS `String(n)` for
the magnitudes we deal with (coords ≪ 1e21, never ≪ 1e-6). If you change `precision`,
re-check both formatters.

---

## Adding a new fixture (as later phases land)

1. Drop a `options/<name>.json` — either a bare ECharts option, or
   `{ "description": "...", "option": { ... } }`. Prefer one shape per fixture (isolate the
   `buildPath` under test); use the `graphic` component or a minimal custom series so it
   hits `PathProxy`.
2. `node dump-displaylist.js <name>` → `fixtures/<name>.json`. Commit both files.
3. Add `<name>` to `GoldenTests.allFixtures`. `testRebuiltDMatchesOracle` now covers it.
4. When the matching Swift shape is ported, add a case to the (un-guarded) layer-2 test so
   the Swift `buildPath` itself — not just the replay — is checked against `rebuiltD`.

### Current fixtures (geometry foundation)

| fixture        | shape        | exercises |
|----------------|--------------|-----------|
| `rect`         | rounded Rect | per-corner radius arcs (`helper/roundRect`) |
| `circle`       | Circle       | single full-turn arc |
| `sector`       | ring Sector  | outer arc + reversed inner arc + joins + close (pie/sunburst core) |
| `arc`          | open Arc     | single non-closed arc |
| `bezier-curve` | cubic Bezier | `bezierCurveTo` branch (both control points) |
| `polygon`      | Polygon      | moveTo + lineTo* + close (`helper/poly`) |
| `combined`     | all of above | display-list ordering via explicit `z2` + per-shape math |
