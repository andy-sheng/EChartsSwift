// heatmap-basic — a cartesian heatmap (category xAxis × category yAxis) whose cells are colored BY VALUE
// through a continuous visualMap. Each [x, y, value] datum becomes one colored Rect centered on its grid
// cell; the cell FILL is the value->color gradient sample the visualMap VISUAL stage wrote into the datum's
// item visual style (low → #313695 blue, high → #a50026 red). A visualMap component is REQUIRED — without
// it the cells receive no color (HeatmapView reads back data.getItemVisual(idx, "style").fill). Renders on
// BOTH panes: native (EChartsKit's HeatmapView draws one Rect per cell) and real echarts.js. Category axes
// with boundaryGap true (onBand) are required so calcBandWidth gives each cell a finite width/height.
extension EChartsDemoRegistry {
    static let demo_heatmap_basic = EChartsDemo(
        name: "heatmap-basic", category: "Heatmap",
        summary: "cartesian heatmap with cells colored by value via a continuous visualMap gradient",
        width: 480, height: 320,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "right": 20.0, "bottom": 40.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["Mon", "Tue", "Wed", "Thu", "Fri"]] as [String: Any],
            "yAxis": ["type": "category", "data": ["AM", "PM", "Eve"]] as [String: Any],
            "visualMap": [
                "type": "continuous",
                "min": 0.0,
                "max": 10.0,
                "calculable": true,
                "inRange": ["color": ["#313695", "#74add1", "#fee090", "#f46d43", "#a50026"]] as [String: Any]
            ] as [String: Any],
            "series": [[
                "type": "heatmap",
                // [xIndex, yIndex, value] — one cell per (day, slot).
                "data": [
                    [0.0, 0.0, 1.0], [1.0, 0.0, 3.0], [2.0, 0.0, 5.0], [3.0, 0.0, 7.0], [4.0, 0.0, 9.0],
                    [0.0, 1.0, 2.0], [1.0, 1.0, 4.0], [2.0, 1.0, 6.0], [3.0, 1.0, 8.0], [4.0, 1.0, 10.0],
                    [0.0, 2.0, 0.0], [1.0, 2.0, 2.0], [2.0, 2.0, 4.0], [3.0, 2.0, 6.0], [4.0, 2.0, 8.0]
                ]
            ] as [String: Any]]
        ])
}
