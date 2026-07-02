// Registry.swift — index of every demo (one per Demos/<name>.swift), grouped by category.
// Add a new Demos/*.swift then append its constant here.
extension EChartsDemoRegistry {
    public static let everything: [EChartsDemo] = [
        EChartsDemoRegistry.demo_bar_basic,   // Bar
        EChartsDemoRegistry.demo_bar_seven,   // Bar
        EChartsDemoRegistry.demo_line_basic,  // Line (html-only for now)
    ]
}
