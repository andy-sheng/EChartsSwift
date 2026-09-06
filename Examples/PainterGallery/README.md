# PainterGallery

This application package combines the core with the independent
`../../RasterizerPainter` repository. The core package has no dependency on it.

From the iOS-Chart root:

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
