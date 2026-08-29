// official-treemap-visual — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-visual
// title: Gradient Mapping / titleCN: 映射为渐变色
// Obama's 2012 federal budget proposal as a treemap: tile AREA is the 2012 amount (`value[0]`), tile
// COLOUR is the year-on-year growth. The colour is the point of the example — `visualDimension: 3`
// tells the treemap to map a FOURTH, synthetic dimension (which the example computes itself) through
// the level-1 `color: ['#942e38', '#aaa', '#269f3c']` gradient with `colorMappingBy: 'value'`, so
// shrinking programs come out red, growing ones green and flat ones grey.
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream does `$.get(ROOT_PATH + '/data/asset/data/obama_budget_proposal_2012.json',
//     function (obama_budget_2012) {...})` and builds the option inside the callback. The page has no
//     network, so the asset is vendored at assets/data/obama_budget_proposal_2012.json (447 nodes, 2
//     levels) and read at demo time via Upstream.repoRoot: the web pane gets the raw JSON text spliced
//     in as `var obama_budget_2012 = ...` and keeps the CALLBACK BODY verbatim at top level —
//     `convertData`, `isValidNumber`, `myChart.setOption((option = {...}))` and all — dropping only the
//     `$.get` wrapper. `showLoading()` / `hideLoading()` keep their upstream order (they now bracket the
//     inlined literal instead of a request, so they pair up synchronously).
//   - TypeScript-only text dropped, as it must be to run as a classic script: the `interface TreeNode`
//     declaration, the `originList: TreeNode[]` / `num: number` / `info: any` parameter annotations, and
//     the trailing `export {};` (a bare export is a SyntaxError that would kill the whole page).
//   - The example's `convertData()` is a DATA transform, not an option closure — it walks the tree and
//     writes `value[3]`, the very dimension `visualDimension: 3` maps — so the native pane PORTS it to
//     Swift (`treemapVisualConvertData` + `treemapVisualLinearMap`, a one-to-one transcription of
//     `echarts.number.linearMap`) rather than omitting it. Both panes therefore colour by the same
//     numbers; only the code that produces them differs.
//   - NATIVE PANE: `tooltip.formatter` is represented by an equivalent typed Swift callback, using
//     Native rich-text newlines while preserving the Web formatter's title, amounts and change value.
//
// The example drives NO timeline — no `setInterval`/`setTimeout`, and its only interactivity is the
// treemap's own built-in drill-down — so there is no `drive` closure to write.
import Foundation
import EChartsKit

private let treemapVisualTooltipFormatter: (TooltipCallbackDataParams) -> String = { info in
    let values = info.value as? [Any] ?? []
    func number(_ index: Int) -> Double? {
        index < values.count ? treemapTooltipFiniteNumber(values[index]) : nil
    }
    let amount = number(0).map { format.addCommas($0 * 1000) + "$" } ?? "-"
    let amount2011 = number(1).map { format.addCommas($0 * 1000) + "$" } ?? "-"
    let change = number(2).map { String(format: "%.2f%%", $0) } ?? "-"
    return [
        info.name,
        "2012 Amount:  \(amount)",
        "2011 Amount:  \(amount2011)",
        "Change From 2011:  \(change)",
    ].joined(separator: "\n")
}

// MARK: - the vendored asset

// Raw JSON text — spliced into the web pane's script (the page cannot reach the filesystem), where the
// example's own `convertData` then mutates it exactly as it does on the website.
private let treemapVisualRawJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/obama_budget_proposal_2012.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// MARK: - the visual mapping bounds (the example's four consts)

private let treemapVisualMin: Double = -100
private let treemapVisualMax: Double = 100
private let treemapVisualMinBound: Double = -40
private let treemapVisualMaxBound: Double = 40

// MARK: - `echarts.number.linearMap`, ported

// One-to-one with upstream `number.ts#linearMap(val, domain, range, clamp)`. The example only ever calls
// it with `clamp = true`, so the clamped branch is the only one transcribed.
private func treemapVisualLinearMap(_ val: Double,
                                    _ domain: (Double, Double),
                                    _ range: (Double, Double)) -> Double {
    let (d0, d1) = domain
    let (r0, r1) = range
    let subDomain = d1 - d0
    let subRange = r1 - r0
    if subDomain == 0 { return subRange == 0 ? r0 : (r0 + r1) / 2 }
    if subDomain > 0 {
        if val <= d0 { return r0 } else if val >= d1 { return r1 }
    } else {
        if val >= d0 { return r0 } else if val <= d1 { return r1 }
    }
    return (val - d0) / subDomain * subRange + r0
}

// MARK: - the example's convertData(), ported

// Upstream walks the tree one SIBLING LIST at a time: it takes the min/max of `value[2]` (the growth %)
// across the current list only, then rescales each sibling's growth into `value[3]` — positives onto
// [visualMaxBound, visualMax], negatives onto [visualMin, visualMinBound], everything else 0 — and
// recurses into that node's children (which get their own, fresh min/max). Nulls (`value[2] == null`, as
// every root has) fall through to 0. Reproduced here move for move, including the `isFinite` guard.
//
// The asset's `value` arrays are `[amount2012, amount2011, growth]` (always length 3, verified), so
// `value[3]` is an APPEND; JS's sparse-safe `value[3] = x` is the same thing here.
private func treemapVisualConvertData(_ originList: inout [[String: Any]]) {
    var min = Double.infinity
    var max = -Double.infinity

    for node in originList {
        guard let value = node["value"] as? [Any], value.count > 2,
              let growth = value[2] as? Double else { continue }   // NSNull / absent == JS `null`
        if growth < min { min = growth }
        if growth > max { max = growth }
    }

    for i in originList.indices {
        guard var value = originList[i]["value"] as? [Any] else { continue }
        let growth = value.count > 2 ? value[2] as? Double : nil

        var mapped: Double
        if let g = growth, g > 0 {
            mapped = treemapVisualLinearMap(g, (0, max), (treemapVisualMaxBound, treemapVisualMax))
        } else if let g = growth, g < 0 {
            mapped = treemapVisualLinearMap(g, (min, 0), (treemapVisualMin, treemapVisualMinBound))
        } else {
            mapped = 0
        }
        if !mapped.isFinite { mapped = 0 }

        if value.count > 3 { value[3] = mapped } else { value.append(mapped) }
        originList[i]["value"] = value

        if var children = originList[i]["children"] as? [[String: Any]] {
            treemapVisualConvertData(&children)
            originList[i]["children"] = children
        }
    }
}

// `series[0].data` — the asset with the synthetic `value[3]` (the colour dimension) filled in.
// A parse failure degrades to an empty treemap rather than crashing the gallery.
private let treemapVisualData: [[String: Any]] = {
    guard let data = treemapVisualRawJSONText.data(using: .utf8),
          var list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    treemapVisualConvertData(&list)
    return list
}()

private let treemapVisualLevels: [[String: Any]] = [
    [
        "itemStyle": [
            "borderWidth": 3.0,
            "borderColor": "#333",
            "gapWidth": 3.0
        ] as [String: Any]
    ],
    [
        "color": ["#942e38", "#aaa", "#269f3c"],
        "colorMappingBy": "value",
        "itemStyle": [
            "gapWidth": 1.0
        ] as [String: Any]
    ]
]

extension EChartsDemoRegistry {
    static let official_treemap_visual = EChartsDemo(
        name: "official-treemap-visual", category: "treemap",
        summary: "映射为渐变色 — Gradient Mapping",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

const household_america_2012 = 113616229;
var obama_budget_2012 = \#(treemapVisualRawJSONText);

myChart.hideLoading();

const visualMin = -100;
const visualMax = 100;
const visualMinBound = -40;
const visualMaxBound = 40;

convertData(obama_budget_2012);

function convertData(originList) {
  let min = Infinity;
  let max = -Infinity;

  for (let i = 0; i < originList.length; i++) {
    let node = originList[i];
    if (node) {
      let value = node.value;
      value[2] != null && value[2] < min && (min = value[2]);
      value[2] != null && value[2] > max && (max = value[2]);
    }
  }

  for (let i = 0; i < originList.length; i++) {
    let node = originList[i];
    if (node) {
      let value = node.value;

      // Scale value for visual effect
      if (value[2] != null && value[2] > 0) {
        value[3] = echarts.number.linearMap(
          value[2],
          [0, max],
          [visualMaxBound, visualMax],
          true
        );
      } else if (value[2] != null && value[2] < 0) {
        value[3] = echarts.number.linearMap(
          value[2],
          [min, 0],
          [visualMin, visualMinBound],
          true
        );
      } else {
        value[3] = 0;
      }

      if (!isFinite(value[3])) {
        value[3] = 0;
      }

      if (node.children) {
        convertData(node.children);
      }
    }
  }
}

function isValidNumber(num) {
  return num != null && isFinite(num);
}

myChart.setOption(
  (option = {
    title: {
      left: 'center',
      text: 'Gradient Mapping',
      subtext: 'Growth > 0: green; Growth < 0: red; Growth = 0: grey'
    },
    tooltip: {
      formatter: function (info) {
        let value = info.value;

        let amount = value[0];
        amount = isValidNumber(amount)
          ? echarts.format.addCommas(amount * 1000) + '$'
          : '-';

        let amount2011 = value[1];
        amount2011 = isValidNumber(amount2011)
          ? echarts.format.addCommas(amount2011 * 1000) + '$'
          : '-';

        let change = value[2];
        change = isValidNumber(change) ? change.toFixed(2) + '%' : '-';

        return [
          '<div class="tooltip-title">' +
            echarts.format.encodeHTML(info.name) +
            '</div>',
          '2012 Amount: &nbsp;&nbsp;' + amount + '<br>',
          '2011 Amount: &nbsp;&nbsp;' + amount2011 + '<br>',
          'Change From 2011: &nbsp;&nbsp;' + change
        ].join('');
      }
    },
    series: [
      {
        name: 'ALL',
        top: 80,
        type: 'treemap',
        label: {
          show: true,
          formatter: '{b}'
        },
        itemStyle: {
          borderColor: 'black'
        },
        visualMin: visualMin,
        visualMax: visualMax,
        visualDimension: 3,
        levels: [
          {
            itemStyle: {
              borderWidth: 3,
              borderColor: '#333',
              gapWidth: 3
            }
          },
          {
            color: ['#942e38', '#aaa', '#269f3c'],
            colorMappingBy: 'value',
            itemStyle: {
              gapWidth: 1
            }
          }
        ],
        data: obama_budget_2012
      }
    ]
  })
);
"""#,
        option: [
            "title": [
                "left": "center",
                "text": "Gradient Mapping",
                "subtext": "Growth > 0: green; Growth < 0: red; Growth = 0: grey"
            ] as [String: Any],
            "tooltip": ["formatter": treemapVisualTooltipFormatter] as [String: Any],
            "series": [
                [
                    "name": "ALL",
                    "top": 80.0,
                    "type": "treemap",
                    "label": [
                        "show": true,
                        "formatter": "{b}"
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": "black"
                    ] as [String: Any],
                    "visualMin": treemapVisualMin,
                    "visualMax": treemapVisualMax,
                    "visualDimension": 3.0,
                    "levels": treemapVisualLevels as [Any],
                    "data": treemapVisualData as [Any]
                ] as [String: Any]
            ]
        ])
}
