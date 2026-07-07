// gallery-batch1 — a batch of demos derived from the canonical echarts `test/` scenarios (goal clause 2:
// "在demo中实现echart test中所有用例"). Each is an option-expressible test case (no JS closures) that
// exercises a ported feature; verified via `swift run EChartsDemoGallery --render-all` (0 failed).
extension EChartsDemoRegistry {

    // --- bar variants (echarts test/ bar-stack, bar-negative, bar horizontal, multi-series) ---
    static let demo_bar_stack = EChartsDemo(
        name: "bar-stack", category: "Bar",
        summary: "two stacked bar series (stack:'total')",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon","Tue","Wed","Thu","Fri"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "A", "type": "bar", "stack": "total", "data": [10.0,22,28,13,27]] as [String: Any],
                ["name": "B", "type": "bar", "stack": "total", "data": [15.0,18,9,24,12]] as [String: Any]
            ]
        ])

    static let demo_bar_negative = EChartsDemo(
        name: "bar-negative", category: "Bar",
        summary: "bar series with negative values crossing the zero axis",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [20.0, -15, 30, -8, 12, -25]] as [String: Any]]
        ])

    static let demo_bar_horizontal = EChartsDemo(
        name: "bar-horizontal", category: "Bar",
        summary: "horizontal bars (yAxis category, xAxis value)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 60.0, "top": 20.0, "width": 370.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["Alpha","Beta","Gamma","Delta"]] as [String: Any],
            "series": [["type": "bar", "data": [18.0, 32, 25, 11]] as [String: Any]]
        ])

    // --- line variants (echarts test/ line-area, line-smooth, line-stack, multi-series) ---
    static let demo_line_area = EChartsDemo(
        name: "line-area", category: "Line",
        summary: "single line with areaStyle (filled area chart)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false, "data": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "areaStyle": [String: Any](), "data": [120.0,132,101,134,90,230,210]] as [String: Any]]
        ])

    static let demo_line_smooth = EChartsDemo(
        name: "line-smooth", category: "Line",
        summary: "smooth line + two series",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "s1", "type": "line", "smooth": true, "data": [12.0,18,15,22,19,26]] as [String: Any],
                ["name": "s2", "type": "line", "smooth": true, "data": [8.0,11,14,9,16,13]] as [String: Any]
            ]
        ])

    static let demo_line_stack = EChartsDemo(
        name: "line-stack", category: "Line",
        summary: "three stacked area lines (stack + areaStyle)",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false, "data": ["Mon","Tue","Wed","Thu","Fri"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "a", "type": "line", "stack": "x", "areaStyle": [String: Any](), "data": [10.0,12,14,11,13]] as [String: Any],
                ["name": "b", "type": "line", "stack": "x", "areaStyle": [String: Any](), "data": [8.0,9,7,10,6]] as [String: Any],
                ["name": "c", "type": "line", "stack": "x", "areaStyle": [String: Any](), "data": [5.0,4,6,3,7]] as [String: Any]
            ]
        ])

    // --- pie variants (echarts test/ pie-doughnut, pie-rose) ---
    static let demo_pie_doughnut = EChartsDemo(
        name: "pie-doughnut", category: "Pie",
        summary: "doughnut pie (radius: ['40%','70%'])",
        width: 400, height: 320,
        option: [
            "legend": ["top": 4.0] as [String: Any],
            "series": [[
                "type": "pie", "radius": ["40%", "70%"],
                "data": [
                    ["value": 40.0, "name": "A"] as [String: Any],
                    ["value": 30.0, "name": "B"] as [String: Any],
                    ["value": 20.0, "name": "C"] as [String: Any],
                    ["value": 10.0, "name": "D"] as [String: Any]
                ]
            ] as [String: Any]]
        ])

    static let demo_pie_rose = EChartsDemo(
        name: "pie-rose", category: "Pie",
        summary: "nightingale rose pie (roseType: 'area')",
        width: 400, height: 320,
        option: [
            "series": [[
                "type": "pie", "radius": ["20%", "72%"], "roseType": "area",
                "data": [
                    ["value": 10.0, "name": "one"] as [String: Any],
                    ["value": 22.0, "name": "two"] as [String: Any],
                    ["value": 28.0, "name": "three"] as [String: Any],
                    ["value": 18.0, "name": "four"] as [String: Any],
                    ["value": 34.0, "name": "five"] as [String: Any]
                ]
            ] as [String: Any]]
        ])

    // --- scatter (echarts test/ scatter multi-series) ---
    static let demo_scatter_multi = EChartsDemo(
        name: "scatter-multi", category: "Scatter",
        summary: "two scatter series on a value/value grid",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 380.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "p", "type": "scatter", "data": [[10.0,8.04],[8.0,6.95],[13.0,7.58],[9.0,8.81],[11.0,8.33]]] as [String: Any],
                ["name": "q", "type": "scatter", "data": [[10.0,7.46],[8.0,6.77],[13.0,12.74],[9.0,7.11],[11.0,7.81]]] as [String: Any]
            ]
        ])

    // --- interactive: a cartesian chart with a slider dataZoom + axis tooltip (exercises Phases 32/35/41) ---
    static let demo_bar_datazoom_slider = EChartsDemo(
        name: "bar-datazoom-slider", category: "DataZoom",
        summary: "bar chart with a bottom slider dataZoom + axis tooltip",
        width: 480, height: 340,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 400.0, "height": 230.0] as [String: Any],
            "tooltip": ["trigger": "axis"] as [String: Any],
            "xAxis": ["type": "category", "data": ["a","b","c","d","e","f","g","h","i","j","k","l"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "dataZoom": [["type": "slider", "start": 10.0, "end": 70.0] as [String: Any]],
            "series": [["type": "bar", "data": [5.0,9,7,12,6,14,8,11,4,10,13,7]] as [String: Any]]
        ])
}
