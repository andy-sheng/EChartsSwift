# Vendored: mindbrix/Rasterizer

Vendored copy of the `Package/` SwiftPM package from
https://github.com/mindbrix/Rasterizer at commit `7058139eeab11b4054c31eca97aa6d1f2d1cb90c`
(2026-05-02). Only the SwiftPM package is vendored (the demo apps and the pdfium
xcframework are not). Upstream's `Package.swift` cannot be consumed directly by SPM
because it lives in a repo subdirectory, hence the local copy.

License: personal-use zlib license (see LICENSE.txt). Commercial use requires a
licence from the author (nigel@mindbrix.co.uk).

## Local modifications (license clause 2: altered source, plainly marked)

- `Sources/RasterizerObjC/include/RARenderHost.h` + `Sources/RasterizerObjC/RARenderHost.mm`
  (ADDED, not upstream): a push-model host that wraps the private `RasterizerLayer`
  (CAMetalLayer) so an external frame clock can drive rendering — the upstream
  `RasterizerView` owns its own CVDisplayLink/CADisplayLink pull loop, which double-clocks
  against ZRenderKit's `AnimationLoop`. Also exposes the `RasterizerCG` CPU reference
  render for headless verification.

Everything else is byte-identical to upstream.
