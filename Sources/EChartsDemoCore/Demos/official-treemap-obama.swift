// official-treemap-obama — replica of https://echarts.apache.org/examples/zh/editor.html?c=treemap-obama
// title: How $3.7 Trillion is Spent / titleCN: 3.7 万亿美元支出构成
// A treemap of Obama's 2012 federal budget proposal: three sibling `treemap` series ('2012Budget',
// '2011Budget', 'Growth') sharing a `selectedMode:'single'` legend so exactly one is shown at a time.
// Each series' data is built by `buildData(mode, ...)`, which clones the raw budget tree, computes a
// per-household amount (value[3] = value[0] / 113,616,229 households) and — for the '2011Budget' mode —
// swaps value[0]/value[1]. The 'Growth' series colours by value[2] via visualDimension:2.
//
// DEVIATIONS from the official source:
//   - The 447-node budget tree is fetched at runtime from assets/data/obama_budget_proposal_2012.json
//     (upstream `$.get(ROOT_PATH + '/data/asset/data/obama_budget_proposal_2012.json', ...)`); the web
//     pane gets the SAME JSON spliced in verbatim, the native pane parses it via Upstream.repoRoot.
//   - `series[].tooltip.formatter` and `series[].label.formatter` are JS closures (they build the rich
//     `{name}/{budget}/{household}` label text and the HTML tooltip with echarts.format.addCommas /
//     encodeHTML) — omitted from the native option (see PORT-NOTEs). The web pane runs them verbatim,
//     so the two panes diverge exactly on those closures: native labels fall back to the node name and
//     native tooltips to the default. The `label.rich` style bag and everything else are ported.
//   - Not dynamic (no setInterval/setTimeout; the only interaction is the legend), so no `drive`.
import Foundation
import EChartsKit

// Raw budget tree, verbatim JSON text — spliced into the web pane (upstream inlines the $.get body).
private let obamaBudgetJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/obama_budget_proposal_2012.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

// Same tree parsed for the native pane; a parse failure degrades to empty (pane renders blank, no crash).
private let obamaBudgetRaw: [[String: Any]] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/obama_budget_proposal_2012.json")
    guard let data = try? Data(contentsOf: url),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
        return []
    }
    return arr
}()

private let householdAmerica2012 = 113616229.0

// Swift port of the example's buildData(mode, originList): clone name/id/value (dropping `discretion`),
// set value[3] = value[0] / households, and for mode 1 swap value[0]/value[1]; recurse into children.
private func buildObamaData(mode: Int, _ originList: [[String: Any]]) -> [[String: Any]] {
    var out: [[String: Any]] = []
    for node in originList {
        var newNode: [String: Any] = [:]
        if let name = node["name"] { newNode["name"] = name }
        if let id = node["id"] { newNode["id"] = id }
        var value: [Any] = (node["value"] as? [Any]) ?? []
        while value.count < 4 { value.append(NSNull()) }
        if let v0 = value[0] as? NSNumber {
            value[3] = v0.doubleValue / householdAmerica2012
        }
        if mode == 1 { value.swapAt(0, 1) }
        newNode["value"] = value
        if let children = node["children"] as? [[String: Any]] {
            newNode["children"] = buildObamaData(mode: mode, children)
        }
        out.append(newNode)
    }
    return out
}

// Swift port of getLevelOption(mode): mode 2 supplies an explicit palette + colorAlpha ramp; the
// `undefined` branches for modes 0/1 are expressed by omitting the key.
private func obamaLevelOption(_ mode: Int) -> [[String: Any]] {
    var level0: [String: Any] = [
        "colorMappingBy": "id",
        "itemStyle": ["borderWidth": 3.0, "gapWidth": 3.0] as [String: Any]
    ]
    if mode == 2 {
        level0["color"] = ["#c23531", "#314656", "#61a0a8", "#dd8668", "#91c7ae",
                           "#6e7074", "#61a0a8", "#bda29a", "#44525d", "#c4ccd3"]
    }
    var level1: [String: Any] = [
        "itemStyle": ["gapWidth": 1.0] as [String: Any]
    ]
    if mode == 2 { level1["colorAlpha"] = [0.5, 1.0] }
    return [level0, level1]
}

private let obamaModes = ["2012Budget", "2011Budget", "Growth"]

// The label.rich style bag from createSeriesCommon (kept verbatim; only the formatter closure is dropped).
private let obamaLabelRich: [String: Any] = [
    "budget": ["fontSize": 22.0, "lineHeight": 30.0, "color": "yellow"] as [String: Any],
    "household": ["fontSize": 14.0, "color": "#fff"] as [String: Any],
    "label": ["fontSize": 9.0, "backgroundColor": "rgba(0,0,0,0.3)", "color": "#fff",
              "borderRadius": 2.0, "padding": [2.0, 4.0], "lineHeight": 25.0, "align": "right"] as [String: Any],
    "name": ["fontSize": 12.0, "color": "#fff"] as [String: Any],
    "hr": ["width": "100%", "borderColor": "rgba(255,255,255,0.2)", "borderWidth": 0.5,
           "height": 0.0, "lineHeight": 10.0] as [String: Any]
]

extension EChartsDemoRegistry {
    static let official_treemap_obama = EChartsDemo(
        name: "official-treemap-obama", category: "treemap",
        summary: "3.7 万亿美元支出构成 — How $3.7 Trillion is Spent",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
myChart.showLoading();

const household_america_2012 = 113616229;

var obama_budget_2012 = \#(obamaBudgetJSONText);

myChart.hideLoading();

function buildData(mode, originList) {
  let out = [];

  for (let i = 0; i < originList.length; i++) {
    let node = originList[i];
    let newNode = cloneNodeInfo(node);

    if (!newNode) {
      continue;
    }
    out[i] = newNode;
    let value = newNode.value;

    // Calculate amount per household.
    value[3] = value[0] / household_america_2012;

    // if mode === 0 and mode === 2 do nothing
    if (mode === 1) {
      // Set 'Change from 2010' to value[0].
      let tmp = value[1];
      value[1] = value[0];
      value[0] = tmp;
    }

    if (node.children) {
      newNode.children = buildData(mode, node.children);
    }
  }

  return out;
}

function cloneNodeInfo(node) {
  if (!node) {
    return;
  }

  const newNode = {};
  newNode.name = node.name;
  newNode.id = node.id;
  newNode.value = (node.value || []).slice();
  return newNode;
}

function getLevelOption(mode) {
  return [
    {
      color:
        mode === 2
          ? [
              '#c23531',
              '#314656',
              '#61a0a8',
              '#dd8668',
              '#91c7ae',
              '#6e7074',
              '#61a0a8',
              '#bda29a',
              '#44525d',
              '#c4ccd3'
            ]
          : undefined,
      colorMappingBy: 'id',
      itemStyle: {
        borderWidth: 3,
        gapWidth: 3
      }
    },
    {
      colorAlpha: mode === 2 ? [0.5, 1] : undefined,
      itemStyle: {
        gapWidth: 1
      }
    }
  ];
}

function isValidNumber(num) {
  return num != null && isFinite(num);
}

function getTooltipFormatter(mode) {
  let amountIndex = mode === 1 ? 1 : 0;
  let amountIndex2011 = mode === 1 ? 0 : 1;

  return function (info) {
    let value = info.value;

    let amount = value[amountIndex];
    amount = isValidNumber(amount)
      ? echarts.format.addCommas(amount * 1000) + '$'
      : '-';

    let amount2011 = value[amountIndex2011];
    amount2011 = isValidNumber(amount2011)
      ? echarts.format.addCommas(amount2011 * 1000) + '$'
      : '-';

    let perHousehold = value[3];
    perHousehold = isValidNumber(perHousehold)
      ? echarts.format.addCommas(+perHousehold.toFixed(4) * 1000) + '$'
      : '-';

    let change = value[2];
    change = isValidNumber(change) ? change.toFixed(2) + '%' : '-';

    return [
      '<div class="tooltip-title">' +
        echarts.format.encodeHTML(info.name) +
        '</div>',
      '2012 Amount: &nbsp;&nbsp;' + amount + '<br>',
      'Per Household: &nbsp;&nbsp;' + perHousehold + '<br>',
      '2011 Amount: &nbsp;&nbsp;' + amount2011 + '<br>',
      'Change From 2011: &nbsp;&nbsp;' + change
    ].join('');
  };
}

function createSeriesCommon(mode) {
  return {
    type: 'treemap',
    tooltip: {
      formatter: getTooltipFormatter(mode)
    },
    label: {
      position: 'insideTopLeft',
      formatter: function (params) {
        let arr = [
          '{name|' + params.name + '}',
          '{hr|}',
          '{budget|$ ' +
            echarts.format.addCommas(params.value[0]) +
            '} {label|budget}'
        ];

        mode !== 1 &&
          arr.push(
            '{household|$ ' +
              echarts.format.addCommas(+params.value[3].toFixed(4) * 1000) +
              '} {label|per household}'
          );

        return arr.join('\n');
      },
      rich: {
        budget: {
          fontSize: 22,
          lineHeight: 30,
          color: 'yellow'
        },
        household: {
          fontSize: 14,
          color: '#fff'
        },
        label: {
          fontSize: 9,
          backgroundColor: 'rgba(0,0,0,0.3)',
          color: '#fff',
          borderRadius: 2,
          padding: [2, 4],
          lineHeight: 25,
          align: 'right'
        },
        name: {
          fontSize: 12,
          color: '#fff'
        },
        hr: {
          width: '100%',
          borderColor: 'rgba(255,255,255,0.2)',
          borderWidth: 0.5,
          height: 0,
          lineHeight: 10
        }
      }
    },
    itemStyle: {
      borderColor: 'black'
    },
    levels: getLevelOption(0)
  };
}

let modes = ['2012Budget', '2011Budget', 'Growth'];

myChart.setOption(
  (option = {
    title: {
      top: 5,
      left: 'center',
      text: 'How $3.7 Trillion is Spent',
      subtext: 'Obama’s 2012 Budget Proposal'
    },

    legend: {
      data: modes,
      selectedMode: 'single',
      top: 55,
      itemGap: 5,
      borderRadius: 5
    },

    tooltip: {},

    series: modes.map(function (mode, idx) {
      let seriesOpt = createSeriesCommon(idx);
      seriesOpt.name = mode;
      seriesOpt.top = 80;
      seriesOpt.visualDimension = idx === 2 ? 2 : undefined;
      seriesOpt.data = buildData(idx, obama_budget_2012);
      seriesOpt.levels = getLevelOption(idx);
      return seriesOpt;
    })
  })
);
"""#,
        option: {
            let series: [[String: Any]] = obamaModes.enumerated().map { (idx, mode) -> [String: Any] in
                var s: [String: Any] = [
                    "type": "treemap",
                    // PORT-NOTE: series.tooltip.formatter omitted — JS closure formatting the 2012/2011
                    // amounts, per-household amount and change% into an HTML tooltip (addCommas/encodeHTML).
                    "label": [
                        "position": "insideTopLeft",
                        // PORT-NOTE: label.formatter omitted — JS closure building rich
                        // {name}/{budget}/{household} text; native falls back to the node name.
                        "rich": obamaLabelRich
                    ] as [String: Any],
                    "itemStyle": ["borderColor": "black"] as [String: Any],
                    "name": mode,
                    "top": 80.0,
                    "levels": obamaLevelOption(idx),
                    "data": buildObamaData(mode: idx, obamaBudgetRaw)
                ]
                if idx == 2 { s["visualDimension"] = 2.0 }
                return s
            }
            return [
                "title": [
                    "top": 5.0,
                    "left": "center",
                    "text": "How $3.7 Trillion is Spent",
                    "subtext": "Obama’s 2012 Budget Proposal"
                ] as [String: Any],
                "legend": [
                    "data": obamaModes,
                    "selectedMode": "single",
                    "top": 55.0,
                    "itemGap": 5.0,
                    "borderRadius": 5.0
                ] as [String: Any],
                "tooltip": [:] as [String: Any],
                "series": series
            ]
        }())
}
