// swift-tools-version:5.9
import PackageDescription

// iOS-Chart: a faithful, line-by-line port of Apache ECharts + ZRender (TypeScript)
// to Swift. The package is split so the *translated* zrender logic (ZRenderKit) is
// kept structurally identical to upstream for future re-syncing, while the actual
// pixel pushing lives in a separate, hand-written native renderer (NativePainter).
let package = Package(
    name: "iOS-Chart",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "ZRenderKit", targets: ["ZRenderKit"]),
        .library(name: "NativePainter", targets: ["NativePainter"]),
        .library(name: "EChartsKit", targets: ["EChartsKit"])
    ],
    targets: [
        // Faithful translation of zrender/src/** — keep in sync with upstream.
        .target(
            name: "ZRenderKit",
            path: "Sources/ZRenderKit"
        ),
        // Fresh native renderer (Core Graphics / Core Animation). NOT a translation.
        // Plugs into the renderer-seam protocols exported by ZRenderKit.
        .target(
            name: "NativePainter",
            dependencies: ["ZRenderKit"],
            path: "Sources/NativePainter"
        ),
        // Translation of echarts/src/** — placeholder for now.
        .target(
            name: "EChartsKit",
            dependencies: ["ZRenderKit"],
            path: "Sources/EChartsKit"
        ),
        .testTarget(
            name: "ZRenderKitTests",
            dependencies: ["ZRenderKit", "NativePainter"],
            path: "Tests/ZRenderKitTests"
        ),
        // Behavioral oracle: ported ECharts unit tests (scale/number) run against
        // the translated EChartsKit modules. The first oracle for the Phase-5a scale math.
        .testTarget(
            name: "EChartsKitTests",
            dependencies: ["EChartsKit", "ZRenderKit", "NativePainter"],
            path: "Tests/EChartsKitTests"
        ),
        // macOS demo gallery — the native equivalent of opening zrender's test/*.html in a
        // browser. A *consumer* of the public API only (no @testable); it renders the migrated
        // demo scenes via NativePainter. Does NOT modify the framework. Run on macOS:
        //   swift run DemoGallery               # GUI: sidebar of demos + live ZRenderView
        //   swift run DemoGallery --list        # list demo names
        //   swift run DemoGallery --render-all <dir>   # headless render every demo to PNG
        .executableTarget(
            name: "DemoGallery",
            dependencies: ["ZRenderKit", "NativePainter"],
            path: "Sources/DemoGallery"
        ),
        // Shared ECharts demo definitions (EChartsDemo value type + Demos/<name>.swift registry +
        // the echarts.js web-pane page builder) — consumed by BOTH the macOS and iOS galleries,
        // which SwiftPM forbids from sharing a source directory. Platform-independent (Foundation).
        .target(
            name: "EChartsDemoCore",
            dependencies: ["ZRenderKit", "EChartsKit"],
            path: "Sources/EChartsDemoCore"
        ),
        // macOS ECharts demo gallery — the echarts analog of DemoGallery. Renders each demo `option`
        // two ways side-by-side: NATIVE (EChartsKit → EChartsSlim → ZRenderKit → NativePainter) and
        // the REAL echarts.js (upstream/echarts/dist) in a WKWebView. A public-API consumer only.
        //   swift run EChartsDemoGallery                        # GUI: native | echarts.js panes
        //   swift run EChartsDemoGallery --list
        //   swift run EChartsDemoGallery --compare bar-basic <dir>   # native + web PNGs
        .executableTarget(
            name: "EChartsDemoGallery",
            dependencies: ["ZRenderKit", "NativePainter", "EChartsKit", "EChartsDemoCore"],
            path: "Sources/EChartsDemoGallery"
        ),
        // iOS ECharts demo gallery — the same gallery as a UIKit app (UISplitViewController: demo
        // list + native | echarts.js panes). Same demo registry via EChartsDemoCore. Built for the
        // iOS SIMULATOR and staged as a .app by scripts/build-echarts-gallery-ios.sh (the web pane
        // reads upstream/echarts/dist off the host filesystem, which only the simulator can).
        // Compiles to a stub `exit(1)` main on non-UIKit platforms so `swift build` stays green.
        .executableTarget(
            name: "EChartsDemoGalleryiOS",
            dependencies: ["ZRenderKit", "NativePainter", "EChartsKit", "EChartsDemoCore"],
            path: "Sources/EChartsDemoGalleryiOS"
        )
    ]
)
