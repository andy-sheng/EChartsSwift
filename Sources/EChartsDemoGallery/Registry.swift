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
        EChartsDemoRegistry.demo_matrix_basic,      // Matrix (table backdrop — header cells + body cells)
        EChartsDemoRegistry.demo_geo_basic,         // Geo (toy GeoJSON regions backdrop)
        EChartsDemoRegistry.demo_map_basic,         // Map (choropleth — toy GeoJSON regions filled by value)
        EChartsDemoRegistry.demo_visualmap_basic,   // VisualMap (continuous, scatter colored by value)
        EChartsDemoRegistry.demo_heatmap_basic,     // Heatmap (cartesian, cells colored by value via visualMap)
        EChartsDemoRegistry.demo_custom_basic,      // Custom (cartesian, renderItem hand-rolls one rect bar per datum)
        // gallery-batch1 — echarts test/ scenarios (goal clause 2).
        EChartsDemoRegistry.demo_bar_stack,             // Bar (stacked)
        EChartsDemoRegistry.demo_bar_negative,          // Bar (negative values)
        EChartsDemoRegistry.demo_bar_horizontal,        // Bar (horizontal / yAxis category)
        EChartsDemoRegistry.demo_line_area,             // Line (areaStyle)
        EChartsDemoRegistry.demo_line_smooth,           // Line (smooth, multi-series)
        EChartsDemoRegistry.demo_line_stack,            // Line (stacked areas)
        EChartsDemoRegistry.demo_pie_doughnut,          // Pie (doughnut)
        EChartsDemoRegistry.demo_pie_rose,              // Pie (nightingale rose)
        EChartsDemoRegistry.demo_scatter_multi,         // Scatter (multi-series)
        EChartsDemoRegistry.demo_bar_datazoom_slider,   // DataZoom (slider + axis tooltip)
        // gallery-batch2 — more echarts test/ scenarios (goal clause 2).
        EChartsDemoRegistry.demo_bar_multi3,            // Bar (3 grouped series)
        EChartsDemoRegistry.demo_line_dashed,           // Line (dashed lineStyle)
        EChartsDemoRegistry.demo_scatter_large,         // Scatter (80-point cloud)
        EChartsDemoRegistry.demo_pie_labeled,           // Pie (labels + label lines)
        EChartsDemoRegistry.demo_radar_multi,           // Radar (3 overlaid series)
        EChartsDemoRegistry.demo_line_multi5,           // Line (5 series)
        EChartsDemoRegistry.demo_mix_bar_line,          // Bar+Line (mixed on one grid)
        EChartsDemoRegistry.demo_area_two,              // Line (two area series)
        // gallery-batch3 — more echarts test/ scenarios (goal clause 2).
        EChartsDemoRegistry.demo_bar_background,         // Bar (showBackground)
        EChartsDemoRegistry.demo_bar_large,             // Bar (40 bars)
        EChartsDemoRegistry.demo_bar_width,             // Bar (fixed barWidth)
        EChartsDemoRegistry.demo_bar_stack_reverse,     // Bar (stacked)
        EChartsDemoRegistry.demo_boxplot_multi,         // Boxplot (multi category)
        EChartsDemoRegistry.demo_candlestick_large,     // Candlestick (20 candles)
        EChartsDemoRegistry.demo_funnel_sorted,         // Funnel (ascending)
        EChartsDemoRegistry.demo_gauge_simple,          // Gauge (single pointer)
        EChartsDemoRegistry.demo_graph_circular,        // Graph (circular layout)
        EChartsDemoRegistry.demo_heatmap_large,         // Heatmap (12×7)
        EChartsDemoRegistry.demo_parallel_multi,        // Parallel (4 dims)
        EChartsDemoRegistry.demo_pie_half,              // Pie (half doughnut)
        EChartsDemoRegistry.demo_radar_filled,          // Radar (areaStyle)
        EChartsDemoRegistry.demo_scatter_symbolsize,    // Scatter (large symbols)
        EChartsDemoRegistry.demo_sankey_vertical,       // Sankey (vertical)
        EChartsDemoRegistry.demo_sunburst_multi,        // Sunburst (2 level)
        EChartsDemoRegistry.demo_treemap_levels,        // Treemap (nested)
        EChartsDemoRegistry.demo_tree_right,            // Tree (LR)
        EChartsDemoRegistry.demo_line_negative,         // Line (negative)
    ]
}
