# Vendored: mindbrix/Rasterizer (script-synced, not committed)

`third_party/Rasterizer/` is the SwiftPM package backing the experimental Metal painter
(`Sources/RasterizerPainter`). Like the `upstream/` reference checkouts, it is
**gitignored and reconstructed by script** — run once after clone, before `swift build`
(the root `Package.swift` has a local path dependency on it):

```sh
scripts/sync-rasterizer.sh          # reconstruct from lock + patch
scripts/sync-rasterizer.sh --check  # verify against the lock + patch
```

What the script does:

1. Checks out https://github.com/mindbrix/Rasterizer at the commit pinned in
   `third_party/rasterizer.lock` (upstream's `Package.swift` lives in the repo's
   `Package/` subdirectory, which SPM cannot consume directly — hence the copy).
2. Copies `Package/` + `LICENSE.txt` into `third_party/Rasterizer/`.
3. Applies `third_party/rasterizer-local.patch` — our local modifications.

License: **personal-use zlib** (see the LICENSE.txt in the checkout). Commercial use
requires a licence from the author (nigel@mindbrix.co.uk).

## Local modifications (in `rasterizer-local.patch`; license clause 2 — altered
## source, plainly marked in-source)

- `Sources/RasterizerObjC/include/RARenderHost.h` + `Sources/RasterizerObjC/RARenderHost.mm`
  (ADDED): a push-model host that wraps the private `RasterizerLayer` (CAMetalLayer) so an
  external frame clock can drive rendering — the upstream `RasterizerView` owns its own
  CVDisplayLink/CADisplayLink pull loop, which double-clocks against ZRenderKit's
  `AnimationLoop`. Also exposes the `RasterizerCG` CPU reference render, a CPU-stage
  bench, and motion-blur/headless access (`setMotionBlurAlpha`, `displayNow`,
  `copyFeedbackFrame`). Uses a direct `_renderer` ivar — an ObjC property getter would
  return the C++ renderer BY COPY, whose refcounted pages release on destruction (SIGSEGV).
- `Sources/RasterizerCpp/include/Shaders.metal` (feedback shaders APPENDED) +
  `Sources/RasterizerObjC/private/RasterizerLayer.h` / `RasterizerLayer.mm` (MODIFIED):
  motion-blur feedback pass — a persistent shared-storage texture retains each presented
  frame; the next frame composites it at `feedbackAlpha` over the clear color before the
  scene renders, and the drawable is blitted back after (the Metal analog of zrender
  canvas/Layer.ts's back-buffer drawImage). Also `displayAndWait` (synchronous render for
  headless testing; `display` drops frames when both in-flight slots are busy) and
  `lastCommandBuffer` (readback synchronization).
- `RasterizerLayer.mm`: runtime shader-compile fallback — the `swift build` CLI copies
  `.metal` package resources verbatim without building `default.metallib` (Xcode's SPM
  integration does compile them); the fallback compiles the source at runtime, inlining
  the bundled `Rasterizer.h`.
- `Package.swift`: bundle `Rasterizer.h` as a resource for that fallback.

## Bumping the pinned commit

Edit `third_party/rasterizer.lock`, re-run `scripts/sync-rasterizer.sh`. If the patch no
longer applies, rebase it: stage a pristine `Package/` subtree in a temp git repo, overlay
the fixed sources, and regenerate with `git diff --cached --binary`.
