// gallery-batch2 — a second batch of demos derived from canonical echarts `test/` scenarios (goal clause 2:
// "在demo中实现echart test中所有用例"). Each is option-expressible (no JS closures) and exercises a ported
// feature combination not yet covered by batch 1; verified via `swift run EChartsDemoGallery --render-all`.
extension EChartsDemoRegistry {

    // --- bar: three grouped series + legend (echarts test/ bar multi-series) ---
    static let demo_bar_multi3 = EChartsDemo(
        name: "bar-multi3", category: "Bar",
        summary: "three grouped bar series with a legend",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Q1","Q2","Q3","Q4"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "A", "type": "bar", "data": [12.0, 18, 14, 22]] as [String: Any],
                ["name": "B", "type": "bar", "data": [9.0, 15, 20, 11]] as [String: Any],
                ["name": "C", "type": "bar", "data": [6.0, 8, 13, 17]] as [String: Any]
            ]
        ])

    // --- line: a dashed line paired with a solid one (lineStyle.type) ---
    static let demo_line_dashed = EChartsDemo(
        name: "line-dashed", category: "Line",
        summary: "two line series, one solid one dashed (lineStyle.type)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "actual", "type": "line", "data": [12.0,18,15,22,19,26]] as [String: Any],
                ["name": "target", "type": "line",
                 "lineStyle": ["type": "dashed"] as [String: Any],
                 "data": [14.0,16,17,20,21,24]] as [String: Any]
            ]
        ])

    // --- scatter: a large single-series cloud (echarts test/ scatter large) ---
    static let demo_scatter_large = EChartsDemo(
        name: "scatter-large", category: "Scatter",
        summary: "an 80-point scatter cloud on a value/value grid",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 8.0, "data": scatterCloud80]] as [[String: Any]]
        ])

    // --- pie: labels + label lines (echarts test/ pie label) ---
    static let demo_pie_labeled = EChartsDemo(
        name: "pie-labeled", category: "Pie",
        summary: "pie with outside labels + label lines",
        width: 440, height: 320,
        option: [
            "series": [[
                "type": "pie", "radius": "60%",
                "label": ["show": true] as [String: Any],
                "data": [
                    ["value": 335.0, "name": "Direct"] as [String: Any],
                    ["value": 310.0, "name": "Email"] as [String: Any],
                    ["value": 234.0, "name": "Affiliate"] as [String: Any],
                    ["value": 135.0, "name": "Video"] as [String: Any],
                    ["value": 154.0, "name": "Search"] as [String: Any]
                ]
            ] as [String: Any]]
        ])

    // --- radar: three overlaid series (echarts test/ radar multiple) ---
    static let demo_radar_multi = EChartsDemo(
        name: "radar-multi", category: "Radar",
        summary: "three overlaid radar series",
        width: 440, height: 360,
        option: [
            "legend": ["top": 4.0] as [String: Any],
            "radar": ["indicator": [
                ["name": "Sales", "max": 100.0] as [String: Any],
                ["name": "Admin", "max": 100.0] as [String: Any],
                ["name": "Tech", "max": 100.0] as [String: Any],
                ["name": "Support", "max": 100.0] as [String: Any],
                ["name": "Dev", "max": 100.0] as [String: Any],
                ["name": "Market", "max": 100.0] as [String: Any]
            ]] as [String: Any],
            "series": [["type": "radar", "data": [
                ["value": [80.0,70,60,85,90,72], "name": "A"] as [String: Any],
                ["value": [60.0,82,74,63,55,88], "name": "B"] as [String: Any],
                ["value": [45.0,50,92,70,66,58], "name": "C"] as [String: Any]
            ]]] as [[String: Any]]
        ])

    // --- line: five series (echarts test/ line multi) ---
    static let demo_line_multi5 = EChartsDemo(
        name: "line-multi5", category: "Line",
        summary: "five line series sharing one grid",
        width: 500, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 420.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "s1", "type": "line", "data": [12.0,14,11,17,15,19,22]] as [String: Any],
                ["name": "s2", "type": "line", "data": [8.0,9,13,10,14,12,16]] as [String: Any],
                ["name": "s3", "type": "line", "data": [5.0,7,6,9,11,8,13]] as [String: Any],
                ["name": "s4", "type": "line", "data": [18.0,16,20,15,19,23,21]] as [String: Any],
                ["name": "s5", "type": "line", "data": [3.0,5,4,7,6,9,8]] as [String: Any]
            ]
        ])

    // --- bar + line on the same grid (echarts test/ mix bar-line) ---
    static let demo_mix_bar_line = EChartsDemo(
        name: "mix-bar-line", category: "Bar",
        summary: "a bar series and a line series sharing one grid",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Jan","Feb","Mar","Apr","May","Jun"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "volume", "type": "bar", "data": [20.0,32,25,38,30,42]] as [String: Any],
                ["name": "trend", "type": "line", "data": [22.0,28,27,34,31,39]] as [String: Any]
            ]
        ])

    // --- area with a distinct filled envelope (echarts test/ line areaStyle) ---
    static let demo_area_two = EChartsDemo(
        name: "area-two", category: "Line",
        summary: "two overlaid area series (areaStyle)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false,
                      "data": ["A","B","C","D","E","F","G"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "hi", "type": "line", "areaStyle": [String: Any](),
                 "data": [30.0,42,35,50,45,60,55]] as [String: Any],
                ["name": "lo", "type": "line", "areaStyle": [String: Any](),
                 "data": [12.0,18,15,22,19,26,24]] as [String: Any]
            ]
        ])
}

// An 80-point deterministic scatter cloud (no RNG — a fixed lattice with a mild diagonal drift).
private let scatterCloud80: [[Double]] = {
    var pts: [[Double]] = []
    var i = 0
    for gx in 0..<10 {
        for gy in 0..<8 {
            let x = Double(gx) * 1.7 + Double((i * 7) % 5) * 0.3
            let y = Double(gy) * 2.1 + Double((i * 3) % 7) * 0.4 + Double(gx) * 0.5
            pts.append([x, y])
            i += 1
        }
    }
    return pts
}()
