import Foundation

// line-lttb — a 10,000-point cartesian line series with `sampling: "lttb"`. Exercises the
// processor/dataSample down-sampling: the series is reduced to roughly the base-axis pixel width
// while preserving the visual envelope (the global spike near x=5000 survives). Renders on BOTH the
// native (EChartsKit) and real echarts.js panes; PNG-comparable so the preserved line shape is visible.
extension EChartsDemoRegistry {
    // Deterministic wiggly signal with a sharp spike in the middle — the spike must survive lttb.
    private static func lttbData() -> [[Double]] {
        var data: [[Double]] = []
        data.reserveCapacity(10000)
        for i in 0..<10000 {
            let x = Double(i)
            let y = sin(x * 0.01) * 40 + cos(x * 0.043) * 18 + (i == 5000 ? 260.0 : 0.0)
            data.append([x, y])
        }
        return data
    }

    static let demo_line_lttb = EChartsDemo(
        name: "line-lttb", category: "Line",
        summary: "10k-point line down-sampled with sampling:\"lttb\" (envelope preserved)",
        width: 600, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "right": 20.0, "bottom": 30.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 10000.0] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "line",
                "sampling": "lttb",
                "showSymbol": false,
                "data": lttbData()
            ] as [String: Any]]
        ])
}
