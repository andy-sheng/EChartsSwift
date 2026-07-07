// gallery-batch4 — a fourth batch of demos from canonical echarts `test/` scenarios (goal clause 2).
// Focus: component + coordinate-system scenarios (dataZoom, tooltip, visualMap, polar, dataset, calendar).
// Verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    // ---- dataZoom: inside (wheel/drag) on a line ----
    static let demo_datazoom_inside = EChartsDemo(
        name: "datazoom-inside", category: "DataZoom",
        summary: "line with an inside dataZoom window",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 400.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<24).map { "t\($0)" }] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "dataZoom": [["type": "inside", "start": 20.0, "end": 70.0] as [String: Any]],
            "series": [["type": "line", "data": (0..<24).map { Double(($0 * 17 + 5) % 40 + 5) }] as [String: Any]]
        ])

    // ---- tooltip: trigger axis on a multi-series line ----
    static let demo_tooltip_axis = EChartsDemo(
        name: "tooltip-axis", category: "Component",
        summary: "multi-line with tooltip trigger:'axis'",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "tooltip": ["trigger": "axis"] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["name": "u", "type": "line", "data": [12.0,18,15,22,19,26]] as [String: Any],
                ["name": "v", "type": "line", "data": [8.0,11,14,9,16,13]] as [String: Any]
            ]
        ])

    // ---- visualMap: piecewise on a scatter ----
    static let demo_visualmap_piecewise = EChartsDemo(
        name: "visualmap-piecewise", category: "VisualMap",
        summary: "scatter colored by a piecewise visualMap",
        width: 480, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 220.0] as [String: Any],
            "visualMap": ["type": "piecewise", "min": 0.0, "max": 30.0, "splitNumber": 3,
                          "dimension": 1, "orient": "horizontal", "left": "center", "bottom": 0.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter", "symbolSize": 14.0,
                        "data": [[5.0,4],[10.0,12],[15.0,20],[20.0,8],[25.0,28],[8.0,16]]] as [String: Any]]
        ])

    // ---- calendar: a heatmap over a calendar range ----
    static let demo_calendar_heatmap = EChartsDemo(
        name: "calendar-heatmap", category: "Calendar",
        summary: "heatmap cells over a one-month calendar",
        width: 520, height: 260,
        option: [
            "visualMap": ["min": 0.0, "max": 10.0, "orient": "horizontal",
                          "left": "center", "top": 0.0] as [String: Any],
            "calendar": ["range": "2017-02", "left": 40.0, "top": 50.0,
                         "cellSize": [30.0, 30.0]] as [String: Any],
            "series": [["type": "heatmap", "coordinateSystem": "calendar", "data": (1...28).map { d -> [Any] in
                let day = String(format: "2017-02-%02d", d)
                return [day, Double((d * 3) % 11)]
            }] as [String: Any]]
        ])

    // ---- polar: a line on a polar coordinate ----
    static let demo_polar_line = EChartsDemo(
        name: "polar-line", category: "Polar",
        summary: "a line series on polar coordinates",
        width: 380, height: 360,
        option: [
            "polar": [String: Any](),
            "angleAxis": ["type": "category", "data": ["a","b","c","d","e","f","g","h"]] as [String: Any],
            "radiusAxis": [String: Any](),
            "series": [["type": "line", "coordinateSystem": "polar",
                        "data": [5.0,8,6,10,7,12,9,11]] as [String: Any]]
        ])

    // ---- dataset: a bar driven by a dataset source ----
    static let demo_dataset_bar = EChartsDemo(
        name: "dataset-bar", category: "Dataset",
        summary: "bar built from a dataset source + encode",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "dataset": ["source": [
                ["product", "count"],
                ["Matcha", 43.0], ["Milk", 83.0], ["Cheese", 86.0], ["Walnut", 72.0], ["Cocoa", 55.0]
            ]] as [String: Any],
            "xAxis": ["type": "category"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar"] as [String: Any]]
        ])

    // ---- lines: a few great-circle-ish segments on a plain grid ----
    static let demo_lines_grid = EChartsDemo(
        name: "lines-grid", category: "Lines",
        summary: "lines series (coord segments) on a value grid",
        width: 460, height: 300,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "width": 400.0, "height": 250.0] as [String: Any],
            "xAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "yAxis": ["type": "value", "min": 0.0, "max": 100.0] as [String: Any],
            "series": [["type": "lines", "coordinateSystem": "cartesian2d",
                        "data": [
                            ["coords": [[10.0,10],[80.0,40]]] as [String: Any],
                            ["coords": [[20.0,60],[70.0,90]]] as [String: Any],
                            ["coords": [[15.0,85],[90.0,20]]] as [String: Any]
                        ]] as [String: Any]]
        ])

    // ---- effectScatter: highlighted points ----
    static let demo_effectscatter_grid = EChartsDemo(
        name: "effectscatter-grid", category: "EffectScatter",
        summary: "effectScatter on a value grid",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "effectScatter", "symbolSize": 16.0,
                        "data": [[10.0,12],[18.0,20],[26.0,9],[14.0,25]]] as [String: Any]]
        ])

    // ---- pie: two concentric rings ----
    static let demo_pie_nest = EChartsDemo(
        name: "pie-nest", category: "Pie",
        summary: "two concentric pie rings",
        width: 420, height: 340,
        option: [
            "series": [
                ["type": "pie", "radius": [0.0, "30%"], "label": ["position": "inner"] as [String: Any],
                 "data": [
                    ["value": 40.0, "name": "A"] as [String: Any],
                    ["value": 60.0, "name": "B"] as [String: Any]
                 ]] as [String: Any],
                ["type": "pie", "radius": ["45%", "70%"],
                 "data": [
                    ["value": 20.0, "name": "A1"] as [String: Any],
                    ["value": 20.0, "name": "A2"] as [String: Any],
                    ["value": 30.0, "name": "B1"] as [String: Any],
                    ["value": 30.0, "name": "B2"] as [String: Any]
                 ]] as [String: Any]
            ]
        ])

    // ---- themeRiver: a stacked stream ----
    static let demo_themeriver_stream = EChartsDemo(
        name: "themeriver-stream", category: "ThemeRiver",
        summary: "a two-series themeRiver stream",
        width: 500, height: 300,
        option: [
            "singleAxis": ["type": "time", "top": 30.0, "bottom": 30.0] as [String: Any],
            "series": [["type": "themeRiver", "data": [
                ["2015/11/08", 10.0, "A"], ["2015/11/09", 15.0, "A"], ["2015/11/10", 12.0, "A"],
                ["2015/11/11", 18.0, "A"], ["2015/11/08", 8.0, "B"], ["2015/11/09", 11.0, "B"],
                ["2015/11/10", 14.0, "B"], ["2015/11/11", 9.0, "B"]
            ]] as [String: Any]]
        ])

    // ---- scatter driven by a dataset ----
    static let demo_dataset_scatter = EChartsDemo(
        name: "dataset-scatter", category: "Dataset",
        summary: "scatter built from a dataset source",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "dataset": ["source": [
                ["x", "y"], [10.0, 8.0], [15.0, 14.0], [8.0, 11.0], [20.0, 6.0], [13.0, 17.0]
            ]] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "scatter"] as [String: Any]]
        ])

    // ---- bar with two y-axes (a value + a second value axis) ----
    static let demo_bar_two_yaxis = EChartsDemo(
        name: "bar-two-yaxis", category: "Bar",
        summary: "bar + line on two independent y-axes",
        width: 500, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Jan","Feb","Mar","Apr","May"]] as [String: Any],
            "yAxis": [
                ["type": "value", "name": "vol"] as [String: Any],
                ["type": "value", "name": "rate"] as [String: Any]
            ],
            "series": [
                ["name": "vol", "type": "bar", "data": [20.0,35,28,42,30]] as [String: Any],
                ["name": "rate", "type": "line", "yAxisIndex": 1, "data": [1.2,2.1,1.8,2.6,2.0]] as [String: Any]
            ]
        ])
}
