// official-line-graphic — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-graphic
// title: Custom Graphic Component / titleCN: 自定义图形组件
//
// A horizontal (value-x / category-y) smooth line of atmospheric temperature vs altitude, overlaid with
// two `graphic` component groups: a 45°-rotated "ECHARTS LINE CHART" banner (a translucent rect + white
// text, `bounding:'raw'`, anchored right/bottom) and a shadowed white callout card whose text wraps via
// `overflow:'break'`, anchored left:'10%' / top:'center'.
//
// DEVIATIONS from the official source:
//   - webOptionJS is the example VERBATIM (all data inline upstream; no $.get, no assets, no timers).
//   - NATIVE PANE ON (nativeSupported: true). Verified pixel-faithful against the reference pane: the
//     `containLabel:true` grid reserves the y-axis "N km" label band, the 45°-rotated `bounding:'raw'`
//     banner ("ECHARTS LINE CHART") anchors by right/bottom, and the shadowed callout text wraps at
//     `width:220` via `overflow:'break'`. Lighting this up required two framework fixes (both aligned to
//     upstream, not worked around): (1) `grid.containLabel` — ported `LegacyGridContainLabel`
//     (installLegacyGridContainLabel.swift + axisHelper.estimateLabelUnionRect), registered by default so
//     the grid shrinks to contain axis labels as echarts.js does; without it the y labels overflowed off
//     the left edge (only " km" showed). (2) graphic `type:'text'` style — a text element's raw
//     `[String:Any]` style bag arriving via `attr(...)` was dropped by Displayable's CommonStyleProps
//     handler; ZRText now overrides `attrKV` to merge it into `textStyle` (mirrors Path.attrKV).
//   - No option key is dropped: every formatter here is a STRING template ('{value} °C',
//     'Temperature : <br/>{b}km : {c}°C'), not a JS closure, so both panes carry the same values.
import Foundation

extension EChartsDemoRegistry {
    static let official_line_graphic = EChartsDemo(
        name: "official-line-graphic", category: "graphic",
        summary: "自定义图形组件 — Custom Graphic Component",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  legend: {
    data: ['Altitude (km) vs Temperature (°C)']
  },
  tooltip: {
    trigger: 'axis',
    formatter: 'Temperature : <br/>{b}km : {c}°C'
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    type: 'value',
    axisLabel: {
      formatter: '{value} °C'
    }
  },
  yAxis: {
    type: 'category',
    axisLine: { onZero: false },
    axisLabel: {
      formatter: '{value} km'
    },
    boundaryGap: true,
    data: ['0', '10', '20', '30', '40', '50', '60', '70', '80']
  },
  graphic: [
    {
      type: 'group',
      rotation: Math.PI / 4,
      bounding: 'raw',
      right: 110,
      bottom: 110,
      z: 100,
      children: [
        {
          type: 'rect',
          left: 'center',
          top: 'center',
          z: 100,
          shape: {
            width: 400,
            height: 50
          },
          style: {
            fill: 'rgba(0,0,0,0.3)'
          }
        },
        {
          type: 'text',
          left: 'center',
          top: 'center',
          z: 100,
          style: {
            fill: '#fff',
            text: 'ECHARTS LINE CHART',
            font: 'bold 26px sans-serif'
          }
        }
      ]
    },
    {
      type: 'group',
      left: '10%',
      top: 'center',
      children: [
        {
          type: 'rect',
          z: 100,
          left: 'center',
          top: 'middle',
          shape: {
            width: 240,
            height: 90
          },
          style: {
            fill: '#fff',
            stroke: '#555',
            lineWidth: 1,
            shadowBlur: 8,
            shadowOffsetX: 3,
            shadowOffsetY: 3,
            shadowColor: 'rgba(0,0,0,0.2)'
          }
        },
        {
          type: 'text',
          z: 100,
          left: 'center',
          top: 'middle',
          style: {
            fill: '#333',
            width: 220,
            overflow: 'break',
            text: 'xAxis represents temperature in °C, yAxis represents altitude in km, An image watermark in the upper right, This text block can be placed in any place',
            font: '14px Microsoft YaHei'
          }
        }
      ]
    }
  ],
  series: [
    {
      name: '高度(km)与气温(°C)变化关系',
      type: 'line',
      smooth: true,
      data: [15, -50, -56.5, -46.5, -22.1, -2.5, -27.7, -55.7, -76.5]
    }
  ]
};
"""#,
        option: [
            "legend": [
                "data": ["Altitude (km) vs Temperature (°C)"]
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                // String template, not a closure — ports verbatim.
                "formatter": "Temperature : <br/>{b}km : {c}°C"
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "axisLabel": [
                    "formatter": "{value} °C"
                ] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "axisLine": ["onZero": false] as [String: Any],
                "axisLabel": [
                    "formatter": "{value} km"
                ] as [String: Any],
                "boundaryGap": true,
                "data": ["0", "10", "20", "30", "40", "50", "60", "70", "80"]
            ] as [String: Any],
            "graphic": lineGraphicElements,
            "series": [
                [
                    "name": "高度(km)与气温(°C)变化关系",
                    "type": "line",
                    "smooth": true,
                    "data": [15.0, -50.0, -56.5, -46.5, -22.1, -2.5, -27.7, -55.7, -76.5]
                ] as [String: Any]
            ]
        ])
}

// The two `graphic` groups, hoisted out of the option literal: nested heterogeneous dictionaries this
// deep blow up Swift's type-checker inside a big literal (annotate every level, hoist the tree).
// Name is demo-specific on purpose — top-level `private` is file-scoped, but a bare `graphicElements`
// would read as the shared one the moment another demo grows a `graphic` block.
private let lineGraphicElements: [[String: Any]] = [
    // 1. The 45°-rotated watermark banner. `bounding: 'raw'` = position by the group's own (unrotated)
    //    raw rect, so right/bottom anchor the banner's pre-rotation box.
    [
        "type": "group",
        "rotation": Double.pi / 4,   // upstream: Math.PI / 4
        "bounding": "raw",
        "right": 110.0,
        "bottom": 110.0,
        "z": 100.0,
        "children": [
            [
                "type": "rect",
                "left": "center",
                "top": "center",
                "z": 100.0,
                "shape": [
                    "width": 400.0,
                    "height": 50.0
                ] as [String: Any],
                "style": [
                    "fill": "rgba(0,0,0,0.3)"
                ] as [String: Any]
            ] as [String: Any],
            [
                "type": "text",
                "left": "center",
                "top": "center",
                "z": 100.0,
                "style": [
                    "fill": "#fff",
                    "text": "ECHARTS LINE CHART",
                    "font": "bold 26px sans-serif"
                ] as [String: Any]
            ] as [String: Any]
        ]
    ],
    // 2. The shadowed callout card: a white rect + a text block wrapped at width 220 (overflow: 'break').
    [
        "type": "group",
        "left": "10%",
        "top": "center",
        "children": [
            [
                "type": "rect",
                "z": 100.0,
                "left": "center",
                "top": "middle",
                "shape": [
                    "width": 240.0,
                    "height": 90.0
                ] as [String: Any],
                "style": [
                    "fill": "#fff",
                    "stroke": "#555",
                    "lineWidth": 1.0,
                    "shadowBlur": 8.0,
                    "shadowOffsetX": 3.0,
                    "shadowOffsetY": 3.0,
                    "shadowColor": "rgba(0,0,0,0.2)"
                ] as [String: Any]
            ] as [String: Any],
            [
                "type": "text",
                "z": 100.0,
                "left": "center",
                "top": "middle",
                "style": [
                    "fill": "#333",
                    "width": 220.0,
                    "overflow": "break",
                    "text": "xAxis represents temperature in °C, yAxis represents altitude in km, An image watermark in the upper right, This text block can be placed in any place",
                    "font": "14px Microsoft YaHei"
                ] as [String: Any]
            ] as [String: Any]
        ]
    ]
]
