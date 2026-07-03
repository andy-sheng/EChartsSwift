// Registry.swift — index of every demo (one per Demos/<name>.swift), grouped by category.
// Add a new Demos/*.swift then append its constant here.
extension EChartsDemoRegistry {
    public static let everything: [EChartsDemo] = [
        EChartsDemoRegistry.demo_bar_basic,     // Bar
        EChartsDemoRegistry.demo_bar_seven,     // Bar
        EChartsDemoRegistry.demo_line_basic,    // Line
        EChartsDemoRegistry.demo_scatter_basic, // Scatter
        EChartsDemoRegistry.demo_pie_basic,     // Pie
        EChartsDemoRegistry.demo_bar_title_legend, // Component (title + legend)
        EChartsDemoRegistry.demo_funnel_basic,      // Funnel
        EChartsDemoRegistry.demo_candlestick_basic, // Candlestick
        EChartsDemoRegistry.demo_boxplot_basic,     // Boxplot
        EChartsDemoRegistry.demo_sunburst_basic,    // Sunburst
        EChartsDemoRegistry.demo_treemap_basic,     // Treemap
        EChartsDemoRegistry.demo_tree_basic,        // Tree
        EChartsDemoRegistry.demo_graph_basic,       // Graph
        EChartsDemoRegistry.demo_radar_basic,       // Radar
    ]
}
