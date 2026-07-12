// calendar-basic — the CALENDAR coordinate system (the 6th, after cartesian/radar/polar/single/parallel),
// a grid of day cells keyed by DATE. This demo renders the calendar BACKDROP alone: the `calendar`
// component + CalendarView draw the month/day-cell grid (split-line outline Polylines), the per-day
// cell rects, and the day/week/month/year labels (ZRText), with all cell geometry coming from the
// Calendar coord (date → cell [x,y]). Renders on BOTH panes: native (EChartsKit) and echarts.js.
// PORT-NOTE (deferred): a scatter/heatmap series ON the calendar is a follow-up demo; this file
// intentionally renders the calendar backdrop only.
extension EChartsDemoRegistry {
    static let demo_calendar_basic = EChartsDemo(
        name: "calendar-basic", category: "Calendar",
        summary: "calendar coordinate-system backdrop — a one-month day-cell grid with day/month labels",
        width: 520, height: 300,
        option: [
            "calendar": [
                "top": 60.0, "left": 40.0, "right": 40.0,
                "cellSize": ["auto", 24.0] as [Any],
                "range": "2017-02",
                "itemStyle": ["borderWidth": 0.5] as [String: Any],
                "dayLabel": ["firstDay": 1] as [String: Any],
                "monthLabel": ["show": true] as [String: Any],
                "yearLabel": ["show": true] as [String: Any]
            ] as [String: Any]
        ])
}
