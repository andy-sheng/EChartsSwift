// official-bar-waterfall2 — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-waterfall2
// title: Waterfall Chart / titleCN: 阶梯瀑布图（柱状图模拟）
// A waterfall faked out of a stacked bar: an invisible 'Placeholder' series lifts each visible bar to
// its running total, then 'Income' / 'Expenses' draw the deltas (a '-' means "no bar this day").
// DEVIATIONS:
//   - The official source is TypeScript; the web pane drops the `params: any` annotation (a type
//     annotation is a SyntaxError in the classic <script> the reference pane runs) and the trailing
//     `export {};`. Everything else in webOptionJS is verbatim, including the xAxis IIFE.
//   - Native pane: the JS `tooltip.formatter` is represented by an equivalent Swift closure. The
//     xAxis IIFE is evaluated in Swift into the same 'Nov 1'…'Nov 11' list.
import EChartsKit

extension EChartsDemoRegistry {
    static let official_bar_waterfall2 = EChartsDemo(
        name: "official-bar-waterfall2", category: "bar",
        summary: "阶梯瀑布图（柱状图模拟） — Waterfall Chart",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
option = {
  title: {
    text: 'Accumulated Waterfall Chart'
  },
  tooltip: {
    trigger: 'axis',
    axisPointer: {
      type: 'shadow'
    },
    formatter: function (params) {
      let tar;
      if (params[1] && params[1].value !== '-') {
        tar = params[1];
      } else {
        tar = params[2];
      }
      return tar && tar.name + '<br/>' + tar.seriesName + ' : ' + tar.value;
    }
  },
  legend: {
    data: ['Expenses', 'Income']
  },
  grid: {
    left: '3%',
    right: '4%',
    bottom: '3%',
    containLabel: true
  },
  xAxis: {
    type: 'category',
    data: (function () {
      let list = [];
      for (let i = 1; i <= 11; i++) {
        list.push('Nov ' + i);
      }
      return list;
    })()
  },
  yAxis: {
    type: 'value'
  },
  series: [
    {
      name: 'Placeholder',
      type: 'bar',
      stack: 'Total',
      silent: true,
      itemStyle: {
        borderColor: 'transparent',
        color: 'transparent'
      },
      emphasis: {
        itemStyle: {
          borderColor: 'transparent',
          color: 'transparent'
        }
      },
      data: [0, 900, 1245, 1530, 1376, 1376, 1511, 1689, 1856, 1495, 1292]
    },
    {
      name: 'Income',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true,
        position: 'top'
      },
      data: [900, 345, 393, '-', '-', 135, 178, 286, '-', '-', '-']
    },
    {
      name: 'Expenses',
      type: 'bar',
      stack: 'Total',
      label: {
        show: true,
        position: 'bottom'
      },
      data: ['-', '-', '-', 108, 154, '-', '-', '-', 119, 361, 203]
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Accumulated Waterfall Chart"
            ] as [String: Any],
            "tooltip": [
                "trigger": "axis",
                "axisPointer": [
                    "type": "shadow"
                ] as [String: Any],
                "formatter": barWaterfall2TooltipFormatter
            ] as [String: Any],
            "legend": [
                "data": ["Expenses", "Income"]
            ] as [String: Any],
            "grid": [
                "left": "3%",
                "right": "4%",
                "bottom": "3%",
                "containLabel": true
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": waterfall2Categories
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                [
                    "name": "Placeholder",
                    "type": "bar",
                    "stack": "Total",
                    "silent": true,
                    "itemStyle": [
                        "borderColor": "transparent",
                        "color": "transparent"
                    ] as [String: Any],
                    "emphasis": [
                        "itemStyle": [
                            "borderColor": "transparent",
                            "color": "transparent"
                        ] as [String: Any]
                    ] as [String: Any],
                    "data": waterfall2Placeholder
                ] as [String: Any],
                [
                    "name": "Income",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true,
                        "position": "top"
                    ] as [String: Any],
                    "data": waterfall2Income
                ] as [String: Any],
                [
                    "name": "Expenses",
                    "type": "bar",
                    "stack": "Total",
                    "label": [
                        "show": true,
                        "position": "bottom"
                    ] as [String: Any],
                    "data": waterfall2Expenses
                ] as [String: Any]
            ]
        ])
}

// The official xAxis data is an IIFE building 'Nov 1' … 'Nov 11'; evaluated here.
private let waterfall2Categories: [String] = (1...11).map { "Nov \($0)" }

// Invisible base: the running total each visible bar sits on top of.
private let waterfall2Placeholder: [Double] = [0, 900, 1245, 1530, 1376, 1376, 1511, 1689, 1856, 1495, 1292]

// '-' = no bar on that day (echarts treats the string '-' as empty).
private let waterfall2Income: [Any] = [900.0, 345.0, 393.0, "-", "-", 135.0, 178.0, 286.0, "-", "-", "-"]
private let waterfall2Expenses: [Any] = ["-", "-", "-", 108.0, 154.0, "-", "-", "-", 119.0, 361.0, 203.0]

private let barWaterfall2TooltipFormatter: ([TooltipCallbackDataParams]) -> String = { params in
    guard let target = params.first(where: {
        $0.seriesName != "Placeholder" && barWaterfall2ValueText($0.value) != "-"
    }) else { return "" }
    return "\(target.name)<br/>\(target.seriesName ?? "") : \(barWaterfall2ValueText(target.value))"
}

private func barWaterfall2ValueText(_ value: Any) -> String {
    if let value = value as? String { return value }
    if let value = value as? Int { return String(value) }
    if let value = value as? Double, value.rounded() == value { return String(Int(value)) }
    return String(describing: value)
}
