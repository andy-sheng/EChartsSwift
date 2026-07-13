// official-mix-zoom-on-value — replica of https://echarts.apache.org/examples/zh/editor.html?c=mix-zoom-on-value
// title: Mix Zoom On Value / titleCN: 多数值轴轴缩放
// Obama's 2012 budget proposal: 447 line-items as two bar series (Budget 2011 / Budget 2012), with
// THREE dataZoom components — a horizontal slider + an `inside` zoom on the category x-axis (both
// windowed to start:94 / end:100, i.e. the last ~6% of the items), and a VERTICAL slider on the value
// y-axis (`yAxisIndex: 0`, `filterMode: 'empty'`, pinned at `left: '93%'`) — which is the point of the
// example: zooming a VALUE axis, not just the category axis.
//
// DEVIATIONS from the official source:
//   - Data inlined. Upstream wraps the whole option in `$.get(ROOT_PATH + '/data/asset/data/
//     obama_budget_proposal_2012.list.json', function (obama_budget_2012) { ... })`. There is no
//     network in the gallery page, so the asset is vendored at assets/data/obama_budget_proposal_2012.list.json
//     and read from disk via Upstream.repoRoot: the native pane consumes the parsed dict; the web pane
//     gets the raw JSON text spliced in as `var obama_budget_2012 = {...};` above an otherwise verbatim
//     callback body. `myChart.showLoading()/hideLoading()` are dropped with the fetch.
//   - NATIVE pane omits `yAxis[0].axisLabel.formatter` (a JS closure — see the PORT-NOTE below); its
//     y-axis labels are therefore raw dollar amounts, not the web pane's comma-grouped thousands.
//   - `budget2011List` contains JSON `null`s (items with no 2011 counterpart). They are preserved as
//     NSNull() — EChartsKit's null convention — so both panes leave those bars empty, as upstream does.
import Foundation

// The upstream asset, verbatim. Read ONCE from the repo (the same #filePath-relative read WebPage.swift
// uses for the echarts dist, so it resolves on macOS and the iOS simulator alike). A read failure degrades
// to an empty-list payload — both panes then render an empty chart rather than crashing.
private let obamaBudgetJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/obama_budget_proposal_2012.list.json")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        return #"{"names":[],"budget2011List":[],"budget2012List":[]}"#
    }
    return text
}()

private let obamaBudgetJSON: [String: Any] = {
    guard let data = obamaBudgetJSONText.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["names": [] as [Any], "budget2011List": [] as [Any], "budget2012List": [] as [Any]]
    }
    return obj
}()

// JSONSerialization hands back NSNumber / NSNull; normalise to Double / NSNull() so the option bag holds
// exactly what a hand-written Swift option would (numbers are Double; JSON null stays the null sentinel).
private func obamaBudgetList(_ key: String) -> [Any] {
    guard let raw = obamaBudgetJSON[key] as? [Any] else { return [] }
    return raw.map { item -> Any in
        if item is NSNull { return NSNull() }
        if let n = item as? NSNumber { return Double(truncating: n) }
        return item
    }
}

private let obamaBudgetNames: [String] = (obamaBudgetJSON["names"] as? [String]) ?? []
private let obamaBudget2011List: [Any] = obamaBudgetList("budget2011List")
private let obamaBudget2012List: [Any] = obamaBudgetList("budget2012List")

extension EChartsDemoRegistry {
    static let official_mix_zoom_on_value = EChartsDemo(
        name: "official-mix-zoom-on-value", category: "bar",
        summary: "多数值轴轴缩放 — Mix Zoom On Value",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var obama_budget_2012 = \#(obamaBudgetJSONText);

option = {
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow',
      label: {
        show: true
      }
    }
  },
  toolbox: {
    show: true,
    feature: {
      mark: { show: true },
      dataView: { show: true, readOnly: false },
      magicType: { show: true, type: ['line', 'bar'] },
      restore: { show: true },
      saveAsImage: { show: true }
    }
  },
  calculable: true,
  legend: {
    data: ['Growth', 'Budget 2011', 'Budget 2012'],
    itemGap: 5
  },
  grid: {
    top: '12%',
    left: '1%',
    right: '10%',
    containLabel: true
  },
  xAxis: [
    {
      type: 'category',
      data: obama_budget_2012.names
    }
  ],
  yAxis: [
    {
      type: 'value',
      name: 'Budget (million USD)',
      axisLabel: {
        formatter: function (a) {
          a = +a;
          return isFinite(a) ? echarts.format.addCommas(+a / 1000) : '';
        }
      }
    }
  ],
  dataZoom: [
    {
      show: true,
      start: 94,
      end: 100
    },
    {
      type: 'inside',
      start: 94,
      end: 100
    },
    {
      show: true,
      yAxisIndex: 0,
      filterMode: 'empty',
      width: 30,
      height: '80%',
      showDataShadow: false,
      left: '93%'
    }
  ],
  series: [
    {
      name: 'Budget 2011',
      type: 'bar',
      data: obama_budget_2012.budget2011List
    },
    {
      name: 'Budget 2012',
      type: 'bar',
      data: obama_budget_2012.budget2012List
    }
  ]
};
"""#,
        option: [
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow",
                    "label": [
                        "show": true
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "toolbox": [
                "show": true,
                "feature": [
                    "mark": ["show": true] as [String: Any],
                    "dataView": ["show": true, "readOnly": false] as [String: Any],
                    "magicType": ["show": true, "type": ["line", "bar"]] as [String: Any],
                    "restore": ["show": true] as [String: Any],
                    "saveAsImage": ["show": true] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "calculable": true,
            "legend": [
                "data": ["Growth", "Budget 2011", "Budget 2012"],
                "itemGap": 5.0
            ] as [String: Any],
            "grid": [
                "top": "12%",
                "left": "1%",
                "right": "10%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                [
                    "type": "category",
                    "data": obamaBudgetNames
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "value",
                    "name": "Budget (million USD)"
                    // PORT-NOTE: yAxis[0].axisLabel.formatter omitted — the JS closure coerced the tick
                    // value to a number and rendered it as `echarts.format.addCommas(value / 1000)`, i.e.
                    // thousands with comma group separators ("1,000" for 1000000), blanking non-finite
                    // ticks. Swift cannot carry a JS function through the option bag, so the native pane
                    // shows the raw tick values.
                ] as [String: Any]
            ],
            "dataZoom": [
                [
                    "show": true,
                    "start": 94.0,
                    "end": 100.0
                ] as [String: Any],
                [
                    "type": "inside",
                    "start": 94.0,
                    "end": 100.0
                ] as [String: Any],
                [
                    "show": true,
                    "yAxisIndex": 0.0,
                    "filterMode": "empty",
                    "width": 30.0,
                    "height": "80%",
                    "showDataShadow": false,
                    "left": "93%"
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "Budget 2011",
                    "type": "bar",
                    "data": obamaBudget2011List
                ] as [String: Any],
                [
                    "name": "Budget 2012",
                    "type": "bar",
                    "data": obamaBudget2012List
                ] as [String: Any]
            ]
        ])
}
