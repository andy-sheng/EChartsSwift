// Ported from echarts/src/theme/dark.ts — keep in sync with upstream.
//
// The built-in "dark" theme. Upstream builds a plain option object from `tokens.darkColor`
// and default-exports it; `echarts.registerTheme('dark', ...)` then makes it selectable by
// name. The Swift port exposes the same nested `[String: Any]` tree via `darkTheme.theme`,
// which `GlobalModel.mergeTheme` merges under every non-component option key.
//
// upstream: import tokens from '../visual/tokens';
//           const color = tokens.darkColor;

// upstream: const color = tokens.darkColor;
private let color = tokens.darkColor
// upstream: const backgroundColor = color.background;
private let backgroundColor = color.background

// upstream: const axisCommon = function () { return { ... }; };
private func axisCommon() -> [String: Any] {
    return [
        "axisLine": [
            "lineStyle": [
                "color": color.axisLine
            ]
        ],
        "splitLine": [
            "lineStyle": [
                "color": color.axisSplitLine
            ]
        ],
        "splitArea": [
            "areaStyle": [
                "color": [
                    color.backgroundTint,
                    color.backgroundTransparent
                ]
            ]
        ],
        "minorSplitLine": [
            "lineStyle": [
                "color": color.axisMinorSplitLine
            ]
        ],
        "axisLabel": [
            "color": color.axisLabel
        ],
        "axisName": [String: Any]()
    ]
}

// upstream: const matrixAxis = { label, itemStyle, dividerLineStyle };
private let matrixAxis: [String: Any] = [
    "label": [
        "color": color.secondary
    ],
    "itemStyle": [
        "borderColor": color.borderTint
    ],
    "dividerLineStyle": [
        "color": color.border
    ]
]

// upstream:
//   radar = axisCommon();
//   radar.axisName = { color: color.axisLabel };
//   radar.axisLine.lineStyle.color = color.neutral20;
private func radarTheme() -> [String: Any] {
    var radar = axisCommon()
    radar["axisName"] = ["color": color.axisLabel]
    radar["axisLine"] = ["lineStyle": ["color": color.neutral20]]
    return radar
}

// upstream: (theme.categoryAxis.splitLine as any).show = false;
private func categoryAxisTheme() -> [String: Any] {
    var categoryAxis = axisCommon()
    var splitLine = (categoryAxis["splitLine"] as? [String: Any]) ?? [:]
    splitLine["show"] = false
    categoryAxis["splitLine"] = splitLine
    return categoryAxis
}

// upstream: const theme = { darkMode: true, color, backgroundColor, ... }; export default theme;
public enum darkTheme {
    public static let theme: [String: Any] = [
        "darkMode": true,

        "color": color.theme,
        "backgroundColor": backgroundColor,
        "axisPointer": [
            "lineStyle": [
                "color": color.border
            ],
            "crossStyle": [
                "color": color.borderShade
            ],
            "label": [
                "color": color.tertiary
            ]
        ],
        "legend": [
            "textStyle": [
                "color": color.secondary
            ],
            "pageTextStyle": [
                "color": color.tertiary
            ]
        ],
        "textStyle": [
            "color": color.secondary
        ],
        "title": [
            "textStyle": [
                "color": color.primary
            ],
            "subtextStyle": [
                "color": color.quaternary
            ]
        ],
        "toolbox": [
            "iconStyle": [
                "borderColor": color.accent50
            ],
            "feature": [
                "dataView": [
                    "backgroundColor": backgroundColor,
                    "textColor": color.primary,
                    "textareaColor": color.background,
                    "textareaBorderColor": color.border,
                    "buttonColor": color.accent50,
                    "buttonTextColor": color.neutral00
                ]
            ]
        ],
        "tooltip": [
            "backgroundColor": color.neutral20,
            "defaultBorderColor": color.border,
            "textStyle": [
                "color": color.tertiary
            ]
        ],
        "dataZoom": [
            "borderColor": color.accent10,
            "textStyle": [
                "color": color.tertiary
            ],
            "brushStyle": [
                "color": color.backgroundTint
            ],
            "handleStyle": [
                "color": color.neutral00,
                "borderColor": color.accent20
            ],
            "moveHandleStyle": [
                "color": color.accent40
            ],
            "emphasis": [
                "handleStyle": [
                    "borderColor": color.accent50
                ]
            ],
            "dataBackground": [
                "lineStyle": [
                    "color": color.accent30
                ],
                "areaStyle": [
                    "color": color.accent20
                ]
            ],
            "selectedDataBackground": [
                "lineStyle": [
                    "color": color.accent50
                ],
                "areaStyle": [
                    "color": color.accent30
                ]
            ]
        ],
        "visualMap": [
            "textStyle": [
                "color": color.secondary
            ],
            "handleStyle": [
                "borderColor": color.neutral30
            ]
        ],
        "timeline": [
            "lineStyle": [
                "color": color.accent10
            ],
            "label": [
                "color": color.tertiary
            ],
            "controlStyle": [
                "color": color.accent30,
                "borderColor": color.accent30
            ]
        ],
        "calendar": [
            "itemStyle": [
                "color": color.neutral00,
                "borderColor": color.neutral20
            ],
            "dayLabel": [
                "color": color.tertiary
            ],
            "monthLabel": [
                "color": color.secondary
            ],
            "yearLabel": [
                "color": color.secondary
            ]
        ],
        "matrix": [
            "x": matrixAxis,
            "y": matrixAxis,
            "backgroundColor": [
                "borderColor": color.axisLine
            ],
            "body": [
                "itemStyle": [
                    "borderColor": color.borderTint
                ]
            ]
        ],
        "timeAxis": axisCommon(),
        "logAxis": axisCommon(),
        "valueAxis": axisCommon(),
        "categoryAxis": categoryAxisTheme(),

        "line": [
            "symbol": "circle"
        ],
        "graph": [
            "color": color.theme
        ],
        "gauge": [
            "title": [
                "color": color.secondary
            ],
            "axisLine": [
                "lineStyle": [
                    "color": [[1, color.neutral05]]
                ]
            ],
            "axisLabel": [
                "color": color.axisLabel
            ],
            "detail": [
                "color": color.primary
            ]
        ],
        "candlestick": [
            "itemStyle": [
                "color": "#f64e56",
                "color0": "#54ea92",
                "borderColor": "#f64e56",
                "borderColor0": "#54ea92"
            ]
        ],
        "funnel": [
            "itemStyle": [
                "borderColor": color.background
            ]
        ],
        "radar": radarTheme(),
        "treemap": [
            "breadcrumb": [
                "itemStyle": [
                    "color": color.neutral20,
                    "textStyle": [
                        "color": color.secondary
                    ]
                ],
                "emphasis": [
                    "itemStyle": [
                        "color": color.neutral30
                    ]
                ]
            ]
        ],
        "sunburst": [
            "itemStyle": [
                "borderColor": color.background
            ]
        ],
        "map": [
            "itemStyle": [
                "borderColor": color.border,
                "areaColor": color.neutral10
            ],
            "label": [
                "color": color.tertiary
            ],
            "emphasis": [
                "label": [
                    "color": color.primary
                ],
                "itemStyle": [
                    "areaColor": color.highlight
                ]
            ],
            "select": [
                "label": [
                    "color": color.primary
                ],
                "itemStyle": [
                    "areaColor": color.highlight
                ]
            ]
        ],
        "geo": [
            "itemStyle": [
                "borderColor": color.border,
                "areaColor": color.neutral10
            ],
            "emphasis": [
                "label": [
                    "color": color.primary
                ],
                "itemStyle": [
                    "areaColor": color.highlight
                ]
            ],
            "select": [
                "label": [
                    "color": color.primary
                ],
                "itemStyle": [
                    "color": color.highlight
                ]
            ]
        ]
    ]
}
