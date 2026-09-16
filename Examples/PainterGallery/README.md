# PainterGallery

This application package combines the core with the independent
`../../RasterizerPainter` repository. The core package has no dependency on it.

Rasterizer's engine lock, local patch, provenance notes, and reconstruction script belong to
that independent repository. The core builds and tests without the plugin or engine checkout;
this gallery opts into them. The root `scripts/sync-rasterizer.sh` forwards to the plugin's script.

From the EChartsSwift root:

```sh
scripts/sync-rasterizer.sh
swift run --package-path Examples/PainterGallery EChartsDemoGallery
swift run --package-path Examples/PainterGallery DemoGallery
```

The existing macOS gallery build and screenshot scripts resolve this package
automatically. Core tests remain `swift test` from the root. Plugin tests use
`swift test --package-path RasterizerPainter` and include real Metal readback.

`Sources/EChartsDemoGallery/EChartsHostView.swift` demonstrates the registered renderer
path with the gallery's existing pointer handling and animation clock.
