// timeline-basic — the bottom timeline playhead switching between option snapshots. Exercises the
//   `{ baseOption, options:[...], timeline:{...} }` merge (OptionManager resolves options[currentIndex]
//   over baseOption) + the SliderTimelineView static render (axis line + per-index tick symbols + the
//   current-index checkpoint + prev/next/play control buttons). Play AUTO-ADVANCE is deferred.
extension EChartsDemoRegistry {
    static let demo_timeline_basic = EChartsDemo(
        name: "timeline-basic", category: "Component",
        summary: "timeline playhead switching option snapshots (currentIndex merge)",
        width: 520, height: 400,
        option: [
            "baseOption": [
                "title": ["text": "Timeline", "left": "center"] as [String: Any],
                "timeline": [
                    "axisType": "time",
                    "currentIndex": 1,
                    "left": "10%",
                    "right": "10%",
                    "bottom": 0.0,
                    "autoPlay": false,
                    "data": ["2010-01-01", "2011-01-01", "2012-01-01"]
                ] as [String: Any],
                "grid": ["left": 55.0, "top": 60.0, "width": 400.0, "height": 260.0] as [String: Any],
                "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
                "yAxis": ["type": "value"] as [String: Any],
                "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
            ] as [String: Any],
            "options": [
                [
                    "title": ["text": "Year 2010"] as [String: Any],
                    "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
                ] as [String: Any],
                [
                    "title": ["text": "Year 2011"] as [String: Any],
                    "series": [["type": "bar", "data": [40.0, 30.0, 20.0, 10.0]] as [String: Any]]
                ] as [String: Any],
                [
                    "title": ["text": "Year 2012"] as [String: Any],
                    "series": [["type": "bar", "data": [25.0, 35.0, 15.0, 45.0]] as [String: Any]]
                ] as [String: Any]
            ]
        ])
}
