// gallery-batch6 — a sixth batch of demos from canonical echarts `test/` scenarios (goal clause 2).
// Coordinate-system + visual variations. Verified via `--render-all` (0 failed).
extension EChartsDemoRegistry {

    static let demo_visualmap_continuous_bar = EChartsDemo(
        name: "visualmap-continuous-bar", category: "VisualMap",
        summary: "bar colored by a continuous visualMap (by y-value)",
        width: 480, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 220.0] as [String: Any],
            "visualMap": ["min": 0.0, "max": 30.0, "calculable": true,
                          "orient": "horizontal", "left": "center", "bottom": 0.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F","G"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [5.0,12,18,24,9,28,15]] as [String: Any]]
        ])

    static let demo_heatmap_small = EChartsDemo(
        name: "heatmap-small", category: "Heatmap",
        summary: "a compact 5×5 heatmap",
        width: 380, height: 320,
        option: [
            "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 220.0] as [String: Any],
            "xAxis": ["type": "category", "data": (0..<5).map { "x\($0)" }] as [String: Any],
            "yAxis": ["type": "category", "data": (0..<5).map { "y\($0)" }] as [String: Any],
            "visualMap": ["min": 0.0, "max": 8.0, "orient": "horizontal",
                          "left": "center", "bottom": 0.0] as [String: Any],
            "series": [["type": "heatmap", "data": {
                var d: [[Double]] = []
                for x in 0..<5 { for y in 0..<5 { d.append([Double(x), Double(y), Double((x * 2 + y * 3) % 9)]) } }
                return d
            }()] as [String: Any]]
        ])

    static let demo_geo_scatter = EChartsDemo(
        name: "geo-scatter", category: "Geo",
        summary: "scatter points over the toy geo backdrop",
        width: 460, height: 320,
        option: [
            "geo": ["map": "toy", "roam": false] as [String: Any],
            "series": [["type": "scatter", "coordinateSystem": "geo",
                        "symbolSize": 12.0,
                        "data": [[10.0, 20.0], [30.0, 15.0], [20.0, 35.0]]] as [String: Any]]
        ])

    static let demo_gauge_progress = EChartsDemo(
        name: "gauge-progress", category: "Gauge",
        summary: "gauge with a progress arc",
        width: 360, height: 340,
        option: [
            "series": [["type": "gauge",
                        "progress": ["show": true] as [String: Any],
                        "data": [["value": 74.0, "name": "load"] as [String: Any]]] as [String: Any]]
        ])

    static let demo_gauge_two = EChartsDemo(
        name: "gauge-two", category: "Gauge",
        summary: "two gauges side by side",
        width: 520, height: 320,
        option: [
            "series": [
                ["type": "gauge", "center": ["27%", "55%"], "radius": "60%",
                 "data": [["value": 40.0] as [String: Any]]] as [String: Any],
                ["type": "gauge", "center": ["73%", "55%"], "radius": "60%",
                 "data": [["value": 82.0] as [String: Any]]] as [String: Any]
            ]
        ])

    static let demo_line_area_gradient = EChartsDemo(
        name: "line-area-gradient", category: "Line",
        summary: "area line with a smooth curve",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "boundaryGap": false,
                      "data": ["A","B","C","D","E","F","G","H"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "smooth": true, "areaStyle": [String: Any](),
                        "data": [10.0,22,18,35,28,42,30,48]] as [String: Any]]
        ])

    static let demo_bar_polar_radial = EChartsDemo(
        name: "bar-polar-radial", category: "Polar",
        summary: "a bar series on polar coordinates",
        width: 380, height: 360,
        option: [
            "polar": [String: Any](),
            "angleAxis": ["type": "category", "data": ["a","b","c","d","e","f"]] as [String: Any],
            "radiusAxis": [String: Any](),
            "series": [["type": "bar", "coordinateSystem": "polar",
                        "data": [4.0,7,5,9,6,8]] as [String: Any]]
        ])

    static let demo_scatter_polar = EChartsDemo(
        name: "scatter-polar", category: "Polar",
        summary: "scatter on a polar coordinate",
        width: 380, height: 360,
        option: [
            "polar": [String: Any](),
            "angleAxis": [String: Any](),
            "radiusAxis": [String: Any](),
            "series": [["type": "scatter", "coordinateSystem": "polar", "symbolSize": 10.0,
                        "data": [[3.0, 30.0], [5.0, 90.0], [7.0, 150.0], [4.0, 220.0], [6.0, 300.0]]] as [String: Any]]
        ])

    static let demo_pie_selected = EChartsDemo(
        name: "pie-selected", category: "Pie",
        summary: "pie with a fixed center and radius",
        width: 400, height: 320,
        option: [
            "series": [["type": "pie", "radius": "55%", "center": ["50%", "55%"],
                        "data": [
                            ["value": 48.0, "name": "north"] as [String: Any],
                            ["value": 26.0, "name": "east"] as [String: Any],
                            ["value": 18.0, "name": "south"] as [String: Any],
                            ["value": 34.0, "name": "west"] as [String: Any]
                        ]] as [String: Any]]
        ])

    static let demo_bar_multi_grid = EChartsDemo(
        name: "bar-two-series-grid", category: "Bar",
        summary: "two bar series with a legend + axis names",
        width: 480, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 30.0, "width": 400.0, "height": 220.0] as [String: Any],
            "legend": ["top": 4.0] as [String: Any],
            "xAxis": ["type": "category", "name": "day", "data": ["Mon","Tue","Wed","Thu","Fri"]] as [String: Any],
            "yAxis": ["type": "value", "name": "count"] as [String: Any],
            "series": [
                ["name": "in", "type": "bar", "data": [12.0,18,15,22,19]] as [String: Any],
                ["name": "out", "type": "bar", "data": [9.0,14,11,17,13]] as [String: Any]
            ]
        ])

    static let demo_line_step = EChartsDemo(
        name: "line-step", category: "Line",
        summary: "a step line (step:'end')",
        width: 460, height: 300,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 380.0, "height": 240.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A","B","C","D","E","F"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "step": "end", "data": [5.0,9,7,12,8,14]] as [String: Any]]
        ])
}
