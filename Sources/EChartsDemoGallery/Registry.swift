// Registry.swift — index of every demo (one per Demos/<name>.swift), grouped by category.
// Add a new Demos/*.swift then append its constant here.
extension EChartsDemoRegistry {
    public static let everything: [EChartsDemo] = [
        EChartsDemoRegistry.demo_bar_basic,     // Bar
        EChartsDemoRegistry.demo_bar_seven,     // Bar
        EChartsDemoRegistry.demo_line_basic,    // Line
        EChartsDemoRegistry.demo_scatter_basic, // Scatter
        EChartsDemoRegistry.demo_effectscatter_basic, // EffectScatter
        EChartsDemoRegistry.demo_lines_basic,   // Lines
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
        EChartsDemoRegistry.demo_polar_basic,       // Polar
        EChartsDemoRegistry.demo_gauge_basic,       // Gauge
        EChartsDemoRegistry.demo_sankey_basic,      // Sankey
        EChartsDemoRegistry.demo_chord_basic,       // Chord
        EChartsDemoRegistry.demo_themeriver_basic,  // ThemeRiver
        EChartsDemoRegistry.demo_parallel_basic,    // Parallel
        EChartsDemoRegistry.demo_calendar_basic,    // Calendar
        EChartsDemoRegistry.demo_geo_basic,         // Geo (toy GeoJSON regions backdrop)
        EChartsDemoRegistry.demo_map_basic,         // Map (choropleth — toy GeoJSON regions filled by value)
        EChartsDemoRegistry.demo_visualmap_basic,   // VisualMap (continuous, scatter colored by value)
        EChartsDemoRegistry.demo_heatmap_basic,     // Heatmap (cartesian, cells colored by value via visualMap)
    ]
}
