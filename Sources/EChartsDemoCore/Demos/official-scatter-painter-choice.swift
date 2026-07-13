// official-scatter-painter-choice — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-painter-choice
// title: Master Painter Color Choices Throughout History / titleCN: 历代绘画大师的色彩运用
// 4111 paintings (year → dominant-colour hue 0..359) as a scatter, each dot sized by the painting's
// area-ish `marker.size` and PAINTED IN ITS OWN COLOUR (marker.color) — the Plot.ly dataset.
//
// DEVIATIONS from the official source:
//   - The `$.get(ROOT_PATH + '/data/asset/data/masterPainterColorChoice.json', ...)` fetch is gone:
//     the page has no network. The asset is vendored at assets/data/masterPainterColorChoice.json and
//     read at demo-build time via Upstream.repoRoot (the same #filePath-relative repo read WebPage.swift
//     uses for the echarts dist). The WEB pane gets the raw JSON text spliced in as `var json = ...`,
//     then runs the official callback body VERBATIM (the `data` map, both closures, the whole option).
//     showLoading()/hideLoading() and the trailing `export {}` are dropped.
//   - NATIVE pane: the example's two per-datum closures — `symbolSize: (val, param) =>
//     marker.size[param.dataIndex] / marker.sizeref` and `itemStyle.color: (param) =>
//     marker.color[param.dataIndex]` — cannot be written as a Swift option value. They are instead
//     PRE-EVALUATED per datum and carried as data items (`{value: [x, y], symbolSize: s,
//     itemStyle: {color: c}}`), which is the option-only equivalent and renders the same chart.
//   - NATIVE pane: `xAxis.axisLabel.formatter: val => val + 's'` is omitted (JS closure), so the
//     native x labels read `1600` where the web pane reads `1600s`. Everything else is verbatim.
import Foundation

// The Plot.ly dataset, parsed ONCE from the repo asset. A missing/corrupt file degrades to an empty
// trace (both panes then render an empty scatter rather than crashing).
private let painterChoiceTrace: [String: Any] = {
    guard let obj = (try? JSONSerialization.jsonObject(with: painterChoiceJSONData)) as? [[String: Any]],
          let first = obj.first else {
        return ["x": [Any](), "y": [Any](), "marker": ["size": [Any](), "sizeref": 1.0, "color": [Any]()] as [String: Any]]
    }
    return first
}()

private let painterChoiceJSONData: Data = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/masterPainterColorChoice.json")
    return (try? Data(contentsOf: url)) ?? Data()
}()

// The raw JSON text, spliced into the web pane as `var json = <...>` so the official callback body can
// run unchanged (it indexes json[0].marker.size / .color / .sizeref inside its two closures).
private let painterChoiceJSONText: String =
    String(data: painterChoiceJSONData, encoding: .utf8)
    ?? #"[{"x":[],"y":[],"marker":{"size":[],"sizeref":1,"color":[]}}]"#

// data + the two closures, pre-evaluated per datum (see DEVIATIONS):
//   value      = [+json[0].x[i], +json[0].y[i]]
//   symbolSize = json[0].marker.size[i] / json[0].marker.sizeref
//   itemStyle.color = json[0].marker.color[i]
private let painterChoiceData: [[String: Any]] = {
    let xs = painterChoiceTrace["x"] as? [Any] ?? []
    let ys = painterChoiceTrace["y"] as? [Any] ?? []
    let marker = painterChoiceTrace["marker"] as? [String: Any] ?? [:]
    let sizes = marker["size"] as? [Any] ?? []
    let colors = marker["color"] as? [Any] ?? []
    let sizeref = toPainterDouble(marker["sizeref"]) ?? 1.0

    var out: [[String: Any]] = []
    out.reserveCapacity(xs.count)
    for i in 0..<xs.count {
        guard i < ys.count,
              let x = toPainterDouble(xs[i]), let y = toPainterDouble(ys[i]) else { continue }
        var item: [String: Any] = ["value": [x, y]]
        if i < sizes.count, let s = toPainterDouble(sizes[i]), sizeref != 0 {
            item["symbolSize"] = s / sizeref
        }
        if i < colors.count, let c = colors[i] as? String {
            item["itemStyle"] = ["color": c] as [String: Any]
        }
        out.append(item)
    }
    return out
}()

/// `+x` — the dataset stores x as strings ("1007") and y/size as numbers.
private func toPainterDouble(_ any: Any?) -> Double? {
    if let d = any as? Double { return d }
    if let i = any as? Int { return Double(i) }
    if let n = any as? NSNumber { return n.doubleValue }
    if let s = any as? String { return Double(s) }
    return nil
}

extension EChartsDemoRegistry {
    static let official_scatter_painter_choice = EChartsDemo(
        name: "official-scatter-painter-choice", category: "scatter",
        summary: "历代绘画大师的色彩运用 — Master Painter Color Choices Throughout History",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var json = \#(painterChoiceJSONText);

var data = json[0].x.map(function (x, idx) {
  return [+x, +json[0].y[idx]];
});

option = {
  title: {
    text: 'Master Painter Color Choices Throughout History',
    subtext: 'Data From Plot.ly',
    left: 'right'
  },
  xAxis: {
    type: 'value',
    splitLine: {
      show: false
    },
    scale: true,
    splitNumber: 5,
    max: 'dataMax',
    axisLabel: {
      formatter: function (val) {
        return val + 's';
      }
    }
  },
  yAxis: {
    type: 'value',
    min: 0,
    max: 360,
    interval: 60,
    name: 'Hue',
    splitLine: {
      show: false
    }
  },
  series: [
    {
      name: 'scatter',
      type: 'scatter',
      symbolSize: function (val, param) {
        return json[0].marker.size[param.dataIndex] / json[0].marker.sizeref;
      },
      itemStyle: {
        color: function (param) {
          return json[0].marker.color[param.dataIndex];
        }
      },
      data: data
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Master Painter Color Choices Throughout History",
                "subtext": "Data From Plot.ly",
                "left": "right"
            ] as [String: Any],
            "xAxis": [
                "type": "value",
                "splitLine": ["show": false] as [String: Any],
                "scale": true,
                "splitNumber": 5.0,
                "max": "dataMax"
                // PORT-NOTE: xAxis.axisLabel.formatter omitted — JS closure `val => val + 's'`
                // (appends the decade suffix: 1600 → "1600s").
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "min": 0.0,
                "max": 360.0,
                "interval": 60.0,
                "name": "Hue",
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "name": "scatter",
                    "type": "scatter",
                    // PORT-NOTE: series.symbolSize omitted as a key — JS closure
                    // `(val, param) => marker.size[param.dataIndex] / marker.sizeref`; pre-evaluated
                    // into each data item's `symbolSize` instead (see DEVIATIONS).
                    // PORT-NOTE: series.itemStyle.color omitted as a key — JS closure
                    // `param => marker.color[param.dataIndex]`; pre-evaluated into each data item's
                    // `itemStyle.color` instead (see DEVIATIONS).
                    "data": painterChoiceData as [Any]
                ] as [String: Any]
            ]
        ])
}
