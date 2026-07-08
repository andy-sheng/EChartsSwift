// Ported from echarts/theme/vintage.js — keep in sync with upstream.
//
// The built-in "vintage" theme (a widely-used ECharts extension theme). Upstream ships it as a
// UMD module whose factory calls `echarts.registerTheme('vintage', { color, backgroundColor, graph })`.
// The Swift port exposes the same nested `[String: Any]` tree via `vintageTheme.theme`, registered by
// name in `EChartsSlim.installOnce()` (mirroring the upstream `registerTheme('vintage', ...)` call).
//
// upstream: var colorPalette = [ ... ]; echarts.registerTheme('vintage', { ... });

// upstream: var colorPalette = [ '#d87c7c', '#919e8b', ... ];
private let colorPalette: [String] = [
    "#d87c7c",
    "#919e8b",
    "#d7ab82",
    "#6e7074",
    "#61a0a8",
    "#efa18d",
    "#787464",
    "#cc7e63",
    "#724e58",
    "#4b565b"
]

public enum vintageTheme {
    // upstream: echarts.registerTheme('vintage', { color, backgroundColor, graph: { color } });
    public static let theme: [String: Any] = [
        "color": colorPalette,
        "backgroundColor": "#fef8ef",
        "graph": [
            "color": colorPalette
        ]
    ]
}
