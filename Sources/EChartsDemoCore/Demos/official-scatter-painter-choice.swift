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
//   - NATIVE PANE: a Swift `[String: Any]` option cannot carry a JS closure, so the example's THREE
//     function-valued keys (series.symbolSize, series.itemStyle.color, xAxis.axisLabel.formatter) are
//     omitted — see the PORT-NOTE lines. Consequence: the native pane plots the same 4111 points on the
//     same axes, but every dot is the default size (10) in the palette's first colour, and the x ticks
//     read `1600` where the web pane reads `1600s`. The colour/size mapping the example exists to show
//     is therefore visible ONLY on the web pane; that difference is the point of the side-by-side.
import Foundation

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
                "max": "dataMax"
                // PORT-NOTE: xAxis.axisLabel.formatter omitted — the JS closure suffixed every tick with
                // the decade 's' (`val + 's'`): 1600 → "1600s".
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
                    // PORT-NOTE: series.symbolSize omitted — the JS closure sized each dot from the
                    // dataset's own marker table: `marker.size[param.dataIndex] / marker.sizeref`
                    // (size ∈ [0, 0.99], sizeref = 0.05 → ~0…19.8px). Native falls back to symbolSize 10.
                    // PORT-NOTE: series.itemStyle.color omitted — the JS closure painted each dot in the
                    // painting's own dominant colour: `marker.color[param.dataIndex]` (4100 of the 4111 are
                    // '#rrggbb'; 11 carry an alpha byte, '#rrggbbaa'). Native falls back to the palette's
                    // first colour, so the native pane shows the DISTRIBUTION but not the COLOURS this
                    // example is named for.
                    "data": painterChoiceData as [Any]
                ] as [String: Any]
            ]
        ])
}
