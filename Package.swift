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
        )
    ]
)
