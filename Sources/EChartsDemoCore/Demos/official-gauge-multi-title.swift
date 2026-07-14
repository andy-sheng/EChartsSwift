// official-gauge-multi-title — replica of https://echarts.apache.org/examples/zh/editor.html?c=gauge-multi-title
// title: Multi Title Gauge / titleCN: 多标题仪表盘
// One `gauge` series carrying THREE data items ('Good' / 'Better' / 'Perfect'), each with its own
// title + detail placed side by side under the dial via per-item `offsetCenter`; overlapping roundCap
// progress arcs, a shared anchor, and a custom `path://` pointer icon.
//
// THE 2s RANDOMIZE IS PORTED, on both panes. The web pane runs the example's own
// `setInterval(function () { …random…; myChart.setOption({ series: [{ data: gaugeData }] }); }, 2000)`
// verbatim; the native pane replays the same timeline through `drive` (see EChartsDemoChart), re-rolling
// all three dials' values and MERGING them back in (upstream's setOption has no `true` second argument).
// The still-frame PNG paths capture the first frame — values 20 / 40 / 60 — and neuter the timer, so a
// snapshot stays deterministic. Because each pane draws its OWN random numbers, the two are not expected
// to agree digit-for-digit while live; what must agree is the three side-by-side title/detail blocks, the
// overlapping roundCap progress arcs and the pointer geometry.
//
// DEVIATIONS from the official source:
//   - The TS type argument on `myChart.setOption<echarts.EChartsOption>({...})` is dropped (a classic
//     script cannot parse it), as is the trailing `export {}`. Nothing else in the JS changed.
//   - Native pane: `detail.formatter: '{value}%'` is a STRING template, not a closure, so it ports
//     as-is — no key omitted from the Swift option.
import Foundation

// The three dials, as upstream's `gaugeData`: value + name + where this item's title/detail sit
// relative to the gauge centre. Upstream mutates the values in place every 2s and re-sends the whole
// array (offsets included), so `drive` rebuilds it the same way.
private func gaugeMultiTitleData(_ values: [Double]) -> [[String: Any]] {
    [
        [
            "value": values[0],
            "name": "Good",
            "title": ["offsetCenter": ["-40%", "80%"]] as [String: Any],
            "detail": ["offsetCenter": ["-40%", "95%"]] as [String: Any]
        ] as [String: Any],
        [
            "value": values[1],
            "name": "Better",
            "title": ["offsetCenter": ["0%", "80%"]] as [String: Any],
            "detail": ["offsetCenter": ["0%", "95%"]] as [String: Any]
        ] as [String: Any],
        [
            "value": values[2],
            "name": "Perfect",
            "title": ["offsetCenter": ["40%", "80%"]] as [String: Any],
            "detail": ["offsetCenter": ["40%", "95%"]] as [String: Any]
        ] as [String: Any]
    ]
}

// `+(Math.random() * 100).toFixed(2)` — a value in [0, 100), rounded to 2 decimals.
// Kept in the example's two steps so it cannot be misread as a double scaling: `Math.random() * 100`
// first, then `.toFixed(2)` (which is `(x * 100).rounded() / 100`).
private func gaugeMultiTitleRandomValue() -> Double {
    let raw = Double.random(in: 0..<1) * 100
    return (raw * 100).rounded() / 100
}

extension EChartsDemoRegistry {
    static let official_gauge_multi_title = EChartsDemo(
        name: "official-gauge-multi-title", category: "gauge",
        summary: "多标题仪表盘 — Multi Title Gauge",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const gaugeData = [
  {
    value: 20,
    name: 'Good',
    title: {
      offsetCenter: ['-40%', '80%']
    },
    detail: {
      offsetCenter: ['-40%', '95%']
    }
  },
  {
    value: 40,
    name: 'Better',
    title: {
      offsetCenter: ['0%', '80%']
    },
    detail: {
      offsetCenter: ['0%', '95%']
    }
  },
  {
    value: 60,
    name: 'Perfect',
    title: {
      offsetCenter: ['40%', '80%']
    },
    detail: {
      offsetCenter: ['40%', '95%']
    }
  }
];

option = {
  series: [
    {
      type: 'gauge',
      anchor: {
        show: true,
        showAbove: true,
        size: 18,
        itemStyle: {
          color: '#FAC858'
        }
      },
      pointer: {
        icon:
          'path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z',
        width: 8,
        length: '80%',
        offsetCenter: [0, '8%']
      },

      progress: {
        show: true,
        overlap: true,
        roundCap: true
      },
      axisLine: {
        roundCap: true
      },
      data: gaugeData,
      title: {
        fontSize: 14
      },
      detail: {
        width: 40,
        height: 14,
        fontSize: 14,
        color: '#fff',
        backgroundColor: 'inherit',
        borderRadius: 3,
        formatter: '{value}%'
      }
    }
  ]
};

setInterval(function () {
  gaugeData[0].value = +(Math.random() * 100).toFixed(2);
  gaugeData[1].value = +(Math.random() * 100).toFixed(2);
  gaugeData[2].value = +(Math.random() * 100).toFixed(2);
  myChart.setOption({
    series: [
      {
        data: gaugeData
      }
    ]
  });
}, 2000);
"""#,
        // The native pane's half of the same timeline: re-roll the three values every 2s and merge the
        // fresh data in — upstream's `myChart.setOption({ series: [{ data: gaugeData }] })` (no `true`),
        // so the series' anchor/pointer/progress/detail styling must survive the update.
        drive: { chart in
            chart.every(2) {
                let values = [gaugeMultiTitleRandomValue(),
                              gaugeMultiTitleRandomValue(),
                              gaugeMultiTitleRandomValue()]
                chart.setOption(
                    ["series": [["data": gaugeMultiTitleData(values)] as [String: Any]]],
                    notMerge: false)
            }
        },
        option: [
            "series": [
                [
                    "type": "gauge",
                    "anchor": [
                        "show": true,
                        "showAbove": true,
                        "size": 18.0,
                        "itemStyle": ["color": "#FAC858"] as [String: Any]
                    ] as [String: Any],
                    "pointer": [
                        "icon": "path://M2.9,0.7L2.9,0.7c1.4,0,2.6,1.2,2.6,2.6v115c0,1.4-1.2,2.6-2.6,2.6l0,0c-1.4,0-2.6-1.2-2.6-2.6V3.3C0.3,1.9,1.4,0.7,2.9,0.7z",
                        "width": 8.0,
                        "length": "80%",
                        "offsetCenter": [0.0, "8%"] as [Any]
                    ] as [String: Any],
                    "progress": [
                        "show": true,
                        "overlap": true,
                        "roundCap": true
                    ] as [String: Any],
                    "axisLine": ["roundCap": true] as [String: Any],
                    // Upstream's initial `gaugeData` — 20 / 40 / 60, before the first interval fires.
                    "data": gaugeMultiTitleData([20, 40, 60]),
                    "title": ["fontSize": 14.0] as [String: Any],
                    "detail": [
                        "width": 40.0,
                        "height": 14.0,
                        "fontSize": 14.0,
                        "color": "#fff",
                        "backgroundColor": "inherit",
                        "borderRadius": 3.0,
                        "formatter": "{value}%"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}
