import Foundation

// large-scatter — a cartesian scatter series with `large: true` and thousands of points. Instead of
// one Symbol group per point (SymbolDraw), the whole series is drawn as ONE LargeSymbolPath whose
// buildPath re-emits the symbol for every packed point (the large-mode fast path, LargeSymbolDraw).
// Renders on BOTH panes: native (LargeSymbolPath point cloud) and real echarts.js.
extension EChartsDemoRegistry {
    static let demo_large_scatter: EChartsDemo = {
        // A deterministic 2-cluster Gaussian-ish cloud (~4000 points) — well past the largeThreshold.
        var data: [[Double]] = []
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double {
            // xorshift64* → [0, 1)
            seed ^= seed >> 12; seed ^= seed << 25; seed ^= seed >> 27
            let x = seed &* 0x2545F4914F6CDD1D
            return Double(x >> 11) / Double(1 << 53)
        }
        func gauss() -> Double {
            // Box-Muller (one component).
            let u1 = Swift.max(rnd(), 1e-9)
            let u2 = rnd()
            return (-2.0 * log(u1)).squareRoot() * cos(2.0 * Double.pi * u2)
        }
        for _ in 0..<2000 {
            data.append([30 + gauss() * 8, 30 + gauss() * 8])
        }
        for _ in 0..<2000 {
            data.append([70 + gauss() * 10, 65 + gauss() * 10])
        }
        return EChartsDemo(
            name: "large-scatter", category: "Scatter",
            summary: "large:true scatter, ~4000 points drawn as one LargeSymbolPath",
            width: 480, height: 360,
            option: [
                "grid": ["left": 40.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
                "xAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
                "yAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
                "series": [[
                    "type": "scatter",
                    "large": true,
                    "largeThreshold": 100,
                    "symbolSize": 5.0,
                    "itemStyle": ["color": "#5470c6", "opacity": 0.6] as [String: Any],
                    "data": data
                ] as [String: Any]]
            ])
    }()
}
