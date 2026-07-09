// dark-basic — a bar chart rendered with the built-in DARK theme's palette.
//
// The gallery renders a demo's `option` through BOTH panes (native EChartsKit and the real
// echarts.js dist); the echarts.js dist does not bundle the separate `theme/dark` module, so this
// demo INLINES the dark theme's key visuals (backgroundColor + light textStyle + dark axis colors,
// taken straight from `tokens.darkColor`) into the option so both panes render an identical dark
// chart. The full theme/dark.ts dictionary + `ECharts(theme:"dark")` merge path is exercised by
// ThemeLocaleTests (dark backgroundColor + light textStyle via GlobalModel.mergeTheme).
import EChartsKit

extension EChartsDemoRegistry {
    static let demo_dark_basic: EChartsDemo = {
        let c = tokens.darkColor
        return EChartsDemo(
            name: "dark-basic", category: "Theme",
            summary: "Bar chart on the built-in dark theme palette (dark bg + light text)",
            width: 400, height: 300,
            option: [
                "backgroundColor": c.background,
                "textStyle": ["color": c.secondary] as [String: Any],
                "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                "xAxis": [
                    "type": "category",
                    "data": ["A", "B", "C", "D"],
                    "axisLine": ["lineStyle": ["color": c.axisLine]] as [String: Any],
                    "axisLabel": ["color": c.axisLabel] as [String: Any]
                ] as [String: Any],
                "yAxis": [
                    "type": "value",
                    "axisLabel": ["color": c.axisLabel] as [String: Any],
                    "splitLine": ["lineStyle": ["color": c.axisSplitLine]] as [String: Any]
                ] as [String: Any],
                "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
            ])
    }()
}
