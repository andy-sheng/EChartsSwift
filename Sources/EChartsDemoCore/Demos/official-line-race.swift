// official-line-race — replica of https://echarts.apache.org/examples/zh/editor.html?c=line-race
// title: Line Race / titleCN: 动态排序折线图
// Eight countries' income since 1950, each a `line` series fed by its OWN dataset: one raw dataset
// (`dataset_raw`, the life-expectancy table) plus a per-country `filter` transform
// (`Year >= 1950 AND Country == <country>`), with `endLabel` naming each line at its right edge.
//
// DEVIATIONS from the official source:
//  - DATA INLINED. Upstream fetches the table with
//    `$.get(ROOT_PATH + '/data/asset/data/life-expectancy-table.json', run)`. The gallery page has no
//    network, so both panes read the repo mirror assets/data/life-expectancy-table.json via
//    Upstream.repoRoot: the native pane parses it, the web pane gets the same raw JSON text spliced in
//    where the fetch was. The `run(_rawData)` body itself is kept verbatim and simply called at the top
//    level, so `option` is assigned unconditionally.
//  - Web pane: the example's TypeScript annotations (`: echarts.DatasetComponentOption[]`,
//    `: echarts.SeriesOption[]`, `(params: any)`, `(_rawData: any)`) are stripped — the page runs a
//    classic script, not TS. `myChart.setOption(option)` and the trailing `export {};` are dropped
//    (the harness owns init/setOption; a bare export is a SyntaxError in a classic script).
//  - ANIMATION. `animationDuration: 10000` is carried through, but the gallery renders ONE static frame
//    with animation forced off — the ten-second left-to-right "race" reveal is not visible; both panes
//    show the finished lines.
//  - Native pane: `series[].endLabel.formatter` is a JS closure and is omitted (see PORT-NOTE below);
//    everything else — the dataset filter transforms, `encode`, `labelLayout`, `emphasis` — is ported.
import Foundation
import EChartsKit

// The life-expectancy table: a header row ['Income','Life Expectancy','Population','Country','Year']
// followed by 1539 data rows. Read ONCE from the repo asset (the same #filePath-relative read the
// echarts.js pane uses for the upstream dist); a parse failure degrades to an empty dataset so the pane
// renders blank rather than crashing.
private let lineRaceRawJSONText: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy-table.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

private let lineRaceRawData: [[Any]] = {
    guard let data = lineRaceRawJSONText.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return rows
}()

// The eight countries the example plots (upstream keeps a wider list commented out above them).
private let lineRaceCountries: [String] = [
    "Finland", "France", "Germany", "Iceland", "Norway", "Poland", "Russia", "United Kingdom"
]

// dataset_raw + one filtered dataset per country (`Year >= 1950 AND Country == <country>`).
private let lineRaceDataset: [[String: Any]] = {
    var out: [[String: Any]] = [
        ["id": "dataset_raw", "source": lineRaceRawData as [Any]] as [String: Any]
    ]
    for country in lineRaceCountries {
        out.append([
            "id": "dataset_" + country,
            "fromDatasetId": "dataset_raw",
            "transform": [
                "type": "filter",
                "config": [
                    "and": [
                        ["dimension": "Year", "gte": 1950.0] as [String: Any],
                        ["dimension": "Country", "=": country] as [String: Any]
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any])
    }
    return out
}()

// upstream: (params) => params.value[3] + ': ' + params.value[0]
//   `params.value` is the raw source row [Income, LifeExpectancy, Population, Country, Year]; dim 3 is
//   the country name, dim 0 the income. JS `x + ''` prints an integral number without a trailing ".0".
private func lineRaceEndLabelFormatter(_ params: CallbackDataParams) -> String {
    guard let row = params.value as? [Any], row.count > 3 else { return "" }
    return lineRaceValueStr(row[3]) + ": " + lineRaceValueStr(row[0])
}

private func lineRaceValueStr(_ v: Any?) -> String {
    switch v {
    case let s as String: return s
    case let n as NSNumber:
        let d = n.doubleValue
        return (d == d.rounded() && Swift.abs(d) < 1e15) ? String(Int(d)) : "\(d)"
    case let d as Double:
        return (d == d.rounded() && Swift.abs(d) < 1e15) ? String(Int(d)) : "\(d)"
    case let i as Int: return String(i)
    case nil: return ""
    default: return String(describing: v!)
    }
}

private let lineRaceSeries: [[String: Any]] = lineRaceCountries.map { country in
    [
        "type": "line",
        "datasetId": "dataset_" + country,
        "showSymbol": false,
        "name": country,
        // upstream: endLabel.formatter = (params) => params.value[3] + ': ' + params.value[0]
        //   — "<Country>: <Income>" (dims 3 and 0 of the raw source row) at each line's right end.
        //   Ported as a native `(CallbackDataParams) -> String` closure (the label subsystem accepts a
        //   callback formatter via DataFormatMixin.getFormattedLabel), so the native pane draws the same
        //   country+income pair the web pane does — not the encode-derived default.
        "endLabel": [
            "show": true,
            "formatter": (lineRaceEndLabelFormatter as (CallbackDataParams) -> String)
        ] as [String: Any],
        "labelLayout": ["moveOverlap": "shiftY"] as [String: Any],
        "emphasis": ["focus": "series"] as [String: Any],
        "encode": [
            "x": "Year",
            "y": "Income",
            "label": ["Country", "Income"],
            "itemName": "Year",
            "tooltip": ["Income"]
        ] as [String: Any]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_line_race = EChartsDemo(
        name: "official-line-race", category: "line",
        summary: "动态排序折线图 — Line Race",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var _lineRaceRawData = \#(lineRaceRawJSONText);

function run(_rawData) {
  // var countries = ['Australia', 'Canada', 'China', 'Cuba', 'Finland', 'France', 'Germany', 'Iceland', 'India', 'Japan', 'North Korea', 'South Korea', 'New Zealand', 'Norway', 'Poland', 'Russia', 'Turkey', 'United Kingdom', 'United States'];
  const countries = [
    'Finland',
    'France',
    'Germany',
    'Iceland',
    'Norway',
    'Poland',
    'Russia',
    'United Kingdom'
  ];
  const datasetWithFilters = [];
  const seriesList = [];
  echarts.util.each(countries, function (country) {
    var datasetId = 'dataset_' + country;
    datasetWithFilters.push({
      id: datasetId,
      fromDatasetId: 'dataset_raw',
      transform: {
        type: 'filter',
        config: {
          and: [
            { dimension: 'Year', gte: 1950 },
            { dimension: 'Country', '=': country }
          ]
        }
      }
    });
    seriesList.push({
      type: 'line',
      datasetId: datasetId,
      showSymbol: false,
      name: country,
      endLabel: {
        show: true,
        formatter: function (params) {
          return params.value[3] + ': ' + params.value[0];
        }
      },
      labelLayout: {
        moveOverlap: 'shiftY'
      },
      emphasis: {
        focus: 'series'
      },
      encode: {
        x: 'Year',
        y: 'Income',
        label: ['Country', 'Income'],
        itemName: 'Year',
        tooltip: ['Income']
      }
    });
  });

  option = {
    animationDuration: 10000,
    dataset: [
      {
        id: 'dataset_raw',
        source: _rawData
      },
      ...datasetWithFilters
    ],
    title: {
      text: 'Income of Germany and France since 1950'
    },
    tooltip: {
      order: 'valueDesc',
      trigger: 'axis'
    },
    xAxis: {
      type: 'category',
      nameLocation: 'middle'
    },
    yAxis: {
      name: 'Income'
    },
    grid: {
      right: 140
    },
    series: seriesList
  };
}

run(_lineRaceRawData);
"""#,
        option: [
            "animationDuration": 10000.0,
            "dataset": lineRaceDataset as [Any],
            "title": [
                "text": "Income of Germany and France since 1950"
            ] as [String: Any],
            "tooltip": [
                "order": "valueDesc",
                "trigger": "axis"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "nameLocation": "middle"
            ] as [String: Any],
            "yAxis": [
                "name": "Income"
            ] as [String: Any],
            "grid": [
                "right": 140.0
            ] as [String: Any],
            "series": lineRaceSeries as [Any]
        ])
}
