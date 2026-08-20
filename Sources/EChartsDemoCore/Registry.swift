// Registry.swift — index of every demo (one per Demos/<name>.swift), grouped by category.
// Add a new Demos/*.swift then append its constant here.
//
// Two collections (see EChartsDemo.Collection), surfaced as separate gallery tabs:
//   .port     — `portDemos`, the port-driven cases grown alongside EChartsKit.
//   .official — `officialDemos`, replicas of echarts.apache.org/examples (Demos/official-*.swift),
//               one representative per chart-type category from `line` through `rich`.
extension EChartsDemoRegistry {
    /// Every demo in both collections (port first). `--list` / `--render-all` walk this.
    public static let everything: [EChartsDemo] = portDemos + officialDemos

    /// The demos of one collection, in registry order.
    public static func demos(in collection: EChartsDemo.Collection) -> [EChartsDemo] {
        collection == .port ? portDemos : officialDemos
    }

    // MARK: - .port — grown alongside the EChartsKit port

    public static let portDemos: [EChartsDemo] = [
        EChartsDemoRegistry.demo_dark_basic,    // Theme (built-in dark theme palette)
        EChartsDemoRegistry.demo_bar_basic,     // Bar
        EChartsDemoRegistry.demo_bar_seven,     // Bar
        EChartsDemoRegistry.demo_line_basic,    // Line
        EChartsDemoRegistry.demo_line_stacked_area, // Line (5-series stacked area, official example)
        EChartsDemoRegistry.demo_line_lttb,     // Line (10k points down-sampled via sampling:"lttb")
        EChartsDemoRegistry.demo_scatter_basic, // Scatter
        EChartsDemoRegistry.demo_large_scatter, // Scatter (large-mode single LargeSymbolPath)
        EChartsDemoRegistry.demo_effectscatter_basic, // EffectScatter
        EChartsDemoRegistry.demo_lines_basic,   // Lines
        EChartsDemoRegistry.demo_lines_effect,  // Lines (flying-trail effect)
        EChartsDemoRegistry.demo_pie_basic,     // Pie
        EChartsDemoRegistry.demo_bar_title_legend, // Component (title + legend)
        EChartsDemoRegistry.demo_legend_selector,  // Component (legend All/Inv selector buttons)
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
        EChartsDemoRegistry.demo_themeriver_full,   // ThemeRiver (6 layers + tooltip/legend/time axis)
        EChartsDemoRegistry.demo_parallel_basic,    // Parallel
        EChartsDemoRegistry.demo_calendar_basic,    // Calendar
        EChartsDemoRegistry.demo_matrix_basic,      // Matrix (table backdrop — header cells + body cells)
        EChartsDemoRegistry.demo_geo_basic,         // Geo (toy GeoJSON regions backdrop)
        EChartsDemoRegistry.demo_map_svg_basic,     // Geo (SVG-backed map — labels + hover-emphasis + roam)
        EChartsDemoRegistry.demo_map_svg_series,    // Geo (series:"map" on an SVG map — regions coloured by value)
        EChartsDemoRegistry.demo_map_basic,         // Map (choropleth — toy GeoJSON regions filled by value)
        EChartsDemoRegistry.demo_map_bar_morph,     // Map (USA population choropleth — map↔bar universalTransition example, static map frame)
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
        // marker — markPoint / markLine / markArea (component/marker).
        EChartsDemoRegistry.demo_marker_markpoint,      // Marker (markPoint max + min)
        EChartsDemoRegistry.demo_marker_markline,       // Marker (markLine average + yAxis line)
        EChartsDemoRegistry.demo_marker_markarea,       // Marker (markArea band)
    ]

    // MARK: - .official — replicas of echarts.apache.org/examples
    //
    // One representative example per chart-type category, in the order the official gallery lists
    // them (`line` … `rich`). Each carries the example's VERBATIM JS (`webOptionJS`, what the web
    // pane runs — so its formatters/renderItem closures execute as real JS) alongside the Swift
    // `option` the native pane consumes; `nativeSupported: false` marks the ones EChartsKit can't
    // drive yet. Keep this list in the official gallery's order — it is the tab's reading order.
    public static let officialDemos: [EChartsDemo] = [
        EChartsDemoRegistry.official_line_simple,                            // line
        EChartsDemoRegistry.official_line_smooth,                            // line
        EChartsDemoRegistry.official_area_basic,                             // line
        EChartsDemoRegistry.official_line_stack,                             // line
        EChartsDemoRegistry.official_area_stack,                             // line
        EChartsDemoRegistry.official_area_stack_gradient,                    // line
        EChartsDemoRegistry.official_bump_chart,                             // line
        EChartsDemoRegistry.official_line_marker,                            // line
        EChartsDemoRegistry.official_area_pieces,                            // line
        EChartsDemoRegistry.official_data_transform_filter,                  // line
        EChartsDemoRegistry.official_line_gradient,                          // line
        EChartsDemoRegistry.official_line_sections,                          // line
        EChartsDemoRegistry.official_confidence_band,                        // line
        EChartsDemoRegistry.official_grid_multiple,                          // line
        EChartsDemoRegistry.official_line_aqi,                               // line
        EChartsDemoRegistry.official_multiple_x_axis,                        // line
        EChartsDemoRegistry.official_area_rainfall,                          // line
        EChartsDemoRegistry.official_area_time_axis,                         // line
        EChartsDemoRegistry.official_dynamic_data2,                          // line
        EChartsDemoRegistry.official_line_function,                          // line
        EChartsDemoRegistry.official_line_race,                              // line
        EChartsDemoRegistry.official_line_markline,                          // line
        EChartsDemoRegistry.official_line_style,                             // line
        EChartsDemoRegistry.official_line_in_cartesian_coordinate_system,    // line
        EChartsDemoRegistry.official_line_log,                               // line
        EChartsDemoRegistry.official_line_step,                              // line
        EChartsDemoRegistry.official_line_easing,                            // line
        EChartsDemoRegistry.official_line_fisheye_lens,                      // line
        EChartsDemoRegistry.official_line_y_category,                        // line
        EChartsDemoRegistry.official_line_pen,                               // line
        EChartsDemoRegistry.official_line_polar,                             // line
        EChartsDemoRegistry.official_line_polar2,                            // line
        EChartsDemoRegistry.official_line_tooltip_touch,                     // line
        EChartsDemoRegistry.official_line_draggable,                         // line
        EChartsDemoRegistry.official_bar_simple,                             // bar
        EChartsDemoRegistry.official_bar_tick_align,                         // bar
        EChartsDemoRegistry.official_bar_background,                         // bar
        EChartsDemoRegistry.official_bar_data_color,                         // bar
        EChartsDemoRegistry.official_bar_waterfall,                          // bar
        EChartsDemoRegistry.official_bar_negative2,                          // bar
        EChartsDemoRegistry.official_bar_polar_label_radial,                 // bar
        EChartsDemoRegistry.official_bar_polar_label_tangential,             // bar
        EChartsDemoRegistry.official_bar_y_category,                         // bar
        EChartsDemoRegistry.official_polar_endangle,                         // bar
        EChartsDemoRegistry.official_bar_breaks_simple,                      // bar
        EChartsDemoRegistry.official_bar_gradient,                           // bar
        EChartsDemoRegistry.official_bar_label_rotation,                     // bar
        EChartsDemoRegistry.official_bar_stack,                              // bar
        EChartsDemoRegistry.official_bar_stack_borderradius,                 // bar
        EChartsDemoRegistry.official_bar_stack_normalization,                // bar
        EChartsDemoRegistry.official_bar_stack_normalization_and_variation,  // bar
        EChartsDemoRegistry.official_bar_waterfall2,                         // bar
        EChartsDemoRegistry.official_bar_y_category_stack,                   // bar
        EChartsDemoRegistry.official_bar_brush,                              // bar
        EChartsDemoRegistry.official_bar_negative,                           // bar
        EChartsDemoRegistry.official_bar1,                                   // bar
        EChartsDemoRegistry.official_mix_line_bar,                           // bar
        EChartsDemoRegistry.official_mix_zoom_on_value,                      // bar
        EChartsDemoRegistry.official_multiple_y_axis,                        // bar
        EChartsDemoRegistry.official_bar_animation_delay,                    // bar
        EChartsDemoRegistry.official_bar_drilldown,                          // bar
        EChartsDemoRegistry.official_bar_large,                              // bar
        EChartsDemoRegistry.official_bar_race,                               // bar
        EChartsDemoRegistry.official_bar_multi_drilldown,                    // bar
        EChartsDemoRegistry.official_bar_race_country,                       // bar
        EChartsDemoRegistry.official_bar_rich_text,                          // bar
        EChartsDemoRegistry.official_dynamic_data,                           // bar
        EChartsDemoRegistry.official_mix_timeline_finance,                   // bar
        EChartsDemoRegistry.official_watermark,                              // bar
        EChartsDemoRegistry.official_bar_polar_real_estate,                  // bar
        EChartsDemoRegistry.official_bar_polar_stack,                        // bar
        EChartsDemoRegistry.official_bar_polar_stack_radial,                 // bar
        EChartsDemoRegistry.official_polar_roundcap,                         // bar
        EChartsDemoRegistry.official_bar_breaks_brush,                       // bar
        EChartsDemoRegistry.official_pie_simple,                             // pie
        EChartsDemoRegistry.official_pie_borderradius,                       // pie
        EChartsDemoRegistry.official_pie_doughnut,                           // pie
        EChartsDemoRegistry.official_pie_half_donut,                         // pie
        EChartsDemoRegistry.official_pie_padangle,                           // pie
        EChartsDemoRegistry.official_pie_custom,                             // pie
        EChartsDemoRegistry.official_pie_pattern,                            // pie
        EChartsDemoRegistry.official_pie_rosetype,                           // pie
        EChartsDemoRegistry.official_pie_rosetype_simple,                    // pie
        EChartsDemoRegistry.official_pie_alignto,                            // pie
        EChartsDemoRegistry.official_pie_labelline_adjust,                   // pie
        EChartsDemoRegistry.official_pie_legend,                             // pie
        EChartsDemoRegistry.official_pie_nest,                               // pie
        EChartsDemoRegistry.official_scatter_simple,                         // scatter
        EChartsDemoRegistry.official_scatter_anscombe_quartet,               // scatter
        EChartsDemoRegistry.official_scatter_clustering,                     // scatter
        EChartsDemoRegistry.official_scatter_clustering_process,             // scatter   (native N/A)
        EChartsDemoRegistry.official_scatter_exponential_regression,         // scatter   (native N/A)
        EChartsDemoRegistry.official_scatter_effect,                         // scatter
        EChartsDemoRegistry.official_scatter_linear_regression,              // scatter   (native N/A)
        EChartsDemoRegistry.official_scatter_polynomial_regression,          // scatter   (native N/A)
        EChartsDemoRegistry.official_scatter_jitter,                         // scatter
        EChartsDemoRegistry.official_scatter_punchcard,                      // scatter
        EChartsDemoRegistry.official_scatter_single_axis,                    // scatter
        EChartsDemoRegistry.official_scatter_weight,                         // scatter
        EChartsDemoRegistry.official_scatter_aggregate_bar,                  // scatter
        EChartsDemoRegistry.official_scatter_label_align_right,              // scatter
        EChartsDemoRegistry.official_scatter_label_align_top,                // scatter
        EChartsDemoRegistry.official_scatter_symbol_morph,                   // scatter
        EChartsDemoRegistry.official_scatter_large,                          // scatter
        EChartsDemoRegistry.official_scatter_nebula,                         // scatter
        EChartsDemoRegistry.official_scatter_stream_visual,                  // scatter
        EChartsDemoRegistry.official_bubble_gradient,                        // scatter
        EChartsDemoRegistry.official_scatter_aqi_color,                      // scatter
        EChartsDemoRegistry.official_scatter_nutrients,                      // scatter
        EChartsDemoRegistry.official_scatter_nutrients_matrix,               // scatter
        EChartsDemoRegistry.official_scatter_polar_punchcard,                // scatter
        EChartsDemoRegistry.official_scatter_life_expectancy_timeline,       // scatter
        EChartsDemoRegistry.official_scatter_painter_choice,                 // scatter
        EChartsDemoRegistry.official_scatter_world_population,               // scatter
        EChartsDemoRegistry.official_scatter_logarithmic_regression,         // scatter   (native N/A)
        EChartsDemoRegistry.official_effectscatter_map,                      // scatter
        EChartsDemoRegistry.official_scatter_map,                            // scatter
        EChartsDemoRegistry.official_scatter_map_brush,                      // scatter
        EChartsDemoRegistry.official_scatter_weibo,                          // scatter
        EChartsDemoRegistry.official_map_iceland_pie,                        // map
        EChartsDemoRegistry.official_geo_choropleth_scatter,                 // map
        EChartsDemoRegistry.official_geo_graph,                              // map
        EChartsDemoRegistry.official_geo_beef_cuts,                          // map
        EChartsDemoRegistry.official_geo_organ,                              // map
        EChartsDemoRegistry.official_geo_seatmap_flight,                     // map
        EChartsDemoRegistry.official_geo_svg_lines,                          // map
        EChartsDemoRegistry.official_geo_svg_map,                            // map
        EChartsDemoRegistry.official_geo_svg_scatter_simple,                 // map
        EChartsDemoRegistry.official_geo_svg_traffic,                        // map
        EChartsDemoRegistry.official_lines_airline,                          // map
        EChartsDemoRegistry.official_lines_ny,                               // map
        EChartsDemoRegistry.official_map_bar_morph,                          // map
        EChartsDemoRegistry.official_map_hk,                                 // map
        EChartsDemoRegistry.official_map_usa,                                // map
        EChartsDemoRegistry.official_map_usa_projection,                     // map
        EChartsDemoRegistry.official_geo_lines,                              // map
        EChartsDemoRegistry.official_geo_map_scatter,                        // map
        EChartsDemoRegistry.official_intraday_breaks_1,                      // candlestick
        EChartsDemoRegistry.official_intraday_breaks_2,                      // candlestick
        EChartsDemoRegistry.official_candlestick_simple,                     // candlestick
        EChartsDemoRegistry.official_custom_ohlc,                            // candlestick   (native N/A)
        EChartsDemoRegistry.official_candlestick_sh,                         // candlestick
        EChartsDemoRegistry.official_candlestick_large,                      // candlestick
        EChartsDemoRegistry.official_candlestick_touch,                      // candlestick
        EChartsDemoRegistry.official_candlestick_brush,                      // candlestick
        EChartsDemoRegistry.official_candlestick_sh_2015,                    // candlestick
        EChartsDemoRegistry.official_radar,                                  // radar
        EChartsDemoRegistry.official_radar_aqi,                              // radar
        EChartsDemoRegistry.official_radar_custom,                           // radar
        EChartsDemoRegistry.official_radar2,                                 // radar
        EChartsDemoRegistry.official_radar_multiple,                         // radar
        EChartsDemoRegistry.official_data_transform_aggregate,               // boxplot   (native N/A)
        EChartsDemoRegistry.official_boxplot_light_velocity,                 // boxplot
        EChartsDemoRegistry.official_boxplot_light_velocity2,                // boxplot
        EChartsDemoRegistry.official_boxplot_multi,                          // boxplot
        EChartsDemoRegistry.official_heatmap_cartesian,                      // heatmap
        EChartsDemoRegistry.official_heatmap_large,                          // heatmap
        EChartsDemoRegistry.official_heatmap_large_piecewise,                // heatmap
        EChartsDemoRegistry.official_heatmap_map,                            // heatmap
        EChartsDemoRegistry.official_graph_force2,                           // graph
        EChartsDemoRegistry.official_graph_grid,                             // graph
        EChartsDemoRegistry.official_graph_simple,                           // graph
        EChartsDemoRegistry.official_graph_label_overlap,                    // graph
        EChartsDemoRegistry.official_graph_circular_layout,                  // graph
        EChartsDemoRegistry.official_graph_force_dynamic,                    // graph
        EChartsDemoRegistry.official_graph_life_expectancy,                  // graph
        EChartsDemoRegistry.official_graph_webkit_dep,                       // graph
        EChartsDemoRegistry.official_graph_npm,                              // graph
        EChartsDemoRegistry.official_tree_basic,                             // tree
        EChartsDemoRegistry.official_tree_legend,                            // tree
        EChartsDemoRegistry.official_tree_orient_bottom_top,                 // tree
        EChartsDemoRegistry.official_tree_orient_right_left,                 // tree
        EChartsDemoRegistry.official_tree_polyline,                          // tree
        EChartsDemoRegistry.official_tree_vertical,                          // tree
        EChartsDemoRegistry.official_treemap_sunburst_transition,            // treemap
        EChartsDemoRegistry.official_treemap_drill_down,                     // treemap
        EChartsDemoRegistry.official_treemap_show_parent,                    // treemap
        EChartsDemoRegistry.official_treemap_simple,                         // treemap
        EChartsDemoRegistry.official_treemap_visual,                         // treemap
        EChartsDemoRegistry.official_treemap_obama,                          // treemap
        EChartsDemoRegistry.official_sunburst_simple,                        // sunburst
        EChartsDemoRegistry.official_sunburst_borderradius,                  // sunburst
        EChartsDemoRegistry.official_sunburst_label_rotate,                  // sunburst
        EChartsDemoRegistry.official_sunburst_monochrome,                    // sunburst
        EChartsDemoRegistry.official_sunburst_visualmap,                     // sunburst
        EChartsDemoRegistry.official_sunburst_drink,                         // sunburst
        EChartsDemoRegistry.official_sunburst_book,                          // sunburst
        EChartsDemoRegistry.official_scatter_matrix,                         // parallel
        EChartsDemoRegistry.official_parallel_simple,                        // parallel
        EChartsDemoRegistry.official_parallel_aqi,                           // parallel
        EChartsDemoRegistry.official_parallel_nutrients,                     // parallel
        EChartsDemoRegistry.official_sankey_simple,                          // sankey
        EChartsDemoRegistry.official_sankey_vertical,                        // sankey
        EChartsDemoRegistry.official_sankey_itemstyle,                       // sankey
        EChartsDemoRegistry.official_sankey_levels,                          // sankey
        EChartsDemoRegistry.official_sankey_energy,                          // sankey
        EChartsDemoRegistry.official_sankey_nodealign_left,                  // sankey
        EChartsDemoRegistry.official_sankey_nodealign_right,                 // sankey
        EChartsDemoRegistry.official_funnel,                                 // funnel
        EChartsDemoRegistry.official_funnel_align,                           // funnel
        EChartsDemoRegistry.official_funnel_customize,                       // funnel
        EChartsDemoRegistry.official_funnel_mutiple,                         // funnel
        EChartsDemoRegistry.official_gauge,                                  // gauge
        EChartsDemoRegistry.official_gauge_simple,                           // gauge
        EChartsDemoRegistry.official_gauge_speed,                            // gauge
        EChartsDemoRegistry.official_gauge_progress,                         // gauge
        EChartsDemoRegistry.official_gauge_stage,                            // gauge
        EChartsDemoRegistry.official_gauge_grade,                            // gauge
        EChartsDemoRegistry.official_gauge_ring,                             // gauge
        EChartsDemoRegistry.official_gauge_multi_title,                      // gauge
        EChartsDemoRegistry.official_gauge_temperature,                      // gauge
        EChartsDemoRegistry.official_gauge_barometer,                        // gauge
        EChartsDemoRegistry.official_gauge_clock,                            // gauge
        EChartsDemoRegistry.official_gauge_car,                              // gauge
        EChartsDemoRegistry.official_pictorialbar_bar_transition,            // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_body_fill,                 // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_dotted,                    // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_forest,                    // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_hill,                      // pictorialBar   (native N/A)
        EChartsDemoRegistry.official_pictorialbar_spirit,                    // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_vehicle,                   // pictorialBar
        EChartsDemoRegistry.official_pictorialbar_velocity,                  // pictorialBar
        EChartsDemoRegistry.official_themeriver_basic,                       // themeRiver
        EChartsDemoRegistry.official_themeriver_lastfm,                      // themeRiver
        EChartsDemoRegistry.official_calendar_pie,                           // calendar
        EChartsDemoRegistry.official_calendar_charts,                        // calendar
        EChartsDemoRegistry.official_calendar_heatmap,                       // calendar
        EChartsDemoRegistry.official_calendar_vertical,                      // calendar
        EChartsDemoRegistry.official_calendar_graph,                         // calendar
        EChartsDemoRegistry.official_calendar_simple,                        // calendar
        EChartsDemoRegistry.official_calendar_horizontal,                    // calendar
        EChartsDemoRegistry.official_calendar_lunar,                         // calendar
        EChartsDemoRegistry.official_calendar_effectscatter,                 // calendar
        EChartsDemoRegistry.official_matrix_sparkline,                       // matrix
        EChartsDemoRegistry.official_matrix_mini_bar_geo,                    // matrix
        EChartsDemoRegistry.official_matrix_stock,                           // matrix
        EChartsDemoRegistry.official_matrix_simple,                          // matrix
        EChartsDemoRegistry.official_matrix_covariance,                      // matrix
        EChartsDemoRegistry.official_matrix_graph,                           // matrix
        EChartsDemoRegistry.official_matrix_pie,                             // matrix
        EChartsDemoRegistry.official_matrix_confusion,                       // matrix   (native N/A)
        EChartsDemoRegistry.official_matrix_grid_layout,                     // matrix
        EChartsDemoRegistry.official_matrix_periodic_table,                  // matrix   (native N/A)
        EChartsDemoRegistry.official_matrix_mini_bar_data_collection,        // matrix   (native N/A)
        EChartsDemoRegistry.official_matrix_mbti,                            // matrix
        EChartsDemoRegistry.official_chord_simple,                           // chord
        EChartsDemoRegistry.official_chord_minangle,                         // chord
        EChartsDemoRegistry.official_chord_linestyle_color,                  // chord
        EChartsDemoRegistry.official_chord_style,                            // chord
        EChartsDemoRegistry.official_custom_hexbin,                          // custom   (native N/A)
        EChartsDemoRegistry.official_custom_calendar_icon,                   // custom   (native N/A)
        EChartsDemoRegistry.official_bar_histogram,                          // custom   (native N/A)
        EChartsDemoRegistry.official_custom_profit,                          // custom   (native N/A)
        EChartsDemoRegistry.official_custom_error_scatter,                   // custom
        EChartsDemoRegistry.official_custom_bar_trend,                       // custom
        EChartsDemoRegistry.official_custom_cartesian_polygon,               // custom
        EChartsDemoRegistry.official_custom_error_bar,                       // custom
        EChartsDemoRegistry.official_custom_profile,                         // custom   (native N/A)
        EChartsDemoRegistry.official_custom_gantt_flight,                    // custom   (native N/A)
        EChartsDemoRegistry.official_custom_polar_heatmap,                   // custom
        EChartsDemoRegistry.official_flame_graph,                            // custom   (native N/A)
        EChartsDemoRegistry.official_custom_wind,                            // custom   (native N/A)
        EChartsDemoRegistry.official_custom_gauge,                           // custom   (native N/A)
        EChartsDemoRegistry.official_geo_svg_custom_effect,                  // custom   (native N/A)
        EChartsDemoRegistry.official_pie_parliament_transition,              // custom
        EChartsDemoRegistry.official_circle_packing_with_d3,                 // custom
        EChartsDemoRegistry.official_cycle_plot,                             // custom   (native N/A)
        EChartsDemoRegistry.official_wind_barb,                              // custom   (native N/A)
        EChartsDemoRegistry.official_custom_spiral_race,                     // custom   (native N/A)
        EChartsDemoRegistry.official_dataset_link,                           // dataset
        EChartsDemoRegistry.official_data_transform_sort_bar,                // dataset
        EChartsDemoRegistry.official_dataset_encode0,                        // dataset
        EChartsDemoRegistry.official_dataset_series_layout_by,               // dataset
        EChartsDemoRegistry.official_dataset_simple0,                        // dataset
        EChartsDemoRegistry.official_dataset_simple1,                        // dataset
        EChartsDemoRegistry.official_data_transform_multiple_pie,            // dataset
        EChartsDemoRegistry.official_dataset_default,                        // dataset
        EChartsDemoRegistry.official_dataset_encode1,                        // dataset
        EChartsDemoRegistry.official_area_simple,                            // dataZoom
        EChartsDemoRegistry.official_line_graphic,                           // graphic   (native N/A)
        EChartsDemoRegistry.official_graphic_stroke_animation,               // graphic   (native N/A)
        EChartsDemoRegistry.official_graphic_loading,                        // graphic
        EChartsDemoRegistry.official_pie_rich_text,                          // rich
    ]

    /// The official gallery's chart-type categories, in ITS nav order (`line` … `rich`) — the
    /// official tab's sidebar reads in this order rather than registry order.
    public static let officialCategoryOrder: [String] = [
        "line", "bar", "pie", "scatter", "map", "candlestick", "radar", "boxplot", "heatmap", "graph", "lines", "tree", "treemap", "sunburst", "parallel", "sankey", "funnel", "gauge", "pictorialBar", "themeRiver", "calendar", "matrix", "chord", "custom", "dataset", "dataZoom", "graphic", "rich"
    ]

    /// Examples the official gallery lists under MORE than one chart-type category (`pie-rich-text`
    /// sits under both `pie` and `rich`). We keep one demo file per example and let the sidebar show
    /// it under each — without this, `rich` / `lines` / `dataZoom`, whose examples are ALL
    /// cross-listed, would have no section at all. demo name -> the categories beyond its primary.
    public static let officialAlsoIn: [String: [String]] = [
        "official-area-simple": ["line"],
        "official-bar-rich-text": ["rich"],
        "official-calendar-charts": ["scatter"],
        "official-calendar-graph": ["graph"],
        "official-calendar-heatmap": ["heatmap"],
        "official-calendar-pie": ["pie"],
        "official-calendar-vertical": ["heatmap"],
        "official-custom-calendar-icon": ["calendar"],
        "official-custom-error-scatter": ["dataZoom"],
        "official-custom-gantt-flight": ["dataZoom"],
        "official-custom-hexbin": ["map"],
        "official-data-transform-multiple-pie": ["pie"],
        "official-data-transform-sort-bar": ["bar"],
        "official-dataset-default": ["pie"],
        "official-dataset-encode0": ["bar"],
        "official-dataset-link": ["line", "pie"],
        "official-dataset-series-layout-by": ["bar"],
        "official-dataset-simple0": ["bar"],
        "official-dataset-simple1": ["bar"],
        "official-geo-choropleth-scatter": ["scatter"],
        "official-geo-graph": ["graph"],
        "official-intraday-breaks-1": ["line"],
        "official-intraday-breaks-2": ["line"],
        "official-line-draggable": ["graphic"],
        "official-line-graphic": ["line"],
        "official-line-tooltip-touch": ["dataZoom"],
        "official-lines-airline": ["lines"],
        "official-lines-ny": ["lines"],
        "official-map-iceland-pie": ["pie"],
        "official-matrix-mini-bar-geo": ["bar"],
        "official-matrix-sparkline": ["line"],
        "official-matrix-stock": ["candlestick"],
        "official-pie-nest": ["rich"],
        "official-pie-rich-text": ["pie"],
        "official-scatter-matrix": ["scatter"],
    ]
}
