# iOS-Chart Development Guide

## Project purpose

iOS-Chart is a SwiftPM port of Apache ECharts and ZRender for iOS 15+ and macOS 12+.
Most code under `Sources/EChartsKit` and `Sources/ZRenderKit` intentionally mirrors the
upstream TypeScript structure so changes can be compared and synchronized. Structural
fidelity takes priority over idiomatic Swift refactoring in translated code.

Before changing translated code, read `CONVENTIONS.md` and `PORTING.md`. They are the
binding translation rules for this repository and take precedence over this summary.

## Repository map

- `Sources/ZRenderKit`: faithful port of `upstream/zrender/src`.
- `Sources/EChartsKit`: faithful port of `upstream/echarts/src`.
- `Sources/NativePainter`: hand-written Core Graphics/Core Animation renderer.
- `Sources/RasterizerPainter`: experimental Metal renderer over Rasterizer.
- `Sources/EChartsDemoCore`: shared ECharts demo definitions.
- `Sources/DemoGallery`: macOS ZRender demo gallery.
- `Sources/EChartsDemoGallery`: macOS ECharts comparison gallery.
- `Sources/EChartsDemoGalleryiOS`: iOS Simulator ECharts gallery.
- `Tests/ZRenderKitTests` and `Tests/EChartsKitTests`: unit, parity, and rendering tests.
- `Oracle`: ECharts/ZRender golden-fixture generator and committed fixtures.
- `upstream`: pinned, read-only ECharts and ZRender reference checkouts.
- `third_party`: lock, patch, and reconstruction metadata for Rasterizer.
- `scripts`: synchronization, build, and parity-check helpers.

## Non-negotiable porting rules

- Preserve upstream file names, identifier spelling, declaration order, and meaningful
  comments, including Chinese comments. Do not rename or reorganize translated code just
  to make it more idiomatic.
- Every translated Swift file starts with
  `// Ported from <upstream path> — keep in sync with upstream`.
- Mark omitted, uncertain, stubbed, or deferred behavior with a precise `// PORT-TODO:`.
  Never silently discard upstream behavior.
- Search before adding shared symbols. Reuse an existing port rather than introducing a
  duplicate helper, namespace, or type.
- Keep renderer-specific Core Graphics, Core Animation, and Metal code outside
  `ZRenderKit` and `EChartsKit`; translated code communicates through renderer seams.
- Follow the type and mutation mappings in `CONVENTIONS.md` and `PORTING.md`, especially
  `number` to `Double`, typed arrays to `ContiguousArray`, and value-returning math APIs
  instead of aliased `inout` output buffers.
- Keep changes focused. Do not mix upstream-parity work with unrelated cleanup or
  refactoring.

## Read-only and generated content

- Never edit `upstream/echarts` or `upstream/zrender`. Update `upstream/upstream.lock`, run
  `scripts/sync-upstream.sh`, inspect the upstream diff, and then port the change.
- Do not hand-edit `third_party/Rasterizer`. Update its lock or patch and reconstruct it
  with `scripts/sync-rasterizer.sh`.
- Treat `.build`, `.swiftpm`, `build`, and `out` as local/generated artifacts.
- Golden fixtures in `Oracle/fixtures` are generated artifacts but are intentionally
  committed. Regenerate them through `Oracle/dump-displaylist.js`; do not fabricate them.

## Setup

The package has a local dependency on the reconstructed Rasterizer checkout. On a fresh
clone, prepare both pinned dependencies before building:

```bash
scripts/sync-upstream.sh
scripts/sync-rasterizer.sh
```

To verify existing checkouts without changing them:

```bash
scripts/sync-upstream.sh --check
scripts/sync-rasterizer.sh --check
```

## Build and test

Run commands from the repository root.

```bash
swift build
swift test
```

During development, run the narrowest relevant test first, then the complete suite before
finishing. SwiftPM test filters use XCTest case or method names:

```bash
swift test --filter <TestCaseOrMethod>
```

Useful demo commands:

```bash
swift run DemoGallery --list
swift run EChartsDemoGallery --list
scripts/build-demo-gallery.sh
scripts/build-echarts-gallery.sh
scripts/build-echarts-gallery-ios.sh
```

The demo build scripts default to Debug so incremental development builds only recompile
affected files. Pass `--release` for an optimized (`-O`) build that retains file-level incremental
compilation, or `--release-wmo` when maximum whole-module optimization is specifically needed.
Incremental and WMO Release builds use separate caches so switching modes does not trigger an
avoidable rebuild. The iOS gallery also uses an isolated `build/swiftpm-ios` scratch directory so
cross-compilation does not invalidate the macOS galleries' build cache.

## Recommended change workflow

1. Locate the Swift symbol and its exact TypeScript source named by the file header.
2. Read both files and search the repository for existing related symbols and tests.
3. Add or update a focused regression/parity test when behavior changes.
4. Port the smallest faithful upstream unit, preserving names and control-flow order.
5. Run the focused test, `swift test`, and any relevant golden or scene comparison.
6. Review the diff for accidental generated files, broad formatting changes, duplicated
   symbols, missing provenance headers, and unmarked gaps.

For rendering or parity changes, prefer the existing oracle and comparison tools over
visual guesswork. See `Oracle/README.md` and the scripts named `scene-*` for the available
workflows.

## Review checklist

- The change matches the pinned upstream behavior or clearly documents an intentional
  native-only deviation.
- Ported files retain provenance headers and structural fidelity.
- New gaps are marked with `PORT-TODO`; resolved gaps remove obsolete markers.
- No read-only checkout or generated build artifact is included.
- Focused verification and the full relevant test suite pass.
