// Registry.swift — index of every demo (one per Demos/<name>.swift), grouped by category.
// Add a new Demos/*.swift then append its constant here.
extension EChartsDemoRegistry {
    public static let everything: [EChartsDemo] = [
        EChartsDemoRegistry.demo_dark_basic,    // Theme (built-in dark theme palette)
        EChartsDemoRegistry.demo_bar_basic,     // Bar
        EChartsDemoRegistry.demo_bar_seven,     // Bar
        EChartsDemoRegistry.demo_line_basic,    // Line
        EChartsDemoRegistry.demo_line_lttb,     // Line (10k points down-sampled via sampling:"lttb")
        EChartsDemoRegistry.demo_scatter_basic, // Scatter
        EChartsDemoRegistry.demo_large_scatter, // Scatter (large-mode single LargeSymbolPath)
        EChartsDemoRegistry.demo_effectscatter_basic, // EffectScatter
        EChartsDemoRegistry.demo_lines_basic,   // Lines
        EChartsDemoRegistry.demo_lines_effect,  // Lines (flying-trail effect)
        EChartsDemoRegistry.demo_pie_basic,     // Pie
        EChartsDemoRegistry.demo_bar_title_legend, // Component (title + legend)
        EChartsDemoRegistry.demo_timeline_basic,   // Component (timeline playhead + baseOption/options merge)
        EChartsDemoRegistry.demo_funnel_basic,      // Funnel
        EChartsDemoRegistry.demo_candlestick_basic, // Candlestick
        EChartsDemoRegistry.demo_boxplot_basic,     // Boxplot
        EChartsDemoRegistry.demo_sunburst_basic,    // Sunburst
        EChartsDemoRegistry.demo_treemap_basic,     // Treemap
        EChartsDemoRegistry.demo_tree_basic,        // Tree
        EChartsDemoRegistry.demo_graph_basic,       // Graph
        EChartsDemoRegistry.demo_graph_force,       // Graph (force layout)
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
        EChartsDemoRegistry.demo_map_svg_basic,     // Geo (SVG-backed map — labels + hover-emphasis + roam)
        EChartsDemoRegistry.demo_map_svg_series,    // Geo (series:"map" on an SVG map — regions coloured by value)
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
        // gallery-batch4 — component + coordinate scenarios (goal clause 2).
        EChartsDemoRegistry.demo_datazoom_inside,       // DataZoom (inside)
        EChartsDemoRegistry.demo_tooltip_axis,          // Component (tooltip trigger axis)
        EChartsDemoRegistry.demo_visualmap_piecewise,   // VisualMap (piecewise)
        EChartsDemoRegistry.demo_calendar_heatmap,      // Calendar (heatmap)
        EChartsDemoRegistry.demo_polar_line,            // Polar (line)
        EChartsDemoRegistry.demo_dataset_bar,           // Dataset (bar)
        EChartsDemoRegistry.demo_lines_grid,            // Lines (cartesian segments)
        EChartsDemoRegistry.demo_effectscatter_grid,    // EffectScatter (grid)
        EChartsDemoRegistry.demo_pie_nest,              // Pie (nested rings)
        EChartsDemoRegistry.demo_themeriver_stream,     // ThemeRiver (stream)
        EChartsDemoRegistry.demo_dataset_scatter,       // Dataset (scatter)
        EChartsDemoRegistry.demo_bar_two_yaxis,         // Bar (two y-axes)
        // gallery-batch5 — more configuration variations (goal clause 2).
        EChartsDemoRegistry.demo_bar_horizontal_stack,  // Bar (horizontal stack)
        EChartsDemoRegistry.demo_line_multi_axis,       // Line (two y-axes)
        EChartsDemoRegistry.demo_scatter_two_axis,      // Scatter (fixed axis range)
        EChartsDemoRegistry.demo_pie_ring_label,        // Pie (ring + labels)
        EChartsDemoRegistry.demo_radar_two,             // Radar (two series)
        EChartsDemoRegistry.demo_graph_symbol,          // Graph (per-node symbolSize)
        EChartsDemoRegistry.demo_sankey_multi,          // Sankey (three column)
        EChartsDemoRegistry.demo_tree_deep,             // Tree (deeper)
        EChartsDemoRegistry.demo_treemap_flat,          // Treemap (flat)
        EChartsDemoRegistry.demo_sunburst_ring,         // Sunburst (inner hole)
        EChartsDemoRegistry.demo_boxplot_wide,          // Boxplot (7 categories)
        EChartsDemoRegistry.demo_funnel_wide,           // Funnel (6 stages)
        // gallery-batch6 — coordinate-system + visual variations (goal clause 2).
        EChartsDemoRegistry.demo_visualmap_continuous_bar, // VisualMap (continuous, bar)
        EChartsDemoRegistry.demo_heatmap_small,         // Heatmap (5×5)
        EChartsDemoRegistry.demo_geo_scatter,           // Geo (scatter over geo)
        EChartsDemoRegistry.demo_gauge_progress,        // Gauge (progress arc)
        EChartsDemoRegistry.demo_gauge_two,             // Gauge (two)
        EChartsDemoRegistry.demo_line_area_gradient,    // Line (smooth area)
        EChartsDemoRegistry.demo_bar_polar_radial,      // Polar (bar)
        EChartsDemoRegistry.demo_scatter_polar,         // Polar (scatter)
        EChartsDemoRegistry.demo_pie_selected,          // Pie (fixed center)
        EChartsDemoRegistry.demo_bar_multi_grid,        // Bar (two series + axis names)
        EChartsDemoRegistry.demo_line_step,             // Line (step)
        // gallery-batch7 — item-style + edge-shape + per-indicator variations (goal clause 2).
        EChartsDemoRegistry.demo_bar_item_color,        // Bar (itemStyle color)
        EChartsDemoRegistry.demo_line_item_color,       // Line (lineStyle color)
        EChartsDemoRegistry.demo_scatter_series_color,  // Scatter (per-series color)
        EChartsDemoRegistry.demo_pie_colored,           // Pie (per-slice color)
        EChartsDemoRegistry.demo_tree_polyline,         // Tree (polyline edges)
        EChartsDemoRegistry.demo_graph_grid,            // Graph (3×3 grid)
        EChartsDemoRegistry.demo_sankey_branch,         // Sankey (branching)
        EChartsDemoRegistry.demo_radar_varied_max,      // Radar (varied max)
        EChartsDemoRegistry.demo_heatmap_piecewise,     // Heatmap (piecewise)
        EChartsDemoRegistry.demo_line_boundary_gap,     // Line (boundaryGap false)
        EChartsDemoRegistry.demo_themeriver_three,      // ThemeRiver (3 series)
        EChartsDemoRegistry.demo_boxplot_single,        // Boxplot (single)
        // gallery-batch8 — label / symbol / split-area / depth variations (goal clause 2).
        EChartsDemoRegistry.demo_bar_label_top,         // Bar (top labels)
        EChartsDemoRegistry.demo_line_no_symbol,        // Line (no symbols)
        EChartsDemoRegistry.demo_pie_label_inside,      // Pie (inside labels)
        EChartsDemoRegistry.demo_scatter_dense,         // Scatter (60 points)
        EChartsDemoRegistry.demo_radar_split_area,      // Radar (split area)
        EChartsDemoRegistry.demo_graph_labeled,         // Graph (labels)
        EChartsDemoRegistry.demo_sankey_labeled,        // Sankey (labels)
        EChartsDemoRegistry.demo_tree_top_bottom,       // Tree (TB orient)
        EChartsDemoRegistry.demo_treemap_three,         // Treemap (three branch)
        EChartsDemoRegistry.demo_sunburst_labeled,      // Sunburst (labels)
        EChartsDemoRegistry.demo_bar_min_height,        // Bar (barMinHeight)
        EChartsDemoRegistry.demo_line_two_smooth,       // Line (two smooth)
        EChartsDemoRegistry.demo_toolbox_basic,         // Component (toolbox icon row)
        // gallery-decal — decal (repeating-texture) patterns (util/decal + aria.decal.show).
        EChartsDemoRegistry.demo_bar_decal,             // Bar (itemStyle.decal texture)
        EChartsDemoRegistry.demo_bar_aria_decal,        // Bar (aria.decal.show auto-texture)
    ]
}
