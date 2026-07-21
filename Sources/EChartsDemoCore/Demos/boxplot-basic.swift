// boxplot-basic — a single cartesian boxplot series. Renders on BOTH panes: native (EChartsKit's
// BoxplotView draws a BoxPath box+median+whiskers per datum) and echarts.js. Data per item =
// [min, Q1, median, Q3, max] (pre-computed here; the `boxplot` dataset transform IS ported —
// chart/boxplot/boxplotTransform.swift, registered in component/transform/transformInstall.swift:69 —
// see the official-boxplot-* demos for the transform-driven form).
extension EChartsDemoRegistry {
    static let demo_boxplot_basic = EChartsDemo(
        name: "boxplot-basic", category: "Boxplot",
        summary: "single boxplot series, 5 groups (pre-computed 5-number)",
        width: 520, height: 340,
        option: [
            "grid": ["left": 50.0, "top": 20.0, "width": 440.0, "height": 260.0] as [String: Any],
            "xAxis": ["type": "category",
                      "data": ["G1", "G2", "G3", "G4", "G5"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "boxplot",
                        "data": [[10.0, 22.0, 28.0, 35.0, 50.0],
                                 [15.0, 25.0, 33.0, 40.0, 55.0],
                                 [8.0, 18.0, 24.0, 30.0, 44.0],
                                 [20.0, 30.0, 38.0, 46.0, 60.0],
                                 [12.0, 20.0, 27.0, 36.0, 48.0]]] as [String: Any]]
        ])
}
