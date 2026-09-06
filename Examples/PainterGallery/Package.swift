// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PainterGallery",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(name: "iOS-Chart", path: "../.."),
        .package(path: "../../RasterizerPainter")
    ],
    targets: [
        .executableTarget(name: "DemoGallery", dependencies: [
            .product(name: "ZRenderKit", package: "iOS-Chart"),
            .product(name: "NativePainter", package: "iOS-Chart"),
            .product(name: "RasterizerPainter", package: "RasterizerPainter")
        ]),
        .executableTarget(name: "EChartsDemoGallery", dependencies: [
            .product(name: "ZRenderKit", package: "iOS-Chart"),
            .product(name: "NativePainter", package: "iOS-Chart"),
            .product(name: "NativeRenderer", package: "iOS-Chart"),
            .product(name: "EChartsKit", package: "iOS-Chart"),
            .product(name: "EChartsDemoCore", package: "iOS-Chart"),
            .product(name: "RasterizerPainter", package: "RasterizerPainter"),
            .product(name: "RasterizerRenderer", package: "RasterizerPainter")
        ])
    ]
)
