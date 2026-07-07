// sunburst-basic — a single sunburst series (no coordinate system; hierarchical tree + angle/radius
// layout, box-like usage like pie). Renders on BOTH panes: native (EChartsKit's SunburstView draws a
// Sector per tree node) and echarts.js.
extension EChartsDemoRegistry {
    static let demo_sunburst_basic = EChartsDemo(
        name: "sunburst-basic", category: "Sunburst",
        summary: "single sunburst series, 2-level hierarchy",
        width: 400, height: 400,
        option: [
            "series": [["type": "sunburst", "radius": ["0%", "90%"],
                        "data": [
                            ["name": "Grandpa", "children": [
                                ["name": "Uncle Leo", "value": 15.0, "children": [
                                    ["name": "Cousin Jack", "value": 2.0],
                                    ["name": "Cousin Mary", "value": 5.0],
                                    ["name": "Cousin Ben", "value": 4.0]
                                ]],
                                ["name": "Father", "value": 10.0, "children": [
                                    ["name": "Me", "value": 5.0],
                                    ["name": "Brother Peter", "value": 1.0]
                                ]]
                            ]],
                            ["name": "Nancy", "children": [
                                ["name": "Uncle Nike", "value": 10.0, "children": [
                                    ["name": "Cousin Betty", "value": 1.0],
                                    ["name": "Cousin Jenny", "value": 2.0]
                                ]]
                            ]]
                        ]] as [String: Any]]
        ])
}
