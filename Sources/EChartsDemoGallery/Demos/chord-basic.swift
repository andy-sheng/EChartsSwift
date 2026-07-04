// chord-basic — a single chord (circular flow) series (no cartesian coord system; box usage). Renders
// on BOTH panes: native (EChartsKit's ChordView draws a Sector arc per node around a circle + a filled
// ribbon ChordPath per edge, positions coming from the chord circular-layout stage) and echarts.js.
// Four nodes a/b/c/d placed on the ring, weighted links drawn as ribbons between their arcs.
extension EChartsDemoRegistry {
    static let demo_chord_basic = EChartsDemo(
        name: "chord-basic", category: "Chord",
        summary: "single chord series, 4 nodes a/b/c/d + weighted links",
        width: 460, height: 360,
        option: [
            "series": [["type": "chord",
                        "center": ["50%", "50%"],
                        "radius": ["60%", "70%"],
                        "padAngle": 3.0,
                        "data": [
                            ["name": "a"],
                            ["name": "b"],
                            ["name": "c"],
                            ["name": "d"]
                        ],
                        "links": [
                            ["source": "a", "target": "b", "value": 5.0],
                            ["source": "a", "target": "c", "value": 3.0],
                            ["source": "b", "target": "c", "value": 4.0],
                            ["source": "b", "target": "d", "value": 2.0],
                            ["source": "c", "target": "d", "value": 6.0]
                        ]] as [String: Any]]
        ])
}
