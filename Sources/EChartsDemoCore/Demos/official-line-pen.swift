// official-line-pen — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-pen
// title: Click to Add Points / titleCN: 点击添加折线图拐点
// A smoothed value-value line through 5 seed points, drawn with 20px symbols on a fixed
// [-60,20] x [0,40] grid; in the official example clicking inside the grid appends the clicked
// point to the series.
// DEVIATIONS:
//   - Interaction dropped (both panes). The official source ends with `zr.on('click', ...)` (append
//     the clicked point via convertFromPixel + setOption) and `zr.on('mousemove', ...)` (swap the
//     cursor to 'copy' inside the grid). The gallery renders ONE static frame, so only the initial
//     5-point state is ported. Keeping the handlers would also blank the reference pane: they call
//     `myChart`, which WebPage.swift declares only AFTER the option script, so `myChart.getZr()`
//     would throw and abort the script before echarts.init runs.
//   - TS type annotations (`function (params: any)`) stripped from the tooltip formatter — the
//     reference pane is a classic script, where they are a SyntaxError.
//   - Native pane: tooltip.formatter omitted (JS closure; see PORT-NOTE). Everything the static
//     frame actually shows — title, grid, both value axes with axisLine.onZero:false, and the
//     smooth 20px-symbol line — is ported.
extension EChartsDemoRegistry {
    static let official_line_pen = EChartsDemo(
        name: "official-line-pen", category: "line",
        summary: "点击添加折线图拐点 — Click to Add Points",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const symbolSize = 20;
const data = [
  [15, 0],
  [-50, 10],
  [-56.5, 20],
  [-46.5, 30],
  [-22.1, 40]
];

option = {
  title: {
    text: 'Click to Add Points'
  },
  tooltip: {
    formatter: function (params) {
      var data = params.data || [0, 0];
      return data[0].toFixed(2) + ', ' + data[1].toFixed(2);
    }
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    min: -60,
    max: 20,
    type: 'value',
    axisLine: { onZero: false }
  },
  yAxis: {
    min: 0,
    max: 40,
    type: 'value',
    axisLine: { onZero: false }
  },
  series: [
    {
      id: 'a',
      type: 'line',
      smooth: true,
      symbolSize: symbolSize,
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Click to Add Points"
            ] as [String: Any],
            // PORT-NOTE: tooltip.formatter omitted — the JS closure rendered the hovered point as
            // `x.toFixed(2) + ', ' + y.toFixed(2)` (defaulting to [0, 0] when params.data was absent).
            "tooltip": [:] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "min": -60.0,
                "max": 20.0,
                "type": "value",
                "axisLine": ["onZero": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "min": 0.0,
                "max": 40.0,
                "type": "value",
                "axisLine": ["onZero": false] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "id": "a",
                    "type": "line",
                    "smooth": true,
                    "symbolSize": 20.0,
                    "data": linePenData
                ] as [String: Any]
            ]
        ])
}

// The 5 seed points ([x, y] on a value-value grid); the official example appends more on click.
private let linePenData: [[Double]] = [
    [15, 0],
    [-50, 10],
    [-56.5, 20],
    [-46.5, 30],
    [-22.1, 40]
]
