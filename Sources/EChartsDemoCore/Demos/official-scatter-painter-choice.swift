// official-scatter-painter-choice — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-painter-choice
// title: Master Painter Color Choices Throughout History / titleCN: 历代绘画大师的色彩运用
// 4111 paintings (Plot.ly's dataset) as a value/value scatter: x = year (1007–1925), y = the dominant
// colour's Hue (0–360). Each dot is PAINTED IN ITS OWN PAINTING'S COLOUR (an `itemStyle.color` closure
// reading `marker.color[dataIndex]`) and sized by `marker.size[dataIndex] / marker.sizeref` (a
// `symbolSize` closure) — the per-datum colour IS what the example is about.
//
// DEVIATIONS from the official source:
//   - DATA INLINED: upstream wraps everything in `$.get(ROOT_PATH +
//     '/data/asset/data/masterPainterColorChoice.json', function (json) { ... })`. The page has no
//     network, so the asset is vendored at assets/data/masterPainterColorChoice.json and read via
//     Upstream.repoRoot (the same #filePath-relative repo read WebPage.swift uses for the echarts dist):
//     the WEB pane gets the raw JSON text spliced in as `var json = ...` and then runs the callback BODY
//     verbatim — `myChart.showLoading()/hideLoading()`, the `data` map, both closures, the whole option.
//     Only the `$.get` wrapper, the TypeScript annotations (`x: number, idx: number`, `as string`) and
//     the trailing `export {}` are gone.
//   - NATIVE PANE: the three function-valued keys are carried through the typed callback seams:
//     per-point symbol size, per-point colour, and the value-axis label formatter.
import Foundation
import EChartsKit

private let painterChoiceAssetURL =
    Upstream.repoRoot.appendingPathComponent("assets/data/masterPainterColorChoice.json")

// The raw JSON text, spliced into webOptionJS so the reference pane runs the official callback body
// against the exact bytes the native pane parses (its two closures index json[0].marker.size/.color).
private let painterChoiceJSONText: String =
    (try? String(contentsOf: painterChoiceAssetURL, encoding: .utf8))
    ?? #"[{"x":[],"y":[],"marker":{"size":[],"sizeref":1,"color":[]}}]"#

// json[0].x.map(function (x, idx) { return [+x, +json[0].y[idx]]; }) — x is a year STRING ("1007"), y is
// the hue. Parsed ONCE from the repo asset; a parse failure degrades to no data (the pane then renders
// empty axes rather than crashing).
private let painterChoiceData: [[Double]] = {
    guard let data = try? Data(contentsOf: painterChoiceAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
          let trace = arr.first,
          let xs = trace["x"] as? [String],
          let ys = trace["y"] as? [NSNumber] else { return [] }
    return zip(xs, ys).compactMap { x, y in
        guard let xv = Double(x) else { return nil }
        return [xv, y.doubleValue]
    }
}()

private struct PainterChoiceMarker {
    let sizes: [Double]
    let sizeRef: Double
    let colors: [String]
}

private let painterChoiceMarker: PainterChoiceMarker = {
    guard let data = try? Data(contentsOf: painterChoiceAssetURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
          let marker = arr.first?["marker"] as? [String: Any] else {
        return PainterChoiceMarker(sizes: [], sizeRef: 1, colors: [])
    }
    let sizes = (marker["size"] as? [NSNumber] ?? []).map(\.doubleValue)
    let sizeRef = (marker["sizeref"] as? NSNumber)?.doubleValue ?? 1
    return PainterChoiceMarker(
        sizes: sizes,
        sizeRef: sizeRef == 0 ? 1 : sizeRef,
        colors: marker["color"] as? [String] ?? []
    )
}()

private let painterChoiceSymbolSize: SymbolSizeCallback<CallbackDataParams> = { _, params in
    let index = Int(params.dataIndex)
    guard painterChoiceMarker.sizes.indices.contains(index) else { return 0.0 }
    return painterChoiceMarker.sizes[index] / painterChoiceMarker.sizeRef
}

private let painterChoiceColor: (CallbackDataParams) -> EChartsKit.ZRColor = { params in
    let index = Int(params.dataIndex)
    let color = painterChoiceMarker.colors.indices.contains(index)
        ? painterChoiceMarker.colors[index]
        : "#5470c6"
    return .color(color)
}

private let painterChoiceXAxisFormatter: AxisLabelValueFormatter = { value, _, _ in
    let rounded = value.rounded()
    let number = rounded == value ? String(Int(rounded)) : String(value)
    return number + "s"
}

extension EChartsDemoRegistry {
    static let official_scatter_painter_choice = EChartsDemo(
        name: "official-scatter-painter-choice", category: "scatter",
        summary: "历代绘画大师的色彩运用 — Master Painter Color Choices Throughout History",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

var json = \#(painterChoiceJSONText);

myChart.hideLoading();

var data = json[0].x.map(function (x, idx) {
  return [+x, +json[0].y[idx]];
});

myChart.setOption(
  (option = {
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
  })
);
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
                "max": "dataMax",
                "axisLabel": [
                    "formatter": painterChoiceXAxisFormatter as AxisLabelValueFormatter
                ] as [String: Any]
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
                    "symbolSize": painterChoiceSymbolSize,
                    "itemStyle": [
                        "color": painterChoiceColor as (CallbackDataParams) -> EChartsKit.ZRColor
                    ] as [String: Any],
                    "data": painterChoiceData as [Any]
                ] as [String: Any]
            ]
        ])
}
