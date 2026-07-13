// official-confidence-band — replica of https://echarts.apache.org/examples/zh/editor.html?c=confidence-band
// title: Confidence Band / titleCN: 置信带
// A grey confidence band (lower bound `l` + the span `u - l`, two invisible-stroke line series STACKED
// under `stack: 'confidence-band'`, the upper one carrying the areaStyle) with the actual `value` line
// drawn on top. Every series is shifted by `base = -floor(min(l))` so the stack stays non-negative;
// the four JS formatters shift it back and render percentages.
//
// DEVIATIONS from the official source:
//   - DATA INLINED: upstream does `$.get(ROOT_PATH + '/data/asset/data/confidence-band.json', ...)` and
//     builds the option inside the callback. The page has no network, so the 91-point asset is vendored
//     at assets/data/confidence-band.json and read via Upstream.repoRoot: the web pane gets the raw JSON
//     text spliced in as `var data = ...` (the callback BODY is otherwise verbatim), the native pane gets
//     it parsed into typed arrays. `myChart.showLoading()/hideLoading()` and the `$.get` wrapper are gone.
//   - NATIVE PANE: the four formatter closures (tooltip + the two axisLabels + the y axisPointer label)
//     cannot be expressed in a Swift option, so they are omitted — see the PORT-NOTE lines. Consequence:
//     the native axes label the RAW shifted values (value + base) rather than `(v - base) * 100 + '%'`,
//     and the x-axis prints full ISO dates instead of the M-D short form for all but the first tick.
//     The GEOMETRY (band, stack, line) is identical; only the tick/tooltip TEXT differs.
import Foundation

// The 91 daily points of the MetricsGraphics.js confidence-band sample. Parsed ONCE from the repo asset;
// a parse failure degrades to no data (the pane renders empty axes rather than crashing).
private struct ConfidenceBandPoint {
    let value: Double
    let date: String
    let l: Double
    let u: Double
}

private let confidenceBandPoints: [ConfidenceBandPoint] = {
    guard let data = try? Data(contentsOf: confidenceBandAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return arr.compactMap { item in
        guard let value = item["value"] as? Double, let date = item["date"] as? String,
              let l = item["l"] as? Double, let u = item["u"] as? Double else { return nil }
        return ConfidenceBandPoint(value: value, date: date, l: l, u: u)
    }
}()

private let confidenceBandAssetURL = Upstream.repoRoot.appendingPathComponent("assets/data/confidence-band.json")

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body
// against the exact bytes the native pane parses.
private let confidenceBandJSONText: String =
    (try? String(contentsOf: confidenceBandAssetURL, encoding: .utf8)) ?? "[]"

// base = -data.reduce((min, val) => Math.floor(Math.min(min, val.l)), Infinity)  →  3 for this asset.
// Every series is shifted up by it so the `l` + `u - l` stack never goes negative.
private let confidenceBandBase: Double = -(confidenceBandPoints.map { $0.l }.min()?.rounded(.down) ?? 0)

private let confidenceBandDates: [String] = confidenceBandPoints.map { $0.date }
private let confidenceBandLower: [Double] = confidenceBandPoints.map { $0.l + confidenceBandBase }
private let confidenceBandSpan: [Double] = confidenceBandPoints.map { $0.u - $0.l }
private let confidenceBandValues: [Double] = confidenceBandPoints.map { $0.value + confidenceBandBase }

extension EChartsDemoRegistry {
    static let official_confidence_band = EChartsDemo(
        name: "official-confidence-band", category: "line",
        summary: "置信带 — Confidence Band",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var data = \#(confidenceBandJSONText);

var base = -data.reduce(function (min, val) {
  return Math.floor(Math.min(min, val.l));
}, Infinity);
option = {
  title: {
    text: 'Confidence Band',
    subtext: 'Example in MetricsGraphics.js',
    left: 'center'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'cross',
      animation: false,
      label: {
        backgroundColor: '#ccc',
        borderColor: '#aaa',
        borderWidth: 1,
        shadowBlur: 0,
        shadowOffsetX: 0,
        shadowOffsetY: 0,

        color: '#222'
      }
    },
    formatter: function (params) {
      return (
        params[2].name +
        '<br />' +
        ((params[2].value - base) * 100).toFixed(1) +
        '%'
      );
    }
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    type: 'category',
    data: data.map(function (item) {
      return item.date;
    }),
    axisLabel: {
      formatter: function (value, idx) {
        var date = new Date(value);
        return idx === 0
          ? value
          : [date.getMonth() + 1, date.getDate()].join('-');
      }
    },
    boundaryGap: false
  },
  yAxis: {
    axisLabel: {
      formatter: function (val) {
        return (val - base) * 100 + '%';
      }
    },
    axisPointer: {
      label: {
        formatter: function (params) {
          return ((params.value - base) * 100).toFixed(1) + '%';
        }
      }
    },
    splitNumber: 3
  },
  series: [
    {
      name: 'L',
      type: 'line',
      data: data.map(function (item) {
        return item.l + base;
      }),
      lineStyle: {
        opacity: 0
      },
      stack: 'confidence-band',
      symbol: 'none'
    },
    {
      name: 'U',
      type: 'line',
      data: data.map(function (item) {
        return item.u - item.l;
      }),
      lineStyle: {
        opacity: 0
      },
      areaStyle: {
        color: '#ccc'
      },
      stack: 'confidence-band',
      symbol: 'none'
    },
    {
      type: 'line',
      data: data.map(function (item) {
        return item.value + base;
      }),
      itemStyle: {
        color: '#333'
      },
      showSymbol: false
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Confidence Band",
                "subtext": "Example in MetricsGraphics.js",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "cross",
                    "animation": false,
                    "label": [
                        "backgroundColor": "#ccc",
                        "borderColor": "#aaa",
                        "borderWidth": 1.0,
                        "shadowBlur": 0.0,
                        "shadowOffsetX": 0.0,
                        "shadowOffsetY": 0.0,
                        "color": "#222"
                    ] as [String: Any]
                ] as [String: Any]
                // PORT-NOTE: tooltip.formatter omitted — the JS closure returned the third series'
                // category name plus `((params[2].value - base) * 100).toFixed(1) + '%'`, i.e. the
                // actual (un-shifted) value as a one-decimal percentage.
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": confidenceBandDates,
                "boundaryGap": false
                // PORT-NOTE: xAxis.axisLabel.formatter omitted — the JS closure printed the first tick
                // as the full ISO date and every other tick as `M-D` (new Date(value), month+1 + '-' + day).
            ] as [String: Any],
            "yAxis": [
                "splitNumber": 3.0
                // PORT-NOTE: yAxis.axisLabel.formatter omitted — the JS closure un-shifted each tick and
                // rendered it as a percentage: `(val - base) * 100 + '%'`.
                // PORT-NOTE: yAxis.axisPointer.label.formatter omitted — same un-shift, one decimal:
                // `((params.value - base) * 100).toFixed(1) + '%'`.
            ] as [String: Any],
            "series": [
                [
                    "name": "L",
                    "type": "line",
                    "data": confidenceBandLower,
                    "lineStyle": ["opacity": 0.0] as [String: Any],
                    "stack": "confidence-band",
                    "symbol": "none"
                ] as [String: Any],
                [
                    "name": "U",
                    "type": "line",
                    "data": confidenceBandSpan,
                    "lineStyle": ["opacity": 0.0] as [String: Any],
                    "areaStyle": ["color": "#ccc"] as [String: Any],
                    "stack": "confidence-band",
                    "symbol": "none"
                ] as [String: Any],
                [
                    "type": "line",
                    "data": confidenceBandValues,
                    "itemStyle": ["color": "#333"] as [String: Any],
                    "showSymbol": false
                ] as [String: Any]
            ]
        ])
}
